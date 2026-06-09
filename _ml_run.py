import asyncio
import json
from pathlib import Path

ROOT = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded")
AUTORUN = ROOT / "reframework" / "autorun"
ORIG = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\ORIGINAL QUEST TRACKER\autorun\quest_tracker.lua")

def read_slice(path, start_line, end_line):
    lines = path.read_text(encoding="utf-8").splitlines()
    body = "\n".join(lines[start_line - 1 : end_line])
    return body

def build_fc():
    parts = []
    for name in ("quest_tracker_map.lua", "quest_tracker.lua", "quest_tracker_plugins.lua"):
        p = AUTORUN / name
        parts.append(f"=== {name} ===\n{p.read_text(encoding='utf-8')}")
    orig = read_slice(ORIG, 796, 1332)
    parts.append(f"=== ORIGINAL quest_tracker.lua map block L796-1332 ===\n{orig}")
    return "\n\n".join(parts)

async def main():
    from mcp.client.streamable_http import streamablehttp_client
    from mcp import ClientSession

    fc = build_fc()
    bundle_path = ROOT / ".megalens_bundle.txt"
    bundle_path.write_text(fc, encoding="utf-8")
    print(f"fileContext chars: {len(fc)}")

    prompt = """Quest Tracker Reduxx v1.1.9 — map pins general-area vs POI audit.

USER TEST (log mod loaded v1.1.9 confirmed):
- POI/manual/giver pins: diamond + text label persist on zoom/pan — PASS
- Sculptor qid=20310 dest-mode general-area: yellow blob shows briefly, vanishes on zoom forever, NO quest name label
- Mercy qid=30210: pinned as manual pos (MANUAL_POS_OVERRIDES) but also journal priority quest — vanilla blob zoomed-in / diamond zoomed-out, clashes with mod point pin + label
- Log: [PIN] pinned qid=20310 dest-mode added=1; [PIN] pinned qid=30210 (manual pos); [QT][map] clear done; setupMapIcon fires on zoom

P0-1: Why do general-area dest markers (makeQuestTargetMarkerInfo) vanish on zoom while POI build_marker_at_pos markers survive? Is reinject_all only hooked on setupQuestTargetMarker not setupMapIcon?
P0-2: v1.1.9 removed pinned_pos for dest-mode to kill white flag ghost — how should dest-mode general-area quests get text labels without white point flags?
P0-3: reinject_all skips pinned_pos when pinned_data exists (L131-137) — correct for double-diamond or breaking area labels?
P0-4: MANUAL_POS_OVERRIDES for 30210 forces point pin on area quest — should area quests bypass manual pos and use dest-mode?
P1-1: Should setupMapIcon hook call reinject_all or setupQuestTargetMarker after updateMapIcon for dest pins?
P1-2: Compare REDUXX vs ORIGINAL map block in fileContext — what minimal diff fixes general-area without reinventing wipe/fingerprint stack?

Max 8 findings with file:line. P0/P1 severity. Concrete BEFORE fix direction."""

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
            out = ROOT / "_ml_result.json"
            if hasattr(result, "model_dump"):
                data = result.model_dump()
            else:
                data = {"raw": str(result)}
            out.write_text(json.dumps(data, indent=2), encoding="utf-8")
            text = ""
            for c in data.get("content", []):
                if c.get("type") == "text":
                    text += c.get("text", "")
            print(text[:8000])

asyncio.run(main())
