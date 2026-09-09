import Foundation
import Testing
@testable import TUIKit

// `effectiveTheme` walks the ancestor chain and cascades every stylesheet on
// it, per view, per frame. It is cached behind a global epoch — and a cached
// theme going stale is a bug this framework has shipped before, so these are
// the tests that matter more than the speed.

@Test @MainActor func aViewsOwnThemeChangeIsSeenImmediately() {
    let view = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    let before = view.effectiveTheme

    view.theme = .turbo
    #expect(view.effectiveTheme != before, "its own theme is the most obvious input")
}

@Test @MainActor func anAncestorsThemeChangeReachesADescendant() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let child = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    root.addSubview(child)

    let before = child.effectiveTheme
    root.theme = .turbo
    #expect(child.effectiveTheme != before,
            "the cache is global, so an ancestor's change clears the descendant's too")
}

@Test @MainActor func aClassChangeRe_resolvesTheCascade() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    root.styleSheet = StyleSheet(".loud { foreground: red; }")
    let child = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    root.addSubview(child)

    let plain = child.effectiveTheme
    child.styleClasses = ["loud"]
    #expect(child.effectiveTheme != plain, "the rule matches now and did not before")

    child.styleClasses = []
    #expect(child.effectiveTheme == plain, "and stops matching again")
}

@Test @MainActor func takingFocusRe_resolvesAFocusRule() {
    let root = TUIView(frame: Rect(x: 0, y: 0, width: 20, height: 4))
    root.styleSheet = StyleSheet("TextField:focused { foreground: red; }")
    let field = TextField()
    field.frame = Rect(x: 0, y: 0, width: 10, height: 1)
    root.addSubview(field)

    let unfocused = field.effectiveTheme
    // Set directly rather than through the window: what is under test is that
    // the flag's own didSet clears the cache, not the responder plumbing.
    field.isFirstResponder = true
    #expect(field.effectiveTheme != unfocused,
            ":focused is a cascade input, so focus has to clear the cache")

    field.isFirstResponder = false
    #expect(field.effectiveTheme == unfocused, "and losing it puts the theme back")
}

@Test @MainActor func movingAViewToANewParentRe_resolves() {
    let plainRoot = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    let themedRoot = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 4))
    themedRoot.theme = .turbo

    let child = TUIView(frame: Rect(x: 0, y: 0, width: 10, height: 1))
    plainRoot.addSubview(child)
    let underPlain = child.effectiveTheme

    child.removeFromSuperview()
    themedRoot.addSubview(child)
    #expect(child.effectiveTheme != underPlain,
            "the chain it walks is an input as much as the properties on it")
}
