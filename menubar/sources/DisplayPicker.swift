import AppKit
import Foundation

final class ChipCardView: NSView, NSDraggingSource {
    static let dragType = NSPasteboard.PasteboardType("com.contexthud.chip")
    let index: Int
    var onToggle: ((Int, Bool) -> Void)?
    private let checkbox: NSButton
    private let handle: NSTextField
    private let label: NSTextField

    init(item: DisplayItem, index: Int) {
        self.index = index
        self.handle = NSTextField(labelWithString: "⠿")
        self.label = NSTextField(labelWithString: item.element.label)
        self.checkbox = NSButton(checkboxWithTitle: L10n.text("Show", "Göster"),
                                 target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        applyAppearance()

        handle.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        handle.textColor = .tertiaryLabelColor
        handle.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        checkbox.state = item.enabled ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(checkboxToggled(_:))
        checkbox.font = NSFont.systemFont(ofSize: 12)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        addSubview(handle)
        addSubview(label)
        addSubview(checkbox)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            handle.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            label.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: handle.centerYAnchor),

            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            checkbox.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 8),
            checkbox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 168),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        NSAppearance.current = effectiveAppearance
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        onToggle?(index, sender.state == .on)
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let cbHit = checkbox.frame.insetBy(dx: -6, dy: -6)
        if cbHit.contains(pt) {
            super.mouseDown(with: event)
            return
        }
        NSCursor.closedHand.push()
        let start = event.locationInWindow
        var current: NSEvent? = event
        while let ev = current {
            if ev.type == .leftMouseUp {
                NSCursor.pop()
                return
            }
            if ev.type == .leftMouseDragged {
                if hypot(ev.locationInWindow.x - start.x, ev.locationInWindow.y - start.y) > 4 {
                    NSCursor.pop()
                    startDrag(event: ev)
                    return
                }
            }
            current = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }
        NSCursor.pop()
    }

    private func startDrag(event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString("\(index)", forType: Self.dragType)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let size = bounds.size
        let snap = NSImage(size: size)
        snap.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAlpha(0.9)
            layer?.render(in: ctx)
        }
        snap.unlockFocus()
        dragItem.setDraggingFrame(NSRect(origin: .zero, size: size), contents: snap)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
}

final class ChipContainer: NSStackView {
    var onReorder: ((Int, Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([ChipCardView.dragType])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([ChipCardView.dragType])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pbItem = sender.draggingPasteboard.pasteboardItems?.first,
              let s = pbItem.string(forType: ChipCardView.dragType),
              let from = Int(s) else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        let cards = arrangedSubviews.compactMap { $0 as? ChipCardView }
        var target = cards.count - 1
        for (i, v) in cards.enumerated() {
            if p.x < v.frame.midX { target = i; break }
        }
        onReorder?(from, target)
        return true
    }
}

final class HorizontalDisplayController: NSObject {
    private var items: [DisplayItem] = DisplayStore.items
    var onChange: (() -> Void)?
    let container: ChipContainer

    override init() {
        self.container = ChipContainer(frame: .zero)
        super.init()
        container.orientation = .horizontal
        container.spacing = 10
        container.alignment = .top
        container.distribution = .fillEqually
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onReorder = { [weak self] from, to in
            self?.reorder(from: from, to: to)
        }
        rebuild()
    }

    var currentItems: [DisplayItem] { items }

    private func rebuild() {
        container.arrangedSubviews.forEach {
            container.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (idx, item) in items.enumerated() {
            let card = ChipCardView(item: item, index: idx)
            card.onToggle = { [weak self] tag, enabled in
                guard let self = self, tag < self.items.count else { return }
                self.items[tag].enabled = enabled
                self.persist()
            }
            container.addArrangedSubview(card)
        }
    }

    private func reorder(from: Int, to: Int) {
        guard from >= 0, from < items.count, to >= 0, to < items.count, from != to else { return }
        let moved = items.remove(at: from)
        items.insert(moved, at: to)
        DisplayStore.save(items)
        rebuild()
        onChange?()
    }

    private func persist() {
        DisplayStore.save(items)
        onChange?()
    }
}

final class TitlePreviewView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        applyAppearance()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    func update(items: [DisplayItem], agent: String, project: String, pct: Double?) {
        let theme = ThemeStore.current
        let font = NSFont.menuBarFont(ofSize: 0)
        let projectAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.projectColor]
        let ctxAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.ctxColor(pct)]
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.separatorColor]
        let rawSep = SeparatorStore.current
        let sep = rawSep.isEmpty ? " " : " \(rawSep) "
        let pctStr = pct.map { String(format: "%.0f%%", $0) } ?? "—"

        let s = NSMutableAttributedString()
        let visible = items.filter { $0.enabled }
        if visible.isEmpty {
            s.append(NSAttributedString(
                string: L10n.text("(nothing selected)", "(hiçbir alan seçili değil)"),
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        } else {
            for (i, item) in visible.enumerated() {
                if i > 0 {
                    s.append(NSAttributedString(string: sep, attributes: dim))
                }
                switch item.element {
                case .agent: s.append(agentInlineString(name: agent, font: font, fallbackColor: theme.agentColor))
                case .project: s.append(NSAttributedString(string: project, attributes: projectAttrs))
                case .pct: s.append(NSAttributedString(string: pctStr, attributes: ctxAttrs))
                }
            }
        }
        label.attributedStringValue = s
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        NSAppearance.current = effectiveAppearance
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor
    }
}

