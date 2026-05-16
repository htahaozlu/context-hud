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

/// Native Usage panel — rebuilt per refresh from hud.json. One card per agent
/// with stat tiles, window progress bars, active-session strip, and a 30-day
/// sparkline. Replaces the previous webview approach so the panel feels at
/// home on macOS (no scrollbars, no font drift, no white flash).
