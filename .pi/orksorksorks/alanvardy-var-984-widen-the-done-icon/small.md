# Task

On the settings screen (iPhone and iPad), the "Done" toolbar button renders
as a round circle that barely contains the word "Done". Widen it so the
button is wider while keeping its height — "Done" should fit comfortably
inside.

The button lives in `CheckStitch/SettingsView.swift` (lines ~46–51):

```swift
.toolbar {
    ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
            .checkStitchButton()
    }
}
```

The sibling detail screen (`CheckStitch/ChecklistDetailView.swift`, lines
~49–58) already solved this exact iOS 26 problem for its own bar item: iOS 26
wraps bar items in a system glass container, and `.fixedSize()` stops that
container collapsing to a circle that clips the title. Mirror that fix on the
settings button — verify what `.checkStitchButton()` does
(`CheckStitch/CheckStitchButtonModifier.swift`) and keep whatever is
appropriate for the bar context (the detail screen deliberately dropped the
modifier in favour of `.fixedSize()` because in a bar the native styling owns
the shape).

When done, the settings-screen "Done" button should be wider than it is tall
(or at least not clipped to a circle around the word), with the same height
as before.

## Why SMALL

Single-file view tweak in the thin app target following an in-repo precedent
(`ChecklistDetailView`'s `.fixedSize()` fix), no schema, no shared/convention
or design decisions, no test infrastructure — all of A–F hold.

## Key files

- `CheckStitch/SettingsView.swift` — the button to fix (lines ~46–51)
- `CheckStitch/ChecklistDetailView.swift` — the in-repo precedent (`.fixedSize()` on its Done bar item, lines ~49–58)
- `CheckStitch/CheckStitchButtonModifier.swift` — the modifier currently applied; decide whether it belongs on a bar item