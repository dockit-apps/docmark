import AppKit

extension NSAttributedString.Key {
    static let dmHidden = NSAttributedString.Key("dmHidden")
    static let dmCodeBlock = NSAttributedString.Key("dmCodeBlock")
    static let dmQuoteDepth = NSAttributedString.Key("dmQuoteDepth")
    static let dmBullet = NSAttributedString.Key("dmBullet")
    static let dmRule = NSAttributedString.Key("dmRule")
    static let dmHeadingRule = NSAttributedString.Key("dmHeadingRule")
    static let dmImage = NSAttributedString.Key("dmImage")
    static let dmTable = NSAttributedString.Key("dmTable")
}

/// Hides Markdown syntax without touching the text, and draws what has no glyphs of its own:
/// code block backgrounds, quote bars, bullets, rules, images and tables.
final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    static let tableMargin: CGFloat = 6

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = textStorage else { return 0 }
        var changed: [NSLayoutManager.GlyphProperty]?
        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            guard character < storage.length, !properties[index].contains(.controlCharacter),
                  storage.attribute(.dmHidden, at: character, effectiveRange: nil) != nil else { continue }
            if changed == nil { changed = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length)) }
            changed?[index] = .null
        }
        guard let changed else { return 0 }
        setGlyphs(glyphs, properties: changed, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            drawBlocks(in: characters, storage: storage, container: container, origin: origin)
            drawLineDecorations(in: characters, storage: storage, origin: origin)
            storage.enumerateAttribute(.dmTable, in: characters) { value, run, _ in
                guard let grid = value as? TableGrid else { return }
                grid.draw(in: frame(of: grid, at: run.location, storage: storage).offsetBy(dx: origin.x, dy: origin.y))
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawBlocks(in characters: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: NSPoint) {
        let whole = NSRange(location: 0, length: storage.length)
        var drawnCode = Set<Int>()
        storage.enumerateAttribute(.dmCodeBlock, in: characters) { value, run, _ in
            guard value != nil else { return }
            var block = NSRange()
            storage.attribute(.dmCodeBlock, at: run.location, longestEffectiveRange: &block, in: whole)
            guard drawnCode.insert(block.location).inserted else { return }
            var rect = boundingRect(forVisible: block, storage: storage, container: container)
            rect.origin.x = origin.x
            rect.size.width = container.size.width
            rect.origin.y += origin.y
            Theme.raised.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: -8), xRadius: 8, yRadius: 8).fill()
        }
        storage.enumerateAttribute(.dmQuoteDepth, in: characters) { value, run, _ in
            guard let depth = value as? Int else { return }
            var rect = boundingRect(forVisible: run, storage: storage, container: container)
            // A table's height is reserved spacing, which the bounding rect of its glyphs leaves out.
            storage.enumerateAttribute(.dmTable, in: run) { value, table, _ in
                guard let grid = value as? TableGrid else { return }
                rect = rect.union(frame(of: grid, at: table.location, storage: storage))
            }
            Theme.border.setFill()
            for bar in 0..<depth {
                NSRect(x: origin.x + CGFloat(bar) * MarkdownRenderer.quoteIndent + 2, y: origin.y + rect.minY, width: 3, height: rect.height).fill()
            }
        }
    }

    private func drawLineDecorations(in characters: NSRange, storage: NSTextStorage, origin: NSPoint) {
        storage.enumerateAttribute(.dmBullet, in: characters) { value, run, _ in
            guard let symbol = value as? String else { return }
            let line = lineFragmentUsedRect(forGlyphAt: glyphIndexForCharacter(at: firstVisibleCharacter(from: run.location, storage: storage)), effectiveRange: nil)
            let style = storage.attribute(.paragraphStyle, at: run.location, effectiveRange: nil) as? NSParagraphStyle
            let text = NSAttributedString(string: symbol, attributes: [.font: Theme.bodyFont, .foregroundColor: Theme.muted])
            let x = origin.x + (style?.headIndent ?? 0) - MarkdownRenderer.listIndent + 4
            text.draw(at: NSPoint(x: x, y: origin.y + line.maxY - text.size().height - 1))
        }
        storage.enumerateAttribute(.dmRule, in: characters) { value, run, _ in
            guard value != nil else { return }
            let line = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: firstVisibleCharacter(from: run.location, storage: storage)), effectiveRange: nil)
            Theme.border.setFill()
            NSRect(x: origin.x + line.minX, y: origin.y + line.midY, width: line.width, height: 1).fill()
        }
        storage.enumerateAttribute(.dmHeadingRule, in: characters) { value, run, _ in
            guard value != nil else { return }
            let last = NSMaxRange(run) - 1
            let line = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: last), effectiveRange: nil)
            Theme.border.setFill()
            NSRect(x: origin.x + line.minX, y: origin.y + line.maxY - 3, width: line.width, height: 1).fill()
        }
        storage.enumerateAttribute(.dmImage, in: characters) { value, run, _ in
            guard let image = value as? NSImage else { return }
            let line = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: firstVisibleCharacter(from: run.location, storage: storage)), effectiveRange: nil)
            let scale = min(1, line.width / max(image.size.width, 1))
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = NSRect(origin: NSPoint(x: origin.x + line.minX, y: origin.y + line.minY + 2), size: size)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// The source location of the table cell under a point in text container coordinates.
    func tableCellLocation(at point: NSPoint) -> Int? {
        guard let storage = textStorage else { return nil }
        var location: Int?
        storage.enumerateAttribute(.dmTable, in: NSRange(location: 0, length: storage.length)) { value, run, stop in
            guard let grid = value as? TableGrid else { return }
            location = grid.location(at: point, in: frame(of: grid, at: run.location, storage: storage))
            if location != nil { stop.pointee = true }
        }
        return location
    }

    /// A table is drawn from its first line, whose line break is the first glyph that really sits there.
    private func frame(of grid: TableGrid, at location: Int, storage: NSTextStorage) -> NSRect {
        let whole = NSRange(location: 0, length: storage.length)
        var table = NSRange()
        storage.attribute(.dmTable, at: location, longestEffectiveRange: &table, in: whole)
        var lineEnd = 0
        (storage.string as NSString).getLineStart(nil, end: nil, contentsEnd: &lineEnd, for: NSRange(location: table.location, length: 0))
        let line = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: lineEnd), effectiveRange: nil)
        return NSRect(x: grid.indent, y: line.minY + Self.tableMargin, width: grid.width, height: grid.height)
    }

    /// Hidden glyphs at the start of a line are laid out at the end of the previous line, so
    /// anything positioned from them has to start at the first character that is really on the line.
    private func firstVisibleCharacter(from location: Int, storage: NSTextStorage) -> Int {
        var index = location
        while index < storage.length {
            var hidden = NSRange()
            guard storage.attribute(.dmHidden, at: index, effectiveRange: &hidden) != nil else { return index }
            index = NSMaxRange(hidden)
        }
        return location
    }

    private func boundingRect(forVisible range: NSRange, storage: NSTextStorage, container: NSTextContainer) -> NSRect {
        let start = min(firstVisibleCharacter(from: range.location, storage: storage), max(NSMaxRange(range) - 1, range.location))
        let visible = NSRange(location: start, length: NSMaxRange(range) - start)
        return boundingRect(forGlyphRange: glyphRange(forCharacterRange: visible, actualCharacterRange: nil), in: container)
    }
}
