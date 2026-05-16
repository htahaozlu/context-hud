import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer!
    var detailWindow: DetailWindowController?
    let hud = Hud()
    var lastActive: Agent?
    private var previewTheme: Theme?
    private let popover = NSPopover()
    private let popoverVC = MenubarPopoverViewController()
    private var fsStream: FSEventStreamRef?
    private var fsDebounce: DispatchWorkItem?
    private var fsRunning = false
    private var popoverVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // No icon — title-only menubar entry to save horizontal space.

        setupPopover()
        refresh()
        if ProcessInfo.processInfo.environment["CONTEXTHUD_OPEN_WINDOW"] == "1" {
            openDetail()
        }
        if let screenshotPath = ProcessInfo.processInfo.environment["CONTEXTHUD_SCREENSHOT_PATH"] {
            openDetail()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.detailWindow?.capture(to: screenshotPath)
                NSApp.terminate(nil)
            }
        }
        if ProcessInfo.processInfo.environment["CONTEXTHUD_MENU_SCREENSHOT_PATH"] != nil {
            // External script (marketing-screenshot.sh) handles the actual capture.
            // This env var just prevents the timer so the app stays responsive.
        }
        if let popoverPath = ProcessInfo.processInfo.environment["CONTEXTHUD_POPOVER_SCREENSHOT_PATH"] {
            // Auto-open the menubar popover, give it a moment to lay out, then
            // shell out to `screencapture -l` on the popover's window number so
            // marketing can rebuild docs/images/context-hud-menubar.png without
            // manual click-and-frame work.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.togglePopover(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    self?.capturePopover(to: popoverPath)
                    NSApp.terminate(nil)
                }
            }
        }

        timer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)

        startAgentDirWatcher()
    }

    /// Watches the agent transcript directories so the menubar reflects the
    /// active project the moment the user starts typing in a different repo.
    /// FSEvents is recursive and debounced so a burst of writes only triggers
    /// one regenerate.
    private func startAgentDirWatcher() {
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            delegate.fsEventFired()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if FSEventStreamStart(stream) {
            fsStream = stream
            fsRunning = true
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func fsEventFired() {
        fsDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.regenerateThenRefresh()
        }
        fsDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @objc func tick() {
        // Battery: only refresh on timer ticks when something is actually
        // visible. FSEvents still trigger a refresh below so the menubar
        // title stays current. The menubar title itself is repainted on
        // refresh() — but the engine respawn is skipped here.
        let detailVisible = detailWindow?.window?.isVisible == true
        guard popoverVisible || detailVisible else { return }
        regenerateThenRefresh()
    }
    @objc func refreshNow() { regenerateThenRefresh() }

    func popoverWillShow(_ notification: Notification) { popoverVisible = true }
    func popoverDidClose(_ notification: Notification) { popoverVisible = false }

    /// Spawns the bundled engine to rewrite ~/.context-hud/hud.json, then reloads
    /// the menu. Engine runs off the main thread so the menubar stays responsive;
    /// UI update is dispatched back to main. If the engine binary is missing
    /// (e.g. running the Swift app standalone in dev), we still refresh from the
    /// existing JSON so behavior degrades gracefully to the previous mode.
    func regenerateThenRefresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runEngine()
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func runEngine() {
        let bundleExe = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/context-hud-engine")
        let candidates: [URL] = [
            bundleExe,
            URL(fileURLWithPath: "/usr/local/bin/context-hud"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/.cargo/bin/context-hud"),
        ]
        guard let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            return
        }
        let pyURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/usage_signal.py")
        let task = Process()
        task.executableURL = exe
        task.arguments = ["global"]
        var env = ProcessInfo.processInfo.environment
        if FileManager.default.fileExists(atPath: pyURL.path) {
            env["CONTEXTHUD_USAGE_SCRIPT"] = pyURL.path
        }
        task.environment = env
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Engine missing or failed — refresh() will fall back to existing JSON.
        }
    }

    /// Wires the popover and rewires the status item button to toggle it. The
    /// status item no longer owns an NSMenu — both left and right clicks open
    /// the modern popover panel. Quick actions (settings/refresh/quit/theme)
    /// live in the popover footer.
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
        if #available(macOS 14.0, *) {
            popover.hasFullSizeContent = true
        }

        popoverVC.onOpenSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.openDetail()
        }
        popoverVC.onRefresh = { [weak self] in
            self?.refreshNow()
            self?.popoverVC.rebuild()
        }
        popoverVC.onQuit = { [weak self] in
            self?.quit()
        }
        popoverVC.onPickTheme = { [weak self] id in
            ThemeStore.set(id)
            self?.previewTheme = nil
            self?.refresh()
            self?.popoverVC.rebuild()
            self?.detailWindow?.load()
        }
        popoverVC.onPreviewTheme = { [weak self] id in
            guard let self else { return }
            self.previewTheme = id.map { Theme.by(id: $0) }
            self.repaintTitle()
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        regenerateThenRefresh()
        popoverVC.rebuild()
        // Activate so popover window becomes key — without this an accessory
        // app's popover requires a first focus-click before buttons respond.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let win = popover.contentViewController?.view.window {
            win.makeKey()
        }
    }

    func refresh() {
        let (active, _, _) = hud.load()
        lastActive = active
        repaintTitle()
        if popover.isShown {
            popoverVC.rebuild()
        }
    }

    /// Repaints the status bar title using the current preview theme if any,
    /// otherwise the persisted theme. Used both on refresh and during the
    /// theme picker's live hover preview.
    private func repaintTitle() {
        let theme = previewTheme ?? ThemeStore.current
        statusItem.button?.attributedTitle = composeTitle(active: lastActive, theme: theme)
    }

    /// Builds the compact menubar title using the active theme:
    ///     <Agent> <sep> <project> <sep> <ctx%>
    private func composeTitle(active: Agent?, theme: Theme = ThemeStore.current) -> NSAttributedString {
        guard let a = active else {
            return NSAttributedString(string: L10n.text(" no agent", " ajan yok"),
                                      attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
        return styleTitle(
            agent: a.name,
            project: a.project,
            pct: a.ctxPct,
            theme: theme,
            font: NSFont.menuBarFont(ofSize: 0)
        )
    }

    private func styleTitle(
        agent: String,
        project: String,
        pct: Double?,
        theme: Theme,
        font: NSFont,
        renderAgentAsIcon: Bool = true
    ) -> NSAttributedString {
        let agentAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.agentColor,
        ]
        let dim: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.separatorColor,
        ]
        let projectAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.projectColor,
        ]
        let ctxAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.ctxColor(pct),
        ]
        let pctStr = pct.map { String(format: "%.0f%%", $0) } ?? "—"
        let rawSep = SeparatorStore.current
        let sep = rawSep.isEmpty ? " " : " \(rawSep) "

        let visible = DisplayStore.items.filter { $0.enabled }
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: " ", attributes: agentAttrs))
        if visible.isEmpty {
            return s
        }
        for (i, item) in visible.enumerated() {
            if i > 0 {
                s.append(NSAttributedString(string: sep, attributes: dim))
            }
            switch item.element {
            case .agent:
                if renderAgentAsIcon {
                    s.append(agentInlineString(name: agent, font: font, fallbackColor: theme.agentColor))
                } else {
                    s.append(NSAttributedString(string: agent, attributes: agentAttrs))
                }
            case .project:
                s.append(NSAttributedString(string: project, attributes: projectAttrs))
            case .pct:
                s.append(NSAttributedString(string: pctStr, attributes: ctxAttrs))
            }
        }
        return s
    }

    @objc func openDetail() {
        if detailWindow == nil {
            detailWindow = DetailWindowController(onThemeChange: { [weak self] _ in
                self?.refresh()
                self?.detailWindow?.load()
            })
        }
        detailWindow?.show()
    }

    private func captureMenu(to path: String) {
        // NSMenu popup is a system-managed CGWindow, not an NSWindow.
        // Use CGWindowList to find the largest visible window owned by this process.
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { NSApp.terminate(nil); return }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var bestID: CGWindowID = kCGNullWindowID
        var bestArea: Double = 0

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == myPID,
                  let widInt = info[kCGWindowNumber as String] as? Int,
                  let boundsAny = info[kCGWindowBounds as String] as? [String: Any],
                  let w = boundsAny["Width"] as? Double,
                  let h = boundsAny["Height"] as? Double,
                  w > 150, h > 100
            else { continue }
            let area = w * h
            if area > bestArea { bestArea = area; bestID = CGWindowID(widInt) }
        }

        guard bestID != kCGNullWindowID else { NSApp.terminate(nil); return }

        // screencapture CLI has system-level screen recording access.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(bestID), path]
        try? task.run()
        task.waitUntilExit()
        NSApp.terminate(nil)
    }

    /// Screencaptures the open popover's window to `path`. Locates the
    /// popover's CGWindow by finding the largest visible window owned by
    /// this process — the popover is system-managed and isn't reachable as
    /// an NSWindow, so we go through CGWindowList + the `screencapture` CLI.
    private func capturePopover(to path: String) {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var bestID: CGWindowID = kCGNullWindowID
        var bestArea: Double = 0
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == myPID,
                  let widInt = info[kCGWindowNumber as String] as? Int,
                  let boundsAny = info[kCGWindowBounds as String] as? [String: Any],
                  let w = boundsAny["Width"] as? Double,
                  let h = boundsAny["Height"] as? Double,
                  w > 200, h > 200
            else { continue }
            let area = w * h
            if area > bestArea { bestArea = area; bestID = CGWindowID(widInt) }
        }
        guard bestID != kCGNullWindowID else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(bestID), path]
        try? task.run()
        task.waitUntilExit()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let quitItem = NSMenuItem(
            title: L10n.text("Quit ContextHUD", "ContextHUD'dan Çık"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        NSApp.mainMenu = mainMenu
    }
}
