#!/bin/sh
set -eu

# sentry-cli powers the dSYM upload in ci_post_xcodebuild.sh.
if ! command -v sentry-cli >/dev/null 2>&1; then
    brew install getsentry/tools/sentry-cli
fi

# Bake the release DSN into the app's Info.plist from the Xcode Cloud
# Environment variable. Left untouched locally, where $(SENTRY_DSN) expands
# to an empty string and the feature stays inert.
if [ -n "${SENTRY_DSN:-}" ]; then
    cd "$CI_PRIMARY_REPOSITORY_PATH"
    /usr/libexec/PlistBuddy -c "Set :SENTRY_DSN $SENTRY_DSN" CheckStitch/Info.plist
fi
