/// Color chooser covering all three `TerminalColor` families.
///
/// Three tabs — Named, Palette, RGB — mirror `TerminalColor`'s cases:
/// a 16-swatch grid for the named ANSI colors, one stepper for the
/// 256-color palette index, and three steppers for 24-bit RGB. A preview
/// row always shows the current color and its description. The picker is
/// deliberately a composite of existing controls (`TabView`, `Stepper`),
/// so its keyboard and mouse behavior is theirs.
///
/// ```swift
/// let picker = ColorPicker(color: .named(.cyan))
/// picker.onColorChanged = { color in theme.accent = color }
/// ```
@MainActor
public final class ColorPicker: View {
    /// Current color.
    public private(set) var color: TerminalColor

    /// Called when the color changes through interaction or
    /// `setColor(_:notify:)`.
    public var onColorChanged: (TerminalColor) -> Void = { _ in }

    // Composite parts.
    private let tabs = TabView()
    private let swatches: NamedSwatchGrid
    private let paletteStepper = Stepper(value: 0, in: 0...255)
    private let redStepper = Stepper(value: 0, in: 0...255)
    private let greenStepper = Stepper(value: 0, in: 0...255)
    private let blueStepper = Stepper(value: 0, in: 0...255)
    private let preview = ColorPreview()
    private let stack = VStack(spacing: 1)

    /// Creates a color picker.
    ///
    /// - Parameter color: Initial color. Defaults to white.
    public init(color: TerminalColor = .named(.white)) {
        self.color = color
        self.swatches = NamedSwatchGrid()
        super.init(frame: .zero)

        // Named tab.
        swatches.onSelectionChanged = { [weak self] named in
            self?.apply(.named(named))
        }

        // Palette tab.
        let paletteRow = HStack(spacing: 1)
        paletteRow.addSubview(Label("Index:", style: CellStyle(flags: .bold)))
        paletteRow.addSubview(paletteStepper)
        paletteRow.addSubview(View())

        paletteStepper.onValueChanged = { [weak self] value in
            self?.apply(.palette(UInt8(value)))
        }

        // RGB tab.
        let rgbRow = HStack(spacing: 2)

        for (label, stepper) in [("R", redStepper), ("G", greenStepper), ("B", blueStepper)] {
            let pair = HStack(spacing: 1)
            pair.addSubview(Label(label, style: CellStyle(flags: .bold)))
            pair.addSubview(stepper)
            rgbRow.addSubview(pair)
            stepper.onValueChanged = { [weak self] _ in
                self?.applyRGB()
            }
        }

        rgbRow.addSubview(View())

        tabs.addTab("Named", content: swatches)
        tabs.addTab("Palette", content: paletteRow)
        tabs.addTab("RGB", content: rgbRow)

        stack.addSubview(tabs)
        stack.addSubview(preview)
        stack.anchors = .fill()
        addSubview(stack)

        synchronize(to: color)
        preview.show(color)
    }

    /// Fits the widest tab plus the preview row.
    public override var intrinsicContentSize: Size? {
        // Tab bar + separator + named grid (2 rows) + spacing + preview.
        Size(width: 36, height: 6)
    }

    /// Sets the color programmatically, switching to the matching tab.
    ///
    /// - Parameters:
    ///   - newColor: Color to show.
    ///   - notify: Whether `onColorChanged` fires. Defaults to silent.
    public func setColor(_ newColor: TerminalColor, notify: Bool = false) {
        guard newColor != color else {
            return
        }

        color = newColor
        synchronize(to: newColor)
        preview.show(newColor)

        if notify {
            onColorChanged(color)
        }
    }

    // MARK: - Internals

    // Interaction path: record, preview, notify.
    private func apply(_ newColor: TerminalColor) {
        guard newColor != color else {
            return
        }

        color = newColor
        preview.show(newColor)
        onColorChanged(newColor)
    }

    private func applyRGB() {
        apply(.rgb(
            red: UInt8(redStepper.value),
            green: UInt8(greenStepper.value),
            blue: UInt8(blueStepper.value)
        ))
    }

    // Points the parts (and the visible tab) at a color.
    private func synchronize(to newColor: TerminalColor) {
        switch newColor {
        case .named(let named):
            swatches.select(named)
            tabs.select(0)

        case .palette(let index):
            paletteStepper.setValue(Int(index))
            tabs.select(1)

        case .rgb(let red, let green, let blue):
            redStepper.setValue(Int(red))
            greenStepper.setValue(Int(green))
            blueStepper.setValue(Int(blue))
            tabs.select(2)

        case .standard:
            break
        }
    }
}

/// 8×2 grid of the 16 named ANSI colors (framework-internal).
@MainActor
final class NamedSwatchGrid: View {
    var onSelectionChanged: (TerminalColor.NamedColor) -> Void = { _ in }

    private(set) var selectedIndex = 0

    private let colors = TerminalColor.NamedColor.allCases
    private let columns = 8
    private let cellWidth = 4

    init() {
        super.init(frame: .zero)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: Size? {
        Size(width: columns * cellWidth, height: (colors.count + columns - 1) / columns)
    }

    func select(_ color: TerminalColor.NamedColor) {
        if let index = colors.firstIndex(of: color) {
            selectedIndex = index
            setNeedsDisplay()
        }
    }

    override func draw(_ painter: Painter) {
        for (index, color) in colors.enumerated() {
            let origin = Point(x: (index % columns) * cellWidth, y: index / columns)
            let selected = index == selectedIndex
            let bracketStyle = CellStyle(flags: isFirstResponder && selected ? .bold : [])

            painter.write(selected ? "[" : " ", at: origin, style: bracketStyle)
            painter.write("██", at: origin + Point(x: 1, y: 0), style: CellStyle(foreground: .named(color)))
            painter.write(selected ? "]" : " ", at: origin + Point(x: 3, y: 0), style: bracketStyle)
        }
    }

    override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            moveSelection(by: -1)
            return true

        case .right:
            moveSelection(by: 1)
            return true

        case .up:
            moveSelection(by: -columns)
            return true

        case .down:
            moveSelection(by: columns)
            return true

        case .home:
            moveSelection(to: 0)
            return true

        case .end:
            moveSelection(to: colors.count - 1)
            return true

        default:
            return false
        }
    }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        let index = mouse.position.y * columns + mouse.position.x / cellWidth

        guard colors.indices.contains(index), mouse.position.x / cellWidth < columns else {
            return false
        }

        moveSelection(to: index)
        return true
    }

    private func moveSelection(by offset: Int) {
        moveSelection(to: selectedIndex + offset)
    }

    private func moveSelection(to index: Int) {
        let clamped = min(max(0, index), colors.count - 1)

        guard clamped != selectedIndex else {
            return
        }

        selectedIndex = clamped
        setNeedsDisplay()
        onSelectionChanged(colors[clamped])
    }
}

/// Swatch + description of the current color (framework-internal).
@MainActor
final class ColorPreview: View {
    private var color: TerminalColor = .standard
    private var text = ""

    init() {
        super.init(frame: .zero)
    }

    override var intrinsicContentSize: Size? {
        Size(width: 6 + 1 + text.count, height: 1)
    }

    func show(_ newColor: TerminalColor) {
        color = newColor
        text = Self.describe(newColor)
        superview?.setNeedsLayout()
        setNeedsDisplay()
    }

    override func draw(_ painter: Painter) {
        painter.write("██████", at: .zero, style: CellStyle(foreground: color))
        painter.write(
            Label.truncated(text, width: max(0, bounds.size.width - 7)),
            at: Point(x: 7, y: 0),
            style: CellStyle(flags: .dim)
        )
    }

    static func describe(_ color: TerminalColor) -> String {
        color.description
    }
}

/// Human-readable color names ("brightCyan", "palette 42", "rgb(1, 2, 3)").
extension TerminalColor: CustomStringConvertible {
    public var description: String {
        switch self {
        case .standard:
            return "standard"

        case .named(let named):
            return named.rawValue

        case .palette(let index):
            return "palette \(index)"

        case .rgb(let red, let green, let blue):
            return "rgb(\(red), \(green), \(blue))"
        }
    }
}
