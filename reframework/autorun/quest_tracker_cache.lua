-- quest_tracker_cache.lua — tiered refresh, row cache, logic tick (Lua 200-local headroom)
local M = package.loaded["quest_tracker_cache"]
if M then return M end
M = {}

function M.install(ctx)
    local mod = ctx.mod
    local mlog = ctx.mlog
    local mlog_boot = ctx.mlog_boot or mlog
    local QD = ctx.QD
    local TAB_NAMES = ctx.TAB_NAMES
    local BUNDLED_LOCKOUTS = ctx.BUNDLED_LOCKOUTS
    local QUEST_START_DAYS = ctx.QUEST_START_DAYS
    local QUEST_START_HOURS = ctx.QUEST_START_HOURS
    local MAP_API = ctx.MAP_API
    local gather = ctx.gather
    local rebuild = ctx.rebuild
    local matches_filter = ctx.matches_filter
    local resolve_meta = ctx.resolve_meta
    local init_map_api = ctx.init_map_api
    local run_autolock = ctx.run_autolock
    local save_prefs = ctx.save_prefs
    local qd_trigger = ctx.qd_trigger
    local qd_prereqs = ctx.qd_prereqs
    local qd_timing_note = ctx.qd_timing_note
    local qd_available_after = ctx.qd_available_after
    local qd_time_limit = ctx.qd_time_limit
    local qd_note = ctx.qd_note
    local qd_during_quest = ctx.qd_during_quest
    local qd_schedule = ctx.qd_schedule
    local is_must_before_feast = ctx.is_must_before_feast
    local _resolve_ongoing_step = ctx._resolve_ongoing_step
    local _is_flavor_text = ctx._is_flavor_text
    local _quest_log_info_fingerprint = ctx._quest_log_info_fingerprint
    local get_primary_secondary_cids = ctx.get_primary_secondary_cids
    local _get_quest_start_pos = ctx._get_quest_start_pos
    local get_all_giver_cids = ctx.get_all_giver_cids
    local _build_npc_rows_for_cache = ctx._build_npc_rows_for_cache
    local friendly_chara_name = ctx.friendly_chara_name
    local _resolve_cid_name = ctx._resolve_cid_name
    local _hours_until_window_start = ctx._hours_until_window_start
    local _get_game_clock_integers = ctx._get_game_clock_integers
    local _get_game_hour_sched = ctx._get_game_hour_sched
    local _format_game_time_line = ctx._format_game_time_line
    local _flush_pos_cache = ctx._flush_pos_cache
    local ensure_all_ids = ctx.ensure_all_ids
    local td = ctx.td
    local call_method = ctx.call_method
    local safe_call = ctx.safe_call
    local safe_get_field = ctx.safe_get_field
    local _guid_to_en_text = ctx._guid_to_en_text
    local iter_list = ctx.iter_list
    local iter_array = ctx.iter_array
    local to_int = ctx.to_int

    local QT_TIME_INTERVAL = ctx.QT_TIME_INTERVAL
    local QT_STATE_PROBE_INTERVAL = ctx.QT_STATE_PROBE_INTERVAL
    local QT_NPC_SCAN_INTERVAL = ctx.QT_NPC_SCAN_INTERVAL
    local QT_COMPLETION_SWEEP = ctx.QT_COMPLETION_SWEEP

    local QT_STEP_REFRESH_INTERVAL = ctx.QT_STEP_REFRESH_INTERVAL or 8.0
    local auto_pin_fn_ongoing   = ctx.auto_pin_fn_ongoing
    local auto_pin_fn_available = ctx.auto_pin_fn_available
    local run_autopin_if_enabled = ctx.run_autopin_if_enabled
    local QT_AUTOPIN_INTERVAL = 25

    local function _completion_sweep(qlm, progressing, acceptable, completed)
        local ALL_IDS = ensure_all_ids()
        local t2 = td("app.QuestLogManager")
        local m_end = t2 and t2:get_method("isQuestLogEnd(app.QuestDefine.ID)")
        if not m_end or not ALL_IDS then return 0 end
        local added = 0
        for qid in pairs(ALL_IDS) do
            if qid and qid >= 0 and not completed[qid] and not progressing[qid] and not acceptable[qid] then
                if call_method(m_end, qlm, qid) == true then
                    completed[qid] = true
                    added = added + 1
                end
            end
        end
        return added
    end

    local function _qt_fingerprint()
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if not qlm then return "no_qlm" end
        local parts = {}
        local pl = safe_call(qlm, "getProgressingQuestIds")
        if pl then
            local ids = {}
            iter_list(pl, function(q) local n = to_int(q); if n then ids[#ids + 1] = n end end)
            table.sort(ids)
            parts[#parts + 1] = "p:" .. table.concat(ids, ",")
        end
        local al = safe_call(qlm, "getAcceptableQuestList")
        if al then
            local ids = {}
            iter_list(al, function(q) local n = to_int(q); if n then ids[#ids + 1] = n end end)
            table.sort(ids)
            parts[#parts + 1] = "a:" .. table.concat(ids, ",")
        end
        local rec = safe_call(qlm, "getOrderedByUpdateQuestList")
        if rec ~= nil then
            local head = {}
            iter_array(rec, function(q, i)
                if i <= 5 then local n = to_int(q); if n then head[#head + 1] = n end end
            end)
            if #head == 0 then
                iter_list(rec, function(q, i)
                    if i <= 5 then local n = to_int(q); if n then head[#head + 1] = n end end
                end)
            end
            parts[#parts + 1] = "r:" .. table.concat(head, ",")
        end
        return table.concat(parts, "|")
    end

    local _STEP_FP_KEYS = {
        "QuestLogText", "GuideText", "CurrentLogText", "TaskLogText", "QuestGuideText",
        "CurrentTaskName", "QuestCurrentTaskName", "ActiveTaskName", "ObjectiveName",
    }

    local function _qt_step_fingerprint(qlm, progressing)
        if not qlm or not progressing then return "" end
        local ids = {}
        for qid in pairs(progressing) do ids[#ids + 1] = qid end
        table.sort(ids)
        local parts = {}
        for _, qid in ipairs(ids) do
            local vi = safe_call(qlm, "getQuestLog", qid)
            if vi then
                local bits = {}
                for _, key in ipairs(_STEP_FP_KEYS) do
                    local v = safe_get_field(vi, key)
                    if type(v) == "string" and #v > 0 then bits[#bits + 1] = v:sub(1, 48) end
                    if _guid_to_en_text then
                        local t = _guid_to_en_text(safe_get_field(vi, key .. "Id"))
                        if t and #t > 0 then bits[#bits + 1] = t:sub(1, 48) end
                    end
                end
                parts[#parts + 1] = qid .. ":" .. table.concat(bits, "/")
                if _quest_log_info_fingerprint then
                    local ok_fp, fp2 = pcall(_quest_log_info_fingerprint, qlm, qid)
                    if ok_fp and type(fp2) == "string" and fp2 ~= "" then
                        parts[#parts] = parts[#parts] .. "@" .. fp2
                    end
                end
            end
        end
        return table.concat(parts, "|")
    end

    local function _qt_show_quest_in_tab(q)
        local cat = TAB_NAMES[mod.tab]
        if cat == "Hidden" then return q.voided
        elseif cat == "All" then return not q.voided
        else return (q.category == cat) and not q.voided end
    end

    local function _build_row_static(qid, q)
        local s = { _cat = q.category }
        if q.category == "Available" then s.trig = qd_trigger(qid) end
        if QD and QD.get_chain_info then
            local ok_ci, ci = pcall(QD.get_chain_info, qid)
            if ok_ci and type(ci) == "table" and type(ci.quests) == "table" and #ci.quests > 1 then
                s.chain_info = ci
            end
        end
        s.prereqs = qd_prereqs(qid)
        s.timing_note = qd_timing_note(qid)
        s.available_after = qd_available_after(qid)
        s.lockout = BUNDLED_LOCKOUTS[qid]
        s.time_limit = qd_time_limit(qid)
        s.note = qd_note(qid)
        s.during = qd_during_quest(qid)
        s.summary = (q.category ~= "Ongoing") and q.summary or nil
        s.wiki_lines = nil
        if q.category ~= "Ongoing" and QD and QD.get_wiki_hint_lines then
            local ok_wh, wlines = pcall(QD.get_wiki_hint_lines, qid)
            if ok_wh and type(wlines) == "table" and #wlines > 0 then s.wiki_lines = wlines end
        end
        s.sched = qd_schedule(qid)
        return s
    end

    local function _qt_apply_static(c, qid, q)
        local st = mod._row_static[qid]
        if not st or st._cat ~= q.category then
            st = _build_row_static(qid, q)
            mod._row_static[qid] = st
        end
        for k, v in pairs(st) do
            if k ~= "_cat" then c[k] = v end
        end
    end

    local function _qt_patch_time_sensitive(c, qid)
        if c.time_limit and c._is_ongoing then
            local start_day = QUEST_START_DAYS[qid]
            local start_hr = QUEST_START_HOURS[qid] or 0
            local cur_day = mod._live_in_game_day or 0
            local cur_hr = mod._live_in_game_hour or 0
            c.timer_rem_h = nil
            if start_day then
                local elapsed_h = (cur_day - start_day) * 24 + (cur_hr - start_hr)
                c.timer_rem_h = c.time_limit * 24 - elapsed_h
            end
        end
        if c.sched and c._cat ~= "Completed" then
            local s, f = tonumber(c.sched.start), tonumber(c.sched.finish)
            local cur_h = mod._cached_sched_hour
            c.sched_in_win, c.sched_s, c.sched_f, c.sched_ff_h = nil, nil, nil, nil
            if s and f and cur_h then
                local in_win = (s > f) and (cur_h >= s or cur_h < f) or (cur_h >= s and cur_h < f)
                c.sched_in_win = in_win
                c.sched_s, c.sched_f = s, f
                if not in_win then c.sched_ff_h = _hours_until_window_start(cur_h, s, f) end
            end
        end
    end

    local function _qt_patch_npc_part(c, qid)
        if not c._givers then return end
        c.npc_rows = _build_npc_rows_for_cache(qid, c.ongoing_step_title, c._givers, c._want, mod._cached_sched_hour)
        c.missing_npc = nil
        if c._want and #c._want > 0 then
            local missing = {}
            for _, wn in ipairs(c._want) do
                local hit = false
                for _, gc in ipairs(c._givers or {}) do
                    local nm = friendly_chara_name(gc, qid, "alt") or _resolve_cid_name(gc)
                    if nm and nm:lower():find(wn, 1, true) then hit = true; break end
                end
                if not hit then missing[#missing + 1] = wn:sub(1, 1):upper() .. wn:sub(2) end
            end
            if #missing > 0 then c.missing_npc = table.concat(missing, ", ") end
        end
    end

    local function _qt_patch_all_time_rows()
        for qid, c in pairs(mod._row_cache or {}) do
            _qt_patch_time_sensitive(c, qid)
            _qt_patch_npc_part(c, qid)
        end
    end

    local _cache_build_fail_logged = {}

    local function _norm_line(text)
        if not text then return "" end
        return text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function _is_quest_name_line(text, qid)
        local qn = mod.name_cache and mod.name_cache[qid]
        if not qn or not text then return false end
        return _norm_line(text) == _norm_line(qn)
    end

    local function _qt_sanitize_ongoing_display(c, qid)
        if not c or not c._is_ongoing then return end
        if c.wiki_progress then return end
        local is_flavor = c.step_title and _is_flavor_text and _is_flavor_text(c.step_title, qid)
        local is_name = c.step_title and _is_quest_name_line(c.step_title, qid)
        if is_flavor or is_name then
            local intro = (is_flavor and c.step_title) or nil
            local guessed = nil
            if QD and QD.guess_step_from_hints then
                local ok_g, g = pcall(QD.guess_step_from_hints, qid, c.step_title or "")
                if ok_g then guessed = g end
            end
            if not guessed and QD and QD.get_fallback_step_title then
                local ok_f, g = pcall(QD.get_fallback_step_title, qid)
                if ok_f then guessed = g end
            end
            if guessed then
                if intro and not c.step_detail then c.step_detail = intro end
                c.step_title = guessed
                c.ongoing_step_title = guessed
                c.wiki_fallback = true
                c.step_from_game = false
                mod._step_field_src = mod._step_field_src or {}
                mod._step_field_src[qid] = "wiki_from_intro"
            elseif intro and not c.step_detail then
                c.step_detail = intro
                c.step_title = nil
                c.ongoing_step_title = nil
            end
        end
        if c.journal_lines then
            local clean = {}
            for _, jl in ipairs(c.journal_lines) do
                if jl ~= c.step_title and jl ~= c.step_detail
                    and not _is_quest_name_line(jl, qid)
                    and not (_is_flavor_text and _is_flavor_text(jl, qid)) then
                    clean[#clean + 1] = jl
                end
            end
            if #clean > 0 then c.journal_lines = clean else c.journal_lines = nil end
        end
        if not c.journal_lines and not c.tips and QD and QD.get_step_hints_for_title and c.ongoing_step_title then
            local ok_t, t = pcall(QD.get_step_hints_for_title, qid, c.ongoing_step_title)
            if ok_t and type(t) == "table" and #t > 0 then c.tips = t end
        end
    end

    local function _qt_find_quest(qid)
        for _, rq in ipairs(mod.quests or {}) do
            if rq.id == qid then return rq end
        end
        return nil
    end

    local function _build_row_cache(q, target_cache)
        local qid = q.id
        local c = { _cat = q.category, _is_ongoing = (q.category == "Ongoing") }
        _qt_apply_static(c, qid, q)
        c.before_milestone = (q.category ~= "Completed" and q.category ~= "Hidden")
            and is_must_before_feast(qid, q.name)
        c.feast_urgent = false
        if c.before_milestone and QD and QD.get_urgent then
            local ok_u, u = pcall(QD.get_urgent, qid)
            c.feast_urgent = ok_u and u == true
        end
        c.ongoing_step_title = nil
        if q.category == "Ongoing" then
            local qlm = sdk.get_managed_singleton("app.QuestLogManager")
            if qlm then resolve_meta(qlm, qid) end
            local ok_st, st, sd, sfg, wfb = pcall(_resolve_ongoing_step, qlm, qid)
            if ok_st then
                c.step_title = st
                c.step_detail = (sd and not _is_flavor_text(sd, qid) and sd ~= st) and sd or nil
                c.step_from_game = sfg
                c.wiki_fallback = wfb
                c.wiki_progress = mod._wiki_progress_flag and mod._wiki_progress_flag[qid] == true
                c.ongoing_step_title = st
            elseif not _cache_build_fail_logged[qid] then
                _cache_build_fail_logged[qid] = true
                mlog_boot("[QT][cache] resolve failed qid=" .. tostring(qid) .. " err=" .. tostring(st))
            end
            if (not c.step_title or c.step_title == (mod.name_cache and mod.name_cache[qid]))
                and QD and QD.get_wiki_journal_lines then
                local ok_jl, jl = pcall(QD.get_wiki_journal_lines, qid)
                if ok_jl and type(jl) == "table" and #jl > 0 then
                    c.step_title = jl[1]
                    c.ongoing_step_title = jl[1]
                    c.step_detail = (#jl > 1) and jl[2] or nil
                    c.journal_lines = jl
                    c.wiki_fallback = false
                    c.wiki_progress = false
                    c.step_from_game = true
                    mod._step_field_src = mod._step_field_src or {}
                    mod._step_field_src[qid] = "wiki_journal_lines"
                end
            end
            c.tips = nil
            if QD and QD.get_step_hints_for_title and c.ongoing_step_title then
                local ok_t, t = pcall(QD.get_step_hints_for_title, qid, c.ongoing_step_title)
                if ok_t and type(t) == "table" and #t > 0 then c.tips = t end
            end
            if not c.journal_lines and not c.tips and QD and QD.get_fallback_step_hints then
                local ok_f, t = pcall(QD.get_fallback_step_hints, qid)
                if ok_f and type(t) == "table" and #t > 0 then c.tips = t end
            end
            if not c.journal_lines and not c.step_title and QD and QD.get_wiki_hint_lines then
                local ok_wh, wlines = pcall(QD.get_wiki_hint_lines, qid)
                if ok_wh and type(wlines) == "table" and #wlines > 0 then c.wiki_lines = wlines end
            end
            _qt_sanitize_ongoing_display(c, qid)
        end
        local ok_tail, err_tail = pcall(function()
            c.pri_c, c.alt_c = get_primary_secondary_cids(qid, c.ongoing_step_title)
            if type(_get_quest_start_pos) == "function" then
                c.tp_x, c.tp_y, c.tp_z = _get_quest_start_pos(qid, c.pri_c)
            end
            c._givers, c._want = nil, nil
            if q.category ~= "Completed" then
                local givers, want = get_all_giver_cids(qid, c.ongoing_step_title)
                c._givers, c._want = givers, want
                _qt_patch_npc_part(c, qid)
            end
            _qt_patch_time_sensitive(c, qid)
        end)
        if not ok_tail then
            error("tail qid=" .. tostring(qid) .. " " .. tostring(err_tail))
        end
        target_cache[qid] = c
        return c
    end

    function ctx._refresh_one_row(q)
        if not q or not q.id then return end
        mod._row_cache = mod._row_cache or {}
        local ok, err = pcall(_build_row_cache, q, mod._row_cache)
        if not ok and not _cache_build_fail_logged[q.id] then
            _cache_build_fail_logged[q.id] = true
            mlog_boot("[QT][cache] refresh_one qid=" .. q.id .. " err=" .. tostring(err))
        end
    end

    function ctx._qt_schedule_cache_refresh()
        mod._qt_pending_cache_refresh = true
    end

    function ctx._qt_refresh_row_caches()
        local tab_name = TAB_NAMES[mod.tab] or "?"
        mlog_boot(string.format("[QT][cache] refresh enter quests=%d tab=%s",
            #(mod.quests or {}), tab_name))
        local prev_cache = mod._row_cache or {}
        local prev_draw = mod._draw_quest_list or {}
        local new_cache = {}
        local new_draw_list = {}
        local built, failed = 0, 0
        for _, q in ipairs(mod.quests or {}) do
            if _qt_show_quest_in_tab(q) then
                local ok_match, want = pcall(matches_filter, q)
                if ok_match and want then
                    local ok_build, err = pcall(_build_row_cache, q, new_cache)
                    if ok_build then
                        built = built + 1
                        new_draw_list[#new_draw_list + 1] = q
                    else
                        failed = failed + 1
                        local qid = q.id
                        if not _cache_build_fail_logged[qid] then
                            _cache_build_fail_logged[qid] = true
                            mlog_boot("[QT][cache] build failed qid=" .. tostring(qid) .. " err=" .. tostring(err))
                        end
                        if prev_cache[qid] then
                            new_cache[qid] = prev_cache[qid]
                            built = built + 1
                            new_draw_list[#new_draw_list + 1] = q
                        end
                    end
                end
            end
        end
        if built > 0 then
            mod._row_cache = new_cache
            mod._draw_quest_list = new_draw_list
            if not mod._qt_draw_list_logged and #new_draw_list > 0 then
                mod._qt_draw_list_logged = true
                local qids = {}
                for _, q in ipairs(new_draw_list) do qids[#qids + 1] = tostring(q.id) end
                mlog_boot("[QT] first draw qids: " .. table.concat(qids, ","))
            end
            mlog_boot(string.format("[QT][cache] refresh OK rows=%d built=%d draw=%d fail=%d",
                #(mod.quests or {}), built, #new_draw_list, failed))
        elseif next(prev_cache) then
            mlog_boot(string.format("[QT][cache] WARN refresh built=0 fail=%d — kept previous cache draw=%d",
                failed, #prev_draw))
        else
            mod._row_cache = new_cache
            mod._draw_quest_list = new_draw_list
            mlog_boot(string.format("[QT][cache] WARN refresh built=0 draw=%d fail=%d (row cache empty)",
                #new_draw_list, failed))
        end
    end

    function ctx._qt_force_refresh()
        mod._logic_force = true
        mod._last_state_probe = 0
        mod._last_npc_tick = 0
        mod._qt_fp = nil
        mod._npc_scan_cache = {}
    end

    function ctx._qt_run_logic_tick(now)
        if mod._qt_shutdown or not mod._game_ready then return end
        if mod._qt_pending_cache_refresh then
            mod._qt_pending_cache_refresh = false
            pcall(ctx._qt_refresh_row_caches)
        end
        local forced = mod._logic_force == true
        if forced then mod._logic_force = false end

        if not mod._map_init_done then
            local ok = pcall(init_map_api)
            if ok and MAP_API and MAP_API.ready then mod._map_init_done = true end
        end

        if forced or (now - (mod._last_time_check or 0)) >= QT_TIME_INTERVAL then
            mod._last_time_check = now
            local d, h, mi = _get_game_clock_integers()
            local clock_changed = d ~= nil and (
                d ~= mod._live_in_game_day or h ~= mod._live_in_game_hour or mi ~= mod._live_in_game_minute)
            if forced or mod._cached_time_line == nil or clock_changed then
                mod._live_in_game_day = d
                mod._live_in_game_hour = h
                mod._live_in_game_minute = mi
                mod._cached_sched_hour = _get_game_hour_sched()
                mod._cached_time_line = _format_game_time_line()
                if mod._row_cache and next(mod._row_cache) then
                    pcall(_qt_patch_all_time_rows)
                end
            end
        end

        if forced or (now - (mod._last_step_refresh or 0)) >= QT_STEP_REFRESH_INTERVAL then
            mod._last_step_refresh = now
            local qlm = sdk.get_managed_singleton("app.QuestLogManager")
            if qlm and mod.progressing_ids and next(mod.progressing_ids) then
                local pqid = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
                if pqid and pqid > 0 and pqid ~= mod._qt_priority_qid then
                    mod._qt_priority_qid = pqid
                    local nm = mod.name_cache and mod.name_cache[pqid] or ("Quest " .. tostring(pqid))
                    mlog(string.format("[QT][priority] map pin qid=%d %s — refresh step", pqid, nm))
                    mod._step_last_title = mod._step_last_title or {}
                    mod._step_last_title[pqid] = nil
                    local pq = _qt_find_quest(pqid)
                    if pq then pcall(ctx._refresh_one_row, pq)
                    else pcall(ctx._qt_refresh_row_caches) end
                end
                local gm = sdk.get_managed_singleton("app.GuiManager")
                local jqid = gm and to_int(safe_get_field(gm, "_TargetQuestId"))
                if jqid and jqid > 0 and jqid ~= mod._qt_journal_qid then
                    mod._qt_journal_qid = jqid
                    local nm = mod.name_cache and mod.name_cache[jqid] or ("Quest " .. tostring(jqid))
                    mlog(string.format("[QT][journal] UI focus qid=%d %s — refresh step", jqid, nm))
                    mod._step_last_title = mod._step_last_title or {}
                    mod._step_last_title[jqid] = nil
                    local jq = _qt_find_quest(jqid)
                    if jq then pcall(ctx._refresh_one_row, jq)
                    else pcall(ctx._qt_refresh_row_caches) end
                end
                local sfp = _qt_step_fingerprint(qlm, mod.progressing_ids)
                if sfp ~= mod._qt_sfp then
                    mod._qt_sfp = sfp
                    mlog("[QT] step fingerprint changed — refreshing ongoing steps")
                    pcall(ctx._qt_refresh_row_caches)
                end
            end
        end

        if (mod.auto_pin_ongoing or mod.auto_pin_available) and run_autopin_if_enabled then
            if (now - (mod._last_autopin_tick or 0)) >= QT_AUTOPIN_INTERVAL then
                mod._last_autopin_tick = now
                pcall(run_autopin_if_enabled)
            end
        end

        if forced or (now - (mod._last_state_probe or 0)) >= QT_STATE_PROBE_INTERVAL then
            mod._last_state_probe = now
            local fp = _qt_fingerprint()
            local qlm = sdk.get_managed_singleton("app.QuestLogManager")
            local sfp = qlm and _qt_step_fingerprint(qlm, mod.progressing_ids) or ""
            if forced or fp ~= mod._qt_fp or not mod.quests or #mod.quests == 0 then
                mod._qt_fp = fp
                mod._qt_sfp = sfp
                _flush_pos_cache()
                local ok, err = pcall(gather)
                if not ok then mlog_boot("[QT][ERROR] gather crashed: " .. tostring(err)) end
                ok, err = pcall(rebuild)
                if not ok then mlog_boot("[QT][ERROR] rebuild crashed: " .. tostring(err)) end
                mod.last_refresh = now
                pcall(ctx._qt_refresh_row_caches)
                if ctx.audit_wiki_gaps_for_ongoing then pcall(ctx.audit_wiki_gaps_for_ongoing) end
            else
                mod._qt_skip_rebuilds = (mod._qt_skip_rebuilds or 0) + 1
                if sfp ~= mod._qt_sfp then
                    mod._qt_sfp = sfp
                    mlog("[QT] step text changed — refreshing ongoing steps")
                    pcall(ctx._qt_refresh_row_caches)
                elseif not mod._row_cache or not next(mod._row_cache) then
                    pcall(ctx._qt_refresh_row_caches)
                end
            end
        end

        if forced or (now - (mod._last_npc_tick or 0)) >= QT_NPC_SCAN_INTERVAL then
            mod._last_npc_tick = now
            mod._npc_scan_cache = {}
            _flush_pos_cache()
            if mod._row_cache and next(mod._row_cache) then
                for qid, c in pairs(mod._row_cache) do
                    if c._givers then
                        local q = nil
                        for _, rq in ipairs(mod.quests or {}) do if rq.id == qid then q = rq; break end end
                        if q and q.category ~= "Completed" then
                            local givers, want = get_all_giver_cids(qid, c.ongoing_step_title)
                            c._givers, c._want = givers, want
                            _qt_patch_npc_part(c, qid)
                            c.pri_c, c.alt_c = get_primary_secondary_cids(qid, c.ongoing_step_title)
                            if type(_get_quest_start_pos) == "function" then
                                c.tp_x, c.tp_y, c.tp_z = _get_quest_start_pos(qid, c.pri_c)
                            end
                        end
                    end
                end
            end
        end

        if (now - (mod._last_completion_sweep or 0)) >= QT_COMPLETION_SWEEP then
            mod._last_completion_sweep = now
            local qlm = sdk.get_managed_singleton("app.QuestLogManager")
            if qlm then
                local added = _completion_sweep(qlm, mod.progressing_ids or {}, mod.acceptable_ids or {}, mod.completed_ids or {})
                if added > 0 then
                    mlog("[QT] completion sweep: +" .. added .. " newly completed")
                    mod._logic_force = true
                    mod._last_state_probe = 0
                end
            end
        end

        local boot_ok = not mod._qt_boot_layout_at or (now - mod._qt_boot_layout_at) >= 2.0
        if not mod._qt_shutdown and boot_ok and mod._prefs_dirty and (now - (mod._last_prefs_flush or 0)) > 5 then
            mod._last_prefs_flush = now
            pcall(save_prefs)
        end
        if (now - (mod.last_autolock or 0)) >= 300 then
            mod.last_autolock = now
            pcall(run_autolock)
        end
    end

    function ctx.qt_background_log_tick(now)
        if now - (mod._qt_bg_log_t or 0) < 55 then return end
        mod._qt_bg_log_t = now
        local n_pin = 0
        if MAP_API then
            local seen = {}
            for qid in pairs(MAP_API.pinned_pos or {}) do if not seen[qid] then seen[qid] = true; n_pin = n_pin + 1 end end
            for qid in pairs(MAP_API.pinned_data or {}) do if not seen[qid] then seen[qid] = true; n_pin = n_pin + 1 end end
        end
        local n_lock, n_hide = 0, 0
        for _, v in pairs(ctx.LOCKED_QUESTS) do if v then n_lock = n_lock + 1 end end
        for _, v in pairs(ctx.VOIDED_QUESTS) do if v then n_hide = n_hide + 1 end end
        mlog_boot(string.format(
            "[QT] tick: day=%s wiki=%s locked=%d user_hidden=%d map_pin_quests=%d qlm=%s state_probe=%.0fs skip_rebuilds=%d rows=%d",
            tostring(mod._live_in_game_day or "?"),
            QD and "on" or "off",
            n_lock,
            n_hide,
            n_pin,
            mod._qt_qlm_ready_logged and "ok" or "waiting",
            mod.refresh_interval or QT_STATE_PROBE_INTERVAL,
            mod._qt_skip_rebuilds or 0,
            #(mod.quests or {})))
    end
end

package.loaded["quest_tracker_cache"] = M
return M
