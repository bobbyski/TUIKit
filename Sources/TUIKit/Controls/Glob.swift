import Foundation

/// Shell-style filename matching for file dialogs and filters.
///
/// `Glob` answers one question — does a file name match a wildcard pattern —
/// for the `FileDialog` filter field and its file-type pop-up. It is a pure,
/// value-free namespace so the matching rules are unit-tested without any
/// view or file system.
///
/// Supported syntax:
///
/// - `*` matches any run of characters (including none).
/// - `?` matches exactly one character.
/// - `{a,b,c}` matches any one of the comma-separated alternatives, each of
///   which may itself contain `*`/`?` (e.g. `*.{txt,md}`).
///
/// Matching is case-insensitive, the convention users expect from a file
/// chooser (`*.TXT` matches `Notes.txt`). An empty pattern — or the bare
/// `*` — matches everything.
///
/// ```swift
/// Glob.matches("Report.txt", pattern: "*.txt")        // true
/// Glob.matches("Report.md",  pattern: "*.{txt,md}")   // true
/// Glob.matchesAny("a.swift", patterns: ["*.h", "*.swift"])   // true
/// ```
public enum Glob {
    /// Whether a name matches any of the patterns (an empty list matches all).
    ///
    /// - Parameters:
    ///   - name: File name to test (no path components).
    ///   - patterns: Wildcard patterns; an empty list matches everything.
    /// - Returns: `true` when `name` matches at least one pattern.
    public static func matchesAny(_ name: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else {
            return true
        }

        return patterns.contains { matches(name, pattern: $0) }
    }

    /// Whether a name matches a single wildcard pattern.
    ///
    /// - Parameters:
    ///   - name: File name to test (no path components).
    ///   - pattern: Wildcard pattern (`*`, `?`, `{a,b}`).
    /// - Returns: `true` when the whole name matches the whole pattern.
    public static func matches(_ name: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty || trimmed == "*" {
            return true
        }

        // A brace group `{a,b}` is any-of; expand it (once, left to right) and
        // match the alternatives, each spliced back into the surrounding text.
        if let group = braceGroup(in: trimmed) {
            return group.alternatives.contains { alternative in
                matches(name, pattern: group.prefix + alternative + group.suffix)
            }
        }

        return wildcard(
            Array(name.lowercased()),
            matches: Array(trimmed.lowercased())
        )
    }

    // MARK: - Internals

    private struct BraceGroup {
        var prefix: String
        var alternatives: [String]
        var suffix: String
    }

    // The first top-level `{…}` group, split into its comma alternatives.
    private static func braceGroup(in pattern: String) -> BraceGroup? {
        guard let open = pattern.firstIndex(of: "{"),
              let close = pattern[open...].firstIndex(of: "}") else {
            return nil
        }

        let inner = pattern[pattern.index(after: open)..<close]

        return BraceGroup(
            prefix: String(pattern[..<open]),
            alternatives: inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init),
            suffix: String(pattern[pattern.index(after: close)...])
        )
    }

    // Classic recursive `*`/`?` matcher over character arrays. `*` consumes
    // greedily but backtracks by trying every split point.
    private static func wildcard(_ name: [Character], matches pattern: [Character]) -> Bool {
        if pattern.isEmpty {
            return name.isEmpty
        }

        switch pattern[0] {
        case "*":
            let rest = Array(pattern.dropFirst())

            // `*` matches zero characters here, or one-plus by dropping a name
            // character and trying again.
            if wildcard(name, matches: rest) {
                return true
            }

            return !name.isEmpty && wildcard(Array(name.dropFirst()), matches: pattern)

        case "?":
            return !name.isEmpty && wildcard(Array(name.dropFirst()), matches: Array(pattern.dropFirst()))

        default:
            guard let first = name.first, first == pattern[0] else {
                return false
            }

            return wildcard(Array(name.dropFirst()), matches: Array(pattern.dropFirst()))
        }
    }
}
