import asyncio
import json
from pathlib import Path

async def main():
    from mcp.client.streamable_http import streamablehttp_client
    from mcp import ClientSession

    fc = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\.megalens_bundle.txt").read_text(encoding="utf-8")
    prompt = (
        "DD2 REFramework Quest Tracker Reduxx v1.1.6 map pin audit vs working Original mod in fileContext.\n\n"
        "USER FAIL (log mod loaded v1.1.6):\n"
        "P0-1: Pin/clear/pin-all no visual change until pan/zoom. Log force refresh map_open=true; sniff IsUpdateIcon=false after clicks.\n"
        "P0-2: Clear drops one diamond layer; ghost layer until zoom.\n"
        "P0-3: Pin-all banners/flags until zoom; labels inconsistent.\n"
        "P0-4: Sculptor qid=20310 dest-mode invisible on world map; yellow blob only on quest-map tab (vanilla).\n"
        "P0-5: v1.1.6 copied Original label inject but added setupMapIcon/clearMapAll on force refresh — still broken.\n\n"
        "Compare REDUXX vs ORIGINAL map blocks. Max 6-8 findings file:line. P0/P1. Concrete fixes for paint pipeline."
    )
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
            print(json.dumps(data)[:8000])

asyncio.run(main())
