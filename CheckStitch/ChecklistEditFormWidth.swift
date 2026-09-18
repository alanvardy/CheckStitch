import CheckStitchCore
import SwiftUI

extension View {
    /// Caps a pushed checklist edit form to a centred reading column.
    ///
    /// The form is capped first (phone-width viewports keep the whole viewport,
    /// wide ones use `ChecklistWidth.editFormMaxWidth`), then that capped column
    /// is centred. The second frame is load-bearing: `GeometryReader` pins its
    /// content to the top-leading corner, so a capped form without it sits hard
    /// against the left edge instead of hugging the middle.
    func checklistEditFormWidth(viewportWidth: CGFloat) -> some View {
        frame(maxWidth: ChecklistWidth.editFormMaxWidth(viewportWidth: viewportWidth))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}