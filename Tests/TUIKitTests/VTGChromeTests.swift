import Foundation
import Testing
@testable import TUIKit

// Phase 10 — VTG vector chrome, proven headlessly (10.7): the cell↔pixel
// mapper, retained-scene reconciliation, the chrome surface's clipping and
// gradient geometry, the Ambiance titlebar/button/desktop passes, and the
// plain-terminal fallback contract (identical behavior, zero chrome).

// MARK: - Mapper (10.3)

@Test func mapperRoundsEdgesIndependentlySoStripsStaySeamless() {
    let mapper = CellPixelMapper(glyphWidth: 9.5, glyphHeight: 20)

    // Two vertically adjacent strips must meet at the same pixel edge.
    let upper = mapper.rect(ChromeRect(x: 0, y: 0, width: 4, height: 0.5))
    let lower = mapper.rect(ChromeRect(x: 0, y: 0.5, width: 4, height: 0.5))

    #expect(upper.y + upper.height == lower.y, "shared edge rounds identically for both strips")
    #expect(upper.height + lower.height == 20, "the strips exactly cover one cell height")

    // Fractional glyph widths accumulate rather than rounding per cell.
    let wide = mapper.rect(ChromeRect(x: 0, y: 0, width: 10, height: 1))
    #expect(wide.width == 95, "10 cells of 9.5px = 95px, not 10 × round(9.5)")
}

@Test func mapperScalarsNeverCollapseToInvisible() {
    let mapper = CellPixelMapper(glyphWidth: 9, glyphHeight: 18)

    #expect(mapper.scalar(0) == 0, "zero stays zero (no rounding-up phantom strokes)")
    #expect(mapper.scalar(0.01) == 1, "a hairline never disappears")
    #expect(mapper.scalar(0.35) == 6, "0.35 cell heights of 18px rounds to 6px")
}

// MARK: - Reconciler (retained scene)

@Test func reconcilerPlansUnchangedInPlaceAndRebuildFrames() {
    func rect(_ id: String, x: Double = 0) -> ChromeCommand {
        ChromeCommand(id: id, shape: .rect(
            ChromeRect(x: x, y: 0, width: 1, height: 1),
            fill: nil, stroke: nil, lineWidth: 0, radius: 0, corners: []
        ))
    }

    let frame = [rect("a"), rect("b"), rect("c")]

    // Identical frames write nothing.
    #expect(ChromeSceneReconciler.plan(previous: frame, current: frame) == .unchanged)

    // Same id order → update in place, only the shapes that changed.
    let moved = [rect("a"), rect("b", x: 5), rect("c")]
    #expect(ChromeSceneReconciler.plan(previous: frame, current: moved) == .update(draw: [rect("b", x: 5)]))

    // Reordered or removed ids → rebuild: retained objects keep their
    // creation-time stacking, so an in-place update after a window raise
    // would stack chrome differently than the cells above it.
    let raised = [rect("b"), rect("a"), rect("c")]
    #expect(ChromeSceneReconciler.plan(previous: frame, current: raised) == .rebuild(delete: ["a", "b", "c"]))

    let shrunk = [rect("b")]
    #expect(ChromeSceneReconciler.plan(previous: frame, current: shrunk) == .rebuild(delete: ["a", "b", "c"]))

    // First frame ever: nothing retained, draw everything.
    #expect(ChromeSceneReconciler.plan(previous: [], current: shrunk) == .rebuild(delete: []))
}

// MARK: - Surface geometry

/// A view that draws one gradient bar through the chrome surface.
@MainActor
private final class GradientView: TUIView {
    override func draw(_ painter: Painter) {
        painter.chrome?.verticalGradient(
            "bar",
            ChromeRect(bounds),
            top: ChromeColor(red: 100, green: 100, blue: 100),
            bottom: ChromeColor(red: 20, green: 20, blue: 20),
            steps: 4,
            radius: 0.4,
            corners: .top
        )
    }
}

@Test @MainActor func gradientStripsStayInsideRoundedCorners() {
    let view = GradientView(frame: Rect(x: 2, y: 1, width: 10, height: 1))
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 20, height: 5))
    root.addSubview(view)

    let renderer = SceneRenderer(root: root)
    renderer.chromeEnabled = true
    _ = renderer.render(size: Size(width: 20, height: 5))

    let commands = renderer.chromeCommands
    #expect(commands.count == 5, "a base rounded rect plus four strips")

    guard case .rect(let base, _, _, _, let radius, let corners) = commands[0].shape else {
        Issue.record("first command should be the base rect")
        return
    }

    #expect(base == ChromeRect(x: 2, y: 1, width: 10, height: 1), "translated into buffer cells")
    #expect(radius == 0.4)
    #expect(corners == .top)

    // The topmost strip crosses the rounded corners, so it is inset on both
    // sides; the bottom strip (square corners) is not.
    guard case .rect(let first, _, _, _, _, _) = commands[1].shape,
          case .rect(let last, _, _, _, _, _) = commands[4].shape else {
        Issue.record("strips should be rects")
        return
    }

    #expect(first.x > base.x, "top strip insets clear of the top-left arc")
    #expect(first.maxX < base.maxX, "and of the top-right arc")
    #expect(last.x == base.x, "bottom strip spans the full width")
    #expect(last.maxX == base.maxX)
}

@Test @MainActor func chromeCommandsClipToAncestorFramesLikeCells() {
    // The view hangs two cells past its parent's right edge; chrome must
    // clamp exactly the way cell drawing clips.
    let parent = TUIView(frame: Rect(x: 0, y: 0, width: 8, height: 3))
    let child = GradientView(frame: Rect(x: 6, y: 0, width: 4, height: 1))
    parent.addSubview(child)

    let renderer = SceneRenderer(root: parent)
    renderer.chromeEnabled = true
    _ = renderer.render(size: Size(width: 8, height: 3))

    for command in renderer.chromeCommands {
        guard case .rect(let rect, _, _, _, _, _) = command.shape else {
            continue
        }

        #expect(rect.maxX <= 8, "no chrome rect escapes the parent's frame")
    }

    #expect(!renderer.chromeCommands.isEmpty, "the visible half still draws")
}

@Test @MainActor func chromeIsAbsentWhenDisabled() {
    let view = GradientView(frame: Rect(x: 0, y: 0, width: 4, height: 1))
    let renderer = SceneRenderer(root: view)

    _ = renderer.render(size: Size(width: 4, height: 1))

    #expect(renderer.chromeCommands.isEmpty, "no surface, no commands — the plain-terminal path")
}

// MARK: - Ambiance chrome passes (10.5)

@MainActor
private func renderedAmbianceWindow(
    chrome: Bool,
    size: Size = Size(width: 40, height: 12)
) -> (window: FloatingWindow, renderer: SceneRenderer, buffer: CellBuffer) {
    let desktop = Desktop()
    desktop.frame = Rect(origin: .zero, size: size)
    desktop.theme = .ambiance

    let window = FloatingWindow(title: "Eiciel", frame: Rect(x: 4, y: 2, width: 30, height: 8))
    desktop.addSubview(window)

    let renderer = SceneRenderer(root: desktop)
    renderer.chromeEnabled = chrome
    let buffer = renderer.render(size: size)

    return (window, renderer, buffer)
}

@Test @MainActor func ambianceTitleBarDrawsGradientRoundedTopAndLeadingRoundButtons() {
    let (window, renderer, buffer) = renderedAmbianceWindow(chrome: true)
    let ids = renderer.chromeCommands.map(\.id)

    // The titlebar gradient with rounded TOP corners, in window cells.
    guard let barBase = renderer.chromeCommands.first(where: { $0.id.hasSuffix("_titlebar-base") }),
          case .rect(let bar, _, _, _, let radius, let corners) = barBase.shape else {
        Issue.record("no titlebar gradient base drawn")
        return
    }

    #expect(bar == ChromeRect(x: 4, y: 2, width: 30, height: 1), "the bar covers the window's top row")
    #expect(corners == .top)
    #expect(radius > 0)

    // A filled close circle at the LEADING side (the Ubuntu arrangement).
    guard let close = renderer.chromeCommands.first(where: { $0.id.hasSuffix("_close-button") }),
          case .circle(let center, _, let fill, _, _) = close.shape else {
        Issue.record("no round close button drawn")
        return
    }

    #expect(center.x == 5.5 && center.y == 2.5, "close centers on the row's second cell — leading placement")
    #expect(fill == ChromeColor(red: 237, green: 106, blue: 61), "the Ambiance orange dot")
    #expect(ids.contains { $0.hasSuffix("_maximize-button") }, "the maximize circle rides beside it")

    // The title is centered native text over transparent cells.
    let row = buffer.textLines()[2]
    let title = row.range(of: "Eiciel")
    #expect(title != nil, "title text survives as cells")

    let titleColumn = row.distance(from: row.startIndex, to: title!.lowerBound)
    #expect(abs(titleColumn - (4 + (30 - 6) / 2)) <= 1, "title is centered in the bar")

    let titleCell = buffer[Point(x: titleColumn, y: 2)]
    #expect(titleCell.style.background == .standard, "titlebar cells stay transparent so the bar shows through")

    // The close glyph sits on the circle.
    #expect(buffer[Point(x: 5, y: 2)].character == "×")

    // Hit-testing follows the leading placement.
    var closed = false
    window.onCloseRequest = { closed = true }
    _ = window.route(.mouse(MouseInput(position: Point(x: 1, y: 0), action: .press, button: .left)))
    #expect(closed, "clicking the leading circle closes")
}

@Test @MainActor func plainTerminalKeepsCellChromeAndBehavior() {
    let (window, renderer, buffer) = renderedAmbianceWindow(chrome: false)

    #expect(renderer.chromeCommands.isEmpty, "no VTG terminal → not a single chrome command")

    // The classic cell chrome: title in the border, trailing [x].
    let row = buffer.textLines()[2]
    #expect(row.contains("Eiciel"))
    #expect(row.contains("[x]"), "cell close box at the trailing edge")

    // And the trailing hit-testing to match.
    var closed = false
    window.onCloseRequest = { closed = true }
    _ = window.route(.mouse(MouseInput(position: Point(x: 30 - 4, y: 0), action: .press, button: .left)))
    #expect(closed, "clicking [x] closes, exactly as before Phase 10")
}

@Test @MainActor func ambianceButtonsWearRoundedGradientPills() {
    let desktop = Desktop()
    desktop.frame = Rect(x: 0, y: 0, width: 30, height: 5)
    desktop.theme = .ambiance

    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 5))
    desktop.addSubview(window)

    let button = Button("Open")
    button.frame = Rect(x: 2, y: 1, width: 8, height: 1)
    window.addSubview(button)
    window.makeFirstResponder(button)

    let renderer = SceneRenderer(root: desktop)
    renderer.chromeEnabled = true
    let buffer = renderer.render(size: Size(width: 30, height: 5))

    guard let pillBase = renderer.chromeCommands.first(where: { $0.id.hasSuffix("_pill-base") }),
          case .rect(let pill, _, _, _, let radius, let corners) = pillBase.shape else {
        Issue.record("no pill drawn behind the button")
        return
    }

    #expect(pill == ChromeRect(x: 2, y: 1, width: 8, height: 1), "the pill covers the button frame")
    #expect(corners == .all, "all four corners round — the requested rounded-corner buttons")
    #expect(radius == 0.4)

    // Focused: the orange glow stroke.
    guard let stroke = renderer.chromeCommands.first(where: { $0.id.hasSuffix("_pill-stroke") }),
          case .rect(_, _, let strokeColor, _, _, _) = stroke.shape else {
        Issue.record("no focus stroke drawn")
        return
    }

    #expect(strokeColor == ChromeColor(red: 240, green: 119, blue: 70), "the Ambiance focus glow")

    // Label cells are transparent so the pill shows behind the text.
    let labelCell = buffer[Point(x: 4, y: 1)]
    #expect(labelCell.style.background == .standard)
    #expect(buffer.textLines()[1].contains("Open"))
}

@Test @MainActor func ambianceDesktopDrawsBackdropGradientAndWindowShadow() {
    let (_, renderer, buffer) = renderedAmbianceWindow(chrome: true)

    // The full-screen backdrop gradient…
    #expect(renderer.chromeCommands.contains { $0.id.hasSuffix("_backdrop-base") })

    // …under transparent desktop cells…
    #expect(buffer[Point(x: 0, y: 0)].style.background == .standard)

    // …with a soft shadow behind the floating window, drawn before the
    // window's own chrome (back-to-front).
    let ids = renderer.chromeCommands.map(\.id)
    guard let shadow = ids.firstIndex(where: { $0.hasSuffix("_shadow-0") }),
          let titlebar = ids.firstIndex(where: { $0.hasSuffix("_titlebar-base") }) else {
        Issue.record("missing shadow or titlebar")
        return
    }

    #expect(shadow < titlebar, "the shadow paints under the window chrome")
}

// MARK: - App/driver integration (10.1, 10.8)

@Test @MainActor func appActivatesChromeOnlyWhenTheDriverSupportsIt() async throws {
    for supports in [true, false] {
        let driver = HeadlessDriver(size: Size(width: 40, height: 12), supportsGraphicsChrome: supports)
        let app = App(driver: driver)
        app.applyTheme(.ambiance)

        let window = FloatingWindow(title: "W", frame: Rect(x: 2, y: 1, width: 20, height: 6))
        let session = Task { try await app.run(window) }

        while await driver.presentCount == 0 {
            await Task.yield()
        }

        #expect(app.isVectorChromeActive == supports)

        if supports {
            #expect(await driver.chromePresentCount > 0, "chrome rides the cell frame")
            #expect(await !driver.presentedChrome.isEmpty)
        } else {
            #expect(await driver.chromePresentCount == 0, "a plain terminal never sees chrome")
            #expect(await driver.presentedChrome.isEmpty)
        }

        app.stop()
        await driver.send(.key(KeyInput(key: .character(" "))))   // wake the loop to observe the stop
        try await session.value
    }
}

// MARK: - Theme model

@Test func vectorChromeSurvivesAJSONRoundTrip() throws {
    let theme = Theme.ambiance

    let encoded = try JSONEncoder().encode(theme)
    let decoded = try JSONDecoder().decode(Theme.self, from: encoded)

    #expect(decoded == theme, "the vector block is fully Codable")
    #expect(decoded.base.vector?.titleBar?.buttonPlacement == .leading)
    #expect(decoded.resolved().vector?.button?.cornerRadius == 0.4)
}
