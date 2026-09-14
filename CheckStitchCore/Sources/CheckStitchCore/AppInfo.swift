import Foundation

/// Bundle-derived app identity — display name, marketing version, and build
/// number — formatted for the About screen. The first runtime `Bundle` read in
/// the codebase, kept injectable so it is unit-testable.
public struct AppInfo: Sendable {
    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Single source of truth for the feedback email address.
    public static let feedbackEmail = "alan@vardy.cc"

    /// `CFBundleShortVersionString` (e.g. "1.0"), nil if absent.
    public var marketingVersion: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// `CFBundleVersion` (e.g. "1"), nil if absent.
    public var buildNumber: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// `CFBundleDisplayName` ?? `CFBundleName` ?? "CheckStitch".
    public var displayName: String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "CheckStitch"
    }

    /// "Version 1.0 (1)"; "Version 1.0" when build is nil; "" when marketing is nil.
    public var versionDescription: String {
        guard let marketing = marketingVersion else { return "" }
        if let build = buildNumber {
            return String(
                localized: "Version \(marketing) (\(build))",
                table: "Localizable",
                bundle: .module)
        }
        return String(
            localized: "Version \(marketing)",
            table: "Localizable",
            bundle: .module)
    }

    private let bundle: Bundle
}