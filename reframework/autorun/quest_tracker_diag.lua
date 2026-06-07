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
        if mod._quest_progress_done_count then
            local qlm = sdk.get_managed_singleton("app.QuestLogManager")
            local ok_d, d = pcall(mod._quest_progress_done_count, qlm, qid)
            if ok_d then done = tostring(d) end
        end
        mlog_boot(string.format("[QT][expand] qid=%d%s %s step=%s done=%s field=%s progress=%s",
            qid, tag, q.name or "?", step:sub(1, 72), done, field,
            tostring(c and c.wiki_progress)))
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
