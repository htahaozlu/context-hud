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
import WebKit

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

/// What to render in the menubar title and in what order.
enum DisplayElement: String, CaseIterable {
    case agent, project, pct
    var label: String {
        switch self {
        case .agent: return "Agent name"
        case .project: return "Project (cwd)"
        case .pct: return "Context %"
        }
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
    let week7d: UInt64
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
    init() {
        self.path = "\(NSHomeDirectory())/.zed-context/hud.json"
    }

    func load() -> (active: Agent?, all: [Agent], others: [ToolSummary]) {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, [], [])
        }

        let claude = parse(root["claude"] as? [String: Any], name: "Claude")
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

    private func parse(_ raw: [String: Any]?, name: String) -> Agent? {
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

        return Agent(
            name: name,
            session5h: (raw["session_5h_tokens"] as? UInt64) ?? UInt64(raw["session_5h_tokens"] as? Int ?? 0),
            week7d: (raw["week_7d_tokens"] as? UInt64) ?? UInt64(raw["week_7d_tokens"] as? Int ?? 0),
            activeSession: (raw["active_session_tokens"] as? UInt64) ?? UInt64(raw["active_session_tokens"] as? Int ?? 0),
            model: raw["last_model"] as? String,
            cwd: raw["last_cwd"] as? String,
            ctxPct: raw["last_context_pct"] as? Double,
            ctxWindow: (raw["last_context_window"] as? UInt64) ?? (raw["last_context_window"] as? Int).map(UInt64.init),
            lastTurn: ts,
            sessionStarted: started,
            activeSessions: actives,
            session5hResetsAt: parseDate(raw["session_5h_resets_at"] as? String),
            week7dResetsAt: parseDate(raw["week_7d_resets_at"] as? String)
        )
    }

    static func resetsIn(_ date: Date?) -> String {
        guard let date else { return "—" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "ready" }
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

    static func relative(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed/60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed/3600))h ago" }
        return "\(Int(elapsed/86400))d ago"
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

/// In-process detail window — WKWebView loading ~/.zed-context/detail.html.
/// We render the report inside our own app so the user never bounces to a
/// browser; the window is created lazily and reused across opens.
final class UsageViewController: NSViewController {
    private var webView: WKWebView!

    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view = webView
    }

    func reload() {
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/.zed-context/detail.html")
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
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
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let descLabel = NSTextField(labelWithString: "Choose a color theme for the menubar and status bar.")
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor

        // Separator section
        let sepTitle = NSTextField(labelWithString: "Separator")
        sepTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let sepDesc = NSTextField(labelWithString: "Character shown between agent name, project, and context %.")
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
        let dispTitle = NSTextField(labelWithString: "Menubar Title")
        dispTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let dispDesc = NSTextField(labelWithString: "Toggle and drag to reorder which parts appear in the menubar title.")
        dispDesc.font = NSFont.systemFont(ofSize: 11)
        dispDesc.textColor = .secondaryLabelColor
        displayTable.onChange = { [weak self] in self?.onThemeChange?(ThemeStore.current.id) }

        let mainStack = NSStackView(views: [
            titleLabel, descLabel, themeGrid,
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
}

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = NSTabViewController()
    let usageVC = UsageViewController()
    private let settingsVC: SettingsViewController

    init(onThemeChange: @escaping (String) -> Void) {
        self.settingsVC = SettingsViewController()
        let usageItem = NSTabViewItem(viewController: usageVC)
        usageItem.label = "Usage"
        let settingsItem = NSTabViewItem(viewController: settingsVC)
        settingsItem.label = "Settings"
        tabVC.tabStyle = .segmentedControlOnTop
        tabVC.addTabViewItem(usageItem)
        tabVC.addTabViewItem(settingsItem)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "zed-context · usage"
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
    func load() { usageVC.reload() }
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
            let empty = NSMenuItem(title: "No agent data yet", action: nil, keyEquivalent: "")
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
                string: "LIMITS",
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
            let header = NSMenuItem(title: "Other Tools", action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(
                string: "OTHER TOOLS",
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
        let themeRoot = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
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
            title: "Open detail report…",
            action: #selector(openDetail),
            keyEquivalent: "d"
        ))
        menu.addItem(NSMenuItem(
            title: "Refresh now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit zed-context-bar",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    /// Builds the compact menubar title using the active theme:
    ///     <Agent> <sep> <project> <sep> <ctx%>
    private func composeTitle(active: Agent?, theme: Theme = ThemeStore.current) -> NSAttributedString {
        guard let a = active else {
            return NSAttributedString(string: " no agent",
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

        let last = a.lastTurn.map { Hud.relative($0) } ?? "—"
        let modelStr = a.model ?? "—"
        let duration = Hud.formatDuration(a.sessionStarted, a.lastTurn)
        let detailSep = SeparatorStore.current.isEmpty ? "·" : SeparatorStore.current
        let detail = "      \(modelStr)  \(detailSep)  session \(duration)  \(detailSep)  \(last)"
        let detailItem = NSMenuItem()
        detailItem.isEnabled = false
        detailItem.attributedTitle = NSAttributedString(
            string: detail,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(detailItem)

        // If more than one session is live concurrently for this agent, render
        // a row per session so 3-5 parallel sessions stay visible. Skip the
        // top one (already represented by the header line above).
        if a.activeSessions.count > 1 {
            let topId = a.activeSessions.first?.id
            for sess in a.activeSessions where sess.id != topId {
                let tok = Hud.formatTokens(sess.tokens)
                let when = sess.lastTurn.map { Hud.relative($0) } ?? "—"
                let proj = sess.project
                let model = sess.model ?? "—"
                let line = "      \(theme.inactiveDot) \(proj)  \(detailSep)  \(tok)  \(detailSep)  \(model)  \(detailSep)  \(when)"
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
        let sep = SeparatorStore.current.isEmpty ? "·" : SeparatorStore.current
        let fiveH = Hud.formatTokens(a.session5h)
        let weekly = Hud.formatTokens(a.week7d)
        let fiveReset = Hud.resetsIn(a.session5hResetsAt)
        let weekReset = Hud.resetsIn(a.week7dResetsAt)
        let line = "      \(a.name)   5h \(fiveH) (resets \(fiveReset))  \(sep)  7d \(weekly) (resets \(weekReset))"
        let item = NSMenuItem()
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: line,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(item)
    }

    private func appendTool(menu: NSMenu, tool: ToolSummary) {
        let item = NSMenuItem()
        item.isEnabled = false
        let tok = tool.tokens7d > 0 ? "  \(Hud.formatTokens(tool.tokens7d))" : ""
        let sess = tool.sessions7d > 0 ? "  \(tool.sessions7d)×/wk" : ""
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
            detailWindow = DetailWindowController(onThemeChange: { [weak self] _ in self?.refresh() })
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
