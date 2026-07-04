import Testing
@testable import TUIKit

// MARK: - Parsing

@Test func acceleratorParsesTheAmpersandMarker() {
    let file = Accelerator("&File")
    #expect(file.display == "File")
    #expect(file.index == 0)
    #expect(file.key == "f")

    // The marker can sit mid-word, and it lowercases the key.
    let save = Accelerator("S&ave")
    #expect(save.display == "Save")
    #expect(save.index == 1)
    #expect(save.key == "a")

    // `&&` is a literal ampersand; no mnemonic here.
    let rnd = Accelerator("R&&D")
    #expect(rnd.display == "R&D")
    #expect(rnd.index == nil)
    #expect(rnd.key == nil)

    // A plain title has no accelerator; a trailing `&` is dropped.
    #expect(Accelerator("Plain").key == nil)
    #expect(Accelerator("Trailing&").display == "Trailing")
}

@Test func acceleratorMatchesAltPlusItsLetter() {
    let save = Accelerator("&Save")
    #expect(save.matches(KeyInput(key: .character("s"), modifiers: .alt)))
    #expect(save.matches(KeyInput(key: .character("S"), modifiers: .alt)))
    #expect(!save.matches(KeyInput(key: .character("s"))), "bare letter is not the chord")
    #expect(!save.matches(KeyInput(key: .character("x"), modifiers: .alt)))
}

// MARK: - Button

@Test @MainActor func buttonMnemonicActivatesAndPaintsRed() {
    var hits = 0
    let button = Button("&Save") { hits += 1 }
    let window = Window(frame: Rect(x: 0, y: 0, width: 8, height: 1))
    window.theme = .turbo
    button.frame = Rect(x: 0, y: 0, width: 6, height: 1)
    window.addSubview(button)

    // Alt+S activates it from anywhere in the window (the hot-key pass).
    window.route(.key(KeyInput(key: .character("s"), modifiers: .alt)))
    #expect(hits == 1)

    // The 'S' of " Save " (column 1) is painted in the red accelerator color.
    let buffer = SceneRenderer(root: window).render(size: Size(width: 8, height: 1))
    #expect(buffer[Point(x: 1, y: 0)].character == "S")
    #expect(buffer[Point(x: 1, y: 0)].style.foreground == .rgb(red: 255, green: 85, blue: 85))
    #expect(buffer[Point(x: 2, y: 0)].style.foreground != .rgb(red: 255, green: 85, blue: 85), "only the mnemonic is red")
}

// MARK: - Menus

@Test @MainActor func altOpensTheMatchingMenu() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    let bar = MenuBar()
    let file = Menu("&File")
    let edit = Menu("&Edit")
    file.addItem("Open")
    bar.addMenu(file)
    bar.addMenu(edit)
    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    window.addSubview(bar)

    #expect(!bar.isMenuOpen)
    window.route(.key(KeyInput(key: .character("e"), modifiers: .alt)))
    #expect(bar.isMenuOpen, "Alt+E opens the Edit menu")
}

@Test @MainActor func mnemonicLetterActivatesAnOpenMenuItem() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 8))
    let bar = MenuBar()
    let file = Menu("File")

    var log: [String] = []
    file.addItem("&Open") { log.append("open") }
    file.addItem("&Save") { log.append("save") }
    bar.addMenu(file)
    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    window.addSubview(bar)

    window.makeFirstResponder(bar)
    window.route(.key(KeyInput(key: .enter)))    // open File
    #expect(bar.isMenuOpen)

    // A bare 'S' picks Save — the Turbo way inside an open menu.
    window.route(.key(KeyInput(key: .character("s"))))
    #expect(log == ["save"])
    #expect(!bar.isMenuOpen)
}

@Test @MainActor func menuBarMnemonicPaintsRedInTurbo() {
    let window = Window(frame: Rect(x: 0, y: 0, width: 30, height: 2))
    window.theme = .turbo
    let bar = MenuBar()
    bar.addMenu(Menu("&File"))
    bar.frame = Rect(x: 0, y: 0, width: 30, height: 1)
    window.addSubview(bar)

    let buffer = SceneRenderer(root: window).render(size: Size(width: 30, height: 2))
    // " File " → 'F' at column 1, red on the gray header.
    #expect(buffer[Point(x: 1, y: 0)].character == "F")
    #expect(buffer[Point(x: 1, y: 0)].style.foreground == .rgb(red: 255, green: 85, blue: 85))
    #expect(buffer[Point(x: 1, y: 0)].style.background == .rgb(red: 170, green: 170, blue: 170), "keeps the header surface")
}
