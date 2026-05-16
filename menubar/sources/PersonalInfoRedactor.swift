import Foundation

/// Masks paths and email addresses in user-facing strings — applied when
/// `DisplayPrefs.redactPaths` is on (notifications, exports, screenshots).
enum PersonalInfoRedactor {
    private static let emailRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            options: []
        )
    }()

    /// Returns the input unchanged when redaction is off. Otherwise replaces
    /// $HOME prefixes with `~`, strips parent path components down to the
    /// basename for absolute paths inside `/Users/<name>/...`, and masks emails.
    static func redact(_ text: String) -> String {
        guard DisplayPrefs.redactPaths else { return text }
        return apply(text)
    }

    /// Forces redaction regardless of toggle. Used by export/share code paths
    /// where the redaction is explicit (e.g. "Copy state — redacted").
    static func force(_ text: String) -> String {
        apply(text)
    }

    private static func apply(_ text: String) -> String {
        var out = text
        let home = NSHomeDirectory()
        if !home.isEmpty {
            out = out.replacingOccurrences(of: home, with: "~")
        }
        out = redactUsersPaths(out)
        out = redactEmails(out)
        return out
    }

    private static func redactUsersPaths(_ text: String) -> String {
        // Replace `/Users/<name>/...` with `~/...` for paths not under our home.
        guard let regex = try? NSRegularExpression(
            pattern: "/Users/[^/\\s]+",
            options: []
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "~")
    }

    private static func redactEmails(_ text: String) -> String {
        guard let regex = emailRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "***@***")
    }
}
