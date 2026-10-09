# Research Questions

## Context
Explore the CheckStitch import/export pipeline, the folder data model and its
versioned serialization, the store write path for imported/duplicated
checklists, the sync/merge handling of folders and tombstones, and the
accompanying test surface. Focus areas live in
CheckStitchCore/Sources/CheckStitchCore/ and the thin CheckStitch app target
(export document, import/export view model, export view). Report factual
descriptions of what exists today, with file:line references.

## Questions
1. How is an export envelope constructed and which fields does the executed
   export payload actually carry (version, deviceID, checklists, tombstones,
   folders, folderTombstones)? Which are populated vs defaulted, how are the
   exported checklists selected, and how is the export encoded, shared, and
   named (ChecklistExport, ChecklistExportDocument,
   ChecklistImportExportViewModel, ExportChecklistsView)?

2. How does the import pipeline decode and version an imported file, and which
   fields does the decoded() step read from the envelope into candidate
   checklists? Which envelope fields (checklists, folders, folderTombstones,
   tombstones, deviceID, itemOrder) are consumed vs ignored at that stage, and
   how are conflicts and decisions computed (ChecklistImportSession,
   ChecklistCodec.classify and its version handling)?

3. How are folders and their tombstones modeled and serialized: the Folder and
   FolderTombstone structs, the folderID field on Checklist, the
   ChecklistEnvelope folders/folderTombstones fields, and the versioned
   ChecklistCodec encode/decode? Detail coding keys, default values,
   decodeIfPresent behavior for pre-v5 files lacking folder keys, which codec
   channel/version serializes folders, and how the isCollapsed state is stored.

4. How does the store write imported or duplicated checklists? Trace
   ChecklistStore freshCopy(of:), importInsert(_:as:), importReplace(id:with:),
   plus the live folder CRUD (createFolder, moveChecklist, renameFolder,
   setFolderCollapsed, moveFolders, deleteFolder). Describe what freshCopy
   preserves, regenerates, and drops (including folderID and archive fields),
   how uniqueName disambiguation and save() work, and how folder CRUD and
   FolderTombstones maintain membership and revision/clock semantics.

5. How do sync and merge handle folders and their tombstones? Trace
   ChecklistSyncService, ChecklistSyncCoordinator pushContext (folders
   encoding), the WatchChecklistStore folder handling, and ChecklistMerge
   (merge(local:remote:), mergedFolders, mergedFolderTombstones, and how a
   checklist folderID is carried). Detail merge semantics: last-write-wins,
   revision/modifiedAt/device comparisons, how folder tombstones suppress live
   folders, when isCollapsed is carried, how deviceID is used, and what happens
   to a checklist folderID that references a dead/tombstoned or absent folder.

6. What test patterns and fixtures cover export, import, codec serialization,
   and the store import/copy path? Survey ChecklistExportTests,
   ChecklistExportDocumentTests, ChecklistImportSessionTests,
   ChecklistImportExportViewModelTests, ChecklistCodecTests,
   ChecklistStoreTests, ChecklistMergeTests, ChecklistGroupingTests, and
   CheckStitchTests/TestFixtures.swift. Describe how test checklists and
   folders are constructed, how folder cases are written, how export/import
   round-trip and versioned codec tests are structured, and any platform
   gating or fixtures a new test must join.