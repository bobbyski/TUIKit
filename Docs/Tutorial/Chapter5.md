# Chapter 5 — Testing your app (Chapter 4's app, under test)

No new UI this chapter — the milestone *is* Chapter 4's app, because the
chapter is about proving it works without a terminal. Every test you'll read
here is real: it lives in `Tests/TUIKitTutorialTests/TutorialMilestoneTests.swift`
and runs in CI right now.

## HeadlessDriver is a full driver

TUIKit's driver layer has two implementations: `ANSIDriver` for a real
terminal, and `HeadlessDriver` for tests. The headless one is a full driver,
not a mock — it keeps an in-memory cell buffer, accepts scripted input
through `send(_:)`, and exposes the rendered screen as `snapshotText()`.
Your app cannot tell the difference, which is why the same `makeWindow` runs
in both places (see the testing model in
[`Architecture.md`](../Architecture.md)).

## The boot / send / snapshot pattern

Every test starts the same way: boot the milestone exactly as the runner
would, but on the headless driver. This is the suite's shared helper,
verbatim:

```swift
/// Boots one milestone exactly the way the runner does, but headlessly.
@MainActor
private func boot(
    _ milestone: any TutorialMilestone.Type,
    size: Size = Size(width: 70, height: 22)
) async throws -> (driver: HeadlessDriver, app: App, session: Task<Void, any Error>) {
    let driver = HeadlessDriver(size: size)
    let app = App(driver: driver)
    let window = milestone.makeWindow(app: app)

    let session = Task {
        try await app.run(window)
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    return (driver, app, session)
}
```

Note the shape: the app runs in a `Task` (it would otherwise suspend the
test), and the helper yields until the driver has presented a first frame.
No sleeps, no timing guesses — the suite polls observable driver state.

## Testing an interaction

Chapter 3's walkthrough — type a task, press Return, see it in the list —
as a test:

```swift
@Test @MainActor func chapter3AddsATaskFromTheKeyboard() async throws {
    // The walkthrough Chapter 5 teaches: type into the focused field,
    // press Return, and the task appears in the list.
    let (driver, _, session) = try await boot(Chapter3.self)

    for character in "Tea" {
        await driver.send(.key(KeyInput(key: .character(character))))
    }
    await driver.send(.key(KeyInput(key: .enter)))

    // Poll for the post-Return status line — "Tea" alone would match the
    // field's echo while typing, before the submit lands.
    while await !driver.snapshotText().joined().contains("2 in the list") {
        await Task.yield()
    }

    let screen = await driver.snapshotText().joined(separator: "\n")
    #expect(screen.contains("Tea"), "the new task is in the list")
    #expect(screen.contains("2 in the list"), "the status line reports the add")

    try await shutDown(driver, session)
}
```

`send(_:)` takes the same `TerminalInput` values a real terminal produces —
keys, mouse, resizes. Chapter 4's hot-key and reflow behavior tests the same
way, including a mid-session resize:

```swift
@Test @MainActor func chapter4HotKeyWorksAndResizeReflows() async throws {
    let (driver, _, session) = try await boot(Chapter4.self)

    // Ctrl+N is answered by the window's hot-key pass from anywhere.
    await driver.send(.key(KeyInput(key: .character("n"), modifiers: .control)))

    while await !driver.snapshotText().joined().contains("ready for a new task") {
        await Task.yield()
    }

    // A resize reflows the same content into the new size.
    await driver.send(.resize(Size(width: 44, height: 14)))

    while await driver.snapshotText().first?.count != 44 {
        await Task.yield()
    }

    let screen = await driver.snapshotText().joined(separator: "\n")
    #expect(screen.contains("Ship Chapter 4"), "content survives the resize")

    try await shutDown(driver, session)
}
```

## The anti-rot idea

The suite's first test, `everyChapterBootsAndRendersItsLandmark`, boots
*every* milestone and asserts one landmark string per chapter — `"Hello,
terminal!"` for Chapter 1, `"Ship Chapter 3"` for Chapter 3, and so on. If a
framework change stops a chapter's app from rendering its own content, CI
fails and names the chapter. That's the runnable-milestone rule with teeth:
the tutorial can't rot, because the tutorial is code.

One more detail worth stealing: the test file imports plain `TUIKit` — no
`@testable` — so everything the suite does, your app's tests can do with
public API only.

## Run it

```sh
swift run TUIKitTutorial ch5     # Chapter 4's app, the subject under test
swift test --filter TUIKitTutorialTests
```

Things to try:

- Run the test filter above and watch four tests script the app you've been
  clicking.
- Break a landmark on purpose — edit nothing, just imagine renaming the
  Chapter 4 seed task — and predict which two tests fail (the landmark map
  says Chapter 5 shares it).
- Copy the `boot` helper into your own project's tests; it's the whole
  pattern.

You've learned to drive your app headlessly: boot, send, snapshot, assert.
Last stop — the appendix, where we rebuild Chapter 3 with no builder at all.
