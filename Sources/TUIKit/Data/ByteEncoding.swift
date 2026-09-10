import Foundation

// Ported from ActiveUI's AUIByteEncoding, decision for decision: the terminal
// arm binds TUIKit's HexView, and an encoding the two sides do not share is a
// text column that cannot agree with itself.

/// One cell of the text column: a character, and how many bytes it took.
///
/// **A cell can be wider than a byte.** In UTF-8 a character is one to four
/// bytes and in UTF-16 two or four, so the text column is not one glyph per
/// byte the way it is in ASCII. Saying how many bytes a character spans is
/// what lets the view draw it ACROSS its own bytes rather than at the first
/// one with three blanks after it -- which would leave the reader to work out
/// where a character starts by counting.
public struct ByteCell: Hashable, Sendable {
    /// The character, or nil when those bytes are not something to show --
    /// a control code, or a sequence that does not decode.
    public let character: Character?
    /// How many bytes the character was written on. At least 1.
    public let byteCount: Int

    /// Creates a cell.
    public init(character: Character?, byteCount: Int) {
        self.character = character
        self.byteCount = max(1, byteCount)
    }
}

/// How bytes become the characters in a hex view's text column.
///
///     view.encoding = .ebcdic
///     let mine = ByteEncoding(name: "CP1252", table: myTable)
///
/// **Open, not an enum.** ASCII, EBCDIC, UTF-8 and UTF-16 are the four that
/// ship, and they are not the four somebody dumping a file will always want --
/// CP1252, Mac OS Roman, Shift-JIS and KOI8-R are all one 256-entry table
/// away. A closed enum would make every one of those a change to TUIKit.
/// This is the same shape as ``LogLevel``, for the same reason.
///
/// **Control characters decode to nil, not to a glyph.** A hex view showing a
/// backspace as a real backspace would move the caret it is drawing; showing
/// a byte that means nothing in this encoding as an arbitrary letter would be
/// a lie. Both are the view's ``HexView/unprintable`` character.
public struct ByteEncoding: Hashable, Sendable {

    /// What the picker calls it.
    public let name: String

    /// How the bytes are read.
    ///
    /// The two multi-byte members cannot be a table -- the whole point of them
    /// is that a character's width is a property of the bytes, not of the
    /// encoding -- so this is a small closed set with an open table case.
    enum Kind: Hashable, Sendable {
        /// 256 entries, one character (or nil) per byte value.
        case table([Character?])
        case utf8
        case utf16(bigEndian: Bool)
    }
    let kind: Kind

    /// Creates a single-byte encoding from a 256-entry table.
    ///
    /// - Parameters:
    ///   - name: What the picker calls it.
    ///   - table: One entry per byte value; nil for "do not show this one".
    ///     Shorter tables are padded with nil, longer ones truncated, because
    ///     a code page that is one entry short should show a dot rather than
    ///     trap in a drawing pass.
    public init(name: String, table: [Character?]) {
        var padded = Array(table.prefix(256))
        padded.append(contentsOf: repeatElement(nil, count: 256 - padded.count))
        self.name = name
        self.kind = .table(padded)
    }

    init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// Whether one byte is always one character.
    ///
    /// Asked before the text column accepts typing: overtyping a one-byte
    /// character with a three-byte one in a buffer whose length is fixed is
    /// not an edit, it is a corruption. The hex column stays editable in every
    /// encoding, because a byte is a byte.
    public var isSingleByte: Bool {
        if case .table = kind { return true }
        return false
    }

    /// The most bytes one character can be written on.
    ///
    /// A decoder reading a window has to be allowed to read this far PAST the
    /// last byte it means to draw, or a character straddling the end of the
    /// window decodes as a broken sequence -- which on screen is a row whose
    /// last character is a dot for no reason the reader can see.
    public var maximumBytesPerCharacter: Int {
        switch kind {
        case .table: return 1
        case .utf8, .utf16: return 4
        }
    }

    /// The byte that writes `character`, or nil if this encoding cannot.
    public func byte(for character: Character) -> UInt8? {
        guard case let .table(table) = kind else { return nil }
        return table.firstIndex(of: character).map(UInt8.init)
    }

    // MARK: - The built-in four

    /// 7-bit ASCII: 0x20 to 0x7E, and nothing else.
    public static let ascii = ByteEncoding(name: "ASCII", table: asciiTable)

    /// EBCDIC, code page 037 -- the IBM mainframe encoding, where the letters
    /// are not contiguous and 0x40 is the space.
    public static let ebcdic = ByteEncoding(name: "EBCDIC", table: ebcdicTable)

    /// UTF-8. A character is one to four bytes and is drawn across them.
    public static let utf8 = ByteEncoding(name: "UTF-8", kind: .utf8)

    /// UTF-16, little-endian -- the byte order these platforms write.
    ///
    /// Unqualified "UTF-16" means big-endian in the standard and
    /// little-endian on every machine this runs on, which is exactly the kind
    /// of disagreement a hex view exists to settle. Both are here;
    /// ``utf16BigEndian`` is the other one, and it is not in ``standard``
    /// only because four choices was the ask.
    public static let utf16 = ByteEncoding(name: "UTF-16", kind: .utf16(bigEndian: false))

    /// UTF-16, big-endian.
    public static let utf16BigEndian =
        ByteEncoding(name: "UTF-16 BE", kind: .utf16(bigEndian: true))

    /// The four the encoding picker offers unless told otherwise.
    public static let standard: [ByteEncoding] = [.ascii, .ebcdic, .utf8, .utf16]

    // MARK: - Reading bytes

    /// Reads `bytes` into cells, one cell per character.
    ///
    /// The cells' `byteCount`s add up to `bytes.count` exactly, so a caller
    /// can walk cells and byte offsets together without a second index.
    public func cells(for bytes: some Collection<UInt8>) -> [ByteCell] {
        let values = Array(bytes)
        switch kind {
        case let .table(table):
            return values.map { ByteCell(character: table[Int($0)], byteCount: 1) }
        case .utf8:
            return Self.utf8Cells(values)
        case let .utf16(bigEndian):
            return Self.utf16Cells(values, bigEndian: bigEndian)
        }
    }

    /// How far back from `offset` a decoder has to start to read the byte at
    /// `offset` correctly.
    ///
    /// **A hex view decodes a window, not a file.** Scrolled to the middle of
    /// a gigabyte, it cannot decode from byte zero to find out what the first
    /// visible byte says -- but it cannot start exactly at the first visible
    /// byte either, or a character straddling the top edge of the screen
    /// decodes as rubbish.
    ///
    /// UTF-8 is self-synchronising: a continuation byte is `10xxxxxx` and a
    /// lead byte never is, so scanning back at most three bytes finds the
    /// start of whatever character `offset` is inside. UTF-16 is not
    /// self-synchronising at all -- `00 41` and `41 00` are both valid and
    /// mean different things -- so its alignment is taken from the start of
    /// the data, which is the only place a UTF-16 stream can be said to begin.
    public func windowStart(before offset: Int, in bytes: some Collection<UInt8>) -> Int {
        switch kind {
        case .table:
            return offset
        case .utf8:
            let values = Array(bytes)
            var start = offset
            var stepped = 0
            while start > 0, stepped < 3, start < values.count,
                  values[start] & 0b1100_0000 == 0b1000_0000 {
                start -= 1
                stepped += 1
            }
            return start
        case .utf16:
            return offset - (offset % 2)
        }
    }

    // MARK: - The multi-byte readers

    private static func utf8Cells(_ bytes: [UInt8]) -> [ByteCell] {
        var cells: [ByteCell] = []
        var index = 0
        while index < bytes.count {
            let lead = bytes[index]
            let width: Int
            switch lead {
            case 0x00...0x7F: width = 1
            case 0xC2...0xDF: width = 2
            case 0xE0...0xEF: width = 3
            case 0xF0...0xF4: width = 4
            default: width = 0          // a continuation byte, or 0xC0/0xC1/0xF5+
            }
            // A sequence running off the end of the window is not a broken
            // sequence -- it is a sequence the window cut in half -- but there
            // is nothing to draw for it either way.
            guard width > 0, index + width <= bytes.count,
                  let text = String(bytes: bytes[index..<(index + width)], encoding: .utf8),
                  let character = text.first, text.count == 1 else {
                cells.append(ByteCell(character: nil, byteCount: 1))
                index += 1
                continue
            }
            cells.append(ByteCell(character: showable(character), byteCount: width))
            index += width
        }
        return cells
    }

    private static func utf16Cells(_ bytes: [UInt8], bigEndian: Bool) -> [ByteCell] {
        var cells: [ByteCell] = []
        var index = 0
        func unit(at position: Int) -> UInt16? {
            guard position + 1 < bytes.count else { return nil }
            let high = UInt16(bytes[position]), low = UInt16(bytes[position + 1])
            return bigEndian ? (high << 8) | low : (low << 8) | high
        }
        while index < bytes.count {
            guard let first = unit(at: index) else {
                cells.append(ByteCell(character: nil, byteCount: 1))
                index += 1
                continue
            }
            // A surrogate pair is one character written on four bytes; a lone
            // surrogate is not a character at all.
            if (0xD800...0xDBFF).contains(first), let second = unit(at: index + 2),
               (0xDC00...0xDFFF).contains(second) {
                let scalarValue = 0x10000
                    + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
                let character = Unicode.Scalar(scalarValue).map(Character.init)
                cells.append(ByteCell(character: character.flatMap(showable),
                                         byteCount: 4))
                index += 4
                continue
            }
            let character = Unicode.Scalar(first).map(Character.init)
            cells.append(ByteCell(character: character.flatMap(showable), byteCount: 2))
            index += 2
        }
        return cells
    }

    /// A character the view can draw, or nil for one it must not.
    private static func showable(_ character: Character) -> Character? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else { return character }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned,
             .lineSeparator, .paragraphSeparator:
            return nil
        default:
            return character
        }
    }

    // MARK: - The tables

    private static let asciiTable: [Character?] = (0..<256).map { value in
        (0x20...0x7E).contains(value) ? Character(Unicode.Scalar(UInt8(value))) : nil
    }

    /// IBM code page 037, generated from the Unicode mapping and then stripped
    /// of everything a view must not draw.
    private static let ebcdicTable: [Character?] = [
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil,
        " ", " ", "â", "ä", "à", "á", "ã", "å",
        "ç", "ñ", "¢", ".", "<", "(", "+", "|",
        "&", "é", "ê", "ë", "è", "í", "î", "ï",
        "ì", "ß", "!", "$", "*", ")", ";", "¬",
        "-", "/", "Â", "Ä", "À", "Á", "Ã", "Å",
        "Ç", "Ñ", "¦", ",", "%", "_", ">", "?",
        "ø", "É", "Ê", "Ë", "È", "Í", "Î", "Ï",
        "Ì", "`", ":", "#", "@", "'", "=", "\"",
        "Ø", "a", "b", "c", "d", "e", "f", "g",
        "h", "i", "«", "»", "ð", "ý", "þ", "±",
        "°", "j", "k", "l", "m", "n", "o", "p",
        "q", "r", "ª", "º", "æ", "¸", "Æ", "¤",
        "µ", "~", "s", "t", "u", "v", "w", "x",
        "y", "z", "¡", "¿", "Ð", "Ý", "Þ", "®",
        "^", "£", "¥", "·", "©", "§", "¶", "¼",
        "½", "¾", "[", "]", "¯", "¨", "´", "×",
        "{", "A", "B", "C", "D", "E", "F", "G",
        "H", "I", nil, "ô", "ö", "ò", "ó", "õ",
        "}", "J", "K", "L", "M", "N", "O", "P",
        "Q", "R", "¹", "û", "ü", "ù", "ú", "ÿ",
        "\\", "÷", "S", "T", "U", "V", "W", "X",
        "Y", "Z", "²", "Ô", "Ö", "Ò", "Ó", "Õ",
        "0", "1", "2", "3", "4", "5", "6", "7",
        "8", "9", "³", "Û", "Ü", "Ù", "Ú", nil
    ]
}
