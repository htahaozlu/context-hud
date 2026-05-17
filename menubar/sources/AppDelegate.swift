import AppKit
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    /// Paths currently fed to FSEventStreamCreate. FSEvents captures the
    /// path set at creation — when ~/.claude/projects or ~/.codex/sessions
    /// materializes after launch we need to tear down and recreate the
    /// stream against the new union, otherwise the new agent stays invisible
    /// until restart.
    private var fsWatchedPaths: Set<String> = []
    private var popoverVisible = false
    private var lastAllAgents: [Agent] = []
    private var engineRunning = false
    private var enginePending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // No icon — title-only menubar entry to save horizontal space.

        setupPopover()
        refresh()
        let args = CommandLine.arguments.dropFirst()
        if ProcessInfo.processInfo.environment["CONTEXTBAR_OPEN_WINDOW"] == "1"
            || args.contains("--settings") || args.contains("--open") {
            openDetail()
        }
        if let screenshotPath = ProcessInfo.processInfo.environment["CONTEXTBAR_SCREENSHOT_PATH"] {
            openDetail()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.detailWindow?.capture(to: screenshotPath)
                NSApp.terminate(nil)
            }
        }
        if ProcessInfo.processInfo.environment["CONTEXTBAR_MENU_SCREENSHOT_PATH"] != nil {
            // External script (marketing-screenshot.sh) handles the actual capture.
            // This env var just prevents the timer so the app stays responsive.
        }
        if let sharePath = ProcessInfo.processInfo.environment["CONTEXTBAR_SHARE_RENDER_PATH"] {
            let masked = (ProcessInfo.processInfo.environment["CONTEXTBAR_SHARE_MASK"] ?? "1") == "1"
            let (_, all, others) = hud.load()
            let img = ShareCard.render(agents: all, others: others, maskProjects: masked)
            try? ShareCard.writePNG(img, to: URL(fileURLWithPath: sharePath))
            NSApp.terminate(nil)
            return
        }
        if let popoverPath = ProcessInfo.processInfo.environment["CONTEXTBAR_POPOVER_SCREENSHOT_PATH"] {
            // Auto-open the menubar popover, give it a moment to lay out, then
            // shell out to `screencapture -l` on the popover's window number so
            // marketing can rebuild docs/images/context-bar-menubar.png without
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
        registerSystemObservers()
        IncidentPoller.shared.start()
    }

    /// Hardens the status item against display reconfigure / sleep — common
    /// failure mode in menubar apps where an external monitor unplug leaves
    /// the status button orphaned with no rendering surface. Also redraws
    /// the title when the incident poller reports a status change so the
    /// overlay can light up between refresh ticks.
    private func registerSystemObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenReconfigure),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncidentChange),
            name: IncidentPoller.didChange,
            object: nil
        )
    }

    @objc private func handleScreenReconfigure() {
        ensureStatusItemAlive()
        repaintTitle()
    }

    @objc private func handleWake() {
        ensureStatusItemAlive()
        regenerateThenRefresh()
        IncidentPoller.shared.pollNow()
    }

    @objc private func handleIncidentChange() {
        repaintTitle()
        if popover.isShown { popoverVC.rebuild() }
    }

    /// Recreates the status item when its button is missing or its window has
    /// been orphaned by a display reconfigure. Idempotent — safe to call from
    /// any observer.
    private func ensureStatusItemAlive() {
        let alive: Bool = {
            guard let btn = statusItem?.button else { return false }
            return btn.window != nil
        }()
        if alive { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Watches the agent transcript directories so the menubar reflects the
    /// active project the moment the user starts typing in a different repo.
    /// FSEvents is recursive and debounced so a burst of writes only triggers
    /// one regenerate.
    private func startAgentDirWatcher() {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
        ]
        let paths = candidates.filter { FileManager.default.fileExists(atPath: $0) }
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
            fsWatchedPaths = Set(paths)
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Rescan agent transcript dirs and, if a new one materialized since
    /// startup (e.g. user just installed the Codex CLI), tear down and
    /// recreate the FSEventStream against the expanded path set. FSEvents
    /// captures paths at creation and offers no in-place add.
    private func rescanAgentDirsIfNeeded() {
        let home = NSHomeDirectory()
        let existing: Set<String> = [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
        ].filter { FileManager.default.fileExists(atPath: $0) }
            .reduce(into: Set<String>()) { $0.insert($1) }
        if existing == fsWatchedPaths { return }
        if let s = fsStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            fsStream = nil
            fsRunning = false
            fsWatchedPaths = []
        }
        startAgentDirWatcher()
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
        // Always regenerate so menubar title reflects the most recently
        // active project/session — even when popover and detail window are
        // both closed. Engine is fast (sub-100ms in steady state) and this
        // closes a UX gap where switching projects in another Claude session
        // left the menubar showing the old project until the popover opened.
        rescanAgentDirsIfNeeded()
        regenerateThenRefresh()
    }

    /// Finder double-click / Dock click while running. Accessory apps with
    /// no Dock tile still receive this when the user launches the app from
    /// Finder, Spotlight, or `open -a ContextBar`. Used as a fallback when
    /// the menubar icon is hidden by overflow / Bartender / Hidden Bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showFromReopen()
        return true
    }

    /// First-launch hand-off: if the app was already running and the user
    /// double-clicked it in Finder, AppKit may send `application(_:open:)`
    /// instead of reopen. Treat both the same.
    func application(_ application: NSApplication, open urls: [URL]) {
        showFromReopen()
    }

    private func showFromReopen() {
        // The status item button sits inside the menubar strip which is
        // outside `visibleFrame` (visibleFrame excludes menubar+dock). Check
        // against `frame` so a normally-visible button doesn't read as hidden.
        let button = statusItem.button
        let buttonHidden: Bool = {
            guard let btn = button, let win = btn.window else { return true }
            let frame = win.convertToScreen(btn.convert(btn.bounds, to: nil))
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(frame.origin) })
                ?? NSScreen.main else { return frame.width < 4 }
            return frame.width < 4 || !screen.frame.intersects(frame)
        }()
        if buttonHidden {
            openDetail()
        } else {
            togglePopover(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func refreshNow() { regenerateThenRefresh() }

    func popoverWillShow(_ notification: Notification) { popoverVisible = true }
    func popoverDidClose(_ notification: Notification) { popoverVisible = false }

    /// Spawns the bundled engine to rewrite ~/.context-bar/hud.json, then reloads
    /// the menu. Engine runs off the main thread so the menubar stays responsive;
    /// UI update is dispatched back to main. If the engine binary is missing
    /// (e.g. running the Swift app standalone in dev), we still refresh from the
    /// existing JSON so behavior degrades gracefully to the previous mode.
    func regenerateThenRefresh() {
        // Reentrancy guard: if an engine run is already in flight, just mark
        // pending so we coalesce overlapping ticks (FSEvents burst + 10s timer
        // + wake-from-sleep) into at most one follow-up run. Without this two
        // engine processes can stomp on hud.json simultaneously.
        if engineRunning {
            enginePending = true
            return
        }
        engineRunning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runEngine()
            DispatchQueue.main.async {
                guard let self else { return }
                self.refresh()
                self.reloadWidgets()
                self.engineRunning = false
                if self.enginePending {
                    self.enginePending = false
                    self.regenerateThenRefresh()
                }
            }
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        if #available(macOS 11.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    private func runEngine() {
        let bundleExe = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/context-bar-engine")
        let candidates: [URL] = [
            bundleExe,
            URL(fileURLWithPath: "/usr/local/bin/context-bar"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/.cargo/bin/context-bar"),
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
            env["CONTEXTBAR_USAGE_SCRIPT"] = pyURL.path
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
        popoverVC.onShare = { [weak self] anchor in
            self?.presentShareCard(from: anchor)
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
        let (active, all, _) = hud.load()
        lastActive = active
        lastAllAgents = all
        repaintTitle()
        if popover.isShown {
            popoverVC.rebuild()
        }
    }

    /// Renders the current usage state to a square-portrait PNG and opens the
    /// native macOS share sheet anchored at `anchor`. Project names are
    /// redacted by default (DisplayPrefs.maskShareProjects) so users can post
    /// the card to social channels without leaking private repository names.
    func presentShareCard(from anchor: NSView) {
        let (_, all, others) = hud.load()
        guard !all.isEmpty else { return }
        let image = ShareCard.render(
            agents: all,
            others: others,
            maskProjects: DisplayPrefs.maskShareProjects
        )
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ContextBar-DailyHUD.png")
        do {
            try ShareCard.writePNG(image, to: outURL)
        } catch {
            NSSound.beep()
            return
        }
        let picker = NSSharingServicePicker(items: [outURL])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
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
        let font = NSFont.menuBarFont(ofSize: 0)
        guard let a = active else {
            return NSAttributedString(string: L10n.text(" no agent", " ajan yok"),
                                      attributes: [
                                          .font: font,
                                          .foregroundColor: NSColor.secondaryLabelColor,
                                      ])
        }
        let base = styleTitle(
            agent: a.name,
            project: a.project,
            pct: a.ctxPct,
            theme: theme,
            font: font
        )
        let result = NSMutableAttributedString(attributedString: base)
        if let prefix = incidentPrefix(font: font) {
            result.insert(prefix, at: 0)
        }
        if let suffix = criticalBackgroundSuffix(font: font, theme: theme) {
            result.append(suffix)
        }
        return result
    }

    /// Builds a leading "● " glyph colored by the active incident severity.
    /// Returns nil when no incident is active or the user disabled the poller.
    private func incidentPrefix(font: NSFont) -> NSAttributedString? {
        guard DisplayPrefs.incidents else { return nil }
        let state = IncidentPoller.shared.current
        guard state.severity != .none else { return nil }
        let color: NSColor
        switch state.severity {
        case .critical: color = .systemRed
        case .major: color = .systemOrange
        case .minor: color = .systemYellow
        case .none: return nil
        }
        return NSAttributedString(string: "● ", attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    /// Surfaces a high-pressure background session when the foreground is
    /// calm. Suppressed when foreground itself is already > 50% (the user is
    /// already seeing the warning color on the main pct field).
    private func criticalBackgroundSuffix(font: NSFont, theme: Theme) -> NSAttributedString? {
        guard DisplayPrefs.criticalBackground else { return nil }
        guard let fg = lastActive, (fg.ctxPct ?? 0) < 50 else { return nil }
        // Look across every agent's parallel sessions and find the highest
        // non-foreground pct. Threshold: 80%.
        var hottest: ActiveSession?
        var hottestPct: Double = 0
        let foregroundProject = fg.project
        for ag in lastAllAgents {
            for sess in ag.activeSessions {
                guard sess.project != foregroundProject else { continue }
                let pct = sess.ctxPct ?? 0
                if pct > hottestPct, pct >= 80 {
                    hottest = sess
                    hottestPct = pct
                }
            }
        }
        guard let h = hottest else { return nil }
        let pctStr = String(format: "%.0f%%", hottestPct)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.ctxColor(hottestPct),
        ]
        return NSAttributedString(string: "  ⚠ \(h.project) \(pctStr)", attributes: attrs)
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

        let opts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        if let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, bestID, opts
        ) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = NSSize(width: cgImage.width, height: cgImage.height)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
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
        // CGWindowListCreateImage works on windows owned by the current
        // process without requiring Screen Recording TCC, unlike the
        // `screencapture` CLI which inherits the parent's permissions and
        // silently fails in headless / freshly-signed launches.
        let opts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, bestID, opts
        ) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: cgImage.width, height: cgImage.height)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
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
            title: L10n.text("Quit ContextBar", "ContextBar'dan Çık"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        NSApp.mainMenu = mainMenu
    }
}
