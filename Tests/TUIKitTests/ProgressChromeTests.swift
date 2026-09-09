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
