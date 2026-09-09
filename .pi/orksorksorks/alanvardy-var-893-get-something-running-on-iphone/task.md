# Task

CheckStitch is a brand-new repo containing only the default Xcode SwiftUI
scaffold (MyApp.swift, ContentView.swift, a stock pbxproj, no entitlements).
The goal is to get this app building, signing, and running on the developer's
physical iPhone — not just the simulator. The sibling SingleThread repo at
/Users/vardy/dev/SingleThread carries a proven on-device setup (signing team,
bundle ID, entitlements, and a build+install+launch script) that this effort
mirrors. Success means the app installs and launches on the actual device.