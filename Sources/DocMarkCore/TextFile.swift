import Foundation

/// Converts file bytes to editor text and back, keeping every byte (BOM and line endings included).
public enum TextFile {
    public struct NotUTF8: LocalizedError {
        public var errorDescription: String? { "This file isn't UTF-8 text." }
    }

    public static func decode(_ data: Data) throws -> String {
        guard let text = String(validating: data, as: UTF8.self) else { throw NotUTF8() }
        return text
    }

    public static func encode(_ text: String) -> Data {
        Data(text.utf8)
    }
}
