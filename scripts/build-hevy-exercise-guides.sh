#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSV="${ROOT}/fixtures/HevyExport.csv"
DB="${ROOT}/Signal/Signal/Resources/free-exercise-db.json"
OUT="${ROOT}/Signal/Signal/Resources/HevyExerciseGuides.json"

python3 << PYEOF
import csv, json, re
from pathlib import Path

csv_path = Path("${CSV}")
db_path = Path("${DB}")
out_path = Path("${OUT}")

titles = set()
with csv_path.open() as f:
    for row in csv.DictReader(f):
        t = row.get("exercise_title", "").strip()
        if t:
            titles.add(t)

db = json.loads(db_path.read_text())

def normalize(s):
    s = re.sub(r"[^a-z0-9 ]", "", s.lower())
    return " ".join(s.split())

def strip_paren(s):
    while "(" in s and s.endswith(")"):
        idx = s.rfind("(")
        if idx > 0:
            s = s[:idx].strip()
        else:
            break
    return s

def score_match(hevy_title, db_name):
    h = normalize(strip_paren(hevy_title))
    d = normalize(db_name)
    if h == d:
        return 1.0
    if h in d or d in h:
        return 0.85
    hw = set(h.split())
    dw = set(d.split())
    if not hw or not dw:
        return 0
    return len(hw & dw) / max(len(hw), len(dw))

guides = []
for title in sorted(titles):
    best = None
    best_score = 0
    for ex in db:
        sc = score_match(title, ex["name"])
        if sc > best_score:
            best_score = sc
            best = ex
    if best and best_score >= 0.5 and best.get("instructions"):
        guides.append({
            "hevyTitle": title,
            "canonicalName": best["name"],
            "instructions": best["instructions"],
            "sourceExerciseId": best["id"],
        })

out_path.write_text(json.dumps({
    "version": 1,
    "generatedFrom": "fixtures/HevyExport.csv",
    "exerciseCount": len(guides),
    "guides": guides,
}, indent=2))
print(f"Wrote {len(guides)} guides to {out_path}")
PYEOF
