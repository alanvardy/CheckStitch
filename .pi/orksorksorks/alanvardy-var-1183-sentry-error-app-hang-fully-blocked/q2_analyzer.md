Report on question 2 — SingleThread's `SentryScrubber` AppHang system-stall drop. All references are to `/Users/vardy/dev/SingleThread/SingleThread/SentryScrubber.swift` unless noted.

## 1. `StackFrameSignature` model
`SentryScrubber.swift:11-16` defines a nested `struct StackFrameSignature: Equatable` with two stored properties:
- `let image: String` — "`Frame.package` — the loaded binary's path" (`:12-13`).
- `let isApp: Bool` — "`Frame.inApp`, with the app-bundle path as a belt-and-braces fallback" (`:14-15`).

The frame→signature conversion lives in an extension at `:99-104`:
```
nonisolated init(_ frame: Frame) {
    let image = frame.package ?? ""
    self.image = image
    isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")
}
```
So `image` is the raw `Frame.package` (empty string if nil), and `isApp` is true when `frame.inApp?.boolValue == true` OR the package path contains `.app/` (`:103`). The comment at `:26-28` notes function names are unavailable in `beforeSend` (sentry-cocoa sets only `package`/`inApp` at capture; symbolication happens server-side), so matching is done on image paths.

## 2. `systemStallSignatureImages` denylist
`:29-32` declares:
```
nonisolated static let systemStallSignatureImages: [String] = [
    "BackBoardServices",
    "libxpc.dylib"
]
```
Comment `:21-24`: these are binary-image substrings of the synchronous BackBoardServices/backlight XPC stall UIKit performs on the main thread; Sentry issue 7821993169 (`BKSDisplayBrightnessGetCurrent` → `bootstrap_look_up`).

## 3. `isSystemStall` predicate
`:41-53`, pure drop decision, fail-open (under-specified input returns `false` → event reported):
```
nonisolated static func isSystemStall(
    mechanismType: String?,
    frames: [StackFrameSignature]) -> Bool {
    guard mechanismType == "AppHang" else { return false }
    guard !frames.isEmpty else { return false }
    guard systemStallSignatureImages.allSatisfy({ signature in
        frames.contains { $0.image.contains(signature) }
    }) else { return false }
    guard let firstStall = frames.firstIndex(where: { frame in
        systemStallSignatureImages.contains { frame.image.contains($0) }
    }) else { return false }
    return !frames[firstStall...].contains(where: \.isApp)
}
```
Three conditions must hold (documented `:37-40`): (1) mechanism type is exactly `"AppHang"` (`:44`); (2) every denylist image appears in some frame via substring `contains` (`:46-48`); (3) no in-app frame sits at or deeper than the first stall frame — `frames[firstStall...]` has no `isApp` frame (`:49-52`).

## 4. `appHangStack` lookup
`:57-68` reduces an `Event` to a tuple or `nil` (fail-open):
```
nonisolated static func appHangStack(
    in event: Event) -> (mechanismType: String, frames: [StackFrameSignature])? {
    guard
        let exception = event.exceptions?.first(where: {
            $0.mechanism?.type == "AppHang"
        }),
        let mechanismType = exception.mechanism?.type,
        let stacktrace = exception.stacktrace,
        !stacktrace.frames.isEmpty
    else { return nil }
    return (mechanismType, stacktrace.frames.map(StackFrameSignature.init))
}
```
It selects the first exception whose `mechanism?.type == "AppHang"` (`:60-62`), requires a non-empty `stacktrace` (`:64-65`), and maps each `Frame` through `StackFrameSignature.init` (`:67`).

## 5. Incorporation into `scrub(_ event:)`
`:70-87`. The drop check runs first, before any field nulling:
```
nonisolated static func scrub(_ event: Event) -> Event? {
    if let stack = appHangStack(in: event),
       isSystemStall(mechanismType: stack.mechanismType, frames: stack.frames) {
        return nil
    }
    event.user = nil
    ... (field scrubbing)
    return event
}
```
If `appHangStack` returns a stack and `isSystemStall` is true, `scrub` returns `nil` (`:71-74`) — dropping the event. Otherwise it proceeds to the allow-list scrub and returns the event (`:75-86`). Note `scrub` is `Event?`-returning; the breadcrumb overload `:92-96` returns `Breadcrumb?` and is unrelated to the stall check.

## Wiring to Sentry
`SentryBootstrap.swift:38` sets `options.beforeSend = { SentryScrubber.scrub($0) }`; `:39` sets `options.beforeBreadcrumb = { SentryScrubber.scrub($0) }`; `:26` sets `options.enableAppHangTracking = true`. Thus the `nil` returned by `scrub(_ event:)` is the mechanism that suppresses the AppHang event in `beforeSend`.

(Report within budget; no write tool available, so returned inline. No `fish:` rejections encountered; commands run via `bash -c`.)