import TUIKit

/// Chapter 3 — Controls & events, the declarative way.
///
/// The To-Do form: a text field, an Add button, the task list, and an About
/// tab — declared with TUIBuilder. Controls are ordinary values, so you keep
/// references to the ones you talk to and wire *semantic* events
/// (`onSubmit`, `onActivate`, `onSelectionChanged`) — never raw key codes.
public enum Chapter3: TutorialMilestone {
    public static let chapter = 3
    public static let title = "Controls & events (declarative)"

    /// The working to-do form inside a tab view.
    public static func makeWindow(app: App) -> Window {
        let window = Window()

        // Controls are declared up front so the event closures below can
        // reach them; they drop into the builder tree like any component.
        let field = TextField(placeholder: "new task")
        let tasks = ListView(items: ["Ship Chapter 3"])
        let status = Label("Type a task and press Return — or click Add.", style: CellStyle(flags: .dim))

        // One code path for every way a task gets added.
        func addTask() {
            guard !field.text.isEmpty else {
                status.text = "type something first"
                return
            }

            tasks.items.append(field.text)
            field.setText("")
            status.text = "added — \(tasks.items.count) in the list"
        }

        // Semantic events: Return in the field submits…
        field.onSubmit = { _ in addTask() }

        // …a click (or arrows) moves the selection…
        tasks.onSelectionChanged = { index in
            if let index {
                status.text = "selected: \(tasks.items[index])"
            }
        }

        // …and Return or a double-click activates: mark the task done.
        tasks.onActivate = { index in
            tasks.items[index] = "✓ " + tasks.items[index]
            status.text = "completed: \(tasks.items[index])"
        }

        window.setContent {
            TabView {
                Tab("Tasks") {
                    VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                        HStack(spacing: 1) {
                            field
                            Button("&Add") { addTask() }.role(.default)
                        }
                        tasks
                        status
                    }
                }
                Tab("About") {
                    VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                        Label("To-Do — the TUIKit tutorial app").bold()
                        Label("Chapter 3: controls and semantic events.")
                        Spacer()
                    }
                }
            }
        }

        // Start with the field focused so the reader can type immediately.
        window.makeFirstResponder(field)
        return window
    }
}
