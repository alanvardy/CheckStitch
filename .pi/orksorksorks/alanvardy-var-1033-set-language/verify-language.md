# VAR-1033 — Live language flip evidence

Record, in this order:

1. **What the user should see**: after choosing Deutsch, the Settings sheet
   header reads `Einstellungen`, the first section `Oberfläche`, the picker
   `Sprache`, the picker rows System/Hell/Dunkel, and the toolbar button
   `Fertig`; the checklist list empty state and the item editor's priority rows
   are German too.

2. **Why the hosted gate cannot see it**: the unit runner resolves
   `String(localized:)` with the process (English) locale
   (`CheckStitchTests/LocalizationTests.swift:77-78`), so `LocalizationTests` is
   not evidence for the live flip. The live flip is evidenced only by the
   simulator screenshot diff below.

3. **Screenshot-diff procedure** (per the `simulator` skill):
   ```bash
   UDID=D6D3CD6F-F7EF-4265-8E93-389ED04891EB   # this worktree's .simulator_id
   make run
   xcrun simctl io "$UDID" screenshot /tmp/lang-en.png     # Settings sheet, English
   # select Deutsch in the running app
   xcrun simctl io "$UDID" screenshot /tmp/lang-de.png     # same screen, German
   shasum -a 256 /tmp/lang-en.png /tmp/lang-de.png         # digests must differ
   ```
   Paste the two digests and the two screenshot paths into this file. A digest
   match means the flip did not happen — treat as a failure.

4. **macOS**: `make build-mac` compiles the macOS slice (gate leg); runtime
   evidence is the signed `make build-mac-signed` manual run, because container
   launches do not surface to the host (spike finding).