import TUIKit

/// Chapter 4 — Focus, keys & mouse.
///
/// The same To-Do app, now with an app-level shortcut. Keys route hot →
/// focused → Tab → cold: a `Window` subclass answers the *hot-key* pass
/// (before any focused control sees the key), the focused control gets its
/// turn next, and Tab traversal is free. Ctrl+N jumps to the task field
/// from anywhere; Alt+A stays the Add mnemonic.
public final class Chapter4Window: Window {
    /// Called when Ctrl+N asks for a new task from anywhere in the window.
    var onNewTask: () -> Void = {}

    /// The hot-key pass runs before focus routing — this fires even while
    /// the list or a button holds the keyboard.
    public override func handleHotKey(_ key: KeyInput) -> Bool {
        if key.modifiers == .control, key.key == .character("n") {
            onNewTask()
            return true
        }

        return false
    }
}

/// The milestone: Chapter 3's form plus keyboard plumbing.
public enum Chapter4: TutorialMilestone {
    public static let chapter = 4
    public static let title = "Focus, keys & mouse"

    /// The to-do form with Ctrl+N, mnemonics, and a focus hint.
    public static func makeWindow(app: App) -> Window {
        let window = Chapter4Window()

        let field = TextField(placeholder: "new task  (^N focuses me from anywhere)")
        let tasks = ListView(items: ["Ship Chapter 4"])
        let status = Label(
            "Tab cycles focus · ^N new task · Alt+A adds · double-click completes",
            style: CellStyle(flags: .dim)
        )

        func addTask() {
            guard !field.text.isEmpty else {
                return
            }

            tasks.items.append(field.text)
            field.setText("")
            status.text = "added — \(tasks.items.count) in the list"
        }

        field.onSubmit = { _ in addTask() }

        tasks.onSelectionChanged = { index in
            if let index {
                status.text = "selected: \(tasks.items[index])"
            }
        }

        tasks.onActivate = { index in
            tasks.items[index] = "✓ " + tasks.items[index]
            status.text = "completed: \(tasks.items[index])"
        }

        // The window-level shortcut: focus the field, wherever keys were.
        window.onNewTask = { [weak window, weak field] in
            if let window, let field {
                window.makeFirstResponder(field)
                status.text = "^N — ready for a new task"
            }
        }

        window.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                HStack(spacing: 1) {
                    field
                    Button("&Add") { addTask() }.role(.default)
                }
                tasks
                status
            }
        }

        window.makeFirstResponder(field)
        return window
    }
}
