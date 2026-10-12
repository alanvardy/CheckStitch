@testable import CheckStitch
import CheckStitchCore
import Testing

struct PromptScalingSheetTests {
    @Test(arguments: ["1", "2", "99", " 7 "])
    func validNumbersEnableConfirm(_ text: String) {
        #expect(PromptScalingSheet.validated(text) != nil)
    }

    @Test(arguments: ["", "0", "100", "-1", "2.5", "seven"])
    func invalidNumbersDisableConfirm(_ text: String) {
        #expect(PromptScalingSheet.validated(text) == nil)
    }

    @Test
    func validatedReturnsTheInRangeValue() {
        #expect(PromptScalingSheet.validated("42") == 42)
        #expect(PromptScalingSheet.validated("0") == nil)
        #expect(PromptScalingSheet.validated("100") == nil)
    }
}