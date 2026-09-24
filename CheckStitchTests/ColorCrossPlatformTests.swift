@testable import CheckStitch
import SwiftUI
import Testing

#if os(macOS)
    import AppKit
#endif

@MainActor
struct ColorCrossPlatformTests {
    // The macOS-hosted unit run is where this suite is exercised; the test
    // bundle is also compiled against the iOS simulator SDK by the `test-ui`
    // leg, on which AppKit (and the macOS branch) is unavailable, so the whole
    // case is guarded to stay a no-op there.
    #if os(macOS)
        @Test
        func systemBackgroundMatchesPlatformSystemColor() {
            // Resolve both sides through `NSColor` so the assert is on the rendered
            // colour, not on `Color`'s opaque provider identity.
            let actual = NSColor(Color.systemBackground).usingColorSpace(.sRGB)
            let expected = NSColor(Color(nsColor: .windowBackgroundColor)).usingColorSpace(.sRGB)
            #expect(actual == expected)
        }
    #endif
}