import Foundation
import Testing
@testable import TUIKit

// Phase 16 Wave B — the medium controls. Headless, like everything else.

@MainActor
private func host(_ view: TUIView, width: Int, height: Int = 1) -> Window {
    let window = Window(frame: Rect(x: 0, y: 0, width: width, height: height))
    view.frame = Rect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    return window
}

@MainActor
private func lines(_ window: Window) -> [String] {
    SceneRenderer(root: window).render(size: window.frame.size).textLines()
}

@MainActor
private func buffer(_ window: Window) -> CellBuffer {
    SceneRenderer(root: window).render(size: window.frame.size)
}

private func key(_ key: Key, _ modifiers: KeyModifiers = []) -> TerminalInput {
    .key(KeyInput(key: key, modifiers: modifiers))
}

// MARK: - Wizard (16.11)

@Test @MainActor func wizardValidatesBranchesAndFinishes() {
    var nameOK = false
    var finished = 0
    var express = false
    let wizard = Wizard(steps: [
        .init(id: "welcome", title: "Welcome", view: Label("hello"),
              next: { express ? "done" : nil }),
        .init(id: "account", title: "Account", view: Label("account"),
              validate: { nameOK ? nil : "Choose a user name to continue." }),
        .init(id: "done", title: "All set", view: Label("summary")),
    ])
    wizard.onFinish = { finished += 1 }
    let window = host(wizard, width: 50, height: 6)

    var text = lines(window)
    #expect(text[0].contains("Welcome") && text[0].contains("step 1 of 3"))
    #expect(text[5].contains("Next"), "the footer shows Next before the last step")

    #expect(wizard.goNext() && wizard.currentStep.id == "account")
    #expect(!wizard.goNext(), "validation blocks")
    text = lines(window)
    #expect(text[5].contains("Choose a user name"))

    nameOK = true
    #expect(wizard.goNext() && wizard.currentStep.id == "done")
    #expect(wizard.isOnFinalStep)
    #expect(lines(window)[5].contains("Finish"))
    #expect(wizard.goNext() && finished == 1, "Finish on the last step finishes")

    #expect(wizard.goBack() && wizard.currentStep.id == "account", "Back walks the trail")
    #expect(wizard.goBack() && wizard.goBack() == false, "and stops at the first step")

    express = true
    #expect(wizard.goNext() && wizard.currentStep.id == "done", "branching skips a step")
    #expect(lines(window)[0].contains("step 2 of 2"))
}

// MARK: - Gauge + LevelIndicator thresholds (16.12)

@Test @MainActor func gaugeBarFillsByFractionAndThresholdsRecolour() {
    let gauge = Gauge(value: 50, in: 0...100)
    gauge.label = "CPU"
    gauge.warningThreshold = 0.7
    gauge.criticalThreshold = 0.9
    gauge.theme = .turbo
    let window = host(gauge, width: 30)
    let theme = Theme.turbo.resolved()

    let row = lines(window)[0]
    #expect(row.hasPrefix("CPU "))
    #expect(row.contains("█") && row.contains("░") && row.hasSuffix("50%"))
    #expect(gauge.fillColor(theme) == theme.chartAccent)

    gauge.setValue(75)
    #expect(gauge.fillColor(theme) == theme.warningAccent)
    gauge.setValue(95)
    #expect(gauge.fillColor(theme) == theme.errorAccent)
}

@Test @MainActor func gaugeRingDrawsSectorsUnderVTGAndABarWithout() {
    let gauge = Gauge(value: 25, in: 0...100, style: .ring)
    gauge.theme = .ambiance   // concrete colours: chrome needs real RGB, not .standard
    gauge.frame = Rect(x: 0, y: 0, width: 16, height: 7)

    let plain = SceneRenderer(root: gauge).render(size: Size(width: 16, height: 7)).textLines()
    #expect(plain[0].contains("█") || plain[0].contains("░"), "no chrome: the bar is the honest form")

    let vector = SceneRenderer(root: gauge)
    vector.chromeEnabled = true
    let text = vector.render(size: Size(width: 16, height: 7)).textLines()
    #expect(text[3].contains("25%"), "the value sits in the ring")
    let ids = vector.chromeCommands.map(\.id)
    #expect(ids.contains { $0.hasSuffix("_track") } && ids.contains { $0.hasSuffix("_fill") } && ids.contains { $0.hasSuffix("_hole") })
}

@Test @MainActor func levelIndicatorThresholdsRecolourTheFill() {
    let level = LevelIndicator(value: 2, maximum: 5)
    level.warningLevel = 3
    level.criticalLevel = 5
    let theme = Theme.turbo.resolved()

    #expect(level.fillColor(theme) == theme.accent)
    level.setValue(3)
    #expect(level.fillColor(theme) == theme.warningAccent)
    level.setValue(5)
    #expect(level.fillColor(theme) == theme.errorAccent)
}

// MARK: - FlowStack (16.17)

@Test @MainActor func flowStackWrapsWhereTheRowRunsOut() {
    let flow = FlowStack(spacing: 1)
    for tag in ["swift", "terminal", "tui", "concurrency", "testing"] {
        flow.addSubview(Label(tag))
    }
    let window = host(flow, width: 20, height: 3)
    let text = lines(window)

    // "swift terminal tui" is 18 wide; "concurrency" would not fit.
    #expect(text[0].hasPrefix("swift terminal tui"))
    #expect(text[1].hasPrefix("concurrency testing"))
    #expect(flow.intrinsicContentSize?.height == 2)

    flow.frame = Rect(x: 0, y: 0, width: 12, height: 3)
    window.frame = Rect(x: 0, y: 0, width: 12, height: 4)
    let narrow = lines(window)
    #expect(narrow[0].hasPrefix("swift") && narrow[1].hasPrefix("terminal tui") && narrow[2].hasPrefix("concurrency"))
}

// MARK: - Form sections (16.18)

@Test @MainActor func formSectionsDrawHeadersAndKeepOneLabelColumn() {
    let form = Form(spacing: 0) {
        Section("Account") {
            Field("Name") { TextField(placeholder: "name") }
            Field("Email") { TextField(placeholder: "email") }
        }
        Section("Look") {
            Field("Theme") { Label("Turbo") }
        }
    }
    let window = host(form, width: 30, height: 5)
    let text = lines(window)

    #expect(text[0].hasPrefix("Account"))
    #expect(text[1].contains(" Name:") && text[2].contains("Email:"))
    #expect(text[3].hasPrefix("Look"))
    #expect(text[4].contains("Theme:"))
    // One label column: every colon sits in the same column.
    let columns = [text[1], text[2], text[4]].map { line in
        line.distance(from: line.startIndex, to: line.firstIndex(of: ":")!)
    }
    #expect(Set(columns).count == 1, "label colons line up across sections: \(columns)")
}

@MainActor
private func click(_ window: Window, x: Int, y: Int = 0) {
    window.route(.mouse(MouseInput(position: Point(x: x, y: y), action: .press, button: .left, modifiers: [])))
    window.route(.mouse(MouseInput(position: Point(x: x, y: y), action: .release, button: .left, modifiers: [])))
}

// MARK: - Matrix (16.13)

@Test @MainActor func matrixRadioAndHighlightSelectByKeysAndClicks() {
    let radio = Matrix(titles: ["Mon", "Tue", "Wed", "Thu"], columns: 2, mode: .radio)
    let window = host(radio, width: 20, height: 2)
    var picks: [Set<Int>] = []
    radio.onSelectionChanged = { picks.append($0) }

    window.makeFirstResponder(radio)
    #expect(lines(window)[0].hasPrefix("[Mon]"), "the cursor cell wears brackets")

    window.route(key(.right))
    window.route(key(.character(" ")))
    #expect(radio.selectedIndex == 1)
    window.route(key(.down))
    window.route(key(.character(" ")))
    #expect(radio.selected == [3], "radio keeps one")
    #expect(picks == [[1], [3]])

    let multi = Matrix(titles: ["a", "b", "c"], columns: 3, mode: .highlight)
    let window2 = host(multi, width: 20, height: 1)
    window2.makeFirstResponder(multi)
    click(window2, x: 0)
    click(window2, x: 8)   // third cell: cells are 3 wide + 1 gap
    #expect(multi.selected == [0, 2])
    click(window2, x: 0)
    #expect(multi.selected == [2], "highlight toggles")
}

// MARK: - Toolbox (16.14)

@Test @MainActor func toolboxSelectsOneToolAndActivatesIt() {
    var activated: [String] = []
    let tools = Toolbox(axis: .vertical, tools: [
        .init(glyph: "↖", caption: "Select") { activated.append("select") },
        .init(glyph: "✎", caption: "Pen") { activated.append("pen") },
        .init(glyph: "▭", caption: "Rect") { activated.append("rect") },
    ])
    let window = host(tools, width: 12, height: 3)
    var picks: [Int] = []
    tools.onSelectionChanged = { picks.append($0) }

    let text = lines(window)
    #expect(text[0].contains("↖ Select") && text[1].contains("✎ Pen"))

    window.makeFirstResponder(tools)
    window.route(key(.down))
    window.route(key(.enter))
    #expect(tools.selectedIndex == 1 && activated == ["pen"])

    click(window, x: 2, y: 2)
    #expect(tools.selectedIndex == 2 && picks == [1, 2])
}

// MARK: - TokenField (16.15)

@Test @MainActor func tokenFieldMintsOnReturnRemovesOnBackspaceAndClick() {
    let field = TokenField(tokens: ["ops"])
    let window = host(field, width: 40)
    var changes: [[String]] = []
    field.onTokensChanged = { changes.append($0) }

    #expect(lines(window)[0].hasPrefix("[ops ×]"))

    window.makeFirstResponder(field)
    for character in "dev" {
        window.route(key(.character(character)))
    }
    window.route(key(.enter))
    #expect(field.tokens == ["ops", "dev"])
    #expect(field.field.text.isEmpty, "Return clears the tail")

    window.route(key(.backspace))   // empty tail → the last token goes
    #expect(field.tokens == ["ops"])

    click(window, x: 5)   // the × of "[ops ×]"
    #expect(field.tokens.isEmpty)
    #expect(changes == [["ops", "dev"], ["ops"], []])
}

// MARK: - CompletionList (16.16)

@Test @MainActor func completionListFollowsTheFieldAndAcceptsWithReturn() {
    let field = TextField()
    let window = host(field, width: 30, height: 8)
    let completions = CompletionList(for: field)
    completions.items = ["turbo", "turbo-dark", "ambiance", "standard"]
    var accepted: [String] = []
    var submitted: [String] = []
    field.onSubmit = { submitted.append($0) }   // set AFTER attach: replaced, the list wraps what was there before
    _ = submitted

    window.makeFirstResponder(field)
    #expect(completions.isHidden, "nothing typed, nothing shown")

    window.route(key(.character("t")))
    #expect(!completions.isHidden && completions.matches == ["turbo", "turbo-dark"])
    #expect(lines(window)[2].contains("▸turbo"), "the list sits under the field (row 1 is its border)")
    #expect(window.firstResponder === field, "the field keeps the focus")

    window.route(key(.down))
    #expect(completions.highlightedIndex == 1)

    completions.onAccept = { accepted.append($0) }
    completions.accept(completions.highlightedIndex)
    #expect(accepted == ["turbo-dark"] && completions.isHidden)

    window.route(key(.character("u")))   // "tu" → turbo, turbo-dark again
    #expect(!completions.isHidden)
    window.route(key(.escape))
    #expect(completions.isHidden)
}


// MARK: - MasterDetail (16.19)

@Test @MainActor func masterDetailTilesWhenWideAndPushesWhenNarrow() {
    let items = [
        SidebarItem(icon: "✉", title: "Inbox", subtitle: "12 unread"),
        SidebarItem(icon: "★", title: "Starred", subtitle: "3 flagged"),
    ]
    let sidebar = MasterDetail(items: items) { index in Label("detail: \(items[index].title)") }
    let window = host(sidebar, width: 80, height: 8)

    var text = lines(window)
    #expect(!sidebar.isCompact)
    #expect(text[0].contains("✉ Inbox") && text[0].contains("detail: Inbox"), "tiled: list beside detail")
    #expect(text[1].contains("12 unread"))

    sidebar.list.select(1, notify: true)
    #expect(lines(window)[0].contains("detail: Starred"))

    // Narrow: the list becomes a navigator root; activating pushes.
    sidebar.frame = Rect(x: 0, y: 0, width: 40, height: 8)
    window.frame = Rect(x: 0, y: 0, width: 40, height: 8)
    text = lines(window)
    #expect(sidebar.isCompact)
    #expect(text[1].contains("Inbox") && !text.joined().contains("detail:"), "compact: list only")

    window.makeFirstResponder(sidebar.list)
    window.route(key(.enter))
    text = lines(window)
    #expect(text[0].contains("◂ Back") && text[0].contains("Starred"))
    #expect(text[1].contains("detail: Starred"))
}

// MARK: - ImageView (16.20)

private let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAABgAAAAQCAIAAACDRijCAAACvUlEQVR4nA3MoQ6FIABAUbrJYpdsM9gd1chmdzNanR/gRrQ6y00Gmlm7hWSnmyh+AO+dDzhCCBJBJsgFhaAS1IJG0Ao6wSCYBLNgEWyCXXAILsEteARe8Ao+QRQIkZKkZCl5SpFSpdQpTUqb0qUMKVPKnLKkbCl7ypFypdwpT4pPeVO+lJj+I0kiySS5pJBUklrSSFpJJxkkk2SWLJJNsksOySW5JY/ES17JJ4nyH5UkJVlJXlKUVCV1SVPSlnQlQ8lUMpcsJVvJXnKUXCV3yVPiS96SrySW/0iRKDJFrigUlaJWNIpW0SkGxaSYFYtiU+yKQ3EpbsWj8IpX8Smi+keaRJNpck2hqTS1ptG0mk4zaCbNrFk0m2bXHJpLc2sejde8mk8T9T/qSXqynryn6Kl66p6mp+3peoaeqWfuWXq2nr3n6Ll67p6nx/e8PV9P7P/RSDKSjeQjxUg1Uo80I+1INzKMTCPzyDKyjewjx8g1co88I37kHflG4viPDIkhM+SGwlAZakNjaA2dYTBMhtmwGDbDbjgMl+E2PAZveA2fIZp/tJKsZCv5SrFSrdQrzUq70q0MK9PKvLKsbCv7yrFyrdwrz4pfeVe+lbj+I0tiySy5pbBUltrSWFpLZxksk2W2LJbNslsOy2W5LY/FW17LZ4n2H50kJ9lJflKcVCf1SXPSnnQnw8l0Mp8sJ9vJfnKcXCf3yXPiT96T7ySe/8iRODJH7igclaN2NI7W0TkGx+SYHYtjc+yOw3E5bsfj8I7X8Tmi+0eexJN5ck/hqTy1p/G0ns4zeCbP7Fk8m2f3HJ7Lc3sej/e8ns8T/T8KJIEskAeKQBWoA02gDXSBITAF5sAS2AJ74AhcgTvwBHzgDXyBGP5RJIlkkTxSRKpIHWkibaSLDJEpMkeWyBbZI0fkityRJ+Ijb+SLxMgPxrJt7yOvB+kAAAAASUVORK5CYII=")!

@Test @MainActor func imageViewReadsTheHeaderShowsACardAndDrawsPixelsUnderVTG() {
    let image = ImageView(data: tinyPNG, caption: "gradient.png")
    #expect(image.format == .png)
    #expect(image.pixelSize?.width == 24 && image.pixelSize?.height == 16)
    #expect(image.detailLine.hasPrefix("24×16 · PNG"))

    let window = host(image, width: 30, height: 4)
    let text = lines(window)
    #expect(text[1].contains("gradient.png") && text[2].contains("24×16"), "cells: the card")
    #expect(image.contextMenu != nil, "with its Open / Copy / Paste menu")

    let vector = SceneRenderer(root: image)
    vector.chromeEnabled = true
    _ = vector.render(size: Size(width: 30, height: 4))
    #expect(vector.chromeCommands.contains { $0.id.hasSuffix("_pixels") }, "VTG: the pixels")

    #expect(ImageView.detectFormat(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
    #expect(ImageView.detectFormat(Data("hello".utf8)) == nil)
}

// MARK: - Scroller (16.21)

@Test @MainActor func scrollerDrawsAThumbAndReportsOffsets() {
    let bar = Scroller(axis: .vertical, span: ScrollSpan(offset: 0, viewport: 10, content: 50))
    let window = host(bar, width: 1, height: 10)
    var offsets: [Int] = []
    bar.onScroll = { offsets.append($0) }

    let text = lines(window)
    #expect(text[0] == "▴" && text[9] == "▾", "arrows at the ends")

    click(window, x: 0, y: 9)   // the down arrow
    #expect(offsets.last == 1)

    window.route(.mouse(MouseInput(position: Point(x: 0, y: 5), action: .scrollDown, button: .none, modifiers: [])))
    #expect(offsets.last == 2)

    bar.setOffset(999)
    #expect(bar.span.offset == 40, "clamped to content - viewport")
}

// MARK: - Preferences (16.22)

@Test @MainActor func ephemeralPreferencesRoundTripTypesAndReportChanges() {
    let prefs = Preferences.ephemeral()
    var changed: [String] = []
    prefs.onChange = { changed.append($0) }

    prefs.set("turbo", forKey: "theme")
    prefs.set(42, forKey: "answer")
    prefs.set(0.5, forKey: "ratio")
    prefs.set(true, forKey: "wraps")

    #expect(prefs.string(forKey: "theme") == "turbo")
    #expect(prefs.integer(forKey: "answer") == 42 && prefs.double(forKey: "answer") == 42)
    #expect(prefs.double(forKey: "ratio") == 0.5)
    #expect(prefs.bool(forKey: "wraps") == true)
    #expect(prefs.string(forKey: "missing") == nil)
    #expect(prefs.keys == ["answer", "ratio", "theme", "wraps"])

    prefs.remove("answer")
    #expect(prefs.integer(forKey: "answer") == nil)
    #expect(changed == ["theme", "answer", "ratio", "wraps", "answer"])
}

@Test @MainActor func filePreferencesPersistAsJSON() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tuikit-prefs-\(UUID().uuidString)")
        .appendingPathComponent("preferences.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let first = Preferences(store: .file(url))
    first.set("ambiance", forKey: "theme")
    first.set(3, forKey: "tabs")

    let second = Preferences(store: .file(url))
    #expect(second.string(forKey: "theme") == "ambiance" && second.integer(forKey: "tabs") == 3)
}

// MARK: - CollectionView (16.23)

@Test @MainActor func collectionViewLaysOutSectionsAndWalksTheSelection() {
    let collection = CollectionView(sections: [
        .init(title: "Recent", items: ["a", "b", "c", "d", "e"]),
        .init(title: "Shared", items: ["x", "y"]),
    ]) { Label($0) }
    collection.itemWidth = 10
    let window = host(collection, width: 30, height: 6)   // three columns
    var picks: [CollectionView.IndexPath?] = []
    var activated: [CollectionView.IndexPath] = []
    collection.onSelectionChanged = { picks.append($0) }
    collection.onActivate = { activated.append($0) }

    let text = lines(window)
    #expect(text[0].hasPrefix("Recent"))
    #expect(text[1].contains("▸ a") && text[1].contains("b") && text[1].contains("c"), "first row, first item selected")
    #expect(text[2].contains("d") && text[2].contains("e"))
    #expect(text[3].hasPrefix("Shared") && text[4].contains("x"))
    #expect(collection.intrinsicContentSize?.height == 5)

    window.makeFirstResponder(collection)
    window.route(key(.right))
    window.route(key(.down))   // b → e (row below, same column)
    #expect(collection.selection == .init(section: 0, item: 4))
    window.route(key(.down))   // into Shared, column 1 → y
    #expect(collection.selection == .init(section: 1, item: 1))
    window.route(key(.enter))
    #expect(activated == [.init(section: 1, item: 1)])

    click(window, x: 22, y: 1)   // third column, first row → c
    #expect(collection.selection == .init(section: 0, item: 2))
    #expect(picks.count == 4)
}

// MARK: - MarkdownView edit mode + MarkdownHighlighter (16.24)

@Test func markdownHighlighterSeesStructure() {
    var state = HighlightState.initial
    let lexer = MarkdownHighlighter()

    #expect(lexer.highlight(line: "# Title", state: &state).first?.kind == .keyword)
    let bullet = lexer.highlight(line: "- item with `code` and **bold**", state: &state)
    #expect(bullet.map(\.kind) == [.tag, .string, .attributeName])
    let link = lexer.highlight(line: "see [docs](https://x)", state: &state)
    #expect(link.map(\.kind) == [.entity, .regex])

    _ = lexer.highlight(line: "```swift", state: &state)
    #expect(state.rawValue == 1, "inside a fence")
    #expect(lexer.highlight(line: "let x = 1", state: &state).first?.kind == .string)
    _ = lexer.highlight(line: "```", state: &state)
    #expect(state.rawValue == 0)
    #expect(SyntaxHighlighters.builtIn(for: "md") is MarkdownHighlighter)
}

@Test @MainActor func markdownViewFlipsToASourceEditorAndBack() {
    let view = MarkdownView(markdown: "# Hello\n\nsome *text*")
    let window = host(view, width: 30, height: 6)
    var sources: [String] = []
    view.onSourceChanged = { sources.append($0) }

    #expect(lines(window)[0].contains("Hello"), "rendered: the heading text")
    #expect(view.editor == nil)

    view.isEditing = true
    #expect(lines(window).joined().contains("# Hello"), "editing: the raw source shows")
    #expect(window.firstResponder === view.editor, "the editor takes the focus")

    window.route(key(.end))
    window.route(key(.character("!")))
    #expect(view.markdown.hasPrefix("# Hello!"))
    #expect(sources.last?.hasPrefix("# Hello!") == true)

    view.toggleEditing()
    #expect(!view.isEditing && lines(window)[0].contains("Hello!"), "back to rendering, with the edit")
}

// MARK: - DocumentController (16.25)

@Test @MainActor func documentControllerTracksDirtyTitleSavesAndOpens() throws {
    let app = App(driver: HeadlessDriver(size: Size(width: 40, height: 10)))
    var content = "hello"
    var titles: [String] = []
    let document = DocumentController(app: app,
        read: { data in content = String(decoding: data, as: UTF8.self) },
        write: { Data(content.utf8) })
    document.onTitleChanged = { titles.append($0) }
    document.recentsStore = Preferences.ephemeral()

    #expect(document.title == "Untitled")
    document.markDirty()
    #expect(document.title == "Untitled •" && document.isDirty)

    let file = FileManager.default.temporaryDirectory.appendingPathComponent("tuikit-doc-\(UUID().uuidString).txt").path
    defer { try? FileManager.default.removeItem(atPath: file) }

    // No path yet: save() would present Save As; open(_:) and a direct
    // write path are the headless-provable pieces.
    #expect(document.open("/definitely/not/here.txt") == false)

    try Data("from disk".utf8).write(to: URL(fileURLWithPath: file))
    #expect(document.open(file))
    #expect(content == "from disk" && !document.isDirty)
    #expect(document.title == (file as NSString).lastPathComponent)
    #expect(document.recents == [file])
    #expect(document.recentsStore?.string(forKey: "recentDocuments") == file)

    content = "edited"
    document.markDirty()
    document.save()
    #expect(!document.isDirty && String(decoding: FileManager.default.contents(atPath: file)!, as: UTF8.self) == "edited")
    #expect(titles.last == (file as NSString).lastPathComponent)

    var closed = 0
    document.close { closed += 1 }
    #expect(closed == 1, "clean: closes straight through")
}

// MARK: - PreferencesDialog (16.29)

@Test @MainActor func preferencesDialogToolbarStyleSwitchesPages() {
    let dialog = PreferencesDialog(style: .toolbar)
    let general = Label("general page body")
    let editor = Label("editor page body")
    dialog.addPage("General", icon: "⚙", content: general)
    dialog.addPage("Editor", icon: "✎", content: editor)
    dialog.addButton("&Done", isDefault: true)
    var changes: [Int] = []
    dialog.onPageChanged = { changes.append($0) }

    dialog.frame = Rect(x: 0, y: 0, width: 44, height: 12)
    var text = SceneRenderer(root: dialog).render(size: Size(width: 44, height: 12)).textLines()

    #expect(text.joined().contains("General") && text.joined().contains("Editor"), "the strip names both pages")
    #expect(text.joined().contains("general page body") && !text.joined().contains("editor page body"))

    dialog.select(1, notify: true)
    text = SceneRenderer(root: dialog).render(size: Size(width: 44, height: 12)).textLines()
    #expect(text.joined().contains("editor page body") && !text.joined().contains("general page body"))
    #expect(changes == [1])
    #expect(dialog.preferredSize.width >= 24 && dialog.preferredSize.height >= 8, "room for strip, page, buttons")
}

@Test @MainActor func preferencesDialogSplitStyleListsPagesBesideThem() {
    let dialog = PreferencesDialog(style: .split)
    dialog.addPage("General", content: Label("the general body"))
    dialog.addPage("Network", content: Label("the network body"))

    dialog.frame = Rect(x: 0, y: 0, width: 50, height: 10)
    let text = SceneRenderer(root: dialog).render(size: Size(width: 50, height: 10)).textLines()

    #expect(text.joined().contains("General") && text.joined().contains("Network"), "the list names the pages")
    #expect(text.joined().contains("the general body") && !text.joined().contains("the network body"))

    dialog.select(1)
    let after = SceneRenderer(root: dialog).render(size: Size(width: 50, height: 10)).textLines()
    #expect(after.joined().contains("the network body"))
}

// MARK: - ImageView placement (2026-08-22: a square logo came out as a tall strip)

@Test @MainActor func aSquarePictureTakesTwiceAsManyColumnsAsRows() {
    // A PNG header is enough: signature, then IHDR with a 1024x1024 size.
    var header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
    header += [0, 0, 4, 0, 0, 0, 4, 0, 8, 6, 0, 0, 0]
    let view = ImageView(data: Data(header), caption: "logo")
    #expect(view.pixelSize?.width == 1024)

    // 80 columns by 23 rows: height-bound, so 23 rows tall and — cells
    // being about 2:1 — 46 columns wide, centred.
    let placed = view.placement(in: ChromeRect(x: 0, y: 0, width: 80, height: 23))
    #expect(placed.height == 23)
    #expect(placed.width == 46)
    #expect(placed.x == 17)

    // Width-bound: 20 columns by 40 rows gives 20 wide, 10 tall.
    let narrow = view.placement(in: ChromeRect(x: 0, y: 0, width: 20, height: 40))
    #expect(narrow.width == 20)
    #expect(narrow.height == 10)
    #expect(narrow.y == 15)
}
