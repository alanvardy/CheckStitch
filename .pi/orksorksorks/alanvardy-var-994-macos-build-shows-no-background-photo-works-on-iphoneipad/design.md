# Design Discussion

## Current State

ContentView builds a three-layer `ZStack` (`CheckStitch/ContentView.swift:25-33`):
`Color.systemBackground.ignoresSafeArea()` (:26) at the bottom, the photo
(`BackgroundPhotoLayer(imageData:isEnabled:opacity:)`, :27-30) in the middle,
and `NavigationStack(path:)` (:31) on top. The photo is therefore *behind* the
navigation container, and its visibility depends entirely on what that container
paints over it.

The only platform branch that touches this compositing is iOS-only
(`ContentView.swift:54-60`):

```swift
#if os(iOS)
.containerBackground(.clear, for: .navigation)   // :59
#endif
```

The comment at :55-58 documents why: iOS 26's `NavigationStack` paints an opaque
container behind its content, so the iOS build explicitly clears it; the comment
asserts **"macOS's stack is already transparent"** — an assumption, not a
runtime measurement. macOS applies no equivalent modifier anywhere.

Every other platform `#if os(...)` in ContentView (:38-49 toolbar, :71-76
appearance, :78-84 `preferredColorScheme`, :96-115 iOS floating chrome,
:129-135 button placement, :137-212 button chrome, :234-242 top padding) changes
chrome, not container transparency.

The other three candidate causes are ruled out by research:

- **Photo wrapper cannot collapse** (`BackgroundPhotoLayer.swift:15-20`):
  `Color.clear.overlay { image.resizable().scaledToFill() }.ignoresSafeArea()
  .opacity(opacity)` is platform-neutral by construction. `Color.clear` is
  proposal-greedy with zero intrinsic size; `.overlay` never affects host layout
  size. Only the decode branches (`:22-25`) and that is `NSImage` vs `UIImage`.
- **Data layer is platform-neutral** (`BackgroundImageStore.swift:188-192`):
  one `defaultDirectory`, no platform branch except `isDecodableImage`
  (:202-209). Same freshness/pin/single-flight gating, same `imageData`→view wire.
- **Settings path is platform-neutral** (`ContentView.swift:12-14`):
  `@AppStorage` on `UserDefaults.standard` for all three keys, identical
  defaults, no App Group/KVS involvement. `backgroundEnabled` is re-read at every
  body evaluation with no conditional read path.

The entire macOS/iOS divergence that can affect the photo is the missing
container-clear.

## Desired End State

On macOS the background photo paints exactly as it does on iOS — same fade
opacity from `BackgroundFade` (`1 - percent/100`), edge-to-edge through
`.ignoresSafeArea()`, correct across window resizes, behind the navigation
chrome. iOS/iPadOS rendering is byte-for-byte unchanged (it already receives the
modifier). No change to fetch, decode, persist, or settings behaviour on any
platform.

Verification:

1. `make build-mac-signed` then launch the macOS app: the photo renders behind
   the content and stays correct while the window is resized.
2. `make test-unit` — new reproduction test fails on the pre-fix container
   condition and passes after the fix.
3. `bash scripts/test.sh` prints `gate: ok` (simulator build, UI smoke, unsigned
   macOS leg, watchOS leg, shell tests, shellcheck).
4. iOS simulator build/UI smoke still green — no iOS change in the diff.

## Patterns to Follow

- **The iOS-26 opaque-container fix is the pattern to copy**
  (`ContentView.swift:54-60`). The fix is the same modifier applied on both
  platforms; the existing iOS behaviour becomes the shared behaviour. This is
  the codebase's own precedent for exactly this class of bug.
- **Minimal, symmetric view-structure change**: platform conditionals in
  ContentView exist only where chrome genuinely differs (floating plates on iOS
  vs title-bar glyphs on macOS, `:96-115`, `:137-212`). Container transparency
  is *not* a chrome difference, so it does not belong behind a conditional.
- **Test style** (`conventions.md`; `BackgroundPhotoLayerTests.swift`,
  `SettingsBindingsTests.swift`): Swift Testing `struct <Thing>Tests`, `@Test`
  with behaviour-named functions (no `test` prefix), `#expect`, `@MainActor` on
  any suite touching views/rendering. Suites that mutate
  `UserDefaults.standard` are `@Suite(.serialized)` with deferred cleanup.
  Platform-gated files use whole-file `#if os(macOS)` (`MacWindowFrameTests.swift:1`).
- **Commands**: `make test-unit` as the fast check, `bash scripts/test.sh` as
  the gate (`conventions.md`).
- **New files need no `project.pbxproj` edit** — `PBXFileSystemSynchronizedRootGroup`.

Patterns **not** to follow:

- The comment at `ContentView.swift:55-58` is an unverified platform assumption;
  do not extend it, replace it. Comments asserting toolchain behaviour should be
  removed when falsified, not left as a second source of truth.
- `ContentView.swift:1-3` has a duplicated `import CheckStitchCore`; do not copy
  that pattern into new files (harmless, out of scope to fix here).

## Design Decisions

1. **Fix is the container clear, applied unconditionally**: delete the
   `#if os(iOS)` wrapper around `.containerBackground(.clear, for: .navigation)`
   so both platforms receive it — one code path, iOS semantics unchanged, macOS
   gets the proven opt-out. Recommended over a macOS-only branch (duplicates the
   modifier and enshrines the divergence) and over restructuring the ZStack
   (larger iOS blast radius for no gain).

2. **Confirm before committing**: first implementation step is a signed macOS
   run (`make build-mac-signed` + launch) to observe the pre-fix failure and the
   post-fix success. The ticket frames this as an unconfirmed regression;
   verification is cheap and the diagnosis becomes evidence rather than
   inference.

3. **Test is a macOS-hosted render reproduction**: an `ImageRenderer`-based
   Swift Testing suite renders a miniature composite mirroring ContentView's
   layering — background fill, photo layer, and a container whose background is
   either left default (opaque) or cleared — and asserts a sampled pixel carries
   the photo colour only in the cleared case. This reproduces the broken
   condition without depending on `NavigationStack` internals and runs in the
   existing `make test-unit` macOS leg. It lands before the fix and must fail
   against the opaque case. If `ImageRenderer` proves unable to observe
   container compositing headless, fall back to extracting the modifier into a
   named helper and asserting on the extracted seam (documented in the plan).

4. **No defensive changes elsewhere**: `BackgroundPhotoLayer` gets no extra
   frame/fill, the store/decode path is untouched, no KVS or App-Group work.
   Research showed hypotheses 2–4 are not platform-divergent; changing them
   would be speculative and would obscure which change actually fixed the photo.

5. **Availability resolved by the compiler**: apply the modifier as-is; the
   unsigned `make build-mac` and `make watch-build` legs will surface any
   deployment-target floor. Only if the compiler objects do we add an
   `@available`/`#available` guard or adjust the target — no pre-emptive guards.

6. **`BackgroundFade` semantics are untouched**: opacity continues to come from
   the existing `1 - percent/100` clamped 0…90 path (`BackgroundFade.swift:17,24-26`,
   call site `ContentView.swift:30`); the fix only changes what is painted over
   the photo.

## What We're NOT Doing

- Not changing `BackgroundPhotoLayer`'s wrapper (no `.frame`, no
  `maxWidth/maxHeight`, no rewrite of the `Color.clear.overlay` mechanism).
- Not touching `BackgroundImageStore` (no `defaultDirectory` changes, no
  sandbox-path workarounds, no network/fetch changes, no decode changes).
- Not touching the settings/storage path (`@AppStorage` keys, `SettingsBindings`,
  `SettingsView`, `BackgroundSettingsView`), and not introducing App Group or
  KVS storage for the background keys.
- Not restructuring the ZStack, moving the photo into `.background(...)`, or
  changing `NavigationStack` composition.
- Not adding snapshot/screenshot test infrastructure, and not adding a macOS UI
  test or a second UI smoke.
- Not changing iOS's `#if os(...)` chrome conditionals, button plates, or
  padding (`:38-49`, `:96-115`, `:129-242`).
- Not fixing the duplicated `import CheckStitchCore` (`ContentView.swift:1-3`).
- Not creating child tickets — all work lands on this ticket's branch.

## Open Risks

- **Root cause could be elsewhere**: if the signed macOS run shows the photo
  still absent after the container clear, the failing layer is not what research
  predicts. Fallback order: check whether `imageData` is non-nil on macOS at
  runtime (hypothesis 3), then the wrapper's rendered size (hypothesis 2). This
  is a diagnostic branch in the plan, not a design change.
- **`ImageRenderer` fidelity headless**: container backgrounds are exactly the
  kind of thing a software renderer may handle differently; the reproduction
  test may not observe the failure. Mitigation is the documented fallback to a
  structural seam (Decision 3).
- **Toolchain drift**: the fix leans on the same API iOS already uses; if macOS
  availability differs, `make build-mac`/`make watch-build` fail loudly
  (Decision 5), which is the intended signal.
- **Sandboxed macOS `applicationSupportDirectory`**: if the store's directory is
  not writable/readable under the signed sandbox, the photo may still not load
  for reasons unrelated to compositing. The diagnostic step above distinguishes
  these.
- **Window-resize correctness is untested in the repo** — it is verified
  manually on the signed macOS run, not by an automated test.