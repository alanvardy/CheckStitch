import Foundation

/// Launch-time UI-testing seams, parsed once at app start from `CommandLine`
/// arguments and the process environment. Every field defaults to off, so a
/// normal launch is byte-for-byte today's behaviour.
///
/// The only reader of launch arguments / UI-testing environment in the app;
/// views receive the parsed value, never `ProcessInfo`.
public struct LaunchSeams: Sendable, Equatable {
    public var isUITesting: Bool
    public var isEmpty: Bool
    public var seedURL: URL?
    public var openSettings: Bool
    public var openChecklistIndex: Int?
    public var language: AppLanguage?

    public init(
        isUITesting: Bool = false, isEmpty: Bool = false, seedURL: URL? = nil,
        openSettings: Bool = false, openChecklistIndex: Int? = nil,
        language: AppLanguage? = nil
    ) {
        self.isUITesting = isUITesting
        self.isEmpty = isEmpty
        self.seedURL = seedURL
        self.openSettings = openSettings
        self.openChecklistIndex = openChecklistIndex
        self.language = language
    }

    /// Ephemeral suite for `--ui-testing`; the real App Group container is
    /// never touched.
    public static let uiTestingSuiteName = "app.alanvardy.CheckStitch.uitesting"

    /// Pure parse. Each flag implies `isUITesting`; unknown arguments ignored.
    public static func parse(arguments: [String], environment: [String: String]) -> LaunchSeams {
        var seams = LaunchSeams()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--ui-testing":
                seams.isUITesting = true
            case "--ui-testing-empty":
                seams.isUITesting = true; seams.isEmpty = true
            case "--ui-testing-open-settings":
                seams.isUITesting = true; seams.openSettings = true
            case "--ui-testing-open-checklist":
                seams.isUITesting = true
                if index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
                    seams.openChecklistIndex = value; index += 1
                }
            case "--ui-testing-app-language":
                seams.isUITesting = true
                if index + 1 < arguments.count, let value = AppLanguage(rawValue: arguments[index + 1]) {
                    seams.language = value; index += 1
                }
            default:
                break // unknown flags tolerated
            }
            index += 1
        }
        if let raw = environment["CHECKSTITCH_UITEST_SEED"], !raw.isEmpty {
            seams.isUITesting = true
            seams.seedURL = URL(fileURLWithPath: raw)
        }
        return seams
    }

    public static func current(processInfo: ProcessInfo = .processInfo) -> LaunchSeams {
        parse(arguments: processInfo.arguments, environment: processInfo.environment)
    }

    /// The seed envelope, or nil when absent, `isEmpty`, or unreadable.
    public func loadSeedEnvelope() -> ChecklistEnvelope? {
        guard !isEmpty, let seedURL, let data = try? Data(contentsOf: seedURL) else { return nil }
        switch ChecklistCodec.classify(data) {
        case .loaded(let envelope):            return envelope
        case .migratable(_, let envelope):     return envelope
        case .unsupportedVersion, .unreadable: return nil
        }
    }
}