// TUIKit Gallery — every control, grouped into folder tabs.
//
//   swift run TUIKitGallery
//
// The shell is the OmegaCLIDE form: a menu bar strip across the top, a
// resizable gallery window floating on the desktop, and a status strip
// along the bottom. The Theme menu restyles everything live (the app boots
// into Modern Turbo); the Charts tab shows each chart's VTG and ANSI
// renderings side by side on a VectorTerminal.

import TUIKit

try await GalleryApp().run()
