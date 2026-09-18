# Research Questions

## Context

Focus on the export flow and platform-presentation layer of the app: how the
app turns selected checklists into an exported document, how it presents
documents/files on iOS vs macOS, how platform-specific code is gated within a
single app target, and what platform document/share APIs Swift/SwiftUI expose.
Areas of interest: `CheckStitch/ContentView.swift`,
`CheckStitch/ChecklistExportDocument.swift`,
`CheckStitch/ChecklistImportExportViewModel.swift`,
`CheckStitch/ExportChecklistsView.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift`, the reference
project `/Users/vardy/dev/SingleThread`, and the `CheckStitchTests`/`CheckStitchUITests`
suites. Several questions are platform-API questions with no in-repo call
sites, so they may need current web/source-backed investigation.

## Questions

1. How does the checklist export flow work end to end, from the user pressing
   export to the save panel being presented? Trace `exportSelected()`,
   `isExporting`, the `.fileExporter` presentation (including the macOS
   staging delay), and what `ChecklistExportDocument`'s `FileDocument`
   actually carries (bytes, MIME/content type, filename derivation).
2. How does the app handle security-scoped resources and file I/O today —
   specifically the `startAccessingSecurityScopedResource()` import path — and
   what patterns exist (if any) for staging a document as an on-disk file or a
   file URL that another platform API could consume? How do iOS and macOS
   differ in how such a document would be presented?
3. How is platform-specific behaviour gated within the single app target that
   builds for iOS and macOS (e.g. `#if os(...)`, separate per-target files)?
   What are the concrete constraints that forced the macOS workaround of
   delaying the `.fileExporter` until after a 400ms sleep (a sheet-nested
   `.fileExporter` never presents on macOS)?
4. What platform share-sheet / share-dialog API exists on iOS and macOS in
   Swift/SwiftUI (e.g. a share sheet, share extension target, or sharing
   activity view controller)? How is it invoked, and what inputs does it
   accept — an in-memory document/bytes, or a security-scoped file/URL that
   must be staged first? Are there known constraints on presenting it from
   within an open sheet/tab?
5. What do the export-related tests pin down that any change to the export
   surface must keep stable (filename, `fileWrapper` bytes, `canExport`/
   `toggled` state, view model flags, the XCTest vs Swift Testing split), and
   which of these are platform-gated?