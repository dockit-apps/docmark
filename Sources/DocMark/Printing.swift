import AppKit
import DocMarkCore

extension NSDocument {
    /// The document's page setup with this print job's settings on top. Pages fill more of the
    /// paper than AppKit's default margins and start at the top.
    func printInfo(with settings: [NSPrintInfo.AttributeKey: Any]) -> NSPrintInfo {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: settings)
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 56
        info.rightMargin = 56
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// Gives the system print panel the same options Preview shows, under the document's name.
    func prepared(_ operation: NSPrintOperation) -> NSPrintOperation {
        operation.jobTitle = displayName
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        return operation
    }
}

/// A copy of a document's text for paper: fully rendered whatever the caret is doing in the window,
/// in the light palette. Laid out at one width and scaled to the page, so any paper size keeps the
/// same line breaks and tables.
final class PrintView: NSTextView {
    private static let layoutWidth: CGFloat = 700
    private let storage = NSTextStorage(string: "")
    private let manager = MarkdownLayoutManager()

    init(text: String, syntax: DocumentSyntax, documentURL: URL?) {
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: Self.layoutWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        appearance = NSAppearance(named: .aqua)
        drawsBackground = false
        isEditable = false

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        let renderer = MarkdownRenderer(storage: storage, layoutManager: manager, documentURL: { documentURL })
        renderer.syntax = syntax
        renderer.textChanged(caret: nil)
        manager.ensureLayout(for: container)
        setFrameSize(NSSize(width: Self.layoutWidth, height: max(ceil(manager.contentBottom), 1)))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override init(frame: NSRect, textContainer: NSTextContainer?) { super.init(frame: frame, textContainer: textContainer) }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        manager.drawTablesAndImages(in: rect, origin: textContainerOrigin, clipSlack: 8)
    }

    /// Lets a page end early rather than cut an image in half.
    override var heightAdjustLimit: CGFloat { 0.9 }

    override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat, bottom oldBottom: CGFloat, limit bottomLimit: CGFloat) {
        super.adjustPageHeightNew(newBottom, top: oldTop, bottom: oldBottom, limit: bottomLimit)
        let moved = manager.pageBreak(atOrAbove: newBottom.pointee)
        // Something taller than the page has to be cut after all.
        if moved > oldTop { newBottom.pointee = moved }
    }
}
