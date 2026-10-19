#!/bin/bash
# scripts/appstore-screenshots.sh — App Store captures, per language and
# display class.
#
# Usage:
#   scripts/appstore-screenshots.sh [options] [class ...]
#
# Output tree: build/appstore-screenshots/<lang>/<device>/<n>-<name>.png, plus
# a per-run manifest.json naming the class, device, size and screens captured.
#
# Known classes and their target sizes (pre/post-flight checked with sips):
#   iphone-6.3  iPhone 17, 1206x2622
#   ipad-13     iPad Pro 13-inch (M5), 2064x2752
#   watch-46mm  Apple Watch Series 11 (46mm), 416x496
#
# Wallpapers live in scripts/fixtures/appstore-wallpapers/; each slot is named
# <class>-<screen> and is staged into the app container before the matching
# shot. `--fetch-wallpapers` fetches new photos from the API.
#
# Options:
#   --no-build            skip the xcodebuild step
#   --no-install          boot the simulator but skip installing the app
#   --settle <seconds>    settle time after launch before shooting (default 6)
#   --lang <id>           capture only this AppLanguage id
#   --udid <class>=<udid> pin a class to an explicit simulator UDID
#   --fetch-wallpapers    fetch wallpapers before capturing
#   --refetch-wallpapers  refetch wallpapers even if already present
#   --wallpaper-url <slot|*>=<url>  pin a slot (or all) to a specific photo
#   --wallpaper-dir <dir> wallpaper + manifest directory
#   -h, --help            print this header and exit 0
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE=app.alanvardy.CheckStitch
SCHEME=CheckStitch
DD=build/appstore-dd
APP="$DD/Build/Products/Debug-iphonesimulator/CheckStitch.app"

# Standalone watch leg: its own scheme, bundle and built app. `make watch-build`
# uses the same destination, so the built app lands in Debug-watchsimulator.
WATCH_SCHEME=CheckStitchWatch
WATCH_BUNDLE=app.alanvardy.CheckStitch.watchkitapp
WATCH_APP="$DD/Build/Products/Debug-watchsimulator/CheckStitchWatch.app"
WATCH_CLASS=watch-46mm
WATCH_PATTERN='Apple Watch Series 11 \(46mm\)'
WATCH_SCREENS=( "1-list" "2-detail" )

OUT=build/appstore-screenshots
SETTLE="${SETTLE:-6}"
SEED_FILE="$PWD/scripts/fixtures/appstore-seed.json"
BUILD=1
INSTALL=1
FETCH_WALLPAPERS=0
REFETCH_WALLPAPERS=0
WALLPAPER_URLS=()
CLASSES=()
OVERRIDE_CLASSES=()
OVERRIDE_UDIDS=()

# The six pinned AppLanguage ids (AppLanguage.swift); each gets its own output
# directory and every shoot pins the app to that language. --lang overrides.
LANGUAGES=(en de es fr ja zh-Hans)

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch-wallpapers)   FETCH_WALLPAPERS=1; shift ;;
    --refetch-wallpapers) FETCH_WALLPAPERS=1; REFETCH_WALLPAPERS=1; shift ;;
    --wallpaper-url)      FETCH_WALLPAPERS=1; WALLPAPER_URLS+=("$2"); shift 2 ;;
    --wallpaper-dir)      WALLPAPER_DIR=$2; shift 2 ;;
    --no-build)           BUILD=0; shift ;;
    --no-install)         INSTALL=0; shift ;;
    --settle)             SETTLE=$2; shift 2 ;;
    --lang)               LANGUAGES=("$2"); shift 2 ;;
    --udid)               OVERRIDE_CLASSES+=("${2%%=*}"); OVERRIDE_UDIDS+=("${2#*=}"); shift 2 ;;
    -h|--help)            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)                   echo "!! unknown option: $1" >&2; exit 2 ;;
    *)                    CLASSES+=("$1"); shift ;;
  esac
done

# class label : simctl devicetype name regex (newest runtime wins)
DEVICE_TYPES=( "iphone-6.3:iPhone 17$" "ipad-13:iPad Pro 13-inch \\(M5\\)" )

# No associative arrays: /bin/bash 3.2 (the gate's `bash -n` parser) rejects them.
size_for() { # $1 = class label
  case "$1" in
    iphone-6.3) echo "1206x2622" ;;
    ipad-13)    echo "2064x2752" ;;
    watch-46mm) echo "416x496" ;;
  esac
}

device_name_for() { # $1 = class label; the model name recorded in the manifest
  case "$1" in
    iphone-6.3) echo "iPhone 17" ;;
    ipad-13)    echo "iPad Pro 13-inch (M5)" ;;
    watch-46mm) echo "Apple Watch Series 11 (46mm)" ;;
  esac
}

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

udid_override_for() { # $1 = class label; prints an explicit UDID or nothing
  local i
  for i in "${!OVERRIDE_CLASSES[@]}"; do
    if [ "${OVERRIDE_CLASSES[$i]}" = "$1" ]; then
      printf '%s' "${OVERRIDE_UDIDS[$i]}"; return 0
    fi
  done
}

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

boot_and_install() { # $1 = udid, $2 = app path (default $APP)
  local udid=$1 app=${2:-$APP}
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  if [ "$INSTALL" -eq 1 ]; then xcrun simctl install "$udid" "$app"; fi
}

shoot() { # $1 = output path, rest = launch arguments
  local out=$1; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" \
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
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

preflight_size() { # $1 = udid, $2 = expected WxH
  local tmp dims
  tmp=$(mktemp -t appstore-preflight).png
  xcrun simctl io "$1" screenshot --mask ignored "$tmp" >/dev/null
  dims=$(sips -g pixelWidth -g pixelHeight "$tmp" | tail -2 | tr -dc '0-9\n' | paste -sd x -)
  rm -f "$tmp"
  if [ "$dims" != "$2" ]; then
    echo "!! simulator $1 captures ${dims}, expected ${2}" >&2; return 1
  fi
}

write_manifest() { # $1 = lang, $2 = class, $3 = device model, $4 = udid, $5 = size, rest = screens
  local lang=$1 class=$2 device=$3 udid=$4 size=$5; shift 5
  python3 - "$OUT/$lang/$class/manifest.json" "$class" "$device" "$udid" "$size" "$@" <<'PY'
import json, sys
path, klass, device, udid, size, *screens = sys.argv[1:]
json.dump({"class": klass, "device": device, "udid": udid,
           "size": size, "screens": screens},
          open(path, "w"), indent=2, sort_keys=True)
PY
}

capture_class() { # $1 = class label, $2 = name regex, $3 = accepted size
  local label=$1 pattern=$2 size=$3 udid dir language entry slot stem
  local stems=()
  udid=$(udid_override_for "$label")
  [ -n "$udid" ] || udid=$(resolve_udid "$pattern" iOS)
  [ -n "$udid" ] || { echo "!! no available simulator for '$pattern'" >&2; return 1; }
  UDID=$udid
  boot_and_install "$UDID"
  preflight_size "$UDID" "$size"
  for language in "${LANGUAGES[@]}"; do
    dir="$OUT/$language/$label"; rm -rf "$dir"; mkdir -p "$dir"
    stems=()
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
      stems+=("$stem")
    done
    write_manifest "$language" "$label" "$(device_name_for "$label")" "$UDID" "$size" "${stems[@]}"
  done
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

watch_shot() { # $1 = output path, rest = watch launch arguments
  local out=$1; shift
  xcrun simctl terminate "$UDID" "$WATCH_BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" \
    xcrun simctl launch "$UDID" "$WATCH_BUNDLE" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "$out" >/dev/null
  echo "    ${out#"$OUT/"}"
}

capture_watch() {
  local udid dir language size
  size=$(size_for "$WATCH_CLASS")
  udid=$(udid_override_for "$WATCH_CLASS")
  [ -n "$udid" ] || udid=$(resolve_udid "$WATCH_PATTERN" watchOS)
  [ -n "$udid" ] || { echo "!! no available watch simulator for '$WATCH_PATTERN'" >&2; return 1; }
  UDID=$udid
  boot_and_install "$UDID" "$WATCH_APP"
  preflight_size "$UDID" "$size"
  for language in "${LANGUAGES[@]}"; do
    dir="$OUT/$language/$WATCH_CLASS"; rm -rf "$dir"; mkdir -p "$dir"
    watch_shot "$dir/1-list.png" --ui-testing --ui-testing-app-language "$language"; verify_size "$dir/1-list.png" "$size"
    watch_shot "$dir/2-detail.png" --ui-testing --ui-testing-app-language "$language" --ui-testing-open-checklist 0; verify_size "$dir/2-detail.png" "$size"
    write_manifest "$language" "$WATCH_CLASS" "$(device_name_for "$WATCH_CLASS")" "$UDID" "$size" "${WATCH_SCREENS[@]}"
  done
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}

[ ${#CLASSES[@]} -gt 0 ] || CLASSES=(iphone-6.3)

for wanted in "${CLASSES[@]}"; do
  case "$wanted" in
    iphone-6.3|ipad-13|watch-46mm) ;;
    *) echo "!! unknown class: $wanted (expected iphone-6.3, ipad-13 or watch-46mm)" >&2; exit 2 ;;
  esac
done

for language in "${LANGUAGES[@]}"; do
  case "$language" in
    en|de|es|fr|ja|zh-Hans) ;;
    *) echo "!! unknown language: $language (expected en, de, es, fr, ja or zh-Hans)" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT"

if [ "$FETCH_WALLPAPERS" -eq 1 ]; then
  echo "==> wallpapers"
  fetch_wallpapers
fi

if [ "$BUILD" -eq 1 ]; then
  xcodebuild -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" build >/dev/null
  if [[ " ${CLASSES[*]} " == *" $WATCH_CLASS "* ]]; then
    xcodebuild -scheme "$WATCH_SCHEME" -configuration Debug \
      -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$DD" build >/dev/null
  fi
fi

for entry in "${DEVICE_TYPES[@]}"; do
  label=${entry%%:*}; pattern=${entry#*:}
  for wanted in "${CLASSES[@]}"; do
    [ "$wanted" = "$label" ] && capture_class "$label" "$pattern" "$(size_for "$label")"
  done
done

for wanted in "${CLASSES[@]}"; do
  [ "$wanted" = "$WATCH_CLASS" ] && capture_watch
done
echo "==> done: $OUT"