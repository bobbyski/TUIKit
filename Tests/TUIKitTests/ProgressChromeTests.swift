import Foundation
import Testing
@testable import TUIKit

// PLAN Phase 10 (VTG chrome), the wider control pass — SUPPORT_TERMINAL_PLAN.md U4.
//
// A progress bar is the shape vector chrome is best at, and the one where the
// cell version is most obviously a rounding of the truth: on a twenty-cell
// track every value between 42% and 47% fills the same eight cells.
//
// Ground rule 8 governs: the cell bar is the path that must work, and it ships
// unchanged. These check that the vector path is *additional*, not a
// replacement for it.

@MainActor
private func commands(for bar: ProgressIndicator, width: Int, chrome: Bool) -> [ChromeCommand] {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: 1))
    bar.frame = Rect(x: 0, y: 0, width: width, height: 1)
    window.addSubview(bar)

    let renderer = SceneRenderer(root: window)
    renderer.chromeEnabled = chrome
    _ = renderer.render(size: Size(width: width, height: 1))
    return renderer.chromeCommands
}

@Test @MainActor func aProgressBarDrawsVectorsWhereTheTerminalHasThem() {
    let bar = ProgressIndicator()
    bar.doubleValue = 0.5

    let drawn = commands(for: bar, width: 20, chrome: true)
    #expect(drawn.contains { $0.id.contains("track") }, "the track is a rounded rect")
    #expect(drawn.contains { $0.id.contains("fill") }, "and the filled part sits over it")
}

@Test @MainActor func aProgressBarWithoutChromeIsStillABar() {
    // The ANSI twin, which is the one that must work. No chrome commands, and
    // the cells carry the bar.
    let bar = ProgressIndicator()
    bar.doubleValue = 0.5

    #expect(commands(for: bar, width: 20, chrome: false).isEmpty)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 1))
    bar.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    window.addSubview(bar)
    let buffer = SceneRenderer(root: window).render(size: Size(width: 20, height: 1))

    // Half the track carries the fill style and half the track style, which is
    // what a cell bar is: two runs of differently-coloured blanks.
    let styles = (0..<20).map { buffer[Point(x: $0, y: 0)].style.background }
    #expect(Set(styles).count >= 2,
            "the cell bar still distinguishes filled from unfilled")
}

@Test @MainActor func theVectorFillIsSubCellRatherThanRoundedToAColumn() {
    // The reason to draw it at all: 42% and 47% are the same eight cells on a
    // twenty-cell track, and different vector rects.
    func fillWidth(_ fraction: Double) -> Double? {
        let bar = ProgressIndicator()
        bar.doubleValue = fraction
        return commands(for: bar, width: 20, chrome: true)
            .first { $0.id.contains("fill") }
            .flatMap { command in
                if case .rect(let rect, _, _, _, _, _) = command.shape { return rect.width }
                return nil
            }
    }

    let low = fillWidth(0.42)
    let high = fillWidth(0.47)
    #expect(low != nil && high != nil)
    #expect(low != high, "a vector fill does not round to the nearest column")
}

// The rest of the wider control pass: the two other controls whose cell form
// rounds a number to the nearest column.

@MainActor
private func chromeCommands(for view: TUIView, width: Int, height: Int = 1) -> [ChromeCommand] {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    // A theme, because vector chrome is drawn in resolved colours and the
    // default palette answers `.standard` — "whatever the terminal uses" —
    // which has no RGB to hand a vector renderer. A control that cannot name
    // its colours correctly draws cells instead, which is the right answer.
    window.theme = .turbo
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)

    let renderer = SceneRenderer(root: window)
    renderer.chromeEnabled = true
    _ = renderer.render(size: Size(width: width, height: height))
    return renderer.chromeCommands
}

@Test @MainActor func aSliderDrawsAVectorTrackAndHandle() {
    let slider = Slider(value: 50, in: 0...100)

    let drawn = chromeCommands(for: slider, width: 20)
    #expect(drawn.contains { $0.id.contains("track") })
    #expect(drawn.contains { $0.id.contains("handle") })
}

@Test @MainActor func aSlidersHandleIsSubCell() {
    // 42 and 47 of 100 land on the same column of a twenty-cell track and on
    // different vector positions. That is the whole reason to draw it.
    func handleX(_ value: Int) -> Double? {
        let slider = Slider(value: value, in: 0...100)
        return chromeCommands(for: slider, width: 20)
            .first { $0.id.contains("handle") }
            .flatMap { command in
                if case .rect(let rect, _, _, _, _, _) = command.shape { return rect.x }
                return nil
            }
    }

    #expect(handleX(42) != nil)
    #expect(handleX(42) != handleX(47), "a vector handle does not round to a column")
}

@Test @MainActor func aLevelIndicatorDrawsOneSegmentPerCell() {
    let level = LevelIndicator(value: 3, maximum: 5)

    let drawn = chromeCommands(for: level, width: 10)
    #expect(drawn.filter { $0.id.contains("segment") }.count == 5,
            "every segment is drawn, filled or not — an empty one is part of the reading")
}

@Test @MainActor func theseControlsStillDrawWithoutChrome() {
    // Ground rule 8: the cell path is the one that must work.
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 2))
    let slider = Slider(value: 50, in: 0...100)
    slider.frame = Rect(x: 0, y: 0, width: 20, height: 1)
    let level = LevelIndicator(value: 3, maximum: 5)
    level.frame = Rect(x: 0, y: 1, width: 20, height: 1)
    window.addSubview(slider)
    window.addSubview(level)

    let renderer = SceneRenderer(root: window)
    let lines = renderer.render(size: Size(width: 20, height: 2)).textLines()
    #expect(renderer.chromeCommands.isEmpty)
    #expect(lines[0].contains("█"), "the slider still has a cell handle")
    #expect(lines[1].trimmingCharacters(in: .whitespaces).isEmpty == false,
            "and the level indicator still has cells")
}

