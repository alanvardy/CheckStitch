#!/bin/bash
# Assert/fix the per-host Simulator.app preference that stops it auto-opening a
# window for every booted device. See 'Simulator windows' in AGENTS.md.
set -euo pipefail

DOMAIN="com.apple.iphonesimulator"
KEY="AutoOpenDevice"

# True when Simulator.app will *not* auto-attach a window to booted devices.
windowless_pref_ok() {
    local value
    value="$(defaults read "$DOMAIN" "$KEY" 2>/dev/null || true)"
    [[ "$value" == "0" ]]
}

main() {
    case "${1:-}" in
    check)
        if windowless_pref_ok; then
            return 0
        fi
        echo "warning: Simulator.app auto-open is on (${DOMAIN} ${KEY} is not 0)." >&2
        echo "         Simulator windows will appear while 'make test' runs." >&2
        echo "         One-time host fix: bash scripts/sim-windowless.sh fix" >&2
        return 1
        ;;
    fix)
        defaults write "$DOMAIN" "$KEY" -bool false
        echo "Wrote ${DOMAIN} ${KEY} = false"
        ;;
    *)
        echo "usage: sim-windowless.sh {check|fix}" >&2
        return 2
        ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi