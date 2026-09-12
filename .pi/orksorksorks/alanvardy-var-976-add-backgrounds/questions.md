# Research Questions

## Context

Two Swift/SwiftUI app repos are in play: the target app CheckStitch
(`/Users/vardy/dev/alanvardy-var-976-add-backgrounds` — one screen, one
settings sheet, UserDefaults-backed prefs, iOS + macOS targets: iphoneos
iphonesimulator macosx) and its sibling reference app SingleThread
(`/Users/vardy/dev/SingleThread` — contains a self-contained background
imagery subsystem: an observable store that fetches a photo + metadata over
HTTP, validates and persists it to disk, a full-bleed background layer view,
a fade percent enum, and a settings subscreen). Focus on how each app is
structured, how state flows, and what platform APIs are already in use.
Description only — no suggestions or proposals.

## Questions

1. How does CheckStitch persist and surface user preferences end to end —
   the @AppStorage/UserDefaults mechanism, the AppearanceMode
   enum/preference helper, and how pref state flows into the ContentView
   and the SettingsView sheet (declaration → read → live change → write)?

2. How is the CheckStitch app built and structured — entry, the content
   screen's layout primitives, the settings sheet's Form/section
   construction, how new source files enter the build, and the iOS/macOS
   dual-target surface (AppDelegate pairing, platform-specific view and
   image/system APIs)?

3. How does SingleThread's BackgroundImageStore work end to end — ownership
   and injection, the fetch endpoints and HTTP error handling, the payload
   and image decode validation, the 6h/24h cache freshness semantics, the
   pin interaction, and the atomic on-disk persistence of the image and
   metadata sidecar, including the isDecodableImage gate across UIImage
   (iOS) and NSImage (macOS)?

4. How is the background rendered and controlled — the BackgroundPhotoLayer
   view composition (Color.clear overlay, scaledToFill, ignoresSafeArea,
   opacity, hit testing, accessibility), the BackgroundFade percent/opacity
   mapping and its picker values, and where the layer mounts inside
   SingleThread's ContentView relative to content that can scroll or
   reflow?

5. How does SingleThread's settings UI expose background controls — the
   SettingsView navigation row into the subscreen, the
   BackgroundSettingsView layout (toggles, picker, refresh button, credit
   link, subscreen layout helper), and the settings bindings bag pattern
   (snapshot + writeback) that carries pref values into and out of the
   sheet?

6. How does SingleThread test the background subsystem — the
   BackgroundImageStoreTests suite design (fake fetcher injection, temp
   directories, case inventory), the BackgroundCardTests seam assertions,
   and the background test fixtures (sample image data)?

7. What network, image, and disk persistence precedents already exist in
   CheckStitch — any existing HTTP/URLSession use, image/Data handling,
   Application Support or file writes — and what do CheckStitch's
   entitlements and app group configuration permit or restrict that could
   affect network or disk access?