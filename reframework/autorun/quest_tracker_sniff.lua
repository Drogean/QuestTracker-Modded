-- quest_tracker_sniff.lua — TEMP dev hooks: dump quest/journal APIs (Heavy = slow poll)
local M = {}

local _hooks_installed = false
local _hook_count = 0
local _last_poll = 0
local _last_heavy = 0
local _last_pqid = nil
local _dump_cooldown = {}
local _perf_dump_count = 0
local _perf_last_log = 0
local _heavy_poll_n = 0

local POLL_INTERVAL = 2.0
local HEAVY_INTERVAL = 0.4  -- heavy poll ~2-3/sec (playable FPS)
local COOLDOWN_S = 0.35

local METHOD_PAT = {
    "Quest", "Log", "Task", "Priority", "Dest", "Select", "Guide", "Update",
    "Current", "Focus", "Target", "Journal", "Catalog", "Progress", "Objective",
    "Marker", "Navi", "Display", "Setup", "Open", "Close", "Change", "Set",
}

local FIELD_PAT = {
    "Quest", "Log", "Task", "Priority", "Dest", "Select", "Guide", "Current",
    "Focus", "Target", "Journal", "Catalog", "Progress", "Objective", "Active",
    "Navi", "Display", "Summary", "Text", "Message", "Name", "Title",
}

local TYPE_CANDIDATES = {
    "app.QuestLogManager",
    "app.GuiManager",
    "app.QuestManager",
    "app.QuestLog",
    "app.QuestLogResource",
    "app.QuestTask",
    "app.QuestDefine",
}

function M.install(ctx)
    local mod = ctx.mod
    local mlog = ctx.mlog
    local safe_get_field = ctx.safe_get_field
    local safe_call = ctx.safe_call
    local iter_list = ctx.iter_list
    local to_int = ctx.to_int
    local td = ctx.td
    local get_quest_resource = ctx.get_quest_resource
    local _guid_to_en_text = ctx._guid_to_en_text
    local _get_live_quest_step = ctx._get_live_quest_step
    local _text_blobs_for_step_match = ctx._text_blobs_for_step_match
    local _resolve_ongoing_step = ctx._resolve_ongoing_step
    local _text_from_dest = ctx._text_from_dest

    local function _iter_managed_list(lst, fn)
        if lst == nil then return end
        local sz = 0
        pcall(function() sz = lst:get_size() end)
        if not sz or sz == 0 then pcall(function() sz = lst:get_Count() end) end
        if not sz or sz == 0 then return end
        for i = 0, sz - 1 do
            local d = nil
            pcall(function() d = lst:get_element(i) end)
            if d == nil then pcall(function() d = lst:call("get_Item", i) end) end
            if d ~= nil then fn(d, i) end
        end
    end

    local function _name_matches(name, patterns)
        for _, p in ipairs(patterns) do
            if name:find(p, 1, true) then return true end
        end
        return false
    end

    local function _fmt_val(v, depth)
        depth = depth or 0
        local t = type(v)
        if t == "string" then
            if #v > 160 then return string.format('"%s…" (%d)', v:sub(1, 160), #v) end
            return string.format('"%s"', v)
        end
        if t == "number" or t == "boolean" then return tostring(v) end
        if t == "userdata" and _guid_to_en_text then
            local gt = _guid_to_en_text(v)
            if gt then return string.format('guid→"%s"', gt:sub(1, 120)) end
        end
        if t == "userdata" and depth < 1 then
            local ok, nm = pcall(function() return v:get_type_definition():get_full_name() end)
            if ok and nm then return "<" .. nm .. ">" end
            return "<userdata>"
        end
        return nil
    end

    local function _log_fields(obj, label, max_n)
        if obj == nil then
            mlog(string.format("[QT][sniff] %s = nil", label))
            return
        end
        local ok, tdef = pcall(function() return obj:get_type_definition() end)
        if not ok or not tdef then return end
        mlog(string.format("[QT][sniff] === %s (%s) ===", label, tdef:get_full_name()))
        local n = 0
        for _, f in ipairs(tdef:get_fields()) do
            local fn = f:get_name()
            if _name_matches(fn, FIELD_PAT) then
                local ok2, v = pcall(function() return f:get_data(obj) end)
                if ok2 then
                    local fs = _fmt_val(v, 0)
                    if fs then
                        n = n + 1
                        mlog(string.format("[QT][sniff]   %s.%s = %s", label, fn, fs))
                        if n >= (max_n or 40) then
                            mlog("[QT][sniff]   … field cap reached")
                            break
                        end
                    end
                end
            end
        end
        if n == 0 then mlog("[QT][sniff]   (no matching string/number fields)") end
    end

    local function _task_title(task)
        if not task then return nil end
        for _, key in ipairs({
            "TaskName", "Name", "Title", "LogText", "ObjectiveName", "GuideText", "Message", "Text",
            "LogMessageId", "TitleId", "<LogMessageId>k__BackingField", "<TitleId>k__BackingField",
        }) do
            local v = safe_get_field(task, key)
            if type(v) == "string" and v ~= "" then return v, key end
            if _guid_to_en_text then
                local gt = _guid_to_en_text(v)
                if gt and gt ~= "" then return gt, key .. ":guid" end
            end
        end
        for _, mn in ipairs({
            "get_TaskName", "get_Name", "get_Title", "get_LogText", "get_GuideText",
            "get_LogMessageId", "get_TitleId", "get_MessageId",
        }) do
            local ok, v = pcall(function() return task:call(mn) end)
            if ok then
                if type(v) == "string" and v ~= "" then return v, mn end
                if _guid_to_en_text then
                    local gt = _guid_to_en_text(v)
                    if gt and gt ~= "" then return gt, mn .. ":guid" end
                end
            end
        end
        return nil, nil
    end

    local function _task_flags(task)
        local bits = {}
        for _, key in ipairs({
            "_IsActive", "IsActive", "_IsCurrent", "IsCurrent", "_IsClear", "IsClear",
            "_IsComplete", "IsComplete", "_State", "State", "_Status", "Status",
        }) do
            local v = safe_get_field(task, key)
            if v ~= nil then bits[#bits + 1] = key .. "=" .. tostring(v) end
        end
        return table.concat(bits, " ")
    end

    local _walk_task_count = 0
    local function _walk_tasks(task_list, label, depth, idx_path)
        depth = depth or 0
        idx_path = idx_path or "0"
        local heavy = mod.deep_sniff_heavy == true
        local max_depth = heavy and 4 or 8
        local max_tasks = heavy and 12 or 40
        if task_list == nil or depth > max_depth then return end
        if _walk_task_count >= max_tasks then return end
        iter_list(task_list, function(task, idx)
            if _walk_task_count >= max_tasks then return end
            _walk_task_count = _walk_task_count + 1
            local path = label .. "[" .. tostring(idx) .. "]"
            if depth > 0 then path = idx_path .. ">" .. path end
            local title, src = _task_title(task)
            if not title and _guid_to_en_text then
                local ok_sc, sc = pcall(function()
                    local ok2, tdef = pcall(function() return task:get_type_definition() end)
                    if not ok2 or not tdef then return nil end
                    for _, f in ipairs(tdef:get_fields()) do
                        local fn = f:get_name()
                        if fn:find("Id") or fn:find("Msg") or fn:find("Log") or fn:find("Text") then
                            local ok3, v = pcall(function() return f:get_data(task) end)
                            if ok3 then
                                local gt = _guid_to_en_text(v)
                                if gt and #gt > 3 then return gt, fn .. ":guid" end
                            end
                        end
                    end
                    return nil
                end)
                if ok_sc and type(sc) == "string" then title, src = sc, "field_scan" end
            end
            local flags = _task_flags(task)
            mlog(string.format("[QT][sniff]   task %s title=%s (%s) %s",
                path, title or "(none)", src or "-", flags))
            if not title and mod.deep_sniff then
                local ok2, tdef = pcall(function() return task:get_type_definition() end)
                if ok2 and tdef then
                    local dn = 0
                    for _, f in ipairs(tdef:get_fields()) do
                        if dn >= 20 then break end
                        local fn = f:get_name()
                        if fn:find("Id") or fn:find("Msg") or fn:find("Log") or fn:find("Text") or fn:find("Task") then
                            dn = dn + 1
                            local ok3, v = pcall(function() return f:get_data(task) end)
                            if ok3 then
                                local fs = _fmt_val(v, 0)
                                local gt = (v ~= nil and _guid_to_en_text) and _guid_to_en_text(v) or nil
                                mlog(string.format("[QT][taskdump] %s.%s = %s%s",
                                    path, fn, fs or "?", gt and (" → " .. gt:sub(1, 60)) or ""))
                            end
                        end
                    end
                end
            end
            for _, nk in ipairs({ "_NextTaskList", "NextTaskList", "_ChildTaskList", "ChildTaskList" }) do
                local nxt = safe_get_field(task, nk) or safe_call(task, "get_NextTaskList") or safe_call(task, "get_ChildTaskList")
                if nxt then _walk_tasks(nxt, nk, depth + 1, path) end
            end
        end)
    end

    local function _dict_entry(dict, qid)
        if not dict then return nil end
        local entry = nil
        pcall(function() entry = dict[qid] end)
        if not entry then
            pcall(function()
                if dict.get_Item then entry = dict:call("get_Item", qid) end
            end)
        end
        return entry
    end

    local function _can_dump(key)
        local now = os.clock()
        local last = _dump_cooldown[key] or 0
        if (now - last) < COOLDOWN_S then return false end
        _dump_cooldown[key] = now
        return true
    end

    function ctx.sniff_dump_qid(qid, reason)
        if not mod.deep_sniff or not qid or qid <= 0 then return end
        local key = tostring(qid) .. "|" .. (reason or "?")
        local skip_cd = (reason == "manual" or reason == "expand")
        if not skip_cd and not _can_dump(key) then return end
        _perf_dump_count = _perf_dump_count + 1
        _walk_task_count = 0

        local field_cap = (mod.deep_sniff_heavy == true) and 15 or 45

        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if not qlm then
            mlog("[QT][sniff] dump qid=" .. qid .. " reason=" .. (reason or "?") .. " — QLM nil")
            return
        end

        mlog(string.format("[QT][sniff] ######## DUMP qid=%d reason=%s ########", qid, reason or "?"))
        _log_fields(qlm, "QuestLogManager", field_cap)

        local pq = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
        if pq then mlog("[QT][sniff] _CurrentDestinationTargetQuestID=" .. tostring(pq)) end

        local vi = safe_call(qlm, "getQuestLog", qid)
        _log_fields(vi, "getQuestLog(" .. qid .. ")", field_cap)

        local dict = safe_get_field(qlm, "_QuestLogInfoDict")
        if dict then
            local entry = _dict_entry(dict, qid)
            if entry then
                _log_fields(entry, "QuestLogInfoDict[" .. qid .. "]", field_cap)
                local ti = to_int(safe_get_field(entry, "<CurrentTaskIndex>k__BackingField"))
                if ti ~= nil then mlog("[QT][sniff]   InfoDict.CurrentTaskIndex=" .. tostring(ti)) end
                if _text_from_dest then
                    _iter_managed_list(safe_get_field(entry, "_CurrentDestinations"), function(dest, i)
                        local t = _text_from_dest(dest, qid)
                        mlog(string.format("[QT][sniff]   InfoDict.dest[%d] text=%s", i, t or "(none)"))
                    end)
                end
            else
                mlog("[QT][sniff] QuestLogInfoDict has no entry for qid=" .. qid)
            end
        else
            mlog("[QT][sniff] _QuestLogInfoDict missing on QLM")
        end

        local res = get_quest_resource and get_quest_resource(qlm, qid) or nil
        if res then
            _log_fields(res, "QuestLogResource", math.min(field_cap, 30))
            mlog("[QT][sniff] --- task trees qid=" .. qid .. " ---")
            for _, src_name in ipairs({ "_FirstTaskList", "_CurrentTaskList", "_TaskList", "_TaskLogList" }) do
                local lst = safe_get_field(res, src_name) or safe_call(res, "get_" .. src_name:sub(2))
                if lst then
                    mlog("[QT][sniff] from resource " .. src_name)
                    _walk_tasks(lst, src_name, 0, "")
                end
            end
        else
            mlog("[QT][sniff] no QuestLogResource for qid=" .. qid)
        end

        if _get_live_quest_step then
            local t, d = _get_live_quest_step(qlm, qid)
            mlog(string.format("[QT][sniff] resolver live step=%s detail=%s",
                tostring(t), d and d:sub(1, 80) or "(none)"))
        end
        if _resolve_ongoing_step then
            local st, sd, fg, wf = _resolve_ongoing_step(qlm, qid)
            mlog(string.format("[QT][sniff] resolver final step=%s from_game=%s wiki_fb=%s",
                tostring(st), tostring(fg), tostring(wf)))
        end
        if _text_blobs_for_step_match then
            for i, blob in ipairs(_text_blobs_for_step_match(qlm, qid)) do
                if i <= 8 then
                    mlog(string.format("[QT][sniff] blob[%d]=%s", i, blob:sub(1, 140)))
                end
            end
        end

        local gm = sdk.get_managed_singleton("app.GuiManager")
        if gm then _log_fields(gm, "GuiManager", math.min(field_cap, 25)) end
        mlog("[QT][sniff] ######## END qid=" .. qid .. " ########")
    end

    local function _hook_method(tdef, method, type_label)
        local name = method:get_name()
        if not _name_matches(name, METHOD_PAT) then return false end
        local addr = nil
        pcall(function() addr = method:get_address() end)
        local dedup_key = addr or (type_label .. "::" .. name)
        if ctx._sniff_hooked_addrs and ctx._sniff_hooked_addrs[dedup_key] then return false end
        ctx._sniff_hooked_addrs = ctx._sniff_hooked_addrs or {}
        ctx._sniff_hooked_addrs[dedup_key] = true

        local ok = pcall(function()
            sdk.hook(method,
                function(args)
                    if not mod.deep_sniff then return end
                    local arg_bits = {}
                    for i = 3, 6 do
                        pcall(function()
                            local n = sdk.to_int64(args[i])
                            if n and n > 0 and n < 100000 then
                                arg_bits[#arg_bits + 1] = "a" .. (i - 2) .. "=" .. tostring(n)
                            end
                        end)
                    end
                    mlog(string.format("[QT][hook] %s:%s(%s)", type_label, name, table.concat(arg_bits, " ")))
                end,
                function(r) return r end)
        end)
        if ok then
            _hook_count = _hook_count + 1
            return true
        end
        return false
    end

    local function _add_ui_type_guesses()
        for a = 401, 409 do
            TYPE_CANDIDATES[#TYPE_CANDIDATES + 1] = string.format("app.ui0404%02d", a - 400)
        end
        for a = 501, 509 do
            TYPE_CANDIDATES[#TYPE_CANDIDATES + 1] = string.format("app.ui0405%02d", a - 500)
        end
        for a = 601, 609 do
            TYPE_CANDIDATES[#TYPE_CANDIDATES + 1] = string.format("app.ui0406%02d", a - 600)
        end
    end

    function ctx.sniff_install_hooks()
        if _hooks_installed then return _hook_count end
        _add_ui_type_guesses()
        local types_hit = 0
        for _, tn in ipairs(TYPE_CANDIDATES) do
            local t = td and td(tn) or sdk.find_type_definition(tn)
            if t then
                types_hit = types_hit + 1
                for _, m in ipairs(t:get_methods()) do
                    _hook_method(t, m, tn)
                end
            end
        end
        _hooks_installed = true
        mlog(string.format("[QT][sniff] hooks installed: %d methods on %d types (leave Deep Sniff on while testing journal)",
            _hook_count, types_hit))
        return _hook_count
    end

    -- Journal select hooks — installed lazily when quest menu is open (not at mod load).
    local _journal_hooks_installed = false
    local _JOURNAL_QLM_METHODS = {
        "setCurrentDestination", "SetCurrentDestination",
        "setCurrentQuestLog", "SetCurrentQuestLog",
        "SetPriorityQuest", "setPriorityQuest",
        "OnSelectQuest", "onSelectQuest",
        "selectQuest", "setSelectQuest",
    }
    local _JOURNAL_GM_METHODS = {
        "setQuestLogInfo", "SetQuestLogInfo",
        "SelectQuestLog", "selectQuestLog",
        "onSelectQuest", "OpenQuestLog", "openQuestLog",
    }
    local _JOURNAL_EXTRA_METHODS = {
        "get_CurrentTaskText", "get_CurrentGuideText", "get_CurrentObjectiveText",
        "get_TaskText", "get_GuideText", "get_CurrentLog", "get_CurrentLogText",
        "get_CurrentTask", "get_LogText", "get_TaskLog", "get_LogMessage", "get_ObjectiveText",
        "get_QuestLogText", "get_ActiveTaskName", "get_CurrentTaskName",
    }

    local function _jhook_grab_text(qlm, qid)
        if not qlm or not qid or qid <= 0 then return nil end
        local vi = safe_call(qlm, "getQuestLog", qid)
        if not vi then return nil end
        for _, mn in ipairs(_JOURNAL_EXTRA_METHODS) do
            local ok2, v = pcall(function() return vi:call(mn) end)
            if ok2 then
                local text = nil
                if type(v) == "string" and #v > 3 then
                    text = v
                elseif v ~= nil then
                    local ok3, gt = pcall(function()
                        if _guid_to_en_text then return _guid_to_en_text(v) end
                    end)
                    if ok3 and type(gt) == "string" and #gt > 3 then text = gt end
                end
                if text then
                    if mod.debug_logging then
                        mlog(string.format("[QT][jhook] %s=%s", mn, text:sub(1, 80)))
                    end
                    return text
                end
            end
        end
        return nil
    end

    local _jhook_last_fire = 0
    local mlog_boot = ctx.mlog_boot or mlog

    local function _jhook_on_fire()
        local now = os.clock()
        if (now - _jhook_last_fire) < 2.0 then return end
        _jhook_last_fire = now
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if not qlm then return end
        local pq = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
        if not pq or pq <= 0 then return end
        if mod._refresh_one_row and mod.quests then
            for _, rq in ipairs(mod.quests) do
                if rq.id == pq then pcall(mod._refresh_one_row, rq); break end
            end
        end
    end

    local function _jhook_name_wants(name)
        local low = name:lower()
        if low:find("^get") or low:find("^is") or low:find("^add_") or low:find("^remove_") then return false end
        return low == "set_targetquestid" or low:find("setcurrentdestination")
            or low:find("onquestlogtaskupdate")
    end

    local function _jhook_scan_type(type_name, cap)
        local tdef = (td and td(type_name)) or sdk.find_type_definition(type_name)
        if not tdef then return 0 end
        local methods = nil
        pcall(function() methods = tdef:get_methods() end)
        if not methods then return 0 end
        local n = 0
        ctx._sniff_hooked_addrs = ctx._sniff_hooked_addrs or {}
        for _, m in ipairs(methods) do
            if n >= (cap or 20) then break end
            local mn = m:get_name()
            if _jhook_name_wants(mn) then
                local dedup_key = type_name .. "::" .. mn
                if not ctx._sniff_hooked_addrs[dedup_key] then
                    ctx._sniff_hooked_addrs[dedup_key] = true
                    local ok = pcall(function()
                        sdk.hook(m,
                            function(_args) end,
                            function(retval) pcall(_jhook_on_fire); return retval end)
                    end)
                    if ok then n = n + 1 end
                end
            end
        end
        return n
    end

    function ctx.install_journal_hooks()
        if _journal_hooks_installed then return end
        _journal_hooks_installed = true
        local ok, n = pcall(function()
            return _jhook_scan_type("app.QuestLogManager", 20)
                + _jhook_scan_type("app.GuiManager", 20)
        end)
        if ok then
            mlog_boot(string.format("[QT][jhook] hooks installed: %d", n or 0))
        else
            mlog_boot("[QT][jhook] hooks FAILED: " .. tostring(n))
        end
    end

    local _last_poll_qid = nil
    local _last_poll_grab = 0
    local _last_menu_qid = nil
    local _last_boot_log = {}

    local function _sphinx_quest(qid)
        if qid == 20200 then return true end
        local nm = mod.name_cache and mod.name_cache[qid]
        if not nm then return false end
        local low = nm:lower()
        return low:find("sphinx") or low:find("game of wits") or low:find("riddle")
    end

    local function _boot_throttle(key, interval)
        local t = _last_boot_log[key] or 0
        if (os.clock() - t) < (interval or 2.0) then return false end
        _last_boot_log[key] = os.clock()
        return true
    end

    function ctx.journal_poll_on_frame(now)
        if mod._qt_shutdown then return end
        if (now - _last_poll_grab) < 0.5 then return end
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if not qlm then return end
        local menu_qid = nil
        if gm then
            menu_qid = to_int(safe_get_field(gm, "_TargetQuestId"))
                or to_int(safe_get_field(gm, "TargetQuestId"))
        end
        local qid = menu_qid
        if not qid or qid <= 0 then
            qid = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
        end
        if menu_qid and menu_qid > 0 and menu_qid ~= _last_menu_qid then
            _last_menu_qid = menu_qid
            local nm = mod.name_cache and mod.name_cache[menu_qid] or "?"
            mlog_boot(string.format("[QT][journal] in-game log selected qid=%d %s%s",
                menu_qid, nm, _sphinx_quest(menu_qid) and " [SPHINX]" or ""))
            if mod._refresh_one_row and mod.quests then
                for _, rq in ipairs(mod.quests) do
                    if rq.id == menu_qid then
                        pcall(mod._refresh_one_row, rq)
                        local c = mod._row_cache and mod._row_cache[menu_qid]
                        local fld = mod._step_field_src and mod._step_field_src[menu_qid]
                        if c and (c.wiki_fallback or fld == "wiki_fallback_key" or fld == "wiki_scraped") then
                            pcall(mod._refresh_one_row, rq)
                        end
                        break
                    end
                end
            end
        end
        if not qid or qid <= 0 then return end
        local wait = (qid == _last_poll_qid) and 1.5 or 0.5
        if (now - _last_poll_grab) < wait then return end
        _last_poll_qid = qid
        _last_poll_grab = now
        if mod._journal_ensure_hooks then pcall(mod._journal_ensure_hooks) end
        pcall(ctx.install_journal_hooks)
        local done = nil
        if mod._quest_progress_done_count then
            local ok_d, d = pcall(mod._quest_progress_done_count, qlm, qid)
            if ok_d then done = d end
        end
        local sphinx = _sphinx_quest(qid)
        if sphinx or _boot_throttle("poll_" .. qid, sphinx and 4.0 or 20.0) then
            mlog_boot(string.format("[QT][poll] qid=%d%s done=%s menu=%s",
                qid, sphinx and " SPHINX" or "", done ~= nil and tostring(done) or "?", tostring(menu_qid)))
        end
        if done ~= nil then
            mod._qt_last_done = mod._qt_last_done or {}
            if mod._qt_last_done[qid] ~= done and mod._refresh_one_row and mod.quests then
                mod._qt_last_done[qid] = done
                for _, rq in ipairs(mod.quests or {}) do
                    if rq.id == qid then pcall(mod._refresh_one_row, rq); break end
                end
            end
        end
    end

    function ctx.sniff_on_frame(now)
        if mod._qt_shutdown then return end
        if not mod.deep_sniff then return end
        if not _hooks_installed then pcall(ctx.sniff_install_hooks) end

        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if not qlm then return end

        local pqid = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
        if pqid and pqid > 0 and pqid ~= _last_pqid then
            _last_pqid = pqid
            local nm = mod.name_cache and mod.name_cache[pqid] or "?"
            mlog(string.format("[QT][sniff] priority changed → qid=%d %s", pqid, nm))
        end

        if mod.debug_logging and (now - _perf_last_log) >= 1.0 then
            if mod.deep_sniff_heavy then
                mlog(string.format("[QT][sniff] perf hooks=%d dumps_last_sec=%d", _hook_count, _perf_dump_count))
                _perf_dump_count = 0
            else
                mlog(string.format("[QT][sniff] perf hooks=%d", _hook_count))
            end
            _perf_last_log = now
        end

        if mod.deep_sniff_heavy ~= true then return end

        if (now - _last_heavy) < HEAVY_INTERVAL then return end
        _last_heavy = now

        if pqid and pqid > 0 then
            _heavy_poll_n = _heavy_poll_n + 1
            if _heavy_poll_n == 1 or (_heavy_poll_n % 5) == 0 then
                mlog(string.format("[QT][sniff] heavy_poll qid=%d tick=%d", pqid, _heavy_poll_n))
            end
            pcall(ctx.sniff_dump_qid, pqid, "heavy_poll")
        elseif mod.progressing_ids then
            local n = 0
            for qid in pairs(mod.progressing_ids) do
                n = n + 1
                if n <= 1 then
                    pcall(ctx.sniff_dump_qid, qid, "heavy_ongoing")
                end
            end
        end
    end
end

return M
