# Version checkpoint — backtrack here

**Recorded:** 2026-06-10 (this chat — auditor started skipping Grok + builder handoffs)

## v1.3.6 — 2026-06-11

Root fix: `flush_journal_pin_pending` and `pin_all_ongoing` now call `pin_quest(qid, true)` before setting `_journal_live_qid`. Previously they only called `_mark_tracked_journal` which set the live flag but never populated `pinned_label_pos`, so inject/reinject had nothing to work with. `inject_tracked_journal_markers` now logs verbose FAIL reason (dests_nil, xyz_nil, marker_nil, add_failed) with IsWorldMap/IsDetailMap/kl/la. `add_labeled_markers_for_all_pins` logs label FAIL reason when journal_live and added=0. `reinject_all` skip_blob branch now explicitly emits a diamond from `pinned_label_pos` instead of silently skipping. `setupMapIcon` logs label FAIL summary once per map open when want>0 and labels==0.

## Pin this build

| Field | Value |
|-------|--------|
| **Source version** | `1.3.4` |
| **MOD_VERSION** | `reframework/autorun/quest_tracker.lua` L5 |
| **MAP_MOD_VER** | `reframework/autorun/quest_tracker_map.lua` L4 |
| **modinfo.ini** | `version = 1.3.3` |
| **Last Fluffy ship** | 2026-06-10 v1.3.3 |
| **Game log proof** | pending playtest |

**Backtrack to 1.3.2** if v1.3.3 breaks auto-pin or labels — git tag `v1.3.2` @ `57d2088`.

---

## What worked at 1.3.2 (keep if backtracking)

- Journal **auto-pin** on map open (deferred `on_frame` / `setupQuestTargetMarker`) — user reported OK once
- Map **labels** via `call6_false` — visible after map open
- Sculptor `20310` first pin: `anchor=live`, `LocalArea=98` (Bakbattahl workshop)
- Log: `auto-pin OK qid=20310 from=on_frame` before manual Pin Ongoing

## Known broken / not fixed at 1.3.2 (do not pretend fixed)

- **No re-pin** when `done` bumps same qid (`done=4→5` @ 02:12:40, zero repin lines)
- **Wiki step** at `done=5` shows "attend unveiling" — should be "wait for fulvio progress" (Grok + Fextralife)
- Sculptor **blob reinject** spam: `reinject=2` per map open, `world=0` lines
- `auto-pin skip already_pinned` blocks refresh after first pin
- Carry P2: 10151 live dest, 5 quests fail pin, Mercy 30210 hybrid, `row_w=-1`

---

## Version timeline (recent)

| Ver | Verdict | Note |
|-----|---------|------|
| 1.2.8 | Partial | Blob OK; labels 3/9; 10151 wrong pin |
| 1.2.9 | FAIL | `_label_slots` dedup killed labels |
| 1.3.0 | Partial | Labels after manual pin; auto-pin weak |
| 1.3.1 | FAIL auto-pin | Pin inside `setupMapIcon` too early |
| **1.3.2** | **CHECKPOINT** | Auto-pin PASS; repin/wiki still broken |
| 1.3.3 | NOT SHIPPED | Handoff only (repin + wiki_done_map) |
| 1.3.4 | Partial | flush never called pin_quest; labels=0 all session |
| 1.3.5 | FAIL labels | inject ran but pin_quest never called; pinned_label_pos empty |
| **1.3.6** | **SHIP** | flush+pin_ongoing call pin_quest; inject verbose FAIL; label FAIL logs; blob skip emits diamond |

---

## Backtrack instructions

1. Workspace source is already at **1.3.2** unless someone bumped version later.
2. Reinstall mod in **Fluffy** from this folder (or last 1.3.2 zip if saved).
3. Confirm log: `-- quest_tracker v1.3.2 started` or `mod loaded v1.3.2`.
4. **Do not** apply v1.3.3 handoff changes until builder ships and user tests.
5. If a future build makes things worse, revert files listed above to 1.3.2 and compare against this doc.

---

## This conversation marker ("went retarded")

- User flagged: Grok skipped, answers without builder handoff, auditor not doing full work.
- Fix for *process* (not code): Grok first → logs → code compare → **BUILDER HANDOFF** box every ship/question.
- **Code state unchanged** at time of this file — still 1.3.2 in repo.

---

## Key log lines (1.3.2 session 2026-06-10)

```
[PIN] pinned qid=20310 sculpt blob+diamond pin_once=1 anchor=live
[QT][map] auto-pin OK qid=20310 from=on_frame
[QT][poll] qid=20310 done=5 menu=20310
[QT][map] auto-pin skip already_pinned qid=20310
```

Test quest: **20310** Sculptor's Block, journal priority, day 62.
