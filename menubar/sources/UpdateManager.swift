import AppKit
import CryptoKit
import Foundation

struct AppMetadata {
    let version: String
    let build: String

    static var current: AppMetadata {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppMetadata(
            version: version ?? "0.1.0",
            build: build ?? "1"
        )
    }

    var versionLabel: String {
        "v\(version)"
    }

    var detailedVersionLabel: String {
        "v\(version) (\(build))"
    }
}

struct ReleaseInfo {
    let latest: String
    let current: String
    let htmlURL: URL
    let dmgURL: URL
    let sha256URL: URL
}

final class UpdateProgressWindowController: NSWindowController {
    private let messageLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 132)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Updating ContextHUD", "ContextHUD güncelleniyor")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let content = NSView(frame: contentRect)
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        messageLabel.textColor = .labelColor
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .regular
        progress.style = .bar
        progress.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(messageLabel)
        content.addSubview(detailLabel)
        content.addSubview(progress)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            messageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),

            progress.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 16),
            progress.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(message: String, detail: String, fraction: Double?) {
        messageLabel.stringValue = message
        detailLabel.stringValue = detail
        if let fraction {
            progress.isIndeterminate = false
            progress.doubleValue = max(0, min(1, fraction))
        } else {
            progress.isIndeterminate = true
            progress.startAnimation(nil)
        }
    }
}

final class UpdateManager: NSObject, URLSessionDownloadDelegate {
    static let shared = UpdateManager()

    private var progressWindow: UpdateProgressWindowController?
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var activeRelease: ReleaseInfo?

    func checkForUpdates(presenter: NSWindow?) {
        let apiURL = URL(string: "https://api.github.com/repos/htahaozlu/context-hud/releases/latest")!
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard err == nil,
                      let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = obj["tag_name"] as? String else {
                    self.presentUpdateError(presenter: presenter)
                    return
                }
                let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let current = AppMetadata.current.version
                let htmlURL = (obj["html_url"] as? String).flatMap(URL.init(string:))
                    ?? URL(string: "https://github.com/htahaozlu/context-hud/releases/latest")!
                let assets = (obj["assets"] as? [[String: Any]]) ?? []
                let dmgURL = assets.compactMap { asset -> URL? in
                    guard let name = asset["name"] as? String,
                          name.hasSuffix(".dmg"),
                          let raw = asset["browser_download_url"] as? String else { return nil }
                    return URL(string: raw)
                }.first
                let shaURL = assets.compactMap { asset -> URL? in
                    guard let name = asset["name"] as? String,
                          name.hasSuffix(".dmg.sha256"),
                          let raw = asset["browser_download_url"] as? String else { return nil }
                    return URL(string: raw)
                }.first
                guard self.isNewer(latest: latest, current: current) else {
                    self.presentUpToDate(current: current, presenter: presenter)
                    return
                }
                guard let dmgURL else {
                    self.presentUpdateError(presenter: presenter)
                    return
                }
                let sha256URL = shaURL ?? URL(string: dmgURL.absoluteString + ".sha256")!
                let release = ReleaseInfo(latest: latest, current: current, htmlURL: htmlURL, dmgURL: dmgURL, sha256URL: sha256URL)
                self.presentUpdateAvailable(release: release, presenter: presenter)
            }
        }.resume()
    }

    private func isNewer(latest: String, current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let li = i < l.count ? l[i] : 0
            let ci = i < c.count ? c[i] : 0
            if li > ci { return true }
            if li < ci { return false }
        }
        return false
    }

    private func presentUpdateAvailable(release: ReleaseInfo, presenter: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Update available", "Güncelleme hazır")
        alert.informativeText = L10n.text(
            "ContextHUD v\(release.latest) is available. Download it now and restart when it's ready.",
            "ContextHUD v\(release.latest) hazır. Şimdi indirilsin, hazır olunca yeniden başlatıp güncelleyin."
        )
        alert.addButton(withTitle: L10n.text("Update Now", "Şimdi Güncelle"))
        alert.addButton(withTitle: L10n.text("Release Notes", "Sürüm Notları"))
        alert.addButton(withTitle: L10n.text("Later", "Daha Sonra"))
        let response = runAlert(alert, presenter: presenter)
        if response == .alertFirstButtonReturn {
            startDownload(release: release)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func startDownload(release: ReleaseInfo) {
        activeRelease = release
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.downloadTask(with: release.dmgURL)
        downloadTask = task
        let progressWindow = UpdateProgressWindowController()
        progressWindow.present()
        progressWindow.update(
            message: L10n.text("Downloading update…", "Güncelleme indiriliyor…"),
            detail: L10n.text("ContextHUD v\(release.latest) is being prepared.", "ContextHUD v\(release.latest) hazırlanıyor."),
            fraction: 0
        )
        self.progressWindow = progressWindow
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let release = activeRelease else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressWindow?.update(
            message: L10n.text("Downloading update…", "Güncelleme indiriliyor…"),
            detail: L10n.text(
                "\(formatBytes(totalBytesWritten)) of \(formatBytes(totalBytesExpectedToWrite))",
                "\(formatBytes(totalBytesWritten)) / \(formatBytes(totalBytesExpectedToWrite))"
            ),
            fraction: fraction
        )
        if fraction >= 1 {
            progressWindow?.update(
                message: L10n.text("Preparing update…", "Güncelleme hazırlanıyor…"),
                detail: L10n.text("Verifying and staging ContextHUD v\(release.latest).", "ContextHUD v\(release.latest) doğrulanıyor ve hazırlanıyor."),
                fraction: nil
            )
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let release = activeRelease else { return }
        // The system removes `location` once this delegate returns, so copy first.
        let stagedDMG = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextHUD-\(UUID().uuidString).dmg")
        do {
            if FileManager.default.fileExists(atPath: stagedDMG.path) {
                try? FileManager.default.removeItem(at: stagedDMG)
            }
            try FileManager.default.copyItem(at: location, to: stagedDMG)
        } catch {
            progressWindow?.close()
            progressWindow = nil
            cleanupSession()
            presentInstallError(error)
            return
        }

        progressWindow?.update(
            message: L10n.text("Verifying update…", "Güncelleme doğrulanıyor…"),
            detail: L10n.text("Checking integrity of ContextHUD v\(release.latest).", "ContextHUD v\(release.latest) bütünlüğü denetleniyor."),
            fraction: nil
        )

        let sha256URL = release.sha256URL
        var shaReq = URLRequest(url: sha256URL)
        shaReq.timeoutInterval = 15
        URLSession.shared.dataTask(with: shaReq) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                let http = response as? HTTPURLResponse
                guard error == nil, let data, (http?.statusCode ?? 200) < 400, !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else {
                    try? FileManager.default.removeItem(at: stagedDMG)
                    self.progressWindow?.close()
                    self.progressWindow = nil
                    self.cleanupSession()
                    self.presentInstallError(NSError(
                        domain: "ContextHUD.Update",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: L10n.text(
                            "Verification asset unavailable.",
                            "Doğrulama dosyası alınamadı."
                        )]
                    ))
                    return
                }
                let expected = self.parseShaToken(text)
                let computed: String
                do {
                    computed = try self.sha256Hex(of: stagedDMG)
                } catch {
                    try? FileManager.default.removeItem(at: stagedDMG)
                    self.progressWindow?.close()
                    self.progressWindow = nil
                    self.cleanupSession()
                    self.presentInstallError(error)
                    return
                }
                guard !expected.isEmpty, expected.lowercased() == computed.lowercased() else {
                    try? FileManager.default.removeItem(at: stagedDMG)
                    self.progressWindow?.close()
                    self.progressWindow = nil
                    self.cleanupSession()
                    self.presentInstallError(NSError(
                        domain: "ContextHUD.Update",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: L10n.text(
                            "Integrity check failed.",
                            "Bütünlük doğrulanamadı."
                        )]
                    ))
                    return
                }
                self.installVerifiedDMG(at: stagedDMG, release: release)
            }
        }.resume()
    }

    private func installVerifiedDMG(at dmgPath: URL, release: ReleaseInfo) {
        do {
            let mountURL = try mountDMG(at: dmgPath)
            let stagedApp = mountURL.appendingPathComponent("ContextHUD.app")
            guard FileManager.default.fileExists(atPath: stagedApp.path) else {
                throw NSError(domain: "ContextHUD.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mounted DMG did not contain ContextHUD.app"])
            }
            try stageInstaller(sourceApp: stagedApp, mountedVolume: mountURL)
            progressWindow?.close()
            progressWindow = nil
            presentRestartPrompt(release: release)
        } catch {
            progressWindow?.close()
            progressWindow = nil
            presentInstallError(error)
        }
        try? FileManager.default.removeItem(at: dmgPath)
        cleanupSession()
    }

    private func parseShaToken(_ text: String) -> String {
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let token = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            if !token.isEmpty { return token }
        }
        return ""
    }

    private func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            progressWindow?.close()
            progressWindow = nil
            cleanupSession()
            presentInstallError(error)
        }
    }

    private func presentRestartPrompt(release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Restart to Update", "Güncellemek İçin Yeniden Başlat")
        alert.informativeText = L10n.text(
            "ContextHUD v\(release.latest) is ready to install. Restart now to finish the update.",
            "ContextHUD v\(release.latest) kuruluma hazır. Güncellemeyi tamamlamak için şimdi yeniden başlatın."
        )
        alert.addButton(withTitle: L10n.text("Restart to Update", "Güncellemek İçin Yeniden Başlat"))
        alert.addButton(withTitle: L10n.text("Later", "Daha Sonra"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func presentUpToDate(current: String, presenter: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Up to date", "Güncel")
        alert.informativeText = L10n.text(
            "You are running the latest version (v\(current)).",
            "En son sürümü kullanıyorsunuz (v\(current))."
        )
        alert.addButton(withTitle: "OK")
        _ = runAlert(alert, presenter: presenter)
    }

    private func presentUpdateError(presenter: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Could not check for updates", "Güncellemeler kontrol edilemedi")
        alert.informativeText = L10n.text(
            "Check your internet connection and try again.",
            "İnternet bağlantınızı kontrol edin ve tekrar deneyin."
        )
        alert.addButton(withTitle: "OK")
        _ = runAlert(alert, presenter: presenter)
    }

    private func presentInstallError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Update could not be completed", "Güncelleme tamamlanamadı")
        alert.informativeText = L10n.text(
            "ContextHUD could not finish installing the update.\n\n\(error.localizedDescription)",
            "ContextHUD güncellemeyi tamamlayamadı.\n\n\(error.localizedDescription)"
        )
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func cleanupSession() {
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func mountDMG(at location: URL) throws -> URL {
        let tempDMG = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextHUD-\(UUID().uuidString).dmg")
        if FileManager.default.fileExists(atPath: tempDMG.path) {
            try? FileManager.default.removeItem(at: tempDMG)
        }
        try FileManager.default.copyItem(at: location, to: tempDMG)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", tempDMG.path, "-nobrowse", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "ContextHUD.Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to mount the downloaded disk image."])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw NSError(domain: "ContextHUD.Update", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not locate the mounted update volume."])
        }
        return URL(fileURLWithPath: mountPath)
    }

    private func stageInstaller(sourceApp: URL, mountedVolume: URL) throws {
        let currentApp = Bundle.main.bundleURL.standardizedFileURL
        let destination = currentApp
        let parent = destination.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = FileManager.default.temporaryDirectory
            .appendingPathComponent("contexthud-update-\(UUID().uuidString).sh")

        let source = shellEscape(sourceApp.path)
        let dest = shellEscape(destination.path)
        let mount = shellEscape(mountedVolume.path)
        let openTarget = shellEscape(destination.path)
        let script = """
#!/bin/sh
set -e
PID="\(pid)"
SRC=\(source)
DST=\(dest)
VOL=\(mount)
TMP="${DST}.new"
OLD="${DST}.old"
while kill -0 "$PID" 2>/dev/null; do
  sleep 0.25
done
/bin/rm -rf "$TMP"
/usr/bin/ditto "$SRC" "$TMP"
/bin/rm -rf "$OLD"
if [ -e "$DST" ]; then
  /bin/mv "$DST" "$OLD"
fi
/bin/mv "$TMP" "$DST"
/usr/bin/xattr -dr com.apple.quarantine "$DST" >/dev/null 2>&1 || true
/usr/bin/hdiutil detach "$VOL" -quiet >/dev/null 2>&1 || true
/usr/bin/open \(openTarget)
/bin/rm -rf "$OLD"
/bin/rm -- "$0"
"""
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let writable = FileManager.default.isWritableFile(atPath: parent.path)
            && FileManager.default.isWritableFile(atPath: destination.path)
        if writable {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [helper.path]
            try task.run()
            return
        }

        let command = "/bin/sh \(shellEscape(helper.path))"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "do shell script " + appleScriptString(command) + " with administrator privileges",
        ]
        try task.run()
    }

    private func runAlert(_ alert: NSAlert, presenter: NSWindow?) -> NSApplication.ModalResponse {
        if presenter != nil {
            return alert.runModal()
        }
        return alert.runModal()
    }

    private func formatBytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: count)
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

func appLogoImage() -> NSImage? {
    if let bundled = Bundle.main.url(forResource: "logo", withExtension: "png") {
        return NSImage(contentsOf: bundled)
    }
    let repoLogo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("logo.png")
    return NSImage(contentsOf: repoLogo)
}

