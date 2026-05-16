import AppKit
import Foundation

final class AppearanceSettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    private var cardViews: [(ThemeCardView, Theme)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        cardViews = Theme.all.map { theme in
            let card = ThemeCardView(theme: theme)
            card.isSelected = theme.id == ThemeStore.current.id
            card.translatesAutoresizingMaskIntoConstraints = false
            card.onSelect = { [weak self] in
                ThemeStore.set(theme.id)
                self?.updateCardSelection()
                self?.onThemeChange?(theme.id)
            }
            return (card, theme)
        }

        let rows = stride(from: 0, to: cardViews.count, by: 3).map { start -> NSStackView in
            let end = min(start + 3, cardViews.count)
            let row = NSStackView(views: cardViews[start..<end].map { $0.0 as NSView })
            row.orientation = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        let themeGrid = NSStackView(views: rows)
        themeGrid.orientation = .vertical
        themeGrid.spacing = 12
        addSection(
            title: L10n.text("Theme", "Tema"),
            subtitle: L10n.text(
                "Pick the menubar palette that matches your desktop. The preview uses the same typography and accent logic shown in the status item.",
                "Masaüstüne en uygun menubar paletini seçin. Önizleme, durum çubuğunda kullanılan aynı tipografi ve vurgu mantığını gösterir."
            ),
            body: themeGrid
        )
        cardViews.forEach { $0.0.heightAnchor.constraint(equalToConstant: 82).isActive = true }

        let langControl = NSSegmentedControl(
            labels: AppLanguage.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        langControl.selectedSegment = AppLanguage.allCases.firstIndex(of: LanguageStore.selected) ?? 0
        addSection(
            title: L10n.text("Language", "Dil"),
            subtitle: L10n.text(
                "Follow the system language or pin the UI to English or Turkish.",
                "Arayuzu sistem diline birakin ya da Ingilizce/Turkce olarak sabitleyin."
            ),
            body: langControl
        )
    }

    private func updateCardSelection() {
        let current = ThemeStore.current.id
        for (card, theme) in cardViews {
            card.isSelected = theme.id == current
        }
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        let language = AppLanguage.allCases[sender.selectedSegment]
        LanguageStore.set(language)
        onThemeChange?(ThemeStore.current.id)
    }
}

final class MenubarSettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    private let displayChips = HorizontalDisplayController()
    private let preview = TitlePreviewView()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshPreview()
    }

    private func buildUI() {
        let sepControl = NSSegmentedControl(
            labels: SeparatorStore.options.map { $0.label },
            trackingMode: .selectOne,
            target: self,
            action: #selector(separatorChanged(_:))
        )
        sepControl.selectedSegment = SeparatorStore.currentIndex
        addSection(
            title: L10n.text("Separator", "Ayraç"),
            subtitle: L10n.text(
                "Character shown between the agent icon, project, and context values in the menubar title.",
                "Menubar başlığında ajan ikonu, proje ve bağlam değerleri arasında gösterilen karakter."
            ),
            body: sepControl
        )

        displayChips.onChange = { [weak self] in
            self?.refreshPreview()
            self?.onThemeChange?(ThemeStore.current.id)
        }
        addSection(
            title: L10n.text("Title content", "Başlık içeriği"),
            subtitle: L10n.text(
                "Toggle the checkbox to show a field. Grab the ⠿ handle and drag a card left or right to reorder.",
                "Bir alanı göstermek için onay kutusunu işaretleyin. Sıralamak için ⠿ tutamacından kartı sağa veya sola sürükleyin."
            ),
            body: displayChips.container
        )

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        addSection(
            title: L10n.text("Preview", "Önizleme"),
            subtitle: L10n.text(
                "Live sample of how the menubar title will look with agent icons. Changes apply instantly.",
                "Menubar başlığının ajan ikonlarıyla nasıl görüneceğine dair canlı örnek. Değişiklikler anında uygulanır."
            ),
            body: preview
        )
    }

    private func refreshPreview() {
        preview.update(
            items: displayChips.currentItems,
            agent: "Claude",
            project: L10n.text("my-project", "projem"),
            pct: 27
        )
    }

    @objc private func separatorChanged(_ sender: NSSegmentedControl) {
        let value = SeparatorStore.options[sender.selectedSegment].value
        SeparatorStore.set(value)
        refreshPreview()
        onThemeChange?(ThemeStore.current.id)
    }
}

final class AboutViewController: PreferencePaneViewController {
    private let changelogURL = URL(string: "https://github.com/htahaozlu/context-hud/blob/main/CHANGELOG.md")!

    override func viewDidLoad() {
        super.viewDidLoad()

        addHero(AboutHeroView())

        let actions = NSStackView(views: [
            makeActionButton(
                title: L10n.text("Check for Updates", "Güncellemeleri kontrol et"),
                action: #selector(checkForUpdates)
            ),
            makeActionButton(
                title: L10n.text("View Changelog", "Değişiklik kaydını aç"),
                action: #selector(openChangelog)
            )
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        addSection(
            title: L10n.text("Updates", "Güncellemeler"),
            subtitle: L10n.text(
                "ContextHUD releases are distributed from GitHub Releases.",
                "ContextHUD sürümleri GitHub Releases üzerinden dağıtılır."
            ),
            body: actions
        )

        let context = NSStackView(views: [
            makeInfoRow(title: L10n.text("Artifacts folder", "Artifact klasörü"), value: "\(NSHomeDirectory())/.context-hud"),
            makeInfoRow(title: L10n.text("Repository brief", "Repo brifi"), value: ".context-hud/AGENT.md"),
            makeInfoRow(title: L10n.text("Claude compatibility", "Claude uyumluluğu"), value: "CLAUDE.md"),
        ])
        context.orientation = .vertical
        context.spacing = 10
        context.alignment = .leading
        addSection(
            title: L10n.text("Repository context", "Repo bağlamı"),
            subtitle: L10n.text(
                "Stable local brief and machine-readable sidecars so agents re-enter a project with less drift.",
                "Ajanlar projeye daha az kayma ile geri dönebilsin diye sabit yerel brief ve makinece okunabilir yan dosyalar."
            ),
            body: context
        )

        let sources = NSStackView(views: [
            makeInfoRow(title: "Git", value: L10n.text("branch, commits, worktree", "branch, commit, worktree")),
            makeInfoRow(title: "Claude Code", value: "~/.claude/projects/**/*.jsonl"),
            makeInfoRow(title: "Codex CLI", value: "~/.codex/sessions/**/*.jsonl"),
            makeInfoRow(title: "Output", value: "~/.context-hud/hud.json"),
        ])
        sources.orientation = .vertical
        sources.spacing = 10
        sources.alignment = .leading
        addSection(
            title: L10n.text("Data sources", "Veri kaynakları"),
            subtitle: L10n.text(
                "Usage is built locally from existing transcript files. No remote service required.",
                "Kullanım özeti mevcut transcript dosyalarından yerelde oluşturulur. Uzak servis gerekmez."
            ),
            body: sources
        )

        let locations = NSStackView(views: [
            makeInfoRow(title: L10n.text("Version", "Sürüm"), value: AppMetadata.current.detailedVersionLabel),
            makeInfoRow(title: L10n.text("App bundle", "Uygulama paketi"), value: "dist/ContextHUD.app"),
            makeInfoRow(title: L10n.text("Disk image", "DMG"), value: "dist/ContextHUD.dmg"),
            makeInfoRow(title: L10n.text("Open window", "Pencereyi aç"), value: "⌘D"),
            makeInfoRow(title: L10n.text("Refresh", "Yenile"), value: "⌘R"),
        ])
        locations.orientation = .vertical
        locations.spacing = 10
        locations.alignment = .leading
        addSection(
            title: L10n.text("Files and shortcuts", "Dosyalar ve kısayollar"),
            subtitle: L10n.text(
                "Build artifacts live in the repository. Runtime data stays under your home directory.",
                "Build artefact'ları repo içinde kalır. Çalışma verileri home dizini altında tutulur."
            ),
            body: locations
        )
    }

    private func makeActionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates(presenter: view.window)
    }

    @objc private func openChangelog() {
        NSWorkspace.shared.open(changelogURL)
    }
}

// MARK: - Modern menubar popover
//
// Replaces the legacy NSMenu dropdown. Renders a native popover with a
// vibrant material background, hero card for the active agent, a context
// window meter, a 3-tile stat grid (5h / 7d / session), an optional list of
// other AI tools, and a footer toolbar (theme / settings / refresh / quit).
// Designed for macOS 13+ — uses NSVisualEffectView (.menu), continuous
// corner curves, and SF Symbol toolbar icons.

/// Rounded card backdrop tuned for use over an NSVisualEffectView. Slightly
/// translucent fill plus a hairline border so it reads on both light and
/// dark menubar materials without competing with the vibrancy underneath.
