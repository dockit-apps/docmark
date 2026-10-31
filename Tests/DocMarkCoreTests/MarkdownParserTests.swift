import AppKit
import Foundation
import Testing
@testable import DocMarkCore

private extension MarkdownLayout {
    func withLength(_ length: Int) -> MarkdownLayout {
        var layout = self
        layout.length = length
        return layout
    }
}

private func text(_ range: NSRange, in source: String) -> String {
    (source as NSString).substring(with: range)
}

private func markerTexts(_ source: String) -> [String] {
    MarkdownParser.parse(source).markers.map { text($0.range, in: source) }
}

private func spanText(_ source: String, where matches: (Span.Kind) -> Bool) -> [String] {
    MarkdownParser.parse(source).spans.filter { matches($0.kind) }.map { text($0.range, in: source) }
}

@Test func headingMarkerIncludesSpace() {
    #expect(markerTexts("### Title\n") == ["### "])
    #expect(spanText("### Title\n") { if case .heading(3) = $0 { true } else { false } } == ["### Title"])
}

@Test func bareHeadingStaysVisible() {
    #expect(markerTexts("###\n").isEmpty)
}

@Test func headingMarkerRevealsOnlyWithCaretInHeading() throws {
    let source = "### Title\nbody\n"
    let marker = try #require(MarkdownParser.parse(source).markers.first)
    #expect(marker.isRevealed(caret: 9))
    #expect(!marker.isRevealed(caret: 10))
}

@Test func setextUnderlineIsSyntaxLine() throws {
    let source = "Title\n=====\n"
    let marker = try #require(MarkdownParser.parse(source).markers.first)
    #expect(marker.kind == .syntaxLine)
    #expect(text(marker.range, in: source) == "=====")
}

@Test func inlineDelimiters() {
    #expect(markerTexts("a **b** c") == ["**", "**"])
    #expect(markerTexts("a *b* c") == ["*", "*"])
    #expect(markerTexts("a __b__ c") == ["__", "__"])
    #expect(markerTexts("a ~~b~~ c") == ["~~", "~~"])
    #expect(markerTexts("a ``b`` c") == ["``", "``"])
}

@Test func inlineRangesAcrossSoftBreaksAndUnicode() {
    let source = "héllo 😀 **one**\nsecond *two* 🎉 `three`\n"
    #expect(markerTexts(source) == ["**", "**", "*", "*", "`", "`"])
    #expect(spanText(source) { $0 == .strong } == ["**one**"])
    #expect(spanText(source) { $0 == .inlineCode } == ["`three`"])
}

@Test func nestedInlinesInsideBlocks() {
    let source = "> quote **bold**\n> more *it*\n\n- item **bold**\n  - nested `code`\n"
    let markers = markerTexts(source)
    #expect(markers.filter { $0 == "**" }.count == 4)
    #expect(markers.filter { $0 == "*" }.count == 2)
    #expect(markers.filter { $0 == "`" }.count == 2)
    #expect(markers.filter { $0 == "> " }.count == 2)
    #expect(spanText(source) { $0 == .strong } == ["**bold**", "**bold**"])
}

@Test func linkMarkersLeaveOnlyTheText() {
    #expect(markerTexts("[a [b] c](http://x.y \"t\") z") == ["[", "](http://x.y \"t\")"])
    #expect(markerTexts("<http://x.y>") == ["<", ">"])
    #expect(markerTexts("see http://x.y now").isEmpty)
}

@Test func fencedCodeHidesBothFences() {
    let source = "```swift\nlet a = 1\n```\nafter\n"
    let layout = MarkdownParser.parse(source)
    #expect(layout.markers.map { text($0.range, in: source) } == ["```swift", "```"])
    #expect(layout.markers.allSatisfy { $0.kind == .syntaxLine })
}

@Test func unclosedFenceHidesOnlyOpening() {
    #expect(markerTexts("```\nabc\n") == ["```"])
}

@Test func indentedCodeHasNoMarkers() {
    #expect(markerTexts("    code\n").isEmpty)
}

@Test func bulletsAndCheckboxes() {
    let layout = MarkdownParser.parse("- a\n- [ ] b\n- [x] c\n")
    #expect(layout.markers.map(\.kind) == [.bullet(checked: nil), .bullet(checked: false), .bullet(checked: true)])
    #expect(layout.markers.map(\.range.length) == [2, 6, 6])
}

@Test func bulletHidesAsSoonAsItsSpaceIsTyped() throws {
    let marker = try #require(MarkdownParser.parse("- ").markers.first)
    #expect(!marker.isRevealed(caret: 2))
    #expect(marker.isRevealed(caret: 1))
}

@Test func orderedListKeepsNumbers() {
    #expect(markerTexts("1. a\n2. b\n").isEmpty)
}

@Test func nestedListHidesIndent() {
    #expect(markerTexts("- a\n  - b\n") == ["- ", "  ", "- "])
}

@Test func standaloneImageIsMarkerInlineImageIsLink() {
    let layout = MarkdownParser.parse("![alt](a%20b.png)\n")
    #expect(layout.markers.first?.kind == .image(source: "a%20b.png"))
    let inline = MarkdownParser.parse("x ![alt](a.png) y\n")
    #expect(inline.markers.count == 2)
}

@Test func thematicBreakIsRule() {
    #expect(MarkdownParser.parse("---\n").markers.first?.kind == .rule)
}

private func tableShape(_ source: String) throws -> TableShape {
    let marker = try #require(MarkdownParser.parse(source).markers.last)
    guard case .table(let shape) = marker.kind else { throw CancellationError() }
    return shape
}

private func cellTexts(_ source: String) throws -> [[String]] {
    try tableShape(source).rows.map { $0.map { text($0, in: source) } }
}

@Test func tableCellsSkipPipesPaddingAndDelimiterLine() throws {
    let source = "| a | b |\n|---|---|\n| 1 |  two words  |\n"
    #expect(spanText(source) { $0 == .table }.count == 1)
    #expect(try cellTexts(source) == [["a", "b"], ["1", "two words"]])
    let marker = try #require(MarkdownParser.parse(source).markers.last)
    #expect(text(marker.range, in: source) == "| a | b |\n|---|---|\n| 1 |  two words  |")
}

@Test func tableWithoutOuterPipesAndWithShortRows() throws {
    #expect(try cellTexts("a | b\n--|--\n1\n") == [["a", "b"], ["1", ""]])
    #expect(try cellTexts("a | b\n--|--\n1 | 2 | 3\n") == [["a", "b"], ["1", "2"]])
}

@Test func tableKeepsAlignmentsAndEscapedPipes() throws {
    let source = "| a | b | c |\n|:--|:-:|--:|\n| x\\|y | `n` | **b** |\n"
    #expect(try tableShape(source).alignments == [.left, .center, .right])
    #expect(try cellTexts(source)[1] == ["x\\|y", "`n`", "**b**"])
    #expect(markerTexts(source).contains("\\"))
}

@Test func tableInQuoteDropsPrefixOnEveryLine() throws {
    #expect(try cellTexts("> | a | b |\n> |---|---|\n> | 1 | 2 |\n") == [["a", "b"], ["1", "2"]])
}

@Test func slashTriggerNeedsAWholeLineOfCommand() throws {
    #expect(try #require(SlashCommand.trigger(inLine: "/")).query == "")
    let indented = try #require(SlashCommand.trigger(inLine: "  /hea"))
    #expect(indented.slash == 2 && indented.query == "hea")
    #expect(try #require(SlashCommand.trigger(inLine: "/heading 2")).query == "heading 2")
    for plain in ["", "text /a", "/usr/bin", "/ and", "- /a", "a/b"] {
        #expect(SlashCommand.trigger(inLine: plain) == nil)
    }
}

@Test func slashCommandsFilterByNameAndAlias() {
    #expect(SlashCommand.matching("").count == SlashCommand.all.count)
    #expect(SlashCommand.matching("HEAD").map(\.title) == ["Heading 1", "Heading 2", "Heading 3"])
    #expect(SlashCommand.matching("h2").map(\.title) == ["Heading 2"])
    #expect(SlashCommand.matching("todo").map(\.title) == ["Task"])
    #expect(SlashCommand.matching("usr").isEmpty)
}

@Test func slashCommandsProduceWhatTheyNameWithCaretInBounds() throws {
    for command in SlashCommand.all {
        #expect(command.caret <= (command.text as NSString).length)
    }
    let table = try #require(SlashCommand.all.first { $0.title == "Table" })
    let shape = try tableShape(table.text)
    #expect(shape.rows.count == 2 && shape.alignments.count == 2)
    #expect(shape.rows[0][0] == NSRange(location: table.caret, length: 0))
    let code = try #require(SlashCommand.all.first { $0.title == "Code block" })
    #expect(MarkdownParser.parse(code.text).spans.contains { $0.kind == .codeBlock })
}

private func codeTokens(_ code: String, _ language: String) -> [String] {
    CodeHighlighter.tokens(in: code, language: language).map { "\($0.kind):\(text($0.range, in: code))" }
}

@Test func highlightsC() {
    let code = "#include <stdio.h>\n// note\nint main(void) {\n    size_t n = 0x1F; /* a\nb */\n    char c = '\\n';\n    printf(\"%d \\\" x\", INT_MAX);\n}\n"
    #expect(codeTokens(code, "c") == [
        "meta:#include <stdio.h>", "comment:// note", "type:int", "function:main", "type:void",
        "type:size_t", "number:0x1F", "comment:/* a\nb */", "type:char", "string:'\\n'",
        "function:printf", "string:\"%d \\\" x\"", "constant:INT_MAX",
    ])
}

@Test func highlightsPythonAndRustSpecifics() {
    #expect(codeTokens("@dec\ndef f(x):\n    '''a\nb'''\n    return None # c\n", "py") == [
        "meta:@dec", "keyword:def", "function:f", "string:'''a\nb'''", "keyword:return", "constant:None", "comment:# c",
    ])
    #expect(codeTokens("fn f<'a>(x: &'a str) { println!(\"{}\", 1); }", "rust") == [
        "keyword:fn", "type:str", "function:println", "string:\"{}\"", "number:1",
    ])
}

@Test func highlightsShellJsonAndYaml() {
    #expect(codeTokens("echo \"$HOME\" $# a#b $x # end", "bash") == [
        "keyword:echo", "string:\"$HOME\"", "comment:# end",
    ].flatMap { $0 == "comment:# end" ? ["type:$x", $0] : [$0] })
    #expect(codeTokens("{\"a\": \"b\", \"c\": 1, \"d\": null}", "json") == [
        "type:\"a\"", "string:\"b\"", "type:\"c\"", "number:1", "type:\"d\"", "constant:null",
    ])
    #expect(codeTokens("key: don't\n- name: 'x' # c\n", "yaml") == ["type:key", "type:name", "string:'x'", "comment:# c"])
    #expect(codeTokens("SELECT id FROM t -- c", "sql") == ["keyword:SELECT", "keyword:FROM", "comment:-- c"])
}

@Test func tolerantOfBrokenCode() {
    #expect(codeTokens("\"open", "c") == ["string:\"open"])
    #expect(codeTokens("\"esc\\", "c") == ["string:\"esc\\"])
    #expect(codeTokens("/* open", "c") == ["comment:/* open"])
    #expect(codeTokens("'", "c").isEmpty)
    #expect(codeTokens("x", "nosuchlanguage").isEmpty)
    #expect(codeTokens("", "c").isEmpty)
    #expect(codeTokens("#define A \\", "c") == ["meta:#define A \\"])
}

@Test func codeBlockSpansLandOnTheCodeInTheSource() {
    let source = "😀\n\n```c\nint x; // é\nint y;\n```\n"
    let types = spanText(source) { $0 == .code(.type) }
    #expect(types == ["int", "int"])
    #expect(spanText(source) { $0 == .code(.comment) } == ["// é"])

    #expect(spanText("```\nint x;\n```\n") { if case .code = $0 { true } else { false } }.isEmpty)
    #expect(spanText("```c\n```\n") { if case .code = $0 { true } else { false } }.isEmpty)
    #expect(spanText("```c\nint x") { $0 == .code(.type) } == ["int"])
    #expect(spanText("> ```c\n> int x;\n> ```\n") { $0 == .code(.type) } == ["int"])
}

@Test func syntaxFollowsTheFileExtension() {
    #expect(DocumentSyntax(fileExtension: "MD") == .markdown)
    #expect(DocumentSyntax(fileExtension: "txt") == .prose)
    #expect(DocumentSyntax(fileExtension: "C") == .code(language: "c"))
    #expect(DocumentSyntax(fileExtension: "") == .code(language: ""))
    #expect(DocumentSyntax.prose.layout(of: "# a **b**") == MarkdownParser.parse("").withLength(9))
    #expect(DocumentSyntax.code(language: "toml").layout(of: "a = 1").spans.isEmpty)
    #expect(DocumentSyntax.code(language: "c").layout(of: "int x").spans == [Span(range: NSRange(location: 0, length: 3), kind: .code(.type))])
}

@Test func crlfOffsets() {
    let source = "# One\r\n\r\ntext **b**\r\n"
    #expect(markerTexts(source) == ["# ", "**", "**"])
}

@Test func emptyAndWhitespaceDocuments() {
    #expect(MarkdownParser.parse("").spans.isEmpty)
    #expect(MarkdownParser.parse("\n\n  \n").markers.isEmpty)
}

@Test func everyRangeStaysInBounds() {
    let sources = ["😀", "- ", ">", "```", "# ", "**", "[a](", "![", "1. ", "\r", "\r\n", "- [ ]", "|a|\n|-|", "<a>", "    x", "🎉 **😀**\n> 😀 *🎉*"]
    for source in sources {
        let layout = MarkdownParser.parse(source)
        let ranges = layout.spans.map(\.range) + layout.markers.map(\.range)
        #expect(ranges.allSatisfy { $0.location >= 0 && NSMaxRange($0) <= layout.length }, "\(source)")
    }
}

@Test func enterRules() {
    #expect(EnterRule.edit(forLine: "###") == .init(text: "### ", caret: 4))
    #expect(EnterRule.edit(forLine: "plain") == nil)
    #expect(EnterRule.edit(forLine: "- a") == .init(text: "- a\n- ", caret: 6))
    #expect(EnterRule.edit(forLine: "- ") == .init(text: "", caret: 0))
    #expect(EnterRule.edit(forLine: "  * [x] a")?.text == "  * [x] a\n  * [ ] ")
    #expect(EnterRule.edit(forLine: "9. a")?.text == "9. a\n10. ")
    #expect(EnterRule.edit(forLine: "> a")?.text == "> a\n> ")
    #expect(EnterRule.edit(forLine: "> ") == .init(text: "", caret: 0))
    #expect(EnterRule.edit(forLine: "```swift", fenceIsUnclosed: true) == .init(text: "```swift\n\n```", caret: 9))
    #expect(EnterRule.edit(forLine: "```swift", fenceIsUnclosed: false) == nil)
}

@Test func filesRoundTripByteForByte() throws {
    let samples = ["# Title\r\n\r\ntext\r\n", "\u{FEFF}# BOM\n", "no newline", "mixed\n\r\n\rend", "😀 é\n", ""]
    for sample in samples {
        let data = Data(sample.utf8)
        let text = try TextFile.decode(data)
        // NSTextStorage is where the text lives while the document is open.
        let storage = NSTextStorage(string: text)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 2), range: NSRange(location: 0, length: storage.length))
        #expect(TextFile.encode(storage.string) == data, "\(sample)")
    }
}

@Test func invalidUTF8IsRejectedNotMangled() {
    #expect(throws: TextFile.NotUTF8.self) { try TextFile.decode(Data([0x66, 0xFF, 0x6F])) }
}
