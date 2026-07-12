-- quest_tracker_map.lua — map pins / icons (require from quest_tracker.lua)
-- REFramework also runs every autorun/*.lua; return cached module so install() is not wiped.

local MAP_MOD_VER = "1.4.48"
local M = package.loaded["quest_tracker_map"]
if M and M._map_mod_ver == MAP_MOD_VER then return M end
M = { _map_mod_ver = MAP_MOD_VER }

local mod, mlog, mlog_boot, qt_verbose, td, safe_get_field, safe_call, safe_dict_get, iter_list, to_int
local _guid_to_en_text

local function _mlog_map(...)
    if mlog_boot then mlog_boot(...)
    elseif mlog then mlog(...) end
end
local cid_eq, cid_norm, get_character_world_pos, mark_prefs_dirty
local try_upgrade_fallback_pins  -- forward decl: defined after unpin_quest
local _pin_available_at          -- forward decl: used by _pin_first_step_giver
local QD
local MANUAL_POS_OVERRIDES, BUNDLED_POS_OVERRIDES, HYBRID_AREA_QIDS, BLOB_AREA_QIDS, MANUAL_GIVER_OVERRIDES, ELIMINATED_OVERRIDES, BUNDLED_GIVER_OVERRIDES
local is_bundled_giver, qd_givers, qd_givers_display_order, TAB_NAMES, get_all_giver_cids

local MAP_API = {
    ready             = false,
    gm                = nil,
    pinned_data       = {},
    pinned_pos        = {},
    pinned_label_pos  = {},
    eliminated_pos    = {},
    _fallback_pending_upgrade = {},  -- qids pinned via npc-ongoing/step-npc fallback, awaiting live upgrade
    status            = "not initialized",
    last_msg          = "",
}

local Labels = require("quest_tracker_map_labels")

local function _td(name)
    if type(td) == "function" then return td(name) end
    return sdk.find_type_definition(name)
end

function M.install(ctx)
    if type(ctx) ~= "table" then return false end
    mod = ctx.mod
    mlog = ctx.mlog
    mlog_boot = ctx.mlog_boot
    qt_verbose = ctx.qt_verbose
    td = ctx.td
    safe_get_field = ctx.safe_get_field
    safe_call = ctx.safe_call
    safe_dict_get = ctx.safe_dict_get
    iter_list = ctx.iter_list
    to_int = ctx.to_int
    cid_eq = ctx.cid_eq
    cid_norm = ctx.cid_norm
    get_character_world_pos = ctx.get_character_world_pos
    mark_prefs_dirty = ctx.mark_prefs_dirty
    MANUAL_POS_OVERRIDES = ctx.MANUAL_POS_OVERRIDES
    BUNDLED_POS_OVERRIDES = ctx.BUNDLED_POS_OVERRIDES
    HYBRID_AREA_QIDS = ctx.HYBRID_AREA_QIDS
    BLOB_AREA_QIDS = ctx.BLOB_AREA_QIDS
    MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
    ELIMINATED_OVERRIDES = ctx.ELIMINATED_OVERRIDES
    BUNDLED_GIVER_OVERRIDES = ctx.BUNDLED_GIVER_OVERRIDES
    is_bundled_giver = ctx.is_bundled_giver
    qd_givers = ctx.qd_givers
    qd_givers_display_order = ctx.qd_givers_display_order
    TAB_NAMES = ctx.TAB_NAMES
    get_all_giver_cids = ctx.get_all_giver_cids
    QD = ctx.QD
    _guid_to_en_text = ctx._guid_to_en_text
    Labels.install(ctx, MAP_API)
    Labels.set_hybrid_qids(HYBRID_AREA_QIDS)
    if type(ELIMINATED_OVERRIDES) == "table" then
        for qid, arr in pairs(ELIMINATED_OVERRIDES) do
            MAP_API.eliminated_pos[qid] = {}
            for _, p in ipairs(arr) do
                table.insert(MAP_API.eliminated_pos[qid], { cid = p.cid, x = p.x, y = p.y, z = p.z })
            end
        end
    end
    return true
end

-- =========== MAP MARKER API ===========
local HOOK_INSTALLED = false
local JOURNAL_PIN_FRAME_HOOK = false

local function get_marker_list()
    local gm = sdk.get_managed_singleton("app.GuiManager")
    if gm == nil then return nil, nil end
    local ok, list = pcall(function() return gm:call("get_QuestTargetMarkerList") end)
    if ok then return list, gm end
    return nil, gm
end

local function build_marker(dest, qid)
    local gm = MAP_API.gm or sdk.get_managed_singleton("app.GuiManager")
    if gm == nil or dest == nil then return nil end
    local ok, m = pcall(function() return gm:call("makeQuestTargetMarkerInfo", dest, qid) end)
    return ok and m or nil
end

local function build_marker_at_pos(wx, wy, wz, qid)
    local t2 = _td("app.GuiManager.QuestTargetMarkerInfo")
    if t2 == nil then return nil end
    local ok, m = pcall(function() return t2:create_instance():add_ref() end)
    if not ok or m == nil then return nil end
    pcall(function()
        m.DestType = 3; m.IconType = 0; m.KeyLocation = 0
        m.LocalArea = 0; m.MapArea = 0
        m.Pos = Vector3f.new(wx, wy, wz)
    end)
    return m
end

local function _pin_complete(msg)
    MAP_API.last_msg = msg
    _mlog_map("[PIN] " .. msg)
    force_marker_refresh()
    return true
end

local function _pin_done(msg, defer_refresh)
    if defer_refresh then
        MAP_API.last_msg = msg
        _mlog_map("[PIN] " .. msg)
        return true
    end
    return _pin_complete(msg)
end

local function _try_add_yellow_marker(list, qid, marker)
    if list == nil or marker == nil then return false end
    MAP_API._diamond_on_list = MAP_API._diamond_on_list or {}
    if MAP_API._diamond_on_list[qid] then
        return false
    end
    pcall(function() list:call("Add", marker) end)
    MAP_API._diamond_on_list[qid] = true
    return true
end

local function _mark_diamond_on_list(qid)
    MAP_API._diamond_on_list = MAP_API._diamond_on_list or {}
    MAP_API._diamond_on_list[qid] = true
end

local function _sculpt_skip_mod_blob_reinject(qid, ui)
    if mod == nil or ui == nil then return false end
    if mod._qt_journal_qid ~= qid and mod._qt_priority_qid ~= qid then return false end
    local detail = safe_get_field(ui, "IsDetailMap")
    if detail == true then
        if not MAP_API._vanilla_blob_skip_logged then
            MAP_API._vanilla_blob_skip_logged = true
            _mlog_map(string.format("[QT][map] sculpt reinject skip blob qid=%d vanilla_blob_active=1", qid))
        end
        return true
    end
    return false
end

local function reinject_all()
    local list = get_marker_list()
    if list == nil then return 0 end
    MAP_API._blob_reinject_this_hook = MAP_API._blob_reinject_this_hook or {}
    local n = 0
    for qid, entry in pairs(MAP_API.pinned_data) do
        if MAP_API._journal_label_only and MAP_API._journal_label_only[qid] then
            -- MAIN: game owns the diamond; QT only adds name banner
        elseif BLOB_AREA_QIDS and BLOB_AREA_QIDS[qid] then
            if UI_MAP and _sculpt_skip_mod_blob_reinject(qid, UI_MAP) then
                -- vanilla draws area blob on detail map
            elseif MAP_API._pin_added_this_hook and MAP_API._pin_added_this_hook[qid] then
                -- pin_quest already added markers this hook
            elseif not MAP_API._blob_reinject_this_hook[qid] then
                MAP_API._blob_reinject_this_hook[qid] = true
                for _, dest in ipairs(entry) do
                    local marker = build_marker(dest, qid)
                    if marker and _try_add_yellow_marker(list, qid, marker) then n = n + 1 end
                end
                local wm = UI_MAP and safe_get_field(UI_MAP, "IsWorldMap")
                _mlog_map(string.format("[QT][map] sculpt reinject blob qid=%d world=%s", qid, wm == true and "1" or "0"))
            end
        else
            for _, dest in ipairs(entry) do
                local marker = build_marker(dest, qid)
                if marker and _try_add_yellow_marker(list, qid, marker) then n = n + 1 end
            end
        end
    end
    -- pinned_label_pos = text label anchor ONLY (no QuestTargetMarker diamond reinject)
    for qid, entry in pairs(MAP_API.pinned_pos) do
        if MAP_API._journal_label_only and MAP_API._journal_label_only[qid] then
            -- skip diamond for MAIN label-only
        elseif MAP_API.pinned_data[qid] == nil then
            for _, p in ipairs(entry) do
                local marker = build_marker_at_pos(p.x, p.y, p.z, qid)
                if marker and _try_add_yellow_marker(list, qid, marker) then n = n + 1 end
            end
        end
    end
    return n
end

local function _marker_world_xyz(marker)
    if marker == nil then return nil end
    local p = safe_get_field(marker, "Pos") or safe_call(marker, "get_Pos")
    if p == nil then return nil end
    local x, y, z
    pcall(function() x, y, z = p.x, p.y, p.z end)
    if x == nil or (x == 0 and y == 0 and z == 0) then return nil end
    return x, y, z
end

-- =========== LABELED MAP ICONS (quest_tracker_map_labels.lua) ===========
local ICON_HOOK_INSTALLED = false
local UI_MAP = nil

local function get_quest_name_guid(qid)
    return Labels.get_quest_name_guid(qid)
end

get_quest_resource = function(qlm, qid)
    return Labels.get_quest_resource(qlm, qid)
end

local function _count_wanted_labels()
    return Labels.count_wanted_labels()
end

local function _log_map_zoom_once(ui)
    if not ui or (mod and mod._qt_map_zoom_logged) then return end
    if mod then mod._qt_map_zoom_logged = true end
    for _, fn in ipairs({ "IsWorldMap", "IsDetailMap", "IconScale", "IconRange" }) do
        local v = safe_get_field(ui, fn)
        if v == nil then pcall(function() v = ui:call("get_" .. fn) end) end
        if v ~= nil then
            _mlog_map(string.format("[QT][map] zoom field %s=%s", fn, tostring(v)))
        end
    end
end

-- =========== DEEP SNIFF MAP UI (no d2d) ===========
local function _fmt_sniff_val(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then
        if #v > 80 then return string.sub(v, 1, 80) .. "…" end
        return v
    end
    return nil
end

local function _sniff_field_match(name)
    if not name then return false end
    return name:find("Cursor") or name:find("Map") or name:find("Icon")
        or name:find("Select") or name:find("Pos") or name:find("Navi") or name:find("Area")
end

local function _sniff_map_ui_once(ui)
    if not mod or mod.deep_sniff ~= true then return end
    pcall(Labels.probe_api)
    if mod._qt_map_sniff_done then return end
    mod._qt_map_sniff_done = true
    local t2 = _td("app.ui040205")
    if t2 then
        pcall(function()
            for _, m in ipairs(t2:get_methods()) do
                local mn = m:get_name()
                if mn:find("Map") or mn:find("Icon") or mn:find("Cursor") or mn:find("Pos") then
                    _mlog_map("[QT][map][sniff] method: " .. mn)
                end
            end
        end)
    end
    if ui then
        pcall(function()
            local tdef = ui:get_type_definition()
            if tdef then
                local n = 0
                for _, f in ipairs(tdef:get_fields()) do
                    local fn = f:get_name()
                    if _sniff_field_match(fn) then
                        local ok2, v = pcall(function() return f:get_data(ui) end)
                        if ok2 then
                            local fs = _fmt_sniff_val(v)
                            if fs then
                                n = n + 1
                                _mlog_map(string.format("[QT][map][sniff] ui field: %s = %s", fn, fs))
                                if n >= 45 then break end
                            end
                        end
                    end
                end
            end
        end)
        local cnt = 0
        pcall(function() cnt = ui.MapIconInfoList:get_Count() end)
        _mlog_map(string.format("[QT][map][sniff] MapIconInfoList count=%d", cnt))
    end
end

local function install_icon_hook()
    if ICON_HOOK_INSTALLED then return true end
    local t2 = _td("app.ui040205")
    if t2 == nil then return false end
    local m_setup = t2:get_method("setupMapIcon")
    if m_setup == nil then return false end
    pcall(Labels.install_vanilla_sniff)
    local ok = pcall(function()
        sdk.hook(m_setup,
            function(args)
                UI_MAP = sdk.to_managed_object(args[2])
            end,
            function(retval)
                local this = UI_MAP
                if this ~= nil then
                    if mod then mod._qt_map_ui_active = true end
                    if mod and not mod._qt_map_open_logged then
                        mod._qt_map_open_logged = true
                        _mlog_map("[QT][map] setupMapIcon — map UI open")
                    end
                    pcall(Labels.probe_api)
                    pcall(_log_map_zoom_once, this)
                    pcall(_sniff_map_ui_once, this)
                    do
                        local wm = safe_get_field(this, "IsWorldMap")
                        local dm = safe_get_field(this, "IsDetailMap")
                        local la = safe_get_field(this, "LocalAreaNow")
                        local layer = string.format("%s|%s|%s", tostring(wm), tostring(dm), tostring(la))
                        if MAP_API._last_map_layer ~= layer then
                            MAP_API._map_icon_gen = (MAP_API._map_icon_gen or 0) + 1
                            MAP_API._last_map_layer = layer
                            MAP_API._blob_reinject_this_hook = {}
                            MAP_API._inject_done_for_gen = {}
                            Labels.on_layer_change()
                            _mlog_map(string.format("[QT][map] map layer change gen=%d world=%s detail=%s local=%s",
                                MAP_API._map_icon_gen, tostring(wm), tostring(dm), tostring(la)))
                            pcall(function() flush_journal_pin_pending("layer_change") end)
                        end
                    end
                    -- Diamonds once per layer gen (QuestTargetMarkerList does NOT reset).
                    -- Labels every setupMapIcon (MapIconInfoList does reset).
                    local gen = MAP_API._map_icon_gen or 0
                    MAP_API._inject_done_for_gen = MAP_API._inject_done_for_gen or {}
                    local reinjected = 0
                    if not MAP_API._inject_done_for_gen[gen] then
                        MAP_API._inject_done_for_gen[gen] = true
                        MAP_API._pin_added_this_hook = {}
                        pcall(queue_journal_pin_if_needed)
                        pcall(function() reinjected = reinject_all() end)
                        pcall(function() this:call("updateMapIcon") end)
                        MAP_API._pin_added_this_hook = {}
                    end
                    -- Test1: game MAIN diamond already on list but Lua label state empty
                    -- (flush blocked / deferred). Attach label here — marker XYZ is live.
                    do
                        local jqid = mod and mod._qt_journal_qid
                        if jqid and jqid > 0 then
                            local already = (MAP_API.pinned_label_pos and MAP_API.pinned_label_pos[jqid])
                                or (MAP_API.pinned_pos and MAP_API.pinned_pos[jqid])
                                or (MAP_API.pinned_data and MAP_API.pinned_data[jqid])
                            if not already then
                                local ok_p, pin_ok, pin_msg = pcall(pin_quest, jqid, true)
                                -- #region agent log
                                _mlog_map(string.format(
                                    "[QT][dbg62] hyp=H10 map_force_MAIN_label qid=%d ok=%s pin_ok=%s msg=%s",
                                    jqid, tostring(ok_p), tostring(pin_ok), tostring(pin_msg)))
                                -- #endregion
                                if ok_p and pin_ok and pin_msg ~= "journal-label-deferred" then
                                    MAP_API._journal_pin_pending = nil
                                    MAP_API._journal_pin_pending_frames = nil
                                end
                            end
                        end
                    end
                    local labels, want = 0, _count_wanted_labels()
                    pcall(function() labels = Labels.add_labeled_markers_for_all_pins(this) or 0 end)
                    pcall(function() this:call("updateMapIcon") end)
                    -- #region agent log
                    do
                        local marker_cnt = -1
                        local list = nil
                        pcall(function()
                            list = get_marker_list()
                            if list then marker_cnt = list:get_Count() end
                        end)
                        local jqid = (mod and mod._qt_journal_qid) or -1
                        _mlog_map(string.format(
                            "[QT][map] setupMapIcon gen=%d reinject=%d labels=%d want=%d markers=%d MAIN=%s",
                            gen, reinjected, labels, want, marker_cnt, tostring(jqid)))
                        -- H4/H7: dump marker XYZ once per gen when count != want (ghosts / extras)
                        MAP_API._marker_dump_gen = MAP_API._marker_dump_gen or {}
                        if list and marker_cnt >= 0 and want >= 0
                            and marker_cnt ~= want and not MAP_API._marker_dump_gen[gen] then
                            MAP_API._marker_dump_gen[gen] = true
                            local dump = {}
                            for i = 0, math.min(marker_cnt, 24) - 1 do
                                local mx, my, mz = nil, nil, nil
                                pcall(function()
                                    local mk = list:call("get_Item", i)
                                    if mk == nil then mk = list[i] end
                                    mx, my, mz = _marker_world_xyz(mk)
                                end)
                                if mx then
                                    dump[#dump + 1] = string.format("%d:%.0f,%.0f,%.0f", i, mx, my, mz)
                                else
                                    dump[#dump + 1] = string.format("%d:?", i)
                                end
                            end
                            _mlog_map(string.format(
                                "[QT][dbg62] hyp=H4 marker_dump gen=%d count=%d want=%d [%s]",
                                gen, marker_cnt, want, table.concat(dump, ";")))
                        end
                    end
                    -- #endregion
                end
                return retval
            end)
    end)
    if ok then ICON_HOOK_INSTALLED = true end
    local mD = t2:get_method("onDestroy")
    if mD then
        pcall(function()
            sdk.hook(mD, function() end, function(retval)
                UI_MAP = nil
                MAP_API._last_map_layer = nil
                MAP_API._blob_reinject_this_hook = {}
                if mod then
                    mod._qt_map_ui_active = false
                    mod._qt_map_sniff_done = nil
                    mod._qt_map_zoom_logged = nil
                    mod._qt_map_open_logged = nil
                    local sdk_close = 1.0
                    mod._qt_map_close_until = os.clock() + sdk_close
                    mod._qt_sdk_suppress_until = os.clock() + sdk_close
                    mod._qt_post_save_block_until = math.max(mod._qt_post_save_block_until or 0, os.clock() + sdk_close)
                    mlog_boot("[QT] map_close sdk=" .. tostring(sdk_close) .. "s (overlay never blocked)")
                end
                MAP_API._journal_pin_pending = nil
                MAP_API._journal_pin_pending_frames = nil
                MAP_API._journal_pin_log_once = nil
                MAP_API._pin_added_this_hook = {}
                return retval
            end)
        end)
    end
    return ICON_HOOK_INSTALLED
end

local _init_map_api_logged = false
init_map_api = function()
    if not ICON_HOOK_INSTALLED then pcall(install_icon_hook) end
    if MAP_API.ready then return true end
    MAP_API.gm = sdk.get_managed_singleton("app.GuiManager")
    if MAP_API.gm == nil then MAP_API.status = "GuiManager nil"; qt_verbose("init_map_api: GuiManager nil (too early?)"); return false end
    local t2 = _td("app.GuiManager")
    if t2 == nil then MAP_API.status = "GuiManager type nil"; qt_verbose("init_map_api: GuiManager type missing"); return false end
    if not HOOK_INSTALLED then
        local m_setup = t2:get_method("setupQuestTargetMarker")
        if m_setup then
            local ok = pcall(function()
                sdk.hook(m_setup, function() end, function(r)
                    -- Game rebuilt QuestTargetMarkerList — our prior Adds are gone.
                    MAP_API._diamond_on_list = {}
                    pcall(function() flush_journal_pin_pending("setupQuestTargetMarker") end)
                    pcall(reinject_all)
                    return r
                end)
            end)
            if ok then HOOK_INSTALLED = true end
            qt_verbose("setupQuestTargetMarker hook: ok=" .. tostring(ok))
        else
            qt_verbose("setupQuestTargetMarker: method not found")
        end
    end
    install_icon_hook()
    MAP_API.ready = true
    MAP_API.status = "ok hook=" .. tostring(HOOK_INSTALLED) .. " iconhook=" .. tostring(ICON_HOOK_INSTALLED)
    if not JOURNAL_PIN_FRAME_HOOK then
        JOURNAL_PIN_FRAME_HOOK = true
        re.on_frame(function()
            local pending = MAP_API._journal_pin_pending
            if pending and pending > 0 then
                MAP_API._journal_pin_pending_frames = (MAP_API._journal_pin_pending_frames or 0) + 1
                if MAP_API._journal_pin_pending_frames < 30 then return end
                local now = os.clock()
                local last = MAP_API._journal_pin_defer_last_try or 0
                if (now - last) < 0.5 then return end
                MAP_API._journal_pin_defer_last_try = now
                _mlog_map(string.format("[QT][map] auto-pin defer frame=%d qid=%d",
                    MAP_API._journal_pin_pending_frames, pending))
                pcall(function() flush_journal_pin_pending("on_frame") end)
                return
            end
            -- No journal pending: periodically try upgrading fallback-pinned ongoing quests
            if next(MAP_API._fallback_pending_upgrade) then
                MAP_API._upgrade_frame_tick = (MAP_API._upgrade_frame_tick or 0) + 1
                if MAP_API._upgrade_frame_tick >= 300 then
                    MAP_API._upgrade_frame_tick = 0
                    pcall(try_upgrade_fallback_pins)
                end
            end
        end)
    end
    if not _init_map_api_logged then
        _init_map_api_logged = true
        qt_verbose("init_map_api: ready — " .. MAP_API.status)
        _mlog_map(string.format("[QT][map] init ok hook=%s iconhook=%s",
            tostring(HOOK_INSTALLED), tostring(ICON_HOOK_INSTALLED)))
    end
    return true
end

-- v1.4.0: never RemoveAt QuestTargetMarkerList — clear Lua pin state, let game rebuild.
clear_injected_markers = function()
    local diamonds = 0
    for _ in pairs(MAP_API.pinned_data or {}) do diamonds = diamonds + 1 end
    for _ in pairs(MAP_API.pinned_pos or {}) do diamonds = diamonds + 1 end
    local markers_before = -1
    pcall(function()
        local list = get_marker_list()
        if list then markers_before = list:get_Count() end
    end)
    local jqid = (mod and mod._qt_journal_qid) or -1
    MAP_API.pinned_data = {}
    MAP_API.pinned_pos = {}
    MAP_API.pinned_label_pos = {}
    MAP_API._journal_label_only = {}
    MAP_API._fallback_pending_upgrade = {}
    MAP_API._diamond_on_list = {}
    MAP_API._journal_pin_log_once = nil
    MAP_API._journal_pin_pending = nil
    MAP_API._journal_pin_pending_frames = nil
    MAP_API._qt_injected_labels = {}
    MAP_API._qt_injected_label_idxs = {}
    MAP_API.last_msg = "pins cleared"
    force_marker_refresh()
    local markers_after = -1
    pcall(function()
        local list = get_marker_list()
        if list then markers_after = list:get_Count() end
    end)
    _mlog_map(string.format(
        "[QT][map] clear done pins=%d markers %d→%d MAIN=%s (no list wipe)",
        diamonds, markers_before, markers_after, tostring(jqid)))
    -- Always restore MAIN name banner (game diamond stays). Not gated on auto_pin_journal —
    -- Clear wipes Lua label state; without this, want=0 and MAIN stays unlabeled (Test2 FAIL).
    if jqid and jqid > 0 then
        local ok_m, pin_ok = pcall(pin_quest, jqid, true)
        -- #region agent log
        _mlog_map(string.format(
            "[QT][dbg62] hyp=H9 clear_restore_MAIN qid=%d ok=%s pin_ok=%s",
            jqid, tostring(ok_m), tostring(pin_ok)))
        -- #endregion
        if not (ok_m and pin_ok) then
            MAP_API._journal_pin_pending = jqid
            MAP_API._journal_pin_pending_frames = 0
            _mlog_map(string.format("[QT][map] clear MAIN restore deferred qid=%d", jqid))
        end
    end
    if mod and (mod.auto_pin_ongoing or mod.auto_pin_available) then
        local av_n, on_n = 0, 0
        for _, q in ipairs(mod.quests or {}) do
            if not q.voided then
                if q.category == "Available" and mod.auto_pin_available then av_n = av_n + 1 end
                if q.category == "Ongoing" and mod.auto_pin_ongoing then on_n = on_n + 1 end
            end
        end
        pcall(run_autopin_if_enabled)
        _mlog_map(string.format("[QT][map] clear repin available=%d ongoing=%d", av_n, on_n))
    end
end

force_marker_refresh = function()
    if MAP_API._refreshing then return end
    MAP_API._refreshing = true
    pcall(function()
        local gm = MAP_API.gm or sdk.get_managed_singleton("app.GuiManager")
        if gm then gm:call("setupQuestTargetMarker") end
    end)
    MAP_API._refreshing = false
end



local GIVER_CACHE = {}
get_quest_cast_charaids = function(qid)
    if GIVER_CACHE[qid] ~= nil then return GIVER_CACHE[qid] end
    local qm = sdk.get_managed_singleton("app.QuestManager")
    if qm == nil then return nil end
    local qcd = safe_get_field(qm, "QuestCatalogDict")
    if qcd == nil then return nil end
    local vals = safe_call(qcd, "getValues")
    if vals == nil then return nil end
    local cdsz = 0; pcall(function() cdsz = vals:get_size() end)
    for k = 0, cdsz - 1 do
        local ok, cd = pcall(function() return vals:get_element(k) end)
        if ok and cd then
            local ctx = safe_get_field(cd, "ContextData")
            if ctx then
                local arr = safe_get_field(ctx, "ContextDataArray")
                if arr then
                    local asz = 0; pcall(function() asz = arr:get_size() end)
                    for j = 0, asz - 1 do
                        local okE, e = pcall(function() return arr:get_element(j) end)
                        if okE and e then
                            if to_int(safe_get_field(e, "_IDValue")) == qid then
                                local cast = safe_get_field(e, "CastNPCIDs")
                                local out = {}
                                if cast then
                                    local csz = 0; pcall(function() csz = cast:get_size() end)
                                    for m2 = 0, csz - 1 do
                                        local okF, item = pcall(function() return cast:get_element(m2) end)
                                        if okF and item then
                                            local n = to_int(item)
                                            if n then out[#out+1] = n end
                                        end
                                    end
                                end
                                GIVER_CACHE[qid] = out; return out
                            end
                        end
                    end
                end
            end
        end
    end
    GIVER_CACHE[qid] = false; return nil
end

local function get_quest_destinations(qlm, qid)
    local res = get_quest_resource(qlm, qid)
    if res == nil then return nil end
    local first_tasks = safe_call(res, "get_FirstTaskList") or safe_get_field(res, "_FirstTaskList")
    if first_tasks == nil then return nil end
    local out = {}
    iter_list(first_tasks, function(task)
        local dests = safe_call(task, "getActiveDestinations") or safe_call(task, "get_Destinations")
                   or safe_get_field(task, "_Destinations")
        if dests == nil then return end
        local sz2 = 0; pcall(function() sz2 = dests:get_size() end)
        for i = 0, sz2 - 1 do
            local ok, d = pcall(function() return dests:get_element(i) end)
            if ok and d then out[#out+1] = d end
        end
    end)
    return #out > 0 and out or nil
end

local function _info_dict_entry(qlm, qid)
    local dict = safe_get_field(qlm, "_QuestLogInfoDict")
    if dict == nil then return nil end
    local want = tonumber(qid) or qid
    if safe_dict_get then
        return safe_dict_get(dict, qid) or safe_dict_get(dict, want)
    end
    return nil
end

local function get_live_info_destinations(qlm, qid)
    local entry = _info_dict_entry(qlm, qid)
    if entry == nil then return nil end
    local cds = safe_get_field(entry, "_CurrentDestinations")
    if cds == nil then return nil end
    local out = {}
    iter_list(cds, function(d)
        if d then out[#out + 1] = d end
    end)
    return #out > 0 and out or nil
end

local function _sniff_dest_once(qid, dests)
    if mod == nil or mod.deep_sniff ~= true then return end
    if dests == nil or #dests == 0 then return end
    MAP_API._dest_sniff_logged = MAP_API._dest_sniff_logged or {}
    if MAP_API._dest_sniff_logged[qid] then return end
    MAP_API._dest_sniff_logged[qid] = true
    local dest = dests[1]
    local parts = {}
    for _, fn in ipairs({ "DestType", "IconType", "Radius", "KeyLocation", "LocalArea", "MapArea" }) do
        local v = safe_get_field(dest, fn) or safe_call(dest, "get_" .. fn)
        if v ~= nil then parts[#parts + 1] = fn .. "=" .. tostring(v) end
    end
    _mlog_map(string.format("[QT][map][sniff] dest qid=%d %s", qid, table.concat(parts, " ")))
end

local function _extract_dest_xyz(dests, qid)
    local marker = build_marker(dests[1], qid)
    if marker then
        local x, y, z = _marker_world_xyz(marker)
        if x then return x, y, z end
    end
    local dest = dests[1]
    local p = safe_get_field(dest, "Pos") or safe_call(dest, "get_Pos")
    if p then
        local x, y, z
        pcall(function() x, y, z = p.x, p.y, p.z end)
        if x then return x, y, z end
    end
    return nil
end

local function _journal_already_pinned(qid)
    return MAP_API.pinned_pos[qid] ~= nil
        or MAP_API.pinned_label_pos[qid] ~= nil
        or MAP_API.pinned_data[qid] ~= nil
end

-- Read world XYZ from an existing game QuestTargetMarker (MAIN journal diamond).
local function _read_game_marker_xyz(list)
    if list == nil then return nil end
    local cnt = 0
    pcall(function() cnt = list:get_Count() end)
    if cnt <= 0 then return nil end
    for i = 0, cnt - 1 do
        local marker = nil
        pcall(function() marker = list:get_Item(i) end)
        if marker == nil then pcall(function() marker = list:call("get_Item", i) end) end
        local x, y, z = _marker_world_xyz(marker)
        if x then return x, y, z end
    end
    return nil
end

-- MAIN journal: label the game's own diamond — never Add a second custom diamond.
local function _pin_journal_label_only(qid, list, defer_refresh)
    local x, y, z = _read_game_marker_xyz(list)
    local src = "game_marker"
    if x == nil then
        local qlm = sdk.get_managed_singleton("app.QuestLogManager")
        local live = qlm and get_live_info_destinations(qlm, qid)
        if live then
            x, y, z = _extract_dest_xyz(live, qid)
            src = "live_dest"
        end
    end
    if x == nil then
        return nil
    end
    MAP_API._journal_label_only = MAP_API._journal_label_only or {}
    MAP_API._journal_label_only[qid] = true
    MAP_API.pinned_data[qid] = nil
    MAP_API.pinned_pos[qid] = nil
    MAP_API.pinned_label_pos[qid] = { x = x, y = y, z = z }
    MAP_API._fallback_pending_upgrade[qid] = nil
    -- #region agent log
    _mlog_map(string.format("[QT][dbg62] hyp=H6 journal_label_only qid=%d src=%s xyz=%.0f,%.0f,%.0f",
        qid, src, x, y, z))
    -- #endregion
    _mlog_map(string.format("[QT][map] pin MAIN label-only qid=%d src=%s (no diamond add)", qid, src))
    return _pin_done(string.format("pinned qid=%d journal-label-only src=%s", qid, src), defer_refresh)
end

local function _journal_pin_log_once(key, msg)
    MAP_API._journal_pin_log_once = MAP_API._journal_pin_log_once or {}
    if MAP_API._journal_pin_log_once[key] then return end
    MAP_API._journal_pin_log_once[key] = true
    _mlog_map(msg)
end

flush_journal_pin_pending = function(from_tag)
    if mod then
        if not mod._game_ready then
            -- #region agent log
            _journal_pin_log_once("flush_not_ready",
                string.format("[QT][dbg62] hyp=H10 flush_block reason=not_ready from=%s", tostring(from_tag)))
            -- #endregion
            return false
        end
        if mod._qt_game_ready_at and os.clock() < mod._qt_game_ready_at + 5.0 then
            -- #region agent log
            _journal_pin_log_once("flush_grace",
                string.format("[QT][dbg62] hyp=H10 flush_block reason=boot_grace from=%s", tostring(from_tag)))
            -- #endregion
            return false
        end
        if mod._qt_is_draw_suppressed and mod._qt_is_draw_suppressed() then
            -- #region agent log
            _journal_pin_log_once("flush_suppress",
                string.format("[QT][dbg62] hyp=H10 flush_block reason=draw_suppress from=%s", tostring(from_tag)))
            -- #endregion
            return false
        end
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if gm then
            local blocked = false
            pcall(function()
                if gm:get_IsLoadGui() == true then blocked = true end
            end)
            if blocked then
                -- #region agent log
                _journal_pin_log_once("flush_loadgui",
                    string.format("[QT][dbg62] hyp=H10 flush_block reason=load_gui from=%s", tostring(from_tag)))
                -- #endregion
                return false
            end
        end
    end
    local pending = MAP_API._journal_pin_pending
    if pending == nil or pending <= 0 then return false end
    if not init_map_api() then
        _mlog_map(string.format("[QT][map] auto-pin FAIL err=map_api_init qid=%d from=%s",
            pending, tostring(from_tag)))
        return false
    end
    if _journal_already_pinned(pending) then
        MAP_API._journal_pin_pending = nil
        MAP_API._journal_pin_pending_frames = nil
        _journal_pin_log_once("skip_pinned_" .. pending,
            string.format("[QT][map] auto-pin skip already_pinned qid=%d from=%s", pending, tostring(from_tag)))
        return true
    end
    local list = get_marker_list()
    if list == nil then
        _mlog_map(string.format("[QT][map] auto-pin FAIL err=list_nil qid=%d from=%s",
            pending, tostring(from_tag)))
        return false
    end
    local ok_pin, pin_ok, pin_err = pcall(pin_quest, pending, true)
    -- Deferred = still waiting for game marker — keep pending (do not treat as OK).
    if ok_pin and pin_ok and pin_err == "journal-label-deferred" then
        _mlog_map(string.format("[QT][map] auto-pin still deferred qid=%d from=%s", pending, tostring(from_tag)))
        return false
    end
    if ok_pin and pin_ok then
        MAP_API._journal_pin_pending = nil
        MAP_API._journal_pin_pending_frames = nil
        MAP_API._journal_pin_defer_last_try = nil
        _mlog_map(string.format("[QT][map] auto-pin OK qid=%d from=%s", pending, tostring(from_tag)))
        if not MAP_API._refreshing then force_marker_refresh() end
        pcall(try_upgrade_fallback_pins)
        return true
    end
    local err = (not ok_pin) and tostring(pin_ok) or tostring(pin_err)
    _mlog_map(string.format("[QT][map] auto-pin FAIL err=%s qid=%d from=%s", err, pending, tostring(from_tag)))
    return false
end

queue_journal_pin_if_needed = function()
    if mod == nil then
        _journal_pin_log_once("mod_nil", "[QT][map] auto-pin skip mod_nil")
        return
    end
    if mod.auto_pin_journal == false then
        _journal_pin_log_once("pref_off", "[QT][map] auto-pin skip pref_off")
        return
    end
    local jqid = mod._qt_journal_qid
    if jqid == nil or jqid <= 0 then
        _journal_pin_log_once("jqid0", "[QT][map] auto-pin skip jqid=0")
        return
    end
    if _journal_already_pinned(jqid) then
        if MAP_API._journal_pin_pending == jqid then MAP_API._journal_pin_pending = nil end
        _journal_pin_log_once("already_" .. jqid,
            string.format("[QT][map] auto-pin skip already_pinned qid=%d", jqid))
        return
    end
    if MAP_API._journal_pin_pending == jqid then return end
    MAP_API._journal_pin_pending = jqid
    MAP_API._journal_pin_pending_frames = 0
    MAP_API._journal_pin_defer_last_try = nil
    _mlog_map(string.format("[QT][map] auto-pin queued qid=%d", jqid))
end

local function on_journal_qid_changed(new_qid)
    MAP_API._journal_pin_pending = nil
    MAP_API._journal_pin_pending_frames = nil
    MAP_API._journal_pin_log_once = nil
    if new_qid and new_qid > 0 and mod and mod.auto_pin_journal ~= false then
        if not _journal_already_pinned(new_qid) then
            MAP_API._journal_pin_pending = new_qid
            MAP_API._journal_pin_pending_frames = 0
            _mlog_map(string.format("[QT][map] auto-pin re-queue journal change qid=%d", new_qid))
        end
    end
end

local function _pin_sculpt_quest(qid, list, dests, defer_refresh, anchor_src)
    _sniff_dest_once(qid, dests)
    local added = 0
    local label_anchor = nil
    local skip_blob = UI_MAP ~= nil and _sculpt_skip_mod_blob_reinject(qid, UI_MAP)
    if not skip_blob then
        for _, dest in ipairs(dests) do
            local marker = build_marker(dest, qid)
            if marker then
                local okA = pcall(function() list:call("Add", marker) end)
                if okA then
                    added = added + 1
                    if label_anchor == nil then
                        local x, y, z = _marker_world_xyz(marker)
                        if x then label_anchor = { x = x, y = y, z = z } end
                    end
                end
            end
        end
        if added == 0 then return false, "no sculpt blob built" end
        MAP_API.pinned_data[qid] = dests
    else
        label_anchor = nil
        local x, y, z = _extract_dest_xyz(dests, qid)
        if x then label_anchor = { x = x, y = y, z = z } end
        MAP_API.pinned_data[qid] = nil
    end
    if label_anchor == nil then
        local x, y, z = _extract_dest_xyz(dests, qid)
        if x then label_anchor = { x = x, y = y, z = z } end
    end
    if label_anchor == nil then return false, "no sculpt anchor" end
    local dm = build_marker_at_pos(label_anchor.x, label_anchor.y, label_anchor.z, qid)
    if dm then
        pcall(function() list:call("Add", dm) end)
        added = added + 1
    end
    MAP_API.pinned_label_pos[qid] = label_anchor
    if skip_blob then
        return _pin_done(string.format("pinned qid=%d sculpt diamond+label vanilla_blob_active=1", qid), defer_refresh)
    end
    anchor_src = anchor_src or "dest"
    return _pin_done(string.format("pinned qid=%d sculpt blob+diamond pin_once=1 anchor=%s", qid, anchor_src), defer_refresh)
end

local function _pin_dest_mode(qid, list, dests, defer_refresh, anchor_override)
    if BLOB_AREA_QIDS and BLOB_AREA_QIDS[qid] and anchor_override == nil then
        return _pin_sculpt_quest(qid, list, dests, defer_refresh)
    end
    _sniff_dest_once(qid, dests)
    local added = 0
    local label_anchor = nil
    for _, dest in ipairs(dests) do
        local marker = build_marker(dest, qid)
        if marker then
            local okA = pcall(function() list:call("Add", marker) end)
            if okA then
                added = added + 1
                if label_anchor == nil then
                    local x, y, z = _marker_world_xyz(marker)
                    if x then label_anchor = { x = x, y = y, z = z } end
                end
            end
        end
    end
    if added == 0 then return false, "no marker built" end
    MAP_API.pinned_data[qid] = dests
    if anchor_override and anchor_override.x then
        label_anchor = { x = anchor_override.x, y = anchor_override.y, z = anchor_override.z }
    end
    if label_anchor then
        local dm = build_marker_at_pos(label_anchor.x, label_anchor.y, label_anchor.z, qid)
        if dm then
            local okD = pcall(function() list:call("Add", dm) end)
            if okD then added = added + 1 end
        end
        MAP_API.pinned_label_pos[qid] = label_anchor
    end
    local is_hybrid = anchor_override ~= nil
    local tag = is_hybrid and "hybrid" or "dest-mode"
    local anchor_src = is_hybrid and "manual" or "dest"
    return _pin_done(string.format("pinned qid=%d %s blob+diamond added=%d anchor=%s",
        qid, tag, added, anchor_src), defer_refresh)
end

local function _is_live_priority_quest(qid, qlm)
    if mod == nil then return false end
    if mod._qt_journal_qid == qid then return true end
    if mod._qt_priority_qid == qid then return true end
    if qlm then
        local pq = to_int(safe_get_field(qlm, "_CurrentDestinationTargetQuestID"))
        if pq == qid then return true end
    end
    return false
end

local function _pin_poi_from_dest_live(qid, list, dests, defer_refresh)
    _sniff_dest_once(qid, dests)
    local x, y, z = _extract_dest_xyz(dests, qid)
    if x == nil then return false, "no live xyz" end
    local marker = build_marker_at_pos(x, y, z, qid)
    if marker == nil then return false, "live poi marker failed" end
    pcall(function() list:call("Add", marker) end)
    MAP_API.pinned_pos[qid] = { { x = x, y = y, z = z, live = true } }
    MAP_API.pinned_label_pos[qid] = { x = x, y = y, z = z }
    return _pin_done(string.format("pinned qid=%d live-dest anchor=live", qid), defer_refresh)
end

local function _pin_live_ongoing_quest(qid, qlm, list, defer_refresh)
    local live = get_live_info_destinations(qlm, qid)
    if live == nil then
        MAP_API._live_miss_logged = MAP_API._live_miss_logged or {}
        if not MAP_API._live_miss_logged[qid] then
            MAP_API._live_miss_logged[qid] = true
            _mlog_map(string.format("[QT][map] live miss qid=%d reason=no_CurrentDestinations", qid))
        end
        return nil
    end
    if BLOB_AREA_QIDS and BLOB_AREA_QIDS[qid] then
        return _pin_sculpt_quest(qid, list, live, defer_refresh, "live")
    end
    return _pin_poi_from_dest_live(qid, list, live, defer_refresh)
end

local function _pin_live_journal_quest(qid, qlm, list, defer_refresh)
    if not _is_live_priority_quest(qid, qlm) then return nil end
    return _pin_live_ongoing_quest(qid, qlm, list, defer_refresh)
end

-- Available pins: giver NPC in world only — never MANUAL_POS / bundled coords.
_pin_available_at = function(qid, list, x, y, z, path_tag, defer_refresh)
    local marker = build_marker_at_pos(x, y, z, qid)
    if marker == nil then return false, "available marker failed" end
    pcall(function() list:call("Add", marker) end)
    _mark_diamond_on_list(qid)
    MAP_API.pinned_pos[qid] = { { x = x, y = y, z = z, available = path_tag } }
    MAP_API.pinned_label_pos[qid] = { x = x, y = y, z = z }
    -- #region agent log
    do
        local parts = {
            string.format('"qid":"%s"', tostring(qid)),
            string.format('"path":"%s"', tostring(path_tag)),
            string.format('"xyz":"%.0f,%.0f,%.0f"', x or 0, y or 0, z or 0),
        }
        local payload = string.format(
            '{"sessionId":"62ebea","runId":"halfpass","hypothesisId":"H5","location":"map:_pin_available_at","message":"pin_xyz","data":{%s},"timestamp":%d}\n',
            table.concat(parts, ","), math.floor((os.clock() or 0) * 1000))
        pcall(function()
            local f = io.open("c:/Users/jzafi/Desktop/New folder/OTHERMODS/QuestTracker-Modded/debug-62ebea.log", "a")
            if f then f:write(payload); f:close() end
        end)
        _mlog_map(string.format("[QT][dbg62] hyp=H5 pin_xyz qid=%s path=%s xyz=%.0f,%.0f,%.0f",
            tostring(qid), tostring(path_tag), x or 0, y or 0, z or 0))
    end
    -- #endregion
    local is_ongoing_path = path_tag == "npc-ongoing" or path_tag == "step-npc" or path_tag == "bundled-ongoing"
    local log_tag = is_ongoing_path and "pin ongoing" or "pin available"
    _mlog_map(string.format("[QT][map] %s qid=%d path=%s", log_tag, qid, path_tag))
    if path_tag == "npc-ongoing" or path_tag == "step-npc" or path_tag == "bundled-ongoing" then
        MAP_API._fallback_pending_upgrade[qid] = true
        _mlog_map(string.format("[QT][map] pin defer live qid=%d fallback=%s pending_upgrade=1", qid, path_tag))
    else
        MAP_API._fallback_pending_upgrade[qid] = nil
    end
    return _pin_done(string.format("pinned qid=%d available path=%s", qid, path_tag), defer_refresh)
end

local function _player_map_region()
    local la = UI_MAP and safe_get_field(UI_MAP, "LocalAreaNow")
    if la == nil and UI_MAP then pcall(function() la = UI_MAP:call("get_LocalAreaNow") end) end
    if type(la) ~= "number" then return nil end
    -- Vernworth/Melve/Borderwatch cluster vs Battahl vs Volcanic (approximate LocalArea bands)
    if la >= 60 and la <= 70 then return "Vermund" end
    if la >= 80 and la <= 90 then return "Battahl" end
    if la >= 100 then return "Volcanic" end
    return nil
end

local function _quest_meta_region(qid)
    if QD and QD.get_quest_meta_region then
        local ok, r = pcall(QD.get_quest_meta_region, qid)
        if ok and type(r) == "string" and r ~= "" then return r end
    end
    return nil
end

local function _region_blocks_available_pin(qid, has_npc)
    if has_npc then return false end
    local qr = _quest_meta_region(qid)
    local pr = _player_map_region()
    if qr and pr and qr ~= pr then return true end
    return false
end

local function _pin_available_skip(qid, reason)
    _mlog_map(string.format("[QT][map] pin available skip qid=%d reason=%s", qid, reason))
    return false, reason
end

local function _try_npc_giver_pin(qid, list, cid, path_tag, defer_refresh)
    local wx, wy, wz = get_character_world_pos(cid)
    if wx then
        return _pin_available_at(qid, list, wx, wy, wz, path_tag, defer_refresh)
    end
    return nil
end

local function _pin_available_quest(qid, list, defer_refresh)
    if MANUAL_GIVER_OVERRIDES[qid] then
        local r = _try_npc_giver_pin(qid, list, MANUAL_GIVER_OVERRIDES[qid], "npc", defer_refresh)
        if r ~= nil then return r end
    end
    if QD and QD.get_primary_giver_cid then
        local ok, pcid = pcall(QD.get_primary_giver_cid, qid)
        if ok and pcid then
            local r = _try_npc_giver_pin(qid, list, pcid, "npc", defer_refresh)
            if r ~= nil then return r end
        end
    end
    local cast = qd_givers_display_order(qid) or qd_givers(qid) or get_quest_cast_charaids(qid)
    if cast and #cast > 0 then
        local GENERIC = { [2891076981] = true, [260732951] = true }
        local elim_cids = {}
        local el = MAP_API.eliminated_pos[qid]
        if el then
            for _, p in ipairs(el) do
                local ek = cid_norm(p.cid)
                if ek then elim_cids[ek] = true end
            end
        end
        for _, c in ipairs(cast) do
            if not GENERIC[c] and not elim_cids[cid_norm(c)] then
                local r = _try_npc_giver_pin(qid, list, c, "npc", defer_refresh)
                if r ~= nil then return r end
            end
        end
    end
    if get_all_giver_cids then
        local ok, cids = pcall(get_all_giver_cids, qid, nil)
        if ok and type(cids) == "table" then
            for _, c in ipairs(cids) do
                local r = _try_npc_giver_pin(qid, list, c, "npc", defer_refresh)
                if r ~= nil then return r end
            end
        end
    end
    if _region_blocks_available_pin(qid, false) then
        return _pin_available_skip(qid, "region")
    end
    return _pin_available_skip(qid, "no_giver")
end

local function _pin_first_step_giver(qid, list, step_title, path_tag, defer_refresh)
    if not get_all_giver_cids or type(step_title) ~= "string" or step_title == "" then return nil end
    local ok, cids = pcall(get_all_giver_cids, qid, step_title)
    if not ok or type(cids) ~= "table" or #cids == 0 then return nil end
    for _, c in ipairs(cids) do
        local wx, wy, wz = get_character_world_pos(c)
        if wx then
            return _pin_available_at(qid, list, wx, wy, wz, path_tag, defer_refresh)
        end
    end
    return nil
end

local function _pin_poi_from_dest(qid, list, dests, defer_refresh, opts)
    opts = opts or {}
    _sniff_dest_once(qid, dests)
    local x, y, z, anchor_src = nil, nil, nil, "dest"
    local skip_manual = opts.skip_manual == true
    if not skip_manual and MANUAL_POS_OVERRIDES and MANUAL_POS_OVERRIDES[qid] then
        local p = MANUAL_POS_OVERRIDES[qid]
        x, y, z = p.x, p.y, p.z
        anchor_src = "manual"
    else
        local marker = build_marker(dests[1], qid)
        if marker then x, y, z = _marker_world_xyz(marker) end
        if x == nil then
            local dest = dests[1]
            local p = safe_get_field(dest, "Pos") or safe_call(dest, "get_Pos")
            if p then pcall(function() x, y, z = p.x, p.y, p.z end) end
        end
    end
    if x == nil then return false, "no poi xyz" end
    local marker = build_marker_at_pos(x, y, z, qid)
    if marker == nil then return false, "poi marker failed" end
    pcall(function() list:call("Add", marker) end)
    MAP_API.pinned_pos[qid] = { { x = x, y = y, z = z } }
    MAP_API.pinned_label_pos[qid] = { x = x, y = y, z = z }
    return _pin_done(string.format("pinned qid=%d poi-diamond anchor=%s", qid, anchor_src), defer_refresh)
end

pin_quest = function(qid, defer_refresh)
    if not init_map_api() then return false, "map api init failed" end
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm == nil then return false, "QLM nil" end
    local list = get_marker_list()
    if list == nil then return false, "marker list nil" end

    -- MAIN journal: never add a second diamond; label the game's own marker.
    -- If game marker / live dest not ready yet: DEFER — never fall back to npc-ongoing
    -- (that created Test1 dual diamond: wrong Hugo NPC + correct game MAIN).
    if mod and mod._qt_journal_qid == qid then
        local jr = _pin_journal_label_only(qid, list, defer_refresh)
        if jr ~= nil then return jr end
        MAP_API._journal_pin_pending = qid
        MAP_API._journal_pin_pending_frames = 0
        -- #region agent log
        _mlog_map(string.format(
            "[QT][dbg62] hyp=H1 MAIN label-only DEFER (no npc fallback) qid=%d", qid))
        -- #endregion
        _mlog_map(string.format(
            "[QT][map] MAIN label-only deferred qid=%d (waiting game marker)", qid))
        return true, "journal-label-deferred"
    end

    -- Acceptable OR side-quest Upcoming (meta ready, game not Acceptable yet).
    -- Main-story upcoming (qid < 20000) stays false so we never npc-pin endgame.
    local is_available = (mod.acceptable_ids and mod.acceptable_ids[qid] == true)
        or (mod.upcoming_ids and mod.upcoming_ids[qid] == true and qid >= 20000)
    local added = 0

    if not is_available and HYBRID_AREA_QIDS and HYBRID_AREA_QIDS[qid] then
        local dests = get_quest_destinations(qlm, qid) or get_live_info_destinations(qlm, qid)
        if dests then
            local anchor = MANUAL_POS_OVERRIDES[qid]
            return _pin_dest_mode(qid, list, dests, defer_refresh, anchor)
        end
    end

    local is_ongoing = (not is_available) and mod and mod.progressing_ids and mod.progressing_ids[qid] == true
    if is_ongoing then
        local live_r, live_msg = _pin_live_ongoing_quest(qid, qlm, list, defer_refresh)
        if live_r ~= nil then return live_r, live_msg end
        local step_title = mod._qt_step_title and mod._qt_step_title[qid]
        local step_r = _pin_first_step_giver(qid, list, step_title, "step-npc", defer_refresh)
        if step_r ~= nil then return step_r end
    end

    local block_manual_main = is_ongoing

    if MANUAL_POS_OVERRIDES[qid] and not block_manual_main and not is_available then
        local p = MANUAL_POS_OVERRIDES[qid]
        local marker = build_marker_at_pos(p.x, p.y, p.z, qid)
        if marker then
            pcall(function() list:call("Add", marker) end)
            _mark_diamond_on_list(qid)
            MAP_API.pinned_pos[qid] = { { x = p.x, y = p.y, z = p.z, manual = true } }
            MAP_API.pinned_label_pos[qid] = { x = p.x, y = p.y, z = p.z }
            if is_available then
                _mlog_map(string.format("[QT][map] pin available qid=%d path=manual", qid))
            end
            return _pin_done(string.format("pinned qid=%d (manual pos)", qid), defer_refresh)
        end
        return false, "manual pos marker failed"
    end

    if is_available then
        return _pin_available_quest(qid, list, defer_refresh)
    else
        local step_title = mod._qt_step_title and mod._qt_step_title[qid]
        local step_r2 = _pin_first_step_giver(qid, list, step_title, "step-npc", defer_refresh)
        if step_r2 ~= nil then return step_r2 end
        if MANUAL_GIVER_OVERRIDES[qid] then
            local cid = MANUAL_GIVER_OVERRIDES[qid]
            local wx, wy, wz = get_character_world_pos(cid)
            if wx then
                return _pin_available_at(qid, list, wx, wy, wz, "npc-ongoing", defer_refresh)
            end
        end
        local cast = qd_givers_display_order(qid) or qd_givers(qid) or get_quest_cast_charaids(qid)
        if cast and #cast > 0 then
            for _, c in ipairs(cast) do
                local wx, wy, wz = get_character_world_pos(c)
                if wx then
                    return _pin_available_at(qid, list, wx, wy, wz, "npc-ongoing", defer_refresh)
                end
            end
        end
        local bp = BUNDLED_POS_OVERRIDES and BUNDLED_POS_OVERRIDES[qid]
        if bp and bp.x then
            return _pin_available_at(qid, list, bp.x, bp.y, bp.z, "bundled-ongoing", defer_refresh)
        end
        return false, "no live/bundled/npc for ongoing quest"
    end
end

unpin_quest = function(qid, defer_refresh)
    MAP_API.pinned_data[qid] = nil
    MAP_API.pinned_pos[qid] = nil
    MAP_API.pinned_label_pos[qid] = nil
    if MAP_API._journal_label_only then MAP_API._journal_label_only[qid] = nil end
    MAP_API._fallback_pending_upgrade[qid] = nil
    MAP_API.last_msg = "unpinned qid=" .. qid
    _mlog_map("[QT][map] unpinned qid=" .. tostring(qid))
    if defer_refresh then return true end
    force_marker_refresh()
    return true
end

local function sweep_ghost_pins(progressing, acceptable, completed)
    if not progressing or not acceptable or not completed then return 0 end
    local swept = 0
    local function sweep_one(qid)
        local reason = nil
        if completed[qid] then
            reason = "quest_completed"
        elseif not progressing[qid] and not acceptable[qid] then
            reason = "not_active"
        end
        if reason and (MAP_API.pinned_pos[qid] or MAP_API.pinned_data[qid]) then
            unpin_quest(qid, true)
            _mlog_map(string.format("[QT][map] unpin complete qid=%d reason=%s", qid, reason))
            swept = swept + 1
        end
    end
    for qid in pairs(MAP_API.pinned_pos or {}) do sweep_one(qid) end
    for qid in pairs(MAP_API.pinned_data or {}) do sweep_one(qid) end
    if swept > 0 then
        force_marker_refresh()
    end
    return swept
end

-- Upgrade any fallback-pinned (npc-ongoing/step-npc) quests to live dest when QLM populates.
-- Called after journal pin succeeds (QLM proven up) and on each autopin tick.
local _upgrade_last_run = 0
try_upgrade_fallback_pins = function()
    if not next(MAP_API._fallback_pending_upgrade) then return end
    local now = os.clock()
    if (now - _upgrade_last_run) < 1.0 then return end
    _upgrade_last_run = now
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm == nil then return end
    local list = get_marker_list()
    if list == nil then return end
    local upgraded = 0
    for qid, _ in pairs(MAP_API._fallback_pending_upgrade) do
        local live = get_live_info_destinations(qlm, qid)
        if live then
            MAP_API._fallback_pending_upgrade[qid] = nil
            if MAP_API._live_miss_logged then MAP_API._live_miss_logged[qid] = nil end
            unpin_quest(qid, true)
            local ok_r, r_ok = pcall(pin_quest, qid, true)
            if ok_r and r_ok then
                upgraded = upgraded + 1
                _mlog_map(string.format("[QT][map] pin upgrade qid=%d fallback->live", qid))
            end
        end
    end
    if upgraded > 0 then
        _mlog_map(string.format("[QT][map] pin upgrade batch upgraded=%d", upgraded))
        if not MAP_API._refreshing then force_marker_refresh() end
    end
end

local function sync_eliminated_to_prefs()
    ELIMINATED_OVERRIDES = {}
    for qid, list2 in pairs(MAP_API.eliminated_pos or {}) do
        if type(list2) == "table" then
            local saved = {}
            for _, p in ipairs(list2) do
                if type(p) == "table" and p.cid and p.cid > 0 then
                    saved[#saved + 1] = { cid = p.cid, x = p.x, y = p.y, z = p.z }
                end
            end
            if #saved > 0 then ELIMINATED_OVERRIDES[qid] = saved end
        end
    end
    mark_prefs_dirty()
end

unpin_candidate = function(qid, cid)
    local pins = MAP_API.pinned_pos[qid]; if not pins then return false end
    local kept, removed = {}, nil
    for _, p in ipairs(pins) do
        if cid_eq(p.cid, cid) and not removed then removed = p else kept[#kept+1] = p end
    end
    MAP_API.pinned_pos[qid] = #kept > 0 and kept or nil
    if removed then
        MAP_API.eliminated_pos[qid] = MAP_API.eliminated_pos[qid] or {}
        MAP_API.eliminated_pos[qid][#MAP_API.eliminated_pos[qid]+1] = removed
        sync_eliminated_to_prefs()
    end
    force_marker_refresh(); return true
end

restore_candidate = function(qid, cid)
    local elim = MAP_API.eliminated_pos[qid]; if not elim then return false end
    local kept, restored = {}, nil
    for _, p in ipairs(elim) do
        if cid_eq(p.cid, cid) and not restored then restored = p else kept[#kept+1] = p end
    end
    MAP_API.eliminated_pos[qid] = #kept > 0 and kept or nil
    if restored then
        MAP_API.pinned_pos[qid] = MAP_API.pinned_pos[qid] or {}
        MAP_API.pinned_pos[qid][#MAP_API.pinned_pos[qid]+1] = restored
    end
    sync_eliminated_to_prefs(); force_marker_refresh(); return true
end

restore_all_candidates = function(qid)
    local elim = MAP_API.eliminated_pos[qid]; if not elim then return end
    MAP_API.pinned_pos[qid] = MAP_API.pinned_pos[qid] or {}
    for _, p in ipairs(elim) do MAP_API.pinned_pos[qid][#MAP_API.pinned_pos[qid]+1] = p end
    MAP_API.eliminated_pos[qid] = nil
    sync_eliminated_to_prefs(); force_marker_refresh()
end

-- =========== FILTER ===========
local function matches_filter(q)
    if mod.filter_text == "" then return true end
    local f = string.lower(mod.filter_text)
    return string.find(string.lower(q.name or ""), f, 1, true)
        or (q.name_en and string.find(string.lower(q.name_en), f, 1, true))
        or string.find(string.lower(q.enum_name or ""), f, 1, true)
        or string.find(string.lower(q.summary or ""), f, 1, true)
        or string.find(tostring(q.id), f, 1, true)
end

local function visible_for_current_tab(q)
    local cat = TAB_NAMES[mod.tab]
    if cat == "Hidden" then return q.voided
    elseif cat == "All" then return not q.voided
    else return (q.category == cat) and not q.voided end
end

-- Pin every Available/Ongoing row that passes the active tab + current filter text.
local function pin_all_in_current_filtered_tab()
    pcall(init_map_api)
    local new_pins, skipped, failed = 0, 0, 0
    for _, q in ipairs(mod.quests or {}) do
        if visible_for_current_tab(q) and matches_filter(q) then
            if q.category ~= "Available" and q.category ~= "Ongoing" then
                skipped = skipped + 1
            else
                local is_pinned = MAP_API.pinned_data[q.id] ~= nil or MAP_API.pinned_pos[q.id] ~= nil
                if is_pinned then
                    skipped = skipped + 1
                else
                    local ok_pin, pin_ok, pin_msg = pcall(pin_quest, q.id)
                    if ok_pin and pin_ok then
                        new_pins = new_pins + 1
                    else
                        failed = failed + 1
                        if mod.debug_logging then
                            mlog("[PIN ALL] qid=" .. q.id ..
                                " pcall_ok=" .. tostring(ok_pin) ..
                                " ok=" .. tostring(pin_ok) ..
                                " err=" .. tostring(pin_msg))
                        end
                    end
                end
            end
        end
    end
    local tabnm = TAB_NAMES[mod.tab] or "?"
    MAP_API.last_msg = string.format("Pin all [%s]: %d new pins, %d skipped, %d failed", tabnm, new_pins, skipped, failed)
    mlog("[PIN ALL] " .. MAP_API.last_msg)
    force_marker_refresh()
end

-- Pin every Ongoing quest (Pin Ongoing button / Autopin Ongoing).
-- force_repin=true: unpin Ongoing first (button). false: skip already-pinned (quiet autopin).
local function pin_all_ongoing_all(force_repin)
    pcall(init_map_api)
    if force_repin then
        for _, q in ipairs(mod.quests or {}) do
            if (not q.voided) and q.category == "Ongoing" then
                local has = MAP_API.pinned_pos[q.id]
                    or MAP_API.pinned_data[q.id]
                    or (MAP_API.pinned_label_pos and MAP_API.pinned_label_pos[q.id])
                    or (MAP_API._journal_label_only and MAP_API._journal_label_only[q.id])
                if has then
                    unpin_quest(q.id, true)
                end
            end
        end
        _mlog_map("[QT][map] Pin Ongoing force unpin all Ongoing")
    end
    local new_pins, skipped, failed = 0, 0, 0
    local jqid = mod and mod._qt_journal_qid
    local main_handled = false
    for _, q in ipairs(mod.quests or {}) do
        if (not q.voided) and q.category == "Ongoing" then
            local is_pinned = MAP_API.pinned_data[q.id] ~= nil
                or MAP_API.pinned_pos[q.id] ~= nil
                or (MAP_API.pinned_label_pos and MAP_API.pinned_label_pos[q.id] ~= nil)
                or (MAP_API._journal_label_only and MAP_API._journal_label_only[q.id])
            if is_pinned then
                skipped = skipped + 1
            else
                local ok_pin, pin_ok, pin_msg = pcall(pin_quest, q.id, true)
                if ok_pin and pin_ok then
                    new_pins = new_pins + 1
                    if jqid and q.id == jqid then main_handled = true end
                else
                    failed = failed + 1
                    if mod.debug_logging then
                        mlog("[PIN ONGOING] qid=" .. q.id .. " err=" .. tostring(pin_msg or pin_ok))
                    end
                end
            end
        end
    end
    local labels_ok, want_labels = 0, 0
    for _, q in ipairs(mod.quests or {}) do
        if (not q.voided) and q.category == "Ongoing" then
            if MAP_API.pinned_data[q.id]
                or MAP_API.pinned_pos[q.id]
                or (MAP_API.pinned_label_pos and MAP_API.pinned_label_pos[q.id])
                or (MAP_API._journal_label_only and MAP_API._journal_label_only[q.id]) then
                want_labels = want_labels + 1
                local g = get_quest_name_guid(q.id)
                if g then labels_ok = labels_ok + 1 end
            end
        end
    end
    MAP_API.last_msg = string.format("Pin Ongoing: %d new, %d skipped, %d failed", new_pins, skipped, failed)
    _mlog_map("[QT][map] " .. MAP_API.last_msg)
    _mlog_map(string.format(
        "[QT][map] Pin Ongoing done new=%d skipped=%d failed=%d labels_ok=%d want=%d main_qid=%s main_ok=%s",
        new_pins, skipped, failed, labels_ok, want_labels,
        tostring(jqid or 0), tostring(main_handled)))
    force_marker_refresh()
end

-- Pin MAIN: journal priority quest ONLY (Pin MAIN button).
local function pin_all_ongoing()
    pcall(init_map_api)
    local jqid = mod and mod._qt_journal_qid
    local map_skipped = 0
    for _, q in ipairs(mod and mod.quests or {}) do
        if (not q.voided) and q.category == "Ongoing" and q.id ~= jqid then
            map_skipped = map_skipped + 1
        end
    end
    if jqid and jqid > 0 then
        local is_pinned = MAP_API.pinned_data[jqid] ~= nil or MAP_API.pinned_pos[jqid] ~= nil
        if not is_pinned then
            local ok_pin, pin_ok, pin_err = pcall(pin_quest, jqid, true)
            if ok_pin and pin_ok then
                _mlog_map(string.format("[QT][map] Pin Ongoing journal qid=%d skipped=%d", jqid, map_skipped))
            else
                _mlog_map(string.format("[QT][map] Pin Ongoing FAIL qid=%d err=%s skipped=%d",
                    jqid, tostring(pin_err or pin_ok), map_skipped))
            end
        else
            _mlog_map(string.format("[QT][map] Pin Ongoing journal qid=%d already_pinned skipped=%d", jqid, map_skipped))
        end
    else
        _mlog_map(string.format("[QT][map] Pin Ongoing skip jqid=0 skipped=%d", map_skipped))
    end
    MAP_API.last_msg = string.format("Pin Ongoing journal qid=%s skipped=%d", tostring(jqid), map_skipped)
    force_marker_refresh()
end

-- Pin every Available quest regardless of active tab or filter.
-- force_repin=true: unpin all Available first (Clear pins / Pin Available button).
local function pin_all_available(force_repin)
    pcall(init_map_api)
    if force_repin then
        for _, q in ipairs(mod.quests or {}) do
            if (not q.voided) and q.category == "Available" then
                if MAP_API.pinned_pos[q.id] or MAP_API.pinned_data[q.id] then
                    unpin_quest(q.id, true)
                end
            end
        end
        _mlog_map("[QT][map] Pin Available force unpin all Available")
    end
    local new_pins, skipped, failed = 0, 0, 0
    for _, q in ipairs(mod.quests or {}) do
        if (not q.voided) and q.category == "Available" then
            local acc = mod.acceptable_ids and mod.acceptable_ids[q.id] == true
            local up = mod.upcoming_ids and mod.upcoming_ids[q.id] == true
            -- Pin game-Acceptable + side Upcoming. Skip main-story Upcoming (10xxx).
            if up and not acc and q.id < 20000 then
                skipped = skipped + 1
                -- #region agent log
                _mlog_map(string.format(
                    "[QT][dbg62] hyp=H8 pin_avail_skip qid=%d reason=main_upcoming name=%s",
                    q.id, tostring(q.name or "?"):sub(1, 40)))
                -- #endregion
            elseif not acc and not up then
                skipped = skipped + 1
                -- #region agent log
                _mlog_map(string.format(
                    "[QT][dbg62] hyp=H8 pin_avail_skip qid=%d reason=not_acceptable name=%s",
                    q.id, tostring(q.name or "?"):sub(1, 40)))
                -- #endregion
            else
            local is_pinned = MAP_API.pinned_data[q.id] ~= nil or MAP_API.pinned_pos[q.id] ~= nil
            if is_pinned then
                skipped = skipped + 1
            else
                -- #region agent log
                do
                    local prog = mod.progressing_ids and mod.progressing_ids[q.id] == true
                    local meta_n = tostring(q.name or "?")
                    _mlog_map(string.format(
                        "[QT][dbg62] hyp=H8 pin_avail_row qid=%d cat=%s acc=%s up=%s prog=%s name=%s",
                        q.id, tostring(q.category), tostring(acc), tostring(up), tostring(prog), meta_n:sub(1, 40)))
                end
                -- #endregion
                local ok_pin, pin_ok, pin_msg = pcall(pin_quest, q.id, true)
                if ok_pin and pin_ok then
                    new_pins = new_pins + 1
                else
                    failed = failed + 1
                    if mod.debug_logging then
                        mlog("[PIN AVAILABLE] qid=" .. q.id ..
                            " pcall_ok=" .. tostring(ok_pin) ..
                            " ok=" .. tostring(pin_ok) ..
                            " err=" .. tostring(pin_msg))
                    end
                end
            end
            end
        end
    end
    local labels_ok, want_labels = 0, 0
    for _, q in ipairs(mod.quests or {}) do
        if (not q.voided) and q.category == "Available" then
            if MAP_API.pinned_data[q.id] or MAP_API.pinned_pos[q.id] then
                want_labels = want_labels + 1
                local g = get_quest_name_guid(q.id)
                if g then
                    labels_ok = labels_ok + 1
                    -- #region agent log
                    -- H2b: resolve Guid → English once (map usually closed on Pin Available click)
                    do
                        local gt = nil
                        if type(_guid_to_en_text) == "function" then
                            pcall(function() gt = _guid_to_en_text(g) end)
                        end
                        local pos = MAP_API.pinned_label_pos and MAP_API.pinned_label_pos[q.id]
                        local xyz = pos and string.format("%.0f,%.0f,%.0f", pos.x, pos.y, pos.z) or "?"
                        _mlog_map(string.format(
                            "[QT][dbg62] hyp=H2b guid_text qid=%d text=%s xyz=%s",
                            q.id, tostring(gt or "nil"):sub(1, 48), xyz))
                    end
                    -- #endregion
                end
            end
        end
    end
    MAP_API.last_msg = string.format("Pin Available: %d new, %d skipped, %d failed", new_pins, skipped, failed)
    _mlog_map("[QT][map] " .. MAP_API.last_msg)
    _mlog_map(string.format("[QT][map] Pin Available done new=%d labels_ok=%d want=%d",
        new_pins, labels_ok, want_labels))
    force_marker_refresh()
end

local function run_autopin_if_enabled()
    if not mod then return end
    if not mod._game_ready then return end
    if mod._qt_game_ready_at and os.clock() < mod._qt_game_ready_at + 5.0 then return end
    if mod._qt_is_draw_suppressed and mod._qt_is_draw_suppressed() then return end
    local gm = sdk.get_managed_singleton("app.GuiManager")
    if gm then
        local blocked = false
        pcall(function()
            if gm:get_IsLoadGui() == true then blocked = true end
        end)
        if blocked then return end
    end
    local ran = false
    if mod.auto_pin_ongoing then
        pcall(pin_all_ongoing_all, false)
        pcall(try_upgrade_fallback_pins)
        ran = true
    end
    if mod.auto_pin_available then
        pcall(pin_all_available)
        ran = true
    end
    if ran then _mlog_map("[QT][map] autopin tick") end
end

package.loaded["quest_tracker_map"] = M

M.API = MAP_API
M.init_map_api = init_map_api
M.clear_injected_markers = clear_injected_markers
M.get_quest_resource = function(qlm, qid) return Labels.get_quest_resource(qlm, qid) end
M.get_quest_cast_charaids = get_quest_cast_charaids
M.force_marker_refresh = force_marker_refresh
M.pin_quest = pin_quest
M.unpin_quest = unpin_quest
M.unpin_candidate = unpin_candidate
M.restore_candidate = restore_candidate
M.restore_all_candidates = restore_all_candidates
M.pin_all = pin_all_in_current_filtered_tab
M.pin_all_ongoing = pin_all_ongoing
M.pin_all_ongoing_all = pin_all_ongoing_all
M.pin_all_current = pin_all_ongoing_all
M.pin_all_available = pin_all_available
M.run_autopin_if_enabled = run_autopin_if_enabled
M.sweep_ghost_pins = sweep_ghost_pins
M.try_upgrade_fallback_pins = try_upgrade_fallback_pins
M.on_journal_qid_changed = on_journal_qid_changed
M.flush_journal_pin_pending = flush_journal_pin_pending

local function on_journal_progress_bump(qid, old_done, new_done)
    MAP_API._pin_fingerprint = MAP_API._pin_fingerprint or {}
    MAP_API._pin_fingerprint[qid] = nil
    MAP_API._dest_sniff_logged = MAP_API._dest_sniff_logged or {}
    MAP_API._dest_sniff_logged[qid] = nil
    MAP_API._live_miss_logged = MAP_API._live_miss_logged or {}
    MAP_API._live_miss_logged[qid] = nil
    _mlog_map(string.format("[QT][map] progress bump qid=%d done %s to %s",
        qid, tostring(old_done), tostring(new_done)))
    unpin_quest(qid, true)
    if mod and (mod.progressing_ids and mod.progressing_ids[qid]
        or (mod._qt_journal_qid == qid and mod.auto_pin_journal ~= false)
        or mod.auto_pin_ongoing) then
        pcall(pin_quest, qid, true)
        _mlog_map(string.format("[QT][map] progress repin qid=%d", qid))
    end
    if not MAP_API._refreshing then force_marker_refresh() end
end

function M.quest_objective_dist_sq(qid, px, pz, step_title)
    if px == nil or pz == nil then return nil end
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm and mod and mod.progressing_ids and mod.progressing_ids[qid] then
        local live = get_live_info_destinations(qlm, qid)
        if live then
            local x, _, z = _extract_dest_xyz(live, qid)
            if x then
                local dx, dz = x - px, z - pz
                return dx * dx + dz * dz
            end
        end
    end
    if get_all_giver_cids and type(step_title) == "string" and step_title ~= "" then
        local ok, cids = pcall(get_all_giver_cids, qid, step_title)
        if ok and type(cids) == "table" then
            for _, c in ipairs(cids) do
                local wx, _, wz = get_character_world_pos(c)
                if wx then
                    local dx, dz = wx - px, wz - pz
                    return dx * dx + dz * dz
                end
            end
        end
    end
    local pins = MAP_API.pinned_pos[qid]
    if pins and pins[1] and pins[1].x then
        local p = pins[1]
        local dx, dz = p.x - px, p.z - pz
        return dx * dx + dz * dz
    end
    local m = MANUAL_POS_OVERRIDES and MANUAL_POS_OVERRIDES[qid]
    if m and m.x then
        local dx, dz = m.x - px, m.z - pz
        return dx * dx + dz * dz
    end
    return nil
end
M.on_journal_progress_bump = on_journal_progress_bump

M.resniff_map_ui = function()
    if mod then
        mod._qt_map_sniff_done = nil
        mod._qt_map_zoom_logged = nil
    end
    Labels.reset_probe()
    if UI_MAP then
        pcall(Labels.probe_api)
        if mod and mod.deep_sniff == true then
            pcall(_sniff_map_ui_once, UI_MAP)
        end
    end
end
M.matches_filter = matches_filter
M.visible_for_current_tab = visible_for_current_tab

return M
