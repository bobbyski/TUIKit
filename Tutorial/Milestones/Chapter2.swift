import TUIKit

/// Chapter 2 — Layout: the app shell.
///
/// Stacks, panels, dividers, and intrinsic sizes build the To-Do app's
/// shell: a header row, a two-pane content area, and a status line. No
/// frames are computed by hand anywhere — fixed-size rows keep their
/// intrinsic height, flexible ones share the rest.
public enum Chapter2: TutorialMilestone {
    public static let chapter = 2
    public static let title = "Layout: the app shell"

    /// The shell: header / content panes / status, all from stacks.
    public static func makeWindow(app: App) -> Window {
        let window = Window()

        window.setContent {
            VStack(spacing: 0) {
                // Header: one intrinsic row.
                Label(" To-Do").bold()
                Divider(axis: .horizontal)

                // Content: two titled panels sharing the flexible middle.
                // Panels draw their own border and inset their content.
                HStack(spacing: 1) {
                    Panel("Tasks") {
                        Label("(the form arrives in Chapter 3)")
                    }
                    Panel("Details") {
                        Label("(select a task to see it here)")
                    }
                }

                // Status: one intrinsic row pinned to the bottom by the
                // flexible content above it.
                Divider(axis: .horizontal)
                Label(" Ready.", style: CellStyle(flags: .dim))
            }
        }

        return window
    }
}
