# TUIKit — optional Embedded Swift / eZOS port

Updated: 2026-09-23. Plan only; implementation has not begun.

**Parent: LLVM Phase 6 (S2).** This component is now part of the main Phase 6
implementation breakdown, after Phase 5. ActivePascal/basicc are Phase 8,
ahead of TI (9) and COBOL (10); the original desktop dashboard stays separate.

**Ownership safety:** ordinary Swift keeps real `weak` references and their
safety guarantees. Any alternative ownership mechanism belongs only to the
explicit Embedded profile. Use narrow shared interfaces/conditional
implementations, preserve deallocation/nil behavior in full Swift, and qualify
stale callbacks/handles, detach and destruction in Embedded. No blanket strong
or unsafe-pointer replacement; document any observable profile differences.

Provide TUIKit controls and TUICodeEditor to native eZOS applications, beginning
with the 512 KiB Agon profile. Keep the desktop framework and ordinary Swift
available. Embedded is an explicit secondary configuration, never a fallback.

## Dashboard

**Implementation: 0% (0/4 acceptance groups).** This is the TUIKit component of
[N4 in the coordinated plan](/Users/bobby/AIResearch/MultiSim/Documents/EMBEDDED_EZOS_DEVELOPMENT_PLAN.md#n4--tuikit-controls-and-editor-on-ezos).
The existing desktop phase percentages are unchanged.

| Group | Milestone | Progress | % | Status |
| --- | --- | --- | ---: | --- |
| T1 / N4.1 | Minimal dependency graph builds | `░░░░░░░░░░░░░░░░░░░░░░░░░` | 0% | ⏳ After eZOS SDK gate N3 |
| T2 / N4.2 | Safe ownership and retained APIs | `░░░░░░░░░░░░░░░░░░░░░░░░░` | 0% | ⏳ After T1 |
| T3 / N4.3 | Event-driven controls on eZOS | `░░░░░░░░░░░░░░░░░░░░░░░░░` | 0% | ⏳ After T2 |
| T4 / N4.4 | Bounded editor and measured fit | `░░░░░░░░░░░░░░░░░░░░░░░░░` | 0% | ⏳ After T3 |

**Current action:** planning complete. **Evidence:** source/dependency audit.
**Blockers:** Embedded SDK/eZOS fit and ownership/executor qualification.
**Next:** coordinated N1 feasibility gate; TUIKit implementation follows N3.
Each demonstrated group contributes 25% to this component. Update here, the
parent PLAN dashboard and LLVM_PLAN after meaningful results; no time estimates.

## Work assessment

This is narrower than the OmegaCLIDE port: reuse the view/layout/focus/control
design and headless tests. It is not just a terminal-driver replacement.
Package.swift directly includes RichSwift and VectorTerminalSDK; TUICodeEditor
adds CodeEditorCore, and the @Bound macro uses SwiftSyntax on the compiler host.
Views/TUIView.swift uses a weak parent and many callbacks use weak captures.
TerminalDriver exposes AsyncStream; ANSIDriver relies on termios and Dispatch.
Preferences, logging, directory controls and links use Foundation services.

### T1 — Dependency boundary

- [ ] Define a cell-mode product graph excluding vector and unrelated rich
  rendering dependencies; move reusable capability boundaries upstream.
- [ ] Separate macro implementation from runtime linkage. Qualify native macro
  tooling or a documented macro-free binding API; no required Mac expansion
  step in the final native consumer workflow.
- [ ] Compile the minimum real control application with the pinned SDK and
  record exactly which controls/APIs remain available.

### T2 — Ownership and runtime

- [ ] Design profile-specific parent/callback lifetimes for Embedded while keeping
  native weak storage in ordinary Swift. Consider
  owner registries with generation-checked handles; do not replace weak links
  blindly with strong references or unchecked pointers.
- [ ] Verify detach, reparent, modal close, callback cancellation and teardown
  without retain cycles or stale references.
- [ ] Audit generic/existential dispatch and Foundation calls against the exact
  compiler version. Reuse supported String/collections/ARC instead of assuming
  Embedded forbids them. Record unsupported APIs explicitly.

### T3 — Driver and events

- [ ] Add eZOS console/VDP, keyboard, cursor, resize and filesystem adapters.
- [ ] Qualify event wakeup, timers and the cooperative executor. Preserve the
  existing event-driven/MainActor contract, clean shutdown and instance-owned
  state. keyScan alone does not provide async waiting; no busy loops or blocking
  the main/cooperative thread.
- [ ] Demonstrate menus, focus, dialogs and text input with headless controls
  and guest execution. Preserve padding/insets, clipping and text-width behavior.

### T4 — Editor and resources

- [ ] Bound CodeEditorCore/TUICodeEditor source, undo, token and render buffers;
  lazy directory lists and explicit file limits. Edit, save, undo and find work.
- [ ] Account for the whole eZOS memory reservation, not only executable size;
  measure heap/stack and check exhaustion/repeated teardown.
- [ ] Run retained desktop/headless regression controls. Record unrelated
  existing failures separately. Hardware qualification remains central N7.

The small-memory editor is shared framework work. OmegaCLIDE owns project and
compiler orchestration; do not add IDE-specific workarounds to controls.
Implementation updates Docs/Architecture.md and Docs/ControlsUML.md when those
contracts change. The central plan owns SDK/compiler/platform acceptance.
