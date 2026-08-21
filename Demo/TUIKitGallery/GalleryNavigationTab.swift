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

    // Accordion: exclusive sections.
    let accordion = Accordion(mode: .exclusive)
    accordion.addSection("General", content: Label("general settings live here"), isExpanded: true)
    accordion.addSection("Appearance", content: Label("theme and colours"))
    accordion.addSection("Advanced", content: Label("the dangerous switches"))

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
    root.addSubview(group("Accordion — exclusive; Space on a header", [accordion]))

    return root
}
