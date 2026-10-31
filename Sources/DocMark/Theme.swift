import AppKit
import CoreText
import DocMarkCore

/// DocShelf's Shelf theme: charcoal and cream with a calm sage accent.
enum Theme {
    static let background = NSColor(hex: 0x262625)
    static let raised = NSColor(hex: 0x323230)
    static let border = NSColor(hex: 0x3E3E3B)
    static let text = NSColor(hex: 0xE4E5D8)
    static let muted = NSColor(hex: 0x8C8C83)
    static let accent = NSColor(hex: 0x9FB59A)
    static let code = NSColor(hex: 0xD2A379)

    static func color(for token: CodeToken) -> NSColor {
        switch token {
        case .keyword: NSColor(hex: 0xCF9BA6)
        case .type: accent
        case .function: NSColor(hex: 0x8FB6C9)
        case .string: code
        case .number, .constant: NSColor(hex: 0xB9A6D6)
        case .comment: muted
        case .meta: NSColor(hex: 0xC9B97F)
        }
    }

    static let columnWidth: CGFloat = 760
    static let bodyFont = NSFont.systemFont(ofSize: 16)
    static let tableFont = NSFont.systemFont(ofSize: 15)
    static let codeFontName = "CaskaydiaCove Nerd Font Mono"

    private static var codeFonts: [CGFloat: NSFont] = [:]

    /// Code shows its exact characters, so the font's ligatures are off (`|---|` stays four symbols).
    static func codeFont(size: CGFloat) -> NSFont {
        if let cached = codeFonts[size] { return cached }
        let base = NSFont(name: codeFontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kContextualAlternatesType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: kContextualAlternatesOffSelector],
            [NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector],
        ]])
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        codeFonts[size] = font
        return font
    }

    static func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [32, 26, 21, 18, 16, 15]
        return .systemFont(ofSize: sizes[min(max(level, 1), 6) - 1], weight: .bold)
    }

    static let bodyParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        return style
    }()

    static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont, .foregroundColor: text, .paragraphStyle: bodyParagraph,
    ]

    static let codeAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.25
        return [.font: codeFont(size: 14), .foregroundColor: text, .paragraphStyle: style]
    }()
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
