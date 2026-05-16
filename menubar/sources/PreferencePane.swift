import AppKit
import Foundation

final class PreferenceSectionCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Surface.applyCard(self)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.m),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.l),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.l),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.m),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

class PreferencePaneViewController: NSViewController {
    let scrollView = NSScrollView()
    let contentStack = NSStackView()

    override func loadView() {
        view = FlippedView()
        view.wantsLayer = true
        // Transparent so the window's NSVisualEffectView frost shows through.
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
        ])
    }

    func addHero(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    func addSection(title: String, subtitle: String? = nil, body: NSView) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4
        section.translatesAutoresizingMaskIntoConstraints = false

        // Sonoma System Settings-style uppercase section header — small,
        // medium weight, secondary color — keeps the focus on the card body.
        let titleLabel = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(title, color: .secondaryLabelColor))
        section.addArrangedSubview(titleLabel)

        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11)
            subtitleLabel.textColor = .tertiaryLabelColor
            subtitleLabel.maximumNumberOfLines = 0
            section.addArrangedSubview(subtitleLabel)
            section.setCustomSpacing(8, after: subtitleLabel)
        } else {
            section.setCustomSpacing(6, after: titleLabel)
        }

        let card = PreferenceSectionCard(content: body)
        section.addArrangedSubview(card)
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    func makeInfoRow(title: String, value: String) -> NSView {
        ResponsiveInfoRowView(title: title, value: value)
    }
}

