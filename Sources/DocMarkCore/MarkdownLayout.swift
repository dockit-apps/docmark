import Foundation

/// What the editor needs to draw a Markdown string. Ranges are UTF-16 offsets into that string,
/// which is never changed by rendering: styling and hiding only affect how it is displayed.
public struct MarkdownLayout: Equatable {
    public var length: Int
    public var spans: [Span] = []
    public var markers: [Marker] = []
}

/// A range that keeps its style wherever the caret is. Parents come before their children.
public struct Span: Equatable {
    public enum Kind: Equatable {
        case heading(level: Int)
        case strong, emphasis, strikethrough, inlineCode, codeBlock, table, html
        case blockQuote(depth: Int)
        case listItem(depth: Int, ordered: Bool)
        case link(destination: String?)
        case code(CodeToken)
    }

    public var range: NSRange
    public var kind: Kind
}

/// The cells of a table. `rows` starts with the header and leaves out the delimiter line; every
/// row has one source range per column, holding the cell's text without pipes or padding.
public struct TableShape: Equatable {
    public enum Alignment: Equatable {
        case left, center, right
    }

    public var alignments: [Alignment]
    public var rows: [[NSRange]]
}

/// Markdown syntax that disappears unless the caret is inside `scope`.
public struct Marker: Equatable {
    public enum Kind: Equatable {
        case plain
        /// A line of only syntax (a code fence or setext underline); collapses when hidden.
        case syntaxLine
        case bullet(checked: Bool?)
        case rule
        case image(source: String)
        case table(TableShape)
    }

    public var range: NSRange
    public var scope: NSRange
    /// Whether a caret right after the scope still reveals it, so `**bold**|` stays editable.
    public var revealsAtScopeEnd: Bool
    public var kind: Kind

    public func isRevealed(caret: Int) -> Bool {
        guard caret >= scope.location else { return false }
        return revealsAtScopeEnd ? caret <= NSMaxRange(scope) : caret < NSMaxRange(scope)
    }
}
