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
public enum TUIKit {
    /// Framework version string.
    ///
    /// Pre-release versions are `0.x` and make no API stability promises.
    public static let version = "0.1.0"
}
