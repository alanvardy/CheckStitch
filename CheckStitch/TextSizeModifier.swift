import SwiftUI

// MARK: - TextSizeModifier

/// Conditionally applies ``TextSize`` to the view hierarchy. When the user
/// selects `.system`, no `dynamicTypeSize` override is applied so the view
/// follows the system Dynamic Type setting.
struct TextSizeModifier: ViewModifier {
    let textSize: TextSize

    func body(content: Content) -> some View {
        if let size = textSize.dynamicTypeSize {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}
