import AppKit
import Foundation
import PDFKit
import Testing
@testable import DocMark

@MainActor
private final class Harness {
    let undo = UndoManager()
    let editor: EditorController
    let window: NSWindow

    init(_ text: String = "") {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let manager = undo
        editor = EditorController(documentURL: { nil }, undoManager: { manager })
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 780), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.scrollView
        window.makeFirstResponder(editor.textView)
        editor.text = text
    }

    var view: NSTextView { editor.textView }
    var text: String { view.string }

    func type(_ string: String) {
        for character in string {
            if character == "\n" { press(#selector(NSResponder.insertNewline(_:))) } else { view.insertText(String(character), replacementRange: view.selectedRange()) }
        }
    }

    func press(_ selector: Selector) { view.doCommand(by: selector) }
    func move(to location: Int) { view.setSelectedRange(NSRange(location: location, length: 0)) }
    func isHidden(_ location: Int) -> Bool { view.textStorage!.attribute(.dmHidden, at: location, effectiveRange: nil) != nil }
    func font(_ location: Int) -> NSFont { view.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont }
}

@MainActor @Test func typedHeadingRendersOnEnter() {
    let editor = Harness()
    editor.type("### Title")
    #expect(editor.font(5).pointSize == 21)
    #expect(!editor.isHidden(0))
    editor.type("\nbody")
    #expect(editor.text == "### Title\nbody")
    #expect(editor.isHidden(0) && editor.isHidden(3))
    #expect(!editor.isHidden(4))
    #expect(editor.font(11).pointSize == 16)
    editor.move(to: 6)
    #expect(!editor.isHidden(0))
}

@MainActor @Test func bareHashesThenEnterStartAHeading() {
    let editor = Harness()
    editor.type("###\nTitle\nbody")
    #expect(editor.text == "### Title\nbody")
    #expect(editor.isHidden(0))
    #expect(editor.font(5).pointSize == 21)
}

@MainActor @Test func inlineSyntaxHidesWhenCaretLeaves() {
    let editor = Harness()
    editor.type("a **b** c")
    #expect(editor.isHidden(2) && editor.isHidden(6))
    editor.move(to: 5)
    #expect(!editor.isHidden(2))
    editor.move(to: 9)
    #expect(editor.isHidden(2))
    #expect(editor.font(4).fontDescriptor.symbolicTraits.contains(.bold))
    #expect(!editor.font(0).fontDescriptor.symbolicTraits.contains(.bold))
}

@MainActor @Test func listsContinueAndEnd() {
    let editor = Harness()
    editor.type("- a\nb\n")
    #expect(editor.text == "- a\n- b\n- ")
    #expect(editor.isHidden(4))
    #expect(!editor.isHidden(8))
    editor.type("\n")
    #expect(editor.text == "- a\n- b\n")
}

@MainActor @Test func backspaceRemovesHiddenBulletWhole() {
    let editor = Harness()
    editor.type("- ")
    #expect(!editor.isHidden(0))
    editor.press(#selector(NSResponder.deleteBackward(_:)))
    #expect(editor.text == "")
}

@MainActor private func pressCommandBackspace(_ editor: Harness) throws {
    let event = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
        characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51
    ))
    editor.view.keyDown(with: event)
}

@MainActor @Test func commandBackspaceDeletesWholeLine() throws {
    let editor = Harness("one\ntwo\nthree\n")
    editor.move(to: 5)
    try pressCommandBackspace(editor)
    #expect(editor.text == "one\nthree\n")
    #expect(editor.view.selectedRange().location == 4)
}

@MainActor @Test func commandBackspaceOnLastLineLeavesNoEmptyLine() throws {
    let editor = Harness("one\r\ntwo")
    editor.move(to: 7)
    try pressCommandBackspace(editor)
    #expect(editor.text == "one")
    #expect(editor.view.selectedRange().location == 3)
}

@MainActor @Test func commandBackspaceEdgeCases() throws {
    let empty = Harness("")
    try pressCommandBackspace(empty)
    #expect(empty.text == "")

    let only = Harness("only")
    only.move(to: 2)
    try pressCommandBackspace(only)
    #expect(only.text == "")

    let blank = Harness("a\n\nb")
    blank.move(to: 2)
    try pressCommandBackspace(blank)
    #expect(blank.text == "a\nb")

    let selected = Harness("one two\nthree")
    selected.view.setSelectedRange(NSRange(location: 4, length: 3))
    try pressCommandBackspace(selected)
    #expect(selected.text == "one \nthree")
}

@MainActor @Test func commandBackspaceRemovesHiddenHeadingSyntaxAndUndoes() throws {
    let editor = Harness("### Title\nbody\n")
    editor.move(to: 12)
    #expect(editor.isHidden(0))
    editor.move(to: 5)
    try pressCommandBackspace(editor)
    #expect(editor.text == "body\n")
    editor.undo.undo()
    #expect(editor.text == "### Title\nbody\n")
}

@MainActor @Test func tableDrawsAsGridUntilCaretEntersIt() throws {
    let source = "| a | b |\n|---|---|\n| 1 | **2** |\n\nend"
    let editor = Harness(source)
    editor.move(to: (source as NSString).length)
    let grid = try #require(editor.view.textStorage!.attribute(.dmTable, at: 0, effectiveRange: nil) as? TableGrid)
    #expect(grid.height > 40)
    #expect(editor.isHidden(0))
    #expect(editor.text == source)
    editor.move(to: 3)
    #expect(editor.view.textStorage!.attribute(.dmTable, at: 0, effectiveRange: nil) == nil)
    #expect(!editor.isHidden(0))
    editor.move(to: (source as NSString).length)
    #expect(editor.isHidden(0))
}

@MainActor @Test func tableCellClickFindsItsSourceLocation() throws {
    let source = "intro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nend"
    let editor = Harness(source)
    editor.move(to: (source as NSString).length)
    let manager = try #require(editor.view.layoutManager as? MarkdownLayoutManager)
    let grid = try #require(editor.view.textStorage!.attribute(.dmTable, at: 7, effectiveRange: nil) as? TableGrid)
    manager.ensureLayout(for: editor.view.textContainer!)
    let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: 16), effectiveRange: nil)
    let top = line.minY + MarkdownLayoutManager.tableMargin
    #expect(manager.tableCellLocation(at: NSPoint(x: 2, y: top + 2)) == 9)
    #expect(manager.tableCellLocation(at: NSPoint(x: grid.width - 2, y: top + grid.height - 2)) == 33)
    #expect(manager.tableCellLocation(at: NSPoint(x: grid.width + 5, y: top + 2)) == nil)
}

@MainActor @Test func tableAtEndWithoutNewlineStillRendersAndKeepsItsRoom() throws {
    let source = "# T\n\n| a | b |\n|---|---|\n| 1 | 2 |"
    let editor = Harness(source)
    editor.move(to: 0)
    let grid = try #require(editor.view.textStorage!.attribute(.dmTable, at: 5, effectiveRange: nil) as? TableGrid)
    let manager = try #require(editor.view.layoutManager)
    manager.ensureLayout(for: editor.view.textContainer!)
    #expect(manager.usedRect(for: editor.view.textContainer!).height > grid.height)
}

@Test func tableColumnsShareWidthWhenTooWide() {
    #expect(TableGrid.fit([50, 100], into: 400) == [50, 100])
    #expect(TableGrid.fit([50, 500, 900], into: 450) == [50, 200, 200])
}

@MainActor @Test func slashMenuFiltersAndInsertsWithReturn() {
    let editor = Harness()
    editor.type("/")
    #expect(editor.editor.slashMenu.isOpen)
    #expect(editor.editor.slashMenu.commands.count > 10)
    editor.type("hea")
    #expect(editor.editor.slashMenu.commands.count == 3)
    // Undo groups close when the event loop turns, which separates each key press in the app.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    editor.press(#selector(NSResponder.moveDown(_:)))
    editor.press(#selector(NSResponder.insertNewline(_:)))
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    #expect(editor.text == "## ")
    #expect(editor.view.selectedRange().location == 3)
    #expect(!editor.editor.slashMenu.isOpen)
    editor.undo.undo()
    #expect(editor.text == "/hea")
    editor.undo.redo()
    #expect(editor.text == "## ")
    editor.type("Title")
    #expect(editor.font(5).pointSize == 26)
}

@MainActor @Test func slashMenuStaysOutOfTheWay() {
    let path = Harness()
    path.type("/usr/")
    #expect(!path.editor.slashMenu.isOpen)
    path.type("\nnext")
    #expect(path.text == "/usr/\nnext")

    let unknown = Harness()
    unknown.type("/zzz")
    #expect(!unknown.editor.slashMenu.isOpen)

    let sentence = Harness()
    sentence.type("a /h")
    #expect(!sentence.editor.slashMenu.isOpen)

    let code = Harness("```\n\n```")
    code.move(to: 4)
    code.type("/")
    #expect(!code.editor.slashMenu.isOpen)

    let escaped = Harness()
    escaped.type("/he")
    escaped.press(#selector(NSResponder.cancelOperation(_:)))
    #expect(!escaped.editor.slashMenu.isOpen)
    escaped.type("a")
    #expect(!escaped.editor.slashMenu.isOpen)
    #expect(escaped.text == "/hea")
    escaped.type("\n")
    #expect(escaped.text == "/hea\n")

    let moved = Harness("first\n")
    moved.move(to: 6)
    moved.type("/")
    #expect(moved.editor.slashMenu.isOpen)
    moved.move(to: 0)
    #expect(!moved.editor.slashMenu.isOpen)
}

@MainActor @Test func slashTableThenTabFillsCellsAndAddsARow() {
    let editor = Harness()
    editor.type("/table\n")
    #expect(editor.text == "|  |  |\n|---|---|\n|  |  |")
    editor.type("a")
    editor.press(#selector(NSResponder.insertTab(_:)))
    editor.type("b")
    editor.press(#selector(NSResponder.insertTab(_:)))
    editor.type("c")
    editor.press(#selector(NSResponder.insertBacktab(_:)))
    #expect(editor.view.selectedRange().location == 7)
    editor.press(#selector(NSResponder.insertTab(_:)))
    editor.press(#selector(NSResponder.insertTab(_:)))
    editor.press(#selector(NSResponder.insertTab(_:)))
    editor.type("d")
    #expect(editor.text == "| a | b |\n|---|---|\n| c |  |\n| d |  |")
}

@MainActor @Test func slashCodeAndDividerLandCleanly() {
    let code = Harness()
    code.type("/code\n")
    #expect(code.text == "```\n\n```")
    #expect(code.view.selectedRange().location == 4)

    let divider = Harness("text\n")
    divider.move(to: 5)
    divider.type("/hr\n")
    #expect(divider.text == "text\n\n---\n")
    #expect(divider.view.selectedRange().location == 10)
    #expect(divider.font(0).pointSize == 16)
}

@MainActor @Test func codeBlockColoursFollowTheLanguage() {
    let editor = Harness("```c\nint x;\n```\n\nend")
    let color = { editor.view.textStorage!.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor }
    #expect(color() == Theme.accent)
    editor.move(to: 4)
    editor.view.insertText("x", replacementRange: editor.view.selectedRange())
    #expect(editor.text.hasPrefix("```cx\n"))
    let plain = editor.view.textStorage!.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
    #expect(plain == Theme.text)
}

@MainActor @Test func fenceClosesItselfAndEnterStaysPlainInside() {
    let editor = Harness()
    editor.type("```swift\n")
    #expect(editor.text == "```swift\n\n```")
    #expect(editor.view.selectedRange().location == 9)
    editor.type("- a\n")
    #expect(editor.text == "```swift\n- a\n\n```")
    editor.view.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(!editor.isHidden(0))
    editor.view.setSelectedRange(NSRange(location: 0, length: 3))
    #expect(editor.isHidden(0))
}

@MainActor @Test func undoRestoresTextAndStyling() {
    let editor = Harness("# One\n\nx")
    editor.move(to: 8)
    editor.undo.beginUndoGrouping()
    editor.view.insertText("y", replacementRange: editor.view.selectedRange())
    editor.undo.endUndoGrouping()
    #expect(editor.text == "# One\n\nxy")
    editor.view.breakUndoCoalescing()
    editor.undo.undo()
    #expect(editor.text == "# One\n\nx")
    #expect(editor.isHidden(0))
}

@MainActor @Test func documentSavesUntouchedFileByteForByte() throws {
    let bytes = Data("\u{FEFF}# Title\r\n\r\n**b** 😀\n\n- a\n- [x] b\n\nno newline".utf8)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("a.md"), target = directory.appendingPathComponent("b.md")
    try bytes.write(to: source)
    _ = NSApplication.shared
    let document = try TextDocument(contentsOf: source, ofType: "net.daringfireball.markdown")
    document.makeWindowControllers()
    try document.write(to: target, ofType: "net.daringfireball.markdown")
    #expect(try Data(contentsOf: target) == bytes)
    document.close()
}

@MainActor @Test func typingMarksDocumentEditedAndSaveWritesIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("a.md")
    try Data("# Title\n".utf8).write(to: file)
    _ = NSApplication.shared
    let document = try TextDocument(contentsOf: file, ofType: "net.daringfireball.markdown")
    document.makeWindowControllers()
    let window = try #require(document.windowControllers.first?.window)
    let view = try #require(window.initialFirstResponder as? NSTextView)
    #expect(window.contentView!.frame.maxY <= window.contentLayoutRect.maxY)
    #expect(!document.isDocumentEdited)
    view.setSelectedRange(NSRange(location: 8, length: 0))
    view.insertText("body", replacementRange: view.selectedRange())
    view.breakUndoCoalescing()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    #expect(document.isDocumentEdited)
    document.save(nil)
    let deadline = Date().addingTimeInterval(3)
    while document.isDocumentEdited, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    #expect(!document.isDocumentEdited)
    #expect(try String(contentsOf: file, encoding: .utf8) == "# Title\nbody")
    document.close()
}

@MainActor @Test func documentCanBeRenamedAndMovedWithItsEditsKept() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = directory.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("a.md"), moved = folder.appendingPathComponent("b.md")
    try Data("# Title\n".utf8).write(to: file)
    _ = NSApplication.shared
    let document = try TextDocument(contentsOf: file, ofType: "net.daringfireball.markdown")
    document.makeWindowControllers()
    defer { document.close() }
    let window = try #require(document.windowControllers.first?.window)
    let view = try #require(window.initialFirstResponder as? NSTextView)
    #expect(TextDocument.autosavesInPlace)
    #expect(window.representedURL?.standardizedFileURL == file.standardizedFileURL)

    view.setSelectedRange(NSRange(location: 8, length: 0))
    view.insertText("body", replacementRange: view.selectedRange())
    view.breakUndoCoalescing()
    try await document.move(to: moved)
    #expect(document.fileURL?.standardizedFileURL == moved.standardizedFileURL)
    #expect(window.title == "b.md")
    #expect(!FileManager.default.fileExists(atPath: file.path))
    try await document.autosave(withImplicitCancellability: false)
    #expect(!document.hasUnautosavedChanges)
    #expect(try String(contentsOf: moved, encoding: .utf8) == "# Title\nbody")
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@MainActor @Test func plainTextHasNoMarkdownBehaviour() {
    let editor = Harness()
    editor.editor.syntax = .prose
    editor.type("# not a heading **x**\n- a\n/h")
    #expect(editor.text == "# not a heading **x**\n- a\n/h")
    #expect(!editor.isHidden(0))
    #expect(!editor.editor.slashMenu.isOpen)
    #expect(editor.font(5).pointSize == 16)
    #expect(editor.font(5).familyName == Theme.bodyFont.familyName)
    editor.type("\nb")
    #expect(editor.text.hasSuffix("/h\nb"))
}

@MainActor @Test func codeFilesAreMonospacedAndColoured() {
    let editor = Harness()
    editor.editor.syntax = .code(language: "c")
    editor.type("int x;\n")
    #expect(editor.font(0).isFixedPitch)
    #expect(editor.view.textStorage!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == Theme.accent)
    #expect(editor.view.typingAttributes[.font] as? NSFont == Theme.codeFont(size: 14))
}

@MainActor @Test func filesOpenByExtensionAndRenamingChangesTheDisplay() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.txt"), renamed = folder.appendingPathComponent("a.md")
    try Data("# Title\n\nbody".utf8).write(to: file)
    _ = NSApplication.shared
    let controller = DocumentController()
    #expect(try controller.typeForContents(of: file) == DocumentController.textType)
    #expect(try controller.typeForContents(of: renamed) == DocumentController.markdownType)
    #expect(try controller.typeForContents(of: folder.appendingPathComponent("Makefile")) == DocumentController.textType)
    #expect(try controller.typeForContents(of: folder.appendingPathComponent("a.PDF")) == DocumentController.pdfType)

    let document = try TextDocument(contentsOf: file, ofType: DocumentController.textType)
    document.makeWindowControllers()
    defer { document.close() }
    let view = try #require(document.windowControllers.first?.window?.initialFirstResponder as? NSTextView)
    view.setSelectedRange(NSRange(location: 13, length: 0))
    #expect(view.textStorage!.attribute(.dmHidden, at: 0, effectiveRange: nil) == nil)
    try await document.move(to: renamed)
    #expect(view.textStorage!.attribute(.dmHidden, at: 0, effectiveRange: nil) != nil)
    #expect(try Data(contentsOf: renamed) == Data("# Title\n\nbody".utf8))
}

@MainActor @Test func nonUTF8TextIsRefusedAndLeftAlone() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.txt")
    let bytes = Data([0x66, 0xFF, 0x6F])
    try bytes.write(to: file)
    #expect(throws: (any Error).self) { try TextDocument(contentsOf: file, ofType: DocumentController.textType) }
    #expect(try Data(contentsOf: file) == bytes)
}

private func samplePDF(_ pages: [String]) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 400, height: 500)
    let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    for page in pages {
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: page, attributes: [.font: NSFont.systemFont(ofSize: 20)]).draw(at: NSPoint(x: 40, y: 400))
        context.endPDFPage()
    }
    context.closePDF()
    NSGraphicsContext.current = nil
    return data as Data
}

@MainActor @Test func pdfOpensReadOnlyAndSavingKeepsItsBytes() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.pdf"), copy = folder.appendingPathComponent("b.pdf")
    let bytes = samplePDF(["first page", "second page"])
    try bytes.write(to: file)
    _ = NSApplication.shared
    let document = try PDFFileDocument(contentsOf: file, ofType: DocumentController.pdfType)
    document.makeWindowControllers()
    defer { document.close() }
    let reader = try #require(document.windowControllers.first?.window?.contentView as? PDFReaderView)
    #expect(reader.document?.pageCount == 2)
    #expect(!document.isDocumentEdited)
    try document.write(to: copy, ofType: DocumentController.pdfType)
    #expect(try Data(contentsOf: copy) == bytes)

    let corrupt = folder.appendingPathComponent("c.pdf")
    try Data("not a pdf".utf8).write(to: corrupt)
    #expect(throws: (any Error).self) { try PDFFileDocument(contentsOf: corrupt, ofType: DocumentController.pdfType) }
}

@MainActor @Test func pdfSearchFindsAndWraps() throws {
    let reader = PDFReaderView()
    reader.document = PDFDocument(data: samplePDF(["first needle", "second needle"]))
    reader.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    reader.searchField.stringValue = "NEEDLE"
    #expect(reader.find(backwards: false, fromStart: true))
    let first = reader.currentSelection?.pages.first
    #expect(reader.document?.index(for: first!) == 0)
    #expect(reader.find(backwards: false))
    #expect(reader.document?.index(for: reader.currentSelection!.pages.first!) == 1)
    #expect(reader.find(backwards: false))
    #expect(reader.document?.index(for: reader.currentSelection!.pages.first!) == 0)
    reader.searchField.stringValue = "missing"
    #expect(!reader.find(backwards: false, fromStart: true))
}

private func scroll(_ lines: Int32, command: Bool = true, over window: NSWindow) throws -> NSEvent {
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0))
    event.flags = command ? .maskCommand : []
    event.location = NSPoint(x: window.frame.midX, y: NSScreen.screens[0].frame.maxY - window.frame.midY)
    return try #require(NSEvent(cgEvent: event))
}

// These go through DocumentWindow.sendEvent, the path a real scroll takes. Calling a view's own
// scrollWheel would pass even when PDFKit's inner views keep the event.
@MainActor @Test func commandScrollThroughTheWindowZoomsAPDF() throws {
    _ = NSApplication.shared
    let reader = PDFReaderView()
    let window = DocumentWindow(content: reader, focus: reader)
    reader.document = PDFDocument(data: samplePDF(["first", "second", "third"]))
    window.layoutIfNeeded()
    reader.layoutDocumentView()
    let start = reader.scaleFactor

    window.sendEvent(try scroll(5, over: window))
    #expect(reader.scaleFactor > start * 1.3)
    #expect(!reader.autoScales)
    let zoomed = reader.scaleFactor
    window.sendEvent(try scroll(-3, over: window))
    #expect(reader.scaleFactor < zoomed)
    for _ in 0..<60 { window.sendEvent(try scroll(-3, over: window)) }
    #expect(reader.scaleFactor >= 0.25)

    let settled = reader.scaleFactor
    window.sendEvent(try scroll(3, command: false, over: window))
    #expect(reader.scaleFactor == settled)
    reader.fitToWidth(nil)
    #expect(reader.autoScales)
}

@MainActor @Test func windowsOpenTallAndFitTheScreen() throws {
    _ = NSApplication.shared
    let reader = PDFReaderView()
    let window = DocumentWindow(content: reader, focus: reader)
    let screen = try #require(NSScreen.main?.visibleFrame)
    #expect(window.frame.height > screen.height * 0.85)
    #expect(window.frame.height <= screen.height)
    #expect(screen.contains(window.frame))
}

@MainActor @Test func pdfZoomKeepsThePointUnderThePointer() throws {
    _ = NSApplication.shared
    let reader = PDFReaderView()
    let window = DocumentWindow(content: reader, focus: reader)
    reader.document = PDFDocument(data: samplePDF(["first", "second"]))
    window.layoutIfNeeded()
    reader.layoutDocumentView()
    let mouse = NSPoint(x: 500, y: 400)
    let page = try #require(reader.page(for: mouse, nearest: true))
    let spot = reader.convert(mouse, to: page)
    reader.zoom(by: 1.5, at: reader.convert(mouse, to: nil))
    let moved = reader.convert(spot, from: page)
    #expect(abs(moved.x - mouse.x) < 2 && abs(moved.y - mouse.y) < 2)
}

@MainActor @Test func commandScrollThroughTheWindowZoomsTextWithoutTouchingIt() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.md")
    let source = String(repeating: "A line of text that is long enough to wrap when the page zooms in. ", count: 200)
    try Data(source.utf8).write(to: file)
    _ = NSApplication.shared
    let document = try TextDocument(contentsOf: file, ofType: DocumentController.markdownType)
    document.makeWindowControllers()
    defer { document.close() }
    let window = try #require(document.windowControllers.first?.window)
    let view = try #require(window.initialFirstResponder as? MarkdownTextView)
    let scrollView = try #require(view.enclosingScrollView)
    window.layoutIfNeeded()

    window.sendEvent(try scroll(5, over: window))
    #expect(scrollView.magnification > 1.3)
    #expect(view.string == source)
    #expect(view.textContainer!.size.width < Theme.columnWidth)
    for _ in 0..<30 { window.sendEvent(try scroll(3, over: window)) }
    #expect(scrollView.magnification == 3)
    for _ in 0..<60 { window.sendEvent(try scroll(-3, over: window)) }
    #expect(scrollView.magnification == 0.5)
    #expect(view.textContainer!.size.width == Theme.columnWidth)
    view.fitToWidth(nil)
    #expect(scrollView.magnification == 1)
    view.zoomIn(nil)
    #expect(scrollView.magnification == 1.25)
}

@MainActor @Test func largeDocumentStaysResponsive() {
    let block = "## Heading\n\nSome **bold** and *italic* text with `code`.\n\n- item one\n- item two\n\n"
    let text = String(repeating: block, count: 1200)
    let editor = Harness(text)
    editor.move(to: text.utf16.count)
    let clock = ContinuousClock()
    let typing = clock.measure { editor.view.insertText("x", replacementRange: editor.view.selectedRange()) }
    let moving = clock.measure { editor.move(to: 5) }
    print("LARGE \(text.utf16.count) chars: keystroke \(typing), caret \(moving)")
    #expect(typing < .milliseconds(1000))
}

@MainActor @Test func rendersSnapshot() throws {
    guard let path = ProcessInfo.processInfo.environment["DOCMARK_SNAPSHOT_MD"] else { return }
    let text = try String(contentsOfFile: path, encoding: .utf8)
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let url = URL(fileURLWithPath: path)
    let editor = EditorController(documentURL: { url }, undoManager: { nil })
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 1500), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = editor.scrollView
    editor.text = text
    let view = editor.textView
    view.layoutManager!.ensureLayout(for: view.textContainer!)
    view.setFrameSize(NSSize(width: 960, height: 1500))
    view.setSelectedRange(NSRange(location: 0, length: 0))
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path + ".png"))
}

@MainActor private func printedPDF(of document: NSDocument) throws -> PDFDocument {
    let url = try temporaryFolder().appendingPathComponent("printed.pdf")
    let operation = try document.printOperation(withSettings: [
        .jobDisposition: NSPrintInfo.JobDisposition.save, .jobSavingURL: url,
    ])
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    #expect(operation.run())
    return try #require(PDFDocument(url: url))
}

@MainActor private func textDocument(_ text: String, named name: String = "note.md") throws -> TextDocument {
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let document = TextDocument()
    document.fileURL = try temporaryFolder().appendingPathComponent(name)
    try document.read(from: Data(text.utf8), ofType: DocumentController.markdownType)
    return document
}

private func pixels(of page: PDFPage) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    page.thumbnail(of: NSSize(width: 600, height: 800), for: .mediaBox).draw(in: NSRect(x: 0, y: 0, width: 600, height: 800))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

@MainActor @Test func fileMenuHasPrintExportAndOpenRecent() throws {
    _ = NSApplication.shared
    let file = try #require(MainMenu.make().item(withTitle: "File")?.submenu)
    let print = try #require(file.item(withTitle: "Print…"))
    #expect(print.keyEquivalent == "p" && print.keyEquivalentModifierMask == .command)
    #expect(print.action == #selector(NSDocument.printDocument(_:)))
    #expect(file.item(withTitle: "Export as PDF…")?.action == #selector(NSDocument.saveToPDF(_:)))
    #expect(file.item(withTitle: "Open Recent")?.submenu?.delegate is RecentFilesMenu)
}

@MainActor @Test func markdownPrintsRenderedInDarkInkOnWhitePaper() throws {
    let document = try textDocument("# Title\n\n**bold** and `code`\n\n| Left | Right |\n|---|---|\n| one | two |\n\n```swift\nlet x = 1\n```\n")
    document.makeWindowControllers()
    let page = try #require(printedPDF(of: document).page(at: 0))
    let text = try #require(page.string)
    for word in ["Title", "bold", "code", "Left", "two", "let x = 1"] { #expect(text.contains(word)) }
    for syntax in ["#", "**", "`", "|", "---"] { #expect(!text.contains(syntax)) }

    let rep = pixels(of: page)
    #expect(rep.colorAt(x: 5, y: 5)!.brightnessComponent > 0.99)
    var darkest: CGFloat = 1
    var charcoal = 0
    for y in stride(from: 0, to: 800, by: 2) {
        for x in stride(from: 0, to: 600, by: 2) {
            let brightness = rep.colorAt(x: x, y: y)!.brightnessComponent
            darkest = min(darkest, brightness)
            if brightness < 0.2 { charcoal += 1 }
        }
    }
    #expect(darkest < 0.4)
    #expect(charcoal < 800, "the screen's dark background must stay off the paper")

    let window = try #require(document.windowControllers.first?.window)
    var background: NSColor?
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
        background = Theme.background.usingColorSpace(.sRGB)
    }
    #expect(try #require(background).brightnessComponent < 0.2)
}

@MainActor @Test func longTablePrintsAcrossPagesWithEveryRowOnOnePage() throws {
    let rows = (1...150).map { "| row\($0)x | value |" }.joined(separator: "\n")
    let printed = try printedPDF(of: textDocument("Intro\n\n| Name | Value |\n|---|---|\n\(rows)\n\nOutro\n"))
    #expect(printed.pageCount > 1)
    let pages = (0..<printed.pageCount).map { printed.page(at: $0)?.string ?? "" }
    for row in 1...150 {
        #expect(pages.filter { $0.contains("row\(row)x") }.count == 1, "row \(row)")
    }
    #expect(pages.last?.contains("Outro") == true)
}

@MainActor @Test func tableEndingTheFileIsPrintedWhole() throws {
    let text = try #require(printedPDF(of: textDocument("Intro\n\n| A | B |\n|---|---|\n| first | second |\n| last | cell |")).page(at: 0)?.string)
    #expect(text.contains("last") && text.contains("cell"))
}

@MainActor @Test func otherTextUnsavedEditsAndEmptyFilesPrint() throws {
    #expect(try printedPDF(of: textDocument("**stays** as typed", named: "notes.txt")).page(at: 0)?.string?.contains("**stays**") == true)
    #expect(try printedPDF(of: textDocument("")).pageCount == 1)
    let edited = try textDocument("saved")
    edited.makeWindowControllers()
    let view = try #require(edited.windowControllers.first?.window?.initialFirstResponder as? NSTextView)
    view.insertText("edited ", replacementRange: NSRange(location: 0, length: 0))
    #expect(try printedPDF(of: edited).page(at: 0)?.string?.contains("edited saved") == true)
    #expect(edited.pdfPrintOperation.jobTitle == edited.displayName)
}

@MainActor @Test func pdfPrintsEveryPage() throws {
    _ = NSApplication.shared
    let document = PDFFileDocument()
    try document.read(from: samplePDF(["first", "second"]), ofType: DocumentController.pdfType)
    let printed = try printedPDF(of: document)
    #expect(printed.pageCount == 2)
    #expect(printed.page(at: 1)?.string?.contains("second") == true)
}

/// Recent files belong to the test runner here, not to the installed app.
@MainActor @Test func recentFilesListAndMenuSkipMissingFilesAndOpenOnLaunch() throws {
    _ = NSApplication.shared
    let controller = NSDocumentController.shared
    controller.clearRecentDocuments(nil)
    defer { controller.clearRecentDocuments(nil) }
    let folder = try temporaryFolder()
    let kept = folder.appendingPathComponent("kept.md"), gone = folder.appendingPathComponent("gone.md")
    try Data().write(to: kept)
    try Data().write(to: gone)
    controller.noteNewRecentDocumentURL(gone)
    controller.noteNewRecentDocumentURL(kept)
    try FileManager.default.removeItem(at: gone)
    #expect(controller.existingRecentURLs.map(\.lastPathComponent) == ["kept.md"])

    let menu = NSMenu()
    RecentFilesMenu().menuNeedsUpdate(menu)
    #expect(menu.items.map(\.title) == ["kept.md", "", "Clear Menu"])

    #expect(AppDelegate().applicationOpenUntitledFile(NSApp))
    let window = try #require(RecentFilesWindow.current)
    #expect(window.isVisible)
    #expect(window.list.files.map(\.lastPathComponent) == ["kept.md"])
    #expect(window.contentLayoutRect.height == window.list.preferredSize.height)

    DocumentController().addDocument(TextDocument())
    #expect(!window.isVisible, "opening any document puts the list away")
}

@MainActor @Test func recentFilesListMovesWithArrowKeysWithinItsRows() throws {
    let list = RecentFilesList()
    list.files = ["a.md", "b.md"].map { URL(fileURLWithPath: "/tmp/\($0)") }
    list.moveDown(nil)
    list.moveDown(nil)
    #expect(list.selected == 1)
    list.moveUp(nil)
    list.moveUp(nil)
    #expect(list.selected == 0)
}

/// Writes the recent files window to `$DOCMARK_RECENT_PNG`, for looking at.
@MainActor @Test func recentFilesSnapshot() throws {
    guard let path = ProcessInfo.processInfo.environment["DOCMARK_RECENT_PNG"] else { return }
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let list = RecentFilesList()
    list.files = ["README.md", "Syspr01ErsteSchritteInC.pdf", "a very long file name that has to be shortened somewhere in the middle.txt"]
        .map { URL(fileURLWithPath: NSHomeDirectory() + "/development/fhnw/syspr/Solutions/01/" + $0) }
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: list.preferredSize), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = list
    list.moveDown(nil)
    let rep = list.bitmapImageRepForCachingDisplay(in: list.bounds)!
    list.cacheDisplay(in: list.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
