import AppKit
import Foundation

// MARK: - ProgressBarView

final class ProgressBarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true; updateA11y() } }
    var tint: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var gradientEnd: NSColor? { didSet { needsDisplay = true } }
    var trackColor: NSColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
    var corner: CGFloat = 3
    var glow: Bool = false { didSet { needsDisplay = true } }
    /// Threshold tick marks rendered as 1pt vertical lines, in `[0, 1]`.
    /// Empty = no marks. Color follows ctx-color thresholds per mark.
    var tickMarks: [Double] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.progressIndicator)
        updateA11y()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateA11y() {
        let clamped = max(0, min(1, value))
        setAccessibilityValue(NSNumber(value: Int(clamped * 100)))
        setAccessibilityLabel("Progress")
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
        trackColor.setFill()
        track.fill()
        let clamped = max(0, min(1, value))
        guard clamped > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let fillRect = NSRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: corner, yRadius: corner)
        ctx.saveGState()
        fillPath.addClip()
        if let end = gradientEnd {
            let cg = CGGradient(colorsSpace: nil,
                                colors: [tint.cgColor, end.cgColor] as CFArray,
                                locations: [0, 1])!
            ctx.drawLinearGradient(cg,
                                   start: CGPoint(x: fillRect.minX, y: 0),
                                   end: CGPoint(x: fillRect.maxX, y: 0),
                                   options: [])
        } else {
            tint.setFill()
            fillPath.fill()
        }
        ctx.restoreGState()
        if !tickMarks.isEmpty {
            ctx.saveGState()
            for raw in tickMarks {
                let t = max(0, min(1, raw))
                let x = bounds.width * CGFloat(t)
                let pctValue = t * 100
                let color: NSColor
                if pctValue >= 90 { color = .systemRed }
                else if pctValue >= 70 { color = .systemOrange }
                else { color = NSColor.tertiaryLabelColor }
                ctx.setFillColor(color.withAlphaComponent(0.85).cgColor)
                ctx.fill(CGRect(x: x - 0.5, y: 0, width: 1, height: bounds.height))
            }
            ctx.restoreGState()
        }
        if glow && !MotionPrefs.reduceTransparency {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6, color: tint.withAlphaComponent(0.55).cgColor)
            tint.withAlphaComponent(0.0).setFill()
            fillPath.fill()
            ctx.restoreGState()
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - SparklineView (gradient area + line + endpoint dot)

/// 30-day sparkline rendered as a smooth gradient-filled area beneath a
/// stroked line, with an emphasized endpoint dot. Replaces the prior
/// bar-style sparkline for a more premium "live ticker" feel.
final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var tint: NSColor = ThemeStore.current.accent { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 56) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("Token usage sparkline")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count >= 2, let maxV = values.max(), maxV > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let n = values.count
        let w = bounds.width
        let h = bounds.height
        let padTop: CGFloat = 6
        let padBottom: CGFloat = 2
        let usableH = h - padTop - padBottom

        func pointAt(_ i: Int) -> CGPoint {
            let x = (n == 1) ? w / 2 : CGFloat(i) * (w / CGFloat(n - 1))
            let norm = CGFloat(values[i] / maxV)
            let y = padBottom + (1 - norm) * usableH
            return CGPoint(x: x, y: y)
        }

        // Line path
        let line = CGMutablePath()
        line.move(to: pointAt(0))
        for i in 1..<n { line.addLine(to: pointAt(i)) }

        // Area path (closed below)
        let area = CGMutablePath()
        area.move(to: CGPoint(x: 0, y: padBottom))
        for i in 0..<n { area.addLine(to: pointAt(i)) }
        area.addLine(to: CGPoint(x: w, y: padBottom))
        area.closeSubpath()

        // Gradient fill
        ctx.saveGState()
        ctx.addPath(area)
        ctx.clip()
        let cg = CGGradient(colorsSpace: nil,
                            colors: [tint.withAlphaComponent(0.22).cgColor,
                                     tint.withAlphaComponent(0.0).cgColor] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(cg,
                               start: CGPoint(x: 0, y: padBottom),
                               end: CGPoint(x: 0, y: h),
                               options: [])
        ctx.restoreGState()

        // Stroke line
        ctx.saveGState()
        ctx.setStrokeColor(tint.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(line)
        ctx.strokePath()
        ctx.restoreGState()

        // Endpoint dot
        let last = pointAt(n - 1)
        let dotR: CGFloat = 2.5
        let ringR: CGFloat = 4.5
        ctx.saveGState()
        ctx.setFillColor(tint.withAlphaComponent(0.20).cgColor)
        ctx.fillEllipse(in: CGRect(x: last.x - ringR, y: last.y - ringR, width: ringR * 2, height: ringR * 2))
        ctx.setFillColor(tint.cgColor)
        ctx.fillEllipse(in: CGRect(x: last.x - dotR, y: last.y - dotR, width: dotR * 2, height: dotR * 2))
        ctx.restoreGState()
    }
}

// MARK: - StatTileView (premium — number first, kerned caption below)

final class StatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Radius.card
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        Surface.refreshCardColors(self)

        let val = NSTextField(labelWithString: value)
        val.font = mono
            ? Typography.displayMono(22, weight: .semibold)
            : Typography.display(22, weight: .semibold)
        val.textColor = valueColor
        val.attributedStringValue = NSAttributedString(string: value, attributes: [
            .font: val.font!,
            .foregroundColor: valueColor,
            .kern: -0.3,
        ])
        val.translatesAutoresizingMaskIntoConstraints = false
        val.lineBreakMode = .byTruncatingTail
        val.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cap = NSTextField(labelWithAttributedString: Typography.captionAttributed(caption))
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.lineBreakMode = .byTruncatingTail

        addSubview(val); addSubview(cap)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            val.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.s),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            cap.topAnchor.constraint(equalTo: val.bottomAnchor, constant: Spacing.xxs),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            cap.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(caption)
        setAccessibilityValue(value)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

// MARK: - DualStatTileView (primary value + sub caption + UPPERCASE label)

final class DualStatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor,
         sub: String, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Radius.card
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        Surface.refreshCardColors(self)

        let val = NSTextField(labelWithString: value)
        let valFont = mono
            ? Typography.displayMono(22, weight: .semibold)
            : Typography.display(22, weight: .semibold)
        val.attributedStringValue = NSAttributedString(string: value, attributes: [
            .font: valFont,
            .foregroundColor: valueColor,
            .kern: -0.3,
        ])
        val.translatesAutoresizingMaskIntoConstraints = false
        val.lineBreakMode = .byTruncatingTail

        let cap = NSTextField(labelWithAttributedString: Typography.captionAttributed(caption))
        cap.translatesAutoresizingMaskIntoConstraints = false

        let subLbl = NSTextField(labelWithString: sub)
        subLbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subLbl.textColor = .secondaryLabelColor
        subLbl.lineBreakMode = .byTruncatingTail
        subLbl.translatesAutoresizingMaskIntoConstraints = false

        addSubview(val); addSubview(cap); addSubview(subLbl)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            val.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.s),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            cap.topAnchor.constraint(equalTo: val.bottomAnchor, constant: Spacing.xxs),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            subLbl.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: Spacing.xxs),
            subLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            subLbl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            subLbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(caption)
        setAccessibilityValue("\(value), \(sub)")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

// MARK: - LoadingStripeView

/// Animated diagonal-stripe placeholder used while the engine is producing
/// the first hud.json. Static gradient when reduce-motion is on.
final class LoadingStripeView: NSView {
    var tint: NSColor = ThemeStore.current.accent { didSet { needsDisplay = true } }
    private var phase: CGFloat = 0
    private var displayLink: CVDisplayLink?
    /// Last CACurrentMediaTime() at which we hopped to main from the CV
    /// callback. Accessed only on the CV display thread, so no lock.
    private var lastFrameHop: CFTimeInterval = 0

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 4) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityLabel("Loading")
        startAnimating()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { stopAnimating() }

    private func startAnimating() {
        guard !MotionPrefs.reduceMotion else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<LoadingStripeView>.fromOpaque(userInfo).takeUnretainedValue()
            // Throttle to ~30fps. CV display link fires at the panel's refresh
            // rate (often 60–120 Hz). Hopping to main every frame saturates
            // the run loop and shows up on Instruments as needless overhead
            // while the loading state is on screen.
            let now = CACurrentMediaTime()
            if now - view.lastFrameHop < 0.033 { return kCVReturnSuccess }
            view.lastFrameHop = now
            DispatchQueue.main.async {
                view.phase = (view.phase + 1.6).truncatingRemainder(dividingBy: 24)
                view.needsDisplay = true
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopAnimating() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.18).setFill()
        track.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        track.addClip()
        let stripeWidth: CGFloat = 12
        let gap: CGFloat = 12
        let step = stripeWidth + gap
        var x: CGFloat = -bounds.height - step + phase
        tint.withAlphaComponent(0.55).setFill()
        while x < bounds.width + bounds.height {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: 0))
            p.line(to: NSPoint(x: x + stripeWidth, y: 0))
            p.line(to: NSPoint(x: x + stripeWidth + bounds.height, y: bounds.height))
            p.line(to: NSPoint(x: x + bounds.height, y: bounds.height))
            p.close()
            p.fill()
            x += step
        }
        ctx.restoreGState()
    }
}

// MARK: - IncidentBadgeView

/// Inline incident strip used in the hero card meta row when upstream
/// status pages report an active incident. Click opens the status URL.
final class IncidentBadgeView: NSView {
    var state: IncidentState = .none {
        didSet {
            rebuild()
            isHidden = state.severity == .none
        }
    }
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        let color: NSColor
        switch state.severity {
        case .critical: color = .systemRed
        case .major: color = .systemOrange
        case .minor: color = .systemYellow
        case .none: color = .clear
        }
        dot.layer?.backgroundColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        label.stringValue = state.title
        toolTip = state.url?.absoluteString
    }

    override func mouseDown(with event: NSEvent) {
        if let url = state.url { NSWorkspace.shared.open(url) }
    }
}

/// Native Usage panel — rebuilt per refresh from hud.json. One card per agent
/// with stat tiles, window progress bars, active-session strip, and a 30-day
/// sparkline. Replaces the previous webview approach so the panel feels at
/// home on macOS (no scrollbars, no font drift, no white flash).
