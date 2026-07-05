import Foundation
import TUIKit
import TUIKitTutorialMilestones

// TUIKitTutorial — runs one chapter's milestone from Docs/Tutorial/.
//
//   swift run TUIKitTutorial ch1     Hello, terminal
//   swift run TUIKitTutorial ch3     Controls & events
//   …
//
// With no (or an unknown) argument it lists the chapters. Each milestone is
// also rendered headlessly by TUIKitTutorialTests, so the tutorial's code
// can never drift from the framework.

let key = CommandLine.arguments.dropFirst().first ?? ""
let milestones = TutorialMilestones.all

guard let milestone = milestones.first(where: { "ch\($0.chapter)" == key }) else {
    print("usage: swift run TUIKitTutorial <chapter>")
    print("")

    for entry in milestones {
        print("  ch\(entry.chapter)   \(entry.title)")
    }

    exit(key.isEmpty ? 0 : 1)
}

let app = App(driver: ANSIDriver())
try await app.run(milestone.makeWindow(app: app))
