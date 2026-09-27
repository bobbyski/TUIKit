// Copyright (c) 2026 Bobby Skinner
// SPDX-License-Identifier: MIT
// See the LICENSE file at the repository root for the full text.

/// Making an app on the terminal, without naming the driver.
///
/// `App(driver:)` takes any `TerminalDriver`, which is the right shape for
/// tests and for a driver that is not a terminal. But nearly every app wants
/// the ANSI one, and writing `App(driver: ANSIDriver())` is ceremony that
/// says nothing — so this is the initializer an app reaches for, and the
/// general one stays for everything else.
///
/// It also happens to be the only initializer a language without Swift's
/// existential types can reach. A C# program importing TUIKit sees
/// `any TerminalDriver` as a protocol it has no way to spell, so
/// `App(driver:)` does not cross — and an app that cannot make an `App` is
/// not an app. `Examples/TurboCounter` in CSharpSwift is the first caller.
@MainActor
extension App {
    /// Creates an application on the terminal.
    ///
    /// - Parameter presentation: The whole screen, or a few rows at the
    ///   cursor. Defaults to the whole screen.
    public convenience init(presentation: ANSIDriver.Presentation = .fullScreen) {
        self.init(driver: ANSIDriver(presentation: presentation))
    }
}
