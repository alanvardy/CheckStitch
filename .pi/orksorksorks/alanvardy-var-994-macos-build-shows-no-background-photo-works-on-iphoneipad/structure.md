# Structure Outline

## Approach

The whole bug is one rendering-side divergence: iOS passes
`.containerBackground(.clear, for: .navigation)` under `#if os(iOS)`
(`ContentView.swift:54-60`) and macOS passes nothing, relying on a comment's
unverified claim that its stack is already transparent. The fix is to make that
opt-out platform-neutral, and the working method is: establish the failure as
evidence, build a testable seam for the container condition, then apply it —
each stage green before the next, with the pixel proof on a signed macOS run.

`BackgroundFade`, `BackgroundPhotoLayer`, `BackgroundImageStore` and the
`@AppStorage` path are **not staged** — research showed they are platform-neutral
and the design forbids touching them.

---

## Stage 1: Diagnostic baseline — evidence, not inference

Freeze the pre-fix failure on record before any code moves, so the remaining
stages have a concrete "before" and the fallback order for the open risk is
already measured. No production code changes.

**Files**: `.pi/orksorksorks/<branch>/diagnosis.md` (new, committed artifact)

**Key changes**:
- Record the signed-run observation: `make build-mac-signed` + launch → flat
  `Color.systemBackground`, no photo, at default fade.
- Record the two cheap discriminators while the app is running: whether
  `BackgroundImageStore.imageData` is non-nil on macOS after refresh (rules
  hypothesis 3 in/out) and whether the layer receives a non-zero proposed size
  (rules hypothesis 2 in/out). Observing only; no code edits to either type.

**Tests**: none — this stage produces the evidence the reproduction test encodes.
**Verify**: signed macOS build launches and the absent-photo state is recorded
with its observation method. If `imageData` is nil here, stop and report: the
failing layer is the store, not compositing, and the design needs revisiting.

---

## Stage 2: Test seam — the container condition becomes a named, testable unit

Extract the container opt-out into a named `View` modifier so the reproduction
suite has a stable seam to assert against, and land the reproduction suite
**before** any call site changes. This is the stage that makes an otherwise
cross-cutting rendering condition testable below the UI layer.

**Files**: `CheckStitch/NavigationContainerClear.swift` (new),
`CheckStitchTests/PhotoBackdropRenderTests.swift` (new; whole-file `#if os(macOS)`)

**Key changes**:
- `extension View { func photoTransparentNavigationContainer() -> some View }`
  — new; body is `containerBackground(.clear, for: .navigation)`, no platform
  branch. This is the single source of truth Stage 3 consumes.
- `enum ContainerBackgroundCase { case defaulted, cleared }` — new test-only
  cases naming the condition under test.
- `@MainActor func sampledPixel(of image: Image, in size: CGSize) -> (r: Double, g: Double, b: Double)?`
  — new test helper; renders via `ImageRenderer` and samples one coordinate.
- `struct PhotoBackdropRenderTests` — new, `@MainActor`; builds a miniature
  composite mirroring ContentView's ZStack (systemBackground fill → photo layer
  carrying the `jpegData` fixture → a `NavigationStack`-shaped container that is
  either `.defaulted` or `.cleared`).

**Tests**:
- `clearedContainerShowsPhotoBehindIt` — happy path: cleared case samples the
  photo's colour.
- `defaultedContainerHidesPhotoBehindIt` — the reproduction: defaulted case does
  **not** sample the photo colour. This is the assertion that encodes the bug;
  demonstrate it red by constructing the composite from the pre-fix macOS
  condition (clear absent) before wiring the seam.
- `photoIsDrawnAtFadedOpacity` — sad-path-adjacent: a faded case samples a
  channel mix between the fill and the photo, pinning that the seam does not
  disturb `BackgroundFade`.

**Verify**: `make test-unit`. Expected: cleared/faded cases green on the seam,
the defaulted reproduction demonstrated red-first (recorded in
`diagnosis.md`), then green once the seam is the only construction path.
**Fallback (design Decision 3)**: if `ImageRenderer` cannot observe container
compositing headless, replace the pixel assertion with a structural assertion
that `photoTransparentNavigationContainer()` produces a view distinct from the
unmodified one, and state the limitation in the test — the real proof then rests
on Stage 4's signed run.

---

## Stage 3: Fix — apply the opt-out on every platform

Apply the Stage 2 seam at the ContentView call site and delete the falsified
comment. This is the smallest possible change; iOS receives byte-identical
semantics (same modifier, now off the conditional).

**Files**: `CheckStitch/ContentView.swift`

**Key changes**:
- Replace the `#if os(iOS) … .containerBackground(.clear, for: .navigation) … #endif`
  block (`:54-60`) with `.photoTransparentNavigationContainer()` on the same
  `Group`, unconditional.
- Delete the `:55-58` comment (an unverified platform assumption); replace with a
  one-line comment stating that the container is cleared on every platform
  because both need the ZStack photo to show through.
- No other `#if os(...)` block, no ZStack change, no store/photo-layer edit.

**Tests**: `PhotoBackdropRenderTests` surface unchanged and must stay green —
this stage's automated coverage is the Stage 2 seam plus the whole gate;
the call-site application itself is deliberately noted as not unit-testable
(the seam *is* the earlier stub for it).
**Verify**: `make test-unit` green; `make build-mac` and `make watch-build`
compile without errors (the availability floor for `.containerBackground` on
macOS surfaces here — Decision 5; only then add an availability guard).

---

## Stage 4: Regression gate and manual rendering proof

Prove the fix on the real macOS renderer, prove iOS is untouched, and close the
ticket on the full gate. This is the only stage that can observe
window-resize behaviour, which the repo does not test.

**Files**: `.pi/orksorksorks/<branch>/diagnosis.md` (append the post-fix record)

**Key changes**: none in production code.

**Tests**: whole suite, including the existing `BackgroundPhotoLayerTests`,
`BackgroundFadeTests`, `BackgroundImageStoreTests`, `SettingsBindingsTests`,
`ViewRenderTests`, `MacWindowFrameTests`, `CheckStitchUITests` smoke.
**Verify**:
- `bash scripts/test.sh` prints `gate: ok` (simulator build → UI smoke →
  unsigned macOS leg → watchOS leg → shell tests → shellcheck).
- `make build-mac-signed` + launch: photo renders behind the content and stays
  correct across window resizes, at default and faded opacity — recorded as the
  post-fix counterpart to Stage 1.
- iOS: diff contains no iOS-conditional change, simulator UI smoke green.

---

## Stage 5 (conditional): Diagnostic branch — only if the photo is still absent

Not planned work; the branch Stage 1's evidence decides between. If after
Stage 4 the photo is missing, the container hypothesis was wrong and the failing
layer is: `BackgroundImageStore` directory/load on sandboxed macOS, then the
`BackgroundPhotoLayer` proposed size. Each is a separate follow-up decision with
the owner — do **not** bundle speculative fixes for them into this change.

---

## Testing Checkpoints

- After Stage 1: signed-run evidence recorded; `imageData` non-nil (else stop).
- After Stage 2: `make test-unit` green for the seam suite; reproduction captured red-first.
- After Stage 3: `make test-unit` green; `make build-mac` + `make watch-build` compile.
- After Stage 4: `bash scripts/test.sh` → `gate: ok`; signed macOS resize check recorded; no iOS diff.