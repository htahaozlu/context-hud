import AppKit
import Foundation

enum IncidentSeverity: Int, Comparable {
    case none = 0
    case minor = 1
    case major = 2
    case critical = 3

    static func < (lhs: IncidentSeverity, rhs: IncidentSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct IncidentState {
    let severity: IncidentSeverity
    let title: String
    let url: URL?
    static let none = IncidentState(severity: .none, title: "", url: nil)
}

/// Polls upstream status pages on a 5-minute timer and emits an IncidentState.
/// Currently surfaces Anthropic (status.anthropic.com); extend `endpoints`
/// when adding agents. Network failures degrade silently to `.none` — never
/// shows "down" because polling itself failed.
final class IncidentPoller {
    static let shared = IncidentPoller()
    static let didChange = Notification.Name("ContextHudIncidentDidChange")

    private(set) var current: IncidentState = .none
    private var timer: Timer?
    private let session: URLSession
    private let interval: TimeInterval = 300

    private struct Endpoint {
        let name: String
        let url: URL
        let homepage: URL
    }

    private let endpoints: [Endpoint] = {
        var out: [Endpoint] = []
        if let s = URL(string: "https://status.anthropic.com/api/v2/status.json"),
           let h = URL(string: "https://status.anthropic.com") {
            out.append(Endpoint(name: "Anthropic", url: s, homepage: h))
        }
        if let s = URL(string: "https://status.openai.com/api/v2/status.json"),
           let h = URL(string: "https://status.openai.com") {
            out.append(Endpoint(name: "OpenAI", url: s, homepage: h))
        }
        return out
    }()

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func start() {
        guard timer == nil else { return }
        guard DisplayPrefs.incidents else { return }
        pollNow()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollNow()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if current.severity != .none {
            current = .none
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    func pollNow() {
        guard DisplayPrefs.incidents, !endpoints.isEmpty else { return }
        let group = DispatchGroup()
        var collected: [IncidentState] = []
        let lock = NSLock()
        for ep in endpoints {
            group.enter()
            let task = session.dataTask(with: ep.url) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? [String: Any],
                      let indicator = status["indicator"] as? String else { return }
                let severity = Self.parseIndicator(indicator)
                if severity != .none {
                    let desc = (status["description"] as? String) ?? indicator
                    let state = IncidentState(
                        severity: severity,
                        title: "\(ep.name): \(desc)",
                        url: ep.homepage
                    )
                    lock.lock()
                    collected.append(state)
                    lock.unlock()
                }
            }
            task.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let highest = collected.max(by: { $0.severity < $1.severity }) ?? .none
            if highest.severity != self.current.severity || highest.title != self.current.title {
                self.current = highest
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        }
    }

    private static func parseIndicator(_ raw: String) -> IncidentSeverity {
        switch raw.lowercased() {
        case "none": return .none
        case "minor": return .minor
        case "major": return .major
        case "critical": return .critical
        default: return .none
        }
    }
}
