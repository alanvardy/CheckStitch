# Design Discussion

## Current State

- The main screen's content column is driven by `ChecklistWidth.maxContentWidth`
  = `min(340, viewportWidth * 0.6)` (`CheckStitchCore/Sources/CheckStitchCore/ChecklistWidth.swift:10-12`),
  called from the iOS header row (`CheckStitch/ContentView.swift:495`) and the
  list card `LazyVStack` (`ContentView.swift:512`).
- Modifier order is load-bearing: `.frame(maxWidth:)` (`:512`) then
  `.padding(.horizontal, 32)` (`:523`) places the gutter *outside* the cap, and
  the whole block is centred (`ContentView.swift:533`). The literal `32` is
  therefore outer gutter that does not change the visible card width.
- The same literal `32` also appears on the iOS header row (`:496`) and the
  empty-state card (`ChecklistContentUnavailable` at `ContentView.swift:749`).
  Inner row/folder padding is `16` (`:580`, `:667`) and nested members `24`
  (`:640`).
- On iPhone Duo the outer (folded) portrait display is **466 × 678 pt at @3x,
  compact width × regular height**; the inner display is 669 × 951,
  regular × regular. So `0.6 × 466 ≈ 280 < 340` — the **fraction term is the
  active lever** and halving the literal `32` alone would not widen the card.
  ([Sarunw](https://sarunw.com/posts/size-classes-on-iphone-duo/),
  [randyventures](https://randyventures.com/blog/iphone-duo-screen-sizes-and-layout-notes-for-developers/))
- There is **no device, size-class, or orientation input in Core**
  (`research.md` Q3): width reaches Core only as a raw `CGFloat` from the
  `GeometryReader` (`ContentView.swift:457`). `horizontalSizeClass`,
  `UIDevice`, and `@available` have zero hits repo-wide.
- Orientation lives app-side only (`OrientationPreference.swift:14-40`,
  `OrientationPolicy` `:48-63`), deliberately cross-platform and unit-testable.
- Deployment target is iOS 18.7 (`CheckStitch.xcodeproj/project.pbxproj:519`).
- Width math is pinned only in Core: `ChecklistWidthTests.swift:8,13,18,25,32`.
  No test asserts a literal padding value (`research.md` Q5).

## Desired End State

On the iPhone Duo outer screen in portrait only, the checklist content column
is visibly wider; every other device, screen, and orientation is pixel-for-pixel
unchanged. Concretely:

- The list card and iOS header row use `min(340, viewportWidth * 0.8)` instead
  of `min(340, 0.6 × viewport)` **only** when the current screen is the Duo
  outer display in portrait.
- The header row, list card, and empty-state card all use a horizontal inset of
  **16** (instead of `32`) in that same context, drawn from one shared constant.
- Off the Duo-outer-portrait context, `maxContentWidth` stays `min(340, 0.6W)`
  and the inset stays `32`, so the existing pinned tests
  (`ChecklistWidthTests`) and all other screens are untouched.

Correctness is verified by Core unit tests over the pure policy math and the
device-identifier mapping (Q8c). The behavioural outcome is not asserted by a
UI test.

## Patterns to Follow

- **Pure, `nonisolated public static` layout math in Core**, callable from the
  `MainActor` app target: `ChecklistWidth.swift:9-19`. New layout math must
  follow the same shape and live beside it.
- **Policy type that keeps platform APIs out of testable code**: `OrientationPolicy`
  (`OrientationPreference.swift:48-63`) is a cross-platform enum derived from a
  plain value, with the UIKit-only part in an `#if os(iOS)` extension. The Duo
  policy should mirror this exactly.
- **Inject the platform value as a function argument** so the pure suite can
  exercise every branch without a device (the `viewportWidth:` seam in
  `ChecklistWidth`; `OrientationPreference(defaults:key:)`).
- **Constants pinned by a direct `@expect`**: `CardPlateTests.swift:30` asserts
  `checklistTopMargin == 100` with rationale at `:6-8`; `ChecklistWidthTests`
  pins width boundaries. New constants get the same treatment.
- **No `@available` / no beta APIs**: platform differences use `#if os(...)`
  inside one file (`research.md` Q4). `uname` needs none.
- **App target is thin (views + delegates)**: device detection is a small
  app-target helper; the decision logic lives in Core.

Patterns **not** to follow:

- Do **not** read `UIScreen.main` (`research.md` Q6; Apple: ambiguous on Duo,
  and it points at the outer display even when the app is on the inner one).
- Do **not** key the behaviour on bare size class: compact×regular is also every
  normal iPhone portrait, which would violate the "no change elsewhere" scope.
- Do **not** copy the `32` literal again; it becomes one shared constant.

## Design Decisions

1. **Interpretation of "widen by halving side padding"**: change the width
   *and* halve the inset (Q1B) — because the literal padding sits outside the
   cap (`ContentView.swift:512-523`) and halving it alone leaves the Duo card at
   ≈280 pt, failing the ticket's own goal. Gutter space reclaimed goes to the
   content.

2. **Duo width formula**: `min(340, viewportWidth * 0.8)` (Q5/W2) — halves the
   fractional side gap (the original `0.6` implies 20 % each side; `0.8` implies
   10 %), preserving the fraction-based intent of `ChecklistWidth` rather than
   inventing a subtractive formula. At 466 or 382 pt this reaches the existing
   340 ceiling; the same 340 cap keeps it from ballooning.

3. **Detection signal**: device identifier `iPhone19,4` via `uname`/`hw.machine`
   **AND** `horizontalSizeClass == .compact` **AND** `verticalSizeClass ==
   .regular` (Q2A). The device gate makes it strictly that device; compact ×
   regular excludes the inner display (regular × regular) and the outer
   landscape (compact × compact), so no separate orientation API is needed.
   Identifier source: ([Xojo forum](https://forum.xojo.com/t/iphone-duo-detection/88967/13),
   [aemisdr](https://github.com/aemi-studio/aemisdr/blob/54edba1fbedec86ecab4877367b9453922d49c99/docs/diary/2026-10-20-02.md)).

4. **Simulator limitation accepted**: `uname` returns the host arch in the iOS
   simulator, so the Duo branch never activates there (Q6a). No
   `SIMULATOR_MODEL_IDENTIFIER` fallback and no `LaunchSeams` switch. The
   detector takes the machine string as a parameter so unit tests can drive both
   branches.

5. **New Core seam `ChecklistLayout`** (Q3B), modelled on `OrientationPolicy`:
   a small `nonisolated public` type that owns the default/Duo insets and width
   fractions and exposes `horizontalInset(...)` and `maxContentWidth(viewportWidth:...)`
   for a plain `Context` value (`isDuoOuterPortrait: Bool`). `ChecklistWidth`
   stays as-is and keeps its pinned tests; `ChecklistLayout` composes it for the
   default case.

6. **One shared constant for the three sites** (Q7a): `ChecklistLayout` is the
   single owner of `defaultHorizontalInset = 32` and
   `duoOuterHorizontalInset = 16`; `ContentView.swift:496`, `:523`, `:749` read
   the active value, and `:495`/`:512` read the active cap. No literal remains.

7. **Surfaces changed** (Q4A): the iOS header row (`:495-496`), the list card
   (`:512-523`), and the empty-state card (`:749`). Inner row/folder padding
   (`:580`, `:640`, `:667`) is untouched. The empty state gains no width cap (it
   has none today); it simply widens via the halved inset.

8. **Verification is unit-level** (Q8c): a pure Core suite pins the policy —
   default context returns `32` / `min(340, 0.6W)`; Duo context returns `16` /
   `min(340, 0.8W)`; boundary at `340/0.8 = 425`; and the detector maps
   `"iPhone19,4"` → true, other machine strings → false. No UI test, no manual
   screenshot gate.

## What We're NOT Doing

- **Not** using hinge / reserved-region / `UIHinge` APIs — beta, iOS 27.1+,
  UIKit-only, and would introduce the repo's first `@available` (Q2D rejected).
- **Not** gating on size class or viewport width alone — that would change other
  iPhones or iPad multitasking widths and break the strict scope (Q2B rejected).
- **Not** using `SIMULATOR_MODEL_IDENTIFIER` or a `LaunchSeams` preview flag
  (Q6 a/vs b,c).
- **Not** adding a UI test or asserting a rendered pixel width (Q8c).
- **Not** changing `ChecklistWidth.maxContentWidth` for the default context, its
  semantics, or its pinned tests.
- **Not** touching inner row/folder padding (`16`/`24`), the selection sheet,
  edit forms (`ChecklistEditFormWidth`), the watch/widget targets, or the
  create/settings chrome.
- **Not** adding localization keys (no user-facing strings).
- **Not** creating child tickets; all work lands on this ticket.

## Open Risks

- **Nothing exercises the Duo branch end-to-end.** Decisions 3–4 + 8 mean the
  feature's only automated coverage is injected-input unit tests; the actual
  device path is never run in the gate (simulator returns host arch). Conventions
  warn that layout tickets cannot close on static evidence — the residual risk is
  accepted but must be stated in the PR.
- **`uname`/`hw.machine` is undocumented** and the identifier list must be
  maintained as Duo variants appear (`iPhone19,4` is the only known value).
- **Safe-area basis is untraced** (`research.md` Open Areas): `geometry.size.width`
  at `ContentView.swift:457` may or may not be safe-area adjusted. With W2 the
  Duo result is 340 at width ≥ 425 and `0.8 × width` below that, so a ~382 pt
  safe-area-adjusted read yields ≈306 rather than 340 — acceptable, but the
  exact device result is unverified (reinforces the first risk).
- **`verticalSizeClass == .regular`** is true on every iPhone portrait, so the
  device gate is doing all the scoping; a mis-mapped identifier silently
  disables the feature (unit-tested, but only against the known string).
- **`ChecklistWidthTests`** must remain untouched and green; `ChecklistLayout`'s
  default path must delegate to `ChecklistWidth` so the two cannot drift.
