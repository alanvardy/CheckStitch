# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `6dee9d1` | Foundation — resource plumbing, test harness, language registration |
| 2     | `3030a14` | Catalog content — all keys × six languages |
| 3     | `5b3b1d4` | Core string access — SharedStrings + localized AppearanceMode |
| 4     | `bed1dad` | App string migration |
| 5     | `478bcac` | Watch string migration |
| 6     | `16df3ef` | Localized Info.plist metadata |

(Plus setup commit `7dbf3ea` — DELETEME placeholder removal; the branch was rebased onto `origin/main` before Phase 1 per the step protocol.)

## Automated Checks

- [x] `make test-unit` — 98+ tests / 20 suites green after Phase 6 (LocalizationTests: parse, six-language completeness, required keys, non-English canary, embedded-bundle proofs for Core and App, InfoPlist per-language keys; AppearanceModeTests incl. `titlesResolveThroughTheCoreCatalog`; ViewRenderTests; all pre-existing suites)
- [x] `make build` — compiles; built app bundle contains all six `.lproj` dirs with `InfoPlist.strings` + `Localizable.strings`
- [x] `make build-mac` — compiles
- [x] `make watch-build` — compiles (watch links the package)
- [x] `bash scripts/test.sh` — prints `gate: ok` (16 shell tests, sim build + boot, test, build-mac, watch-build, shellcheck)
- [x] `git status` after Phases 1–2 — only pbxproj change is `knownRegions`; no unexpected keys extracted by any build (catalogs = 31 app / 3 core / 5 watch keys, each with en/de/es/fr/ja/zh-Hans)
- [x] `plutil -lint` on all 12 `InfoPlist.strings` files
- [x] `CheckStitchCore_CheckStitchCore.bundle` confirmed embedded in built products (app, sim, watch)

## Plan adaptations (deviations applied during implementation)

1. **`catalogsParse` in Phase 1** — plan's literal form (`catalogs.count >= Catalogs.all.count`) requires non-empty keys and would fail against the empty skeleton catalogs (plan deviation #6 already flagged this tension); kept as a pure parse proof, replaced in Phase 2 exactly as planned.
2. **`%lld%%` uses `"extractionState": "extracted"` instead of `"manual"`** (Phase 2) — the app target's pre-existing `STRING_CATALOG_GENERATE_SYMBOLS = YES` hard-fails on a manual entry with no Swift-derivable symbol name; `xcstringstool` probe confirmed `extracted` skips symbol generation. The key genuinely is source-extracted via `Text("\(percent)%")` (design.md:113 forbids turning the setting off). Runtime lookup key unchanged.
3. **`String(localized:locale:)` does not pin language in the hosted test runner** (Phases 3–4) — the process locale wins, so `locale: Locale(identifier: "de")` returned English. `coreCatalogValuesAreEmbeddedInTheResourceBundle` and `appCatalogIsEmbeddedInTheMainBundle` instead resolve the embedded `de.lproj/Localizable.strings` via `Bundle(.core|.main).url(forResource: "Localizable", withExtension: "strings", subdirectory: "", localization: "de")` and assert the German value matches the source-tree catalog — arguably a stronger, deterministic proof that the compiled bundle carries the German catalog.
4. **No `excludedIdentities` additions needed** — the canary's seeded five identities sufficed; no legitimately-identical non-English values surfaced.

## Manual Verification Items (from the plan)

- [ ] Inspect the built products and confirm `CheckStitchCore_CheckStitchCore.bundle` is embedded inside the built `CheckStitch.app` (macOS: `CheckStitch.app/Contents/Resources/`)
- [ ] Open each `.xcstrings` in Xcode (`open CheckStitch/Localizable.xcstrings`) and confirm the six languages appear with no "needs translation" markers
- [ ] Run the macOS app and confirm the appearance picker still shows System / Light / Dark in English
- [ ] `make build` then confirm the built `CheckStitch.app` contains `en.lproj/Localizable.strings` (and `de.lproj` etc.) inside the bundle
- [ ] Build the watch scheme and confirm `CheckStitchWatch.app` contains `en.lproj/Localizable.strings`
- [ ] Set a simulator/device to German and relaunch from clean (delete app + revoke Reminders access so the prompt reappears):
  ```bash
  xcrun simctl spawn <UDID> defaults write -g AppleLanguages -array de
  xcrun simctl spawn <UDID> defaults write -g AppleLocale -string de_DE
  xcrun simctl shutdown <UDID> && xcrun simctl boot <UDID>
  ```
  or via Settings → General → Language & Region → German.
- [ ] Confirm translated UI copy: nav titles `Einstellungen` / `Hintergrund` / `Checkliste bearbeiten`, empty state `Keine Checklisten`, picker row `Hell`/`Dunkel`, photo credit `Foto von … auf Unsplash`
- [ ] Confirm the Reminders permission prompt shows the German usage description
- [ ] Confirm the home-screen app name still reads **CheckStitch** (and the watch app name too)
- [ ] Switch the device to `ja` or `zh-Hans` and spot-check the same screens

The manual device-locale smoke (item 5 onward) is the only proof that the localized Info.plist metadata surfaces — generated-Info.plist precedence (`INFOPLIST_KEY_*` vs `.lproj`) cannot be asserted from unit tests (plan's non-horizontal caveat).