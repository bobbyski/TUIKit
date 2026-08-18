import Foundation
import Testing
@testable import TUIKit

// Comparing frames without comparing megabytes.

private let hero = Data(repeating: 0xAB, count: 2_000_000)

private func sprite(_ id: String, rect: ChromeRect, asset: ChromeImageAsset) -> ChromeCommand {
    ChromeCommand(id: id, layer: .underText, shape: .sprite(rect, asset: asset))
}

@Test func anAssetIsComparedByIdRatherThanByItsPixels() {
    // The whole point: two megabytes, one string comparison.
    let a = ChromeImageAsset(id: "hero-9f2c", data: hero)
    let b = ChromeImageAsset(id: "hero-9f2c", data: hero)
    let other = ChromeImageAsset(id: "hero-0001", data: hero)

    #expect(a == b)
    #expect(a != other, "a different id is a different picture, whatever the bytes say")
}

@Test func anUnmovedSpriteFrameIsRecognisedAsUnchanged() {
    let asset = ChromeImageAsset(id: "hero-9f2c", data: hero)
    let rect = ChromeRect(x: 0, y: 0, width: 20, height: 10)
    let frame = [sprite("hero", rect: rect, asset: asset)]

    #expect(ChromeSceneReconciler.plan(previous: frame, current: frame) == .unchanged)

    // And moving it IS a change, or a scroll would draw nothing.
    let moved = [sprite("hero", rect: ChromeRect(x: 0, y: 1, width: 20, height: 10), asset: asset)]
    #expect(ChromeSceneReconciler.plan(previous: frame, current: moved) != .unchanged)
}

@Test func swappingThePictureUnderTheSamePlacementIsAChange() {
    // THE TRAP in "just drop the bytes from equality": the command id names
    // the PLACEMENT, not the pixels. A play button becoming a pause button
    // keeps its placement and must still be redrawn — which is why the ASSET
    // carries the identity and the producer promises it is content-addressed.
    let rect = ChromeRect(x: 0, y: 0, width: 2, height: 1)
    let play = sprite("button", rect: rect, asset: ChromeImageAsset(id: "play-1", data: Data([1])))
    let pause = sprite("button", rect: rect, asset: ChromeImageAsset(id: "pause-1", data: Data([2])))

    #expect(play != pause)
    #expect(ChromeSceneReconciler.plan(previous: [play], current: [pause]) != .unchanged)
}

@Test func comparingFramesOfSpritesCostsAlmostNothing() {
    // Not a benchmark anybody has to maintain — a bound loose enough to be
    // stable and tight enough that a per-frame megabyte comparison cannot
    // pass it. Sixty frames of eight two-megabyte images.
    let assets = (0..<8).map { ChromeImageAsset(id: "image-\($0)", data: hero) }
    let rect = ChromeRect(x: 0, y: 0, width: 40, height: 20)
    let frame = assets.enumerated().map { sprite("image\($0.offset)", rect: rect, asset: $0.element) }

    let start = ContinuousClock.now

    for _ in 0..<60 where ChromeSceneReconciler.plan(previous: frame, current: frame) != .unchanged {
        Issue.record("an unmoving frame reported a change")
    }

    #expect(start.duration(to: .now) < .milliseconds(50))
}

@Test func anIdTheTerminalWouldRejectIsRepairedRatherThanDropped() {
    // VTG ids are [A-Za-z0-9_-], and a caller's most natural id is a path.
    // An id the terminal refuses is an image that silently never appears.
    let asset = ChromeImageAsset(id: "/proj/images/hero photo.png", data: Data([1]))

    #expect(asset.id == "_proj_images_hero_photo_png")
    #expect(ChromeImageAsset(id: "", data: Data()).id == "asset")
}
