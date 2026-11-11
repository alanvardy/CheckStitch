/// Pure mapping from a device machine identifier plus size classes to the
/// "Duo outer display in portrait" condition. No UIKit, no `@available` —
/// unit-testable on the macOS-hosted suite.
public enum DuoDisplay {
    /// Model identifiers (`hw.machine`) of iPhones whose outer/cover display
    /// reports compact width × regular height in portrait. This set is the
    /// single maintenance point — add new Duo variants here and nowhere else.
    nonisolated public static let outerPortraitMachines: Set<String> = ["iPhone19,4"]

    /// The size-class pair is what scopes the match: the inner display and the
    /// outer landscape both fail it, so only the outer portrait presentation
    /// of a known machine fires.
    nonisolated public static func isOuterPortrait(
        machine: String,
        isCompactWidth: Bool,
        isRegularHeight: Bool
    ) -> Bool {
        outerPortraitMachines.contains(machine)
            && isCompactWidth
            && isRegularHeight
    }
}
