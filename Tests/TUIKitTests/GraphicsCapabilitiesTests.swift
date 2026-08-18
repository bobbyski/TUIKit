import Testing
@testable import TUIKit

// Asking before emitting: a terminal that does not implement sprites answers
// a sprite command by drawing nothing, which looks exactly like success.

@Test @MainActor func aDriverWithNoGraphicsPlaneHasNoCapabilities() async {
    let driver = HeadlessDriver(size: Size(width: 20, height: 5))

    #expect(await driver.supportsGraphicsChrome == false)
    #expect(await driver.graphicsCapabilities == nil, "nil matches supportsGraphicsChrome == false")
}

@Test @MainActor func aGraphicsDriverThatWasNeverAskedReportsTheBaseline() async {
    // "It draws images, we do not know what else" is the true statement, and
    // refusing to draw anything would be a worse one.
    let driver = HeadlessDriver(size: Size(width: 20, height: 5), supportsGraphicsChrome: true)
    let capabilities = await driver.graphicsCapabilities

    #expect(capabilities == .baseline)
    #expect(capabilities?.accepts(.png) == true)
    #expect(capabilities?.accepts(.jpeg) == true)
    #expect(capabilities?.supportsSprites == false, "nothing optional is assumed")
    #expect(capabilities?.supportsLayerScroll == false)
}

@Test @MainActor func aTestCanPinWhatTheTerminalCanDo() async {
    let rich = GraphicsCapabilities(
        rasterFormats: [.png],
        supportsSprites: true,
        supportsLayerScroll: true,
        supportsClipping: true,
        supportsHitRegions: false
    )

    let driver = HeadlessDriver(
        size: Size(width: 20, height: 5),
        supportsGraphicsChrome: true,
        graphicsCapabilities: rich
    )

    #expect(await driver.graphicsCapabilities == rich)
    #expect(rich.accepts(.png))
    #expect(!rich.accepts(.jpeg), "a format the terminal did not list is a placeholder, not a gamble")
}

private struct OldDriverSimulation: TerminalDriver {
    // A driver written before capabilities existed: it implements the
    // protocol as it was, and must keep compiling and answer honestly.
    let hasPlane: Bool

    var size: Size { get async { Size(width: 10, height: 3) } }
    func inputStream() async -> AsyncStream<TerminalInput> { AsyncStream { $0.finish() } }
    func setCursor(_ cursor: TerminalCursor) async {}
    func begin() async throws {}
    func end() async {}
    func present(_ buffer: CellBuffer) async {}
    var supportsGraphicsChrome: Bool { get async { hasPlane } }
}

@Test func aDriverWrittenBeforeThisExistedStillCompilesAndAnswers() async {
    #expect(await OldDriverSimulation(hasPlane: false).graphicsCapabilities == nil)
    #expect(await OldDriverSimulation(hasPlane: true).graphicsCapabilities == .baseline)
}
