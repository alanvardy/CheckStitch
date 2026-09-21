# Task

Add in-app purchases to CheckStitch: introduce a purchasable license and require
the user to purchase it after they have run 20 checklists. Running a checklist
must track a durable count, and crossing the threshold must gate the app behind a
purchase flow (in-app purchase via StoreKit 2, wired to the `CheckStitchCore`
checklist creator and the `ContentView`). This is the LARGE-classify task for the
VAR-1058 work, sourced from `.pi/orksorksorks/alanvardy-var-1058-add-iap/large.md`.