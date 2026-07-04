import Testing
@testable import TUIKit

// MARK: - Determinate bar

@Test @MainActor func progressBarFillsAndLabels() {
    let bar = ProgressIndicator(style: .bar, value: 5, minValue: 0, maxValue: 10)
    bar.showsPercentage = true

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 1))
    bar.frame = window.bounds
    window.addSubview(bar)

    #expect(bar.fractionCompleted == 0.5)

    // 20 wide − " 50%" (4) = 16 track; half filled = 8 cells. Cells are
    // solid backgrounds (accent fill over a dim track), never shaded glyphs.
    let buffer = SceneRenderer(root: window).render(size: Size(width: 20, height: 1))
    #expect(buffer[Point(x: 0, y: 0)].style.background == .named(.brightCyan), "accent fill")
    #expect(buffer[Point(x: 7, y: 0)].style.background == .named(.brightCyan))
    #expect(buffer[Point(x: 8, y: 0)].style.background == .named(.brightBlack), "dim track")
    #expect(buffer[Point(x: 15, y: 0)].style.background == .named(.brightBlack))

    let line = buffer.textLines()[0]
    #expect(line.hasSuffix("50%"))
    #expect(!line.contains("░") && !line.contains("█"), "never a hash/shade pattern")
}

@Test @MainActor func progressBarClampsValue() {
    let bar = ProgressIndicator(style: .bar, value: 0, minValue: 0, maxValue: 8)

    bar.doubleValue = 100
    #expect(bar.doubleValue == 8, "clamped to the maximum")
    #expect(bar.fractionCompleted == 1)

    bar.doubleValue = -5
    #expect(bar.doubleValue == 0, "clamped to the minimum")

    // A degenerate range never divides by zero.
    let flat = ProgressIndicator(style: .bar, value: 3, minValue: 4, maxValue: 4)
    #expect(flat.fractionCompleted == 0)
}

// MARK: - Indeterminate spinner

@Test @MainActor func spinnerAdvancesAndWraps() {
    let spinner = ProgressIndicator(style: .spinner)
    spinner.caption = "Load"

    #expect(spinner.currentSpinnerGlyph == "|")

    spinner.advance()
    #expect(spinner.currentSpinnerGlyph == "/")

    spinner.advance()
    spinner.advance()
    #expect(spinner.currentSpinnerGlyph == "\\")

    spinner.advance()
    #expect(spinner.currentSpinnerGlyph == "|", "wraps back to the first frame")

    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 1))
    spinner.frame = window.bounds
    window.addSubview(spinner)
    let line = SceneRenderer(root: window).render(size: Size(width: 8, height: 1)).textLines()[0]
    #expect(line.hasPrefix("| Load"))

    // The bar style ignores advance().
    let bar = ProgressIndicator(style: .bar)
    bar.advance()
    #expect(bar.currentSpinnerGlyph == nil)
}

// MARK: - App timer story (never blocks, headless-scriptable)

@Test @MainActor func appTimerAdvancesSpinnerThroughTheRunLoop() async throws {
    let driver = HeadlessDriver(size: Size(width: 6, height: 1))
    let clock = ManualTimerSource()
    let app = App(driver: driver, timerSource: clock)

    let window = Window()
    let spinner = ProgressIndicator(style: .spinner)
    spinner.frame = Rect(x: 0, y: 0, width: 6, height: 1)
    window.addSubview(spinner)

    let session = Task {
        try await app.run(window)
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    #expect(await driver.snapshotText().first?.first == "|")

    let ticker = app.addTimer(every: .milliseconds(50)) { spinner.advance() }

    // Wait until the timer's tick stream is live, so no fire is dropped.
    while clock.streamCount == 0 {
        await Task.yield()
    }

    // Each manual tick advances the spinner and presents a new frame — with
    // no real time elapsed, proving the timer path is non-blocking.
    clock.fire()
    while await driver.snapshotText().first?.first != "/" {
        await Task.yield()
    }

    clock.fire()
    while await driver.snapshotText().first?.first != "-" {
        await Task.yield()
    }

    // Cancelling stops further ticks; a fire afterward changes nothing.
    ticker.cancel()
    let frozen = await driver.presentCount
    clock.fire()
    await Task.yield()
    await Task.yield()
    #expect(await driver.presentCount == frozen, "a cancelled timer presents no more frames")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func scheduledOneShotFiresOnceThenCancels() async throws {
    let driver = HeadlessDriver(size: Size(width: 4, height: 1))
    let clock = ManualTimerSource()
    let app = App(driver: driver, timerSource: clock)

    let window = Window()
    window.addSubview(Label("x"))

    let session = Task {
        try await app.run(window)
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    var fires = 0
    let timer = app.schedule(after: .milliseconds(10)) { fires += 1 }

    while clock.streamCount == 0 {
        await Task.yield()
    }

    // First tick fires the body; the one-shot then cancels itself.
    clock.fire()
    while fires == 0 {
        await Task.yield()
    }
    #expect(timer.isCancelled, "a one-shot cancels itself after firing")

    // Further ticks do nothing.
    clock.fire()
    await Task.yield()
    await Task.yield()
    #expect(fires == 1, "the one-shot fires exactly once")

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}
