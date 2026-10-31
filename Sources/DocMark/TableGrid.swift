import AppKit

/// A Markdown table measured for drawing: columns fit the text width and long cells wrap.
final class TableGrid {
    struct Cell {
        let text: NSAttributedString
        /// Where the cell's text starts in the Markdown source.
        let location: Int
    }

    private static let padding = NSSize(width: 12, height: 6)

    let indent: CGFloat
    private let rows: [[Cell]]
    private let columnWidths: [CGFloat]
    private let rowHeights: [CGFloat]

    var width: CGFloat { columnWidths.reduce(0, +) }
    var height: CGFloat { rowHeights.reduce(0, +) }

    init(rows: [[Cell]], alignments: [NSTextAlignment], availableWidth: CGFloat, indent: CGFloat) {
        self.indent = indent
        let padding = Self.padding
        let aligned = rows.map { row in
            zip(row, alignments).map { cell, alignment in
                Cell(text: Self.styled(cell.text, alignment: alignment), location: cell.location)
            }
        }
        let natural = alignments.indices.map { column in
            aligned.map { ceil($0[column].text.size().width) + 1 + padding.width * 2 }.max() ?? 0
        }
        let widths = Self.fit(natural, into: availableWidth)
        self.rows = aligned
        columnWidths = widths
        rowHeights = aligned.map { row in
            let text = zip(row, widths).map { cell, width in
                cell.text.boundingRect(
                    with: NSSize(width: width - padding.width * 2, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height
            }
            return ceil(max(text.max() ?? 0, Theme.tableFont.ascender - Theme.tableFont.descender)) + padding.height * 2
        }
    }

    /// Columns keep their natural width when everything fits. Otherwise narrow columns stay
    /// whole and the wide ones share what is left.
    static func fit(_ natural: [CGFloat], into available: CGFloat) -> [CGFloat] {
        guard natural.reduce(0, +) > available else { return natural }
        var widths = natural
        var remaining = available
        let narrowestFirst = natural.indices.sorted { natural[$0] < natural[$1] }
        for (offset, column) in narrowestFirst.enumerated() {
            widths[column] = min(natural[column], remaining / CGFloat(natural.count - offset))
            remaining -= widths[column]
        }
        return widths
    }

    func draw(in frame: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let outline = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        outline.addClip()
        Theme.raised.setFill()
        NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: rowHeights.first ?? 0).fill()
        Theme.border.setFill()
        forEachCell(in: frame) { cell, rect, row, column in
            if row > 0 { NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill() }
            if column > 0 { NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill() }
            cell.text.draw(
                with: rect.insetBy(dx: Self.padding.width, dy: Self.padding.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            Theme.border.setFill()
        }
        NSGraphicsContext.restoreGraphicsState()
        Theme.border.setStroke()
        outline.stroke()
    }

    /// The source location of the cell under `point`.
    func location(at point: NSPoint, in frame: NSRect) -> Int? {
        var location: Int?
        forEachCell(in: frame) { cell, rect, _, _ in
            if rect.contains(point) { location = cell.location }
        }
        return location
    }

    private func forEachCell(in frame: NSRect, _ body: (Cell, NSRect, Int, Int) -> Void) {
        var y = frame.minY
        for (rowIndex, row) in rows.enumerated() {
            var x = frame.minX
            for (column, cell) in row.enumerated() {
                body(cell, NSRect(x: x, y: y, width: columnWidths[column], height: rowHeights[rowIndex]), rowIndex, column)
                x += columnWidths[column]
            }
            y += rowHeights[rowIndex]
        }
    }

    private static func styled(_ text: NSAttributedString, alignment: NSTextAlignment) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        let result = NSMutableAttributedString(attributedString: text)
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }
}
