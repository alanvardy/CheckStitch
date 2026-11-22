Report for Question 4. (No write tool available; returning the full artifact below as instructed.)

# Q4 — How the Sentry test suites build and assert events

## Scope of what exists
Two Swift Testing suites, one per repo, both `import Sentry` + `@testable import <App>`:
- CheckStitch: `CheckStitchTests/SentryScrubberTests.swift` (84 lines), `CheckStitchTests/SentryConfigurationTests.swift` (36 lines).
- SingleThread: `SingleThreadTests/SentryScrubberTests.swift` (201 lines), `SingleThreadTests/SentryConfigurationTests.swift` (47 lines).
- No Sentry tests exist in `CheckStitchCore/` or `SingleThreadCore/`; all Sentry test code lives in the app-target test dirs. SingleThread has **no** stall logic in its Core package (grep empty).

## Fixture / construction conventions
- Events are built inline with the SDK's own types: `let event = Event()`, then mutate `event.extra`, `event.user = User(userId:)`, `event.tags`, `event.exceptions`, `event.message = SentryMessage(formatted:)`, `event.transaction`. See `CheckStitchTests/SentryScrubberTests.swift:9-12`, `:62-65`, `:75-77`.
- Breadcrumbs: `Breadcrumb(level: .info, category: "reminder")`, then `breadcrumb.message`, `breadcrumb.setData(value:key:)` (`CheckStitchTests/SentryScrubberTests.swift:24-28`). CheckStitch also sets `breadcrumb.type` (`:25`); SingleThread's parallel test does not (`SingleThreadTests/SentryScrubberTests.swift:26-29`).
- Exceptions: `Exception(value: "...", type: "NSInternalInconsistencyException")` (`CheckStitchTests/SentryScrubberTests.swift:63-65`).
- Assertions are non-optional-`nil`/survival checks via Swift Testing `#expect`: dropped fields `#expect(scrubbed?.extra == nil)` (`:16`); surviving fields `#expect(scrubbed?.tags?["environment"] == "debug")` (`:19`); event-return checks `#expect(scrubbed != nil)` (`:44`). No custom fixture helper type in CheckStitch — construction is per-test inline.

## SingleThread system-stall test structure (the only stall tests)
Struct `SentryScrubberTests` (`SingleThreadTests/SentryScrubberTests.swift:6`), organized by `// MARK:` sections: `// MARK: Internal` (`:7`), `// MARK: App-hang system-stall predicate` (`:85`), `// MARK: Fail-open guarantee` (`:109`), `// MARK: Private` (`:151`), `// MARK: Fixtures` (`:153`).

### Fixture helpers
- `private static let` image-path constants: `appImage` (points at `SingleThread.app/SingleThread`, `:155-156`), `swiftUI`, `uiKit`, `graphicsServices`, `coreFoundation`, `libDispatch`, `backBoard` (BackBoardServices), `libXPC` (`/usr/lib/system/libxpc.dylib`), `libObjCMsgSend` (`:157-167`).
- `private static let capturedFrames: [(image: String, inApp: Bool)]` — the verbatim client-side stack of the real issue, ~26 `(image, inApp)` tuples with `dyld` false, the one `appImage` true, and repeated `swiftUI`/`uiKit`/`coreFoundation`/`libDispatch`/`backBoard`/`libXPC` frames (`:169-182`).
- `private func hangEvent(frames:mechanismType: = "AppHang") -> Event` — the synthetic event builder (`:184-200`): creates `Event()`, `Exception(value: "App hanging.", type: "App Hang Fully Blocked")`, sets `exception.mechanism = Mechanism(type: mechanismType)`, builds `exception.stacktrace = SentryStacktrace(frames:registers: [:])` by mapping each tuple into a `Frame` with `sentryFrame.package = frame.image` and `sentryFrame.inApp = NSNumber(value: frame.inApp)` (with a `swiftlint:disable:next legacy_objc_type` comment, `:193-195`), then `event.exceptions = [exception]`.

### Event-return vs event-drop assertions
- Drop assertion: `#expect(SentryScrubber.scrub(hangEvent(frames: Self.capturedFrames)) == nil)` (`:88-90`).
- Return assertion: `#expect(SentryScrubber.scrub(hangEvent(...)) != nil)` for keep cases (`:97`, `:128`, `:135`, `:142`, `:148`).
- Mixed case asserts both survival and continued PII scrubbing: `#expect(scrubbed != nil)` + `#expect(scrubbed?.extra == nil)` for a non-`AppHang` mechanism (`:101-107`).
- Mutated-frame cases copy `Self.capturedFrames` into a `var`, then overwrite/insert an app frame to test the "app frame in blocked chain" predicate (`:93-98`, `:139-143`).

### Test naming
Descriptive camelCase behavioral sentences: `dropsCapturedBacklightSystemStall` (`:87`), `keepsHangWithAppFrameInBlockedChain` (`:93`), `keepsNonHangBacklightEvent` (`:100`), and the fail-open family `keepsEventWhenMechanismRenamed` (`:112`), `keepsEventWhenStacktraceMissing` (`:117`), `keepsEventWhenFrameListEmpty` (`:127`), `keepsEventWhenDenylistPartiallyMatches` (`:131`), `keepsEventWhenAppFrameIsInBlockedChain` (`:138`), `keepsEventWhenFramePackageIsMissing` (`:145`). The `keeps...When...` prefix encodes the fail-open contract; the missing-stacktrace case constructs its event inline rather than via `hangEvent` (`:118-124`).

## Configuration suite conventions (both repos, near-identical)
`@MainActor struct SentryConfigurationTests` calling `SentryConfiguration.make(dsn:environment:)` and asserting with `#expect`: DSN trimming (`SentryConfigurationTests.swift:8-11`), empty/whitespace → `nil` (`:14-18`), safe privacy defaults (`sendDefaultPii == false`, `tracesSampleRate == 0`, `0 < maxBreadcrumbs <= 50`, `:21-26`), and a `#if DEBUG` environment mapping check (`:28-35`). SingleThread adds `emptyDsnIsNeverStarted` (`SingleThreadTests/SentryConfigurationTests.swift:20-29`); CheckStitch does not. These suites do not construct `Event` objects.

## CheckStitch's own scrubber suite (no stall coverage)
`CheckStitchTests/SentryScrubberTests.swift` mirrors the SingleThread non-stall tests (event PII removal, breadcrumb rebuild, exception type survival) but has **no** `AppHang`/`StackFrameSignature`/`isSystemStall` tests and no frame-fixture helpers; CheckStitch's `SentryScrubber.swift` has no stall code (only `allowedTags` + the two `scrub` overloads, `CheckStitch/SentryScrubber.swift:12-40`).