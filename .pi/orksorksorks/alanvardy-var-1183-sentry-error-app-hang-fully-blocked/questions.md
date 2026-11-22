# Research Questions

## Context

Focus on the Sentry integration surface: how CheckStitch initializes and
configures Sentry, how the `SentryScrubber` `beforeSend` / `beforeBreadcrumb`
path transforms events and breadcrumbs, what the Sentry `Event` / exception /
`Frame` model exposes for diagnosing hangs, how the analogous SingleThread
scrubber implements a stack-frame-based system-stall drop, how the existing
test suites build synthetic Sentry events, and how the CheckStitch app target
and `CheckStitchCore` package divide code and dependencies.

## Questions

1. How does CheckStitch's Sentry initialization and scrub pipeline work end to
   end — from `SentrySDK.start` in `SentryBootstrap` through the
   `beforeSend` / `beforeBreadcrumb` closures into `SentryScrubber.scrub(_:)`
   — including exactly which event and breadcrumb fields are nulled,
   preserved, or rebuilt?

2. How does SingleThread's `SentryScrubber` implement its AppHang
   system-stall drop — the `StackFrameSignature` model, the
   `systemStallSignatureImages` denylist, the `isSystemStall` predicate, the
   `appHangStack` lookup, and how the result is incorporated into
   `scrub(_ event:)`?

3. What does the Sentry `Event` / `Exception` / `Mechanism` / `Frame` object
   model expose for identifying a hang — including `mechanism?.type`,
   `exceptions`, `threads`, `stacktrace`, `frame.package`, and `frame.inApp` —
   as evidenced by how existing production and test code reads those fields?

4. How do the existing Sentry test suites in CheckStitch and SingleThread build
   and assert on Sentry events — fixture helpers, synthetic event/exception/
   frame construction, event-return vs event-drop assertions, and the naming
   and structure conventions of the system-stall tests?

5. How is Sentry configured in CheckStitch — the pure `SentryConfiguration`
   value type, the options set in `SentryBootstrap` (app-hang tracking,
   watchdog termination, auto session tracking, breadcrumb limits, PII,
   tracing), and how the DSN, environment, and crash-reporting opt-in
   preference reach the SDK?

6. How is code and dependency responsibility divided between the CheckStitch
   app target and the `CheckStitchCore` SPM package — which target(s) import
   or link Sentry, what the local package can depend on, and what the build,
   test, and gate commands imply for code that touches the Sentry SDK?
