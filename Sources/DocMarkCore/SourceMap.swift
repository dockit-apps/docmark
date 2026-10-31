import Foundation
import Markdown

/// Converts swift-markdown's line and UTF-8 column positions to UTF-16 string offsets.
struct SourceMap {
    private let bytes: [UInt8]
    private var lines: [(utf8: Int, utf16: Int)] = [(0, 0)]

    init(_ source: String) {
        bytes = Array(source.utf8)
        var utf16 = 0
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            utf16 += Self.utf16Width(leadByte: byte)
            index += 1
            let isLoneCR = byte == 0x0D && (index == bytes.count || bytes[index] != 0x0A)
            if byte == 0x0A || isLoneCR {
                lines.append((index, utf16))
            }
        }
    }

    func offset(_ location: SourceLocation) -> Int {
        let line = lines[min(max(location.line - 1, 0), lines.count - 1)]
        let end = min(line.utf8 + max(location.column - 1, 0), bytes.count)
        var utf16 = line.utf16
        for index in line.utf8..<max(end, line.utf8) {
            utf16 += Self.utf16Width(leadByte: bytes[index])
        }
        return utf16
    }

    func range(_ sourceRange: SourceRange) -> NSRange {
        let start = offset(sourceRange.lowerBound)
        return NSRange(location: start, length: max(offset(sourceRange.upperBound) - start, 0))
    }

    private static func utf16Width(leadByte byte: UInt8) -> Int {
        if byte & 0xC0 == 0x80 { return 0 }
        return byte >= 0xF0 ? 2 : 1
    }
}
