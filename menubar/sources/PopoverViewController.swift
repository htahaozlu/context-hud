import AppKit
import Foundation

final class MenubarPopoverViewController: NSViewController, NSMenuDelegate {
    static let contentWidth: CGFloat = 360
    private let hPad: CGFloat = 14
    private let vGap: CGFloat = 10

    var onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onPickTheme: ((String) -> Void)?
    /// Called while the user hovers theme menu items. Passes the hovered
    /// theme id (or nil to clear the preview). The host (AppDelegate) uses
    /// this to repaint the menubar title in the theme's colors live, without
    /// persisting the choice until the menu item is actually selected.
    var onPreviewTheme: ((String?) -> Void)?

    private let visualEffect = NSVisualEffectView()
    private let contentStack = NSStackView()

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true

        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(visualEffect)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: root.topAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])
        view = root
    }

    func rebuild() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let hud = Hud()
        let (active, all, others) = hud.load()
        let primary = active ?? all.first

        if let agent = primary {
            addCard(buildHero(agent: agent, isActive: agent.name == active?.name))
            if let pct = agent.ctxPct {
                addCard(buildContextMeter(agent: agent, pct: pct))
            }
            addCard(buildStatRow(agent: agent))
            if agent.activeSessions.count > 1 {
                addCard(buildConcurrentSessions(agent: agent))
            }
        } else {
            addCard(buildEmptyState())
        }
        if !others.isEmpty {
            addCard(buildOthers(tools: others))
        }
        addCard(buildFooter())

        view.layoutSubtreeIfNeeded()
        let fit = view.fittingSize
        preferredContentSize = NSSize(
            width: Self.contentWidth,
            height: max(fit.height, 1)
        )
    }

    /// Adds a section view to the popover stack and pins both leading and
    /// trailing edges to the stack — without this, NSStackView's `.leading`
    /// alignment only pins one edge and views with narrow intrinsic content
    /// (e.g. a card with a single short row) shrink instead of filling the
    /// full popover width.
    private func addCard(_ v: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.required, for: .vertical)
        v.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.addArrangedSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -10),
        ])
    }

    // MARK: - Sections

    /// Returns a (card, contentStack) pair. The content stack is constrained
    /// inside the card with consistent 14h/12v padding. Callers add content to
    /// the stack and the card auto-sizes its height while filling the popover
    /// width via the parent contentStack's `.width` alignment.
    private func sectionContainer() -> (NSView, NSStackView) {
        let card = MenubarCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return (card, stack)
    }

    private func buildEmptyState() -> NSView {
        let (container, stack) = sectionContainer()
        let title = NSTextField(labelWithString: L10n.text("No agent data yet", "Henüz ajan verisi yok"))
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        let sub = NSTextField(wrappingLabelWithString: L10n.text(
            "Start a Claude or Codex session to see context and limits here.",
            "Bağlam ve limitleri görmek için Claude veya Codex oturumu başlatın."
        ))
        sub.font = NSFont.systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.maximumNumberOfLines = 0
        sub.preferredMaxLayoutWidth = Self.contentWidth - 2 * hPad
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    private func buildHero(agent a: Agent, isActive: Bool) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 2

        let dot = ActivityDotView()
        dot.isActive = isActive

        let nameLbl = agentInlineLabel(
            name: a.name,
            font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            color: .labelColor,
            iconScale: 1.3
        )
        nameLbl.toolTip = a.name

        let titleRow = NSStackView(views: [dot, nameLbl])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        // Order: project first (the user's primary signal), then model, then
        // "Xs ago", then duration. Tail truncation drops the least-important
        // suffix (duration / time) before the project.
        var metaParts: [String] = []
        metaParts.append(a.project)
        if let m = a.model { metaParts.append(m) }
        if let t = a.lastTurn { metaParts.append(Hud.relative(t)) }
        let duration = Hud.formatDuration(a.sessionStarted, a.lastTurn)
        if duration != "—" {
            metaParts.append(L10n.text("\(duration) running", "\(duration)"))
        }
        let meta = NSTextField(labelWithString: metaParts.joined(separator: "  ·  "))
        meta.font = NSFont.systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.maximumNumberOfLines = 1
        meta.cell?.usesSingleLineMode = true
        meta.toolTip = metaParts.joined(separator: "  ·  ")
        nameLbl.maximumNumberOfLines = 1
        nameLbl.cell?.usesSingleLineMode = true

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(meta)
        return container
    }

    private func buildContextMeter(agent a: Agent, pct: Double) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 6

        let label = NSTextField(labelWithString: L10n.text("Context", "Bağlam"))
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor

        let pctStr = String(format: "%.0f%%", pct)
        let pctLbl = NSTextField(labelWithString: pctStr)
        pctLbl.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        pctLbl.textColor = Hud.ctxColor(pct)

        let used = a.activeSession
        let detailText = a.ctxWindow.map { w in
            "\(Hud.formatTokens(used)) / \(Hud.formatTokens(w))"
        } ?? Hud.formatTokens(used)
        let detail = NSTextField(labelWithString: detailText)
        detail.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .tertiaryLabelColor
        detail.alignment = .right

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let headerRow = NSStackView(views: [label, spacer, pctLbl, detail])
        headerRow.orientation = .horizontal
        headerRow.alignment = .firstBaseline
        headerRow.distribution = .fill
        headerRow.spacing = 6

        let bar = ProgressBarView()
        bar.value = max(0, min(1, pct / 100.0))
        bar.tint = Hud.ctxColor(pct)
        bar.corner = 2.5
        bar.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(bar)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 5).isActive = true
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    private func buildStatRow(agent a: Agent) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 10

        var rows: [NSView] = []
        if a.session5hPercent != nil || a.session5h > 0 {
            rows.append(makeLimitRow(
                label: L10n.text("5h limit", "5sa limit"),
                percent: a.session5hPercent,
                fallbackValue: Hud.formatTokens(a.session5h),
                resetsAt: a.session5hResetsAt
            ))
        }
        if a.week7dPercent != nil || a.week7d > 0 {
            rows.append(makeLimitRow(
                label: L10n.text("7d limit", "7g limit"),
                percent: a.week7dPercent,
                fallbackValue: Hud.formatTokens(a.week7d),
                resetsAt: a.week7dResetsAt
            ))
        }
        rows.append(makeSimpleStatRow(
            label: L10n.text("Session total", "Oturum toplam"),
            value: Hud.formatTokens(a.activeSession),
            valueColor: .secondaryLabelColor
        ))

        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    /// Limit row with inline progress bar: label + percent + reset on top line,
    /// full-width bar below. Bar color tracks the usage threshold.
    private func makeLimitRow(label: String, percent: Double?, fallbackValue: String, resetsAt: Date?) -> NSView {
        let color = usageColor(percent)
        let valueText = percent.map { String(format: "%.0f%%", $0) } ?? fallbackValue

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.textColor = .labelColor

        let val = NSTextField(labelWithString: valueText)
        val.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        val.textColor = color

        let resetLbl: NSTextField? = resetsAt.map { _ in
            let l = NSTextField(labelWithString: "↻ \(Hud.resetsIn(resetsAt))")
            l.font = NSFont.systemFont(ofSize: 10)
            l.textColor = .tertiaryLabelColor
            return l
        }

        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.alignment = .firstBaseline
        rightStack.spacing = 8
        rightStack.addArrangedSubview(val)
        if let r = resetLbl { rightStack.addArrangedSubview(r) }

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let header = NSStackView(views: [lbl, spacer, rightStack])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.distribution = .fill
        header.spacing = 6

        let bar = ProgressBarView()
        bar.value = max(0, min(1, (percent ?? 0) / 100.0))
        bar.tint = color
        bar.corner = 2
        bar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return stack
    }

    /// Simple key/value row without a bar — used for stats that aren't a
    /// proportion of a known budget (e.g. raw session token counter).
    private func makeSimpleStatRow(label: String, value: String, valueColor: NSColor) -> NSView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.textColor = .labelColor

        let val = NSTextField(labelWithString: value)
        val.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        val.textColor = valueColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [lbl, spacer, val])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func buildConcurrentSessions(agent a: Agent) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 4

        let header = NSTextField(labelWithString: L10n.text("Parallel sessions", "Paralel oturumlar"))
        header.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)

        let topId = a.activeSessions.first?.id
        for sess in a.activeSessions where sess.id != topId {
            let proj = NSTextField(labelWithString: sess.project)
            proj.font = NSFont.systemFont(ofSize: 12)
            proj.textColor = .labelColor
            proj.lineBreakMode = .byTruncatingMiddle

            let pctStr = sess.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
            let pct = NSTextField(labelWithString: pctStr)
            pct.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            pct.textColor = Hud.ctxColor(sess.ctxPct)

            let when = sess.lastTurn.map { Hud.relative($0) } ?? "—"
            let whenLbl = NSTextField(labelWithString: when)
            whenLbl.font = NSFont.systemFont(ofSize: 10)
            whenLbl.textColor = .tertiaryLabelColor

            let right = NSStackView(views: [pct, whenLbl])
            right.orientation = .horizontal
            right.alignment = .firstBaseline
            right.spacing = 8

            let sp = NSView()
            sp.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            let r = NSStackView(views: [proj, sp, right])
            r.orientation = .horizontal
            r.alignment = .firstBaseline
            r.distribution = .fill
            r.spacing = 6
            stack.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    private func buildOthers(tools: [ToolSummary]) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 4

        let header = NSTextField(labelWithString: L10n.text("Other tools", "Diğer araçlar"))
        header.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)

        for tool in tools {
            let r = OtherToolRowView(tool: tool)
            stack.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    private func buildFooter() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let themeBtn = makeThemeButton()
        themeBtn.translatesAutoresizingMaskIntoConstraints = false

        let settingsBtn = FooterIconButton(
            symbol: "slider.horizontal.3",
            tooltip: L10n.text("Settings", "Ayarlar"),
            target: self,
            action: #selector(handleSettings)
        )
        let refreshBtn = FooterIconButton(
            symbol: "arrow.clockwise",
            tooltip: L10n.text("Refresh", "Yenile"),
            target: self,
            action: #selector(handleRefresh)
        )
        let quitBtn = FooterIconButton(
            symbol: "power",
            tooltip: L10n.text("Quit", "Çık"),
            target: self,
            action: #selector(handleQuit)
        )

        let rightStack = NSStackView(views: [settingsBtn, refreshBtn, quitBtn])
        rightStack.orientation = .horizontal
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(themeBtn)
        container.addSubview(rightStack)

        NSLayoutConstraint.activate([
            themeBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            themeBtn.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            themeBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            themeBtn.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -14),
            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            rightStack.centerYAnchor.constraint(equalTo: themeBtn.centerYAnchor),
        ])
        return container
    }

    private func makeThemeButton() -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.bezelStyle = .rounded
        popup.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.target = self
        popup.action = #selector(handleThemePopupChange(_:))

        let currentId = ThemeStore.current.id
        for theme in Theme.all {
            let item = NSMenuItem(title: theme.name, action: nil, keyEquivalent: "")
            item.representedObject = theme.id
            item.attributedTitle = themeSwatchTitle(theme: theme)
            popup.menu?.addItem(item)
        }
        if let idx = Theme.all.firstIndex(where: { $0.id == currentId }) {
            popup.selectItem(at: idx)
        }
        popup.menu?.delegate = self

        let prefix = NSTextField(labelWithString: L10n.text("Theme", "Tema"))
        prefix.font = NSFont.systemFont(ofSize: 11)
        prefix.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [prefix, popup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    @objc private func handleThemePopupChange(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        onPickTheme?(id)
    }

    // MARK: NSMenuDelegate — live theme preview while hovering items.

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let id = item?.representedObject as? String,
           Theme.all.contains(where: { $0.id == id }) {
            onPreviewTheme?(id)
        } else {
            onPreviewTheme?(nil)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        onPreviewTheme?(nil)
    }

    /// Builds a "● ● ●  Theme name" attributed string where the bullets are
    /// rendered in the theme's agent / project / accent colors. Lets the user
    /// see each theme's palette inline without reading a label.
    private func themeSwatchTitle(theme: Theme, compact: Bool = false) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let result = NSMutableAttributedString()
        let swatchAttrs: (NSColor) -> [NSAttributedString.Key: Any] = { color in
            [.font: font, .foregroundColor: color]
        }
        result.append(NSAttributedString(string: "● ", attributes: swatchAttrs(theme.agentColor)))
        result.append(NSAttributedString(string: "● ", attributes: swatchAttrs(theme.projectColor)))
        result.append(NSAttributedString(string: "● ", attributes: swatchAttrs(theme.pctMid)))
        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
        result.append(NSAttributedString(
            string: theme.name,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        ))
        if !compact {
            // Trailing example token ("42%") in the theme's percent color so
            // the user sees how the numeric values will render.
            result.append(NSAttributedString(
                string: "   42%",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                    .foregroundColor: theme.pctMid,
                ]
            ))
        }
        return result
    }

    private func usageColor(_ pct: Double?) -> NSColor {
        guard let pct else { return .labelColor }
        if pct >= 90 { return .systemRed }
        if pct >= 70 { return .systemOrange }
        return .systemGreen
    }

    // MARK: Actions

    @objc private func handleSettings() { onOpenSettings?() }
    @objc private func handleRefresh() { onRefresh?() }
    @objc private func handleQuit() { onQuit?() }
    @objc private func handleThemePick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onPickTheme?(id)
    }
}

