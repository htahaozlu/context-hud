import AppKit
import Foundation

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
        let savedOrigin = scrollView.contentView.bounds.origin
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

        DispatchQueue.main.async { [scrollView] in
            scrollView.contentView.scroll(to: savedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Agent card: header + 4 stat tiles (context / active session / 5h / 7d) +
    /// 30-day sparkline. All data visible by default — no disclosures. Each
    /// tile pairs a primary value with a faded sub-value so the user sees both
    /// "what" and "when/how much" without scanning multiple sections.
    private func buildAgentCard(agent a: Agent, isActive: Bool, showsHeader: Bool) -> NSView {
        let card = NSView()
        Surface.applyCard(card)
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
            DualStatTileView(caption: L10n.text("context", "bağlam"),
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
        let cap = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(L10n.text("30-day tokens", "30 gün token")))
        cap.translatesAutoresizingMaskIntoConstraints = false

        let total = values.reduce(0, +)
        let totalLbl = NSTextField(labelWithString: Hud.formatTokens(UInt64(total)))
        totalLbl.font = Typography.bodyMono(11, weight: .regular)
        totalLbl.textColor = .secondaryLabelColor
        totalLbl.alignment = .right
        totalLbl.translatesAutoresizingMaskIntoConstraints = false

        let spark = SparklineView()
        spark.values = Array(values)
        spark.tint = ThemeStore.current.accent
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
        Surface.applyCard(card)
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
