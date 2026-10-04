# Q6 — Checklist field threading: export/share/import/duplicate-freshCopy + localization baseline

## Export (ChecklistExport)
- CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift:11-15 — envelope(checklists:)
  builds a ChecklistEnvelope with version: ChecklistCodec.currentVersion, empty deviceID,
  the checklists, empty tombstones. Valid codec payload (classify == .loaded); never resurrects
  deletions; never injects a foreign deviceID.
- :17-19 — data(checklists:) runs ChecklistCodec.encode(envelope(...)).
- :22-27 — filename(for:calendar:), "CheckStitch-<yyyy-MM-dd>", en_US_POSIX, no extension.
- CheckStitch/ChecklistExportDocument.swift:12-26 — FileDocument, readableContentTypes=[.json];
  data set via ChecklistExport.data; export is in-memory (import never opens documents; goes
  through .fileImporter).
- Serialization is the same full codec path as persistence: threaded scalars are
  name, items (title/description/relativeDate/priority), destinationListIdentifier,
  prefixesReminderNumbers, showsOnWatch, modifiedAt, revision.

## Share (ChecklistShare)
- CheckStitch/ChecklistShare.swift:11-29 — itemProvider(for:filename:) captures only the document
  Data (Sendable) and registers it as NSItemProvider data under UTType.json.identifier,
  visibility .all, suggestedName=filename. No file URL, no staging.
- :33-54 — iOS-only ShareSheet: UIViewControllerRepresentable wrapping UIActivityViewController
  with the item provider; popover anchored for iPad.
- CheckStitch/ChecklistImportExportViewModel.swift:15-16,30,70-75 — exportSelection:Set<UUID>,
  pendingShare:ChecklistExportDocument?; shareSelected() builds ChecklistExportDocument from
  selected ids, deferred to sheet onDismiss. Value identity preserved in bytes; no field skipped.

## Import (ChecklistImportSession)
- CheckStitch/ChecklistImportSession.swift:29-46 — @MainActor @Observable session holding store +
  now() clock; state pending/candidates/summary.
- :55-70 stage(data:) — decode-only, no store writes; maps each checklist to
  ChecklistImportCandidate(id:fileUUID, checklist, conflicting:) via store.conflictingChecklist.
- :75-95 commit(selectedIDs:) — authoritative conflict check re-run; colliding names enqueue
  pending FIFO; others go to store.importInsert.
- :98-103 discard() — drops staged state, no writes.
- :107-125 decoded(_:) — ChecklistCodec.classify; .loaded→checklists; .migratable v1→
  checklist.migrated(at:now()), v2→seededOrder(); .unsupportedVersion/.unreadable throw.
- :129-139 decide(_:for:) — replace→store.importReplace; keepBoth→store.importInsert
  (disambiguated); keepExisting→count only.
- :9-23 ChecklistImportError (unreadable/unsupportedVersion) plain-English message, Equatable.

## Duplicate / freshCopy (ChecklistStore)
- duplicate CheckStitchCore/.../ChecklistStore.swift:156-189 — duplicateName="<name> copy";
  duplicate(id:name:) guards source existence (nil no-op); blank name falls back to offered
  default; name disambiguated via uniqueName (success guaranteed). Items rebuilt fresh
  ChecklistItem (new UUID, revision:1, modifiedAt:now()) copying title/description/
  relativeDate/priority. Copy carries destinationListIdentifier, prefixesReminderNumbers,
  showsOnWatch, modifiedAt:now(), revision:1; append + save().
- freshCopy :195-213 — private, shared by import. Fresh local identity: new checklist AND item
  UUIDs, revision:1, now(); carries destinationListIdentifier, prefixesReminderNumbers,
  showsOnWatch; name kept as-is (unlike duplicate).
- :216-227 importInsert(_:as:) — freshCopy, renames via uniqueName (Keep Both, non-destructive),
  append+save(), returns new id.
- :230-244 importReplace(id:with:) — removes local, appends whole-checklist tombstone
  (itemID:nil, revision+1) mirroring delete, then freshCopy inserts; single save() = one push.
- Shared convention: duplicate/freshCopy never re-enter LWW merge; stamp new local identity and
  carry destinationListIdentifier/prefixesReminderNumbers/showsOnWatch untouched so the user's
  Reminders target survives. No scalar invented or dropped.

## Localization baseline
- Catalogs: CheckStitch/Localizable.xcstrings, CheckStitchCore/Sources/CheckStitchCore/Resources/
  Localizable.xcstrings, CheckStitchWatch/Localizable.xcstrings, CheckStitchWidget/Localizable.xcstrings
  (App/Core/Watch/Widget; .lproj holds only InfoPlist.strings).
- Structure (Apple xcstrings JSON): sourceLanguage "en"; strings keyed by UI key; each entry has
  extractionState "manual" and localizations with 6 languages en/fr/es/de/ja/zh-Hans, each a
  stringUnit {state:translated, value}.
- CheckStitchTests/LocalizationFixtures.swift:12-152 — requiredKeys:[(catalog,[String])] enumerates
  every key each guarded catalog must carry: ("App",[...]), ("Core",["System",...]),
  ("Watch",[...]), ("Widget",[...]). Prevents a key being dropped (raw key would render).
- :8 guardedCatalogs=["App","Core","Watch","Widget"] (non-English-differs canary covers all).
  New key must: exist in its Localizable.xcstrings across all 6 languages AND be added to its
  catalog's requiredKeys entry. :157-207 infoPlistTargets+excludedIdentities handle InfoPlist.strings
  + identical non-English spellings; missingInfoPlistKeys tests the incomplete-plist path. AGENTS.md:
  run scripts/l10n-check.sh first, per the localization skill.
