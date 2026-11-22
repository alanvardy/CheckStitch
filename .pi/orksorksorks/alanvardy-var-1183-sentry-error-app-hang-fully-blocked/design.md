# Design Discussion

## Current State

CheckStitch reports to Sentry through a deliberately thin integration:

- `MyApp.init()` starts Sentry first, gated on `!seams.isUITesting`
  (`CheckStitch/MyApp.swift:42-45`), via `SentryBootstrap.startIfEnabled()`
  (`CheckStitch/SentryBootstrap.swift:10-16`).
- `SentryBootstrap` configures the SDK (`SentryBootstrap.swift:17-41`) and wires
  `options.beforeSend = { SentryScrubber.scrub($0) }` and
  `options.beforeBreadcrumb = { SentryScrubber.scrub($0) }`
  (`SentryBootstrap.swift:40-41`).
- App-hang tracking is explicitly on: `enableAppHangTracking = true`
  (`SentryBootstrap.swift:26`).
- `SentryScrubber.scrub(_ event:) -> Event?` (`CheckStitch/SentryScrubber.swift:16-27`)
  nulls `user`, `extra`, `request`, `modules`, `message`, `transaction`, each
  `exceptions[].value`, filters `tags` to `allowedTags`
  (`SentryScrubber.swift:13,22`), and rebuilds `breadcrumbs`. It **always
  returns `event`** — there is no whole-event drop path today, and no
  `StackFrameSignature`, `systemStallSignatureImages`, `isSystemStall`, or
  `appHangStack` anywhere in the repo (research cross-cutting observations).

The production event in question (Linear VAR-1183, Sentry issue 7849871699,
`App Hang Fully Blocked`, culprit `MyApp.$main`) has **no CheckStitch app-logic
frames** on the hung main thread. Its `exceptions[0].stacktrace.frames`
(`Frame.package`, outermost → innermost) are:

```
dyld
.../CheckStitch.app/CheckStitch           (MyApp.$main, main — In app)
/System/Library/Frameworks/SwiftUI.framework/SwiftUI
/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore
/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices
/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
/System/Library/AccessibilityBundles/AccessibilitySettingsLoader.bundle/AccessibilitySettingsLoader
/usr/lib/system/libdispatch.dylib
/System/Library/Frameworks/Foundation.framework/Foundation
/usr/lib/system/libsystem_kernel.dylib   (innermost — blocking `access`)
```

The stall is Guided Access bundle loading: `GuidedAccessManager._loadRequiredBundles`
→ `_loadClientBundle` → `-[NSBundle loadAndReturnError:]` →
`_NSFrameworkPathFromLibraryPath` → a blocking `access` syscall. It is a system
stall, not an app bug.

The directly analogous precedent is SingleThread VAR-1165
(`/Users/vardy/dev/SingleThread/SingleThread/SentryScrubber.swift`), which added
a fail-open `beforeSend` drop for a *different* system stall
(BackBoardServices → libxpc, Sentry issue 7821993169) at `:29-53,57-68,74-77`.

## Desired End State

`SentryScrubber.scrub(_ event:)` drops (returns `nil` for) AppHang events whose
stack matches the AccessibilitySettingsLoader/`NSBundle` stall above, while
behaving exactly as today for every other event. The drop is fail-open: any
under-specified or unrecognised input reports the event rather than losing it.

Correctness is verified by a unit test that feeds a synthetic `Event` built from
the verbatim captured stack and asserts the drop, plus the precedent's fail-open
family (renamed mechanism, missing stacktrace, empty frames, partial signature,
app frame inside the blocked chain, missing `package`). Verified with
`make test-unit` (fast) then `./scripts/test.sh` (gate).

## Patterns to Follow

**Adopt (from SingleThread VAR-1165):**

- Frame reduction reads only `Frame.package` and `Frame.inApp`; function names
  are server-side-only in `beforeSend`
  (`SingleThread/SingleThread/SentryScrubber.swift:26-28,99-104`). Match on
  binary-image path substrings, never on function names.
- `struct StackFrameSignature: Equatable { image: String; isApp: Bool }`, built
  by an `init(_ frame: Frame)` extension: `image = frame.package ?? ""`,
  `isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")`
  (`SingleThread/.../SentryScrubber.swift:11-16,99-104`).
- Predicate shape (`SingleThread/.../SentryScrubber.swift:41-53`): `guard
  mechanismType == "AppHang"`, `guard !frames.isEmpty`, every signature image
  present as a substring, then no `.isApp` frame at/deeper than the first
  signature-image frame. Fail-open on every guard.
- `appHangStack(in:)` selects the first exception whose `mechanism?.type ==
  "AppHang"` with a non-empty stacktrace
  (`SingleThread/.../SentryScrubber.swift:57-68`).
- Run the drop check at the very top of `scrub(_ event:)`, before any PII
  scrubbing (`SingleThread/.../SentryScrubber.swift:70-77`).
- Keep Sentry imports confined to `SentryBootstrap.swift` and
  `SentryScrubber.swift`; `SentryConfiguration.swift` stays Sentry-free
  (`SentryConfiguration.swift:3-4`, `SentryBootstrap.swift:5-6`).
- Test conventions: Swift Testing `@Test`/`#expect`, inline `Event()` construction,
  a verbatim `(image, inApp)` tuple array + a `hangEvent(frames:mechanismType:)`
  builder, and `keeps...When...` names for the fail-open family
  (`SingleThreadTests/SentryScrubberTests.swift:85-201`). `Frame.inApp` is an
  SDK-mandated `NSNumber`, built behind
  `// swiftlint:disable:next legacy_objc_type`
  (`SingleThreadTests/SentryScrubberTests.swift:193-195`).
- `SentryScrubber` remains an app-internal `enum` with `nonisolated static`
  members (`CheckStitch/SentryScrubber.swift:12-16,32`); tests reach it via
  `@testable import CheckStitch`. Warnings-as-errors applies to this target.

**Do NOT follow:**

- Do not copy SingleThread's breadcrumb scrub, which drops `breadcrumb.type`;
  CheckStitch deliberately preserves it (`CheckStitch/SentryScrubber.swift:35`).
- Do not read `event.threads`; no code in either repo does, and the hang data
  lives in `exceptions[].stacktrace` (research Q3).
- Do not add a new app file importing Sentry (keeps the two-file invariant).

## Design Decisions

1. **Containment point**: drop inside `SentryScrubber.scrub(_ event:) -> Event?`
   at the top, returning `nil` — the shared `beforeSend` privacy path named by
   the task, mirroring the precedent's placement.
2. **Signature images**: `systemStallSignatureImages = ["AccessibilitySettingsLoader"]`
   (one distinctive binary). `Foundation`/`libsystem_kernel.dylib` are
   near-universal, add no specificity, and would miss variant stacks; the
   AppHang mechanism guard plus app-frame-position guard carry the safety.
3. **Predicate shape**: port `isSystemStall(mechanismType:frames:)` verbatim from
   `SingleThread/.../SentryScrubber.swift:41-53` (all signature images present +
   no app frame at/deeper than the first stall frame), fail-open.
4. **Stack extraction**: port `appHangStack(in:)`
   (`SingleThread/.../SentryScrubber.swift:57-68`) to pull
   `mechanismType`/frames from the first AppHang exception.
5. **Drop semantics**: return `nil` (whole-event drop) only when
   `isSystemStall` is true; otherwise fall through to the existing scrub body
   unchanged. Matches the task's "drop this class of system-stall hang".
6. **Scope**: only this stall. Do **not** port the BackBoardServices/libxpc
   signature — CheckStitch has no report of it, and shipping untested signatures
   violates the unit-test policy and drifts from precedent.
7. **Code placement**: extend `CheckStitch/SentryScrubber.swift`; mirror the
   precedent's structure in the same file rather than adding a
   `SentryHangFilter.swift` (keeps the two-file Sentry-import invariant and the
   minimal diff).
8. **Observability**: silently `return nil`, as in the precedent
   (`SingleThread/.../SentryScrubber.swift:74-77`). No `os_log`, no counter; the
   unit test is the evidence.
9. **Test fixture**: reproduce the verbatim captured `(image, inApp)` tuple
   array from the Linear stack plus a `hangEvent(frames:mechanismType:)` builder,
   mirroring `SingleThreadTests/SentryScrubberTests.swift:151-201`, and port the
   full fail-open family adapted to this stall. Fixture file is
   `CheckStitchTests/SentryScrubberTests.swift` (new-file project.pbxproj edits
   are not needed; target membership is synchronized).

## What We're NOT Doing

- Not porting or re-testing the SingleThread BackBoardServices/libxpc signature.
- Not generalizing the denylist into a list-of-signature-sets (OR across stalls);
  one flat `[String]` list, as precedent.
- Not touching breadcrumb scrubbing, `contexts`, `allowedTags`, or any other
  field handling in `SentryScrubber`.
- Not changing `SentryBootstrap` options (app-hang tracking stays on), the DSN,
  environment, opt-in preference, or `CheckStitchCore`.
- Not modifying the SingleThread repo.
- Not adding telemetry/logging for dropped events.
- Not adding a new Sentry-importing file or files, and no changes to
  `project.pbxproj`.
- Not filing child tickets or contacting Sentry/Apple; containment only.

## Open Risks

- **`threads` vs `exceptions`**: sentry-cocoa populates both for AppHang, but the
  scrubber only reads `exceptions[].stacktrace`. If a future SDK version moves
  the blocked stack solely into `event.threads`, the drop silently stops firing
  (fail-open: event reports, no data loss). No code reads `threads` today.
- **`package` absent**: if sentry-cocoa omits `Frame.package` on the relevant
  frames, the signature never matches and the event is kept (fail-open by
  design). The precedent accepts the same limitation.
- **Over-drop edge case**: a genuine app-caused hang that happens to include an
  AccessibilitySettingsLoader frame with no deeper app frame would be dropped.
  Judged unlikely, and the app-frame-position guard is the primary defence.
- **`inApp` fallback**: relying on `image.contains(".app/")` in addition to
  `frame.inApp` mirrors precedent; the captured stack marks app frames `In app`,
  so both should hold.
- **No captured in-repo stack artifact**: the stack currently lives only in the
  Linear ticket; the test fixture copies it verbatim, so future SDK/report format
  drift would surface as a fixture mismatch rather than silent over-dropping.
- **`isSystemStall` is `nonisolated static` and pure**; no concurrency risk
  expected, but the test suite must stay a plain Swift Testing suite (no
  `@MainActor` needed unless it touches EventKit/view model).
