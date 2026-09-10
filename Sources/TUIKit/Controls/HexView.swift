import Foundation

/// A hex dump: addresses, bytes, and what those bytes say.
///
///     let view = HexView(bytes: [UInt8](contents))
///     view.baseAddress = 0x1000
///     view.onEdit = { offset, byte in patch(offset, byte) }
///
/// **Three columns of fixed-width text, which is the one shape a terminal
/// renders better than any canvas.** A hex view reached TUIKit late because
/// ActiveUI drew one with `CGContext` on macOS, and the terminal port took
/// that implementation for the definition — it composed rows into a `Label`
/// instead, which reads correctly and cannot carry a caret. This is the
/// control that can.
///
/// **Fitting is the default.** `bytesPerRow = 0` puts as many bytes on a row
/// as the width allows, so the view re-flows with the window; pin it to 8 or
/// 16 to compare two dumps side by side.
///
/// The text column is decoded by ``character(for:)``, a closure rather than an
/// encoding enum: a terminal has no opinion about EBCDIC, and the caller
/// already knows which encoding it means.
@MainActor
public final class HexView: TUIView {
    /// The bytes on show.
    public var bytes: [UInt8] {
        didSet {
            clampCaret()
            setNeedsDisplay()
        }
    }

    /// The address the first byte is labelled with.
    public var baseAddress: UInt64 = 0 {
        didSet { setNeedsDisplay() }
    }

    /// Bytes per row, or 0 to fit the width.
    public var bytesPerRow = 0 {
        didSet { setNeedsDisplay() }
    }

    /// How many bytes a fitted row rounds down to a whole number of.
    public var bytesPerGroup = 8 {
        didSet { setNeedsDisplay() }
    }

    /// Whether a fitted row is rounded down to a whole group.
    ///
    /// On, because a fitted row of 17 bytes fills the width and then steps the
    /// address column by 0x11 -- 1000, 1011, 1022 -- which is arithmetic nobody
    /// does in their head. A dump is read by counting across a row, so the
    /// leftover columns stay empty. Off if you would rather have the width.
    public var fitSnapsToGroups = true {
        didSet { setNeedsDisplay() }
    }

    /// Whether typing hex digits edits the bytes.
    public var isEditable = false

    /// Called with the offset and the new value when a byte is edited.
    public var onEdit: ((Int, UInt8) -> Void)?

    /// Called when the caret moves, with its byte offset.
    public var onCaretMoved: ((Int) -> Void)?

    /// How a byte is shown in the text column.
    ///
    /// Printable ASCII by default; hand it something else for Latin-1, for a
    /// code page, or for the caller's own idea of printable.
    public var character: (UInt8) -> Character = { byte in
        (0x20...0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : "."
    }

    /// The byte the caret sits on.
    public private(set) var caret = 0

    /// Which column the caret is in. Tab moves between them.
    public private(set) var isEditingText = false

    // The first row on screen.
    private var topRow = 0

    // Half-typed byte: the first of the two hex digits, when there is one.
    private var pendingDigit: UInt8?

    /// Creates a hex view.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to show.
    ///   - baseAddress: The address of the first byte.
    public init(bytes: [UInt8] = [], baseAddress: UInt64 = 0) {
        self.bytes = bytes
        self.baseAddress = baseAddress
        super.init(frame: .zero)
    }

    /// A hex view takes keyboard focus: it has a caret.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Sixteen bytes a row, and as many rows as there are.
    public override var intrinsicContentSize: Size? {
        let perRow = bytesPerRow > 0 ? bytesPerRow : 16
        let rows = max(1, (bytes.count + perRow - 1) / perRow)
        return Size(width: rowWidth(perRow: perRow), height: rows)
    }

    // MARK: - Geometry

    /// Address digits: enough for the last address, never fewer than four.
    private var addressDigits: Int {
        let last = baseAddress &+ UInt64(max(0, bytes.count - 1))
        return max(4, String(last, radix: 16).count)
    }

    private func rowWidth(perRow: Int) -> Int {
        // address, two spaces, the hex pairs, two spaces, the text column.
        addressDigits + 2 + (perRow * 3 - 1) + 2 + perRow
    }

    /// How many bytes fit a row of `width` columns.
    ///
    /// Each byte costs four columns — two hex digits, the space after them,
    /// and one character in the text column — over the address and gaps.
    func bytesThatFit(width: Int) -> Int {
        guard bytesPerRow == 0 else { return bytesPerRow }
        let fixed = addressDigits + 4 - 1
        let raw = (width - fixed) / 4

        guard fitSnapsToGroups, bytesPerGroup > 1 else {
            return Swift.max(1, raw)
        }

        // Down to a whole group -- see `fitSnapsToGroups`. Narrower than one
        // group shows what it can rather than nothing.
        let groups = raw / bytesPerGroup
        return groups > 0 ? groups * bytesPerGroup : Swift.max(1, raw)
    }

    /// The row and column the caret is on, for the drawing pass.
    private func position(of offset: Int, perRow: Int) -> (row: Int, column: Int) {
        (offset / perRow, offset % perRow)
    }

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        let width = bounds.size.width
        let height = bounds.size.height

        guard width > 0, height > 0 else {
            return
        }

        let theme = effectiveTheme
        let perRow = bytesThatFit(width: width)
        let digits = addressDigits
        let hexStart = digits + 2
        let textStart = hexStart + perRow * 3 - 1 + 2

        scrollCaretIntoView(perRow: perRow, rows: height)

        for screenRow in 0..<height {
            let start = (topRow + screenRow) * perRow

            guard start < bytes.count else {
                break
            }

            let end = Swift.min(bytes.count, start + perRow)
            let address = String(format: "%0\(digits)llX", baseAddress &+ UInt64(start))
            painter.write(address, at: Point(x: 0, y: screenRow), style: theme.placeholder)

            for (column, offset) in (start..<end).enumerated() {
                let byte = bytes[offset]
                let hexStyle = style(for: offset, inText: false, theme: theme)
                let textStyle = style(for: offset, inText: true, theme: theme)

                painter.write(String(format: "%02X", byte),
                              at: Point(x: hexStart + column * 3, y: screenRow),
                              style: hexStyle)
                painter.write(String(character(byte)),
                              at: Point(x: textStart + column, y: screenRow),
                              style: textStyle)
            }
        }
    }

    // The caret is drawn as the cell it is on, inverted — in whichever column
    // has it. The other column marks the same byte more quietly, so you can
    // see what you are editing on both sides at once.
    private func style(for offset: Int, inText: Bool, theme: ResolvedTheme) -> CellStyle {
        guard offset == caret else {
            return CellStyle()
        }

        var style = CellStyle()

        if inText == isEditingText {
            style = theme.selection

            if isFirstResponder {
                style.flags.insert(.bold)
            }
        } else {
            style.flags.insert(.underline)
        }

        return style
    }

    private func scrollCaretIntoView(perRow: Int, rows: Int) {
        let row = position(of: caret, perRow: perRow).row

        if row < topRow {
            topRow = row
        } else if row >= topRow + rows {
            topRow = row - rows + 1
        }

        topRow = max(0, topRow)
    }

    // MARK: - Keys

    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        let perRow = bytesThatFit(width: max(1, bounds.size.width))

        switch key.key {
        case .left:      return moveCaret(by: -1)
        case .right:     return moveCaret(by: 1)
        case .up:        return moveCaret(by: -perRow)
        case .down:      return moveCaret(by: perRow)
        case .pageUp:    return moveCaret(by: -perRow * max(1, bounds.size.height))
        case .pageDown:  return moveCaret(by: perRow * max(1, bounds.size.height))
        case .home:      return moveCaret(to: 0)
        case .end:       return moveCaret(to: bytes.count - 1)

        case .tab:
            // Tab crosses to the other column rather than leaving the view:
            // a hex editor's two halves are one control.
            isEditingText.toggle()
            pendingDigit = nil
            setNeedsDisplay()
            return true

        case .character(let typed):
            return type(typed)

        default:
            return false
        }
    }

    /// Types one character at the caret.
    ///
    /// In the hex column that is a hex digit, and **two of them make a byte**
    /// — the first is held, the second commits and steps on. In the text
    /// column it is the byte itself, which is only meaningful for a
    /// single-byte encoding, so the caller decides by setting
    /// ``character(for:)`` to match.
    private func type(_ typed: Character) -> Bool {
        guard isEditable, !bytes.isEmpty else {
            return false
        }

        if isEditingText {
            guard let ascii = typed.asciiValue else { return false }
            commit(ascii)
            return true
        }

        guard let digit = typed.hexDigitValue, digit >= 0, digit <= 15 else {
            return false
        }

        if let first = pendingDigit {
            commit(first << 4 | UInt8(digit))
            pendingDigit = nil
        } else {
            pendingDigit = UInt8(digit)
            setNeedsDisplay()
        }

        return true
    }

    private func commit(_ byte: UInt8) {
        bytes[caret] = byte
        onEdit?(caret, byte)
        _ = moveCaret(by: 1)
        setNeedsDisplay()
    }

    @discardableResult
    private func moveCaret(by delta: Int) -> Bool {
        moveCaret(to: caret + delta)
    }

    @discardableResult
    private func moveCaret(to offset: Int) -> Bool {
        let target = Swift.min(Swift.max(offset, 0), Swift.max(0, bytes.count - 1))

        guard target != caret else {
            return false
        }

        caret = target
        pendingDigit = nil
        onCaretMoved?(caret)
        setNeedsDisplay()
        return true
    }

    private func clampCaret() {
        caret = Swift.min(caret, Swift.max(0, bytes.count - 1))
    }

    // MARK: - Mouse

    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        let perRow = bytesThatFit(width: max(1, bounds.size.width))

        switch mouse.action {
        case .scrollUp:
            topRow = max(0, topRow - 3)
            setNeedsDisplay()
            return true

        case .scrollDown:
            let rows = max(1, (bytes.count + perRow - 1) / perRow)
            topRow = Swift.min(max(0, rows - 1), topRow + 3)
            setNeedsDisplay()
            return true

        case .press:
            guard let hit = byteOffset(at: mouse.position, perRow: perRow) else {
                return false
            }
            isEditingText = hit.inText
            _ = moveCaret(to: hit.offset)
            return true

        default:
            return false
        }
    }

    /// The byte a click landed on, and which column it was in.
    func byteOffset(at point: Point, perRow: Int) -> (offset: Int, inText: Bool)? {
        let digits = addressDigits
        let hexStart = digits + 2
        let hexEnd = hexStart + perRow * 3 - 1
        let textStart = hexEnd + 2
        let row = topRow + point.y

        let column: Int
        let inText: Bool

        switch point.x {
        case hexStart..<hexEnd:
            column = (point.x - hexStart) / 3
            inText = false
        case textStart..<(textStart + perRow):
            column = point.x - textStart
            inText = true
        default:
            return nil
        }

        let offset = row * perRow + column

        guard offset >= 0, offset < bytes.count else {
            return nil
        }

        return (offset, inText)
    }
}
