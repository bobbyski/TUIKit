/// TUIKit — an AppKit-inspired terminal UI framework for Swift.
///
/// TUIKit layers a familiar desktop architecture over the terminal:
///
/// ```text
///   Application code            (semantic events in, view tree out)
///        |
///   Controls & Views            (own interaction state, keys, mouse)
///        |
///   Layout & Rendering          (frames -> deterministic cells)
///        |
///   TerminalDriver protocol     (the only layer that sees a terminal)
///     |- ANSIDriver             (real terminals, macOS + Linux)
///     `- HeadlessDriver         (in-memory buffer for tests)
/// ```
///
/// Applications never touch escape sequences, raw key codes, or terminal
/// state; those live behind `TerminalDriver`. Everything above the driver is
/// deterministic — the same state, style, and frame always produce the same
/// cells — which is what makes the whole framework testable in CI through
/// `HeadlessDriver`.
///
/// Anything that needs to happen over *time* — animation, debounces, delayed
/// actions — goes through the timer facility rather than a blocking sleep or
/// a detached thread. `App.addTimer(every:)` and `App.schedule(after:)`
/// return a cancellable `AppTimer` whose body runs on the `MainActor` inside
/// the run loop (so a tick presents a frame like a keypress does), and whose
/// ticks come from an injectable `TimerSource` — the real clock in
/// production, a `ManualTimerSource` in tests. Timing is therefore
/// non-blocking and headless-scriptable, exactly like input. See
/// `Docs/Architecture.md`.

// RichSwift is part of TUIKit's public surface (`RichText`,
// `SyntaxTextView`, and their renderable/markup types), so it is
// re-exported: `import TUIKit` alone gives applications the full RichSwift
// API (Markup, Table, Panel, Syntax, …) with no separate import or
// dependency declaration. Note both modules export a few shared names
// (`Panel`, `Table`, `Text`) — qualify with `TUIKit.` or `RichSwift.` where
// the compiler asks.
@_exported import RichSwift

/// Framework metadata.
///
/// Named `TUIKitInfo` rather than `TUIKit` on purpose: a type with the
/// module's own name shadows the module, breaking `TUIKit.Panel`-style
/// qualification — which consumers need now that TUIKit re-exports
/// RichSwift and the two modules share a few type names.
public enum TUIKitInfo {
    /// Framework version string.
    ///
    /// Pre-release versions are `0.x` and make no API stability promises.
    public static let version = "0.1.0"
}
