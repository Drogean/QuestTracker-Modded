import asyncio
import json
from pathlib import Path

async def main():
    from mcp.client.streamable_http import streamablehttp_client
    from mcp import ClientSession

    fc = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\.megalens_bundle.txt").read_text(encoding="utf-8")
    prompt = """DD2 Quest Tracker Reduxx v1.1.8 map audit vs ORIGINAL QUEST TRACKER (working).

USER FAIL TAKE 5 (log mod loaded v1.1.8):
- Pin all ongoing: white banners appear first; diamonds+yellow areas only after pan map
- Sculptor qid=20310: general-area quest — no yellow diamond when zoomed in; zoom out shows quest area then white flag disappears permanently; other quests keep diamonds but LOSE text labels until repin
- Zoom out: all labels vanish; repin restores text until next zoom
- User: mod puts banners first then diamonds on top — reinventing wheel vs Original

LOG PROOF v1.1.8 session:
- clear done wiped=0 labels=0 mapicon_after=302 (wipe finds ZERO type-25 but mapicon count 302!)
- Pin Ongoing: paint labels=10 wiped=0 markers=10 mapicon_after=312
- wipe t25 always 0 — ghost banners persist

BUILDER v1.1.8 claims: _wipe_mod_type25_icons, fingerprint skip zoom, reinject skip double dest, dest pin no list:Add

Compare REDUXX vs ORIGINAL in fileContext. Max 8 findings file:line P0/P1.
ROOT QUESTION: Should Reduxx DELETE custom wipe/reinject/paint stack and port Original map block (~878-1322) verbatim into quest_tracker_map.lua with only split-file wiring?

Concrete fixes for: wipe t25=0 always, label loss on zoom, sculptor general-area, banner-before-diamond UX."""

    url = "https://megalens.ai/api/mcp"
    headers = {"Authorization": "Bearer ml_tok_4309695cd373acf363b5977618d4a1cc"}

    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "megalens_debate",
                {
                    "prompt": prompt,
                    "fileContext": fc,
                    "tier": "standard",
                    "mode": "multi",
                    "skill": "code_intelligence",
                },
            )
            out = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\_ml_result.json")
            if hasattr(result, "model_dump"):
                data = result.model_dump()
            else:
                data = {"raw": str(result)}
            out.write_text(json.dumps(data, indent=2), encoding="utf-8")
            text = ""
            for c in data.get("content", []):
                if c.get("type") == "text":
                    text += c.get("text", "")
            print(text[:12000])

asyncio.run(main())
