import Foundation

/// Date, time, or calendar editor backed by Foundation's `Calendar`.
///
/// ```text
///   2026-07-03 ▾      .date     — Y/M/D segments + a calendar popup
///   14:30             .time     — H/M segments
///   ┌ Jul 2026  ▲▼┐   .calendar — an inline month grid (▲▼ step months)
///   │ Su Mo Tu …  │
///   │  … 3  4  5  │
///   └─────────────┘
/// ```
///
/// In `.date`/`.time` modes the picker is a segmented field: `←`/`→` move
/// between segments, `↑`/`↓` step the focused segment (Foundation does the
/// calendar arithmetic, so month lengths and leap years are handled), and in
/// `.date` mode Space (or clicking the `▾`) drops a month-grid popup. In
/// `.calendar` mode the grid is always visible and the arrows walk days.
///
/// ```swift
/// let due = DatePicker(mode: .date, date: today)
/// due.onDateChanged = { date in task.dueDate = date }
/// ```
@MainActor
public final class DatePicker: TUIView {
    /// Editing modes.
    public enum Mode: Sendable {
        /// `YYYY-MM-DD` segments with a calendar popup.
        case date

        /// `HH:MM` segments.
        case time

        /// An always-visible month grid.
        case calendar
    }

    /// Editing mode.
    public let mode: Mode

    /// Calendar used for all decomposition and arithmetic.
    public let calendar: Calendar

    /// Current date/time value.
    public private(set) var date: Date

    /// Called when the value changes through interaction or
    /// `setDate(_:notify:)`.
    public var onDateChanged: (Date) -> Void = { _ in }

    // Focused segment (date/time modes).
    private var segmentIndex = 0

    // Inline grid (calendar mode) / open popup (date mode).
    private var inlineGrid: CalendarView?
    private var popup: CalendarView?

    /// Creates a date picker.
    ///
    /// - Parameters:
    ///   - mode: Editing mode.
    ///   - date: Initial value.
    ///   - calendar: Calendar for decomposition and arithmetic.
    public init(mode: Mode = .date, date: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.mode = mode
        self.calendar = calendar
        self.date = date
        super.init(frame: .zero)

        if mode == .calendar {
            let grid = CalendarView(date: date, calendar: calendar, isPopup: false)
            grid.anchors = .fill()
            grid.onDateChanged = { [weak self] newDate in
                self?.apply(newDate, notify: true)
            }
            addSubview(grid)
            inlineGrid = grid
        }
    }

    /// Segmented modes take focus; calendar mode delegates focus to its grid.
    public override var acceptsFirstResponder: Bool {
        mode != .calendar
    }

    /// The field width, or the month grid's size.
    public override var intrinsicContentSize: Size? {
        switch mode {
        case .date:
            return Size(width: formatted.count + 2, height: 1)   // "…-…-…" + " ▾"

        case .time:
            return Size(width: formatted.count, height: 1)

        case .calendar:
            return CalendarView.contentSize(isPopup: false)
        }
    }

    /// Sets the value programmatically.
    ///
    /// - Parameters:
    ///   - newDate: Desired value.
    ///   - notify: Whether `onDateChanged` fires. Defaults to silent.
    public func setDate(_ newDate: Date, notify: Bool = false) {
        apply(newDate, notify: notify)
    }

    /// Draws the segmented field (calendar mode draws through its subview).
    public override func draw(_ painter: Painter) {
        guard mode != .calendar else {
            return
        }

        let theme = effectiveTheme
        painter.write(formatted, at: .zero, style: CellStyle())

        // Highlight the focused segment while the field holds focus.
        if isFirstResponder {
            let segment = segments[segmentIndex]
            let text = String(Array(formatted)[segment.range])
            painter.write(text, at: Point(x: segment.range.lowerBound, y: 0), style: theme.selection)
        }

        if mode == .date {
            var glyphStyle = CellStyle()

            if isFirstResponder, theme.accent != .standard {
                glyphStyle.foreground = theme.accent
            }

            painter.set(TerminalCell(character: "▾", style: glyphStyle), at: Point(x: formatted.count + 1, y: 0))
        }
    }

    /// Arrows move/step segments; Space opens the calendar popup.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard mode != .calendar, key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            moveSegment(by: -1)
            return true

        case .right:
            moveSegment(by: 1)
            return true

        case .up:
            step(by: 1)
            return true

        case .down:
            step(by: -1)
            return true

        case .character(" ") where mode == .date:
            openPopup()
            return true

        default:
            return false
        }
    }

    /// Click focuses a segment, or opens the popup on the `▾`.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mode != .calendar, mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        if mode == .date, mouse.position.x == formatted.count + 1 {
            openPopup()
            return true
        }

        for (index, segment) in segments.enumerated() where segment.range.contains(mouse.position.x) {
            segmentIndex = index
            setNeedsDisplay()
            return true
        }

        return false
    }

    // MARK: - Segment model

    private struct Segment {
        let component: Calendar.Component
        let range: Range<Int>
    }

    private var segments: [Segment] {
        switch mode {
        case .date:
            return [
                Segment(component: .year, range: 0..<4),
                Segment(component: .month, range: 5..<7),
                Segment(component: .day, range: 8..<10),
            ]

        case .time:
            return [
                Segment(component: .hour, range: 0..<2),
                Segment(component: .minute, range: 3..<5),
            ]

        case .calendar:
            return []
        }
    }

    private var formatted: String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        switch mode {
        case .date, .calendar:
            return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)

        case .time:
            return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        }
    }

    private func moveSegment(by direction: Int) {
        let count = segments.count

        guard count > 0 else {
            return
        }

        segmentIndex = min(max(0, segmentIndex + direction), count - 1)
        setNeedsDisplay()
    }

    private func step(by delta: Int) {
        let segment = segments[segmentIndex]

        guard let stepped = calendar.date(byAdding: segment.component, value: delta, to: date) else {
            return
        }

        apply(stepped, notify: true)
    }

    // MARK: - Popup

    private func openPopup() {
        guard mode == .date, popup == nil,
              let grid = CalendarView.present(date: date, calendar: calendar, anchor: self) else {
            return
        }

        grid.onDateChanged = { [weak self] newDate in
            self?.apply(newDate, notify: true)
        }

        grid.onChoose = { [weak self] newDate in
            self?.apply(newDate, notify: true)
            self?.closePopup()
        }

        grid.onDismiss = { [weak self] in
            self?.closePopup()
        }

        popup = grid
        setNeedsDisplay()
    }

    private func closePopup() {
        guard let popup else {
            return
        }

        let window = owningWindow
        let popupHadFocus = window?.firstResponder === popup

        self.popup = nil
        popup.removeFromSuperview()

        if popupHadFocus {
            window?.makeFirstResponder(self)
        }

        setNeedsDisplay()
    }

    // MARK: - Value plumbing

    private func apply(_ newDate: Date, notify: Bool) {
        guard newDate != date else {
            return
        }

        date = newDate
        inlineGrid?.setDate(newDate)
        popup?.setDate(newDate)
        setNeedsDisplay()

        if notify {
            onDateChanged(newDate)
        }
    }

    private var owningWindow: Window? {
        var current: TUIView? = self

        while let view = current {
            if let window = view as? Window {
                return window
            }

            current = view.superview
        }

        return nil
    }
}
