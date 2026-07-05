import Testing
import TUIKit
import TUIKitTutorialMilestones

// The tutorial's anti-rot suite: every chapter milestone boots through the
// headless driver and renders its landmark content, and the interaction
// walkthrough Chapter 5 teaches runs here for real. Note the plain
// `import TUIKit` — no @testable — so the tutorial provably uses only
// public API.

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

/// Stops a running session the way a user would (Ctrl+C).
@MainActor
private func shutDown(_ driver: HeadlessDriver, _ session: Task<Void, any Error>) async throws {
    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}

@Test @MainActor func everyChapterBootsAndRendersItsLandmark() async throws {
    // A landmark string per chapter: if a milestone stops rendering its own
    // content, the chapter it anchors has rotted.
    let landmarks: [Int: String] = [
        1: "Hello, terminal!",
        2: "To-Do",
        3: "Ship Chapter 3",
        4: "Ship Chapter 4",
        5: "Ship Chapter 4",   // Chapter 5 tests Chapter 4's app
        6: "Ship Chapter 6",
    ]

    for milestone in TutorialMilestones.all {
        let (driver, _, session) = try await boot(milestone)
        let screen = await driver.snapshotText().joined(separator: "\n")

        #expect(
            screen.contains(landmarks[milestone.chapter]!),
            "chapter \(milestone.chapter) (\(milestone.title)) lost its landmark"
        )

        try await shutDown(driver, session)
    }
}

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

@Test @MainActor func chapter6MatchesChapter3Behavior() async throws {
    // The traditional rebuild behaves like the declarative original: same
    // typing walkthrough, same outcome.
    let (driver, _, session) = try await boot(Chapter6.self)

    for character in "Tea" {
        await driver.send(.key(KeyInput(key: .character(character))))
    }
    await driver.send(.key(KeyInput(key: .enter)))

    // Same post-Return poll as the Chapter 3 test (the field echoes "Tea"
    // while typing, so polling for the title alone would race the submit).
    while await !driver.snapshotText().joined().contains("2 in the list") {
        await Task.yield()
    }

    #expect(await driver.snapshotText().joined(separator: "\n").contains("Tea"))

    try await shutDown(driver, session)
}
