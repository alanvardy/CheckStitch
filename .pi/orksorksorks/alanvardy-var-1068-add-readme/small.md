# Task

Add a `README.md` to the CheckStitch repository root (it currently has none), writing it as a
marketing/product README modeled on the CheckStitch page at
`/Users/vardy/dev/vardy/templates/checkstitch.html` (the "example" the ticket references). Blog the
same shape the sibling `SingleThread` repo already uses: a `# SingleThread` title, tagline, an App
Store badge block (only if a badge exists — CheckStitch has **no** App Store presence yet, so omit
the badge), followed by the platform list, a short "what it is" intro, and the feature/privacy
sections — adapted to CheckStitch's actual behavior.

CheckStitch facts to use (from `AGENTS.md` and `CheckStitchCore`/UI):
- Turns a list of items into Apple Reminders — one reminder per item, grouped in a checklists
  list; runs a checklist to bulk-create reminders.
- Works on iPhone, iPad, Mac, and Apple Watch (a `CheckStitchWatch` watchOS target exists).
- It only ever **creates** reminders — it never reads, edits, completes, or deletes them afterwards.
- Number Reminders prefixes each title with its position; notes under an item ride into the
  reminder's note; user picks the destination list; checklists live on device and sync via the
  user's own iCloud (no account to create); export/import from Settings; System/Light/Dark
  appearance plus an optional nature wallpaper.
- No analytics/tracking/advertising. The only network traffic is the optional background wallpaper.
- There is no App Store listing, so do **not** add a "Download on the App Store" badge.
- Do not fabricate features that the app does not have; keep copy honest to the page and AGENTS.md.

## Why SMALL

Single file (`README.md` at repo root), no code/schema/test-surface touched, and an existing
pattern to copy (the `SingleThread` repo's README, which is itself the marketing page in README
form). Approach is fully known — no unknowns, no design decision, no sign-off needed.

## Key files

- `/Users/vardy/dev/vardy/templates/checkstitch.html` — the example page to model content on.
- `/Users/vardy/dev/SingleThread/README.md` — the repo-level README pattern to match in tone and
  structure (tagline, platform line, sections, "Thoughtful by design"-style privacy bullets).
- `/Users/vardy/dev/alanvardy-var-1068-add-readme/AGENTS.md` — authoritative app facts and the
  "create-only" constraint (check `CheckStitchCore` if any fact is in doubt).
- Write the file to `/Users/vardy/dev/alanvardy-var-1068-add-readme/README.md`.

No tests are required; verify with a read-through against the facts above. The gate
(`./scripts/test.sh`) is not affected by a docs-only change, but still run it if you touch anything
else.