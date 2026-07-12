#!/usr/bin/env python3
"""Scrape Fextralife quest pages into quest_tracker_wiki_hints.json (v2)."""
from __future__ import annotations

import argparse
import json
import re
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
META_PATH = ROOT / "reframework" / "data" / "quest_tracker_meta.json"
HINTS_PATH = ROOT / "reframework" / "data" / "quest_tracker_wiki_hints.json"
CACHE_DIR = Path(__file__).resolve().parent / "wiki_cache"
REPORT_PATH = Path(__file__).resolve().parent / "scrape_report.txt"
QUESTS_INDEX = "https://dragonsdogma2.wiki.fextralife.com/Quests"
RATE_SEC = 1.0
UA = "QuestTrackerScraper/1.4.25 (+local mod tool)"
MAX_HINT = 200
MAX_BULLETS = 4


def norm_key(s: str) -> str:
    s = re.sub(r"&nbsp;?", " ", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9' ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def fetch(url: str) -> str:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^a-zA-Z0-9]+", "_", url)[:120]
    cache = CACHE_DIR / f"{safe}.html"
    if cache.exists() and cache.stat().st_size > 500:
        return cache.read_text(encoding="utf-8", errors="replace")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    html = urllib.request.urlopen(req, timeout=45).read().decode("utf-8", errors="replace")
    cache.write_text(html, encoding="utf-8")
    time.sleep(RATE_SEC)
    return html


def strip_html(s: str) -> str:
    s = re.sub(r"&nbsp;?", " ", s, flags=re.I)
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def parse_objectives(html: str) -> list[str]:
    for pat in (
        r"Quest Objectives.*?<ul>(.*?)</ul>",
        r"Objectives.*?<ul>(.*?)</ul>",
    ):
        m = re.search(pat, html, re.I | re.S)
        if m:
            items = re.findall(r"<li[^>]*>(.*?)</li>", m.group(1), re.S)
            out = [strip_html(x) for x in items if strip_html(x)]
            if out:
                return out
    return []


def parse_walkthrough(html: str) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    parts = re.split(r"<h4[^>]*>", html, flags=re.I)
    for chunk in parts[1:]:
        title_m = re.match(r".*?<span[^>]*>([^<]+)</span>", chunk, re.S)
        if not title_m:
            continue
        title = strip_html(title_m.group(1))
        key = norm_key(title)
        if not key:
            continue
        body = chunk.split("</h4>", 1)[-1]
        body = re.split(r"<h[234]", body, 1, flags=re.I)[0]
        bullets: list[str] = []
        for li in re.findall(r"<li[^>]*>(.*?)</li>", body, re.S):
            t = strip_html(li)
            if t and 8 < len(t) <= MAX_HINT:
                bullets.append(t)
        if bullets:
            out[key] = bullets[:MAX_BULLETS]
    return out


def wiki_url_for(row: dict, qname: str) -> str | None:
    if isinstance(row.get("wiki"), str) and row["wiki"].startswith("http"):
        return row["wiki"]
    slug = re.sub(r"[^A-Za-z0-9]+", "+", qname.strip())
    return f"https://dragonsdogma2.wiki.fextralife.com/{slug}"


def preserve_hints(old: dict | None, new: dict) -> dict:
    if not old:
        return new
    out = dict(old)
    for k, v in new.items():
        if k not in out:
            out[k] = v
            continue
        if isinstance(v, list) and isinstance(out.get(k), list):
            old_short = all(isinstance(x, str) and len(x) <= MAX_HINT for x in out[k])
            new_short = all(isinstance(x, str) and len(x) <= MAX_HINT for x in v)
            if old_short and not new_short:
                continue
        out[k] = v
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preserve-curated", action="store_true", default=True)
    ap.add_argument("--qid", type=str, default="", help="scrape single qid only")
    args = ap.parse_args()

    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    hints = json.loads(HINTS_PATH.read_text(encoding="utf-8"))
    by_qid = hints.setdefault("by_qid", {})
    quests = meta.get("quests", {})
    warnings: list[str] = []

    targets = quests.items()
    if args.qid:
        targets = [(args.qid, quests[args.qid])]

    updated = 0
    for qid, mq in sorted(targets, key=lambda x: int(x[0])):
        qname = mq.get("name", f"Quest {qid}")
        row = by_qid.setdefault(str(qid), {})
        old_hints = row.get("step_hints")
        url = wiki_url_for(row, qname)
        if not url:
            continue
        row["wiki"] = url
        try:
            html = fetch(url)
        except Exception as e:
            warnings.append(f"FAIL {qid} {qname}: {e}")
            continue

        objectives = parse_objectives(html)
        walk = parse_walkthrough(html)

        if objectives:
            row["step_order"] = [norm_key(o) for o in objectives]
            row.setdefault("step_hints", {})
            for obj in objectives:
                k = norm_key(obj)
                scraped = walk.get(k)
                if scraped:
                    if args.preserve_curated:
                        row["step_hints"][k] = preserve_hints(
                            {k: row["step_hints"].get(k)} if k in row["step_hints"] else None,
                            {k: scraped},
                        ).get(k, scraped)
                    else:
                        row["step_hints"][k] = scraped
                elif k not in row["step_hints"]:
                    row["step_hints"][k] = [obj[:MAX_HINT]]
            if objectives:
                row["fallback_step_key"] = row["step_order"][0]

        if not row.get("lines"):
            row["lines"] = objectives[:3] if objectives else [f"See Fextralife: {qname}"]

        by_qid[str(qid)] = row
        updated += 1
        print(f"OK {qid} {qname}: steps={len(row.get('step_order', []))} hints={len(row.get('step_hints', {}))}")

    hints["by_qid"] = by_qid
    HINTS_PATH.write_text(json.dumps(hints, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    cast_n = sum(1 for r in by_qid.values() if isinstance(r.get("step_cast"), dict) and r["step_cast"])
    report = f"updated={updated}/{len(quests)} step_cast={cast_n} warnings={len(warnings)}\n"
    if warnings:
        report += "\n".join(warnings[:20]) + "\n"
    REPORT_PATH.write_text(report, encoding="utf-8")
    print(report.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
