import Foundation
import Markdown

public enum MarkdownParser {
    public static func parse(_ source: String) -> MarkdownLayout {
        var builder = LayoutBuilder(source: source)
        builder.visit(Document(parsing: source))
        return builder.layout
    }
}

private struct LayoutBuilder: MarkupWalker {
    let text: NSString
    let map: SourceMap
    var layout: MarkdownLayout
    var quoteDepth = 0
    var listDepth = 0
    var orderedLists: [Bool] = []

    init(source: String) {
        text = source as NSString
        map = SourceMap(source)
        layout = MarkdownLayout(length: text.length)
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) {
        guard let range = range(of: heading) else { return descendInto(heading) }
        layout.spans.append(Span(range: range, kind: .heading(level: heading.level)))
        if character(at: range.location) == "#" {
            var end = range.location
            while character(at: end) == "#" { end += 1 }
            while character(at: end) == " " || character(at: end) == "\t" { end += 1 }
            // A bare `###` stays visible: hiding it would leave a blank line with no explanation.
            if heading.childCount > 0 {
                addMarker(NSRange(location: range.location, length: end - range.location), scope: range)
            }
        } else if let underline = lastLine(of: range) {
            addMarker(underline, scope: range, kind: .syntaxLine)
        }
        descendInto(heading)
    }

    mutating func visitCodeBlock(_ block: CodeBlock) {
        guard let range = range(of: block) else { return }
        layout.spans.append(Span(range: range, kind: .codeBlock))
        guard let opening = firstLine(of: range), let fence = fenceCharacter(in: opening) else { return }
        addMarker(opening, scope: range, kind: .syntaxLine)
        var codeEnd = NSMaxRange(trimmingLineEnd(range))
        if let closing = lastLine(of: range), closing != opening, isClosingFence(closing, fence: fence) {
            addMarker(closing, scope: range, kind: .syntaxLine)
            codeEnd = closing.location
        }
        let codeStart = NSMaxRange(text.lineRange(for: opening))
        if let language = block.language, codeStart < codeEnd {
            let code = text.substring(with: NSRange(location: codeStart, length: codeEnd - codeStart))
            for token in CodeHighlighter.tokens(in: code, language: language) {
                let range = NSRange(location: codeStart + token.range.location, length: token.range.length)
                layout.spans.append(Span(range: range, kind: .code(token.kind)))
            }
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = range(of: thematicBreak) else { return }
        addMarker(trimmingLineEnd(range), scope: range, kind: .rule)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        guard let range = range(of: html) else { return }
        layout.spans.append(Span(range: range, kind: .html))
    }

    mutating func visitTable(_ table: Table) {
        guard let range = range(of: table) else { return descendInto(table) }
        layout.spans.append(Span(range: range, kind: .table))
        descendInto(table)
        // After the cell contents, which the grid is built from once they are hidden.
        let whole = trimmingLineEnd(range)
        addMarker(whole, scope: whole, kind: .table(tableShape(of: table, in: whole)))
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) {
        guard let range = range(of: quote) else { return descendInto(quote) }
        quoteDepth += 1
        layout.spans.append(Span(range: range, kind: .blockQuote(depth: quoteDepth)))
        addQuotePrefixes(in: range, depth: quoteDepth)
        descendInto(quote)
        quoteDepth -= 1
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        visitList(list, ordered: false)
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        visitList(list, ordered: true)
    }

    private mutating func visitList(_ list: Markup, ordered: Bool) {
        listDepth += 1
        orderedLists.append(ordered)
        descendInto(list)
        orderedLists.removeLast()
        listDepth -= 1
    }

    mutating func visitListItem(_ item: ListItem) {
        guard let range = range(of: item) else { return descendInto(item) }
        let ordered = orderedLists.last ?? false
        layout.spans.append(Span(range: range, kind: .listItem(depth: listDepth, ordered: ordered)))
        addListIndent(before: range.location)
        if !ordered, "-+*".contains(character(at: range.location) ?? "?") {
            addBullet(at: range.location, checkbox: item.checkbox)
        }
        descendInto(item)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Image, let range = range(of: image),
           let source = image.source, !source.isEmpty {
            addMarker(range, scope: range, kind: .image(source: source))
            return
        }
        descendInto(paragraph)
    }

    private mutating func tableShape(of table: Table, in range: NSRange) -> TableShape {
        let columns = table.maxColumnCount
        var rows: [[NSRange]] = []
        var lineStart = range.location
        var lineNumber = 0
        while lineStart < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let row = NSRange(location: lineStart, length: min(NSMaxRange(line), NSMaxRange(range)) - lineStart)
            if lineNumber != 1 { rows.append(tableCells(in: trimmingLineEnd(row), table: range, columns: columns)) }
            lineNumber += 1
            lineStart = NSMaxRange(line)
        }
        var alignments = table.columnAlignments.prefix(columns).map { alignment -> TableShape.Alignment in
            switch alignment {
            case .center: .center
            case .right: .right
            default: .left
            }
        }
        alignments += Array(repeating: .left, count: columns - alignments.count)
        return TableShape(alignments: alignments, rows: rows)
    }

    /// Splits a row on unescaped pipes, which is exactly how GFM reads it, even inside code spans.
    private mutating func tableCells(in row: NSRange, table: NSRange, columns: Int) -> [NSRange] {
        var index = row.location
        let end = NSMaxRange(row)
        // A table in a quote or list repeats that prefix on every line.
        while index < end, character(at: index) == " " || character(at: index) == "\t" || (quoteDepth > 0 && character(at: index) == ">") {
            index += 1
        }
        if character(at: index) == "|" { index += 1 }
        var cells: [NSRange] = []
        var cellStart = index
        while index < end {
            if character(at: index) == "\\", index + 1 < end {
                if character(at: index + 1) == "|" {
                    addMarker(NSRange(location: index, length: 1), scope: table)
                }
                index += 2
            } else if character(at: index) == "|" {
                cells.append(cellRange(NSRange(location: cellStart, length: index - cellStart)))
                index += 1
                cellStart = index
            } else {
                index += 1
            }
        }
        let last = cellRange(NSRange(location: cellStart, length: end - cellStart))
        if last.length > 0 { cells.append(last) }
        cells = Array(cells.prefix(columns))
        cells += Array(repeating: NSRange(location: end, length: 0), count: columns - cells.count)
        return cells
    }

    /// An empty cell sits after the padding's first space, where typing leaves tidy source.
    private func cellRange(_ range: NSRange) -> NSRange {
        let trimmed = trimmingSpaces(range)
        return trimmed.length == 0 && range.length > 0 ? NSRange(location: range.location + 1, length: 0) : trimmed
    }

    // MARK: Inlines

    mutating func visitStrong(_ strong: Strong) {
        addDelimited(strong, kind: .strong, delimiters: ["**", "__"])
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        addDelimited(emphasis, kind: .emphasis, delimiters: ["*", "_"])
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        addDelimited(strikethrough, kind: .strikethrough, delimiters: ["~~", "~"])
    }

    mutating func visitInlineCode(_ code: InlineCode) {
        guard let range = range(of: code) else { return }
        layout.spans.append(Span(range: range, kind: .inlineCode))
        var ticks = 0
        while character(at: range.location + ticks) == "`" { ticks += 1 }
        addPairedMarkers(in: range, opening: ticks, closing: ticks)
    }

    mutating func visitLink(_ link: Link) {
        addLink(link, destination: link.destination, hasBang: false)
    }

    mutating func visitImage(_ image: Image) {
        addLink(image, destination: image.source, hasBang: true)
    }

    private mutating func addLink(_ node: Markup, destination: String?, hasBang: Bool) {
        guard let range = range(of: node) else { return descendInto(node) }
        layout.spans.append(Span(range: range, kind: .link(destination: destination)))
        let opening = hasBang ? 2 : 1
        if character(at: range.location) == "<" {
            addPairedMarkers(in: range, opening: 1, closing: 1)
        } else if character(at: range.location + opening - 1) == "[", let closing = closingBracket(of: range) {
            addMarker(NSRange(location: range.location, length: opening), scope: range)
            addMarker(NSRange(location: closing, length: NSMaxRange(range) - closing), scope: range)
        }
        descendInto(node)
    }

    private mutating func addDelimited(_ node: Markup, kind: Span.Kind, delimiters: [String]) {
        guard let range = range(of: node) else { return descendInto(node) }
        layout.spans.append(Span(range: range, kind: kind))
        for delimiter in delimiters where hasPrefix(delimiter, at: range.location) {
            let width = (delimiter as NSString).length
            if hasPrefix(delimiter, at: NSMaxRange(range) - width) {
                addPairedMarkers(in: range, opening: width, closing: width)
            }
            break
        }
        descendInto(node)
    }

    // MARK: Markers

    private mutating func addMarker(_ range: NSRange, scope: NSRange, kind: Marker.Kind = .plain, revealsAtScopeEnd: Bool = true) {
        guard range.length > 0 else { return }
        layout.markers.append(Marker(range: range, scope: scope, revealsAtScopeEnd: revealsAtScopeEnd, kind: kind))
    }

    private mutating func addPairedMarkers(in range: NSRange, opening: Int, closing: Int) {
        guard opening + closing <= range.length else { return }
        addMarker(NSRange(location: range.location, length: opening), scope: range)
        addMarker(NSRange(location: NSMaxRange(range) - closing, length: closing), scope: range)
    }

    /// Hides `> ` on every line of a quote. Each prefix reveals only while the caret is inside it.
    private mutating func addQuotePrefixes(in range: NSRange, depth: Int) {
        var lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        while lineStart < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
            var end = lineStart
            var seen = 0
            while seen < depth {
                while character(at: end) == " " || character(at: end) == "\t" { end += 1 }
                guard character(at: end) == ">" else { break }
                end += 1
                seen += 1
                if character(at: end) == " " { end += 1 }
            }
            if seen == depth {
                let prefix = NSRange(location: lineStart, length: end - lineStart)
                addMarker(prefix, scope: prefix, revealsAtScopeEnd: false)
            }
            lineStart = NSMaxRange(line)
        }
    }

    /// Nested items indent through paragraph style, so their source whitespace is hidden.
    private mutating func addListIndent(before location: Int) {
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        guard location > lineStart else { return }
        let indent = NSRange(location: lineStart, length: location - lineStart)
        guard text.substring(with: indent).allSatisfy({ $0 == " " || $0 == "\t" }) else { return }
        addMarker(indent, scope: indent, revealsAtScopeEnd: false)
    }

    private mutating func addBullet(at location: Int, checkbox: Checkbox?) {
        var end = location + 1
        guard character(at: end) == " " || character(at: end) == "\t" else { return }
        end += 1
        if checkbox != nil, character(at: end) == "[", character(at: end + 2) == "]", character(at: end + 3) == " " {
            end += 4
        }
        let range = NSRange(location: location, length: end - location)
        let checked: Bool? = checkbox.map { $0 == .checked }
        addMarker(range, scope: range, kind: .bullet(checked: checked), revealsAtScopeEnd: false)
    }

    // MARK: Source helpers

    private func range(of node: Markup) -> NSRange? {
        node.range.map { map.range($0) }
    }

    private func character(at index: Int) -> Character? {
        guard index >= 0, index < text.length else { return nil }
        return Character(UnicodeScalar(text.character(at: index)) ?? " ")
    }

    private func hasPrefix(_ prefix: String, at index: Int) -> Bool {
        let length = (prefix as NSString).length
        guard index >= 0, index + length <= text.length else { return false }
        return text.substring(with: NSRange(location: index, length: length)) == prefix
    }

    private func firstLine(of range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        return trimmingLineEnd(NSRange(location: range.location, length: NSMaxRange(line) - range.location))
    }

    private func lastLine(of range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        let trimmed = trimmingLineEnd(range)
        guard trimmed.length > 0 else { return nil }
        let line = text.lineRange(for: NSRange(location: NSMaxRange(trimmed) - 1, length: 0))
        let start = max(line.location, range.location)
        return trimmingLineEnd(NSRange(location: start, length: NSMaxRange(line) - start))
    }

    private func trimmingLineEnd(_ range: NSRange) -> NSRange {
        var length = range.length
        while length > 0, let last = character(at: range.location + length - 1), last == "\n" || last == "\r" { length -= 1 }
        return NSRange(location: range.location, length: length)
    }

    private func trimmingSpaces(_ range: NSRange) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, character(at: start) == " " || character(at: start) == "\t" { start += 1 }
        while end > start, character(at: end - 1) == " " || character(at: end - 1) == "\t" { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private func fenceCharacter(in line: NSRange) -> Character? {
        let content = text.substring(with: line).drop { $0 == " " || $0 == ">" }
        if content.hasPrefix("```") { return "`" }
        if content.hasPrefix("~~~") { return "~" }
        return nil
    }

    private func isClosingFence(_ line: NSRange, fence: Character) -> Bool {
        let content = text.substring(with: line).filter { $0 != " " && $0 != ">" }
        return content.count >= 3 && content.allSatisfy { $0 == fence }
    }

    /// The `]` that closes a link's text, skipping nested brackets and escapes.
    private func closingBracket(of range: NSRange) -> Int? {
        var depth = 0
        var index = range.location
        while index < NSMaxRange(range) {
            switch character(at: index) {
            case "\\": index += 1
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index += 1
        }
        return nil
    }
}
