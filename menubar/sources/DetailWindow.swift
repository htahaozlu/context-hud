import AppKit
import Foundation

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = NSTabViewController()
    let usageVC = UsageViewController()
    let statsVC = StatsViewController()
    private let appearanceVC = AppearanceSettingsViewController()
    private let menubarVC = MenubarSettingsViewController()
    private let aboutVC = AboutViewController()

    init(onThemeChange: @escaping (String) -> Void) {
        super.init(window: nil)

        tabVC.tabStyle = .toolbar

        let usageItem = NSTabViewItem(viewController: usageVC)
        usageItem.label = L10n.text("Usage", "Kullanım")
        usageItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: usageItem.label)

        let statsItem = NSTabViewItem(viewController: statsVC)
        statsItem.label = L10n.text("Stats", "İstatistik")
        statsItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: statsItem.label)

        let appearanceItem = NSTabViewItem(viewController: appearanceVC)
        appearanceItem.label = L10n.text("Appearance", "Görünüm")
        appearanceItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: appearanceItem.label)

        let menubarItem = NSTabViewItem(viewController: menubarVC)
        menubarItem.label = L10n.text("Menubar", "Menubar")
        menubarItem.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: menubarItem.label)

        let aboutItem = NSTabViewItem(viewController: aboutVC)
        aboutItem.label = L10n.text("About", "Hakkında")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: aboutItem.label)

        [usageItem, statsItem, appearanceItem, menubarItem, aboutItem].forEach(tabVC.addTabViewItem)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ContextHUD"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 560)
        window.center()
        window.contentViewController = tabVC
        self.window = window
        window.delegate = self

        // Premium frosted background — under-window blending so the desktop
        // wallpaper softly bleeds through behind the tab content.
        if let contentView = window.contentView {
            let effect = NSVisualEffectView(frame: contentView.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            contentView.addSubview(effect, positioned: .below, relativeTo: nil)
        }

        appearanceVC.onThemeChange = onThemeChange
        menubarVC.onThemeChange = onThemeChange
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        load()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func load() {
        usageVC.reload()
        statsVC.reload()
    }

    func selectTab(index: Int) {
        guard index >= 0, index < tabVC.tabViewItems.count else { return }
        tabVC.selectedTabViewItemIndex = index
    }

    func capture(to path: String) {
        load()
        if let rawIndex = ProcessInfo.processInfo.environment["CONTEXTHUD_SELECT_TAB"],
           let index = Int(rawIndex) {
            selectTab(index: index)
        }
        guard let window, let targetView = window.contentView?.superview ?? window.contentView else { return }
        window.displayIfNeeded()
        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds
        guard let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        targetView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

