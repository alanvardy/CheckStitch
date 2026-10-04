# QUESTION 4 - read-only vs editing surfaces: how checklist/item text renders

Scope: iOS and macOS share one set of SwiftUI views under CheckStitch/; watchOS has
its own target (CheckStitchWatch/); the widget is a third target (CheckStitchWidget/).
There is no dedicated macOS item or editor view: the iOS row and editor are
cross-platform and gate on os(iOS) only for the keyboard type.

## Read-only row (iOS/macOS) - ItemRow

- ItemRow, CheckStitch/ChecklistDetailView.swift:305. The whole row is a
  NavigationLink into ItemEditView (:310-315), so it holds no editable controls.
- Title: Text(Self.displayTitle(title)) at :331. displayTitle(_:) at :362-365 is
  DERIVED: an empty title falls back to the localized Item placeholder
  (resolvedInAppLanguage()); a non-empty title passes through raw.
- Date: Text(DueDateLabel.resource(for: relativeDate)) at :336 - DERIVED from the
  integer day offset (Today / Tomorrow / Yesterday / In N days / N days ago); nil maps
  to empty. Label map in CheckStitch/DueDateLabel.swift:16-33.
- Priority badge: Text(priority.marker) at :326 plus priorityColor at :339-349; hidden
  when marker.isEmpty; rendered on the title HStack (not a List-side badge).
- Description: Text(description) at :343 - RAW, shown verbatim under the title
  (footnote/secondary); only when non-empty (:342).

## Watch (read-only rows)

- WatchChecklistDetailView.swift:57-66 renders Text(item.title) (RAW) and
  Text(item.description) (RAW, only when item.hasDescription). No displayTitle
  fallback, no DueDateLabel, no priority marker on the watch; rows are plain and are
  not NavigationLinks into an editor.
- List-level labels (WatchChecklistListView.swift:30-38) show RAW folder.name and
  checklist.name.

## Editor - ItemEditView (iOS/macOS)

- CheckStitch/ItemEditView.swift:12, pushed from the row; reads the item from the
  store each pass (store.checklist(id:)...first(where:) at :21-22).
- Title/Description: RAW text fields bound via titleBinding / descriptionBinding
  (Section at :24-32); strings are edited raw.
- Priority: Menu of ChecklistItemPriority at :33-52 showing item.priority.label.
- Date: buffered dueDateField + RelativeDateDraft seam; its caption reuses the same
  DERIVED DueDateLabel phrases so editor and read-only row agree (header :5-10).
- Mutations go through per-field store mutators (bindings); no editing view model.

## Widget (read-only; checklist-level only)

- Widgets never render item text; they render checklist names and run controls.
- ChecklistWidgetDisplayModel.swift:8-19 is the pure row model (name is the raw
  checklist name; indicator; access state).
- SingleChecklistWidgetView (SingleChecklistWidget.swift:92-129): RAW
  Text(row.name) at :95; access/purchase labels are derived copy.
- MultiChecklistWidgetView (MultiChecklistWidget.swift:77-113): RAW
  Text(row.name) per row at :85 with lineLimit(1).

## Summary (raw vs derived)

- ItemRow iOS/macOS read-only: title derived (displayTitle fallback), description raw,
  date derived (DueDateLabel), priority derived (marker + color).
- ItemEditView iOS/macOS editor: title raw TextField, description raw TextField,
  date derived label caption, priority menu label.
- Watch detail read-only: title raw item.title, description raw item.description,
  date and priority not shown.
- Widget read-only: checklist name raw; no item fields shown.
