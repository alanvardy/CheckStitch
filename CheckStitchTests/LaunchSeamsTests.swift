import CheckStitchCore
import Foundation
import Testing

struct LaunchSeamsTests {
    @Test func noArgumentsIsANoOp() {
        #expect(LaunchSeams.parse(arguments: [], environment: [:]) == LaunchSeams())
    }

    @Test(arguments: [
        ["--ui-testing"], ["--ui-testing-empty"], ["--ui-testing-open-settings"],
    ])
    func eachFlagTurnsOnUITesting(_ arguments: [String]) {
        #expect(LaunchSeams.parse(arguments: arguments, environment: [:]).isUITesting)
    }

    @Test func emptyFlagSetsIsEmpty() {
        #expect(LaunchSeams.parse(arguments: ["--ui-testing-empty"], environment: [:]).isEmpty)
    }

    @Test func openSettingsFlagSetsOpenSettings() {
        #expect(LaunchSeams.parse(arguments: ["--ui-testing-open-settings"], environment: [:]).openSettings)
    }

    @Test func openChecklistParsesIndex() {
        let seams = LaunchSeams.parse(arguments: ["--ui-testing-open-checklist", "3"], environment: [:])
        #expect(seams.openChecklistIndex == 3)
    }

    @Test func openChecklistIgnoresNonInteger() {
        let seams = LaunchSeams.parse(arguments: ["--ui-testing-open-checklist", "banana"], environment: [:])
        #expect(seams.openChecklistIndex == nil)
        #expect(seams.isUITesting)
    }

    @Test(arguments: AppLanguage.allCases.filter { $0 != .system })
    func appLanguageParsesEveryPinnedId(_ language: AppLanguage) {
        let seams = LaunchSeams.parse(arguments: ["--ui-testing-app-language", language.rawValue], environment: [:])
        #expect(seams.language == language)
    }

    @Test func unknownLanguageIsNil() {
        let seams = LaunchSeams.parse(arguments: ["--ui-testing-app-language", "xx"], environment: [:])
        #expect(seams.language == nil)
    }

    @Test func unknownFlagIsTolerated() {
        #expect(LaunchSeams.parse(arguments: ["--not-a-flag"], environment: [:]) == LaunchSeams())
    }

    @Test func environmentSeedBecomesAFileURL() {
        let seams = LaunchSeams.parse(arguments: [], environment: ["CHECKSTITCH_UITEST_SEED": "/tmp/x.json"])
        #expect(seams.seedURL == URL(fileURLWithPath: "/tmp/x.json"))
        #expect(seams.isUITesting)
    }

    @Test func uiTestingWithoutSeedLoadsNoEnvelope() {
        var seams = LaunchSeams()
        seams.isUITesting = true
        #expect(seams.loadSeedEnvelope() == nil)
    }

    @Test func malformedSeedFileLoadsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).json")
        try Data("{not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var seams = LaunchSeams()
        seams.seedURL = url
        #expect(seams.loadSeedEnvelope() == nil)
    }

    @Test func validSeedFileLoadsEnvelope() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString).json")
        let uuid = UUID().uuidString
        let body =
            #"{"version":6,"deviceID":"t","checklists":[{"id":"\#(uuid)","name":"A","items":[{"id":"\#(uuid)","title":"x"}]}]}"#
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var seams = LaunchSeams()
        seams.seedURL = url
        let envelope = seams.loadSeedEnvelope()
        #expect(envelope != nil)
        #expect(envelope?.checklists.count == 1)
        #expect(envelope?.checklists.first?.name == "A")
    }
}