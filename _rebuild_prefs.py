from pathlib import Path

bak = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun\quest_tracker.lua.bak")
lines = bak.read_text(encoding="utf-8", errors="replace").splitlines()
body = lines[193:513]

header = """-- quest_tracker_prefs.lua — prefs load/save, window layout, PREF_KEYS
local M = package.loaded["quest_tracker_prefs"]
if M then return M end
M = {}

function M.install(ctx)
  local mod = ctx.mod
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

footer = """
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

  function ctx.load_prefs_early()
    load_prefs()
  end

  ctx.save_prefs = save_prefs
  ctx.mark_prefs_dirty = mark_prefs_dirty
  ctx._display_size = _display_size
  ctx._saved_window_pos_valid = _saved_window_pos_valid
  ctx._clear_saved_window_position = _clear_saved_window_position
  ctx._apply_saved_window_once = _apply_saved_window_once
end

return M
"""

indented = "\n".join("  " + ln if ln.strip() else ln for ln in body)
out = header + indented + footer
Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun\quest_tracker_prefs.lua").write_text(out, encoding="utf-8")
print("prefs lines", len(out.splitlines()))
