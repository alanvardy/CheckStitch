import CoreGraphics

/// Layout policy for the checklist content column, scoped to the iPhone Duo
/// outer screen. Mirrors `OrientationPolicy`: a plain, cross-platform value
/// (`Context`) plus pure math, with the platform value injected by the caller.
///
/// `nonisolated` keeps the pure math callable outside the app target's
/// `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`), like `ChecklistWidth`.
///
/// The detector that produces `isDuoOuterPortrait` lives in the iOS-only app
/// target, so macOS, watchOS and every other platform always resolve to
/// `.standard` and keep the existing `min(340, 0.6W)` behaviour.
public enum ChecklistLayout {
    /// The screen context the layout should adapt to. `isDuoOuterPortrait` is
    /// false on every non-Duo device, every other Duo screen, and every other
    /// orientation, which resolves to the existing `.standard` behaviour.
    public struct Context: Equatable, Sendable {
        public let isDuoOuterPortrait: Bool

        public init(isDuoOuterPortrait: Bool) {
            self.isDuoOuterPortrait = isDuoOuterPortrait
        }

        public static let standard = Context(isDuoOuterPortrait: false)
    }

    /// Single home of the two gutter values — never copy these literals.
    nonisolated public static let defaultHorizontalInset: CGFloat = 32
    nonisolated public static let duoOuterHorizontalInset: CGFloat = 16

    /// Outer gutter applied outside the width cap. Halved on the Duo outer
    /// screen so the reclaimed space widens the visible card.
    nonisolated public static func horizontalInset(_ context: Context) -> CGFloat {
        context.isDuoOuterPortrait ? duoOuterHorizontalInset : defaultHorizontalInset
    }

    /// Viewport-relative cap for the list card and iOS header row. The default
    /// path delegates to `ChecklistWidth.maxContentWidth` so the two stay in
    /// lockstep; the Duo path halves the fractional side gap (20 % → 10 % per
    /// side) while keeping the same 340 ceiling. The two paths are equal at
    /// exactly `425` (the exact `340 / 0.8` crossover); below it the Duo
    /// fraction is active, at and above it both clamp to 340.
    nonisolated public static func maxContentWidth(
        viewportWidth: CGFloat,
        context: Context
    ) -> CGFloat {
        context.isDuoOuterPortrait
            ? min(340, viewportWidth * 0.8)
            : ChecklistWidth.maxContentWidth(viewportWidth: viewportWidth)
    }
}
