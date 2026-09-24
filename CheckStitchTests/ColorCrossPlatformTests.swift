@testable import CheckStitch
import AppKit
import SwiftUI
import Testing

@MainActor
struct ColorCrossPlatformTests {
    @Test
    func systemBackgroundMatchesPlatformSystemColor() {
        // Resolve both sides through `NSColor` so the assert is on the rendered
        // colour, not on `Color`'s opaque provider identity.
        let actual = NSColor(Color.systemBackground).usingColorSpace(.sRGB)
        let expected = NSColor(Color(nsColor: .windowBackgroundColor)).usingColorSpace(.sRGB)
        #expect(actual == expected)
    }
}