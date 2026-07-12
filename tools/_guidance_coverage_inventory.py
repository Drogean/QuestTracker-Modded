# -*- coding: utf-8 -*-
"""Generate full-catalog quest guidance coverage inventory."""
from __future__ import annotations

import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
hints = json.loads((root / "reframework/data/quest_tracker_wiki_hints.json").read_text(encoding="utf-8"))
meta = json.loads((root / "reframework/data/quest_tracker_meta.json").read_text(encoding="utf-8"))
data = json.loads((root / "reframework/data/quest_tracker_data.json").read_text(encoding="utf-8"))
manifest = {}
mp = root / "tools/data/quest_catalog_manifest.json"
if mp.exists():
    manifest = json.loads(mp.read_text(encoding="utf-8"))

by = hints.get("by_qid", {})
mq = meta.get("quests", {})
dq = data.get("quests", {}) if isinstance(data.get("quests"), dict) else {}


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(s).lower())


def actionable_hint_count(hints_map, order):
    n = 0
    for k in order or []:
        lines = (hints_map or {}).get(k)
        if not isinstance(lines, list):
            continue
        for line in lines:
            if isinstance(line, str) and line.strip() and norm(line) != norm(k):
                n += 1
                break
    return n


rows = []
for qid in sorted(by.keys(), key=lambda x: int(x)):
    r = by[qid]
    m = mq.get(qid, {})
    order = r.get("step_order") or []
    cast = r.get("step_cast") or {}
    cids = r.get("step_npc_cids") or {}
    rows.append(
        {
            "qid": qid,
            "name": m.get("name") or r.get("wiki", "").rsplit("/", 1)[-1],
            "step_order_n": len(order),
            "actionable_hint_keys": actionable_hint_count(r.get("step_hints"), order),
            "cast_nonempty": sum(1 for s in order if isinstance(cast.get(s), list) and cast.get(s)),
            "cid_n": len(cids),
            "has_npc_hours": bool(r.get("npc_hours")),
            "has_warnings": bool(r.get("warnings")),
            "has_lockout": m.get("lockout_after") is not None,
            "has_prereq": bool(m.get("prereq_quests") or m.get("available_after") is not None),
            "has_schedule": m.get("avail_hour_start") is not None or bool(r.get("npc_hours")),
            "primary_giver_cid": m.get("primary_giver_cid"),
            "in_data": qid in dq,
        }
    )

summary = {
    "catalog_records": manifest.get("catalog_records"),
    "playable_records": manifest.get("playable_records"),
    "hint_rows": len(by),
    "meta_rows": len(mq),
    "with_actionable_all_steps": sum(1 for r in rows if r["actionable_hint_keys"] == r["step_order_n"] and r["step_order_n"] > 0),
    "with_any_cast": sum(1 for r in rows if r["cast_nonempty"] > 0),
    "with_cids": sum(1 for r in rows if r["cid_n"] > 0),
    "with_warnings": sum(1 for r in rows if r["has_warnings"]),
    "with_lockout": sum(1 for r in rows if r["has_lockout"]),
    "with_prereq": sum(1 for r in rows if r["has_prereq"]),
    "with_schedule": sum(1 for r in rows if r["has_schedule"]),
    "with_primary_giver_cid": sum(1 for r in rows if isinstance(r["primary_giver_cid"], int) and r["primary_giver_cid"] > 0),
}

out = {"summary": summary, "quests": rows}
out_path = root / "tools/_guidance_coverage_inventory.json"
out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))
print("wrote", out_path)
