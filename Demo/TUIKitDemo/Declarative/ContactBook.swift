import Foundation
import TUIKit

// Contact Book — the flagship example of TUIKit's declarative builder (Phase 12)
// meeting its data-binding layer (Phase 14). Read this file top-to-bottom to see
// how a "SwiftUI-ish" declarative tree coexists with imperative, rebuilt-on-the-
// fly content. The two window factories live in an `extension DemoApp` so each
// demo window gets its own file while still sharing the app's single `App`.
extension DemoApp {

    // A read-only table of every contact. Simpler than the editor below: it is
    // built once and never rebuilt.
    func presentContactTable() {
        // `self.app` is the one shared App. We rebind it to a local `app` so the
        // closures below (onCloseRequest, etc.) capture the value directly
        // instead of capturing `self` — keeps the closures free of `self.`.
        let app = self.app
        let store = ContactStore.shared

        let window = FloatingWindow(
            title: "All Contacts (\(store.people.count))",
            frame: Rect(x: 16, y: 5, width: 72, height: 18)
        )
        // Pin this window to the standard theme so the Theme menu's app-wide
        // theming leaves it alone (a deliberate local override — see App.applyTheme).
        window.theme = .standard
        // The window never closes itself; it asks, and the app decides. Here the
        // app just dismisses it. `[weak window]` avoids the window retaining itself
        // through its own callback.
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        let table = TableView(columns: [
            TableColumn("Name"),
            TableColumn("Born", width: .fixed(12)),
            TableColumn("Address"),
        ])
        // TableView takes rows as arrays of strings (one per column). We map the
        // model into that shape here; the date is formatted for display only.
        table.rows = store.people.map {
            [$0.name, ContactStore.displayFormatter.string(from: $0.birthday), $0.address]
        }

        // `content.setContent { ... }` is the hosting bridge: it runs the
        // declarative builder closure to produce a view tree, then installs that
        // tree as the panel content's single child, fill-anchored to the content
        // bounds. (`window.content` is the area inside the window's border.)
        window.content.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                Label("Saved contacts — reopen after a Save to see changes land").bold()
                table
            }
        }
        window.makeFirstResponder(table)   // arrow keys land on the table, not the window
        app.present(window)
    }

    // The Contact Book editor: a master/detail. The LEFT pane (names + ✚ Add) is
    // built once. The RIGHT pane is *rebuilt from scratch every time you pick a
    // different contact* — this is where the declarative builder turns dynamic,
    // and it's the part most likely to surprise a first-time reader, so it's
    // commented heavily below.
    func makeContactBook(index: Int) -> FloatingWindow {
        let app = self.app
        let store = ContactStore.shared

        let window = FloatingWindow(
            title: "Contact Book \(index)",
            frame: Rect(x: 10 + index * 4, y: 3 + index * 2, width: 68, height: 22)
        )
        window.theme = .standard
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        let list = ListView()

        // The right pane is a *plain* `TUIView`, on purpose. `setContent`
        // fill-anchors whatever tree it builds to this view's bounds. A plain
        // TUIView uses absolute/anchor layout, so it honors that fill anchor and
        // the content stretches to fill the pane. A stack (VStack/HStack) would
        // instead IGNORE the fill anchor and size the built tree to its intrinsic
        // height — which would collapse the flexible notes editor to zero rows.
        // So: host dynamic content in a plain TUIView, put the stack *inside*.
        let detail = TUIView()   // right pane — its children are replaced on each selection

        let status = Label("Select a contact, or ✚ Add a new one.", style: CellStyle(flags: .dim))

        // Rebuilds the list's visible titles from the model. Called after Add and
        // after Save, since either can change what a row should read.
        func refreshList(select selection: Int?) {
            list.items = store.people.map { $0.name.isEmpty ? "(new contact)" : $0.name }
            if let selection { list.select(selection, notify: true) }
        }

        // Builds the entire detail pane for one contact. THIS is the dynamic
        // moment: every selection throws away the old controls and builds fresh
        // ones bound to the newly-selected `person`. Rebuilding (rather than
        // re-pointing existing controls at a new model) keeps the binding wiring
        // trivial — each control is created already bound to its field.
        func showPerson(at personIndex: Int) {
            guard store.people.indices.contains(personIndex) else {
                detail.setContent { Label("No contact selected.", style: CellStyle(flags: .dim)) }
                return
            }

            let person = store.people[personIndex]

            // The notes editor is created *outside* the builder closure so we can
            // keep a reference and bind it. `person.$notes` is the projected
            // binding the `@Bound` macro generates for `var notes` on `Person`;
            // `.bind` wires this control's value two-way to that field. It does
            // NOT copy the value yet — `load()` (below) does the first pull.
            let notes = TextView()
            notes.bind(person.$notes)

            // Build the detail tree declaratively. Controls created *inside* the
            // closure (the TextField/DatePicker) are bound inline the same way.
            detail.setContent {
                VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                    Label("Contact details").bold()

                    // `Form` lays out labeled rows. Each field binds a control to a
                    // `person.$field` projection; the DatePicker uses a shared UTC
                    // calendar so date math is deterministic.
                    Form {
                        Field("Name")    { TextField(placeholder: "full name").bind(person.$name) }
                        Field("Born")    { DatePicker(mode: .date, calendar: ContactStore.calendar).bind(person.$birthday) }
                        Field("Address") { TextField().bind(person.$address) }
                    }

                    Label("Notes").bold()
                    notes   // the bound editor built above drops into the tree here

                    HStack(spacing: 2) {
                        Spacer()   // pushes the buttons to the right edge
                        // Revert = re-pull the model into the controls, discarding
                        // edits. Save = push the controls back into the model.
                        // Both walk `detail`'s whole subtree, so one call reaches
                        // every bound control at once. `[weak detail]` avoids a
                        // retain cycle (the button lives inside `detail`).
                        Button("Revert") { [weak detail] in
                            detail?.load()
                            status.text = "reverted"
                        }
                        Button("Save") { [weak detail] in
                            detail?.save()
                            refreshList(select: list.selectedIndex)   // a renamed contact re-titles its row
                            status.text = "saved — open Table to confirm"
                        }
                    }
                }
            }

            // The controls were just built empty. `load()` pulls the model values
            // into them (model → controls) across the whole subtree. Without this,
            // the freshly-built fields would show blank until the first edit.
            detail.load()
        }

        // The list drives the detail pane: pick a row → rebuild the right side.
        list.onSelectionChanged = { selection in
            if let selection { showPerson(at: selection) }
        }

        // Left pane header: Add a contact, or open the read-only table. Built once
        // (static), so plain declarative code with no rebuild concerns.
        let leftHeader = HStack(spacing: 1, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1)) {
            Button("✚ Add") {
                store.add()
                refreshList(select: store.people.count - 1)   // select the new row → showPerson rebuilds detail
                status.text = "added a contact — fill it in and Save"
            }
            Button("Table") { self.presentContactTable() }
            Spacer()
        }

        // Left column: header, a rule, then the (flexible) list filling the rest.
        let left = VStack(spacing: 0) {
            leftHeader
            Divider(axis: .horizontal)
            list
        }

        // Master/detail split. `left` (a stack) and `detail` (a plain view) are
        // both real views the builder accepts as leaves. SplitView owns their
        // frames, so `left` being a stack is fine here — only `setContent`'s
        // fill-anchoring is picky about stacks, and SplitView doesn't use it.
        let split = SplitView(.horizontal) { left; detail }
        split.minimumFirstLength = 16
        split.minimumSecondLength = 24

        // Window content = the split above a one-line status bar. This IS hosted
        // via setContent, and the root is a VStack — which is allowed as a
        // setContent root because a VStack distributes its *own* fill among its
        // children (giving the flexible split the remaining rows); the pitfall is
        // only nesting a flexible child that the stack sizes to intrinsic. The
        // `detail` pitfall above is different: there the stack would have been the
        // thing setContent anchored.
        window.content.setContent {
            VStack(spacing: 0) {
                split
                status
            }
        }
        split.setDividerPosition(22)   // set after layout exists so it clamps correctly

        refreshList(select: store.people.isEmpty ? nil : 0)   // show the first contact at open
        window.makeFirstResponder(list)   // focus the list, not the divider
        return window
    }
}
