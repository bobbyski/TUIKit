import Foundation
import TUIKit

// Declarative Example — the "hello, TUIBuilder" window and the app's default at
// launch. Everything here is built once and never rebuilt, so it stays purely
// declarative (no setContent-per-selection like the Contact Book). It shows how
// controls talk to each other via their change callbacks.
extension DemoApp {
    func makeDeclarativeExample(index: Int) -> FloatingWindow {
        let app = self.app
        let window = FloatingWindow(
            title: "Declarative Example \(index)",
            frame: Rect(x: 8 + index * 4, y: 4 + index * 2, width: 54, height: 20)
        )
        // No theme override: inherit the app theme (the desktop), so a window
        // opened after the user picks Turbo comes up Turbo, not standard.
        window.themeContext = .secondaryWindows   // a form/dialog surface (Turbo: gray)
        window.onCloseRequest = { [weak window] in
            if let window { app.dismiss(window) }
        }

        // These three are declared *before* the builder and captured inside it.
        // Why not inline them? Because other controls' callbacks need to reach
        // them by name — the Slider updates `progress`, and several controls write
        // to `status`. Declaring them here gives those closures something stable
        // to refer to. Controls with no such cross-references (the buttons, the
        // segmented control) are created inline in the tree below.
        let status = Label("Built with TUIBuilder — try the controls.", style: CellStyle(flags: .dim))
        let progress = ProgressIndicator(style: .bar, value: 40, minValue: 0, maxValue: 100)
        progress.showsPercentage = true

        let nameField = TextField(placeholder: "type a name")
        nameField.onSubmit { status.text = "name: \($0)" }

        // The whole window content, declared once. `Form` lines the labeled rows
        // up for free; `.onValueChanged`/`.onSelectionChanged` are builder
        // modifiers that attach callbacks inline. `setContent` runs this closure
        // to build a view tree and fill-anchors it into the window's content area.
        window.content.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                Label("A form, declared with TUIBuilder").bold()

                Form {
                    Field("Name") { nameField }
                    Field("Mode") {
                        SegmentedControl(["Fast", "Balanced", "Accurate"], selectedIndex: 1)
                            .onSelectionChanged { status.text = "mode \($0)" }
                    }
                    Field("Fill") {
                        Slider(value: 40, in: 0...100, step: 5).onValueChanged { value in
                            progress.doubleValue = Double(value)
                            status.text = "fill \(value)%"
                        }
                    }
                }

                Toggle("Wrap lines").onChange { status.text = "wrap: \($0)" }
                progress

                Spacer()

                HStack(spacing: 2) {
                    Spacer()
                    Button("&Reset") { status.text = "reset" }
                    Button("&Save") { status.text = "saved" }.role(.default)
                }

                status
            }
        }

        window.makeFirstResponder(nameField)   // start typing immediately
        return window
    }
}
