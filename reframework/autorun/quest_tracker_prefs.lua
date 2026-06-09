-- quest_tracker_prefs.lua — prefs load/save, window layout, PREF_KEYS
local M = package.loaded["quest_tracker_prefs"]
if M then return M end
M = {}

function M.install(ctx)
  local mod = ctx.mod
  local mlog = ctx.mlog
  local mlog_boot = ctx.mlog_boot
  local PREF_KEYS = ctx.PREF_KEYS
  local PREFS_PATH = ctx.PREFS_PATH
  local BAKED_LAYOUT_PATH = ctx.BAKED_LAYOUT_PATH
  local LAST_LAYOUT_PATH = ctx.LAST_LAYOUT_PATH
  local PERMANENT_LAYOUT_PATH = ctx.PERMANENT_LAYOUT_PATH or "quest_tracker_permanent_layout.json"
  local MIN_SAVE_WIN_W = ctx.MIN_SAVE_WIN_W or 520
  local MIN_SAVE_WIN_H = ctx.MIN_SAVE_WIN_H or 280
  local DEFAULT_QUEST_WIN_Y = ctx.DEFAULT_QUEST_WIN_Y
  local DEFAULT_QUEST_WIN_W = ctx.DEFAULT_QUEST_WIN_W
  local DEFAULT_QUEST_WIN_H = ctx.DEFAULT_QUEST_WIN_H
  local DEFAULT_QUEST_WIN_MARGIN_R = ctx.DEFAULT_QUEST_WIN_MARGIN_R or 24
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

  local function _prefs_is_stub(data)
      if type(data) ~= "table" then return true end
      for k, _ in pairs(data) do
          if k ~= "prefs_version" then return false end
      end
      return true
  end

  local function _default_window_size()
      return DEFAULT_QUEST_WIN_W, DEFAULT_QUEST_WIN_H
  end

  -- Display helpers MUST be declared before any function that calls them (Lua local forward-ref).
  local _display_cache = nil

  local function _display_size_uncached()
      local dw, dh = 1920, 1080
      pcall(function()
          if imgui.get_display_size then
              local ds = imgui.get_display_size()
              if type(ds) == "table" or type(ds) == "userdata" then
                  dw = ds.x or dw
                  dh = ds.y or dh
              elseif type(ds) == "number" then
                  dw = ds
              end
          end
      end)
      return dw, dh
  end

  local function _display_size()
      if _display_cache then return _display_cache.dw, _display_cache.dh end
      local dw, dh = _display_size_uncached()
      _display_cache = { dw = dw, dh = dh }
      return dw, dh
  end

  local function _refresh_display_cache()
      local dw, dh = _display_size_uncached()
      _display_cache = { dw = dw, dh = dh }
  end

  local function _pos_in_viewport(x, y, dw, dh)
      return type(x) == "number" and type(y) == "number"
          and x >= -50 and x <= dw + 50
          and y >= -50 and y <= dh + 50
  end

  local function _clamp_layout_size(w, h)
      local dw, dh = _display_size()
      local max_w = math.max(MIN_SAVE_WIN_W, dw - 40)
      local max_h = math.max(MIN_SAVE_WIN_H, dh - 40)
      w = math.max(MIN_SAVE_WIN_W, math.min(w, max_w))
      h = math.max(MIN_SAVE_WIN_H, math.min(h, max_h))
      return w, h
  end

  local function _migrate_layout_v10(data)
      if type(data.layout_margin_r) == "number" then return end
      local dw = _display_size_uncached()
      local w = (type(data.win_w) == "number") and data.win_w or DEFAULT_QUEST_WIN_W
      local x = data.win_x
      if type(x) == "number" and x > dw + 50 then
          data.layout_margin_r = DEFAULT_QUEST_WIN_MARGIN_R
      elseif type(x) == "number" then
          local mr = dw - x - w
          data.layout_margin_r = (mr >= 0 and mr <= dw) and mr or DEFAULT_QUEST_WIN_MARGIN_R
      else
          data.layout_margin_r = DEFAULT_QUEST_WIN_MARGIN_R
      end
  end

  local function _resolve_layout_xy(margin_r, y, w, h)
      _refresh_display_cache()
      local dw, dh = _display_size()
      w, h = _clamp_layout_size(w or DEFAULT_QUEST_WIN_W, h or DEFAULT_QUEST_WIN_H)
      margin_r = (type(margin_r) == "number") and margin_r or DEFAULT_QUEST_WIN_MARGIN_R
      margin_r = math.max(0, math.min(margin_r, math.max(0, dw - w - 10)))
      y = (type(y) == "number") and y or DEFAULT_QUEST_WIN_Y
      local x = dw - w - margin_r
      return x, y, w, h, dw, dh
  end

  local function _apply_layout_coords_to_mod()
      local x, y, w, h = _resolve_layout_xy(
          mod.layout_margin_r, mod.win_y, mod.win_w, mod.win_h)
      mod.win_x, mod.win_y, mod.win_w, mod.win_h = x, y, w, h
  end

  local function _sync_margin_from_viewport()
      if type(mod.win_x) ~= "number" or type(mod.win_w) ~= "number" then return end
      _refresh_display_cache()
      local dw = _display_size()
      mod.layout_margin_r = math.max(0, dw - mod.win_x - mod.win_w)
  end

  local function _load_json_layout(path)
      local ok, data = pcall(function() return json.load_file(path) end)
      if ok and type(data) == "table" then return data end
      return nil
  end

  local function _win_layout_complete(data)
      if type(data) ~= "table" then return false end
      local has_margin = type(data.layout_margin_r) == "number"
      local has_legacy = type(data.win_x) == "number"
      return (has_margin or has_legacy) and type(data.win_y) == "number"
          and type(data.win_w) == "number" and type(data.win_h) == "number"
  end

  local function _apply_layout_table(data, source)
      _migrate_layout_v10(data)
      local mr = (type(data.layout_margin_r) == "number") and data.layout_margin_r or DEFAULT_QUEST_WIN_MARGIN_R
      local y = (type(data.win_y) == "number") and data.win_y or DEFAULT_QUEST_WIN_Y
      local w = (type(data.win_w) == "number") and data.win_w or DEFAULT_QUEST_WIN_W
      local h = (type(data.win_h) == "number") and data.win_h or DEFAULT_QUEST_WIN_H
      local fs = (type(data.font_size) == "number") and data.font_size or 28
      local x, ry, rw, rh, dw, dh = _resolve_layout_xy(mr, y, w, h)
      _G["_qt_pref_layout_margin_r"] = mr
      _G["_qt_pref_win_y"] = ry
      _G["_qt_pref_win_w"] = rw
      _G["_qt_pref_win_h"] = rh
      _G["_qt_pref_font_size"] = fs
      _G._qt_layout_source = source
      mlog_boot(string.format("[QT] restored margin_r=%.0f y=%.0f %dx%d → x=%.0f display=%dx%d (source=%s)",
          mr, ry, rw, rh, x, dw, dh, source))
      _G._qt_layout_boot_logged = true
  end

  local function _apply_baked_layout(source)
      _apply_layout_table(_load_json_layout(BAKED_LAYOUT_PATH) or {}, source)
  end

  local function _pref_layout_loaded()
      return type(_G["_qt_pref_layout_margin_r"]) == "number"
          and type(_G["_qt_pref_win_y"]) == "number"
          and type(_G["_qt_pref_win_w"]) == "number" and type(_G["_qt_pref_win_h"]) == "number"
  end

  local function _layout_payload(margin_r, win_y, win_w, win_h, font_size)
      return {
          layout_margin_r = margin_r, win_y = win_y, win_w = win_w, win_h = win_h,
          font_size = font_size,
      }
  end

  local function _fill_layout_tier_permanent_or_baked()
      local perm = _load_json_layout(PERMANENT_LAYOUT_PATH)
      if perm and _win_layout_complete(perm) then
          _apply_layout_table(perm, "permanent")
          return
      end
      _apply_baked_layout("baked")
  end

  local function _save_layout_files(margin_r, win_y, win_w, win_h, font_size)
      local layout = _layout_payload(margin_r, win_y, win_w, win_h, font_size)
      pcall(function() json.dump_file(LAST_LAYOUT_PATH, layout) end)
      pcall(function() json.dump_file(PERMANENT_LAYOUT_PATH, layout) end)
  end

  local function load_prefs()
      local ok, data = pcall(function() return json.load_file(PREFS_PATH) end)
      if not (ok and type(data) == "table") then
          _fill_layout_tier_permanent_or_baked()
          _G._qt_prefs_stub = true
          return
      end
      if _prefs_is_stub(data) then
          _fill_layout_tier_permanent_or_baked()
          _G._qt_prefs_stub = true
          return
      end
      for _, k in ipairs(PREF_KEYS) do
          if data[k] ~= nil then
              -- mod table not declared yet â€” stored in a temp; applied after mod is created
              _G["_qt_pref_" .. k] = data[k]
          end
      end
      if type(data.giver_overrides) == "table" then
          for k, v in pairs(data.giver_overrides) do
              local kn = tonumber(k)
              if kn and type(v) == "number" and v > 0 then MANUAL_GIVER_OVERRIDES[kn] = v end
          end
      end
      if type(data.manual_pos_overrides) == "table" then
          for k, v in pairs(data.manual_pos_overrides) do
              local kn = tonumber(k)
              if kn and type(v) == "table" and v.x and v.y and v.z then
                  MANUAL_POS_OVERRIDES[kn] = { x = v.x, y = v.y, z = v.z }
              end
          end
      end
      if type(data.eliminated_overrides) == "table" then
          for k, arr in pairs(data.eliminated_overrides) do
              local kn = tonumber(k)
              if kn and type(arr) == "table" then
                  local kept = {}
                  for _, p in ipairs(arr) do
                      if type(p) == "table" and type(p.cid) == "number" and p.cid > 0 then
                          kept[#kept+1] = { cid = p.cid, x = p.x, y = p.y, z = p.z }
                      end
                  end
                  if #kept > 0 then ELIMINATED_OVERRIDES[kn] = kept end
              end
          end
      end
      if type(data.voided_quests) == "table" then
          for k, v in pairs(data.voided_quests) do
              local kn = tonumber(k); if kn and v == true then VOIDED_QUESTS[kn] = true end
          end
      end
      if type(data.locked_quests) == "table" then
          for k, v in pairs(data.locked_quests) do
              local kn = tonumber(k); if kn and v == true then LOCKED_QUESTS[kn] = true end
          end
      end
      if type(data.quest_start_days) == "table" then
          for k, v in pairs(data.quest_start_days) do
              local kn = tonumber(k); if kn and type(v) == "number" then QUEST_START_DAYS[kn] = v end
          end
      end
      if type(data.quest_start_hours) == "table" then
          for k, v in pairs(data.quest_start_hours) do
              local kn = tonumber(k); if kn and type(v) == "number" then QUEST_START_HOURS[kn] = v end
          end
      end
      if type(data.learned_chara_names) == "table" then
          for k, v in pairs(data.learned_chara_names) do
              if type(v) == "string" and v ~= "" then LEARNED_CHARA_NAMES[tostring(k)] = v end
          end
      end
      if type(data.prefs_version) ~= "number" or data.prefs_version < 4 then
          data.prefs_version = 4
          if data.debug_logging == nil then
              _G["_qt_pref_debug_logging"] = true
          end
      end
      if type(data.prefs_version) ~= "number" or data.prefs_version < 5 then
          if data.win_alpha == nil then
              _G["_qt_pref_win_alpha"] = 0.4
          end
      end
      if type(data.prefs_version) ~= "number" or data.prefs_version < 9 then
          if data.win_x == nil and data.win_y == nil and data.win_w == nil and data.win_h == nil then
              _fill_layout_tier_permanent_or_baked()
          end
      end
      _migrate_layout_v10(data)
      if type(data.layout_margin_r) == "number" then
          _G["_qt_pref_layout_margin_r"] = data.layout_margin_r
      end
      if not _pref_layout_loaded() then
          if _win_layout_complete(data) then
              _apply_layout_table(data, "prefs")
          else
              _fill_layout_tier_permanent_or_baked()
          end
      else
          _G._qt_layout_source = "prefs"
      end
  end

  local function save_prefs()
      if type(mod) ~= "table" then return end
      if mod._qt_shutdown then return end
      local out = {}
      for _, k in ipairs(PREF_KEYS) do out[k] = mod[k] end
      local go = {}
      for k, v in pairs(MANUAL_GIVER_OVERRIDES) do
          if not is_bundled_giver(k, v) then go[tostring(k)] = v end
      end
      out.giver_overrides = go
      local po = {}
      for k, v in pairs(MANUAL_POS_OVERRIDES) do
          if not is_bundled_pos(k, v) then po[tostring(k)] = v end
      end
      out.manual_pos_overrides = po
      local eo = {}
      for k, v in pairs(ELIMINATED_OVERRIDES) do eo[tostring(k)] = v end
      out.eliminated_overrides = eo
      local vq = {}
      for k, v in pairs(VOIDED_QUESTS) do if v == true then vq[tostring(k)] = true end end
      out.voided_quests = vq
      local lq = {}
      for k, v in pairs(LOCKED_QUESTS) do if v == true then lq[tostring(k)] = true end end
      out.locked_quests = lq
      local sd = {}
      for k, v in pairs(QUEST_START_DAYS) do sd[tostring(k)] = v end
      out.quest_start_days = sd
      local sh = {}
      for k, v in pairs(QUEST_START_HOURS) do sh[tostring(k)] = v end
      out.quest_start_hours = sh
      out.learned_chara_names = LEARNED_CHARA_NAMES
      out.prefs_version = 11
      -- JSON-safe scalars only (userdata in mod table broke silent dumps on some installs)
      local safe = {}
      for _, k in ipairs(PREF_KEYS) do
          local v = out[k]
          if type(v) == "number" then safe[k] = v
          elseif type(v) == "boolean" then safe[k] = v
          elseif type(v) == "string" then safe[k] = v end
      end
      safe.giver_overrides = out.giver_overrides
      safe.manual_pos_overrides = out.manual_pos_overrides
      safe.eliminated_overrides = out.eliminated_overrides
      safe.voided_quests = out.voided_quests
      safe.locked_quests = out.locked_quests
      safe.quest_start_days = out.quest_start_days
      safe.quest_start_hours = out.quest_start_hours
      safe.learned_chara_names = out.learned_chara_names
      _sync_margin_from_viewport()
      _apply_layout_coords_to_mod()
      safe.layout_margin_r = mod.layout_margin_r
      safe.win_y = mod.win_y
      safe.prefs_version = 11
      if type(safe.win_w) == "number" and type(safe.win_h) == "number" then
          safe.win_w, safe.win_h = _clamp_layout_size(safe.win_w, safe.win_h)
          mod.win_w, mod.win_h = safe.win_w, safe.win_h
          _sync_margin_from_viewport()
          safe.layout_margin_r = mod.layout_margin_r
      end
      local ok_dump, err_dump = pcall(function() json.dump_file(PREFS_PATH, safe) end)
      if not ok_dump then
          mlog_boot("[QT] save_prefs FAILED: " .. tostring(err_dump))
          return
      end
      _save_layout_files(safe.layout_margin_r, safe.win_y, safe.win_w, safe.win_h, safe.font_size)
      mod._prefs_dirty = false
      _G._qt_prefs_stub = nil
      local layout_key = string.format("margin_r=%.0f y=%.0f %dx%d",
          tonumber(safe.layout_margin_r) or -1, tonumber(safe.win_y) or -1,
          tonumber(safe.win_w) or -1, tonumber(safe.win_h) or -1)
      if mod._last_layout_log_key ~= layout_key then
          mod._last_layout_log_key = layout_key
          mlog_boot(string.format("[QT] layout saved %s → prefs+permanent", layout_key))
      end
  end

  local function mark_prefs_dirty()
      if type(mod) == "table" then mod._prefs_dirty = true end
  end

  local function _saved_window_pos_valid()
      _refresh_display_cache()
      if type(mod.win_x) ~= "number" or type(mod.win_y) ~= "number" then return false end
      if type(mod.win_w) ~= "number" or mod.win_w < MIN_SAVE_WIN_W then return false end
      if type(mod.win_h) ~= "number" or mod.win_h < MIN_SAVE_WIN_H then return false end
      local dw, dh = _display_size()
      local ww, wh = _clamp_layout_size(mod.win_w, mod.win_h)
      mod.win_w, mod.win_h = ww, wh
      return _pos_in_viewport(mod.win_x, mod.win_y, dw, dh)
  end

  local function _clear_saved_window_position()
      mod.layout_margin_r = DEFAULT_QUEST_WIN_MARGIN_R
      mod.win_y = DEFAULT_QUEST_WIN_Y
      mod.win_w, mod.win_h = DEFAULT_QUEST_WIN_W, DEFAULT_QUEST_WIN_H
      _apply_layout_coords_to_mod()
      mod._win_apply_count = 0
      mod._win_capture_after = nil
      mark_prefs_dirty()
      save_prefs()
      if mlog then mlog("[QT] cleared saved window position") else mlog_boot("[QT] cleared saved window position") end
  end

  local function _reset_window_layout()
      mod.layout_margin_r = DEFAULT_QUEST_WIN_MARGIN_R
      mod.win_y = DEFAULT_QUEST_WIN_Y
      mod.win_w, mod.win_h = DEFAULT_QUEST_WIN_W, DEFAULT_QUEST_WIN_H
      _apply_layout_coords_to_mod()
      mod._win_apply_count = 0
      mod._win_capture_after = nil
      mod._qt_boot_had_valid_layout = true
      _G._qt_layout_source = "baked"
      mark_prefs_dirty()
      save_prefs()
      mlog_boot(string.format("[QT] reset window layout to baked %.0f,%.0f %dx%d",
          mod.win_x, mod.win_y, mod.win_w, mod.win_h))
  end

  local QT_BOOT_APPLY_MAX = 60

  local function _imgui_vec2(x, y)
      if Vector2f and type(Vector2f.new) == "function" then
          local ok, v = pcall(Vector2f.new, x, y)
          if ok and v ~= nil then return v end
      end
      return { x = x, y = y }
  end

  local function _size_within_pct(aw, ah, tw, th, pct)
      if not aw or not ah or not tw or not th then return false end
      if math.abs(aw - tw) / math.max(tw, 1) > pct then return false end
      if math.abs(ah - th) / math.max(th, 1) > pct then return false end
      return true
  end

  local function _apply_saved_window_once()
      if mod._qt_boot_layout_done then return end
      local frame = (mod._qt_boot_apply_frames or 0) + 1
      mod._qt_boot_apply_frames = frame
      if frame > QT_BOOT_APPLY_MAX then
          mod._qt_boot_layout_done = true
          return
      end

      _refresh_display_cache()
      local cond = 1

      if not mod._qt_boot_had_valid_layout then
          if type(mod.layout_margin_r) ~= "number" then
              mod.layout_margin_r = DEFAULT_QUEST_WIN_MARGIN_R
          end
          _apply_layout_coords_to_mod()
          mod._qt_boot_had_valid_layout = true
      else
          _apply_layout_coords_to_mod()
      end

      local cx, cy, ww, wh = mod.win_x, mod.win_y, mod.win_w, mod.win_h
      local dw, dh = _display_size()
      if frame == 1 then
          if not _G._qt_layout_boot_logged then
              local src = _G._qt_layout_source or "prefs"
              mlog_boot(string.format("[QT] restored margin_r=%.0f y=%.0f %dx%d → x=%.0f display=%dx%d (source=%s)",
                  mod.layout_margin_r or -1, cy, ww, wh, cx, dw, dh, src))
              _G._qt_layout_boot_logged = true
          end
          mod._win_capture_after = os.clock() + 2.0
          mod._qt_boot_layout_at = os.clock()
          mod._qt_boot_restore_w = ww
          mod._qt_boot_restore_h = wh
      end

      if frame == 1 then
          mlog_boot(string.format("[QT] apply window intended pos=%.0f,%.0f size=%dx%d cond=%d frame=1",
              cx, cy, ww, wh, cond))
      end
      pcall(function() imgui.set_next_window_pos(_imgui_vec2(cx, cy), cond) end)
      if ww and wh then
          pcall(function() imgui.set_next_window_size(_imgui_vec2(ww, wh), cond) end)
      end
  end

  function ctx._qt_check_boot_layout_settled(aw, ah)
      if mod._qt_boot_layout_done then return true end
      local tw, th = mod._qt_boot_restore_w, mod._qt_boot_restore_h
      if _size_within_pct(aw, ah, tw, th, 0.05) then
          mod._qt_boot_layout_done = true
          mlog_boot(string.format("[QT] boot layout settled actual=%dx%d target=%dx%d",
              aw, ah, tw, th))
          return true
      end
      if (mod._qt_boot_apply_frames or 0) >= QT_BOOT_APPLY_MAX then
          mod._qt_boot_layout_done = true
          mlog_boot(string.format("[QT] boot layout apply max frames actual=%dx%d target=%dx%d",
              aw or -1, ah or -1, tw or -1, th or -1))
          return true
      end
      return false
  end

  function ctx.apply_prefs_to_mod()
    if type(mod) ~= "table" then return end
    for _, k in ipairs(PREF_KEYS) do
      local tmp = _G["_qt_pref_" .. k]
      if tmp ~= nil then mod[k] = tmp; _G["_qt_pref_" .. k] = nil end
    end
    mod.show_window = (mod.show_window ~= false)
    if type(mod.win_alpha) ~= "number" then mod.win_alpha = 0.4 end
    mod.win_alpha = math.max(0.0, math.min(1.0, mod.win_alpha))
    mlog_boot("[QT] prefs show_window=" .. tostring(mod.show_window))
    if mod.debug_logging then mlog_boot("[QT] verbose debug ON") end
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
    if type(mod.layout_margin_r) ~= "number" then
      mod.layout_margin_r = DEFAULT_QUEST_WIN_MARGIN_R
    end
    if type(mod.win_w) == "number" and type(mod.win_h) == "number" then
      mod.win_w, mod.win_h = _clamp_layout_size(mod.win_w, mod.win_h)
    end
    _apply_layout_coords_to_mod()
    mlog_boot(string.format("[QT][sniff] deep_sniff=%s heavy=%s (prefs)",
        mod.deep_sniff == true and "ON" or "OFF",
        mod.deep_sniff_heavy == true and "ON" or "OFF"))
  end

  function ctx.load_prefs_early()
    load_prefs()
  end

  ctx.save_prefs = save_prefs
  ctx.mark_prefs_dirty = mark_prefs_dirty
  ctx._display_size = _display_size
  ctx._saved_window_pos_valid = _saved_window_pos_valid
  ctx._clear_saved_window_position = _clear_saved_window_position
  ctx._reset_window_layout = _reset_window_layout
  ctx._apply_saved_window_once = _apply_saved_window_once
  ctx._clamp_layout_size = _clamp_layout_size
  ctx._refresh_display_cache = _refresh_display_cache
  ctx._apply_layout_coords_to_mod = _apply_layout_coords_to_mod
  ctx._sync_margin_from_viewport = _sync_margin_from_viewport
  ctx._imgui_vec2 = _imgui_vec2
end

return M
