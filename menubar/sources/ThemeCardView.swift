import AppKit
import Foundation

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

        let swatchLabel = NSTextField(labelWithAttributedString: ThemeCardView.swatchString(theme))
        swatchLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchLabel)

        let nameLabel = NSTextField(labelWithString: theme.name)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            previewLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            swatchLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
            swatchLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            swatchLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSAppearance.current = effectiveAppearance
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
        return s
    }

    /// Three threshold swatches painted in pctLow / pctMid / pctHigh so the
    /// user sees how each tier renders before committing.
    private static func swatchString(_ theme: Theme) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "12%", attributes: [.font: font, .foregroundColor: theme.pctLow]))
        s.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        s.append(NSAttributedString(string: "42%", attributes: [.font: font, .foregroundColor: theme.pctMid]))
        s.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        s.append(NSAttributedString(string: "85%", attributes: [.font: font, .foregroundColor: theme.pctHigh]))
        return s
    }
}
