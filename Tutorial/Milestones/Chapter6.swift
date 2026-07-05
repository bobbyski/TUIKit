import TUIKit

/// Chapter 6 — The traditional approach (the old-school appendix).
///
/// Chapter 3's form again, with no builder in sight: views constructed by
/// hand, added with `addSubview`, positioned with `AnchorSet` (or explicit
/// frames), events wired the same way. Builders emit exactly this tree —
/// the declarative chapters and this one produce the same `TUIView`s, so
/// everything (themes, focus, testing) works identically. Prefer the
/// declarative style; drop down here when a view graph is dynamic or a
/// custom container wants full control.
public enum Chapter6: TutorialMilestone {
    public static let chapter = 6
    public static let title = "Traditional approach (hand-wired Chapter 3)"

    /// The to-do form, hand-wired.
    public static func makeWindow(app: App) -> Window {
        let window = Window()

        // 1. Construct the views.
        let field = TextField(placeholder: "new task")
        let add = Button("&Add")
        add.role = .default
        let tasks = ListView(items: ["Ship Chapter 6"])
        let status = Label("The same app — not a builder in sight.", style: CellStyle(flags: .dim))

        // 2. Position them: anchors pin edges; unpinned axes take the
        //    view's intrinsic size (the button sizes itself, trailing-pinned).
        field.anchors = AnchorSet(leading: 1, trailing: 10, top: 1, height: 1)
        add.anchors = AnchorSet(trailing: 1, top: 1, height: 1)
        tasks.anchors = AnchorSet(leading: 1, trailing: 1, top: 3, bottom: 2)
        status.anchors = AnchorSet(leading: 1, trailing: 1, bottom: 0, height: 1)

        // 3. Wire the events — identical to Chapter 3.
        func addTask() {
            guard !field.text.isEmpty else {
                return
            }

            tasks.items.append(field.text)
            field.setText("")
            status.text = "added — \(tasks.items.count) in the list"
        }

        field.onSubmit = { _ in addTask() }
        add.onActivate = { addTask() }

        tasks.onSelectionChanged = { index in
            if let index {
                status.text = "selected: \(tasks.items[index])"
            }
        }

        tasks.onActivate = { index in
            tasks.items[index] = "✓ " + tasks.items[index]
            status.text = "completed: \(tasks.items[index])"
        }

        // 4. Hang everything off the window.
        window.addSubview(field)
        window.addSubview(add)
        window.addSubview(tasks)
        window.addSubview(status)

        window.makeFirstResponder(field)
        return window
    }
}
