# -*- coding: utf-8 -*-
"""Fill empty step_cast / step_npc_cids from step_order names + learned CIDs.

Does not invent npc_hours. Does not overwrite nonempty curated casts.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HINTS = ROOT / "reframework/data/quest_tracker_wiki_hints.json"
META = ROOT / "reframework/data/quest_tracker_meta.json"
PREFS = Path(
    r"C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\reframework\data\quest_tracker_prefs.json"
)

PERSON_HINT = re.compile(
    r"\b(speak|talk|report|deliver|give|return|meet|visit|escort|accompany|aid|find|lead|follow|inform|bring)\b",
    re.I,
)


def load_name_to_cid() -> dict[str, int]:
    name_to_cid: dict[str, int] = {}
    # Existing wiki_hints CIDs first
    hints = json.loads(HINTS.read_text(encoding="utf-8"))
    for row in (hints.get("by_qid") or {}).values():
        for n, c in (row.get("step_npc_cids") or {}).items():
            if isinstance(n, str) and isinstance(c, int) and c > 0:
                name_to_cid[n] = c
    # Meta givers
    meta = json.loads(META.read_text(encoding="utf-8"))
    for row in (meta.get("quests") or {}).values():
        gn = row.get("giver_name")
        pc = row.get("primary_giver_cid")
        if isinstance(gn, str) and isinstance(pc, int) and pc > 0:
            name_to_cid.setdefault(gn, pc)
    # Learned runtime names (cid -> name)
    if PREFS.exists():
        prefs = json.loads(PREFS.read_text(encoding="utf-8"))
        learned = prefs.get("learned_chara_names") or {}
        for cid_s, name in learned.items():
            try:
                cid = int(cid_s)
            except (TypeError, ValueError):
                continue
            if isinstance(name, str) and name.strip() and cid > 0:
                name_to_cid.setdefault(name.strip(), cid)
    return name_to_cid


def names_in_step(sk: str, known: list[str]) -> list[str]:
    low = sk.lower()
    found: list[str] = []
    for nm in known:
        nlow = nm.lower()
        # whole-word-ish: allow "captain brant" containing "brant"
        if re.search(rf"(?<![a-z0-9]){re.escape(nlow)}(?![a-z0-9])", low):
            found.append(nm)
    return found


def main() -> None:
    name_to_cid = load_name_to_cid()
    # Longest names first so "Rivage Elder" beats "Elder"
    known = sorted(name_to_cid.keys(), key=lambda s: (-len(s), s.lower()))
    data = json.loads(HINTS.read_text(encoding="utf-8"))
    by = data["by_qid"]
    filled = 0
    skipped = 0
    for qid, row in by.items():
        cast = row.get("step_cast") or {}
        nonempty = sum(1 for v in cast.values() if isinstance(v, list) and len(v) > 0)
        if nonempty > 0:
            skipped += 1
            # Still backfill missing CIDs for existing cast names
            cids = dict(row.get("step_npc_cids") or {})
            changed = False
            for v in cast.values():
                if not isinstance(v, list):
                    continue
                for nm in v:
                    if nm in name_to_cid and nm not in cids:
                        cids[nm] = name_to_cid[nm]
                        changed = True
            if changed:
                row["step_npc_cids"] = cids
            continue

        order = row.get("step_order") or []
        if not order:
            continue
        new_cast: dict[str, list[str]] = {}
        used: set[str] = set()
        for sk in order:
            hits = names_in_step(sk, known) if PERSON_HINT.search(sk) or names_in_step(sk, known) else []
            # Always try name match even on location-looking keys
            if not hits:
                hits = names_in_step(sk, known)
            new_cast[sk] = hits
            for h in hits:
                used.add(h)
        if not used:
            continue
        row["step_cast"] = new_cast
        cids = dict(row.get("step_npc_cids") or {})
        for nm in used:
            if nm in name_to_cid:
                cids[nm] = name_to_cid[nm]
        row["step_npc_cids"] = cids
        filled += 1
        print(f"{qid}: cast NPCs={sorted(used)}")

    HINTS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"filled_empty={filled} skipped_nonempty={skipped} known_names={len(known)}")


if __name__ == "__main__":
    main()
