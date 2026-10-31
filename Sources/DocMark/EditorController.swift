import AppKit
import DocMarkCore

/// Owns one document's text stack and turns edits and caret moves into rendering.
final class EditorController: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView: MarkdownTextView
    private let storage = NSTextStorage()
    private let layoutManager = MarkdownLayoutManager()
    private let renderer: MarkdownRenderer
    private let undoManagerProvider: () -> UndoManager?
    let slashMenu = SlashMenu()
    /// The `/` whose menu was closed with Escape, which stays closed until that `/` is gone.
    private var dismissedSlash: Int?

    init(documentURL: @escaping () -> URL?, undoManager: @escaping () -> UndoManager?) {
        undoManagerProvider = undoManager
        renderer = MarkdownRenderer(storage: storage, layoutManager: layoutManager, documentURL: documentURL)
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: Theme.columnWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.allowsNonContiguousLayout = true
        textView = MarkdownTextView(frame: .zero, textContainer: container)
        super.init()
        configureTextView()
        textView.layoutSource = { [unowned self] in renderer.layout }
        textView.columnWidthChanged = { [unowned self] in renderer.columnWidthChanged() }
        slashMenu.onPick = { [unowned self] in apply($0) }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(closeSlashMenu), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(closeSlashMenu), name: NSWindow.didResignKeyNotification, object: nil)
    }

    var syntax: DocumentSyntax {
        get { renderer.syntax }
        set {
            guard newValue != renderer.syntax else { return }
            renderer.syntax = newValue
            renderer.textChanged(caret: caret)
            textView.typingAttributes = renderer.baseAttributes
        }
    }

    var text: String {
        get { storage.string }
        set {
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: newValue)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            renderer.textChanged(caret: nil)
            textView.typingAttributes = renderer.baseAttributes
        }
    }

    private func configureTextView() {
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.accent
        textView.selectedTextAttributes = [.backgroundColor: Theme.accent.withAlphaComponent(0.3)]
        textView.typingAttributes = renderer.baseAttributes
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 24)

        scrollView.documentView = textView
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.5
        scrollView.maxMagnification = 3
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
    }

    private var caret: Int? {
        let selection = textView.selectedRange()
        return selection.length == 0 ? selection.location : nil
    }

    // MARK: NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManagerProvider()
    }

    func textDidChange(_ notification: Notification) {
        guard !textView.hasMarkedText() else { return }
        renderer.textChanged(caret: caret)
        textView.typingAttributes = renderer.baseAttributes
        updateSlashMenu()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // Reflowing under the mouse mid-drag would make the selection jump.
        guard !textView.hasMarkedText(), NSApp.currentEvent?.type != .leftMouseDragged else { return }
        renderer.caretMoved(to: caret)
        textView.typingAttributes = renderer.baseAttributes
        if slashMenu.isOpen { updateSlashMenu() }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if slashMenu.isOpen, handleSlashMenuKey(selector) { return true }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): return handleNewline()
        case #selector(NSResponder.deleteBackward(_:)): return handleBackspace()
        case #selector(NSResponder.deleteToBeginningOfLine(_:)): return handleDeleteLine()
        case #selector(NSResponder.insertTab(_:)): return handleTableTab(forward: true)
        case #selector(NSResponder.insertBacktab(_:)): return handleTableTab(forward: false)
        default: return false
        }
    }

    private func handleNewline() -> Bool {
        guard syntax == .markdown, let caret else { return false }
        let text = storage.string as NSString
        var start = 0, contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        guard caret == contentsEnd else { return false }
        let line = NSRange(location: start, length: contentsEnd - start)
        var fenceIsUnclosed = false
        if let block = codeBlock(containing: caret) {
            let fences = renderer.layout.markers.filter { $0.kind == .syntaxLine && $0.scope == block }
            guard block.location >= start, fences.count == 1 else { return false }
            fenceIsUnclosed = true
        }
        guard let edit = EnterRule.edit(forLine: text.substring(with: line), fenceIsUnclosed: fenceIsUnclosed) else { return false }
        replace(line, with: edit.text, caret: start + edit.caret)
        return true
    }

    private func handleBackspace() -> Bool {
        guard let caret, let marker = renderer.hiddenMarker(endingAt: caret) else { return false }
        replace(marker.range, with: "", caret: marker.range.location)
        return true
    }

    /// Command-Backspace removes the whole source line. A selection is deleted as usual.
    private func handleDeleteLine() -> Bool {
        guard let caret, storage.length > 0 else { return false }
        let text = storage.string as NSString
        var line = text.lineRange(for: NSRange(location: caret, length: 0))
        // The last line has no newline of its own, so it takes the one before it.
        if NSMaxRange(line) == storage.length, line.location > 0, !text.substring(with: line).hasSuffix("\n") {
            let previousLine = text.lineRange(for: NSRange(location: line.location - 1, length: 0))
            var contentsEnd = 0
            text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: previousLine)
            line = NSRange(location: contentsEnd, length: storage.length - contentsEnd)
        }
        textView.breakUndoCoalescing()
        replace(line, with: "", caret: line.location)
        textView.breakUndoCoalescing()
        return true
    }

    /// Tab moves between the cells of a table, and past the last one adds a row.
    private func handleTableTab(forward: Bool) -> Bool {
        guard let caret else { return false }
        for marker in renderer.layout.markers where caret >= marker.range.location && caret <= NSMaxRange(marker.range) {
            guard case .table(let shape) = marker.kind else { continue }
            let cells = shape.rows.flatMap { $0 }
            guard let current = cells.lastIndex(where: { $0.location <= caret }) else { return true }
            let target = current + (forward ? 1 : -1)
            if cells.indices.contains(target) {
                textView.setSelectedRange(NSRange(location: NSMaxRange(cells[target]), length: 0))
            } else if forward {
                let row = "\n|" + String(repeating: "  |", count: shape.alignments.count)
                replace(NSRange(location: NSMaxRange(marker.range), length: 0), with: row, caret: NSMaxRange(marker.range) + 3)
            }
            return true
        }
        return false
    }

    // MARK: Slash commands

    private func slashTrigger() -> (slash: Int, end: Int, query: String)? {
        guard syntax == .markdown, let caret else { return nil }
        let text = storage.string as NSString
        var start = 0, contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        guard let trigger = SlashCommand.trigger(inLine: line), caret > start + trigger.slash else { return nil }
        // Source blocks show their characters as they are, so `/` means nothing inside them.
        let insideSource = renderer.layout.spans.contains { span in
            guard span.kind == .codeBlock || span.kind == .table || span.kind == .html else { return false }
            return caret >= span.range.location && caret <= NSMaxRange(span.range)
        }
        guard !insideSource else { return nil }
        return (start + trigger.slash, contentsEnd, trigger.query)
    }

    private func updateSlashMenu() {
        guard let trigger = slashTrigger() else {
            dismissedSlash = nil
            return closeSlashMenu()
        }
        let commands = SlashCommand.matching(trigger.query)
        guard dismissedSlash != trigger.slash, !commands.isEmpty, let window = textView.window else {
            return closeSlashMenu()
        }
        let slash = textView.firstRect(forCharacterRange: NSRange(location: trigger.slash, length: 1), actualRange: nil)
        slashMenu.show(commands, below: slash, in: window)
    }

    @objc private func closeSlashMenu() {
        slashMenu.close()
    }

    private func handleSlashMenuKey(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): slashMenu.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): slashMenu.moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            if let command = slashMenu.selectedCommand { apply(command) }
        case #selector(NSResponder.cancelOperation(_:)):
            dismissedSlash = slashTrigger()?.slash
            closeSlashMenu()
        default: return false
        }
        return true
    }

    private func apply(_ command: SlashCommand) {
        guard let trigger = slashTrigger() else { return closeSlashMenu() }
        closeSlashMenu()
        let source = storage.string as NSString
        var separator = ""
        if command.needsBlankLineAbove, trigger.slash > 0 {
            let above = source.lineRange(for: NSRange(location: trigger.slash - 1, length: 0))
            if !source.substring(with: above).allSatisfy(\.isWhitespace) { separator = "\n" }
        }
        textView.breakUndoCoalescing()
        replace(
            NSRange(location: trigger.slash, length: trigger.end - trigger.slash), with: separator + command.text,
            caret: trigger.slash + (separator as NSString).length + command.caret
        )
        textView.breakUndoCoalescing()
    }

    private func codeBlock(containing caret: Int) -> NSRange? {
        renderer.layout.spans.first {
            $0.kind == .codeBlock && caret >= $0.range.location && caret <= NSMaxRange($0.range)
        }?.range
    }

    private func replace(_ range: NSRange, with replacement: String, caret: Int) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.didChangeText()
    }
}
