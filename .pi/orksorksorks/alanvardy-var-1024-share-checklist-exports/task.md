# Task

When a user exports one or more checklists, give them the option to share the
result through the system share sheet (iOS / macOS) so they can share it over
iMessage or email. Today, exporting builds a `ChecklistExportDocument` and
presents a `.fileExporter` save panel (ContentView.exportSelected → isExporting
→ .fileExporter). The change adds the option to hand that exported document to
the platform share sheet instead of (or alongside) the save panel. The share
sheet is a new platform integration with no existing use in the codebase, so
the correct invocation must be researched and validated against the Swift/SwiftUI
SDK; whether it accepts the in-memory document directly or needs a
security-scoped file/URL staged first is unknown. Product/UX trade-offs
(share vs save panel, iOS-only vs also macOS) need a decision during design.