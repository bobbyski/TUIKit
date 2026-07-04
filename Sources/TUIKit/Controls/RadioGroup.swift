/// Exclusive choice among vertically listed options, rendered as `(•)`.
///
/// Arrow keys move the selection; a click selects a row. The application
/// receives one semantic event:
///
/// ```swift
/// let mode = RadioGroup(["Fast", "Accurate", "Balanced"])
/// mode.onSelectionChanged = { index in engine.mode = index }
/// ```
@MainActor
public final class RadioGroup: TUIView {
    /// Option titles, one per row.
    public var options: [String] {
        didSet {
            if options != oldValue {
                clampSelection()
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Index of the selected option, when any.
    public private(set) var selectedIndex: Int?

    /// Called when the selection changes through interaction or
    /// `select(_:notify:)`.
    public var onSelectionChanged: (Int) -> Void = { _ in }

    /// Creates a radio group.
    ///
    /// - Parameters:
    ///   - options: Option titles, one per row.
    ///   - selectedIndex: Initially selected option, when any.
    public init(_ options: [String], selectedIndex: Int? = nil) {
        self.options = options
        self.selectedIndex = selectedIndex
        super.init(frame: .zero)
        clampSelection()
    }

    /// Radio groups take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row per option at `(•) Label` width.
    public override var intrinsicContentSize: Size? {
        let widest = options.map(\.count).max() ?? 0
        return Size(width: widest + 4, height: options.count)
    }

    /// Selects an option programmatically.
    ///
    /// - Parameters:
    ///   - index: Option to select.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int, notify: Bool = false) {
        guard options.indices.contains(index), index != selectedIndex else {
            return
        }

        selectedIndex = index
        setNeedsDisplay()

        if notify {
            onSelectionChanged(index)
        }
    }

    /// Draws one `( )` / `(•)` row per option.
    ///
    /// When focused, the current row (the selection, or the first row when
    /// nothing is selected yet) is fully inverted so focus is always visible.
    public override func draw(_ painter: Painter) {
        let focusRow = selectedIndex ?? 0

        for (index, option) in options.enumerated() {
            let isSelected = index == selectedIndex
            let isFocusRow = isFirstResponder && index == focusRow
            let rowStyle = CellStyle(flags: isFocusRow ? .inverse : [])

            painter.write(isSelected ? "(•)" : "( )", at: Point(x: 0, y: index), style: rowStyle)
            painter.write(
                Label.truncated(option, width: max(0, bounds.size.width - 4)),
                at: Point(x: 4, y: index),
                style: rowStyle
            )
        }
    }

    /// Arrows move the selection.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !options.isEmpty else {
            return false
        }

        switch key.key {
        case .up:
            moveSelection(by: -1)
            return true

        case .down:
            moveSelection(by: 1)
            return true

        default:
            return false
        }
    }

    /// Click selects the clicked row.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press,
              mouse.button == .left,
              options.indices.contains(mouse.position.y) else {
            return false
        }

        selectAndNotify(mouse.position.y)
        return true
    }

    private func moveSelection(by offset: Int) {
        let current = selectedIndex ?? (offset > 0 ? -1 : options.count)
        let next = min(max(0, current + offset), options.count - 1)
        selectAndNotify(next)
    }

    private func selectAndNotify(_ index: Int) {
        guard index != selectedIndex else {
            return
        }

        selectedIndex = index
        setNeedsDisplay()
        onSelectionChanged(index)
    }

    private func clampSelection() {
        if let selected = selectedIndex, !options.indices.contains(selected) {
            selectedIndex = options.isEmpty ? nil : options.count - 1
        }
    }
}
