import Foundation

/// How a text file is displayed, decided by its extension.
public enum DocumentSyntax: Equatable {
    case markdown
    /// Plain writing, shown in the body font.
    case prose
    /// Everything else, shown monospaced and coloured when the language is known.
    case code(language: String)

    public static let markdownExtensions: Set = ["md", "markdown", "mdown", "mkd", "mkdn"]

    public init(fileExtension: String) {
        let name = fileExtension.lowercased()
        if Self.markdownExtensions.contains(name) {
            self = .markdown
        } else if name == "txt" || name == "text" {
            self = .prose
        } else {
            self = .code(language: name)
        }
    }

    public func layout(of text: String) -> MarkdownLayout {
        switch self {
        case .markdown:
            return MarkdownParser.parse(text)
        case .prose:
            return MarkdownLayout(length: (text as NSString).length)
        case .code(let language):
            var layout = MarkdownLayout(length: (text as NSString).length)
            layout.spans = CodeHighlighter.tokens(in: text, language: language).map { Span(range: $0.range, kind: .code($0.kind)) }
            return layout
        }
    }
}
