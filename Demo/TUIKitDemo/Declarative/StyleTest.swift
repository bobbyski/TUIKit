import Foundation
import TUIKit

// CSS Demo — a purpose-built window for the stylesheet layer (Docs/StyleSheets.md).
//
// It shows the three ways a CSS rule *selects* controls — by **type**
// (`Button { … }`), by **#id** (`#save { … }`), and by **.class**
// (`.danger { … }`) — plus a "complex" sheet that **combines** them (compound
// selectors like `Button.primary`, `:focused`, comma grouping, and specificity).
//
// A pop-up **menu** swaps between the test stylesheets; "None" clears it
// (`styleSheet = nil`). CSS is a *layer on top of the window's theme*, so you
// watch it apply and lift off over whatever theme is active — pick a theme from
// the Theme menu, then flip through the CSS tests here.
extension DemoApp {
    func makeStyleTest(index: Int) -> FloatingWindow {
        let app = self.app
        let window = FloatingWindow(
            title: "CSS Demo \(index)",
            frame: Rect(x: 12 + index * 3, y: 4 + index * 2, width: 64, height: 26)
        )
        window.themeContext = .secondaryWindows
        window.onCloseRequest = { [weak window] in if let window { app.dismiss(window) } }

        // The demo controls, each tagged so the selectors below have targets:
        //   • `save` carries an identifier AND a class → hit by #save, .primary,
        //     and the compound Button.primary.
        //   • `danger`/`info` carry classes → hit by .danger / .info.
        //   • all Buttons/Labels are hit by the bare type selectors.
        let alpha = Button("Alpha")
        let beta = Button("Beta")
        let save = Button("Save")
        save.identifier = "save"
        save.styleClasses = ["primary"]

        let normal = Label(" normal ")
        let danger = Label(" danger ")
        danger.styleClasses = ["danger"]
        let info = Label(" info ")
        info.styleClasses = ["info"]

        let list = ListView(items: ["one", "two", "three"])
        list.select(0)

        // Read-only viewer showing the stylesheet that's currently applied.
        let activeCSS = SyntaxTextView(language: "css")
        activeCSS.isEditable = false

        let status = Label("Pick a test — CSS layers over the theme.", style: CellStyle(flags: .dim))

        // The test stylesheets. Each is a self-contained CSS "file" (a string
        // here; `StyleSheet(String)` is exactly a .css file's contents).
        let tests: [(name: String, css: String?)] = [
            ("None", nil),

            ("Control (by type)", """
            /* Select every control of a type. */
            Button   { background: #004400; color: brightGreen; bold: true; }
            Label    { color: brightCyan; }
            ListView { selection-background: #aa5500; selection-color: brightWhite; }
            """),

            ("ID (#save)", """
            /* Select one specific control by its identifier. */
            #save { background: #aa0000; color: brightWhite; bold: true; }
            """),

            ("Style (.class)", """
            /* Select controls by style class — any type that carries it. */
            .danger  { background: #aa0000; color: brightWhite; bold: true; }
            .primary { background: #004488; color: brightYellow; bold: true; }
            .info    { color: brightCyan; }
            """),

            ("Complex (combined)", """
            /* Combine type, class, id, :focused, and comma grouping; specificity
               resolves overlaps (id > class > type). */
            Button          { background: #222222; color: white; }
            Button.primary  { background: #004488; color: brightYellow; bold: true; }
            #save           { border-color: brightRed; }
            .danger         { color: brightRed; bold: true; }
            Button:focused, ListView:focused { underline: true; }
            """),
        ]

        let menu = PopUpButton(items: tests.map(\.name), selectedIndex: 0)
        menu.onSelectionChanged = { i in
            let test = tests[i]
            window.content.styleSheet = test.css.map { StyleSheet($0) }   // nil clears it
            activeCSS.setText(test.css ?? "/* None — no stylesheet (styleSheet = nil). */")
            status.text = test.css == nil
                ? "cleared — the window shows its plain theme"
                : "applied \"\(test.name)\" — layered over the theme"
        }

        window.content.setContent {
            VStack(spacing: 1, insets: EdgeInsets(all: 1)) {
                Label("CSS selectors — type · #id · .class · combined").bold()

                HStack(spacing: 2) { alpha; beta; save; Spacer() }   // Buttons (save is #save .primary)
                HStack(spacing: 2) { normal; danger; info; Spacer() }   // Labels (.danger / .info)

                Label("A list — its selection is a common CSS target:").bold()
                list

                Label("Active stylesheet:").bold()
                activeCSS

                HStack(spacing: 2) { Label("Test:"); menu; Spacer() }
                status
            }
        }

        window.makeFirstResponder(menu)
        return window
    }
}
