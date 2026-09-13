# Task

Add localization for the common languages (de, en, es, fr, ja, zh-Hans) to
CheckStitch, mirroring the localization work already implemented in the sibling
SingleThread app (VAR-749 / VAR-791). Today all user-facing copy across the
iOS/macOS app target, the CheckStitchCore SPM package, and the CheckStitchWatch
target is hardcoded English (~170 string literals) with zero localization
infrastructure (verified: no `.lproj`, `.xcstrings`, or `LocalizedString`
types). The work introduces a string-catalog subsystem — per-target `.xcstrings`
resources, per-language `.lproj/InfoPlist.strings` including localized app
name/description — plus localization tests, while keeping the full gate
(simulator build/test, macOS build, watch build, shell tests) green.