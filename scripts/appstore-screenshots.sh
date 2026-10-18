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
FETCH_WALLPAPERS=0
REFETCH_WALLPAPERS=0
WALLPAPER_URLS=()
CLASSES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch-wallpapers)   FETCH_WALLPAPERS=1; shift ;;
    --refetch-wallpapers) FETCH_WALLPAPERS=1; REFETCH_WALLPAPERS=1; shift ;;
    --wallpaper-url)      FETCH_WALLPAPERS=1; WALLPAPER_URLS+=("$2"); shift 2 ;;
    --wallpaper-dir)      WALLPAPER_DIR=$2; shift 2 ;;
    --no-build)           BUILD=0; shift ;;
    --no-install)         INSTALL=0; shift ;;
    -h|--help)            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)                   echo "!! unknown option: $1" >&2; exit 2 ;;
    *)                    CLASSES+=("$1"); shift ;;
  esac
done

# class label : simctl devicetype name regex (newest runtime wins)
DEVICE_TYPES=( "iphone-6.3:iPhone 17$" )

IOS_WALLPAPER_DIR="${WALLPAPER_DIR:-scripts/fixtures/appstore-wallpapers}"
MANIFEST="$IOS_WALLPAPER_DIR/manifest.json"
WALLPAPER_API="${WALLPAPER_API:-https://vardy.cc/unsplash/random}"

# <wallpaper slot>:<output stem>; slots are per class, not per language.
SCREENS=(
  "main-dark:1-main-dark"
  "empty:2-empty"
  "settings:3-settings"
  "main-light:4-main-light"
  "detail:5-detail"
)

# The six pinned AppLanguage ids (AppLanguage.swift); each gets its own output
# directory and every shoot pins the app to that language.
LANGUAGES=(en de es fr ja zh-Hans)

wallpaper_dir() { # app-private photo directory inside the app container
  local container
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  echo "$container/Library/Application Support/CheckStitch"
}

slot_names() { # every slot for the device classes in play, as <class>-<screen>
  local entry label screen
  for entry in "${DEVICE_TYPES[@]}"; do
    label=${entry%%:*}
    for screen in "${SCREENS[@]}"; do
      echo "$label-${screen%%:*}"
    done
  done
}

fetch_wallpapers() { # one photo per slot, kept once fetched
  local slots=()
  local slot
  while IFS= read -r slot; do slots+=("$slot"); done < <(slot_names)
  mkdir -p "$IOS_WALLPAPER_DIR"
  [ -f "$MANIFEST" ] || echo '{}' >"$MANIFEST"
  python3 - "$MANIFEST" "$WALLPAPER_API" "$REFETCH_WALLPAPERS" "${WALLPAPER_URLS[@]+"${WALLPAPER_URLS[@]}"}" "${slots[@]}" <<'PY'
import datetime, hashlib, json, os, sys, urllib.request

manifest_path, api, refetch, *rest = sys.argv[1:]
slots = [item for item in rest if "=" not in item]
overrides = dict(item.split("=", 1) for item in rest if "=" in item)
directory = os.path.dirname(manifest_path)
manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}

# One photo per slot is the whole point, and the random endpoint does repeat
# itself, so every draw is checked against the photos already in play.
REDRAWS = 5


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "appstore-screenshots"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def draw(url):
    """One photo: the default endpoint is JSON describing it, while an
    explicit --wallpaper-url may already be the image itself."""
    payload = download(url)
    photographer, photographer_url = "CheckStitch", None
    try:
        described = json.loads(payload)
        photographer = described.get("photographer", "Unknown")
        photographer_url = described.get("photographer_url")
        payload = download(described["url"])
    except (ValueError, KeyError, TypeError):
        pass
    return payload, photographer, photographer_url


in_play = {}
for other, entry in manifest.items():
    path = os.path.join(directory, entry["file"])
    if os.path.isfile(path):
        in_play[digest(open(path, "rb").read())] = other

for slot in slots:
    target = os.path.join(directory, slot + ".jpg")
    if os.path.exists(target) and slot in manifest and not int(refetch):
        print("    kept {} ({})".format(slot, manifest[slot]["photographer"]))
        continue
    url = overrides.get(slot, overrides.get("*", api))
    pinned = slot in overrides or "*" in overrides
    payload, photographer, photographer_url = draw(url)
    redraws = 0
    while not pinned and in_play.get(digest(payload), slot) != slot and redraws < REDRAWS:
        redraws += 1
        payload, photographer, photographer_url = draw(url)
    clash = in_play.get(digest(payload))
    if clash and clash != slot:
        print("    !! {} still duplicates {} after {} redraws".format(slot, clash, redraws))
    with open(target, "wb") as handle:
        handle.write(payload)
    in_play[digest(payload)] = slot
    if redraws:
        print("    redrew {} {}x to avoid a duplicate".format(slot, redraws))
    manifest[slot] = {
        "file": os.path.basename(target),
        "source": url,
        "photographer": photographer,
        "photographerURL": photographer_url,
        "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
    }
    print("    fetched {} -> {} ({} bytes)".format(slot, photographer, len(payload)))

json.dump(manifest, open(manifest_path, "w"), indent=2, sort_keys=True)
PY
  echo "    manifest: $MANIFEST"
}

stage_slot() { # $1 = class, $2 = screen — pin that slot's photo into the app
  local slot="$1-$2" dir
  [ -f "$MANIFEST" ] || { echo "!! no wallpaper manifest at $MANIFEST" >&2; return 1; }
  dir=$(wallpaper_dir); mkdir -p "$dir"
  python3 - "$MANIFEST" "$slot" "$dir" <<'PY'
import datetime, json, os, shutil, sys
manifest_path, slot, target_dir = sys.argv[1:4]
entry = json.load(open(manifest_path)).get(slot)
if not entry: sys.exit(3)
source = os.path.join(os.path.dirname(manifest_path), entry["file"])
if not os.path.isfile(source): sys.exit(4)
shutil.copyfile(source, os.path.join(target_dir, "background.jpg"))
meta = {"photographer": entry["photographer"],
        "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
if entry.get("photographerURL"): meta["photographerURL"] = entry["photographerURL"]
json.dump(meta, open(os.path.join(target_dir, "background.json"), "w"))
PY
  echo "    wallpaper: $slot"
}

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
  local label=$1 pattern=$2 size=$3 udid dir language entry slot stem
  udid=$(resolve_udid "$pattern" iOS)
  [ -n "$udid" ] || { echo "!! no available simulator for '$pattern'" >&2; return 1; }
  UDID=$udid
  boot_and_install "$UDID"
  for language in "${LANGUAGES[@]}"; do
    dir="$OUT/$language/$label"; mkdir -p "$dir"
    for entry in "${SCREENS[@]}"; do
      slot=${entry%%:*}; stem=${entry##*:}
      case "$stem" in
        *-dark)  xcrun simctl ui "$UDID" appearance dark ;;
        *-light) xcrun simctl ui "$UDID" appearance light ;;
      esac
      stage_slot "$label" "$slot"
      case "$stem" in
        # Per-stem launch args; the seed env is always exported by `shoot`.
        1-main-dark)  shoot "$dir/$stem.png" --ui-testing --ui-testing-app-language "$language"; verify_size "$dir/$stem.png" "$size" ;;
        2-empty)      shoot "$dir/$stem.png" --ui-testing --ui-testing-app-language "$language" --ui-testing-empty; verify_size "$dir/$stem.png" "$size" ;;
        3-settings)   shoot "$dir/$stem.png" --ui-testing --ui-testing-app-language "$language" --ui-testing-open-settings; verify_size "$dir/$stem.png" "$size" ;;
        4-main-light) shoot "$dir/$stem.png" --ui-testing --ui-testing-app-language "$language"; verify_size "$dir/$stem.png" "$size" ;;
        5-detail)     shoot "$dir/$stem.png" --ui-testing --ui-testing-app-language "$language" --ui-testing-open-checklist 0; verify_size "$dir/$stem.png" "$size" ;;
      esac
    done
  done
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

[ ${#CLASSES[@]} -gt 0 ] || CLASSES=(iphone-6.3)
rm -rf "$OUT"; mkdir -p "$OUT"

if [ "$FETCH_WALLPAPERS" -eq 1 ]; then
  echo "==> wallpapers"
  fetch_wallpapers
fi

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