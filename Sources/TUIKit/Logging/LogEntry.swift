import Foundation

/// One line in the log.
///
/// **A value, not an object.** An entry already written cannot be edited
/// afterwards — a log you can rewrite is not a log.
public struct LogEntry: Hashable, Sendable, Codable, Identifiable {
    /// A stable identity, so a view can diff without comparing messages.
    public let id: UInt64

    /// When it happened.
    public let date: Date

    /// How serious.
    public let level: LogLevel

    /// What part of the program it came from.
    public let category: LogCategory

    /// What was said.
    public let message: String

    /// The file the call was made from.
    public let file: String

    /// The line the call was made from.
    public let line: Int

    /// The function the call was made from.
    public let function: String

    /// Creates an entry.
    public init(id: UInt64, date: Date, level: LogLevel, category: LogCategory,
                message: String, file: String, line: Int, function: String) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.file = file
        self.line = line
        self.function = function
    }

    /// Just the file name, which is what a log line has room for.
    public var fileName: String {
        file.split(separator: "/").last.map(String.init) ?? file
    }

    /// `TUIView.swift:412`, the thing you actually want to look up.
    public var origin: String { "\(fileName):\(line)" }

    /// The first line of the message, for a list that shows one line per
    /// entry.
    public var summary: String {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
    }

    /// Whether the message runs to more than one line.
    public var isMultiline: Bool { message.contains("\n") }
}
