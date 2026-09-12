# Implementation Plan

## Overview

CheckStitch keeps its iPhone authoring flow, grows a tested `CheckStitchCore`
package (model, codec, file store), persists checklists, and adds an embedded
companion `CheckStitchWatch` app that lists saved checklists and runs one by
sending a WatchConnectivity message the phone turns into Reminders. The watch
never writes EventKit.

> **Deployment-target correction (read first).** `structure.md` says watchOS
> `27.0` (taken from the project-level `WATCHOS_DEPLOYMENT_TARGET`). The real
> target watch, `Alan's Apple Watch`, runs **watchOS 26.6** (`devicectl`, verified
> this session), and the installed SDK caps the supported target at
> `26.5.99`. A `27.0` deployment target produces SDK warnings and, more
> importantly, an app the real watch cannot install. **Every watch deployment
> target in this plan is `26.5`** (watch target + `CheckStitchCore` manifest).
> The pre-existing project-level `27.0` value is left untouched (target-level
> settings win); only files this ticket adds use `26.5`. This is a deliberate
> deviation — see "Deviations from structure.md".

## Phase order at a glance

| Phase | Deliverable | Automated check |
|---|---|---|
| 1 | `CheckStitchCore` package + tests + iOS package link | `swift test --package-path CheckStitchCore`; `make build` |
| 2 | iPhone persistence wiring | `make build` |
| 3 | `ReminderWriter` extraction | `make build` |
| 4 | `PhoneSyncService` transport | `make build` |
| 5 | Watch target + `watch-build` + `run-watch.sh` | `make watch-build`; `shellcheck` |
| 6 | `WatchSyncService` cache/sync | `make watch-build` |
| 7 | Watch UI (list → detail → Run) | `make watch-build` |
| 8 | Gate + docs | `./scripts/test.sh` |

---

## Phase 1: `CheckStitchCore` package — model, codec, store (+ tests)

Pure, dependency-free types and persistence both targets import. This is the
only phase with a fully automated suite. All code below was compiled and
`swift test` was run green during planning.

### Changes

#### 1. Package manifest
**File**: `CheckStitchCore/Package.swift`
**Action**: create

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CheckStitchCore",
    platforms: [
        .iOS("18.7"),
        .watchOS("26.5"),
        .macOS("27.0")
    ],
    products: [
        .library(name: "CheckStitchCore", targets: ["CheckStitchCore"])
    ],
    targets: [
        .target(name: "CheckStitchCore"),
        .testTarget(name: "CheckStitchCoreTests", dependencies: ["CheckStitchCore"])
    ])
```

`watchOS("26.5")` (not `27.0`) — see the Overview correction. `macOS("27.0")`
matches the host (macOS 27.0) and the app's `MACOSX_DEPLOYMENT_TARGET`; `swift
test` builds/runs on the host.

#### 2. Model + the blank-skipping rule
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: create

```swift
import Foundation

public struct Checklist: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var items: [ChecklistItem]

    public init(id: UUID = UUID(), name: String, items: [ChecklistItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

public extension Checklist {
    /// Titles that will produce a reminder: trimmed, blanks dropped, order
    /// preserved. This was the inline rule at `CheckStitch/ContentView.swift:94`.
    var reminderTitles: [String] {
        items
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
```

#### 3. Message contract + codec
**File**: `CheckStitchCore/Sources/CheckStitchCore/SyncContract.swift`
**Action**: create

```swift
import Foundation

public enum SyncKey {
    public static let checklists = "checklists"
    public static let runChecklistID = "runChecklistID"
    public static let runReceipt = "runReceipt"
    public static let requestChecklists = "requestChecklists"
}

public struct RunReceipt: Codable, Hashable, Sendable {
    public let checklistID: UUID
    public let createdCount: Int
    public let at: Date

    public init(checklistID: UUID, createdCount: Int, at: Date = Date()) {
        self.checklistID = checklistID
        self.createdCount = createdCount
        self.at = at
    }
}

public enum ChecklistCodec {
    public static func encode(_ checklists: [Checklist]) -> Data {
        (try? JSONEncoder().encode(checklists)) ?? Data()
    }

    // `decode` cannot be overloaded on return type, so decoding uses explicit
    // names; `encode` overloads on the parameter type.
    public static func decodeChecklists(_ data: Data) -> [Checklist] {
        (try? JSONDecoder().decode([Checklist].self, from: data)) ?? []
    }

    public static func encode(_ receipt: RunReceipt) -> Data {
        (try? JSONEncoder().encode(receipt)) ?? Data()
    }

    public static func decodeReceipt(_ data: Data) -> RunReceipt? {
        try? JSONDecoder().decode(RunReceipt.self, from: data)
    }
}
```

`requestChecklists` is added beyond `structure.md`: the watch asks the phone to
push the current set on launch (Phase 6), and the phone answers in Phase 4.

#### 4. File-backed store
**File**: `CheckStitchCore/Sources/CheckStitchCore/FileChecklistStore.swift`
**Action**: create

```swift
import Foundation

public struct FileChecklistStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Missing or corrupt files are treated as an empty set — never thrown.
    public func load() -> [Checklist] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return ChecklistCodec.decodeChecklists(data)
    }

    public func upsert(_ checklist: Checklist) throws {
        var all = load()
        if let index = all.firstIndex(where: { $0.id == checklist.id }) {
            all[index] = checklist
        } else {
            all.append(checklist)
        }
        try save(all)
    }

    /// Replaces the whole set — used by the watch cache when a context arrives.
    public func replaceAll(_ checklists: [Checklist]) throws {
        try save(checklists)
    }

    private func save(_ checklists: [Checklist]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = ChecklistCodec.encode(checklists)
        try data.write(to: fileURL, options: [.atomic])
    }
}
```

`replaceAll` is an addition beyond `structure.md`'s `init/load/upsert` list;
Phase 6 needs it to swap the cache when `updateApplicationContext` delivers a
new set.

#### 5. Tests
**Files** (create):
`CheckStitchCore/Tests/CheckStitchCoreTests/ChecklistTests.swift`,
`CheckStitchCore/Tests/CheckStitchCoreTests/ChecklistCodecTests.swift`,
`CheckStitchCore/Tests/CheckStitchCoreTests/FileChecklistStoreTests.swift`

```swift
// ChecklistTests.swift
import Foundation
import Testing
@testable import CheckStitchCore

struct ChecklistTests {
    @Test func reminderTitlesTrimsAndDropsBlanksKeepingOrder() {
        let checklist = Checklist(name: "Groceries", items: [
            ChecklistItem(title: "  milk  "),
            ChecklistItem(title: "   "),
            ChecklistItem(title: ""),
            ChecklistItem(title: "eggs"),
        ])

        #expect(checklist.reminderTitles == ["milk", "eggs"])
    }

    @Test func reminderTitlesIsEmptyWhenEveryItemIsBlank() {
        let checklist = Checklist(name: "Blank", items: [
            ChecklistItem(title: " "),
            ChecklistItem(title: "\n\t"),
        ])

        #expect(checklist.reminderTitles.isEmpty)
    }
}
```

```swift
// ChecklistCodecTests.swift
import Foundation
import Testing
@testable import CheckStitchCore

struct ChecklistCodecTests {
    @Test func checklistsRoundTrip() {
        let checklists = [
            Checklist(name: "Groceries", items: [
                ChecklistItem(title: "milk"),
                ChecklistItem(title: "eggs"),
            ]),
            Checklist(name: "Packing", items: [ChecklistItem(title: "socks")]),
        ]

        let decoded = ChecklistCodec.decodeChecklists(ChecklistCodec.encode(checklists))

        #expect(decoded == checklists)
    }

    @Test func decodeGarbageIsEmpty() {
        #expect(ChecklistCodec.decodeChecklists(Data("not json".utf8)).isEmpty)
        #expect(ChecklistCodec.decodeChecklists(Data()).isEmpty)
    }

    @Test func receiptRoundTrip() {
        let receipt = RunReceipt(checklistID: UUID(), createdCount: 3, at: Date(timeIntervalSince1970: 0))
        let decoded = ChecklistCodec.decodeReceipt(ChecklistCodec.encode(receipt))
        #expect(decoded == receipt)
    }

    @Test func decodeGarbageReceiptIsNil() {
        #expect(ChecklistCodec.decodeReceipt(Data("nope".utf8)) == nil)
    }
}
```

```swift
// FileChecklistStoreTests.swift
import Foundation
import Testing
@testable import CheckStitchCore

struct FileChecklistStoreTests {
    private func makeStore() -> (FileChecklistStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("checklists.json")
        return (FileChecklistStore(fileURL: url), url)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let (store, _) = makeStore()
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "milk")])

        try store.upsert(checklist)

        #expect(store.load() == [checklist])
    }

    @Test func upsertReplacesByID() throws {
        let (store, _) = makeStore()
        let id = UUID()
        try store.upsert(Checklist(id: id, name: "Old", items: [ChecklistItem(title: "one")]))
        try store.upsert(Checklist(id: id, name: "New", items: [ChecklistItem(title: "two")]))

        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "New")
    }

    @Test func missingFileLoadsEmpty() {
        let (store, _) = makeStore()
        #expect(store.load().isEmpty)
    }

    @Test func corruptFileLoadsEmptyWithoutThrowing() throws {
        let (store, url) = makeStore()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        #expect(store.load().isEmpty)
    }

    @Test func replaceAllOverwritesTheSet() throws {
        let (store, _) = makeStore()
        try store.upsert(Checklist(name: "Old", items: []))
        let replacement = [Checklist(name: "New", items: [])]

        try store.replaceAll(replacement)

        #expect(store.load() == replacement)
    }
}
```

#### 6. Link `CheckStitchCore` into the iOS target (pbxproj)
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — **via the `xcodeproj` Ruby gem, not by hand.**

The iOS target imports `CheckStitchCore` from Phase 2 onward, so the package
wiring has to land in this phase (not Phase 5 as `structure.md` implies).

`xcodeproj` (1.27.0) is installed at `/opt/homebrew/bin/xcodeproj`. Write
`/tmp/add-core-package.rb` with the `write` tool (content in
[Appendix A](#appendix-a-add-core-packagerb)), then run from the repo root:

```bash
ruby /tmp/add-core-package.rb
```

It adds an `XCLocalSwiftPackageReference` to `CheckStitchCore`, an
`XCSwiftPackageProductDependency` named `CheckStitchCore`, and a `PBXBuildFile`
in the iOS target's Frameworks phase. It is idempotent.

### Verification

#### Automated
- [ ] `swift test --package-path CheckStitchCore` — 11 tests in 3 suites pass
- [ ] `ruby /tmp/add-core-package.rb` — "Linked CheckStitchCore into CheckStitch"
- [ ] `make build` passes; `xcodebuild -list -project CheckStitch.xcodeproj` shows a `CheckStitchCore` scheme and the package resolves as `local`

#### Manual
- [ ] `git diff CheckStitch.xcodeproj/project.pbxproj` contains only the package reference/product/build-file additions (plus re-serialization by the gem)

---

## Phase 2: iPhone persistence wiring

Checklists stop being ephemeral: Create persists `{name, items}` through the
tested `FileChecklistStore` and reloads on launch.

**Design note (decision here):** the phone screen authors **one checklist at a
time**. Each Create appends a new `Checklist` (fresh `id`) via
`store.upsert(...)`, so repeated Create taps with edited name/items build up
the set the watch lists. `upsert`-by-id remains Core-tested; the single-screen
UI has no id to re-save.

### Changes

#### 1. `CheckStitch/MyApp.swift`
**Action**: modify

```swift
import CheckStitchCore
import SwiftUI

@main struct MyApp: App {
    private let store: FileChecklistStore

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.store = FileChecklistStore(fileURL: base.appendingPathComponent("checklists.json"))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
```

#### 2. `CheckStitch/ContentView.swift`
**Action**: modify

- Add `import CheckStitchCore` at the top (keep `import EventKit`, `import os`,
  `import SwiftUI`).
- Replace the `@State private var checklistName = "checklist"` and the
  `@State private var items = [...]` block with injected storage + an `init`:

```swift
    let store: FileChecklistStore

    @State private var checklistName: String
    @State private var items: [ChecklistItem]

    init(store: FileChecklistStore) {
        self.store = store
        let saved = store.load().last
        _checklistName = State(initialValue: saved?.name ?? "checklist")
        _items = State(initialValue: saved?.items ?? [
            ChecklistItem(title: "one"),
            ChecklistItem(title: "two"),
            ChecklistItem(title: "three"),
        ])
    }
```

- In `createChecklistReminders()`, at the top of the function, persist before
  writing:

```swift
    func createChecklistReminders() async {
        let checklist = Checklist(name: checklistName, items: items)
        do {
            try store.upsert(checklist)
        } catch {
            Self.logger.error("Failed to save checklist: \(error.localizedDescription, privacy: .public)")
        }

        let eventStore = EKEventStore()
        // …existing EventKit body unchanged…
    }
```

- Delete the local `struct ChecklistItem` (now supplied by `CheckStitchCore`).
- Replace the `#Preview` block (it can no longer call `ContentView()`):

```swift
#Preview {
    let base = FileManager.default.temporaryDirectory
    let store = FileChecklistStore(fileURL: base.appendingPathComponent("preview-checklists.json"))
    return ContentView(store: store)
}
```

### Verification

#### Automated
- [ ] `make build` passes
- [ ] `swift test --package-path CheckStitchCore` still passes

#### Manual
- [ ] `make run`; create a checklist, quit and relaunch the app in the simulator — the name/items are reloaded from the last saved checklist
- [ ] Create "a", then edit the name to "b" and Create again → the stored set has both checklists (append-per-Create)

---

## Phase 3: iPhone reminder writer — `ReminderWriter`

Extract the EventKit write out of the view so the view and sync service share
one owner holding a **single** `EKEventStore` (avoids `EKCADErrorDomain
Code=1021`).

### Changes

#### 1. `CheckStitch/ReminderWriter.swift`
**Action**: create

```swift
import CheckStitchCore
import EventKit
import os

@MainActor
final class ReminderWriter {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ReminderWriter")

    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            Self.logger.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Writes one reminder per non-blank checklist item and returns how many
    /// were created. Returns 0 when reminder access is denied.
    @discardableResult
    func write(_ checklist: Checklist) async throws -> Int {
        guard await requestAccess() else { return 0 }
        let titles = checklist.reminderTitles
        for title in titles {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = store.defaultCalendarForNewReminders()
            try store.save(reminder, commit: true)
        }
        return titles.count
    }
}
```

#### 2. `CheckStitch/ContentView.swift`
**Action**: modify

- Add a `writer` property + init parameter:

```swift
    let store: FileChecklistStore
    let writer: ReminderWriter

    init(store: FileChecklistStore, writer: ReminderWriter) {
        self.store = store
        self.writer = writer
        let saved = store.load().last
        // …state seeding as in Phase 2…
    }
```

- Replace the whole `let eventStore = EKEventStore(); do { … } catch { … }`
  EventKit body of `createChecklistReminders()` with:

```swift
        do {
            _ = try await writer.write(checklist)
        } catch {
            Self.logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        }
```

- Drop `import EventKit` (no longer used in the view).
- Update the preview to pass a writer (see Phase 4 final preview).

#### 3. `CheckStitch/MyApp.swift`
**Action**: modify — own the writer and inject it.

```swift
    private let store: FileChecklistStore
    private let writer: ReminderWriter

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.store = FileChecklistStore(fileURL: base.appendingPathComponent("checklists.json"))
        self.writer = ReminderWriter()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, writer: writer)
        }
    }
```

### Verification

#### Automated
- [ ] `make build` passes

#### Manual
- [ ] `make run`; grant Reminders access, Create a checklist with a blank row and a valid row → exactly one reminder appears (the filtering rule is unit-tested in Phase 1)
- [ ] Deny Reminders access → no reminders, no crash

---

## Phase 4: iPhone transport — `PhoneSyncService`

Activate `WCSession`, publish the checklist set via
`updateApplicationContext`, consume run triggers, write reminders, and send
back a `RunReceipt`.

### Changes

#### 1. `CheckStitch/PhoneSyncService.swift`
**Action**: create

```swift
import CheckStitchCore
import Foundation
import os
import WatchConnectivity

@MainActor
final class PhoneSyncService: NSObject, WCSessionDelegate {
    // `nonisolated` — WCSessionDelegate callbacks are nonisolated under Swift 6.
    private nonisolated static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "PhoneSync")

    private let store: FileChecklistStore
    private let writer: ReminderWriter
    private let session: WCSession

    init(store: FileChecklistStore, writer: ReminderWriter, session: WCSession = .default) {
        self.store = store
        self.writer = writer
        self.session = session
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func pushChecklists() {
        guard session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext([
                SyncKey.checklists: ChecklistCodec.encode(store.load()),
            ])
        } catch {
            Self.logger.error("Failed to push checklists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func run(checklistID: UUID) async {
        guard let checklist = store.load().first(where: { $0.id == checklistID }) else {
            Self.logger.info("Ignoring run request for unknown checklist \(checklistID.uuidString, privacy: .public)")
            return
        }
        do {
            let created = try await writer.write(checklist)
            sendReceipt(RunReceipt(checklistID: checklistID, createdCount: created))
        } catch {
            Self.logger.error("Run failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendReceipt(_ receipt: RunReceipt) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo([SyncKey.runReceipt: ChecklistCodec.encode(receipt)])
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.pushChecklists() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if userInfo[SyncKey.requestChecklists] != nil {
            Task { @MainActor in self.pushChecklists() }
            return
        }
        guard let raw = userInfo[SyncKey.runChecklistID] as? String,
              let checklistID = UUID(uuidString: raw) else {
            Self.logger.info("Ignoring malformed run request")
            return
        }
        Task { @MainActor in await self.run(checklistID: checklistID) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushChecklists() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
```

#### 2. `CheckStitch/MyApp.swift` — final shape
**Action**: modify

```swift
import CheckStitchCore
import SwiftUI

@main struct MyApp: App {
    private let store: FileChecklistStore
    private let writer: ReminderWriter
    private let sync: PhoneSyncService

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let store = FileChecklistStore(fileURL: base.appendingPathComponent("checklists.json"))
        let writer = ReminderWriter()
        self.store = store
        self.writer = writer
        self.sync = PhoneSyncService(store: store, writer: writer)
        self.sync.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, writer: writer, sync: sync)
        }
    }
}
```

#### 3. `CheckStitch/ContentView.swift` — final shape
**Action**: modify

- Final init signature: `init(store: FileChecklistStore, writer: ReminderWriter, sync: PhoneSyncService)`.
- In `createChecklistReminders()`, after the successful `store.upsert`,
  publish the new set to the watch:

```swift
        sync.pushChecklists()
        do {
            _ = try await writer.write(checklist)
        } catch {
            Self.logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        }
```

- Final preview:

```swift
#Preview {
    let base = FileManager.default.temporaryDirectory
    let store = FileChecklistStore(fileURL: base.appendingPathComponent("preview-checklists.json"))
    let writer = ReminderWriter()
    return ContentView(
        store: store,
        writer: writer,
        sync: PhoneSyncService(store: store, writer: writer))
}
```

### Verification

#### Automated
- [ ] `make build` passes
- [ ] `swift test --package-path CheckStitchCore` still passes (payload encode/decode covered by `ChecklistCodecTests`)

#### Manual
- [ ] Optional paired-simulator check: boot the worktree simulator (`1134601D-40CB-47A1-979B-67D8C14A9221`) and a watch sim (`3F69EA19-301C-4978-AA7B-A63DE7CE69F5`), `xcrun simctl pair 3F69EA19-301C-4978-AA7B-A63DE7CE69F5 1134601D-40CB-47A1-979B-67D8C14A9221`, install both apps; create a checklist → the phone logs a context push
- [ ] Unlock the real iPhone; `bash scripts/run-devices.sh` installs `CheckStitch.app`
- [ ] A run request for an unknown checklist id is ignored (log line "Ignoring run request…"), not crashed

---

## Phase 5: Watch target + tooling (deploy risk retired early)

Add `CheckStitchWatch` as a companion target with a hello-world `WindowGroup`,
embed it in `CheckStitch.app`, and install it on the **real** watch before any
watch logic exists.

### Changes

#### 1. Watch scaffold
**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: create (temporary hello-world; replaced in Phase 7)

```swift
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("CheckStitch")
        }
    }
}
```

#### 2. `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify — via the `xcodeproj` Ruby gem.

Write `/tmp/add-watch-target.rb` with the `write` tool (content in
[Appendix B](#appendix-b-add-watch-targetrb)), then run from the repo root:

```bash
ruby /tmp/add-watch-target.rb
```

It adds the `CheckStitchWatch` application target (`SDKROOT = watchos`,
`SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`,
`WATCHOS_DEPLOYMENT_TARGET = 26.5`, `SKIP_INSTALL = YES`,
`PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch.watchkitapp`, the
`WKCompanionAppBundleIdentifier`/`WKWatchOnly`/`NSReminders*` infoplist keys,
`DEVELOPMENT_TEAM = 6NWX2DHB9Q`, and **no** `CODE_SIGN_ENTITLEMENTS`), a
`PBXFileSystemSynchronizedRootGroup` over `CheckStitchWatch/`, an "Embed Watch
Content" copy phase (`dstPath = $(CONTENTS_FOLDER_PATH)/Watch`) on the iOS
target, a `PBXTargetDependency`, and links the existing `CheckStitchCore`
product into the watch target.

`xcodebuild -list` autocreates the `CheckStitchWatch` scheme; no scheme file is
needed (`-scheme CheckStitchWatch` resolves).

#### 3. `Makefile`
**Action**: modify — add the watch destination, scheme and target.

```makefile
WATCH_SIM := generic/platform=watchOS
WATCH_SCHEME := CheckStitchWatch
```

and:

```makefile
watch-build:
	xcodebuild -scheme '$(WATCH_SCHEME)' \
	  -destination '$(WATCH_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -allowProvisioningUpdates \
	  build
```

Add `watch-build` to the `.PHONY` line.

#### 4. `scripts/run-watch.sh`
**Action**: create (`chmod +x`, mode `100755`) — full content in
[Appendix C](#appendix-c-run-watchsh).

Builds the watch app, discovers the paired **physical** watch via `devicectl`
JSON + a python filter (`platform == watchOS`, `reality == physical`,
developer mode enabled, reachable), then `devicectl device install app` +
`device process launch --terminate-existing --activate`. On install failure it
tells the user to run `./scripts/run-devices.sh` (which puts `CheckStitch.app`
on the iPhone; the phone then delivers the embedded watch app).

### Verification

#### Automated
- [ ] `ruby /tmp/add-watch-target.rb` → "Added CheckStitchWatch target…"
- [ ] `make watch-build` passes (watch deployment target `26.5`, no "supported deployment target versions is 4.0 to 26.5.99" warning)
- [ ] `make build` passes and `CheckStitch.app/Watch/CheckStitchWatch.app` exists in `DerivedData/Build/Products/Debug-iphoneos/`
- [ ] `shellcheck scripts/*.sh` clean

#### Manual
- [ ] `bash scripts/run-watch.sh` builds and attempts to install on `Alan's Apple Watch` (`00008301-209B793C010BC02E`); if the direct watch install is rejected, run `bash scripts/run-devices.sh` and confirm the app appears on the watch
- [ ] Unreachable watch → the script exits non-zero with a clear message (no bare `name=` destination)

---

## Phase 6: Watch sync + cache

The watch keeps a cached checklist set in its own container (tested
`FileChecklistStore`) and exchanges messages with the phone.

### Changes

#### 1. `CheckStitchWatch/WatchSyncService.swift`
**Action**: create

```swift
import CheckStitchCore
import Foundation
import Observation
import WatchConnectivity
import os

@MainActor
@Observable
final class WatchSyncService: NSObject, WCSessionDelegate {
    private nonisolated static let logger = Logger(
        subsystem: "app.alanvardy.CheckStitch.watchkitapp", category: "WatchSync")

    enum RunState: Equatable {
        case idle
        case queued
        case accepted(RunReceipt)
        case failed
    }

    private let cache: FileChecklistStore
    private let session: WCSession

    private(set) var checklists: [Checklist] = []
    private(set) var runState: RunState = .idle

    init(cache: FileChecklistStore, session: WCSession = .default) {
        self.cache = cache
        self.session = session
        self.checklists = cache.load()
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func requestChecklists() {
        guard session.activationState == .activated else { return }
        session.transferUserInfo([SyncKey.requestChecklists: true])
    }

    func run(_ checklist: Checklist) {
        runState = .queued
        session.transferUserInfo([SyncKey.runChecklistID: checklist.id.uuidString])
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.requestChecklists() }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[SyncKey.checklists] as? Data else { return }
        let checklists = ChecklistCodec.decodeChecklists(data)
        Task { @MainActor in
            try? self.cache.replaceAll(checklists)
            self.checklists = checklists
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[SyncKey.runReceipt] as? Data,
              let receipt = ChecklistCodec.decodeReceipt(data) else { return }
        Task { @MainActor in
            self.runState = .accepted(receipt)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.requestChecklists() }
    }
}
```

`private(set) var checklists` is an addition beyond `structure.md` (which only
listed `runState`): the list view must react when the application context
arrives while the app is open. `runState` is never left at "success" without a
receipt — `.queued` is the only state after tapping Run.

### Verification

#### Automated
- [ ] `make watch-build` passes

#### Manual
- [ ] Paired-sim or real-device check: a context from the phone populates the cached set; `Run` flips `.queued` → `.accepted(RunReceipt)` after the phone writes
- [ ] Run while the phone is unreachable stays `.queued` (never shown as success)
- [ ] Kill and relaunch the watch app → the cached checklists are still listed (file store)

---

## Phase 7: Watch UI — list → items → Run

### Changes

#### 1. `CheckStitchWatch/WatchChecklistViewModel.swift`
**Action**: create

```swift
import CheckStitchCore
import Foundation
import Observation

@MainActor
@Observable
final class WatchChecklistViewModel {
    private let cache: FileChecklistStore
    let sync: WatchSyncService

    var checklists: [Checklist] { sync.checklists }
    var runState: WatchSyncService.RunState { sync.runState }

    init(cache: FileChecklistStore, sync: WatchSyncService) {
        self.cache = cache
        self.sync = sync
    }

    func start() {
        sync.start()
        sync.requestChecklists()
    }

    func run(_ checklist: Checklist) {
        sync.run(checklist)
    }

    /// Cache lives in the watch app's own Application Support container.
    static func live() -> WatchChecklistViewModel {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cache = FileChecklistStore(fileURL: base.appendingPathComponent("checklists.json"))
        return WatchChecklistViewModel(cache: cache, sync: WatchSyncService(cache: cache))
    }
}
```

#### 2. `CheckStitchWatch/ChecklistListView.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

struct ChecklistListView: View {
    @State private var viewModel: WatchChecklistViewModel

    init(viewModel: WatchChecklistViewModel = .live()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.checklists.isEmpty {
                    ContentUnavailableView("No checklists yet", systemImage: "checklist")
                } else {
                    List(viewModel.checklists) { checklist in
                        NavigationLink(value: checklist) {
                            Text(checklist.name)
                        }
                    }
                }
            }
            .navigationTitle("CheckStitch")
            .navigationDestination(for: Checklist.self) { checklist in
                ChecklistDetailView(checklist: checklist, viewModel: viewModel)
            }
        }
        .task { viewModel.start() }
    }
}
```

#### 3. `CheckStitchWatch/ChecklistDetailView.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

struct ChecklistDetailView: View {
    let checklist: Checklist
    let viewModel: WatchChecklistViewModel

    var body: some View {
        List {
            Section("Items") {
                ForEach(checklist.items) { item in
                    Text(item.title)
                }
            }
            Section {
                Button("Run") {
                    viewModel.run(checklist)
                }
                .accessibilityIdentifier("runChecklistButton")
                runStatus
            }
        }
        .navigationTitle(checklist.name)
    }

    @ViewBuilder
    private var runStatus: some View {
        switch viewModel.runState {
        case .idle:
            EmptyView()
        case .queued:
            Text("Queued")
                .foregroundStyle(.secondary)
        case .accepted(let receipt):
            Text("Added \(receipt.createdCount) reminders")
                .foregroundStyle(.green)
        case .failed:
            Text("Couldn't run — try again")
                .foregroundStyle(.red)
        }
    }
}
```

#### 4. `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: modify — swap the hello-world body.

```swift
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ChecklistListView()
        }
    }
}
```

### Verification

#### Automated
- [ ] `make watch-build` passes
- [ ] `swift test --package-path CheckStitchCore` passes
- [ ] `shellcheck scripts/*.sh` clean

#### Manual
- [ ] `bash scripts/run-watch.sh`: create a checklist on the phone → it appears in the watch list (launch-fresh if needed); open it → items shown read-only; Run → "Queued" then "Added N reminders"; N one-per-item reminders appear in the Inbox on both devices (design acceptance 3 & 4)
- [ ] Empty cache → "No checklists yet"
- [ ] Phone unreachable → Run shows "Queued" and does not show success
- [ ] Watch app never writes Reminders (no EventKit write API on watchOS)

---

## Phase 8: Gate + docs

Make the automated suite part of the single gate.

### Changes

#### 1. `scripts/test.sh`
**Action**: modify

```bash
#!/bin/bash
# CheckStitch gate: the Xcode project has no test target (EventKit and
# WatchConnectivity are thin shells, verified manually on device), so the gate
# is both platform builds plus the CheckStitchCore Swift Testing suite and
# static checks over the repo's shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

make build
make watch-build

swift test --package-path CheckStitchCore

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "warning: shellcheck not installed — skipping script lint" >&2
  for f in scripts/*.sh; do bash -n "$f"; done
fi

echo "gate: ok"
```

`AGENTS.md` was already updated in the structure step to describe
`CheckStitchCore`, `make watch-build`, `scripts/run-watch.sh`, and this gate;
no further docs change is needed. Do **not** create child tickets.

### Verification

#### Automated
- [ ] `./scripts/test.sh` prints `gate: ok` (make build + make watch-build + swift test + shellcheck)

#### Manual
- [ ] `git status` shows only intended files; `scripts/run-watch.sh` is mode `100755`

---

## Deviations from structure.md

1. **watchOS deployment target `26.5`, not `27.0`.** The real watch runs
   watchOS 26.6 and the installed SDK caps the target at `26.5.99`; `27.0`
   cannot install on the device this ticket exists to run on. Applies to the
   watch target build settings, the `xcodeproj` script, and
   `CheckStitchCore/Package.swift`.
2. **`CheckStitchCore` is linked into the iOS target in Phase 1, not Phase 5.**
   Phase 2's `ContentView` imports it, so the package reference must land
   earlier. Phase 5's script links it into the watch target.
3. **`project.pbxproj` is mutated with the `xcodeproj` Ruby gem, not hand-edited.**
   `xcodeproj` 1.27.0 is installed; hand-writing the ~150 lines of cross-referenced
   pbxproj objects is the highest-risk part of the ticket. Both scripts are
   idempotent and were run against a copy of the repo during planning.
4. **`SyncKey.requestChecklists` added** so the watch can ask the phone to push
   (the phone also pushes on activation/reachability).
5. **`FileChecklistStore.replaceAll(_:)` added** for the watch cache to swap the
   whole set on a context update.
6. **`WatchSyncService` publishes `checklists`** (not just `runState`) so the
   list reacts to an in-session context update.
7. **`PhoneSyncService.logger` is `nonisolated static let`** — required by Swift
   6 because `WCSessionDelegate` callbacks are nonisolated.
8. **`ChecklistCodec` decode methods are named `decodeChecklists`/`decodeReceipt`**
   (Swift cannot overload on return type); `encode` is overloaded on the
   parameter type.
9. **Phase 2 persists append-per-Create** (fresh `id`), so the watch list can
   hold more than one checklist from the single-screen iOS UI. `upsert`'s
   by-id replacement is covered by `FileChecklistStoreTests` but is not
   reachable from the UI.

## Known risks carried into implementation

- **Direct `devicectl` install of a companion (`WKWatchOnly = NO`) watch app is
  unvalidated in either repo.** `scripts/run-watch.sh` attempts it and falls
  back to advising `run-devices.sh`. The watch JSON this session showed
  `tunnelState: disconnected` / `ddiServicesAvailable: false`; the install may
  require the paired iPhone nearby and awake.
- **WatchConnectivity deliverability**: `transferUserInfo` queues while the
  phone app is not running; the watch cannot tell "delivered" from "waiting", so
  `.queued` must never render as success (enforced by `RunState`).
- **Test suite takes a few seconds; `make watch-build` and `make build` are the
  slow parts of the gate.**

---

## Appendix A: `/tmp/add-core-package.rb`

```ruby
# Stage 1: link the local CheckStitchCore package into the iOS CheckStitch
# target. Run from the repo root:  ruby /tmp/add-core-package.rb
require 'xcodeproj'

project = Xcodeproj::Project.open('CheckStitch.xcodeproj')
ios = project.targets.find { |t| t.name == 'CheckStitch' }
raise 'CheckStitch target not found' unless ios

if project.root_object.package_references.any? { |r| r.respond_to?(:relative_path) && r.relative_path == 'CheckStitchCore' }
  warn 'CheckStitchCore package already referenced — nothing to do'
  exit 0
end

ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
ref.relative_path = 'CheckStitchCore'
project.root_object.package_references << ref

dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.product_name = 'CheckStitchCore'
ios.package_product_dependencies << dep

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = dep
ios.frameworks_build_phase.files << build_file

project.save
puts 'Linked CheckStitchCore into CheckStitch'
```

## Appendix B: `/tmp/add-watch-target.rb`

```ruby
# Stage 5: add the CheckStitchWatch target, embed it in CheckStitch.app, and
# link the existing CheckStitchCore package into it.
# Run from the repo root:  ruby /tmp/add-watch-target.rb
require 'xcodeproj'

project = Xcodeproj::Project.open('CheckStitch.xcodeproj')
ios = project.targets.find { |t| t.name == 'CheckStitch' }
raise 'CheckStitch target not found' unless ios

if project.targets.any? { |t| t.name == 'CheckStitchWatch' }
  warn 'CheckStitchWatch already exists — nothing to do'
  exit 0
end

core_dependency = ios.package_product_dependencies.find { |d| d.product_name == 'CheckStitchCore' }
raise 'CheckStitchCore is not linked into CheckStitch yet (run add-core-package.rb first)' unless core_dependency

watch = project.new_target(:application, 'CheckStitchWatch', :watchos, '26.5')
watch.product_reference.path = 'CheckStitchWatch.app'

# Synchronized root group over CheckStitchWatch/ (no per-file pbxproj entries).
sync = Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup.new(project, project.generate_uuid)
sync.path = 'CheckStitchWatch'
sync.source_tree = '<group>'
project.main_group.children << sync
watch.instance_variable_set(:@file_system_synchronized_groups, [sync])

watch.build_configurations.each do |config|
  settings = config.build_settings
  settings['SDKROOT'] = 'watchos'
  settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['WATCHOS_DEPLOYMENT_TARGET'] = '26.5'
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = '6NWX2DHB9Q'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'CheckStitch'
  settings['INFOPLIST_KEY_NSRemindersFullAccessUsageDescription'] =
    'CheckStitch needs access to create reminders.'
  settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = 'app.alanvardy.CheckStitch'
  settings['INFOPLIST_KEY_WKWatchOnly'] = 'NO'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.alanvardy.CheckStitch.watchkitapp'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SWIFT_VERSION'] = '6.0'
  settings['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
  settings['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['STRING_CATALOG_GENERATE_SYMBOLS'] = 'NO'
end

# Embed Watch Content into CheckStitch.app/Watch.
embed = ios.new_copy_files_build_phase('Embed Watch Content')
embed.dst_subfolder_spec = '16'
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
embed_build_file.file_ref = watch.product_reference
embed_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
embed_build_file.platform_filter = 'ios'
embed.files << embed_build_file

# iOS target builds the watch first and depends on it.
ios.add_dependency(watch)

# Link the already-declared CheckStitchCore product into the watch target.
watch.package_product_dependencies << core_dependency
watch_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
watch_build_file.product_ref = core_dependency
watch.frameworks_build_phase.files << watch_build_file

project.save
puts 'Added CheckStitchWatch target and embedded it in CheckStitch.app'
```

> Note: `new_target` also links `Foundation.framework` into the watch target and
> adds empty `exceptions = ()` to synchronized groups. Harmless; do not hand-remove
> it unless it causes a build problem (it does not, verified by `make watch-build`).

## Appendix C: `scripts/run-watch.sh`

```bash
#!/bin/bash
set -euo pipefail

# scripts/run-watch.sh — build the CheckStitchWatch companion app and install +
# launch it on the paired physical Apple Watch (via devicectl).
#
#   ./scripts/run-watch.sh
#
# Overrides (same env-override pattern as the Makefile):
#   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#
# The watch app is a companion to CheckStitch (WKWatchOnly = NO). Installing the
# watch bundle directly works when the watch is reachable; if it does not, run
# ./scripts/run-devices.sh to put CheckStitch.app on the paired iPhone, which
# delivers the embedded watch app to the watch.
#
# A watch that is unreachable (locked, asleep, off this Wi-Fi, unplugged
# mid-run) is reported and counted as a failure so the run exits non-zero.

SCHEME="${SCHEME:-CheckStitchWatch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch.watchkitapp}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-watch-$$.json"
trap 'rm -f "$DEVICES_JSON"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-watchos/${SCHEME}.app"

cd "$REPO_ROOT"

echo "==> Discovering paired Apple Watch devices…"
if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    echo "   Unlock the watch, confirm it is paired and on this Mac's Wi-Fi, then retry." >&2
    exit 1
fi

WATCHES=()
while IFS= read -r entry; do
    WATCHES+=("$entry")
done < <(python3 - "$DEVICES_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

for device in payload["result"]["devices"]:
    hardware = device.get("hardwareProperties", {})
    props = device.get("deviceProperties", {})
    if hardware.get("platform") != "watchOS":
        continue
    if hardware.get("reality") != "physical":
        continue
    name = props.get("name", "unknown watch")
    if props.get("developerModeStatus") != "enabled":
        print(f"  (skipping {name} — Developer Mode disabled)", file=sys.stderr)
        continue
    conn = device.get("connectionProperties", {}) or {}
    if conn.get("transportType") is None or conn.get("tunnelState") == "unavailable":
        print(f"  (skipping {name} — unreachable (locked, asleep, or on another network?)\n    unlock it, confirm it is on the same Wi-Fi as this Mac, then retry)", file=sys.stderr)
        continue
    print(f"{device['identifier']}|{name}")
PY
)

if [[ ${#WATCHES[@]} -eq 0 ]]; then
    echo "❌ No reachable physical Apple Watch found." >&2
    echo "   Unlock the watch, keep the paired iPhone nearby, and confirm the watch is on this Mac's Wi-Fi." >&2
    exit 1
fi

echo ""
echo "==> Building $SCHEME ($CONFIGURATION) for watchOS…"
xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=watchOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Built watch app not found at $APP_PATH" >&2
    exit 1
fi

failures=0
for entry in "${WATCHES[@]}"; do
    device_id="${entry%%|*}"
    device_name="${entry#*|}"

    echo ""
    echo "==> Installing on ${device_name}…"
    if ! xcrun devicectl device install app --device "$device_id" "$APP_PATH"; then
        echo "❌ Install failed on $device_name." >&2
        echo "   If the watch app cannot be installed directly, run ./scripts/run-devices.sh" >&2
        echo "   to put CheckStitch.app on the paired iPhone; it delivers the watch app." >&2
        failures=$((failures + 1))
        continue
    fi

    echo "==> Launching on ${device_name}…"
    if ! xcrun devicectl device process launch --terminate-existing --activate --device "$device_id" "$BUNDLE_ID"; then
        echo "❌ Launch failed on $device_name." >&2
        failures=$((failures + 1))
    fi
done

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "✅ Installed and launched on ${#WATCHES[@]} watch(es)."
else
    echo "❌ $failures step(s) failed — see errors above." >&2
    exit 1
fi
```
