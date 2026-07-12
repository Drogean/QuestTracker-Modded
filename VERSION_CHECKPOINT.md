# VERSION CHECKPOINT v1.4.8

Sniff/prefs/live-dest cluster only (no map-pin refactor this ship).

- deep_sniff OFF default + prefs migrate v12 forces OFF on old saves
- Live dest hooks always at boot (updateQuestMarker, onQuestContextUpdate, setCurrentDestination)
- onUpdateQuestDestination blacklisted (TU 3.1 crash)
- Deep sniff METHOD_PAT scan only when user toggles ON; skip add_/remove_; hook FAIL once
- Map exports try_upgrade_fallback_pins for sniff callback

NOT TESTED — user boot + log proof required before READY-FOR-TEST.
