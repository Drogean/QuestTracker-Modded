-- quest_tracker_window.lua — quest window UI + row draw (Lua 200-local headroom)
local M = package.loaded["quest_tracker_window"]
if M then return M end
M = {}

function M.install(ctx)
    local mod = ctx.mod
    if mod._qt_window_installed then return end
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
    local _clamp_layout_size = ctx._clamp_layout_size
    local _refresh_display_cache = ctx._refresh_display_cache
    local _display_size = ctx._display_size
    local _reset_window_layout = ctx._reset_window_layout
    local DEFAULT_QUEST_WIN_Y = ctx.DEFAULT_QUEST_WIN_Y
    local DEFAULT_QUEST_WIN_H = ctx.DEFAULT_QUEST_WIN_H
    local mark_prefs_dirty = ctx.mark_prefs_dirty
    local rebuild = ctx.rebuild
    local pin_all_in_current_filtered_tab = ctx.pin_all_in_current_filtered_tab
    local clear_injected_markers = ctx.clear_injected_markers
    local pin_quest = ctx.pin_quest
    local unpin_quest = ctx.unpin_quest
    local get_player_universal_pos = ctx.get_player_universal_pos
    local _teleport_player_to = ctx._teleport_player_to
    local resolve_teleport_pos = ctx.resolve_teleport_pos
    local MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
    local QD = ctx.QD
    local _draw_npc_rows_cached = ctx._draw_npc_rows_cached
    local _name_for_qid = ctx._name_for_qid
    local milestone_label = ctx.milestone_label
    local _format_hour_12 = ctx._format_hour_12
    local _start_fast_forward = ctx._start_fast_forward
    local _set_time_scale = ctx._set_time_scale
    local _tick_fast_forward = ctx._tick_fast_forward
    local TimeMod = ctx.TimeMod
    local _apply_saved_window_once = ctx._apply_saved_window_once
    local _check_game_ready = ctx._check_game_ready
    local _sync_margin_from_viewport = ctx._sync_margin_from_viewport
    local _apply_layout_coords_to_mod = ctx._apply_layout_coords_to_mod
    local _qt_check_boot_layout_settled = ctx._qt_check_boot_layout_settled
    local _imgui_vec2 = ctx._imgui_vec2
    local _clear_saved_window_position = ctx._clear_saved_window_position
    local safe_get_field = ctx.safe_get_field
    local to_int = ctx.to_int
    local _qt_force_refresh = ctx._qt_force_refresh
    local _qt_run_logic_tick = ctx._qt_run_logic_tick
    local qt_background_log_tick = ctx.qt_background_log_tick
    if type(_qt_run_logic_tick) ~= "function" then
        mlog_boot("[QT] FATAL window install: _qt_run_logic_tick missing — UI will show loading rows")
        _qt_run_logic_tick = function() end
    end
    local is_bundled_pos = ctx.is_bundled_pos

    local function _qt_prequire(name)
        local ok, lib = pcall(require, name)
        if ok then return lib end
        return nil
    end
    local Child = {
        begin = function() return false end,
        end_child = function() end,
        ensure_closed = function() end,
    }
    local ChildMod = _qt_prequire("quest_tracker_window_child")
    if ChildMod and ChildMod.install then
        local installed = ChildMod.install({ mod = mod, mlog_boot = mlog_boot, _imgui_vec2 = _imgui_vec2 })
        if installed and type(installed.begin) == "function" then
            Child = installed
        else
            mlog_boot("[QT] FATAL child install bad return — quest list draw disabled")
        end
    else
        mlog_boot("[QT] FATAL child module missing — quest list draw disabled")
    end

    local function _qt_num_field(v, key)
        if type(v) == "number" then return v end
        if v and type(v[key]) == "number" then return v[key] end
        return nil
    end

    local function _qt_parse_vec2(v, fb_x, fb_y)
        if type(v) == "number" then return v, fb_y end
        if v == nil then return fb_x, fb_y end
        local x, y = fb_x, fb_y
        pcall(function()
            if type(v.x) == "number" then x = v.x end
            if type(v.y) == "number" then y = v.y end
        end)
        return x, y
    end

    local function _qt_item_rect_max_x()
        if not imgui.get_item_rect_max then return nil end
        local ok, r = pcall(imgui.get_item_rect_max)
        if not ok or r == nil then return nil end
        return _qt_num_field(r, "x")
    end

    local function _qt_window_pos_x()
        if not imgui.get_window_pos then return 0 end
        local ok, p = pcall(imgui.get_window_pos)
        if not ok then return 0 end
        return _qt_num_field(p, "x") or (type(p) == "number" and p) or 0
    end

    local function _qt_content_region_max_local()
        if not imgui.get_window_content_region_max then return nil end
        local ok, v = pcall(imgui.get_window_content_region_max)
        if not ok then return nil end
        return _qt_num_field(v, "x") or (type(v) == "number" and v) or nil
    end

    local function _qt_child_content_span()
        local cr_min, cr_max = 0, _qt_content_region_max_local()
        if imgui.get_window_content_region_min then
            local ok, v = pcall(imgui.get_window_content_region_min)
            local mn = _qt_num_field(v, "x") or (type(v) == "number" and v)
            if mn then cr_min = mn end
        end
        if cr_max and cr_max > cr_min + 80 then return cr_max - cr_min end
        return nil
    end

    -- Inside ##qtquestscroll child: use content-region span, not parent window pos.
    local function _qt_capture_wrap_right_from_tabs()
        if type(mod) ~= "table" then return end
        local span = _qt_child_content_span()
        local right_local = span and (span - 5) or nil
        local tab_right = _qt_item_rect_max_x()
        if tab_right and span then
            local cr_min = 0
            if imgui.get_window_content_region_min then
                local ok, v = pcall(imgui.get_window_content_region_min)
                cr_min = _qt_num_field(v, "x") or 0
            end
            local tab_local = tab_right - cr_min - 5
            if tab_local > 80 and (not right_local or tab_local < right_local) then
                right_local = tab_local
            end
        end
        if right_local and right_local > 80 then
            mod._qt_wrap_right_local = right_local
            mod._qt_row_width = right_local
        end
    end

    local _QT_ROW_PAD = 5
    local TAB_SHORT_NAMES = { "Avail", "On", "Done", "All", "Hide" }
    local _QT_TAB_BTN_PAD = 18

    local function _qt_measure_anchor_width()
        local right = _qt_item_rect_max_x()
        if right then
            local w = right - _qt_window_pos_x() - _QT_ROW_PAD
            if w > 80 then return w end
        end
        local cr = _qt_content_region_max_local()
        if cr and cr > 80 then return cr - _QT_ROW_PAD end
        return DEFAULT_QUEST_WIN_W - 15
    end

    local function _qt_set_row_width(w)
        if type(mod) == "table" and type(w) == "number" and w > 80 then
            mod._qt_row_width = w
        end
    end

    local function _qt_measure_text_width(s)
        if not s or s == "" then return 0 end
        if imgui.calc_text_size then
            local ok, sz = pcall(imgui.calc_text_size, s)
            if ok and sz and type(sz.x) == "number" and sz.x > 0 then return sz.x end
        end
        return #s * 5.8
    end

    local function _qt_wrap_line_pixels(line, max_w)
        if not line or line == "" then return "" end
        if _qt_measure_text_width(line) <= max_w then return line end
        local out, cur = {}, ""
        for word in line:gmatch("%S+") do
            local trial = (cur == "") and word or (cur .. " " .. word)
            if _qt_measure_text_width(trial) <= max_w then
                cur = trial
            else
                if cur ~= "" then out[#out + 1] = cur end
                cur = word
            end
        end
        if cur ~= "" then out[#out + 1] = cur end
        return table.concat(out, "\n")
    end

    local WIN_LAYOUT_STABLE_FRAMES = 3
    local WIN_LAYOUT_DEBOUNCE_S = 0.5

    local function _qt_layout_stage(key, value, now)
        mod._qt_layout_stage = mod._qt_layout_stage or {}
        local st = mod._qt_layout_stage
        if st[key] ~= value then
            st[key] = value
            st[key .. "_n"] = 1
            st[key .. "_at"] = now
            return false
        end
        st[key .. "_n"] = (st[key .. "_n"] or 0) + 1
        return st[key .. "_n"] >= WIN_LAYOUT_STABLE_FRAMES
            or (now - (st[key .. "_at"] or now)) >= WIN_LAYOUT_DEBOUNCE_S
    end

    local function _qt_pos_capture_ok(wpx, wpy)
        if not wpx or not wpy then return false end
        if wpx < 100 or wpy < 10 then return false end
        if _refresh_display_cache then pcall(_refresh_display_cache) end
        local dw, dh = 1920, 1080
        if _display_size then dw, dh = _display_size() end
        if wpx < -50 or wpx > dw + 50 or wpy < -50 or wpy > dh + 50 then return false end
        return true
    end

    local function _qt_content_width()
        local span = _qt_child_content_span()
        if span and span > 80 then return span - 4 end
        return (type(mod.win_w) == "number" and mod.win_w > 80) and (mod.win_w - 36) or (DEFAULT_QUEST_WIN_W - 36)
    end

    local function _qt_estimate_tab_row_width(labels)
        local total = 0
        for i = 1, #labels do
            total = total + _qt_measure_text_width(labels[i]) + _QT_TAB_BTN_PAD
        end
        return total
    end

    local function _qt_layout_capture_allowed(now)
        if mod._win_capture_after and now < mod._win_capture_after then return false end
        return true
    end

    local function _qt_size_delta_ok(nw, nh, now)
        if not mod._qt_boot_layout_at or (now - mod._qt_boot_layout_at) >= 2.0 then return true end
        local rw = mod._qt_boot_restore_w
        local rh = mod._qt_boot_restore_h
        if not rw or not rh then return true end
        if math.abs(nw - rw) / math.max(rw, 1) > 0.15 then return false end
        if math.abs(nh - rh) / math.max(rh, 1) > 0.15 then return false end
        return true
    end

    local function _qt_boot_save_allowed(now)
        if not mod._qt_boot_layout_at then return true end
        return (now - mod._qt_boot_layout_at) >= 2.0
    end

    local function _qt_draw_tab_row()
        mod._qt_wrap_right_local = nil
        local avail = _qt_content_width()
        local full_labels = {}
        for i, name in ipairs(TAB_NAMES) do
            local count = mod.state_counts[i]
            if type(count) ~= "number" then count = 0 end
            full_labels[i] = name .. "(" .. tostring(count) .. ")"
        end
        local use_short = _qt_estimate_tab_row_width(full_labels) > avail
        for i, name in ipairs(TAB_NAMES) do
            if i > 1 then imgui.same_line() end
            local count = mod.state_counts[i]
            if type(count) ~= "number" then count = 0 end
            local label = use_short and (TAB_SHORT_NAMES[i] .. "(" .. tostring(count) .. ")") or full_labels[i]
            if imgui.button(label .. "##qttab" .. i) then
                Child.ensure_closed()
                mod.tab = i
                mod._qt_tab_scroll_reset = true
                if mod._qt_refilter_draw_list then
                    pcall(mod._qt_refilter_draw_list)
                end
                mod._last_win_save = os.clock()
                mark_prefs_dirty()
            end
            if i == #TAB_NAMES then _qt_capture_wrap_right_from_tabs() end
        end
    end

    local function _qt_align_row_full_width()
        if not imgui.set_cursor_pos_x then return end
        if imgui.unindent then pcall(imgui.unindent, 28) end
        local min_x = 8
        if imgui.get_window_content_region_min then
            local ok, v = pcall(imgui.get_window_content_region_min)
            local mn = _qt_num_field(v, "x") or (type(v) == "number" and v)
            if mn then min_x = mn end
        end
        pcall(imgui.set_cursor_pos_x, min_x)
    end

    local function _qt_draw_wrapped_text(hex, txt)
        if txt == nil or txt == "" then return end
        if type(txt) ~= "string" then txt = tostring(txt) end
        txt = txt:gsub("\r\n", "\n")
        _qt_align_row_full_width()
        local w = (type(mod._qt_row_width) == "number" and mod._qt_row_width)
            or _qt_measure_anchor_width()
        w = math.max(200, w)
        local wrapped = {}
        for line in (txt .. "\n"):gmatch("([^\n]*)\n") do
            wrapped[#wrapped + 1] = _qt_wrap_line_pixels(line, w)
        end
        imgui.text_colored(table.concat(wrapped, "\n"), hex)
    end

    local function _qt_draw_colored_lines(hex, lines)
        if lines == nil then return end
        if type(lines) == "string" then
            _qt_draw_wrapped_text(hex, lines)
            return
        end
        if type(lines) == "table" then
            for _, line in ipairs(lines) do
                if type(line) == "string" and line ~= "" then
                    _qt_draw_wrapped_text(hex, line)
                end
            end
        end
    end

    local function clamp_font_size(sz)
        if type(sz) ~= "number" then sz = 28 end
        return math.max(18, math.min(38, math.floor(sz + 0.5)))
    end

    -- Same idea as Affinity Bar readable text: real point size via load_font (Tahoma etc.), not missing APIs.
    local _qt_ui_font = nil
    local _qt_ui_font_pt = -1
    local _qt_ui_font_path = nil
    local _qt_font_ok_logged, _qt_font_bad_logged = false, false

    local _QT_FONT_CANDIDATES = {
        "segoeui.ttf", "arial.ttf", "Tahoma.ttf", "verdana.ttf", "calibri.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/tahoma.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibri.ttf",
        "C:/Windows/Fonts/verdana.ttf",
    }

    local function ensure_quest_tracker_ui_font(_content_w)
        local sz = clamp_font_size(mod.font_size)
        if mod.font_size ~= sz then mod.font_size = sz end
        local cache_key = tostring(sz)
        if _qt_ui_font and mod._qt_font_cache_key == cache_key then return _qt_ui_font end
        mod._qt_font_cache_key = cache_key
        _qt_ui_font = nil
        _qt_ui_font_pt = -1
        _qt_ui_font_path = nil
        for _, path in ipairs(_QT_FONT_CANDIDATES) do
            local ok, f = pcall(function() return imgui.load_font(path, sz) end)
            if ok and f ~= nil then
                _qt_ui_font = f
                _qt_ui_font_pt = sz
                _qt_ui_font_path = path
                if not _qt_font_ok_logged then
                    _qt_font_ok_logged = true
                    mlog_boot("[QT] UI font OK: " .. path .. " @ " .. sz .. "pt (title+body same)")
                end
                return _qt_ui_font
            end
        end
        if not _qt_font_bad_logged then
            _qt_font_bad_logged = true
            mlog_boot("[QT] UI font FAILED — copy segoeui.ttf or tahoma.ttf into reframework/fonts")
        end
        return nil
    end

    mod.font_size = clamp_font_size(mod.font_size)

    local COL_AVAIL = 0xFFFFFFFF
    local COL_ONGO  = 0xFFFFFFFF
    local COL_DONE  = 0xFF66FF66
    local COL_HL    = 0xFF66FFFF
    local COL_RED    = 0xFF4444FF
    local COL_GREY   = 0xFF888888

    local function cat_color(c)
        if c == "Ongoing"   then return COL_ONGO end
        if c == "Completed" then return COL_DONE end
        return COL_AVAIL
    end


    -- =========== QUEST ROW UI ===========
    local _draw_row_logged = {}

    local function _status_tag(qid)
        if mod.completed_ids[qid]   then return "done" end
        if mod.progressing_ids[qid] then return "ongoing" end
        if mod.acceptable_ids[qid]  then return "available" end
        return "missing"
    end

    local function _status_color(tag)
        if tag == "done"     then return 0xFF66FF66 end
        if tag == "ongoing"  then return 0xFF66CCFF end
        if tag == "available" then return 0xFFFFFFFF end
        return 0xFF888888
    end

    local function _draw_compact_links(q, c)
        if not QD or not QD.format_quest_links then return end
        local ok, links = pcall(QD.format_quest_links, q.id, _name_for_qid)
        if not ok or type(links) ~= "table" or #links == 0 then return end
        imgui.text_colored("More detail:", 0xFFAAAA88)
        for _, ln in ipairs(links) do
            _qt_draw_wrapped_text(0xFFCCCCAA, ln)
        end
        imgui.spacing()
    end

    local function _draw_row_body(q, c)
        mod._qt_row_width = nil
        _qt_align_row_full_width()
        if not c and mod._row_cache_prev then c = mod._row_cache_prev[q.id] end
        if not c then
            imgui.text_colored("(loading quest row…)", 0xFF888888)
            imgui.spacing()
            return
        end
        if q.category == "Ongoing" then
            if c.step_title then
                _qt_draw_wrapped_text(0xFFFFCC66, "STEP: " .. c.step_title)
            else
                imgui.text_colored("STEP: (unknown — open in-game journal)", 0xFF888888)
            end
            if c.tips and #c.tips > 0 then
                _qt_draw_colored_lines(0xFFEEEEEE, c.tips)
            elseif c.step_title and QD and QD.get_step_hints_for_title then
                local ok_t, t = pcall(QD.get_step_hints_for_title, q.id, c.step_title, c.wiki_substep_key)
                if ok_t and type(t) == "table" and #t > 0 then
                    _qt_draw_colored_lines(0xFFEEEEEE, t)
                end
            end
            imgui.spacing()
        elseif q.category == "Available" then
            local start_txt = nil
            if c.tips and c.tips[1] then start_txt = c.tips[1]
            elseif c.step_title then start_txt = c.step_title
            elseif QD and QD.get_fallback_step_title then
                local ok_f, fb = pcall(QD.get_fallback_step_title, q.id)
                if ok_f and type(fb) == "string" and fb ~= "" then start_txt = fb end
            end
            if start_txt then
                _qt_draw_wrapped_text(0xFFFFEE99, "START: " .. start_txt)
            end
            if c.tips and #c.tips > 1 then
                local extra = {}
                for i = 2, #c.tips do extra[#extra + 1] = c.tips[i] end
                _qt_draw_colored_lines(0xFFEEEEEE, extra)
            end
            imgui.spacing()
        end
        _draw_compact_links(q, c)
        if c.time_limit and q.category == "Ongoing" then
            if c.timer_rem_h then
                local rem_h = c.timer_rem_h
                if rem_h > 0 then
                    local d = math.floor(rem_h / 24)
                    local h = rem_h - d * 24
                    local col = (rem_h <= 12) and COL_RED or (rem_h <= 24 and 0xFFFF8844 or 0xFFFFCC44)
                    imgui.text_colored(string.format("TIMER: %dd %dh left (of %.0f days)", d, h, c.time_limit), col)
                else
                    imgui.text_colored(string.format("TIME LIMIT EXCEEDED (%dh over)", -rem_h), COL_RED)
                end
            else
                imgui.text_colored(string.format("~%d day time limit (start day unknown)", c.time_limit), 0xFFFFCC44)
            end
        end
        if c.sched and q.category ~= "Completed" and c.sched_s and c.sched_f then
            local s, f = c.sched_s, c.sched_f
            local col = c.sched_in_win and 0xFF44FF44 or 0xFFFF4444
            local lbl = c.sched_in_win and string.format("NPC available now (window %d:00-%d:00)", s, f)
                                or string.format("NPC only available %d:00-%d:00", s, f)
            imgui.text_colored(lbl, col)
            if not c.sched_in_win and c.sched_ff_h and c.sched_ff_h > 0.01 and c.sched_ff_h < 18 then
                if imgui.button(string.format("Skip %.1fh to %s##ts%d", c.sched_ff_h, _format_hour_12(s), q.id)) then
                    _start_fast_forward(c.sched_ff_h + (1 / 60))
                    _qt_force_refresh()
                end
            end
        end
        imgui.separator()
        local row_active = (q.category == "Available" or q.category == "Ongoing" or q.category == "Upcoming")
        if q.category == "Available" or q.category == "Ongoing" then
            local is_pinned = MAP_API.pinned_data[q.id] ~= nil or MAP_API.pinned_pos[q.id] ~= nil
            if imgui.button((is_pinned and "Unpin" or "Pin map") .. "##pin" .. q.id) then
                if is_pinned then pcall(unpin_quest, q.id)
                else
                    local ok_pin, pin_ok, pin_msg = pcall(pin_quest, q.id)
                    if not ok_pin then MAP_API.last_msg = "Pin crashed: " .. tostring(pin_ok)
                    elseif not pin_ok then MAP_API.last_msg = tostring(pin_msg or "pin failed") end
                end
            end
        end
        if row_active then
            imgui.same_line()
            if imgui.button("TP start##tps" .. q.id) then
                local tx, ty, tz, src = nil, nil, nil, "cache_tp"
                if resolve_teleport_pos then
                    local cid = MANUAL_GIVER_OVERRIDES and MANUAL_GIVER_OVERRIDES[q.id]
                    tx, ty, tz, src = resolve_teleport_pos(q.id, cid)
                end
                if not tx and c.tp_x then tx, ty, tz, src = c.tp_x, c.tp_y, c.tp_z, "cache_tp" end
                local ok = tx and _teleport_player_to and _teleport_player_to(tx, ty, tz, {
                    qid = q.id, cid = MANUAL_GIVER_OVERRIDES and MANUAL_GIVER_OVERRIDES[q.id], src = src,
                })
                MAP_API.last_msg = ok and "TP to quest start" or "TP failed — see log"
                _qt_force_refresh()
            end
        end
        if row_active and (c.tp_x or (MANUAL_POS_OVERRIDES and MANUAL_POS_OVERRIDES[q.id])) then
            imgui.same_line()
            if imgui.button("Mark start##savehere" .. q.id) then
                local px, py, pz = get_player_universal_pos()
                if px then
                    MANUAL_POS_OVERRIDES[q.id] = { x = px, y = py, z = pz }
                    mark_prefs_dirty()
                    _qt_force_refresh()
                end
            end
            if MANUAL_POS_OVERRIDES[q.id] and not is_bundled_pos(q.id, MANUAL_POS_OVERRIDES[q.id]) then
                imgui.same_line()
                if imgui.button("Reset start##rstpos" .. q.id) then
                    if BUNDLED_POS_OVERRIDES[q.id] then
                        local b = BUNDLED_POS_OVERRIDES[q.id]
                        MANUAL_POS_OVERRIDES[q.id] = { x = b.x, y = b.y, z = b.z }
                    else MANUAL_POS_OVERRIDES[q.id] = nil end
                    mark_prefs_dirty()
                    _qt_force_refresh()
                end
            end
        end
        if q.category ~= "Completed" then
            _draw_npc_rows_cached(q.id, c.npc_rows, row_active)
            if c.missing_npc then
                imgui.text_colored("Not loaded: " .. c.missing_npc, COL_NPC_ORANGE)
            end
        end
        imgui.separator()
        local is_voided = VOIDED_QUESTS[q.id] == true
        local cv, vv = imgui.checkbox("Hide##void" .. q.id, is_voided)
        if cv then
            VOIDED_QUESTS[q.id] = vv or nil
            mark_prefs_dirty()
            pcall(rebuild); pcall(mod._qt_schedule_cache_refresh, "lock")
        end
        imgui.same_line()
        if LOCKED_QUESTS[q.id] then
            if imgui.button("Unlock##ulk" .. q.id) then
                LOCKED_QUESTS[q.id] = nil; VOIDED_QUESTS[q.id] = nil
                mark_prefs_dirty(); pcall(rebuild); pcall(mod._qt_schedule_cache_refresh, "lock")
            end
        else
            if imgui.button("Mark Locked##lck" .. q.id) then
                LOCKED_QUESTS[q.id] = true; VOIDED_QUESTS[q.id] = true
                mark_prefs_dirty(); pcall(rebuild); pcall(mod._qt_schedule_cache_refresh, "lock")
            end
        end
    end

    local function draw_row(q)
        imgui.push_id(q.id)
        local c = mod._row_cache and mod._row_cache[q.id]
        local is_recent = mod.highlight_recent and mod.newest_completed == q.id
        local is_locked = LOCKED_QUESTS[q.id] == true

        local prefix = is_recent and "* " or "  "
        local tier_col = nil
        local tier_name = nil
        if mod.show_quest_tiers ~= false and QD and QD.get_quest_tier then
            tier_name = QD.get_quest_tier(q.id)
        end
        if mod.show_quest_tiers ~= false and QD and QD.get_quest_tier_color then
            tier_col = QD.get_quest_tier_color(q.id)
        end
        local show_fan_suffix = (mod.show_quest_tiers ~= false) and QD and QD.show_fan_stars and QD.show_fan_stars(q.id)
        local raw_name = (QD and QD.strip_fan_markers_from_name and QD.strip_fan_markers_from_name(q.name))
            or q.name or "?"
        local label  = prefix .. raw_name
        local color  = is_locked and (QD and QD.get_locked_quest_color and QD.get_locked_quest_color() or COL_GREY)
                  or tier_col
                  or (is_recent and COL_HL or cat_color(q.category))

        if mod.show_quest_tiers ~= false and QD and QD.get_quest_tier and not mod._qt_color_logged then
            mod._qt_color_logged = mod._qt_color_logged or {}
        end
        if mod.show_quest_tiers ~= false and QD and QD.get_quest_tier and not (mod._qt_color_logged and mod._qt_color_logged[q.id]) then
            mod._qt_color_logged = mod._qt_color_logged or {}
            mod._qt_color_logged[q.id] = true
            local tier = tier_name or QD.get_quest_tier(q.id)
            local fan = (QD.is_fan_favorite and QD.is_fan_favorite(q.id)) and 1 or 0
            local reward = (QD.is_reward_quest and QD.is_reward_quest(q.id)) and 1 or 0
            mlog_boot(string.format("[QT][color] qid=%d tier=%s fan=%d reward=%d locked=%d",
                q.id, tostring(tier), fan, reward, is_locked and 1 or 0))
        end

        local open = imgui.tree_node("##qt" .. tostring(q.id))
        imgui.same_line()
        imgui.text_colored(label, color)
        if show_fan_suffix then
            imgui.same_line()
            local star_glyph = (QD.get_fan_star_glyph and QD.get_fan_star_glyph(q.id)) or "★"
            local star_col = QD.get_fan_star_color(q.id)
            imgui.text_colored(star_glyph, star_col)
        end

        mod._row_open_prev = mod._row_open_prev or {}
        local was_open = mod._row_open_prev[q.id] == true
        if open then
            mod._qt_last_expanded_qid = q.id
            if not was_open then
                if q.category == "Ongoing" then
                    mod._step_last_title = mod._step_last_title or {}
                    mod._step_last_title[q.id] = nil
                end
                if mod._refresh_one_row then
                    pcall(mod._refresh_one_row, q)
                    c = mod._row_cache and mod._row_cache[q.id]
                end
            end
            if not was_open and mod._log_quest_expand then pcall(mod._log_quest_expand, q, c) end
            local ok, err = pcall(function() _draw_row_body(q, c) end)
            imgui.tree_pop()
            if not ok then
                local ekey = tostring(q.id) .. tostring(err)
                if not _draw_row_logged[ekey] then
                    _draw_row_logged[ekey] = true
                    mlog_boot(string.format("[QT][ERROR] draw_row qid=%d | %s", q.id, tostring(err)))
                end
                imgui.text_colored("[ERR in this row â€” see log]", COL_RED)
            end
        end
        mod._row_open_prev[q.id] = open

        imgui.pop_id()
    end

    -- =========== RE FRAME ===========

    local _SAVE_GUARD_HOOKED = false

    local function _qt_arm_suppress_draw(secs, reason)
        local dur = (type(secs) == "number" and secs > 0) and secs or 2.0
        local now = os.clock()
        if reason == "execSave" then
            mod._qt_sdk_suppress_until = now + dur
            mod._qt_post_save_block_until = now + 1.0
            mod._qt_save_deferred_refresh_at = now + 0.5
            mlog_boot("[QT] sdk suppressed reason=execSave secs=" .. tostring(dur) .. " (overlay never blocked)")
            return
        end
        mod._qt_suppress_draw_until = now + dur
        mlog_boot("[QT] draw suppressed reason=" .. tostring(reason or "?") .. " secs=" .. tostring(dur))
    end

    local function _qt_tick_suppress_clear(now)
        if mod._qt_suppress_draw_until and now >= mod._qt_suppress_draw_until then
            mod._qt_suppress_draw_until = nil
        end
        if mod._qt_sdk_suppress_until and now >= mod._qt_sdk_suppress_until then
            mod._qt_sdk_suppress_until = nil
            mlog_boot("[QT] sdk suppress expired")
        end
    end

    local function _qt_install_save_guard_hooks()
        if _SAVE_GUARD_HOOKED then return end
        local tdef = sdk.find_type_definition("app.GuiManager")
        if tdef == nil then return end
        local n = 0
        pcall(function()
            for _, m in ipairs(tdef:get_methods()) do
                if m:get_name() == "execSave" then
                    local ok = pcall(function()
                        sdk.hook(m,
                            function(_args) _qt_arm_suppress_draw(2.0, "execSave") end,
                            function(ret)
                                mod._qt_save_completed_at = os.clock()
                                return ret
                            end)
                    end)
                    if ok then n = n + 1 end
                end
            end
        end)
        if n > 0 then
            _SAVE_GUARD_HOOKED = true
            mlog_boot("[QT] save guard hooks installed: " .. tostring(n))
        end
    end
    pcall(_qt_install_save_guard_hooks)

    local function _qt_is_true_load_gui()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if not gm then return false end
        local load_gui = false
        pcall(function()
            load_gui = gm:get_IsLoadGui() == true
        end)
        return load_gui
    end

    local function _qt_is_load_gui_pause()
        if _qt_is_true_load_gui() then return true end
        if mod._qt_is_draw_suppressed and mod._qt_is_draw_suppressed() then return true end
        return false
    end
    ctx._qt_is_load_gui_pause = _qt_is_load_gui_pause

    local function _qt_draw_quest_overlay()
        if _G._qt_frame_gen ~= _QT_FRAME_GEN then return end
        if mod._qt_shutdown then return end
        if not mod.show_window then
            if not mod._qt_skip_win_logged then
                mod._qt_skip_win_logged = true
                mlog_boot("[QT] window hidden (Show Window off — mod checkbox only)")
            end
            return
        end
        mod._qt_skip_win_logged = nil
        if not mod._game_ready then
            return
        end
        if not mod._qt_overlay_should_draw or not mod._qt_overlay_should_draw() then
            return
        end
        if mod._qt_overlay_log_sig then mod._qt_overlay_log_sig() end
        if mod._qt_overlay_before_window then mod._qt_overlay_before_window() end

        if _refresh_display_cache and not mod._qt_display_refreshed then
            mod._qt_display_refreshed = true
            pcall(_refresh_display_cache)
            if _apply_layout_coords_to_mod then pcall(_apply_layout_coords_to_mod) end
        end
        _apply_saved_window_once()

        if _imgui_vec2 and imgui.set_next_window_size_constraints then
            local vmin = _imgui_vec2(MIN_SAVE_WIN_W, MIN_SAVE_WIN_H)
            local vmax = _imgui_vec2(4096, 4096)
            pcall(imgui.set_next_window_size_constraints, vmin, vmax)
        end

        local _fnt = ensure_quest_tracker_ui_font()
        mod._qt_style_pops = 0
        local wa = tonumber(mod.win_alpha) or 1.0
        wa = math.max(0.0, math.min(1.0, wa))
        if wa < 0.995 then
            local ab = math.max(0, math.floor(wa * 255))
            local bg = ab * 0x1000000 + 0x00080808
            if pcall(imgui.push_style_color, 2, bg) then mod._qt_style_pops = mod._qt_style_pops + 1 end
            if imgui.Col and imgui.Col.WindowBg then
                if pcall(imgui.push_style_color, imgui.Col.WindowBg, bg) then
                    mod._qt_style_pops = mod._qt_style_pops + 1
                end
            end
        end

        -- Push font BEFORE begin_window so title bar matches Tools/list (not microscopic default).
        local _font_pushed = false
        if _fnt and pcall(imgui.push_font, _fnt) then _font_pushed = true end

        local draw = imgui.begin_window(MOD_NAME .. " [" .. MOD_VERSION .. "]", nil, 0)
        if not mod._win_draw_logged then
            mod._win_draw_logged = true
            mlog_boot("[QT] window draw visible=" .. tostring(draw))
        end

        local function _qt_pop_font_if_needed()
            if _font_pushed and _fnt then
                pcall(imgui.pop_font)
                _font_pushed = false
            end
        end
        local function _qt_pop_style_if_needed()
            for _ = 1, (mod._qt_style_pops or 0) do pcall(imgui.pop_style_color) end
            mod._qt_style_pops = 0
        end
        local function _qt_finish_window()
            Child.ensure_closed()
            if draw then pcall(imgui.end_window) end
            _qt_pop_font_if_needed()
            _qt_pop_style_if_needed()
        end

        local ok_body, err_body = pcall(function()
        if draw then
            if not mod._qt_frame1_layout_logged then
                mod._qt_frame1_layout_logged = true
                local ok_p, p = pcall(imgui.get_window_pos)
                local ok_s, s = pcall(imgui.get_window_size)
                local apx, apy = _qt_parse_vec2(p, -1, -1)
                local asw, ash = _qt_parse_vec2(s, -1, -1)
                mlog_boot(string.format(
                    "[QT] window actual frame1 pos=%.0f,%.0f size=%dx%d (intended %.0f,%.0f %dx%d)",
                    apx, apy, asw, ash,
                    mod.win_x or -1, mod.win_y or -1, mod.win_w or -1, mod.win_h or -1))
                if _qt_check_boot_layout_settled then
                    pcall(_qt_check_boot_layout_settled, asw, ash)
                end
            end
            pcall(function()
                if imgui.get_io then
                    local ok_io, io = pcall(imgui.get_io)
                    if ok_io and io and io.MouseDrawCursor ~= nil then io.MouseDrawCursor = true end
                end
            end)

            local ch
            local hint_n = mod._cached_wiki_hint_n or 0
            if hint_n < 5 then
                imgui.text_colored("Wiki data missing â€” reinstall mod data via Fluffy", 0xFF4444FF)
            end
            if mod._steps_module_ok == false then
                imgui.text_colored("Steps module missing â€” install quest_tracker_steps.lua (see FLUFFY_INSTALL.txt)", 0xFF4444FF)
            end

            if mod._qt_doze then
                imgui.text_colored("Fast-forwardâ€¦", 0xFF22FFFF); imgui.same_line()
                if imgui.button("Stop##ffstop") then
                    _set_time_scale(1.0)
                    mod._qt_doze = nil
                    mlog("[FF] stopped manually")
                end
            else
                imgui.text_colored(mod._cached_time_line or "Game time: ...", 0xFFAABBFF); imgui.same_line()
                if imgui.button("+3h") then _start_fast_forward(3) end
                imgui.same_line()
                if imgui.button("+6h") then _start_fast_forward(6) end
                imgui.same_line()
                if imgui.button("+8h") then _start_fast_forward(8) end
            end
            if MAP_API.last_msg and MAP_API.last_msg ~= "" then
                imgui.text_colored(MAP_API.last_msg, 0xFF88CC88)
            end

            if not mod._qt_draw_shell_logged then
                mod._qt_draw_shell_logged = true
                mlog_boot("[QT] draw shell enter")
            end

            if imgui.set_next_item_open and not mod._qt_tools_tree_inited then
                mod._qt_tools_tree_inited = true
                pcall(imgui.set_next_item_open, false, 4)
            end
            if imgui.tree_node("Tools##qttools") then
                if not mod._qt_doze then
                    imgui.text("Sort:"); imgui.same_line()
                    if imgui.push_item_width then pcall(imgui.push_item_width, 200) end
                    ch, mod.sort_mode = imgui.combo("##srt", mod.sort_mode, SORT_NAMES)
                    if imgui.pop_item_width then pcall(imgui.pop_item_width) end
                    if ch then pcall(rebuild); pcall(mod._qt_schedule_cache_refresh, "sort")
                        mod._last_win_save = os.clock(); mark_prefs_dirty() end
                    imgui.same_line()
                    ch, mod.highlight_recent = imgui.checkbox("Newest", mod.highlight_recent)
                    if ch then mod._last_win_save = os.clock(); mark_prefs_dirty() end
                end
                if imgui.button("Pin Available") then
                    if Map and Map.pin_all_available then Map.pin_all_available(true) end
                end
                imgui.same_line()
                if imgui.button("Pin Ongoing") then
                    if Map and Map.pin_all_current then Map.pin_all_current(true)
                    elseif Map and Map.pin_all_ongoing_all then Map.pin_all_ongoing_all(true) end
                end
                imgui.same_line()
                if imgui.button("Pin MAIN") then
                    if Map and Map.pin_all_ongoing then Map.pin_all_ongoing() end
                end
                imgui.same_line()
                if imgui.button("Clear pins") then pcall(clear_injected_markers) end
                ch, mod.auto_pin_journal = imgui.checkbox("Autopin MAIN", mod.auto_pin_journal ~= false)
                if ch then mod._last_win_save = os.clock(); mark_prefs_dirty() end
                imgui.same_line()
                ch, mod.auto_pin_ongoing = imgui.checkbox("Autopin Ongoing", mod.auto_pin_ongoing == true)
                if ch then
                    mod._last_autopin_tick = 0
                    mod._last_win_save = os.clock(); mark_prefs_dirty()
                    if Map and Map.run_autopin_if_enabled then pcall(Map.run_autopin_if_enabled) end
                end
                imgui.same_line()
                ch, mod.auto_pin_available = imgui.checkbox("Autopin Available", mod.auto_pin_available == true)
                if ch then
                    mod._last_autopin_tick = 0
                    mod._last_win_save = os.clock(); mark_prefs_dirty()
                    if Map and Map.run_autopin_if_enabled then pcall(Map.run_autopin_if_enabled) end
                end
                imgui.text_colored("Pin Ongoing = all Ongoing. Pin Available = Available only. MAIN = priority.", 0xFF888888)
                imgui.separator()
                imgui.text("Quest name colors")
                ch, mod.show_quest_tiers = imgui.checkbox("Show tier colors", mod.show_quest_tiers ~= false)
                if ch then mod._last_win_save = os.clock(); mark_prefs_dirty() end
                imgui.text_colored("Gold = Good reward", 0xFF00D7FF)
                imgui.text_colored("Green = Main story", 0xFF66FF66)
                imgui.text_colored("White = Normal side / ongoing / available", 0xFFFFFFFF)
                imgui.text_colored("Purple = Rare special", 0xFFAA00FF)
                imgui.text_colored("Cyan ★ = Fan favorite (after name)", 0xFFFFFF00)
                imgui.text_colored("Grey = Locked by you", COL_GREY)
                imgui.separator()
                imgui.text("Time")
                ch, mod.time_longer_days = imgui.checkbox("Longer days (before dark = half speed)", mod.time_longer_days == true)
                if ch then
                    mod._last_win_save = os.clock(); mark_prefs_dirty()
                    if TimeMod and TimeMod.on_toggle then pcall(TimeMod.on_toggle) end
                end
                ch, mod.time_faster_nights = imgui.checkbox("Faster nights (when dark = 4x speed)", mod.time_faster_nights == true)
                if ch then
                    mod._last_win_save = os.clock(); mark_prefs_dirty()
                    if TimeMod and TimeMod.on_toggle then pcall(TimeMod.on_toggle) end
                end
                ch, mod.time_pause = imgui.checkbox("Pause time", mod.time_pause == true)
                if ch then
                    mod._last_win_save = os.clock(); mark_prefs_dirty()
                    if TimeMod and TimeMod.on_toggle then pcall(TimeMod.on_toggle) end
                end
                imgui.text_colored("Watch In-game clock or HUD; faster nights when game is dark (8pm+)", 0xFF888888)
                if TimeMod and TimeMod.get_status_line then
                    local status, col = TimeMod.get_status_line()
                    if status then imgui.text_colored(status, col or 0xFF66FF66) end
                end
                imgui.same_line()
                if imgui.button("Save") then
                    save_prefs()
                    MAP_API.last_msg = "saved " .. os.date("%H:%M:%S")
                    mlog("[SAVE] manual save triggered")
                end
                if imgui.tree_node("Active pins##qttoolspins") then
                    local qname_for = {}
                    for _, q in ipairs(mod.quests or {}) do qname_for[q.id] = q.name end
                    local any = false
                    for qid, _ in pairs(MAP_API.pinned_pos or {}) do
                        any = true
                        imgui.text_colored((qname_for[qid] or ("Quest " .. qid)) .. ":", 0xFFFFCC66)
                    end
                    for qid in pairs(MAP_API.pinned_data or {}) do
                        if not (MAP_API.pinned_pos and MAP_API.pinned_pos[qid]) then
                            any = true
                            imgui.text_colored((qname_for[qid] or ("Quest " .. qid)) .. " (objective)", 0xFFAABBFF)
                        end
                    end
                    if not any then imgui.text("(no active pins)") end
                    if imgui.button("Clear all pins") then pcall(clear_injected_markers) end
                    imgui.tree_pop()
                end
                imgui.tree_pop()
            end

            local child_open = Child.begin()
            local ok_list, err_list = pcall(function()
            if not child_open then
                if not mod._qt_list_child_fail_logged then
                    mod._qt_list_child_fail_logged = true
                    mlog_boot("[QT] list child window failed to open")
                end
                return
            end
            if mod._qt_tab_scroll_reset then
                mod._qt_tab_scroll_reset = false
                if imgui.set_scroll_y then pcall(imgui.set_scroll_y, 0) end
            end
            local dlist = mod._draw_quest_list or {}
            if not mod._qt_list_draw_logged then
                mod._qt_list_draw_logged = true
                mlog_boot("[QT] list draw enter dlist=" .. tostring(#dlist))
            end
            imgui.separator()
            _qt_draw_tab_row()
            imgui.separator()

            for ri = 1, #dlist do
                local ok_row, err_row = pcall(draw_row, dlist[ri])
                if not ok_row and not mod._draw_row_fail_logged then
                    mod._draw_row_fail_logged = true
                    mlog_boot("[QT][draw] draw_row failed: " .. tostring(err_row))
                end
            end

            if not mod._qt_wrap_logged then
                mod._qt_wrap_logged = true
                mlog_boot(string.format("[QT][wrap] row_w=%.0f tab=%.0f win_w=%.0f",
                    mod._qt_row_width or -1, mod._qt_wrap_right_local or -1, mod.win_w or -1))
            end
            end)
            Child.end_child()
            if not ok_list then
                mlog_boot("[QT] list draw CRASH: " .. tostring(err_list))
            end

            local function _num(v)
                return type(v) == "number" and v or nil
            end
            local layout_now = os.clock()
            local ok_wp, a, b = pcall(imgui.get_window_pos)
            if ok_wp and (mod._qt_boot_apply_frames or 0) >= 1 and draw
                and _qt_layout_capture_allowed(layout_now) then
                local wpx, wpy = _num(a), _num(b)
                if wpx == nil and a ~= nil then pcall(function() wpx, wpy = a.x, a.y end) end
                if _qt_pos_capture_ok(wpx, wpy) then
                    local sx = _qt_layout_stage("win_x", wpx, layout_now)
                    local sy = _qt_layout_stage("win_y", wpy, layout_now)
                    if sx and sy and (mod.win_x ~= wpx or mod.win_y ~= wpy) then
                        mod.win_x, mod.win_y = wpx, wpy
                        if _sync_margin_from_viewport then pcall(_sync_margin_from_viewport) end
                        mod._last_win_save = layout_now
                        mark_prefs_dirty()
                        if not mod._win_pos_saved_logged then
                            mod._win_pos_saved_logged = true
                            mlog_boot(string.format("[QT] window position captured %.0f, %.0f", wpx, wpy))
                        end
                    end
                end
            end
            local ok_ws, aw, ah = pcall(imgui.get_window_size)
            if ok_ws and draw and _qt_layout_capture_allowed(layout_now) then
                local ww, wh = _num(aw), _num(ah)
                if ww == nil and aw ~= nil then pcall(function() ww, wh = aw.x, aw.y end) end
                if ww and wh and ww >= MIN_SAVE_WIN_W and wh >= MIN_SAVE_WIN_H then
                    if _clamp_layout_size then ww, wh = _clamp_layout_size(ww, wh) end
                    if _qt_size_delta_ok(ww, wh, layout_now) then
                        local sw = _qt_layout_stage("win_w", ww, layout_now)
                        local sh = _qt_layout_stage("win_h", wh, layout_now)
                        if sw and sh and (mod.win_w ~= ww or mod.win_h ~= wh) then
                            mod.win_w, mod.win_h = ww, wh
                            mod._last_win_save = layout_now
                            mark_prefs_dirty()
                        end
                    end
                end
            end
            if _G._qt_prefs_stub and not mod._prefs_stub_flushed
                and _qt_boot_save_allowed(layout_now)
                and mod.win_x and mod.win_y
                and mod.win_w and mod.win_w >= MIN_SAVE_WIN_W
                and mod.win_h and mod.win_h >= MIN_SAVE_WIN_H then
                mod._prefs_stub_flushed = true
                mod._last_win_save = os.clock()
                mark_prefs_dirty()
                mlog_boot(string.format("[QT] prefs stub — auto-saving layout %.0f,%.0f %dx%d",
                    mod.win_x, mod.win_y, mod.win_w, mod.win_h))
            end
        end
        end)

        _qt_finish_window()
        if not ok_body and not mod._qt_draw_body_err_logged then
            mod._qt_draw_body_err_logged = true
            mlog_boot("[QT][draw] window body CRASH: " .. tostring(err_body))
        end
    end


    re.on_frame(function()
        if _G._qt_frame_gen ~= _QT_FRAME_GEN then return end

        local now = os.clock()
        local was_ready = mod._game_ready
        if _check_game_ready then _check_game_ready() end
        if mod._qt_shutdown then return end

        if TimeMod and TimeMod.tick then pcall(TimeMod.tick) end

        if mod._game_ready and not was_ready then
            mod._qt_game_ready_at = now
            mod._qt_display_refreshed = false
            mod._win_apply_count = 0
            mod._win_capture_after = nil
            mod._qt_boot_layout_done = false
            mod._qt_boot_apply_frames = 0
            mod._qt_frame1_layout_logged = false
            mod._qt_child_deferred_logged = false
            mod._qt_list_child_fail_logged = false
            mod._win_draw_logged = false
            mod._qt_wrap_logged = false
            mod._qt_list_draw_logged = false
            mod._qt_last_logged_draw_n = nil
            mod._qt_draw_list_logged = false
            mod._qt_menu_draw_err_logged = false
            mod._qt_draw_body_err_logged = false
            mod._qt_draw_skip_menu_logged = false
            mod._qt_draw_shell_logged = false
        end
        _qt_tick_suppress_clear(now)
        if mod._qt_overlay_tick then mod._qt_overlay_tick() end
        if mod._game_ready then
            if _qt_is_load_gui_pause() then
                mod._qt_was_load_gui_pause = true
            else
                if mod._qt_was_load_gui_pause then
                    mod._qt_was_load_gui_pause = false
                    if mod._qt_schedule_cache_refresh then
                        pcall(mod._qt_schedule_cache_refresh, "load_gui_resume")
                    end
                end
                pcall(_qt_run_logic_tick, now)
                local dlist_n = #(mod._draw_quest_list or {})
                if mod._qt_last_logged_draw_n ~= dlist_n then
                    mod._qt_last_logged_draw_n = dlist_n
                    mlog_boot("[QT] draw_list count=" .. tostring(dlist_n))
                end
            end
        end

        -- Window drag: debounced prefs flush (0.5s after last layout change)
        if mod._game_ready and mod._prefs_dirty and mod._last_win_save
            and (now - mod._last_win_save) >= 0.5 and _qt_boot_save_allowed(now) then
            mod._last_prefs_flush = now
            mod._last_win_save = nil
            pcall(save_prefs)
        end

        if mod._qt_overlay_should_draw and mod._qt_overlay_should_draw() then
            qt_background_log_tick(now)
            if mod._journal_poll_on_frame then pcall(mod._journal_poll_on_frame, now) end
            if mod._journal_on_frame and mod.debug_logging then pcall(mod._journal_on_frame, now) end
            if mod._sniff_on_frame then pcall(mod._sniff_on_frame, now) end
            mod._qt_imgui_overlay_active = true
            pcall(_qt_draw_quest_overlay)
            mod._qt_imgui_overlay_active = false
        end
    end)

    -- REFramework settings tree only — never draw the floating quest window here.
    -- NOTE: imgui.begin_window MUST stay in on_frame (REF docs) — on_draw_ui is REF menu tree only.
    re.on_draw_ui(function()
        if not imgui.tree_node(MOD_NAME .. " [" .. MOD_VERSION .. "]") then return end
        local _menu_font_pushed = false
        local function _menu_finish()
            if _menu_font_pushed then pcall(imgui.pop_font); _menu_font_pushed = false end
            pcall(imgui.tree_pop)
        end
        local _menu_cw = (type(mod.win_w) == "number" and mod.win_w > 80) and (mod.win_w - 32)
            or (DEFAULT_QUEST_WIN_W - 32)
        local _menu_fnt = ensure_quest_tracker_ui_font(_menu_cw)
        if _menu_fnt and pcall(imgui.push_font, _menu_fnt) then _menu_font_pushed = true end
        local ok_menu, err_menu = pcall(function()
        local ch
        ch, mod.show_window = imgui.checkbox("Show Window", mod.show_window)
            if ch then
                mod._qt_skip_win_logged = nil
                mod._win_draw_logged = nil
                save_prefs()
            end
            ch, mod.show_overlay_on_map = imgui.checkbox("Show tracker on map", mod.show_overlay_on_map ~= false)
            if ch then save_prefs() end
            if imgui.button("Clear saved window position") then
                _clear_saved_window_position()
                mod._win_pos_saved_logged = nil
                mod._win_apply_count = 0
            end
            if imgui.button("Reset window layout") and _reset_window_layout then
                pcall(_reset_window_layout)
                mod._win_pos_saved_logged = nil
                mod._win_apply_count = 0
            end
            imgui.text("Search filter (applies to quest list below):")
            ch, mod.filter_text = imgui.input_text("##flt_menu", mod.filter_text)
            if ch then
                if mod._qt_refilter_draw_list then pcall(mod._qt_refilter_draw_list)
                else pcall(mod._qt_schedule_cache_refresh, "filter") end
            end
            ch, mod.label_pins = imgui.checkbox("Label map pins with quest name", mod.label_pins)
            if ch then mod._last_win_save = os.clock(); mark_prefs_dirty() end
            ch, mod.debug_logging = imgui.checkbox("Verbose debug (extra disk log — ON by default)", mod.debug_logging)
            if ch then mod._last_win_save = os.clock(); mark_prefs_dirty() end
            local ch_ds, ds_val = imgui.checkbox(
                "Deep Sniff TEMP (hooks log only — full dump on button / slow poll)", mod.deep_sniff == true)
            if ch_ds then
                mod.deep_sniff = (ds_val == true)
                mlog_boot(string.format("[QT][sniff] toggled deep_sniff=%s heavy=%s (v%s)",
                    mod.deep_sniff and "ON" or "OFF", mod.deep_sniff_heavy and "ON" or "OFF", MOD_VERSION))
                if mod.deep_sniff then
                    if mod._sniff_install then pcall(mod._sniff_install) end
                    if mod._journal_install_hooks then pcall(mod._journal_install_hooks) end
                    if Map and Map.resniff_map_ui then pcall(Map.resniff_map_ui) end
                else
                    mod.deep_sniff_heavy = false
                end
                mod._last_win_save = os.clock(); mark_prefs_dirty()
                pcall(save_prefs)
            end
            if mod.deep_sniff then
                ch, mod.deep_sniff_heavy = imgui.checkbox("  Heavy (slow poll — playable FPS)", mod.deep_sniff_heavy == true)
                if ch then
                    local st = mod.deep_sniff_heavy and "ON" or "OFF"
                    mlog(string.format("[QT][sniff] heavy mode %s", st))
                    if mlog_boot then mlog_boot(string.format("[QT][sniff] heavy mode %s (prefs)", st)) end
                    mod._last_win_save = os.clock(); mark_prefs_dirty()
                    pcall(save_prefs)
                end
                if imgui.button("Dump priority quest NOW") then
                    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
                    local pq = qlm and to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
                    if pq and pq > 0 and mod._sniff_dump_qid then
                        pcall(mod._sniff_dump_qid, pq, "manual")
                    else
                        mlog("[QT][sniff] manual dump — no priority qid (set one in journal)")
                    end
                end
                imgui.text_colored("Log: reframework/data/quest_tracker_log.txt — grep [QT][sniff] and [QT][hook]", 0xFF88CCFF)
            end
            local ch_fs, fs_new = imgui.slider_int("Quest window text size", mod.font_size, 18, 38)
            if fs_new ~= nil then
                mod.font_size = clamp_font_size(fs_new)
                mod._qt_font_cache_key = nil
            end
            if ch_fs then mod._last_win_save = os.clock(); mark_prefs_dirty() end
            local ch_a, a_new = imgui.slider_int("Window background %", math.floor((mod.win_alpha or 1) * 100), 0, 100)
            if a_new ~= nil then mod.win_alpha = math.max(0.0, math.min(1.0, a_new / 100.0)) end
            if ch_a then mod._last_win_save = os.clock(); mark_prefs_dirty() end
            imgui.text_colored("0% = most transparent panel (not true glass).", 0xFF666666)
            imgui.text_colored("Move or resize the quest window â€” position is remembered automatically.", 0xFF888888)
        imgui.text_colored(MAP_API.status, 0xFF888888)
        end)
        _menu_finish()
        if not ok_menu and not mod._qt_menu_draw_err_logged then
            mod._qt_menu_draw_err_logged = true
            mlog_boot("[QT][draw] menu CRASH: " .. tostring(err_menu))
        end
    end)

    mod._qt_window_installed = true
end

package.loaded["quest_tracker_window"] = M
return M
