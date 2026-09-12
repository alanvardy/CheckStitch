import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct BackgroundPhotoLayer: View {
    let imageData: Data?
    var isEnabled = true
    var opacity = BackgroundFade.opacity(for: BackgroundFade.defaultValue)

    var body: some View {
        if isEnabled, let image = imageData.flatMap(Self.image(from:)) {
            // The overlay wrapper pins the layer to its parent's size so
            // `scaledToFill` can never expand the surrounding layout.
            Color.clear
                .overlay { image.resizable().scaledToFill() }
                .ignoresSafeArea()
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    static func image(from data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}
