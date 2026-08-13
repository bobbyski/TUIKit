import CodeEditorCore
import TUIKit

/// Maps the core's UI-free colours onto terminal cells.
///
/// The whole reason `CodeEditorCore` speaks in ``EditorColor`` rather than
/// `CellStyle`: the core stays adoptable by a GUI editor, and this file is the
/// entire cost of that on the terminal side.
extension EditorColor {
    /// The terminal colour for this scope colour.
    var terminalColor: TerminalColor {
        switch self {
        case .default: return .standard
        case .black: return .named(.black)
        case .red: return .named(.red)
        case .green: return .named(.green)
        case .yellow: return .named(.yellow)
        case .blue: return .named(.blue)
        case .magenta: return .named(.magenta)
        case .cyan: return .named(.cyan)
        case .white: return .named(.white)
        case .brightBlack: return .named(.brightBlack)
        case .brightRed: return .named(.brightRed)
        case .brightGreen: return .named(.brightGreen)
        case .brightYellow: return .named(.brightYellow)
        case .brightBlue: return .named(.brightBlue)
        case .brightMagenta: return .named(.brightMagenta)
        case .brightCyan: return .named(.brightCyan)
        case .brightWhite: return .named(.brightWhite)
        }
    }
}

extension ScopeStyle {
    /// This scope style as a cell style, over a base.
    ///
    /// - Parameter base: The theme's ordinary text style, so a scope that
    ///   only sets bold keeps the theme's colours.
    func cellStyle(over base: CellStyle) -> CellStyle {
        var style = base

        if color != .default {
            style.foreground = color.terminalColor
        }

        if isBold {
            style.flags.insert(.bold)
        }

        if isDim {
            style.flags.insert(.dim)
        }

        if isItalic {
            style.flags.insert(.italic)
        }

        return style
    }
}
