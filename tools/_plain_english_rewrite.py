#!/usr/bin/env python3
"""Rewrite all quest step_hints into plain English (no journal echo, no arrow chains)."""
from __future__ import annotations

import json
import re
from pathlib import Path

from _guidance_catalog_data import STEP_OVERRIDES
from _rebuild_complete_guidance import (
    HINTS_PATH,
    META_PATH,
    best_walkthrough_hint,
    cache_path,
    fetch_cached,
    fextra_url,
    norm,
    short_sentence,
    strip_html,
)

MAX_LINES = 6
MAX_LINE = 160

BAD_MARKERS = (
    "Complete the named action",
    "Keep the required item or news",
    "Rest at an inn, house, or bench until at least the next day, then return for",
    "Follow the active quest marker for this stage",
    "Journal may say",
    "→",
    "ONLY THEN",
    "DO THIS NOW",
    "STOP.",
)


def title_key(meta_row: dict, row: dict) -> str:
    title = meta_row.get("name") or ""
    if not title:
        title = (row.get("wiki") or "").rsplit("/", 1)[-1].replace("+", " ")
    return norm(title)


def is_bad_line(line: str) -> bool:
    s = str(line).strip()
    if not s:
        return True
    if any(m in s for m in BAD_MARKERS):
        return True
    if re.search(r'for [“"].+[”"]', s):
        return True
    if re.match(r"^\d+[\)\.]\s*$", s):
        return True
    return False


def is_bad_block(lines: list) -> bool:
    if not lines:
        return True
    bad = sum(1 for x in lines if is_bad_line(x))
    return bad >= max(1, len(lines) // 2)


def scrub_line(line: str) -> str:
    s = str(line).strip()
    s = re.sub(r"^\d+[\)\.]\s*", "", s)
    s = s.replace("→", ". Then ")
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"(\d+)G\b", r"\1 gold", s)
    s = re.sub(r"\bG\b(?=\s|$)", "gold", s)
    if len(s) > MAX_LINE:
        s = short_sentence(s)
    return s


def plain_fallback(step: str) -> list[str]:
    low = norm(step)
    if re.search(r"\b(wait|revisit|return in a few days|check on|visit .* in a few days)\b", low):
        return [
            "Leave the area and sleep until the next morning (inn, house, or bench).",
            "Come back and talk to the same person again until the journal updates.",
        ]
    if re.search(r"\b(deliver|give|bring|turn over|report back|inform)\b", low):
        return [
            "Carry the item on your character — not in storage and not on a pawn.",
            "Return to the person who asked for it and pick the hand-in dialogue option.",
        ]
    if re.search(r"\b(procure|obtain|gather|acquire|find some|find a bunch|collect)\b", low):
        return [
            "Buy, craft, or loot what the journal asks for before you travel back.",
            "Keep everything on the Arisen until you turn it in.",
        ]
    if re.search(r"\b(escort|accompany|lead|follow)\b", low):
        return [
            "Stay close to the NPC on the road. Clear enemies ahead of them.",
            "If they die, you may need a Wakestone or to restart from a recent save.",
        ]
    if re.search(r"\b(defeat|fend|rid|cull|deal with|kill)\b", low):
        return [
            "Go to the marked fight area and kill every enemy the quest cares about.",
            "Stay nearby after the last kill until the journal objective changes.",
        ]
    if re.search(r"\b(speak|talk|consult|inquire|ask|meet)\b", low):
        return [
            "Find the named NPC and talk until they repeat themselves or go quiet.",
            "Missing? Try sleeping to the next day or the time window the quest mentions.",
        ]
    if re.search(r"\b(search|investigate|explore|traverse|enter|seek|pursue|go to|make for)\b", low):
        return [
            "Follow the map marker into the area and search the whole highlighted zone.",
            "Click every person and object that looks important before you leave.",
        ]
    return [
        "Do what the journal title describes in the marked area.",
        "If nothing happens, sleep once and return before you assume it is broken.",
    ]


def split_walkthrough(text: str) -> list[str]:
    text = short_sentence(text)
    parts = re.split(r"(?<=[.!?])\s+", text)
    out: list[str] = []
    for part in parts:
        part = scrub_line(part)
        if len(part) < 12:
            continue
        out.append(part)
        if len(out) >= MAX_LINES:
            break
    return out or [scrub_line(text)]


def rewrite_step(step: str, title: str, walkthrough: dict[str, str], old: list | None) -> list[str]:
    key = norm(title)
    override = STEP_OVERRIDES.get(key, {}).get(step)
    if override:
        return [scrub_line(x) for x in override[:MAX_LINES]]

    parsed = best_walkthrough_hint(step, walkthrough)
    if parsed and len(parsed) >= 20:
        lines = split_walkthrough(parsed)
        if lines and not is_bad_block(lines):
            return lines

    if old and not is_bad_block(old):
        cleaned = [scrub_line(x) for x in old if str(x).strip()]
        cleaned = [x for x in cleaned if x and not is_bad_line(x)]
        if cleaned:
            return cleaned[:MAX_LINES]

    return plain_fallback(step)[:MAX_LINES]


def main() -> int:
    hints_doc = json.loads(HINTS_PATH.read_text(encoding="utf-8"))
    meta_doc = json.loads(META_PATH.read_text(encoding="utf-8"))
    hints = hints_doc["by_qid"]
    meta = meta_doc["quests"]

    walk_cache: dict[str, dict[str, str]] = {}
    rewritten = 0
    for qid, row in hints.items():
        meta_row = meta.get(qid, {})
        title = meta_row.get("name") or qid
        key = title_key(meta_row, row)
        url = row.get("wiki") or fextra_url(title)
        if key not in walk_cache:
            wt: dict[str, str] = {}
            try:
                if cache_path(url).exists():
                    body = cache_path(url).read_text(encoding="utf-8", errors="replace")
                else:
                    body = fetch_cached(url)
                from _rebuild_complete_guidance import parse_walkthrough

                wt = parse_walkthrough(body)
            except Exception:
                wt = {}
            walk_cache[key] = wt

        order = row.get("step_order") or []
        if not order:
            continue
        old_map = row.get("step_hints") or {}
        new_map: dict[str, list[str]] = {}
        for step in order:
            new_map[step] = rewrite_step(step, title, walk_cache[key], old_map.get(step))
        row["step_hints"] = new_map
        rewritten += 1

    HINTS_PATH.write_text(json.dumps(hints_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"OK rewrote step_hints for {rewritten} quests -> {HINTS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
