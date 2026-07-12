-- quest_tracker_steps.lua — quest step resolution (kept out of main chunk local limit)
local M = package.loaded["quest_tracker_steps"]
if M then return M end
M = {}

local TASK_WALK_MAX_DEPTH = 32
local _step_fail_logged = {}
local _step_probe_done = {}

function M.reset()
    for k in pairs(_step_fail_logged) do _step_fail_logged[k] = nil end
    for k in pairs(_step_probe_done) do _step_probe_done[k] = nil end
end

function M.install(ctx)
  local mod = ctx.mod
  local mlog = ctx.mlog
  local QD = ctx.QD
  local safe_get_field = ctx.safe_get_field
  local safe_call = ctx.safe_call
  local safe_dict_get = ctx.safe_dict_get
  local iter_list = ctx.iter_list
  local get_quest_resource = ctx.get_quest_resource
  local _guid_to_en_text = ctx._guid_to_en_text
  local _read_text_field = ctx._read_text_field
  local _name_for_qid = ctx._name_for_qid
  local resolve_meta = ctx.resolve_meta
  local _text_from_hex32 = ctx._text_from_hex32
  local to_int = ctx.to_int or function(x)
    if type(x) == "number" then return math.floor(x) end
    if type(x) ~= "userdata" and type(x) ~= "table" then return nil end
    local ok, n = pcall(function() return x:call("ToInt32") end)
    if ok and type(n) == "number" then return n end
    ok, n = pcall(function() return x.value__ end)
    if ok and type(n) == "number" then return n end
    return nil
  end

local function _task_status_num(task)
    for _, key in ipairs({ "_State", "State", "_Status", "Status", "_TaskState", "TaskState", "_ProgressState", "ProgressState" }) do
        local v = safe_get_field(task, key)
        if type(v) == "number" then return v end
    end
    for _, mn in ipairs({ "get_State", "get_Status", "get_TaskState", "get_ProgressState" }) do
        local ok, v = pcall(function() return task:call(mn) end)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

local function _task_is_active(task)
    for _, key in ipairs({
        "_IsActive", "IsActive", "_IsCurrent", "IsCurrent", "_IsProgress", "IsProgress",
        "<IsActive>k__BackingField", "<IsCurrent>k__BackingField", "<IsProgress>k__BackingField",
        "_LogState", "LogState",
    }) do
        if safe_get_field(task, key) == true then return true end
    end
    for _, mn in ipairs({ "get_IsActive", "get_IsCurrent", "get_IsProgress", "get_LogState", "getIsActive" }) do
        if safe_call(task, mn) == true then return true end
    end
    local st = _task_status_num(task)
    if st == 1 then return true end
    return false
end

local function _task_is_cleared(task)
    if _task_is_active(task) then return false end
    for _, key in ipairs({ "_IsClear", "IsClear", "_IsComplete", "IsComplete", "_IsDone", "IsDone" }) do
        if safe_get_field(task, key) == true then return true end
    end
    for _, mn in ipairs({ "get_IsClear", "get_IsComplete", "get_IsDone", "isClear", "get_IsDone" }) do
        local ok, v = pcall(function() return task:call(mn) end)
        if ok and v == true then return true end
    end
    local st = _task_status_num(task)
    if type(st) == "number" and st >= 2 then return true end
    return false
end

local _TASK_STRING_KEYS = {
    "TaskName", "Name", "Title", "LogText", "TaskLogText", "ObjectiveName",
    "Caption", "Message", "Text", "ObjectiveText", "GuideText", "LogMessage",
}
local _TASK_GUID_KEYS = {
    "TaskNameId", "NameId", "TitleId", "LogTextId", "TaskTitleId", "ObjectiveNameId",
    "CaptionId", "MessageId", "TextId", "ObjectiveTextId", "GuideTextId", "LogMessageId",
    "_TaskNameId", "_LogTextId", "_TitleId", "_MessageId", "LogId", "TaskLogId",
    "<LogMessageId>k__BackingField", "<TitleId>k__BackingField", "<TaskLogId>k__BackingField",
    "<LogId>k__BackingField", "<MessageId>k__BackingField", "<TaskNameId>k__BackingField",
    "<NameId>k__BackingField", "<CaptionId>k__BackingField", "<ObjectiveTextId>k__BackingField",
    "<GuideTextId>k__BackingField", "<LogTextId>k__BackingField",
}
local _TASK_GUID_METHODS = {
    "get_LogMessageId", "get_TitleId", "get_TaskLogId", "get_LogId", "get_MessageId",
    "get_ObjectiveTextId", "get_GuideTextId", "get_TaskNameId", "get_CaptionId",
    "get_NameId", "get_LogTextId", "get_TextId", "get_TaskTitleId",
}
local _TASK_DETAIL_KEYS = {
    "TaskSummary", "Summary", "Description", "TaskDescription", "LogDetail", "TaskLogDetail",
    "TaskDetail", "Detail", "ObjectiveDetail", "GuideDetail",
}
local _TASK_DETAIL_GUID = {
    "TaskSummaryId", "SummaryId", "DescriptionId", "TaskDescriptionId", "DetailId", "LogDetailId",
    "<SummaryId>k__BackingField", "<DescriptionId>k__BackingField", "<DetailId>k__BackingField",
    "<LogDetailId>k__BackingField", "<TaskSummaryId>k__BackingField",
}
local _TASK_DETAIL_GUID_METHODS = {
    "get_SummaryId", "get_DescriptionId", "get_DetailId", "get_TaskSummaryId", "get_LogDetailId",
}
local _LOG_STRING_KEYS = {
    "CurrentTaskName", "QuestCurrentTaskName", "ActiveTaskName", "ObjectiveName",
    "CurrentObjective", "TaskName", "ProgressName",
    "QuestLogText", "GuideText", "CurrentLogText", "TaskLogText", "QuestGuideText",
    "ObjectiveText", "CurrentObjectiveText", "ProgressText", "SubTaskName", "MainTaskName",
}
local _LOG_GUID_SUFFIXES = { "Id", "ID", "Guid", "GUID" }

local function _guid_text_from_task(task, field_keys, method_names)
    for _, key in ipairs(field_keys) do
        local gt = _guid_to_en_text(safe_get_field(task, key))
        if gt then return gt, key end
    end
    for _, mn in ipairs(method_names) do
        local v = safe_call(task, mn)
        if type(v) == "string" and v ~= "" then return v, mn end
        local gt = _guid_to_en_text(v)
        if gt then return gt, mn .. ":guid" end
    end
    return nil, nil
end

local function _task_title_and_detail(task)
    local title, src = nil, nil
    title = _read_text_field(task, _TASK_STRING_KEYS, _TASK_GUID_KEYS)
    local detail = _read_text_field(task, _TASK_DETAIL_KEYS, _TASK_DETAIL_GUID)
    if not title then
        title, src = _guid_text_from_task(task, _TASK_GUID_KEYS, _TASK_GUID_METHODS)
    end
    if not title then
        for _, mn in ipairs({
            "get_TaskName", "get_Name", "get_Title", "get_LogText", "get_ObjectiveName",
            "get_Message", "get_Caption", "get_Text", "get_LogMessage", "get_TaskLog",
        }) do
            local v = safe_call(task, mn)
            if type(v) == "string" and v ~= "" then title = v; src = mn; break end
            local gt = _guid_to_en_text(v)
            if gt then title = gt; src = mn .. ":guid"; break end
        end
    end
    if not detail then
        local d2, ds = _guid_text_from_task(task, _TASK_DETAIL_GUID, _TASK_DETAIL_GUID_METHODS)
        if d2 then detail = d2; if mod and mod.debug_logging then
            mlog(string.format("[QT][steps] task detail via %s", ds or "?"))
        end end
    end
    if mod and mod.debug_logging and title and src then
        mlog(string.format("[QT][steps] task title via %s: %s", src, title:sub(1, 80)))
    end
    return title, detail
end

local function _walk_task_list(task_list, found, pass, depth)
    depth = depth or 0
    if task_list == nil or found[1] or depth >= TASK_WALK_MAX_DEPTH then return end
    iter_list(task_list, function(task)
        if found[1] then return end
        local is_current = (pass == 1) and _task_is_active(task)
        local is_open = (pass == 2) and not _task_is_cleared(task)
        if is_current or is_open then
            local title, detail = _task_title_and_detail(task)
            if title then
                found[1] = title
                found[2] = detail
                return
            end
        end
        for _, nk in ipairs({ "_NextTaskList", "NextTaskList", "_ChildTaskList", "ChildTaskList" }) do
            local nxt = safe_get_field(task, nk)
            if nxt == nil then nxt = safe_call(task, "get_NextTaskList") end
            if nxt == nil then nxt = safe_call(task, "get_ChildTaskList") end
            _walk_task_list(nxt, found, pass, depth + 1)
        end
    end)
end

-- Journal order: last objective that still has a title and is not cleared (matches in-game checklist).
local function _walk_journal_current(task_list, found, depth)
    depth = depth or 0
    if task_list == nil or depth >= TASK_WALK_MAX_DEPTH then return end
    iter_list(task_list, function(task)
        local title, detail = _task_title_and_detail(task)
        if title and not _task_is_cleared(task) then
            found[1] = title
            found[2] = detail
        end
        for _, nk in ipairs({ "_NextTaskList", "NextTaskList", "_ChildTaskList", "ChildTaskList" }) do
            local nxt = safe_get_field(task, nk)
            if nxt == nil then nxt = safe_call(task, "get_NextTaskList") end
            if nxt == nil then nxt = safe_call(task, "get_ChildTaskList") end
            _walk_journal_current(nxt, found, depth + 1)
        end
    end)
end

local function _invalidate_step_cache_for(qid)
    _step_fail_logged[qid] = nil
    _step_probe_done[qid] = nil
    if mod and mod.summary_cache then mod.summary_cache[qid] = nil end
end

local function _task_lists_from_vi(vi)
    local out = {}
    for _, key in ipairs({
        "_CurrentTaskList", "CurrentTaskList", "_TaskLogList", "TaskLogList",
        "_TaskList", "TaskList", "_LogTaskList", "LogTaskList",
    }) do
        local v = safe_get_field(vi, key)
        if v then out[#out + 1] = v end
    end
    for _, mn in ipairs({
        "get_CurrentTaskList", "get_TaskLogList", "get_TaskList", "get_LogTaskList", "get_ProgressTaskList",
    }) do
        local v = safe_call(vi, mn)
        if v then out[#out + 1] = v end
    end
    return out
end

local function _task_from_questlog_vi(vi)
    if vi == nil then return nil end
    for _, key in ipairs({ "<Task>k__BackingField", "_Task", "Task" }) do
        local t = safe_get_field(vi, key)
        if t then return t end
    end
    return safe_call(vi, "get_Task")
end

local _log_objective_from_vi

local function _probe_step_api(qid, vi, res)
    if not mod.debug_logging or _step_probe_done[qid] then return end
    _step_probe_done[qid] = true
    mlog("[QT][probe] qid=" .. tostring(qid) .. " — dump Task/Log fields (enable Verbose debug)")
    local function log_type_fields(obj, label)
        if obj == nil then return end
        local ok, t = pcall(function() return obj:get_type_definition() end)
        if not ok or t == nil then return end
        local n = 0
        for _, f in ipairs(t:get_fields()) do
            local fn = f:get_name()
            if fn:find("Task", 1, true) or fn:find("Log", 1, true) or fn:find("Objective", 1, true)
                or fn:find("Progress", 1, true) or fn:find("Clear", 1, true) or fn:find("Active", 1, true) then
                n = n + 1
                if n <= 25 then mlog(string.format("[QT][probe] %s field %s", label, fn)) end
            end
        end
    end
    log_type_fields(vi, "QuestLog")
    if vi then
        local bt = _task_from_questlog_vi(vi)
        if bt then
            local tt, td = _task_title_and_detail(bt)
            mlog(string.format("[QT][probe] QuestLog.<Task> title=%s", tostring(tt)))
            if td and td ~= tt then mlog("[QT][probe] QuestLog.<Task> detail=" .. tostring(td):sub(1, 100)) end
        else
            mlog("[QT][probe] QuestLog.<Task> missing")
        end
        local lt, _ = _log_objective_from_vi(vi, qid)
        mlog("[QT][probe] QuestLog log-objective=" .. tostring(lt))
    end
    log_type_fields(res, "QuestLogResource")
    if res then
        local lst = safe_call(res, "get_FirstTaskList") or safe_get_field(res, "_FirstTaskList")
        if lst then
            iter_list(lst, function(task, idx)
                if idx > 0 then return end
                log_type_fields(task, "QuestTask[0]")
            end)
        else
            mlog("[QT][probe] no FirstTaskList on resource")
        end
    else
        mlog("[QT][probe] no QuestLogResource in catalog for qid=" .. tostring(qid))
    end
end

local _STEP_VERBS = {
    "return", "deliver", "journey", "speak", "talk", "find", "hunt", "search", "collect",
    "gather", "defeat", "slay", "kill", "investigate", "report", "head", "make", "use",
    "bring", "obtain", "acquire", "meet", "visit", "enter", "pass", "escort", "protect",
    "follow", "track", "recover", "steal", "give", "seek", "locate", "retrieve", "hand",
}

local function _step_has_verb(text)
    local low = text:lower()
    for _, v in ipairs(_STEP_VERBS) do
        if low:find("%f[%a]" .. v .. "%f[%A]", 1) or low:find("^" .. v, 1) then return true end
    end
    return false
end

local function _is_weak_step(text)
    if not text or text == "" then return true end
    if _step_has_verb(text) then return false end
    if #text > 36 or text:find(" to ") or text:find(" the ") then return false end
    local words = 0
    for _ in text:gmatch("%S+") do words = words + 1 end
    return words <= 3
end

local function _is_flavor_text(text, qid)
    if not text or text == "" then return true end
    local summ = mod.summary_cache[qid]
    if summ and text == summ then return true end
    if summ and #text > 120 and summ:sub(1, 40) == text:sub(1, 40) then return true end
    return false
end

local function _pick_step(qid, title, detail, field)
    if not title or _is_flavor_text(title, qid) or _is_weak_step(title) then return nil, nil end
    mod._step_field_src = mod._step_field_src or {}
    mod._step_field_src[qid] = field
    return title, detail
end

_log_objective_from_vi = function(vi, qid)
    if vi == nil then return nil, nil end
    for _, mn in ipairs({
        "get_QuestLogText", "get_GuideText", "get_CurrentLogText", "get_TaskLogText",
        "get_QuestGuideText", "get_CurrentTaskName", "get_ActiveTaskName", "get_ObjectiveName",
        "get_ProgressText",
        -- Additional journal fields (Feature 2C)
        "get_CurrentTaskText", "get_CurrentGuideText", "get_CurrentObjectiveText",
        "get_TaskText", "get_CurrentLog", "get_CurrentTask",
    }) do
        local ok, v = pcall(function() return vi:call(mn) end)
        if ok then
            if type(v) == "string" and v ~= "" then
                local t, d = _pick_step(qid, v, nil, mn)
                if t then return t, d end
            else
                local gt = _guid_to_en_text(v)
                if gt then
                    local t, d = _pick_step(qid, gt, nil, mn .. ":guid")
                    if t then return t, d end
                end
            end
        end
    end
    for _, key in ipairs(_LOG_STRING_KEYS) do
        local v = safe_get_field(vi, key)
        if type(v) == "string" and v ~= "" then
            local t, d = _pick_step(qid, v, nil, key)
            if t then return t, d end
        end
        for _, suf in ipairs(_LOG_GUID_SUFFIXES) do
            local gt = _guid_to_en_text(safe_get_field(vi, key .. suf))
            if gt then
                local t, d = _pick_step(qid, gt, nil, key .. suf)
                if t then return t, d end
            end
        end
    end
    return nil, nil
end

local function _journal_step_from_sources(qlm, qid)
    local found = {}
    local res = qlm and get_quest_resource(qlm, qid) or nil
    if res then
        for _, src in ipairs({
            safe_call(res, "get_FirstTaskList"), safe_get_field(res, "_FirstTaskList"),
            safe_get_field(res, "_TaskList"), safe_call(res, "get_TaskList"),
            safe_get_field(res, "_TaskLogList"), safe_call(res, "get_TaskLogList"),
            safe_get_field(res, "_CurrentTaskList"), safe_call(res, "get_CurrentTaskList"),
        }) do
            if src then
                _walk_journal_current(src, found)
                if found[1] then return found[1], found[2] end
            end
        end
    end
    local vi = qlm and safe_call(qlm, "getQuestLog", qid) or nil
    if vi then
        for _, src in ipairs(_task_lists_from_vi(vi)) do
            _walk_journal_current(src, found)
            if found[1] then return found[1], found[2] end
        end
    end
    return nil, nil
end

local function _foreach_task_tree(task_list, fn, depth)
    depth = depth or 0
    if task_list == nil or depth >= TASK_WALK_MAX_DEPTH then return end
    iter_list(task_list, function(task)
        fn(task)
        for _, nk in ipairs({ "_NextTaskList", "NextTaskList", "_ChildTaskList", "ChildTaskList" }) do
            local nxt = safe_get_field(task, nk)
            if nxt == nil then nxt = safe_call(task, "get_NextTaskList") end
            if nxt == nil then nxt = safe_call(task, "get_ChildTaskList") end
            _foreach_task_tree(nxt, fn, depth + 1)
        end
    end)
end

local function _count_cleared_and_last_open(task_list)
    local cleared, last_title, last_detail = 0, nil, nil
    _foreach_task_tree(task_list, function(task)
        local title, detail = _task_title_and_detail(task)
        if title then
            if _task_is_cleared(task) then
                cleared = cleared + 1
            else
                last_title, last_detail = title, detail
            end
        elseif _task_is_cleared(task) then
            cleared = cleared + 1
        end
    end)
    return cleared, last_title, last_detail
end

local function _task_tree_sources(qlm, qid)
    local sources = {}
    local res = qlm and get_quest_resource(qlm, qid) or nil
    if res then
        for _, src in ipairs({
            safe_call(res, "get_FirstTaskList"), safe_get_field(res, "_FirstTaskList"),
            safe_get_field(res, "_TaskList"), safe_call(res, "get_TaskList"),
            safe_get_field(res, "_CurrentTaskList"), safe_call(res, "get_CurrentTaskList"),
            safe_get_field(res, "_TaskLogList"), safe_call(res, "get_TaskLogList"),
        }) do
            if src then sources[#sources + 1] = src end
        end
    end
    local vi = qlm and safe_call(qlm, "getQuestLog", qid) or nil
    if vi then
        for _, src in ipairs(_task_lists_from_vi(vi)) do
            sources[#sources + 1] = src
        end
    end
    return sources, vi, res
end

local function _text_from_gui_obj(obj, qid)
    if not obj then return nil end
    for _, mn in ipairs({ "get_Message", "get_Text", "get_Caption" }) do
        local ok, v = pcall(function() return obj:call(mn) end)
        if ok and type(v) == "string" and #v > 2 and not _is_flavor_text(v, qid) then return v end
    end
    local ok, mid = pcall(function() return obj:call("get_MessageId") end)
    if ok and mid then
        local t = _guid_to_en_text(mid)
        if t and not _is_flavor_text(t, qid) then return t end
    end
    return nil
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

local function _log_info_entry(qlm, qid)
    if not qlm or not qid then return nil end
    local dict = safe_get_field(qlm, "_QuestLogInfoDict")
    if not dict then return nil end
    local want = tonumber(qid) or qid
    if safe_dict_get then
        return safe_dict_get(dict, qid) or safe_dict_get(dict, want)
    end
    return nil
end

local function _info_task_index(entry)
    if not entry then return nil end
    return to_int(safe_get_field(entry, "<CurrentTaskIndex>k__BackingField"))
        or to_int(safe_get_field(entry, "CurrentTaskIndex"))
        or to_int(safe_call(entry, "get_CurrentTaskIndex"))
end

local function _text_from_dest(dest, qid)
    if not dest then return nil end
    local t = _text_from_gui_obj(dest, qid)
    if t then return t end
    for _, key in ipairs({
        "MessageId", "_MessageId", "MsgId", "_MsgId", "LogMessageId", "_LogMessageId",
        "TaskMessageId", "_TaskMessageId", "Msg", "_Msg", "NameId", "_NameId",
        "GuideTextId", "_GuideTextId", "ObjectiveTextId", "_ObjectiveTextId",
    }) do
        local v = safe_get_field(dest, key)
        if type(v) == "string" and #v >= 32 and _text_from_hex32 then
            local hx = _text_from_hex32(v)
            if hx and not _is_flavor_text(hx, qid) then return hx end
        end
        local gt = _guid_to_en_text(v)
        if gt and not _is_flavor_text(gt, qid) then return gt end
    end
    for _, mn in ipairs({
        "get_Message", "get_MessageId", "get_Msg", "get_LogText", "get_GuideText",
        "get_ObjectiveText", "get_Name", "get_Title",
    }) do
        local ok, v = pcall(function() return dest:call(mn) end)
        if ok then
            if type(v) == "string" and #v > 2 and not _is_flavor_text(v, qid) then return v end
            local gt = _guid_to_en_text(v)
            if gt and not _is_flavor_text(gt, qid) then return gt end
        end
    end
    return nil
end

local function _pick_from_dests(dests, qid, field)
    local found = nil
    _iter_managed_list(dests, function(d)
        if found then return end
        local t = _text_from_dest(d, qid)
        if t then
            local p = _pick_step(qid, t, nil, field)
            if p then found = p end
        end
    end)
    return found
end

local function _task_from_resource_index(res, idx)
    if res == nil or idx == nil or idx < 0 then return nil end
    local task = nil
    local arr = safe_get_field(res, "_TaskList")
    if arr then
        pcall(function() task = arr:get_element(idx) end)
        if task == nil then pcall(function() task = arr[idx] end) end
    end
    if task == nil then
        local lst = safe_get_field(res, "_FirstTaskList") or safe_call(res, "get_FirstTaskList")
        if lst then
            pcall(function() task = lst:get_element(idx) end)
            if task == nil then pcall(function() task = lst:call("get_Item", idx) end) end
        end
    end
    return task
end

local function _dests_on_task(task)
    if not task then return nil end
    return safe_call(task, "getActiveDestinations")
        or safe_call(task, "get_Destinations")
        or safe_get_field(task, "_Destinations")
        or safe_get_field(task, "_CurrentDestinations")
end

local function _step_from_active_dests(qlm, qid)
    local found = {}
    local sources = _task_tree_sources(qlm, qid)
    for _, src in ipairs(sources) do
        iter_list(src, function(task)
            if found[1] or _task_is_cleared(task) then return end
            local dests = safe_call(task, "getActiveDestinations") or safe_call(task, "get_Destinations")
                or safe_get_field(task, "_Destinations")
            if not dests then return end
            local sz = 0
            pcall(function() sz = dests:get_size() end)
            for i = 0, (sz or 0) - 1 do
                local ok, d = pcall(function() return dests:get_element(i) end)
                if ok and d then
                    local t = _text_from_dest(d, qid)
                    if t and not _is_weak_step(t) then found[1] = t; return end
                end
            end
        end)
        if found[1] then return found[1] end
    end
    return nil
end

local function _step_from_decomp_dests(qlm, qid)
    if not QD or not QD.get_quest_dests or not _text_from_hex32 then return nil end
    local dests = QD.get_quest_dests(qid)
    if not dests or #dests == 0 then return nil end
    local best_cleared = 0
    for _, src in ipairs(_task_tree_sources(qlm, qid)) do
        local c = (_count_cleared_and_last_open(src))
        if c > best_cleared then best_cleared = c end
    end
    local idx = math.max(1, math.min(best_cleared + 1, #dests))
    local msg = dests[idx] and dests[idx].msg
    if type(msg) == "string" and msg ~= "" then
        local t = _text_from_hex32(msg)
        if t and not _is_flavor_text(t, qid) and not _is_weak_step(t) then return t end
    end
    return nil
end

local SCAVENGE_MAX_FIELDS = 80

local function _scavenge_object_text(obj, qid, skip)
    if not obj then return nil end
    skip = skip or {}
    local ok, tdef = pcall(function() return obj:get_type_definition() end)
    if not ok or not tdef then return nil end
    local n = 0
    for _, f in ipairs(tdef:get_fields()) do
        n = n + 1
        if n > SCAVENGE_MAX_FIELDS then break end
        local fn = f:get_name()
        if not skip[fn] then
            local ok2, v = pcall(function() return f:get_data(obj) end)
            if ok2 then
                if type(v) == "string" and #v > 3 and not _is_flavor_text(v, qid) then return v end
                if fn:find("Id") or fn:find("Msg") or fn:find("Message") or fn:find("Text") or fn:find("Log") then
                    local gt = _guid_to_en_text(v)
                    if gt and not _is_flavor_text(gt, qid) then return gt end
                    if type(v) == "string" and _text_from_hex32 then
                        local hx = _text_from_hex32(v)
                        if hx and not _is_flavor_text(hx, qid) then return hx end
                    end
                end
            end
        end
    end
    return _text_from_gui_obj(obj, qid)
end

local function _step_from_decomp_by_index(qid, task_index)
    if not QD or not QD.get_quest_dests or not _text_from_hex32 then return nil end
    if task_index == nil then return nil end
    local dests = QD.get_quest_dests(qid)
    if not dests or #dests == 0 then return nil end
    local idx = math.max(1, math.min(task_index + 1, #dests))
    local msg = dests[idx] and dests[idx].msg
    if type(msg) ~= "string" or msg == "" then return nil end
    local t = _text_from_hex32(msg)
    if t and not _is_flavor_text(t, qid) and not _is_weak_step(t) then return t end
    return nil
end

local function _first_dest_text(dests, qid)
    local raw = nil
    _iter_managed_list(dests, function(d)
        if not raw then raw = _text_from_dest(d, qid) end
    end)
    return raw
end

local function _resolve_info_dest_step(entry, qid)
    if not entry then return nil, nil end
    local task_idx = _info_task_index(entry)
    local raw = _first_dest_text(safe_get_field(entry, "_CurrentDestinations"), qid)
    if not raw or raw == "" or _is_flavor_text(raw, qid) then return nil, nil end

    mod._step_field_src = mod._step_field_src or {}
    local t = _pick_step(qid, raw, nil, "InfoDict._CurrentDestinations")
    if t then return t, nil end

    if task_idx ~= nil then
        local dt = _step_from_decomp_by_index(qid, task_idx)
        if dt then
            mod._step_field_src[qid] = "InfoDict.live_pin+decomp"
            return dt, nil
        end
    end
    return nil, nil
end

local function _completed_task_count(entry)
    if not entry then return 0 end
    local lst = safe_get_field(entry, "<CompletedTaskIndexes>k__BackingField")
        or safe_get_field(entry, "CompletedTaskIndexes")
    if not lst then return 0 end
    local n = 0
    _iter_managed_list(lst, function() n = n + 1 end)
    return n
end

local function _step_from_all_tasks_scavenge(qlm, qid)
    local last_open, last_detail = nil, nil
    local function try_task(task)
        if not task then return end
        local title, detail = _task_title_and_detail(task)
        if not title then
            local ok_sc, sc = pcall(_scavenge_object_text, task, qid, {})
            if ok_sc and sc then title = sc end
        end
        if title and not _is_flavor_text(title, qid) and not _is_weak_step(title) then
            if not _task_is_cleared(task) then
                last_open, last_detail = title, detail
            elseif not last_open then
                last_open, last_detail = title, detail
            end
        end
    end
    local function walk_list(lst)
        if not lst then return end
        iter_list(lst, function(task) try_task(task) end)
    end
    local res = qlm and get_quest_resource(qlm, qid) or nil
    if res then
        for _, src in ipairs({
            safe_get_field(res, "_TaskList"), safe_get_field(res, "_FirstTaskList"),
            safe_call(res, "get_TaskList"), safe_call(res, "get_FirstTaskList"),
        }) do walk_list(src) end
    end
    local vi = qlm and safe_call(qlm, "getQuestLog", qid) or nil
    if vi then
        local bt = _task_from_questlog_vi(vi)
        try_task(bt)
        for _, src in ipairs(_task_lists_from_vi(vi)) do walk_list(src) end
    end
    if last_open then
        mod._step_field_src = mod._step_field_src or {}
        mod._step_field_src[qid] = "task_scavenge_all"
        return last_open, last_detail
    end
    return nil, nil
end

local function _step_from_log_info_dict(qlm, qid)
    if not qlm then return nil, nil end
    local entry = _log_info_entry(qlm, qid)
    if not entry then return nil, nil end

    local t, d = _resolve_info_dest_step(entry, qid)
    if t then return t, d end

    local task_idx = _info_task_index(entry)
    if task_idx ~= nil then
        local res = get_quest_resource(qlm, qid)
        local task = _task_from_resource_index(res, task_idx)
        t = _pick_from_dests(_dests_on_task(task), qid, "InfoDict.taskIndex.dest")
        if t then return t, nil end
        local dt = _step_from_decomp_by_index(qid, task_idx)
        if dt then
            mod._step_field_src = mod._step_field_src or {}
            mod._step_field_src[qid] = "InfoDict.taskIndex+decomp"
            return dt, nil
        end
    end

    local lo, ld = _log_objective_from_vi(entry, qid)
    if lo then
        mod._step_field_src = mod._step_field_src or {}
        mod._step_field_src[qid] = "QuestLogInfo.fields"
        return lo, ld
    end
    return nil, nil
end

local function _step_from_vi_task(vi, qid)
    if not vi then return nil, nil end
    local task = _task_from_questlog_vi(vi)
    local t = _pick_from_dests(_dests_on_task(task), qid, "QuestLogViewInfo.Task.dest")
    if t then return t, nil end
    if task then
        local title, detail = _task_title_and_detail(task)
        if not title then
            local ok_sc, sc = pcall(_scavenge_object_text, task, qid, {})
            if ok_sc and sc then title = sc; mod._step_field_src = mod._step_field_src or {}; mod._step_field_src[qid] = "QuestLogViewInfo.Task.scavenge" end
        end
        return _pick_step(qid, title, detail, "QuestLogViewInfo.Task")
    end
    return nil, nil
end



  ctx._is_flavor_text = _is_flavor_text
  ctx._is_weak_step = _is_weak_step
  ctx._pick_step = _pick_step
  ctx._log_info_entry = _log_info_entry
  ctx._info_task_index = _info_task_index
  ctx._text_from_dest = _text_from_dest
  ctx._iter_managed_list = _iter_managed_list
  ctx._task_tree_sources = _task_tree_sources
  ctx._count_cleared_and_last_open = _count_cleared_and_last_open
  ctx._step_from_vi_task = _step_from_vi_task
  ctx._log_objective_from_vi = _log_objective_from_vi
  ctx._journal_step_from_sources = _journal_step_from_sources
  ctx._step_from_active_dests = _step_from_active_dests
  ctx._step_from_decomp_by_index = _step_from_decomp_by_index
  ctx._step_from_decomp_dests = _step_from_decomp_dests
  ctx._step_from_all_tasks_scavenge = _step_from_all_tasks_scavenge
  ctx._step_from_log_info_dict = _step_from_log_info_dict
  ctx._task_from_questlog_vi = _task_from_questlog_vi
  ctx._task_lists_from_vi = _task_lists_from_vi
  ctx._walk_task_list = _walk_task_list
  ctx._walk_journal_current = _walk_journal_current
  ctx._task_title_and_detail = _task_title_and_detail
  ctx._scavenge_object_text = _scavenge_object_text
  ctx._completed_task_count = _completed_task_count
  ctx._resolve_info_dest_step = _resolve_info_dest_step
  ctx._probe_step_api = _probe_step_api
  require("quest_tracker_steps_resolve").install(ctx)

  function ctx._quest_log_info_fingerprint(qlm, qid)
    local entry = _log_info_entry(qlm, qid)
    if not entry then return "" end
    local bits = {}
    local ti = _info_task_index(entry)
    if ti ~= nil then bits[#bits + 1] = "i" .. tostring(ti) end
    local done = safe_get_field(entry, "<CompletedTaskIndexes>k__BackingField")
        or safe_get_field(entry, "CompletedTaskIndexes")
    local dn = 0
    _iter_managed_list(done, function() dn = dn + 1 end)
    bits[#bits + 1] = "d" .. tostring(dn)
    local n = 0
    _iter_managed_list(safe_get_field(entry, "_CurrentDestinations"), function(dest)
        n = n + 1
        if n <= 2 then
            local t = _text_from_dest(dest, qid)
            if t then bits[#bits + 1] = t:sub(1, 40) end
        end
    end)
    return table.concat(bits, "/")
  end

  ctx._invalidate_step_cache_for = _invalidate_step_cache_for
  ctx._is_flavor_text = _is_flavor_text
  ctx._log_info_entry = _log_info_entry
  ctx._text_from_dest = _text_from_dest
  ctx._steps_probe_qid = function(qid)
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if not qlm then return end
    _step_probe_done[qid] = nil
    local vi = safe_call(qlm, "getQuestLog", qid)
    local res = get_quest_resource(qlm, qid)
    _probe_step_api(qid, vi, res)
  end
  mod._steps_probe_qid = ctx._steps_probe_qid
end

return M