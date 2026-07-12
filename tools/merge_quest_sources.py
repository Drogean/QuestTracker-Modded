#!/usr/bin/env python3
"""Gate quest_tracker_wiki_hints.json coverage for ship.

Fails if any meta QID lacks step_order or has empty/echo-only hints.
Does NOT invent title-as-hint placeholders.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
META_PATH = ROOT / "reframework" / "data" / "quest_tracker_meta.json"
HINTS_PATH = ROOT / "reframework" / "data" / "quest_tracker_wiki_hints.json"
MANIFEST_PATH = ROOT / "tools" / "data" / "quest_catalog_manifest.json"


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(s).lower())


def echo_only(step: str, lines: object) -> bool:
    if not isinstance(lines, list) or not lines:
        return True
    useful = [str(x).strip() for x in lines if str(x).strip()]
    if not useful:
        return True
    return all(norm(x) == norm(step) for x in useful)


def load_meta_qids() -> list[str]:
    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    quests = meta.get("quests") or {}
    return sorted({str(k) for k in quests if str(k).isdigit()})


def main() -> int:
    hints = json.loads(HINTS_PATH.read_text(encoding="utf-8"))
    hints["version"] = max(int(hints.get("version") or 0), 4)
    by = hints.get("by_qid") or {}
    qids = load_meta_qids()
    miss_order: list[str] = []
    bad_hints: list[str] = []
    for qid in qids:
        row = by.get(qid)
        if not row or not row.get("step_order"):
            miss_order.append(qid)
            continue
        sh = row.get("step_hints") or {}
        for key in row["step_order"]:
            if echo_only(key, sh.get(key)):
                bad_hints.append(f"{qid}:{key}")

    if MANIFEST_PATH.exists():
        man = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        if len(man.get("records") or []) != 85:
            print(f"FAIL manifest records != 85 ({len(man.get('records') or [])})")
            return 1

    HINTS_PATH.write_text(json.dumps(hints, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wiki_hints: {HINTS_PATH}")
    print(f"meta_qids={len(qids)} hint_rows={len(by)}")
    if miss_order:
        print("FAIL missing step_order:", ", ".join(miss_order[:40]))
        return 1
    if bad_hints:
        print("FAIL empty/echo hints:", len(bad_hints))
        for x in bad_hints[:40]:
            print(" -", x)
        return 1
    print("OK coverage gate (no placeholder fill)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
