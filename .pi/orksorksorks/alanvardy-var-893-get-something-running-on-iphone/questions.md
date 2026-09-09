# Research Questions

## Context

Two sibling iOS repositories live side by side on this machine: a fresh
default Xcode SwiftUI scaffold at
/Users/vardy/dev/alanvardy-var-893-get-something-running-on-iphone, and a
mature SwiftUI app at /Users/vardy/dev/SingleThread that builds, signs, and
runs on physical devices. Focus on the Xcode project configuration,
signing/entitlements setup, device build+install scripts, verification
commands, and the machine's current signing/device environment. Report what
exists and how it works, with file:line references.

## Questions

1. How is the scaffold app in /Users/vardy/dev/alanvardy-var-893-get-something-running-on-iphone
   configured today? Enumerate every setting in CheckStitch.xcodeproj/project.pbxproj
   that governs building for a device: product type, platform, SDKROOT,
   deployment target, supported platforms, targeted device family, code
   signing style and team, bundle identifier, register-app-groups, and any
   icon/asset/entitlements references. Also inventory the source files and
   asset catalog as they exist.

2. How does /Users/vardy/dev/SingleThread configure signing and device
   deployment in SingleThread.xcodeproj/project.pbxproj? Trace all
   signing-related settings (DEVELOPMENT_TEAM, CODE_SIGN_STYLE,
   CODE_SIGN_ENTITLEMENTS, CODE_SIGN_IDENTITY), the bundle identifiers for
   each target, the sdk-conditioned setting variants (iphoneos,
   iphonesimulator, macosx), AppGroup.entitlements, app icon settings,
   deployment targets, and targeted device families. Note which settings
   apply to which target and how they interlock.

3. What does /Users/vardy/dev/SingleThread/scripts/run-devices.sh do?
   Trace the full physical-device flow: how it detects devices and filters
   them, what xcodebuild invocation and destination it uses, how it installs
   and launches the app on the device, what bundle ID and team values it
   passes, and its error handling and exit behavior.

4. What build/verify/test commands does the SingleThread project define,
   and how are they combined? Survey the Makefile targets, scripts/test.sh
   flow, scripts/simverify.sh, scripts/distribute-macos.sh, and the
   .github/workflows/ci.yml jobs. Note which steps build for a device vs
   simulator vs macOS, which neutralize or override signing (for example
   DEVELOPMENT_TEAM overrides), and any deployment-target or config
   consistency guards.

5. What is the current machine environment relevant to building and signing
   for a physical iOS device? Determine: installed Xcode/xcodebuild version
   and toolchain, available code-signing identities (security find-identity
   and iprofile), the Apple team/account state (iprofile provisioning),
   any connected physical devices and their Developer Mode state (xcrun
   devicectl list devices and similar read-only commands), and the presence
   of the SingleThread signing identity on this machine. Report only what is
   observed; do not modify anything.

6. Where do app identifiers and display names live outside the pbxproj in
   both repositories? Find concrete examples of how the bundle ID, suite
   name, display name, and team ID are threaded through source files, plist
   files, string files, and scripts (for example suiteName strings,
   InfoPlist/Info.plist files, en.lproj string catalogs, and references in
   scripts and docs). Cite each location and how the identifier is used
   there.