#!/bin/bash
# scripts/appstore-screenshots.sh — App Store captures, per language and
# display class. `-h` prints this header.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE=app.alanvardy.CheckStitch
SCHEME=CheckStitch
DD=build/appstore-dd
APP="$DD/Build/Products/Debug-iphonesimulator/CheckStitch.app"
OUT=build/appstore-screenshots
SETTLE="${SETTLE:-6}"
SEED_FILE="$PWD/scripts/fixtures/appstore-seed.json"
BUILD=1
INSTALL=1
CLASSES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build)   BUILD=0; shift ;;
    --no-install) INSTALL=0; shift ;;
    -h|--help)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "!! unknown option: $1" >&2; exit 2 ;;
    *)            CLASSES+=("$1"); shift ;;
  esac
done

# class label : simctl devicetype name regex (newest runtime wins)
DEVICE_TYPES=( "iphone-6.3:iPhone 17$" )

resolve_udid() { # $1 = name regex, $2 = runtime family
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys
pattern, family = re.compile(sys.argv[1]), sys.argv[2]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if family not in runtime: continue
    version = tuple(int(n) for n in re.findall(r"[0-9]+", runtime.rsplit(".", 1)[-1]))
    for device in devices:
        if pattern.match(device["name"]) and (best is None or version > best[0]):
            best = (version, device["udid"])
print(best[1] if best else "")
' "$1" "$2"
}

boot_and_install() { # $1 = udid
  local udid=$1
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  if [ "$INSTALL" -eq 1 ]; then xcrun simctl install "$udid" "$APP"; fi
}

shoot() { # $1 = output path, rest = launch arguments
  local out=$1; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" \
    xcrun simctl launch "$UDID" "$BUNDLE" --terminate-running-process "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "$out" >/dev/null
  echo "    ${out#"$OUT/"}"
}

verify_size() { # $1 = file, $2 = accepted WxH
  local dims
  dims=$(sips -g pixelWidth -g pixelHeight "$1" | tail -2 | tr -dc '0-9\n' | paste -sd x -)
  if [ "$dims" != "$2" ]; then
    echo "!! ${1} is ${dims}, expected ${2}" >&2; return 1
  fi
}

capture_class() { # $1 = class label, $2 = name regex, $3 = accepted size
  local label=$1 pattern=$2 size=$3 udid dir
  udid=$(resolve_udid "$pattern" iOS)
  [ -n "$udid" ] || { echo "!! no available simulator for '$pattern'" >&2; return 1; }
  UDID=$udid
  boot_and_install "$UDID"
  dir="$OUT/en/$label"; mkdir -p "$dir"
  shoot "$dir/1-main-dark.png" --ui-testing --ui-testing-empty
  verify_size "$dir/1-main-dark.png" "$size"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

[ ${#CLASSES[@]} -gt 0 ] || CLASSES=(iphone-6.3)
rm -rf "$OUT"; mkdir -p "$OUT"

if [ "$BUILD" -eq 1 ]; then
  xcodebuild -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" build >/dev/null
fi

for entry in "${DEVICE_TYPES[@]}"; do
  label=${entry%%:*}; pattern=${entry#*:}
  for wanted in "${CLASSES[@]}"; do
    [ "$wanted" = "$label" ] && capture_class "$label" "$pattern" "1206x2622"
  done
done
echo "==> done: $OUT"