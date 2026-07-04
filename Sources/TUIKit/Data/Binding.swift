import Foundation

/// A non-reactive two-way connection to a value: read it, write it. No
/// observation — it is pulled/pushed at explicit moments (`load()`/`save()`)
/// or, opt-in, on edit.
public struct Binding<Value> {
    /// Reads the current value.
    public let get: () -> Value

    /// Writes a new value.
    public let set: (Value) -> Void

    /// Creates a binding from get/set closures (use for value-type models).
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}

/// `$model.property` bindings for a reference-type model, with no macro.
///
/// ```swift
/// let form = ProfileForm()          // a class
/// let $form = Bindings(form)
/// field.bind($form.name)            // Binding<String> to form.name
/// ```
@dynamicMemberLookup
public struct Bindings<Root: AnyObject> {
    private let root: Root

    /// Wraps a reference-type model.
    public init(_ root: Root) {
        self.root = root
    }

    /// A binding to one writable property of the model.
    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Root, Value>) -> Binding<Value> {
        let root = self.root
        return Binding(get: { root[keyPath: keyPath] }, set: { root[keyPath: keyPath] = $0 })
    }
}

/// A control's installed binding, type-erased so `load()`/`save()` can walk the
/// tree. `pull` sends model→control (silently); `push` sends control→model.
struct FieldBinding {
    let pull: () -> Void
    let push: () -> Void
}

/// A control whose value can be bound to a model.
@MainActor
public protocol Bindable: TUIView {
    /// The bound value type.
    associatedtype Value

    /// Binds the control's value to a `Binding`, optionally pushing on edit.
    @discardableResult
    func bind(_ binding: Binding<Value>, live: Bool) -> Self
}

public extension Bindable {
    /// Binds without live push (the default; sync via `load()`/`save()`).
    @discardableResult
    func bind(_ binding: Binding<Value>) -> Self {
        bind(binding, live: false)
    }

    /// Binds directly to a writable key path of a reference-type model.
    @discardableResult
    func bind<Root: AnyObject>(
        _ root: Root,
        _ keyPath: ReferenceWritableKeyPath<Root, Value>,
        live: Bool = false
    ) -> Self {
        bind(Binding(get: { root[keyPath: keyPath] }, set: { root[keyPath: keyPath] = $0 }), live: live)
    }
}

extension TUIView {
    // Stores the type-erased binding for tree-wide sync.
    func setFieldBinding(pull: @escaping () -> Void, push: @escaping () -> Void) {
        fieldBinding = FieldBinding(pull: pull, push: push)
    }
}

public extension TUIView {
    /// Pulls every binding in the subtree: model → controls (silently).
    /// Idempotent — safe to call repeatedly.
    func load() {
        forEachBinding { $0.pull() }
    }

    /// Pushes every binding in the subtree: controls → model. Idempotent.
    func save() {
        forEachBinding { $0.push() }
    }

    private func forEachBinding(_ body: (FieldBinding) -> Void) {
        if let fieldBinding {
            body(fieldBinding)
        }

        for child in subviews {
            child.forEachBinding(body)
        }
    }
}

// MARK: - Per-control bindings
//
// Each control conforms to `Bindable`, wiring: pull (silent setter), push
// (read value), and — for `live` — a wrap of its existing change event so the
// user's handler still runs.

extension TextField: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<String>, live: Bool) -> TextField {
        setFieldBinding(pull: { [weak self] in self?.setText(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.text) } })
        if live { let prev = onChanged; onChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension ComboBox: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<String>, live: Bool) -> ComboBox {
        setFieldBinding(pull: { [weak self] in self?.setText(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.text) } })
        if live { let prev = onChanged; onChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension SyntaxTextView: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<String>, live: Bool) -> SyntaxTextView {
        setFieldBinding(pull: { [weak self] in self?.setText(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.text) } })
        if live { let prev = onChanged; onChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension PathControl: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<String>, live: Bool) -> PathControl {
        setFieldBinding(pull: { [weak self] in self?.setPath(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.path) } })
        if live { let prev = onPathSelected; onPathSelected = { binding.set($0); prev($0) } }
        return self
    }
}

extension Label: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<String>, live: Bool) -> Label {
        setFieldBinding(pull: { [weak self] in self?.text = binding.get() },
                        push: { [weak self] in self.map { binding.set($0.text) } })
        return self   // display-only: no live event
    }
}

extension Checkbox: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Bool>, live: Bool) -> Checkbox {
        setFieldBinding(pull: { [weak self] in self?.setChecked(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.isChecked) } })
        if live { let prev = onChange; onChange = { binding.set($0); prev($0) } }
        return self
    }
}

extension ToggleButton: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Bool>, live: Bool) -> ToggleButton {
        setFieldBinding(pull: { [weak self] in self?.setOn(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.isOn) } })
        if live { let prev = onChange; onChange = { binding.set($0); prev($0) } }
        return self
    }
}

extension Slider: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int>, live: Bool) -> Slider {
        setFieldBinding(pull: { [weak self] in self?.setValue(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.value) } })
        if live { let prev = onValueChanged; onValueChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension Stepper: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int>, live: Bool) -> Stepper {
        setFieldBinding(pull: { [weak self] in self?.setValue(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.value) } })
        if live { let prev = onValueChanged; onValueChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension LevelIndicator: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int>, live: Bool) -> LevelIndicator {
        setFieldBinding(pull: { [weak self] in self?.setValue(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.value) } })
        if live { let prev = onValueChanged; onValueChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension TabView: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int>, live: Bool) -> TabView {
        setFieldBinding(pull: { [weak self] in self?.select(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.selectedIndex) } })
        if live { let prev = onSelectionChanged; onSelectionChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension SegmentedControl: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int?>, live: Bool) -> SegmentedControl {
        setFieldBinding(pull: { [weak self] in binding.get().map { self?.select($0) } },
                        push: { [weak self] in self.map { binding.set($0.selectedIndex) } })
        if live { let prev = onSelectionChanged; onSelectionChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension RadioGroup: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int?>, live: Bool) -> RadioGroup {
        setFieldBinding(pull: { [weak self] in binding.get().map { self?.select($0) } },
                        push: { [weak self] in self.map { binding.set($0.selectedIndex) } })
        if live { let prev = onSelectionChanged; onSelectionChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension PopUpButton: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int?>, live: Bool) -> PopUpButton {
        setFieldBinding(pull: { [weak self] in self?.select(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.selectedIndex) } })
        if live { let prev = onSelectionChanged; onSelectionChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension ListView: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int?>, live: Bool) -> ListView {
        setFieldBinding(pull: { [weak self] in self?.select(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.selectedIndex) } })
        if live { let prev = onSelectionChanged; onSelectionChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension TableView: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Int?>, live: Bool) -> TableView {
        setFieldBinding(pull: { [weak self] in self?.select(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.selectedIndex) } })
        if live { let prev = onSelectionChanged; onSelectionChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension DatePicker: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<Date>, live: Bool) -> DatePicker {
        setFieldBinding(pull: { [weak self] in self?.setDate(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.date) } })
        if live { let prev = onDateChanged; onDateChanged = { binding.set($0); prev($0) } }
        return self
    }
}

extension ColorPicker: Bindable {
    @discardableResult
    public func bind(_ binding: Binding<TerminalColor>, live: Bool) -> ColorPicker {
        setFieldBinding(pull: { [weak self] in self?.setColor(binding.get()) },
                        push: { [weak self] in self.map { binding.set($0.color) } })
        if live { let prev = onColorChanged; onColorChanged = { binding.set($0); prev($0) } }
        return self
    }
}
