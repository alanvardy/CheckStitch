# Done

- **Branch / head SHA**: `alanvardy-var-994-macos-build-shows-no-background-photo-works-on-iphoneipad` @ `6506bee58c1d4c46868b89bb01750711a32d780d` (rebased on `main` @ `7aacadf`; working tree clean; no rebase conflicts; local == `origin/*`, nothing left to push)
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` (simulator build, headless pre-boot, unit + UI smoke, unsigned macOS leg, watchOS leg, `scripts/tests/run.sh` 17 passed / 0 failed including the new `macos_slice_requests_outgoing_network` pin, `shellcheck` clean). No warnings beyond the pre-existing watchOS AppIntents "Metadata extraction skipped" note.
- **Review outcome**:
  - Diff vs `main`: `CheckStitch.xcodeproj/project.pbxproj` (+2: `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;` in the app target's Debug and Release configs), `scripts/tests/run.sh` (+18: regression pin), plus pipeline artifacts.
  - One bounded fresh-context reviewer, five adapted angles (fix correctness, entitlement placement, pin robustness, shell correctness, docs). **No blockers.**
  - Fix correctness confirmed: `ENABLE_APP_SANDBOX = YES;` occurs exactly twice (lines 497, 542), both in the `CheckStitch` app target's Debug/Release blocks for `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`; the watch target and test targets are not sandboxed. Entitlement belongs in the build settings (which synthesize `com.apple.security.network.client`) and *not* in the shared `CheckStitch/AppGroup.entitlements`, which is code-signed into all three SDK slices.
  - Pin catches the real regression (removing either egress line drops the count and fails). It is a whole-file count equality, not per-block co-location — accepted as adequate for the stated invariant, optional hardening deferred.
  - No fixes applied — the two reviewer P2 items are test-quality/defensive, not current defects; optional improvements left to the user.
- **Remaining manual items** (from `plan.md` / `implement.md`, unchanged by this review):
  - [ ] Signed launch + Settings → **Refresh wallpaper** with `log stream --predicate 'subsystem == "app.alanvardy.CheckStitch"'` running: no `Background force refresh failed`, and the photo renders (default 50 and faded opacity, correct across window resizes).
  - [ ] `make run` on the simulator: iOS rendering unchanged (iOS received no code change).