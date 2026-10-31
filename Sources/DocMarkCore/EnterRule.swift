import Foundation

/// What pressing Return at the end of a line does in a Markdown document.
public enum EnterRule {
    public struct Edit: Equatable {
        /// Replaces the whole current line (without its line ending).
        public var text: String
        /// Where the caret lands, as a UTF-16 offset into `text`.
        public var caret: Int
    }

    public static func edit(forLine line: String, fenceIsUnclosed: Bool = false) -> Edit? {
        if line.wholeMatch(of: emptyHeading) != nil {
            return Edit(text: line + " ", caret: line.utf16.count + 1)
        }
        if fenceIsUnclosed, let match = line.wholeMatch(of: openingFence), let fence = match.output[1].substring {
            return Edit(text: "\(line)\n\n\(fence)", caret: line.utf16.count + 1)
        }
        if let match = line.wholeMatch(of: unorderedItem) {
            let box = match.output[3].substring.map { _ in " [ ]" } ?? ""
            return continuing(line, rest: match.output[4].substring, next: "\(match.output[1].substring ?? "")\(match.output[2].substring ?? "")\(box) ")
        }
        if let match = line.wholeMatch(of: orderedItem), let number = match.output[2].substring.flatMap({ Int($0) }) {
            return continuing(line, rest: match.output[4].substring, next: "\(match.output[1].substring ?? "")\(number + 1)\(match.output[3].substring ?? "") ")
        }
        if let match = line.wholeMatch(of: quote) {
            return continuing(line, rest: match.output[2].substring, next: String(match.output[1].substring ?? ""))
        }
        return nil
    }

    /// Continues the block on a new line, or ends it when the current line has no content.
    private static func continuing(_ line: String, rest: Substring?, next: String) -> Edit {
        if rest?.isEmpty ?? true { return Edit(text: "", caret: 0) }
        let text = "\(line)\n\(next)"
        return Edit(text: text, caret: text.utf16.count)
    }

    private static let emptyHeading = try! Regex(#" {0,3}#{1,6}"#)
    private static let openingFence = try! Regex(#" {0,3}(`{3,}|~{3,})[^`]*"#)
    private static let unorderedItem = try! Regex(#"(\s*)([-+*])( \[[ xX]\])? (.*)"#)
    private static let orderedItem = try! Regex(#"(\s*)(\d{1,9})([.)]) (.*)"#)
    private static let quote = try! Regex(#"((?:\s*> ?)+)(.*)"#)
}
