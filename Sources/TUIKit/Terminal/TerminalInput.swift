/// A key a terminal can deliver.
///
/// Drivers decode raw bytes and escape sequences into these values; nothing
/// above the driver layer ever sees an escape sequence.
public enum Key: Hashable, Sendable {
    /// A printable character.
    case character(Character)

    /// The Return/Enter key.
    case enter

    /// The Tab key.
    case tab

    /// The Backspace key.
    case backspace

    /// The Escape key.
    case escape

    /// Arrow keys.
    case up, down, left, right

    /// Navigation keys.
    case home, end, pageUp, pageDown

    /// The forward-delete key.
    case delete

    /// The Insert key (with modifiers, the classic clipboard chords:
    /// Ctrl+Insert copy, Shift+Insert paste).
    case insert

    /// A function key by number (F1 is `function(1)`).
    case function(Int)
}

/// Modifier keys active during an input event.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    /// Raw bitset value.
    public let rawValue: Int

    /// Creates modifiers from a raw bitset.
    ///
    /// - Parameter rawValue: Raw bitset value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Shift key.
    public static let shift = KeyModifiers(rawValue: 1 << 0)

    /// Control key.
    public static let control = KeyModifiers(rawValue: 1 << 1)

    /// Alt/Option key.
    public static let alt = KeyModifiers(rawValue: 1 << 2)
}

/// One decoded keyboard event.
public struct KeyInput: Hashable, Sendable {
    /// Key that was pressed.
    public var key: Key

    /// Modifiers active for the press.
    public var modifiers: KeyModifiers

    /// Creates a keyboard event.
    ///
    /// - Parameters:
    ///   - key: Key that was pressed.
    ///   - modifiers: Modifiers active for the press.
    public init(key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// One decoded mouse event.
public struct MouseInput: Hashable, Sendable {
    /// What the mouse did.
    public enum Action: Hashable, Sendable {
        /// A button was pressed.
        case press

        /// A button was released.
        case release

        /// The pointer moved with a button held.
        case drag

        /// A completed click gesture (press + release at the same spot),
        /// delivered once the multi-click guard settles — see `clickCount`.
        /// Low-level `press`/`release` still fire immediately and unchanged;
        /// this is the debounced semantic event that tells single from double.
        case click

        /// The pointer moved with no button held.
        case move

        /// The scroll wheel moved up.
        case scrollUp

        /// The scroll wheel moved down.
        case scrollDown
    }

    /// Mouse button involved, when any.
    public enum Button: Hashable, Sendable {
        /// Primary button.
        case left

        /// Middle button.
        case middle

        /// Secondary button.
        case right

        /// No button (moves and scrolls).
        case none
    }

    /// Pointer position in terminal cell coordinates.
    public var position: Point

    /// What the mouse did.
    public var action: Action

    /// Button involved.
    public var button: Button

    /// Modifiers active for the event.
    public var modifiers: KeyModifiers

    /// How many clicks this gesture is part of, capped at 3. Only meaningful on
    /// `.click` events: `1` single, `2` double, `3` triple. Other actions leave
    /// it at `1`.
    public var clickCount: Int

    /// Creates a mouse event.
    ///
    /// - Parameters:
    ///   - position: Pointer position in terminal cell coordinates.
    ///   - action: What the mouse did.
    ///   - button: Button involved.
    ///   - modifiers: Modifiers active for the event.
    ///   - clickCount: Clicks in this gesture (`.click` only); defaults to `1`.
    public init(
        position: Point,
        action: Action,
        button: Button = .none,
        modifiers: KeyModifiers = [],
        clickCount: Int = 1
    ) {
        self.position = position
        self.action = action
        self.button = button
        self.modifiers = modifiers
        self.clickCount = clickCount
    }
}

/// One decoded terminal input event.
public enum TerminalInput: Hashable, Sendable {
    /// A keyboard event.
    case key(KeyInput)

    /// A mouse event.
    case mouse(MouseInput)

    /// The terminal was resized.
    case resize(Size)
}
