# Implementation Plan

## Overview

Add a pure `ChecklistLayout` policy seam in Core plus a `DuoDisplay`
machine-identifier mapping, and feed a `Context` (resolved app-side from `uname`
+ size classes) into the three `ContentView` content sites so the checklist
column uses `min(340, viewportWidth * 0.8)` and a 16 pt gutter **only** on the
iPhone Duo outer display in portrait; every other device/screen/orientation
stays pixel-for-pixel on `min(340, 0.6W)` with a 32 pt gutter.

---

## Phase 1: Walking skeleton — Duo-outer card widens end to end

One real device signal (`uname` + size classes) → Core policy → the checklist
card's cap and gutter, with the badge-standard values everywhere else. Green
tests prove the policy math and the identifier mapping; both Xcode platform legs
prove the detector compiles.

### Changes

#### 1. `ChecklistLayout` policy seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift`
**Action**: create

Plain-value `Context` (mirrors `OrientationPolicy`'s cross-platform shape),
`nonisolated public static` math callable from the `MainActor` app target
(mirrors `ChecklistWidth`). The default branch **delegates** to `ChecklistWidth`
so the two cannot drift; the Duo branch is `min(340, viewportWidth * 0.8)`.

```swift
import CoreGraphics

/// Layout policy for the checklist content column, scoped to the iPhone Duo
/// outer screen. Mirrors `OrientationPolicy`: a plain, cross-platform value
/// (`Context`) plus pure math, with the platform value injected by the caller.
///
/// `nonisolated` keeps the pure math callable outside the app target's
/// `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`), like `ChecklistWidth`.
public enum ChecklistLayout {
    /// The screen context the layout should adapt to. `isDuoOuterPortrait` is
    /// false on every non-Duo device, every other Duo screen, and every other
    /// orientation, which resolves to the existing `.standard` behaviour.
    public struct Context: Equatable, Sendable {
        public let isDuoOuterPortrait: Bool

        public init(isDuoOuterPortrait: Bool) {
            self.isDuoOuterPortrait = isDuoOuterPortrait
        }

        public static let standard = Context(isDuoOuterPortrait: false)
    }

    /// Single home of the two gutter values — never copy these literals.
    nonisolated public static let defaultHorizontalInset: CGFloat = 32
    nonisolated public static let duoOuterHorizontalInset: CGFloat = 16

    /// Outer gutter applied outside the width cap. Halved on the Duo outer
    /// screen so the reclaimed space widens the visible card.
    nonisolated public static func horizontalInset(_ context: Context) -> CGFloat {
        context.isDuoOuterPortrait ? duoOuterHorizontalInset : defaultHorizontalInset
    }

    /// Viewport-relative cap for the list card and iOS header row. The default
    /// path delegates to `ChecklistWidth.maxContentWidth` so the two stay in
    /// lockstep; the Duo path halves the fractional side gap (20 % → 10 % per
    /// side) while keeping the same 340 ceiling.
    nonisolated public static func maxContentWidth(
        viewportWidth: CGFloat,
        context: Context
    ) -> CGFloat {
        context.isDuoOuterPortrait
            ? min(340, viewportWidth * 0.8)
            : ChecklistWidth.maxContentWidth(viewportWidth: viewportWidth)
    }
}
```

> Compiler note: if `nonisolated public static let` is rejected on the stored
> constants under the app's default isolation, make them computed
> (`nonisolated public static var defaultHorizontalInset: CGFloat { 32 }`);
> the value and the tests are unchanged.

#### 2. Duo device-identifier mapping
**File**: `CheckStitchCore/Sources/CheckStitchCore/DuoDisplay.swift`
**Action**: create

The identifier set is the single maintenance point as new Duo variants appear.
The size-class pair is the scoping that excludes the inner display
(regular × regular) and outer landscape (compact × compact).

```swift
/// Pure mapping from a device machine identifier plus size classes to the
/// "Duo outer display in portrait" condition. No UIKit, no `@available` —
/// unit-testable on the macOS-hosted suite.
public enum DuoDisplay {
    /// Model identifiers (`hw.machine`) of iPhones whose outer/cover display
    /// reports compact width × regular height in portrait. Single maintenance
    /// point — add new Duo variants here.
    nonisolated public static let outerPortraitMachines: Set<String> = ["iPhone19,4"]

    nonisolated public static func isOuterPortrait(
        machine: String,
        isCompactWidth: Bool,
        isRegularHeight: Bool
    ) -> Bool {
        outerPortraitMachines.contains(machine)
            && isCompactWidth
            && isRegularHeight
    }
}
```

#### 3. App-side detector
**File**: `CheckStitch/DuoOuterPortrait.swift`
**Action**: create

Thin app-target helper (views + platform delegates layer): reads the machine
identifier and turns the two size classes into a `ChecklistLayout.Context`.
`uname` returns the host arch in the iOS simulator, so the Duo branch never
activates there — that is accepted (design decision 4); the real mapping is
unit-tested via `DuoDisplay`'s injected inputs.

```swift
import CheckStitchCore
import SwiftUI
#if os(iOS)
    import Darwin
#endif

/// Resolves the layout context for the iPhone Duo outer screen. The decision
/// logic lives in `CheckStitchCore.DuoDisplay`; this only supplies the platform
/// values.
enum DuoOuterPortrait {
    /// Device model identifier (`hw.machine`), e.g. `"iPhone19,4"`. Read once.
    /// On macOS and in the iOS Simulator it is not the Duo model, so the
    /// detector resolves to the standard context.
    static let machineIdentifier: String = {
        #if os(iOS)
            var info = utsname()
            guard uname(&info) == 0 else { return "" }
            return withUnsafeBytes(of: &info.machine) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
        #else
            return ""
        #endif
    }()

    static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        machine: String = machineIdentifier
    ) -> ChecklistLayout.Context {
        ChecklistLayout.Context(
            isDuoOuterPortrait: DuoDisplay.isOuterPortrait(
                machine: machine,
                isCompactWidth: horizontal == .compact,
                isRegularHeight: vertical == .regular))
    }
}
```

New files under the synchronized root groups need no `project.pbxproj` edit.

#### 4. Wire the context into the list card
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add the two size-class environment reads and one computed context beside the
existing `colorScheme` read (after line 15):

```swift
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
```

Add the derived context near the other private members (e.g. just above
`private var checklistList`):

```swift
    /// Layout context for the Duo outer screen in portrait; `.standard`
    /// everywhere else.
    private var layoutContext: ChecklistLayout.Context {
        DuoOuterPortrait.context(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }
```

Change the card frame/padding (currently `ContentView.swift:512` and `:523`):

```swift
                    .frame(maxWidth: ChecklistLayout.maxContentWidth(
                        viewportWidth: geometry.size.width, context: layoutContext))
                    // …plate background/overlay unchanged…
                    .padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))
```

(`geometry` is in scope inside the `GeometryReader` at `:457`.)

#### 5. Core test suites
**Files**:
- `CheckStitchTests/ChecklistLayoutTests.swift` (create)
- `CheckStitchTests/DuoDisplayTests.swift` (create)

Both are pure-core suites: plain `struct`, no `@MainActor`, `@testable import
CheckStitchCore` (mirror `ChecklistWidthTests.swift`). No `project.pbxproj` edit.

```swift
// ChecklistLayoutTests.swift
@testable import CheckStitchCore
import CoreGraphics
import Testing

struct ChecklistLayoutTests {
    @Test
    func defaultContextKeepsTheStandardGutter() {
        #expect(ChecklistLayout.horizontalInset(.standard) == 32)
    }

    @Test
    func duoOuterContextHalvesTheGutter() {
        #expect(ChecklistLayout.horizontalInset(.init(isDuoOuterPortrait: true)) == 16)
    }

    /// Anti-drift: the default path delegates to `ChecklistWidth`, never
    /// re-deriving the 0.6 fraction.
    @Test(arguments: [10.0, 200.0, 340.0, 566.0, 567.0, 1000.0, 1500.0] as [CGFloat])
    func defaultWidthMatchesChecklistWidth(width: CGFloat) {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: width, context: .standard)
            == ChecklistWidth.maxContentWidth(viewportWidth: width))
    }

    @Test
    func duoOuterWidthUsesTheLargerFractionBelowTheCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 200, context: .init(isDuoOuterPortrait: true)) == 160)
    }

    @Test
    func duoOuterWidthClampsAtCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 466, context: .init(isDuoOuterPortrait: true)) == 340)
    }

    @Test
    func duoOuterWidthHitsCeilingAtBoundary() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 340 / 0.8, context: .init(isDuoOuterPortrait: true)) == 340)
    }
}
```

```swift
// DuoDisplayTests.swift
@testable import CheckStitchCore
import Testing

struct DuoDisplayTests {
    @Test
    func knownMachineInOuterPortraitIsRecognised() {
        #expect(DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: true))
    }

    @Test
    func knownMachineWithRegularWidthIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: false, isRegularHeight: true))
    }

    @Test
    func knownMachineWithCompactHeightIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: false))
    }

    @Test
    func otherMachinesAreNeverRecognised() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone17,1", isCompactWidth: true, isRegularHeight: true))
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "", isCompactWidth: true, isRegularHeight: true))
    }
}
```

`CheckStitchTests/ChecklistWidthTests.swift` stays untouched (regression pin).

### Verification

#### Automated
- [x] `make test-unit` green, including the two new suites and the untouched `ChecklistWidthTests`
- [x] `make build` green (iOS simulator leg — `uname`/`Darwin` `#if os(iOS)` branch)
- [x] `make build-mac` green (macOS leg — `#else return ""` branch; warnings-as-errors proves the split compiles)

#### Manual
- [ ] On a real iPhone Duo outer display in portrait, the checklist card is visibly wider than before (cap uses the 0.8 fraction; gutter is 16).
- [ ] On every other device/simulator/orientation the card width and gutter are unchanged. (Not runnable in the gate: the simulator reports the host arch; accepted risk, to be stated in the PR.)

---

## Phase 2: The whole content column uses the shared width — header row + empty state

The iOS edit-toggle header row and the no-checklists empty-state card adopt the
same `Context`-driven cap/inset, so the header aligns to the widened card and
the empty state widens by the same gutter. Every literal `32` disappears from
`ContentView.swift`, pinned by a source-level regression check.

### Changes

#### 1. Header row
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Currently `:495` (frame) and `:496` (padding), inside the `#if os(iOS)` block:

```swift
                        .frame(maxWidth: ChecklistLayout.maxContentWidth(
                            viewportWidth: geometry.size.width, context: layoutContext))
                        .padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))
                        .padding(.bottom, 8)
```

#### 2. Empty-state card
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Currently `:749` (`.padding(.horizontal, 32)` inside `emptyState`); it gains no
width cap (it has none today, design decision 7), only the shared inset:

```swift
            .padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))
            .padding(.top, 80)
```

`layoutContext` is a member of `ContentView`, so it resolves in `emptyState`
without a `GeometryReader`.

#### 3. Source-scan regression pin
**File**: `scripts/tests/run.sh`
**Action**: modify

Add a case proving no literal content gutter or inlined fraction returns to
`ContentView.swift`. Place it in its own section, mirroring the
`documentTypeRegistrationWiresInfoPlist` shape (`grep -q … || return 1` +
`run_case`).

```bash
# --- shared-width seam ------------------------------------------------------

# `ChecklistLayout` must be the only source of the 32/16 content gutter; a
# re-introduced literal would silently reopen the regression this ticket fixes.
# The Duo branch itself is proven by `ChecklistLayoutTests`.
contentViewHasNoLiteralContentGutter() {
    if grep -q '\.padding(\.horizontal, 32)' CheckStitch/ContentView.swift; then return 1; fi
    # Regression guard: the default fraction lives in Core, never inline here.
    ! grep -q 'viewportWidth: geometry.size.width \* 0.6' CheckStitch/ContentView.swift
}

run_case contentViewHasNoLiteralContentGutter contentViewHasNoLiteralContentGutter
```

#### 4. `ViewRenderTests` empty-state canary — **not added**

Structure marked this optional. `emptyState` is a private member requiring the
full `ContentView` environment graph (seven injected view models + stores), so a
canary would add a large fixture for no coverage beyond the literal-scan pin and
`ChecklistLayoutTests`. Resolved: omitted.

### Verification

#### Automated
- [x] `make test-unit` green (no render regression; `ChecklistLayoutTests` already pin every value used here)
- [x] `bash scripts/tests/run.sh` green, including the new `contentViewHasNoLiteralContentGutter` case
- [x] `make build` green

#### Manual
- [ ] On a real Duo outer display in portrait, the edit-toggle header row and the empty-state card share the widened card's column edges (16 pt gutter).
- [ ] On other devices the header row still aligns with the card.

---

## Phase 3: Hardening — prove the scoping can't over- or under-fire

No new user-visible behaviour. Closes the two silent-failure modes (a wrong
identifier disables the feature; a wrong size-class check widens a normal
iPhone) and records the un-executable device path as a stated risk.

### Changes

#### 1. `ChecklistLayout` documentation + boundary pins
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift`
**Action**: modify (doc comments only)

Extend the doc comments: `425` is the exact `340 / 0.8` crossover; macOS/watch/
other targets always resolve to `.standard` (the detector lives in the iOS-only
app target).

#### 2. `ChecklistLayoutTests` boundary + equivalence expansion
**File**: `CheckStitchTests/ChecklistLayoutTests.swift`
**Action**: modify

Replace the Phase-1 `defaultWidthMatchesChecklistWidth` argument list with the
full `10…1500` sweep and add the documented boundaries:

```swift
    /// Anti-drift across the whole domain: default never diverges from
    /// `ChecklistWidth`.
    @Test(arguments: Array(stride(from: 10.0, through: 1500.0, by: 10.0)) as [CGFloat])
    func defaultWidthMatchesChecklistWidthAcrossTheDomain(width: CGFloat) {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: width, context: .standard)
            == ChecklistWidth.maxContentWidth(viewportWidth: width))
    }

    /// 425 is the exact 340/0.8 crossover; below it the fraction is active.
    @Test
    func duoOuterWidthBoundaryIs425() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 425, context: duo) == 340)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 424.9, context: duo) < 340)
    }

    /// A ~382 pt safe-area-adjusted read (design risk) yields 0.8 × 382 = 305.6.
    @Test
    func duoOuterWidthAtSafeAreaAdjusted382() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 382, context: duo) == 305.6)
    }
```

> If `382 * 0.8` and the `305.6` literal disagree by one ULP on the runner,
> compare with `abs(actual - 305.6) < 0.0001`.

#### 3. `DuoDisplay` documentation + exhaustiveness
**File**: `CheckStitchCore/Sources/CheckStitchCore/DuoDisplay.swift`
**Action**: modify (doc comment only)

Note the identifier list is the single maintenance point and that the size-class
pair is what excludes the inner display / outer landscape.

#### 4. `DuoDisplayTests` exhaustive matrix
**File**: `CheckStitchTests/DuoDisplayTests.swift`
**Action**: modify

Add the full four-combination matrix for a known and an unknown machine, and the
malformed-string fail-safe direction:

```swift
    /// Exactly one (width, height) combination fires for the known machine.
    @Test(arguments: [("iPhone19,4", true), ("iPhone17,1", false), ("", false), ("iPad13,1", false)])
    func sizeClassMatrixFiresOnlyForKnownMachine(machine: String, expected: Bool) {
        let combinations: [(Bool, Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        for (compactWidth, regularHeight) in combinations {
            let fired = DuoDisplay.isOuterPortrait(
                machine: machine, isCompactWidth: compactWidth, isRegularHeight: regularHeight)
            let isFiringCombination = compactWidth && regularHeight
            #expect(fired == (expected && isFiringCombination))
        }
    }

    /// Malformed identifiers fail safe (feature off), never on.
    @Test(arguments: ["", "iPad13,1", "iPhone19,4 ", "iPhone19,4\n", "iphone19,4"])
    func malformedMachinesAreNotOuterPortrait(machine: String) {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: machine, isCompactWidth: true, isRegularHeight: true))
    }
```

### Verification

#### Automated
- [x] `make test-unit` green (expanded `ChecklistLayoutTests` + `DuoDisplayTests`)
- [x] `./scripts/test.sh` prints `gate: ok` (runs `make build` → sim pre-boot → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` → `shellcheck`)

#### Manual
- [ ] PR body states the accepted risk: the Duo device path is unit-tested only (the simulator reports the host arch), and describes what a user should see on a real Duo outer screen in portrait (a visibly wider card and a 16 pt gutter).

---

## Traceability

| `structure.md` file | Phase | Action |
| --- | --- | --- |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift` | 1, 3 | create, then doc-only |
| `CheckStitchCore/Sources/CheckStitchCore/DuoDisplay.swift` | 1, 3 | create, then doc-only |
| `CheckStitch/DuoOuterPortrait.swift` | 1 | create |
| `CheckStitch/ContentView.swift` | 1, 2 | modify (card; header + empty state) |
| `CheckStitchTests/ChecklistLayoutTests.swift` | 1, 3 | create, then expand |
| `CheckStitchTests/DuoDisplayTests.swift` | 1, 3 | create, then expand |
| `scripts/tests/run.sh` | 2 | modify (literal-scan pin) |
| `CheckStitchTests/ViewRenderTests.swift` | 2 | not changed (optional canary omitted) |

No schema, codegen, migration, or localization changes.
