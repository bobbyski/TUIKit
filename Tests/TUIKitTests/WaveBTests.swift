import Testing
@testable import TUIKit

// Phase 16 Wave B — the medium controls. Headless, like everything else.

@MainActor
private func host(_ view: TUIView, width: Int, height: Int = 1) -> Window {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    return window
}

@MainActor
private func lines(_ window: Window) -> [String] {
    SceneRenderer(root: window).render(size: window.frame.size).textLines()
}

@MainActor
private func buffer(_ window: Window) -> CellBuffer {
    SceneRenderer(root: window).render(size: window.frame.size)
}

private func key(_ key: Key, _ modifiers: KeyModifiers = []) -> TerminalInput {
    .key(KeyInput(key: key, modifiers: modifiers))
}

// MARK: - Wizard (16.11)

@Test @MainActor func wizardValidatesBranchesAndFinishes() {
    var nameOK = false
    var finished = 0
    var express = false
    let wizard = Wizard(steps: [
        .init(id: "welcome", title: "Welcome", view: Label("hello"),
              next: { express ? "done" : nil }),
        .init(id: "account", title: "Account", view: Label("account"),
              validate: { nameOK ? nil : "Choose a user name to continue." }),
        .init(id: "done", title: "All set", view: Label("summary")),
    ])
    wizard.onFinish = { finished += 1 }
    let window = host(wizard, width: 50, height: 6)

    var text = lines(window)
    #expect(text[0].contains("Welcome") && text[0].contains("step 1 of 3"))
    #expect(text[5].contains("Next"), "the footer shows Next before the last step")

    #expect(wizard.goNext() && wizard.currentStep.id == "account")
    #expect(!wizard.goNext(), "validation blocks")
    text = lines(window)
    #expect(text[5].contains("Choose a user name"))

    nameOK = true
    #expect(wizard.goNext() && wizard.currentStep.id == "done")
    #expect(wizard.isOnFinalStep)
    #expect(lines(window)[5].contains("Finish"))
    #expect(wizard.goNext() && finished == 1, "Finish on the last step finishes")

    #expect(wizard.goBack() && wizard.currentStep.id == "account", "Back walks the trail")
    #expect(wizard.goBack() && wizard.goBack() == false, "and stops at the first step")

    express = true
    #expect(wizard.goNext() && wizard.currentStep.id == "done", "branching skips a step")
    #expect(lines(window)[0].contains("step 2 of 2"))
}

// MARK: - Gauge + LevelIndicator thresholds (16.12)

@Test @MainActor func gaugeBarFillsByFractionAndThresholdsRecolour() {
    let gauge = Gauge(value: 50, in: 0...100)
    gauge.label = "CPU"
    gauge.warningThreshold = 0.7
    gauge.criticalThreshold = 0.9
    gauge.theme = .turbo
    let window = host(gauge, width: 30)
    let theme = Theme.turbo.resolved()

    let row = lines(window)[0]
    #expect(row.hasPrefix("CPU "))
    #expect(row.contains("█") && row.contains("░") && row.hasSuffix("50%"))
    #expect(gauge.fillColor(theme) == theme.chartAccent)

    gauge.setValue(75)
    #expect(gauge.fillColor(theme) == theme.warningAccent)
    gauge.setValue(95)
    #expect(gauge.fillColor(theme) == theme.errorAccent)
}

@Test @MainActor func gaugeRingDrawsSectorsUnderVTGAndABarWithout() {
    let gauge = Gauge(value: 25, in: 0...100, style: .ring)
    gauge.theme = .ambiance   // concrete colours: chrome needs real RGB, not .standard
    gauge.frame = Rect(x: 0, y: 0, width: 16, height: 7)

    let plain = SceneRenderer(root: gauge).render(size: Size(width: 16, height: 7)).textLines()
    #expect(plain[0].contains("█") || plain[0].contains("░"), "no chrome: the bar is the honest form")

    let vector = SceneRenderer(root: gauge)
    vector.chromeEnabled = true
    let text = vector.render(size: Size(width: 16, height: 7)).textLines()
    #expect(text[3].contains("25%"), "the value sits in the ring")
    let ids = vector.chromeCommands.map(\.id)
    #expect(ids.contains { $0.hasSuffix("_track") } && ids.contains { $0.hasSuffix("_fill") } && ids.contains { $0.hasSuffix("_hole") })
}

@Test @MainActor func levelIndicatorThresholdsRecolourTheFill() {
    let level = LevelIndicator(value: 2, maximum: 5)
    level.warningLevel = 3
    level.criticalLevel = 5
    let theme = Theme.turbo.resolved()

    #expect(level.fillColor(theme) == theme.accent)
    level.setValue(3)
    #expect(level.fillColor(theme) == theme.warningAccent)
    level.setValue(5)
    #expect(level.fillColor(theme) == theme.errorAccent)
}

// MARK: - FlowStack (16.17)

@Test @MainActor func flowStackWrapsWhereTheRowRunsOut() {
    let flow = FlowStack(spacing: 1)
    for tag in ["swift", "terminal", "tui", "concurrency", "testing"] {
        flow.addSubview(Label(tag))
    }
    let window = host(flow, width: 20, height: 3)
    let text = lines(window)

    // "swift terminal tui" is 18 wide; "concurrency" would not fit.
    #expect(text[0].hasPrefix("swift terminal tui"))
    #expect(text[1].hasPrefix("concurrency testing"))
    #expect(flow.intrinsicContentSize?.height == 2)

    flow.frame = Rect(x: 0, y: 0, width: 12, height: 3)
    window.frame = Rect(x: 0, y: 0, width: 12, height: 4)
    let narrow = lines(window)
    #expect(narrow[0].hasPrefix("swift") && narrow[1].hasPrefix("terminal tui") && narrow[2].hasPrefix("concurrency"))
}

// MARK: - Form sections (16.18)

@Test @MainActor func formSectionsDrawHeadersAndKeepOneLabelColumn() {
    let form = Form(spacing: 0) {
        Section("Account") {
            Field("Name") { TextField(placeholder: "name") }
            Field("Email") { TextField(placeholder: "email") }
        }
        Section("Look") {
            Field("Theme") { Label("Turbo") }
        }
    }
    let window = host(form, width: 30, height: 5)
    let text = lines(window)

    #expect(text[0].hasPrefix("Account"))
    #expect(text[1].contains(" Name:") && text[2].contains("Email:"))
    #expect(text[3].hasPrefix("Look"))
    #expect(text[4].contains("Theme:"))
    // One label column: every colon sits in the same column.
    let columns = [text[1], text[2], text[4]].map { line in
        line.distance(from: line.startIndex, to: line.firstIndex(of: ":")!)
    }
    #expect(Set(columns).count == 1, "label colons line up across sections: \(columns)")
}
