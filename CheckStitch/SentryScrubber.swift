import Foundation
import Sentry

/// Allow-list scrubber applied to every event and breadcrumb before send.
/// It strips the free-text fields the SDK populates from app content — user,
/// extra, request, message, transaction, exception reasons, and breadcrumb
/// message/data — and keeps only structural metadata (exception type,
/// allow-listed tags, and breadcrumb category/type/level/timestamp). Sentry's
/// `contexts` are left intact: they carry SDK device/app metadata only, and no
/// CheckStitch code adds reminder/list content to them.
///
/// `scrub(_ event:)` returns `nil` to drop a whole event that matches the
/// captured system-stall app hang; `scrub(_ breadcrumb:)` returns `nil` when a
/// breadcrumb's payload is not allow-listed.
enum SentryScrubber {
    /// One frame reduced to the fields `beforeSend` actually receives.
    struct StackFrameSignature: Equatable {
        /// `Frame.package` — the loaded binary's path.
        let image: String
        /// `Frame.inApp`, with the app-bundle path as a belt-and-braces fallback.
        let isApp: Bool
    }

    /// Tag keys that carry app/device metadata only — never reminder content.
    nonisolated static let allowedTags: Set<String> = ["environment", "release", "level"]

    /// Binary-image substring of the synchronous Guided Access bundle-loading
    /// stall UIKit performs on the main thread. Sentry issue 7849871699:
    /// `GuidedAccessManager._loadRequiredBundles` → `_loadClientBundle` →
    /// `-[NSBundle loadAndReturnError:]` → `_NSFrameworkPathFromLibraryPath`
    /// (blocking `access` syscall). `AccessibilitySettingsLoader` is the one
    /// distinctive binary; `Foundation`/`libsystem_kernel.dylib` are
    /// near-universal and add no specificity.
    ///
    /// Function names are NOT available in `beforeSend` — sentry-cocoa sets only
    /// `package`/`inApp` at capture and symbolicates `function` server-side — so
    /// the signature is matched on image paths.
    nonisolated static let systemStallSignatureImages: [String] = [
        "AccessibilitySettingsLoader"
    ]

    /// Pure drop decision. Fail-open: any under-specified input returns `false`,
    /// so the event is reported rather than silently lost. `frames` is ordered
    /// outermost → innermost, as sentry-cocoa serializes the stack.
    ///
    /// All three conditions must hold:
    ///  1. the mechanism is the public, stable `"AppHang"` marker,
    ///  2. the stack contains every image in `systemStallSignatureImages`,
    ///  3. no in-app frame sits at or deeper than the first stall frame.
    nonisolated static func isSystemStall(
        mechanismType: String?,
        frames: [StackFrameSignature]) -> Bool {
        // Redundant with `appHangStack`'s filter; kept so the predicate stands
        // alone and can never drop a non-`AppHang` event.
        guard mechanismType == "AppHang" else { return false }
        guard !frames.isEmpty else { return false }
        guard systemStallSignatureImages.allSatisfy({ signature in
            frames.contains { $0.image.contains(signature) }
        }) else { return false }
        guard let firstStall = frames.firstIndex(where: { frame in
            systemStallSignatureImages.contains { frame.image.contains($0) }
        }) else { return false }
        return !frames[firstStall...].contains(where: \.isApp)
    }

    /// Reduces a Sentry event to an app-hang signature, or `nil` for any shape it
    /// does not recognise (fail-open).
    nonisolated static func appHangStack(
        in event: Event) -> (mechanismType: String, frames: [StackFrameSignature])? {
        guard
            let exception = event.exceptions?.first(where: {
                $0.mechanism?.type == "AppHang"
            }),
            let mechanismType = exception.mechanism?.type,
            let stacktrace = exception.stacktrace,
            !stacktrace.frames.isEmpty
        else { return nil }
        return (mechanismType, stacktrace.frames.map(StackFrameSignature.init))
    }

    nonisolated static func scrub(_ event: Event) -> Event? {
        if let stack = appHangStack(in: event),
           isSystemStall(mechanismType: stack.mechanismType, frames: stack.frames) {
            return nil
        }
        event.user = nil
        event.extra = nil
        event.request = nil
        event.modules = nil
        event.message = nil
        event.transaction = nil
        event.tags = event.tags?.filter { allowedTags.contains($0.key) }
        // `Exception.value` is free text (an uncaught `NSException`'s reason on
        // Apple platforms); keep the structural `type` so crashes still group.
        event.exceptions?.forEach { $0.value = nil }
        event.breadcrumbs = event.breadcrumbs?.compactMap(scrub)
        return event
    }

    /// Keeps category/type/level/timestamp, drops the free-text message and data
    /// bag. The `data` setter is deprecated in sentry-cocoa (it becomes
    /// read-only), so a clean breadcrumb is rebuilt with only the structural
    /// fields.
    nonisolated static func scrub(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        let scrubbed = Breadcrumb(level: breadcrumb.level, category: breadcrumb.category)
        scrubbed.type = breadcrumb.type
        scrubbed.timestamp = breadcrumb.timestamp
        return scrubbed
    }
}

extension SentryScrubber.StackFrameSignature {
    nonisolated init(_ frame: Frame) {
        let image = frame.package ?? ""
        self.image = image
        isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")
    }
}
