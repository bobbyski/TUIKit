import Foundation

/// How serious a log entry is.
///
/// **A name you can invent, and a number it sorts by.** Levels are open — an
/// app that wants `COMMAND` and `RESULT` alongside the usual ladder just makes
/// them:
///
/// ```swift
/// extension LogLevel {
///     static let command = LogLevel("COMMAND", severity: 25, icon: "🟣")
/// }
/// TUILogger.shared.log(.command, "git status")
/// ```
///
/// **The severity is what makes the filter safe.** Comparing numbers cannot
/// pass `COMM` because `COMMAND` contains it, whatever anybody names their
/// levels. (Mirrors ActiveUI's `AUILogLevel`, which replaced exactly that
/// string-matching bug.)
///
/// **A level *is* its name.** Two values with the same name are the same
/// level, so a category override set with one matches an entry logged with the
/// other. Do not make two levels with the same name and different severities;
/// there is nothing sensible for them to mean.
public struct LogLevel: Hashable, Sendable, Codable, Comparable,
                        ExpressibleByStringLiteral, CustomStringConvertible {
    /// What it is called. Upper-cased, so `"debug"` and `"DEBUG"` are one
    /// level rather than two that print differently.
    public let name: String

    /// Where it sits on the ladder. Higher is more serious.
    public let severity: Int

    /// The badge a console line is prefixed with.
    public let icon: String

    /// The ink this level's lines use — in a ``LogView`` and, via the SGR
    /// encoder, on a color console.
    public let color: TerminalColor

    /// Creates a level.
    ///
    /// `icon` and `color` default to the band the severity falls in, so a
    /// custom level looks like its neighbors without being told to.
    public init(_ name: String, severity: Int, icon: String? = nil, color: TerminalColor? = nil) {
        let upper = name.uppercased()
        self.name = upper
        self.severity = severity
        self.icon = icon ?? Self.defaultIcon(for: severity)
        self.color = color ?? Self.defaultColor(for: severity)
    }

    /// A level from a literal, matching a known one by name.
    ///
    /// `"warning"` is ``warning``, with its severity and its badge. A name
    /// nobody has heard of gets `info`'s severity, because a level that
    /// silently sorted below `trace` would vanish from every log.
    public init(stringLiteral value: String) {
        if let known = Self.known[value.uppercased()] {
            self = known
        } else {
            self.init(value, severity: LogLevel.info.severity)
        }
    }

    /// Reads a level written either as a bare name or as name-and-severity.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let name = try? container.decode(String.self) {
            self.init(stringLiteral: name)
            return
        }

        let pair = try container.decode([String: Int].self)

        guard let first = pair.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "empty log level")
        }

        self.init(first.key, severity: first.value)
    }

    /// Encodes as the bare name for a known level, so a saved log reads as
    /// `"WARNING"`; as name-and-severity for a custom one, so it comes back
    /// sorting where it did.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if Self.known[name] == self {
            try container.encode(name)
        } else {
            try container.encode([name: severity])
        }
    }

    /// A level is its name.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }

    /// Hashed by name, so a category override keyed by one value matches an
    /// entry logged with another of the same name.
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// Ordered by severity, then by name so a sort is stable.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.severity == rhs.severity ? lhs.name < rhs.name : lhs.severity < rhs.severity
    }

    /// The level, as its name.
    public var description: String { name }

    // MARK: - The usual ladder

    /// Very fine detail — every layout pass, every event.
    public static let trace = LogLevel("TRACE", severity: 0, icon: "⚪", color: .named(.brightBlack))

    /// What the code is doing, while you are working on it.
    public static let debug = LogLevel("DEBUG", severity: 10, icon: "🪲", color: .named(.blue))

    /// Something worth knowing happened.
    public static let info = LogLevel("INFO", severity: 20, icon: "⚫", color: .standard)

    /// Worth knowing and worth keeping: a document opened, a window restored.
    public static let notice = LogLevel("NOTICE", severity: 30, icon: "🟢", color: .named(.green))

    /// Something is off but the program carried on.
    public static let warning = LogLevel("WARNING", severity: 40, icon: "🟡", color: .named(.yellow))

    /// Something failed.
    public static let error = LogLevel("ERROR", severity: 50, icon: "🔴", color: .named(.red))

    /// Something failed that should have been impossible.
    public static let fault = LogLevel("FAULT", severity: 60, icon: "🟥", color: .named(.brightRed))

    /// The built-in ladder, in order.
    public static let standard: [LogLevel] = [.trace, .debug, .info, .notice, .warning, .error, .fault]

    private static let known: [String: LogLevel] =
        Dictionary(uniqueKeysWithValues: standard.map { ($0.name, $0) })

    /// The badge for a severity that named no icon of its own.
    private static func defaultIcon(for severity: Int) -> String {
        switch severity {
        case ..<10: "⚪"
        case ..<20: "🪲"
        case ..<30: "⚫"
        case ..<40: "🟢"
        case ..<50: "🟡"
        case ..<60: "🔴"
        default: "🟥"
        }
    }

    /// The ink for a severity that named no color of its own.
    private static func defaultColor(for severity: Int) -> TerminalColor {
        switch severity {
        case ..<10: .named(.brightBlack)
        case ..<20: .named(.blue)
        case ..<30: .standard
        case ..<40: .named(.green)
        case ..<50: .named(.yellow)
        case ..<60: .named(.red)
        default: .named(.brightRed)
        }
    }
}

/// What part of the program an entry came from.
///
/// **Separate from the level, because they answer different questions.** A
/// level says how much you want to hear; a category says what about. Rolled
/// into one, silencing the layout chatter also silences every error the app
/// raises, so nobody turns anything down and the log stays unreadable.
public struct LogCategory: Hashable, Sendable, Codable,
                           ExpressibleByStringLiteral, Comparable, CustomStringConvertible {
    /// The category's name.
    public let rawValue: String

    /// Creates a category.
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// Creates a category from a literal.
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Reads a category from a bare string.
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// Writes a category as a bare string.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The category, as its name.
    public var description: String { rawValue }

    /// Alphabetical, so a list of categories has a stable order.
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Anything the app itself logs.
    public static let app: LogCategory = "app"

    /// Layout passes and sizing.
    public static let layout: LogCategory = "layout"

    /// Theming and style resolution.
    public static let theme: LogCategory = "theme"

    /// Windows, documents and the application lifecycle.
    public static let lifecycle: LogCategory = "lifecycle"

    /// Mouse, keyboard, gestures.
    public static let input: LogCategory = "input"

    /// The terminal driver: probes, presents, resizes.
    public static let driver: LogCategory = "driver"

    /// Networking and anything else that crosses a wire.
    public static let network: LogCategory = "network"
}
