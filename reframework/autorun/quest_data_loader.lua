-- quest_data_loader.lua — required by quest_tracker.lua (ModRules sub-module)
-- Loads quest_tracker_data.json (givers, rec_level) and
-- quest_tracker_meta.json (prereqs, notes, extra_giver_cids, primary_giver_cid, timers, schedules, side-chain, lockouts).
local M = {}

-- =========== TRACKER DATA (givers / rec level) ===========
local DATA_PATH = "quest_tracker_data.json"
M.DATA = nil

local function ensure_data()
    if M.DATA then return M.DATA end
    local ok, data = pcall(json.load_file, DATA_PATH)
    if ok and type(data) == "table" then
        M.DATA = data
    else
        M.DATA = { quests = {}, common_noise_cids = {} }
    end
    return M.DATA
end

local _noise = nil
local function noise_set()
    if _noise then return _noise end
    _noise = {}
    for _, cid in ipairs(ensure_data().common_noise_cids or {}) do _noise[cid] = true end
    return _noise
end

local function qd(qid)
    return ensure_data().quests[tostring(qid)]
end

function M.get_recommended_level(qid)
    local d = qd(qid); return d and d.rec_level or nil
end

function M.get_quest_dests(qid)
    local d = qd(qid)
    return d and d.dests or nil
end

-- =========== META DATA (wiki-sourced) ===========
local META_PATH = "quest_tracker_meta.json"
local _meta = nil
local _chara_name_cache = nil       -- charaID -> friendly name (built from giver_name + chara_names override)
local rebuild_chara_name_cache      -- forward decl (iter_chara_name_cids must not call before this exists)

local function ensure_meta()
    if _meta then return _meta end
    local ok, data = pcall(json.load_file, META_PATH)
    if ok and type(data) == "table" then
        _meta = data
    else
        _meta = { quests = {} }
    end
    if type(_meta.quests) ~= "table" then _meta.quests = {} end
    return _meta
end

-- IMPORTANT: meta JSON wraps quest objects under .quests; index there, not the root.
local function qm(qid)
    return ensure_meta().quests[tostring(qid)]
end

-- ---- standard accessors ----------
function M.get_prereq_quests(qid)
    local d = qm(qid); return d and d.prereq_quests or nil
end

-- True when this quest has a meta entry (used to whitelist "Upcoming" candidates,
-- so the tab doesn't show all 600 quest enum entries).
function M.has_meta(qid)
    return qm(qid) ~= nil
end

-- PoNR/milestone gate: completing this quest hides the side quest forever (wiki: lockout_after).
function M.get_lockout_after(qid)
    local d = qm(qid); return d and d.lockout_after or nil
end

-- Fextralife "Vermund Quests 1" + reddit extras: finish before Feast of Deception (10140).
-- Side quests: lockout_after 10140 (not available_after 10140 — those unlock post-Feast).
-- Main/reddit gates: must_before_feast on the meta row.
function M.is_must_before_feast(qid)
    local d = qm(qid)
    if not d then return false end
    if d.must_before_feast == true then return true end
    if d.wiki_bucket == "vermund_1" then return true end
    if d.lockout_after == 10140 then
        if d.available_after == 10140 then return false end
        return true
    end
    return false
end

function M.get_urgent(qid)
    local d = qm(qid); return d and d.urgent == true
end

-- Wiki PoNR bucket: quest only becomes trackable AFTER this main quest is completed
-- (e.g. Vermund/Battahl side quests after Feast of Deception 10140).
function M.get_available_after(qid)
    local d = qm(qid); return d and d.available_after or nil
end

-- Iterate every quest id with a meta entry. Lets quest_tracker enumerate Upcoming candidates
-- without needing app.QuestDefine.ID enum coverage for late-bound side quests.
function M.iter_meta_qids()
    local m = ensure_meta()
    local out = {}
    for k, _ in pairs(m.quests or {}) do
        local n = tonumber(k)
        if n then out[#out + 1] = n end
    end
    return out
end

function M.get_time_limit_days(qid)
    local d = qm(qid); return d and d.time_limit_days or nil
end

-- If ANY of these listed quest IDs is Completed → this quest is permanently locked.
function M.get_locked_if_completed(qid)
    local d = qm(qid); return d and d.locked_if_completed or nil
end

function M.format_quest_links(qid, name_fn)
    if type(name_fn) ~= "function" then
        name_fn = function(nq) return "Quest " .. tostring(nq) end
    end
    local lines = {}
    local d = qm(qid)
    if not d then return lines end
    if type(d.locked_if_completed) == "table" then
        for _, nq in ipairs(d.locked_if_completed) do
            lines[#lines + 1] = "Locks after you finish: " .. tostring(name_fn(nq))
        end
    end
    if type(d.lockout_after) == "number" then
        lines[#lines + 1] = "Finish this before main story: " .. tostring(name_fn(d.lockout_after))
    elseif d.must_before_feast then
        lines[#lines + 1] = "Finish this before main story: " .. tostring(name_fn(10140))
    end
    if type(d.prereq_quests) == "table" then
        for _, nq in ipairs(d.prereq_quests) do
            lines[#lines + 1] = "Requires: " .. tostring(name_fn(nq))
        end
    end
    local chains = ensure_meta().chains
    if type(chains) == "table" then
        for _, ch in pairs(chains) do
            if type(ch) == "table" and type(ch.quests) == "table" then
                for i, nq in ipairs(ch.quests) do
                    if nq == qid and ch.quests[i + 1] then
                        lines[#lines + 1] = "Leads to: " .. tostring(name_fn(ch.quests[i + 1]))
                    end
                end
            end
        end
    end
    if #lines > 3 then
        local trimmed = {}
        for i = 1, 3 do trimmed[i] = lines[i] end
        return trimmed
    end
    return lines
end

-- Short wiki note (helpful tips/quips) shown in the row.
function M.get_note(qid)
    local d = qm(qid); return d and d.note or nil
end

function M.get_schedule(qid)
    local d = qm(qid)
    if not d then return nil end
    local sch = d.schedule
    if type(sch) == "table" then return sch end
    local sa, eb = d.avail_hour_start, d.avail_hour_end
    if type(sa) == "number" and type(eb) == "number" then
        return { start = sa, finish = eb }
    end
    return nil
end

function M.get_giver_name(qid)
    local d = qm(qid); return d and d.giver_name or nil
end

-- Authoritative wiki cast list (lowercased) — when present, the UI shows ONLY NPCs whose
-- resolved name matches one of these. Cuts the runtime CastNPCIDs noise (random bystanders,
-- city ambient NPCs) down to the people the wiki actually names for the quest.
function M.get_wiki_cast(qid)
    local d = qm(qid)
    if not d or type(d.wiki_cast) ~= "table" then return nil end
    local out = {}
    for _, n in ipairs(d.wiki_cast) do
        if type(n) == "string" and n ~= "" then out[#out + 1] = n:lower() end
    end
    if #out == 0 then return nil end
    return out
end

-- Friendly quest name from meta JSON (e.g. "Hunt for the Jadeite Orb") used when the live
-- QuestLogManager has not yet exposed the quest (Upcoming / not-acceptable case).
function M.get_quest_meta_name(qid)
    local d = qm(qid); return d and d.name or nil
end

function M.get_quest_meta_region(qid)
    local d = qm(qid); return d and d.region or nil
end

-- Optional explicit primary giver CID when game data lists rumor NPCs first
-- or when the wiki-named NPC is not the first entry in quest_tracker_data.json.
function M.get_primary_giver_cid(qid)
    local d = qm(qid)
    if not d or type(d.primary_giver_cid) ~= "number" or d.primary_giver_cid <= 0 then return nil end
    return d.primary_giver_cid
end

function M.get_extra_giver_cids(qid)
    local d = qm(qid)
    if not d or type(d.extra_giver_cids) ~= "table" then return nil end
    local out = {}
    for _, c in ipairs(d.extra_giver_cids) do
        local n = tonumber(c)
        if n and n > 0 then out[#out + 1] = n end
    end
    if #out == 0 then return nil end
    return out
end

-- Wiki / hand-authored NPCs not present in quest_tracker_data.json givers[] (e.g. gate NPC from another quest).
-- Prepended so callers can still reorder by giver_name / primary_giver_cid.
function M.get_givers(qid)
    local d = qd(qid)
    local mq = qm(qid)
    local noise = noise_set()
    local out, seen = {}, {}
    local extra = mq and mq.extra_giver_cids
    if type(extra) == "table" then
        for _, cid in ipairs(extra) do
            local n = tonumber(cid)
            if n and n > 0 and not noise[n] and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
    end
    if not d then return out end
    for _, cid in ipairs(d.givers or {}) do
        if not noise[cid] and not seen[cid] then
            seen[cid] = true
            out[#out + 1] = cid
        end
    end
    return out
end

function M.get_timing_note(qid)
    local d = qm(qid); return d and d.timing_note or nil
end

function M.get_during_quest(qid)
    local d = qm(qid); return d and d.during_quest or nil
end

-- HOW to make this quest appear / start (non-obvious activation conditions from the wiki).
function M.get_trigger(qid)
    local d = qm(qid); return d and d.trigger or nil
end

-- ---- side-quest chain helpers ----------
-- A "chain" groups related side quests (e.g. all Sven side content) so we can:
--   * show "part 2 of 4" in the UI
--   * auto-lock earlier entries when a later one is Ongoing/Completed (giver moved on)
-- Top-level meta JSON shape:
--   "chains": { "Sven": { "name": "Sven (side)", "quests": [30010,30040,30041,30042,30180] }, ... }

local _chain_index = nil
local function rebuild_chain_index()
    _chain_index = {}
    local m = ensure_meta()
    if type(m.chains) ~= "table" then return _chain_index end
    for chain_id, c in pairs(m.chains) do
        if type(c) == "table" and type(c.quests) == "table" then
            for i, qid in ipairs(c.quests) do
                _chain_index[qid] = {
                    chain_id = chain_id,
                    name     = c.name or chain_id,
                    quests   = c.quests,
                    index    = i,
                }
            end
        end
    end
    return _chain_index
end

function M.get_chain_info(qid)
    if _chain_index == nil then rebuild_chain_index() end
    return _chain_index[qid]
end

-- ---- chara-name reverse lookup (so we never display NPC#1234567 to the user) ----------
-- Built once from giver_name fields plus an explicit chara_names map under meta:
--   "chara_names": { "1065353216": "Lennart", "1210835050": "Sven", ... }
-- giver_name + the qid->cid table in quest_tracker_data.json gives us most defaults
-- automatically, then chara_names overrides anything wrong.
rebuild_chara_name_cache = function()
    _chara_name_cache = {}
    local m = ensure_meta()
    if type(m.chara_names) == "table" then
        for k, v in pairs(m.chara_names) do
            local n = tonumber(k)
            if n and type(v) == "string" and v ~= "" then _chara_name_cache[n] = v end
        end
    end
    -- Auto-fill wiki giver_name only when the decomp list has exactly ONE non-noise
    -- giver — otherwise the first unnamed slot is often a shopkeeper / rumor NPC (e.g. Ornate Box).
    local noise = {}
    for _, cid in ipairs(ensure_data().common_noise_cids or {}) do noise[cid] = true end
    for qid_str, q in pairs(m.quests or {}) do
        local nm = q and q.giver_name
        if type(nm) == "string" and nm ~= "" then
            local d = qd(tonumber(qid_str))
            if d and type(d.givers) == "table" then
                local fg = {}
                for _, cid in ipairs(d.givers) do
                    if type(cid) == "number" and cid > 0 and not noise[cid] then fg[#fg + 1] = cid end
                end
                if #fg == 1 and not _chara_name_cache[fg[1]] then _chara_name_cache[fg[1]] = nm end
            end
        end
    end
end

function M.lookup_chara_name(cid)
    if _chara_name_cache == nil then rebuild_chara_name_cache() end
    if type(cid) ~= "number" then return nil end
    return _chara_name_cache[cid]
end

function M.iter_chara_name_cids()
    if _chara_name_cache == nil then rebuild_chara_name_cache() end
    return _chara_name_cache
end

-- =========== WIKI HINTS (quest_tracker_wiki_hints.json — 1–3 lines per quest) ===========
local HINTS_PATH = "quest_tracker_wiki_hints.json"
local _hints = nil

local function ensure_hints()
    if _hints then return _hints end
    local ok, data = pcall(json.load_file, HINTS_PATH)
    if ok and type(data) == "table" and type(data.by_qid) == "table" then
        _hints = data
    else
        _hints = { by_qid = {}, global = {} }
    end
    if type(_hints.global) ~= "table" then _hints.global = {} end
    if type(_hints.by_qid) ~= "table" then _hints.by_qid = {} end
    return _hints
end

function M.count_wiki_hint_quests()
    local n = 0
    for _ in pairs(ensure_hints().by_qid) do n = n + 1 end
    return n
end

function M.has_quest_hints(qid)
    return ensure_hints().by_qid[tostring(qid)] ~= nil
end

function M.get_wiki_step_order(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if row and type(row.step_order) == "table" and #row.step_order > 0 then
        return row.step_order
    end
    return M.get_wiki_steps(qid)
end

function M.titleize_step_key(key)
    if type(key) ~= "string" or key == "" then return nil end
    return key:sub(1, 1):upper() .. key:sub(2)
end

function M.get_step_title_from_order_index(qid, idx)
    local order = M.get_wiki_step_order(qid)
    if not order or type(idx) ~= "number" then return nil end
    local i = math.floor(idx)
    if i < 1 or i > #order then return nil end
    return M.titleize_step_key(order[i])
end

-- done_count = completed objectives; task_index = CurrentTaskIndex from game (preferred when set).
function M.get_wiki_step_for_progress(qid, done_count, task_index)
    local order = M.get_wiki_step_order(qid)
    if not order or #order == 0 then return nil, nil, nil end
    local done = math.max(0, math.floor(tonumber(done_count) or 0))
    local idx_done = math.max(1, math.min(done + 1, #order))
    local idx
    if type(task_index) == "number" and task_index >= 0 then
        local idx_task = math.max(1, math.min(task_index + 1, #order))
        idx = math.max(idx_done, idx_task)
    else
        idx = idx_done
    end
    -- #region agent log
    if tostring(qid) == "30220" then
        pcall(function()
            local f = io.open("c:/Users/jzafi/Desktop/New folder/OTHERMODS/QuestTracker-Modded/debug-62ebea.log", "a")
            if f then
                local key = order[idx] or "?"
                f:write(string.format(
                    '{"sessionId":"62ebea","hypothesisId":"A","location":"quest_data_loader.lua:get_wiki_step_for_progress","message":"30220 wiki idx","data":{"done":%d,"task_index":%s,"idx":%d,"order_n":%d,"key":"%s"},"timestamp":%d}\n',
                    done, tostring(task_index), idx, #order, tostring(key):gsub('"','\\"'), os.time() * 1000))
                f:close()
            end
        end)
    end
    -- #endregion
    return M.get_step_title_from_order_index(qid, idx), idx, #order
end

function M.get_step_order_index(qid, step_key)
    if type(step_key) ~= "string" or step_key == "" then return nil end
    local order = M.get_wiki_step_order(qid)
    if not order then return nil end
    local low = step_key:lower()
    for i, k in ipairs(order) do
        if type(k) == "string" and (k == step_key or k:lower() == low) then return i end
    end
    return nil
end

function M.is_top_level_step_key(qid, step_key)
    return M.get_step_order_index(qid, step_key) ~= nil
end

function M.has_wiki_step_order(qid)
    local order = M.get_wiki_step_order(qid)
    return order ~= nil and #order > 0
end

function M.get_wiki_journal_lines(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.journal_lines) ~= "table" or #row.journal_lines == 0 then return nil end
    return row.journal_lines
end

function M.get_wiki_hint_lines(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row then return nil end
    local out = nil
    if type(row.lines) == "table" and #row.lines > 0 then out = row.lines
    elseif type(row.lines) == "string" and row.lines ~= "" then out = { row.lines } end
    if not out then return nil end
    if #out > 3 then
        return { out[1], out[2], out[3] }
    end
    return out
end

-- Optional wiki walkthrough steps (ongoing quests). Match journal text to guess current step.
function M.get_wiki_steps(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.steps) ~= "table" or #row.steps == 0 then return nil end
    return row.steps
end

function M.get_step_hints_for_title(qid, step_title, active_key)
    if type(step_title) ~= "string" or step_title == "" then return nil end
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.step_hints) ~= "table" then return nil end

    local function _line_ok(line)
        if type(line) ~= "string" or line == "" then return false end
        local dec = M.decode_wiki_text(line)
        return #dec <= 200 and not dec:lower():find("when you first encounter", 1, true)
    end

    local function _hints_from_key(key)
        if type(key) ~= "string" or key == "" then return nil end
        local raw = row.step_hints[key]
        if type(raw) ~= "table" then return nil end
        local out = {}
        for _, line in ipairs(raw) do
            if _line_ok(line) then out[#out + 1] = M.decode_wiki_text(line) end
        end
        if #out > 0 then return out end
        return nil
    end

    if type(active_key) == "string" and active_key ~= "" then
        local direct = _hints_from_key(active_key)
        if direct then return direct end
    end

    local low = step_title:lower()
    local candidates = {}
    for k, lines in pairs(row.step_hints) do
        if type(k) == "string" and type(lines) == "table" and #lines > 0 then
            local kl = k:lower()
            local match = (low:find(kl, 1, true) or kl:find(low, 1, true))
            if match then
                local score = #kl
                local short = true
                for _, line in ipairs(lines) do
                    if type(line) == "string" and #M.decode_wiki_text(line) > 200 then
                        short = false
                        score = score - 500
                        break
                    end
                end
                if row.step_sub_order then
                    for _, subs in pairs(row.step_sub_order) do
                        if type(subs) == "table" then
                            for _, sk in ipairs(subs) do
                                if sk == k then score = score + 200; break end
                            end
                        end
                    end
                end
                if row.step_cast and row.step_cast[k] then score = score + 100 end
                if short then score = score + 50 end
                candidates[#candidates + 1] = { key = k, score = score }
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    for _, c in ipairs(candidates) do
        local h = _hints_from_key(c.key)
        if h then return h end
    end
    return nil
end

-- Pick micro-step key under an umbrella objective (hints + TP focus).
function M.resolve_active_step_key(qid, step_title, blobs)
    if type(step_title) ~= "string" or step_title == "" then return nil, "no_title" end
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row then return nil, "no_row" end
    local st_low = step_title:lower()
    local order_key = nil
    if type(row.step_order) == "table" then
        for _, k in ipairs(row.step_order) do
            if type(k) == "string" then
                local kl = k:lower()
                if st_low:find(kl, 1, true) or kl:find(st_low, 1, true) then
                    order_key = k
                    break
                end
            end
        end
    end
    if not order_key then return nil, "no_order_key" end
    local order_idx = M.get_step_order_index(qid, order_key)
    if order_idx and order_idx > 1 then return order_key, "macro_gt1" end
    if tonumber(qid) == 30120 then
        for _, blob in ipairs(blobs or {}) do
            if type(blob) == "string" and blob:lower():find("glimmercoal", 1, true) then
                return "find fifteen or more pieces of glimmercoal", "blob_glimmercoal"
            end
        end
        if order_key:find("glimmercoal", 1, true) or order_key:find("deliver", 1, true) then
            return order_key, "macro_30120"
        end
    end
    local subs = row.step_sub_order and row.step_sub_order[order_key]
    if type(subs) ~= "table" or #subs == 0 then return order_key, "no_subs" end

    local blob_n = (type(blobs) == "table") and #blobs or 0
    local best_sub, best_len = nil, 0
    for _, blob in ipairs(blobs or {}) do
        if type(blob) == "string" then
            local low = blob:lower()
            for _, sk in ipairs(subs) do
                local sl = sk:lower()
                if low:find(sl, 1, true) and #sl > best_len then
                    best_sub, best_len = sk, #sl
                end
            end
            if tonumber(qid) == 30120 and order_key:find("repair", 1, true) then
                if low:find("brokkr", 1, true) or low:find("smithy", 1, true) or low:find("battahl", 1, true) then
                    best_sub = "speak with brokkr at bakbattahl"
                elseif low:find("sara", 1, true) and not low:find("deliver", 1, true) and not low:find("glimmercoal", 1, true) then
                    best_sub = "speak with sara"
                elseif low:find("armorer", 1, true) or low:find("blacksmith", 1, true) or low:find("merchant square", 1, true) then
                    best_sub = "speak with the vernworth armorer"
                end
            end
        end
    end
    if best_sub then return best_sub, "blob_match" end

    local sub_default = row.step_sub_default and row.step_sub_default[order_key]
    -- Never apply umbrella sub_default when progress index is past this order key.
    if type(sub_default) == "string" and sub_default ~= "" then
        if order_idx and order_idx > 1 then
            return order_key, "skip_sub_default_past"
        end
        return sub_default, (blob_n == 0) and "sub_default_no_blobs" or "sub_default"
    end

    for _, sk in ipairs(subs) do
        if row.step_cast and type(row.step_cast[sk]) == "table" and #row.step_cast[sk] > 0 then
            return sk, "first_sub_cast"
        end
    end
    if subs[1] then return subs[1], "first_sub" end
    return order_key, "umbrella"
end

-- When the game API does not return a step title, optional wiki fallback key per quest.
function M.get_fallback_step_hints(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.fallback_step_key) ~= "string" or row.fallback_step_key == "" then return nil end
    if type(row.step_hints) ~= "table" then return nil end
    local raw = row.step_hints[row.fallback_step_key]
    if type(raw) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(raw) do
        if type(line) == "string" and line ~= "" then out[#out + 1] = M.decode_wiki_text(line) end
    end
    if #out > 0 then return out end
    return nil
end

function M.get_fallback_step_title(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.fallback_step_key) ~= "string" or row.fallback_step_key == "" then return nil end
    return M.titleize_step_key(row.fallback_step_key)
end

local function _parse_npc_hour_entry(h)
    if type(h) ~= "table" then return nil end
    local s = tonumber(h.start)
    local f = tonumber(h.finish or h["end"])
    if not s or not f then return nil end
    return { start = s, finish = f, note = (type(h.note) == "string" and h.note ~= "") and h.note or nil }
end

-- Hours for one NPC name on this quest (wiki_hints.npc_hours).
function M.get_npc_hours_for_name(qid, npc_name)
    if type(npc_name) ~= "string" or npc_name == "" then return nil end
    local row = ensure_hints().by_qid[tostring(qid)]
    if row and type(row.npc_hours) == "table" then
        local nlow = npc_name:lower()
        for key, raw in pairs(row.npc_hours) do
            if type(key) == "string" and key:lower() == nlow then
                local parsed = _parse_npc_hour_entry(raw)
                if parsed then return parsed end
            end
        end
    end
    local mq = qm(qid)
    if mq and mq.giver_name and type(mq.avail_hour_start) == "number" and type(mq.avail_hour_end) == "number" then
        if mq.giver_name:lower() == npc_name:lower() then
            return { start = mq.avail_hour_start, finish = mq.avail_hour_end }
        end
    end
    return nil
end

-- NPC hours for current step (wiki_hints.npc_hours + step_cast filter).
function M.get_step_relevant_npc_hours(qid, step_title)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.npc_hours) ~= "table" then return nil end
    local want = {}
    if type(step_title) == "string" and step_title ~= "" and type(row.step_cast) == "table" then
        local st = step_title:lower()
        for k, cast in pairs(row.step_cast) do
            if type(k) == "string" and st:find(k:lower(), 1, true) and type(cast) == "table" then
                for _, n in ipairs(cast) do
                    if type(n) == "string" and n ~= "" then want[n:lower()] = n end
                end
            end
        end
    end
    local out = {}
    for key, raw in pairs(row.npc_hours) do
        local parsed = _parse_npc_hour_entry(raw)
        if parsed then
            local display = type(key) == "string" and key or tostring(key)
            local nlow = display:lower()
            if next(want) == nil or want[nlow] then
                parsed.name = display
                out[#out + 1] = parsed
            end
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    if #out == 0 then return nil end
    return out
end

local _SKIP_NPC_WORDS = {
    the = true, you = true, your = true, quest = true,
    basement = true, outside = true, night = true, day = true, vernworth = true,
    ["and"] = true, ["for"] = true,
    this = true, him = true, her = true, them = true, it = true,
    area = true, spot = true, note = true, sleep = true, morning = true,
}

function M.decode_wiki_text(s)
    if type(s) ~= "string" then return s end
    return s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function _add_npc_name(names, seen, raw, from_hint_line)
    if type(raw) ~= "string" or raw == "" then return end
    local n = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if from_hint_line then
        n = n:match("^([%w']+)") or n
        local fc = n:sub(1, 1)
        if fc == fc:lower() and fc ~= fc:upper() then return end
    end
    if #n < 2 or _SKIP_NPC_WORDS[n:lower()] then return end
    local key = n:lower()
    if seen[key] then return end
    seen[key] = true
    names[#names + 1] = n
end

local function _names_from_hint_lines(lines, names, seen)
    if type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            for nm in line:gmatch("[Tt]alk to ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Ss]peak with ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Ss]peak to ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Ff]ollow ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Rr]eturn to ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Ff]ind ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Vv]isit ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch(" to ([%w']+) in ") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Ii]nform ([%w']+)") do _add_npc_name(names, seen, nm, true) end
            for nm in line:gmatch("[Gg]rab/pin ([%w']+)") do _add_npc_name(names, seen, nm, true) end
        end
    end
end

-- True when wiki step_cast matches this step (TP list should be step NPCs only).
function M.has_step_cast_focus(qid, step_title, active_key)
    if type(step_title) ~= "string" or step_title == "" then return false end
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.step_cast) ~= "table" then return false end
    local lookup = (type(active_key) == "string" and active_key ~= "") and active_key or step_title
    local st = lookup:lower()
    for k, cast in pairs(row.step_cast) do
        if type(k) == "string" and type(cast) == "table" and st:find(k:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- Every wiki-named NPC for the TP list. When step_cast matches, only that step's cast.
function M.get_quest_npc_names(qid, step_title, active_key)
    local names, seen = {}, {}
    local row = ensure_hints().by_qid[tostring(qid)]
    local lookup = (type(active_key) == "string" and active_key ~= "") and active_key or step_title
    local st_low = type(lookup) == "string" and lookup:lower() or nil
    if not st_low and row and type(row.fallback_step_key) == "string" then
        st_low = row.fallback_step_key:lower()
    end

    if row and st_low and type(row.step_cast) == "table" then
        for k, cast in pairs(row.step_cast) do
            if type(k) == "string" and st_low:find(k:lower(), 1, true) and type(cast) == "table" then
                for _, n in ipairs(cast) do _add_npc_name(names, seen, n) end
                if #names > 0 then return names end
                return {}
            end
        end
    end

    local mq = qm(qid)
    if mq and mq.giver_name then _add_npc_name(names, seen, mq.giver_name) end
    if mq and type(mq.wiki_cast) == "table" then
        for _, n in ipairs(mq.wiki_cast) do _add_npc_name(names, seen, n) end
    end
    if row and type(row.step_npcs) == "table" then
        for _, n in ipairs(row.step_npcs) do _add_npc_name(names, seen, n) end
    end
    if #names == 0 then return nil end
    return names
end

-- Optional name -> CharacterID map in wiki_hints (by_qid.step_npc_cids). Survives when NPC not in NPCHolderDic scan.
function M.get_npc_cids(qid)
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.step_npc_cids) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(row.step_npc_cids) do
        local cid = tonumber(v)
        if type(k) == "string" and cid and cid > 0 then
            out[k:lower()] = cid
            out[k] = cid
        end
    end
    if next(out) == nil then return nil end
    return out
end

-- Match in-game objective / journal text to a wiki step key (step_order + step_hints keys).
function M.match_step_key_from_text(qid, text)
    if type(text) ~= "string" or text == "" then return nil end
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row then return nil end
    local low = text:lower()
    local best_key, best_len = nil, 0
    local function try_key(k)
        if type(k) ~= "string" or k == "" then return end
        local kl = k:lower()
        if low:find(kl, 1, true) and #kl > best_len then
            best_key, best_len = k, #kl
        end
    end
    if type(row.step_order) == "table" then
        for _, k in ipairs(row.step_order) do try_key(k) end
    end
    if type(row.step_hints) == "table" then
        for k in pairs(row.step_hints) do try_key(k) end
    end
    if best_key then return M.titleize_step_key(best_key) end
    return nil
end

-- Game objective text often does not match step keys ("Escort Daphne…" vs "look-alike").
function M.guess_step_from_hints(qid, text)
    local t = M.match_step_key_from_text(qid, text)
    if t then return t end
    if type(text) ~= "string" or text == "" then return nil end
    local row = ensure_hints().by_qid[tostring(qid)]
    if not row or type(row.step_hints) ~= "table" then return nil end
    local low = text:lower()
    local best_key, best_score = nil, 0
    for key, lines in pairs(row.step_hints) do
        if type(key) == "string" then
            local score = 0
            local kl = key:lower()
            if low:find(kl, 1, true) then score = score + math.min(#kl, 12) end
            if type(lines) == "table" then
                for _, line in ipairs(lines) do
                    if type(line) == "string" then
                        for w in line:lower():gmatch("[%a']+") do
                            if #w >= 4 and low:find(w, 1, true) then score = score + 1 end
                        end
                    end
                end
            end
            if score > best_score then best_key, best_score = key, score end
        end
    end
    if best_key and best_score >= 2 then return M.titleize_step_key(best_key) end
    return nil
end

function M.match_wiki_step_index(qid, journal_text)
    local steps = M.get_wiki_steps(qid)
    if not steps or #steps == 0 then
        local row = ensure_hints().by_qid[tostring(qid)]
        if row and type(row.step_order) == "table" and #row.step_order > 0 then
            steps = row.step_order
        end
    end
    if not steps or type(journal_text) ~= "string" or journal_text == "" then
        return nil, steps
    end
    local low = journal_text:lower()
    local best_i, best_len = nil, 0
    for i, s in ipairs(steps) do
        if type(s) == "string" then
            local sl = s:lower()
            if low:find(sl, 1, true) and #sl > best_len then
                best_i, best_len = i, #sl
            end
        end
    end
    if best_i then return best_i, steps end
    for i, s in ipairs(steps) do
        if type(s) == "string" then
            local sl = s:lower()
            for w in sl:gmatch("[%a']+") do
                if #w >= 6 and low:find(w, 1, true) then return i, steps end
            end
        end
    end
    return nil, steps
end

-- Highest step_order index whose key appears in journal text (1-based).
function M.max_matched_step_index(qid, journal_text)
    local idx = M.match_wiki_step_index(qid, journal_text)
    return idx
end

-- Prefer FULL journal/objective key matches over raw CompletedTask counts.
-- Game done often overshoots curated step_order (tips jump to the last step too early).
function M.effective_progress_done(qid, game_done, blobs)
    game_done = math.max(0, math.floor(tonumber(game_done) or 0))
    local order = M.get_wiki_step_order(qid)
    if type(order) ~= "table" or #order == 0 then return game_done end
    local strong_idx = 0
    for _, blob in ipairs(blobs or {}) do
        if type(blob) == "string" and blob ~= "" then
            local low = blob:lower()
            for i, k in ipairs(order) do
                if type(k) == "string" and #k >= 8 and low:find(k:lower(), 1, true) then
                    if i > strong_idx then strong_idx = i end
                end
            end
        end
    end
    if strong_idx > 0 then
        return strong_idx - 1
    end
    return game_done
end

function M.get_wiki_global_hints()
    return ensure_hints().global
end

-- Build Fextralife / IGN wiki URLs from display name (for scraping or notes).
function M.wiki_urls_for_name(display_name)
    if type(display_name) ~= "string" or display_name == "" then return nil end
    local n = display_name
    local fe = n:gsub("'", "'"):gsub("%(", "%%28"):gsub("%)", "%%29"):gsub(" ", "+")
    local ign = n:gsub("'", ""):gsub(" ", "_")
    return {
        fextralife = "https://dragonsdogma2.wiki.fextralife.com/" .. fe,
        ign = "https://www.ign.com/wikis/dragons-dogma-2/" .. ign,
    }
end

function M.wiki_urls_for_qid(qid)
    local nm = M.get_quest_meta_name(qid)
    if nm then return M.wiki_urls_for_name(nm) end
    return nil
end

-- Quest list color tiers (story / special / fan_favorite / normal) — quest_tracker_quest_tiers.json
local TIERS_PATH = "quest_tracker_quest_tiers.json"
local _tiers = nil

local _tiers_load_logged = false
local _tiers_boot_logged = false

local FAN_NORMAL_BLUE = { ["20080"] = true, ["20140"] = true, ["20150"] = true }
local FAN_DUAL_STARS  = { ["20200"] = true, ["30100"] = true, ["20082"] = true, ["30110"] = true }

local function ensure_tiers()
    if _tiers then return _tiers end
    local ok, data = pcall(json.load_file, TIERS_PATH)
    if ok and type(data) == "table" then
        _tiers = data
        if not _tiers_boot_logged then
            _tiers_boot_logged = true
            local n_by = 0
            if type(_tiers.by_qid) == "table" then
                for _ in pairs(_tiers.by_qid) do n_by = n_by + 1 end
            end
            local n_fan = type(_tiers.fan_qids) == "table" and #_tiers.fan_qids or 0
            if log and log.info then
                log.info(string.format("[QT][tiers] loaded v%s by_qid=%d fan=%d",
                    tostring(_tiers.version or "?"), n_by, n_fan))
            end
        end
    else
        _tiers = { by_qid = {}, tier_colors_abgr = {}, reward_qids = {}, fan_qids = {} }
        if not _tiers_load_logged then
            _tiers_load_logged = true
            if log and log.warn then
                log.warn("[QT] tiers JSON parse FAIL — quest colors fall back to category defaults")
            end
        end
    end
    return _tiers
end

local function _tier_color(key, fallback)
    local t = ensure_tiers()
    local c = t.tier_colors_abgr and t.tier_colors_abgr[key]
    if type(c) == "number" then return c end
    return fallback
end

function M.is_reward_quest(qid)
    local t = ensure_tiers()
    if type(t.reward_qids) ~= "table" then return false end
    local want = tostring(qid)
    for _, id in ipairs(t.reward_qids) do
        if tostring(id) == want then return true end
    end
    return false
end

function M.get_quest_tier(qid)
    if M.is_reward_quest(qid) then return "reward_quest" end
    local row = ensure_tiers().by_qid
    if not row then return "normal" end
    local tier = row[tostring(qid)] or "normal"
    if tier == "fan_favorite" then return "normal" end
    return tier
end

function M.is_fan_favorite(qid)
    local t = ensure_tiers()
    if type(t.fan_qids) == "table" then
        local want = tostring(qid)
        for _, id in ipairs(t.fan_qids) do
            if tostring(id) == want then return true end
        end
    end
    return M.get_quest_tier(qid) == "fan_favorite"
end

function M.get_fan_star_color(qid)
    local want = tostring(qid)
    local tier = M.get_quest_tier(qid)
    if FAN_DUAL_STARS[want] and (tier == "story" or tier == "special") then
        return _tier_color("fan_star_purple", 0xFFAA00FF)
    end
    if FAN_NORMAL_BLUE[want] or tier == "side" or tier == "normal" then
        return _tier_color("fan_star_cyan", 0xFFFFFF00)
    end
    if tier == "story" or tier == "special" then
        return _tier_color("fan_star_purple", 0xFFAA00FF)
    end
    return _tier_color("fan_star_cyan", 0xFFFFFF00)
end

function M.get_fan_star_glyph(qid)
    local want = tostring(qid)
    local tier = M.get_quest_tier(qid)
    if FAN_DUAL_STARS[want] and (tier == "story" or tier == "special") then
        return "★★"
    end
    if FAN_DUAL_STARS[want] then
        return "★★"
    end
    if (tier == "story" or tier == "special") and M.is_fan_favorite(qid) then
        return "★★"
    end
    return "★"
end

function M.strip_fan_markers_from_name(name)
    if type(name) ~= "string" then return name end
    return name:gsub("%s*%*%*$", ""):gsub("%s+$", "")
end

function M.show_fan_stars(qid)
    return M.is_fan_favorite(qid)
end

function M.get_quest_tier_color(qid)
    local tier = M.get_quest_tier(qid)
    if tier == "reward_quest" then return _tier_color("reward_quest", 0xFF00D7FF) end
    if tier == "story" then return _tier_color("story", 0xFF66FF66) end
    if tier == "special" then return _tier_color("special", 0xFFAA00FF) end
    if tier == "side" then return _tier_color("side", 0xFFFFFFFF) end
    return _tier_color("normal", 0xFFFFFFFF)
end

function M.get_locked_quest_color()
    return _tier_color("locked", 0xFF888888)
end

return M
