/// How an actionable control signals that it can be activated.
///
/// ```text
///   .tinted     Run          ← accent-colored label (the default)
///   .bordered  [ Run ]       ← bracketed, for monochrome or minimalist UIs
/// ```
///
/// Buttons, pop-up buttons, and toolbar items default to `.tinted`: color
/// carries the affordance, so the label reads as a control without `[ ]`
/// chrome. `.bordered` keeps the classic bracketed look. On a colorless
/// theme (no accent) the tinted style falls back to an underline, so the
/// affordance survives without either color or brackets.
public enum ControlStyle: Sendable {
    /// Accent-colored label, no brackets (the default).
    case tinted

    /// Bracketed `[ Label ]`.
    case bordered

    /// Cells a label gains horizontally from this style's decoration
    /// (`[ x ]` adds four, ` x ` adds two).
    public var horizontalPadding: Int {
        self == .bordered ? 4 : 2
    }

    /// Wraps a label in the style's decoration.
    ///
    /// - Parameter label: The (already width-fitted) label text.
    /// - Returns: The decorated string, exactly `horizontalPadding` wider.
    func decorate(_ label: String) -> String {
        switch self {
        case .bordered:
            return "[ \(label) ]"

        case .tinted:
            return " \(label) "
        }
    }

    /// The resting style for an actionable, unfocused, un-pressed control.
    ///
    /// Bordered controls rest plain; tinted controls rest in the accent
    /// (bold), or underlined when the theme has no accent color.
    ///
    /// - Parameter theme: The control's effective theme.
    /// - Returns: The resting cell style.
    func restingStyle(theme: Theme) -> CellStyle {
        switch self {
        case .bordered:
            return CellStyle()

        case .tinted:
            if theme.accent != .standard {
                return CellStyle(foreground: theme.accent, flags: .bold)
            }

            return CellStyle(flags: .underline)
        }
    }
}
