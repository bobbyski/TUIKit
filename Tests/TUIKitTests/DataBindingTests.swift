import Testing
import Foundation
@testable import TUIKit

// A reference-type model for key-path binding.
@MainActor
private final class Profile {
    var name = ""
    var age = 0
    var subscribed = false
}

// A model using the @Bound macro to project `$` bindings — types are inferred
// from the literal initializers (no explicit annotations needed).
@MainActor
private final class BoundProfile {
    @Bound var name = ""
    @Bound var age = 0
}

// MARK: - Layer 1: ValueControl round-trip

@Test @MainActor func valueControlsRoundTripAndCoerce() throws {
    let field = TextField()
    try field.setAnyValue("hi")
    #expect(field.anyValue() as? String == "hi")
    #expect(field.text == "hi", "setAnyValue used the silent setter")

    let check = Checkbox("x")
    try check.setAnyValue(true)
    #expect(check.anyValue() as? Bool == true)

    let slider = Slider(value: 0, in: 0...100)
    try slider.setAnyValue(30)
    #expect(slider.anyValue() as? Int == 30)
    try slider.setAnyValue(45.0)   // Double → Int coercion
    #expect(slider.anyValue() as? Int == 45)

    #expect(throws: ValueError.self) { try check.setAnyValue(Date()) }
}

@Test @MainActor func setAnyValueDoesNotFireEvents() throws {
    let field = TextField()
    var changes = 0
    field.onChanged = { _ in changes += 1 }

    try field.setAnyValue("silent")
    #expect(field.text == "silent")
    #expect(changes == 0, "setAnyValue must not fire onChanged")
}

// MARK: - Layer 2: dotted-path lookup

@Test @MainActor func dottedPathReadsAndWritesAtDepth() throws {
    let root = VStack()
    let address = VStack().named("address")
    let city = TextField().named("city")
    city.setText("Portland")
    address.addSubview(city)
    root.addSubview(address)

    #expect(try root.value(for: "address.city") as? String == "Portland")

    try root.setValue("Seattle", for: "address.city")
    #expect(city.text == "Seattle")

    #expect(throws: ValueError.self) { _ = try root.value(for: "address.zip") }
}

// MARK: - Layer 3: bulk dict I/O

@Test @MainActor func formValuesDumpAndApply() throws {
    let root = VStack()
    let name = TextField().named("name")
    name.setText("Bobby")
    let sub = Checkbox("Subscribe").named("subscribe")
    sub.setChecked(true)
    root.addSubview(name)
    root.addSubview(sub)

    let values = root.formValues()
    #expect(values["name"] as? String == "Bobby")
    #expect(values["subscribe"] as? Bool == true)

    try root.applyValues(["name": "Sam", "subscribe": false, "unknown.key": 1])
    #expect(name.text == "Sam")
    #expect(sub.isChecked == false, "unknown keys are ignored")
}

// MARK: - Layer 3/5: typed binding + load/save

@Test @MainActor func keyPathBindingLoadsSavesAndIsIdempotent() {
    let model = Profile()
    model.name = "init"
    model.age = 5

    let root = VStack()
    let name = TextField().bind(model, \.name)
    let age = Slider(value: 0, in: 0...100).bind(model, \.age)
    root.addSubview(name)
    root.addSubview(age)

    // load: model → controls
    root.load()
    #expect(name.text == "init")
    #expect(age.value == 5)

    // edit controls, then save: controls → model
    name.setText("changed")
    age.setValue(42)
    root.save()
    #expect(model.name == "changed")
    #expect(model.age == 42)

    // idempotent
    root.save()
    #expect(model.name == "changed")
    root.load()
    root.load()
    #expect(name.text == "changed")
}

@Test @MainActor func closureBindingWorksForValueTypeModelsViaClass() {
    // A struct model wrapped in a class box, bound with explicit closures.
    let model = Profile()
    let toggle = ToggleButton("On")
    toggle.bind(Binding(get: { model.subscribed }, set: { model.subscribed = $0 }))

    model.subscribed = true
    toggle.load()
    #expect(toggle.isOn == true)

    toggle.setOn(false)
    toggle.save()
    #expect(model.subscribed == false)
}

// MARK: - Layer 6: @Bound macro

@Test @MainActor func boundMacroProjectsBindings() {
    let model = BoundProfile()
    model.name = "start"
    model.age = 7

    let root = VStack()
    let field = TextField().bind(model.$name)          // $name from @Bound
    let stepper = Stepper(value: 0, in: 0...100).bind(model.$age)
    root.addSubview(field)
    root.addSubview(stepper)

    root.load()
    #expect(field.text == "start")
    #expect(stepper.value == 7)

    field.setText("edited")
    stepper.setValue(9)
    root.save()
    #expect(model.name == "edited")
    #expect(model.age == 9)
}

// MARK: - Layer 5: live binding

@Test @MainActor func liveBindingPushesOnEditAndKeepsTheHandler() {
    let model = Profile()
    var handlerCalls = 0

    let field = TextField()
    field.onChanged = { _ in handlerCalls += 1 }
    field.bind(model, \.name, live: true)   // wraps the handler set above

    // Simulate an edit firing the (now composed) change event.
    field.onChanged("typed")
    #expect(model.name == "typed", "live push updated the model")
    #expect(handlerCalls == 1, "the user's handler still ran")
}

@MainActor private final class NoteModel { @Bound var notes = "" }

@Test @MainActor func boundSyntaxViewLoadsMultilineText() {
    let model = NoteModel()
    model.notes = "alpha\nbeta\ngamma"

    let editor = SyntaxTextView(language: "text")
    editor.showsLineNumbers = false
    editor.bind(model.$notes)

    let window = Window(frame: Rect(x: 0, y: 0, width: 20, height: 6))
    editor.anchors = .fill()
    window.addSubview(editor)
    window.load()
    window.layoutIfNeeded()

    let lines = SceneRenderer(root: window).render(size: window.frame.size).textLines()
    #expect(lines[0].contains("alpha"))
    #expect(lines[1].contains("beta"))
    #expect(lines[2].contains("gamma"))
}
