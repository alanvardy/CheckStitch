# Task

VAR-1033 — Let the user set the app's UI language from a dropdown on the
Settings screen ("interface section"). CheckStitch's catalogs already carry
six locales (en, de, es, fr, ja, zh-Hans) but `String(localized:)` today
always resolves by process locale, so this adds the first user-facing override
of that resolution: a persisted language preference plus a settings dropdown,
applied app-wide. Because the runtime language-override mechanism is unknown
territory (nothing in the codebase sets or overrides the resolved n outside
test-only pinning), the target surfaces (iOS app, macOS leg, paired watch) and
the exact placement ("interface section" does not exist in the current
Settings screen) must be pinned down first.

## Why LARGE

UNKNOWNS (which Swift 6/Foundation API overrides `String(localized:)`
resolution at runtime vs. pinning the n at app startup — needs a spike; plus
watch/macOS scope and dropdown placement are un-specified), CROSS_CUTTING
(persistence via `UserDefaults`/`@AppStorage`, the shared string catalogs,
Settings UI, and platform application code), and CONVENTION_RISK (SharedStrings
and the six-language Localizable.xcstrings catalogs are gated by the
LocalizationTests suites in every target).