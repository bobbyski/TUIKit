/// How wide the next double-click should select.
public enum SelectionScope: Equatable, Sendable {
    /// The word under the pointer.
    case word

    /// The whole line it is on.
    case line

    /// Everything in the control.
    case all

    /// Nothing — the click after "everything".
    case none
}

/// The escalating double-click, as every Mac text control does it.
///
/// ```text
///   double-click a word            → the word
///   double-click it again          → its line
///   double-click the line again    → everything
///   double-click everything        → nothing
/// ```
///
/// Derived from what is ALREADY SELECTED rather than from a count of clicks.
/// A counter has to be reset — on a click elsewhere, on a keystroke, on a
/// selection made some other way — and every one of those resets is a rule
/// somebody has to remember to write. "If the selection is already the word,
/// widen to the line" needs no memory at all, and behaves correctly when the
/// selection arrived from the keyboard, from Select All, or from a drag.
///
/// A single-line control passes the same range for `line` and `all`, and the
/// ladder simply has one rung fewer.
public enum SelectionEscalation {
    /// What a double-click should select next.
    ///
    /// - Parameters:
    ///   - isWord: Whether the current selection is exactly the clicked word.
    ///   - isLine: Whether it is exactly the clicked line.
    ///   - isAll: Whether it is the whole content.
    /// - Returns: The scope to select.
    public static func nextScope(isWord: Bool, isLine: Bool, isAll: Bool) -> SelectionScope {
        // Widest first: in a one-line control the line IS everything, and
        // asking about the word first would loop between word and line.
        if isAll {
            return .none
        }

        if isLine {
            return .all
        }

        if isWord {
            return .line
        }

        return .word
    }
}
