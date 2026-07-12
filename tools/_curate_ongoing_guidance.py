# -*- coding: utf-8 -*-
"""Curate step_cast / step_npc_cids / actionable hints for the 12 current Ongoing quests."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HINTS = ROOT / "reframework/data/quest_tracker_wiki_hints.json"
BACKUP = ROOT / "_BACKUP_TOUCHES/2026-07-12_0655_guidance_recovery/reframework/data/quest_tracker_wiki_hints.json"

# Confirmed CharaIDs from prefs / decomp / overrides (explore report).
CIDS = {
    "Hugo": 665009116,
    "Ernesto": 3059207198,
    "Barbas": 3756687913,
    "Everard": 3027823138,
    "Offulve": 3680129867,
    "Gallad": 2950601180,
    "Disa": 1483341763,
    "Doireann": 1007143618,
    "Glyndwr": 3560980369,
    "Sara": 1363233817,  # prefs; 1892817290 is Messara — do not use
    "Brokkr": 2439785051,
    "Jarle": 2151757684,
    "Myrdin": 1603137626,
    "Trysha": 678396953,
    "Isaac": 1545619405,
    "Diana": 3743885470,
    "Sebastian": 4124055264,
    "Daphne": 1488552131,
    "Cliodhna": 2544621420,
    "Gautstafr": 1468499554,
    "Pathfinder": 504636546,
    "Ambrosius": 3463222861,
    "Luz": 2411836891,
    "The Dragonforged": 561828483,
    "Dragonforged": 561828483,
    "Rivage Elder": 2190167323,
    "Roman": 1424070675,
    "Roderick": 1460554004,
    "Lamond": 3252066890,
}


def merge_cids(row: dict, names: list[str]) -> None:
    cids = dict(row.get("step_npc_cids") or {})
    for n in names:
        if n in CIDS:
            cids[n] = CIDS[n]
    # Drop known-wrong Sara CID if present
    if cids.get("Sara") == 1892817290:
        cids["Sara"] = CIDS["Sara"]
    row["step_npc_cids"] = cids


def set_hint(row: dict, key: str, lines: list[str]) -> None:
    sh = dict(row.get("step_hints") or {})
    sh[key] = lines
    row["step_hints"] = sh


def apply(by: dict) -> list[str]:
    notes: list[str] = []

    # --- 30220 Off the Pilfered Path ---
    r = by["30220"]
    r["step_cast"] = {
        "speak with hugo": ["Hugo"],
        "investigate the theft on the highroad": [],
        "follow the suspect": [],
        "report back to hugo": ["Hugo"],
    }
    merge_cids(r, ["Hugo"])
    set_hint(
        r,
        "speak with hugo",
        [
            "Find Hugo on the Battahl highroad (after Mercy Among Thieves chain).",
            "Accept the theft investigation from him.",
        ],
    )
    set_hint(
        r,
        "report back to hugo",
        ["Return to Hugo on the highroad with what you learned about the theft."],
    )
    notes.append("30220: Hugo cast+CID")

    # --- 20060 Twixt a Rock ---
    r = by["20060"]
    r["step_cast"] = {
        "deliver the letter to ernesto": ["Ernesto"],
        "deliver the letter to barbas": ["Barbas"],
    }
    merge_cids(r, ["Ernesto", "Barbas"])
    set_hint(
        r,
        "deliver the letter to ernesto",
        [
            "Deliver the traveler's letter to Ernesto (Bakbattahl / volcanic area).",
            "Use TP when Ernesto is loaded; otherwise travel to his marked area.",
        ],
    )
    set_hint(
        r,
        "deliver the letter to barbas",
        [
            "Deliver the other letter to Barbas.",
            "Both deliveries finish the letter chain after the ravine rescue.",
        ],
    )
    notes.append("20060: Ernesto/Barbas cast+CID + letter hints")

    # --- 20350 Hunt for the Jadeite Orb ---
    r = by["20350"]
    r["step_cast"] = {
        "hunt for the jadeite orb": ["Disa"],
        "you received a second request for the jadeite orb": ["Everard", "Offulve"],
        "deliver the jadeite orb bring the jadeite orb to the individual who requested it everard offulve": [
            "Everard",
            "Offulve",
        ],
    }
    merge_cids(r, ["Disa", "Everard", "Offulve", "Gallad"])
    set_hint(
        r,
        "hunt for the jadeite orb",
        [
            "Talk to Sven's mother (Disa) in Vernworth Castle to start the hunt.",
            "Search castle side rooms and upper floors; check containers thoroughly.",
            "Do not sell the unique Jadeite Orb mid-quest.",
        ],
    )
    set_hint(
        r,
        "you received a second request for the jadeite orb",
        [
            "A second party wants the orb — Everard and Offulve both request it.",
            "Decide who you will deliver to before turning it in.",
        ],
    )
    set_hint(
        r,
        "deliver the jadeite orb bring the jadeite orb to the individual who requested it everard offulve",
        [
            "Bring the Jadeite Orb to Everard or Offulve (your choice).",
            "Ending/reward differs by who receives it — check wiki if unsure.",
        ],
    )
    notes.append("20350: Disa/Everard/Offulve cast+CID + castle hints")

    # --- 30080 Ailing Arborheart — fix cast key + Sara/Brokkr CIDs ---
    r = by["30080"]
    r["step_cast"] = {
        "find out what gwyfencha is": ["Doireann", "Glyndwr"],
        "speak with a battahli blacksmith": ["Sara", "Brokkr"],
    }
    merge_cids(r, ["Doireann", "Glyndwr", "Sara", "Brokkr"])
    notes.append("30080: cast key aligned + Sara/Brokkr CIDs")

    # --- 20280 Poisonous Proposal ---
    r = by["20280"]
    r["step_cast"] = {
        "allow yourself to be poisoned by an asp": [],
        "return to jarle afflicted with asp venom": ["Jarle"],
        "allow yourself to be poisoned by a venin harpy": [],
        "return to jarle afflicted with venin harpy venom": ["Jarle"],
        "join jarle at the meeting place": ["Jarle"],
        "aid jarle in being poisoned by the chimera": ["Jarle"],
        "find out how jarle fared": ["Jarle"],
    }
    merge_cids(r, ["Jarle"])
    set_hint(
        r,
        "allow yourself to be poisoned by an asp",
        [
            "Find an asp (snake) in Battahl wilderness and let it poison you.",
            "Do not cure the venom before returning to Jarle.",
        ],
    )
    set_hint(
        r,
        "return to jarle afflicted with asp venom",
        ["Return to Jarle while still poisoned by asp venom so he can take a sample."],
    )
    set_hint(
        r,
        "allow yourself to be poisoned by a venin harpy",
        [
            "Find a Venin Harpy and take its poison (stay afflicted).",
            "Common near cliffs / Battahl sky paths — do not cure early.",
        ],
    )
    set_hint(
        r,
        "return to jarle afflicted with venin harpy venom",
        ["Return to Jarle while still under Venin Harpy poison."],
    )
    set_hint(
        r,
        "join jarle at the meeting place",
        ["Meet Jarle at the agreed spot for the Chimera poison plan."],
    )
    set_hint(
        r,
        "aid jarle in being poisoned by the chimera",
        [
            "Help Jarle get Chimera poison — protect him during the encounter.",
            "Chimera fights are dangerous; bring curatives for yourself after.",
        ],
    )
    set_hint(
        r,
        "find out how jarle fared",
        ["Check back with Jarle after the Chimera step to finish the proposal."],
    )
    notes.append("20280: Jarle cast+CID + poison walkthrough hints")

    # --- 30160 Sorcerer's Appraisal ---
    r = by["30160"]
    r["step_cast"] = {
        "gather grimoires for myrddin": ["Myrdin"],
        "prove your friendship with trysha": ["Trysha"],
        "revisit myrddin in a few days' time": ["Myrdin"],
    }
    merge_cids(r, ["Myrdin", "Trysha"])
    set_hint(
        r,
        "prove your friendship with trysha",
        [
            "Raise friendship with Trysha (Spellbound chain) so Myrddin trusts you.",
            "Wear the Turquoise Ring from Spellbound when dealing with Myrddin.",
        ],
    )
    set_hint(
        r,
        "revisit myrddin in a few days' time",
        [
            "Rest a few in-game days, then return to Myrddin's Home.",
            "Wear Courtly Tunic + Breeches before entering.",
            "Reward includes Myrddin's Chronicle (Maelstrom) when ready.",
        ],
    )
    notes.append("30160: Myrdin/Trysha cast+CID")

    # --- 20290 Short-Sighted Ambition ---
    r = by["20290"]
    r["step_cast"] = {
        "bring isaac a ripened quince": ["Isaac"],
        "find the grimoire's second volume give isaac the original grimoire": ["Isaac"],
        "create a forgery of the grimoire": ["Isaac"],
    }
    merge_cids(r, ["Isaac"])
    set_hint(
        r,
        "bring isaac a ripened quince",
        [
            "Buy or loot a Quince, then rest ~3 days on a Bakbattahl bench to ripen it.",
            "Give the Ripened Quince to Isaac at Isaac's Wares.",
        ],
    )
    set_hint(
        r,
        "find the grimoire's second volume give isaac the original grimoire",
        [
            "Buy On the Transference of Souls 2 from Ibrahim (Checkpoint Rest Town, ~2000 G).",
            "Giving Isaac the ORIGINAL leads to a worse ending — prefer forging a fake next.",
        ],
    )
    set_hint(
        r,
        "create a forgery of the grimoire",
        [
            "Forge On the Transit of Souls 2 at Ibrahim (~2400 G).",
            "Give the FAKE to Isaac for the good ending.",
        ],
    )
    notes.append("20290: Isaac cast+CID + quince/forge hints")

    # --- 20150 House of the Blue Sunbright — align cast keys ---
    r = by["20150"]
    r["step_cast"] = {
        "visit the manor": ["Diana", "Sebastian"],
        "find sebastian's look alike": ["Daphne", "Sebastian", "Diana"],
        "escort daphne to the manor": ["Daphne", "Diana"],
        "help sebastian prepare by giving him the necessary items": ["Sebastian", "Diana"],
    }
    merge_cids(r, ["Diana", "Sebastian", "Daphne"])
    set_hint(
        r,
        "visit the manor",
        [
            "Visit the Noble Quarter manor — talk to Diana / Sebastian to begin.",
            "Requires The Gift of Giving completed first.",
        ],
    )
    set_hint(
        r,
        "find sebastian's look alike",
        [
            "Find Daphne at the slums tent by the Gracious Hand.",
            "She is Sebastian's look-alike — prepare to escort her to the manor.",
        ],
    )
    set_hint(
        r,
        "escort daphne to the manor",
        ["Escort Daphne from the slums tent to the manor safely."],
    )
    set_hint(
        r,
        "help sebastian prepare by giving him the necessary items",
        [
            "Give Sebastian: Detoxifying Decoction (or Allheal) + Waking Powder.",
            "Give something that smells like cyclops — Rugged Bone works.",
            "Wait a few in-game days, then return for the Blue Sunbright outcome.",
        ],
    )
    notes.append("20150: cast keys aligned + Diana/Sebastian/Daphne CIDs")

    # --- 30170 Put a Spring in Thy Step ---
    r = by["30170"]
    # Fix nbsp key clutter in order display by keeping existing key but also clean hint
    r["step_cast"] = {
        "find three wildflowers": ["Cliodhna"],
        "deliver the wildflowers": ["Cliodhna"],
        "visit gautstafr's home for a reward": ["Gautstafr"],
        "escort gautstafr to geyser hamlet": ["Gautstafr"],
        "report back to nbsp cliodhna": ["Cliodhna"],
        "report back to cliodhna": ["Cliodhna"],
    }
    merge_cids(r, ["Cliodhna", "Gautstafr"])
    set_hint(
        r,
        "find three wildflowers",
        [
            "Gather three wildflowers for Cliodhna (Bakbattahl dancer / festival).",
            "Some festival steps are night-only — camp until dusk if she is missing.",
        ],
    )
    set_hint(
        r,
        "deliver the wildflowers",
        ["Return the wildflowers to Cliodhna in Bakbattahl."],
    )
    set_hint(
        r,
        "visit gautstafr's home for a reward",
        ["Visit Gautstafr's home for the next reward beat of the festival chain."],
    )
    set_hint(
        r,
        "escort gautstafr to geyser hamlet",
        ["Escort Gautstafr to Geyser Hamlet — protect him on the road."],
    )
    set_hint(
        r,
        "report back to nbsp cliodhna",
        ["Report back to Cliodhna in Bakbattahl to finish the festival quest."],
    )
    notes.append("30170: Cliodhna/Gautstafr cast+CID")

    # --- 10151 Flickering Shadows — add CIDs ---
    r = by["10151"]
    merge_cids(
        r,
        ["Pathfinder", "Ambrosius", "Luz", "The Dragonforged", "Dragonforged", "Rivage Elder"],
    )
    notes.append("10151: step_npc_cids added")

    # --- 30120 Dulled Steel — Sara CID fix + Roderick cast ---
    r = by["30120"]
    cast = dict(r.get("step_cast") or {})
    cast["speak with the vernworth armorer"] = ["Roderick"]
    r["step_cast"] = cast
    merge_cids(r, ["Roman", "Brokkr", "Sara", "Roderick"])
    notes.append("30120: Sara CID fixed + Roderick cast")

    # --- 20270 Sotted Sage ---
    r = by["20270"]
    r["step_cast"] = {
        "give lamond what he seeks": ["Lamond"],
        "bring lamond more newt liqueur": ["Lamond"],
    }
    merge_cids(r, ["Lamond"])
    set_hint(
        r,
        "give lamond what he seeks",
        [
            "Find Lamond (drunken sage) in a Volcanic Island / Bakbattahl tavern.",
            "Camp until evening if he is not at the bar.",
            "Bring what he asks for (usually drink-related).",
        ],
    )
    notes.append("20270: Lamond cast+CID + tavern hint")

    return notes


def main() -> None:
    if not BACKUP.exists():
        BACKUP.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(HINTS, BACKUP)
    data = json.loads(HINTS.read_text(encoding="utf-8"))
    by = data["by_qid"]
    notes = apply(by)
    HINTS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("UPDATED", HINTS)
    for n in notes:
        print("-", n)


if __name__ == "__main__":
    main()
