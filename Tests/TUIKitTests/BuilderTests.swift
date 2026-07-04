import Testing
@testable import TUIKit

// A user-defined compound control, usable like a bundled one.
private struct LabeledField: Composable {
    let title: String
    var placeholder = ""

    var body: some Component {
        HStack(spacing: 1) {
            Label("\(title):").bold()
            TextField(placeholder: placeholder)
        }
    }
}

@Test @MainActor func builderAssemblesAViewTree() {
    var submitted: [String] = []

    let field = TextField(placeholder: "name")
    let root = VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
        Label("Title").bold()
        field.onSubmit { submitted.append($0) }
        Toggle("Wrap")
        Spacer()
    }

    // The builder produced a real VStack with four children.
    #expect(root is VStack)
    #expect(root.subviews.count == 4)
    #expect(root.subviews[0] is Label)
    #expect(root.subviews[1] === field, "typed modifier returns the same control")
    #expect(root.subviews[3] is Spacer)

    // The event wire is a plain closure — no reactivity.
    field.onSubmit("Bobby")
    #expect(submitted == ["Bobby"])
}

@Test @MainActor func builderConditionalsResolveAtBuildTime() {
    func make(showExtra: Bool) -> VStack {
        VStack {
            Label("always")
            if showExtra {
                Label("extra")
            }
            for i in 0..<3 {
                Label("row \(i)")
            }
        }
    }

    #expect(make(showExtra: true).subviews.count == 5)
    #expect(make(showExtra: false).subviews.count == 4)
}

@Test @MainActor func composableIsUsableLikeABundledControl() {
    let form = VStack {
        LabeledField(title: "Name", placeholder: "full name")
        LabeledField(title: "Email")
    }

    #expect(form.subviews.count == 2)
    #expect(form.subviews[0] is HStack, "the compound built its body's container")
    #expect(form.subviews[0].subviews.count == 2, "label + field")
}

@Test @MainActor func structuralModifiersConfigureTheView() {
    let view = Label("x").id("greeting").frame(minWidth: 12).makeView()
    #expect(view.identifier == "greeting")
    #expect(view.minimumSize.width == 12)
}

@Test @MainActor func formAlignsTheLabelColumn() {
    let form = Form(spacing: 0) {
        Field("A")    { TextField(placeholder: "x") }
        Field("Name") { TextField(placeholder: "y") }
    }

    let window = Window(frame: Rect(x: 0, y: 0, width: 24, height: 2))
    form.anchors = .fill()
    window.addSubview(form)

    #expect(form.intrinsicContentSize?.height == 2)

    let lines = SceneRenderer(root: window).render(size: Size(width: 24, height: 2)).textLines()
    #expect(lines[0].hasPrefix("   A:"), "the short label right-aligns to the colon")
    #expect(lines[1].hasPrefix("Name:"))
    #expect(Array(lines[0])[4] == ":" && Array(lines[1])[4] == ":", "colons align across rows")
}

@Test @MainActor func zStackOverlapsChildren() {
    let z = ZStack {
        Label("background")
        Label("FG")
    }

    let window = Window(frame: Rect(x: 0, y: 0, width: 12, height: 1))
    z.anchors = .fill()
    window.addSubview(z)
    window.layoutIfNeeded()

    #expect(z.subviews.count == 2)
    #expect(z.subviews[1].frame == Rect(x: 0, y: 0, width: 12, height: 1), "children fill")

    // The later child draws over the earlier one.
    let line = SceneRenderer(root: window).render(size: Size(width: 12, height: 1)).textLines()[0]
    #expect(line.hasPrefix("FG"))
}

@Test @MainActor func setContentInstallsAFillAnchoredRoot() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 3))
    window.setContent {
        VStack { Label("one"); Label("two") }
    }

    #expect(window.subviews.count == 1)
    #expect(window.subviews[0] is VStack)
    #expect(window.subviews[0].anchors == .fill())

    window.layoutIfNeeded()
    #expect(window.subviews[0].frame == Rect(x: 0, y: 0, width: 20, height: 3))
}

@Test @MainActor func appRunBuilderPresentsBuiltContent() async throws {
    let driver = HeadlessDriver(size: Size(width: 8, height: 1))
    let app = App(driver: driver)

    let session = Task {
        try await app.run {
            Label("hello")
        }
    }

    while await driver.presentCount == 0 {
        await Task.yield()
    }

    #expect(await driver.snapshotText().first?.contains("hello") == true)

    await driver.send(.key(KeyInput(key: .character("c"), modifiers: .control)))
    try await session.value
}
