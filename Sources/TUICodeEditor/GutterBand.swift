import CodeEditorCore
import TUIKit

/// One vertical strip of the gutter.
///
/// The gutter is stacked bands rather than a wider number column, because the
/// things that belong there are independent: line numbers, a git change
/// ribbon, diagnostic severity, fold controls, breakpoints. Each knows its
/// own width, paints its own cells, and handles its own clicks; the editor
/// only stacks them.
///
/// ```text
///   ● ▌ ▾  12 │ func draw() {
///   │ │ │   └── numbers
///   │ │ └────── fold
///   │ └──────── git ribbon
///   └────────── breakpoint
/// ```
@MainActor
public protocol GutterBand: AnyObject {
    /// How many columns the band occupies. May change (line numbers widen).
    var width: Int { get }

    /// The cells for one document line.
    ///
    /// - Parameters:
    ///   - line: Zero-based document line.
    ///   - theme: The resolved theme, for colours.
    /// - Returns: Exactly ``width`` cells.
    func cells(forLine line: Int, theme: ResolvedTheme) -> [TerminalCell]

    /// A click landed in this band.
    ///
    /// - Parameter line: The document line clicked.
    /// - Returns: Whether the band consumed it.
    func handleClick(onLine line: Int) -> Bool
}

public extension GutterBand {
    func handleClick(onLine line: Int) -> Bool { false }
}

/// Right-aligned line numbers.
public final class LineNumberBand: GutterBand {
    /// Total lines, which decides how wide the band needs to be.
    public var lineCount: Int = 1

    /// The line the caret is on, drawn brighter.
    public var caretLine: Int = 0

    /// Creates the band.
    public init() {}

    public var width: Int {
        // Digits plus a trailing space; never narrower than 3 so the gutter
        // does not jitter as a file crosses 9 or 99 lines.
        max(3, String(max(1, lineCount)).count + 1)
    }

    public func cells(forLine line: Int, theme: ResolvedTheme) -> [TerminalCell] {
        guard line < lineCount else {
            return Array(repeating: TerminalCell(character: " ", style: theme.base), count: width)
        }

        var style = theme.base
        style.flags.insert(line == caretLine ? .bold : .dim)

        let text = String(line + 1).padded(to: width - 1, alignedRight: true) + " "
        return text.map { TerminalCell(character: $0, style: style) }
    }
}

/// The git change ribbon: one column showing how each line differs from the
/// committed baseline.
public final class ChangeRibbonBand: GutterBand {
    /// Working line → how it changed.
    public var changes: [Int: EditorLineChangeKind] = [:]

    /// Creates the band.
    public init() {}

    public var width: Int { 1 }

    public func cells(forLine line: Int, theme: ResolvedTheme) -> [TerminalCell] {
        var style = theme.base

        switch changes[line] {
        case .added:
            style.foreground = .named(.brightGreen)
            return [TerminalCell(character: "▌", style: style)]

        case .modified:
            style.foreground = .named(.brightYellow)
            return [TerminalCell(character: "▌", style: style)]

        case .deletedAbove:
            // The deleted text is by definition not on screen, so the marker
            // points at the boundary rather than at a line.
            style.foreground = .named(.brightRed)
            return [TerminalCell(character: "▔", style: style)]

        case nil:
            return [TerminalCell(character: " ", style: style)]
        }
    }
}

/// Diagnostic severity, one glyph per line.
public final class DiagnosticBand: GutterBand {
    /// The diagnostics being shown.
    public var diagnostics = DiagnosticSet()

    /// Called when a marked line is clicked.
    public var onSelect: (Int) -> Void = { _ in }

    /// Creates the band.
    public init() {}

    public var width: Int { 1 }

    public func cells(forLine line: Int, theme: ResolvedTheme) -> [TerminalCell] {
        guard let severity = diagnostics.worstSeverity(forLine: line) else {
            return [TerminalCell(character: " ", style: theme.base)]
        }

        var style = theme.base

        switch severity {
        case .error:
            style.foreground = .named(.brightRed)

        case .warning:
            style.foreground = .named(.brightYellow)

        case .info:
            style.foreground = .named(.brightCyan)
        }

        // Stale markers dim rather than vanish: after an edit they are out of
        // date but still the best information there is, and hiding them would
        // make a broken file look clean.
        if diagnostics.isStale {
            style.flags.insert(.dim)
        }

        let glyph: Character = severity == .error ? "✖" : (severity == .warning ? "⚠" : "●")
        return [TerminalCell(character: glyph, style: style)]
    }

    public func handleClick(onLine line: Int) -> Bool {
        guard diagnostics.worstSeverity(forLine: line) != nil else {
            return false
        }

        onSelect(line)
        return true
    }
}

/// Breakpoints. Nothing here knows what a debugger is — it stores dots and
/// reports clicks, so Phase 9B can adopt it without an upstream round trip.
public final class BreakpointBand: GutterBand {
    /// Lines carrying a breakpoint.
    public var breakpoints: Set<Int> = []

    /// Called when a line is clicked; the host decides what a breakpoint means.
    public var onToggle: (Int) -> Void = { _ in }

    /// Creates the band.
    public init() {}

    public var width: Int { 1 }

    public func cells(forLine line: Int, theme: ResolvedTheme) -> [TerminalCell] {
        var style = theme.base
        style.foreground = .named(.brightRed)
        return [TerminalCell(character: breakpoints.contains(line) ? "●" : " ", style: style)]
    }

    public func handleClick(onLine line: Int) -> Bool {
        onToggle(line)
        return true
    }
}

private extension String {
    func padded(to width: Int, alignedRight: Bool) -> String {
        guard count < width else {
            return String(suffix(width))
        }

        let padding = String(repeating: " ", count: width - count)
        return alignedRight ? padding + self : self + padding
    }
}

/// Fold controls: ▾ open, ▸ collapsed, blank when a line opens nothing.
public final class FoldBand: GutterBand {
    /// Which lines are foldable and which are collapsed.
    public var map = FoldMap()

    /// Called when a control is clicked.
    public var onToggle: (Int) -> Void = { _ in }

    /// Creates the band.
    public init() {}

    public var width: Int { 1 }

    public func cells(forLine line: Int, theme: ResolvedTheme) -> [TerminalCell] {
        guard map.isFoldable(line) else {
            return [TerminalCell(character: " ", style: theme.base)]
        }

        var style = theme.base
        style.flags.insert(.dim)
        return [TerminalCell(character: map.isFolded(line) ? "▸" : "▾", style: style)]
    }

    public func handleClick(onLine line: Int) -> Bool {
        guard map.isFoldable(line) else {
            return false
        }

        onToggle(line)
        return true
    }
}
