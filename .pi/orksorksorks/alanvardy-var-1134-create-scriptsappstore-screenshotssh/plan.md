# Implementation Plan

## Overview

Port `SingleThread/scripts/appstore-screenshots.sh` to CheckStitch: a new
`scripts/appstore-screenshots.sh` captures per-language, per-display-class PNGs
into `build/appstore-screenshots/<lang>/<device>/<n>-<name>.png`, staged with
deterministic wallpapers and verified with `sips`. Because CheckStitch has no
launch seam today, the app grows one Core `LaunchSeams` type (parsed in
`MyApp.init()` and `CheckStitchWatchApp.init()`) plus a small amount of
in-memory seeding, so the script can drive empty/list/settings/detail/watch
screens non-interactively. Output classes are iPhone 6.3" (1206×2622), iPad 13"
(2064×2752) and Apple Watch Series 11 46mm (416×496).

## Deviations from `structure.md` (recorded, then followed)

1. **`BackgroundViewModel.swift` is added to Phase 1.** Design decision 7 says
   `--ui-testing` turns the background-photo fetch off, but the fetch is driven
   by `BackgroundViewModel.task(pinned:)` from `ContentView`'s `.task`, which no
   other Phase-1 file touches. A two-line guard is the smallest faithful
   implementation; Phase 2's staged `background.json` makes the network call
   moot anyway, but Phase 1 must stay hermetic.
2. **`--no-build` / `--no-install` land in Phase 1**, not Phase 7. Phase 1's own
   manual verify uses `--no-build`, and the harness needs both to avoid a real
   `xcodebuild`. Phase 7 keeps `--settle`, `--lang`, `--udid`, pre/post-flight
   checks and the help header.
3. **Applied launch state lives in `ContentView`, not `MyApp`.** The settings
   snapshot (`settingsSnapshot()`) and `path` (`@State`) are `ContentView`
   members, so `ContentView` takes the parsed `LaunchSeams` (defaulted) and
   applies `openSettings` / `openChecklistIndex`; `MyApp` remains the only
   `ProcessInfo` caller.
4. **Phase 1 writes `en/iphone-6.3/1-main-dark.png`** exactly as `structure.md`
   states, but that shot is the *empty* state there; Phase 3 re-points the same
   path at the seeded main list and adds `2-empty.png`.

---

## Phase 1: Walking skeleton — one hermetic empty-state capture

### Changes

#### 1. `LaunchSeams` — the single arg/env reader
**File**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift`
**Action**: create

```swift
import Foundation

/// Launch-time UI-testing seams, parsed once at app start from `CommandLine`
/// arguments and the process environment. Every field defaults to off, so a
/// normal launch is byte-for-byte today's behaviour.
///
/// The only reader of launch arguments / UI-testing environment in the app;
/// views receive the parsed value, never `ProcessInfo`.
public struct LaunchSeams: Sendable, Equatable {
    public var isUITesting: Bool
    public var isEmpty: Bool
    public var seedURL: URL?
    public var openSettings: Bool
    public var openChecklistIndex: Int?
    public var language: AppLanguage?

    public init(
        isUITesting: Bool = false, isEmpty: Bool = false, seedURL: URL? = nil,
        openSettings: Bool = false, openChecklistIndex: Int? = nil,
        language: AppLanguage? = nil
    ) {
        self.isUITesting = isUITesting
        self.isEmpty = isEmpty
        self.seedURL = seedURL
        self.openSettings = openSettings
        self.openChecklistIndex = openChecklistIndex
        self.language = language
    }

    /// Ephemeral suite for `--ui-testing`; the real App Group container is
    /// never touched.
    public static let uiTestingSuiteName = "app.alanvardy.CheckStitch.uitesting"

    /// Pure parse. Each flag implies `isUITesting`; unknown arguments ignored.
    public static func parse(arguments: [String], environment: [String: String]) -> LaunchSeams {
        var seams = LaunchSeams()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--ui-testing":
                seams.isUITesting = true
            case "--ui-testing-empty":
                seams.isUITesting = true; seams.isEmpty = true
            case "--ui-testing-open-settings":
                seams.isUITesting = true; seams.openSettings = true
            case "--ui-testing-open-checklist":
                seams.isUITesting = true
                if index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
                    seams.openChecklistIndex = value; index += 1
                }
            case "--ui-testing-app-language":
                seams.isUITesting = true
                if index + 1 < arguments.count, let value = AppLanguage(rawValue: arguments[index + 1]) {
                    seams.language = value; index += 1
                }
            default:
                break // unknown flags tolerated
            }
            index += 1
        }
        if let raw = environment["CHECKSTITCH_UITEST_SEED"], !raw.isEmpty {
            seams.isUITesting = true
            seams.seedURL = URL(fileURLWithPath: raw)
        }
        return seams
    }

    public static func current(processInfo: ProcessInfo = .processInfo) -> LaunchSeams {
        parse(arguments: processInfo.arguments, environment: processInfo.environment)
    }

    /// The seed envelope, or nil when absent, `isEmpty`, or unreadable.
    public func loadSeedEnvelope() -> ChecklistEnvelope? {
        guard !isEmpty, let seedURL, let data = try? Data(contentsOf: seedURL) else { return nil }
        switch ChecklistCodec.classify(data) {
        case .loaded(let envelope):            return envelope
        case .migratable(_, let envelope):     return envelope
        case .unsupportedVersion, .unreadable: return nil
        }
    }
}
```

#### 2. `ChecklistStore` seed parameter
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

Add `seed: ChecklistEnvelope? = nil` after `textEditDelay` in `init`. Directly
after the `deviceID` assignment block (`ChecklistStore.swift:31-38`), insert:

```swift
if let seed {
    self.checklists = seed.checklists
    self.tombstones = seed.tombstones
    self.folders = seed.folders
    self.folderTombstones = seed.folderTombstones
    self.canOverwriteStoredPayload = true
    return
}
```

This skips the defaults read entirely (design decision 3). `envelope` and every
mutator stay untouched.

#### 3. `MyApp.init()` branch
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add a stored property and read the seams first; guard every service start.

```swift
@State private var store: ChecklistStore
// … existing @State properties unchanged …
private let seams: LaunchSeams

init() {
    let seams = LaunchSeams.current()
    self.seams = seams

    if !seams.isUITesting {
        SentryBootstrap.startIfEnabled()
    }
    PurchaseEnvironment.service = PurchaseService(
        provider: StoreKitPurchaseService(),
        cache: PurchaseEntitlementCache(defaults: AppGroup.defaults))

    let defaults: UserDefaults
    if seams.isUITesting {
        let suite = LaunchSeams.uiTestingSuiteName
        defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
    } else {
        defaults = AppGroup.defaults
    }

    let store = ChecklistStore(defaults: defaults, seed: seams.loadSeedEnvelope())
    if let language = seams.language { AppLocaleState.current.set(language) }

    let syncService = ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store)
    if !seams.isUITesting { syncService.start() }

    _store = State(initialValue: store)
    // … every existing _…ViewModel assignment unchanged, except:
    _backgroundViewModel = State(initialValue: BackgroundViewModel(isUITesting: seams.isUITesting))
    _syncService = State(initialValue: syncService)
    _purchaseService = State(initialValue: PurchaseEnvironment.service)
}
```

In both `WindowGroup` bodies, pass the seams to `ContentView` and guard the
service tasks (macOS and iOS branches):

```swift
ContentView(seams: seams)
    // … .environment(...) chain unchanged …
    .task { if !seams.isUITesting { await syncService.syncOnLaunch() } }
    .task { if !seams.isUITesting { await purchaseService.start() } }
```

Guard the iOS coordinator `.task` with `guard !seams.isUITesting else { return }`
as its first line, and wrap both `scenePhase` `.onChange` bodies in
`if !seams.isUITesting { … }` so no reconcile/push happens in hermetic mode.

#### 4. `BackgroundViewModel` hermetic guard
**File**: `CheckStitch/BackgroundViewModel.swift`
**Action**: modify

```swift
@MainActor
@Observable
final class BackgroundViewModel {
    var image: BackgroundImageStore
    private let isUITesting: Bool

    init(image: BackgroundImageStore = BackgroundImageStore(), isUITesting: Bool = false) {
        self.image = image
        self.isUITesting = isUITesting
    }

    func task(pinned: Bool) async {
        await image.setPinned(pinned)
        if isUITesting {
            image.loadStoredImage()   // disk only; no network
            return
        }
        await image.refreshIfNeeded()
    }
    // … setPinned unchanged …
}
```

`loadStoredImage()` (`CheckStitch/BackgroundImageStore.swift:151`) is internal to
the app target, so no visibility change is needed. Under UI testing it reads the
staged `background.jpg`; with nothing staged it renders the plain background.

#### 5. `ContentView` seam parameter
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add a stored property (default keeps tests/previews compiling):

```swift
struct ContentView: View {
    var seams = LaunchSeams()
    // … existing @Environment / @AppStorage / @State unchanged …
```

Add a `.task` beside the existing `consumePendingSharedImport()` task:

```swift
.task {
    if seams.openSettings {
        settingsVM.begin(from: settingsSnapshot())
    }
    if let index = seams.openChecklistIndex,
       listVM.checklists.indices.contains(index) {
        path = [listVM.checklists[index].id]
    }
}
```

(Phase 1 only needs the property to exist; wiring is exercised in Phase 4.)

#### 6. `scripts/appstore-screenshots.sh`
**File**: `scripts/appstore-screenshots.sh`
**Action**: create (mode `100755`)

Walking-skeleton shape — `resolve_udid`, `boot_and_install`, `shoot`,
`verify_size`, one class, `--no-build` / `--no-install` / `-h` / unknown `-*`
exits 2:

```bash
#!/bin/bash
# scripts/appstore-screenshots.sh — App Store captures, per language and
# display class. `-h` prints this header.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE=app.alanvardy.CheckStitch
SCHEME=CheckStitch
DD=build/appstore-dd
APP="$DD/Build/Products/Debug-iphonesimulator/CheckStitch.app"
OUT=build/appstore-screenshots
SETTLE="${SETTLE:-6}"
SEED_FILE="$PWD/scripts/fixtures/appstore-seed.json"
BUILD=1
INSTALL=1
CLASSES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build)   BUILD=0; shift ;;
    --no-install) INSTALL=0; shift ;;
    -h|--help)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "!! unknown option: $1" >&2; exit 2 ;;
    *)            CLASSES+=("$1"); shift ;;
  esac
done

# class label : simctl devicetype name regex (newest runtime wins)
DEVICE_TYPES=( "iphone-6.3:iPhone 17$" )

resolve_udid() { # $1 = name regex, $2 = runtime family
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys
pattern, family = re.compile(sys.argv[1]), sys.argv[2]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if family not in runtime: continue
    version = tuple(int(n) for n in re.findall(r"[0-9]+", runtime.rsplit(".", 1)[-1]))
    for device in devices:
        if pattern.match(device["name"]) and (best is None or version > best[0]):
            best = (version, device["udid"])
print(best[1] if best else "")
' "$1" "$2"
}

boot_and_install() { # $1 = udid
  local udid=$1
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  if [ "$INSTALL" -eq 1 ]; then xcrun simctl install "$udid" "$APP"; fi
}

shoot() { # $1 = output path, rest = launch arguments
  local out=$1; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" \
    xcrun simctl launch "$UDID" "$BUNDLE" --terminate-running-process "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "$out" >/dev/null
  echo "    ${out#"$OUT/"}"
}

verify_size() { # $1 = file, $2 = accepted WxH
  local dims
  dims=$(sips -g pixelWidth -g pixelHeight "$1" | tail -2 | tr -dc '0-9\n' | paste -sd x -)
  if [ "$dims" != "$2" ]; then
    echo "!! ${1} is ${dims}, expected ${2}" >&2; return 1
  fi
}

capture_class() { # $1 = class label, $2 = name regex, $3 = accepted size
  local label=$1 pattern=$2 size=$3 udid dir
  udid=$(resolve_udid "$pattern" iOS)
  [ -n "$udid" ] || { echo "!! no available simulator for '$pattern'" >&2; return 1; }
  UDID=$udid
  boot_and_install "$UDID"
  dir="$OUT/en/$label"; mkdir -p "$dir"
  shoot "$dir/1-main-dark.png" --ui-testing --ui-testing-empty
  verify_size "$dir/1-main-dark.png" "$size"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

[ ${#CLASSES[@]} -gt 0 ] || CLASSES=(iphone-6.3)
rm -rf "$OUT"; mkdir -p "$OUT"

if [ "$BUILD" -eq 1 ]; then
  xcodebuild -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" build >/dev/null
fi

for entry in "${DEVICE_TYPES[@]}"; do
  label=${entry%%:*}; pattern=${entry#*:}
  for wanted in "${CLASSES[@]}"; do
    [ "$wanted" = "$label" ] && capture_class "$label" "$pattern" "1206x2622"
  done
done
echo "==> done: $OUT"
```

#### 7. Harness cases
**File**: `scripts/tests/run.sh`
**Action**: modify

Append a section before the `bash -n` block. Add a helper that stubs
`xcrun`/`xcodebuild`/`sips` on `PATH` (mirroring `new_stubs`): the `xcrun` stub
returns the device JSON for `simctl list devices available --json`, a fixed
directory for `simctl get_app_container`, creates the last-argv file for
`simctl io`, and logs every call; the `sips` stub prints the pair the case wants.

```bash
# --- appstore-screenshots.sh ------------------------------------------------

stub_appstore_capture() { # $1 = "WxH" the sips stub reports
    local pair="$1"
    new_stubs xcrun xcodebuild sips
    cat >"$STUB_ROOT/xcrun" <<STUB
#!/bin/bash
echo "\$*" >>"$STUB_ROOT/xcrun.log"
case "\$1 \$2" in
  "simctl list")
    echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"iPhone 17","udid":"IPHONE-UDID-1","state":"Shutdown"}]}}' ;;
  "simctl get_app_container")
    echo "$STUB_ROOT/container" ;;
  "simctl io")
    for last in "\$@"; do :; done
    mkdir -p "\$(dirname "\$last")"; : >"\$last" ;;
esac
exit 0
STUB
    chmod +x "$STUB_ROOT/xcrun"
    cat >"$STUB_ROOT/sips" <<STUB
#!/bin/bash
echo "pixelWidth: ${pair%x*}"
echo "pixelHeight: ${pair#*x}"
STUB
    chmod +x "$STUB_ROOT/sips"
}

appstore_boots_installs_and_launches_empty_state() {
    stub_appstore_capture 1206x2622
    bash scripts/appstore-screenshots.sh iphone-6.3 >/dev/null 2>&1 || return 1
    grep -q 'simctl boot IPHONE-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'simctl install IPHONE-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'simctl launch IPHONE-UDID-1 app.alanvardy.CheckStitch' "$STUB_ROOT/xcrun.log" || return 1
    grep -q -- '--ui-testing-empty' "$STUB_ROOT/xcrun.log"
}

appstore_size_mismatch_exits_one_and_names_file() {
    stub_appstore_capture 999x999
    local out status
    set +e
    out="$(bash scripts/appstore-screenshots.sh iphone-6.3 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"1-main-dark.png"* ]]
}

run_case appstore_boots_installs_and_launches_empty_state appstore_boots_installs_and_launches_empty_state
run_case appstore_size_mismatch_exits_one_and_names_file appstore_size_mismatch_exits_one_and_names_file
```

#### 8. `LaunchSeamsTests`
**File**: `CheckStitchTests/LaunchSeamsTests.swift`
**Action**: create

Swift Testing, `import CheckStitchCore`, `import Testing`. Cases:

```swift
struct LaunchSeamsTests {
    @Test func noArgumentsIsANoOp() {
        #expect(LaunchSeams.parse(arguments: [], environment: [:]) == LaunchSeams())
    }

    @Test(arguments: [
        ["--ui-testing"], ["--ui-testing-empty"], ["--ui-testing-open-settings"],
    ])
    func eachFlagTurnsOnUITesting(_ arguments: [String]) {
        #expect(LaunchSeams.parse(arguments: arguments, environment: [:]).isUITesting)
    }

    @Test func emptyFlagSetsIsEmpty() { /* --ui-testing-empty → isEmpty */ }
    @Test func openSettingsFlagSetsOpenSettings() { /* … */ }
    @Test func openChecklistParsesIndex() { /* ["--ui-testing-open-checklist","3"] → 3 */ }
    @Test func openChecklistIgnoresNonInteger() { /* → nil, still UITesting */ }
    @Test func appLanguageParsesEveryPinnedId() { /* AppLanguage.allCases minus .system */ }
    @Test func unknownLanguageIsNil() { /* "xx" → nil */ }
    @Test func unknownFlagIsTolerated() { /* ["--not-a-flag"] → no-op */ }
    @Test func environmentSeedBecomesAFileURL() { /* env = /tmp/x.json */ }

    @Test func uiTestingWithoutSeedLoadsNoEnvelope() { /* isEmpty == false, no seed → nil */ }

    @Test func malformedSeedFileLoadsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).json")
        try Data("{not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var seams = LaunchSeams(); seams.seedURL = url
        #expect(seams.loadSeedEnvelope() == nil)
    }

    @Test func validSeedFileLoadsEnvelope() throws { /* write a minimal v6 envelope; #expect envelope != nil */ }
}
```

The valid-seed JSON body is the same minimal shape as `appstore-seed.json`
(below): `{"version":6,"deviceID":"t","checklists":[{"id":"<uuid>","name":"A","items":[{"id":"<uuid>","title":"x"}]}]}`.

### Verification

#### Automated
- [x] `make test-unit` passes (new `LaunchSeamsTests` green; existing suites unaffected)
- [x] `bash scripts/tests/run.sh` passes (two new `appstore_*` cases green)
- [x] `make build` succeeds with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (new Core + app files compile)
- [x] `bash -n scripts/appstore-screenshots.sh` and `shellcheck scripts/appstore-screenshots.sh` are clean

#### Manual
- [ ] `make build && bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` writes `build/appstore-screenshots/en/iphone-6.3/1-main-dark.png` and prints no size error
- [ ] `sips -g pixelWidth -g pixelHeight build/appstore-screenshots/en/iphone-6.3/1-main-dark.png` reports `1206` × `2622`
- [ ] The shot shows the empty state (no list rows), proving `--ui-testing` + ephemeral defaults took effect
- [ ] `xcrun simctl get_app_container <udid> app.alanvardy.CheckStitch data` is unchanged after the run (real App Group container untouched)

---

## Phase 2: Deterministic wallpapers staged into the app container

### Changes

#### 1. Wallpaper fixtures
**File**: `scripts/fixtures/appstore-wallpapers/` (10 JPEGs + `manifest.json`)
**Action**: create

Copy the reference set from `/Users/vardy/dev/SingleThread/scripts/fixtures/appstore-wallpapers/`
(2.0 MB, Unsplash credits) and remap the slot families to CheckStitch's names.
The five screen slots map `options` → `settings` and `no-reminders` → `detail`,
for classes `iphone-6.3` and `ipad-13`:

```bash
mkdir -p scripts/fixtures/appstore-wallpapers
cp /Users/vardy/dev/SingleThread/scripts/fixtures/appstore-wallpapers/*.{jpg,json} \
   scripts/fixtures/appstore-wallpapers/
cd scripts/fixtures/appstore-wallpapers
for c in iphone-6.3 ipad-13; do
  mv "$c-options.jpg"      "$c-settings.jpg"
  mv "$c-no-reminders.jpg" "$c-detail.jpg"
done
python3 - <<'PY'
import json
p = "manifest.json"
m = json.load(open(p))
out = {}
for k, v in m.items():
    nk = k.replace("-options", "-settings").replace("-no-reminders", "-detail")
    v["file"] = v["file"].replace("-options", "-settings").replace("-no-reminders", "-detail")
    out[nk] = v
json.dump(out, open(p, "w"), indent=2, sort_keys=True)
PY
```

The staged files must land at:
`<app data container>/Library/Application Support/CheckStitch/background.jpg`
plus a sibling `background.json` with keys `photographer`, `photographerURL`
(optional) and `fetchedAt` — exactly what `BackgroundImageStore` reads
(`BackgroundImageStore.swift:29-34,88,151-162,190`). This is a confirmation, not
a code change.

#### 2. Wallpaper staging + fetch options in the script
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

Add after `DEVICE_TYPES`:

```bash
IOS_WALLPAPER_DIR="${WALLPAPER_DIR:-scripts/fixtures/appstore-wallpapers}"
MANIFEST="$IOS_WALLPAPER_DIR/manifest.json"
WALLPAPER_API="${WALLPAPER_API:-https://vardy.cc/unsplash/random}"
FETCH_WALLPAPERS=0
REFETCH_WALLPAPERS=0
WALLPAPER_URLS=()

# <wallpaper slot>:<output stem>; slots are per class, not per language.
SCREENS=(
  "main-dark:1-main-dark"
  "empty:2-empty"
  "settings:3-settings"
  "main-light:4-main-light"
  "detail:5-detail"
)

wallpaper_dir() { # app-private photo directory inside the app container
  local container
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  echo "$container/Library/Application Support/CheckStitch"
}

stage_slot() { # $1 = class, $2 = screen — pin that slot's photo into the app
  local slot="$1-$2" dir
  [ -f "$MANIFEST" ] || { echo "!! no wallpaper manifest at $MANIFEST" >&2; return 1; }
  dir=$(wallpaper_dir); mkdir -p "$dir"
  python3 - "$MANIFEST" "$slot" "$dir" <<'PY'
import datetime, json, os, shutil, sys
manifest_path, slot, target_dir = sys.argv[1:4]
entry = json.load(open(manifest_path)).get(slot)
if not entry: sys.exit(3)
source = os.path.join(os.path.dirname(manifest_path), entry["file"])
if not os.path.isfile(source): sys.exit(4)
shutil.copyfile(source, os.path.join(target_dir, "background.jpg"))
meta = {"photographer": entry["photographer"],
        "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
if entry.get("photographerURL"): meta["photographerURL"] = entry["photographerURL"]
json.dump(meta, open(os.path.join(target_dir, "background.json"), "w"))
PY
  echo "    wallpaper: $slot"
}
```

`fetch_wallpapers` is ported from the reference (same Python redraw/duplicate
guard, `--wallpaper-dir` / `--wallpaper-url` / `--wallpaper-api`, keys
`file, source, photographer, photographerURL, fetchedAt`); add
`--fetch-wallpapers`, `--refetch-wallpapers`, `--wallpaper-url <slot=url|url>`,
`--wallpaper-dir <dir>` to the CLI `case` (all except `-h` are new in this
phase). In `capture_class`, replace the single shot with the `SCREENS` loop:

```bash
for language in "${LANGUAGES[@]}"; do
  dir="$OUT/$language/$label"; mkdir -p "$dir"
  for entry in "${SCREENS[@]}"; do
    slot=${entry%%:*}; stem=${entry##*:}
    case "$stem" in
      *-dark) xcrun simctl ui "$UDID" appearance dark ;;
      *-light) xcrun simctl ui "$UDID" appearance light ;;
    esac
    stage_slot "$label" "$slot"
    shoot "$dir/$stem.png" --ui-testing
    verify_size "$dir/$stem.png" "$size"
  done
done
```

(`--ui-testing-empty` / seed args arrive in Phase 3/4; Phase 2 shoots the empty
state for every stem.)

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` passes with a new case that stubs
      `simctl get_app_container`, runs `--no-install --no-build`, and asserts
      `$STUB_ROOT/container/Library/Application Support/CheckStitch/background.jpg`
      and `background.json` exist with a non-empty `photographer`
- [x] `shellcheck scripts/appstore-screenshots.sh` and `bash -n` are clean

#### Manual
- [ ] `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` then
      `xcrun simctl get_app_container <udid> app.alanvardy.CheckStitch data` →
      the container holds `Library/Application Support/CheckStitch/background.jpg`
- [ ] Reopening the captured PNG shows the staged photo behind the card, not the plain background colour

---

## Phase 3: Seeded main list (dark + light)

### Changes

#### 1. Seed fixture
**File**: `scripts/fixtures/appstore-seed.json`
**Action**: create

A minimal version-6 `ChecklistEnvelope`: only `version`, `deviceID` and
`checklists` are required; checklists need `id`/`name`; items need `id`/`title`
(all other keys are `decodeIfPresent` with defaults — `Checklist.swift:619-672,363,101`).
Use fixed UUIDs so UI tests and screenshots are reproducible:

```json
{
  "version": 6,
  "deviceID": "appstore-screenshots",
  "checklists": [
    { "id": "11111111-1111-4111-8111-111111111111", "name": "Weekend Trip",
      "items": [
        { "id": "11111111-1111-4111-8111-111111111101", "title": "Book train tickets" },
        { "id": "11111111-1111-4111-8111-111111111102", "title": "Pack the charger" },
        { "id": "11111111-1111-4111-8111-111111111103", "title": "Water the plants" }
      ] },
    { "id": "22222222-2222-4222-8222-222222222222", "name": "Groceries",
      "items": [
        { "id": "22222222-2222-4222-8222-222222222201", "title": "Oat milk" },
        { "id": "22222222-2222-4222-8222-222222222202", "title": "Blueberries" }
      ] },
    { "id": "33333333-3333-4333-8333-333333333333", "name": "Morning Routine",
      "items": [
        { "id": "33333333-3333-4333-8333-333333333301", "title": "Stretch" },
        { "id": "33333333-3333-4333-8333-333333333302", "title": "Journal" }
      ] }
  ]
}
```

No `folders` (design decision 2). `showsOnWatch` defaults true, so the watch
seed below shows the same rows.

#### 2. List-row accessibility identifier
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

In `checklistRow(for:)`, on the non-editing `NavigationLink`:

```swift
NavigationLink(checklist.name, value: checklist.id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("checklistRow-\(checklist.id.uuidString)")
```

#### 3. Seed wiring in `MyApp`
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Already done by `ChecklistStore(defaults:, seed: seams.loadSeedEnvelope())`
(Phase 1) — no additional change beyond the Phase 1 block. Confirm the seed is
passed even for non-`isEmpty` UI-testing launches.

#### 3b. Store seed test
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Add one Swift Testing case using an isolated `UserDefaults(suiteName:)` suite:

```swift
@MainActor
@Test
func seedPopulatesTheStoreAndPermitsOverwrite() throws {
    let suite = "test.store.seed.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    // A newer-version payload would normally refuse to overwrite.
    defaults.set(Data("{\"version\": 99}".utf8), forKey: "checklists.v1")
    let seed = ChecklistEnvelope(
        version: ChecklistCodec.currentVersion, deviceID: "seed",
        checklists: [Checklist(name: "Seeded")])
    let store = ChecklistStore(defaults: defaults, key: "checklists.v1",
                               textEditDelay: nil, seed: seed)
    #expect(store.checklists.map(\.name) == ["Seeded"])
    #expect(store.canAcceptRemoteChanges)
}
```

#### 4. Script seed + appearance per `SCREENS` entry
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

In the `SCREENS` loop from Phase 2, pass the matching launch arguments:

```bash
case "$stem" in
  1-main-dark)  shoot "$dir/$stem.png" --ui-testing ;;
  2-empty)      shoot "$dir/$stem.png" --ui-testing --ui-testing-empty ;;
esac
```

`shoot` already exports `SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE"`, and
`--ui-testing-empty` makes `loadSeedEnvelope()` return nil, so the same binary
covers both shots. (Phases 4-6 replace this `case` with the full per-stem args.)

#### 5. UI test
**File**: `CheckStitchUITests/CheckStitchUITests.swift`
**Action**: modify

Add a seeded launch case and a private fixture writer:

```swift
@MainActor
func testUITestingSeededListRendersARow() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launchEnvironment["CHECKSTITCH_UITEST_SEED"] = try Self.writeSeedFixture().path
    app.launch()
    let row = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH 'checklistRow-'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "Seeded row should render")
}

private static func writeSeedFixture() throws -> URL {
    let json = """
    {"version":6,"deviceID":"uitest","checklists":[
      {"id":"11111111-1111-4111-8111-111111111111","name":"Weekend Trip",
       "items":[{"id":"11111111-1111-4111-8111-111111111101","title":"Book train tickets"}]}]}
    """
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("appstore-seed-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url, options: .atomic)
    return url
}
```

### Verification

#### Automated
- [x] `make test-unit` passes with the new `ChecklistStoreTests.seedPopulatesTheStoreAndPermitsOverwrite` case (seed populates `checklists`; `canAcceptRemoteChanges == true`)
- [x] `make test-ui` passes (new seeded case finds a `checklistRow-*`)
- [x] `bash scripts/tests/run.sh` passes with a case asserting the two-shot order (`1-main-dark` launched with the seed, `2-empty` with `--ui-testing-empty`)

#### Manual
- [ ] `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` writes `1-main-dark.png` (three seeded rows) and `2-empty.png` (empty state)
- [ ] The dark shot is dark and the light shot is light (`simctl ui … appearance` took effect)

---

## Phase 4: Settings and detail screens

### Changes

#### 1. Settings + detail seams
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

The `.task` added in Phase 1 already applies both seams:

```swift
if seams.openSettings { settingsVM.begin(from: settingsSnapshot()) }
if let index = seams.openChecklistIndex, listVM.checklists.indices.contains(index) {
    path = [listVM.checklists[index].id]
}
```

`settingsSnapshot()` (`ContentView.swift:863-872`) and `path` (`:24`) are the
existing members; `SettingsViewModel.begin(from:)` (`SettingsViewModel.swift:15-23`)
is unchanged. No route enum, no new presentation mechanism.

#### 2. `LaunchSeams` parsing
**File**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift`
**Action**: modify

Already parses `--ui-testing-open-settings` and `--ui-testing-open-checklist <n>`
(Phase 1). No change beyond confirming the index is positional over
`store.activeChecklists` in list order (`ChecklistListViewModel.checklists` is
`store.activeChecklists`, `ChecklistListViewModel.swift:17`).

#### 3. `MyApp`
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

No change beyond Phase 1's `ContentView(seams: seams)`.

#### 4. Script: all five iOS slots
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

Extend the per-stem `case`:

```bash
case "$stem" in
  1-main-dark)  shoot "$dir/$stem.png" --ui-testing ;;
  2-empty)      shoot "$dir/$stem.png" --ui-testing --ui-testing-empty ;;
  3-settings)   shoot "$dir/$stem.png" --ui-testing --ui-testing-open-settings ;;
  4-main-light) shoot "$dir/$stem.png" --ui-testing ;;
  5-detail)     shoot "$dir/$stem.png" --ui-testing --ui-testing-open-checklist 0 ;;
esac
```

`SCREENS` already declares all five slugs from Phase 2.

#### 5. UI tests
**File**: `CheckStitchUITests/CheckStitchUITests.swift`
**Action**: modify

```swift
@MainActor
func testUITestingOpenSettingsShowsSettingsSheet() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-open-settings"]
    app.launch()
    XCTAssertTrue(app.descendants(matching: .any)["appearancePicker"]
        .waitForExistence(timeout: 5), "Settings sheet should present")
}

@MainActor
func testUITestingOpenChecklistPushesDetail() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-open-checklist", "0"]
    app.launchEnvironment["CHECKSTITCH_UITEST_SEED"] = try Self.writeSeedFixture().path
    app.launch()
    XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5),
                  "A back button implies the detail screen was pushed")
}
```

`appearancePicker` is the existing identifier in `InterfaceSettingsView.swift:28`.

### Verification

#### Automated
- [x] `make test-unit` passes (`LaunchSeamsTests` flag cases from Phase 1 cover both flags)
- [x] `make test-ui` passes (four UI cases: smoke, seeded list, settings, detail)
- [x] `bash scripts/tests/run.sh` passes with a case asserting the five-shot `SCREENS` sequence and each stem's launch args

#### Manual
- [ ] `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` writes all five `en/iphone-6.3/*.png`
- [ ] `3-settings.png` shows the settings sheet; `5-detail.png` shows the first seeded checklist's items

---

## Phase 5: Multi-language loop

### Changes

#### 1. Language seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift`
**Action**: modify

Already parses `--ui-testing-app-language <id>` into `language: AppLanguage?`
(Phase 1); unknown ids parse to `nil`.

#### 2. Apply language before render
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Already done in Phase 1: `if let language = seams.language { AppLocaleState.current.set(language) }`
before the scene is built, so `\.locale` (`MyApp.swift:76,104`) uses it.

#### 3. `AppLocaleState`
**File**: `CheckStitchCore/Sources/CheckStitchCore/AppLocaleState.swift`
**Action**: modify

No code change; reuse the existing `set(_:)` (`AppLocaleState.swift:34-39`).

#### 4. Script language loop
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

```bash
LANGUAGES=(en de es fr ja zh-Hans)
```

Wrap the `SCREENS` loop in `for language in "${LANGUAGES[@]}"; do … done`, write
`"$OUT/$language/$label"`, and add `--ui-testing-app-language "$language"` to
every `shoot` call:

```bash
3-settings) shoot "$dir/$stem.png" --ui-testing --ui-testing-app-language "$language" --ui-testing-open-settings ;;
```

`AppLanguage` raw values are exactly these six ids (`AppLanguage.swift:5-17`), and
there are no new user-facing strings, so `LocalizationFixtures.requiredKeys` and
`scripts/l10n-check.sh` are untouched.

#### 5. `LaunchSeamsTests` language matrix
**File**: `CheckStitchTests/LaunchSeamsTests.swift`
**Action**: modify

```swift
@Test(arguments: ["en", "de", "es", "fr", "ja", "zh-Hans"])
func everyPinnedLanguageParses(_ raw: String) {
    let seams = LaunchSeams.parse(
        arguments: ["--ui-testing-app-language", raw], environment: [:])
    #expect(seams.language?.rawValue == raw)
}

@Test func unknownLanguageParsesNil() {
    let seams = LaunchSeams.parse(
        arguments: ["--ui-testing-app-language", "xx"], environment: [:])
    #expect(seams.language == nil)
}
```

### Verification

#### Automated
- [x] `make test-unit` passes with the six-id + unknown-language cases
- [x] `bash scripts/tests/run.sh` passes with a case (stubbed `sips`) asserting the six `<lang>/iphone-6.3/` directories exist after a run

#### Manual
- [ ] A full `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` run creates `en de es fr ja zh-Hans` folders, each with the five PNGs
- [ ] Opening the `ja` and `zh-Hans` main shots shows Japanese / Simplified Chinese chrome (buttons, nav title)

---

## Phase 6: iPad, standalone watch, and per-run manifest

### Changes

#### 1. Watch store seed + no-transport guard
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify (`WatchChecklistStore`)

```swift
/// UI-testing only: replace the mirrored list with a seeded envelope. While
/// seeded, `start()` and `requestRefresh()` are no-ops so no `WCSession` is
/// created.
public func seed(_ envelope: ChecklistEnvelope) {
    checklists = envelope.checklists
    folders = envelope.folders
    isSeeded = true
}

public func start() {
    guard !isSeeded else { return }
    transport.onMessage = { [weak self] in self?.receive($0) }
    transport.onActivated = { [weak self] in
        self?.requestRefresh()
        self?.retryPendingRuns()
    }
    transport.activate()
}

@discardableResult
public func requestRefresh() -> Bool {
    guard !isSeeded else { return false }
    return transport.sendUserInfo(.requestChecklists)
}
```

Add `@ObservationIgnored private var isSeeded = false` alongside the other
private stored properties.

#### 2. LaunchSeams in the watch app
**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: modify

```swift
@main
struct CheckStitchWatchApp: App {
    private let seams: LaunchSeams
    @State private var viewModel: WatchChecklistViewModel

    init() {
        let seams = LaunchSeams.current()
        self.seams = seams
        if let language = seams.language { AppLocaleState.current.set(language) }
        let store = WatchChecklistStore(transport: WatchSyncAdapter())
        if seams.isUITesting, let envelope = seams.loadSeedEnvelope() {
            store.seed(envelope)
        }
        _viewModel = State(initialValue: WatchChecklistViewModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView(initialChecklistIndex: seams.openChecklistIndex)
                .environment(viewModel)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
        }
    }
}
```

#### 3. Watch list programmatic detail push
**File**: `CheckStitchWatch/WatchChecklistListView.swift`
**Action**: modify

```swift
struct WatchChecklistListView: View {
    var initialChecklistIndex: Int? = nil
    @Environment(WatchChecklistViewModel.self) private var viewModel
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group { /* existing empty/list branches unchanged */ }
                .navigationTitle("Checklists")
                .navigationDestination(for: UUID.self) { id in
                    if let checklist = viewModel.checklists.first(where: { $0.id == id }) {
                        WatchChecklistDetailView(checklist: checklist)
                    }
                }
        }
        .tint(.blue)
        .task {
            viewModel.onAppear()
            if let index = initialChecklistIndex,
               viewModel.checklists.indices.contains(index) {
                path = [viewModel.checklists[index].id]
            }
        }
    }
}
```

`viewModel.onAppear()` still calls `store.start()` / `store.requestRefresh()`,
which are now guard-protected while seeded, so the seeded simulator never
activates `WCSession`. Watch screens: `1-list` and `2-detail`, no wallpaper slots.

#### 4. Script iPad + watch legs and manifest
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

```bash
DEVICE_TYPES=(
  "iphone-6.3:iPhone 17$"
  "ipad-13:iPad Pro 13-inch \\(M5\\)"
)
WATCH_CLASS=watch-46mm
WATCH_PATTERN='Apple Watch Series 11 \(46mm\)'
WATCH_BUNDLE=app.alanvardy.CheckStitch.watchkitapp
WATCH_APP="$DD/Build/Products/Debug-watchsimulator/CheckStitchWatch.app"
WATCH_SCREENS=( "1-list" "2-detail" )

# No associative arrays: /bin/bash 3.2 (the gate's `bash -n` parser) rejects them.
size_for() { # $1 = class label
  case "$1" in
    iphone-6.3) echo "1206x2622" ;;
    ipad-13)    echo "2064x2752" ;;
    watch-46mm) echo "416x496" ;;
  esac
}
```

- `ipad-13` reuses `capture_class` with its own size (Phase 2's `capture_class`
  gains a `size` argument); the class loop passes `"$(size_for "$label")"`.
- `capture_watch` mirrors the reference: `udid=$(udid_override_for watch-46mm)`,
  falling back to `resolve_udid "$WATCH_PATTERN" watchOS`, then `boot_and_install`
  against `WATCH_BUNDLE`/`WATCH_APP`, then per language two `watch_shot` calls
  (`--ui-testing`; `--ui-testing-open-checklist 0` for `2-detail`), each followed
  by `verify_size "$..." "416x496"`.

```bash
watch_shot() { # $1 = output path, rest = watch launch arguments
  local out=$1; shift
  xcrun simctl terminate "$UDID" "$WATCH_BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" \
    xcrun simctl launch "$UDID" "$WATCH_BUNDLE" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "$out" >/dev/null
  echo "    ${out#"$OUT/"}"
}
```
- `build` also runs `xcodebuild -scheme CheckStitchWatch … -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$DD"` when `watch-46mm` is requested.

Manifest writer:

```bash
write_manifest() { # $1 = lang, $2 = class, $3 = device model, $4 = udid, $5 = size, rest = screens
  local lang=$1 class=$2 device=$3 udid=$4 size=$5; shift 5
  python3 - "$OUT/$lang/$class/manifest.json" "$class" "$device" "$udid" "$size" "$@" <<'PY'
import json, sys
path, klass, device, udid, size, *screens = sys.argv[1:]
json.dump({"class": klass, "device": device, "udid": udid,
           "size": size, "screens": screens},
          open(path, "w"), indent=2, sort_keys=True)
PY
}
```

Call `write_manifest "$language" "$label" "$pattern" "$UDID" "$(size_for "$label")" "${stems[@]}"`
at the end of each language's capture loop (and the watch equivalent with
`"$(size_for watch-46mm)" "${WATCH_SCREENS[@]}"`).

#### 5. Tests
**Files**: `CheckStitchTests/WatchChecklistStoreTests.swift`, `scripts/tests/run.sh`
**Action**: modify

```swift
@Test func seedPopulatesWithoutStartingTheTransport() {
    let transport = FakeChecklistSyncTransport()
    let store = WatchChecklistStore(transport: transport)
    let envelope = ChecklistEnvelope(
        version: ChecklistCodec.currentVersion, deviceID: "",
        checklists: [Checklist(name: "Groceries")])
    store.seed(envelope)
    #expect(store.checklists.map(\.name) == ["Groceries"])
    store.start()
    #expect(transport.activateCount == 0)
}
```

Harness: add a case that runs the watch class with a stubbed watchOS device JSON
and asserts the `watchkitapp` install/launch argv, and a case asserting
`manifest.json` exists with `class`/`device`/`udid`/`size`/`screens` keys.

### Verification

#### Automated
- [x] `make test-unit` passes (`WatchChecklistStoreTests` seed case green; `LaunchSeamsTests` shared by app and watch)
- [x] `make watch-build` succeeds
- [x] `bash scripts/tests/run.sh` passes with the watch + manifest cases

#### Manual
- [ ] `bash scripts/appstore-screenshots.sh` (all classes, `--no-build` after one build) writes `iphone-6.3`, `ipad-13` and `watch-46mm` folders for all six languages
- [ ] Both watch PNGs are `416×496`; `1-list.png` shows the seeded rows and `2-detail.png` shows the first checklist's items
- [ ] Each `manifest.json` lists the captured screens in order

---

## Phase 7: Hardening, CLI surface, docs

### Changes

#### 1. Full CLI + pre/post-flight checks
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

Add options to the `while` loop:

```bash
--settle) SETTLE=$2; shift 2 ;;
--lang)   LANGUAGES=("$2"); shift 2 ;;
--udid)
  # Parallel arrays, not an associative array: /bin/bash 3.2 rejects `declare -A`.
  OVERRIDE_CLASSES+=("${2%%=*}")
  OVERRIDE_UDIDS+=("${2#*=}")
  shift 2
  ;;
```

with `OVERRIDE_CLASSES=()` / `OVERRIDE_UDIDS=()` declared beside `CLASSES`.
`capture_class` and `capture_watch` consult the override before resolving:

```bash
udid_override_for() { # $1 = class label; prints the UDID or nothing
  local i
  for i in "${!OVERRIDE_CLASSES[@]}"; do
    if [ "${OVERRIDE_CLASSES[$i]}" = "$1" ]; then printf '%s' "${OVERRIDE_UDIDS[$i]}"; return 0; fi
  done
}

# at the top of capture_class / capture_watch:
udid=$(udid_override_for "$label")
[ -n "$udid" ] || udid=$(resolve_udid "$pattern" iOS)
```

Add a pre-flight, called after `boot_and_install` and before the first shot:

```bash
preflight_size() { # $1 = udid, $2 = expected WxH
  local tmp dims
  tmp=$(mktemp -t appstore-preflight).png
  xcrun simctl io "$1" screenshot --mask ignored "$tmp" >/dev/null
  dims=$(sips -g pixelWidth -g pixelHeight "$tmp" | tail -2 | tr -dc '0-9\n' | paste -sd x -)
  rm -f "$tmp"
  if [ "$dims" != "$2" ]; then
    echo "!! simulator $1 captures ${dims}, expected ${2}" >&2; return 1
  fi
}
```

`verify_size` (post-flight) already names the offending file and exits non-zero
via `set -e`. Expand the header comment into the `-h` documentation (classes,
options, output tree, wallpaper fixtures); keep unknown `-*` → exit 2.

#### 2. Makefile target
**File**: `Makefile`
**Action**: modify

Add `appstore-screenshots` to `.PHONY` and:

```make
# Capture App Store screenshots (not part of the gate). ARGS pass through to
# the script, e.g. `make appstore-screenshots ARGS='iphone-6.3 --no-build'`.
appstore-screenshots:
	bash scripts/appstore-screenshots.sh $(ARGS)
```

#### 3. `AGENTS.md`
**File**: `AGENTS.md`
**Action**: modify

Add an "App Store screenshots" section under "Build, run, gate":

```markdown
- `make appstore-screenshots` / `bash scripts/appstore-screenshots.sh [class ...]`
  captures per-language App Store PNGs into
  `build/appstore-screenshots/<lang>/<device>/`. Classes: `iphone-6.3`
  (iPhone 17, 1206×2622), `ipad-13` (iPad Pro 13-inch (M5), 2064×2752),
  `watch-46mm` (Apple Watch Series 11 (46mm), 416×496). Wallpapers live in
  `scripts/fixtures/appstore-wallpapers/` (slot `<class>-<screen>`). The app
  reads the same launch seams under `--ui-testing*`; `LaunchSeams` in
  `CheckStitchCore` is the only arg reader. This run is **not** part of
  `scripts/test.sh`. Device lookup by name is the exception to the no-bare-name
  rule and always resolves to a UDID before any `simctl` call.
```

#### 4. Harness option/edge cases
**File**: `scripts/tests/run.sh`
**Action**: modify

```bash
appstore_help_prints_and_exits_zero() {
    local out
    out="$(bash scripts/appstore-screenshots.sh -h)"
    [[ "$out" == *"Usage:"* ]]
}

appstore_unknown_flag_exits_two() {
    local status
    set +e; bash scripts/appstore-screenshots.sh --nope >/dev/null 2>&1; status=$?; set -e
    [[ $status -eq 2 ]]
}

appstore_preflight_mismatch_names_the_simulator() {
    stub_appstore_capture 999x999
    local out status
    set +e; out="$(bash scripts/appstore-screenshots.sh iphone-6.3 2>&1)"; status=$?; set -e
    [[ $status -ne 0 && "$out" == *"expected 1206x2622"* ]]
}

run_case appstore_help_prints_and_exits_zero appstore_help_prints_and_exits_zero
run_case appstore_unknown_flag_exits_two appstore_unknown_flag_exits_two
run_case appstore_preflight_mismatch_names_the_simulator appstore_preflight_mismatch_names_the_simulator
```

#### 5. Determinism run
No code change: a clean-clone, no-network run is a manual check below. No new
gate leg is added; `shellcheck` + the harness remain the script's gate.

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` passes (all `appstore_*` cases, option-parse, `-h`, unknown flag, pre/post-flight)
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` and `bash -n` are clean
- [x] `bash scripts/test.sh` prints `gate: ok`
- [x] The capture run is absent from `scripts/test.sh` (grep for `appstore-screenshots` returns nothing)

#### Manual
- [ ] Two consecutive `bash scripts/appstore-screenshots.sh --no-build` runs produce byte-identical PNGs (`shasum build/appstore-screenshots/**/*.png` before/after)
- [ ] A clean clone with networking disabled still produces the full tree (wallpapers are committed, not fetched)
- [ ] `make appstore-screenshots ARGS='iphone-6.3 --no-build'` runs the script
- [ ] A deliberate `--udid iphone-6.3=<wrong-udid>` on a wrong-class simulator fails at pre-flight naming the simulator, before any capture
