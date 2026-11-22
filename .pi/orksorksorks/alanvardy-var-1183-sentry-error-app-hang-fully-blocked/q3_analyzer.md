# Q3 - Sentry Event / Exception / Mechanism / Frame object model for hang identification

Scope: what the model exposes for identifying a hang, evidenced by how existing
production and test code reads those fields. No improvements proposed.

## Where the hang-relevant model is actually read

- Production: only `SingleThread/SingleThread/SentryScrubber.swift` reads the
  hang-relevant fields (`mechanism`, `exceptions`, `stacktrace`, `Frame.package`,
  `Frame.inApp`).
- CheckStitch production scrubber (`CheckStitch/SentryScrubber.swift`) reads none
  of them; it only touches `event.exceptions?.value`
  (`CheckStitch/SentryScrubber.swift:26`).

## Event

- Entry point is `event.exceptions` (an optional array of `Exception`):
  `SingleThread/SingleThread/SentryScrubber.swift:60` -
  `event.exceptions?.first(where: { $0.mechanism?.type == "AppHang" })`.
- No code in CheckStitch or SingleThread reads `event.threads`: a grep for
  `.threads` over `*.swift` in both repos returns nothing. The model exposes
  `threads`, but no production/test code here uses it.
- `event.exceptions?.forEach { $0.value = nil }` scrubs exceptions in both
  scrubbers: `CheckStitch/SentryScrubber.swift:26`,
  `SingleThread/SingleThread/SentryScrubber.swift:84`.

## Exception

- Fields read: `.mechanism` (`Mechanism?`), `.stacktrace` (`SentryStacktrace?`),
  `.type` (structural `String?`), `.value` (free-text `String?`).
- `.type` is preserved (never nulled) so crashes still group; tests assert it:
  `CheckStitchTests/SentryScrubberTests.swift:70`,
  `SingleThread/SingleThreadTests/SentryScrubberTests.swift:70`.
- `.value` is treated as free text and nulled in both scrubbers (refs above).
- Test construction: `Exception(value:type:)`, then
  `exception.mechanism = Mechanism(type:)` and
  `exception.stacktrace = SentryStacktrace(frames:registers:)` -
  `SingleThread/SingleThreadTests/SentryScrubberTests.swift:120-122, 186-201`.

## Mechanism

- Constructed as `Mechanism(type: ...)`:
  `SingleThread/SingleThreadTests/SentryScrubberTests.swift:121, 189`.
- Read via `exception.mechanism?.type`:
  - `SingleThread/SingleThread/SentryScrubber.swift:61` and `:63`
    (`appHangStack` filter and returned `mechanismType`).
  - `SingleThread/SingleThread/SentryScrubber.swift:44`
    (`isSystemStall` guards `mechanismType == "AppHang"`).
- Comment (`SingleThread/SingleThread/SentryScrubber.swift:37-38`) states
  `"AppHang"` is the public, stable marker; the predicate fails open on any
  other/renamed value (test `keepsEventWhenMechanismRenamed`).

## Stacktrace and Frame

- `exception.stacktrace` gives `SentryStacktrace`; `.frames` is `[Frame]` and is
  required non-empty:
  `SingleThread/SingleThread/SentryScrubber.swift:64-65`.
- Frame fields read at capture time are exactly `.package` (`String?`, loaded
  binary path) and `.inApp` (`NSNumber?`; SDK-mandated NSNumber, read via
  `.boolValue`):
  `SingleThread/SingleThread/SentryScrubber.swift:99-104` -
  `let image = frame.package ?? ""` and
  `isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")`.
- No code reads `Frame.function`, `frame.lineNo`, `frame.fileName`, etc.
  Comment `SingleThread/SingleThread/SentryScrubber.swift:35-36` says function
  names are not available in `beforeSend` (symbolicated server-side), so the
  signature matches on image paths instead.
- The model is reduced to `StackFrameSignature { image, isApp }`:
  `SingleThread/SingleThread/SentryScrubber.swift:11-16`, init at `:99-104`.

## Test-side event construction

- CheckStitch tests build only PII-oriented events/exceptions; there is no
  hang/mechanism/frame fixture: `CheckStitchTests/SentryScrubberTests.swift:62-70`.
- SingleThread builds synthetic hang events in `hangEvent(frames:mechanismType:)`:
  `SingleThread/SingleThreadTests/SentryScrubberTests.swift:120-122` (mechanism),
  `:186-201` (`Frame`, `frame.package`, `frame.inApp = NSNumber(value:)`,
  `SentryStacktrace(frames:registers:)`).
- `capturedFrames` fixture (`SingleThread/SingleThreadTests/SentryScrubberTests.swift:161-184`)
  is the raw client-side exception stack as `(package, in_app)` pairs, verbatim.

## Summary of what exists

- Hang identification is driven by `Event.exceptions` -> `Exception.mechanism?.type == "AppHang"`
  -> `Exception.stacktrace.frames` -> `Frame.package` + `Frame.inApp`.
- `Event.threads` is part of the model but unused in either repo.
- CheckStitch production does not read any of these hang fields; the same object
  model is exercised only in SingleThread.
