import Foundation

/// Test fixture: a `Bundle` subclass returning a fixed info dictionary so
/// `AppInfo` can be exercised without the real bundle's Info.plist.
///
/// Must restate `@unchecked Sendable`: `Bundle` is `@unchecked Sendable`, and
/// Swift 6 + warnings-as-errors rejects subclasses that don't restate it.
final class StubBundle: Bundle, @unchecked Sendable {
    init(info: [String: Any]) {
        stubbedInfo = info
        super.init()
    }

    override var infoDictionary: [String: Any]? { stubbedInfo }

    override func object(forInfoDictionaryKey key: String) -> Any? { stubbedInfo[key] }

    private let stubbedInfo: [String: Any]
}