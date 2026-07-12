#!/usr/bin/env python3
"""Strip paragraph poison from quest_tracker_wiki_hints.json."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HINTS = ROOT / "reframework" / "data" / "quest_tracker_wiki_hints.json"
REPORT = ROOT / "tools" / "scrape_report.txt"
MAX_LINE = 200


def norm_key(s: str) -> str:
    s = re.sub(r"&nbsp;?", " ", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9' ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def main() -> int:
    data = json.loads(HINTS.read_text(encoding="utf-8"))
    by_qid = data.get("by_qid", {})
    stripped_lines = 0
    nbsp_keys = 0
    paragraph_keys = 0
    cast_added = 0

    for qid, row in by_qid.items():
        if not isinstance(row, dict):
            continue
        hints = row.get("step_hints")
        if isinstance(hints, dict):
            new_hints: dict[str, list[str]] = {}
            for k, lines in hints.items():
                nk = norm_key(k)
                if nk != k:
                    nbsp_keys += 1
                if nk in new_hints and nk != k:
                    continue
                kept: list[str] = []
                if isinstance(lines, list):
                    for line in lines:
                        if not isinstance(line, str):
                            continue
                        t = re.sub(r"&nbsp;?", " ", line, flags=re.I).strip()
                        if len(t) > MAX_LINE:
                            stripped_lines += 1
                            continue
                        if len(t) >= 8:
                            kept.append(t[:MAX_LINE])
                if kept:
                    new_hints[nk] = kept[:4]
                elif isinstance(lines, list) and lines:
                    paragraph_keys += 1
            row["step_hints"] = new_hints

        if isinstance(row.get("step_order"), list):
            row["step_order"] = [norm_key(x) if isinstance(x, str) else x for x in row["step_order"]]
        if isinstance(row.get("fallback_step_key"), str):
            row["fallback_step_key"] = norm_key(row["fallback_step_key"])

        cast = row.setdefault("step_cast", {})
        if isinstance(cast, dict) and isinstance(row.get("step_order"), list):
            npcs = row.get("step_npcs") or []
            for sk in row["step_order"]:
                if sk in cast:
                    continue
                if len(npcs) == 1:
                    cast[sk] = [npcs[0]]
                    cast_added += 1

    data["by_qid"] = by_qid
    HINTS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    step_cast_n = sum(
        1 for r in by_qid.values() if isinstance(r, dict) and isinstance(r.get("step_cast"), dict) and r["step_cast"]
    )
    step_order_n = sum(
        1 for r in by_qid.values() if isinstance(r, dict) and isinstance(r.get("step_order"), list) and r["step_order"]
    )
    long_left = 0
    for r in by_qid.values():
        for lines in (r.get("step_hints") or {}).values():
            for ln in lines:
                if isinstance(ln, str) and len(ln) > MAX_LINE:
                    long_left += 1

    report = "\n".join(
        [
            f"quests={len(by_qid)}",
            f"step_order={step_order_n}",
            f"step_cast={step_cast_n}",
            f"stripped_lines={stripped_lines}",
            f"nbsp_keys_fixed={nbsp_keys}",
            f"empty_after_strip={paragraph_keys}",
            f"cast_inferred={cast_added}",
            f"paragraph_lines_remaining={long_left}",
        ]
    )
    REPORT.write_text(report + "\n", encoding="utf-8")
    print(report)
    return 1 if long_left > 5 else 0


if __name__ == "__main__":
    sys.exit(main())
