#!/usr/bin/env python3
"""Idempotently prepares pubspec.yaml: code generation for localization, asset folders, Bengali
font (only when the font files exist) and the encrypted-SQLite build hook. Works the same on
Linux and macOS. Run from the project folder."""
import os
import re
import sys

PATH = "pubspec.yaml"
lines = open(PATH, encoding="utf-8").read().split("\n")


def top_level_index(key):
    for i, line in enumerate(lines):
        if re.match(rf"^{re.escape(key)}:\s*$", line):
            return i
    return None


def section_end(start):
    for j in range(start + 1, len(lines)):
        if lines[j] and not lines[j].startswith((" ", "#")):
            return j
    return len(lines)


# ---- flutter: section
fi = top_level_index("flutter")
if fi is None:
    lines += ["", "flutter:"]
    fi = len(lines) - 1
end = section_end(fi)
body = "\n".join(lines[fi + 1:end])
inserts = []
if not re.search(r"^\s{2}generate:\s*true", body, re.M):
    inserts.append("  generate: true")
if not re.search(r"^\s{2}uses-material-design:", body, re.M):
    inserts.append("  uses-material-design: true")
have_assets = re.search(r"^\s{2}assets:", body, re.M) is not None
if not have_assets:
    inserts += ["  assets:", "    - assets/brand/", "    - assets/fonts/", "    - assets/tessdata/", "    - assets/tessdata_config.json"]
fonts_ok = all(
    os.path.exists(f"assets/fonts/NotoSansBengali-{w}.ttf") for w in ("Regular", "Bold")
)
if fonts_ok and not re.search(r"family:\s*NotoSansBengali", body):
    inserts += [
        "  fonts:",
        "    - family: NotoSansBengali",
        "      fonts:",
        "        - asset: assets/fonts/NotoSansBengali-Regular.ttf",
        "        - asset: assets/fonts/NotoSansBengali-Bold.ttf",
        "          weight: 700",
    ]
lines[fi + 1:fi + 1] = inserts

# make sure every needed asset entry is listed (also when `assets:` already existed)
needed = ["assets/brand/", "assets/fonts/", "assets/tessdata/", "assets/tessdata_config.json"]
text_now = "\n".join(lines)
if re.search(r"^\s{2}assets:", text_now, re.M):
    for entry in needed:
        if entry not in text_now:
            idx = next(i for i, line in enumerate(lines) if re.match(r"^\s{2}assets:", line))
            lines.insert(idx + 1, f"    - {entry}")
            text_now = "\n".join(lines)

# ---- hooks block for encrypted SQLite (SQLite3MultipleCiphers)
text = "\n".join(lines)
if "source: sqlite3mc" not in text:
    lines += ["", "hooks:", "  user_defines:", "    sqlite3:", "      source: sqlite3mc"]

open(PATH, "w", encoding="utf-8").write("\n".join(lines).rstrip("\n") + "\n")
print("pubspec.yaml prepared (assets, generate: true, hooks%s)" % (", Bengali font" if fonts_ok else "; Bengali font files not found yet"))
if not fonts_ok:
    print("NOTE: add assets/fonts/NotoSansBengali-Regular.ttf and -Bold.ttf, then run this script again.", file=sys.stderr)
