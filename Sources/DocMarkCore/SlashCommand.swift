import Foundation

/// A block typed by name: `/` at the start of a line opens the list of these.
public struct SlashCommand: Equatable {
    public let title: String
    /// The syntax it inserts, shown beside the title.
    public let hint: String
    public let aliases: [String]
    public let text: String
    /// Where the caret lands, as a UTF-16 offset into `text`.
    public let caret: Int
    /// Needs a blank line above, because text directly above would change what it means (`---` makes a heading).
    public let needsBlankLineAbove: Bool

    private init(_ title: String, hint: String, aliases: [String], text: String, caret: Int? = nil, needsBlankLineAbove: Bool = false) {
        self.title = title
        self.hint = hint
        self.aliases = aliases
        self.text = text
        self.caret = caret ?? (text as NSString).length
        self.needsBlankLineAbove = needsBlankLineAbove
    }

    public static let all = [
        SlashCommand("Heading 1", hint: "#", aliases: ["h1", "title"], text: "# "),
        SlashCommand("Heading 2", hint: "##", aliases: ["h2"], text: "## "),
        SlashCommand("Heading 3", hint: "###", aliases: ["h3"], text: "### "),
        SlashCommand("Bulleted list", hint: "-", aliases: ["ul", "unordered"], text: "- "),
        SlashCommand("Numbered list", hint: "1.", aliases: ["ol", "ordered"], text: "1. "),
        SlashCommand("Task", hint: "- [ ]", aliases: ["todo", "checkbox"], text: "- [ ] "),
        SlashCommand("Quote", hint: ">", aliases: ["blockquote"], text: "> "),
        SlashCommand("Code block", hint: "```", aliases: ["fence", "pre"], text: "```\n\n```", caret: 4),
        SlashCommand("Table", hint: "| |", aliases: ["grid"], text: "|  |  |\n|---|---|\n|  |  |", caret: 2),
        SlashCommand("Divider", hint: "---", aliases: ["hr", "rule", "line"], text: "---\n", needsBlankLineAbove: true),
        SlashCommand("Link", hint: "[]()", aliases: ["url"], text: "[]()", caret: 1),
        SlashCommand("Image", hint: "![]()", aliases: ["picture"], text: "![]()", caret: 2),
    ]

    public static func matching(_ query: String) -> [SlashCommand] {
        let query = query.lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { command in
            command.title.lowercased().contains(query) || command.aliases.contains { $0.hasPrefix(query) }
        }
    }

    /// The `/` and query when a whole line is a slash command being typed. Indentation is allowed;
    /// any other text on the line isn't, so a path such as `/usr/bin` or a sentence stays plain text.
    public static func trigger(inLine line: String) -> (slash: Int, query: String)? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        guard rest.first == "/" else { return nil }
        let query = rest.dropFirst()
        guard query.first != " ", query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }) else { return nil }
        return (indent.utf16.count, String(query))
    }
}
