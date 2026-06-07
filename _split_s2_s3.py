# One-shot Builder #2: extract S2/S3 modules from quest_tracker.lua / quest_tracker_steps.lua
from pathlib import Path

ROOT = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun")
MAIN = ROOT / "quest_tracker.lua"
STEPS = ROOT / "quest_tracker_steps.lua"


def slines(path):
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def slice_lines(lines, start, end):
    return lines[start - 1 : end]


def guard_header(name, desc):
    return f"""-- {name} — {desc}
local M = package.loaded["{name}"]
if M then return M end
M = {{}}

function M.install(ctx)
"""


def guard_footer():
    return """
end

return M
"""


def write_sdk(src):
    body = []
    body.extend(slice_lines(src, 522, 613))  # td .. cid_norm
    body.extend(slice_lines(src, 617, 628))  # dump_quest_id_enum
    body.extend(slice_lines(src, 632, 692))  # english lookup
    body.extend(slice_lines(src, 1753, 1764))  # _read_text_field
    assigns = """
  ctx.td = td
  ctx.safe_get_field = safe_get_field
  ctx.safe_call = safe_call
  ctx.call_method = call_method
  ctx.iter_list = iter_list
  ctx.iter_array = iter_array
  ctx.to_int = to_int
  ctx.cid_eq = cid_eq
  ctx.cid_norm = cid_norm
  ctx.dump_quest_id_enum = dump_quest_id_enum
  ctx.init_english_lookup = init_english_lookup
  ctx._guid_to_en_text = _guid_to_en_text
  ctx._text_from_hex32 = _text_from_hex32
  ctx._read_text_field = _read_text_field
"""
    out = guard_header("quest_tracker_sdk", "SDK helpers (td, safe_call, guid text)")
    out += "  local mod = ctx.mod\n  local mlog = ctx.mlog\n  local mlog_boot = ctx.mlog_boot\n\n"
    out += "\n".join("  " + ln if ln.strip() else ln for ln in body)
    out += assigns
    out += guard_footer()
    (ROOT / "quest_tracker_sdk.lua").write_text(out, encoding="utf-8")
    print("sdk", len(out.splitlines()))


def write_prefs(src):
    body = []
    body.extend(slice_lines(src, 185, 381))  # PREFS through load_prefs end (skip load_prefs call line 384)
    body.extend(slice_lines(src, 367, 381))  # _display_size already in range
    # save_prefs, mark_prefs_dirty from 303-365
    # Re-include save_prefs block - it's inside 303-365 in first chunk? 303-365 is part of 210-301 load only
    body2 = slice_lines(src, 303, 365)  # save_prefs + mark_prefs_dirty
    body3 = slice_lines(src, 452, 514)  # window helpers + sort migration
    out = guard_header("quest_tracker_prefs", "prefs load/save, window layout, PREF_KEYS")
    out += """  local mod = ctx.mod
  local mlog = ctx.mlog
  local mlog_boot = ctx.mlog_boot
  local PREF_KEYS = ctx.PREF_KEYS
  local PREFS_PATH = ctx.PREFS_PATH
  local DEFAULT_QUEST_WIN_X = ctx.DEFAULT_QUEST_WIN_X
  local DEFAULT_QUEST_WIN_Y = ctx.DEFAULT_QUEST_WIN_Y
  local DEFAULT_QUEST_WIN_W = ctx.DEFAULT_QUEST_WIN_W
  local DEFAULT_QUEST_WIN_H = ctx.DEFAULT_QUEST_WIN_H
  local SORT_NAMES = ctx.SORT_NAMES
  local MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
  local MANUAL_POS_OVERRIDES = ctx.MANUAL_POS_OVERRIDES
  local ELIMINATED_OVERRIDES = ctx.ELIMINATED_OVERRIDES
  local VOIDED_QUESTS = ctx.VOIDED_QUESTS
  local LOCKED_QUESTS = ctx.LOCKED_QUESTS
  local QUEST_START_DAYS = ctx.QUEST_START_DAYS
  local QUEST_START_HOURS = ctx.QUEST_START_HOURS
  local LEARNED_CHARA_NAMES = ctx.LEARNED_CHARA_NAMES
  local is_bundled_giver = ctx.is_bundled_giver
  local is_bundled_pos = ctx.is_bundled_pos

"""
    # Dedupe: use 194-301 load_prefs, 303-365 save, 367-381 display, 452-514 window
    chunks = slice_lines(src, 194, 301) + slice_lines(src, 303, 381) + slice_lines(src, 452, 514)
    out += "\n".join("  " + ln if ln.strip() else ln for ln in chunks)
    out += """
  function ctx.load_prefs_early()
"""
    out += "\n".join("    " + ln if ln.strip() else ln for ln in slice_lines(src, 210, 301))
    out += """
  end

  function ctx.apply_prefs_to_mod()
    for _, k in ipairs(PREF_KEYS) do
      local tmp = _G["_qt_pref_" .. k]
      if tmp ~= nil then mod[k] = tmp; _G["_qt_pref_" .. k] = nil end
    end
    mod.show_window = (mod.show_window ~= false)
    if type(mod.win_alpha) ~= "number" then mod.win_alpha = 0.4 end
    mod.win_alpha = math.max(0.0, math.min(1.0, mod.win_alpha))
    mlog("[QT] prefs show_window=" .. tostring(mod.show_window))
    if mod.debug_logging then mlog("[QT] verbose debug ON") end
    if type(mod.sort_mode) == "number" then
      local s = math.floor(mod.sort_mode)
      if s < 1 then s = 1 end
      if s > #SORT_NAMES then s = #SORT_NAMES end
      if not _qt_sort_v2_migrated and s == 2 then s = 3 end
      if s > #SORT_NAMES then s = #SORT_NAMES end
      mod.sort_mode = s
    end
    _qt_sort_v2_migrated = true
    do
      local fs = (type(mod.font_size) == "number") and mod.font_size or 28
      mod.font_size = math.max(18, math.min(38, math.floor(fs + 0.5)))
    end
  end

  ctx.save_prefs = save_prefs
  ctx.mark_prefs_dirty = mark_prefs_dirty
  ctx._display_size = _display_size
  ctx._saved_window_pos_valid = _saved_window_pos_valid
  ctx._clear_saved_window_position = _clear_saved_window_position
  ctx._apply_saved_window_once = _apply_saved_window_once
"""
    out += guard_footer()
    (ROOT / "quest_tracker_prefs.lua").write_text(out, encoding="utf-8")
    print("prefs", len(out.splitlines()))


def write_gather(src):
    ranges = [
        (694, 705),   # resolve_meta
        (730, 827),   # qd_* wrappers + PONR
        (829, 1570),  # chara through _build_npc_rows_for_cache
        (1593, 1938), # gather + rebuild block (skip autolock 1572-1591)
    ]
    body = []
    for a, b in ranges:
        body.extend(slice_lines(src, a, b))
    out = guard_header("quest_tracker_gather", "gather/rebuild, NPC, time, meta resolve")
    out += """  local mod = ctx.mod
  local mlog = ctx.mlog
  local mlog_boot = ctx.mlog_boot
  local QD = ctx.QD
  local td = ctx.td
  local safe_get_field = ctx.safe_get_field
  local safe_call = ctx.safe_call
  local iter_list = ctx.iter_list
  local iter_array = ctx.iter_array
  local to_int = ctx.to_int
  local cid_eq = ctx.cid_eq
  local _guid_to_en_text = ctx._guid_to_en_text
  local mark_prefs_dirty = ctx.mark_prefs_dirty
  local TAB_NAMES = ctx.TAB_NAMES
  local FEAST_MILESTONE = ctx.FEAST_MILESTONE
  local PONR_NAMES = ctx.PONR_NAMES
  local BUNDLED_LOCKOUTS = ctx.BUNDLED_LOCKOUTS
  local BUNDLED_POS_OVERRIDES = ctx.BUNDLED_POS_OVERRIDES
  local MANUAL_POS_OVERRIDES = ctx.MANUAL_POS_OVERRIDES
  local MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
  local VOIDED_QUESTS = ctx.VOIDED_QUESTS
  local LOCKED_QUESTS = ctx.LOCKED_QUESTS
  local QUEST_START_DAYS = ctx.QUEST_START_DAYS
  local QUEST_START_HOURS = ctx.QUEST_START_HOURS
  local LEARNED_CHARA_NAMES = ctx.LEARNED_CHARA_NAMES
  local MAP_API = ctx.MAP_API
  local MapBridge = ctx.MapBridge
  local COL_NPC_GOOD = ctx.COL_NPC_GOOD
  local COL_NPC_ORANGE = ctx.COL_NPC_ORANGE
  local NPC_SCAN_CACHE_TTL = ctx.NPC_SCAN_CACHE_TTL
  local ALL_IDS = ctx.ALL_IDS

"""
    out += "\n".join("  " + ln if ln.strip() else ln for ln in body)
    out += """
  ctx.ALL_IDS = ALL_IDS
  ctx.resolve_meta = resolve_meta
  ctx.qd_givers = qd_givers
  ctx.qd_prereqs = qd_prereqs
  ctx.qd_note = qd_note
  ctx.qd_time_limit = qd_time_limit
  ctx.qd_available_after = qd_available_after
  ctx.qd_during_quest = qd_during_quest
  ctx.qd_trigger = qd_trigger
  ctx.qd_schedule = qd_schedule
  ctx.qd_timing_note = qd_timing_note
  ctx.qd_givers_display_order = qd_givers_display_order
  ctx.get_character_world_pos = get_character_world_pos
  ctx.get_player_universal_pos = get_player_universal_pos
  ctx._get_manual_player = _get_manual_player
  ctx.matches_filter = matches_filter
  ctx.pin_all_in_current_filtered_tab = pin_all_in_current_filtered_tab
  ctx.get_all_giver_cids = get_all_giver_cids
  ctx.get_primary_secondary_cids = get_primary_secondary_cids
  ctx._get_quest_start_pos = _get_quest_start_pos
  ctx.friendly_chara_name = friendly_chara_name
  ctx._resolve_cid_name = _resolve_cid_name
  ctx._build_npc_rows_for_cache = _build_npc_rows_for_cache
  ctx._draw_npc_rows_cached = _draw_npc_rows_cached
  ctx._hours_until_window_start = _hours_until_window_start
  ctx._get_game_clock_integers = _get_game_clock_integers
  ctx._get_game_hour_sched = _get_game_hour_sched
  ctx._format_game_time_line = _format_game_time_line
  ctx._format_hour_12 = _format_hour_12
  ctx._flush_pos_cache = _flush_pos_cache
  ctx._start_fast_forward = _start_fast_forward
  ctx._tick_fast_forward = _tick_fast_forward
  ctx._set_time_scale = _set_time_scale
  ctx.gather = gather
  ctx.rebuild = rebuild
  ctx.classify = classify
  ctx.milestone_label = milestone_label
  ctx._name_for_qid = _name_for_qid
  ctx.is_must_before_feast = is_must_before_feast
  ctx.dump_quest_id_enum = ctx.dump_quest_id_enum
"""
    out += guard_footer()
    (ROOT / "quest_tracker_gather.lua").write_text(out, encoding="utf-8")
    print("gather", len(out.splitlines()))


def write_steps_resolve(steps):
    ranges = [(808, 1107)]
    body = []
    for a, b in ranges:
        body.extend(slice_lines(steps, a, b))
    out = guard_header("quest_tracker_steps_resolve", "resolve_ongoing_step chain + wiki progress")
    out += """  local mod = ctx.mod
  local mlog = ctx.mlog
  local QD = ctx.QD
  local safe_get_field = ctx.safe_get_field
  local safe_call = ctx.safe_call
  local iter_list = ctx.iter_list
  local get_quest_resource = ctx.get_quest_resource
  local _guid_to_en_text = ctx._guid_to_en_text
  local resolve_meta = ctx.resolve_meta
  local _text_from_hex32 = ctx._text_from_hex32
  local to_int = ctx.to_int
  local _is_flavor_text = ctx._is_flavor_text
  local _is_weak_step = ctx._is_weak_step
  local _pick_step = ctx._pick_step
  local _log_info_entry = ctx._log_info_entry
  local _info_task_index = ctx._info_task_index
  local _text_from_dest = ctx._text_from_dest
  local _iter_managed_list = ctx._iter_managed_list
  local _task_tree_sources = ctx._task_tree_sources
  local _count_cleared_and_last_open = ctx._count_cleared_and_last_open
  local _step_from_vi_task = ctx._step_from_vi_task
  local _log_objective_from_vi = ctx._log_objective_from_vi
  local _journal_step_from_sources = ctx._journal_step_from_sources
  local _step_from_active_dests = ctx._step_from_active_dests
  local _step_from_decomp_by_index = ctx._step_from_decomp_by_index
  local _step_from_decomp_dests = ctx._step_from_decomp_dests
  local _step_from_all_tasks_scavenge = ctx._step_from_all_tasks_scavenge
  local _step_from_log_info_dict = ctx._step_from_log_info_dict
  local _task_from_questlog_vi = ctx._task_from_questlog_vi
  local _task_lists_from_vi = ctx._task_lists_from_vi
  local _walk_task_list = ctx._walk_task_list
  local _walk_journal_current = ctx._walk_journal_current
  local _task_title_and_detail = ctx._task_title_and_detail
  local _scavenge_object_text = ctx._scavenge_object_text
  local _completed_task_count = ctx._completed_task_count
  local _resolve_info_dest_step = ctx._resolve_info_dest_step
  local _probe_step_api = ctx._probe_step_api

"""
    out += "\n".join("  " + ln if ln.strip() else ln for ln in body)
    out += """
  ctx._quest_progress_done_count = _quest_progress_done_count
  ctx._get_live_quest_step = _get_live_quest_step
  ctx._text_blobs_for_step_match = _text_blobs_for_step_match
  ctx._resolve_ongoing_step = _resolve_ongoing_step
"""
    out += guard_footer()
    (ROOT / "quest_tracker_steps_resolve.lua").write_text(out, encoding="utf-8")
    print("steps_resolve", len(out.splitlines()))


if __name__ == "__main__":
    main = slines(MAIN)
    steps = slines(STEPS)
    write_sdk(main)
    write_prefs(main)
    write_gather(main)
    write_steps_resolve(steps)
    print("done")
