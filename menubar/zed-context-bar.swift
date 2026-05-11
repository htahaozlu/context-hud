// zed-context-bar
//
// macOS menubar HUD for Claude Code + Codex CLI usage. Reads the structured
// JSON sidecar at ~/.zed-context/hud.json (kept fresh by the zed-context
// daemon) and renders:
//   - menubar icon (SF Symbol "sparkles") + colored compact title with the
//     currently-active agent, its project basename, and context %
//   - dropdown listing every agent stacked, with project, model, tokens, and
//     relative "last turn" time
//
// Build:   swiftc -O zed-context-bar.swift -o ~/.cargo/bin/zed-context-bar
//
// Tiny by design: no third-party deps, no app bundle, AppKit + Foundation.

import AppKit
import Foundation

// MARK: - Themes

/// Visual theme — each preset overrides the menubar/dropdown palette and the
/// glyphs used to mark the active agent and separators. Selected via the
/// "Theme" submenu and persisted in UserDefaults under `theme`.
struct Theme {
    let id: String
    let name: String
    let agentColor: NSColor
    let projectColor: NSColor
    let separatorColor: NSColor
    let pctLow: NSColor       // < 60%
    let pctMid: NSColor       // < 85%
    let pctHigh: NSColor      // >= 85%
    let activeDot: String
    let inactiveDot: String
    let separator: String

    func ctxColor(_ pct: Double?) -> NSColor {
        guard let pct else { return agentColor }
        switch pct {
        case ..<60: return pctLow
        case ..<85: return pctMid
        default:    return pctHigh
        }
    }

    static let all: [Theme] = [
        Theme(
            id: "default",
            name: "Default",
            agentColor: .labelColor,
            projectColor: .controlAccentColor,
            separatorColor: .tertiaryLabelColor,
            pctLow: .systemGreen,
            pctMid: .systemOrange,
            pctHigh: .systemRed,
            activeDot: "●", inactiveDot: "○", separator: "·"
        ),
        Theme(
            id: "mono",
            name: "Mono",
            agentColor: .labelColor,
            projectColor: .labelColor,
            separatorColor: .tertiaryLabelColor,
            pctLow: .labelColor,
            pctMid: .labelColor,
            pctHigh: .labelColor,
            activeDot: "▸", inactiveDot: "·", separator: "·"
        ),
        Theme(
            id: "neon",
            name: "Neon",
            agentColor: NSColor(srgbRed: 0.45, green: 1.00, blue: 0.85, alpha: 1.0),
            projectColor: NSColor(srgbRed: 1.00, green: 0.45, blue: 0.85, alpha: 1.0),
            separatorColor: NSColor(srgbRed: 0.55, green: 0.45, blue: 0.85, alpha: 0.6),
            pctLow: NSColor(srgbRed: 0.10, green: 1.00, blue: 0.55, alpha: 1.0),
            pctMid: NSColor(srgbRed: 1.00, green: 0.85, blue: 0.20, alpha: 1.0),
            pctHigh: NSColor(srgbRed: 1.00, green: 0.30, blue: 0.45, alpha: 1.0),
            activeDot: "◆", inactiveDot: "◇", separator: "·"
        ),
        Theme(
            id: "pastel",
            name: "Pastel",
            agentColor: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.85, alpha: 1.0),
            projectColor: NSColor(srgbRed: 0.85, green: 0.65, blue: 0.95, alpha: 1.0),
            separatorColor: NSColor(srgbRed: 0.70, green: 0.70, blue: 0.78, alpha: 0.7),
            pctLow: NSColor(srgbRed: 0.60, green: 0.85, blue: 0.70, alpha: 1.0),
            pctMid: NSColor(srgbRed: 0.95, green: 0.80, blue: 0.55, alpha: 1.0),
            pctHigh: NSColor(srgbRed: 0.95, green: 0.65, blue: 0.70, alpha: 1.0),
            activeDot: "✦", inactiveDot: "✧", separator: "—"
        ),
        Theme(
            id: "terminal",
            name: "Terminal",
            agentColor: NSColor.systemGreen,
            projectColor: NSColor.systemYellow,
            separatorColor: .secondaryLabelColor,
            pctLow: NSColor.systemGreen,
            pctMid: NSColor.systemYellow,
            pctHigh: NSColor.systemRed,
            activeDot: ">", inactiveDot: " ", separator: "|"
        ),
        Theme(
            id: "compact",
            name: "Compact",
            agentColor: .labelColor,
            projectColor: .secondaryLabelColor,
            separatorColor: .tertiaryLabelColor,
            pctLow: .systemTeal,
            pctMid: .systemOrange,
            pctHigh: .systemRed,
            activeDot: "·", inactiveDot: " ", separator: ""
        ),
    ]

    static func by(id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

final class ThemeStore {
    static let key = "theme"
    static var current: Theme {
        get { Theme.by(id: UserDefaults.standard.string(forKey: key) ?? "default") }
    }
    static func set(_ id: String) {
        UserDefaults.standard.set(id, forKey: key)
    }
}

final class SeparatorStore {
    static let key = "separator"
    static let options: [(label: String, value: String)] = [
        ("·", "·"), ("|", "|"), ("-", "-"), ("—", "—"), ("/", "/"), ("none", ""),
    ]
    static var current: String {
        UserDefaults.standard.string(forKey: key) ?? "·"
    }
    static var currentIndex: Int {
        options.firstIndex(where: { $0.value == current }) ?? 0
    }
    static func set(_ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

enum AppLanguage: String, CaseIterable {
    case auto
    case en
    case tr

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .en: return "EN"
        case .tr: return "TR"
        }
    }
}

final class LanguageStore {
    static let key = "language"

    static var selected: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "auto") ?? .auto }
    }

    static var resolved: AppLanguage {
        switch selected {
        case .auto:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("tr") ? .tr : .en
        case .en, .tr:
            return selected
        }
    }

    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }
}

enum L10n {
    static var lang: AppLanguage { LanguageStore.resolved }

    static func text(_ en: String, _ tr: String) -> String {
        lang == .tr ? tr : en
    }

    static func displayElementLabel(_ element: DisplayElement) -> String {
        switch element {
        case .agent: return text("Agent name", "Ajan adı")
        case .project: return text("Project (cwd)", "Proje (cwd)")
        case .pct: return text("Context %", "Bağlam %")
        }
    }

    static func relative(_ elapsed: TimeInterval) -> String {
        if elapsed < 60 { return lang == .tr ? "\(Int(elapsed)) sn önce" : "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return lang == .tr ? "\(Int(elapsed/60)) dk önce" : "\(Int(elapsed/60))m ago" }
        if elapsed < 86400 { return lang == .tr ? "\(Int(elapsed/3600)) sa önce" : "\(Int(elapsed/3600))h ago" }
        return lang == .tr ? "\(Int(elapsed/86400)) g önce" : "\(Int(elapsed/86400))d ago"
    }
}

/// What to render in the menubar title and in what order.
enum DisplayElement: String, CaseIterable {
    case agent, project, pct
    var label: String {
        L10n.displayElementLabel(self)
    }
}

struct DisplayItem {
    let element: DisplayElement
    var enabled: Bool
}

final class DisplayStore {
    static let key = "displayItems"
    static var items: [DisplayItem] {
        if let arr = UserDefaults.standard.array(forKey: key) as? [[String: Any]] {
            var parsed: [DisplayItem] = []
            var seen = Set<DisplayElement>()
            for dict in arr {
                if let id = dict["id"] as? String, let elem = DisplayElement(rawValue: id), !seen.contains(elem) {
                    parsed.append(DisplayItem(element: elem, enabled: (dict["enabled"] as? Bool) ?? true))
                    seen.insert(elem)
                }
            }
            for elem in DisplayElement.allCases where !seen.contains(elem) {
                parsed.append(DisplayItem(element: elem, enabled: true))
            }
            return parsed
        }
        return DisplayElement.allCases.map { DisplayItem(element: $0, enabled: true) }
    }
    static func save(_ items: [DisplayItem]) {
        let arr: [[String: Any]] = items.map { ["id": $0.element.rawValue, "enabled": $0.enabled] }
        UserDefaults.standard.set(arr, forKey: key)
    }
}

struct ToolSummary {
    let name: String
    let sessions7d: Int
    let tokens7d: UInt64
    let lastUsed: String?
    let lastModel: String?
}

struct ActiveSession {
    let id: String
    let tokens: UInt64
    let project: String
    let model: String?
    let lastTurn: Date?
    let started: Date?
}

struct Agent {
    let name: String
    let session5h: UInt64
    let session5hPercent: Double?
    let week7d: UInt64
    let week7dPercent: Double?
    let activeSession: UInt64
    let model: String?
    let cwd: String?
    let ctxPct: Double?
    let ctxWindow: UInt64?
    let lastTurn: Date?
    let sessionStarted: Date?
    let activeSessions: [ActiveSession]
    let session5hResetsAt: Date?
    let week7dResetsAt: Date?

    /// Returns project basename (last path segment) or "—".
    var project: String {
        guard let cwd, !cwd.isEmpty else { return "—" }
        return (cwd as NSString).lastPathComponent
    }
}

final class Hud {
    let path: String
    let usageCachePath: String
    init() {
        self.path = "\(NSHomeDirectory())/.zed-context/hud.json"
        self.usageCachePath = "\(NSHomeDirectory())/.zed-context/usage_api_cache.json"
    }

    func load() -> (active: Agent?, all: [Agent], others: [ToolSummary]) {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, [], [])
        }

        let claude = parse(root["claude"] as? [String: Any], name: "Claude", overlay: parseClaudeUsageCache())
        let codex = parse(root["codex"] as? [String: Any], name: "Codex")
        let all = [claude, codex].compactMap { $0 }
        let active = all.max(by: {
            ($0.lastTurn ?? .distantPast) < ($1.lastTurn ?? .distantPast)
        })
        let others = parseOthers(root["others"] as? [[String: Any]])
        return (active, all, others)
    }

    private func parseOthers(_ raw: [[String: Any]]?) -> [ToolSummary] {
        guard let raw else { return [] }
        return raw.compactMap { obj in
            guard let name = obj["name"] as? String, !name.isEmpty else { return nil }
            return ToolSummary(
                name: name,
                sessions7d: obj["sessions_7d"] as? Int ?? 0,
                tokens7d: (obj["tokens_7d"] as? UInt64) ?? UInt64(obj["tokens_7d"] as? Int ?? 0),
                lastUsed: obj["last_used"] as? String,
                lastModel: obj["last_model"] as? String
            )
        }
    }

    private func parseClaudeUsageCache() -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: usageCachePath)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["data"] as? [String: Any]
        else {
            return nil
        }
        return payload
    }

    private func parse(_ raw: [String: Any]?, name: String, overlay: [String: Any]? = nil) -> Agent? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        let tsRaw = raw["last_turn_at"] as? String
        let ts: Date? = tsRaw.flatMap {
            iso.date(from: $0) ?? isoNoFrac.date(from: $0)
        }
        let startRaw = raw["active_session_started_at"] as? String
        let started: Date? = startRaw.flatMap {
            iso.date(from: $0) ?? isoNoFrac.date(from: $0)
        }

        let actives = (raw["active_sessions"] as? [[String: Any]] ?? []).compactMap { obj -> ActiveSession? in
            guard let id = obj["id"] as? String else { return nil }
            let lastRaw = obj["last_turn_at"] as? String
            let startedRaw = obj["started_at"] as? String
            let last: Date? = lastRaw.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
            let st: Date? = startedRaw.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
            return ActiveSession(
                id: id,
                tokens: (obj["tokens"] as? UInt64) ?? UInt64(obj["tokens"] as? Int ?? 0),
                project: (obj["project"] as? String) ?? "—",
                model: obj["model"] as? String,
                lastTurn: last,
                started: st
            )
        }

        let parseDate: (String?) -> Date? = { s in
            guard let s else { return nil }
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }

        let fiveHourOverlay = overlay?["five_hour"] as? [String: Any]
        let sevenDayOverlay = overlay?["seven_day"] as? [String: Any]

        return Agent(
            name: name,
            session5h: (raw["session_5h_tokens"] as? UInt64) ?? UInt64(raw["session_5h_tokens"] as? Int ?? 0),
            session5hPercent: (raw["session_5h_percent"] as? Double)
                ?? (fiveHourOverlay?["utilization"] as? Double)
                ?? (fiveHourOverlay?["used_percentage"] as? Double),
            week7d: (raw["week_7d_tokens"] as? UInt64) ?? UInt64(raw["week_7d_tokens"] as? Int ?? 0),
            week7dPercent: (raw["week_7d_percent"] as? Double)
                ?? (sevenDayOverlay?["utilization"] as? Double)
                ?? (sevenDayOverlay?["used_percentage"] as? Double),
            activeSession: (raw["active_session_tokens"] as? UInt64) ?? UInt64(raw["active_session_tokens"] as? Int ?? 0),
            model: raw["last_model"] as? String,
            cwd: raw["last_cwd"] as? String,
            ctxPct: raw["last_context_pct"] as? Double,
            ctxWindow: (raw["last_context_window"] as? UInt64) ?? (raw["last_context_window"] as? Int).map(UInt64.init),
            lastTurn: ts,
            sessionStarted: started,
            activeSessions: actives,
            session5hResetsAt: parseDate(raw["session_5h_resets_at"] as? String)
                ?? parseDate(fiveHourOverlay?["resets_at"] as? String),
            week7dResetsAt: parseDate(raw["week_7d_resets_at"] as? String)
                ?? parseDate(sevenDayOverlay?["resets_at"] as? String)
        )
    }

    static func resetsIn(_ date: Date?) -> String {
        guard let date else { return "—" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return L10n.text("ready", "hazır") }
        if remaining < 60 { return "<1m" }
        if remaining < 3600 { return "\(Int(remaining/60))m" }
        let h = Int(remaining / 3600)
        let m = (Int(remaining) % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func formatDuration(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "—" }
        let s = max(0.0, end.timeIntervalSince(start))
        if s < 60 { return "\(Int(s))s" }
        let m = Int(s / 60)
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let mm = m % 60
        return mm == 0 ? "\(h)h" : "\(h)h \(mm)m"
    }

    static func formatTokens(_ value: UInt64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000.0) }
        return "\(value)"
    }

    static func formatUsageValue(percent: Double?, tokens: UInt64) -> String {
        if let percent {
            return String(format: "%.0f%%", percent)
        }
        return formatTokens(tokens)
    }

    static func relative(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        return L10n.relative(elapsed)
    }

    /// Traffic-light color for a context % value.
    static func ctxColor(_ pct: Double?) -> NSColor {
        guard let pct else { return .labelColor }
        switch pct {
        case ..<60: return NSColor.systemGreen
        case ..<85: return NSColor.systemOrange
        default:    return NSColor.systemRed
        }
    }
}

// MARK: - Detail window

/// Horizontal progress bar drawn natively. Fills `value` (0...1) with the
/// supplied tint over a subtle track. Used for window-elapsed limits and
/// active-session context-window meters.
final class ProgressBarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var tint: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var trackColor: NSColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
    var corner: CGFloat = 3

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
        trackColor.setFill()
        track.fill()
        let clamped = max(0, min(1, value))
        guard clamped > 0 else { return }
        let fillRect = NSRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: corner, yRadius: corner)
        tint.setFill()
        fill.fill()
    }
}

/// Compact 30-day sparkline drawn with rounded mini bars. Highlights the most
/// recent day to give an at-a-glance sense of recent burn vs trend.
final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var tint: NSColor = .controlAccentColor

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 56) }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty, let maxV = values.max(), maxV > 0 else { return }
        let n = values.count
        let gap: CGFloat = 2
        let totalGap = gap * CGFloat(n - 1)
        let barW = max(2, (bounds.width - totalGap) / CGFloat(n))
        for (i, v) in values.enumerated() {
            let h = max(2, CGFloat(v / maxV) * (bounds.height - 4))
            let x = CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: bounds.height - h, width: barW, height: h)
            let color = (i == n - 1) ? tint : tint.withAlphaComponent(0.45)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

/// Custom NSView used inside an NSMenuItem to render a per-window limit row
/// with a horizontal progress bar showing window-elapsed fraction.
final class LimitRowView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let tokenField = NSTextField(labelWithString: "")
    private let resetField = NSTextField(labelWithString: "")
    private let bar = ProgressBarView()

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 22) }

    init(label: String, tokens: String, reset: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 22))

        labelField.stringValue = label
        labelField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        labelField.textColor = .secondaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false

        tokenField.stringValue = tokens
        tokenField.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        tokenField.textColor = .labelColor
        tokenField.translatesAutoresizingMaskIntoConstraints = false

        resetField.stringValue = "↻ \(reset)"
        resetField.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
        resetField.textColor = .tertiaryLabelColor
        resetField.alignment = .right
        resetField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelField); addSubview(tokenField); addSubview(resetField)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.widthAnchor.constraint(equalToConstant: 56),

            tokenField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 4),
            tokenField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),

            resetField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            resetField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),
        ])
        _ = bar
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Stat tile — a small native card with a caption + big value. Used in the
/// Usage tab to surface tokens / sessions / context % at a glance.
final class StatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 1

        let cap = NSTextField(labelWithString: caption.uppercased())
        cap.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        cap.textColor = .tertiaryLabelColor
        cap.translatesAutoresizingMaskIntoConstraints = false

        let val = NSTextField(labelWithString: value)
        val.font = mono
            ? NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
            : NSFont.systemFont(ofSize: 20, weight: .semibold)
        val.textColor = valueColor
        val.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cap)
        addSubview(val)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cap.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            val.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 4),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            val.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Stat tile with caption + primary value + faded sub-value. Lets each tile
/// surface a number (eg "3.4M") alongside its context (eg "resets in 2h").
final class DualStatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor,
         sub: String, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 1

        let cap = NSTextField(labelWithString: caption.uppercased())
        cap.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        cap.textColor = .tertiaryLabelColor
        cap.translatesAutoresizingMaskIntoConstraints = false

        let val = NSTextField(labelWithString: value)
        val.font = mono
            ? NSFont.monospacedSystemFont(ofSize: 22, weight: .medium)
            : NSFont.systemFont(ofSize: 22, weight: .semibold)
        val.textColor = valueColor
        val.translatesAutoresizingMaskIntoConstraints = false

        let subLbl = NSTextField(labelWithString: sub)
        subLbl.font = NSFont.systemFont(ofSize: 10)
        subLbl.textColor = .secondaryLabelColor
        subLbl.lineBreakMode = .byTruncatingTail
        subLbl.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cap); addSubview(val); addSubview(subLbl)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cap.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            val.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 4),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            subLbl.topAnchor.constraint(equalTo: val.bottomAnchor, constant: 4),
            subLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            subLbl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            subLbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Native Usage panel — rebuilt per refresh from hud.json. One card per agent
/// with stat tiles, window progress bars, active-session strip, and a 30-day
/// sparkline. Replaces the previous WKWebView approach so the panel feels at
/// home on macOS (no scrollbars, no font drift, no white flash).
final class UsageViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let container = NSStackView()

    override func loadView() {
        view = NSView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 18
        container.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(container)
        scrollView.documentView = doc

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            container.topAnchor.constraint(equalTo: doc.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -24),
        ])
    }

    func reload() {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hud = Hud()
        let (active, all, others) = hud.load()
        if all.isEmpty {
            let empty = NSTextField(labelWithString: L10n.text(
                "No agent data yet. Start a Claude or Codex session.",
                "Henüz ajan verisi yok. Bir Claude veya Codex oturumu başlatın."
            ))
            empty.font = NSFont.systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            container.addArrangedSubview(empty)
            return
        }
        for a in all {
            let card = buildAgentCard(agent: a, isActive: a.name == active?.name)
            container.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
        if !others.isEmpty {
            let card = buildOthersCard(tools: others)
            container.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
    }

    /// Agent card: header + 4 stat tiles (context / active session / 5h / 7d) +
    /// 30-day sparkline. All data visible by default — no disclosures. Each
    /// tile pairs a primary value with a faded sub-value so the user sees both
    /// "what" and "when/how much" without scanning multiple sections.
    private func buildAgentCard(agent a: Agent, isActive: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false

        // Header: ● Name  · model · project · last turn
        let dot = NSTextField(labelWithString: "●")
        dot.font = NSFont.systemFont(ofSize: 10)
        dot.textColor = isActive ? .systemGreen : .tertiaryLabelColor

        let nameLbl = NSTextField(labelWithString: a.name)
        nameLbl.font = NSFont.systemFont(ofSize: 16, weight: .semibold)

        var metaParts: [String] = []
        if let m = a.model { metaParts.append(m) }
        metaParts.append(a.project)
        if let t = a.lastTurn { metaParts.append(Hud.relative(t)) }
        let metaLbl = NSTextField(labelWithString: metaParts.joined(separator: "  ·  "))
        metaLbl.font = NSFont.systemFont(ofSize: 11)
        metaLbl.textColor = .secondaryLabelColor

        let titleRow = NSStackView(views: [dot, nameLbl])
        titleRow.orientation = .horizontal; titleRow.spacing = 6; titleRow.alignment = .firstBaseline

        let header = NSStackView(views: [titleRow, metaLbl])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 2
        header.translatesAutoresizingMaskIntoConstraints = false

        // Stat tiles
        let ctxPctStr = a.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
        let ctxSub = a.ctxWindow.map { "\(Hud.formatTokens(a.activeSession)) of \(Hud.formatTokens($0))" } ?? "—"
        let sessDur = Hud.formatDuration(a.sessionStarted, a.lastTurn)

        let tiles = NSStackView(views: [
            DualStatTileView(caption: "context",
                             value: ctxPctStr, valueColor: Hud.ctxColor(a.ctxPct),
                             sub: ctxSub, mono: false),
            DualStatTileView(caption: L10n.text("session", "oturum"),
                             value: Hud.formatTokens(a.activeSession),
                             sub: L10n.text("\(sessDur) running", "\(sessDur) süredir aktif")),
            DualStatTileView(caption: L10n.text("5h window", "5s pencere"),
                             value: Hud.formatUsageValue(percent: a.session5hPercent, tokens: a.session5h),
                             sub: L10n.text("resets in \(Hud.resetsIn(a.session5hResetsAt))", "\(Hud.resetsIn(a.session5hResetsAt)) sonra sıfırlanır")),
            DualStatTileView(caption: L10n.text("7d window", "7g pencere"),
                             value: Hud.formatUsageValue(percent: a.week7dPercent, tokens: a.week7d),
                             sub: L10n.text("resets in \(Hud.resetsIn(a.week7dResetsAt))", "\(Hud.resetsIn(a.week7dResetsAt)) sonra sıfırlanır")),
        ])
        tiles.orientation = .horizontal
        tiles.distribution = .fillEqually
        tiles.spacing = 10
        tiles.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(tiles)

        if let spark = buildSparkline(forAgent: a.name) {
            stack.addArrangedSubview(spark)
            spark.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tiles.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return card
    }

    private func buildContextRow(pct: Double, window: UInt64?, used: UInt64) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: L10n.text("context window", "bağlam penceresi"))
        lbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let detail: String = {
            let pctS = String(format: "%.0f%%", pct)
            if let w = window {
                return "\(pctS)   \(Hud.formatTokens(used)) / \(Hud.formatTokens(w))"
            }
            return pctS
        }()
        let v = NSTextField(labelWithString: detail)
        v.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        v.textColor = Hud.ctxColor(pct)
        v.alignment = .right
        v.translatesAutoresizingMaskIntoConstraints = false

        let bar = ProgressBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.value = max(0, min(1, pct / 100.0))
        bar.tint = Hud.ctxColor(pct)

        row.addSubview(lbl); row.addSubview(v); row.addSubview(bar)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            lbl.topAnchor.constraint(equalTo: row.topAnchor),
            v.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            v.firstBaselineAnchor.constraint(equalTo: lbl.firstBaselineAnchor),
            bar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            bar.topAnchor.constraint(equalTo: lbl.bottomAnchor, constant: 6),
            bar.heightAnchor.constraint(equalToConstant: 6),
            bar.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func buildSparkline(forAgent name: String) -> NSView? {
        let path = "\(NSHomeDirectory())/.zed-context/hud.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agent = root[name.lowercased()] as? [String: Any],
              let byDay = agent["by_day"] as? [[String: Any]],
              !byDay.isEmpty else {
            return nil
        }
        let last = Array(byDay.prefix(30)).reversed()
        let values = last.map { Double(($0["tokens"] as? UInt64) ?? UInt64($0["tokens"] as? Int ?? 0)) }

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let cap = NSTextField(labelWithString: L10n.text("30-DAY TOKENS", "30 GÜN TOKEN"))
        cap.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        cap.textColor = .tertiaryLabelColor
        cap.translatesAutoresizingMaskIntoConstraints = false

        let total = values.reduce(0, +)
        let totalLbl = NSTextField(labelWithString: Hud.formatTokens(UInt64(total)))
        totalLbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        totalLbl.textColor = .secondaryLabelColor
        totalLbl.alignment = .right
        totalLbl.translatesAutoresizingMaskIntoConstraints = false

        let spark = SparklineView()
        spark.values = Array(values)
        spark.tint = .controlAccentColor
        spark.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(cap); row.addSubview(totalLbl); row.addSubview(spark)
        NSLayoutConstraint.activate([
            cap.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            cap.topAnchor.constraint(equalTo: row.topAnchor),
            totalLbl.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            totalLbl.firstBaselineAnchor.constraint(equalTo: cap.firstBaselineAnchor),
            spark.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            spark.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            spark.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 6),
            spark.heightAnchor.constraint(equalToConstant: 56),
            spark.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func buildOthersCard(tools: [ToolSummary]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L10n.text("Other AI tools", "Diğer AI araçları"))
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        for t in tools {
            let name = NSTextField(labelWithString: t.name)
            name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let info = NSTextField(labelWithString: "\(Hud.formatTokens(t.tokens7d))  ·  \(t.sessions7d)×/\(L10n.text("wk", "hf"))  ·  \(t.lastModel ?? "—")")
            info.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            info.textColor = .secondaryLabelColor
            let r = NSStackView(views: [name, NSView(), info])
            r.orientation = .horizontal
            r.spacing = 8
            r.translatesAutoresizingMaskIntoConstraints = false
            rows.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        let stack = NSStackView(views: [title, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return card
    }
}

final class ThemeCardView: NSView {
    let theme: Theme
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 148, height: 76) }

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 148, height: 76))
        wantsLayer = true

        let previewLabel = NSTextField(labelWithAttributedString: ThemeCardView.previewString(theme))
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewLabel)

        let nameLabel = NSTextField(labelWithString: theme.name)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            previewLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor
        let border = isSelected ? NSColor.controlAccentColor : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        bg.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = isSelected ? 2.0 : 1.0
        path.stroke()
    }

    override func mouseUp(with event: NSEvent) {
        onSelect?()
    }

    private static func previewString(_ theme: Theme) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 11)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Claude", attributes: [
            .font: font,
            .foregroundColor: theme.agentColor,
        ]))
        s.append(NSAttributedString(string: " · ", attributes: [
            .font: font,
            .foregroundColor: theme.separatorColor,
        ]))
        s.append(NSAttributedString(string: "proj", attributes: [
            .font: font,
            .foregroundColor: theme.projectColor,
        ]))
        s.append(NSAttributedString(string: " · ", attributes: [
            .font: font,
            .foregroundColor: theme.separatorColor,
        ]))
        s.append(NSAttributedString(string: "85%", attributes: [
            .font: font,
            .foregroundColor: theme.pctHigh,
        ]))
        return s
    }
}

/// Manages the menubar title element list: drag-to-reorder rows with a
/// checkbox per element. Persists to `DisplayStore` on every change.
final class DisplayTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var items: [DisplayItem] = DisplayStore.items
    var onChange: (() -> Void)?
    let tableView = NSTableView()
    let scrollView = NSScrollView()
    private static let dragType = NSPasteboard.PasteboardType("com.zedcontext.bar.displayItem.row")

    override init() {
        super.init()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        col.title = ""
        col.width = 320
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .lineBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSView()
        let handle = NSTextField(labelWithString: "⠿")
        handle.font = NSFont.systemFont(ofSize: 13)
        handle.textColor = .tertiaryLabelColor
        handle.translatesAutoresizingMaskIntoConstraints = false
        let checkbox = NSButton(checkboxWithTitle: item.element.label,
                                target: self, action: #selector(toggleEnabled(_:)))
        checkbox.state = item.enabled ? .on : .off
        checkbox.tag = row
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(handle)
        cell.addSubview(checkbox)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            handle.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            checkbox.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 10),
            checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < items.count else { return }
        items[sender.tag].enabled = (sender.state == .on)
        persist()
    }

    // Drag source
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let p = NSPasteboardItem()
        p.setString("\(row)", forType: Self.dragType)
        return p
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        return op == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let pbItems = info.draggingPasteboard.pasteboardItems,
              let str = pbItems.first?.string(forType: Self.dragType),
              let from = Int(str) else { return false }
        let target = from < row ? row - 1 : row
        if target == from { return false }
        let moved = items.remove(at: from)
        items.insert(moved, at: max(0, min(items.count, target)))
        tableView.reloadData()
        persist()
        return true
    }

    private func persist() {
        DisplayStore.save(items)
        onChange?()
    }
}

final class SettingsViewController: NSViewController {
    var onThemeChange: ((String) -> Void)?
    private var cardViews: [(ThemeCardView, Theme)] = []
    private var sepControl: NSSegmentedControl?
    private var langControl: NSSegmentedControl?
    private let displayTable = DisplayTableController()

    override func loadView() { view = NSView() }
    override func viewDidLoad() { super.viewDidLoad(); buildUI() }

    private func buildUI() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = container
        cardViews = []
        for theme in Theme.all {
            let card = ThemeCardView(theme: theme)
            card.isSelected = theme.id == ThemeStore.current.id
            card.translatesAutoresizingMaskIntoConstraints = false
            let t = theme
            card.onSelect = { [weak self] in
                ThemeStore.set(t.id)
                self?.updateCardSelection()
                self?.onThemeChange?(t.id)
            }
            cardViews.append((card, theme))
        }
        let row1 = NSStackView(views: cardViews[0..<3].map { $0.0 as NSView })
        row1.orientation = .horizontal; row1.spacing = 12; row1.translatesAutoresizingMaskIntoConstraints = false
        let row2 = NSStackView(views: cardViews[3..<6].map { $0.0 as NSView })
        row2.orientation = .horizontal; row2.spacing = 12; row2.translatesAutoresizingMaskIntoConstraints = false
        let themeGrid = NSStackView(views: [row1, row2])
        themeGrid.orientation = .vertical; themeGrid.spacing = 10; themeGrid.alignment = .leading
        themeGrid.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: "Appearance")
        titleLabel.stringValue = L10n.text("Appearance", "Görünüm")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let descLabel = NSTextField(labelWithString: L10n.text(
            "Choose a color theme for the menubar and status bar.",
            "Menubar ve durum çubuğu için bir renk teması seçin."
        ))
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor

        let langTitle = NSTextField(labelWithString: L10n.text("Language", "Dil"))
        langTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let langDesc = NSTextField(labelWithString: L10n.text(
            "Use system language automatically or force English/Turkish.",
            "Sistem dilini otomatik kullanın veya İngilizce/Türkçe zorlayın."
        ))
        langDesc.font = NSFont.systemFont(ofSize: 11)
        langDesc.textColor = .secondaryLabelColor
        let langSeg = NSSegmentedControl(
            labels: AppLanguage.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        langSeg.selectedSegment = AppLanguage.allCases.firstIndex(of: LanguageStore.selected) ?? 0
        langSeg.translatesAutoresizingMaskIntoConstraints = false
        langControl = langSeg

        // Separator section
        let sepTitle = NSTextField(labelWithString: L10n.text("Separator", "Ayraç"))
        sepTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let sepDesc = NSTextField(labelWithString: L10n.text(
            "Character shown between agent name, project, and context %.",
            "Ajan adı, proje ve bağlam % arasında gösterilen karakter."
        ))
        sepDesc.font = NSFont.systemFont(ofSize: 11)
        sepDesc.textColor = .secondaryLabelColor

        let seg = NSSegmentedControl(
            labels: SeparatorStore.options.map { $0.label },
            trackingMode: .selectOne,
            target: self,
            action: #selector(separatorChanged(_:))
        )
        seg.selectedSegment = SeparatorStore.currentIndex
        seg.translatesAutoresizingMaskIntoConstraints = false
        sepControl = seg

        // Display elements section — reorder + toggle each menubar title element.
        let dispTitle = NSTextField(labelWithString: L10n.text("Menubar Title", "Menubar Başlığı"))
        dispTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let dispDesc = NSTextField(labelWithString: L10n.text(
            "Toggle and drag to reorder which parts appear in the menubar title.",
            "Menubar başlığında görünecek parçaları açın/kapatın ve sürükleyerek sıralayın."
        ))
        dispDesc.font = NSFont.systemFont(ofSize: 11)
        dispDesc.textColor = .secondaryLabelColor
        displayTable.onChange = { [weak self] in self?.onThemeChange?(ThemeStore.current.id) }

        let mainStack = NSStackView(views: [
            titleLabel, descLabel, themeGrid,
            langTitle, langDesc, langSeg,
            sepTitle, sepDesc, seg,
            dispTitle, dispDesc, displayTable.scrollView,
        ])
        mainStack.orientation = .vertical; mainStack.alignment = .leading; mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            row1.widthAnchor.constraint(equalTo: themeGrid.widthAnchor),
            row2.widthAnchor.constraint(equalTo: themeGrid.widthAnchor),
            displayTable.scrollView.widthAnchor.constraint(equalToConstant: 360),
            displayTable.scrollView.heightAnchor.constraint(equalToConstant: 120),
        ] + cardViews.map { $0.0.heightAnchor.constraint(equalToConstant: 76) })
    }

    private func updateCardSelection() {
        let current = ThemeStore.current.id
        for (card, theme) in cardViews { card.isSelected = theme.id == current }
    }

    @objc private func separatorChanged(_ sender: NSSegmentedControl) {
        let value = SeparatorStore.options[sender.selectedSegment].value
        SeparatorStore.set(value)
        onThemeChange?(ThemeStore.current.id)
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        let language = AppLanguage.allCases[sender.selectedSegment]
        LanguageStore.set(language)
        onThemeChange?(ThemeStore.current.id)
    }
}

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = NSTabViewController()
    let usageVC = UsageViewController()
    private let settingsVC: SettingsViewController

    init(onThemeChange: @escaping (String) -> Void) {
        self.settingsVC = SettingsViewController()
        let usageItem = NSTabViewItem(viewController: usageVC)
        usageItem.label = L10n.text("Usage", "Kullanım")
        let settingsItem = NSTabViewItem(viewController: settingsVC)
        settingsItem.label = L10n.text("Settings", "Ayarlar")
        tabVC.tabStyle = .segmentedControlOnTop
        tabVC.addTabViewItem(usageItem)
        tabVC.addTabViewItem(settingsItem)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = L10n.text("zed-context · usage", "zed-context · kullanım")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = tabVC
        super.init(window: window)
        window.delegate = self
        settingsVC.onThemeChange = onThemeChange
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() { load(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func load() {
        if tabVC.tabViewItems.count >= 2 {
            tabVC.tabViewItems[0].label = L10n.text("Usage", "Kullanım")
            tabVC.tabViewItems[1].label = L10n.text("Settings", "Ayarlar")
        }
        window?.title = L10n.text("zed-context · usage", "zed-context · kullanım")
        usageVC.reload()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer!
    var detailWindow: DetailWindowController?
    let hud = Hud()
    var lastActive: Agent?
    var previewTheme: Theme?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // No icon — title-only menubar entry to save horizontal space.

        refresh()

        timer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc func tick() { refresh() }
    @objc func refreshNow() { refresh() }

    func refresh() {
        let (active, all, others) = hud.load()
        lastActive = active
        let titleTheme = previewTheme ?? ThemeStore.current
        statusItem.button?.attributedTitle = composeTitle(active: active, theme: titleTheme)

        let menu = NSMenu()
        if all.isEmpty {
            let empty = NSMenuItem(title: L10n.text("No agent data yet", "Henüz ajan verisi yok"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let ordered = (active.map { [$0] } ?? []) + all.filter { $0.name != active?.name }
            for (i, a) in ordered.enumerated() {
                let isActive = (a.name == active?.name)
                appendAgent(menu: menu, agent: a, active: isActive)
                if i < ordered.count - 1 {
                    menu.addItem(NSMenuItem.separator())
                }
            }
        }

        // Limits — rolling 5h/7d usage windows with reset countdowns, so the
        // user can see remaining budget without opening the detail page.
        if !all.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let h = NSMenuItem()
            h.isEnabled = false
            h.attributedTitle = NSAttributedString(
                string: L10n.text("LIMITS", "LİMİTLER"),
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 1),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
            menu.addItem(h)
            for a in all {
                appendLimits(menu: menu, agent: a)
            }
        }

        // Other AI tools detected on this system
        if !others.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: L10n.text("Other Tools", "Diğer Araçlar"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(
                string: L10n.text("OTHER TOOLS", "DİĞER ARAÇLAR"),
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 1),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
            menu.addItem(header)
            for tool in others {
                appendTool(menu: menu, tool: tool)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Theme submenu — each entry previews its own colors using a sample
        // title so the user can compare looks before committing.
        let themeRoot = NSMenuItem(title: L10n.text("Theme", "Tema"), action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: L10n.text("Theme", "Tema"))
        let currentId = ThemeStore.current.id
        let sampleProject = active?.project ?? "project"
        let samplePct = active?.ctxPct ?? 42.0
        for t in Theme.all {
            let item = NSMenuItem(
                title: t.name,
                action: #selector(pickTheme(_:)),
                keyEquivalent: ""
            )
            item.representedObject = t.id
            item.state = (t.id == currentId) ? .on : .off
            // Preview: render the sample title in the theme's own colors.
            item.attributedTitle = styleTitle(
                agent: t.name,
                project: sampleProject,
                pct: samplePct,
                theme: t,
                font: NSFont.menuFont(ofSize: 0)
            )
            themeMenu.addItem(item)
        }
        themeMenu.delegate = self
        themeRoot.submenu = themeMenu
        menu.addItem(themeRoot)

        menu.addItem(NSMenuItem(
            title: L10n.text("Open detail report…", "Detay raporunu aç…"),
            action: #selector(openDetail),
            keyEquivalent: "d"
        ))
        menu.addItem(NSMenuItem(
            title: L10n.text("Refresh now", "Şimdi yenile"),
            action: #selector(refreshNow),
            keyEquivalent: "r"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: L10n.text("Quit zed-context-bar", "zed-context-bar'dan çık"),
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    /// Builds the compact menubar title using the active theme:
    ///     <Agent> <sep> <project> <sep> <ctx%>
    private func composeTitle(active: Agent?, theme: Theme = ThemeStore.current) -> NSAttributedString {
        guard let a = active else {
            return NSAttributedString(string: L10n.text(" no agent", " ajan yok"),
                                      attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
        return styleTitle(
            agent: a.name,
            project: a.project,
            pct: a.ctxPct,
            theme: theme,
            font: NSFont.menuBarFont(ofSize: 0)
        )
    }

    private func styleTitle(
        agent: String,
        project: String,
        pct: Double?,
        theme: Theme,
        font: NSFont
    ) -> NSAttributedString {
        let agentAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.agentColor,
        ]
        let dim: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.separatorColor,
        ]
        let projectAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.projectColor,
        ]
        let ctxAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.ctxColor(pct),
        ]
        let pctStr = pct.map { String(format: "%.0f%%", $0) } ?? "—"
        let rawSep = SeparatorStore.current
        let sep = rawSep.isEmpty ? " " : " \(rawSep) "

        let visible = DisplayStore.items.filter { $0.enabled }
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: " ", attributes: agentAttrs))
        if visible.isEmpty {
            return s
        }
        for (i, item) in visible.enumerated() {
            if i > 0 {
                s.append(NSAttributedString(string: sep, attributes: dim))
            }
            switch item.element {
            case .agent:
                s.append(NSAttributedString(string: agent, attributes: agentAttrs))
            case .project:
                s.append(NSAttributedString(string: project, attributes: projectAttrs))
            case .pct:
                s.append(NSAttributedString(string: pctStr, attributes: ctxAttrs))
            }
        }
        return s
    }

    /// Appends a 2-line block describing one agent, themed by the current theme.
    private func appendAgent(menu: NSMenu, agent a: Agent, active: Bool, theme: Theme = ThemeStore.current) {
        let header = NSMenuItem()
        header.isEnabled = false
        let pctStr = a.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
        let dot = active ? theme.activeDot : theme.inactiveDot
        let rawSep = SeparatorStore.current
        let sep = rawSep.isEmpty ? "  " : "  \(rawSep)  "
        let titleStr = "\(dot) \(a.name)\(sep)\(a.project)\(sep)\(pctStr)"

        let font = NSFont.menuFont(ofSize: 0)
        let attr = NSMutableAttributedString(
            string: titleStr,
            attributes: [.font: font, .foregroundColor: theme.agentColor]
        )
        if let range = titleStr.range(of: a.project) {
            attr.addAttribute(
                .foregroundColor,
                value: theme.projectColor,
                range: NSRange(range, in: titleStr)
            )
        }
        if let range = titleStr.range(of: pctStr) {
            attr.addAttribute(
                .foregroundColor,
                value: theme.ctxColor(a.ctxPct),
                range: NSRange(range, in: titleStr)
            )
        }
        header.attributedTitle = attr
        menu.addItem(header)

        let modelStr = a.model ?? "—"
        let duration = Hud.formatDuration(a.sessionStarted, a.lastTurn)

        // ── Active session row ─────────────────────────────────
        let sessionItem = NSMenuItem()
        sessionItem.isEnabled = false
        let sess = NSMutableAttributedString()
        let sessionFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let mono = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        sess.append(NSAttributedString(string: "      ", attributes: [.font: sessionFont]))
        // Green dot when active, dim when idle
        let dotColor: NSColor = active ? .systemGreen : .tertiaryLabelColor
        sess.append(NSAttributedString(string: "⏺  ", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: dotColor,
        ]))
        sess.append(NSAttributedString(string: modelStr, attributes: [
            .font: mono, .foregroundColor: NSColor.labelColor,
        ]))
        sess.append(NSAttributedString(string: "   \(duration)", attributes: [
            .font: sessionFont, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        sessionItem.attributedTitle = sess
        menu.addItem(sessionItem)

        // ── Last turn row ──────────────────────────────────────
        let last = a.lastTurn.map { Hud.relative($0) } ?? "—"
        let lastItem = NSMenuItem()
        lastItem.isEnabled = false
        lastItem.attributedTitle = NSAttributedString(
            string: "             \(L10n.text("last turn", "son tur"))   \(last)",
            attributes: [
                .font: sessionFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        menu.addItem(lastItem)

        // If more than one session is live concurrently for this agent, render
        // a row per session so 3-5 parallel sessions stay visible. Skip the
        // top one (already represented by the header line above).
        if a.activeSessions.count > 1 {
            let concurrentSep = SeparatorStore.current.isEmpty ? "·" : SeparatorStore.current
            let topId = a.activeSessions.first?.id
            for sess in a.activeSessions where sess.id != topId {
                let tok = Hud.formatTokens(sess.tokens)
                let when = sess.lastTurn.map { Hud.relative($0) } ?? "—"
                let proj = sess.project
                let model = sess.model ?? "—"
                let line = "      \(theme.inactiveDot) \(proj)  \(concurrentSep)  \(tok)  \(concurrentSep)  \(model)  \(concurrentSep)  \(when)"
                let item = NSMenuItem()
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(
                    string: line,
                    attributes: [
                        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
                menu.addItem(item)
            }
        }
    }

    // MARK: - NSMenuDelegate (live theme preview)

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let item, let themeId = item.representedObject as? String,
              Theme.all.contains(where: { $0.id == themeId }) else {
            if previewTheme != nil {
                previewTheme = nil
                statusItem.button?.attributedTitle = composeTitle(active: lastActive)
            }
            return
        }
        let theme = Theme.by(id: themeId)
        previewTheme = theme
        statusItem.button?.attributedTitle = composeTitle(active: lastActive, theme: theme)
    }

    func menuDidClose(_ menu: NSMenu) {
        previewTheme = nil
        statusItem.button?.attributedTitle = composeTitle(active: lastActive)
    }

    private func appendLimits(menu: NSMenu, agent a: Agent) {
        // Agent name row
        let nameItem = NSMenuItem()
        nameItem.isEnabled = false
        nameItem.attributedTitle = NSAttributedString(
            string: "      \(a.name)",
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 0.5),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(nameItem)

        for (label, tokens, resetsAt) in [
            ("5h", a.session5h, a.session5hResetsAt),
            ("7d", a.week7d, a.week7dResetsAt),
        ] {
            let view = LimitRowView(
                label: label,
                tokens: label == "5h"
                    ? Hud.formatUsageValue(percent: a.session5hPercent, tokens: tokens)
                    : Hud.formatUsageValue(percent: a.week7dPercent, tokens: tokens),
                reset: Hud.resetsIn(resetsAt)
            )
            view.frame = NSRect(x: 0, y: 0, width: 320, height: 22)
            let item = NSMenuItem()
            item.isEnabled = false
            item.view = view
            menu.addItem(item)
        }
    }

    private func appendTool(menu: NSMenu, tool: ToolSummary) {
        let item = NSMenuItem()
        item.isEnabled = false
        let tok = tool.tokens7d > 0 ? "  \(Hud.formatTokens(tool.tokens7d))" : ""
        let sess = tool.sessions7d > 0 ? "  \(tool.sessions7d)×/\(L10n.text("wk", "hf"))" : ""
        let model = tool.lastModel.map { "  \($0)" } ?? ""
        let line = "\(tool.name)\(tok)\(sess)\(model)"
        item.attributedTitle = NSAttributedString(
            string: line,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(item)
    }

    @objc func pickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeStore.set(id)
        refresh()
    }

    @objc func openDetail() {
        if detailWindow == nil {
            detailWindow = DetailWindowController(onThemeChange: { [weak self] _ in
                self?.refresh()
                self?.detailWindow?.load()
            })
        }
        detailWindow?.show()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
