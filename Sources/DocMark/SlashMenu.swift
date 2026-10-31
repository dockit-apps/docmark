import AppKit
import DocMarkCore

/// The list under the caret while a slash command is typed. The panel never takes focus, so
/// typing stays in the text view, which forwards the arrow keys, Return and Escape here.
final class SlashMenu {
    private(set) var commands: [SlashCommand] = []
    private(set) var selected = 0
    private(set) var isOpen = false
    var onPick: ((SlashCommand) -> Void)?

    private lazy var list = SlashMenuList(owner: self)
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = list
        return panel
    }()

    var selectedCommand: SlashCommand? { commands.indices.contains(selected) ? commands[selected] : nil }

    /// `caret` is the screen rectangle of the `/`.
    func show(_ commands: [SlashCommand], below caret: NSRect, in parent: NSWindow) {
        if commands != self.commands { selected = 0 }
        self.commands = commands
        let size = NSSize(width: SlashMenuList.width, height: CGFloat(commands.count) * SlashMenuList.rowHeight + SlashMenuList.inset * 2)
        var origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 4)
        if let screen = parent.screen, origin.y < screen.visibleFrame.minY { origin.y = caret.maxY + 4 }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        list.needsDisplay = true
        if !isOpen { parent.addChildWindow(panel, ordered: .above) }
        isOpen = true
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveSelection(by offset: Int) {
        guard !commands.isEmpty else { return }
        select((selected + offset + commands.count) % commands.count)
    }

    fileprivate func select(_ index: Int) {
        selected = index
        list.needsDisplay = true
    }

    fileprivate func pick(_ index: Int) {
        guard commands.indices.contains(index) else { return }
        onPick?(commands[index])
    }
}

private final class SlashMenuList: NSView {
    static let width: CGFloat = 260
    static let rowHeight: CGFloat = 28
    static let inset: CGFloat = 5

    private unowned let owner: SlashMenu

    init(owner: SlashMenu) {
        self.owner = owner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let row = row(at: event)
        if owner.commands.indices.contains(row), row != owner.selected { owner.select(row) }
    }

    override func mouseDown(with event: NSEvent) {
        owner.pick(row(at: event))
    }

    private func row(at event: NSEvent) -> Int {
        Int(floor((convert(event.locationInWindow, from: nil).y - Self.inset) / Self.rowHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Theme.raised.setFill()
        outline.fill()
        Theme.border.setStroke()
        outline.stroke()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Theme.text]
        let hint: [NSAttributedString.Key: Any] = [.font: Theme.codeFont(size: 12), .foregroundColor: Theme.muted]
        for (index, command) in owner.commands.enumerated() {
            let row = NSRect(x: Self.inset, y: Self.inset + CGFloat(index) * Self.rowHeight, width: bounds.width - Self.inset * 2, height: Self.rowHeight)
            if index == owner.selected {
                Theme.accent.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
            }
            let name = NSAttributedString(string: command.title, attributes: title)
            name.draw(at: NSPoint(x: row.minX + 8, y: row.midY - name.size().height / 2))
            let syntax = NSAttributedString(string: command.hint, attributes: hint)
            syntax.draw(at: NSPoint(x: row.maxX - 8 - syntax.size().width, y: row.midY - syntax.size().height / 2))
        }
    }
}
