import Foundation

public enum CodeToken: Equatable {
    case keyword, type, function, string, number, comment, constant, meta
}

/// A small tokenizer for colouring code. It reads a language's shape (comments, strings, keywords)
/// instead of its grammar, which is what keeps it fast while parsing on every keystroke.
public enum CodeHighlighter {
    public static func tokens(in code: String, language name: String) -> [(range: NSRange, kind: CodeToken)] {
        guard let language = CodeLanguage.named(name) else { return [] }
        var scanner = Scanner(code: Array(code.utf16), language: language)
        scanner.run()
        return scanner.tokens
    }
}

private struct Scanner {
    let code: [unichar]
    let language: CodeLanguage
    var tokens: [(range: NSRange, kind: CodeToken)] = []
    var index = 0
    var atLineStart = true

    private static let newline = unichar(10), `return` = unichar(13)
    private static func scalar(_ character: Unicode.Scalar) -> unichar { unichar(character.value) }

    mutating func run() {
        while index < code.count {
            let character = code[index]
            if isNewline(character) {
                atLineStart = true
                index += 1
            } else if isSpace(character) {
                index += 1
            } else {
                let wasAtLineStart = atLineStart
                atLineStart = false
                scanToken(character, atLineStart: wasAtLineStart)
            }
        }
    }

    private mutating func scanToken(_ character: unichar, atLineStart: Bool) {
        if atLineStart, language.directives, character == Self.scalar("#") { return scanDirective() }
        if atLineStart, language.plainKeys {
            if character == Self.scalar("-"), index + 1 < code.count, isSpace(code[index + 1]) {
                self.atLineStart = true
                index += 1
                return
            }
            if scanPlainKey() { return }
        }
        if scanComment() || scanString(character) { return }
        if language.annotations, character == Self.scalar("@"), index + 1 < code.count, isWord(code[index + 1]) {
            return scanWordToken(prefix: 1, kind: .meta)
        }
        if language.variables, character == Self.scalar("$"), index + 1 < code.count, isWord(code[index + 1]) {
            return scanWordToken(prefix: 1, kind: .type)
        }
        if isDigit(character) { return scanNumber() }
        if isWord(character) { return scanWord() }
        index += 1
    }

    // MARK: Comments and directives

    private mutating func scanComment() -> Bool {
        for comment in language.lineComments where matches(Array(comment.utf16), at: index) {
            if language.commentNeedsSpaceBefore, index > 0, !isSpace(code[index - 1]), !isNewline(code[index - 1]) { continue }
            add(from: index, to: lineEnd(from: index), .comment)
            return true
        }
        if let block = language.blockComment, matches(Array(block.open.utf16), at: index) {
            let close = Array(block.close.utf16)
            var end = index + block.open.utf16.count
            while end < code.count, !matches(close, at: end) { end += 1 }
            add(from: index, to: min(end + close.count, code.count), .comment)
            return true
        }
        return false
    }

    /// Runs to the line end, following `\` line continuations.
    private mutating func scanDirective() {
        var end = lineEnd(from: index)
        while end > index, code[end - 1] == Self.scalar("\\"), end < code.count {
            end = lineEnd(from: end + 1)
        }
        add(from: index, to: end, .meta)
    }

    // MARK: Strings

    private mutating func scanString(_ character: unichar) -> Bool {
        if language.charLiterals, character == Self.scalar("'") { return scanCharLiteral() }
        if language.apostrophes, character == Self.scalar("'"), index > 0, isWord(code[index - 1]) { return false }
        for rule in language.strings where matches(rule.open, at: index) {
            let start = index
            var end = index + rule.open.count
            while end < code.count {
                if rule.escapes, code[end] == Self.scalar("\\") {
                    end += 2
                } else if matches(rule.close, at: end) {
                    end += rule.close.count
                    break
                } else if !rule.multiline, isNewline(code[end]) {
                    break
                } else {
                    end += 1
                }
            }
            end = min(end, code.count)
            add(from: start, to: end, language.quotedKeys && nextVisible(after: end) == Self.scalar(":") ? .type : .string)
            return true
        }
        return false
    }

    private mutating func scanCharLiteral() -> Bool {
        var end = index + 1
        guard end < code.count else { return false }
        if code[end] == Self.scalar("\\") {
            // An escape can be long: '\n', '\x41', '\u{1F600}'.
            end += 2
            let limit = min(index + 12, code.count)
            while end < limit, !isNewline(code[end]), code[end] != Self.scalar("'") { end += 1 }
        } else {
            end += UTF16.isLeadSurrogate(code[end]) ? 2 : 1
        }
        guard end < code.count, code[end] == Self.scalar("'") else { return false }
        add(from: index, to: end + 1, .string)
        return true
    }

    // MARK: Numbers and words

    private mutating func scanNumber() {
        var end = index
        while end < code.count, isWord(code[end]) || (code[end] == Self.scalar(".") && end + 1 < code.count && isDigit(code[end + 1])) {
            end += 1
        }
        add(from: index, to: end, .number)
    }

    private mutating func scanWordToken(prefix: Int, kind: CodeToken) {
        var end = index + prefix
        while end < code.count, isWord(code[end]) { end += 1 }
        add(from: index, to: end, kind)
    }

    private mutating func scanWord() {
        var end = index
        while end < code.count, isWord(code[end]) { end += 1 }
        let word = String(decoding: code[index..<end], as: UTF16.self)
        if let kind = classify(word, end: end) {
            add(from: index, to: end, kind)
        } else {
            index = end
        }
    }

    private func classify(_ word: String, end: Int) -> CodeToken? {
        let name = language.ignoresCase ? word.lowercased() : word
        if language.keywords.contains(name) { return .keyword }
        if language.constants.contains(name) { return .constant }
        if language.types.contains(name) { return .type }
        if word.count >= 2, word.contains(where: \.isLetter), word == word.uppercased() { return .constant }
        if language.capitalizedTypes, word.first?.isUppercase == true { return .type }
        if language.suffixTypes, word.hasSuffix("_t") { return .type }
        if language.macros, end < code.count, code[end] == Self.scalar("!"), end + 1 >= code.count || code[end + 1] != Self.scalar("=") { return .function }
        return nextVisible(after: end) == Self.scalar("(") ? .function : nil
    }

    /// `key:` with the colon ending the word, which is how YAML separates it from a plain value.
    private mutating func scanPlainKey() -> Bool {
        var end = index
        while end < code.count, !isSpace(code[end]), !isNewline(code[end]), code[end] != Self.scalar(":") { end += 1 }
        guard end > index, end < code.count, code[end] == Self.scalar(":"),
              end + 1 == code.count || isSpace(code[end + 1]) || isNewline(code[end + 1]),
              code[index] != Self.scalar("#") else { return false }
        add(from: index, to: end, .type)
        return true
    }

    // MARK: Helpers

    private mutating func add(from start: Int, to end: Int, _ kind: CodeToken) {
        tokens.append((NSRange(location: start, length: end - start), kind))
        index = end
    }

    private func matches(_ pattern: [unichar], at position: Int) -> Bool {
        guard position + pattern.count <= code.count else { return false }
        return pattern.indices.allSatisfy { code[position + $0] == pattern[$0] }
    }

    private func lineEnd(from position: Int) -> Int {
        var end = position
        while end < code.count, !isNewline(code[end]) { end += 1 }
        return end
    }

    private func nextVisible(after position: Int) -> unichar? {
        var next = position
        while next < code.count, isSpace(code[next]) { next += 1 }
        return next < code.count ? code[next] : nil
    }

    private func isNewline(_ character: unichar) -> Bool { character == Self.newline || character == Self.return }
    private func isSpace(_ character: unichar) -> Bool { character == 32 || character == 9 }
    private func isDigit(_ character: unichar) -> Bool { character >= 48 && character <= 57 }

    private func isWord(_ character: unichar) -> Bool {
        isDigit(character) || (character >= 65 && character <= 90) || (character >= 97 && character <= 122) || character == 95 || character >= 128
    }
}
