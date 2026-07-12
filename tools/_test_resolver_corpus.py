# -*- coding: utf-8 -*-
"""Offline resolver corpus: every step_order / alternate hint key maps to actionable guidance."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HINTS = ROOT / "reframework/data/quest_tracker_wiki_hints.json"
FIXTURES = ROOT / "tools/data/resolver_fixtures.json"


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(s).lower())


def titleize(key: str) -> str:
    return " ".join(w[:1].upper() + w[1:] if w else w for w in key.split(" "))


def match_step_key_from_text(row: dict, text: str) -> str | None:
    if not text:
        return None
    low = text.lower()
    best_key, best_len, best_pri = None, 0, -1
    order = [k for k in (row.get("step_order") or []) if isinstance(k, str)]
    extras = [k for k in (row.get("step_hints") or {}) if isinstance(k, str) and k not in order]
    for pri, keys in ((2, order), (1, extras)):
        for k in keys:
            kl = k.lower()
            if kl in low and (len(kl) > best_len or (len(kl) == best_len and pri > best_pri)):
                best_key, best_len, best_pri = k, len(kl), pri
    return best_key


def actionable(row: dict, key: str) -> bool:
    lines = (row.get("step_hints") or {}).get(key)
    if not isinstance(lines, list) or not lines:
        return False
    return any(isinstance(x, str) and x.strip() and norm(x) != norm(key) for x in lines)


def build_fixtures(by: dict) -> list[dict]:
    fixtures = []
    for qid, row in sorted(by.items(), key=lambda x: int(x[0])):
        order = row.get("step_order") or []
        for key in order:
            fixtures.append(
                {
                    "qid": qid,
                    "input": titleize(key),
                    "expect_key": key,
                    "kind": "canonical",
                }
            )
        # alternate / umbrella keys present in hints but not order
        for key in row.get("step_hints") or {}:
            if key in order:
                continue
            if not actionable(row, key):
                continue
            fixtures.append(
                {
                    "qid": qid,
                    "input": titleize(key),
                    "expect_key": key,
                    "kind": "alternate",
                }
            )
        fb = row.get("fallback_step_key")
        if fb:
            fixtures.append(
                {
                    "qid": qid,
                    "input": "",
                    "expect_key": fb,
                    "kind": "fallback",
                }
            )
    return fixtures


def main() -> int:
    hints = json.loads(HINTS.read_text(encoding="utf-8"))
    by = hints.get("by_qid") or {}
    fixtures = build_fixtures(by)
    FIXTURES.parent.mkdir(parents=True, exist_ok=True)
    FIXTURES.write_text(
        json.dumps({"version": 1, "count": len(fixtures), "fixtures": fixtures}, indent=2, ensure_ascii=False)
        + "\n",
        encoding="utf-8",
    )

    errors: list[str] = []
    for fx in fixtures:
        qid = fx["qid"]
        row = by[qid]
        if fx["kind"] == "fallback":
            key = fx["expect_key"]
            if not actionable(row, key):
                errors.append(f"{qid}: fallback '{key}' not actionable")
            continue
        got = match_step_key_from_text(row, fx["input"])
        if got != fx["expect_key"]:
            errors.append(f"{qid}: input={fx['input']!r} got={got!r} want={fx['expect_key']!r}")
            continue
        if not actionable(row, got):
            errors.append(f"{qid}: matched '{got}' but hint not actionable")

    print(f"fixtures={len(fixtures)} wrote={FIXTURES}")
    if errors:
        print("FAIL", len(errors))
        for e in errors[:60]:
            print(" -", e)
        if len(errors) > 60:
            print(f" - ... +{len(errors) - 60} more")
        return 1
    print("OK resolver corpus")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
