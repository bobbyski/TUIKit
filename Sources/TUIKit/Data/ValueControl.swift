import Foundation

/// Errors thrown by the data layer.
public enum ValueError: Error, Equatable {
    /// A value could not be coerced to the control's type.
    case typeMismatch(expected: String, got: String)

    /// No control was found at a dotted path.
    case notFound(path: String)

    /// The addressed view holds no value.
    case notAValueControl(path: String)
}

/// A control whose primitive value can be read and set generically — the
/// foundation of TUIKit's non-reactive data layer (see `Docs/DataBinding.md`).
///
/// `setAnyValue` always uses the control's **silent** setter, so pushing data
/// in never re-fires the control's semantic event — making `load()` and
/// `applyValues(_:)` safe to call repeatedly.
@MainActor
public protocol ValueControl: TUIView {
    /// The control's current primitive value, type-erased.
    func anyValue() -> Any

    /// Sets the control's value from a type-erased value, silently.
    ///
    /// - Parameter value: The new value (light coercion is applied — see the
    ///   `Coerce` helpers).
    /// - Throws: `ValueError.typeMismatch` when the value cannot be coerced.
    func setAnyValue(_ value: Any) throws
}

/// Lenient conversions so JSON-ish dictionaries load: numbers interconvert and
/// anything renders to `String`; everything else is a type mismatch.
enum Coerce {
    static func string(_ value: Any) throws -> String {
        if let s = value as? String { return s }
        if let c = value as? CustomStringConvertible { return c.description }
        throw ValueError.typeMismatch(expected: "String", got: "\(type(of: value))")
    }

    static func int(_ value: Any) throws -> Int {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let i = Int(s) { return i }
        throw ValueError.typeMismatch(expected: "Int", got: "\(type(of: value))")
    }

    static func double(_ value: Any) throws -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s) { return d }
        throw ValueError.typeMismatch(expected: "Double", got: "\(type(of: value))")
    }

    static func bool(_ value: Any) throws -> Bool {
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        throw ValueError.typeMismatch(expected: "Bool", got: "\(type(of: value))")
    }

    /// An optional selection index. `NSNull`/`Optional.none` clear the
    /// selection; otherwise coerce to `Int`.
    static func optionalInt(_ value: Any) throws -> Int? {
        if value is NSNull { return nil }
        if case Optional<Any>.none = value { return nil }
        return try int(value)
    }

    static func exact<T>(_ value: Any, as type: T.Type) throws -> T {
        guard let typed = value as? T else {
            throw ValueError.typeMismatch(expected: "\(T.self)", got: "\(Swift.type(of: value))")
        }
        return typed
    }
}

// MARK: - String controls

extension TextField: ValueControl {
    /// The field's text.
    public func anyValue() -> Any { text }
    /// Sets the text silently, coercing stringly values.
    public func setAnyValue(_ value: Any) throws { setText(try Coerce.string(value)) }
}

extension ComboBox: ValueControl {
    /// The combo box's text.
    public func anyValue() -> Any { text }
    /// Sets the text silently, coercing stringly values.
    public func setAnyValue(_ value: Any) throws { setText(try Coerce.string(value)) }
}

extension SyntaxTextView: ValueControl {
    /// The editor's text.
    public func anyValue() -> Any { text }
    /// Sets the text silently, coercing stringly values.
    public func setAnyValue(_ value: Any) throws { setText(try Coerce.string(value)) }
}

extension TextView: ValueControl {
    /// The text view's text.
    public func anyValue() -> Any { text }
    /// Sets the text silently, coercing stringly values.
    public func setAnyValue(_ value: Any) throws { setText(try Coerce.string(value)) }
}

extension PathControl: ValueControl {
    /// The control's path.
    public func anyValue() -> Any { path }
    /// Sets the path silently, coercing stringly values.
    public func setAnyValue(_ value: Any) throws { setPath(try Coerce.string(value)) }
}

extension Label: ValueControl {
    /// The label's text.
    public func anyValue() -> Any { text }
    /// Sets the text, coercing stringly values.
    public func setAnyValue(_ value: Any) throws { text = try Coerce.string(value) }
}

// MARK: - Bool controls

extension Checkbox: ValueControl {
    /// The checked state.
    public func anyValue() -> Any { isChecked }
    /// Sets the checked state silently, coercing `Bool`-ish values.
    public func setAnyValue(_ value: Any) throws { setChecked(try Coerce.bool(value)) }
}

extension ToggleButton: ValueControl {
    /// The on state.
    public func anyValue() -> Any { isOn }
    /// Sets the on state silently, coercing `Bool`-ish values.
    public func setAnyValue(_ value: Any) throws { setOn(try Coerce.bool(value)) }
}

// MARK: - Int controls

extension Slider: ValueControl {
    /// The slider's value.
    public func anyValue() -> Any { value }
    /// Sets the value silently, coercing numeric values.
    public func setAnyValue(_ value: Any) throws { setValue(try Coerce.int(value)) }
}

extension Stepper: ValueControl {
    /// The stepper's value.
    public func anyValue() -> Any { value }
    /// Sets the value silently, coercing numeric values.
    public func setAnyValue(_ value: Any) throws { setValue(try Coerce.int(value)) }
}

extension LevelIndicator: ValueControl {
    /// The indicator's value.
    public func anyValue() -> Any { value }
    /// Sets the value silently, coercing numeric values.
    public func setAnyValue(_ value: Any) throws { setValue(try Coerce.int(value)) }
}

extension TabView: ValueControl {
    /// The selected tab index.
    public func anyValue() -> Any { selectedIndex }
    /// Selects a tab silently, coercing numeric values.
    public func setAnyValue(_ value: Any) throws { select(try Coerce.int(value)) }
}

// MARK: - Optional-index selection controls

extension SegmentedControl: ValueControl {
    /// The selected segment index, or `nil`.
    public func anyValue() -> Any { selectedIndex as Any }
    /// Selects a segment silently; `nil` leaves the selection unchanged.
    public func setAnyValue(_ value: Any) throws {
        if let index = try Coerce.optionalInt(value) { select(index) }
    }
}

extension RadioGroup: ValueControl {
    /// The selected button index, or `nil`.
    public func anyValue() -> Any { selectedIndex as Any }
    /// Selects a button silently; `nil` leaves the selection unchanged.
    public func setAnyValue(_ value: Any) throws {
        if let index = try Coerce.optionalInt(value) { select(index) }
    }
}

extension PopUpButton: ValueControl {
    /// The selected item index, or `nil`.
    public func anyValue() -> Any { selectedIndex as Any }
    /// Selects an item silently; `nil` clears the selection.
    public func setAnyValue(_ value: Any) throws { select(try Coerce.optionalInt(value)) }
}

extension ListView: ValueControl {
    /// The selected row index, or `nil`.
    public func anyValue() -> Any { selectedIndex as Any }
    /// Selects a row silently; `nil` clears the selection.
    public func setAnyValue(_ value: Any) throws { select(try Coerce.optionalInt(value)) }
}

extension TableView: ValueControl {
    /// The selected row index, or `nil`.
    public func anyValue() -> Any { selectedIndex as Any }
    /// Selects a row silently; `nil` clears the selection.
    public func setAnyValue(_ value: Any) throws { select(try Coerce.optionalInt(value)) }
}

// MARK: - Other typed controls

extension DatePicker: ValueControl {
    /// The picker's date.
    public func anyValue() -> Any { date }
    /// Sets the date silently (an exact `Date` is required).
    public func setAnyValue(_ value: Any) throws { setDate(try Coerce.exact(value, as: Date.self)) }
}

extension ColorPicker: ValueControl {
    /// The picker's color.
    public func anyValue() -> Any { color }
    /// Sets the color silently (an exact `TerminalColor` is required).
    public func setAnyValue(_ value: Any) throws { setColor(try Coerce.exact(value, as: TerminalColor.self)) }
}

extension ProgressIndicator: ValueControl {
    /// The progress value.
    public func anyValue() -> Any { doubleValue }
    /// Sets the progress, coercing numeric values.
    public func setAnyValue(_ value: Any) throws { doubleValue = try Coerce.double(value) }
}
