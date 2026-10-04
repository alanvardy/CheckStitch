# Q2: Checklist scalar field round-trip through persistence codec and merge
#
All refs under CheckStitchCore/Sources/CheckStitchCore/.
#
## Encode / decode (decodeIfPresent ?? default)
- Item decode: Checklist.swift:78-108. Required keys id/title via decode (79-80); every other scalar uses decodeIfPresent(...) ?? default:
  - description ?? "" (88); modifiedAt ?? .distantPast (89); revision ?? 0 (90); relativeDate Int? no default (92).
  - Per-field clocks seeded from the coarse clock when absent: titleRevision ?? revision (95), titleModifiedAt ?? modifiedAt (96), description* (97-98), relativeDate* (99-100), priority ?? .none (106), priorityRevision/ModifiedAt ?? revision/modifiedAt (107-108).
- Item encode: Checklist.swift:111-139. Writes every key (127-128); relativeDate written key-or-Nil (130-134).
- Checklist decode: Checklist.swift:211-243. name required (213); items ?? [] (214); destinationListIdentifier no default (215); prefixesReminderNumbers ?? false (218); showsOnWatch ?? true (223, only default-true); folderID no default (226); modifiedAt ?? .distantPast (227); revision ?? 0 (228); itemOrder ?? items.map(id) (229); orderRevision ?? 0 (230); orderModifiedAt ?? .distantPast (231); decode-time self-heal via normalizedOrder (232-243).
- Checklist encode: Checklist.swift:245-263; folderID key-or-Nil (251-257).
- Folder decode/encode: Checklist.swift:386-391,393-404; isCollapsed ?? false (388).
#
## ChecklistEnvelope (versioned wire container)
- Checklist.swift:419-439. Fields: version, deviceID, checklists, tombstones, folders, folderTombstones; Codable, Sendable, Equatable.
- Decode: 444-454 — version required (446); deviceID ?? "" (447); checklists ?? [] (448); tombstones ?? [] (449); folders ?? [] (452); folderTombstones ?? [] (453).
- Encode: 456-462 — all six keys.
- contentEquals (ignores deviceID): 470-473.
#
## Format versioning — enum ChecklistCodec, currentVersion = 5 (Checklist.swift:476-477)
- encode = JSONEncoder().encode(envelope) (498-500). Store is the only encoder — ChecklistStore.swift:115-120 builds envelope at currentVersion.
- classify (504-533) probes version via VersionProbe (547) BEFORE full decode. Outcomes (483-496): loaded / migratable(from,envelope) / unsupportedVersion / unreadable.
  - currentVersion=5 -> .loaded (508); case 4 folders verbatim (510-514); case 3 predates relativeDate (515-519); case 2 seed ordering no restamp (520-524); case 1 full migrated(at:) restamp (527); default .unsupportedVersion (529-530); catch .unreadable (533-534).
- decode convenience: 539-545 (.loaded/.migratable -> checklists; unsupported/unreadable -> []).
- Migration call site: ChecklistStore.swift:72-98. v1 -> migrated(at:) item field clocks from coarse (Checklist.swift:266-296); v2 -> seededOrder() (298-324); v3+ verbatim. unsupportedVersion -> empty + canOverwriteStoredPayload=false (90-93).
#
## ChecklistMerge reconciliation (ChecklistMerge.swift)
- Entry merge(local,remote)->ChecklistEnvelope (24-52), symmetric. Tombstones union first (26); dead checklists/folders/items pruned (29-44). Emits envelope at currentVersion with local deviceID (46-51).
- Winner rule wins() (287-303): per-field revision higher wins; tie -> newer modifiedAt (Date >); tie -> smaller device id (device < overDevice). Symmetric.
- Structure: local-first, remote-only entries append (e.g. mergedChecklists 127-132); LWW only picks values when both sides have the record.
- Checklist scalar fields (name, destinationListIdentifier, prefixesReminderNumbers, showsOnWatch, folderID) share ONE coarse revision/modifiedAt clock: if remote wins coarse wins() test, ALL copied wholesale (145-157). No per-field clocks at checklist level.
- Item fields ARE per-field: title (titleRevision/titleModifiedAt) (172-177), description (179-184), relativeDate (186-191), priority (193-198). Coarse item revision/modifiedAt from whole-item winner (161-169) then raised to max of adopted field clocks (202-207) to preserve tombstone removed.revision+1 invariant.
- Ordering independent: orderRevision/orderModifiedAt decide whose itemOrder wins (160-168), reconciled against surviving ids (218-236).
- Call site ChecklistStore.apply(remote) (584-611): refuses non-current versions (588), merges, re-canonicalises normalizedOrder (590), no-op iff equal (591), saves (601).
