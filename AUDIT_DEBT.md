# Audit debt — running log (append every audit fuckup)

Format: `date | failure | impact | next-audit fix | status`

## Consecutive FAILs (MegaLens gate)

| Feature area | Streak | Last versions | Next action |
|--------------|--------|---------------|-------------|
| map pins / labels / instant refresh | **4** | v1.1.4–v1.1.7 FAIL (ghost banners after clear) | v1.1.8: wipe type-25 on clear + dedup inject + updateQuestPointIcon |

Reset streak when: user PASS on map pins, or new unrelated feature audit.

## OPEN

| Date | Audit failure | Impact | Next-audit fix | Status |
|------|---------------|--------|----------------|--------|
| 2026-06-07 | Half-ass 3.0.88 handoff — skipped corners, thin BUILDER HANDOFF | Coordinator shipped broken layout/sniff fixes without full log proof | Full thermo-nuclear pass + L## per P0 before handoff | OPEN |
| 2026-06-07 | PASS/summary without insisting on `quest_tracker_log.txt` when re2 is the only surviving log | Coordinator thought QT log proved session; file truncated | State which log file was read; if QT log empty say **audit blocked — QT log truncated** | OPEN |
| 2026-06-07 | 3.0.93 handoff — no static grep for Lua forward-ref before ship | Missed `_QT_TAB_BTN_PAD` L198 vs L321; red ImGui box in-game | Grep `window.lua` + `prefs.lua` for locals used before `local` declaration **before** every handoff | OPEN |
| 2026-06-09 | Thin BUILDER HANDOFF tables — Builder blind to coordinator chat | v1.1.4–1.1.6 map fixes kept missing paint pipeline | Always use `builder-handoff-full-spec.mdc` FULL block on FAIL | OPEN |

## CLOSED (last 3)

| Date | Audit failure | Closed when |
|------|---------------|-------------|
| 2026-06-07 | First audit after 3.0.90 — user yelled, demanded full re-audit | Coordinator got log-proof handoff with disk prefs + coordinator test steps |
