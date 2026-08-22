import TUIKit

// The inline presentation: a utility that needs a couple of parameters
// asks for them in a few rows right at the cursor — no alternate screen —
// and when it is done the cursor sits on the line below the prompt, so
// the shell (and this program's own output) continue underneath.
//
//   $ swift run TUIKitInlineDemo
//   ┌─ Deploy ──────────────────────────────┐
//   │ Target:  [ staging ▾ ]                 │
//   │    Tag:  v1.4.2                        │
//   │                    [ Cancel ] [ Deploy ]│
//   └────────────────────────────────────────┘
//   deploying v1.4.2 to staging        ← printed after run() returns

@MainActor
func runInlinePrompt() async throws -> (target: String, tag: String)? {
    let app = App(driver: ANSIDriver(presentation: .inline(rows: 7)))
    app.applyTheme(.standard)

    let window = Window()   // fills the inline rows
    let panel = Panel("Deploy")
    panel.anchors = .fill()
    window.addSubview(panel)

    let targets = ["staging", "production"]
    let target = PopUpButton(items: targets, selectedIndex: 0)
    let tag = TextField(placeholder: "v1.4.2")
    var result: (target: String, tag: String)?

    let form = Form(spacing: 0) {
        Field("Target") { target }
        Field("Tag") { tag }
    }

    let buttons = HStack(spacing: 1)
    buttons.addSubview(TUIView())   // spacer
    buttons.addSubview(Button("&Cancel") { app.stop() })
    let deploy = Button("&Deploy") {
        result = (targets[target.selectedIndex ?? 0], tag.text.isEmpty ? "v1.4.2" : tag.text)
        app.stop()
    }
    deploy.role = .default
    buttons.addSubview(deploy)

    let column = VStack(spacing: 0)
    column.addSubview(form)
    column.addSubview(buttons)
    column.anchors = .fill()
    panel.content.addSubview(column)

    window.makeFirstResponder(tag)
    try await app.run(window)
    return result
}

do {
    if let choice = try await runInlinePrompt() {
        print("deploying \(choice.tag) to \(choice.target)")
    } else {
        print("cancelled")
    }
} catch {
    print("TUIKitInlineDemo needs a real terminal (\(error)).")
}
