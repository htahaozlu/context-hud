import AppKit

/// Renders a square-portrait PNG snapshot of the current usage state for
/// social sharing. Pure AppKit drawing — does not depend on the live popover
/// view tree, so it can be invoked from a menu item without showing the UI.
///
/// Output is 1080×1350 (Instagram portrait, also clean on WhatsApp / X).
/// When `maskProjects` is true (default), project names are replaced with
/// generic labels ("Project A", "Project B") so users can post without leaking
/// repository names.
enum ShareCard {
    static let size = NSSize(width: 1080, height: 1350)

    static func render(agents: [Agent], others: [ToolSummary], maskProjects: Bool) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        drawBackground()
        drawHeader()
        drawAgentCards(agents, maskProjects: maskProjects)
        drawFooter(others: others)
        return image
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "ShareCard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try png.write(to: url)
    }

    // MARK: - Background

    private static func drawBackground() {
        let bg = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0)
        bg.setFill()
        NSRect(origin: .zero, size: size).fill()

        let accent = ThemeStore.current.accent
        let gradient = NSGradient(colors: [
            accent.withAlphaComponent(0.18),
            NSColor.clear,
        ]) ?? NSGradient(starting: accent.withAlphaComponent(0.18), ending: .clear)
        gradient?.draw(in: NSRect(x: -200, y: size.height - 700, width: 800, height: 800),
                       relativeCenterPosition: NSPoint(x: 0, y: 0))
    }

    // MARK: - Header

    private static func drawHeader() {
        let title = "ContextBar"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 64, weight: .heavy),
            .foregroundColor: NSColor.white,
            .kern: -1.0,
        ]
        title.draw(at: NSPoint(x: 64, y: size.height - 132), withAttributes: titleAttrs)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d MMM yyyy"
        let subtitle = "Daily HUD · \(dateFmt.string(from: Date()))"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        subtitle.draw(at: NSPoint(x: 64, y: size.height - 168), withAttributes: subAttrs)
    }

    // MARK: - Agent cards

    private static func drawAgentCards(_ agents: [Agent], maskProjects: Bool) {
        let cardHeight: CGFloat = 380
        let cardSpacing: CGFloat = 28
        let cardWidth: CGFloat = size.width - 128
        let topY = size.height - 220
        let cards = Array(agents.prefix(2))

        for (idx, agent) in cards.enumerated() {
            let y = topY - CGFloat(idx + 1) * cardHeight - CGFloat(idx) * cardSpacing
            let rect = NSRect(x: 64, y: y, width: cardWidth, height: cardHeight)
            let projectLabel = maskProjects
                ? "Project \(String(UnicodeScalar(65 + idx)!))"
                : agent.project
            drawAgentCard(in: rect, agent: agent, projectLabel: projectLabel)
        }
    }

    private static func drawAgentCard(in rect: NSRect, agent: Agent, projectLabel: String) {
        let cardBg = NSColor.white.withAlphaComponent(0.04)
        let border = NSColor.white.withAlphaComponent(0.08)
        let path = NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32)
        cardBg.setFill(); path.fill()
        border.setStroke(); path.lineWidth = 1; path.stroke()

        let pad: CGFloat = 36
        let headerY = rect.maxY - pad - 36

        // Agent name (top-left)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        agent.name.draw(at: NSPoint(x: rect.minX + pad, y: headerY), withAttributes: nameAttrs)

        // Project · model (under name)
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.50),
        ]
        let modelStr = agent.model ?? "—"
        let metaLine = "\(projectLabel) · \(modelStr)"
        metaLine.draw(at: NSPoint(x: rect.minX + pad, y: headerY - 32), withAttributes: metaAttrs)

        // Big context %
        if let pct = agent.ctxPct {
            let pctStr = "\(Int(pct))%"
            let pctAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 72, weight: .heavy),
                .foregroundColor: ThemeStore.current.accent,
                .kern: -2.0,
            ]
            let pctSize = (pctStr as NSString).size(withAttributes: pctAttrs)
            pctStr.draw(at: NSPoint(x: rect.maxX - pad - pctSize.width, y: headerY - 24),
                        withAttributes: pctAttrs)
            let pctLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            ]
            "CONTEXT".draw(at: NSPoint(x: rect.maxX - pad - pctSize.width, y: headerY - 46),
                           withAttributes: pctLabelAttrs)
        }

        // 5h / 7d bars
        drawBar(in: rect, label: "5h limit", pct: agent.session5hPercent, yOffset: 200, color: NSColor.systemGreen)
        drawBar(in: rect, label: "7d limit", pct: agent.week7dPercent, yOffset: 280, color: ThemeStore.current.accent)

        // Session total (bottom-left)
        let totalStr = formatTokens(agent.activeSession)
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let totalLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        ]
        "SESSION".draw(at: NSPoint(x: rect.minX + pad, y: rect.minY + pad), withAttributes: totalLabelAttrs)
        totalStr.draw(at: NSPoint(x: rect.minX + pad, y: rect.minY + pad + 22), withAttributes: totalAttrs)
    }

    private static func drawBar(in card: NSRect, label: String, pct: Double?, yOffset: CGFloat, color: NSColor) {
        let pad: CGFloat = 36
        let barY = card.maxY - yOffset
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        label.draw(at: NSPoint(x: card.minX + pad, y: barY + 8), withAttributes: labelAttrs)
        let valueStr = pct.map { "\(Int($0))%" } ?? "—"
        let valueSize = (valueStr as NSString).size(withAttributes: valueAttrs)
        valueStr.draw(at: NSPoint(x: card.maxX - pad - valueSize.width, y: barY + 8), withAttributes: valueAttrs)

        let trackRect = NSRect(x: card.minX + pad, y: barY, width: card.width - pad * 2, height: 10)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 5, yRadius: 5)
        NSColor.white.withAlphaComponent(0.08).setFill(); track.fill()
        if let pct {
            let frac = max(0, min(1, pct / 100))
            let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY,
                                  width: trackRect.width * frac, height: trackRect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 5, yRadius: 5)
            (pct >= 90 ? NSColor.systemRed : color).setFill(); fill.fill()
        }
    }

    // MARK: - Footer

    private static func drawFooter(others: [ToolSummary]) {
        let footerY: CGFloat = 56
        let urlAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        let url = "github.com/htahaozlu/context-bar"
        let urlSize = (url as NSString).size(withAttributes: urlAttrs)
        url.draw(at: NSPoint(x: (size.width - urlSize.width) / 2, y: footerY), withAttributes: urlAttrs)

        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.35),
        ]
        let tag = "Track your Claude · Codex · agents"
        let tagSize = (tag as NSString).size(withAttributes: tagAttrs)
        tag.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: footerY + 28), withAttributes: tagAttrs)
    }

    // MARK: - Helpers

    private static func formatTokens(_ n: UInt64) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fk", d / 1_000) }
        return "\(n)"
    }
}
