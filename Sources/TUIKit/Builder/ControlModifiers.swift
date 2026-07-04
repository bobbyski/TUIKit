// Typed, chainable setters for the controls, so the builder can wire events
// and tweak config inline: `Button("Save") { save() }.style(.tinted)`. Each
// returns the concrete control (a leaf component), so it keeps composing.

public extension Label {
    /// Adds the bold attribute to the label's text.
    @discardableResult func bold() -> Self { style.flags.insert(.bold); return self }

    /// Adds the dim attribute to the label's text.
    @discardableResult func dim() -> Self { style.flags.insert(.dim); return self }

    /// Sets the text alignment.
    @discardableResult func align(_ alignment: TextAlignment) -> Self { self.alignment = alignment; return self }
}

public extension Button {
    /// Sets the activation handler.
    @discardableResult func onActivate(_ handler: @escaping () -> Void) -> Self { onActivate = handler; return self }

    /// Sets the visual style (tinted vs. bordered).
    @discardableResult func style(_ style: ControlStyle) -> Self { self.style = style; return self }
}

public extension TextField {
    /// Sets the per-keystroke change handler.
    @discardableResult func onChange(_ handler: @escaping (String) -> Void) -> Self { onChanged = handler; return self }

    /// Sets the Return/submit handler.
    @discardableResult func onSubmit(_ handler: @escaping (String) -> Void) -> Self { onSubmit = handler; return self }
}

public extension Checkbox {
    /// Sets the toggle handler.
    @discardableResult func onChange(_ handler: @escaping (Bool) -> Void) -> Self { onChange = handler; return self }
}

/// SwiftUI-familiar spelling of `ToggleButton` for the builder.
public typealias Toggle = ToggleButton

public extension ToggleButton {
    /// Sets the toggle handler.
    @discardableResult func onChange(_ handler: @escaping (Bool) -> Void) -> Self { onChange = handler; return self }
}

public extension SegmentedControl {
    /// Sets the selection handler.
    @discardableResult func onSelectionChanged(_ handler: @escaping (Int) -> Void) -> Self { onSelectionChanged = handler; return self }
}

public extension RadioGroup {
    /// Sets the selection handler.
    @discardableResult func onSelectionChanged(_ handler: @escaping (Int) -> Void) -> Self { onSelectionChanged = handler; return self }
}

public extension Slider {
    /// Sets the value handler.
    @discardableResult func onValueChanged(_ handler: @escaping (Int) -> Void) -> Self { onValueChanged = handler; return self }
}

public extension Stepper {
    /// Sets the value handler.
    @discardableResult func onValueChanged(_ handler: @escaping (Int) -> Void) -> Self { onValueChanged = handler; return self }
}

public extension PopUpButton {
    /// Sets the selection handler.
    @discardableResult func onSelectionChanged(_ handler: @escaping (Int) -> Void) -> Self { onSelectionChanged = handler; return self }

    /// Sets the visual style (tinted vs. bordered).
    @discardableResult func style(_ style: ControlStyle) -> Self { self.style = style; return self }
}

public extension ListView {
    /// Sets the selection handler.
    @discardableResult func onSelectionChanged(_ handler: @escaping (Int?) -> Void) -> Self { onSelectionChanged = handler; return self }

    /// Sets the activation handler.
    @discardableResult func onActivate(_ handler: @escaping (Int) -> Void) -> Self { onActivate = handler; return self }
}
