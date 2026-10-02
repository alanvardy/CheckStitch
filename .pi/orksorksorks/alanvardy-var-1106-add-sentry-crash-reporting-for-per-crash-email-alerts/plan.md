# Implementation Plan

## Overview

Port SingleThread's shipped Sentry crash-reporting integration into CheckStitch:
link `sentry-cocoa` to the app + test targets only, start an inert-when-DSN-empty
bootstrap from `MyApp.init()`, scrub every event/breadcrumb to structural
metadata, add the app privacy manifest + a 6-language "Crash Reports"
disclosure with a user opt-out toggle, and add Xcode Cloud dSYM-upload scripts +
docs. Three dependency-ordered phases, one commit each.

Recon decisions (resolved):
- **Q1 → port the consent toggle.** A Sentry-free `CrashReportingPreference`
  (UserDefaults key `crashReportingEnabled`, absent → enabled) lives in
  `CheckStitchCore`; `SentryBootstrap.startIfEnabled()` gates on it; the toggle
  lives at the top of `PrivacySettingsView`. `CheckStitchCore` never imports
  Sentry.
- **Q2 → extend the gate's shellcheck** to `ci_scripts/*.sh` (keep those scripts
  `#!/bin/sh`, matching SingleThread).
- **Q3 → new sibling `docs/CrashReporting.md`**, linked from
  `docs/TestFlight-xcode-cloud.md`.

Reference implementation (read-only source of truth for every ported file):
`/Users/vardy/dev/SingleThread`.

---

## Phase 1: Dependency + inert Sentry bootstrap + privacy scrubber (walking skeleton)

Thinnest end-to-end path: the package is linked, the app starts the SDK only
when a DSN is present and the user prefers it, and every event is scrubbed.
Locally the DSN is empty, so the app stays inert — the green signal is build +
unit tests.

### Changes

#### 1. Sentry package wiring
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify

Add the remote package to the **project** `packageReferences` (line ~356), the
product dependency, and the two build files. IDs `90`–`93` are verified unused;
keep the project's synthetic-ID convention (`0000000000000000000000NN`).

```diff
 			packageReferences = (
 				000000000000000000000030 /* XCLocalSwiftPackageReference "CheckStitchCore" */,
+				000000000000000000000090 /* XCRemoteSwiftPackageReference "sentry-cocoa" */,
 			);
```

Add to the `PBXBuildFile` section (after line ~15):

```
		000000000000000000000092 /* Sentry in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000091 /* Sentry */; };
		000000000000000000000093 /* Sentry in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000091 /* Sentry */; };
```

App target `CheckStitch` (`packageProductDependencies`, line ~220) and test
target `CheckStitchTests` (line ~242) each gain:

```
				000000000000000000000091 /* Sentry */,
```

App `Frameworks` build phase `000000000000000130000000` (line ~135) gains
`000000000000000000000092 /* Sentry in Frameworks */,`; test `Frameworks` phase
`000000000000000221000000` (line ~141) gains
`000000000000000000000093 /* Sentry in Frameworks */,`. **Do not** touch
`CheckStitchCore`, `CheckStitchWatch`, or `CheckStitchWidget` — the dependency
must not propagate there.

Add the two new sections (mirror SingleThread
`SingleThread.xcodeproj/project.pbxproj:1254-1274`):

```
/* Begin XCRemoteSwiftPackageReference section */
		000000000000000000000090 /* XCRemoteSwiftPackageReference "sentry-cocoa" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/getsentry/sentry-cocoa";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 9.26.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		000000000000000000000091 /* Sentry */ = {
			isa = XCSwiftPackageProductDependency;
			package = 000000000000000000000090 /* XCRemoteSwiftPackageReference "sentry-cocoa" */;
			productName = Sentry;
		};
		000000000000000000000031 /* CheckStitchCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = CheckStitchCore;
		};
/* End XCSwiftPackageProductDependency section */
```

#### 2. Pure options factory (no Sentry import)
**File**: `CheckStitch/SentryConfiguration.swift`
**Action**: create

Port `SingleThread/SentryConfiguration.swift` verbatim (doc comment included).

```swift
import Foundation

/// Pure description of the crash-reporting configuration. Imports no Sentry so it
/// stays unit-testable; `SentryBootstrap` maps it to `SentryOptions`.
struct SentryConfiguration: Equatable, Sendable {
    static var currentEnvironment: String {
        #if DEBUG
            return "debug"
        #else
            return "production"
        #endif
    }

    let dsn: String
    let environment: String
    let maxBreadcrumbs: Int
    let sendDefaultPii: Bool
    let tracesSampleRate: Double

    static func make(dsn: String?, environment: String) -> Self? {
        guard let trimmed = dsn?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return Self(
            dsn: trimmed,
            environment: environment,
            maxBreadcrumbs: 20,
            sendDefaultPii: false,
            tracesSampleRate: 0)
    }
}
```

#### 3. Consent preference (Sentry-free, in Core)
**File**: `CheckStitchCore/Sources/CheckStitchCore/CrashReportingPreference.swift`
**Action**: create

Mirrors the `AppLanguagePreference` seam; absent/unrecognized → enabled so
existing installs keep reporting until the user opts out.

```swift
import Foundation

/// Persists the crash-reporting opt-out in `UserDefaults.standard`. An absent or
/// unrecognized value resolves to `true`, preserving today's behaviour.
public struct CrashReportingPreference {
    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "crashReportingEnabled"

    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

#### 4. Sentry-importing bootstrap
**File**: `CheckStitch/SentryBootstrap.swift`
**Action**: create

Port `SingleThread/SentryBootstrap.swift`; swap `import SingleThreadCore` →
`import CheckStitchCore` and keep `CrashReportingPreference()`.

```swift
import CheckStitchCore
import Foundation
import Sentry

/// Thin adapter from `SentryConfiguration` to `SentrySDK`. The only file besides
/// `SentryScrubber` that imports Sentry.
enum SentryBootstrap {
    static func startIfEnabled() {
        guard CrashReportingPreference().isEnabled,
              let configuration = SentryConfiguration.make(
                  dsn: bundleDSN,
                  environment: SentryConfiguration.currentEnvironment) else {
            return
        }
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.environment = configuration.environment
            options.maxBreadcrumbs = UInt(configuration.maxBreadcrumbs)
            options.sendDefaultPii = configuration.sendDefaultPii
            options.tracesSampleRate = NSNumber(value: configuration.tracesSampleRate)
            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.enableAutoSessionTracking = false
            #if os(iOS) || os(tvOS) || os(visionOS)
                options.attachScreenshot = false
                options.attachViewHierarchy = false
            #endif
            #if os(macOS)
                options.enableUncaughtNSExceptionReporting = true
            #endif
            options.beforeSend = { SentryScrubber.scrub($0) }
            options.beforeBreadcrumb = { SentryScrubber.scrub($0) }
        }
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            startIfEnabled()
        } else {
            SentrySDK.close()
        }
    }

    private static var bundleDSN: String? {
        Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String
    }
}
```

#### 5. Privacy scrubber
**File**: `CheckStitch/SentryScrubber.swift`
**Action**: create

Port `SingleThread/SentryScrubber.swift` verbatim (allow-listed tags,
nil out free-text fields, rebuild breadcrumbs).

#### 6. Start from the app entry
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

First statement of `init()` (currently `PurchaseEnvironment.service = …`):

```swift
    init() {
        SentryBootstrap.startIfEnabled()
        // … existing setup unchanged
```

`AppDelegate` needs no change — the task allows a UIKit hook but the app entry
is sufficient (SingleThread precedent).

#### 7. DSN token in Info.plist
**File**: `CheckStitch/Info.plist`
**Action**: modify

Add before `</dict>` (mirror `SingleThread/SingleThread/Info.plist:5-6`). The
token expands to empty locally; `ci_post_clone.sh` re-bakes it from the Xcode
Cloud env.

```xml
	<key>SENTRY_DSN</key>
	<string>$(SENTRY_DSN)</string>
```

#### 8. Tests
**Files**: create `CheckStitchTests/SentryConfigurationTests.swift`,
`CheckStitchTests/SentryScrubberTests.swift`,
`CheckStitchTests/CrashReportingPreferenceTests.swift`
**Action**: create

- `SentryConfigurationTests` (`@MainActor struct`, Swift Testing): port
  `SingleThreadTests/SentryConfigurationTests.swift` — `dsnIsTrimmedAndKept`,
  `emptyDsnYieldsNil` (nil / `" "` / `"\n"`), `privacyDefaultsAreSafe`
  (`sendDefaultPii == false`, `tracesSampleRate == 0`, `maxBreadcrumbs` in
  `(0, 50]`), `environmentMapsDebugBuild`.
- `SentryScrubberTests` (imports `Sentry`; port
  `SingleThreadTests/SentryScrubberTests.swift`). Must include the sad-path
  checklist-content leak guards: an event with a checklist-name tag/extra/user
  → `extra`/`user` nil, the tag dropped, allow-listed `environment` survives;
  a breadcrumb carrying item text → `message`/`data` nil, `category`/`level`
  survive; `Exception.value` nil while `type` survives; `message`/`transaction`
  nil.
- `CrashReportingPreferenceTests` (`@MainActor struct`): absent key → enabled;
  explicit `false` → disabled; explicit `true` → enabled; injected
  `UserDefaults(suiteName:)` isolates state; `setEnabled` round-trips.

### Verification
#### Automated
- [x] `make build` passes (first run resolves `sentry-cocoa` from the network)
- [x] `make test-unit` passes, including the three new suites
- [x] `make build-mac` passes (Sentry links on macOS without signing)
- [x] `make watch-build` passes (Core gained `CrashReportingPreference`; no Sentry on watch)

#### Manual
- [ ] Confirm the `Sentry` product is linked only to `CheckStitch` +
  `CheckStitchTests` (inspect the two targets in Xcode; Watch/Widget/Core
  unchanged)

---

## Phase 2: Privacy manifest, disclosure copy, opt-out toggle, 6-language localization

Declare what the app collects, tell the truth in-app about Sentry, and give the
user the opt-out the copy promises.

### Changes

#### 1. App privacy manifest
**File**: `CheckStitch/PrivacyInfo.xcprivacy`
**Action**: create

Port `SingleThread/SingleThread/PrivacyInfo.xcprivacy` verbatim (CrashData not
linked / not tracking / AppFunctionality; UserDefaults `CA92.1`,`1C8F.1`;
SystemBootTime `35F9.1`; FileTimestamp `C617.1`).

#### 2. Disclosure copy
**File**: `CheckStitch/PrivacySettingsContent.swift`
**Action**: modify

Add a `crashReports` section after `background`, and replace the background body
(its *"This is the app's only network traffic"* clause is falsified by Sentry).
Keep `reminders`/`sync` bodies — they scope the "never sent" claim to checklist
content, which remains true. Keep `closingLine` unchanged.

```swift
            PrivacySection(
                id: "background",
                title: resource("Background Image"),
                body: resource("When the background is enabled, the wallpaper "
                    + "and artist information are fetched via a proxy at vardy.cc. "
                    + "This request never includes any reminder, checklist, or "
                    + "preference data.")),
            PrivacySection(
                id: "crashReports",
                title: resource("Crash Reports"),
                body: resource("When crash reporting is enabled, CheckStitch "
                    + "sends crash and diagnostic information to Sentry, our "
                    + "crash-reporting provider. This data is processed in the "
                    + "United States and never includes any checklist, item, "
                    + "reminder, or preference content. You can turn crash "
                    + "reporting off at any time in Settings."))
```

Also update the file's header comment to list Sentry crash reporting as a data
flow that must stay in sync with this copy.

#### 3. Opt-out toggle
**File**: `CheckStitch/PrivacySettingsView.swift`
**Action**: modify

The view is no longer read-only; update its doc comment. Add the toggle above
the disclosure sections:

```swift
import CheckStitchCore
import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(CrashReportingPreference.defaultsKey) private var crashReportingEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Crash Reports", isOn: $crashReportingEnabled)
                    .accessibilityIdentifier("privacyCrashReportsToggle")
                    .onChange(of: crashReportingEnabled) { _, enabled in
                        SentryBootstrap.setEnabled(enabled)
                    }
            }
            ForEach(PrivacyGuideContent.sections) { section in
                // … unchanged
```

`@AppStorage`'s default (`true`) matches `CrashReportingPreference.isEnabled`'s
absent-key default.

#### 4. Catalog — 3 new/changed App keys × 6 languages
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add `"Crash Reports"` and the new crash-report body; **replace** the old
background-body key with the new sentence. Keys are the full English sentences.
Use a small unique anchor per `edit` (the catalog is 135 KB — see the
`localization`/`edit` skills).

```jsonc
"Crash Reports": {
  "extractionState": "manual",
  "localizations": {
    "en":      { "stringUnit": { "state": "translated", "value": "Crash Reports" } },
    "de":      { "stringUnit": { "state": "translated", "value": "Absturzberichte" } },
    "es":      { "stringUnit": { "state": "translated", "value": "Informes de fallos" } },
    "fr":      { "stringUnit": { "state": "translated", "value": "Rapports d'erreur" } },
    "ja":      { "stringUnit": { "state": "translated", "value": "クラッシュレポート" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "崩溃报告" } }
  }
}
```

Crash-report body (en is the key):

```
When crash reporting is enabled, CheckStitch sends crash and diagnostic information to Sentry, our crash-reporting provider. This data is processed in the United States and never includes any checklist, item, reminder, or preference content. You can turn crash reporting off at any time in Settings.
```

| lang | value |
|---|---|
| de | Wenn Absturzberichte aktiviert sind, sendet CheckStitch Absturz- und Diagnoseinformationen an Sentry, unseren Anbieter für Absturzberichte. Diese Daten werden in den Vereinigten Staaten verarbeitet und enthalten niemals Inhalte von Checklisten, Einträgen, Erinnerungen oder Einstellungen. Du kannst Absturzberichte jederzeit in den Einstellungen deaktivieren. |
| es | Cuando los informes de fallos están activados, CheckStitch envía información de fallos y diagnósticos a Sentry, nuestro proveedor de informes de fallos. Estos datos se procesan en Estados Unidos y nunca incluyen contenido de listas, elementos, recordatorios ni preferencias. Puedes desactivar los informes de fallos en cualquier momento en Ajustes. |
| fr | Lorsque les rapports d'erreur sont activés, CheckStitch envoie des informations de plantage et de diagnostic à Sentry, notre fournisseur de rapports d'erreur. Ces données sont traitées aux États-Unis et ne contiennent jamais de contenu de listes, d'éléments, de rappels ou de préférences. Vous pouvez désactiver les rapports d'erreur à tout moment dans les Réglages. |
| ja | クラッシュレポートが有効な場合、CheckStitch はクラッシュおよび診断情報をクラッシュレポート提供元の Sentry に送信します。このデータは米国で処理され、チェックリスト、項目、リマインダー、設定の内容が含まれることはありません。クラッシュレポートは設定でいつでもオフにできます。 |
| zh-Hans | 启用崩溃报告后，CheckStitch 会将崩溃和诊断信息发送给我们的崩溃报告服务提供商 Sentry。这些数据在美国处理，绝不会包含任何清单、项目、提醒事项或偏好内容。您可以随时在“设置”中关闭崩溃报告。 |

New background body (replaces the old key; translations are the existing ones
with the "only network traffic" clause removed):

```
When the background is enabled, the wallpaper and artist information are fetched via a proxy at vardy.cc. This request never includes any reminder, checklist, or preference data.
```

| lang | value |
|---|---|
| de | Wenn der Hintergrund aktiviert ist, werden das Hintergrundbild und die Künstlerinformationen von einem Proxy unter vardy.cc heruntergeladen. Diese Anfrage enthält niemals Erinnerungs-, Checklisten- oder Präferenzdaten. |
| es | Cuando el fondo está activado, el fondo de pantalla y la información del artista se descargan desde un proxy en vardy.cc. Esta solicitud nunca incluye datos de recordatorios, listas de verificación ni preferencias. |
| fr | Lorsque l'arrière-plan est activé, le fond d'écran et les informations sur l'artiste sont téléchargés depuis un proxy à vardy.cc. Cette requête ne contient jamais de données de rappel, de liste de contrôle ni de préférences. |
| ja | 背景を有効にすると、壁紙とアーティスト情報がvardy.ccのプロキシからダウンロードされます。このリクエストに、リマインダー、チェックリスト、設定データが含まれることはありません。 |
| zh-Hans | 启用背景后，壁纸和艺术家信息会从vardy.cc的代理服务器下载。此请求绝不会包含任何提醒事项、清单或偏好数据。 |

Remove the old background-body key entirely (it is no longer referenced) so the
catalog does not drift.

#### 5. Localization fixtures
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

In the `"App"` key list (line ~118-125) add `"Crash Reports"` and the new
crash-report body sentence; replace the old background-body string with the new
one.

#### 6. Disclosure tests
**File**: `CheckStitchTests/PrivacySettingsContentTests.swift`
**Action**: modify

- `privacyGuideContentCoversAllDisclosures`: `#expect(sections.count == 4)`;
  add `#expect(sections.contains { $0.id == "crashReports" })` and that its
  English body `contains("Sentry")`.
- `privacyGuideContentHasNoAnalyticsClaim`: unchanged (closing line kept).
- `privacyGuideContentResolvesInTheSelectedLanguageRatherThanTheProcessLocale`:
  the loop is generic — no hardcoded list — but confirm it still compiles.
- `privacyGuideContentResolvesTranslatedTextFromTheMainBundle`: add
  `"Crash Reports"` and both new body strings to `privacyKeys`; drop the old
  background-body string.

### Verification
#### Automated
- [x] `scripts/l10n-check.sh` passes (all 6 languages present, non-English differs)
- [x] `make test-unit` passes (disclosure + localization suites)
- [x] `make build` passes

#### Manual
- [ ] Settings → Privacy Policy shows a "Crash Reports" toggle + section, with
  no "only network traffic" claim remaining
- [ ] Switching app language to German renders the new section in German

---

## Phase 3: CI dSYM upload, gate enforcement, docs

Operationalize symbolication and reconcile the public claims.

### Changes

#### 1. Xcode Cloud dSYM upload
**Files**: `ci_scripts/ci_post_clone.sh`, `ci_scripts/ci_post_xcodebuild.sh`
**Action**: create (mode `100755`)

Port `SingleThread/ci_scripts/*` verbatim, both `#!/bin/sh` with `set -eu`.
In `ci_post_clone.sh` change the PlistBuddy target to `CheckStitch/Info.plist`:

```sh
    /usr/libexec/PlistBuddy -c "Set :SENTRY_DSN $SENTRY_DSN" CheckStitch/Info.plist
```

`ci_post_xcodebuild.sh` needs no edits (paths are relative only in
`ci_post_clone.sh`).

#### 2. Extend the gate's shellcheck leg
**File**: `scripts/test.sh`
**Action**: modify

```diff
-  shellcheck scripts/*.sh scripts/tests/*.sh
+  shellcheck scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh
```

Also extend the shell-level parseability test, `scripts/tests/run.sh`
(line ~460), so the new scripts are pinned the same way:

```diff
-    for f in scripts/*.sh scripts/tests/*.sh; do
+    for f in scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh; do
         /bin/bash -n "$f" || return 1
     done
```

Keep both `ci_scripts` as `#!/bin/sh` (POSIX, matching SingleThread) — both
shellcheck and `/bin/bash -n` accept them.

#### 3. Crash-reporting doc
**File**: `docs/CrashReporting.md`
**Action**: create

Port `SingleThread/docs/CrashReporting.md`, replacing `SingleThread` with
`CheckStitch` and reminders/list wording with checklists/items/reminders,
including the macOS slice. Keep all sections: intro (app-target-only linkage,
SentryConfiguration/SentryBootstrap/SentryScrubber, US region + free Developer
plan, DSN only in Xcode Cloud env), `## Sentry org setup`,
`## Xcode Cloud Environment` (table: `SENTRY_DSN`/`SENTRY_ORG`/`SENTRY_PROJECT`
non-secret, `SENTRY_AUTH_TOKEN` **secret**), `## Alert rule` (issue alert,
"email on every new crash", no filters/threshold, recipient author email —
dashboard config, not gate-testable), `## Triage steps`, `## dSYM upload`
(values exist only for archives; Debug is `dwarf` so only Release archives
symbolicate; late upload needs event reprocessing).

#### 4. Link from the TestFlight doc
**File**: `docs/TestFlight-xcode-cloud.md`
**Action**: modify

Add a short `## Crash reporting` section linking `CrashReporting.md` and naming
the required Xcode Cloud Environment variables + secret.

#### 5. README claim
**File**: `README.md`
**Action**: modify

The line-33 reminder/checklist bullet stays (content claim remains true).
Replace the line-36 "only network traffic" claim:

```
- No analytics, no tracking, and no advertising. Network traffic is limited to the optional background wallpaper and, if enabled, crash reports (see the Privacy Policy in the app).
```

### Verification
#### Automated
- [x] `./scripts/test.sh` passes end to end — the full gate, including the
  extended `shellcheck scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh` leg and
  `scripts/tests/run.sh`
- [x] `scripts/l10n-check.sh` passes
- [x] `bash -n ci_scripts/ci_post_clone.sh ci_scripts/ci_post_xcodebuild.sh` passes

#### Manual
- [ ] In Xcode Cloud, confirm the workflow Environment carries `SENTRY_DSN`,
  `SENTRY_ORG`, `SENTRY_PROJECT` (non-secret) and `SENTRY_AUTH_TOKEN` (secret)
- [ ] Configure the Sentry issue alert "email on every new crash" (no filters,
  no threshold, recipient = author email)
- [ ] Set the App Store Connect privacy label: Diagnostics → Crash Data,
  Not Linked to You
- [ ] End-to-end: on a TestFlight (Release) build, trigger a deliberate error /
  crash, then confirm a symbolicated Sentry issue **and** the per-crash email
  arrive within minutes
