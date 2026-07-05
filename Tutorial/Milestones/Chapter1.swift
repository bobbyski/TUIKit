import TUIKit

/// Chapter 1 — Hello, terminal.
///
/// The smallest possible TUIKit app: an `App` on a driver, one `Window`,
/// declarative content, and a clean exit. Run it:
///
/// ```sh
/// swift run TUIKitTutorial ch1
/// ```
public enum Chapter1: TutorialMilestone {
    public static let chapter = 1
    public static let title = "Hello, terminal"

    /// A full-screen window with a greeting and a Quit button.
    public static func makeWindow(app: App) -> Window {
        // A zero-frame window fills the screen and follows resizes.
        let window = Window()

        // `setContent` installs a built component tree as the window's
        // (fill-anchored) root. Everything here is a plain TUIView underneath.
        window.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 2)) {
                Label("Hello, terminal!").bold()
                Label("Every frame you see is cells — try resizing the window.")

                // The `&` marks a keyboard mnemonic: Alt+Q activates it, and
                // the Q renders in the theme's accelerator color.
                Button("&Quit") { app.stop() }

                // A flexible spacer keeps the content at the top.
                Spacer()
            }
        }

        return window
    }
}
