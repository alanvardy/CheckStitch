# Phase 0 Spike — VAR-1033 language override: result

**Verdict: NO-GO.** Evidence-backed, on the iOS 18.7 simulator (the plan's
primary runtime). Stop; re-run `design` for Open Risk 1's fallback.

## Summary of evidence

| Item | Result |
|---|---|
| `make build` (simulator, probe present) | PASSED |
| `make test-unit` | PASSED (0 failures, `TEST SUCCEEDED`) |
| macOS app runtime probe | App runs; no observable output on any launch path (open / direct exec / tty); one unreproducible full report at 14:39 |
| iOS 18.7 simulator runtime probe | **Full report recovered from app data container** via `simctl get_app_container` |
| `String(localized:)` under isa-swap + `code="de"` | `de-main={Settings}`, `de-core={Dark}` — **stays English**; `routing-3arg-redirects=0` |
| Explicit-locale lookup | `explicit-de-main={Settings}` — also English |
| Direct `de.lproj` sub-bundle lookup | `core-sub-bundle-lookup=Dunkel` — **German IS there** |
| Nil-code restore | `restored-main/restored-core matches-baseline=true` (byte-identical) |
| `Text("literal")` follows `\.locale` | MANUAL-ONLY (not machine-observable headlessly) |

## Core structural finding

`String(localized:)` does NOT call the overridable
`localizedString(forKey:value:table:)` (probe: `routing-3arg-redirects=0`).
The runtime seam is the 4-arg
`localizedString(forKey:value:table:localizations:)`
(`@available(macOS 15.4, iOS 18.4, …)`), which is declared in
`extension Foundation::Bundle` and **cannot be overridden** — the Swift
compiler rejects it:
`instance method 'localizedString(forKey:value:table:localizations:)' is declared in extension of 'Bundle' and cannot be overridden`.

The plan's Phase 1 `LanguageBundle` (isa-swap + 3-arg override) would therefore
produce **zero visible language change** and must not be built as written.

## Artifacts (uncommitted — verdict is NO-GO)

- `.pi/orksorksorks/alanvardy-var-1033-set-language/spike.md` — full record + verdict
- `.pi/orksorksorks/alanvardy-var-1033-set-language/spike-ios-report.txt` — the iOS probe output
- `CheckStitch/SpikeLanguageOverride.swift` + `CheckStitch/MyApp.swift` hook — kept for inspection/re-run (throwaway; delete when done)
- `plan.md` — Phase 0 automated checkboxes checked (verified); manual unchecked

## State

- Nothing committed or staged (NO-GO → no phase-0 commit per brief).
- Simulator UDID `D6D3CD6F-…` shut down (scoped), `Simulator.app` quit, mac app processes killed.

## Recommended next step (for parent/user)

Re-run `design`: `Bundle` subclassing cannot redirect `String(localized:)` on
macOS 15/iOS 18. Candidates: (a) Open Risk 1 restart-to-apply + persisted
choice; (b) SwiftUI `\.locale`-driven literals + catalog strings on relaunch;
(c) investigate a Foundation-level localization override hook on this
toolchain before committing. Do not start Phase 1 with `LanguageBundle` as
planned.