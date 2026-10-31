import AppKit
import DocMarkCore

/// Applies a parsed layout to the text storage as display attributes. The characters never change.
final class MarkdownRenderer {
    static let quoteIndent: CGFloat = 20
    static let listIndent: CGFloat = 26

    private let storage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let documentURL: () -> URL?
    var syntax = DocumentSyntax.markdown
    private(set) var layout = MarkdownParser.parse("")
    private var revealed = Set<Int>()
    private var images: [String: NSImage] = [:]
    private var missingImages = Set<String>()

    init(storage: NSTextStorage, layoutManager: NSLayoutManager, documentURL: @escaping () -> URL?) {
        self.storage = storage
        self.layoutManager = layoutManager
        self.documentURL = documentURL
    }

    /// What text has before any styling. Markdown and plain writing read in the body font, code doesn't.
    var baseAttributes: [NSAttributedString.Key: Any] {
        if case .code = syntax { return Theme.codeAttributes }
        return Theme.bodyAttributes
    }

    /// Reparses after the text changed. `caret` is nil while a range is selected.
    func textChanged(caret: Int?) {
        layout = syntax.layout(of: storage.string)
        revealed = revealedMarkers(caret: caret)
        render(NSRange(location: 0, length: storage.length))
    }

    /// Redraws only the syntax that appeared or disappeared because the caret moved.
    func caretMoved(to caret: Int?) {
        guard layout.length == storage.length else { return }
        let updated = revealedMarkers(caret: caret)
        let changed = revealed.symmetricDifference(updated)
        revealed = updated
        let text = storage.string as NSString
        for index in changed {
            render(text.paragraphRange(for: layout.markers[index].range))
        }
    }

    /// Tables are measured against the column width, so they follow it when the window resizes.
    func columnWidthChanged() {
        guard layout.length == storage.length else { return }
        let text = storage.string as NSString
        for (index, marker) in layout.markers.enumerated() where !revealed.contains(index) {
            if case .table = marker.kind { render(text.paragraphRange(for: marker.range)) }
        }
    }

    /// The hidden marker that ends at `caret`, which Backspace should remove as one unit.
    func hiddenMarker(endingAt caret: Int) -> Marker? {
        layout.markers.first { !$0.revealsAtScopeEnd && NSMaxRange($0.range) == caret }
    }

    private func revealedMarkers(caret: Int?) -> Set<Int> {
        guard let caret else { return [] }
        var result = Set<Int>()
        for (index, marker) in layout.markers.enumerated() where marker.isRevealed(caret: caret) {
            result.insert(index)
        }
        return result
    }

    private func render(_ range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: range)
        for span in layout.spans {
            let clipped = NSIntersectionRange(span.range, range)
            if clipped.length > 0 { apply(span.kind, to: clipped) }
        }
        for (index, marker) in layout.markers.enumerated() where !revealed.contains(index) {
            let clipped = NSIntersectionRange(marker.range, range)
            if clipped.length > 0, !wouldHideLastLine(marker) { hide(marker, clipped: clipped) }
        }
        storage.endEditing()
        layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    /// A last line with no visible character and no newline has no line of its own to draw on,
    /// which would put the caret on the line above. It stays visible until there is text after it.
    private func wouldHideLastLine(_ marker: Marker) -> Bool {
        guard NSMaxRange(marker.range) == storage.length else { return false }
        switch marker.kind {
        case .bullet, .rule, .image: return true
        case .syntaxLine, .table: return false
        case .plain:
            return (storage.string as NSString).lineRange(for: NSRange(location: marker.range.location, length: 0)).location == marker.range.location
        }
    }

    private func apply(_ kind: Span.Kind, to range: NSRange) {
        switch kind {
        case .heading(let level):
            storage.addAttribute(.font, value: Theme.headingFont(level: level), range: range)
            if level == 6 { storage.addAttribute(.foregroundColor, value: Theme.muted, range: range) }
            if level <= 2 { storage.addAttribute(.dmHeadingRule, value: true, range: range) }
            updateParagraph(in: range) {
                $0.paragraphSpacingBefore = 10
                $0.paragraphSpacing = level <= 2 ? 10 : 4
            }
        case .strong:
            addTrait(.bold, to: range)
        case .emphasis:
            addTrait(.italic, to: range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode:
            let size = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 16
            storage.addAttributes([
                .font: Theme.codeFont(size: size * 0.88), .foregroundColor: Theme.code, .backgroundColor: Theme.raised,
            ], range: range)
        case .codeBlock:
            storage.addAttributes([.font: Theme.codeFont(size: 14), .dmCodeBlock: true], range: range)
            updateParagraph(in: range) {
                $0.headIndent += 14
                $0.firstLineHeadIndent = $0.headIndent
                $0.tailIndent = -14
                $0.lineHeightMultiple = 1.25
            }
        case .code(let token):
            storage.addAttribute(.foregroundColor, value: Theme.color(for: token), range: range)
        case .table:
            // The caret shows the table's source, otherwise this is the text the grid draws.
            storage.addAttribute(.font, value: isRevealedTable(at: range.location) ? Theme.codeFont(size: 14) : Theme.tableFont, range: range)
        case .html:
            storage.addAttributes([.font: Theme.codeFont(size: 14), .foregroundColor: Theme.muted], range: range)
        case .blockQuote(let depth):
            storage.addAttributes([.foregroundColor: Theme.muted, .dmQuoteDepth: depth], range: range)
            updateParagraph(in: range) {
                $0.headIndent = CGFloat(depth) * Self.quoteIndent
                $0.firstLineHeadIndent = $0.headIndent
            }
        case .listItem(let depth, let ordered):
            updateParagraph(in: range) { paragraph in
                let quote = self.quoteOffset(at: range.location)
                paragraph.headIndent = quote + CGFloat(depth) * Self.listIndent
                paragraph.firstLineHeadIndent = paragraph.headIndent
                if ordered { paragraph.firstLineHeadIndent -= Self.listIndent }
            }
        case .link:
            storage.addAttributes([
                .foregroundColor: Theme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        }
    }

    private func hide(_ marker: Marker, clipped: NSRange) {
        switch marker.kind {
        case .plain:
            break
        case .syntaxLine:
            collapseLine(of: clipped)
        case .bullet(let checked):
            let symbol = switch checked {
            case .none: "•"
            case .some(true): "☑"
            case .some(false): "☐"
            }
            storage.addAttribute(.dmBullet, value: symbol, range: NSRange(location: clipped.location, length: 1))
        case .rule:
            storage.addAttribute(.dmRule, value: true, range: clipped)
        case .image(let source):
            guard let image = image(for: source) else { return }
            collapseLine(of: clipped)
            storage.addAttribute(.dmImage, value: image, range: NSRange(location: clipped.location, length: 1))
            let scale = min(1, Theme.columnWidth / max(image.size.width, 1))
            updateParagraph(in: clipped) { $0.paragraphSpacing = image.size.height * scale + 8 }
        case .table(let shape):
            hideTable(shape, range: clipped)
        }
        storage.addAttribute(.dmHidden, value: true, range: clipped)
    }

    private func isRevealedTable(at location: Int) -> Bool {
        revealed.contains { index in
            guard case .table = layout.markers[index].kind else { return false }
            return NSLocationInRange(location, layout.markers[index].range)
        }
    }

    /// Collapses the source lines and reserves room for the grid the layout manager draws over them.
    private func hideTable(_ shape: TableShape, range: NSRange) {
        let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let indent = style?.headIndent ?? 0
        let column = layoutManager.textContainers.first?.size.width ?? Theme.columnWidth
        let rows = shape.rows.enumerated().map { rowIndex, cells in
            cells.map { TableGrid.Cell(text: visibleText(of: $0, bold: rowIndex == 0), location: $0.location) }
        }
        let alignments = shape.alignments.map { alignment -> NSTextAlignment in
            switch alignment {
            case .left: .left
            case .center: .center
            case .right: .right
            }
        }
        let grid = TableGrid(rows: rows, alignments: alignments, availableWidth: max(column - indent, 100), indent: indent)
        collapseLine(of: range)
        storage.addAttribute(.dmTable, value: grid, range: range)
        // A last line with no newline has no line of its own, so the one above it holds the room.
        let text = storage.string as NSString
        var last = text.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
        if !text.substring(with: last).hasSuffix("\n"), last.location > 0 {
            last = text.lineRange(for: NSRange(location: last.location - 1, length: 0))
        }
        let collapsedHeight = CGFloat(shape.rows.count + 1)
        updateParagraph(in: last) {
            $0.paragraphSpacing = max(grid.height + MarkdownLayoutManager.tableMargin * 2 - collapsedHeight, 0)
        }
    }

    private func visibleText(of range: NSRange, bold: Bool) -> NSAttributedString {
        let cell = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var hidden: [NSRange] = []
        cell.enumerateAttribute(.dmHidden, in: NSRange(location: 0, length: cell.length)) { value, run, _ in
            if value != nil { hidden.append(run) }
        }
        for run in hidden.reversed() { cell.deleteCharacters(in: run) }
        if bold { addTrait(.bold, to: NSRange(location: 0, length: cell.length), in: cell) }
        return cell
    }

    /// Shrinks a line that only holds hidden syntax so it leaves no gap.
    private func collapseLine(of range: NSRange) {
        let line = (storage.string as NSString).paragraphRange(for: range)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: line)
        updateParagraph(in: range) {
            $0.minimumLineHeight = 1
            $0.maximumLineHeight = 1
            $0.lineHeightMultiple = 0
        }
    }

    private func updateParagraph(in range: NSRange, _ change: (NSMutableParagraphStyle) -> Void) {
        let paragraph = (storage.string as NSString).paragraphRange(for: range)
        let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existing ?? Theme.bodyParagraph).mutableCopy() as! NSMutableParagraphStyle
        change(style)
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    private func quoteOffset(at location: Int) -> CGFloat {
        let depth = storage.attribute(.dmQuoteDepth, at: location, effectiveRange: nil) as? Int ?? 0
        return CGFloat(depth) * Self.quoteIndent
    }

    private func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, to range: NSRange, in text: NSMutableAttributedString? = nil) {
        let target = text ?? storage
        target.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            if let converted = NSFont(descriptor: descriptor, size: font.pointSize) {
                target.addAttribute(.font, value: converted, range: run)
            }
        }
    }

    /// Local images only: the editor never touches the network.
    private func image(for source: String) -> NSImage? {
        if let cached = images[source] { return cached }
        if missingImages.contains(source) { return nil }
        guard let url = fileURL(for: source), let image = NSImage(contentsOf: url) else {
            missingImages.insert(source)
            return nil
        }
        images[source] = image
        return image
    }

    private func fileURL(for source: String) -> URL? {
        if let url = URL(string: source), let scheme = url.scheme {
            return scheme == "file" ? url : nil
        }
        let path = source.removingPercentEncoding ?? source
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return documentURL()?.deletingLastPathComponent().appendingPathComponent(path)
    }
}
