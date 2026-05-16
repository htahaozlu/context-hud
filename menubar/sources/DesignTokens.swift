import AppKit
import Foundation

// MARK: - Design Tokens
//
// Single source of truth for spacing, corner radii, typography, and motion
// across every menubar surface (popover, usage, stats, appearance, about).
// All ad-hoc paddings and font sizes should reference these values so the
// app feels consistent end to end.

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let chip: CGFloat = 8
    static let card: CGFloat = 12
    static let hero: CGFloat = 16
    static let popover: CGFloat = 20
}

enum Typography {
    static func display(_ size: CGFloat = 28, weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func displayMono(_ size: CGFloat = 28, weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
    static func title(_ size: CGFloat = 15) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 12) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }
    static func bodyMono(_ size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
    static func caption() -> NSFont {
        NSFont.systemFont(ofSize: 10, weight: .semibold)
    }

    /// Builds an UPPERCASE kerned attributed string used for section captions
    /// ("CONTEXT", "30-DAY TOKENS", etc.). Consistent across all panes.
    static func captionAttributed(_ text: String, color: NSColor = .tertiaryLabelColor) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: caption(),
            .foregroundColor: color,
            .kern: 0.8,
        ])
    }

    /// Display number — supports tabular figures and slight tracking for the
    /// premium hero "42%" look. Number labels that animate / update on refresh
    /// should always use this so the width doesn't jitter as digits change.
    static func displayNumberAttributed(_ text: String, size: CGFloat = 28,
                                        weight: NSFont.Weight = .semibold,
                                        color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: -0.4,
        ])
    }
}

enum MotionPrefs {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

// MARK: - Accent helpers

extension Theme {
    /// Semantic accent — the project / agent signature color of the theme.
    /// Used for sparkline strokes, heatmap ramps, hero gradients.
    var accent: NSColor { projectColor }

    /// Soft fill version of the accent — for hero gradients, chips, hover
    /// states. Alpha 0.18 by default.
    var accentSoft: NSColor { accent.withAlphaComponent(0.18) }

    /// Glow version — used for the "high pct" warning glow under the meter
    /// and as the second stop in gradient strokes.
    var accentGlow: NSColor { pctMid.withAlphaComponent(0.35) }
}

// MARK: - Surface recipes

enum Surface {
    /// THE card recipe. One definition for every pane.
    /// - fill: controlBackgroundColor at 0.55 light / 0.35 dark
    /// - border: separatorColor at 0.45 alpha, 0.5pt
    /// - corner: Radius.card, continuous
    static func applyCard(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = Radius.card
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 0.5
        refreshCardColors(view)
    }

    static func refreshCardColors(_ view: NSView) {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha: CGFloat = MotionPrefs.reduceTransparency ? 1.0 : (isDark ? 0.35 : 0.55)
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(alpha).cgColor
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }

    /// Hero card recipe — larger radius, subtle elevation shadow,
    /// continuous corners. Caller sets the gradient layer separately.
    static func applyHero(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = Radius.hero
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 0.5
        refreshHeroChrome(view)
    }

    static func refreshHeroChrome(_ view: NSView) {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        // Subtle elevation shadow
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOffset = CGSize(width: 0, height: -4)
        view.layer?.shadowRadius = 9 // ~ blur 18 / 2
        view.layer?.shadowOpacity = MotionPrefs.reduceTransparency ? 0 : (isDark ? 0.30 : 0.10)
        view.layer?.masksToBounds = false
    }
}
