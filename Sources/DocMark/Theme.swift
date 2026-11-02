import AppKit
import CoreText
import DocMarkCore

/// DocShelf's Shelf theme: charcoal and cream with a calm sage accent. The app is always dark, so
/// the light side of each colour is what a view set to the light appearance draws on paper.
enum Theme {
    static let background = NSColor(dark: 0x262625, light: 0xFFFFFF)
    static let raised = NSColor(dark: 0x323230, light: 0xF1F1EC)
    static let border = NSColor(dark: 0x3E3E3B, light: 0xD4D4CC)
    static let text = NSColor(dark: 0xE4E5D8, light: 0x1F1F1E)
    static let muted = NSColor(dark: 0x8C8C83, light: 0x66665F)
    static let accent = NSColor(dark: 0x9FB59A, light: 0x47663F)
    static let code = NSColor(dark: 0xD2A379, light: 0x8F5420)

    static func color(for token: CodeToken) -> NSColor {
        switch token {
        case .keyword: NSColor(dark: 0xCF9BA6, light: 0x9C3F57)
        case .type: accent
        case .function: NSColor(dark: 0x8FB6C9, light: 0x2B6480)
        case .string: code
        case .number, .constant: NSColor(dark: 0xB9A6D6, light: 0x634A94)
        case .comment: muted
        case .meta: NSColor(dark: 0xC9B97F, light: 0x77691F)
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
    convenience init(dark: UInt32, light: UInt32) {
        let darkColor = NSColor(hex: dark), lightColor = NSColor(hex: light)
        self.init(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? lightColor : darkColor }
    }

    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
