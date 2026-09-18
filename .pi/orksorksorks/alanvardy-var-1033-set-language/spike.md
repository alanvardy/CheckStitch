# VAR-1033 Phase 0 spike: proving the language-override mechanism

**Verdict: NO-GO** (the plan's Phase 1–3 core mechanism cannot work as designed;
stop, re-run `design` for the fallback in Open Risk 1).

## What was run

| Leg | OS / runtime | Launch path | Result |
|---|---|---|---|
| macOS | macOS 15 (Xcode 26.6, Swift 6 Debug) | `make build-mac-signed` → `open` and direct exec | App runs; probe produces NO observable output (see macOS quirk below) |
| iOS | **iOS 18.7 simulator** (UDID `D6D3CD6F-F7EF-4265-8E93-389ED04891EB`) | `make run` / `simctl boot+install+launch` | **Full probe report captured** from the app's data container |
| iOS | simulator data container | `xcrun simctl get_app_container <udid> app.alanvardy.CheckStitch data` | Host-readable; report recovered |

Automated checks (verified, `make build`/`make test-unit` green with the probe
present) are checked in `plan.md` Phase 0.

## Probe design (throwaway `CheckStitch/SpikeLanguageOverride.swift`)

- `ProbeBundle: Bundle, @unchecked Sendable` overrides
  `localizedString(forKey:value:table:)` (3-arg), forwarding to the
  `code.lproj` sub-bundle while a code is installed, else `super` (nil path).
- `object_setClass(Bundle.main, ProbeBundle.self)` + the same for the embedded
  Core resource bundle (`CheckStitchCore_CheckStitchCore.bundle`).
- Redirect counter; fresh `LocalizationValue`s constructed inside the swap
  window; nil-restore byte-identity checks; report persisted to the app's
  Application Support (iOS data container).

## Observed output (iOS 18.7, quoted from `spike-ios-report.txt`)

```
probe-start
baseline-main=Settings
english-main-pin=Settings
baseline-core=Dark
english-core-pin=Dark
de-main={Settings}
de-core={Dark}
explicit-de-main={Settings}
routing-3arg-redirects={0}
core-sub-bundle-lookup=Dunkel
restored-core=Dark
restored-core-matches-baseline=true
restored-main=Settings
restored-main-matches-baseline=true
text-follows-locale=MANUAL-ONLY
probe-completed
```

The full file is preserved at
`.pi/orksorksorks/alanvardy-var-1033-set-language/spike-ios-report.txt`.

## Findings

1. **The isa-swap + `localizedString(forKey:value:table:)` override does NOT
   redirect `String(localized:)`.** With the swap installed and `code = "de"`,
   `de-main` and `de-core` stay English, and `routing-3arg-redirects=0`: the
   runtime never calls the overridden 3-arg method on iOS 18.7 (measured at
   runtime) or macOS (measured at runtime on the one launch that produced a
   report, and corroborated by compiler evidence below).
2. **`String(localized:)` uses the 4-arg seam, which cannot be overridden.**
   The only `Bundle.localizedString(forKey:…)` in the SDKs is
   `localizedString(forKey:value:table:localizations:)`
   (`@available(macOS 15.4, iOS 18.4, …)`), declared in
   `extension Foundation::Bundle`. Swift rejects an override:
   `instance method 'localizedString(forKey:value:table:localizations:)' is
   declared in extension of 'Bundle' and cannot be overridden` (build error,
   macOS leg). The plan's Phase 1 instruction "if `String(localized:)` routes
   through `...localizations:`, add an override for it" is therefore
   **impossible** on this toolchain.
3. **Explicit-locale lookups don't help either.** `explicit-de-main={Settings}`
   even with `locale: Locale(identifier: "de")` returns English — the
   explicit-locale path also does not reach the overridable 3-arg.
4. **The resolution primitive itself works.** `core-sub-bundle-lookup=Dunkel`:
   opening the compiled `de.lproj` as a `Bundle` and calling
   `localizedString(forKey: "Dark", value: "Dark", table: "Localizable")`
   returns German at runtime on iOS 18.7 — so the German resources are present
   and decodable; the block is purely at the "which seam the app's bulk
   `String(localized:)` reaches" level.
5. **Nil/unsupported-code path is byte-identical to English**
   (`restored-main-matches-baseline=true`, `restored-core-matches-baseline=true`),
   so a no-op fallback is safe — the mechanism just can't *do anything*.
6. **`Text("literal")` following `\.locale`** could not be machine-observed
   headlessly (SwiftUI resolves literals at render; no accessibility
   introspection available). Recorded `MANUAL-ONLY`.

## macOS quirk (why macOS produced no report)

Containerized `open`-launches run the app but its writes never surface —
`~/Library/Application Support/CheckStitch`, the container Data, `/tmp` and
the worktree cwd were all empty after multiple 45–150 s launches, with no
crash logs and no unified-log entries, while the process stayed alive. A
single complete report (`spike`-shaped, English baselines, `Dunkel` sub-bundle
lookup, redirects=0) was observed at 14:39 from an earlier build, but could not
be reproduced from any app launch; it appears to have come from a
non-containerized/auxiliary execution (e.g. an Xcode preview pass). If the
design is redone, macOS runtime evidence must be captured through the same
simulator-container technique or a bounded logging channel, not stdout/open.

## Open decision for `design`

- The ticket still needs a runtime-viable seam. `String(localized:)` cannot be
  redirected via `Bundle` subclassing on macOS 15/iOS 18 (4-arg extension
  method). Candidate alternatives: (a) the plan's Open Risk 1 fallback
  (restart-to-apply, persist choice, re-render on relaunch); (b) a `.locale`
  /SwiftUI-environment-driven approach for literals *plus* accepting catalog
  strings on relaunch; (c) re-examine whether Foundation offers another
  injectable localization hook on this toolchain (e.g. resource/localization
  override APIs) before committing to any of them. Do not build Phase 1 with
  `LanguageBundle` as written — the picker would visibly do nothing.