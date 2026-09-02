import Foundation

/// Turns an entry into one line of text.
///
/// **One formatter, used everywhere text comes out.** The console, the file a
/// destination writes, ``LogStore/exported(using:)`` and the pasteboard all go
/// through this, so a log looks the same wherever it lands — and a line
/// copied out of ``LogView`` into a bug report is the same line that was in
/// the terminal.
///
/// **Fixed columns, because a log ends up in a text file.** Every field is
/// padded to a known width — in display COLUMNS, not characters
/// (`DisplayWidth`), because the badge is two columns wide and a CJK path
/// would otherwise stagger every line after it. Ragged columns are unreadable
/// down the page and undiffable between two runs.
///
/// **The widths are worked out once.** `indent` — the blanks a continuation
/// line hangs under — is built when the formatter is made, not counted per
/// entry, and the head width follows from the options rather than from the
/// longest thing seen so far.
public struct LogLineFormatter: Sendable {
    /// Whether the timestamp is written.
    public let showsTime: Bool

    /// Whether the level's badge is written.
    public let showsIcon: Bool

    /// Whether the category is written.
    public let showsCategory: Bool

    /// Whether `File.swift:42` is written.
    public let showsOrigin: Bool

    /// How wide the category column is.
    public let categoryWidth: Int

    /// How wide the origin column is.
    public let originWidth: Int

    /// How wide the level column is.
    public let levelWidth: Int

    /// The blanks a continuation line starts with. Built once.
    public let indent: String

    /// How many columns come before the message.
    public let headWidth: Int

    /// **One `DateFormatter`, reused.** Building one per line costs 16µs
    /// against 0.8µs — twenty times over, on every line of every log. The
    /// format is fixed rather than the locale's short style, because a
    /// timestamp that changes shape by region is one you cannot grep and
    /// cannot compare against another machine's log. Configured once and
    /// never mutated, which is the shape `DateFormatter` is thread-safe in.
    private let formatter: DateFormatter

    /// The width of `yyyy-MM-dd HH:mm:ss.SSS`.
    private static let timeWidth = 23

    /// Creates a formatter.
    public init(showsTime: Bool = true, showsIcon: Bool = true,
                showsCategory: Bool = true, showsOrigin: Bool = true,
                categoryWidth: Int = 10, originWidth: Int = 24, levelWidth: Int = 7) {
        self.showsTime = showsTime
        self.showsIcon = showsIcon
        self.showsCategory = showsCategory
        self.showsOrigin = showsOrigin
        self.categoryWidth = max(1, categoryWidth)
        self.originWidth = max(1, originWidth)
        self.levelWidth = max(1, levelWidth)

        let made = DateFormatter()
        made.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        made.locale = Locale(identifier: "en_US_POSIX")
        formatter = made

        var width = 0
        if showsTime { width += Self.timeWidth + 2 }
        width += self.levelWidth
        if showsIcon { width += 4 }   // " " + a two-column badge + " "
        if showsCategory { width += self.categoryWidth + 3 }   // " [" name "]"
        if showsOrigin { width += self.originWidth + 1 }
        width += 2
        headWidth = width
        indent = String(repeating: " ", count: width)
    }

    /// Everything before the message.
    public func head(for entry: LogEntry) -> String {
        var head = ""
        if showsTime { head += formatter.string(from: entry.date) + "  " }
        head += Self.fit(entry.level.name, levelWidth)
        if showsIcon { head += " " + Self.fit(entry.level.icon, 2) + " " }
        if showsCategory { head += " [" + Self.fit(entry.category.rawValue, categoryWidth) + "]" }
        if showsOrigin { head += " " + Self.fit(entry.origin, originWidth) }
        return head + "  "
    }

    /// One entry as text, with continuation lines hanging under the message.
    public func string(for entry: LogEntry) -> String {
        let head = head(for: entry)

        guard entry.isMultiline else { return head + entry.message }

        let lines = entry.message.split(separator: "\n", omittingEmptySubsequences: false)
        return ([head + (lines.first.map(String.init) ?? "")]
                + lines.dropFirst().map { indent + $0 }).joined(separator: "\n")
    }

    /// A whole run of entries.
    public func string(for entries: [LogEntry]) -> String {
        entries.map { string(for: $0) }.joined(separator: "\n")
    }

    /// Pads or trims to an exact width in display columns, so every column
    /// starts where the one above it did.
    ///
    /// Trimmed from the **front**, because the end of a path or a line number
    /// is the part that identifies it: `…View.swift:412` still tells you
    /// where to look, and `AVeryLongNa…` does not.
    public static func fit(_ text: String, _ width: Int) -> String {
        let occupied = DisplayWidth.of(text)

        if occupied == width { return text }

        if occupied < width {
            return text + String(repeating: " ", count: width - occupied)
        }

        // Keep the TAIL that fits after the leading ellipsis — walked from
        // the back so a wide character is dropped whole, never halved.
        var kept = ""
        var used = 0

        for character in text.reversed() {
            let cost = DisplayWidth.of(character)
            if used + cost > width - 1 { break }
            used += cost
            kept = String(character) + kept
        }

        return "…" + kept + String(repeating: " ", count: max(0, width - 1 - used))
    }

    /// The default: everything, at the standard widths.
    public static let standard = LogLineFormatter()

    /// For a file, where the badge is noise and the timestamp is the point.
    public static let file = LogLineFormatter(showsIcon: false)
}
