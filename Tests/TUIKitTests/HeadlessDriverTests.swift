import Testing
@testable import TUIKit

@Test func beginEndLifecycle() async throws {
    let driver = HeadlessDriver()

    #expect(await driver.isRunning == false)

    try await driver.begin()
    #expect(await driver.isRunning)

    await #expect(throws: HeadlessDriver.DriverError.alreadyBegan) {
        try await driver.begin()
    }

    await driver.end()
    #expect(await driver.isRunning == false)

    // end() is safe to call again (unconditional cleanup contract).
    await driver.end()
}

@Test func presentRecordsBufferAndCount() async throws {
    let driver = HeadlessDriver(size: Size(width: 10, height: 2))
    try await driver.begin()

    var buffer = CellBuffer(size: Size(width: 10, height: 2))
    buffer.write("hello", at: .zero)
    await driver.present(buffer)

    #expect(await driver.presentCount == 1)
    #expect(await driver.snapshotText() == ["hello     ", "          "])
    #expect(await driver.presentedBuffer == buffer)
}

@Test func cursorStateIsRecorded() async throws {
    let driver = HeadlessDriver()

    #expect(await driver.cursor == .hidden)

    let cursor = TerminalCursor(position: Point(x: 3, y: 1), isVisible: true)
    await driver.setCursor(cursor)

    #expect(await driver.cursor == cursor)
}

@Test func scriptedInputReachesTheStream() async throws {
    let driver = HeadlessDriver()
    try await driver.begin()

    let stream = await driver.inputStream()
    let enter = TerminalInput.key(KeyInput(key: .enter))
    let click = TerminalInput.mouse(
        MouseInput(position: Point(x: 2, y: 2), action: .press, button: .left)
    )

    await driver.send(enter)
    await driver.send(click)
    await driver.end()

    var received: [TerminalInput] = []

    for await input in stream {
        received.append(input)
    }

    #expect(received == [enter, click])
}

@Test func resizeUpdatesSizeAndEmitsInput() async throws {
    let driver = HeadlessDriver(size: Size(width: 80, height: 24))
    try await driver.begin()

    let stream = await driver.inputStream()
    let newSize = Size(width: 120, height: 40)

    await driver.resize(to: newSize)
    await driver.end()

    #expect(await driver.size == newSize)

    var received: [TerminalInput] = []

    for await input in stream {
        received.append(input)
    }

    #expect(received == [.resize(newSize)])
}

@Test func endFinishesInputStreams() async throws {
    let driver = HeadlessDriver()
    try await driver.begin()

    let stream = await driver.inputStream()
    await driver.end()

    var count = 0

    for await _ in stream {
        count += 1
    }

    #expect(count == 0)
}
