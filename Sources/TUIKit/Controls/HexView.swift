import Foundation

/// A hex editor: addresses, bytes, and what those bytes say in ASCII,
/// EBCDIC, UTF-8 or UTF-16.
///
///     let view = HexView(bytes: [UInt8](contents))   // fits the width
///     view.encoding = .utf8
///     view.onEdit = { offset, byte in patch(offset, byte) }
///
/// **Three columns of fixed-width text, which is the one shape a terminal
/// renders better than any canvas.** The grid sits under an optional control
/// bar — a Bytes picker (Fit, 4 … 64) and a Text picker over
/// ``encodingChoices`` — the same bar `AUIHexView` wears, because the two
/// are one control on two backends.
///
/// **Fitting is the default.** `bytesPerRow = 0` puts as many bytes on a row
/// as the width allows, so the view re-flows with the window; pin it to 8 or
/// 16 to compare two dumps side by side. `rowsShown` pins the height the
/// same way.
///
/// **Editable is the default; read-only is a mode.** `isEditable = false`
/// keeps the caret and the address callback — they are most of what a
/// *viewer* is for — but draws no cursor: a cursor is a promise that typing
/// will land, and a read-only view is not accepting any.
@MainActor
public final class HexView: TUIView {
    // MARK: - What is shown

    /// The bytes on show.
    public var bytes: [UInt8] {
        didSet {
            clampCaret()
            setNeedsDisplay()
        }
    }

    /// The address the first byte is labelled with. A window onto a file at
    /// an offset, or a dump of memory, does not start at zero.
    public var baseAddress: UInt64 = 0 {
        didSet { setNeedsDisplay() }
    }

    /// Bytes per row, or **0 to fit the width** — the default.
    public var bytesPerRow = 0 {
        didSet {
            guard bytesPerRow != oldValue else { return }

            // The picker is a view of this property, not a second copy of
            // it: set in code, it has to move too.
            if let index = Self.widthChoices.firstIndex(of: bytesPerRow) {
                widthPicker.select(index)
            }

            setNeedsDisplay()
        }
    }

    /// Rows of bytes on show, or **0 to fit the height** — the default.
    ///
    /// Pinned, the view's natural height is exactly this many rows (plus the
    /// control bar when shown) and the grid scrolls inside it.
    public var rowsShown = 0 {
        didSet {
            guard rowsShown != oldValue else { return }

            setNeedsLayout()
            setNeedsDisplay()
        }
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

    /// Whether the text column is drawn.
    public var showsTextColumn = true {
        didSet {
            guard showsTextColumn != oldValue else { return }

            if !showsTextColumn {
                isEditingText = false
            }

            setNeedsDisplay()
        }
    }

    /// How the bytes are read into the text column.
    ///
    /// In a multi-byte encoding (UTF-8, UTF-16) a character is drawn ACROSS
    /// its bytes, and the text column stops accepting the caret — overtyping
    /// a one-byte character with a three-byte one in a fixed-length buffer
    /// is not an edit. The hex column stays editable in every encoding,
    /// because a byte is a byte.
    public var encoding: ByteEncoding = .ascii {
        didSet {
            guard encoding != oldValue else { return }

            if !encoding.isSingleByte, isEditingText {
                isEditingText = false
            }

            syncEncodingPicker()
            setNeedsDisplay()
        }
    }

    /// What the Text picker offers.
    public var encodingChoices: [ByteEncoding] = ByteEncoding.standard {
        didSet { rebuildEncodingPicker() }
    }

    /// What stands in for a byte the encoding will not show.
    public var unprintable: Character = "." {
        didSet {
            if unprintable != oldValue { setNeedsDisplay() }
        }
    }

    // MARK: - Editing

    /// Whether typing changes bytes. On by default; off is the viewer mode —
    /// the caret and ``onCaretMoved`` keep working, but no cursor is drawn
    /// and typing changes nothing.
    public var isEditable = true {
        didSet {
            if isEditable != oldValue { setNeedsDisplay() }
        }
    }

    /// The two ways the edit cursor is drawn.
    public enum CursorStyle: Sendable {
        /// The cell inverted under the caret. The default.
        case block

        /// The classic bar: an underline beneath the character.
        case underline
    }

    /// How the edit cursor is drawn.
    public var cursorStyle: CursorStyle = .block {
        didSet { setNeedsDisplay() }
    }

    /// Whether the bar with the Bytes and Text pickers is shown.
    ///
    /// Hide it for an inspector pane that is exactly as big as it says —
    /// the "eight bytes a row, three rows, no chrome" shape.
    public var showsControlBar = true {
        didSet {
            guard showsControlBar != oldValue else { return }

            for control in barControls {
                control.isHidden = !showsControlBar
            }

            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    // MARK: - Reporting

    /// Called with the whole buffer after an edit. Copy-on-write, so handing
    /// it over costs nothing until somebody keeps it.
    public var onChange: (([UInt8]) -> Void)?

    /// Called with the offset and the new value when a byte is edited.
    public var onEdit: ((Int, UInt8) -> Void)?

    /// Called when the caret moves, with its byte offset.
    public var onCaretMoved: ((Int) -> Void)?

    // MARK: - Where the caret is

    /// The byte the caret is on.
    public private(set) var caret = 0

    /// Which half of the byte the caret is on in the hex column: 0 is the
    /// high nibble. Two keystrokes per byte, high nibble first, the way a
    /// hex editor has typed since there were hex editors.
    public private(set) var caretNibble = 0

    /// Whether the caret is in the text column. Tab crosses over — in a
    /// single-byte encoding.
    public private(set) var isEditingText = false

    // The first row of bytes on screen.
    private var topRow = 0

    // MARK: - The control bar

    /// The row widths the Bytes picker offers. 0 is "Fit".
    public static let widthChoices = [0, 4, 8, 16, 24, 32, 64]

    /// What a width choice is called in the picker.
    nonisolated static func widthChoiceName(_ count: Int) -> String {
        count == 0 ? "Fit" : String(count)
    }

    private let bytesLabel = Label("Bytes")
    private let textLabel = Label("Text")
    private let widthPicker = PopUpButton(items: HexView.widthChoices.map(HexView.widthChoiceName), selectedIndex: 0)
    private let encodingPicker = PopUpButton()

    private var barControls: [TUIView] {
        [bytesLabel, widthPicker, textLabel, encodingPicker]
    }

    /// Creates a hex view.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to show.
    ///   - baseAddress: The address of the first byte.
    public init(bytes: [UInt8] = [], baseAddress: UInt64 = 0) {
        self.bytes = bytes
        self.baseAddress = baseAddress
        super.init(frame: .zero)

        var quiet = CellStyle()
        quiet.flags.insert(.dim)
        bytesLabel.style = quiet
        textLabel.style = quiet

        widthPicker.onSelectionChanged = { [weak self] index in
            guard let self, Self.widthChoices.indices.contains(index) else { return }
            bytesPerRow = Self.widthChoices[index]
        }

        rebuildEncodingPicker()
        barControls.forEach(addSubview)
    }

    /// A hex view takes keyboard focus: it has a caret.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// A pinned row width exactly; sixteen bytes' worth when fitting. A
    /// pinned `rowsShown` exactly; every row when fitting.
    public override var intrinsicContentSize: Size? {
        let perRow = bytesPerRow > 0 ? bytesPerRow : 16
        let rows = rowsShown > 0 ? rowsShown : max(1, (bytes.count + perRow - 1) / perRow)
        return Size(width: rowWidth(perRow: perRow), height: rows + (showsControlBar ? 1 : 0))
    }

    /// The pickers take the top row when the bar is shown.
    public override func layoutSubviews() {
        super.layoutSubviews()

        guard showsControlBar, bounds.size.width > 0 else { return }

        var x = 0

        for control in [bytesLabel, widthPicker, textLabel, encodingPicker] {
            let width = min(control.intrinsicContentSize?.width ?? 6, max(0, bounds.size.width - x))
            control.frame = Rect(x: x, y: 0, width: width, height: 1)
            x += width + 1
        }
    }

    private func rebuildEncodingPicker() {
        encodingPicker.items = encodingChoices.map(\.name)
        syncEncodingPicker()

        encodingPicker.onSelectionChanged = { [weak self] index in
            guard let self, encodingChoices.indices.contains(index) else { return }
            encoding = encodingChoices[index]
        }

        setNeedsLayout()
    }

    private func syncEncodingPicker() {
        if let index = encodingChoices.firstIndex(of: encoding) {
            encodingPicker.select(index)
        }
    }

    // MARK: - Geometry

    /// Address digits: enough for the last address, never fewer than four.
    private var addressDigits: Int {
        let last = baseAddress &+ UInt64(max(0, bytes.count - 1))
        return max(4, String(last, radix: 16).count)
    }

    // The grid starts under the control bar.
    private var gridTop: Int {
        showsControlBar ? 1 : 0
    }

    private var gridRows: Int {
        max(1, bounds.size.height - gridTop)
    }

    // The wider gap after each group of hex pairs — the column rhythm a
    // dump is counted by. `bytesPerGroup` 0 or 1 means no grouping.
    private var groupSize: Int {
        bytesPerGroup > 1 ? bytesPerGroup : 0
    }

    // Extra gap columns to the left of hex column `column`.
    private func gaps(beforeColumn column: Int) -> Int {
        groupSize > 0 ? column / groupSize : 0
    }

    // The hex pane's width: pairs, their single spaces, and the group gaps.
    private func hexWidth(perRow: Int) -> Int {
        perRow * 3 - 1 + (groupSize > 0 ? (perRow - 1) / groupSize : 0)
    }

    private func rowWidth(perRow: Int) -> Int {
        // address, two spaces, the hex pane — and the text column after two
        // more, when it is shown.
        let hex = addressDigits + 2 + hexWidth(perRow: perRow)
        return showsTextColumn ? hex + 2 + perRow : hex
    }

    /// How many bytes fit a row of `width` columns.
    ///
    /// With the text column, each byte costs four columns — two hex digits,
    /// the space after them, and one character of text; without it, three —
    /// plus the group gap after every eight.
    func bytesThatFit(width: Int) -> Int {
        guard bytesPerRow == 0 else { return bytesPerRow }

        var count = Swift.max(1, (width - addressDigits) / 3)

        while count > 1, rowWidth(perRow: count) > width {
            count -= 1
        }

        guard fitSnapsToGroups, bytesPerGroup > 1 else {
            return count
        }

        // Down to a whole group -- see `fitSnapsToGroups`. Narrower than one
        // group shows what it can rather than nothing.
        let groups = count / bytesPerGroup
        return groups > 0 ? groups * bytesPerGroup : count
    }

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        let width = bounds.size.width
        let height = bounds.size.height

        guard width > 0, height > gridTop else {
            return
        }

        let theme = effectiveTheme
        let perRow = bytesThatFit(width: width)
        let digits = addressDigits
        let hexStart = digits + 2
        let textStart = hexStart + hexWidth(perRow: perRow) + 2

        scrollCaretIntoView(perRow: perRow, rows: gridRows)

        for screenRow in 0..<gridRows {
            let start = (topRow + screenRow) * perRow

            guard start < bytes.count else {
                break
            }

            let y = gridTop + screenRow
            let end = Swift.min(bytes.count, start + perRow)
            let address = String(format: "%0\(digits)llX", baseAddress &+ UInt64(start))
            painter.write(address, at: Point(x: 0, y: y), style: theme.placeholder)

            for (column, offset) in (start..<end).enumerated() {
                painter.write(String(format: "%02X", bytes[offset]),
                              at: Point(x: hexStart + column * 3 + gaps(beforeColumn: column), y: y),
                              style: CellStyle())
            }

            if showsTextColumn {
                drawText(painter, rowStart: start, rowEnd: end, at: Point(x: textStart, y: y))
            }

            drawCursor(painter, rowStart: start, rowEnd: end, y: y, hexStart: hexStart, textStart: textStart, theme: theme)
        }
    }

    /// The text column for one row: characters drawn ACROSS their bytes.
    ///
    /// **Decoded from a window that starts before the row.** A UTF-8
    /// character can straddle the top edge of the row, and starting the
    /// decoder at the first visible byte would read the tail of that
    /// character as rubbish — `windowStart(before:in:)` backs up to a lead
    /// byte. It reads PAST the row too: a character straddling the end of a
    /// row is not a broken sequence, and a row whose last character is a dot
    /// because the window stopped mid-character is a lie about the bytes.
    private func drawText(_ painter: Painter, rowStart: Int, rowEnd: Int, at origin: Point) {
        let start = encoding.windowStart(before: rowStart, in: bytes)
        let window = Swift.min(bytes.count, rowEnd + encoding.maximumBytesPerCharacter - 1)

        guard start < window else { return }

        var quiet = CellStyle()
        quiet.flags.insert(.dim)

        var position = start

        for cell in encoding.cells(for: bytes[start..<window]) {
            defer { position += cell.byteCount }

            // Cells that ended before this row began are only here to get
            // the decoder in step; they are drawn on the row they belong to.
            guard position + cell.byteCount > rowStart, position < rowEnd else { continue }

            let column = position - rowStart

            guard column >= 0 else { continue }

            let character = cell.character ?? unprintable
            let span = Swift.min(cell.byteCount, rowEnd - position)

            // Centred over the bytes it occupies, so a three-byte character
            // sits over its three bytes rather than at the first of them.
            let x = origin.x + column + Swift.max(0, (span - DisplayWidth.of(character)) / 2)
            painter.write(String(character), at: Point(x: x, y: origin.y),
                          style: cell.character == nil ? quiet : CellStyle())
        }
    }

    /// The edit cursor — on the nibble (or character) the next keystroke
    /// replaces — and a quiet mark on the same byte in the other column. A
    /// read-only view draws neither: a cursor is a promise that typing will
    /// land, and this view is not accepting any.
    private func drawCursor(_ painter: Painter, rowStart: Int, rowEnd: Int, y: Int, hexStart: Int, textStart: Int, theme: ResolvedTheme) {
        guard isEditable, !bytes.isEmpty, (rowStart..<rowEnd).contains(caret) else { return }

        let column = caret - rowStart
        let digits = String(format: "%02X", bytes[caret])

        var cursor = CellStyle()

        switch cursorStyle {
        case .block:
            cursor = theme.selection

            if isFirstResponder {
                cursor.flags.insert(.bold)
            }

        case .underline:
            cursor.flags.insert(.underline)

            if isFirstResponder {
                cursor.flags.insert(.bold)
            }
        }

        var marker = CellStyle()
        marker.flags.insert(.underline)

        let hexX = hexStart + column * 3 + gaps(beforeColumn: column)
        let character = encoding.isSingleByte
            ? String(encoding.cells(for: [bytes[caret]]).first?.character ?? unprintable)
            : nil

        if isEditingText {
            // The cursor rides the character; the byte's digits carry the
            // quiet mark.
            painter.write(character ?? " ", at: Point(x: textStart + column, y: y), style: cursor)
            painter.write(digits, at: Point(x: hexX, y: y), style: marker)
        } else {
            // On the nibble the next keystroke replaces.
            let nibble = digits[digits.index(digits.startIndex, offsetBy: caretNibble)]
            painter.write(String(nibble), at: Point(x: hexX + caretNibble, y: y), style: cursor)

            if showsTextColumn, encoding.isSingleByte, let character {
                painter.write(character, at: Point(x: textStart + column, y: y), style: marker)
            }
        }
    }

    private func scrollCaretIntoView(perRow: Int, rows: Int) {
        let row = caret / perRow

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
        case .left:      stepBack(); return true
        case .right:     stepForward(); return true
        case .up:        return moveCaret(to: caret - perRow, nibble: caretNibble)
        case .down:      return moveCaret(to: caret + perRow, nibble: caretNibble)

        case .home:
            // The row's edges — a dump is read a row at a time.
            return moveCaret(to: caret - caret % perRow)

        case .end:
            return moveCaret(to: Swift.min(caret - caret % perRow + perRow - 1, bytes.count - 1))

        case .pageUp:
            return moveCaret(to: caret - perRow * gridRows, nibble: caretNibble)

        case .pageDown:
            return moveCaret(to: caret + perRow * gridRows, nibble: caretNibble)

        case .tab:
            // Tab crosses to the other column rather than leaving the view —
            // in a single-byte encoding; see ``encoding``.
            guard showsTextColumn, encoding.isSingleByte else { return false }
            isEditingText.toggle()
            caretNibble = 0
            setNeedsDisplay()
            return true

        case .character(let typed):
            return type(typed)

        default:
            return false
        }
    }

    /// Types one character at the caret.
    private func type(_ typed: Character) -> Bool {
        guard isEditable, !bytes.isEmpty else {
            return false
        }

        if isEditingText {
            // Only reachable in a single-byte encoding; the byte is whatever
            // this encoding writes the character as.
            guard let byte = encoding.byte(for: typed) else { return false }
            write(byte, at: caret)
            stepForward()
            return true
        }

        guard let digit = typed.hexDigitValue, digit >= 0, digit <= 15 else {
            return false
        }

        // Half a byte at a time, high nibble first.
        let old = bytes[caret]
        let new = caretNibble == 0
            ? (old & 0x0F) | (UInt8(digit) << 4)
            : (old & 0xF0) | UInt8(digit)
        write(new, at: caret)
        stepForward()
        return true
    }

    private func write(_ byte: UInt8, at offset: Int) {
        bytes[offset] = byte
        onEdit?(offset, byte)
        onChange?(bytes)
        setNeedsDisplay()
    }

    // MARK: - Stepping

    /// One nibble forward in the hex column, one byte in the text column.
    private func stepForward() {
        if !isEditingText, caretNibble == 0 {
            caretNibble = 1
            setNeedsDisplay()
        } else {
            _ = moveCaret(to: Swift.min(caret + 1, Swift.max(0, bytes.count - 1)))
        }
    }

    private func stepBack() {
        if !isEditingText, caretNibble == 1 {
            caretNibble = 0
            setNeedsDisplay()
        } else {
            _ = moveCaret(to: Swift.max(0, caret - 1), nibble: isEditingText ? 0 : 1)
        }
    }

    @discardableResult
    private func moveCaret(to offset: Int, nibble: Int = 0) -> Bool {
        let target = Swift.min(Swift.max(offset, 0), Swift.max(0, bytes.count - 1))
        let targetNibble = Swift.min(Swift.max(0, nibble), 1)

        guard target != caret || targetNibble != caretNibble else {
            return false
        }

        let moved = target != caret
        caret = target
        caretNibble = targetNibble

        if moved {
            onCaretMoved?(caret)
        }

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

            owningWindow?.makeFirstResponder(self)
            // The text column takes the caret only where it takes typing.
            isEditingText = hit.inText && encoding.isSingleByte
            _ = moveCaret(to: hit.offset, nibble: hit.nibble)
            setNeedsDisplay()
            return true

        default:
            return false
        }
    }

    /// The byte a click landed on, which column it was in, and — in the hex
    /// column — which nibble.
    func byteOffset(at point: Point, perRow: Int) -> (offset: Int, inText: Bool, nibble: Int)? {
        let digits = addressDigits
        let hexStart = digits + 2
        let hexEnd = hexStart + hexWidth(perRow: perRow)
        let textStart = hexEnd + 2
        let row = topRow + point.y - gridTop

        guard point.y >= gridTop else { return nil }

        let column: Int
        let inText: Bool
        var nibble = 0

        switch point.x {
        case hexStart..<hexEnd:
            var offset = point.x - hexStart

            if groupSize > 0 {
                // A group block is its pairs, their spaces, and the gap.
                let block = groupSize * 3 + 1
                let group = offset / block
                // A click on the gap itself clamps to the group's last byte.
                let within = Swift.min(offset % block, groupSize * 3 - 1)
                offset = group * groupSize * 3 + within
                column = group * groupSize + within / 3
                nibble = within % 3 == 1 ? 1 : 0
            } else {
                column = offset / 3
                nibble = offset % 3 == 1 ? 1 : 0
            }

            inText = false
        case textStart..<(textStart + perRow) where showsTextColumn:
            column = point.x - textStart
            inText = true
        default:
            return nil
        }

        let offset = row * perRow + column

        guard offset >= 0, offset < bytes.count else {
            return nil
        }

        return (offset, inText, nibble)
    }
}
