import Foundation
import Sentry
import CheckStitchCore

/// Thin adapter from `SentryConfiguration` to `SentrySDK`. The only file besides
/// `SentryScrubber` that imports Sentry.
enum SentryBootstrap {
    // MARK: Internal

    static func startIfEnabled() {
        guard CrashReportingPreference().isEnabled,
              let configuration = SentryConfiguration.make(
                  dsn: bundleDSN,
                  environment: SentryConfiguration.currentEnvironment) else {
            return
        }
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.environment = configuration.environment
            options.maxBreadcrumbs = UInt(configuration.maxBreadcrumbs)
            options.sendDefaultPii = configuration.sendDefaultPii
            // Sentry's `Options.tracesSampleRate` is SDK-mandated NSNumber.
            // swiftlint:disable:next legacy_objc_type
            options.tracesSampleRate = NSNumber(value: configuration.tracesSampleRate)
            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.enableAutoSessionTracking = false
            // `attachScreenshot`/`attachViewHierarchy` only exist on UIKit-backed
            // platforms; sentry-cocoa does not declare them for macOS.
            #if os(iOS) || os(tvOS) || os(visionOS)
                options.attachScreenshot = false
                options.attachViewHierarchy = false
            #endif
            #if os(macOS)
                options.enableUncaughtNSExceptionReporting = true
            #endif
            options.beforeSend = { SentryScrubber.scrub($0) }
            options.beforeBreadcrumb = { SentryScrubber.scrub($0) }
        }
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            startIfEnabled()
        } else {
            SentrySDK.close()
        }
    }

    // MARK: Private

    private static var bundleDSN: String? {
        Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String
    }
}
