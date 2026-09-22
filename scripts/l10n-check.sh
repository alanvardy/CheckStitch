#!/bin/bash
set -euo pipefail
# Fast localization gate: validates every String Catalog key has all six
# languages (non-empty) and that each non-English value differs from English,
# honouring LocalizationFixtures.excludedIdentities. Mirrors
# CheckStitchTests/LocalizationTests.swift without an xcodebuild run.
#
# Usage: scripts/l10n-check.sh

cd "$(dirname "$0")/.."

python3 - <<'PY'
import json
import re
import sys
from pathlib import Path

LANGS = ["en", "de", "es", "fr", "ja", "zh-Hans"]
NON_EN = ["de", "es", "fr", "ja", "zh-Hans"]

CATALOGS = {
    "App": Path("CheckStitch/Localizable.xcstrings"),
    "Core": Path("CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings"),
    "Watch": Path("CheckStitchWatch/Localizable.xcstrings"),
}

fixtures = Path("CheckStitchTests/LocalizationFixtures.swift").read_text()
excluded = set(
    re.findall(
        r'ExclusionEntry\(\s*catalog:\s*"([^"]+)"\s*,\s*key:\s*"([^"]+)"\s*\)',
        fixtures,
    )
)

problems = []
for name, path in CATALOGS.items():
    if not path.is_file():
        problems.append(f"{name}: catalog not found at {path}")
        continue
    strings = json.loads(path.read_text()).get("strings", {})
    if not strings:
        problems.append(f"{name}: catalog has no keys")
    for key, entry in strings.items():
        locs = entry.get("localizations") or {}
        values = {}
        for lang in LANGS:
            unit = (locs.get(lang) or {}).get("stringUnit") or {}
            value = unit.get("value")
            values[lang] = value
            if not value:
                problems.append(f"{name}/{key}: missing or empty {lang}")
        english = values.get("en")
        if not english:
            continue
        if (name, key) in excluded:
            continue
        for lang in NON_EN:
            value = values.get(lang)
            if value and value == english:
                problems.append(
                    f'{name}/{key}: {lang} identical to English: "{value}"'
                )

if problems:
    print(f"l10n-check: {len(problems)} problem(s)", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

total = sum(
    len(json.loads(p.read_text()).get("strings", {})) for p in CATALOGS.values()
)
print(f"l10n-check: ok ({len(CATALOGS)} catalogs, {total} keys, {len(LANGS)} languages)")
PY