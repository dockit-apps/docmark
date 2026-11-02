import AppKit
import DocMarkCore

/// Every file is one of three types, chosen by extension. This is also what lets `dm` open text
/// files whose extensions macOS has never heard of, such as `.toml` or a `Makefile`.
final class DocumentController: NSDocumentController {
    static let markdownType = "net.daringfireball.markdown"
    static let textType = "public.plain-text"
    static let pdfType = "com.adobe.pdf"

    override func addDocument(_ document: NSDocument) {
        super.addDocument(document)
        RecentFilesWindow.dismiss()
    }

    override func typeForContents(of url: URL) throws -> String {
        let name = url.pathExtension.lowercased()
        if name == "pdf" { return Self.pdfType }
        return DocumentSyntax.markdownExtensions.contains(name) ? Self.markdownType : Self.textType
    }
}

/// The window every document opens in, with the same frame and background.
final class DocumentWindow: NSWindow {
    private weak var zoomTarget: (NSView & ScrollZooming)?

    init(content: NSView, focus: NSView & ScrollZooming) {
        zoomTarget = focus
        // Documents read top to bottom, so windows use most of the screen's height.
        let height = (NSScreen.main?.visibleFrame.height ?? 800) * 0.9
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        backgroundColor = Theme.background
        minSize = NSSize(width: 420, height: 320)
        contentView = content
        center()
        initialFirstResponder = focus
    }

    /// Scroll events go straight to the deepest view under the pointer, and scroll views inside
    /// PDFKit keep them, so Command-scroll is caught here before any view can.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let factor = event.commandScrollZoom, let zoomTarget {
            zoomTarget.zoom(by: factor, at: event.locationInWindow)
        } else {
            super.sendEvent(event)
        }
    }
}
