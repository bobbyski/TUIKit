/// Exclusive choice rendered as a row of button-like segments.
///
/// A segmented control is a horizontal `RadioGroup` that looks like joined
/// buttons instead of radio dots — the selected segment is inverted:
///
/// ```text
///   [ Day ][ Week ][ Month ]     ← "Week" selected renders inverted
/// ```
///
/// Left/Right arrows move the selection, Home/End jump to the ends, and a
/// click selects the segment under the pointer. One semantic event:
///
/// ```swift
/// let range = SegmentedControl(["Day", "Week", "Month"], selectedIndex: 1)
/// range.onSelectionChanged = { index in reload(range.segments[index]) }
/// ```
@MainActor
public final class SegmentedControl: TUIView {
    /// Segment titles, leading to trailing.
    public var segments: [String] {
        didSet {
            if segments != oldValue {
                clampSelection()
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Index of the selected segment, when any.
    public private(set) var selectedIndex: Int?

    /// Called when the selection changes through interaction or
    /// `select(_:notify:)`.
    public var onSelectionChanged: (Int) -> Void = { _ in }

    /// Creates a segmented control.
    ///
    /// - Parameters:
    ///   - segments: Segment titles, leading to trailing.
    ///   - selectedIndex: Initially selected segment, when any.
    public init(_ segments: [String], selectedIndex: Int? = nil) {
        self.segments = segments
        self.selectedIndex = selectedIndex
        super.init(frame: .zero)
        clampSelection()
    }

    /// Segmented controls take keyboard focus.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// One row at the summed width of all segments.
    public override var intrinsicContentSize: Size? {
        Size(width: totalWidth, height: 1)
    }

    /// Selects a segment programmatically.
    ///
    /// - Parameters:
    ///   - index: Segment to select.
    ///   - notify: Whether `onSelectionChanged` fires. Defaults to silent.
    public func select(_ index: Int, notify: Bool = false) {
        guard segments.indices.contains(index), index != selectedIndex else {
            return
        }

        selectedIndex = index
        setNeedsDisplay()

        if notify {
            onSelectionChanged(index)
        }
    }

    /// Draws each segment; the selected one is inverted.
    public override func draw(_ painter: Painter) {
        var x = 0

        for (index, title) in segments.enumerated() {
            let label = " \(title) "
            let isSelected = index == selectedIndex
            var flags: CellFlags = []

            if isSelected {
                flags.insert(.inverse)
                if isFirstResponder {
                    flags.insert(.bold)
                }
            } else {
                flags.insert(.dim)
            }

            painter.write(label, at: Point(x: x, y: 0), style: CellStyle(flags: flags))
            x += label.count
        }
    }

    /// Left/Right/Home/End move the selection.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty, !segments.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            moveSelection(by: -1)
            return true

        case .right:
            moveSelection(by: 1)
            return true

        case .home:
            selectAndNotify(0)
            return true

        case .end:
            selectAndNotify(segments.count - 1)
            return true

        default:
            return false
        }
    }

    /// Click selects the segment under the pointer.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        guard let index = segmentIndex(atX: mouse.position.x) else {
            return false
        }

        selectAndNotify(index)
        return true
    }

    // MARK: - Geometry

    // Width of one segment including its padding spaces.
    private func width(of title: String) -> Int {
        title.count + 2
    }

    private var totalWidth: Int {
        segments.reduce(0) { $0 + width(of: $1) }
    }

    // The segment whose x-range contains a local x coordinate.
    private func segmentIndex(atX x: Int) -> Int? {
        var start = 0

        for (index, title) in segments.enumerated() {
            let end = start + width(of: title)

            if x >= start, x < end {
                return index
            }

            start = end
        }

        return nil
    }

    private func moveSelection(by offset: Int) {
        let current = selectedIndex ?? (offset > 0 ? -1 : segments.count)
        selectAndNotify(min(max(0, current + offset), segments.count - 1))
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
        if let selected = selectedIndex, !segments.indices.contains(selected) {
            selectedIndex = segments.isEmpty ? nil : segments.count - 1
        }
    }
}
