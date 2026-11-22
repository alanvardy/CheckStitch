# Implementation Plan

## Overview

Extend `CheckStitch/SentryScrubber.swift` with a fail-open `beforeSend` predicate
that drops (returns `nil` for) AppHang events whose captured stack matches the
AccessibilitySettingsLoader / `NSBundle` system stall (Sentry issue 7849871699),
leaving every other event's scrubbing unchanged. Ported from the SingleThread
VAR-1165 precedent but with a signature re-derived for this stall. Two vertical
slices: the walking skeleton, then the fail-open hardening + full gate.

## Phase 1: Walking skeleton — drop the captured system stall end to end

**Outcome**: The real VAR-1183 AppHang stack no longer reaches Sentry; a unit
test builds a synthetic `Event` from the captured stack, runs it through the
production `scrub(_ event:)` entry point, and asserts the drop. Non-hang /
mismatched events still return a scrubbed event.

### Changes

#### 1. Add frame signature type + reducer to `SentryScrubber`
**File**: `CheckStitch/SentryScrubber.swift`
**Action**: modify

Add the nested type at the top of `enum SentryScrubber`, mirroring
`SingleThread/SingleThread/SentryScrubber.swift:11-16`. Note CheckStitch already
has `allowedTags` and both `scrub` overloads — do not touch those field lists.

```swift
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
    // ... existing content unchanged ...
```

#### 2. Add the signature image, predicate and extractor
**File**: `CheckStitch/SentryScrubber.swift`
**Action**: modify

Insert after `allowedTags` (before the existing `scrub(_ event:)`).
`isSystemStall` and `appHangStack` are ported verbatim from
`SingleThread/SingleThread/SentryScrubber.swift:41-68`, with only the denylist
value changed from `["BackBoardServices", "libxpc.dylib"]` to this stall's one
distinctive binary.

```swift
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
    /// so the event is reported rather than silently lost.
    ///
    /// All three conditions must hold:
    ///  1. the mechanism is the public, stable `"AppHang"` marker,
    ///  2. the stack contains every image in `systemStallSignatureImages`,
    ///  3. no in-app frame sits at or deeper than the first stall frame.
    nonisolated static func isSystemStall(
        mechanismType: String?,
        frames: [StackFrameSignature]) -> Bool {
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
```

#### 3. Wire the drop at the top of `scrub(_ event:)`
**File**: `CheckStitch/SentryScrubber.swift`
**Action**: modify

Add the drop check as the first statement of the existing `scrub(_ event:)`
body. Everything below it (existing PII scrubbing, `breadcrumb.type` preservation)
stays byte-for-byte as today.

```swift
    nonisolated static func scrub(_ event: Event) -> Event? {
        if let stack = appHangStack(in: event),
           isSystemStall(mechanismType: stack.mechanismType, frames: stack.frames) {
            return nil
        }
        event.user = nil
        event.extra = nil
        // ... existing body unchanged ...
        return event
    }
```

#### 4. Add the `Frame` → `StackFrameSignature` initializer
**File**: `CheckStitch/SentryScrubber.swift`
**Action**: modify

Append at end of file, after the closing `}` of `enum SentryScrubber`
(verbatim from `SingleThread/SingleThread/SentryScrubber.swift:99-104`):

```swift
extension SentryScrubber.StackFrameSignature {
    nonisolated init(_ frame: Frame) {
        let image = frame.package ?? ""
        self.image = image
        isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")
    }
}
```

#### 5. Add the AppHang fixtures + skeleton tests
**File**: `CheckStitchTests/SentryScrubberTests.swift`
**Action**: modify

Append after the last existing `@Test` (before the final `}`), mirroring
`SingleThreadTests/SentryScrubberTests.swift:85-201`. No `project.pbxproj` edit
— test target membership is synchronized. The suite stays a plain Swift Testing
`struct` (no `@MainActor`; it does not touch EventKit or the view model).

```swift
    // MARK: App-hang system-stall predicate

    @Test
    func dropsCapturedGuidedAccessSystemStall() {
        #expect(SentryScrubber.scrub(hangEvent(frames: Self.capturedFrames)) == nil)
    }

    @Test
    func keepsHangWithAppFrameInBlockedChain() {
        var frames = Self.capturedFrames
        frames[frames.count - 1] = (Self.appImage, true) // app is the blocked (deepest) frame
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    // MARK: Fixtures

    private static let appImage =
        "/private/var/containers/Bundle/Application/277152F6-B99C-4FA0-BADB-098D8D06EC13/CheckStitch.app/CheckStitch"
    private static let swiftUI = "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
    private static let uiKit = "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"
    private static let graphicsServices =
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices"
    private static let coreFoundation =
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    private static let accessibilitySettingsLoader =
        "/System/Library/AccessibilityBundles/AccessibilitySettingsLoader.bundle/AccessibilitySettingsLoader"
    private static let libDispatch = "/usr/lib/system/libdispatch.dylib"
    private static let foundation = "/System/Library/Frameworks/Foundation.framework/Foundation"
    private static let libSystemKernel = "/usr/lib/system/libsystem_kernel.dylib"

    /// The VAR-1183 event's client-side exception stack (`package` + `in_app`),
    /// outermost → innermost, as captured in the Linear ticket (`design.md`).
    /// The only in-app frame is `MyApp.$main`; `AccessibilitySettingsLoader` is
    /// the signature frame and has only system frames at/deeper than it.
    private static let capturedFrames: [(image: String, inApp: Bool)] = [
        ("dyld", false),
        (appImage, true),
        (swiftUI, false),
        (uiKit, false),
        (graphicsServices, false),
        (coreFoundation, false),
        (accessibilitySettingsLoader, false),
        (libDispatch, false),
        (foundation, false),
        (libSystemKernel, false)
    ]

    private func hangEvent(
        frames: [(image: String, inApp: Bool)],
        mechanismType: String = "AppHang") -> Event {
        let event = Event()
        let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: mechanismType)
        exception.stacktrace = SentryStacktrace(frames: frames.map { frame in
            let sentryFrame = Frame()
            sentryFrame.package = frame.image
            // Sentry's `Frame.inApp` is SDK-mandated NSNumber.
            // swiftlint:disable:next legacy_objc_type
            sentryFrame.inApp = NSNumber(value: frame.inApp)
            return sentryFrame
        }, registers: [:])
        event.exceptions = [exception]
        return event
    }
```

> Fixture note: the ticket stack exists only in Linear; `design.md` is the
> in-repo transcription of it. The tuple array above reproduces that
> outermost→innermost image list verbatim, with the app frame marked `In app`.
> The signature frame `AccessibilitySettingsLoader` sits at index 6 with only
> system frames after it, so the drop fires. If the real capture later shows
> repeated frames or a different `inApp`, update the tuple array — the tests are
> the fixture contract.

### Verification

#### Automated
- [x] `make test-unit` passes with `dropsCapturedGuidedAccessSystemStall` and
      `keepsHangWithAppFrameInBlockedChain` green, and all pre-existing
      `SentryScrubberTests` / `SentryConfigurationTests` still green.
- [x] Confirm the new production symbols compile under warnings-as-errors:
      `make build-mac` passes (`Frame.inApp` NSNumber cast is explicit).

#### Manual
- [ ] None. The captured-stack fixture is the evidence; Sentry intake is not
      observable from CI and there is no runtime repro on demand.

---

## Phase 2: Fail-open hardening — never lose a report

**Outcome**: Under-specified or unrecognised input is reported rather than
dropped. A renamed mechanism, missing stacktrace, empty frame list, partial
signature, missing `package`, and a non-AppHang event all survive; a kept event
still gets the full PII scrub (proving the drop check did not displace the
existing body). Full gate green.

### Changes

#### 1. Add the fail-open test family
**File**: `CheckStitchTests/SentryScrubberTests.swift`
**Action**: modify

Append to the same `// MARK:` region added in Phase 1, reusing the existing
`hangEvent(frames:mechanismType:)` builder and static frame fixtures. Names are
copied from `SingleThreadTests/SentryScrubberTests.swift:109-148` and adapted to
this stall's signature image.

```swift
    // MARK: Fail-open guarantee

    @Test
    func keepsEventWhenMechanismRenamed() {
        #expect(SentryScrubber.scrub(hangEvent(
            frames: Self.capturedFrames, mechanismType: "AppHangRenamed")) != nil)
    }

    @Test
    func keepsEventWhenStacktraceMissing() {
        let event = Event()
        let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]
        #expect(SentryScrubber.scrub(event) != nil)
    }

    @Test
    func keepsEventWhenFrameListEmpty() {
        #expect(SentryScrubber.scrub(hangEvent(frames: [])) != nil)
    }

    @Test
    func keepsEventWhenSignaturePartiallyMatches() {
        // AccessibilitySettingsLoader absent ⇒ not the Guided Access stall.
        let frames = Self.capturedFrames.filter {
            $0.image != Self.accessibilitySettingsLoader
        }
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    @Test
    func keepsEventWhenFramePackageIsMissing() {
        let frames = Self.capturedFrames.map { (image: "", inApp: $0.inApp) }
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    @Test
    func keepsNonHangEventWithStallFrames() {
        let event = hangEvent(frames: Self.capturedFrames, mechanismType: "Crash")
        event.extra = ["reminderTitle": "Buy milk"]
        let scrubbed = SentryScrubber.scrub(event)
        #expect(scrubbed != nil) // not dropped
        #expect(scrubbed?.extra == nil) // PII scrubbing still runs
    }

    @Test
    func keepsStallLikeEventWhenAppFramePresent() {
        var frames = Self.capturedFrames
        frames.insert((Self.appImage, true), at: 7) // app frame just past the stall frame
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    @Test
    func scrubsKeptEventStill() {
        var frames = Self.capturedFrames
        frames.insert((Self.appImage, true), at: 7)
        let event = hangEvent(frames: frames)
        event.exceptions?[0].value = "Buy milk from the Grocery list"
        event.user = User(userId: "Buy milk")
        let scrubbed = SentryScrubber.scrub(event)
        #expect(scrubbed != nil)
        #expect(scrubbed?.exceptions?.first?.value == nil)
        #expect(scrubbed?.user == nil)
    }
```

#### 2. No production change expected
**File**: n/a
**Action**: none

If a fail-open test fails, the fix is inside Phase 1's guards (they must return
`false`/`nil` for the under-specified input), never a widened signature. Do not
add `@MainActor`, imports, or new files.

### Verification

#### Automated
- [x] `make test-unit` passes with the full fail-open family green plus the
      Phase 1 tests.
- [x] `./scripts/test.sh` prints `gate: ok` (simulator build → pre-boot →
      `make test` → `make build-mac` → `make watch-build` → `make widget-build` →
      `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh
      ci_scripts/*.sh`).
- [x] `git diff --stat` shows changes confined to
      `CheckStitch/SentryScrubber.swift` and
      `CheckStitchTests/SentryScrubberTests.swift` (no `project.pbxproj`, no
      `SentryBootstrap`, no new Sentry-importing file).

#### Manual
- [ ] None required. No production behaviour outside
      `SentryScrubber.scrub(_ event:)` may change; the gate + diff check confirm
      the two-file blast radius.

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` green — captured stall dropped, app frame
  in blocked chain kept. Do not start Phase 2 otherwise.
- **After Phase 2**: `make test-unit` green for the full fail-open family;
  `./scripts/test.sh` prints `gate: ok`. Feature is shippable on its own.

## Notes / Deviations from `structure.md`

- No deviations in phase order or scope. The single signature image
  (`AccessibilitySettingsLoader`) and fail-open predicate shape are exactly as
  `structure.md` specifies; the BackBoardServices/libxpc signature is
  deliberately not ported.
- `structure.md` lists both `keepsStallLikeEventWhenAppFramePresent` and
  `scrubsKeptEventStill` under Phase 2. They are implemented as two distinct
  tests (presence guard vs. continued PII scrub) to keep the assertions single
  purpose, matching the precedent's one-concern-per-test style.
- The fixture tuple array is transcribed from `design.md`'s captured-frame list
  (the only in-repo copy of the VAR-1183 stack); marked as a fixture-contract
  note in Phase 1.
- No schema, migration, codegen, or `project.pbxproj` step exists in this work.
