from pathlib import Path
p = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun\quest_tracker.lua")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
# 1-based inclusive ranges to DELETE
drop = set()
for start, end in [(2033, 2045), (2077, 2635)]:
    for i in range(start, end + 1):
        drop.add(i)
new_lines = [ln for i, ln in enumerate(lines, 1) if i not in drop]
# insert window install after plugin exports (find line with qt_background_log_tick =)
insert_at = None
for i, ln in enumerate(new_lines):
    if "local qt_background_log_tick = _qt_plugin_out" in ln:
        insert_at = i + 1
        break
window_install = [
    "",
    "-- =========== QUEST WINDOW UI (quest_tracker_window.lua — Lua 200-local limit) ===========",
    "require(\"quest_tracker_window\").install({",
    "    mod = mod, MOD_NAME = MOD_NAME, MOD_VERSION = MOD_VERSION, _QT_FRAME_GEN = _QT_FRAME_GEN,",
    "    TAB_NAMES = TAB_NAMES, SORT_NAMES = SORT_NAMES, MAP_API = MAP_API, Map = Map,",
    "    VOIDED_QUESTS = VOIDED_QUESTS, LOCKED_QUESTS = LOCKED_QUESTS,",
    "    MANUAL_POS_OVERRIDES = MANUAL_POS_OVERRIDES, BUNDLED_POS_OVERRIDES = BUNDLED_POS_OVERRIDES,",
    "    COL_NPC_ORANGE = COL_NPC_ORANGE, DEFAULT_QUEST_WIN_W = DEFAULT_QUEST_WIN_W,",
    "    MIN_SAVE_WIN_W = MIN_SAVE_WIN_W, MIN_SAVE_WIN_H = MIN_SAVE_WIN_H,",
    "    mlog = mlog, mlog_boot = mlog_boot, save_prefs = save_prefs, mark_prefs_dirty = mark_prefs_dirty,",
    "    rebuild = rebuild, pin_all_in_current_filtered_tab = pin_all_in_current_filtered_tab,",
    "    clear_injected_markers = clear_injected_markers, pin_quest = pin_quest, unpin_quest = unpin_quest,",
    "    get_player_universal_pos = get_player_universal_pos, _teleport_player_to = _teleport_player_to,",
    "    _draw_npc_rows_cached = _draw_npc_rows_cached, _name_for_qid = _name_for_qid,",
    "    milestone_label = milestone_label, _format_hour_12 = _format_hour_12,",
    "    _start_fast_forward = _start_fast_forward, _set_time_scale = _set_time_scale,",
    "    _tick_fast_forward = _tick_fast_forward, _apply_saved_window_once = _apply_saved_window_once,",
    "    _clear_saved_window_position = _clear_saved_window_position,",
    "    safe_get_field = safe_get_field, to_int = to_int, is_bundled_pos = is_bundled_pos,",
    "    _qt_force_refresh = _qt_force_refresh, _qt_run_logic_tick = _qt_run_logic_tick,",
    "    qt_background_log_tick = qt_background_log_tick,",
    "})",
]
if insert_at:
    new_lines = new_lines[:insert_at] + window_install + new_lines[insert_at:]
p.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
print("lines", len(lines), "->", len(new_lines))
