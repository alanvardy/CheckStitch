import Foundation
import UniformTypeIdentifiers

#if os(iOS)
import SwiftUI
import UIKit
#endif

/// Builds the shared payload. The item-provider builder is intentionally
/// un-gated so the macOS-hosted unit suite can assert the type identifier,
/// `suggestedName` and the bytes an `NSItemProvider` yields; the representable
/// itself is iOS-only, as all platform wrappers here are.
enum ChecklistShare {
    /// The document's existing encoded bytes, registered under `UTType.json`
    /// with the `.json`-suffixed suggested name. No file URL, no staging.
    static func itemProvider(for document: ChecklistExportDocument,
                             filename: String) -> NSItemProvider {
        // Capture only the `Data` (Sendable) — the load handler is @Sendable.
        let payload = document.data
        let provider = NSItemProvider()
        provider.suggestedName = filename
        provider.registerDataRepresentation(forTypeIdentifier: UTType.json.identifier,
                                            visibility: .all) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }
}

#if os(iOS)
/// Root-owned wrapper over `UIActivityViewController`. Anchors the popover so
/// iPad does not trap at presentation time.
struct ShareSheet: UIViewControllerRepresentable {
    let document: ChecklistExportDocument
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [ChecklistShare.itemProvider(for: document, filename: filename)],
            applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                        y: controller.view.bounds.midY,
                                        width: 0,
                                        height: 0)
        }
    }
}
#endif