# BUILDER SHIP — UI red box + overlay crash (Quest Tracker Reduxx)

**Paste this at the top of every Builder chat.**  
**Target ship:** `v1.4.12` (workspace) → user installs Fluffy zip → Auditor retests.

---

## Mission (priority order)

| P | Problem | User sees | Ship gate |
|---|---------|-----------|-----------|
| **P0** | Red Dear ImGui floating box | `Missing End()`, `Missing PopFont()`, `Missing PopStyleColor()` | **Zero red box for 60s** with Show Window ON |
| **P0** | Quest UI blank | Window shell + Tools/time only — **no tabs, no quest list** | Log must show `list draw enter dlist=N` (N > 0) |
| **P1** | Idle CTD | Game dies standing still ~3 min, overlay ON | **5+ min idle**, no `c0000005` |
| **P1** | Save CTD | Crash on save/quit with overlay | Save + quit once, no CTD |

Map pin bugs (ocean diamonds, unpin complete, etc.) are **OUT OF SCOPE** for this ship. Do not refactor map.lua unless UI gates pass first.

---

## What broke (merged: CRASH FIX audit + Grok + game logs)

### Crash session proof (v1.4.11 — user tested FAIL)

- **When:** 2026-06-14 22:35–22:38, idle standing still
- **Error:** `Exception occurred: c0000005` @ 22:38:08
- **Stack:** `igWindowRectRelToAbs` → `ImTextureData_GetTexID` (dinput8.dll / REFramework ImGui)
- **Mod:** v1.4.11, `show_window=true`, overlay 743×788 @ 2486,22 (4K)
- **Last QT log:** `[QT][poll] qid=30070` @ 22:38:06
- **Save guard:** fired + cleared OK @ 22:36:14
- **Same stack** as earlier 21:51:58 crash

**Log paths (read yourself — never ask user to paste):**

```
C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\reframework\data\quest_tracker_log.txt
C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\re2_framework_log.txt
C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\reframework_crash.dmp
```

### Why v1.4.11 UI was dead (P0 smoking gun)

v1.4.11 log shows window opened at full size but **never**:

- `[QT] list draw enter dlist=...`
- `[QT] list child window failed to open`
- `[QT] draw child begin FAIL ...`

Window shell drew; **quest list path never ran**. ImGui internal stack was already corrupt → red box → eventual CTD.

### Root causes (all must be addressed)

| # | Cause | v1.4.9–1.4.11 | v1.4.12 fix |
|---|--------|---------------|-------------|
| 1 | **ImGui overlay in `re.on_frame`** | Yes — wrong REFramework lifecycle | **Moved to `re.on_draw_ui`** |
| 2 | Lua throw mid-draw → no pop/end | Style/font/window left open | **`pcall` body + `_qt_finish_window()` always** |
| 3 | `begin_child` treated `open == true` only | Valid RF return rejected | **`if ok and open then`** (truthy) |
| 4 | Style pop **before** `end_window` (1.4.11) | Wrong ImGui order | Pop style **after** `end_window` |
| 5 | Tools tree in pcall without guaranteed `tree_pop` | Stack leak on throw | Direct draw + `_menu_finish()` on REFramework menu |
| 6 | `_qt_quest_child_open = true` when begin failed | Missing EndChild | Set flag only when begin succeeds |

**Grok verdict (REFramework / cursey book):** cleanup-only (`finally` pops) without moving to `on_draw_ui` = **band-aid**. Both are required.

**Reference mod pattern:** `OTHERMODS/enemy_nameplates/reframework/autorun/enemy_nameplates.lua` — ImGui in `re.on_draw_ui`, not `on_frame`.

---

## What is already in workspace (v1.4.12)

File: `reframework/autorun/quest_tracker_window.lua`

- [x] Game logic stays in `re.on_frame` (poll, cache tick, prefs debounce — **no imgui**)
- [x] Overlay in `re.on_draw_ui` → `_qt_draw_quest_overlay()` wrapped in outer `pcall`
- [x] `_qt_finish_window()`: child close → pop font → `end_window` → pop style
- [x] Save guard: skip draw during `execSave` (`_qt_arm_suppress_draw` / `_qt_gui_saving`)
- [x] Child defer when `win_h < 200` (frame-1 collapse guard)
- [x] REFramework settings menu: separate `on_draw_ui` with `_menu_finish()` (pop font + tree_pop)

Version sync:

- `quest_tracker.lua` → `MOD_VERSION = "1.4.12"`
- `modinfo.ini` → `version = 1.4.12`

**NOT user-tested yet.** Game log still shows v1.4.11 from last session.

---

## Pre-ship code checklist (Builder MUST verify before zip)

### A. ImGui pairing audit (`quest_tracker_window.lua`)

Walk the overlay draw path and confirm **every push has a guaranteed pop on ALL paths** (success, early return, Lua error):

| Push / Begin | Pop / End | Where cleaned |
|--------------|-----------|---------------|
| `push_style_color` (alpha bg) | `pop_style_color` × N | `_qt_pop_style_if_needed()` in `_qt_finish_window` |
| `begin_window` | `end_window` | `_qt_finish_window` if `draw` |
| `push_font` | `pop_font` | `_qt_pop_font_if_needed()` |
| `begin_child_window` | `end_child_window` | `_qt_ensure_child_closed()` |
| `tree_node("Tools")` | `tree_pop` | Same block (no inner pcall wrapping whole tree) |
| `tree_node("Active pins")` | `tree_pop` | Inner pcall OK — `tree_pop` is **outside** pcall |
| `tree_node("##qt" .. qid)` in `draw_row` | `tree_pop` | Always after body pcall when `open` |
| `push_id` in `draw_row` | `pop_id` | End of `draw_row` |

**grep sanity (must pass):**

```powershell
# Overlay must NOT call begin_window in on_frame
Select-String -Path reframework\autorun\quest_tracker_window.lua -Pattern "on_frame" -Context 0,15
# Must show on_frame block has NO imgui.begin_window

# Overlay must be in on_draw_ui
Select-String -Path reframework\autorun\quest_tracker_window.lua -Pattern "on_draw_ui|_qt_draw_quest_overlay"
```

### B. Optional hardening (add if time — recommended)

These were in CRASH FIX spec but **not yet in v1.4.12**:

1. **Skip overlay when game pause/menu open** — probe `app.GuiManager` or existing game-ready flag; if menu up, `return` before any `begin_window`. Log once: `[QT] draw skipped reason=game_menu`.

2. **Stack mismatch log** — after `_qt_finish_window()`, if REFramework exposes stack depth API, log mismatch once. If no API, log when `ok_body == false`: `[QT][draw] window body CRASH: ...` (already partially there).

3. **Sync `MAP_MOD_VER`** in `quest_tracker_map.lua` to match ship version (cosmetic log only).

If you add (1) or (2), bump to **v1.4.13** and update `modinfo.ini` description.

### C. Do NOT regress

- Do **not** wrap the whole Tools `tree_node` block in `pcall` without `_menu_finish` equivalent.
- Do **not** move overlay back to `on_frame`.
- Do **not** pop style before `end_window`.
- Do **not** set `_qt_quest_child_open = true` unless `begin_child_window` succeeded.

---

## Build & ship steps (exact order)

```powershell
cd "c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded"

# 1. Syntax + version + zip
powershell -ExecutionPolicy Bypass -File _ship_check.ps1

# 2. Confirm zip exists
# Output: ..\QuestTracker-Reduxx-v1.4.12-fluffy.zip  (or v1.4.13 if bumped)
```

**Ship check failures:**

- `luac not on PATH` → WARN only; still ship if manual read looks OK
- `version mismatch` → fix `quest_tracker.lua` + `modinfo.ini` before zip
- `locals > 180` in main → split file first (don't ship)

**After zip built, tell user:**

> Install `QuestTracker-Reduxx-v1.4.12-fluffy.zip` in **Fluffy Mod Manager** (not the repo folder).  
> **Verbose** stays ON by default. **Deep Sniff** stays OFF unless debugging hooks.

**User workaround until new build installed:**

- REFramework → Quest Tracker → uncheck **Show Window**, OR disable mod in Fluffy

---

## Auditor test script (PASS / FAIL)

User boots game with **Show Window ON**. Builder reads logs after session — do not claim fixed until user confirms.

### Boot (first 30s) — MUST PASS

| Check | PASS log line | FAIL if missing / wrong |
|-------|---------------|-------------------------|
| Correct version | `[QT] ===== mod loaded v1.4.12 =====` | Still says v1.4.11 → Fluffy stale |
| Window opens | `[QT] window draw visible=true` | — |
| Layout OK | `[QT] boot layout settled actual=743x788` (or user size) | Tiny collapsed window |
| **List paints** | `[QT] list draw enter dlist=13` (or similar N>0) | **P0 FAIL** — same as v1.4.11 |
| Cache OK | `[QT][cache] refresh OK rows=70 built=13 draw=13 fail=0` | — |
| No ImGui red box | Visual + no `Missing End` in re2 log | **P0 FAIL** |
| No Lua crash | grep `list draw CRASH` = 0, `window body CRASH` = 0 | Fix before retest |

### Idle stability (5+ min) — MUST PASS for P1

- Stand still, overlay visible, do nothing
- **PASS:** no CTD, no red box, poll lines every ~20s (`[QT][poll]`)
- **FAIL:** `Exception occurred: c0000005` + `igWindowRectRelToAbs` in re2 log

### Save test — MUST PASS for P1

- Trigger save (game save or Tools → Save button)
- Expect: `[QT] draw suppressed reason=execSave` then `draw suppress cleared reason=execSave_post`
- Save + quit with overlay ON
- **PASS:** no CTD on quit

### Visual — MUST PASS for P0

- Tab row visible: `Available(n) Ongoing(n) Completed(n) Hidden(n)`
- Quest names listed under tabs
- Expand one quest → steps/body text (not empty shell)
- Tools tree expands (not dead click)

---

## If still broken after v1.4.12

| Symptom | Next move |
|---------|-----------|
| Red box but `list draw enter` logs | Tree/pop leak in `draw_row` or Tools — add per-row `tree_pop` guard in finally |
| No `list draw enter`, no child fail log | Draw aborts before child — add boot log line before Tools tree |
| `list child window failed to open` | Child begin failing — log `open=` value; check `win_h` defer |
| CTD only on save | Extend suppress window past 2.0s; skip draw entire save sequence |
| CTD idle, clean logs | **LET'S MEGALENSE** wiring bundle only after log proves v1.4.12 installed |

**Nuclear debug (one session only):** comment out quest list loop, ship v1.4.12-debug — if red box gone, leak is in `draw_row`; if red box stays, leak is Tools/window shell.

---

## Files in scope

| File | Role |
|------|------|
| `reframework/autorun/quest_tracker_window.lua` | **Primary** — overlay draw, ImGui lifecycle |
| `reframework/autorun/quest_tracker.lua` | `MOD_VERSION`, boot log wipe |
| `modinfo.ini` | Fluffy version string |
| `quest_tracker_map.lua` | Version string sync only (optional) |

**Out of scope this ship:** map pin ocean fix, completion unpin, deep_sniff hooks, PATH B journal inject.

---

## Agent rules (non-negotiable)

From `.cursor/rules/agent-ship-gates.mdc`:

- `luac -p` on every changed `.lua` (if available)
- **Never claim fixed** without user boot test + log read
- Read `re2_framework_log.txt` from session **after** install
- Bump version when you ship
- One change at a time — UI fix before map refactor

**Debug toggles (tell user every session):**

| Toggle | Default | When |
|--------|---------|------|
| Verbose | ON | Safe; extra disk log |
| Deep Sniff | OFF | Only when assistant says turn on ultimate pussy sniffin |
| Heavy | OFF | Only with deep sniff + assistant says heavy too |

---

## Quick reference — v1.4.11 vs v1.4.12

```
v1.4.11 FAIL:
  ImGui in on_frame → stack corruption every frame
  Red box → list path never runs → CTD @ igWindowRectRelToAbs

v1.4.12 SHIP TARGET:
  on_frame = logic only
  on_draw_ui = overlay + guaranteed _qt_finish_window()
  Expect: list draw enter + tabs visible + no red box + 5min idle
```

**Builder done when:** `_ship_check.ps1` green, zip in `OTHERMODS/`, handoff to user with test script above.  
**Ship complete when:** user Auditor returns PASS on all P0 + P1 gates.
