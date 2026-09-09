# Done

- **Branch / head SHA**: `alanvardy-var-893-get-something-running-on-iphone` @ `2684077`
- **Mechanical checks**:
  - `xcodebuild -scheme CheckStitch -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath DerivedData build` → **BUILD SUCCEEDED** (re-run after fixes; Swift 6.0 / iOS-only platforms / productName rename all compile)
  - `bash -n scripts/run-devices.sh` → OK; `shellcheck scripts/run-devices.sh` → clean
  - `plutil -lint CheckStitch/AppGroup.entitlements` → OK
  - `codesign --verify --deep --strict` → valid; `codesign -d --entitlements -` shows `application-identifier = 6NWX2DHB9Q.app.alanvardy.CheckStitch` and `com.apple.security.application-groups = group.app.alanvardy.CheckStitch`
  - Info.plist identity: `CFBundleIdentifier = app.alanvardy.CheckStitch`, `CFBundleName = CheckStitch`, `MinimumOSVersion = 18.7`
- **Review outcome**:
  - **Blocker fixed** — `scripts/run-devices.sh` device discovery was broken (`devicectl list devices -j` missing its `<path>` value; jq filter read a non-existent schema). Rewritten to match the proven SingleThread parser (`result.devices[]`, `hardwareProperties`/`deviceProperties`/`connectionProperties`), prefer iPhone, guard the `jq` dependency, and avoid clobbering `$TMPDIR` (commit `6ee30bf`). Verified against live `devicectl` output: resolves "Alan's iPhone" (`6C1EA973-…`).
  - **Fix applied** — `-allowProvisioningUpdates` added to the build step so a clean clone provisions once (per `implement.md` fresh-machine caveat).
  - **Optional improvements applied** (commit `2684077`) — `SWIFT_VERSION` 5.0 → 6.0, `SUPPORTED_PLATFORMS` → `"iphoneos iphonesimulator"`, `TARGETED_DEVICE_FAMILY` → `"1,2"`, `productName` `MyApp` → `CheckStitch`, trailing newline on `AppGroup.entitlements`; doc-drift ("three levels"/"~50-line") corrected in `structure.md` and `design.md`.
- **Convention decision deferred (needs user call)** — `.pi/…/plan.md` and `linear-project.md` are committed while other `.pi/` docs stay untracked, contradicting «`.pi/` docs untracked by design». Not touched; recommend `git rm --cached .pi/…/plan.md` + add `.pi/` to `.gitignore` if that convention is intended.
- **Declined / deferred** — App icon (needs real binary assets, out of scope); signing "team mismatch" (refuted — the app is correctly signed to team `6NWX2DHB9Q` and both devices are provisioned).
- **Remaining manual items**:
  - Run `bash scripts/run-devices.sh` end-to-end on the physical device (did not perform — installs/launches on the user's iPhone, a live side effect).
  - Confirm "Hello, world!" is visible on the iPhone screen.