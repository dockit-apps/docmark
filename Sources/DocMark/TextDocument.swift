import AppKit
import DocMarkCore

/// A Markdown or other text file. Named for Objective-C so `NSDocumentClass` in Info.plist can find it.
@objc(TextDocument)
final class TextDocument: NSDocument {
    private var loadedText = ""
    private var editor: EditorController?

    /// macOS only offers the title bar popover (rename, tags, move) to documents that save themselves.
    override class var autosavesInPlace: Bool { true }

    /// Editing is the reason to open a file here, and earlier versions stay available through
    /// File > Revert To, so old files and ~/Downloads don't ask for confirmation first.
    override func checkAutosavingSafety() throws {}

    /// Renaming `notes.txt` to `notes.md` changes how it is displayed.
    override var fileURL: URL? {
        didSet { editor?.syntax = syntax }
    }

    private var syntax: DocumentSyntax {
        fileURL.map { DocumentSyntax(fileExtension: $0.pathExtension) } ?? .markdown
    }

    override func makeWindowControllers() {
        let editor = EditorController(
            documentURL: { [unowned self] in fileURL },
            undoManager: { [unowned self] in undoManager }
        )
        let window = DocumentWindow(content: editor.scrollView, focus: editor.textView)
        editor.syntax = syntax
        editor.text = loadedText
        self.editor = editor
        addWindowController(NSWindowController(window: window))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let text = try TextFile.decode(data)
        loadedText = text
        editor?.text = text
    }

    override func data(ofType typeName: String) throws -> Data {
        TextFile.encode(editor?.text ?? loadedText)
    }
}
