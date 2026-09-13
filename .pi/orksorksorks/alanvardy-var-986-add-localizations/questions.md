# Research Questions

## Context

This research covers two repositories: the CheckStitch app (an iOS/macOS app
target `CheckStitch/`, a local sources-only SPM package `CheckStitchCore`, and
a watchOS target `CheckStitchWatch`, with tests and shell scripts), and a
sibling iOS app `SingleThread` that uses the same target structure and build
conventions (including a shared check of how its strings and resources are
organized). Focus is on: where user-facing text physically lives across
CheckStitch's three targets; the localization-relevant build configuration in
CheckStitch's Xcode project; the end-to-end localization implementation in
SingleThread (string catalogs, string abstractions, resource declaration,
localized Info.plist handling, tests); and CheckStitch's test suites and build
gate plumbing.

## Questions

1. iOS/macOS app target: where does user-facing copy live, and what is the
   target's localization-relevant build configuration (GENERATE_INFOPLIST_FILE,
   INFOPLIST_KEY_* usage descriptions, display name, PRODUCT_NAME) and
   resource-membership mechanism in the Xcode project?

2. CheckStitchCore SPM package: how is Package.swift structured (targets,
   products, platforms, resources), and which source files contain
   user-facing or fallback text?

3. CheckStitchWatch target: what user-facing copy does it hold, and what is
   its configuration (build settings, display name, resources)?

4. SingleThread, end to end: how is localization implemented across its app
   target, SPM package, watch and widget targets — the .xcstrings catalogs,
   the string abstraction types in use (LocalizedStringResource,
   String(localized:table:bundle:)), how each target declares its catalog
   resource, which languages are present, and how localized app-name /
   Info.plist strings are handled?

5. SingleThread localization tests: how do LocalizationTests.swift,
   LocalizationTestHelpers.swift and related suites validate catalogs,
   per-language completeness, plurals and InfoPlist.strings — what helpers and
   APIs do they use, and what do they assert?

6. CheckStitch tests and gate plumbing: what test files exist, what do they
   cover, what platform gating applies, what does the build/test gate run in
   order (Makefile targets, scripts/test.sh, scripts/tests/run.sh), and how
   does the Xcode project declare file/resource membership for the app and
   watch targets (PBXFileSystemSynchronizedRootGroup)?