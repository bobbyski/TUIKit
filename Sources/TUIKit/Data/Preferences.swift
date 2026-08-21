import Foundation

/// The defaults system — Apple's `UserDefaults` on Apple platforms, a JSON
/// file in `$XDG_CONFIG_HOME` (or `~/.config`) elsewhere — behind one typed,
/// testable API.
///
/// ```swift
/// let prefs = Preferences(suite: "com.example.myapp")
/// prefs.set("turbo", forKey: "theme")
/// let theme = prefs.string(forKey: "theme") ?? "standard"
///
/// let scratch = Preferences.ephemeral()   // tests: nothing touches disk
/// ```
///
/// Values are strings, integers, doubles and booleans; `onChange` fires for
/// every write so a settings form can bind and a status bar can react.
/// Writes go straight through (UserDefaults batches; the file store writes
/// on `synchronize()` and on every `set` unless `writesLazily`).
@MainActor
public final class Preferences {
    /// Where values live.
    public enum Store {
        /// `UserDefaults` (Apple platforms); falls back to the file store
        /// elsewhere.
        case system(suite: String?)

        /// A JSON file.
        case file(URL)

        /// Memory only — for tests and previews.
        case ephemeral
    }

    /// Called with the key after every write or removal.
    public var onChange: (String) -> Void = { _ in }

    /// Whether the file store waits for `synchronize()` instead of writing
    /// on every set. Off by default.
    public var writesLazily = false

    private let store: Store
    private var values: [String: Any] = [:]

    #if canImport(Darwin)
    private let defaults: UserDefaults?
    #endif

    /// Creates preferences in a store.
    ///
    /// - Parameter store: Where values live. Defaults to the system store.
    public init(store: Store = .system(suite: nil)) {
        self.store = store

        #if canImport(Darwin)
        if case .system(let suite) = store {
            defaults = suite.map { UserDefaults(suiteName: $0) ?? .standard } ?? .standard
        } else {
            defaults = nil
        }
        #endif

        if let url = fileURL, let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            values = object
        }
    }

    /// Preferences under a suite name (an app's bundle identifier).
    ///
    /// - Parameter suite: The suite.
    public convenience init(suite: String) {
        self.init(store: .system(suite: suite))
    }

    /// Memory-only preferences for tests.
    public static func ephemeral() -> Preferences {
        Preferences(store: .ephemeral)
    }

    // MARK: - Reading

    /// The string for a key.
    public func string(forKey key: String) -> String? {
        value(forKey: key) as? String
    }

    /// The integer for a key (doubles truncate).
    public func integer(forKey key: String) -> Int? {
        switch value(forKey: key) {
        case let number as Int: return number
        case let number as Double: return Int(number)
        case let text as String: return Int(text)
        default: return nil
        }
    }

    /// The double for a key.
    public func double(forKey key: String) -> Double? {
        switch value(forKey: key) {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let text as String: return Double(text)
        default: return nil
        }
    }

    /// The boolean for a key.
    public func bool(forKey key: String) -> Bool? {
        switch value(forKey: key) {
        case let flag as Bool: return flag
        case let number as Int: return number != 0
        case let text as String: return ["true", "yes", "1"].contains(text.lowercased()) ? true : (["false", "no", "0"].contains(text.lowercased()) ? false : nil)
        default: return nil
        }
    }

    /// Every key with a value.
    public var keys: [String] {
        #if canImport(Darwin)
        if let defaults {
            return defaults.dictionaryRepresentation().keys.sorted()
        }
        #endif

        return values.keys.sorted()
    }

    // MARK: - Writing

    /// Stores a string.
    public func set(_ text: String, forKey key: String) {
        write(text, forKey: key)
    }

    /// Stores an integer.
    public func set(_ number: Int, forKey key: String) {
        write(number, forKey: key)
    }

    /// Stores a double.
    public func set(_ number: Double, forKey key: String) {
        write(number, forKey: key)
    }

    /// Stores a boolean.
    public func set(_ flag: Bool, forKey key: String) {
        write(flag, forKey: key)
    }

    /// Removes a key.
    public func remove(_ key: String) {
        #if canImport(Darwin)
        if let defaults {
            defaults.removeObject(forKey: key)
            onChange(key)
            return
        }
        #endif

        values[key] = nil
        persistIfEager()
        onChange(key)
    }

    /// Flushes the file store (no-op for the others).
    public func synchronize() {
        guard let url = fileURL else {
            return
        }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Plumbing

    private func value(forKey key: String) -> Any? {
        #if canImport(Darwin)
        if let defaults {
            return defaults.object(forKey: key)
        }
        #endif

        return values[key]
    }

    private func write(_ value: Any, forKey key: String) {
        #if canImport(Darwin)
        if let defaults {
            defaults.set(value, forKey: key)
            onChange(key)
            return
        }
        #endif

        values[key] = value
        persistIfEager()
        onChange(key)
    }

    private func persistIfEager() {
        if !writesLazily {
            synchronize()
        }
    }

    // The JSON file for `.file`, or the XDG location for `.system` where
    // there is no UserDefaults; `nil` for ephemeral and UserDefaults.
    private var fileURL: URL? {
        switch store {
        case .file(let url):
            return url

        case .ephemeral:
            return nil

        case .system(let suite):
            #if canImport(Darwin)
            return nil
            #else
            let environment = ProcessInfo.processInfo.environment
            let base = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
            return base.appendingPathComponent(suite ?? "tuikit").appendingPathComponent("preferences.json")
            #endif
        }
    }
}
