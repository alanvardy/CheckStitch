@testable import CheckStitch
import SwiftUI
import Testing

/// The app target's default actor isolation marks `TextSize`'s members
/// `@MainActor`, so the suite opts in like `ViewRenderTests`.
@MainActor
struct TextSizeTests {
    @Test
    func dynamicTypeSizeMapsEachCase() {
        #expect(TextSize.system.dynamicTypeSize == nil)
        #expect(TextSize.small.dynamicTypeSize == .small)
        #expect(TextSize.medium.dynamicTypeSize == .medium)
        #expect(TextSize.large.dynamicTypeSize == .xLarge)
        #expect(TextSize.extraLarge.dynamicTypeSize == .xxxLarge)
    }

    @Test
    func allCasesAreOrderedAndUnique() {
        #expect(TextSize.allCases.map(\.rawValue) ==
            ["system", "small", "medium", "large", "extraLarge"])
        #expect(Set(TextSize.allCases.map(\.rawValue)).count == TextSize.allCases.count)
    }

    @Test
    func titlesAndSymbolsResolveThroughTheAppCatalog() {
        // Same pinned-locale approach as ViewRenderTests' appearance assertion.
        #expect(TextSize.allCases.map(\.title) ==
            ["System", "Small", "Medium", "Large", "Extra Large"])
        #expect(TextSize.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }

    @Test
    func unknownRawValueDoesNotResolve() {
        // `@AppStorage` falls back to the declared default for a bad string.
        #expect(TextSize(rawValue: "gigantic") == nil)
        #expect(TextSize(rawValue: "extraLarge") == .extraLarge)
    }
}
