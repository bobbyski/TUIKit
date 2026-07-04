import Testing
@testable import TUIKit

// A user-defined compound control, usable like a bundled one.
private struct LabeledField: Composable {
    let title: String
    var placeholder = ""

    var body: some Component {
        HStack(spacing: 1) {
            Label("\(title):").bold()
            TextField(placeholder: placeholder)
        }
    }
}

@Test @MainActor func builderAssemblesAViewTree() {
    var submitted: [String] = []

    let field = TextField(placeholder: "name")
    let root = VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
        Label("Title").bold()
        field.onSubmit { submitted.append($0) }
        Toggle("Wrap")
        Spacer()
    }

    // The builder produced a real VStack with four children.
    #expect(root is VStack)
    #expect(root.subviews.count == 4)
    #expect(root.subviews[0] is Label)
    #expect(root.subviews[1] === field, "typed modifier returns the same control")
    #expect(root.subviews[3] is Spacer)

    // The event wire is a plain closure — no reactivity.
    field.onSubmit("Bobby")
    #expect(submitted == ["Bobby"])
}

@Test @MainActor func builderConditionalsResolveAtBuildTime() {
    func make(showExtra: Bool) -> VStack {
        VStack {
            Label("always")
            if showExtra {
                Label("extra")
            }
            for i in 0..<3 {
                Label("row \(i)")
            }
        }
    }

    #expect(make(showExtra: true).subviews.count == 5)
    #expect(make(showExtra: false).subviews.count == 4)
}

@Test @MainActor func composableIsUsableLikeABundledControl() {
    let form = VStack {
        LabeledField(title: "Name", placeholder: "full name")
        LabeledField(title: "Email")
    }

    #expect(form.subviews.count == 2)
    #expect(form.subviews[0] is HStack, "the compound built its body's container")
    #expect(form.subviews[0].subviews.count == 2, "label + field")
}

@Test @MainActor func structuralModifiersConfigureTheView() {
    let view = Label("x").id("greeting").frame(minWidth: 12).makeView()
    #expect(view.identifier == "greeting")
    #expect(view.minimumSize.width == 12)
}
