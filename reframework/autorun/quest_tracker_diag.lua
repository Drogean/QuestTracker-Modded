-- quest_tracker_diag.lua — one-shot expand logging (cache only, no per-frame SDK work)
local M = {}

function M.install(ctx)
    local mod = ctx.mod
    local mlog = ctx.mlog
    local mlog_boot = ctx.mlog_boot or mlog
    local QD = ctx.QD

    local function _wiki_flags(qid)
        if not QD then return nil end
        local has_lines, has_fb, has_order, has_step_hints = false, false, false, false
        local ok_l, lines = pcall(QD.get_wiki_hint_lines, qid)
        if ok_l and type(lines) == "table" and #lines > 0 then has_lines = true end
        local ok_f, fb = pcall(QD.get_fallback_step_title, qid)
        if ok_f and type(fb) == "string" and fb ~= "" then has_fb = true end
        if QD.get_wiki_step_order then
            local ok_o, ord = pcall(QD.get_wiki_step_order, qid)
            if ok_o and type(ord) == "table" and #ord > 0 then has_order = true end
        end
        if QD.get_fallback_step_hints then
            local ok_fh, fh = pcall(QD.get_fallback_step_hints, qid)
            if ok_fh and type(fh) == "table" and #fh > 0 then has_step_hints = true end
        end
        return {
            has_lines = has_lines,
            has_fallback = has_fb,
            has_order = has_order,
            has_step_hints = has_step_hints,
        }
    end

    function ctx.audit_wiki_gaps_for_ongoing()
        if not mod.progressing_ids then return end
        mod._wiki_gap_logged = mod._wiki_gap_logged or {}
        for qid in pairs(mod.progressing_ids) do
            if not mod._wiki_gap_logged[qid] then
                local wf = _wiki_flags(qid)
                if wf and not wf.has_order then
                    mod._wiki_gap_logged[qid] = true
                    local nm = mod.name_cache[qid] or ("Quest " .. tostring(qid))
                    mlog_boot(string.format("[QT][wiki-gap] qid=%d %s missing step_order (fallback=%s)",
                        qid, nm, wf.has_fallback and "yes" or "no"))
                end
            end
        end
    end

    -- Called once when user opens a quest row (not every frame).
    function ctx.log_quest_expand(q, c)
        local qid = q.id
        local step = (c and c.step_title) or "(none)"
        local field = (mod._step_field_src and mod._step_field_src[qid]) or "-"
        local low = (q.name or ""):lower()
        local tag = (qid == 20200 or low:find("sphinx") or low:find("wits") or low:find("riddle")) and " SPHINX" or ""
        local done = "?"
        local task_idx = "?"
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        if mod._quest_progress_done_count and qlm then
            local ok_d, d = pcall(mod._quest_progress_done_count, qlm, qid)
            if ok_d then done = tostring(d) end
        end
        if mod._quest_current_task_index and qlm then
            local ok_ti, ti = pcall(mod._quest_current_task_index, qlm, qid)
            if ok_ti and ti ~= nil then task_idx = tostring(ti) end
        end
        local src = (c and c.step_from_game) and "game" or ((c and c.wiki_progress) and "wiki" or "other")
        mlog_boot(string.format("[QT][expand] qid=%d%s %s step=%s done=%s task_idx=%s field=%s src=%s progress=%s",
            qid, tag, q.name or "?", step:sub(1, 72), done, task_idx, field, src,
            tostring(c and c.wiki_progress)))
        if c and q.category == "Ongoing" then
            local want_s = "-"
            if c._want and #c._want > 0 then
                local parts = {}
                for _, w in ipairs(c._want) do parts[#parts + 1] = w:sub(1, 1):upper() .. w:sub(2) end
                want_s = table.concat(parts, ",")
            end
            local cid_s = "-"
            if c._givers and #c._givers > 0 then
                local cp = {}
                for _, gc in ipairs(c._givers) do cp[#cp + 1] = tostring(gc) end
                cid_s = table.concat(cp, ",")
            end
            local hrs_s, pos_s = "-", "-"
            if c.npc_rows and #c.npc_rows > 0 then
                local hp, pp = {}, {}
                for _, nr in ipairs(c.npc_rows) do
                    if type(nr.label) == "string" and nr.label:find("%(", 1, true) then
                        hp[#hp + 1] = nr.label
                    end
                    local nm = nr.nm or "?"
                    if nr.tp_ready then
                        pp[#pp + 1] = nm .. "=ok"
                    else
                        pp[#pp + 1] = nm .. "=miss"
                    end
                end
                if #hp > 0 then hrs_s = table.concat(hp, ",") end
                if #pp > 0 then pos_s = table.concat(pp, ",") end
            end
            mlog_boot(string.format("[QT][npc] qid=%d want=%s step=%s cids=%s missing=%s hours=%s pos=%s",
                qid, want_s, step:sub(1, 48), cid_s, c.missing_npc or "none", hrs_s, pos_s))
            -- #region agent log
            if qid == 30220 and c.npc_rows then
                for _, nr in ipairs(c.npc_rows) do
                    mlog_boot(string.format("[QT][dbg62] hyp=H3 expand qid=30220 nm=%s live=%s tp_ready=%s src=%s",
                        tostring(nr.nm), nr.live_npc and "1" or "0", nr.tp_ready and "1" or "0", tostring(nr.pos_src or "-")))
                end
            end
            -- #endregion
        end
        if not mod.debug_logging and not mod.deep_sniff then return end
        mlog(string.format("[QT][expand] qid=%d %s [%s] (one-shot)", qid, q.name or "?", q.category or "?"))
        if mod._steps_probe_qid then pcall(mod._steps_probe_qid, qid) end
        if mod.deep_sniff and mod.deep_sniff_heavy and mod._sniff_dump_qid then
            pcall(mod._sniff_dump_qid, qid, "expand")
        end
        if not mod.debug_logging then return end

        if not c then
            mlog_boot("[QT][expand] cache=MISSING → UI: loading row")
            return
        end

        local field = (mod._step_field_src and mod._step_field_src[qid]) or "-"
        local n_tips = (c.tips and #c.tips) or 0
        local n_wiki = (c.wiki_lines and #c.wiki_lines) or 0
        local n_npc = (c.npc_rows and #c.npc_rows) or 0

        if q.category == "Ongoing" then
            mlog(string.format("[QT][expand] step=%s field=%s wiki_fb=%s game=%s sniff=%s",
                c.step_title or "(none)", field, tostring(c.wiki_fallback), tostring(c.step_from_game),
                mod.deep_sniff and "ON" or "OFF"))
            mlog(string.format("[QT][expand] UI: tips=%d wiki_lines=%d npcs=%d detail=%s",
                n_tips, n_wiki, n_npc, (c.step_detail and "yes") or "no"))
            if not c.step_title and n_tips == 0 and n_wiki == 0 then
                mlog("[QT][expand] STILL UNKNOWN — select quest in game journal then re-expand")
            elseif not c.step_title then
                mlog("[QT][expand] STEP UNKNOWN — showing wiki/tips fallback")
            end
        end

        local wf = _wiki_flags(qid)
        if wf then
            mlog(string.format("[QT][expand] wiki: lines=%s fallback=%s order=%s hints=%s",
                wf.has_lines and "yes" or "NO", wf.has_fallback and "yes" or "NO",
                wf.has_order and "yes" or "no", wf.has_step_hints and "yes" or "NO"))
        end
    end
end

return M
