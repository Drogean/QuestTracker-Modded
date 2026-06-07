-- quest_tracker_autolock.lua — milestone / NPC-vanish auto-lock (local limit headroom)
local M = {}

function M.install(ctx)
    local mod = ctx.mod
    local mlog = ctx.mlog
    local QD = ctx.QD
    local LOCKED_QUESTS = ctx.LOCKED_QUESTS
    local VOIDED_QUESTS = ctx.VOIDED_QUESTS
    local BUNDLED_LOCKOUTS = ctx.BUNDLED_LOCKOUTS
    local MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
    local mark_prefs_dirty = ctx.mark_prefs_dirty
    local qd_locked_if = ctx.qd_locked_if
    local qd_givers_display_order = ctx.qd_givers_display_order
    local qd_givers = ctx.qd_givers
    local get_character_world_pos = ctx.get_character_world_pos

    local function is_milestone_completed(mid)
        return mod.completed_ids[mid] == true
    end

    function ctx.run_autolock()
        for qid, bl in pairs(BUNDLED_LOCKOUTS) do
            if not LOCKED_QUESTS[qid]
            and type(bl.after) == "number"
            and is_milestone_completed(bl.after)
            and mod.acceptable_ids[qid]
            and not mod.progressing_ids[qid]
            and not mod.completed_ids[qid] then
                LOCKED_QUESTS[qid] = true; VOIDED_QUESTS[qid] = true
                mark_prefs_dirty()
                mlog("[AUTOLOCK] qid=" .. qid .. " milestone=" .. bl.after .. " passed")
            end
        end

        if QD and QD.get_locked_if_completed then
            for _, q in ipairs(mod.quests or {}) do
                local qid = q.id
                if not LOCKED_QUESTS[qid] and mod.acceptable_ids[qid]
                and not mod.progressing_ids[qid] and not mod.completed_ids[qid] then
                    local lic = qd_locked_if(qid)
                    if lic then
                        for _, blocker in ipairs(lic) do
                            if mod.completed_ids[blocker] then
                                LOCKED_QUESTS[qid] = true; VOIDED_QUESTS[qid] = true
                                mark_prefs_dirty()
                                mlog(string.format("[AUTOLOCK] qid=%d blocker=%d done (locked_if_completed)", qid, blocker))
                                break
                            end
                        end
                    end
                end
            end
        end

        for _, q in ipairs(mod.quests or {}) do
            local qid = q.id
            if not LOCKED_QUESTS[qid] and mod.acceptable_ids[qid]
            and not mod.progressing_ids[qid] and not mod.completed_ids[qid] then
                local givers = {}
                local gst = qd_givers_display_order(qid) or qd_givers(qid)
                if gst then for _, c in ipairs(gst) do if c and c > 0 then givers[#givers + 1] = c end end end
                local gov = MANUAL_GIVER_OVERRIDES[qid]; if gov and gov > 0 then givers[#givers + 1] = gov end
                if #givers > 0 then
                    local any_in_world = false
                    for _, cid in ipairs(givers) do
                        if get_character_world_pos(cid) then any_in_world = true; break end
                    end
                    if not any_in_world then
                        local base = math.floor(qid / 100) * 100
                        local line_advanced = false
                        for _, q2 in ipairs(mod.quests or {}) do
                            if q2.id > qid and q2.id < base + 100 then
                                if mod.progressing_ids[q2.id] or mod.completed_ids[q2.id] then
                                    line_advanced = true; break
                                end
                            end
                        end
                        if line_advanced then
                            LOCKED_QUESTS[qid] = true; VOIDED_QUESTS[qid] = true
                            mark_prefs_dirty()
                            mlog("[AUTOLOCK] qid=" .. qid .. " NPC vanished + line advanced")
                        end
                    end
                end
            end
        end
    end
end

return M
