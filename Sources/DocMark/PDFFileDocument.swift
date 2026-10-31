import AppKit
import PDFKit

/// A read-only PDF. Named for Objective-C so `NSDocumentClass` in Info.plist can find it.
@objc(PDFFileDocument)
final class PDFFileDocument: NSDocument {
    private var bytes = Data()
    private var pdf: PDFDocument?
    private var reader: PDFReaderView?

    /// Gives PDFs the same title bar popover as text files. A PDF never has changes of its own, so
    /// this only renames and moves the file.
    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let reader = PDFReaderView()
        reader.document = pdf
        self.reader = reader
        addWindowController(NSWindowController(window: DocumentWindow(content: reader, focus: reader)))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let pdf = PDFDocument(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        bytes = data
        self.pdf = pdf
        reader?.document = pdf
    }

    /// The original bytes, so saving or duplicating can't change the file.
    override func data(ofType typeName: String) throws -> Data {
        bytes
    }
}

/// PDFKit's view on the app's background, plus the search field PDFKit doesn't include.
final class PDFReaderView: PDFView, NSSearchFieldDelegate, ScrollZooming {
    let searchField = NSSearchField()

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        displayMode = .singlePageContinuous
        autoScales = true
        backgroundColor = Theme.background
        pageShadowsEnabled = false
        searchField.delegate = self
        searchField.placeholderString = "Find"
        searchField.isHidden = true
        addSubview(searchField)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let size = NSSize(width: 240, height: 28)
        let y = isFlipped ? 10 : bounds.maxY - size.height - 10
        searchField.frame = NSRect(origin: NSPoint(x: bounds.maxX - size.width - 24, y: y), size: size)
    }

    func zoom(by factor: CGFloat, at windowPoint: NSPoint?) {
        let mouse = windowPoint.map { convert($0, from: nil) } ?? NSPoint(x: bounds.midX, y: bounds.midY)
        let anchorPage = page(for: mouse, nearest: true)
        let anchor = anchorPage.map { convert(mouse, to: $0) }
        autoScales = false
        scaleFactor = min(max(scaleFactor * factor, 0.25), 8)
        layoutDocumentView()
        // Keeps the spot under the pointer in place.
        if let anchorPage, let anchor, let clip = documentView?.enclosingScrollView?.contentView {
            let moved = clip.convert(convert(anchor, from: anchorPage), from: self)
            let target = clip.convert(mouse, from: self)
            clip.scroll(to: NSPoint(x: clip.bounds.minX + moved.x - target.x, y: clip.bounds.minY + moved.y - target.y))
            documentView?.enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    /// Fills the window's width again after zooming, the size a PDF opens at.
    @objc func fitToWidth(_ sender: Any?) {
        autoScales = true
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        switch (sender as? NSMenuItem)?.tag {
        case NSTextFinder.Action.nextMatch.rawValue: find(backwards: false)
        case NSTextFinder.Action.previousMatch.rawValue: find(backwards: true)
        default:
            searchField.isHidden = false
            window?.makeFirstResponder(searchField)
        }
    }

    /// Selects the next match, wrapping around the document. Returns whether there was one.
    @discardableResult
    func find(backwards: Bool, fromStart: Bool = false) -> Bool {
        guard let document, !searchField.stringValue.isEmpty else { return false }
        let query = searchField.stringValue
        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
        let match = document.findString(query, fromSelection: fromStart ? nil : currentSelection, withOptions: options)
            ?? document.findString(query, fromSelection: nil, withOptions: options)
        setCurrentSelection(match, animate: false)
        if match != nil { scrollSelectionToVisible(nil) }
        return match != nil
    }

    func controlTextDidChange(_ notification: Notification) {
        find(backwards: false, fromStart: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
        case #selector(NSResponder.cancelOperation(_:)):
            searchField.stringValue = ""
            searchField.isHidden = true
            clearSelection()
            window?.makeFirstResponder(self)
        default:
            return false
        }
        return true
    }
}
