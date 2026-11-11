import CheckStitchCore
import SwiftUI
#if os(iOS)
    import Darwin
#endif

/// Resolves the layout context for the iPhone Duo outer screen. The decision
/// logic lives in `CheckStitchCore.DuoDisplay`; this only supplies the platform
/// values.
enum DuoOuterPortrait {
    /// Device model identifier (`hw.machine`), e.g. `"iPhone19,4"`. Read once.
    /// On macOS and in the iOS Simulator it is not the Duo model, so the
    /// detector resolves to the standard context.
    static let machineIdentifier: String = {
        #if os(iOS)
            var info = utsname()
            guard uname(&info) == 0 else { return "" }
            return withUnsafeBytes(of: &info.machine) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
        #else
            return ""
        #endif
    }()

    static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        machine: String = machineIdentifier
    ) -> ChecklistLayout.Context {
        ChecklistLayout.Context(
            isDuoOuterPortrait: DuoDisplay.isOuterPortrait(
                machine: machine,
                isCompactWidth: horizontal == .compact,
                isRegularHeight: vertical == .regular))
    }
}
