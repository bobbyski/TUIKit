# Building with TUIKit

A six-chapter tutorial for readers who have never used TUIKit. The running
example is a small To-Do app that grows chapter over chapter: a greeting
becomes a shell, the shell gains a working form, the form gains keyboard
plumbing, the whole thing goes under test — and an appendix rebuilds it by
hand for readers who prefer the old school.

Each chapter is a 5–10 minute read. Background and reference material live in
the other `Docs/` files — [`TUIBuilder.md`](../TUIBuilder.md),
[`Architecture.md`](../Architecture.md), [`Themes.md`](../Themes.md),
[`DataBinding.md`](../DataBinding.md) — and the chapters link into them
rather than repeating them.

## Ground rules

Two rules govern every page of this tutorial.

**The runnable-milestone rule.** Every chapter ends in a milestone the reader
runs:

```sh
swift run TUIKitTutorial ch1
```

The milestone code lives in the `TUIKitTutorialMilestones` target
(`Tutorial/Milestones/ChapterN.swift`), so it compiles forever, and
`TUIKitTutorialTests` renders each milestone headlessly in CI. Every snippet
in the chapter text is an excerpt of that compiling code — never pseudo-code.
If a chapter drifts from the framework, the build or CI fails instead of the
tutorial silently rotting.

**The declarative-first policy.** Chapters 1–5 build the app the declarative
way, with [TUIBuilder](../TUIBuilder.md) — the recommended style. Chapter 6
is the appendix for readers who prefer the old school: the same form
hand-wired with `addSubview` and anchors. Builders emit the identical
`TUIView` tree, so nothing you learn in one style is wasted in the other,
and Chapter 6 explains when dropping down is genuinely useful.

## The chapters

| Run | Chapter | What it covers |
| --- | --- | --- |
| `swift run TUIKitTutorial ch1` | [1 — Hello, terminal](Chapter1.md) | App + driver, a zero-frame window, `setContent`, the run loop, quitting |
| `swift run TUIKitTutorial ch2` | [2 — Layout: the app shell](Chapter2.md) | Stacks, panels, dividers, spacers; intrinsic vs flexible; no hand-computed frames |
| `swift run TUIKitTutorial ch3` | [3 — Controls & events (declarative)](Chapter3.md) | Controls as plain values; `onSubmit` / `onSelectionChanged` / `onActivate`; TabView; mnemonics; first responder |
| `swift run TUIKitTutorial ch4` | [4 — Focus, keys & mouse](Chapter4.md) | Key routing hot → focused → Tab → cold; `handleHotKey` for Ctrl+N; mouse for free |
| `swift run TUIKitTutorial ch5` | [5 — Testing your app (Chapter 4's app, under test)](Chapter5.md) | `HeadlessDriver` as a full driver; boot / send / snapshot; the anti-rot suite |
| `swift run TUIKitTutorial ch6` | [6 — Traditional approach (hand-wired Chapter 3)](Chapter6.md) | Construct → anchor → wire → addSubview; when to drop below the builder |

## Running and guarding it

Run any chapter from the package root with `swift run TUIKitTutorial chN`;
with no argument the runner lists the chapters (see
`Tutorial/Runner/main.swift`). Quit any milestone with Ctrl+C.

The tutorial is kept honest by `Tests/TUIKitTutorialTests/`: every milestone
boots through the `HeadlessDriver` and must render a landmark string, and the
interaction walkthroughs the chapters teach (typing a task, pressing the
hot-key, resizing) run there for real. The test file imports plain `TUIKit`
— no `@testable` — so the tutorial provably uses only public API. Run it
yourself:

```sh
swift test --filter TUIKitTutorialTests
```

Start with [Chapter 1 — Hello, terminal](Chapter1.md).
