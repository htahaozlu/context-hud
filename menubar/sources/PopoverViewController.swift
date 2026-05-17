import AppKit
import Foundation

final class MenubarPopoverViewController: NSViewController, NSMenuDelegate {
    static let contentWidth: CGFloat = 360
    private let hPad: CGFloat = Spacing.m
    private let vGap: CGFloat = Spacing.s
    private var didShowOnce = false
    /// SHA-ish fingerprint of the snapshot the last rebuild rendered. When the
    /// next refresh tick computes the same fingerprint we skip the teardown to
    /// stop the popover from flashing on every 10s tick.
    private var lastSnapshotKey: String?

    var onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShare: ((NSView) -> Void)?
    var onPickTheme: ((String) -> Void)?
    /// Called while the user hovers theme menu items. Passes the hovered
    /// theme id (or nil to clear the preview). The host (AppDelegate) uses
    /// this to repaint the menubar title in the theme's colors live, without
    /// persisting the choice until the menu item is actually selected.
    var onPreviewTheme: ((String?) -> Void)?

    private let visualEffect = NSVisualEffectView()
    private let contentStack = NSStackView()

    /// Held weakly so the button — which lives on a stack rebuilt every show —
    /// can be told to spin while a manual refresh is in flight without taking
    /// ownership of view lifetime.
    private weak var refreshBtn: FooterIconButton?
    /// Last manual-refresh click; debounces double-clicks so we don't queue
    /// duplicate engine runs when a user hammers the button.
    private var lastRefreshClickAt: Date?

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
        contentStack.spacing = Spacing.s
        // All four edges equalized — top/bottom carry the full Spacing.m and
        // leading/trailing get the remainder via `addCard()` so every visible
        // gap around the cards is 16pt. Previously top/bottom were 16 while
        // L/R were only 12, which read as a top/right whitespace bias.
        // Footer view brings its own vertical pad — match that here so the
        // gap above/below the footer reads symmetric with the side insets.
        contentStack.edgeInsets = NSEdgeInsets(top: Spacing.m, left: 0, bottom: Spacing.xs, right: 0)
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
        let hud = Hud()
        let (active, all, others) = hud.load()
        let primary = active ?? all.first
        let key = snapshotKey(active: active, primary: primary, all: all, others: others)
        // Engine returned — stop the manual-refresh spinner whether or not the
        // snapshot key actually changed. If the footer gets rebuilt below the
        // call is a no-op against the new button.
        refreshBtn?.setSpinning(false)
        // Bail early when nothing the popover renders has changed — this is
        // the cheapest fix for the 10s tick flicker (no teardown, no relayout).
        if key == lastSnapshotKey, !contentStack.arrangedSubviews.isEmpty {
            return
        }
        lastSnapshotKey = key

        // Suppress implicit CAAnimations so the rebuild swap doesn't crossfade
        // sublayers — that was the source of the visible flash when the active
        // sessions array changed shape between ticks.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let agent = primary {
            // Card order: hero (active session) → parallel sessions →
            // per-agent limits (primary first, then any others) → other tools.
            addCard(buildHero(agent: agent, isActive: agent.name == active?.name))
            if hasParallelSessions(agent: agent) {
                addCard(buildParallelSessions(agent: agent))
            }
            // Primary agent's limits first, then any other agents with data.
            let orderedAgents = [agent] + all.filter { $0.name != agent.name }
            for ag in orderedAgents where hasSecondaryData(ag) {
                addCard(buildAgentLimits(ag))
            }
        } else {
            // Before the engine has produced a hud.json (first launch / cache
            // miss after purge) show the loading stripe instead of the
            // "no agent" empty state — the latter falsely implies the user has
            // nothing running.
            let hudExists = FileManager.default.fileExists(atPath: hud.path)
            if hudExists {
                addCard(buildEmptyState())
            } else {
                addCard(buildLoadingState())
            }
        }
        if !others.isEmpty {
            addCard(buildOthers(tools: others))
        }
        addCard(buildFooter())

        view.layoutSubtreeIfNeeded()
        CATransaction.commit()
        let fit = view.fittingSize
        preferredContentSize = NSSize(
            width: Self.contentWidth,
            height: max(fit.height, 1)
        )

        // First-show fade-in. Subsequent rebuilds skip this so the panel
        // doesn't flicker on data refresh.
        if !didShowOnce, !MotionPrefs.reduceMotion {
            didShowOnce = true
            let t = CATransition()
            t.type = .fade
            t.duration = 0.20
            contentStack.layer?.add(t, forKey: "fadeIn")
        }
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
            v.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: Spacing.m),
            v.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -Spacing.m),
        ])
    }

    // MARK: - Sections

    /// Returns a (card, contentStack) pair. The content stack is constrained
    /// inside the card with consistent 14h/12v padding. Callers add content to
    /// the stack and the card auto-sizes its height while filling the popover
    /// width via the parent contentStack's `.width` alignment.
    private func sectionContainer(hero: Bool = false) -> (NSView, NSStackView) {
        let card: NSView = hero ? MenubarHeroCardView() : MenubarCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        let pad: CGFloat = hero ? Spacing.m : Spacing.s
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: pad),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -pad),
        ])
        return (card, stack)
    }

    private func buildLoadingState() -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.alignment = .leading
        stack.spacing = Spacing.s

        let title = NSTextField(labelWithString: L10n.text("Gathering session data…", "Oturum verileri toplanıyor…"))
        title.font = Typography.title(14)
        title.textColor = .labelColor

        let sub = NSTextField(wrappingLabelWithString: L10n.text(
            "Scanning Claude and Codex transcripts. This usually takes a second.",
            "Claude ve Codex transcript'leri taranıyor. Genellikle bir saniye sürer."
        ))
        sub.font = Typography.body(11)
        sub.textColor = .secondaryLabelColor
        sub.maximumNumberOfLines = 0
        sub.preferredMaxLayoutWidth = Self.contentWidth - 2 * hPad

        let stripe = LoadingStripeView()
        stripe.tint = ThemeStore.current.accent
        stripe.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        stack.addArrangedSubview(stripe)
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stripe.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stripe.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return container
    }

    private func buildEmptyState() -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.alignment = .centerX
        stack.spacing = Spacing.s

        let cfg = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iv.contentTintColor = .tertiaryLabelColor
        iv.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L10n.text("No agent data yet", "Henüz ajan verisi yok"))
        title.font = Typography.title(14)
        title.textColor = .labelColor
        title.alignment = .center

        let sub = NSTextField(wrappingLabelWithString: L10n.text(
            "Start a Claude or Codex session to see context and limits here.",
            "Bağlam ve limitleri görmek için Claude veya Codex oturumu başlatın."
        ))
        sub.font = Typography.body(11)
        sub.textColor = .secondaryLabelColor
        sub.alignment = .center
        sub.maximumNumberOfLines = 0
        sub.preferredMaxLayoutWidth = Self.contentWidth - 2 * hPad

        stack.addArrangedSubview(iv)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    private func buildHero(agent a: Agent, isActive: Bool) -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.spacing = Spacing.s

        // Inline "●" glyph as the activity indicator — drawing the dot as a
        // text character in the same attributed string as the project name
        // guarantees baseline alignment regardless of font metrics. No more
        // Auto Layout / cap-height / x-height math.
        let projectFont = Typography.display(22, weight: .semibold)
        let dotColor: NSColor = isActive ? .systemGreen : .tertiaryLabelColor
        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: "●  ", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: dotColor,
            .baselineOffset: 3,
        ]))
        title.append(NSAttributedString(string: a.project, attributes: [
            .font: projectFont,
            .foregroundColor: Palette.primaryText,
            .kern: -0.3,
        ]))
        let projectLbl = NSTextField(labelWithAttributedString: title)
        projectLbl.lineBreakMode = .byTruncatingTail
        projectLbl.maximumNumberOfLines = 1
        projectLbl.cell?.usesSingleLineMode = true
        projectLbl.toolTip = a.project
        projectLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // (dot is inline in projectLbl — no wrapper container needed)

        let pct = a.ctxPct
        let pctStr = pct.map { String(format: "%.0f%%", $0) } ?? "—"
        let pctColor: NSColor = pct.map { Hud.ctxColor($0) } ?? .tertiaryLabelColor
        // Use the IDENTICAL font as projectLbl — same family, weight, AND
        // size. `monospacedDigitSystemFont` has different cap/x-height
        // metrics than systemFont so even at 22pt vs 22pt the baseline /
        // cap-mid won't match. Same font end-to-end is the only reliable
        // way to get the title and pct visually centered on the same line.
        let pctLbl = NSTextField(labelWithAttributedString: NSAttributedString(
            string: pctStr,
            attributes: [
                .font: projectFont,
                .foregroundColor: pctColor,
                .kern: -0.3,
            ]
        ))
        pctLbl.setContentHuggingPriority(.required, for: .horizontal)

        // Same-size baseline align — project and pct share font metrics so
        // .firstBaseline is also cap-mid is also centerY.
        let topRow = NSStackView(views: [projectLbl, pctLbl])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.distribution = .fill
        topRow.spacing = Spacing.s

        // Meta row: brand icon + agent name + model + time + duration
        let brandView = NSImageView()
        if let url = agentIconURL(name: a.name), let img = NSImage(contentsOf: url) {
            brandView.image = img
        }
        brandView.imageScaling = .scaleProportionallyUpOrDown
        brandView.translatesAutoresizingMaskIntoConstraints = false
        brandView.toolTip = AgentVisual.forName(a.name).accessibilityLabel
        NSLayoutConstraint.activate([
            brandView.widthAnchor.constraint(equalToConstant: 14),
            brandView.heightAnchor.constraint(equalToConstant: 14),
        ])

        var metaParts: [String] = []
        metaParts.append(a.name)
        if let m = a.model { metaParts.append(m) }
        if let t = a.lastTurn { metaParts.append(Hud.relative(t)) }
        let duration = Hud.formatDuration(a.sessionStarted, a.lastTurn)
        if duration != "—" {
            metaParts.append(L10n.text("\(duration) running", "\(duration) aktif"))
        }
        let metaText = metaParts.joined(separator: "  ·  ")
        let meta = NSTextField(labelWithString: metaText)
        meta.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        meta.textColor = .tertiaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.maximumNumberOfLines = 1
        meta.cell?.usesSingleLineMode = true
        meta.toolTip = metaText

        let metaRow = NSStackView(views: [brandView, meta])
        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        metaRow.spacing = Spacing.xs

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(metaRow)
        topRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        metaRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Context meter (capsule, 4pt). Always show — provides hero rhythm
        // and keeps card height stable when pct/window unknown.
        let bar = ProgressBarView()
        bar.value = pct.map { max(0, min(1, $0 / 100.0)) } ?? 0
        bar.tint = ThemeStore.current.accent
        bar.gradientEnd = ThemeStore.current.pctMid
        bar.corner = 2
        bar.glow = (pct ?? 0) > 75
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setAccessibilityLabel(L10n.text("Context usage", "Bağlam kullanımı"))

        let used = a.activeSession
        let detailText: String
        if let w = a.ctxWindow {
            detailText = "\(Hud.formatTokens(used)) / \(Hud.formatTokens(w))"
        } else if used > 0 {
            detailText = "\(Hud.formatTokens(used)) " + L10n.text("session", "oturum")
        } else {
            detailText = L10n.text("context unknown", "bağlam bilinmiyor")
        }
        let detail = NSTextField(labelWithString: detailText)
        detail.font = Typography.bodyMono(11, weight: .regular)
        detail.textColor = .tertiaryLabelColor

        stack.addArrangedSubview(bar)
        stack.addArrangedSubview(detail)
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true

        // Burn-rate forecast line — only shown when the prefs flag is on and
        // the extrapolation cleared the confidence gate inside Hud.burnRate.
        if DisplayPrefs.burnRate, (pct ?? 0) > 40,
           let burn = Hud.burnRate(a) {
            let eta = Hud.burnRateText(burn.etaSeconds)
            let resetTxt: String? = {
                if let r = a.session5hResetsAt { return Hud.resetsText(r) }
                return nil
            }()
            var parts: [String] = ["↗ " + L10n.text("on pace to fill in", "doluş süresi") + " \(eta)"]
            if let r = resetTxt {
                parts.append(L10n.text("window resets in \(r)", "pencere \(r) sonra"))
            }
            let forecast = NSTextField(labelWithString: parts.joined(separator: "  ·  "))
            forecast.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            forecast.textColor = .tertiaryLabelColor
            forecast.lineBreakMode = .byTruncatingTail
            forecast.maximumNumberOfLines = 1
            stack.addArrangedSubview(forecast)
            forecast.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // Incident strip — visible only when IncidentPoller surfaces an
        // active upstream incident. Click opens the status page.
        let incident = IncidentBadgeView()
        incident.state = IncidentPoller.shared.current
        if !incident.isHidden {
            stack.addArrangedSubview(incident)
            incident.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // Celebration trigger — once per window rollover.
        if DisplayPrefs.confetti,
           Celebration.consumeReset(a.session5hResetsAt, key: "\(a.name).\(Celebration.session5hKey())") ||
            Celebration.consumeReset(a.week7dResetsAt, key: "\(a.name).\(Celebration.week7dKey())") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak container] in
                guard let container else { return }
                Celebration.burst(in: container)
            }
        }
        return container
    }

    @available(*, deprecated)
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

    private func hasSecondaryData(_ a: Agent) -> Bool {
        if a.session5h > 0 || a.session5hPercent != nil { return true }
        if a.week7d > 0 || a.week7dPercent != nil { return true }
        if a.activeSession > 0 { return true }
        return false
    }

    /// Limits card for one agent — header strip with brand icon + agent
    /// name + last-turn metadata, followed by 5h / 7d / session rows. Used
    /// for both the foreground and any other agents so every limits card has
    /// the same visual treatment.
    private func buildAgentLimits(_ a: Agent) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = Spacing.xs

        let brand = NSImageView()
        if let url = agentIconURL(name: a.name), let img = NSImage(contentsOf: url) {
            brand.image = img
        }
        brand.imageScaling = .scaleProportionallyUpOrDown
        brand.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brand.widthAnchor.constraint(equalToConstant: 16),
            brand.heightAnchor.constraint(equalToConstant: 16),
        ])

        let nameLbl = NSTextField(labelWithString: a.name)
        nameLbl.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLbl.textColor = .labelColor

        var metaParts: [String] = []
        if let m = a.model { metaParts.append(m) }
        if let t = a.lastTurn { metaParts.append(Hud.relative(t)) }
        let meta = NSTextField(labelWithString: metaParts.joined(separator: " · "))
        meta.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        meta.textColor = .tertiaryLabelColor
        meta.lineBreakMode = .byTruncatingTail

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let header = NSStackView(views: [brand, nameLbl, spacer, meta])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = Spacing.xs

        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        var rows: [NSView] = []
        let showsRemaining = a.name.caseInsensitiveCompare("Codex") == .orderedSame
        if a.session5hPercent != nil || a.session5h > 0 {
            rows.append(makeLimitRow(
                label: L10n.text("5h limit", "5sa limit"),
                percent: a.session5hPercent,
                fallbackValue: Hud.formatTokens(a.session5h),
                resetsAt: a.session5hResetsAt,
                showsRemaining: showsRemaining
            ))
        }
        if a.week7dPercent != nil || a.week7d > 0 {
            rows.append(makeLimitRow(
                label: L10n.text("7d limit", "7g limit"),
                percent: a.week7dPercent,
                fallbackValue: Hud.formatTokens(a.week7d),
                resetsAt: a.week7dResetsAt,
                showsRemaining: showsRemaining
            ))
        }
        if a.activeSession > 0 {
            rows.append(makeSimpleStatRow(
                label: L10n.text("Session total", "Oturum toplam"),
                value: Hud.formatTokens(a.activeSession),
                valueColor: .secondaryLabelColor
            ))
        }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    /// Limit row with inline progress bar: label + percent + reset on top line,
    /// full-width bar below. Bar color tracks the usage threshold.
    private func makeLimitRow(label: String, percent: Double?, fallbackValue: String, resetsAt: Date?, showsRemaining: Bool = false) -> NSView {
        let color = usageColor(percent)
        let valueText: String = {
            guard let percent else { return fallbackValue }
            if showsRemaining {
                return Hud.formatRemainingValue(percentUsed: percent, tokens: 0)
            }
            return String(format: "%.0f%%", percent)
        }()

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.textColor = .labelColor

        let val = NSTextField(labelWithString: valueText)
        val.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        val.textColor = color

        let resetLbl: NSTextField? = resetsAt.map { _ in
            let l = NSTextField(labelWithString: "↻ \(Hud.resetsText(resetsAt))")
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
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
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

    /// "Parallel Sessions" card — one row per concurrent Claude/Codex session
    /// other than the hero (foreground) one. Each row shows the project name +
    /// model on top, a thin context-percent bar underneath, the percent text +
    /// last-turn relative time on the right. Capped at 5 rows; a "+N more"
    /// footer appears if exceeded. Caller is responsible for only invoking
    /// this when `hasParallelSessions(agent:)` returns true.
    private func parallelSessions(for a: Agent) -> [ActiveSession] {
        let foregroundCwd = a.cwd
        return a.activeSessions.filter { sess in
            if let fg = foregroundCwd, !fg.isEmpty {
                let proj = (fg as NSString).lastPathComponent
                return sess.project != proj
            }
            return sess.id != a.activeSessions.first?.id
        }
    }

    private func hasParallelSessions(agent a: Agent) -> Bool {
        !parallelSessions(for: a).isEmpty
    }

    private func buildParallelSessions(agent a: Agent) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = Spacing.xs

        let header = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(L10n.text("Parallel Sessions", "Paralel oturumlar")))
        stack.addArrangedSubview(header)

        let allOthers = parallelSessions(for: a)
        let cap = 5
        let shown = Array(allOthers.prefix(cap))
        let overflow = max(0, allOthers.count - cap)

        for sess in shown {
            stack.addArrangedSubview(makeParallelSessionRow(sess))
            stack.arrangedSubviews.last?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if overflow > 0 {
            let more = NSTextField(labelWithString: L10n.text("+ \(overflow) more", "+ \(overflow) daha"))
            more.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            more.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(more)
        }
        return container
    }

    /// Single row inside the parallel-sessions card: project · model on top
    /// row, capsule progress bar + percent + last-turn time below.
    private func makeParallelSessionRow(_ sess: ActiveSession) -> NSView {
        let proj = NSTextField(labelWithString: sess.project)
        proj.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        proj.textColor = .labelColor
        proj.lineBreakMode = .byTruncatingMiddle
        proj.cell?.usesSingleLineMode = true
        proj.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var metaParts: [String] = []
        if let m = sess.model { metaParts.append(m) }
        if let t = sess.lastTurn { metaParts.append(Hud.relative(t)) }
        let meta = NSTextField(labelWithString: metaParts.joined(separator: " · "))
        meta.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        meta.textColor = .tertiaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pctStr = sess.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
        let pctLbl = NSTextField(labelWithString: pctStr)
        pctLbl.font = Typography.bodyMono(11, weight: .semibold)
        pctLbl.textColor = Hud.ctxColor(sess.ctxPct)
        pctLbl.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let topRow = NSStackView(views: [proj, spacer, pctLbl])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.distribution = .fill
        topRow.spacing = Spacing.xs

        let bar = ProgressBarView()
        if let p = sess.ctxPct {
            bar.value = max(0, min(1, p / 100.0))
        } else {
            bar.value = 0
        }
        bar.tint = ThemeStore.current.accent
        bar.gradientEnd = ThemeStore.current.pctMid
        bar.corner = 2
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
        bar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [topRow, bar, meta])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        topRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return stack
    }

    /// Fingerprint of the data the popover actually renders. Two consecutive
    /// refreshes producing the same key skip the rebuild entirely so the
    /// popover doesn't tear down + re-add its cards on every 10s tick.
    private func snapshotKey(active: Agent?, primary: Agent?, all: [Agent], others: [ToolSummary]) -> String {
        var parts: [String] = []
        parts.append(active?.name ?? "-")
        if let p = primary {
            parts.append(p.name)
            parts.append(p.project)
            parts.append(p.model ?? "-")
            parts.append(p.ctxPct.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(p.ctxWindow.map(String.init) ?? "-")
            parts.append(String(p.activeSession))
            parts.append(String(p.session5h))
            parts.append(p.session5hPercent.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(String(p.week7d))
            parts.append(p.week7dPercent.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(p.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")
            parts.append(p.sessionStarted.map { String(Int($0.timeIntervalSince1970)) } ?? "-")
            for s in p.activeSessions {
                parts.append("S:\(s.id)|\(s.project)|\(s.model ?? "-")|\(s.ctxPct.map { String(format: "%.1f", $0) } ?? "-")|\(s.tokens)|\(s.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")")
            }
        }
        for ag in all where ag.name != primary?.name {
            parts.append("A:\(ag.name)|\(ag.session5h)|\(ag.session5hPercent.map { String(format: "%.1f", $0) } ?? "-")|\(ag.week7d)|\(ag.week7dPercent.map { String(format: "%.1f", $0) } ?? "-")|\(ag.activeSession)|\(ag.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")|\(ag.model ?? "-")")
        }
        for t in others {
            parts.append("O:\(t.name)|\(t.tokens7d)|\(t.sessions7d)|\(t.lastModel ?? "-")")
        }
        parts.append("T:\(ThemeStore.current.id)")
        parts.append("L:\(L10n.lang.rawValue)")
        return parts.joined(separator: "\u{1F}")
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

        let shareBtn = FooterIconButton(
            symbol: "square.and.arrow.up",
            tooltip: L10n.text("Share Today's HUD", "Bugünün HUD'unu paylaş"),
            target: self,
            action: #selector(handleShare(_:))
        )
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
        self.refreshBtn = refreshBtn
        let quitBtn = FooterIconButton(
            symbol: "power",
            tooltip: L10n.text("Quit", "Çık"),
            target: self,
            action: #selector(handleQuit)
        )

        let rightStack = NSStackView(views: [shareBtn, settingsBtn, refreshBtn, quitBtn])
        rightStack.orientation = .horizontal
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(themeBtn)
        container.addSubview(rightStack)

        NSLayoutConstraint.activate([
            themeBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            themeBtn.topAnchor.constraint(equalTo: container.topAnchor, constant: Spacing.xs),
            themeBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Spacing.xs),
            themeBtn.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -Spacing.xs),
            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
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

        let prefix = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(L10n.text("Theme", "Tema")))
        prefix.lineBreakMode = .byClipping
        prefix.cell?.usesSingleLineMode = true
        prefix.maximumNumberOfLines = 1
        prefix.setContentCompressionResistancePriority(.required, for: .horizontal)
        prefix.setContentHuggingPriority(.required, for: .horizontal)

        // Popup absorbs the squeeze instead of forcing "Theme" to wrap.
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [prefix, popup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Spacing.xs
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
            attributes: [.font: font, .foregroundColor: Palette.primaryText]
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
    @objc private func handleRefresh() {
        let now = Date()
        if let last = lastRefreshClickAt, now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastRefreshClickAt = now
        refreshBtn?.setSpinning(true)
        onRefresh?()
    }
    @objc private func handleQuit() { onQuit?() }
    @objc private func handleShare(_ sender: NSView) { onShare?(sender) }
    @objc private func handleThemePick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onPickTheme?(id)
    }
}
