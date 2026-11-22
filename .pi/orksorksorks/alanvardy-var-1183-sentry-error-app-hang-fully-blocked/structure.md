# Structure Outline

## Approach

Contain the `App Hang Fully Blocked` system stall at the existing `beforeSend`
seam: extend `CheckStitch/SentryScrubber.swift` with a fail-open predicate that
drops (returns `nil`) AppHang events whose frames match the verbatim captured
AccessibilitySettingsLoader/`NSBundle` stack, leaving every other event's
scrubbing unchanged. Ported from the SingleThread VAR-1165 precedent; signature
matching uses binary-image substrings only (`Frame.package` + `Frame.inApp`).

Two slices. Slice 1 is the walking skeleton (types → extraction → predicate →
drop → test). Slice 2 is the fail-open hardening guarantee and the full gate.
There is no horizontal prerequisite phase: no schema, no new file, no
`project.pbxproj` edit, no Sentry-import change.

---

## Phase 1: Walking skeleton — drop the captured system stall end to end

**Outcome**: The real VAR-1183 AppHang event (verbatim captured stack) no longer
reaches Sentry; a unit test builds a synthetic `Event` from that exact stack,
runs it through the production `beforeSend` entry point, and asserts the drop.
Non-hang / mismatched events still return a scrubbed event.

**Files**: `CheckStitch/SentryScrubber.swift` (predicate, extraction, drop wiring),
`CheckStitchTests/SentryScrubberTests.swift` (new AppHang tests + frame fixtures)

**Key changes**:
- `struct StackFrameSignature: Equatable { let image: String; let isApp: Bool }` — new type
- `extension StackFrameSignature { init(_ frame: Frame) }` — `image = frame.package ?? ""`; `isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")`
- `nonisolated static let systemStallSignatureImages: [String] = ["AccessibilitySettingsLoader"]` — new
- `nonisolated static func isSystemStall(mechanismType: String, frames: [StackFrameSignature]) -> Bool` — new; guards `== "AppHang"`, non-empty frames, every signature image present as a substring, then no `.isApp` frame at/deeper than the first signature-image frame
- `nonisolated static func appHangStack(in event: Event) -> (mechanismType: String, frames: [StackFrameSignature])?` — new; first AppHang exception with non-empty stacktrace
- `scrub(_ event: Event) -> Event?` — modified; drop check at the very top, before any PII scrubbing: `if let stack = appHangStack(in: event), isSystemStall(...) { return nil }`

**Contract**: `SentryScrubber.scrub(_:)` keeps its `Event?` signature and its
existing scrub body; `StackFrameSignature`, `isSystemStall`, `appHangStack` and
`systemStallSignatureImages` are the app-internal seam the tests reach via
`@testable import CheckStitch`. Slice 2 depends only on these names, not on
their internals.

**Tests** (in `CheckStitchTests/SentryScrubberTests.swift`, Swift Testing):
- `dropsCapturedGuidedAccessSystemStall` — verbatim captured `(image, inApp)`
  tuple array + `hangEvent(frames:mechanismType:)` builder; `#expect(... == nil)`
- `keepsHangWithAppFrameInBlockedChain` — app frame inside the blocked chain
  survives (`!= nil`) — the sad path that proves the app-frame-position guard

**Verify**: `make test-unit` green (fast, macOS, no signing). No live/manual
check — the fixture is the evidence; Sentry intake is not observable from CI.

---

## Phase 2: Fail-open hardening — never lose a report

**Outcome**: Under-specified or unrecognised input is reported rather than
dropped. A renamed mechanism, missing stacktrace, empty frames, partial
signature, missing `package`, and a non-AppHang event all survive; a kept
AppHang event still gets the full PII scrub (proving the drop check did not
displace the existing body). Gate green.

**Files**: `CheckStitchTests/SentryScrubberTests.swift` (fail-open family + PII
co-assertion; no production change expected — this slice is the evidence that
Phase 1's guards are fail-open)

**Key changes**:
- No production signature changes. If a fail-open test fails, the fix is inside
  Phase 1's guards (return `false`/`nil`), never a widened signature.
- Reuses Phase 1's `hangEvent(frames:mechanismType:)` builder with
  `mechanismType` overrides and mutated `package`/frame lists.

**Contract**: none new — this slice consumes Phase 1's documented fail-open
behaviour and pins it.

**Tests**:
- `keepsEventWhenMechanismRenamed`
- `keepsEventWhenStacktraceMissing`
- `keepsEventWhenFrameListEmpty`
- `keepsEventWhenSignaturePartiallyMatches`
- `keepsEventWhenFramePackageIsMissing`
- `keepsNonHangEventWithStallFrames`
- `keepsStallLikeEventWhenAppFramePresent` / `scrubsKeptEventStill` — asserts a
  kept event returns non-nil **and** its `exceptions[].value`/`user` are nulled
- Existing `CheckStitchTests/SentryScrubberTests.swift` PII tests
  (`CheckStitchTests/SentryConfigurationTests.swift` unaffected)

**Verify**: `make test-unit` green for the fail-open family; then
`./scripts/test.sh` prints `gate: ok` (simulator build → test → `build-mac` →
`watch-build` → `widget-build` → shell tests → shellcheck). No production
behaviour outside `SentryScrubber.scrub` may change.

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` green — captured stall dropped, app frame
  in blocked chain kept. Do not start Phase 2 otherwise.
- **After Phase 2**: `make test-unit` green for the full fail-open family;
  `./scripts/test.sh` `gate: ok`. Then the feature is shippable on its own.

## Notes / Non-Vertical Work

- No horizontal phase needed — no migration, no schema, no cross-cutting
  refactor, no new Sentry-importing file, no `project.pbxproj` change.
- Slice 2 is hardening, deliberately kept out of Slice 1, per the workflow.
- Scope stays one stall: the SingleThread BackBoardServices/libxpc signature is
  **not** ported (no CheckStitch report of it; would ship an untested signature).
