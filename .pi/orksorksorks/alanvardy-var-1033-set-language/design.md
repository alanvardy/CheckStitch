# Design Discussion — VAR-1033 Set app UI language

## Current State

**Resolution is process-locale-only.** Every user-visible string resolves through
Foundation's `String(localized:)`, which picks a language from the process /
preferred localizations; no production call site selects a language (research
Q1). Three `Localizable.xcstrings` catalogs ship, one per target, each with six
languages `en, de, es, fr, ja, zh-Hans`:

- App → `.main` bundle (`CheckStitch/Localizable.xcstrings`)
- Core → `.module` bundle (`CheckStitchCore/Sources/CheckStitchCore/Resources/`)
- Watch → its own `.main` bundle (`CheckStitchWatch/Localizable.xcstrings`, 5 keys)

String sites split into two shapes, and **both must be handled**:

- *Lazy/SwiftUI*: `Text("literal")` compiles to a `LocalizedStringKey` and
  resolves at render against the environment locale.
- *Eager*: `String(localized:table:bundle:)` evaluated immediately into a stored
  `String` — `SharedStrings.swift:8,12,16` (core), `AppearanceMode.swift:71-73`,
  `BackgroundSettingsView.swift:68-69`, `DueDateLabel.swift:17-25`,
  `ChecklistDetailView.swift:296`, `AppInfo.swift:38,43`, and the watch's
  `WatchChecklistDetailView.swift:28-29`.

**The planned mechanism is dead.** The spike (`.pi/.../spike.md`, NO-GO) proved
`String(localized:)` on this toolchain routes through the 4-arg
`localizedString(forKey:value:table:localizations:)`, declared in an *extension*
of `Bundle` — Swift refuses the override, and the isa-swap 3-arg override saw
`routing-3arg-redirects=0`. The explicit-locale *parameter* form
(`String(localized:…, locale:)`) also returned English. The German resources
themselves are fine (`core-sub-bundle-lookup=Dunkel`). No `Bundle` subclassing.

**Settings today** (`SettingsView.swift:7-87`): a `Form` inside a `NavigationStack`
with four sibling `Section`s — Appearance (18-30), Background (32-40), Import and
Export (42-51), About (53-58). The Appearance `Picker` is the template: `Picker`
over `ForEach(allCases)` + `Label(mode.title, systemImage:)`, bound straight
through `$appearanceMode` → `@AppStorage("appearanceMode")` → `.onChange` →
`AppDelegate.applyAppearance` (research Q2/Q3).

**Preferences** follow one pattern: an enum plus a `*Preference` struct doing
raw-string validation with a fallback (`AppearanceModePreference`,
`AppearanceMode.swift:68-95`), stored in `UserDefaults.standard`, covered by
round-trip and unknown-value tests (`AppearanceModeTests.swift`,
`AppearanceModePreferenceTests.swift`).

**Platforms**: iOS and macOS are one `MyApp` process with per-OS delegates
(`MyApp.swift:10-33`); the watch is a separate `@main` app with no delegates, no
`@AppStorage` and no settings surface (`CheckStitchWatch/CheckStitchWatchApp.swift:4-14`),
talking to the phone over the `ChecklistSyncTransport` / `ChecklistSyncMessage`
seam (`ChecklistSync.swift:11-57`).

**Test reality**: the hosted runner resolves `String(localized:)` with the
process (English) locale, so `String.en(…)` pins are English-only; non-English
verification today uses compiled-`.lproj` diffs, not `String(localized:)`
(`LocalizationTests.swift:69-127`, conventions.md).

## Desired End State

A **Language** row in Settings → Interface. Choosing a language flips the
app's UI language **live**, with no relaunch, across the whole iOS/macOS view
tree; the choice survives relaunch; the paired watch renders in the same
language (it does not offer the choice).

Concretely:

- `Section("Interface")` is the first section of the settings `Form`, holding a
  `Picker` whose options are `System`, `English`, `Deutsch`, `Español`,
  `Français`, `日本語`, `简体中文` (verbatim endonyms; only *System* is a catalog key).
- Selecting an option immediately re-renders visible SwiftUI text, including the
  appearance picker titles, the background footer, due-date labels and the
  core-package strings. No restart, no "relaunch to apply" prompt.
- `appLanguage` persists in `UserDefaults.standard`; a cold launch restores it.
- The watch applies the phone's choice while running and after a cold launch.

**How we know it works**: `make test-unit` covers `AppLanguage` mapping,
`AppLanguagePreference` round-trip/fallback, and
`LocalizedStringResource.resolved(in:)` for at least one non-English catalog
string; the live flip is verified on this worktree's simulator by screenshot
diff (per the `simulator` skill, since the hosted runner cannot observe it); the
whole change passes `./scripts/test.sh`.

## Patterns to Follow

- **Preference template** — `AppLanguagePreference` mirrors
  `AppearanceModePreference` (`AppearanceMode.swift:68-95`): injectable
  `defaults` + `key`, `rawValue` validated against the enum's cases, unknown →
  default, plus `AppLanguage.load(from:)`.
- **Dual enum** — app-facing enum in `CheckStitch` with the shared/Sendable twin
  in `CheckStitchCore` (`AppearanceMode.swift` app + core twin, research Q2).
  Here both halves live in Core, because the watch needs the same type.
- **Settings picker template** — `SettingsView.swift:18-30`: `Picker` over
  `ForEach(allCases)`, `Label(…)` rows, `.accessibilityIdentifier`, a `Section`
  with a header, no staging bag (write-through binding).
- **Observable state holder** — `@MainActor @Observable final class` with a
  process-wide `current`, exactly like `WatchChecklistStore`
  (`ChecklistSync.swift:69-118`); mirror `AppLocaleState` from SingleThread
  (`SingleThreadCore/Sources/SingleThreadCore/AppLocaleState.swift:7-45`).
- **Roots set the environment** — attach `.environment(\.locale, …)` where the
  window content is built (`MyApp.swift:42-83`), mirroring
  `SingleThread/SingleThreadApp.swift:19,44` and its watch root (`:17`).
- **Lazy resources in core** — `SharedStrings` returns
  `LocalizedStringResource` (`.module` bundle) and callers resolve with
  `resolved(in:)`, which sets `resource.locale` **before** evaluating
  `String(localized:)` — the seam the spike proved works
  (`SingleThreadCore/.../LocalizedString+Shared.swift:107-117`).
- **Sync seam** — extend the existing `ChecklistSyncMessage` enum + adapters
  (`ChecklistSync.swift:11-57`, `PhoneSyncAdapter.swift:27-36`,
  `WatchSyncAdapter.swift:24-31`) rather than inventing a second channel.
- **Tests** — Swift Testing, behaviour-named functions, `@MainActor` on any
  suite touching the view model, isolated defaults via `makeIsolatedDefaults()`
  (`TestFixtures.swift:10-12`).

**Patterns NOT to follow** (found during research; do not resurrect them):

- `Bundle` subclassing / `object_setClass` / `localizedString` overrides — spike
  NO-GO; the override is a compile error on macOS.
- `String(localized:…, locale:)` as an override seam — spike: returned English.
- Writing `AppleLanguages` to `UserDefaults` (the classic hack) — undocumented
  private key, App-Review risk, requires the write before `UIApplicationMain`,
  and it suppresses the system per-app Language row.
- Storing an already-resolved `String` on a type (e.g. `AppearanceMode.title`
  today) — it freezes the language at first evaluation and can never flip live.
- `Text(someString)` for a string that should localize — `String` overload never
  localizes.

## Design Decisions

1. **Mechanism: SwiftUI `\.locale` + observable app-locale state** — port the
   SingleThread pattern (`AppLanguage`, `AppLocaleState`, `AppLanguagePreference`).
   It is the only runtime-viable, App-Store-safe seam, it is already shipping on
   this exact toolchain, and it gives a live flip. Bundle redirects are dead
   (spike); `AppleLanguages` is unsupported and review-risky.
2. **Platform scope: iOS + macOS in-process; watch renders only** — iOS and
   macOS share one `MyApp` process, so both roots get `.environment(\.locale, …)`
   for free. The watch gets no picker (no settings surface exists, research Q4);
   it receives the language over the existing WatchConnectivity seam.
3. **Watch delivery rides the existing sync protocol** — add a
   `.language(String)` case to `ChecklistSyncMessage` (new `ChecklistSyncKey`
   entry, `userInfo` + `init?(userInfo:)` branches), push it from
   `ChecklistSyncCoordinator` alongside `pushContext()`, and handle it in
   `WatchChecklistStore.receive`; the watch persists it locally so a cold launch
   keeps it, and re-pushes on activation/`requestChecklists` for a fresh install.
4. **Persist in `UserDefaults.standard`, key `"appLanguage"`** — consistent with
   `AppearanceModePreference` and sufficient because the watch is a separate
   container reached by sync, not by shared defaults.
5. **Convert every eager string site to `LocalizedStringResource`** — a complete
   conversion is what makes the language genuinely app-wide; a partial one
   produces a visibly mixed-language UI after a switch. `Text` gets the resource
   directly; non-View consumers call `resolved(in:)` with the effective locale.
6. **Placement: a new `Section("Interface")` as the first section**, matching
   the ticket's wording and leaving Appearance/Background/Import/About siblings
   untouched.
7. **Picker contents are verbatim endonyms; only "System" is localized** — the
   list stays readable whatever the current language is (SingleThread precedent,
   `InterfaceSettingsView.swift:63-76`).
8. **`System` means `Locale.current`** — the device/process locale, so the
   default behaviour is exactly today's.
9. **Write-through binding, no staging bag** — `SettingsBindings` stages only
   the three background keys (`SettingsBindings.swift:4-6`); the language picker
   follows the appearance picker and persists immediately through the holder's
   `set`.

## What We're NOT Doing

- No `Bundle` subclass, isa-swap, swizzling, or `localizedString` override.
- No `AppleLanguages` write, no custom `main.swift`, no auto-relaunch.
- No deep-link to the system per-app Language setting (no in-app dropdown).
- No language picker or settings surface on the watch.
- No change to `InfoPlist.strings` / OS-level metadata (display name, permission
  prompts stay on the device language) — only in-app rendering follows the
  preference.
- No new locales beyond the six already in the catalogs.
- No new appearance/background behaviour; no unrelated Settings refactor.
- No change to the catalog-discipline tests; new keys land in the catalogs with
  all six translations or the suites fail.

## Open Risks

- **Missed eager site leaks the old language.** `\.locale` only reaches SwiftUI
  rendering; any non-View consumer (accessibility labels, `AppInfo`, watch
  strings) needs `resolved(in:)`. Detection is manual — a grep inventory of
  `String(localized:` is the checklist.
- **The gate cannot see a language switch.** The hosted runner pins the process
  locale (conventions.md, `LocalizationTests.swift:77-105`), so a regression in
  the live flip would pass CI. Mitigation: unit-test `resolved(in:)` against a
  `Locale(identifier: "de")` plus an end-to-end simulator screenshot diff, and
  record what the user should see.
- **macOS runtime evidence is hard to capture** (spike's macOS quirk: container
  launches produce no host-visible output). macOS is verified by the
  `make build-mac` compile leg plus a signed manual run, not by an automated
  assertion.
- **WatchConnectivity lag / cold launch.** A language change while the watch is
  unreachable is delivered on next activation; until then the watch shows its
  last persisted value. Reading it back from the phone on `requestChecklists`
  is the recovery path, but it is not instant.
- **Watch catalog breadth.** The watch catalog has only five keys and its UI
  uses exactly those; any future watch string must be cataloged in all six
  languages or it will stay English under the override.
- **Singleton observability.** `AppLocaleState.current` must be read inside a
  view body for `@Observable` to re-render; reading it once into a stored
  property (the very pattern decision 5 removes) would silently stop updates.
- **`resolved(in:)` depends on setting `resource.locale` before evaluating** —
  the working but non-obvious seam (SingleThread precedent). If a future
  toolchain changes it, eager strings regress while the live SwiftUI path keeps
  working; a focused test should pin it.
- **Reminder creation text.** Reminder titles come from user-entered checklist
  items, so they are unaffected; but any app-generated string that reaches
  EventKit must resolve through `resolved(in:)` at creation time to match the
  chosen language.
