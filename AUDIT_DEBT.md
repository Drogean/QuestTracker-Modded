# Audit debt — running log (append every audit fuckup)

Format: `date | failure | impact | next-audit fix | status`

## OPEN

| Date | Audit failure | Impact | Next-audit fix | Status |
|------|---------------|--------|----------------|--------|
| 2026-06-07 | Half-ass 3.0.88 handoff — skipped corners, thin BUILDER HANDOFF | Coordinator shipped broken layout/sniff fixes without full log proof | Full thermo-nuclear pass + L## per P0 before handoff | OPEN |
| 2026-06-07 | PASS/summary without insisting on `quest_tracker_log.txt` when re2 is the only surviving log | Coordinator thought QT log proved session; file truncated | State which log file was read; if QT log empty say **audit blocked — QT log truncated** | OPEN |
| 2026-06-07 | 3.0.93 handoff — no static grep for Lua forward-ref before ship | Missed `_QT_TAB_BTN_PAD` L198 vs L321; red ImGui box in-game | Grep `window.lua` + `prefs.lua` for locals used before `local` declaration **before** every handoff | OPEN |

## CLOSED (last 3)

| Date | Audit failure | Closed when |
|------|---------------|-------------|
| 2026-06-07 | First audit after 3.0.90 — user yelled, demanded full re-audit | Coordinator got log-proof handoff with disk prefs + coordinator test steps |
