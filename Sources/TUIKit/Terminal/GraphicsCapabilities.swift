/// What a terminal's graphics plane can actually do.
///
/// One `Bool` — "has a graphics plane" — is enough while everything drawn on
/// it is baseline: rounded rectangles and circles, which every VectorTerminal
/// build implements. It stops being enough the moment anything OPTIONAL is
/// emitted, because a terminal that does not implement sprites answers a
/// sprite command by drawing nothing. A blank region where an image should be
/// is the worst kind of failure: it looks like a slow load, it produces no
/// error, and it is indistinguishable from success until somebody notices the
/// picture never arrived.
///
/// So this is the shape of "ask before you emit". It is a TUIKit value type
/// rather than a re-export of the SDK's own capability record, which keeps
/// raw VTG types inside the driver layer — the invariant `Docs/VTGChrome.md`
/// states, and the reason a non-VTG driver can answer this question at all.
public struct GraphicsCapabilities: Equatable, Sendable {
    /// Raster formats the terminal accepts.
    ///
    /// Empty means no raster at all: vector shapes only. A page whose image
    /// is a GIF can then say so instead of sending bytes into a void.
    public var rasterFormats: Set<ChromeCommand.ImageFormat>

    /// Whether images can be uploaded once and moved thereafter.
    ///
    /// The difference between re-sending two megabytes per scroll step and
    /// sending twenty bytes.
    public var supportsSprites: Bool

    /// Whether a layer can be scrolled as a unit.
    public var supportsLayerScroll: Bool

    /// Whether the terminal can clip a layer.
    public var supportsClipping: Bool

    /// Whether the terminal can hit-test regions for the app.
    public var supportsHitRegions: Bool

    /// Whether raster (images and sprites) draws on the plane UNDER the text.
    ///
    /// VectorTerminal's Metal build renders layer `-1` with a narrow native
    /// pass — shapes only — and says so in its capability reply; images sent
    /// there are accepted, retained, and never drawn. A black box where a
    /// picture should be. Its overlay planes draw the full primitive set, so
    /// when this is `false` the driver lifts raster to the overlay instead:
    /// see ``rasterLayer(requested:)``.
    public var supportsUnderTextRaster: Bool

    /// Creates a capability set.
    ///
    /// Every flag defaults to off, which is the honest default for a
    /// question nobody answered.
    public init(
        rasterFormats: Set<ChromeCommand.ImageFormat> = [],
        supportsSprites: Bool = false,
        supportsLayerScroll: Bool = false,
        supportsClipping: Bool = false,
        supportsHitRegions: Bool = false,
        supportsUnderTextRaster: Bool = false
    ) {
        self.rasterFormats = rasterFormats
        self.supportsSprites = supportsSprites
        self.supportsLayerScroll = supportsLayerScroll
        self.supportsClipping = supportsClipping
        self.supportsHitRegions = supportsHitRegions
        self.supportsUnderTextRaster = supportsUnderTextRaster
    }

    /// What a VectorTerminal is assumed to do before anything is asked.
    ///
    /// PNG and JPEG rasters and nothing optional — the set every build has
    /// been observed to implement. A driver that cannot answer the capability
    /// query reports this rather than nothing, because "we know it draws
    /// images, we do not know what else" is the true statement.
    public static let baseline = GraphicsCapabilities(rasterFormats: [.png, .jpeg])

    /// Whether an image in this format can be sent at all.
    ///
    /// - Parameter format: The raster format.
    public func accepts(_ format: ChromeCommand.ImageFormat) -> Bool {
        rasterFormats.contains(format)
    }

    /// The plane a raster command actually goes to.
    ///
    /// Under-text raster that the terminal cannot draw natively moves to the
    /// overlay, where every terminal draws it. The picture covers its cells
    /// either way — an image view blanks them — so nothing is lost by
    /// sitting above the text rather than beneath it.
    ///
    /// - Parameter requested: The plane the view asked for.
    /// - Returns: The plane to send.
    public func rasterLayer(requested: ChromeLayer) -> ChromeLayer {
        requested == .underText && !supportsUnderTextRaster ? .overlay : requested
    }
}

#if canImport(VectorTerminalSDK)
import VectorTerminalSDK

extension GraphicsCapabilities {
    /// Reads a terminal's reported capabilities.
    ///
    /// The translation lives here, at the driver boundary, so the SDK's own
    /// record never crosses into the framework: above this line TUIKit talks
    /// about sprites and formats, not about a semicolon-separated APC reply.
    ///
    /// Read PERMISSIVELY. A terminal listing `sprites=bitmap|indexed` and one
    /// listing `sprites=yes` both mean yes; the question being asked is
    /// "can I send this at all", and refusing over an unfamiliar spelling
    /// would turn a working terminal into a blank one.
    ///
    /// - Parameter reported: What the terminal answered.
    init(reported: VTGCapabilities) {
        let formats = Set(reported.formats.compactMap(ChromeCommand.ImageFormat.init(rawValue:)))

        self.init(
            rasterFormats: formats.isEmpty ? [] : formats,
            supportsSprites: !reported.sprites.isEmpty,
            supportsLayerScroll: reported.layerScroll == true,
            supportsClipping: reported.clip != nil,
            supportsHitRegions: reported.hit != nil,
            // Read STRICTLY, unlike the rest: the question is not "may I
            // send this" but "where will it show", and the overlay is the
            // answer that draws on every build.
            supportsUnderTextRaster: reported.underTextPrimitives.contains("image")
        )
    }
}
#endif
