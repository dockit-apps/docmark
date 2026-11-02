import AppKit

extension NSDocumentController {
    /// The files opened lately, newest first, leaving out ones moved or deleted since.
    var existingRecentURLs: [URL] {
        recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func openRecent(_ url: URL) {
        openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}

/// Starting or reopening DocMark without a file lists the recent files. Before there are any,
/// it starts a new document instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let files = NSDocumentController.shared.existingRecentURLs
        if files.isEmpty {
            NSDocumentController.shared.newDocument(nil)
        } else {
            RecentFilesWindow.show(files)
        }
        return true
    }
}

/// File > Open Recent, filled each time it opens.
final class RecentFilesMenu: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.existingRecentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(open(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: ""))
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openRecent(url)
    }
}

/// A small window listing recent files. It goes away once any document opens.
final class RecentFilesWindow: NSWindow {
    private(set) static var current: RecentFilesWindow?
    let list = RecentFilesList()

    static func show(_ files: [URL]) {
        let window = current ?? RecentFilesWindow()
        current = window
        window.list.files = files
        window.setContentSize(window.list.preferredSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static func dismiss() {
        current?.close()
    }

    private init() {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = "Recent Files"
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        backgroundColor = Theme.background
        contentView = list
        initialFirstResponder = list
    }
}

/// The rows of the recent files window: name, then folder. Arrow keys or the pointer select,
/// Return or a click opens.
final class RecentFilesList: NSView {
    private static let width: CGFloat = 520
    private static let rowHeight: CGFloat = 46
    private static let inset: CGFloat = 10
    private static let footerHeight: CGFloat = 34

    var files: [URL] = [] {
        didSet {
            selected = 0
            needsDisplay = true
        }
    }
    private(set) var selected = 0

    var preferredSize: NSSize {
        NSSize(width: Self.width, height: Self.inset * 2 + CGFloat(files.count) * Self.rowHeight + Self.footerHeight)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let row = row(at: event)
        if files.indices.contains(row), row != selected { select(row) }
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: event)
        if files.indices.contains(row) { NSDocumentController.shared.openRecent(files[row]) }
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func moveUp(_ sender: Any?) { select(max(selected - 1, 0)) }
    override func moveDown(_ sender: Any?) { select(min(selected + 1, files.count - 1)) }

    override func insertNewline(_ sender: Any?) {
        if files.indices.contains(selected) { NSDocumentController.shared.openRecent(files[selected]) }
    }

    override func cancelOperation(_ sender: Any?) {
        window?.performClose(sender)
    }

    private func select(_ row: Int) {
        selected = row
        needsDisplay = true
    }

    private func row(at event: NSEvent) -> Int {
        Int(floor((convert(event.locationInWindow, from: nil).y - Self.inset) / Self.rowHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingMiddle
        let name: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Theme.text, .paragraphStyle: truncating]
        let folder: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.muted, .paragraphStyle: truncating]
        for (index, url) in files.enumerated() {
            let row = NSRect(x: Self.inset, y: Self.inset + CGFloat(index) * Self.rowHeight, width: bounds.width - Self.inset * 2, height: Self.rowHeight)
            if index == selected {
                Theme.accent.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: row, xRadius: 6, yRadius: 6).fill()
            }
            let text = row.insetBy(dx: 12, dy: 0)
            NSAttributedString(string: url.lastPathComponent, attributes: name)
                .draw(in: NSRect(x: text.minX, y: row.minY + 6, width: text.width, height: 18))
            let path = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            NSAttributedString(string: path, attributes: folder)
                .draw(in: NSRect(x: text.minX, y: row.minY + 25, width: text.width, height: 16))
        }
        let hint = NSAttributedString(string: "⌘N  New document      ⌘O  Open…", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.muted])
        hint.draw(at: NSPoint(x: Self.inset + 12, y: bounds.maxY - Self.footerHeight + (Self.footerHeight - hint.size().height) / 2 - 4))
    }
}
