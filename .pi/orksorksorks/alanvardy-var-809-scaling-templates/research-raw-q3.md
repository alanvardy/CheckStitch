# Question 3 — Checklist to instantiated reminder items (raw report)

## 1. ChecklistTitleNumbering — the pure title resolver
Defined in CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift:16-28.
- public enum ChecklistTitleNumbering (:16), single static pure resolver
  title(_ title: String, position: Int, numbered: Bool, itemCount: Int) -> String (:22-27).
- If !numbered -> returns title unchanged (raw, no derived text) (:23).
- Else zero-pads single-digit positions to two digits (01:...09:) only when
  itemCount > 9 && position < 10, so titles sort numerically under Reminders lexical ordering (:24);
  returns "\\(padded): \\(title)" (:25). Position is 1-based, unbounded past 9.

## 2. Two run paths
### Path A (production): ChecklistReminders.create (ChecklistReminders.swift)
- ChecklistReminders is a @MainActor enum (:9). Entry create(from checklist: Checklist) (:19-22)
  resolves the production destination seam and builds the gate, then delegates.
- Real path create(from:targeting:gate:) (:26-71):
  - gate.reserveRun() first (:35); refused -> .purchaseRequired (:36).
  - let prefixNumbers = checklist.prefixesReminderNumbers — reads the toggle from the Checklist (:32).
  - requestAccess() (:38), snapshot resolve destination (:42-47); .destinationMissing if unresolved.
  - let itemCount = checklist.items.filter { !$0.isBlank }.count (:50).
  - Loop for item in checklist.items where !item.isBlank (:52); position += 1 after blanks dropped (:54).
  - Raw reads: item.title (broadcast into resolver), item.description / item.hasDescription (:58-59),
    item.priority (:60), item.dueDateComponents(today:) (:61).
  - Derived text produced at :56-57: ChecklistTitleNumbering.title(item.title, position:, numbered: prefixNumbers, itemCount:).
  - ReminderRunOutcome: .created(count:) / .permissionDenied / .destinationMissing / .purchaseRequired / .failed / .partiallyCreated (:67-71).
  - Note: this path also passes notes: (raw description) — the only path that surfaces descriptions.

### Path B (core/test-only): ChecklistCreator.create (ChecklistCreator.swift)
- public struct ChecklistCreator: Sendable (:37), init takes a ReminderCreating seam + prefixNumbers: Bool = false (:38-44).
- create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome (:46-68):
  - guard requestAccess() else { return .permissionDenied } (:47-48).
  - let itemCount = items.filter { !$0.isBlank }.count (:51).
  - Loop for item in items where !item.isBlank (:54); position += 1 (:56).
  - Raw read: item.title (resolver input) and item.dueDateComponents(today:calendar:) (:60-63).
  - Derived text at :60-61: ChecklistTitleNumbering.title(item.title, position:, numbered: prefixNumbers, itemCount:).
  - No notes/description passed; returns ChecklistCreationOutcome
    .created(count:) / .permissionDenied / .failed(String) (:6-10, :66-67).

Both paths share the same resolver, the same blank-drop-first position cursor
(no gap after empty rows), and the same itemCount (non-blank count).

## 3. RunCounter / RunGate (RunCounter.swift)
- @MainActor final class RunCounter (:10): durable successful-runs counter in UserDefaults
  (production key "runCount.v1", :17). Validated read: absent/non-integer/negative -> 0 (:21-24);
  increment() (:25), decrement() never below 0 (:26-31), reset() (:33).
- @MainActor struct RunGate (:42): freeRunLimit = 20 (:44). permitsRun = isUnlocked || count < limit (:53).
  reserveRun() atomic check+increment (.count < limit only) (:56-62); releaseRun() decrements when no item created (:64-71).
- RunCounter does not touch titles — it gates runs (free-tier limit) before any reminder is created.

## 4. Call sites
- Production run: CheckStitch/ChecklistRunViewModel.swift:47-48 — builds RunGate(counter:, isUnlocked:),
  calls ChecklistReminders.create(from:targeting:gate:).
- CheckStitch/MyApp.swift:108 — phone-sync path: createReminders: { await ChecklistReminders.create(from: $0) }.
- Legacy CheckStitch/ContentView.swift previously called createChecklistReminders() (pre-gate/old path); gate now lives in ChecklistRunViewModel.
- ChecklistCreator has no production consumer; only CheckStitchTests/ChecklistCreatorTests.swift (test-only).
- Gate wiring tests: CheckStitchTests/ChecklistRemindersTests.swift:21-23, 391-486; CheckStitchTests/ChecklistImportSessionTests.swift:241-243.
- Toggle storage: Checklist.prefixesReminderNumbers (Checklist.swift:183, codec :206,218,251),
  set via ChecklistStore.swift:280-281, read in UI (ChecklistDetailView.swift:266).

## 5. Where raw vs derived text live (summary)
- Raw read: item.title -> ChecklistCreator.swift:61, ChecklistReminders.swift:57; item.description -> ChecklistReminders.swift:59 (notes). Never mutated.
- Derived text: produced only inside ChecklistTitleNumbering.title at the two call sites
  (ChecklistCreator.swift:60-61, ChecklistReminders.swift:56-57); its output is the reminder
  title / create(title:) argument. position and zero-padding are the only transformations;
  blank items are excluded first so position never gaps.
