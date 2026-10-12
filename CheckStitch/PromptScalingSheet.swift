import CheckStitchCore
import SwiftUI

/// Asks for the scaling factor for one Prompt-mode run. The entered number is
/// per-run: `onConfirm` hands it to the run's `multipleOverride` and nothing
/// here writes to the store. Confirm is disabled until the typed value is within
/// `Checklist.multipleRange`.
struct PromptScalingSheet: View {
    let lastFixed: Int
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(lastFixed: Int, onConfirm: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.lastFixed = lastFixed
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _text = State(initialValue: String(Checklist.clampedMultiple(lastFixed)))
    }

    /// The valid factor for the typed text, or `nil` when it is not an in-range
    /// integer. Pure so the suite pins the enable/disable rule without staging
    /// the sheet.
    static func validated(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              Checklist.multipleRange.contains(value)
        else { return nil }
        return value
    }

    private var enteredValue: Int? { Self.validated(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Scaling", text: $text)
                        .accessibilityIdentifier("promptScalingField")
                } footer: {
                    Text("Enter a number between 1 and 99.")
                }
            }
            .navigationTitle("Scale this run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .accessibilityIdentifier("promptScalingCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { if let enteredValue { onConfirm(enteredValue) } }
                        .disabled(enteredValue == nil)
                        .accessibilityIdentifier("promptScalingConfirmButton")
                }
            }
        }
    }
}