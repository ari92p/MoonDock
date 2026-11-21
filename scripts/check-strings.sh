#!/bin/bash
# Checks that every L("...") key in the Swift source exists in each Localizable.strings
# file and that no file carries keys the source no longer uses.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root" <<'PY'
import glob, re, sys
root = sys.argv[1]
src = open(f"{root}/Sources/MoonDock.swift", encoding="utf-8").read()
used = set(re.findall(r'L\("((?:[^"\\]|\\.)*)"\)', src))
failed = False
for path in sorted(glob.glob(f"{root}/Resources/*.lproj/Localizable.strings")):
    text = open(path, encoding="utf-8").read()
    keys = set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.M))
    for label, keys_missing in (("missing", used - keys), ("unused", keys - used)):
        for key in sorted(keys_missing):
            print(f"{path.split('/')[-2]}: {label} key: {key}")
            failed = True
sys.exit(1 if failed else 0)
PY
echo "Localization keys are consistent."
