import Testing
import Foundation
@testable import TUIKit

// A fixed calendar so month layout and arithmetic are deterministic.
@MainActor
private func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = 1   // Sunday
    return calendar
}

@MainActor
private func makeDate(
    _ calendar: Calendar,
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// MARK: - Date segments

@Test @MainActor func datePickerEditsDateSegments() {
    let calendar = fixedCalendar()
    let picker = DatePicker(mode: .date, date: makeDate(calendar, 2026, 7, 3), calendar: calendar)
    picker.frame = Rect(x: 0, y: 0, width: 14, height: 1)

    let window = Window(frame: Rect(x: 0, y: 0, width: 14, height: 1))
    window.addSubview(picker)

    let line = SceneRenderer(root: window).render(size: Size(width: 14, height: 1)).textLines()[0]
    #expect(line.hasPrefix("2026-07-03 ▾"))

    var changes: [Date] = []
    picker.onDateChanged = { changes.append($0) }
    window.makeFirstResponder(picker)

    window.route(.key(KeyInput(key: .up)))       // year → 2027
    window.route(.key(KeyInput(key: .right)))    // focus month (no change)
    window.route(.key(KeyInput(key: .up)))       // month → August
    window.route(.key(KeyInput(key: .right)))    // focus day (no change)
    window.route(.key(KeyInput(key: .down)))     // day → 2

    let components = calendar.dateComponents([.year, .month, .day], from: picker.date)
    #expect(components.year == 2027)
    #expect(components.month == 8)
    #expect(components.day == 2)
    #expect(changes.count == 3, "only the three steps fire; segment moves are silent")
}

// MARK: - Time segments

@Test @MainActor func datePickerEditsTimeSegments() {
    let calendar = fixedCalendar()
    let picker = DatePicker(mode: .time, date: makeDate(calendar, 2026, 7, 3, 14, 30), calendar: calendar)
    picker.frame = Rect(x: 0, y: 0, width: 5, height: 1)

    let window = Window(frame: Rect(x: 0, y: 0, width: 5, height: 1))
    window.addSubview(picker)

    let line = SceneRenderer(root: window).render(size: Size(width: 5, height: 1)).textLines()[0]
    #expect(line == "14:30")

    window.makeFirstResponder(picker)
    window.route(.key(KeyInput(key: .up)))       // hour → 15
    window.route(.key(KeyInput(key: .right)))    // focus minute
    window.route(.key(KeyInput(key: .down)))     // minute → 29

    let components = calendar.dateComponents([.hour, .minute], from: picker.date)
    #expect(components.hour == 15)
    #expect(components.minute == 29)
}

// MARK: - Calendar popup (date mode)

@Test @MainActor func datePickerPopupPicksADay() {
    let calendar = fixedCalendar()
    let picker = DatePicker(mode: .date, date: makeDate(calendar, 2026, 7, 3), calendar: calendar)
    picker.frame = Rect(x: 2, y: 1, width: 14, height: 1)

    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 14))
    window.addSubview(picker)
    window.makeFirstResponder(picker)

    // Space drops the month grid.
    window.route(.key(KeyInput(key: .character(" "))))
    let lines = SceneRenderer(root: window).render(size: Size(width: 30, height: 14)).textLines()
    #expect(lines.contains { $0.contains("Jul 2026") })
    #expect(lines.contains { $0.contains("Su Mo Tu We Th Fr Sa") })

    // Move a day forward in the popup and choose it; the field updates and
    // the popup closes.
    window.route(.key(KeyInput(key: .right)))
    window.route(.key(KeyInput(key: .enter)))

    #expect(calendar.component(.day, from: picker.date) == 4)

    let closed = SceneRenderer(root: window).render(size: Size(width: 30, height: 14)).textLines()
    #expect(!closed.contains { $0.contains("Jul 2026") }, "the popup dismissed after choosing")
}

// MARK: - Inline calendar mode

@Test @MainActor func datePickerCalendarModeWalksDays() {
    let calendar = fixedCalendar()
    let picker = DatePicker(mode: .calendar, date: makeDate(calendar, 2026, 7, 3), calendar: calendar)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    picker.frame = window.bounds
    window.addSubview(picker)
    window.layoutIfNeeded()

    let lines = SceneRenderer(root: window).render(size: Size(width: 20, height: 8)).textLines()
    #expect(lines[0].hasPrefix("Jul 2026"))
    #expect(lines[1].hasPrefix("Su Mo Tu We Th Fr Sa"))

    var changed: [Date] = []
    picker.onDateChanged = { changed.append($0) }

    _ = window.focusNext()   // focus the inline grid

    window.route(.key(KeyInput(key: .right)))      // 3 → 4
    #expect(calendar.component(.day, from: picker.date) == 4)

    window.route(.key(KeyInput(key: .down)))       // +7 → 11
    #expect(calendar.component(.day, from: picker.date) == 11)

    window.route(.key(KeyInput(key: .pageDown)))   // +1 month → August
    #expect(calendar.component(.month, from: picker.date) == 8)

    #expect(changed.count == 3)
}

@Test @MainActor func calendarMonthSteppersClickToChangeMonth() {
    let calendar = fixedCalendar()
    let picker = DatePicker(mode: .calendar, date: makeDate(calendar, 2026, 7, 3), calendar: calendar)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 8))
    picker.frame = window.bounds
    window.addSubview(picker)
    window.layoutIfNeeded()

    // The title reads a month name, never an ISO "M07" code.
    let title = SceneRenderer(root: window).render(size: Size(width: 20, height: 8)).textLines()[0]
    #expect(title.hasPrefix("Jul 2026"))

    var changed: [Date] = []
    picker.onDateChanged = { changed.append($0) }

    // ▼ at the right of the title row → next month.
    window.route(.mouse(MouseInput(position: Point(x: 19, y: 0), action: .press, button: .left)))
    #expect(calendar.component(.month, from: picker.date) == 8)

    // ▲ → previous month, back to July.
    window.route(.mouse(MouseInput(position: Point(x: 17, y: 0), action: .press, button: .left)))
    #expect(calendar.component(.month, from: picker.date) == 7)

    #expect(changed.count == 2)
}
