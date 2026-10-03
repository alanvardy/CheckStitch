#!/bin/sh
set -eu

# ci_post_clone.sh installs sentry-cli via Homebrew, whose bin dir is not
# guaranteed to be on PATH in this non-login post-build shell.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

# dSYMs only exist for archive actions.
if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
    exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
    echo "sentry-cli: SENTRY_* upload credentials not set; skipping dSYM upload."
    exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
    echo "sentry-cli: not found on PATH; skipping dSYM upload."
    exit 0
fi

sentry-cli debug-files upload \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    "$CI_ARCHIVE_PATH/dSYMs"
