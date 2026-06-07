from pathlib import Path
root = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun")
main = (root / "quest_tracker.lua").read_text(encoding="utf-8", errors="replace")
lines = main.splitlines()

def extract(start, end):
    return "\n".join(lines[start - 1:end])

header = """-- quest_tracker_window.lua — quest window UI + row draw (Lua 200-local headroom)
local M = {}

function M.install(ctx)
"""

footer = """
end

package.loaded["quest_tracker_window"] = M
return M
"""

unpack = """    local mod = ctx.mod
    local MOD_NAME = ctx.MOD_NAME
    local MOD_VERSION = ctx.MOD_VERSION
    local _QT_FRAME_GEN = ctx._QT_FRAME_GEN
    local TAB_NAMES = ctx.TAB_NAMES
    local SORT_NAMES = ctx.SORT_NAMES
    local MAP_API = ctx.MAP_API
    local Map = ctx.Map
    local VOIDED_QUESTS = ctx.VOIDED_QUESTS
    local LOCKED_QUESTS = ctx.LOCKED_QUESTS
    local MANUAL_POS_OVERRIDES = ctx.MANUAL_POS_OVERRIDES
    local BUNDLED_POS_OVERRIDES = ctx.BUNDLED_POS_OVERRIDES
    local COL_NPC_ORANGE = ctx.COL_NPC_ORANGE
    local DEFAULT_QUEST_WIN_W = ctx.DEFAULT_QUEST_WIN_W
    local MIN_SAVE_WIN_W = ctx.MIN_SAVE_WIN_W
    local MIN_SAVE_WIN_H = ctx.MIN_SAVE_WIN_H
    local mlog = ctx.mlog
    local mlog_boot = ctx.mlog_boot
    local save_prefs = ctx.save_prefs
    local mark_prefs_dirty = ctx.mark_prefs_dirty
    local rebuild = ctx.rebuild
    local pin_all_in_current_filtered_tab = ctx.pin_all_in_current_filtered_tab
    local clear_injected_markers = ctx.clear_injected_markers
    local pin_quest = ctx.pin_quest
    local unpin_quest = ctx.unpin_quest
    local get_player_universal_pos = ctx.get_player_universal_pos
    local _teleport_player_to = ctx._teleport_player_to
    local _draw_npc_rows_cached = ctx._draw_npc_rows_cached
    local _name_for_qid = ctx._name_for_qid
    local milestone_label = ctx.milestone_label
    local _format_hour_12 = ctx._format_hour_12
    local _start_fast_forward = ctx._start_fast_forward
    local _set_time_scale = ctx._set_time_scale
    local _qt_doze = ctx._qt_doze
    local _apply_saved_window_once = ctx._apply_saved_window_once
    local _clear_saved_window_position = ctx._clear_saved_window_position
    local clamp_font_size = ctx.clamp_font_size
    local safe_get_field = ctx.safe_get_field
    local to_int = ctx.to_int
    local _qt_force_refresh = ctx._qt_force_refresh
    local _qt_run_logic_tick = ctx._qt_run_logic_tick
    local qt_background_log_tick = ctx.qt_background_log_tick
    local is_bundled_pos = ctx.is_bundled_pos

"""

sections = [(356, 509), (665, 717), (2246, 2955)]
body_parts = []
for start, end in sections:
    chunk = extract(start, end)
    indented = "\n".join(("    " + ln if ln.strip() else ln) for ln in chunk.splitlines())
    body_parts.append(indented)

out = header + unpack + "\n\n".join(body_parts) + footer
(root / "quest_tracker_window.lua").write_text(out, encoding="utf-8")
print("wrote", len(out.splitlines()), "lines")
