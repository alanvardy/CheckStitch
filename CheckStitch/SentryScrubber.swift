import Foundation
import Sentry

/// Allow-list scrubber applied to every event and breadcrumb before send.
/// It strips the free-text fields the SDK populates from app content — user,
/// extra, request, message, transaction, exception reasons, and breadcrumb
/// message/data — and keeps only structural metadata (exception type,
/// allow-listed tags, and breadcrumb category/type/level/timestamp). Sentry's
/// `contexts` are left intact: they carry SDK device/app metadata only, and no
/// CheckStitch code adds reminder/list content to them.
/// Returns `nil` to drop a breadcrumb when its payload is not allow-listed.
enum SentryScrubber {
    /// Tag keys that carry app/device metadata only — never reminder content.
    nonisolated static let allowedTags: Set<String> = ["environment", "release", "level"]

    nonisolated static func scrub(_ event: Event) -> Event? {
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
