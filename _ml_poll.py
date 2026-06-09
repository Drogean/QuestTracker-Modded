import asyncio
import json
import sys
from pathlib import Path

async def main():
    from mcp.client.streamable_http import streamablehttp_client
    from mcp import ClientSession

    run_id = sys.argv[1] if len(sys.argv) > 1 else "1e2d4612-e6c1-4105-82a9-cf85a2e732d0"
    url = "https://megalens.ai/api/mcp"
    headers = {"Authorization": "Bearer ml_tok_4309695cd373acf363b5977618d4a1cc"}

    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool("megalens_poll", {"run_id": run_id})
            if hasattr(result, "model_dump"):
                data = result.model_dump()
            else:
                data = {"raw": str(result)}
            out = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\_ml_poll_result.json")
            out.write_text(json.dumps(data, indent=2), encoding="utf-8")
            text = ""
            for c in data.get("content", []):
                if c.get("type") == "text":
                    text += c.get("text", "")
            print(text[:20000])

asyncio.run(main())
