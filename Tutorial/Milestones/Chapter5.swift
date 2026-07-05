import TUIKit

/// Chapter 5 — Testing your app.
///
/// No new UI: the milestone IS Chapter 4's app, because the chapter is
/// about proving it works headlessly. `HeadlessDriver` is a full driver,
/// not a mock — tests script real input through `send(_:)` and assert on
/// `snapshotText()`. The chapter's example tests live in
/// `Tests/TUIKitTutorialTests/` and run in CI, so they can never rot.
public enum Chapter5: TutorialMilestone {
    public static let chapter = 5
    public static let title = "Testing your app (Chapter 4's app, under test)"

    /// Chapter 4's window, unchanged — the subject under test.
    public static func makeWindow(app: App) -> Window {
        Chapter4.makeWindow(app: app)
    }
}
