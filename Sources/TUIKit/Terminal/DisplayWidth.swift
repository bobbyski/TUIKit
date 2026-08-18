import Foundation

/// How many columns a character occupies on a terminal.
///
/// A terminal grid is columns, not characters, and the two stop agreeing the
/// moment text is not Latin. `日` is one Character and two columns; a flag
/// emoji is one Character and two columns; a combining accent is one
/// Character and zero. TUIKit counted characters everywhere, which is why
/// `Label`, `TextView`, `TableView` and `DirectoryTree` all mis-align on CJK
/// and emoji today — not a rendering bug in any of them, one missing
/// function underneath all of them.
///
/// This is `wcwidth`'s job, and the ranges are the East Asian Width property
/// from UAX #11 plus the emoji presentation ranges. It is deliberately a
/// table rather than a call into libc: `wcwidth` depends on the process
/// locale, which a TUI cannot rely on being set, and it answers for one
/// `wchar_t` rather than for a grapheme cluster — which is the unit a
/// terminal actually advances by.
public enum DisplayWidth {
    /// Columns one grapheme cluster occupies: 0, 1 or 2.
    ///
    /// - Parameter character: The grapheme cluster.
    public static func of(_ character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else {
            return 0
        }

        // A cluster with an emoji presentation selector is wide however its
        // base scalar is classified — `⚒` is narrow, `⚒️` is not, and the
        // difference is invisible in a source file.
        if character.unicodeScalars.contains(where: { $0.value == 0xFE0F }) {
            return 2
        }

        // Zero-width: combining marks, joiners, and the format characters a
        // terminal advances past without drawing.
        if isZeroWidth(scalar) {
            return 0
        }

        return isWide(scalar) ? 2 : 1
    }

    /// Columns a string occupies.
    ///
    /// - Parameter text: The text.
    public static func of(_ text: some StringProtocol) -> Int {
        text.reduce(0) { $0 + of($1) }
    }

    /// The longest prefix of a string that fits in a column budget.
    ///
    /// Never splits a wide character across the boundary: a cluster that
    /// would half-fit is left out, because half of a `日` is not a
    /// character, it is a corrupted row.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - columns: Cells available.
    /// - Returns: The prefix, and the columns it actually uses.
    public static func prefix(of text: some StringProtocol, fitting columns: Int) -> (text: String, width: Int) {
        var result = ""
        var used = 0

        for character in text {
            let width = of(character)

            guard used + width <= columns else {
                break
            }

            result.append(character)
            used += width
        }

        return (result, used)
    }

    // MARK: - Tables

    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0300...0x036F,        // combining diacritical marks
             0x0483...0x0489,
             0x0591...0x05BD,
             0x0610...0x061A,
             0x064B...0x065F,
             0x0670,
             0x06D6...0x06DC,
             0x0E31, 0x0E34...0x0E3A, 0x0E47...0x0E4E,
             0x200B...0x200F,        // zero-width space, joiners, marks
             0x2028...0x202E,
             0x20D0...0x20F0,        // combining marks for symbols
             0xFE00...0xFE0E,        // variation selectors (FE0F handled above)
             0xFE20...0xFE2F:
            return true

        default:
            return false
        }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,        // Hangul Jamo initial consonants
             0x2E80...0x303E,        // CJK radicals, Kangxi, CJK symbols
             0x3041...0x33FF,        // Hiragana … CJK compatibility
             0x3400...0x4DBF,        // CJK extension A
             0x4E00...0x9FFF,        // CJK unified ideographs
             0xA000...0xA4CF,        // Yi
             0xAC00...0xD7A3,        // Hangul syllables
             0xF900...0xFAFF,        // CJK compatibility ideographs
             0xFE10...0xFE19,        // vertical forms
             0xFE30...0xFE6F,        // CJK compatibility forms
             0xFF00...0xFF60,        // fullwidth forms
             0xFFE0...0xFFE6,
             0x1F004, 0x1F0CF,
             0x1F18E, 0x1F191...0x1F19A,
             0x1F200...0x1F320,      // enclosed ideographs, emoji
             0x1F32D...0x1F335,
             0x1F337...0x1F37C,
             0x1F37E...0x1F393,
             0x1F3A0...0x1F3CA,
             0x1F3CF...0x1F3D3,
             0x1F3E0...0x1F3F0,
             0x1F3F4,
             0x1F3F8...0x1F43E,
             0x1F440,
             0x1F442...0x1F4FC,
             0x1F4FF...0x1F53D,
             0x1F54B...0x1F54E,
             0x1F550...0x1F567,
             0x1F57A,
             0x1F595...0x1F596,
             0x1F5A4,
             0x1F5FB...0x1F64F,
             0x1F680...0x1F6C5,
             0x1F6CC,
             0x1F6D0...0x1F6D2,
             0x1F6EB...0x1F6EC,
             0x1F6F4...0x1F6FC,
             0x1F7E0...0x1F7EB,
             0x1F90C...0x1F93A,
             0x1F93C...0x1F945,
             0x1F947...0x1F9FF,
             0x1FA70...0x1FAFF,
             0x20000...0x2FFFD,      // CJK extensions B onward
             0x30000...0x3FFFD:
            return true

        default:
            return false
        }
    }
}
