import Foundation

/// Month-grid calendar (framework-internal), used inline by `DatePicker`'s
/// `.calendar` mode and as its date-mode popup.
@MainActor
final class CalendarView: View {
    var onDateChanged: (Date) -> Void = { _ in }
    var onChoose: (Date) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    private let calendar: Calendar
    private let isPopup: Bool
    private var date: Date
    private var isDismissed = false

    // Two-letter weekday labels, Sunday first; rotated to the calendar's
    // first weekday at render time.
    private static let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    init(date: Date, calendar: Calendar, isPopup: Bool) {
        self.date = date
        self.calendar = calendar
        self.isPopup = isPopup
        super.init(frame: .zero)
    }

    /// Creates, places, and focuses a popup grid anchored to a view.
    static func present(date: Date, calendar: Calendar, anchor: View) -> CalendarView? {
        var window: Window?
        var origin = Point.zero
        var current: View? = anchor

        while let view = current {
            if let found = view as? Window {
                window = found
                break
            }

            origin = origin + view.frame.origin
            current = view.superview
        }

        guard let window else {
            return nil
        }

        let grid = CalendarView(date: date, calendar: calendar, isPopup: true)
        let size = grid.intrinsicContentSize ?? contentSize(isPopup: true)
        let spaceBelow = window.bounds.size.height - (origin.y + 1)

        let y = spaceBelow >= size.height || origin.y < size.height
            ? origin.y + 1
            : origin.y - size.height

        grid.frame = Rect(
            origin: Point(
                x: max(0, min(origin.x, window.bounds.size.width - size.width)),
                y: max(0, y)
            ),
            size: size
        )

        window.addSubview(grid)
        window.makeFirstResponder(grid)
        return grid
    }

    // Content size for a month grid: title + weekday header + 6 week rows,
    // 20 cells wide, plus a border when shown as a popup.
    static func contentSize(isPopup: Bool) -> Size {
        let inset = isPopup ? 2 : 0
        return Size(width: 20 + inset, height: 8 + inset)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: Size? {
        Self.contentSize(isPopup: isPopup)
    }

    func setDate(_ newDate: Date) {
        guard newDate != date else {
            return
        }

        date = newDate
        setNeedsDisplay()
    }

    override func didResignFirstResponder() {
        if isPopup {
            dismiss()
        }
    }

    override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        let contentOrigin: Point

        if isPopup {
            painter.fill(bounds, with: .blank)
            painter.drawBox(bounds, style: theme.border, border: theme.borderStyle)
            contentOrigin = Point(x: 1, y: 1)
        } else {
            contentOrigin = .zero
        }

        let grid = monthGrid()

        // Title (centered-ish): "July 2026".
        painter.write(grid.title, at: contentOrigin, style: theme.header)

        // Weekday header, rotated to the first weekday.
        var header = ""

        for offset in 0..<7 {
            let label = Self.weekdayLabels[(calendar.firstWeekday - 1 + offset) % 7]
            header += (offset == 0 ? "" : " ") + label
        }

        painter.write(header, at: contentOrigin + Point(x: 0, y: 1), style: theme.placeholder)

        let selectedDay = calendar.component(.day, from: date)

        for (weekIndex, week) in grid.weeks.enumerated() {
            for (dayIndex, day) in week.enumerated() {
                guard let day else {
                    continue
                }

                let cell = String(format: "%2d", day)
                let point = contentOrigin + Point(x: dayIndex * 3, y: 2 + weekIndex)
                let style = day == selectedDay ? theme.selection : CellStyle()
                painter.write(cell, at: point, style: style)
            }
        }
    }

    override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        switch key.key {
        case .left:
            move(byDays: -1)
            return true

        case .right:
            move(byDays: 1)
            return true

        case .up:
            move(byDays: -7)
            return true

        case .down:
            move(byDays: 7)
            return true

        case .pageUp:
            move(byMonths: -1)
            return true

        case .pageDown:
            move(byMonths: 1)
            return true

        case .enter:
            choose()
            return true

        case .escape where isPopup:
            dismiss()
            return true

        default:
            return false
        }
    }

    override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left else {
            return false
        }

        let contentOrigin = isPopup ? Point(x: 1, y: 1) : .zero
        let row = mouse.position.y - contentOrigin.y - 2
        let column = (mouse.position.x - contentOrigin.x) / 3

        guard row >= 0, column >= 0, column < 7 else {
            return false
        }

        let weeks = monthGrid().weeks

        guard weeks.indices.contains(row), let day = weeks[row][column] else {
            return false
        }

        select(day: day)
        choose()
        return true
    }

    // MARK: - Navigation

    private func move(byDays days: Int) {
        guard let moved = calendar.date(byAdding: .day, value: days, to: date) else {
            return
        }

        date = moved
        setNeedsDisplay()
        onDateChanged(moved)
    }

    private func move(byMonths months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: date) else {
            return
        }

        date = moved
        setNeedsDisplay()
        onDateChanged(moved)
    }

    private func select(day: Int) {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.day = day

        guard let moved = calendar.date(from: components), moved != date else {
            return
        }

        date = moved
        setNeedsDisplay()
        onDateChanged(moved)
    }

    private func choose() {
        guard !isDismissed else {
            return
        }

        if isPopup {
            isDismissed = true
        }

        onChoose(date)
    }

    private func dismiss() {
        guard !isDismissed else {
            return
        }

        isDismissed = true
        onDismiss()
    }

    // Grid layout for the month containing `date`.
    private func monthGrid() -> (title: String, weeks: [[Int?]]) {
        let components = calendar.dateComponents([.year, .month], from: date)

        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return ("", [])
        }

        let daysInMonth = range.count
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var cells: [Int?] = Array(repeating: nil, count: leading)
        cells += (1...daysInMonth).map { Optional($0) }

        while cells.count % 7 != 0 || cells.count < 42 {
            cells.append(nil)
        }

        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }

        let monthName = calendar.monthSymbols[(components.month ?? 1) - 1]
        let title = "\(monthName) \(components.year ?? 0)"

        return (title, weeks)
    }
}
