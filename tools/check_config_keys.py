#!/usr/bin/env python3
"""Проверяет, что все литеральные пути Config.*("файл.ключ...") из src/ существуют в data/*.json.
Пути с подстановкой (%s, +) проверяются по префиксу до первой подстановки."""
import json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
FILES = {"rules": "rules.json", "units": "units.json", "zombies": "zombies.json", "civilians": "civilians.json",
         "buildings": "buildings.json", "tech": "tech.json", "doctrines": "doctrines.json", "waves": "waves.json",
         "combat": "combat.json", "map": "map_luzhniki.json"}
data = {k: json.loads((ROOT / "data" / v).read_text()) for k, v in FILES.items()}
pat = re.compile(r'Config\.(f|i|g|d|a|opt|has|keys_of|range_roll)\("([^"]+)"')
bad = 0
for p in sorted((ROOT / "src").rglob("*.gd")):
    for ln, line in enumerate(p.read_text().splitlines(), 1):
        for m in pat.finditer(line):
            fn, path = m.groups()
            if fn in ("opt", "has"):
                continue
            full = "%" not in path and not line[m.end():].lstrip().startswith("+")
            parts = path.split("%")[0].split(".")
            if not full:
                parts = parts[:-1] if parts and parts[-1] == "" else parts[:-1]
            cur = data
            ok = True
            for part in parts:
                if part == "":
                    continue
                if isinstance(cur, dict) and part in cur:
                    cur = cur[part]
                else:
                    ok = False
                    break
            if not ok:
                bad += 1
                print(f"{p.relative_to(ROOT)}:{ln}: нет ключа {path}")
print("OK" if bad == 0 else f"{bad} проблем")
sys.exit(1 if bad else 0)
