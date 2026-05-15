import AppKit
import Foundation

/// Stats pane — Claude-app style usage overview computed locally from
/// ~/.context-hud/hud.json (the same artifact the Usage tab reads).
///
/// All numbers come from the `claude` AgentBlock written by
/// src/usage_signal.py — no synthetic data. Fields used:
///   - by_day:        last 30 days [{date, tokens, sessions}]
///   - by_month:      last 12 months [{date "YYYY-MM", tokens, sessions}]
///   - by_model:      all-time, sorted by tokens
///   - recent_sessions: last 20 with duration_minutes
///   - total_tokens_30d / total_sessions_30d
final class StatsViewController: PreferencePaneViewController {
    enum Range: Int { case all = 0, last30 = 1, last7 = 2 }
    private var range: Range = .all

    private let rangeControl = NSSegmentedControl()
    private let tilesStack = NSStackView()
    private let heatmapHost = NSView()
    private let comparisonLabel = NSTextField(labelWithString: "")
    private var heatmapView: HeatmapView?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    private func buildUI() {
        rangeControl.segmentStyle = .texturedRounded
        rangeControl.segmentCount = 3
        rangeControl.setLabel(L10n.text("All time", "Tüm zaman"), forSegment: 0)
        rangeControl.setLabel(L10n.text("Last 30 days", "Son 30 gün"), forSegment: 1)
        rangeControl.setLabel(L10n.text("Last 7 days", "Son 7 gün"), forSegment: 2)
        rangeControl.selectedSegment = 0
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Range", "Aralık"),
            subtitle: L10n.text(
                "Summary scope. Streaks and most-active day always reflect available history.",
                "Özet kapsamı. Seriler ve en aktif gün her zaman mevcut geçmişi yansıtır."
            ),
            body: rangeControl
        )

        tilesStack.orientation = .vertical
        tilesStack.alignment = .leading
        tilesStack.spacing = 10
        tilesStack.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Overview", "Genel bakış"),
            subtitle: nil,
            body: tilesStack
        )

        heatmapHost.translatesAutoresizingMaskIntoConstraints = false
        heatmapHost.heightAnchor.constraint(equalToConstant: 124).isActive = true
        addSection(
            title: L10n.text("Activity (last 30 days)", "Aktivite (son 30 gün)"),
            subtitle: L10n.text(
                "Each cell is one day. Darker means more tokens. Empty days are blank.",
                "Her hücre bir gün. Koyu renk daha fazla token. Boş günler boş bırakılır."
            ),
            body: heatmapHost
        )

        comparisonLabel.font = NSFont.systemFont(ofSize: 11)
        comparisonLabel.textColor = .secondaryLabelColor
        comparisonLabel.maximumNumberOfLines = 0
        comparisonLabel.translatesAutoresizingMaskIntoConstraints = false
        addSection(
            title: L10n.text("Fun fact", "Eğlenceli bilgi"),
            subtitle: nil,
            body: comparisonLabel
        )
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        range = Range(rawValue: sender.selectedSegment) ?? .all
        reload()
    }

    // MARK: - Data

    private struct Day { let date: String; let tokens: UInt64; let sessions: Int }
    private struct ModelBucket { let model: String; let tokens: UInt64; let sessions: Int }
    private struct Session { let durationMinutes: Double; let tokens: UInt64 }

    private struct Snapshot {
        var byDay: [Day] = []          // newest-first, up to 30
        var byMonth: [Day] = []        // newest-first, up to 12 (date="YYYY-MM")
        var byModel: [ModelBucket] = []
        var recent: [Session] = []
        var total30dTokens: UInt64 = 0
        var total30dSessions: Int = 0
    }

    private func loadSnapshot() -> Snapshot {
        let path = "\(NSHomeDirectory())/.context-hud/hud.json"
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let c = root["claude"] as? [String: Any]
        else {
            return Snapshot()
        }
        func u64(_ any: Any?) -> UInt64 {
            (any as? UInt64) ?? UInt64(any as? Int ?? 0)
        }
        var snap = Snapshot()
        snap.total30dTokens = u64(c["total_tokens_30d"])
        snap.total30dSessions = (c["total_sessions_30d"] as? Int) ?? 0
        snap.byDay = ((c["by_day"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let d = o["date"] as? String else { return nil }
            return Day(date: d, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0)
        }
        snap.byMonth = ((c["by_month"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let d = (o["date"] as? String) ?? (o["month"] as? String) else { return nil }
            return Day(date: d, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0)
        }
        snap.byModel = ((c["by_model"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let m = o["model"] as? String else { return nil }
            return ModelBucket(model: m, tokens: u64(o["tokens"]), sessions: (o["sessions"] as? Int) ?? 0)
        }
        snap.recent = ((c["recent_sessions"] as? [[String: Any]]) ?? []).compactMap { o in
            Session(
                durationMinutes: (o["duration_minutes"] as? Double) ?? 0,
                tokens: u64(o["tokens"])
            )
        }
        return snap
    }

    // MARK: - Aggregates

    private func tokensInRange(_ snap: Snapshot) -> UInt64 {
        switch range {
        case .all:    return snap.byMonth.reduce(0) { $0 + $1.tokens }
        case .last30: return snap.total30dTokens
        case .last7:  return snap.byDay.prefix(7).reduce(0) { $0 + $1.tokens }
        }
    }

    private func sessionsInRange(_ snap: Snapshot) -> Int {
        switch range {
        case .all:    return snap.byMonth.reduce(0) { $0 + $1.sessions }
        case .last30: return snap.total30dSessions
        case .last7:  return snap.byDay.prefix(7).reduce(0) { $0 + $1.sessions }
        }
    }

    private func activeDaysInRange(_ snap: Snapshot) -> (active: Int, total: Int) {
        switch range {
        case .all:
            // Total = calendar days since first recorded activity (so the
            // ratio stays meaningful instead of always being X/365).
            let active = snap.byDay.filter { $0.tokens > 0 }.count
            guard let firstActive = snap.byDay.last(where: { $0.tokens > 0 }) else {
                return (0, 0)
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = .current
            guard let firstDate = fmt.date(from: firstActive.date) else { return (active, active) }
            let days = Calendar(identifier: .gregorian).dateComponents([.day], from: firstDate, to: Date()).day ?? 0
            return (active, max(active, days + 1))
        case .last30:
            let slice = Array(snap.byDay.prefix(30))
            return (slice.filter { $0.tokens > 0 }.count, 30)
        case .last7:
            let slice = Array(snap.byDay.prefix(7))
            return (slice.filter { $0.tokens > 0 }.count, 7)
        }
    }

    /// Walks by_day (newest-first) and counts consecutive non-empty days from
    /// the most recent entry. If today has no entry yet, the streak still
    /// counts yesterday and earlier as a continuous run.
    private func currentStreak(_ snap: Snapshot) -> Int {
        var streak = 0
        var sawActive = false
        for d in snap.byDay {
            if d.tokens > 0 {
                streak += 1
                sawActive = true
            } else if sawActive {
                break
            }
            // Leading empty days (today not used yet) are skipped so the
            // streak keeps reflecting yesterday and earlier.
        }
        return streak
    }

    private func longestStreak(_ snap: Snapshot) -> Int {
        var best = 0, run = 0
        for d in snap.byDay {
            if d.tokens > 0 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    private func longestSession(_ snap: Snapshot) -> Double {
        snap.recent.map(\.durationMinutes).max() ?? 0
    }

    private func mostActiveDay(_ snap: Snapshot) -> Day? {
        snap.byDay.max(by: { $0.tokens < $1.tokens })
    }

    private func favoriteModel(_ snap: Snapshot) -> String? {
        snap.byModel.first.map { prettyModelName($0.model) }
    }

    /// Map Anthropic / OpenAI model IDs to the short labels each vendor shows
    /// in its own UI. Unknown IDs fall back to the raw string.
    private func prettyModelName(_ id: String) -> String {
        let m = id.lowercased()
        let suffix = m.contains("[1m]") || m.contains("-1m") ? " (1M)" : ""
        let base: String
        switch true {
        case m.contains("opus-4-7"):    base = "Opus 4.7"
        case m.contains("opus-4-6"):    base = "Opus 4.6"
        case m.contains("opus-4-5"):    base = "Opus 4.5"
        case m.contains("opus-4"):      base = "Opus 4"
        case m.contains("sonnet-4-6"):  base = "Sonnet 4.6"
        case m.contains("sonnet-4-5"):  base = "Sonnet 4.5"
        case m.contains("sonnet-4"):    base = "Sonnet 4"
        case m.contains("haiku-4-5"):   base = "Haiku 4.5"
        case m.contains("haiku-4"):     base = "Haiku 4"
        case m.contains("gpt-5"):       base = "GPT-5"
        case m.contains("gpt-4"):       base = "GPT-4"
        case m.contains("mythos"):      base = "Claude Mythos"
        default:                        return id
        }
        return base + suffix
    }

    // MARK: - Render

    func reload() {
        guard isViewLoaded else { return }
        let snap = loadSnapshot()
        tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        heatmapView?.removeFromSuperview()
        heatmapView = nil

        let tokens = tokensInRange(snap)
        let sessions = sessionsInRange(snap)
        let (active, total) = activeDaysInRange(snap)

        let tiles: [NSView] = [
            StatTileView(
                caption: L10n.text("sessions", "oturum"),
                value: numberString(sessions)
            ),
            StatTileView(
                caption: L10n.text("total tokens", "toplam token"),
                value: Hud.formatTokens(tokens)
            ),
            StatTileView(
                caption: L10n.text("active days", "aktif gün"),
                value: total > 0 ? "\(active)/\(total)" : "—"
            ),
            StatTileView(
                caption: L10n.text("current streak", "mevcut seri"),
                value: streakString(currentStreak(snap))
            ),
            StatTileView(
                caption: L10n.text("longest streak", "en uzun seri"),
                value: streakString(longestStreak(snap))
            ),
            StatTileView(
                caption: L10n.text("longest session", "en uzun oturum"),
                value: durationString(minutes: longestSession(snap))
            ),
            StatTileView(
                caption: L10n.text("most active day", "en aktif gün"),
                value: mostActiveDay(snap).map { formatDay($0.date) } ?? "—",
                mono: false
            ),
            StatTileView(
                caption: L10n.text("favorite model", "favori model"),
                value: favoriteModel(snap) ?? "—",
                mono: false
            ),
        ]

        let rows = stride(from: 0, to: tiles.count, by: 4).map { start -> NSStackView in
            let end = min(start + 4, tiles.count)
            let row = NSStackView(views: Array(tiles[start..<end]))
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        rows.forEach {
            tilesStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: tilesStack.widthAnchor).isActive = true
        }

        let hm = HeatmapView()
        // Limit to the last 30 days so cells stay readable; the full byDay
        // window (≈365) is kept around for streak / longest-streak math.
        hm.values = snap.byDay.prefix(30).map { (date: $0.date, tokens: $0.tokens) }
        hm.translatesAutoresizingMaskIntoConstraints = false
        heatmapHost.addSubview(hm)
        NSLayoutConstraint.activate([
            hm.topAnchor.constraint(equalTo: heatmapHost.topAnchor),
            hm.leadingAnchor.constraint(equalTo: heatmapHost.leadingAnchor),
            hm.trailingAnchor.constraint(equalTo: heatmapHost.trailingAnchor),
            hm.bottomAnchor.constraint(equalTo: heatmapHost.bottomAnchor),
        ])
        heatmapView = hm

        comparisonLabel.stringValue = comparisonString(totalAllTime: snap.byMonth.reduce(0) { $0 + $1.tokens })
    }

    // MARK: - Formatting

    private func numberString(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func streakString(_ days: Int) -> String {
        if days <= 0 { return "—" }
        return L10n.text("\(days)d", "\(days)g")
    }

    private func durationString(minutes m: Double) -> String {
        if m <= 0 { return "—" }
        if m < 60 { return String(format: "%.0f%@", m, L10n.text("m", "dk")) }
        let h = Int(m / 60)
        let mm = Int(m.truncatingRemainder(dividingBy: 60))
        let hU = L10n.text("h", "sa")
        let mU = L10n.text("m", "dk")
        if h < 24 {
            return mm == 0 ? "\(h)\(hU)" : "\(h)\(hU) \(mm)\(mU)"
        }
        let d = h / 24
        let hh = h % 24
        let dU = L10n.text("d", "g")
        return hh == 0 ? "\(d)\(dU)" : "\(d)\(dU) \(hh)\(hU)"
    }

    private func formatDay(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inFmt.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.lang == .tr ? "tr_TR" : "en_US")
        out.dateFormat = L10n.lang == .tr ? "d MMM" : "MMM d"
        return out.string(from: date)
    }

    /// War and Peace ≈ 587,287 words. At ~0.75 words/token that is ~783,000
    /// tokens — used as a stable reference so users get a sense of scale.
    /// Same idea as Claude's "X× more than The Hobbit" line, but with a book
    /// that scales better for heavy users.
    private static let warAndPeaceTokens: Double = 783_000

    private func comparisonString(totalAllTime: UInt64) -> String {
        guard totalAllTime > 0 else {
            return L10n.text(
                "No usage recorded yet.",
                "Henüz kullanım kaydı yok."
            )
        }
        let ratio = Double(totalAllTime) / Self.warAndPeaceTokens
        let ratioStr: String = {
            if ratio >= 10 { return String(format: "%.0f×", ratio) }
            return String(format: "%.1f×", ratio)
        }()
        return L10n.text(
            "You've used ~\(ratioStr) more tokens than War and Peace.",
            "Savaş ve Barış'tan ~\(ratioStr) daha fazla token kullandınız."
        )
    }
}

/// 7-row × N-column GitHub-style heatmap. Each cell = one day from
/// `values` (newest-first). Days are placed bottom-right to top-left so the
/// most recent day is the bottom-right cell.
final class HeatmapView: NSView {
    var values: [(date: String, tokens: UInt64)] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 124) }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        // Lay out by weekday: most-recent day in its true weekday row, then
        // walk backwards filling cells from right to left.
        let rows = 7
        let dayCount = values.count
        let cols = Int(ceil(Double(dayCount) / Double(rows)))
        guard cols > 0 else { return }

        let gap: CGFloat = 3
        let totalGapW = gap * CGFloat(cols - 1)
        let totalGapH = gap * CGFloat(rows - 1)
        let cell = min(
            (bounds.width - totalGapW) / CGFloat(cols),
            (bounds.height - totalGapH) / CGFloat(rows)
        )
        guard cell > 1 else { return }

        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = TimeZone.current

        // Map index -> (col, row). Newest day (index 0) sits in last col, in
        // its own weekday row. Older days subtract one day at a time.
        let cal = Calendar(identifier: .gregorian)
        guard let newestDate = values.first.flatMap({ inFmt.date(from: $0.date) }) else { return }
        let newestWeekday = (cal.component(.weekday, from: newestDate) + 5) % 7 // Mon=0..Sun=6

        let maxTok = max(values.map(\.tokens).max() ?? 1, 1)
        let accent = NSColor.systemOrange

        for (i, v) in values.enumerated() {
            let offsetFromNewest = i
            let row = (newestWeekday - offsetFromNewest % 7 + 7 * 7) % 7
            let col = cols - 1 - ((offsetFromNewest + (6 - newestWeekday)) / 7)
            guard col >= 0 else { continue }

            let x = CGFloat(col) * (cell + gap)
            let y = CGFloat(row) * (cell + gap)
            let rect = NSRect(x: x, y: y, width: cell, height: cell)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if v.tokens == 0 {
                NSColor.tertiaryLabelColor.withAlphaComponent(0.12).setFill()
                path.fill()
                continue
            }
            // 4 buckets, log-scaled so very large days don't drown the rest.
            let norm = log(Double(v.tokens) + 1) / log(Double(maxTok) + 1)
            let alpha: CGFloat
            switch norm {
            case ..<0.35: alpha = 0.28
            case ..<0.6:  alpha = 0.5
            case ..<0.85: alpha = 0.75
            default:      alpha = 1.0
            }
            accent.withAlphaComponent(alpha).setFill()
            path.fill()
        }
    }
}
