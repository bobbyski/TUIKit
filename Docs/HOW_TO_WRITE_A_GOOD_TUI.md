# How to write a good TUI

**A living document.** These are the rules a TUIKit app should follow to look
like an application rather than a debug dump. Rules get added as we find them;
each one exists because something real got it wrong first.

- [Why apps get this wrong](#why-apps-get-this-wrong)
- [Rule 1 — Give every window a theme context](#rule-1--give-every-window-a-theme-context)
- [Rule 2 — Default to Modern Turbo](#rule-2--default-to-modern-turbo)
- [Rule 3 — Chrome is grey, content is not](#rule-3--chrome-is-grey-content-is-not)
- [Rule 4 — Give it a menu bar, with File ▸ Quit at minimum](#rule-4--give-it-a-menu-bar-with-file--quit-at-minimum)
- [Rule 5 — Give it a status bar (usually)](#rule-5--give-it-a-status-bar-usually)
- [The whole thing, in one file](#the-whole-thing-in-one-file)
- [Checklist](#checklist)

---

## Why apps get this wrong

Every TUIKit app that looks wrong looks wrong in the *same way*: uniformly
grey, no visible desktop, content drawn in chrome colours, no bar top or
bottom. It reads as a diagnostic dump of a control library rather than as a
program.

There is one cause, and it is not the app's fault.

**A plain `Window` has no theme context.** `ThemeContext` selects which
palette a view's slots resolve through, and a view with none set inherits its
parent's; unresolved, it falls back to `base`. `base` is the **chrome**
palette — the grey a menu bar and a status strip are meant to be. So a window
that never says what it is gets painted in the colour reserved for the
furniture around it.

Grep the framework and the pattern is plain:

```
Sources/TUIKit/Controls/MenuBar.swift:566        themeContext = .menus
Sources/TUIKit/Controls/PopUpButton.swift:288    themeContext = .menus
Sources/TUIKit/Controls/CompletionList.swift:67  themeContext = .menus
Sources/TUIKit/Controls/Dialog.swift:99          themeContext = .modalWindows
```

Floating chrome pins itself. `Dialog` pins itself. **`Window` pins nothing** —
so the one view an app is guaranteed to create is the one view with no
default. Every shipping app has fixed this by hand, one line per window, and
nothing in the framework or its docs tells you that you must:

```
Demo/TUIKitDemo/Declarative/DemoSource.swift:69   window.themeContext = .contentWindow
Demo/TUIKitDemo/Declarative/ContactBook.swift:30  window.themeContext = .secondaryWindows
Demo/TUIKitDemo/Traditional/FileDialogDemo.swift:24 window.themeContext = .secondaryWindows
```

An author who has read those files copies the line. An author who has not —
which includes every AI writing its first TUIKit app — does not, and gets the
grey app. That is the whole phenomenon.

> **Open question for TUIKit itself.** `Window` defaulting to
> `.contentWindow` would make the common case right and cost the rare case one
> line — the same line the rare case already writes. Until that lands, the
> rule below is mandatory in every app.

---

## Rule 1 — Give every window a theme context

One line per window, set before it is presented.

```swift
let window = Window(frame: Rect(x: 0, y: 0, width: 80, height: 24))
window.themeContext = .contentWindow    // the document surface
```

Pick by **what the window is for**, not by how it looks:

| Context | Use it for | Turbo gives you |
|---|---|---|
| `.contentWindow` | The document. Editors, tables, the thing the app is *about* | Blue ground, yellow text, double frame |
| `.secondaryWindows` | Forms, inspectors, pickers — supporting windows | Grey ground, double frame |
| `.modalWindows` | Dialogs. `Dialog` sets this for you | Grey ground, single frame |
| `.desktop` | The backdrop behind windows | Light blue |
| `.menus` | Dropdowns and pop-ups. The controls set this themselves | Grey, opaque |
| `.accessoryView` | Strips that should *match* the document — **not** chrome | Echoes the content window |

Nothing set → `base` → grey chrome. That is the bug, not a style.

**A window with panes still sets it once.** Context inherits, so a split view
full of children needs one line on the window, not one per child. Set it on a
child only where that child is genuinely a different *kind* of surface — an
inspector strip inside a document window.

---

## Rule 2 — Default to Modern Turbo

```swift
app.applyTheme(.modernTurbo)
```

`Theme.turbo` is the Borland palette. `Theme.modernTurbo` is the same palette
with the button drop-shadow unset, so buttons stay one-row pills like every
other control instead of costing two rows and animating on press.

Prefer `.modernTurbo` unless the app has a reason. The reason to have a
default at all: an unthemed app resolves to whatever `base` happens to be, and
the result is the grey dump above.

Offer the others (`.dark`, `.homebrew`, `.ocean`, `.manPage`, `.pro`, …)
through a Theme menu if the app wants; `Theme.builtIn` is the list.

---

## Rule 3 — Chrome is grey, content is not

This is the rule that makes an app *read* correctly, and it follows from
Rule 1 rather than being separate.

- **Chrome** — menu bar, status bar, toolbars, dropdowns — lives in `base`.
  Grey, in Turbo. Do **not** put it in `.desktop`: that context's background
  is the blue backdrop, and a dropdown wearing it dissolves into the window
  it covers.
- **Content** — the document, its text, its tables — lives in
  `.contentWindow`. Blue, in Turbo.

The contrast between the two is what tells the eye which parts are the
program and which are the thing being worked on. An app painted in one colour
throughout has thrown that away, and no amount of border drawing gets it back.

### The trap: `.accessoryView` is not the chrome context

The name reads like "the context for bars attached to a window". It is not.
It resolves `[accessoryView, contentWindow, base]` — it deliberately **echoes
the document** so a strip can match the surface it belongs to. Put a menu bar
in it and the bar comes out the document's blue, which is the exact problem
Rule 3 is about.

Chrome that must never take the colour of what it covers goes in `.menus`,
which resolves `[menus, base]` — "floating chrome: never the surface being
covered". A menu bar and a status bar are that, whatever their names suggest.

```swift
menuBar.themeContext = .menus     // grey chrome on a blue window
statusBar.themeContext = .menus   // the same
```

Only needed when the bar's *parent* has a context to inherit. A bar on a
plain `Window` that set none already resolves through `base` and comes out
grey — which is why the demo app looks right without these lines, and why an
app that follows Rule 1 needs them.

A toolbar is the instructive case: it sits *on* a content window but is
chrome, so `.contentWindow` gives it its own `toolbar*` slots — grey bar,
blue text — rather than making it more blue. White-on-blue made toolbars
disappear into the page behind them.

---

## Rule 4 — Give it a menu bar, with File ▸ Quit at minimum

An app the user cannot quit without knowing a magic key is not finished.

```swift
let fileMenu = Menu("File")
fileMenu.addItem("Quit", keyEquivalent: KeyInput(key: .character("q"),
                                                 modifiers: .control)) {
    app.stop()
}

let menuBar = MenuBar()
menuBar.addMenu(fileMenu)
// Edge to edge, so the whole row is chrome rather than only the titles' width
// — and so a dropdown near the right edge has a bar to hang from.
menuBar.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, height: 1)
window.addSubview(menuBar)
window.makeFirstResponder(menuBar)
```

**Quit belongs under File.** macOS puts it in the application menu because
macOS has one; a terminal does not, and every full-screen text app since
Turbo Pascal has put it at the foot of File.

**`Ctrl-Q`, not `⌘Q`.** A terminal never sees Command — the emulator keeps
it. Item key equivalents fire from anywhere, so the chord works without the
menu being open.

The bar owns the top row. Whatever lays out the window's content must start
one row lower; a bar drawn over the first row of a document is a bar that
looks like a bug.

---

## Rule 5 — Give it a status bar (usually)

Optional, and most apps should have one. It is where a TUI puts the things a
GUI would put in a toolbar or a title bar: what file is open, what mode you
are in, and — most usefully — **the keys that work right now**.

```swift
let statusBar = StatusBar()
statusBar.addSegment(Label(" MyApp"), minimumWidth: 12)
statusBar.addSegment(Label("^N new · ^O open · ^S save · ^Q quit"), percentage: 60)
statusBar.addSegment(Label("Ln 1:1"), minimumWidth: 10)
statusBar.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
window.addSubview(statusBar)
```

It paints itself in the theme's `header` slot, so it is grey chrome without
being told (Rule 3). `flash(_:for:)` puts a transient message in it — the
right home for "Saved", which does not deserve a dialog.

Leave it out for a genuinely single-purpose full-screen view with no modes and
no shortcuts worth listing. Everything else earns one.

---

## The whole thing, in one file

A complete app that follows every rule above. This is the shape to start
from.

```swift
import TUIKit

@main
struct MyApp {
    @MainActor
    static func main() async throws {
        let app = App(driver: ANSIDriver())

        // Rule 2 — a default theme, before anything is built.
        app.applyTheme(.modernTurbo)

        // Rule 1 — the window says what kind of surface it is. Without this
        // line the whole app is grey chrome.
        let window = Window(frame: Rect(x: 0, y: 0, width: 80, height: 24))
        window.themeContext = .contentWindow
        window.fillsScreen = true

        // Rule 4 — the menu bar owns the top row.
        let fileMenu = Menu("File")
        fileMenu.addItem("Quit", keyEquivalent: KeyInput(key: .character("q"),
                                                         modifiers: .control)) {
            app.stop()
        }
        let menuBar = MenuBar()
        menuBar.addMenu(fileMenu)
        menuBar.anchors = AnchorSet(leading: 0, trailing: 0, top: 0, height: 1)
        window.addSubview(menuBar)

        // Rule 5 — and the status bar owns the bottom one.
        let statusBar = StatusBar()
        statusBar.addSegment(Label(" MyApp"), minimumWidth: 10)
        statusBar.addSegment(Label("^Q quit"), percentage: 60)
        statusBar.anchors = AnchorSet(leading: 0, trailing: 0, bottom: 0, height: 1)
        window.addSubview(statusBar)

        // The content sits between the two bars — never under them.
        let content = StackView(axis: .vertical, spacing: 1)
        content.anchors = AnchorSet(leading: 0, trailing: 0, top: 1, bottom: 1)
        content.addArrangedSubview(Label("Hello from a real terminal app."))
        window.addSubview(content)

        window.makeFirstResponder(menuBar)
        try await app.run(window)
    }
}
```

---

## Checklist

Before calling a TUIKit app done:

- [ ] Every window sets `themeContext`. The document window is
      `.contentWindow`, not the default.
- [ ] `app.applyTheme(.modernTurbo)` (or a deliberate alternative) runs before
      the window is built.
- [ ] Chrome and content are visibly different colours. If the whole screen is
      one grey, Rule 1 was missed.
- [ ] There is a menu bar, and `File ▸ Quit` works — both from the menu and
      from `Ctrl-Q`.
- [ ] There is a status bar, or a stated reason there is not.
- [ ] Content is laid out *between* the bars, not under them.
- [ ] The app restores the terminal on exit **and on crash**. `ANSIDriver.end()`
      is idempotent and must run from a trap, not from the last line of `main`
      — raw mode has to be undone on the runs that fail, which are the runs you
      most want to debug.

---

## See also

- `Docs/Themes.md` — the palette slots and how they resolve
- `Docs/StyleSheets.md` — CSS-style styling over the same model
- `Demo/TUIKitDemo/` — the reference app; `DemoApp.swift` is the menu-bar,
  desktop and status-strip shape
- OmegaCLIDE — the behaviour reference: a real IDE that follows all of this
