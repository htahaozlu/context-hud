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
                "Arayüzü sistem diline bırakın ya da İngilizce veya Türkçe olarak sabitleyin."
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

// MARK: - Display preferences pane

/// Surfaces the display-side toggles that don't fit on the existing
/// Appearance / Menubar panes: reset-style, threshold tick marks,
/// burn-rate forecast, critical-background indicator.
final class DisplaySettingsViewController: PreferencePaneViewController {
    var onChange: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let resetCtrl = NSSegmentedControl(
            labels: [L10n.text("Relative", "Göreli"), L10n.text("Absolute", "Mutlak")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(resetStyleChanged(_:))
        )
        resetCtrl.selectedSegment = DisplayPrefs.resetStyle == .relative ? 0 : 1
        addSection(
            title: L10n.text("Reset time", "Sıfırlama zamanı"),
            subtitle: L10n.text(
                "Show window resets as a relative duration (\"in 1h 47m\") or an absolute clock time (\"14:32\").",
                "Pencere sıfırlamalarını göreli süre (\"1sa 47dk\") veya saat olarak (\"14:32\") göster."
            ),
            body: resetCtrl
        )

        let ticks = makeToggle(
            title: L10n.text("Warning marks on bars", "Çubuklarda uyarı işaretleri"),
            on: DisplayPrefs.tickMarks,
            action: #selector(ticksChanged(_:))
        )
        addSection(
            title: L10n.text("Bar marks", "Çubuk işaretleri"),
            subtitle: L10n.text(
                "Adds thin tick marks at 70% and 90% on every context bar. Off by default for a cleaner look.",
                "Her bağlam çubuğunda %70 ve %90'a ince çizgiler ekler. Daha sade görünüm için varsayılan kapalıdır."
            ),
            body: ticks
        )

        let burn = makeToggle(
            title: L10n.text("Burn-rate forecast", "Tüketim tahmini"),
            on: DisplayPrefs.burnRate,
            action: #selector(burnChanged(_:))
        )
        addSection(
            title: L10n.text("Forecast", "Tahmin"),
            subtitle: L10n.text(
                "Adds an \"on pace to fill in X\" line under the context bar when usage trends predictively.",
                "Kullanım eğilim gösterdiğinde bağlam çubuğunun altına \"X içinde dolacak\" satırı ekler."
            ),
            body: burn
        )

        let crit = makeToggle(
            title: L10n.text("Surface critical background sessions", "Kritik arka plan oturumlarını göster"),
            on: DisplayPrefs.criticalBackground,
            action: #selector(criticalChanged(_:))
        )
        addSection(
            title: L10n.text("Menubar", "Menubar"),
            subtitle: L10n.text(
                "When the foreground session is calm and a background session exceeds 80%, append a warning chip to the menubar title.",
                "Aktif oturum sakinken arka plan oturumu %80'i geçerse menubar başlığına uyarı eklenir."
            ),
            body: crit
        )
    }

    private func makeToggle(title: String, on: Bool, action: Selector) -> NSView {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
        btn.state = on ? .on : .off
        return btn
    }

    @objc private func resetStyleChanged(_ sender: NSSegmentedControl) {
        DisplayPrefs.resetStyle = sender.selectedSegment == 0 ? .relative : .absolute
        onChange?()
    }
    @objc private func ticksChanged(_ sender: NSButton) {
        DisplayPrefs.tickMarks = sender.state == .on
        onChange?()
    }
    @objc private func burnChanged(_ sender: NSButton) {
        DisplayPrefs.burnRate = sender.state == .on
        onChange?()
    }
    @objc private func criticalChanged(_ sender: NSButton) {
        DisplayPrefs.criticalBackground = sender.state == .on
        onChange?()
    }
}

// MARK: - Notifications pane

final class NotificationSettingsViewController: PreferencePaneViewController {
    var onChange: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let incidents = makeToggle(
            title: L10n.text("Show upstream incident overlay", "Üst kaynak olay göstergesi"),
            on: DisplayPrefs.incidents,
            action: #selector(incidentsChanged(_:))
        )
        addSection(
            title: L10n.text("Provider status", "Sağlayıcı durumu"),
            subtitle: L10n.text(
                "Polls Anthropic and OpenAI status pages every 5 minutes. Adds a colored dot to the menubar title and an incident card to the popover when an incident is active.",
                "Anthropic ve OpenAI durum sayfaları 5 dakikada bir kontrol edilir. Olay olduğunda menubar başlığında renkli nokta ve popover'da kart görünür."
            ),
            body: incidents
        )

        let confetti = makeToggle(
            title: L10n.text("Celebrate quota window resets", "Pencere sıfırlamada kutlama"),
            on: DisplayPrefs.confetti,
            action: #selector(confettiChanged(_:))
        )
        addSection(
            title: L10n.text("Delight", "İnce dokunuş"),
            subtitle: L10n.text(
                "Plays a brief particle burst in the popover when a 5-hour or weekly quota window resets. Respects reduce-motion.",
                "5 saatlik veya haftalık kota penceresi sıfırlandığında popover'da kısa bir parçacık animasyonu oynatır. Hareketi azalt ayarına uyar."
            ),
            body: confetti
        )
    }

    private func makeToggle(title: String, on: Bool, action: Selector) -> NSView {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
        btn.state = on ? .on : .off
        return btn
    }

    @objc private func incidentsChanged(_ sender: NSButton) {
        DisplayPrefs.incidents = sender.state == .on
        if sender.state == .on {
            IncidentPoller.shared.start()
        } else {
            IncidentPoller.shared.stop()
        }
        onChange?()
    }
    @objc private func confettiChanged(_ sender: NSButton) {
        DisplayPrefs.confetti = sender.state == .on
        onChange?()
    }
}

// MARK: - Privacy pane

final class PrivacySettingsViewController: PreferencePaneViewController {
    var onChange: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let redact = makeToggle(
            title: L10n.text("Mask project paths and emails", "Proje yollarını ve e-postaları gizle"),
            on: DisplayPrefs.redactPaths,
            action: #selector(redactChanged(_:))
        )
        addSection(
            title: L10n.text("Shared output", "Paylaşılan çıktı"),
            subtitle: L10n.text(
                "Replaces $HOME with ~, collapses /Users/<name>/ paths, and masks email addresses in any text exported through the app — useful before sharing screenshots or logs.",
                "$HOME değerini ~ ile değiştirir, /Users/<ad>/ yollarını sadeleştirir ve uygulamadan dışa aktarılan metinlerde e-posta adreslerini gizler. Ekran görüntüsü veya günlük paylaşmadan önce işe yarar."
            ),
            body: redact
        )

        let preview = makeInfoRow(
            title: L10n.text("Sample", "Örnek"),
            value: PersonalInfoRedactor.force("/Users/jane/projects/secret-app — jane@example.com")
        )
        let previewStack = NSStackView(views: [preview])
        previewStack.orientation = .vertical
        previewStack.alignment = .leading
        previewStack.spacing = 6
        addSection(
            title: L10n.text("Preview", "Önizleme"),
            subtitle: L10n.text(
                "How a path/email looks after redaction.",
                "Bir yol/e-postanın gizleme sonrası görünümü."
            ),
            body: previewStack
        )

        let maskShare = makeToggle(
            title: L10n.text("Mask project names on share card", "Paylaşım kartında proje adlarını gizle"),
            on: DisplayPrefs.maskShareProjects,
            action: #selector(maskShareChanged(_:))
        )
        addSection(
            title: L10n.text("Share card", "Paylaşım kartı"),
            subtitle: L10n.text(
                "When you share Today's HUD from the popover footer, real project names are replaced with generic labels (Project A, Project B). Turn off to share real names.",
                "Popover altındaki paylaşım düğmesinden Today's HUD'u paylaşırken proje adları genel etiketlerle değiştirilir (Project A, Project B). Gerçek adları paylaşmak için kapatın."
            ),
            body: maskShare
        )
    }

    private func makeToggle(title: String, on: Bool, action: Selector) -> NSView {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
        btn.state = on ? .on : .off
        return btn
    }

    @objc private func redactChanged(_ sender: NSButton) {
        DisplayPrefs.redactPaths = sender.state == .on
        onChange?()
    }

    @objc private func maskShareChanged(_ sender: NSButton) {
        DisplayPrefs.maskShareProjects = sender.state == .on
        onChange?()
    }
}

final class AboutViewController: PreferencePaneViewController {
    private let changelogURL = URL(string: "https://github.com/htahaozlu/context-bar/blob/main/CHANGELOG.md")!

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
                "ContextBar releases are distributed from GitHub Releases.",
                "ContextBar sürümleri GitHub Releases üzerinden dağıtılır."
            ),
            body: actions
        )

        let context = NSStackView(views: [
            makeInfoRow(title: L10n.text("Artifacts folder", "Artifact klasörü"), value: "\(NSHomeDirectory())/.context-bar"),
            makeInfoRow(title: L10n.text("Repository brief", "Repo brifi"), value: ".context-bar/AGENT.md"),
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
            makeInfoRow(title: "Output", value: "~/.context-bar/hud.json"),
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
            makeInfoRow(title: L10n.text("App bundle", "Uygulama paketi"), value: "dist/ContextBar.app"),
            makeInfoRow(title: L10n.text("Disk image", "DMG"), value: "dist/ContextBar.dmg"),
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
