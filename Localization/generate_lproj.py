#!/usr/bin/env python3
"""Generates all 25 .lproj/Localizable.strings bundles for CmdTab."""
import os
from pathlib import Path
from translations_part1 import TRANSLATIONS_PART1
from translations_part2 import TRANSLATIONS_PART2

ROOT = Path(__file__).resolve().parent

ALL_LANGS = {}
ALL_LANGS.update(TRANSLATIONS_PART1)
ALL_LANGS.update(TRANSLATIONS_PART2)

def escape_strings_val(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )

def main():
    en_keys = list(ALL_LANGS["en"].keys())
    print(f"Generating {len(ALL_LANGS)} languages × {len(en_keys)} strings...")
    for code, table in sorted(ALL_LANGS.items()):
        lproj = ROOT / f"{code}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)
        out_path = lproj / "Localizable.strings"
        lines = [f'/* CmdTab Localization ({code}) */\n']
        for k in en_keys:
            v = table.get(k, ALL_LANGS["en"][k])
            lines.append(f'"{escape_strings_val(k)}" = "{escape_strings_val(v)}";\n')
        out_path.write_text("".join(lines), encoding="utf-8")
    print(f"Done! Generated {len(ALL_LANGS)} .lproj bundles in {ROOT}")

if __name__ == "__main__":
    main()
