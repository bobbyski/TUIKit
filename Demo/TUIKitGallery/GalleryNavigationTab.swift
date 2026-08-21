import Foundation
import TUIKit

// The Navigation folder tab: the Phase 16 structural pieces — pages,
// accordion sections, a layout that degrades, and (16.1) the navigator.

@MainActor
func makeNavigationTab() -> TUIView {
    let root = VStack(spacing: 0, insets: EdgeInsets(top: 0, left: 1, bottom: 0, right: 1))

    // ViewThatFits: the same intent at three sizes. The narrow group is
    // capped, so the same control picks a shorter candidate there.
    func saveChoices() -> ViewThatFits {
        ViewThatFits(axis: .horizontal, candidates: [
            Button("Save the document to disk") {},
            Button("Save document") {},
            Button("Save") {},
        ])
    }
    let narrow = group("ViewThatFits — narrow", [saveChoices()])
    narrow.maximumSize = Size(width: 22, height: Int.max)

    // PageView: three pages, dots and arrows.
    let pageLabel = Label("page 1 of 3 — ←/→ turn, or click the dots")
    let pages = PageView(pages: [
        Label("Welcome — the first page."),
        Label("Features — the second page."),
        Label("Finish — the last page."),
    ])
    pages.onPageChanged = { pageLabel.text = "page \($0 + 1) of 3 — ←/→ turn, or click the dots" }

    // Accordion: two sections with more options than fit, two with a line
    // or two. The sections do NOT scroll themselves — the accordion sits in
    // a ScrollView and is scrolled as a whole, its open section at its
    // natural height.
    func options(_ prefix: String, count: Int) -> TUIView {
        let list = VStack(spacing: 0)
        for index in 1...count {
            list.addSubview(pinnedHeight(Checkbox("\(prefix) option \(index)"), 1))
        }
        return list
    }
    let accordion = Accordion(mode: .exclusive)
    accordion.addSection("General — 30 options", content: options("General", count: 30), isExpanded: true)
    accordion.addSection("Appearance — 24 options", content: options("Appearance", count: 24))
    accordion.addSection("Shortcuts — one item", content: Label("⌘K opens the command palette"))
    let about = VStack(spacing: 0)
    about.addSubview(pinnedHeight(Label("TUIKit Gallery"), 1))
    about.addSubview(pinnedHeight(Label("the control showroom"), 1))
    accordion.addSection("About — two items", content: about)
    let accordionScroll = ScrollView(document: accordion)
    accordionScroll.fitsDocumentWidth = true

    // Navigator: a drill-down menu two levels deep. Esc or ◂ Back returns.
    let menu = VStack(spacing: 0)
    let navigator = Navigator(root: menu, title: "Settings")
    let depthLabel = Label("level 1 — Enter a row to drill in")
    navigator.onDepthChanged = { depthLabel.text = "level \($0) — Esc, Backspace or ◂ Back returns" }

    for (title, body) in [("Appearance", "theme, colours, fonts"), ("Network", "proxies and timeouts")] {
        menu.addSubview(pinnedHeight(Button("\(title) ›") { [weak navigator] in
            let page = VStack(spacing: 0)
            page.addSubview(pinnedHeight(Label(body), 1))
            page.addSubview(pinnedHeight(Button("Advanced \(title) ›") { [weak navigator] in
                navigator?.push(Label("the deep end of \(title)"), title: "Advanced \(title)")
            }, 1))
            navigator?.push(page, title: title)
        }, 1))
    }

    root.addSubview(pinnedHeight(row([group("ViewThatFits — wide", [saveChoices()]), narrow]), 4))
    root.addSubview(pinnedHeight(row([
        group("PageView", [pages, pageLabel]),
        group("Navigator — drill in, Esc back", [navigator, depthLabel]),
    ]), 7))
    root.addSubview(group("Accordion — exclusive; Space on a header; the whole accordion scrolls", [accordionScroll]))

    return root
}
