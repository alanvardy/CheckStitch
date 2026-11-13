# App Store screenshot wallpapers

Per-slot background photos used only by `scripts/appstore-screenshots.sh`; they
are staged into the simulator's app container and never shipped in the app.

Fifteen slots are committed: five each for `iphone-6.3`, `ipad-13` and
`iphone-duo`. The five `iphone-duo-<screen>` slots are shared by all four Duo
variants (`outer-portrait`, `outer-landscape`, `inner-portrait`,
`inner-landscape`).

Each photo was fetched once from the Unsplash-backed endpoint
`https://vardy.cc/unsplash/random` and is used under the
[Unsplash License](https://unsplash.com/license). Photographer credit and the
source URL for every slot are recorded in `manifest.json`. `--fetch-wallpapers`
keeps existing files unless `--refetch-wallpapers` is passed, so credits stay in
sync with the committed images.
