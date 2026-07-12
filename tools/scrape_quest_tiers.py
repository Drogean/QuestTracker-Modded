#!/usr/bin/env python3
"""Scrape Game8 + Steam fan-favorite thread → quest_tracker_quest_tiers.json qids."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
META = ROOT / "reframework" / "data" / "quest_tracker_meta.json"
OUT = ROOT / "reframework" / "data" / "quest_tracker_quest_tiers.json"
CACHE = ROOT / "tools" / "tier_cache"

GAME8 = "https://game8.co/games/Dragons-Dogma-2/archives/448509"
STEAM = "https://steamcommunity.com/app/2054970/discussions/0/4352240180488225008/"

STORY_QIDS = [
    10030, 10050, 10060, 10080, 10090, 10100, 10110, 10120, 10130,
    10140, 10150, 10160, 10170, 10180,
]

# Game8 "best side quests" name → qid (manual map; scraper validates names exist in meta)
GAME8_SPECIAL = {
    "Vocation Frustration": 20240,
    "Claw Them Into Shape": 30020,
    "Beren's Final Lesson": 30030,
    "The Sorcerer's Appraisal": 30160,
    "Spellbound": 30150,
    "Readvent of Calamity": 30100,
    "Trouble on the Cape": 20082,
    "Home Is Where the Hearth Is": 30110,
    "Every Rose Has Its Thorn": 30050,
    "Gift of the Bow": 30060,
    "A Trial of Archery": 30070,
    "The Ailing Arborheart": 30080,
    "Out of the Forest, Into the Forge": 30090,
    "A Game of Wits": 20200,
    "Dulled Steel, Cold Forge": 30120,
    "Steeled Resolve, Blazing Forge": 20340,
    "Put a Spring in Thy Step": 30170,
    "The Sotted Sage": 20270,
}

STEAM_FAN_QIDS = [20200, 20080, 30100, 20082, 30110, 20140, 20150]

STEAM_FAN = {
    "sphinx": 20200,
    "game of wits": 20200,
    "ulrika": 30100,
    "melve": 20080,
    "liberating melve": 20080,
    "readvent": 30100,
    "trouble on the cape": 20082,
    "home is where": 30110,
    "daphne": 20140,
    "gift of giving": 20140,
    "house of the blue sunbright": 20150,
}


def fetch(url: str) -> str:
    CACHE.mkdir(parents=True, exist_ok=True)
    key = re.sub(r"[^\w]+", "_", url)[:80]
    path = CACHE / f"{key}.html"
    if not path.exists():
        req = Request(url, headers={"User-Agent": "QuestTracker-TierScraper/1.0"})
        path.write_bytes(urlopen(req, timeout=30).read())
    return path.read_text(encoding="utf-8", errors="replace")


def name_to_qid(meta: dict) -> dict[str, int]:
    out = {}
    for k, v in (meta.get("quests") or {}).items():
        nm = (v.get("name") or "").strip().lower()
        if nm:
            out[nm] = int(k)
    return out


def main() -> int:
    meta = json.loads(META.read_text(encoding="utf-8"))
    by_name = name_to_qid(meta)
    game8_html = fetch(GAME8)
    steam_html = fetch(STEAM)

    by_qid: dict[str, str] = {str(q): "story" for q in STORY_QIDS}

    for name, qid in GAME8_SPECIAL.items():
        if str(qid) not in by_qid or by_qid[str(qid)] == "story":
            by_qid[str(qid)] = "special"
        if name.lower() not in game8_html.lower():
            print(f"warn: Game8 page missing quest name {name!r}", file=sys.stderr)

    fan_qids: list[int] = []
    steam_low = steam_html.lower()
    for needle, qid in STEAM_FAN.items():
        if needle in steam_low:
            fan_qids.append(qid)
    for qid in STEAM_FAN_QIDS:
    fan_qids = sorted(set(fan_qids))

    for qid in fan_qids:
        if str(qid) not in by_qid:
            by_qid[str(qid)] = "normal"

    payload = {
        "version": 2,
        "sources": [GAME8, STEAM],
        "tier_colors_abgr": {
            "story": 0xFF66FF66,
            "special": 0xFF00D7FF,
            "fan_favorite": 0xFF44AAFF,
            "normal": 0xFFFFFFFF,
        },
        "fan_qids": fan_qids,
        "by_qid": by_qid,
        "scrape_notes": {
            "game8_bytes": len(game8_html),
            "steam_bytes": len(steam_html),
            "special_count": sum(1 for t in by_qid.values() if t == "special"),
            "fan_count": len(fan_qids),
        },
    }
    OUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT} tiers={len(by_qid)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
