import Foundation

/// What the tokenizer needs to know about a language. Everything else is shared.
struct CodeLanguage {
    struct StringRule {
        let open: [unichar]
        let close: [unichar]
        var multiline = false
        var escapes = true

        init(_ open: String, _ close: String? = nil, multiline: Bool = false, escapes: Bool = true) {
            self.open = Array(open.utf16)
            self.close = Array((close ?? open).utf16)
            self.multiline = multiline
            self.escapes = escapes
        }
    }

    var keywords: Set<String> = []
    var types: Set<String> = []
    var constants: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var strings: [StringRule] = []
    /// `'` only opens a string around a single character, so `'a` in Rust stays plain.
    var charLiterals = false
    /// `#` only starts a comment after whitespace, so `$#` and `a#b` stay plain.
    var commentNeedsSpaceBefore = false
    /// `'` after a word is an apostrophe, as in unquoted `don't`.
    var apostrophes = false
    /// A `#` line is a directive: `#include`, `#[derive]`.
    var directives = false
    var annotations = false
    var variables = false
    var capitalizedTypes = false
    var suffixTypes = false
    var macros = false
    var ignoresCase = false
    /// `"key":` in JSON.
    var quotedKeys = false
    /// `key:` at the start of a YAML line.
    var plainKeys = false

    static func named(_ name: String) -> CodeLanguage? {
        byName[name.lowercased()]
    }

    private static let double = StringRule("\"")
    private static let single = StringRule("'")

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    private static let cKeywords = "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while"
    private static let cTypes = "void char short int long float double signed unsigned bool"

    private static let c = CodeLanguage(
        keywords: words(cKeywords), types: words(cTypes), constants: words("true false"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [double], charLiterals: true, directives: true, suffixTypes: true
    )

    private static let cpp = CodeLanguage(
        keywords: words(cKeywords + " alignas alignof catch class concept constexpr consteval co_await co_return co_yield decltype delete explicit export final friend mutable namespace new noexcept operator override private protected public requires static_cast dynamic_cast reinterpret_cast const_cast template this throw try typename using virtual"),
        types: words(cTypes + " auto wchar_t char8_t char16_t char32_t string vector map set"), constants: words("true false nullptr"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [double], charLiterals: true, directives: true, capitalizedTypes: true, suffixTypes: true
    )

    private static let java = CodeLanguage(
        keywords: words("abstract assert break case catch class continue default do else enum extends final finally for if implements import instanceof interface native new package private protected public record return sealed static super switch synchronized this throw throws transient try var volatile while yield"),
        types: words("boolean byte char double float int long short void"), constants: words("true false null"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [StringRule("\"\"\"", multiline: true), double], charLiterals: true, annotations: true, capitalizedTypes: true
    )

    private static let script = CodeLanguage(
        keywords: words("abstract as async await break case catch class const continue debugger declare default delete do else enum export extends finally for from function get if implements import in instanceof interface let namespace new of private protected public readonly return set static super switch this throw try type typeof var void while with yield"),
        types: words("any bigint boolean never number object string symbol unknown"), constants: words("true false null undefined NaN Infinity"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [double, single, StringRule("`", multiline: true)], annotations: true, capitalizedTypes: true
    )

    private static let swift = CodeLanguage(
        keywords: words("actor as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough fileprivate final for func guard if import in init inout internal is lazy let nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws try typealias unowned var weak where while any"),
        constants: words("true false nil"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [StringRule("\"\"\"", multiline: true), double], annotations: true, capitalizedTypes: true
    )

    private static let python = CodeLanguage(
        keywords: words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda match nonlocal not or pass raise return try while with yield self"),
        types: words("bool bytes dict float int list object set str tuple"), constants: words("True False None"),
        lineComments: ["#"],
        strings: [StringRule("\"\"\"", multiline: true), StringRule("'''", multiline: true), double, single], annotations: true, capitalizedTypes: true
    )

    private static let go = CodeLanguage(
        keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
        types: words("any bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr"), constants: words("true false nil iota"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [double, StringRule("`", multiline: true, escapes: false)], charLiterals: true, capitalizedTypes: true
    )

    private static let rust = CodeLanguage(
        keywords: words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while"),
        types: words("bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize"), constants: words("true false"),
        lineComments: ["//"], blockComment: ("/*", "*/"), strings: [StringRule("\"", multiline: true)], charLiterals: true, directives: true, capitalizedTypes: true, macros: true
    )

    private static let shell = CodeLanguage(
        keywords: words("alias case cd do done echo elif else esac exit export fi for function if in local printf read readonly return set shift source then trap unset until while"),
        constants: words("true false"),
        lineComments: ["#"], strings: [double, StringRule("'", escapes: false)], commentNeedsSpaceBefore: true, apostrophes: true, variables: true
    )

    private static let sql = CodeLanguage(
        keywords: words("add all alter and as asc begin between by case check column commit constraint create default delete desc distinct drop else end exists foreign from group having if in index inner insert into is join key left like limit not offset on or order outer primary references returning right rollback select set table then transaction union unique update values view when where with"),
        types: words("bigint blob boolean char date datetime decimal double float int integer numeric real serial smallint text time timestamp uuid varchar"), constants: words("true false null"),
        lineComments: ["--"], blockComment: ("/*", "*/"), strings: [StringRule("'", escapes: false), StringRule("\"", escapes: false)], ignoresCase: true
    )

    private static let json = CodeLanguage(
        constants: words("true false null"), lineComments: ["//"], blockComment: ("/*", "*/"), strings: [double], quotedKeys: true
    )

    private static let yaml = CodeLanguage(
        constants: words("true false null yes no on off"), lineComments: ["#"],
        strings: [double, StringRule("'", escapes: false)], commentNeedsSpaceBefore: true, apostrophes: true, plainKeys: true
    )

    private static let byName: [String: CodeLanguage] = {
        let groups: [(CodeLanguage, String)] = [
            (c, "c h"), (cpp, "cpp c++ cc cxx hpp"), (java, "java"),
            (script, "js javascript jsx mjs ts typescript tsx"), (swift, "swift"),
            (python, "py python python3"), (go, "go golang"), (rust, "rs rust"),
            (shell, "sh bash shell zsh"), (sql, "sql"), (json, "json jsonc"), (yaml, "yml yaml"),
        ]
        var result: [String: CodeLanguage] = [:]
        for (language, names) in groups {
            for name in words(names) { result[name] = language }
        }
        return result
    }()
}
