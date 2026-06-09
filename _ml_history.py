import asyncio
import json
from pathlib import Path

async def main():
    from mcp.client.streamable_http import streamablehttp_client
    from mcp import ClientSession

    url = "https://megalens.ai/api/mcp"
    headers = {"Authorization": "Bearer ml_tok_4309695cd373acf363b5977618d4a1cc"}

    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool("megalens_history", {"limit": 20})
            if hasattr(result, "model_dump"):
                data = result.model_dump()
            else:
                data = {"raw": str(result)}
            out = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\_ml_history.json")
            out.write_text(json.dumps(data, indent=2), encoding="utf-8")
            text = ""
            for c in data.get("content", []):
                if c.get("type") == "text":
                    text += c.get("text", "")
            print(text)

asyncio.run(main())
