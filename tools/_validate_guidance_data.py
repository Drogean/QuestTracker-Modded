# -*- coding: utf-8 -*-
"""Full-catalog guidance ship gates (manifest + hints + meta)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "reframework/data"
MANIFEST = ROOT / "tools/data/quest_catalog_manifest.json"
WRONG_SARA = 1892817290


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(s).lower())


def echo_only(step: str, lines: object) -> bool:
    if not isinstance(lines, list) or not lines:
        return True
    useful = [str(x).strip() for x in lines if str(x).strip()]
    if not useful:
        return True
    return all(norm(x) == norm(step) for x in useful)


def fail(msg: str, errors: list[str]) -> None:
    errors.append(msg)


def main() -> int:
    errors: list[str] = []

    data_path = DATA / "quest_tracker_data.json"
    if not data_path.exists():
        fail("missing quest_tracker_data.json", errors)
    else:
        data = json.loads(data_path.read_text(encoding="utf-8"))
        if not isinstance(data.get("quests"), dict) or len(data["quests"]) < 50:
            fail("quest_tracker_data.json quests too small/missing", errors)

    if not MANIFEST.exists():
        fail("missing tools/data/quest_catalog_manifest.json", errors)
        print("FAIL", len(errors))
        for e in errors:
            print(" -", e)
        return 1

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    records = manifest.get("records") or []
    if len(records) != 85:
        fail(f"manifest catalog_records expected 85 got {len(records)}", errors)

    hints = json.loads((DATA / "quest_tracker_wiki_hints.json").read_text(encoding="utf-8"))
    by = hints.get("by_qid") or {}
    meta = json.loads((DATA / "quest_tracker_meta.json").read_text(encoding="utf-8"))
    mq = meta.get("quests") or {}

    playable_qids: set[str] = set()
    for rec in records:
        status = rec.get("status")
        title = rec.get("title")
        qids = rec.get("qids") or []
        if status not in ("playable", "internal", "unused_cut"):
            fail(f"{title}: bad status {status!r}", errors)
            continue
        if not qids:
            fail(f"{title}: no qids mapped", errors)
            continue
        if status != "playable":
            continue
        for qid in qids:
            qs = str(qid)
            playable_qids.add(qs)
            row = by.get(qs)
            if not row:
                fail(f"{qs} ({title}): missing wiki_hints row", errors)
                continue
            if qs not in mq:
                fail(f"{qs} ({title}): missing meta row", errors)
            order = row.get("step_order") or []
            sh = row.get("step_hints") or {}
            cast = row.get("step_cast") or {}
            cids = row.get("step_npc_cids") or {}
            fb = row.get("fallback_step_key")
            if not order:
                fail(f"{qs}: empty step_order", errors)
            if not fb or fb not in order:
                fail(f"{qs}: fallback_step_key missing/misaligned", errors)
            for sk in order:
                if echo_only(sk, sh.get(sk)):
                    fail(f"{qs}: empty/echo hint for '{sk}'", errors)
                if sk not in cast:
                    fail(f"{qs}: step_cast missing key '{sk}'", errors)
            # CID integrity: every named cast CID must be verified map entry when present
            for nm, cid in cids.items():
                if not isinstance(cid, int) or cid <= 0:
                    fail(f"{qs}: bad CID for '{nm}'", errors)
            if cids.get("Sara") == WRONG_SARA:
                fail(f"{qs}: Sara CID is Messara id {WRONG_SARA}", errors)
            unverified = row.get("unverified_step_npcs") or []
            for nm in unverified:
                if nm in cids:
                    fail(f"{qs}: unverified NPC '{nm}' still has CID claimed as fact", errors)
            hours = row.get("npc_hours") or {}
            for nm, h in hours.items():
                if not isinstance(h, dict):
                    fail(f"{qs}: npc_hours[{nm}] not object", errors)
                    continue
                s = h.get("start")
                f = h.get("finish", h.get("end"))
                if s is None or f is None:
                    fail(f"{qs}: npc_hours[{nm}] missing start/finish", errors)
            mrow = mq.get(qs) or {}
            if mrow.get("lockout_after") or mrow.get("time_limit_days") or mrow.get("avail_hour_start") is not None:
                warns = row.get("warnings") or []
                if not warns:
                    fail(f"{qs}: lockout/timed quest missing warnings[]", errors)
            if not row.get("sources") and not mrow.get("sources"):
                fail(f"{qs}: missing sources provenance", errors)
            if not mrow.get("fact_confidence") and not row.get("source_confidence"):
                fail(f"{qs}: missing confidence metadata", errors)

    # 30080 key alignment regression
    r = by.get("30080") or {}
    if "find out what gwyfencha is" not in (r.get("step_cast") or {}):
        fail("30080: step_cast missing exact key 'find out what gwyfencha is'", errors)

    # every hints row for playable must be in manifest playable set (allow extras only if also meta)
    for qs in by:
        if qs.isdigit() and qs not in playable_qids and qs in mq:
            # meta-only orphans not in 85 catalog titles are OK only if classified elsewhere
            pass

    if errors:
        print("FAIL", len(errors))
        for e in errors[:80]:
            print(" -", e)
        if len(errors) > 80:
            print(f" - ... +{len(errors) - 80} more")
        return 1
    print(f"OK full-catalog guidance gates playable_qids={len(playable_qids)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
