# Task

VAR-1033 — Let the user set the app's UI language from a dropdown on the
Settings screen ("interface section"). CheckStitch's catalogs already carry
six locales (en, de, es, fr, ja, zh-Hans) but `String(localized:)` today
always resolves by process/preferred localization, so this adds the first
user-facing override of that resolution: a persisted language preference plus
a settings dropdown, applied app-wide. The runtime language-override
mechanism is unknown territory (nothing in the codebase sets or overrides the
resolved locale outside test-only pinning), so the target surfaces (iOS app,
macOS leg, paired watch), the placement in the Settings screen, and the
persistence pattern must be pinned down first.