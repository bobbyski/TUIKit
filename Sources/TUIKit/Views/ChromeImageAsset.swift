import Foundation

/// Image bytes with an identity, so frames can be compared without them.
///
/// The id is the promise: **equal ids mean equal pixels**. Whoever makes an
/// asset is the only one who can promise that — they know when the picture
/// changed — and it is what lets a scroll of a two-megabyte image cost a
/// string comparison per frame instead of a megabyte one.
///
/// A terminal that implements sprites also uses the id directly: upload once,
/// then move for about twenty bytes a frame. One that does not gets the image
/// drawn the old way, from the same bytes, so an asset is never a reason for
/// something not to appear.
public struct ChromeImageAsset: Hashable, Sendable {
    /// Content-addressed identity, VTG-legal: letters, digits, `_` and `-`.
    ///
    /// A hash of the bytes is the obvious choice. A path plus a modification
    /// date is fine too. A counter that increments per draw is not — that is
    /// a new asset every frame, which is the behaviour this replaces.
    public let id: String

    /// The image's own pixel size, so a driver can scale without decoding.
    public let pixelWidth: Int

    /// The image's own pixel height.
    public let pixelHeight: Int

    /// Which raster format `data` is in.
    public let format: ChromeCommand.ImageFormat

    /// The bytes. Never compared — see ``id``.
    public let data: Data

    /// Creates an asset.
    ///
    /// - Parameters:
    ///   - id: Content-addressed identity. Sanitised to the characters VTG
    ///     accepts, since an id it rejects is an image that never draws.
    ///   - pixelWidth: Natural width in pixels.
    ///   - pixelHeight: Natural height in pixels.
    ///   - format: Raster format.
    ///   - data: The encoded image.
    public init(
        id: String,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        format: ChromeCommand.ImageFormat = .png,
        data: Data
    ) {
        self.id = Self.sanitised(id)
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.format = format
        self.data = data
    }

    /// Equality is the id, which is the whole point: comparing two megabytes
    /// to discover they are the same two megabytes is the cost being removed.
    public static func == (lhs: ChromeImageAsset, rhs: ChromeImageAsset) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // VTG ids are [A-Za-z0-9_-]; anything else is replaced rather than
    // rejected, because an id the terminal refuses is an image that silently
    // never appears — and a path or a URL is the most natural thing for a
    // caller to reach for.
    private static func sanitised(_ id: String) -> String {
        let cleaned = id.map { character -> Character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
                ? character
                : "_"
        }

        return cleaned.isEmpty ? "asset" : String(cleaned)
    }
}
