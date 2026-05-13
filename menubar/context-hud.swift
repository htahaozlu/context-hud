// context-hud
//
// macOS menubar HUD for Claude Code + Codex CLI usage. Reads the structured
// JSON sidecar at ~/.context-hud/hud.json (kept fresh by the context-hud
// daemon) and renders:
//   - menubar icon (SF Symbol "sparkles") + colored compact title with the
//     currently-active agent, its project basename, and context %
//   - dropdown listing every agent stacked, with project, model, tokens, and
//     relative "last turn" time
//
// Build:   swiftc -O context-hud.swift -o ~/.cargo/bin/context-hud
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
        case .agent: return text("Agent icon", "Ajan ikonu")
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

struct AgentVisual {
    let assetName: String?
    let accessibilityLabel: String

    static func forName(_ name: String) -> Self {
        switch name.lowercased() {
        case "claude":
            return .init(assetName: "claude", accessibilityLabel: "Claude")
        case "codex":
            return .init(assetName: "codex", accessibilityLabel: "Codex")
        case "gemini":
            return .init(assetName: "gemini", accessibilityLabel: "Gemini")
        case "copilot cli", "copilot":
            return .init(assetName: "copilot", accessibilityLabel: "Copilot CLI")
        case "deepseek":
            return .init(assetName: "deepseek", accessibilityLabel: "DeepSeek")
        case "qwen":
            return .init(assetName: "qwen", accessibilityLabel: "Qwen")
        case "minimax":
            return .init(assetName: "minimax", accessibilityLabel: "MiniMax")
        default:
            return .init(assetName: nil, accessibilityLabel: name)
        }
    }
}

private func agentIconURL(name: String) -> URL? {
    guard let assetName = AgentVisual.forName(name).assetName else { return nil }
    if let bundled = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "brands") {
        return bundled
    }
    let repoAsset = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("menubar/assets/brands/\(assetName).png")
    return FileManager.default.fileExists(atPath: repoAsset.path) ? repoAsset : nil
}

private func agentInlineString(
    name: String,
    font: NSFont,
    fallbackColor: NSColor,
    iconScale: CGFloat = 1.0
) -> NSAttributedString {
    let visual = AgentVisual.forName(name)
    if let url = agentIconURL(name: name), let image = NSImage(contentsOf: url) {
        let attachment = NSTextAttachment()
        let icon = (image.copy() as? NSImage) ?? image
        let side = max(12, round(font.capHeight * iconScale))
        icon.size = NSSize(width: side, height: side)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: icon)
        attachment.bounds = NSRect(x: 0, y: round((font.capHeight - side) / 2) - 1, width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }
    return NSAttributedString(
        string: visual.accessibilityLabel,
        attributes: [
            .font: font,
            .foregroundColor: fallbackColor,
        ]
    )
}

private func agentInlineLabel(name: String, font: NSFont, color: NSColor, iconScale: CGFloat = 1.0) -> NSTextField {
    let label = NSTextField(
        labelWithAttributedString: agentInlineString(
            name: name,
            font: font,
            fallbackColor: color,
            iconScale: iconScale
        )
    )
    label.toolTip = AgentVisual.forName(name).accessibilityLabel
    return label
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
        let env = ProcessInfo.processInfo.environment
        self.path = env["CONTEXTHUD_HUD_PATH"] ?? "\(NSHomeDirectory())/.context-hud/hud.json"
        self.usageCachePath = env["CONTEXTHUD_USAGE_CACHE_PATH"] ?? "\(NSHomeDirectory())/.context-hud/usage_api_cache.json"
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
        let tr = L10n.lang == .tr
        let dU = tr ? "g" : "d"
        let hU = tr ? "sa" : "h"
        let mU = tr ? "dk" : "m"
        if remaining <= 0 { return L10n.text("ready", "hazır") }
        if remaining < 60 { return "<1\(mU)" }
        if remaining < 3600 { return "\(Int(remaining/60))\(mU)" }
        if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = (Int(remaining) % 3600) / 60
            return m == 0 ? "\(h)\(hU)" : "\(h)\(hU) \(m)\(mU)"
        }
        let d = Int(remaining / 86400)
        let h = (Int(remaining) % 86400) / 3600
        return h == 0 ? "\(d)\(dU)" : "\(d)\(dU) \(h)\(hU)"
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

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
    private let pctField   = NSTextField(labelWithString: "")
    private let resetField = NSTextField(labelWithString: "")
    private let bar        = ProgressBarView()

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 38) }

    init(label: String, percent: Double?, reset: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 38))

        let pctText = percent.map { String(format: "%.0f%%", $0) } ?? "—"
        let barValue = (percent ?? 0) / 100.0
        let barColor: NSColor = {
            guard let p = percent else { return .controlAccentColor }
            if p >= 90 { return .systemRed }
            if p >= 70 { return .systemOrange }
            return .systemGreen
        }()

        labelField.stringValue = label
        labelField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        labelField.textColor = .secondaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false

        pctField.stringValue = pctText
        pctField.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        pctField.textColor = barColor
        pctField.translatesAutoresizingMaskIntoConstraints = false

        resetField.stringValue = "↻ \(reset)"
        resetField.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
        resetField.textColor = .tertiaryLabelColor
        resetField.alignment = .right
        resetField.translatesAutoresizingMaskIntoConstraints = false

        bar.value = barValue
        bar.tint = barColor
        bar.corner = 2
        bar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelField); addSubview(pctField); addSubview(resetField); addSubview(bar)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            labelField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            labelField.widthAnchor.constraint(equalToConstant: 36),

            pctField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 6),
            pctField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),

            resetField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            resetField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),

            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bar.topAnchor.constraint(equalTo: labelField.bottomAnchor, constant: 5),
            bar.heightAnchor.constraint(equalToConstant: 4),
        ])
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
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 0

        let cap = NSTextField(labelWithString: caption)
        cap.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        cap.textColor = .secondaryLabelColor
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
/// sparkline. Replaces the previous webview approach so the panel feels at
/// home on macOS (no scrollbars, no font drift, no white flash).
final class UsageViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let container = NSStackView()

    override func loadView() {
        view = FlippedView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 18, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 18
        container.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(container)
        scrollView.documentView = doc

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
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
        let primary = active ?? all[0]
        let card = buildAgentCard(agent: primary, isActive: true, showsHeader: true)
        container.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        if !others.isEmpty {
            let othersCard = buildOthersCard(tools: others)
            container.addArrangedSubview(othersCard)
            othersCard.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
    }

    /// Agent card: header + 4 stat tiles (context / active session / 5h / 7d) +
    /// 30-day sparkline. All data visible by default — no disclosures. Each
    /// tile pairs a primary value with a faded sub-value so the user sees both
    /// "what" and "when/how much" without scanning multiple sections.
    private func buildAgentCard(agent a: Agent, isActive: Bool, showsHeader: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        card.layer?.borderWidth = 0
        card.translatesAutoresizingMaskIntoConstraints = false

        // Header: ● Name  · model · project · last turn
        let dot = NSTextField(labelWithString: "●")
        dot.font = NSFont.systemFont(ofSize: 10)
        dot.textColor = isActive ? .systemGreen : .tertiaryLabelColor

        let nameLbl = agentInlineLabel(
            name: a.name,
            font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            color: .labelColor,
            iconScale: 1.15
        )

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
        let ctxSub = a.ctxWindow.map { L10n.text("\(Hud.formatTokens($0)) window", "\(Hud.formatTokens($0)) pencere") } ?? "—"
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
        if showsHeader {
            stack.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
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
        let path = "\(NSHomeDirectory())/.context-hud/hud.json"
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
            let name = agentInlineLabel(
                name: t.name,
                font: NSFont.systemFont(ofSize: 12, weight: .medium),
                color: .labelColor
            )
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
        s.append(agentInlineString(name: "Claude", font: font, fallbackColor: theme.agentColor))
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

struct AppMetadata {
    let version: String
    let build: String

    static var current: AppMetadata {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppMetadata(
            version: version ?? "0.1.0",
            build: build ?? "1"
        )
    }

    var versionLabel: String {
        "v\(version)"
    }

    var detailedVersionLabel: String {
        "v\(version) (\(build))"
    }
}

struct ReleaseInfo {
    let latest: String
    let current: String
    let htmlURL: URL
    let dmgURL: URL
}

final class UpdateProgressWindowController: NSWindowController {
    private let messageLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 132)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Updating ContextHUD", "ContextHUD güncelleniyor")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let content = NSView(frame: contentRect)
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        messageLabel.textColor = .labelColor
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .regular
        progress.style = .bar
        progress.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(messageLabel)
        content.addSubview(detailLabel)
        content.addSubview(progress)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            messageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),

            progress.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 16),
            progress.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(message: String, detail: String, fraction: Double?) {
        messageLabel.stringValue = message
        detailLabel.stringValue = detail
        if let fraction {
            progress.isIndeterminate = false
            progress.doubleValue = max(0, min(1, fraction))
        } else {
            progress.isIndeterminate = true
            progress.startAnimation(nil)
        }
    }
}

final class UpdateManager: NSObject, URLSessionDownloadDelegate {
    static let shared = UpdateManager()

    private var progressWindow: UpdateProgressWindowController?
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var activeRelease: ReleaseInfo?

    func checkForUpdates(presenter: NSWindow?) {
        let apiURL = URL(string: "https://api.github.com/repos/htahaozlu/context-hud/releases/latest")!
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard err == nil,
                      let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = obj["tag_name"] as? String else {
                    self.presentUpdateError(presenter: presenter)
                    return
                }
                let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let current = AppMetadata.current.version
                let htmlURL = (obj["html_url"] as? String).flatMap(URL.init(string:))
                    ?? URL(string: "https://github.com/htahaozlu/context-hud/releases/latest")!
                let assets = (obj["assets"] as? [[String: Any]]) ?? []
                let dmgURL = assets.compactMap { asset -> URL? in
                    guard let name = asset["name"] as? String,
                          name.hasSuffix(".dmg"),
                          let raw = asset["browser_download_url"] as? String else { return nil }
                    return URL(string: raw)
                }.first
                guard self.isNewer(latest: latest, current: current) else {
                    self.presentUpToDate(current: current, presenter: presenter)
                    return
                }
                guard let dmgURL else {
                    self.presentUpdateError(presenter: presenter)
                    return
                }
                let release = ReleaseInfo(latest: latest, current: current, htmlURL: htmlURL, dmgURL: dmgURL)
                self.presentUpdateAvailable(release: release, presenter: presenter)
            }
        }.resume()
    }

    private func isNewer(latest: String, current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let li = i < l.count ? l[i] : 0
            let ci = i < c.count ? c[i] : 0
            if li > ci { return true }
            if li < ci { return false }
        }
        return false
    }

    private func presentUpdateAvailable(release: ReleaseInfo, presenter: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Update available", "Güncelleme hazır")
        alert.informativeText = L10n.text(
            "ContextHUD v\(release.latest) is available. Download it now and restart when it's ready.",
            "ContextHUD v\(release.latest) hazır. Şimdi indirilsin, hazır olunca yeniden başlatıp güncelleyin."
        )
        alert.addButton(withTitle: L10n.text("Update Now", "Şimdi Güncelle"))
        alert.addButton(withTitle: L10n.text("Release Notes", "Sürüm Notları"))
        alert.addButton(withTitle: L10n.text("Later", "Daha Sonra"))
        let response = runAlert(alert, presenter: presenter)
        if response == .alertFirstButtonReturn {
            startDownload(release: release)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func startDownload(release: ReleaseInfo) {
        activeRelease = release
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.downloadTask(with: release.dmgURL)
        downloadTask = task
        let progressWindow = UpdateProgressWindowController()
        progressWindow.present()
        progressWindow.update(
            message: L10n.text("Downloading update…", "Güncelleme indiriliyor…"),
            detail: L10n.text("ContextHUD v\(release.latest) is being prepared.", "ContextHUD v\(release.latest) hazırlanıyor."),
            fraction: 0
        )
        self.progressWindow = progressWindow
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let release = activeRelease else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressWindow?.update(
            message: L10n.text("Downloading update…", "Güncelleme indiriliyor…"),
            detail: L10n.text(
                "\(formatBytes(totalBytesWritten)) of \(formatBytes(totalBytesExpectedToWrite))",
                "\(formatBytes(totalBytesWritten)) / \(formatBytes(totalBytesExpectedToWrite))"
            ),
            fraction: fraction
        )
        if fraction >= 1 {
            progressWindow?.update(
                message: L10n.text("Preparing update…", "Güncelleme hazırlanıyor…"),
                detail: L10n.text("Verifying and staging ContextHUD v\(release.latest).", "ContextHUD v\(release.latest) doğrulanıyor ve hazırlanıyor."),
                fraction: nil
            )
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let release = activeRelease else { return }
        do {
            let mountURL = try mountDMG(at: location)
            let stagedApp = mountURL.appendingPathComponent("ContextHUD.app")
            guard FileManager.default.fileExists(atPath: stagedApp.path) else {
                throw NSError(domain: "ContextHUD.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mounted DMG did not contain ContextHUD.app"])
            }
            try stageInstaller(sourceApp: stagedApp, mountedVolume: mountURL)
            progressWindow?.close()
            progressWindow = nil
            presentRestartPrompt(release: release)
        } catch {
            progressWindow?.close()
            progressWindow = nil
            presentInstallError(error)
        }
        cleanupSession()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            progressWindow?.close()
            progressWindow = nil
            cleanupSession()
            presentInstallError(error)
        }
    }

    private func presentRestartPrompt(release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Restart to Update", "Güncellemek İçin Yeniden Başlat")
        alert.informativeText = L10n.text(
            "ContextHUD v\(release.latest) is ready to install. Restart now to finish the update.",
            "ContextHUD v\(release.latest) kuruluma hazır. Güncellemeyi tamamlamak için şimdi yeniden başlatın."
        )
        alert.addButton(withTitle: L10n.text("Restart to Update", "Güncellemek İçin Yeniden Başlat"))
        alert.addButton(withTitle: L10n.text("Later", "Daha Sonra"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func presentUpToDate(current: String, presenter: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Up to date", "Güncel")
        alert.informativeText = L10n.text(
            "You are running the latest version (v\(current)).",
            "En son sürümü kullanıyorsunuz (v\(current))."
        )
        alert.addButton(withTitle: "OK")
        _ = runAlert(alert, presenter: presenter)
    }

    private func presentUpdateError(presenter: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Could not check for updates", "Güncellemeler kontrol edilemedi")
        alert.informativeText = L10n.text(
            "Check your internet connection and try again.",
            "İnternet bağlantınızı kontrol edin ve tekrar deneyin."
        )
        alert.addButton(withTitle: "OK")
        _ = runAlert(alert, presenter: presenter)
    }

    private func presentInstallError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Update could not be completed", "Güncelleme tamamlanamadı")
        alert.informativeText = L10n.text(
            "ContextHUD could not finish installing the update.\n\n\(error.localizedDescription)",
            "ContextHUD güncellemeyi tamamlayamadı.\n\n\(error.localizedDescription)"
        )
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func cleanupSession() {
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func mountDMG(at location: URL) throws -> URL {
        let tempDMG = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextHUD-\(UUID().uuidString).dmg")
        if FileManager.default.fileExists(atPath: tempDMG.path) {
            try? FileManager.default.removeItem(at: tempDMG)
        }
        try FileManager.default.copyItem(at: location, to: tempDMG)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", tempDMG.path, "-nobrowse", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "ContextHUD.Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to mount the downloaded disk image."])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw NSError(domain: "ContextHUD.Update", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not locate the mounted update volume."])
        }
        return URL(fileURLWithPath: mountPath)
    }

    private func stageInstaller(sourceApp: URL, mountedVolume: URL) throws {
        let currentApp = Bundle.main.bundleURL.standardizedFileURL
        let destination = currentApp
        let parent = destination.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexthud-update-\(UUID().uuidString).sh")

        let source = shellEscape(sourceApp.path)
        let dest = shellEscape(destination.path)
        let mount = shellEscape(mountedVolume.path)
        let openTarget = shellEscape(destination.path)
        let script = """
#!/bin/sh
set -e
PID="\(pid)"
SRC=\(source)
DST=\(dest)
VOL=\(mount)
TMP="${DST}.new"
OLD="${DST}.old"
while kill -0 "$PID" 2>/dev/null; do
  sleep 0.25
done
/bin/rm -rf "$TMP"
/usr/bin/ditto "$SRC" "$TMP"
/bin/rm -rf "$OLD"
if [ -e "$DST" ]; then
  /bin/mv "$DST" "$OLD"
fi
/bin/mv "$TMP" "$DST"
/usr/bin/xattr -dr com.apple.quarantine "$DST" >/dev/null 2>&1 || true
/usr/bin/hdiutil detach "$VOL" -quiet >/dev/null 2>&1 || true
/usr/bin/open \(openTarget)
/bin/rm -rf "$OLD"
/bin/rm -- "$0"
"""
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let writable = FileManager.default.isWritableFile(atPath: parent.path)
            && FileManager.default.isWritableFile(atPath: destination.path)
        if writable {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [helper.path]
            try task.run()
            return
        }

        let command = "/bin/sh \(shellEscape(helper.path))"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "do shell script " + appleScriptString(command) + " with administrator privileges",
        ]
        try task.run()
    }

    private func runAlert(_ alert: NSAlert, presenter: NSWindow?) -> NSApplication.ModalResponse {
        if presenter != nil {
            return alert.runModal()
        }
        return alert.runModal()
    }

    private func formatBytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: count)
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

func appLogoImage() -> NSImage? {
    if let bundled = Bundle.main.url(forResource: "logo", withExtension: "png") {
        return NSImage(contentsOf: bundled)
    }
    let repoLogo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("logo.png")
    return NSImage(contentsOf: repoLogo)
}

final class AboutHeroView: NSView {
    init(metadata: AppMetadata = .current) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let logoView = NSImageView()
        logoView.image = appLogoImage()
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.imageAlignment = .alignCenter
        logoView.translatesAutoresizingMaskIntoConstraints = false

        let appName = NSTextField(labelWithString: "ContextHUD")
        appName.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        appName.textColor = .labelColor
        appName.alignment = .center

        let version = NSTextField(labelWithString: "Version \(metadata.version) (\(metadata.build))")
        version.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let note = NSTextField(wrappingLabelWithString: L10n.text(
            "Native repository context and coding-agent usage visibility for macOS.",
            "macOS için yerel depo bağlamı ve kodlama ajanı kullanım görünürlüğü."
        ))
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = .tertiaryLabelColor
        note.maximumNumberOfLines = 0
        note.alignment = .center

        let stack = NSStackView(views: [logoView, appName, version, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: logoView)
        stack.setCustomSpacing(2, after: appName)
        stack.setCustomSpacing(10, after: version)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            logoView.heightAnchor.constraint(equalToConstant: 120),
            logoView.widthAnchor.constraint(equalToConstant: 360),
            note.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class ResponsiveInfoRowView: NSView {
    init(title: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.maximumNumberOfLines = 2
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class MenuHeaderView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 324, height: 84) }

    init(active: Agent?, metadata: AppMetadata = .current) {
        super.init(frame: NSRect(x: 0, y: 0, width: 324, height: 84))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let title = NSTextField(labelWithString: "ContextHUD")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

        let subtitleText = active.map {
            let pct = $0.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
            return "\($0.name)  ·  \($0.project)  ·  \(pct)"
        } ?? L10n.text("No active agent yet", "Henüz aktif ajan yok")
        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
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

final class ChipCardView: NSView, NSDraggingSource {
    static let dragType = NSPasteboard.PasteboardType("com.contexthud.chip")
    let index: Int
    var onToggle: ((Int, Bool) -> Void)?
    private let checkbox: NSButton
    private let handle: NSTextField
    private let label: NSTextField

    init(item: DisplayItem, index: Int) {
        self.index = index
        self.handle = NSTextField(labelWithString: "⠿")
        self.label = NSTextField(labelWithString: item.element.label)
        self.checkbox = NSButton(checkboxWithTitle: L10n.text("Show", "Göster"),
                                 target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        handle.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        handle.textColor = .tertiaryLabelColor
        handle.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        checkbox.state = item.enabled ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(checkboxToggled(_:))
        checkbox.font = NSFont.systemFont(ofSize: 12)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        addSubview(handle)
        addSubview(label)
        addSubview(checkbox)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            handle.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            label.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: handle.centerYAnchor),

            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            checkbox.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 8),
            checkbox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 168),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        onToggle?(index, sender.state == .on)
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let cbHit = checkbox.frame.insetBy(dx: -6, dy: -6)
        if cbHit.contains(pt) {
            super.mouseDown(with: event)
            return
        }
        NSCursor.closedHand.push()
        let start = event.locationInWindow
        var current: NSEvent? = event
        while let ev = current {
            if ev.type == .leftMouseUp {
                NSCursor.pop()
                return
            }
            if ev.type == .leftMouseDragged {
                if hypot(ev.locationInWindow.x - start.x, ev.locationInWindow.y - start.y) > 4 {
                    NSCursor.pop()
                    startDrag(event: ev)
                    return
                }
            }
            current = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }
        NSCursor.pop()
    }

    private func startDrag(event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString("\(index)", forType: Self.dragType)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let size = bounds.size
        let snap = NSImage(size: size)
        snap.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAlpha(0.9)
            layer?.render(in: ctx)
        }
        snap.unlockFocus()
        dragItem.setDraggingFrame(NSRect(origin: .zero, size: size), contents: snap)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
}

final class ChipContainer: NSStackView {
    var onReorder: ((Int, Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([ChipCardView.dragType])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([ChipCardView.dragType])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pbItem = sender.draggingPasteboard.pasteboardItems?.first,
              let s = pbItem.string(forType: ChipCardView.dragType),
              let from = Int(s) else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        let cards = arrangedSubviews.compactMap { $0 as? ChipCardView }
        var target = cards.count - 1
        for (i, v) in cards.enumerated() {
            if p.x < v.frame.midX { target = i; break }
        }
        onReorder?(from, target)
        return true
    }
}

final class HorizontalDisplayController: NSObject {
    private var items: [DisplayItem] = DisplayStore.items
    var onChange: (() -> Void)?
    let container: ChipContainer

    override init() {
        self.container = ChipContainer(frame: .zero)
        super.init()
        container.orientation = .horizontal
        container.spacing = 10
        container.alignment = .top
        container.distribution = .fillEqually
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onReorder = { [weak self] from, to in
            self?.reorder(from: from, to: to)
        }
        rebuild()
    }

    var currentItems: [DisplayItem] { items }

    private func rebuild() {
        container.arrangedSubviews.forEach {
            container.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (idx, item) in items.enumerated() {
            let card = ChipCardView(item: item, index: idx)
            card.onToggle = { [weak self] tag, enabled in
                guard let self = self, tag < self.items.count else { return }
                self.items[tag].enabled = enabled
                self.persist()
            }
            container.addArrangedSubview(card)
        }
    }

    private func reorder(from: Int, to: Int) {
        guard from >= 0, from < items.count, to >= 0, to < items.count, from != to else { return }
        let moved = items.remove(at: from)
        items.insert(moved, at: to)
        DisplayStore.save(items)
        rebuild()
        onChange?()
    }

    private func persist() {
        DisplayStore.save(items)
        onChange?()
    }
}

final class TitlePreviewView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    func update(items: [DisplayItem], agent: String, project: String, pct: Double?) {
        let theme = ThemeStore.current
        let font = NSFont.menuBarFont(ofSize: 0)
        let projectAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.projectColor]
        let ctxAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.ctxColor(pct)]
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.separatorColor]
        let rawSep = SeparatorStore.current
        let sep = rawSep.isEmpty ? " " : " \(rawSep) "
        let pctStr = pct.map { String(format: "%.0f%%", $0) } ?? "—"

        let s = NSMutableAttributedString()
        let visible = items.filter { $0.enabled }
        if visible.isEmpty {
            s.append(NSAttributedString(
                string: L10n.text("(nothing selected)", "(hiçbir alan seçili değil)"),
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        } else {
            for (i, item) in visible.enumerated() {
                if i > 0 {
                    s.append(NSAttributedString(string: sep, attributes: dim))
                }
                switch item.element {
                case .agent: s.append(agentInlineString(name: agent, font: font, fallbackColor: theme.agentColor))
                case .project: s.append(NSAttributedString(string: project, attributes: projectAttrs))
                case .pct: s.append(NSAttributedString(string: pctStr, attributes: ctxAttrs))
                }
            }
        }
        label.attributedStringValue = s
    }
}

final class PreferenceSectionCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 0
        translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

class PreferencePaneViewController: NSViewController {
    let scrollView = NSScrollView()
    let contentStack = NSStackView()

    override func loadView() {
        view = FlippedView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 22
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 28),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -28),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28),
        ])
    }

    func addHero(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    func addSection(title: String, subtitle: String? = nil, body: NSView) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4
        section.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        section.addArrangedSubview(titleLabel)

        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.maximumNumberOfLines = 0
            section.addArrangedSubview(subtitleLabel)
            section.setCustomSpacing(10, after: subtitleLabel)
        } else {
            section.setCustomSpacing(8, after: titleLabel)
        }

        let card = PreferenceSectionCard(content: body)
        section.addArrangedSubview(card)
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    func makeInfoRow(title: String, value: String) -> NSView {
        ResponsiveInfoRowView(title: title, value: value)
    }
}

final class AppearanceSettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    private var cardViews: [(ThemeCardView, Theme)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        cardViews = Theme.all.map { theme in
            let card = ThemeCardView(theme: theme)
            card.isSelected = theme.id == ThemeStore.current.id
            card.translatesAutoresizingMaskIntoConstraints = false
            card.onSelect = { [weak self] in
                ThemeStore.set(theme.id)
                self?.updateCardSelection()
                self?.onThemeChange?(theme.id)
            }
            return (card, theme)
        }

        let rows = stride(from: 0, to: cardViews.count, by: 3).map { start -> NSStackView in
            let end = min(start + 3, cardViews.count)
            let row = NSStackView(views: cardViews[start..<end].map { $0.0 as NSView })
            row.orientation = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        let themeGrid = NSStackView(views: rows)
        themeGrid.orientation = .vertical
        themeGrid.spacing = 12
        addSection(
            title: L10n.text("Theme", "Tema"),
            subtitle: L10n.text(
                "Pick the menubar palette that matches your desktop. The preview uses the same typography and accent logic shown in the status item.",
                "Masaüstüne en uygun menubar paletini seçin. Önizleme, durum çubuğunda kullanılan aynı tipografi ve vurgu mantığını gösterir."
            ),
            body: themeGrid
        )
        cardViews.forEach { $0.0.heightAnchor.constraint(equalToConstant: 82).isActive = true }

        let langControl = NSSegmentedControl(
            labels: AppLanguage.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        langControl.selectedSegment = AppLanguage.allCases.firstIndex(of: LanguageStore.selected) ?? 0
        addSection(
            title: L10n.text("Language", "Dil"),
            subtitle: L10n.text(
                "Follow the system language or pin the UI to English or Turkish.",
                "Arayuzu sistem diline birakin ya da Ingilizce/Turkce olarak sabitleyin."
            ),
            body: langControl
        )
    }

    private func updateCardSelection() {
        let current = ThemeStore.current.id
        for (card, theme) in cardViews {
            card.isSelected = theme.id == current
        }
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        let language = AppLanguage.allCases[sender.selectedSegment]
        LanguageStore.set(language)
        onThemeChange?(ThemeStore.current.id)
    }
}

final class MenubarSettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    private let displayChips = HorizontalDisplayController()
    private let preview = TitlePreviewView()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshPreview()
    }

    private func buildUI() {
        let sepControl = NSSegmentedControl(
            labels: SeparatorStore.options.map { $0.label },
            trackingMode: .selectOne,
            target: self,
            action: #selector(separatorChanged(_:))
        )
        sepControl.selectedSegment = SeparatorStore.currentIndex
        addSection(
            title: L10n.text("Separator", "Ayraç"),
            subtitle: L10n.text(
                "Character shown between the agent icon, project, and context values in the menubar title.",
                "Menubar başlığında ajan ikonu, proje ve bağlam değerleri arasında gösterilen karakter."
            ),
            body: sepControl
        )

        displayChips.onChange = { [weak self] in
            self?.refreshPreview()
            self?.onThemeChange?(ThemeStore.current.id)
        }
        addSection(
            title: L10n.text("Title content", "Başlık içeriği"),
            subtitle: L10n.text(
                "Toggle the checkbox to show a field. Grab the ⠿ handle and drag a card left or right to reorder.",
                "Bir alanı göstermek için onay kutusunu işaretleyin. Sıralamak için ⠿ tutamacından kartı sağa veya sola sürükleyin."
            ),
            body: displayChips.container
        )

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        addSection(
            title: L10n.text("Preview", "Önizleme"),
            subtitle: L10n.text(
                "Live sample of how the menubar title will look with agent icons. Changes apply instantly.",
                "Menubar başlığının ajan ikonlarıyla nasıl görüneceğine dair canlı örnek. Değişiklikler anında uygulanır."
            ),
            body: preview
        )
    }

    private func refreshPreview() {
        preview.update(
            items: displayChips.currentItems,
            agent: "Claude",
            project: "hususi-app",
            pct: 27
        )
    }

    @objc private func separatorChanged(_ sender: NSSegmentedControl) {
        let value = SeparatorStore.options[sender.selectedSegment].value
        SeparatorStore.set(value)
        refreshPreview()
        onThemeChange?(ThemeStore.current.id)
    }
}

final class AboutViewController: PreferencePaneViewController {
    private let changelogURL = URL(string: "https://github.com/htahaozlu/context-hud/blob/main/CHANGELOG.md")!

    override func viewDidLoad() {
        super.viewDidLoad()

        addHero(AboutHeroView())

        let actions = NSStackView(views: [
            makeActionButton(
                title: L10n.text("Check for Updates", "Güncellemeleri kontrol et"),
                action: #selector(checkForUpdates)
            ),
            makeActionButton(
                title: L10n.text("View Changelog", "Değişiklik kaydını aç"),
                action: #selector(openChangelog)
            )
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        addSection(
            title: L10n.text("Updates", "Güncellemeler"),
            subtitle: L10n.text(
                "ContextHUD releases are distributed from GitHub Releases.",
                "ContextHUD sürümleri GitHub Releases üzerinden dağıtılır."
            ),
            body: actions
        )

        let context = NSStackView(views: [
            makeInfoRow(title: L10n.text("Artifacts folder", "Artifact klasörü"), value: "\(NSHomeDirectory())/.context-hud"),
            makeInfoRow(title: L10n.text("Repository brief", "Repo brifi"), value: ".context-hud/AGENT.md"),
            makeInfoRow(title: L10n.text("Claude compatibility", "Claude uyumluluğu"), value: "CLAUDE.md"),
        ])
        context.orientation = .vertical
        context.spacing = 10
        context.alignment = .leading
        addSection(
            title: L10n.text("Repository context", "Repo bağlamı"),
            subtitle: L10n.text(
                "Stable local brief and machine-readable sidecars so agents re-enter a project with less drift.",
                "Ajanlar projeye daha az kayma ile geri dönebilsin diye sabit yerel brief ve makinece okunabilir yan dosyalar."
            ),
            body: context
        )

        let sources = NSStackView(views: [
            makeInfoRow(title: "Git", value: L10n.text("branch, commits, worktree", "branch, commit, worktree")),
            makeInfoRow(title: "Claude Code", value: "~/.claude/projects/**/*.jsonl"),
            makeInfoRow(title: "Codex CLI", value: "~/.codex/sessions/**/*.jsonl"),
            makeInfoRow(title: "Output", value: "~/.context-hud/hud.json"),
        ])
        sources.orientation = .vertical
        sources.spacing = 10
        sources.alignment = .leading
        addSection(
            title: L10n.text("Data sources", "Veri kaynakları"),
            subtitle: L10n.text(
                "Usage is built locally from existing transcript files. No remote service required.",
                "Kullanım özeti mevcut transcript dosyalarından yerelde oluşturulur. Uzak servis gerekmez."
            ),
            body: sources
        )

        let locations = NSStackView(views: [
            makeInfoRow(title: L10n.text("Version", "Sürüm"), value: AppMetadata.current.detailedVersionLabel),
            makeInfoRow(title: L10n.text("App bundle", "Uygulama paketi"), value: "dist/ContextHUD.app"),
            makeInfoRow(title: L10n.text("Disk image", "DMG"), value: "dist/ContextHUD.dmg"),
            makeInfoRow(title: L10n.text("Open window", "Pencereyi aç"), value: "⌘D"),
            makeInfoRow(title: L10n.text("Refresh", "Yenile"), value: "⌘R"),
        ])
        locations.orientation = .vertical
        locations.spacing = 10
        locations.alignment = .leading
        addSection(
            title: L10n.text("Files and shortcuts", "Dosyalar ve kısayollar"),
            subtitle: L10n.text(
                "Build artifacts live in the repository. Runtime data stays under your home directory.",
                "Build artefact'ları repo içinde kalır. Çalışma verileri home dizini altında tutulur."
            ),
            body: locations
        )
    }

    private func makeActionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates(presenter: view.window)
    }

    @objc private func openChangelog() {
        NSWorkspace.shared.open(changelogURL)
    }
}

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = NSTabViewController()
    let usageVC = UsageViewController()
    private let appearanceVC = AppearanceSettingsViewController()
    private let menubarVC = MenubarSettingsViewController()
    private let aboutVC = AboutViewController()

    init(onThemeChange: @escaping (String) -> Void) {
        super.init(window: nil)

        tabVC.tabStyle = .toolbar

        let usageItem = NSTabViewItem(viewController: usageVC)
        usageItem.label = L10n.text("Usage", "Kullanım")
        usageItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: usageItem.label)

        let appearanceItem = NSTabViewItem(viewController: appearanceVC)
        appearanceItem.label = L10n.text("Appearance", "Görünüm")
        appearanceItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: appearanceItem.label)

        let menubarItem = NSTabViewItem(viewController: menubarVC)
        menubarItem.label = L10n.text("Menubar", "Menubar")
        menubarItem.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: menubarItem.label)

        let aboutItem = NSTabViewItem(viewController: aboutVC)
        aboutItem.label = L10n.text("About", "Hakkında")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: aboutItem.label)

        [usageItem, appearanceItem, menubarItem, aboutItem].forEach(tabVC.addTabViewItem)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ContextHUD"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = tabVC
        self.window = window
        window.delegate = self

        appearanceVC.onThemeChange = onThemeChange
        menubarVC.onThemeChange = onThemeChange
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        load()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func load() {
        usageVC.reload()
    }

    func selectTab(index: Int) {
        guard index >= 0, index < tabVC.tabViewItems.count else { return }
        tabVC.selectedTabViewItemIndex = index
    }

    func capture(to path: String) {
        load()
        if let rawIndex = ProcessInfo.processInfo.environment["CONTEXTHUD_SELECT_TAB"],
           let index = Int(rawIndex) {
            selectTab(index: index)
        }
        guard let window, let targetView = window.contentView?.superview ?? window.contentView else { return }
        window.displayIfNeeded()
        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds
        guard let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        targetView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer!
    var detailWindow: DetailWindowController?
    let hud = Hud()
    var lastActive: Agent?
    var previewTheme: Theme?
    private var fsStream: FSEventStreamRef?
    private var fsDebounce: DispatchWorkItem?
    private var fsRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // No icon — title-only menubar entry to save horizontal space.

        refresh()
        if ProcessInfo.processInfo.environment["CONTEXTHUD_OPEN_WINDOW"] == "1" {
            openDetail()
        }
        if let screenshotPath = ProcessInfo.processInfo.environment["CONTEXTHUD_SCREENSHOT_PATH"] {
            openDetail()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.detailWindow?.capture(to: screenshotPath)
                NSApp.terminate(nil)
            }
        }
        if ProcessInfo.processInfo.environment["CONTEXTHUD_MENU_SCREENSHOT_PATH"] != nil {
            // External script (marketing-screenshot.sh) handles the actual capture.
            // This env var just prevents the timer so the app stays responsive.
        }

        timer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)

        startAgentDirWatcher()
    }

    /// Watches the agent transcript directories so the menubar reflects the
    /// active project the moment the user starts typing in a different repo.
    /// FSEvents is recursive and debounced so a burst of writes only triggers
    /// one regenerate.
    private func startAgentDirWatcher() {
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            delegate.fsEventFired()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if FSEventStreamStart(stream) {
            fsStream = stream
            fsRunning = true
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func fsEventFired() {
        fsDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.regenerateThenRefresh()
        }
        fsDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @objc func tick() { regenerateThenRefresh() }
    @objc func refreshNow() { regenerateThenRefresh() }

    /// Spawns the bundled engine to rewrite ~/.context-hud/hud.json, then reloads
    /// the menu. Engine runs off the main thread so the menubar stays responsive;
    /// UI update is dispatched back to main. If the engine binary is missing
    /// (e.g. running the Swift app standalone in dev), we still refresh from the
    /// existing JSON so behavior degrades gracefully to the previous mode.
    func regenerateThenRefresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runEngine()
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func runEngine() {
        let bundleExe = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/context-hud-engine")
        let candidates: [URL] = [
            bundleExe,
            URL(fileURLWithPath: "/usr/local/bin/context-hud"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/.cargo/bin/context-hud"),
        ]
        guard let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            return
        }
        let pyURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/usage_signal.py")
        let task = Process()
        task.executableURL = exe
        task.arguments = ["global"]
        var env = ProcessInfo.processInfo.environment
        if FileManager.default.fileExists(atPath: pyURL.path) {
            env["CONTEXTHUD_USAGE_SCRIPT"] = pyURL.path
        }
        task.environment = env
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Engine missing or failed — refresh() will fall back to existing JSON.
        }
    }

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

        // Limits — rolling 5h/7d usage windows for subscription-based agents.
        // Only shown for agents that have actual percent data (Claude Pro/Max).
        // Codex uses OpenAI token billing with no rolling message limits.
        let limitAgents = all.filter { $0.session5hPercent != nil || $0.week7dPercent != nil }
        if !limitAgents.isEmpty {
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
            for a in limitAgents {
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
                font: NSFont.menuFont(ofSize: 0),
                renderAgentAsIcon: false
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
            title: L10n.text("Quit ContextHUD", "ContextHUD'dan çık"),
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
        font: NSFont,
        renderAgentAsIcon: Bool = true
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
                if renderAgentAsIcon {
                    s.append(agentInlineString(name: agent, font: font, fallbackColor: theme.agentColor))
                } else {
                    s.append(NSAttributedString(string: agent, attributes: agentAttrs))
                }
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

        let font = NSFont.menuFont(ofSize: 0)
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(
            string: "\(dot) ",
            attributes: [.font: font, .foregroundColor: theme.agentColor]
        ))
        attr.append(agentInlineString(name: a.name, font: font, fallbackColor: theme.agentColor))
        attr.append(NSAttributedString(
            string: sep,
            attributes: [.font: font, .foregroundColor: theme.separatorColor]
        ))
        attr.append(NSAttributedString(
            string: a.project,
            attributes: [.font: font, .foregroundColor: theme.projectColor]
        ))
        attr.append(NSAttributedString(
            string: sep,
            attributes: [.font: font, .foregroundColor: theme.separatorColor]
        ))
        attr.append(NSAttributedString(
            string: pctStr,
            attributes: [.font: font, .foregroundColor: theme.ctxColor(a.ctxPct)]
        ))
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
        let nameFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 0.5)
        let nameAttr = NSMutableAttributedString(
            string: "      ",
            attributes: [
                .font: nameFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        nameAttr.append(agentInlineString(name: a.name, font: nameFont, fallbackColor: NSColor.secondaryLabelColor))
        nameItem.attributedTitle = nameAttr
        menu.addItem(nameItem)

        for (label, percent, resetsAt) in [
            ("5h", a.session5hPercent, a.session5hResetsAt),
            ("7d", a.week7dPercent, a.week7dResetsAt),
        ] {
            let view = LimitRowView(
                label: label,
                percent: percent,
                reset: Hud.resetsIn(resetsAt)
            )
            view.frame = NSRect(x: 0, y: 0, width: 320, height: 38)
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
        let font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let attr = NSMutableAttributedString()
        attr.append(agentInlineString(name: tool.name, font: font, fallbackColor: NSColor.secondaryLabelColor))
        attr.append(NSAttributedString(
            string: " \(line)",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        item.attributedTitle = attr
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

    private func captureMenu(to path: String) {
        // NSMenu popup is a system-managed CGWindow, not an NSWindow.
        // Use CGWindowList to find the largest visible window owned by this process.
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { NSApp.terminate(nil); return }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var bestID: CGWindowID = kCGNullWindowID
        var bestArea: Double = 0

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == myPID,
                  let widInt = info[kCGWindowNumber as String] as? Int,
                  let boundsAny = info[kCGWindowBounds as String] as? [String: Any],
                  let w = boundsAny["Width"] as? Double,
                  let h = boundsAny["Height"] as? Double,
                  w > 150, h > 100
            else { continue }
            let area = w * h
            if area > bestArea { bestArea = area; bestID = CGWindowID(widInt) }
        }

        guard bestID != kCGNullWindowID else { NSApp.terminate(nil); return }

        // screencapture CLI has system-level screen recording access.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(bestID), path]
        try? task.run()
        task.waitUntilExit()
        NSApp.terminate(nil)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
