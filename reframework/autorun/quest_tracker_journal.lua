-- quest_tracker_journal.lua — always-on journal capture (hooks + deep SDK harvest)
if package.loaded["quest_tracker_journal"] then return package.loaded["quest_tracker_journal"] end
local M = {}

local _hooked_addrs = {}
local _hooks_done = false
local _last_harvest_t = {}
local HARVEST_COOLDOWN = 1.0
local HARVEST_COOLDOWN_DEBUG = 0.35
local FRAME_POLL_INTERVAL = 1.25

function M.install(ctx)
    local mod = ctx.mod
    local mlog = ctx.mlog
    local mlog_boot = ctx.mlog_boot or mlog
    local safe_get_field = ctx.safe_get_field
    local safe_call = ctx.safe_call
    local iter_list = ctx.iter_list
    local to_int = ctx.to_int
    local td = ctx.td
    local get_quest_resource = ctx.get_quest_resource
    local _guid_to_en_text = ctx._guid_to_en_text
    local _text_from_hex32 = ctx._text_from_hex32
    local _is_flavor_text = ctx._is_flavor_text
    local init_english_lookup = ctx.init_english_lookup
    local QD = ctx.QD

    local function _quest_name(qid)
        return (mod.name_cache and mod.name_cache[qid]) or nil
    end

    local function _norm_line(text)
        if not text then return "" end
        return text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function _is_quest_name_line(text, qid)
        local qn = _quest_name(qid)
        if not qn or not text then return false end
        return _norm_line(text) == _norm_line(qn)
    end

    local function _line_score(text, qid)
        if not text or #text < 8 then return -9999 end
        if _is_quest_name_line(text, qid) then return -9999 end
        if _is_flavor_text(text, qid) then return -800 end
        local low = text:lower()
        if low:find("you have encountered") then return -700 end
        local score = #text
        if low:find("riddle") or low:find("heard") or low:find("answer")
            or low:find("tasked") or low:find("provide") or low:find("retrieve") then
            score = score + 250
        end
        return score
    end

    local function _is_bad_title(text, qid)
        return _line_score(text, qid) < 0
    end

    local function _active_journal_qid()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if gm then
            local tq = to_int(safe_get_field(gm, "_TargetQuestId")) or to_int(safe_get_field(gm, "TargetQuestId"))
            if tq and tq > 0 then return tq end
        end
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if qlm then
            local pq = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
            if pq and pq > 0 then return pq end
        end
        return nil
    end

    local function _ingest_line(qid, text, src)
        if not text or _is_bad_title(text, qid) then return end
        mod._journal_step_cache = mod._journal_step_cache or {}
        local c = mod._journal_step_cache[qid] or { lines = {}, t = os.clock() }
        c.lines = c.lines or {}
        local low = text:lower()
        for _, ex in ipairs(c.lines) do
            if ex == text or ex:lower() == low then return end
        end
        c.lines[#c.lines + 1] = text
        local best_t, best_d, best_sc = nil, nil, -9999
        for _, line in ipairs(c.lines) do
            local sc = _line_score(line, qid)
            if sc > best_sc then best_t, best_sc = line, sc end
        end
        for _, line in ipairs(c.lines) do
            if line ~= best_t and #line > 30 and _line_score(line, qid) > 0 then
                if not best_d or #line > #best_d then best_d = line end
            end
        end
        if best_t then
            c.text = best_t
            c.detail = best_d
            c.t = os.clock()
            c.src = src or "message"
            mod._journal_step_cache[qid] = c
            mod._step_field_src = mod._step_field_src or {}
            mod._step_field_src[qid] = "journal_msg"
            if mod.debug_logging then
                mlog(string.format("[QT][journal] MSG qid=%d: %s", qid, best_t:sub(1, 90)))
            end
        end
    end

    local function _retval_to_string(retval)
        if retval == nil then return nil end
        if type(retval) == "string" then return retval end
        local s = nil
        pcall(function()
            local o = sdk.to_managed_object(retval)
            if o then
                local ok, ts = pcall(function() return o:call("ToString") end)
                if ok and type(ts) == "string" and #ts > 0 then s = ts end
            end
        end)
        return s
    end

    local function _install_message_hooks()
        local hooked = 0
        local function hook_ret(m, label)
            if not m then return end
            local addr = nil
            pcall(function() addr = m:get_address() end)
            if addr and _hooked_addrs[addr] then return end
            if addr then _hooked_addrs[addr] = true end
            local ok = pcall(function()
                sdk.hook(m, nil, function(retval)
                    local qid = _active_journal_qid()
                    if qid and qid > 0 then
                        local s = _retval_to_string(retval)
                        if s then _ingest_line(qid, s, label) end
                    end
                    return retval
                end)
            end)
            if ok then hooked = hooked + 1 end
        end
        local mm = _td("app.MessageManager")
        if mm then
            for _, mn in ipairs({ "getMessage", "GetMessage", "get_Message", "Get_Message" }) do
                hook_ret(mm:get_method(mn), "MessageManager." .. mn)
            end
        end
        local vmsg = _td("via.gui.message")
        if vmsg then
            for _, sig in ipairs({ "get(System.Guid)", "get(System.Guid, via.Language)" }) do
                hook_ret(vmsg:get_method(sig), "via.gui.message." .. sig)
            end
        end
        if hooked > 0 then
            mlog(string.format("[QT][journal] message hooks: %d", hooked))
        end
    end

    local function _td(name)
        if td then return td(name) end
        return sdk.find_type_definition(name)
    end

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

    local function _text_from_any(v, qid)
        if v == nil then return nil end
        if type(v) == "string" then
            if #v == 32 or #v == 36 then
                local hx = _text_from_hex32 and _text_from_hex32(v)
                if hx and not _is_flavor_text(hx, qid) then return hx end
            end
            if #v > 3 and not _is_flavor_text(v, qid) then return v end
            return nil
        end
        local gt = _guid_to_en_text and _guid_to_en_text(v)
        if gt and #gt > 3 and not _is_flavor_text(gt, qid) then return gt end
        return nil
    end

    local function _harvest_object(obj, qid, out, depth)
        if obj == nil or depth > 4 then return end
        local ok, tdef = pcall(function() return obj:get_type_definition() end)
        if not ok or not tdef then return end
        for _, f in ipairs(tdef:get_fields()) do
            local ok2, v = pcall(function() return f:get_data(obj) end)
            if ok2 then
                local t = _text_from_any(v, qid)
                if t then out[#out + 1] = { text = t, src = f:get_name() } end
            end
        end
        local methods = nil
        pcall(function() methods = tdef:get_methods() end)
        if methods then
            for _, m in ipairs(methods) do
                local mn = m:get_name()
                if mn:find("^get_") or mn:find("^Get") or mn:find("^is") then
                    local ok3, v = pcall(function() return obj:call(mn) end)
                    if ok3 then
                        local t = _text_from_any(v, qid)
                        if t then out[#out + 1] = { text = t, src = mn } end
                    end
                end
            end
        end
    end

    local function _task_cleared(task)
        for _, key in ipairs({ "_IsClear", "IsClear", "_IsComplete", "IsComplete", "<IsClear>k__BackingField" }) do
            if safe_get_field(task, key) == true then return true end
        end
        for _, mn in ipairs({ "get_IsClear", "get_IsComplete" }) do
            if safe_call(task, mn) == true then return true end
        end
        return false
    end

    local function _walk_tasks(task_list, qid, steps, depth)
        depth = depth or 0
        if task_list == nil or depth > 10 then return end
        iter_list(task_list, function(task)
            local title, detail = nil, nil
            local blob = {}
            _harvest_object(task, qid, blob, 0)
            for _, b in ipairs(blob) do
                if not title then title = b.text
                elseif not detail and b.text ~= title and #b.text > #title then detail = b.text
                elseif #b.text > 20 and (not detail or #b.text > #detail) then detail = b.text end
            end
            if title then
                steps[#steps + 1] = { title = title, detail = detail, cleared = _task_cleared(task) }
            end
            for _, nk in ipairs({ "_NextTaskList", "NextTaskList", "_ChildTaskList", "ChildTaskList" }) do
                local nxt = safe_get_field(task, nk) or safe_call(task, "get_NextTaskList") or safe_call(task, "get_ChildTaskList")
                _walk_tasks(nxt, qid, steps, depth + 1)
            end
        end)
    end

    local function _pick_current_step(steps, qid)
        local best_t, best_d, best_sc = nil, nil, -9999
        for i = 1, #steps do
            local s = steps[i]
            if s.title then
                local sc = _line_score(s.title, qid)
                if not s.cleared and sc > best_sc then
                    best_t, best_d, best_sc = s.title, s.detail, sc
                end
            end
        end
        if best_t and best_sc > 0 then return best_t, best_d end
        for i = 1, #steps do
            local s = steps[i]
            if s.title then
                local sc = _line_score(s.title, qid)
                if sc > best_sc then best_t, best_d, best_sc = s.title, s.detail, sc end
            end
        end
        if best_t and best_sc > 0 then return best_t, best_d end
        return nil, nil
    end

    local function _apply_wiki_journal_fallback(qid)
        if not QD or not QD.get_wiki_journal_lines then return false end
        local ok, lines = pcall(QD.get_wiki_journal_lines, qid)
        if not ok or type(lines) ~= "table" or #lines == 0 then return false end
        mod._journal_step_cache = mod._journal_step_cache or {}
        mod._journal_step_cache[qid] = {
            text = lines[1],
            detail = (#lines > 1) and lines[2] or nil,
            lines = lines,
            t = os.clock(),
            src = "wiki_journal_lines",
        }
        mod._step_field_src = mod._step_field_src or {}
        mod._step_field_src[qid] = "wiki_journal_lines"
        if mod.debug_logging then
            mlog(string.format("[QT][journal] wiki lines qid=%d title=%s", qid, lines[1]:sub(1, 80)))
        end
        return true
    end

    function M.harvest(_qlm, _qid)
        -- v3.0.63+: steps come from progress-first resolver (quest_tracker_steps.lua).
        -- Deep SDK/guid harvest disabled — caused via.gui.message crashes and wrong intro text.
        return false
    end

    local function _refresh_qid(qid)
        if mod._refresh_one_row and mod.quests then
            for _, rq in ipairs(mod.quests) do
                if rq.id == qid then pcall(mod._refresh_one_row, rq); return end
            end
        end
        if mod._qt_refresh_row_caches then pcall(mod._qt_refresh_row_caches) end
    end

    local _evt_debounce = 0
    local _frame_last = 0

    local function _on_journal_event()
        local now = os.clock()
        if (now - _evt_debounce) < 2.0 then return end
        _evt_debounce = now
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if not qlm then return end
        local qid = nil
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if gm then
            qid = to_int(safe_get_field(gm, "_TargetQuestId")) or to_int(safe_get_field(gm, "TargetQuestId"))
        end
        if not qid or qid <= 0 then
            qid = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
        end
        if qid and qid > 0 then
            mlog_boot(string.format("[QT][journal] hook fired qid=%d (refresh only, no guid harvest)", qid))
            _refresh_qid(qid)
        end
    end

    local _JOURNAL_EVENT_METHODS = {
        ["app.QuestLogManager"] = {
            "setCurrentDestination", "SetCurrentDestination",
            "setCurrentQuestLog", "SetCurrentQuestLog",
            "SetPriorityQuest", "setPriorityQuest",
            "OnSelectQuest", "onSelectQuest",
        },
        ["app.GuiManager"] = {
            "setQuestLogInfo", "SetQuestLogInfo",
            "SelectQuestLog", "selectQuestLog",
            "onSelectQuest", "OpenQuestLog", "openQuestLog",
        },
    }

    local function _name_wants_hook(name)
        local low = name:lower()
        if low:find("^get") or low:find("^is") or low:find("^add_") or low:find("^remove_") then return false end
        return low == "set_targetquestid" or low:find("setcurrentdestination")
            or low:find("onquestlogtaskupdate") or low:find("setcurrentquestlog")
    end

    local function _hook_scan_type(type_name, cap)
        local tdef = _td(type_name)
        if not tdef then return 0, "" end
        local methods = nil
        pcall(function() methods = tdef:get_methods() end)
        if not methods then return 0, "" end
        local n, sample = 0, {}
        for _, m in ipairs(methods) do
            if n >= (cap or 24) then break end
            local mn = m:get_name()
            if _name_wants_hook(mn) then
                sample[#sample + 1] = mn
                local dedup_key = type_name .. "::" .. mn
                if not _hooked_addrs[dedup_key] then
                    _hooked_addrs[dedup_key] = true
                    local ok = pcall(function()
                        sdk.hook(m,
                            function(_args) end,
                            function(ret)
                                pcall(_on_journal_event)
                                return ret
                            end)
                    end)
                    if ok then n = n + 1 end
                end
            end
        end
        return n, table.concat(sample, ", "):sub(1, 200)
    end

    function M.ensure_hooks()
        if _hooks_done then return end
        _hooks_done = true
        local total = 0
        local notes = {}
        for tn, _ in pairs(_JOURNAL_EVENT_METHODS) do
            local n, samp = _hook_scan_type(tn, 24)
            total = total + n
            if samp ~= "" then notes[#notes + 1] = tn .. ": " .. samp end
        end
        mlog_boot(string.format("[QT][journal] hooks installed: %d", total))
        if #notes > 0 then
            mlog_boot("[QT][journal] methods: " .. table.concat(notes, " | "))
        end
    end

    function M.on_frame(_now)
        -- Harvest disabled; journal hooks only fire on quest selection events.
    end

    mod._journal_harvest = M.harvest
    mod._journal_ensure_hooks = M.ensure_hooks
    mod._journal_on_frame = M.on_frame
end

package.loaded["quest_tracker_journal"] = M
return M
