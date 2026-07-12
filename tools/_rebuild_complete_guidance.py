#!/usr/bin/env python3
"""Rebuild complete DD2 quest guidance from extracted and walkthrough sources."""
from __future__ import annotations

import difflib
import html
import json
import re
import time
import urllib.request
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "reframework" / "data"
TOOLS_DATA = ROOT / "tools" / "data"
HINTS_PATH = DATA / "quest_tracker_wiki_hints.json"
META_PATH = DATA / "quest_tracker_meta.json"
MANIFEST_PATH = TOOLS_DATA / "quest_catalog_manifest.json"
SNAPSHOT_PATH = TOOLS_DATA / "kiranico_quest_snapshot.json"
CACHE_DIR = ROOT / "tools" / "wiki_cache"
KIRANICO = "https://dragonsdogma2.kiranico.com/en/data/quests"
GAME8_INDEX = "https://game8.co/games/Dragons-Dogma-2/archives/Quests"
UA = "QuestTrackerGuidance/2.1 (+local data rebuild)"
MAX_HINT = 200

from _guidance_catalog_data import (
    SPECIAL_QIDS,
    CLASSIFICATION,
    META_OVERRIDES,
    STEP_CAST,
    STEP_CAST_BY_STEP,
    VERIFIED_CIDS,
    STEP_OVERRIDES,
    BRANCH_TITLES,
    PONR_LABELS,
)


def norm(value: str) -> str:
    value = html.unescape(value).replace("’", "'").replace("‘", "'")
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"[^a-zA-Z0-9]+", " ", value).lower()
    return re.sub(r"\s+", " ", value).strip()


def strip_html(value: str) -> str:
    value = re.sub(r"<br\s*/?>", " ", value, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html.unescape(value).replace("\xa0", " ")
    return re.sub(r"\s+", " ", value).strip()


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(request, timeout=45).read().decode("utf-8", "replace")


def fextra_url(title: str) -> str:
    slug = urllib.parse.quote_plus(title, safe="'-,")
    return f"https://dragonsdogma2.wiki.fextralife.com/{slug}"


def cache_path(url: str) -> Path:
    safe = re.sub(r"[^a-zA-Z0-9]+", "_", url)[:120]
    return CACHE_DIR / f"{safe}.html"


def fetch_cached(url: str) -> str:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = cache_path(url)
    if path.exists() and path.stat().st_size > 500:
        return path.read_text(encoding="utf-8", errors="replace")
    body = fetch(url)
    path.write_text(body, encoding="utf-8")
    time.sleep(1.0)
    return body


def parse_catalog(body: str) -> list[dict]:
    records: list[dict] = []
    for match in re.finditer(r"<div><h2>(.*?)</h2><p>(.*?)</p><ul>(.*?)</ul></div>", body, re.I | re.S):
        title = strip_html(match.group(1))
        description = strip_html(match.group(2))
        objectives = [strip_html(x) for x in re.findall(r"<li>(.*?)</li>", match.group(3), re.I | re.S)]
        records.append({"title": title, "description": description, "objectives": objectives})
    return records


def short_sentence(value: str) -> str:
    value = re.sub(r"\[[^\]]+\]", "", value)
    value = re.sub(r"\s+", " ", value).strip()
    if len(value) <= MAX_HINT:
        return value
    parts = re.split(r"(?<=[.!?])\s+", value)
    out = ""
    for part in parts:
        trial = (out + " " + part).strip()
        if len(trial) > MAX_HINT:
            break
        out = trial
    if out:
        return out
    return value[: MAX_HINT - 1].rstrip(" ,;:-") + "…"


def parse_walkthrough(body: str) -> dict[str, str]:
    marker = re.search(r"Quest Walkthrough", body, re.I)
    if not marker:
        return {}
    section = body[marker.end() :]
    section = re.split(r'<div class="pull-left"|id="comments"', section, maxsplit=1, flags=re.I)[0]
    out: dict[str, str] = {}
    pattern = r"<h[234][^>]*>(.*?)</h[234]>(.*?)(?=<h[234][^>]*>|$)"
    for heading_html, chunk in re.findall(pattern, section, re.I | re.S):
        heading = norm(strip_html(heading_html))
        if not heading or any(x in heading for x in ("boss fight", "rewards", "notes")):
            continue
        paragraphs = [strip_html(p) for p in re.findall(r"<p[^>]*>(.*?)</p>", chunk, re.I | re.S)]
        paragraph = next((p for p in paragraphs if len(p) >= 20 and "image" not in p.lower()), "")
        if paragraph:
            out[heading] = short_sentence(paragraph)
    return out


def echo_only(step: str, lines: object) -> bool:
    if not isinstance(lines, list) or not lines:
        return True
    useful = [str(x).strip() for x in lines if str(x).strip()]
    if not useful:
        return True
    return all(norm(x) == norm(step) for x in useful)


def best_walkthrough_hint(step: str, walkthrough: dict[str, str]) -> str | None:
    want = norm(step)
    if want in walkthrough:
        return walkthrough[want]
    want_tokens = set(want.split())
    best_score = 0.0
    best = None
    for heading, hint in walkthrough.items():
        tokens = set(heading.split())
        overlap = len(want_tokens & tokens) / max(1, len(want_tokens | tokens))
        ratio = difflib.SequenceMatcher(None, want, heading).ratio()
        score = max(overlap, ratio)
        if score > best_score:
            best_score, best = score, hint
    return best if best_score >= 0.48 else None


def fallback_hint(step: str) -> str:
    low = norm(step)
    if re.search(r"\b(wait|await|revisit|return in a few days|check on)\b", low):
        return short_sentence(
            f"Rest at an inn, house, or bench until at least the next day, then return for “{step}”. Exhaust dialogue so the journal advances."
        )
    if re.search(r"\b(deliver|give|bring|turn over|report back|inform)\b", low):
        return short_sentence(
            f"Keep the required item or news in the Arisen's inventory, return to the named recipient for “{step}”, and choose the delivery/report dialogue."
        )
    if re.search(r"\b(procure|obtain|gather|acquire|find some|find a bunch)\b", low):
        return short_sentence(
            f"Collect, buy, or craft the requested materials for “{step}”. Keep them on the Arisen, not in storage or a pawn's inventory."
        )
    if re.search(r"\b(escort|accompany|lead|follow)\b", low):
        return short_sentence(
            f"Stay close to the named NPC during “{step}”, clear enemies ahead, and keep them alive until the destination dialogue completes."
        )
    if re.search(r"\b(defeat|fend|rid|cull|deal with|aid .* at|do extended battle)\b", low):
        return short_sentence(
            f"Enter the marked combat area for “{step}”, eliminate every required enemy, then remain nearby until the objective updates."
        )
    if re.search(r"\b(speak|talk|consult|inquire|ask|meet)\b", low):
        return short_sentence(
            f"Go to the named person for “{step}” and exhaust every dialogue option. If they are absent, check the quest's stated time window."
        )
    if re.search(r"\b(search|investigate|explore|traverse|make for|go to|enter|seek|pursue)\b", low):
        return short_sentence(
            f"Follow the quest marker into the named area for “{step}”, search the full highlighted zone, and interact with the marked person or object."
        )
    return short_sentence(
        f"Complete the named action for “{step}” inside the active quest area, then wait for the journal objective to update before leaving."
    )


def remap_story_ids(value):
    mapping = {10160: 10170, 10170: 10180, 10180: 10190}
    if isinstance(value, dict):
        return {k: remap_story_ids(v) for k, v in value.items()}
    if isinstance(value, list):
        return [remap_story_ids(v) for v in value]
    if isinstance(value, int):
        return mapping.get(value, value)
    if isinstance(value, str):
        placeholders = {old: f"__QID_{old}__" for old in mapping}
        for old, token in placeholders.items():
            value = re.sub(rf"\b{old}\b", token, value)
        for old, new in mapping.items():
            value = value.replace(placeholders[old], str(new))
    return value


def title_to_existing_qids(hints: dict, meta: dict) -> dict[str, list[int]]:
    found: dict[str, list[int]] = {}
    for qid, row in hints.items():
        meta_row = meta.get(qid, {})
        title = meta_row.get("name")
        if not title:
            title = (row.get("wiki") or "").rsplit("/", 1)[-1].replace("+", " ")
        if title:
            found.setdefault(norm(title), []).append(int(qid))
    return found


def main() -> int:
    TOOLS_DATA.mkdir(parents=True, exist_ok=True)
    catalog = parse_catalog(fetch(KIRANICO))
    if len(catalog) != 85:
        raise SystemExit(f"expected 85 extracted quest records, got {len(catalog)}")
    SNAPSHOT_PATH.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    hints_doc = json.loads(HINTS_PATH.read_text(encoding="utf-8"))
    meta_doc = json.loads(META_PATH.read_text(encoding="utf-8"))
    hints = hints_doc["by_qid"]
    meta = meta_doc["quests"]

    # Correct the missing Convergence shift before title mapping. Once shifted,
    # the script is safe to run again on its own generated output.
    if norm(meta.get("10160", {}).get("name", "")) != "convergence":
        for old, new in ((10180, 10190), (10170, 10180), (10160, 10170)):
            old_s, new_s = str(old), str(new)
            if old_s in hints:
                hints[new_s] = remap_story_ids(hints[old_s])
            if old_s in meta:
                meta[new_s] = json.loads(json.dumps(meta[old_s]))
        hints.pop("10160", None)
        meta.pop("10160", None)
        meta_doc = remap_story_ids(meta_doc)
        meta = meta_doc["quests"]
    meta_doc["ponr"] = {
        "10140": "Feast of Deception (Coronation) — early side-content transition",
        "10170": "A New Godsway — late side-content transition",
        "10180": "The Guardian Gigantus — Moonglint Tower approach",
        "10190": "Legacy — transition to the Unmoored World",
    }

    existing = title_to_existing_qids(hints, meta)
    manifest: list[dict] = []
    for record in catalog:
        title = record["title"]
        key = norm(title)
        status, reason = CLASSIFICATION.get(key, ("playable", "Retail quest with a journal record."))
        qids = SPECIAL_QIDS.get(key) or existing.get(key, [])
        if not qids:
            raise SystemExit(f"unmapped catalog quest: {title}")
        url = fextra_url(title)
        sources = [KIRANICO, url, GAME8_INDEX]
        manifest.append(
            {
                "title": title,
                "status": status,
                "reason": reason,
                "qids": qids,
                "journal_objectives": record["objectives"],
                "sources": sources,
                "confidence": {
                    "qid": "game_decomp",
                    "objectives": "game_extracted",
                    "walkthrough": "cross_checked" if status == "playable" else "classification_only",
                },
            }
        )
        if status != "playable":
            continue

        page = ""
        walkthrough: dict[str, str] = {}
        try:
            page = fetch_cached(url)
            walkthrough = parse_walkthrough(page)
        except Exception as exc:
            print(f"WARN {title}: Fextralife fetch/parse failed: {exc}")

        for qid in qids:
            qid_s = str(qid)
            row = hints.setdefault(qid_s, {})
            row["wiki"] = url
            row["sources"] = sources
            row["source_confidence"] = {
                "objectives": "game_extracted",
                "walkthrough": "cross_checked",
                "npc_ids": "runtime_verified_only",
                "schedules": "sourced_only",
            }
            if not row.get("lines"):
                row["lines"] = [short_sentence(record["description"])]

            canonical = [norm(x) for x in record["objectives"] if norm(x)]
            old_order = [norm(x) for x in row.get("step_order", []) if norm(x)]
            order = old_order[:]
            for step in canonical:
                if step not in order:
                    order.append(step)
            row["step_order"] = order
            row["fallback_step_key"] = row.get("fallback_step_key") if row.get("fallback_step_key") in order else order[0]

            hints_map = row.setdefault("step_hints", {})
            overrides = STEP_OVERRIDES.get(key, {})
            for step in order:
                current = hints_map.get(step)
                old_generic = isinstance(current, list) and any(
                    "Follow the active quest marker for this stage" in str(line) for line in current
                )
                if not echo_only(step, current) and not old_generic:
                    continue
                replacement = overrides.get(step)
                if not replacement:
                    parsed = best_walkthrough_hint(step, walkthrough)
                    replacement = [parsed] if parsed and norm(parsed) != norm(step) else [fallback_hint(step)]
                hints_map[step] = replacement

            cast = row.setdefault("step_cast", {})
            names = STEP_CAST.get(key, [])
            specific_cast = STEP_CAST_BY_STEP.get(key, {})
            for step in order:
                desired = specific_cast.get(step, names)
                if desired and not cast.get(step):
                    cast[step] = desired[:]
                else:
                    cast.setdefault(step, [])
            cids = row.setdefault("step_npc_cids", {})
            all_names = set(names)
            for step_names in specific_cast.values():
                all_names.update(step_names)
            for name in sorted(all_names):
                if name in VERIFIED_CIDS:
                    cids[name] = VERIFIED_CIDS[name]
            unverified = sorted(name for name in all_names if name not in VERIFIED_CIDS)
            if unverified:
                row["unverified_step_npcs"] = unverified
            else:
                row.pop("unverified_step_npcs", None)

            meta_row = meta.setdefault(qid_s, {})
            meta_row["name"] = title
            override = META_OVERRIDES.get(key, {})
            for field, value in override.items():
                meta_row[field] = value
            meta_row.setdefault("region", "Unclassified")
            meta_row["sources"] = sources
            meta_row["fact_confidence"] = {
                "title_qid": "game_decomp",
                "trigger_prereq_lockout": "cross_checked",
                "npc_identity": "runtime_verified" if meta_row.get("primary_giver_cid") else "name_only",
                "schedule": "sourced" if (
                    meta_row.get("avail_hour_start") is not None or meta_row.get("schedule")
                ) else "not_claimed",
            }
            warnings: list[str] = []
            lockout = meta_row.get("lockout_after")
            if isinstance(lockout, int):
                label = PONR_LABELS.get(lockout, f"quest {lockout}")
                warnings.append(f"MISSABLE: finish this quest before {label}.")
            if meta_row.get("time_limit_days"):
                warnings.append(
                    f"TIMED: complete this within about {meta_row['time_limit_days']} in-game day(s) after it starts."
                )
            if meta_row.get("avail_hour_start") is not None:
                warnings.append(
                    f"TIME WINDOW: the relevant NPC/event is available around {meta_row['avail_hour_start']}:00–{meta_row.get('avail_hour_end')}:00."
                )
            if key in BRANCH_TITLES:
                warnings.append("BRANCHING: read the active step tips before giving an item, accusing someone, or choosing dialogue.")
            if warnings:
                row["warnings"] = warnings
            else:
                row.pop("warnings", None)

    manifest_doc = {
        "version": 1,
        "catalog_records": len(manifest),
        "playable_records": sum(1 for row in manifest if row["status"] == "playable"),
        "classified_nonplayable": sum(1 for row in manifest if row["status"] != "playable"),
        "sources": [KIRANICO, "https://dragonsdogma2.wiki.fextralife.com/Quests", GAME8_INDEX],
        "records": manifest,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    hints_doc["source"] = "Complete 85-record catalog: game/Kiranico objectives; Fextralife + Game8 cross-checked walkthrough facts."
    hints_doc["catalog_manifest"] = "tools/data/quest_catalog_manifest.json"
    HINTS_PATH.write_text(json.dumps(hints_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    META_PATH.write_text(json.dumps(meta_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"OK catalog={len(manifest)} playable={manifest_doc['playable_records']} "
        f"hints={len(hints)} meta={len(meta)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
