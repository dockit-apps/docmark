import AppKit
import DocMarkCore

/// A text view with a centered reading column; Command-click follows links and a click in a
/// table opens its source at that cell. Command-scroll and pinching zoom the page.
final class MarkdownTextView: NSTextView, ScrollZooming {
    private static let verticalInset: CGFloat = 24
    private static let minimumMargin: CGFloat = 32
    var layoutSource: (() -> MarkdownLayout)?
    var columnWidthChanged: (() -> Void)?

    override var textContainerOrigin: NSPoint {
        let width = textContainer?.size.width ?? 0
        return NSPoint(x: max((bounds.width - width) / 2, 0), y: Self.verticalInset)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = min(Theme.columnWidth, newSize.width - Self.minimumMargin * 2)
        if let container = textContainer, container.size.width != width {
            container.size = NSSize(width: max(width, 100), height: .greatestFiniteMagnitude)
            columnWidthChanged?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        if let location = (layoutManager as? MarkdownLayoutManager)?.tableCellLocation(at: inContainer) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: location, length: 0))
            return
        }
        if event.modifierFlags.contains(.command), let url = linkURL(at: event) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    @objc func zoomIn(_ sender: Any?) {
        zoom(by: 1.25, at: nil)
    }

    @objc func zoomOut(_ sender: Any?) {
        zoom(by: 0.8, at: nil)
    }

    @objc func fitToWidth(_ sender: Any?) {
        enclosingScrollView?.magnification = 1
    }

    /// Text rewraps when the zoom changes, so what stays in place is the line under the pointer,
    /// or at the top of the window when there is no pointer to follow.
    func zoom(by factor: CGFloat, at windowPoint: NSPoint?) {
        guard let scrollView = enclosingScrollView, let manager = layoutManager, let container = textContainer else { return }
        let clip = scrollView.contentView
        let anchor = windowPoint.map { convert($0, from: nil) } ?? clip.bounds.origin
        let index = characterIndexForInsertion(at: anchor)
        let offset = (anchor.y - clip.bounds.minY) * scrollView.magnification
        scrollView.magnification = factor * scrollView.magnification
        guard index < textStorage?.length ?? 0 else { return }
        manager.ensureLayout(for: container)
        let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: index), effectiveRange: nil)
        let top = line.midY + textContainerOrigin.y - offset / scrollView.magnification
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: top), size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private func linkURL(at event: NSEvent) -> URL? {
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        for span in layoutSource?().spans ?? [] where NSLocationInRange(index, span.range) {
            guard case .link(let destination?) = span.kind, let url = URL(string: destination),
                  ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { continue }
            return url
        }
        return nil
    }
}
