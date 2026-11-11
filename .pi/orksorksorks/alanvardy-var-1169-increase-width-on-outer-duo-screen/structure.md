# Structure Outline

## Approach

Add a pure, cross-platform `ChecklistLayout` seam in Core (mirroring
`OrientationPolicy`: plain-value `Context`, no UIKit) that owns the two insets
and the two width fractions, plus a pure `DuoDisplay` machine-identifier
mapping. The app target reads `uname` + size classes in one thin helper and
passes the resulting `Context` into the three existing `ContentView` sites, so
the whole change is pure math + one injected value — no `@available`, no
`UIScreen`, no beta APIs.

Slices are ordered dependency → risk → value. The riskiest integration is
front-loaded in Slice 1: `uname` must compile across both SDK legs (the app
target is iOS **and** macOS) and the Context must actually reach the card.

---

## Phase 1: Walking skeleton — Duo-outer card widens end to end

One real device signal (`uname` + size classes) → Core policy → the checklist
card's cap and gutter, with a real visible width change on a Duo outer display
in portrait and the badge-standard value everywhere else. Green tests prove the
policy math and the identifier mapping; `make build` / `make build-mac` prove
the detector compiles on both platform legs.

**Files**
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift` (new) — policy math
- `CheckStitchCore/Sources/CheckStitchCore/DuoDisplay.swift` (new) — machine→Bool mapping
- `CheckStitch/DuoOuterPortrait.swift` (new) — `uname` + size-class → `Context`
- `CheckStitch/ContentView.swift` — card cap `:512` + gutter `:523`
- `CheckStitchTests/ChecklistLayoutTests.swift`, `CheckStitchTests/DuoDisplayTests.swift` (new)

**Key changes**
- `ChecklistLayout.Context { isDuoOuterPortrait: Bool }` — new, `Sendable`/`Equatable`,
  `public static let standard = Context(isDuoOuterPortrait: false)`.
- `ChecklistLayout.horizontalInset(_ context: Context) -> CGFloat` — new; `32` / `16`.
- `ChecklistLayout.maxContentWidth(viewportWidth: CGFloat, context: Context) -> CGFloat`
  — new; default branch **delegates to** `ChecklistWidth.maxContentWidth` (never
  re-derives `0.6`), Duo branch is `min(340, viewportWidth * 0.8)`.
- `ChecklistLayout.defaultHorizontalInset` / `.duoOuterHorizontalInset` — new
  `nonisolated public static` constants, the only home of `32`/`16`.
- `DuoDisplay.isOuterPortrait(machine: String, isCompactWidth: Bool, isRegularHeight: Bool) -> Bool`
  — new pure function; identifier set is `DuoDisplay.outerPortraitMachines`.
- `ChecklistWidth` — **unchanged**, keeps its pinned tests.
- App target: `DuoOuterPortrait.machineIdentifier: String` (`uname(&info).machine`
  under `#if os(iOS)`, `""` otherwise) and
  `DuoOuterPortrait.context(horizontal:vertical:machine:) -> ChecklistLayout.Context`.
- `ContentView` — add `@Environment(\.horizontalSizeClass)` / `(\.verticalSizeClass)`
  and one `let layoutContext = …` per body; `:512` becomes
  `ChecklistLayout.maxContentWidth(viewportWidth: geometry.size.width, context: layoutContext)`
  and `:523` becomes `.padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))`.

**Contract**: `ChecklistLayout.Context`, `ChecklistLayout.maxContentWidth(viewportWidth:context:)`,
`ChecklistLayout.horizontalInset(_:)`. Later slices consume only these; nothing
reads `ContentView` internals or the detector directly.

**Tests**
- `ChecklistLayoutTests` — default context returns `32` and matches
  `ChecklistWidth.maxContentWidth` at several widths (anti-drift); Duo context
  returns `16`, `min(340, 0.8W)` at 200 → 160, ceiling at 466 → 340.
- `DuoDisplayTests` — `"iPhone19,4"` + compact + regular → true; `"iPhone19,4"`
  + regular width → false; other machines (`"iPhone17,1"`, `""`) → false.
- Regression: `ChecklistWidthTests` untouched and green.

**Verify**: `make test-unit` green; `make build` and `make build-mac` green
(warnings-as-errors on both legs proves the `uname` `#if` split). Manual: the
card visibly widens only on a Duo outer display in portrait — **not runnable in
the gate** (simulator reports host arch), accepted risk, stated in the PR.

---

## Phase 2: The whole content column uses the shared width — header row + empty state

The edit-toggle header row and the first-run empty-state card adopt the same
`Context`-driven cap/inset, so on a Duo outer display the header aligns to the
widened card and the no-checklists screen widens by the same 16 pt gutter. Every
hardcoded `32` disappears from `ContentView.swift`, and a source-level regression
pin keeps it gone.

**Files**: `CheckStitch/ContentView.swift` (`:495-496`, `:749`),
`scripts/tests/run.sh` (new assertion), `CheckStitchTests/ViewRenderTests.swift`
(empty-state canary case, optional).

**Key changes**
- Header row `:495` → `ChecklistLayout.maxContentWidth(viewportWidth:context:)`; `:496` → `.padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))`.
- Empty state `:749` → `.padding(.horizontal, ChecklistLayout.horizontalInset(...))`
  (gains no width cap, per design decision 7).
- `scripts/tests/run.sh`: add a text assertion that `CheckStitch/ContentView.swift`
  contains no `.padding(.horizontal, 32)` and no `viewportWidth: geometry.size.width * 0.6`
  — pins the "one shared constant" rule.

**Contract**: no new API; slice 1's signatures are consumed unchanged. The
source-scan pin is the contract that no literal gutter returns.

**Tests**: existing `ViewRenderTests` still green (no render regression);
shell suite gains the literal-scan case; `ChecklistLayoutTests` already cover
every value used here.

**Verify**: `make test-unit` + `bash scripts/tests/run.sh` green; `make build`;
manual: on a Duo outer display the header row and empty-state card share the
card's new column edges.

---

## Phase 3: Hardening — prove the scoping can't over- or under-fire

No new user-visible behaviour: this slice closes the two silent-failure modes
(a wrong identifier disables the feature; a wrong size-class check widens a
normal iPhone) and records the un-executable device path as a stated risk.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/DuoDisplay.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift` (doc comments
only), `CheckStitchTests/DuoDisplayTests.swift`, `CheckStitchTests/ChecklistLayoutTests.swift`.

**Key changes**
- `DuoDisplay.isOuterPortrait` exhaustive size-class matrix: all four
  (width, height) Bool combinations × known/unknown machine → exactly one `true`.
- Unknown/malformed machine strings (`""`, `"iPad13,1"`, `"iPhone19,4 "` with
  whitespace) return `false` — the maintenance-fail-safe direction.
- `ChecklistLayout` boundary pins: `425` is the exact `340/0.8` crossover;
  `382` (safe-area-adjusted Duo width per design risk) → `305.6`; duplicated
  default-path equivalence across `10…1500` widths so `ChecklistLayout` and
  `ChecklistWidth` cannot drift.
- Doc comments: identifier list is the single maintenance point; macOS/other
  targets always resolve to the default context.

**Contract**: no API change — the hardening is test-only plus comments.

**Tests**: the two suites above, expanded; `ChecklistWidthTests` still its own file.

**Verify**: `make test-unit`; then the full gate `./scripts/test.sh` (includes
`make build`, `make test`, `make build-mac`, `make watch-build`,
`bash scripts/tests/run.sh`, `shellcheck`) printing `gate: ok`.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `make build` + `make build-mac` green, and
  `ChecklistWidthTests` untouched — the Context seam reaches the card without
  changing any default-case value.
- After Phase 2: `make test-unit` + `bash scripts/tests/run.sh` green with the
  literal-scan pin in place — no `32` gutter or inline `0.6` remains in
  `ContentView.swift`.
- After Phase 3: `./scripts/test.sh` prints `gate: ok`, and the PR states the
  accepted risk that the Duo device path is unit-tested only (simulator reports
  host arch), with what a user should see on a real Duo outer screen in portrait.

## Note on non-vertical work

Nothing here is a schema migration or wide refactor. The one non-vertical
element is genuinely horizontal and already isolated: the new Core seam
(`ChecklistLayout` + `DuoDisplay`) must exist before any view consumes it, and
`ChecklistWidth` stays frozen rather than being refactored — that sequencing is
inside Phase 1, not a separate layer milestone.
