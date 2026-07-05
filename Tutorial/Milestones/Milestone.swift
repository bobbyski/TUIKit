import TUIKit

/// One tutorial chapter's runnable end state.
///
/// Every chapter of `Docs/Tutorial/` ends in a milestone the reader can run
/// (`swift run TUIKitTutorial ch3`). The milestone types in this target ARE
/// the chapters' code: the markdown quotes these files, this library builds
/// with only public TUIKit API, and `TUIKitTutorialTests` renders each
/// milestone headlessly — so a chapter that drifts from the framework fails
/// the build or CI instead of silently rotting.
@MainActor
public protocol TutorialMilestone {
    /// Chapter number; `ch3` on the command line runs chapter 3.
    static var chapter: Int { get }

    /// Short title shown by the runner's usage listing.
    static var title: String { get }

    /// Builds the chapter's window against the running app.
    ///
    /// The window is handed straight to `app.run(_:)`; a zero frame means
    /// it fills the screen and follows resizes.
    static func makeWindow(app: App) -> Window
}

/// The chapter registry, in order — the runner and the anti-rot tests
/// iterate this, so adding a chapter is one entry here.
public enum TutorialMilestones {
    /// Every milestone, chapter 1 through 6.
    @MainActor
    public static let all: [any TutorialMilestone.Type] = [
        Chapter1.self,
        Chapter2.self,
        Chapter3.self,
        Chapter4.self,
        Chapter5.self,
        Chapter6.self,
    ]
}
