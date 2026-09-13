# Task

Add localization for the common languages to CheckStitch, mirroring the
localization work implemented in the sibling SingleThread app (VAR-749 /
VAR-791). Today all user-facing copy across the iOS/macOS app target
(ContentView, ChecklistDetailView, SettingsView, …), the CheckStitchCore SPM
package, and the CheckStitchWatch target is hardcoded English with zero
localization infrastructure in the project (verified: no `.lproj`,
`.xcstrings`, or `LocalizedString` types; ~170 hardcoded string literals
across the three targets, plus app metadata like Info.plist usage-description
keys). The work therefore introduces a string-catalog subsystem and migrates
the app's copy end to end: Catalog/`LocalizedString` infrastructure, per-target
`.xcstrings` resources, per-language `.lproj/InfoPlist.strings` (SingleThread
covers de/en/es/fr/ja/zh-Hans plus the localized app name/description), and
localization tests — keeping the full gate (simulator build/test, macOS build,
watch build, shell tests) green.

## Why LARGE

Matched NEW_SURFACE (i18n string-catalog subsystem introduced project-wide
where none exists today — not a localized change to existing code),
CROSS_CUTTING (spans the iOS/macOS app target, CheckStitchCore, the watchOS
target, and packaging/l10n file formats: `.xcstrings` resources, `.lproj`
InfoPlist.strings interplay with `GENERATE_INFOPLIST_FILE`, SPM package
resources — with the layering for THIS codebase dictated by a reference in a
sibling repo, not an in-repo pattern), CONVENTION_RISK (shared
CheckStitchCore and build/packaging formats), and UNKNOWNS (which languages
"common" means, how far the string surface extends — accessibility labels /
AppIntent titles / Info.plist descriptions / macOS surface — and what in
SingleThread's App-Store-metadata research transfers). SingleThread's own
implementation went through the full research → design → plan pipeline before
landing, and this ticket is a terse pointer at that work.