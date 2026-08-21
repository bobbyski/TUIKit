/// Decodes raw terminal bytes into typed `TerminalInput` events.
///
/// The decoder is pure: bytes in, events out, no I/O and no timers. That
/// keeps the async boundary in the driver (per the never-block requirement)
/// and makes every escape sequence unit-testable byte for byte.
///
/// ```text
///   bytes ──> [ idle | escape | csi | ss3 | utf8 ] ──> TerminalInput
/// ```
///
/// A lone ESC is ambiguous (Escape key vs. the start of a sequence), so the
/// decoder holds it as pending; the driver calls `flushPending()` after a
/// short async delay when no more bytes arrive. Incomplete sequences cut off
/// mid-chunk are retained and completed by the next `feed(_:)`.
public struct ANSIInputDecoder: Sendable {
    private enum State: Sendable {
        /// Waiting for the start of a key or sequence.
        case idle

        /// Received ESC; the next byte decides key vs. sequence.
        case escape

        /// Inside a CSI sequence (`ESC [`); accumulating parameter bytes.
        case csi(parameters: [UInt8])

        /// Received `ESC O` (SS3); the next byte names a function key.
        case ss3

        /// Inside a UTF-8 multibyte character.
        case utf8(remaining: Int, bytes: [UInt8])

        /// Inside a control string — APC, DCS, OSC, PM or SOS.
        ///
        /// The payload is arbitrary text addressed to the *terminal*, not to
        /// the application, and is swallowed whole. `acceptsBEL` is set for
        /// OSC, the one form xterm also lets BEL terminate. `length` counts
        /// payload bytes toward ``controlStringCap``.
        case controlString(acceptsBEL: Bool, length: Int)

        /// Saw ESC inside a control string; `\` ends it, anything else is
        /// still payload.
        case controlStringEscape(acceptsBEL: Bool, length: Int)
    }

    /// The longest control-string payload the decoder will swallow.
    ///
    /// Real replies (VTG frame acks, OSC colour answers) are tens of bytes.
    /// This cap is the keyboard's lifeline: a control string whose
    /// terminator is lost — a dropped byte, a terminal dying mid-reply —
    /// would otherwise swallow every subsequent keystroke FOREVER, which
    /// reads as "the app locked up" while it still renders happily. Past
    /// the cap the decoder abandons the string and returns to idle; the
    /// stray tail may type a little garbage, but garbage beats deafness.
    static let controlStringCap = 4096

    private var state: State = .idle

    /// Creates a decoder in the idle state.
    public init() {}

    /// Whether a lone ESC is being held pending disambiguation.
    public var hasPendingEscape: Bool {
        if case .escape = state {
            return true
        }

        return false
    }

    /// Decodes a chunk of bytes into events.
    ///
    /// - Parameter bytes: Raw bytes read from the terminal.
    /// - Returns: Events completed by this chunk, in order.
    public mutating func feed(_ bytes: [UInt8]) -> [TerminalInput] {
        var events: [TerminalInput] = []

        for byte in bytes {
            events.append(contentsOf: consume(byte))
        }

        return events
    }

    /// Resolves a pending lone ESC as the Escape key.
    ///
    /// The driver calls this after a short delay when no further bytes have
    /// arrived. Any other incomplete sequence is discarded, since real
    /// terminals emit sequences atomically.
    ///
    /// - Returns: The Escape key event when one was pending.
    public mutating func flushPending() -> [TerminalInput] {
        defer { state = .idle }

        if case .escape = state {
            return [.key(KeyInput(key: .escape))]
        }

        return []
    }

    // Consumes one byte, advancing the state machine.
    private mutating func consume(_ byte: UInt8) -> [TerminalInput] {
        switch state {
        case .idle:
            return consumeIdle(byte)

        case .escape:
            return consumeEscape(byte)

        case .csi(let parameters):
            return consumeCSI(byte, parameters: parameters)

        case .ss3:
            state = .idle
            return ss3Key(byte).map { [.key(KeyInput(key: $0))] } ?? []

        case .controlString(let acceptsBEL, let length):
            return consumeControlString(byte, acceptsBEL: acceptsBEL, length: length)

        case .controlStringEscape(let acceptsBEL, let length):
            return consumeControlStringEscape(byte, acceptsBEL: acceptsBEL, length: length)

        case .utf8(let remaining, let bytes):
            return consumeUTF8(byte, remaining: remaining, collected: bytes)
        }
    }

    // MARK: - Idle

    private mutating func consumeIdle(_ byte: UInt8) -> [TerminalInput] {
        switch byte {
        // The C1 single-byte introducers (0x90, 0x98, 0x9D—0x9F) are deliberately
        // NOT recognised here. They are also UTF-8 continuation bytes, and a
        // terminal in UTF-8 mode — which is every terminal TUIKit targets —
        // sends the two-byte ESC forms instead. Treating a stray continuation
        // byte as "start swallowing until ST" would turn one corrupt byte into
        // a dead keyboard; dropping it costs nothing.
        case 0x1B:
            state = .escape
            return []

        case 0x0D, 0x0A:
            return [.key(KeyInput(key: .enter))]

        case 0x09:
            return [.key(KeyInput(key: .tab))]

        case 0x7F, 0x08:
            return [.key(KeyInput(key: .backspace))]

        case 0x01...0x1A:
            // Remaining control characters are Control+letter.
            let letter = Character(UnicodeScalar(byte + 0x60))
            return [.key(KeyInput(key: .character(letter), modifiers: .control))]

        case 0x1F:
            // US, and what a terminal sends for Ctrl+/ — the chord every GUI
            // editor uses for "comment this out". It arrives from Ctrl+_ and
            // Ctrl+7 as well on some terminals, since all three collapse to
            // the same byte; reported as Ctrl+/ because that is the one
            // anybody is actually pressing.
            //
            // Dropped before this, which made the most familiar shortcut in
            // any code editor the one chord a TUI could not offer.
            return [.key(KeyInput(key: .character("/"), modifiers: .control))]

        case 0x20...0x7E:
            return [.key(KeyInput(key: .character(Character(UnicodeScalar(byte)))))]

        case 0xC2...0xDF:
            state = .utf8(remaining: 1, bytes: [byte])
            return []

        case 0xE0...0xEF:
            state = .utf8(remaining: 2, bytes: [byte])
            return []

        case 0xF0...0xF4:
            state = .utf8(remaining: 3, bytes: [byte])
            return []

        default:
            // Unrepresentable byte; drop it.
            return []
        }
    }

    // MARK: - Escape

    /// Swallows a control-string payload, watching for its terminator.
    private mutating func consumeControlString(
        _ byte: UInt8,
        acceptsBEL: Bool,
        length: Int
    ) -> [TerminalInput] {
        switch byte {
        case 0x1B:
            state = .controlStringEscape(acceptsBEL: acceptsBEL, length: length)

        case 0x9C:
            // ST in its single-byte C1 form.
            state = .idle

        case 0x07 where acceptsBEL:
            state = .idle

        default:
            guard length < Self.controlStringCap else {
                // Terminator lost. Abandon the string rather than staying
                // deaf; this byte is stale payload, so drop it too.
                state = .idle
                return []
            }

            state = .controlString(acceptsBEL: acceptsBEL, length: length + 1)
        }

        return []
    }

    /// Resolves ESC inside a control string: `ESC \` is ST, anything else is
    /// payload that happened to contain an ESC.
    private mutating func consumeControlStringEscape(
        _ byte: UInt8,
        acceptsBEL: Bool,
        length: Int
    ) -> [TerminalInput] {
        state = byte == UInt8(ascii: "\\")
            ? .idle
            : .controlString(acceptsBEL: acceptsBEL, length: length + 1)

        return []
    }

    private mutating func consumeEscape(_ byte: UInt8) -> [TerminalInput] {
        switch byte {
        case UInt8(ascii: "["):
            state = .csi(parameters: [])
            return []

        case UInt8(ascii: "O"):
            state = .ss3
            return []

        case 0x1B:
            // ESC ESC: report the first, hold the second.
            return [.key(KeyInput(key: .escape))]

        // Control-string introducers. Their payload is a conversation between
        // the terminal and whatever is driving it — a VTG frame acknowledgement,
        // an OSC colour reply — and it is *printable text*. Without a state to
        // swallow it, every byte falls through to "Alt+printable" below and
        // then to plain characters, so the reply gets typed into whatever holds
        // focus: `VTG;frameStarted,id=tuikit-chrome,timeout=250` appearing in a
        // text field is this bug, not the terminal misbehaving.
        case UInt8(ascii: "_"), UInt8(ascii: "P"), UInt8(ascii: "^"), UInt8(ascii: "X"):
            state = .controlString(acceptsBEL: false, length: 0)
            return []

        case UInt8(ascii: "]"):
            state = .controlString(acceptsBEL: true, length: 0)
            return []

        case 0x20...0x7E:
            // Alt+printable.
            state = .idle
            return [.key(KeyInput(key: .character(Character(UnicodeScalar(byte))), modifiers: .alt))]

        default:
            state = .idle
            return [.key(KeyInput(key: .escape))]
        }
    }

    // MARK: - CSI

    private mutating func consumeCSI(_ byte: UInt8, parameters: [UInt8]) -> [TerminalInput] {
        // Parameter (0x30-0x3F) and intermediate (0x20-0x2F) bytes accumulate;
        // a final byte (0x40-0x7E) terminates the sequence.
        if (0x20...0x3F).contains(byte) {
            state = .csi(parameters: parameters + [byte])
            return []
        }

        state = .idle

        guard (0x40...0x7E).contains(byte) else {
            return []
        }

        let final = Character(UnicodeScalar(byte))
        let text = String(decoding: parameters, as: UTF8.self)

        if text.hasPrefix("<"), final == "M" || final == "m" {
            return decodeSGRMouse(text.dropFirst(), isPress: final == "M")
        }

        return decodeCSIKey(final: final, parameters: text)
    }

    // Decodes non-mouse CSI finals into key events.
    private func decodeCSIKey(final: Character, parameters: String) -> [TerminalInput] {
        let fields = parameters.split(separator: ";").map { Int($0) ?? 0 }
        let modifiers = Self.modifiers(fromXtermField: fields.count > 1 ? fields[1] : 1)

        let key: Key?

        switch final {
        case "A": key = .up
        case "B": key = .down
        case "C": key = .right
        case "D": key = .left
        case "H": key = .home
        case "F": key = .end
        case "Z": return [.key(KeyInput(key: .tab, modifiers: modifiers.union(.shift)))]
        case "P", "Q", "R", "S":
            // F1-F4 in the CSI form some terminals use with modifiers.
            let numbers: [Character: Int] = ["P": 1, "Q": 2, "R": 3, "S": 4]
            key = numbers[final].map(Key.function)
        case "~": key = Self.tildeKey(code: fields.first ?? 0)
        default: key = nil
        }

        guard let key else {
            return []
        }

        return [.key(KeyInput(key: key, modifiers: modifiers))]
    }

    // Maps `CSI n ~` key codes.
    private static func tildeKey(code: Int) -> Key? {
        switch code {
        case 1, 7: .home
        case 2: .insert
        case 3: .delete
        case 4, 8: .end
        case 5: .pageUp
        case 6: .pageDown
        case 11...15: .function(code - 10)
        case 17...21: .function(code - 11)
        case 23, 24: .function(code - 12)
        default: nil
        }
    }

    // Maps SS3 finals (`ESC O x`) to keys.
    private func ss3Key(_ byte: UInt8) -> Key? {
        switch byte {
        case UInt8(ascii: "P"): .function(1)
        case UInt8(ascii: "Q"): .function(2)
        case UInt8(ascii: "R"): .function(3)
        case UInt8(ascii: "S"): .function(4)
        case UInt8(ascii: "A"): .up
        case UInt8(ascii: "B"): .down
        case UInt8(ascii: "C"): .right
        case UInt8(ascii: "D"): .left
        case UInt8(ascii: "H"): .home
        case UInt8(ascii: "F"): .end
        default: nil
        }
    }

    // Converts the xterm modifier field (value = 1 + bitmask) to modifiers.
    private static func modifiers(fromXtermField field: Int) -> KeyModifiers {
        let mask = max(0, field - 1)
        var modifiers: KeyModifiers = []

        if mask & 1 != 0 { modifiers.insert(.shift) }
        if mask & 2 != 0 { modifiers.insert(.alt) }
        if mask & 4 != 0 { modifiers.insert(.control) }

        return modifiers
    }

    // MARK: - SGR Mouse

    // Decodes `CSI < b ; x ; y M/m` (SGR mouse mode 1006).
    private func decodeSGRMouse(_ body: Substring, isPress: Bool) -> [TerminalInput] {
        let fields = body.split(separator: ";").map { Int($0) ?? 0 }

        guard fields.count == 3 else {
            return []
        }

        let code = fields[0]
        // SGR positions are 1-based.
        let position = Point(x: fields[1] - 1, y: fields[2] - 1)

        var modifiers: KeyModifiers = []
        if code & 4 != 0 { modifiers.insert(.shift) }
        if code & 8 != 0 { modifiers.insert(.alt) }
        if code & 16 != 0 { modifiers.insert(.control) }

        let action: MouseInput.Action
        let button: MouseInput.Button

        if code & 64 != 0 {
            action = (code & 3) == 0 ? .scrollUp : .scrollDown
            button = .none
        } else {
            let buttonBits = code & 3

            button = switch buttonBits {
            case 0: .left
            case 1: .middle
            case 2: .right
            default: .none
            }

            if code & 32 != 0 {
                action = buttonBits == 3 ? .move : .drag
            } else {
                action = isPress ? .press : .release
            }
        }

        return [.mouse(MouseInput(position: position, action: action, button: button, modifiers: modifiers))]
    }

    // MARK: - UTF-8

    private mutating func consumeUTF8(
        _ byte: UInt8,
        remaining: Int,
        collected: [UInt8]
    ) -> [TerminalInput] {
        guard (0x80...0xBF).contains(byte) else {
            // Broken sequence; drop it and reprocess this byte from idle.
            state = .idle
            return consume(byte)
        }

        let bytes = collected + [byte]

        if remaining > 1 {
            state = .utf8(remaining: remaining - 1, bytes: bytes)
            return []
        }

        state = .idle

        let text = String(decoding: bytes, as: UTF8.self)

        guard let character = text.first, character != "\u{FFFD}" else {
            return []
        }

        return [.key(KeyInput(key: .character(character)))]
    }
}
