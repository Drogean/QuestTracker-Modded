"""Static mappings and curated facts for the complete DD2 quest catalog."""

# Game enum/decomp mapping. Multiple QIDs are retained where the game exposes
# separate journal records for one public quest title.
SPECIAL_QIDS: dict[str, list[int]] = {
    "the hand that guides": [10040],
    "one eyed interloper": [10070],
    "the arisen s shadow": [10085],
    "convergence": [10160],
    "a new godsway": [10170],
    "the guardian gigantus": [10180],
    "legacy": [10190],
    "the expeditious explorer": [20160],
    "the inveterate explorer": [20170],
    "belle of the bar": [20180],
    "crossing in shadow": [20320],
    "dreams apart": [20360],
    "halls of the first dawn": [10200],
    "when wills collide": [20380],
    "the regentkin s resolve": [20390],
    "civil unrest": [20420],
    "a scholarly pursuit": [20370],
    "wandering roots": [20450],
    "the importance of aiding ernesto": [20460],
    "shepherd of the pawns": [20470],
    "the nameless village": [10130, 20220],
}

CLASSIFICATION = {
    "the hand that guides": (
        "internal",
        "Opening sequence record folded into Gaoled Awakening; no standalone journal quest.",
    ),
    "the expeditious explorer": (
        "unused_cut",
        "Extracted Vidal quest record has no accessible retail trigger.",
    ),
    "the inveterate explorer": (
        "unused_cut",
        "Extracted Vidal continuation has no accessible retail trigger.",
    ),
    "belle of the bar": (
        "unused_cut",
        "Extracted Adelina/Walter quest lacks a functional retail trigger.",
    ),
}

META_OVERRIDES: dict[str, dict] = {
    "one eyed interloper": {
        "region": "Vermund",
        "available_after": 10050,
        "trigger": "During In Dragon's Wake, follow Gregor's party toward Vernworth; the cyclops encounter starts automatically.",
    },
    "the arisen s shadow": {
        "region": "Vermund",
        "available_after": 10080,
        "lockout_after": 10140,
        "urgent": True,
        "giver_name": "Bermudo",
        "primary_giver_cid": 663264662,
        "trigger": "After enough of Brant's early requests, catch the hooded man stalking you in Vernworth.",
    },
    "convergence": {
        "region": "Battahl",
        "available_after": 10151,
        "prereq_quests": [10151],
        "trigger": "Starts automatically after Flickering Shadows; enter Stormwind Cave from Harve and descend into the Seafloor Shrine.",
    },
    "crossing in shadow": {
        "region": "Vermund",
        "available_after": 10140,
        "lockout_after": 10190,
        "urgent": True,
        "prereq_quests": [20230, 30200],
        "giver_name": "Vera",
        "primary_giver_cid": 407577432,
        "avail_hour_start": 20,
        "avail_hour_end": 6,
        "trigger": "Complete A Place to Call Home and A Candle in the Storm, then enter your Vernworth home at night.",
    },
    "dreams apart": {
        "region": "Unmoored World",
        "available_after": 10190,
        "urgent": True,
        "trigger": "Starts on entering the Unmoored World; find Phaesus in the Forbidden Magick Research Lab.",
    },
    "halls of the first dawn": {
        "region": "Unmoored World",
        "available_after": 10190,
        "urgent": True,
        "trigger": "In the Unmoored World, speak with Rothais at the Seafloor Shrine and begin all five evacuations.",
    },
    "when wills collide": {
        "region": "Unmoored World",
        "available_after": 10200,
        "prereq_quests": [20360],
        "urgent": True,
        "trigger": "After reuniting with your pawn, follow Phaesus toward the fallen Gigantus at the Excavation Site.",
    },
    "the regentkin s resolve": {
        "region": "Unmoored World",
        "available_after": 10200,
        "prereq_quests": [10200],
        "urgent": True,
        "giver_name": "Brant",
        "primary_giver_cid": 189868107,
        "trigger": "During Halls of the First Dawn, speak to Brant and Sven to evacuate Vernworth.",
    },
    "civil unrest": {
        "region": "Unmoored World",
        "available_after": 10200,
        "prereq_quests": [10200],
        "urgent": True,
        "giver_name": "Menella",
        "primary_giver_cid": 4137867127,
        "trigger": "During Halls of the First Dawn, meet Menella at Bakbattahl's palace entrance.",
    },
    "a scholarly pursuit": {
        "region": "Unmoored World",
        "available_after": 20360,
        "prereq_quests": [20360],
        "urgent": True,
        "trigger": "After Dreams Apart, interact with Bakbattahl's red beacon and follow Phaesus.",
    },
    "wandering roots": {
        "region": "Unmoored World",
        "available_after": 10200,
        "prereq_quests": [10200],
        "urgent": True,
        "giver_name": "Doireann",
        "primary_giver_cid": 1007143618,
        "trigger": "During Halls of the First Dawn, speak with Taliesin and Doireann in Sacred Arbor.",
    },
    "the importance of aiding ernesto": {
        "region": "Unmoored World",
        "available_after": 10200,
        "prereq_quests": [10200],
        "urgent": True,
        "giver_name": "Ernesto",
        "primary_giver_cid": 3059207198,
        "trigger": "During Halls of the First Dawn, speak with Ernesto at the Volcanic Island Camp entrance.",
    },
    "shepherd of the pawns": {
        "region": "Unmoored World",
        "available_after": 10200,
        "prereq_quests": [10200],
        "urgent": True,
        "giver_name": "Henrique",
        "primary_giver_cid": 3530434734,
        "trigger": "During Halls of the First Dawn, help Henrique clear the Excavation Site and lead the pawns out.",
    },
}

STEP_CAST: dict[str, list[str]] = {
    "one eyed interloper": ["Gregor"],
    "a beggar s tale": ["Albert", "Celina", "Hilda"],
    "the arisen s shadow": ["Bermudo", "Brant"],
    "convergence": ["Rivage Elder", "Rothais"],
    "crossing in shadow": ["Vera", "Nadinia"],
    "dreams apart": ["Phaesus"],
    "halls of the first dawn": ["Rothais"],
    "when wills collide": ["Phaesus"],
    "the regentkin s resolve": ["Brant", "Sven", "Disa"],
    "civil unrest": ["Menella", "Nadinia"],
    "a scholarly pursuit": ["Phaesus"],
    "wandering roots": ["Doireann", "Taliesin"],
    "the importance of aiding ernesto": ["Ernesto", "Gautstafr", "Cliodhna"],
    "shepherd of the pawns": ["Henrique"],
}

STEP_CAST_BY_STEP: dict[str, dict[str, list[str]]] = {
    "nation of the lambent flame": {"make for the rockmouse s burrow": ["Menella"]},
    "medicament predicament": {"deliver the fruit roborant": ["Flora"]},
    "a noble exchange": {
        "exchange gifts": ["Gunther"],
        "clear yourself of suspicion": ["Gunther"],
    },
    "a game of wits": {
        "the riddle of eyes": ["Sphinx"],
        "the riddle of madness": ["Sphinx"],
        "the riddle of wisdom": ["Sphinx"],
        "the riddle of conviction": ["Sphinx"],
        "the riddle of rumination": ["Sphinx"],
        "answer the sphinx s riddles": ["Sphinx"],
    },
    "vocation frustration": {
        "obtain an archistaff and greatsword": ["Roderick"],
        "you were advised to speak with the local armorer": ["Roderick"],
        "bring the weapons you have acquired to the guild and present them to the guildhead": ["Klaus"],
        "take the archistaff and greatsword to the guild": ["Klaus"],
        "obtain a greatsword": ["Roderick"],
        "obtain an archistaff": ["Roderick"],
    },
    "shadowed prayers": {
        "go to flamebearer palace in the morning": ["Menella", "Nadinia"],
        "identify the assassin": ["Menella", "Nadinia", "Herman"],
        "apprehend the assassin": ["Menella", "Nadinia", "Herman"],
    },
    "welcome to battahl": {
        "enter the wanderer s haven": ["Roger"],
        "defeat the ruffians": ["Roger", "Raghnall", "Taleef"],
        "conditional participate in the duel": ["Raghnall", "Taleef"],
        "participate in the duel": ["Raghnall", "Taleef"],
    },
    "mercy among thieves": {
        "inquire about the bandit gang": ["Lyssandro"],
        "visit the site of the oxcart raid": ["Lyssandro", "Hugo"],
        "locate the coral snakes hideout": ["Hugo"],
        "pursue the bandit": ["Hugo", "Benjamin"],
        "storm the coral snakes hideout": ["Hugo", "Benjamin", "Lanzo"],
    },
}

VERIFIED_CIDS = {
    "Gregor": 1584718463,
    "Albert": 2696546033,
    "Celina": 3282344307,
    "Hilda": 2408633150,
    "Bermudo": 663264662,
    "Brant": 189868107,
    "Rivage Elder": 2190167323,
    "Rothais": 1977045206,
    "Vera": 407577432,
    "Nadinia": 1872023094,
    "Phaesus": 2365554741,
    "Sven": 1210835050,
    "Disa": 1483341763,
    "Menella": 4137867127,
    "Doireann": 1007143618,
    "Taliesin": 3597605784,
    "Ernesto": 3059207198,
    "Gautstafr": 1468499554,
    "Cliodhna": 2544621420,
    "Henrique": 3530434734,
    "Flora": 3287815186,
    "Gunther": 3689427708,
    "Klaus": 3335726897,
    "Roderick": 1460554004,
    "Roger": 1327866194,
    "Raghnall": 1874680072,
    "Taleef": 2891172534,
    "Lyssandro": 2097686220,
    "Hugo": 665009116,
    "Benjamin": 1766073404,
    "Lanzo": 1282542142,
    "Herman": 2088314313,
}

STEP_OVERRIDES: dict[str, dict[str, list[str]]] = {
    "nation of the lambent flame": {
        "journey to battahl": ["Use Brant's border permit at Checkpoint Rest Town, or enter Battahl by an alternate route. Continue south to Bakbattahl."],
        "make for the rockmouse s burrow": ["Enter Bakbattahl and follow the main road to the Rockmouse's Burrow tavern. Speak with Menella after the Pathfinder encounter."],
    },
    "medicament predicament": {
        "deliver the fruit roborant": ["Buy or craft a Fruit Roborant, keep it on the Arisen, and give it to Flora outside Runne's Apothecary in Melve."],
    },
    "a game of wits": {
        "the riddle of eyes": ["Enter the nearby doorway, take the Sealing Phial from the chest above the entrance, and present it to the Sphinx."],
        "the riddle of madness": ["Carry your main pawn or highest-affinity beloved onto the pedestal, then tell the Sphinx this is your beloved."],
        "the riddle of wisdom": ["Hire an official Capcom pawn named SphinxParent, SphinxFather, or SphinxMother, place them on the pedestal, and answer."],
        "the riddle of conviction": ["Give the Sphinx any item; she returns a duplicate in the reward chest, so choose an item worth duplicating."],
        "the riddle of rumination": ["Return to the location of your first Seeker's Token and collect the Finder's Token within seven in-game days."],
        "answer the sphinx s riddles": ["You get one attempt per riddle. Solve five at Mountain Shrine, then continue at Frontier Shrine; save before each answer."],
    },
    "vocation frustration": {
        "obtain an archistaff and greatsword": ["Speak with Roderick, then search Trevo Mine west of Vernworth. Loot the greatsword and archistaff from separate chests."],
        "you were advised to speak with the local armorer": ["Cross Vernworth's market square from the Vocation Guild and speak with Roderick at Roderick's Smithy."],
        "bring the weapons you have acquired to the guild and present them to the guildhead": ["Keep both weapons on the Arisen and give them to Klaus at the Vernworth Vocation Guild to unlock Warrior and Sorcerer."],
        "take the archistaff and greatsword to the guild": ["Return both Trevo Mine weapons to Klaus at the Vernworth Vocation Guild; speak twice if both vocation unlocks do not appear."],
        "obtain a greatsword": ["Loot the two-handed sword from its chest inside Trevo Mine; do not sell or store it before reporting to Klaus."],
        "obtain an archistaff": ["Loot the archistaff from the separate chest inside Trevo Mine; do not sell or store it before reporting to Klaus."],
    },
    "shadowed prayers": {
        "go to flamebearer palace in the morning": ["Rest until the next morning, then meet Menella inside Flamebearer Palace before the prayer ritual begins."],
        "identify the assassin": ["Find Herman among the worshippers: loose tied-back hair, a scarred right arm, gray clothing, and a sword at his left hip."],
        "apprehend the assassin": ["Grab Herman immediately during the ritual. Grabbing an innocent worshipper or waiting too long fails the quest."],
    },
    "welcome to battahl": {
        "enter the wanderer s haven": ["Walk past The Wanderer's Haven in Bakbattahl's Mercantile Ward; Roger approaches and starts the confrontation automatically."],
        "defeat the ruffians": ["Fight Roger's three ruffians until Raghnall intervenes. Survive in the narrow lane; the fight then becomes one-on-one."],
        "conditional participate in the duel": ["Duel Taleef alone after Raghnall intervenes. Dodge his slow greatsword swings and punish from behind."],
        "participate in the duel": ["Defeat Taleef for the best reward. Losing still completes the quest, but costs 3,000 G and forfeits the Fruit Wine."],
    },
    "mercy among thieves": {
        "inquire about the bandit gang": ["On the Battahl side of Checkpoint Rest Town, speak with the oxcart men and then Lyssandro in white robes by the ox pens."],
        "visit the site of the oxcart raid": ["Follow the main road south from Checkpoint Rest Town and question travelers until the raided oxcart is marked."],
        "locate the coral snakes hideout": ["At the raided oxcart, follow Hugo and the fleeing Coral Snakes southwest into the canyon tunnel."],
        "pursue the bandit": ["Keep Hugo in sight through the tunnels. When the first rope bridge breaks, use the farther bridge or climb through the middle route."],
        "storm the coral snakes hideout": ["Fight through the hideout with Benjamin's guards and reach the final chamber; Lanzo escapes and Hugo is arrested."],
    },
    "crossing in shadow": {
        "escort nadinia without exposing her identity": ["Follow Vera and Nadinia through Vernworth before dawn. At the medicine dispute, pay Philbert 1,000 G; later refuse to aid the fleeing thief."],
    },
    "dreams apart": {
        "find your pawn": ["Enter Bakbattahl's Forbidden Magick Research Lab and go to Phaesus's room above Ambrosius. Exhaust Phaesus's dialogue to recover your pawn."],
    },
    "halls of the first dawn": {
        "visit the seafloor shrine": ["Go to the Seafloor Shrine and speak with Rothais at the blue beacon to unlock the evacuation effort and restored portcrystals."],
        "lead the evacuation effort": ["Complete the five settlement evacuations: Vernworth, Bakbattahl, Sacred Arbor, Volcanic Island Camp, and the Excavation Site."],
    },
    "when wills collide": {
        "follow phaesus": ["Meet Phaesus near the Excavation Site and follow him to the fallen Gigantus. This resolves through the Gigantus/Talos sequence."],
    },
    "the regentkin s resolve": {
        "aid in the evacuation of vermund": ["Speak with Brant, then Sven. Resolve Disa and secure the oxcarts; report back to Sven to evacuate Vernworth."],
    },
    "civil unrest": {
        "aid in the evacuation of battahl": ["Help Menella settle all three Bakbattahl disputes, then report to her. If Nadinia survived Shadowed Prayers, speak with her to finish the evacuation."],
    },
    "a scholarly pursuit": {
        "investigate the red beacon": ["Interact with Bakbattahl's red beacon, stay close to Phaesus, and destroy the weak points on the pursuing serpent."],
    },
    "wandering roots": {
        "aid in the evacuation of the sacred arbor": ["Speak with Taliesin and Doireann. Bring arborheart cutting evidence from the Seafloor Shrine if Taliesin refuses to leave."],
    },
    "the importance of aiding ernesto": {
        "aid in the evacuation of the volcanic island camp": ["Help Ernesto evacuate the camp, escort Gautstafr and Cliodhna, then return to Ernesto before resting advances the fog."],
    },
    "shepherd of the pawns": {
        "aid in the evacuation of the excavation site": ["Defeat the golem threatening the Excavation Site, speak with Henrique, and lead the pawns to safety."],
    },
    "convergence": {
        "explore the seafloor shrine": ["Enter Stormwind Cave from Harve, follow the newly opened passage into the Seafloor Shrine, and speak with Rothais on the throne."],
    },
    "one eyed interloper": {
        "defeat the cyclops": ["Fight the cyclops blocking Gregor's road party. Attack its legs to topple it, then finish it while it is down."],
        "proceed to vernworth": ["After the cyclops falls, continue with Gregor or use the oxcart to reach Vernworth and receive the missive for Brant."],
    },
}

BRANCH_TITLES = {
    "a beggar s tale",
    "a candle in the storm",
    "a game of wits",
    "a noble exchange",
    "a poisonous proposal",
    "every rose has its thorn",
    "hunt for the jadeite orb",
    "off the pilfered path",
    "saint of the slums",
    "short sighted ambition",
    "the arisen s shadow",
    "the sorcerer s appraisal",
    "welcome to battahl",
}

PONR_LABELS = {
    10140: "Feast of Deception",
    10170: "A New Godsway",
    10180: "The Guardian Gigantus",
    10190: "Legacy",
}
