# Implementation Plan

## Overview

Add a per-item edit affordance to the checklist detail screen and a pushed
`ItemEditView` that edits an item's `description` and `relativeDate` (days until
due), with helper text explaining empty = no due date and `0` = today. The model,
codec, store mutators and sync path already support both fields, so this is UI +
localization + tests only: one new view, one row change, four new catalog keys,
and test extensions. The row's existing inline description/date fields are left
as they are — the new screen is an additional editor, not a replacement.

Two phases, one commit each:

1. **Localization** — add the four new user-visible strings (all six locales) and
   register them in the localization fixture. Independently green.
2. **UI** — create `ItemEditView`, add the row's edit icon/NavigationLink, and
   extend the tests.

---

## Phase 1: Localization — strings for the edit screen

### Changes

#### 1. Add four keys to the app string catalog
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

The catalog is plain JSON in Xcode's own formatting (`" : "` spacing, 2-space
indent); the `localizations` object holds all six of `en/de/es/fr/ja/zh-Hans`,
each a `stringUnit` with `"state" : "translated"`. Insert the four entries below
in their alphabetical positions (order is not load-bearing — `LocalizationTests`
parses the JSON — but keeps the file tidy). The exact block to add:

```json
    "Days" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Days"
          }
        },
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Tage"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Días"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Jours"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "日数"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "天数"
          }
        }
      }
    },
    "Edit item" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Edit item"
          }
        },
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Eintrag bearbeiten"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Editar elemento"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Modifier l'élément"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "項目を編集"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "编辑项目"
          }
        }
      }
    },
    "Item not found" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Item not found"
          }
        },
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Eintrag nicht gefunden"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Elemento no encontrado"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Élément introuvable"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "項目が見つかりません"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "找不到项目"
          }
        }
      }
    },
    "Leave empty for no due date. 0 means today." : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Leave empty for no due date. 0 means today."
          }
        },
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Leer lassen für kein Fälligkeitsdatum. 0 bedeutet heute."
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Déjalo vacío para no tener fecha de vencimiento. 0 significa hoy."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Laissez vide pour aucune date d'échéance. 0 signifie aujourd'hui."
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "空欄にすると期限なしになります。0 は今日を意味します。"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "留空表示没有截止日期。0 表示今天。"
          }
        }
      }
    },
```

Note `"Description"` already exists for the edit screen's description field;
`"Item"`/`"Items"` exist for the detail screen. `"Days"` was previously absent
(the existing `ItemRow` placeholder falls back to the raw key); adding it also
localizes that placeholder, which is expected.

#### 2. Register the new keys as required
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add them to the `("App", [...])` entry of `requiredKeys` (alphabetical, matching
the surrounding list) so `everyRequiredKeyIsPresent` catches a dropped key:

```swift
            "Days",
            "Edit item",
            "Item not found",
            "Leave empty for no due date. 0 means today.",
```

### Verification

#### Automated
- [x] `make test-unit` passes — `LocalizationTests.catalogsHaveAllSixLanguages`,
      `.nonEnglishValuesDifferFromEnglish` and `.everyRequiredKeyIsPresent` all
      cover the four new entries.

#### Manual
- [ ] `python3 -c "import json;json.load(open('CheckStitch/Localizable.xcstrings'))"`
      exits 0 and the catalog reports all six locales for each new key.

---

## Phase 2: Edit screen and row affordance

### Changes

#### 1. Create the item edit screen
**File**: `CheckStitch/ItemEditView.swift`
**Action**: create

New app-target file under the `PBXFileSystemSynchronizedRootGroup` folder, so no
`project.pbxproj` edit is needed. Mirrors `ChecklistDetailView`'s binding
factories (read the item from the store each pass, commit through the per-field
mutators) and reuses `ItemRow`'s pure `parse`/`format`/`draft` helpers so the
date buffer behaves exactly like the inline row. Builds on iOS and macOS; the
`#if os(iOS)` split exists only for `keyboardType`, matching `ItemRow`.

```swift
import SwiftUI

/// Edits one item's description and relative due date ("days until due").
///
/// Pushed from the edit affordance on an `ItemRow`. Reads the item from the
/// store each pass so an iCloud merge lands live, committing through the same
/// per-field mutators as the detail screen. The date field buffers its text
/// exactly like `ItemRow` (reusing its parse/format helpers) so a half-typed
/// `"-"` survives; the store no-ops an unchanged date.
struct ItemEditView: View {
    let checklistID: UUID
    let itemID: UUID

    @Environment(ChecklistStore.self) private var store
    @State private var draftDate = ""
    @State private var didLoadDraft = false

    var body: some View {
        Group {
            if let item = store.checklist(id: checklistID)?
                .items.first(where: { $0.id == itemID }) {
                Form {
                    Section {
                        TextField("Description", text: descriptionBinding, axis: .vertical)
                            .accessibilityIdentifier("itemEditDescriptionField")
                    }
                    Section {
                        dueDateField
                    } footer: {
                        caption("Leave empty for no due date. 0 means today.")
                    }
                }
                .onChange(of: item.relativeDate) { _, newValue in
                    // External (iCloud) change updates the buffer unless the
                    // buffer already represents it, matching `ItemRow`.
                    if let refreshed = ItemRow.draft(
                        afterExternalChange: newValue, current: draftDate) {
                        draftDate = refreshed
                    }
                }
            } else {
                // Deleted elsewhere (e.g. an iCloud merge) while on the stack.
                ContentUnavailableView("Item not found", systemImage: "trash")
            }
        }
        .navigationTitle("Edit item")
        .toolbarTitleDisplayMode(.inline)
        .settingsSubscreenLayout()
        .onAppear {
            guard !didLoadDraft else { return }
            let item = store.checklist(id: checklistID)?.items.first { $0.id == itemID }
            draftDate = ItemRow.format(item?.relativeDate)
            didLoadDraft = true
        }
        .onDisappear { store.flushPendingSave() }
    }

    /// Per-keystroke description write, mirroring `ChecklistDetailView`.
    private var descriptionBinding: Binding<String> {
        Binding(
            get: {
                store.checklist(id: checklistID)?
                    .items.first { $0.id == itemID }?.description ?? ""
            },
            set: {
                store.updateItemDescription(
                    checklistID: checklistID, itemID: itemID, description: $0)
            }
        )
    }

    /// The numbers-and-punctuation keyboard is iOS-only (macOS has no software
    /// keyboard) and is what keeps a leading `-` typeable; the chain is
    /// duplicated under the guard because SwiftUI modifier calls return
    /// distinct opaque view types, matching `ItemRow.dueDateField`.
    private var dueDateField: some View {
        #if os(iOS)
            TextField("Days", text: $draftDate)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("itemEditRelativeDateField")
                .onChange(of: draftDate) { _, newValue in
                    store.updateItem(
                        checklistID: checklistID, itemID: itemID,
                        relativeDate: ItemRow.parse(newValue))
                }
        #else
            TextField("Days", text: $draftDate)
                .accessibilityIdentifier("itemEditRelativeDateField")
                .onChange(of: draftDate) { _, newValue in
                    store.updateItem(
                        checklistID: checklistID, itemID: itemID,
                        relativeDate: ItemRow.parse(newValue))
                }
        #endif
    }

    @ViewBuilder
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

#### 2. Add the edit affordance to `ItemRow`
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add a stored `checklistID` so the row can build the pushed destination (the
store reaches the destination through the existing root `.environment(store)`,
like `ChecklistDetailView` itself). The `.buttonStyle(.borderless)` keeps the tap
target to the icon so the row's inline text fields stay editable.

Add the stored property and init parameter:

```swift
struct ItemRow: View {
    let checklistID: UUID
    let itemID: UUID
    let title: Binding<String>
    let description: Binding<String>
    let relativeDate: Int?
    let commitRelativeDate: (Int?) -> Void

    init(
        checklistID: UUID,
        itemID: UUID = UUID(),
        title: Binding<String>,
        description: Binding<String> = .constant(""),
        relativeDate: Int?,
        commitRelativeDate: @escaping (Int?) -> Void
    ) {
        self.checklistID = checklistID
        self.itemID = itemID
        self.title = title
        self.description = description
        self.relativeDate = relativeDate
        self.commitRelativeDate = commitRelativeDate
    }
```

Add the link to the top `HStack` and the new computed property:

```swift
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Item", text: title)
                dueDateField
                editLink
            }
            // ...existing description TextField unchanged...
        }
```

```swift
    /// Pushed editor for this item's description and relative due date.
    /// `borderless` keeps the tap target to the icon so the row's inline fields
    /// stay editable.
    private var editLink: some View {
        NavigationLink {
            ItemEditView(checklistID: checklistID, itemID: itemID)
        } label: {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("editItemButton-\(itemID.uuidString)")
    }
```

Update the row's call site in the `ForEach` to pass the checklist id:

```swift
                        ItemRow(
                            checklistID: checklistID,
                            itemID: item.id,
                            title: titleBinding(checklistID: checklistID, itemID: item.id),
                            description: descriptionBinding(checklistID: checklistID, itemID: item.id),
                            relativeDate: item.relativeDate
                        ) { newValue in
                            store.updateItem(checklistID: checklistID, itemID: item.id, relativeDate: newValue)
                        }
```

#### 3. Extend the tests
**File**: `CheckStitchTests/ChecklistDetailViewTests.swift`
**Action**: modify

`ItemRow`'s init gained a required parameter, so both existing `ItemRow(...)`
constructions must pass one. In `itemRowBuffersItsDateText`:

```swift
        let described = String(describing: ItemRow(
            checklistID: UUID(), itemID: UUID(), title: .constant("Milk"),
            relativeDate: 1, commitRelativeDate: { _ in }))
```

Add a value-graph pin for the row's new identity and two render tests for the
new screen (the existing `detailViewRendersItemsWithDescriptions` stays as the
render canary for the row *with* the link). Follow the existing
`makeIsolatedDefaults()` + `ImageRenderer` idiom:

```swift
    /// The row carries the checklist identity its pushed edit link needs.
    @Test
    func itemRowCarriesItsChecklistForTheEditLink() {
        let described = String(describing: ItemRow(
            checklistID: UUID(), itemID: UUID(), title: .constant("Milk"),
            relativeDate: 1, commitRelativeDate: { _ in }))
        #expect(described.contains("checklistID"))
        #expect(described.contains("itemID"))
    }

    /// The edit screen renders against an injected store for an existing item.
    @Test
    func itemEditViewRendersForAnExistingItem() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")
        store.addItem(to: checklist.id)
        let itemID = store.checklist(id: checklist.id)?.items.first?.id ?? UUID()
        store.updateItemDescription(checklistID: checklist.id, itemID: itemID, description: "2 litres")
        store.updateItem(checklistID: checklist.id, itemID: itemID, relativeDate: 1)

        let view = ItemEditView(checklistID: checklist.id, itemID: itemID).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// A deleted item (e.g. an iCloud merge) renders the not-found placeholder
    /// instead of a form bound to a missing item.
    @Test
    func itemEditViewRendersNotFoundForAMissingItem() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")

        let view = ItemEditView(checklistID: checklist.id, itemID: UUID()).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }
```

No change to `ChecklistStoreTests` — no store mutator is added (the existing
per-field mutators already cover persistence and revision stamping). No change
to the UI smoke test: the new affordance needs an existing item, which the
launch smoke does not create.

### Verification

#### Automated
- [x] `make test-unit` passes — updated `ItemRow` constructions, the new
      `ItemEditView` render tests, and the localization suites.
- [x] `make build-mac` passes — the `#if os(iOS)`/`#else` `dueDateField` branch
      compiles against the macOS SDK (unsigned, no provisioning).
- [x] `make build` passes — iOS simulator compile.

#### Manual
- [ ] `make run`; open a checklist, tap the pencil on a row, type a description,
      confirm the change is reflected in the detail row after going back.
- [ ] On the edit screen, type `0` → item due today; clear the field → no due
      date; type `-3` → a past date; confirm the helper caption sits under the
      date field.
- [ ] Delete the item from another device/sync while the edit screen is open and
      confirm the not-found placeholder appears (sad path).
- [ ] Confirm the inline description/date fields on the row still type normally
      (the edit link does not steal the whole row's tap).

#### Gate
- [ ] `bash scripts/test.sh` prints `gate: ok` (run once, after this phase
      commits).