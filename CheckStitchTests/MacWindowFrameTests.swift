@testable import CheckStitch
import CoreGraphics
import Foundation
import Testing

struct MacWindowFrameTests {
    private let primary = NSRect(x: 0, y: 0, width: 1512, height: 982)

    private func isWithin(_ outer: NSRect, contains inner: NSRect) -> Bool {
        inner.origin.x >= outer.origin.x
            && inner.origin.y >= outer.origin.y
            && inner.maxX <= outer.maxX
            && inner.maxY <= outer.maxY
    }

    @Test
    func onScreenFrameLeavesFullyVisibleWindowUntouched() {
        let frame = NSRect(x: 100, y: 20, width: 501, height: 944)
        #expect(MacAppDelegate.onScreenFrame(frame, screenFrames: [primary]) == frame)
    }

    @Test
    func onScreenFrameMovesOffScreenWindowOntoPrimaryScreen() {
        let frame = NSRect(x: 2350, y: -531, width: 501, height: 944)
        let clamped = MacAppDelegate.onScreenFrame(frame, screenFrames: [primary])
        #expect(isWithin(primary, contains: clamped))
        #expect(clamped.size == frame.size)
    }

    @Test
    func onScreenFrameClampsOversizedWindowToScreenSize() {
        let frame = NSRect(x: 5000, y: 5000, width: 3000, height: 2000)
        let clamped = MacAppDelegate.onScreenFrame(frame, screenFrames: [primary])
        #expect(isWithin(primary, contains: clamped))
        #expect(clamped.size == primary.size)
    }

    @Test
    func onScreenFrameLeavesWindowOnSecondaryScreenUntouched() {
        let secondary = NSRect(x: 1512, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: 2000, y: 300, width: 501, height: 944)
        #expect(MacAppDelegate.onScreenFrame(frame, screenFrames: [primary, secondary]) == frame)
    }

    @Test
    func onScreenFrameLeavesFrameUnchangedWithoutAnyScreen() {
        let frame = NSRect(x: 2350, y: -531, width: 501, height: 944)
        #expect(MacAppDelegate.onScreenFrame(frame, screenFrames: []) == frame)
    }

    @Test
    func onScreenFrameLeavesEmptyFrameUnchanged() {
        let frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        #expect(MacAppDelegate.onScreenFrame(frame, screenFrames: [primary]) == frame)
    }
}
