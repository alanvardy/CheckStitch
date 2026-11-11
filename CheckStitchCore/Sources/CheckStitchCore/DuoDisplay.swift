/// Pure mapping from a device machine identifier plus size classes to the
/// "Duo outer display in portrait" condition. No UIKit, no `@available` —
/// unit-testable on the macOS-hosted suite.
public enum DuoDisplay {
    /// Model identifiers (`hw.machine`) of iPhones whose outer/cover display
    /// reports compact width × regular height in portrait. Single maintenance
    /// point — add new Duo variants here.
    nonisolated public static let outerPortraitMachines: Set<String> = ["iPhone19,4"]

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
