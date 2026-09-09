# Task

This is a brand-new repo: `CheckStitch` is currently just the default Xcode
SwiftUI scaffold (MyApp.swift, ContentView.swift, a stock pbxproj, no
entitlements). The ticket asks to "get this app running on my iphone" — i.e.
deploy the freshly-scaffolded app to a physical iPhone and confirm it runs
there (not just the simulator). This requires determining and setting up the
device-deployment path: signing (developer account/personal team), bundle ID,
provisioning, device trust/registration, and the build+run flow for the
developer's actual hardware.

Reference resource: `@../SingleThread/` (`/Users/vardy/dev/SingleThread/`) is a
fully functioning SwiftUI app with a proven on-device setup — its
`SingleThread.xcodeproj/project.pbxproj` carries working device-deployment
config (DEVELOPMENT_TEAM, CODE_SIGN_STYLE/CODE_SIGN_ENTITLEMENTS, bundled
bundle identifiers, AppGroup.entitlements), and its scripts/docs folder the
verification flow. The analysis/plan steps should mine it for the exact
signing, provisioning, and build+run steps to replicate for CheckStitch.

## Why LARGE

UNKNOWNS + NEW_SURFACE + CONVENTION_RISK — deploying to a physical iPhone is
a new integration (device signing, entitlements, provisioning, bundle ID)
with several open questions about the developer's Apple account/device setup,
and it touches shared project config (pbxproj signing settings) where a
misstep blocks all future builds.