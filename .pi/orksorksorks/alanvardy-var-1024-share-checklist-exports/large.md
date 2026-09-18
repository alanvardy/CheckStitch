# Task

When a user exports one or more checklists, give them the option to share the
result through the system share dialog (iOS share sheet / macOS share sheet)
so they can share it over iMessage or email if they wish.

Today, exporting a checklist builds a `ChecklistExportDocument` and presents a
`.fileExporter` save panel (see `ContentView.exportSelected()` →
`isExporting` → `.fileExporter`). The change gives the user the option to hand
that exported document to the platform share sheet instead of (or alongside)
the save panel, so the share targets (iMessage, email, etc.) are available.

## Why LARGE

- **UNKNOWNS** — the iOS/macOS share sheet is a platform API with no existing
  use in this codebase (`rg` for share/sheet matches nothing but unrelated
  strings), so the correct invocation must be researched and validated against
  the Swift/SwiftUI SDK (compiler-as-oracle per `swiftui-sdk` skill); whether
  the share sheet accepts the in-memory document directly or needs a
  security-scoped file/URL written first is unknown and may require a spike.
- **NEW_SURFACE** — a new platform integration (the share dialog / sheet) rather
  than a localized change inside the existing panel.
- **DESIGN_SIGN-OFF** — product/UX trade-off on how share relates to the save
  panel (replace vs offer both), and whether it applies to iOS only or also
  macOS, needs a decision before implementation.

## Key files (pre-recon)

- `CheckStitch/ContentView.swift` — `exportSelected()`, `isExporting`, the
  `.fileExporter` block (lines ~186–194, ~610–625).
- `CheckStitch/ChecklistExportDocument.swift` — the `FileDocument` carrying the
  export bytes.
- `CheckStitch/ExportChecklistsView.swift` — the multi-select sheet that kicks
  off the export.
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift` — envelope
  encoding.