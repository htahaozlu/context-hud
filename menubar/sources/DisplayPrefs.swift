import Foundation

enum ResetStyle: String {
    case relative
    case absolute
}

/// User-tunable display flags for popover surfaces. Persisted in
/// UserDefaults; defaults chosen so out-of-box UI stays minimal.
enum DisplayPrefs {
    private static let kResetStyle = "displayPrefs.resetStyle"
    private static let kTickMarks = "displayPrefs.tickMarks"
    private static let kCriticalBg = "displayPrefs.criticalBg"
    private static let kBurnRate = "displayPrefs.burnRate"
    private static let kIncidents = "displayPrefs.incidents"
    private static let kConfetti = "displayPrefs.confetti"
    private static let kRedactPaths = "displayPrefs.redactPaths"

    static var resetStyle: ResetStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: kResetStyle),
               let v = ResetStyle(rawValue: raw) {
                return v
            }
            return .relative
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kResetStyle) }
    }

    static var tickMarks: Bool {
        get { UserDefaults.standard.bool(forKey: kTickMarks) }
        set { UserDefaults.standard.set(newValue, forKey: kTickMarks) }
    }

    /// Surface a background session > 80% in the menubar when foreground is calm.
    static var criticalBackground: Bool {
        get { defaultsBool(kCriticalBg, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: kCriticalBg) }
    }

    /// Burn-rate forecast line in the hero card.
    static var burnRate: Bool {
        get { defaultsBool(kBurnRate, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: kBurnRate) }
    }

    /// Poll upstream status pages and surface incident overlay.
    static var incidents: Bool {
        get { defaultsBool(kIncidents, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: kIncidents) }
    }

    /// Confetti animation on quota window reset.
    static var confetti: Bool {
        get { defaultsBool(kConfetti, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: kConfetti) }
    }

    /// Mask project paths / emails in notifications and shared output.
    static var redactPaths: Bool {
        get { UserDefaults.standard.bool(forKey: kRedactPaths) }
        set { UserDefaults.standard.set(newValue, forKey: kRedactPaths) }
    }

    private static func defaultsBool(_ key: String, default def: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return def }
        return UserDefaults.standard.bool(forKey: key)
    }
}
