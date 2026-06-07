# Builder debt — Quest Tracker Reduxx

One line per fuckup. Auditor appends on FAIL. Builder marks FIXED only with log proof.

| Version | Date | Symptom | Log proof | Root cause | Status |
|---------|------|---------|-----------|------------|--------|
| 3.0.91 | 2026-06-07 | Window tiny top-left, only time line | L20 restore OK, no wrap/draw logs; screenshot | prefs.lua set_next scalars; window.lua title font before begin | OPEN → 3.0.92 partial |
| 3.0.92 | 2026-06-07 | Right position, blank tabs/quests | L18 draw=15, no [QT][wrap]; screenshot Tools only | window.lua ok_list never paints; no child scroll | OPEN → 3.0.93 |
| 3.0.93 | 2026-06-07 | Red ImGui EndChild, no tabs/quests | re2 list draw CRASH :198 `_QT_TAB_BTN_PAD` nil; dlist=15 | window.lua:198 uses pad declared :321; end_child skipped on crash | FIXED in 3.0.94 |
| 3.0.94 | 2026-06-07 | PASS core — layout, list, expands, save | L25-32 L39-58 L65 shutdown; no CRASH | — | PASS (playable) |
| 3.0.94 | 2026-06-07 | "More detail" body purple unreadable | screenshot Spellbound qid=30150 | window.lua:517 `0xFFAABBFF` on c.note | FIXED in 3.0.95 |
| 3.0.94 | 2026-06-07 | wrap width telemetry wrong | L32 row_w=-1 tab=-1 | tab capture in child window | FIXED in 3.0.95 |
| 3.0.95 | 2026-06-07 | Tools click does nothing | window.lua:815-816 set_next_item_open(false,1) every frame | window.lua:815-817 FirstUseEver once | FIXED in 3.0.96 (L3 L41 expand Tools screenshot) |
| 3.0.95 | 2026-06-07 | Main quest ~45-60s late | L16 Completed=0; L44 +17s Completed=41 | boot completion sweep gather.lua | FIXED in 3.0.96 (L16-19 10151 first draw) |
| 3.0.96 | 2026-06-07 | PASS — playable sign-off | L3 v3.0.96 L16-19 L27-32 L41 expand 10151; screenshot Tools+quests | — | PASS (coordinator 06:05) |
| 3.0.96 | 2026-06-07 | Expanded text slightly past tab row | screenshot; L34 row_w=-1 | child wrap width telemetry | OPEN P2 cosmetic only |
| 3.0.96 | 2026-06-07 | Luz/Dragonforged TP click no-op | user report; no [QT][tp] in log | direct UniversalPosition write | FIXED in 3.0.97 ferrystone |
| 3.0.96 | 2026-06-07 | Minimize → red ImGui EndChild/End errors | screenshot Dear ImGui box | child draw when collapsed + double begin_child | OPEN → 3.0.98 |
| 3.0.96 | 2026-06-07 | Collapsed title bar text tiny | screenshot | font pushed only inside expanded content | FIXED in 3.0.98 |
| 3.0.96 | 2026-06-07 | Map yellow diamonds no quest name | screenshot chimera; map_pin_quests=5 L2799 | vanilla QuestTargetMarkerList unlabeled | FIXED in 3.0.102 label+filter |
| 3.0.96 | 2026-06-07 | Map clutter many diamonds one spot | screenshot red circle; map_pin_quests=5 | vanilla all-ongoing markers + mod pins | FIXED in 3.0.102 filter non-MAIN |

## Rules

- Do not ship without grep `list draw CRASH` = 0 on boot
- Move locals above first use (same class as 3.0.88 prefs forward-ref)
- Always `end_child_window` in finally path after `begin_child_window`
