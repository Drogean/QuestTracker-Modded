-- quest_tracker_map.lua — map pins / icons (require from quest_tracker.lua)
-- REFramework also runs every autorun/*.lua; return cached module so install() is not wiped.

local M = package.loaded["quest_tracker_map"]
if M then return M end
M = {}

local mod, mlog, qt_verbose, td, safe_get_field, safe_call, iter_list, to_int
local cid_eq, cid_norm, get_character_world_pos, mark_prefs_dirty
local MANUAL_POS_OVERRIDES, MANUAL_GIVER_OVERRIDES, ELIMINATED_OVERRIDES, BUNDLED_GIVER_OVERRIDES
local is_bundled_giver, qd_givers, qd_givers_display_order, TAB_NAMES

local MAP_API = {
    ready          = false,
    gm             = nil,
    pinned_data    = {},
    pinned_pos     = {},
    eliminated_pos = {},
    status         = "not initialized",
    last_msg       = "",
}

local function _td(name)
    if type(td) == "function" then return td(name) end
    return sdk.find_type_definition(name)
end

function M.install(ctx)
    if type(ctx) ~= "table" then return false end
    mod = ctx.mod
    mlog = ctx.mlog
    qt_verbose = ctx.qt_verbose
    td = ctx.td
    safe_get_field = ctx.safe_get_field
    safe_call = ctx.safe_call
    iter_list = ctx.iter_list
    to_int = ctx.to_int
    cid_eq = ctx.cid_eq
    cid_norm = ctx.cid_norm
    get_character_world_pos = ctx.get_character_world_pos
    mark_prefs_dirty = ctx.mark_prefs_dirty
    MANUAL_POS_OVERRIDES = ctx.MANUAL_POS_OVERRIDES
    MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
    ELIMINATED_OVERRIDES = ctx.ELIMINATED_OVERRIDES
    BUNDLED_GIVER_OVERRIDES = ctx.BUNDLED_GIVER_OVERRIDES
    is_bundled_giver = ctx.is_bundled_giver
    qd_givers = ctx.qd_givers
    qd_givers_display_order = ctx.qd_givers_display_order
    TAB_NAMES = ctx.TAB_NAMES
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

local function reinject_all()
    local list = get_marker_list()
    if list == nil then return end
    for qid, entry in pairs(MAP_API.pinned_data) do
        for _, dest in ipairs(entry) do
            local marker = build_marker(dest, qid)
            if marker then pcall(function() list:call("Add", marker) end) end
        end
    end
    for qid, entry in pairs(MAP_API.pinned_pos) do
        for _, p in ipairs(entry) do
            local marker = build_marker_at_pos(p.x, p.y, p.z, qid)
            if marker then pcall(function() list:call("Add", marker) end) end
        end
    end
end

-- =========== LABELED MAP ICONS ===========
local ICON_HOOK_INSTALLED = false
local ICON_ICON_TYPE = 25
local INT_T, INT_T_VOFF
local UI_MAP = nil

local function _icon_init_helpers()
    if INT_T == nil then
        INT_T = sdk.find_type_definition("System.Int32")
        if INT_T then
            local f = INT_T:get_field("m_value")
            if f then INT_T_VOFF = f:get_offset_from_base() end
        end
    end
end

local function get_quest_name_guid(qid)
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm == nil then return nil end
    local vi = safe_call(qlm, "getQuestLog", qid)
    if vi == nil then return nil end
    return safe_get_field(vi, "QuestNameId")
end

local function _add_one_labeled_icon(this, x, y, z, name_guid, idx_obj)
    local t2 = _td("app.GuiManager.MapIconInfo")
    if t2 == nil then return nil end
    local ok, info = pcall(function() return t2:create_instance():add_ref() end)
    if not ok or info == nil then return nil end
    pcall(function()
        info.IsEnable = true; info.IsNavi = false; info.IconId = 0; info.SortNo = 0
        info.IconType = ICON_ICON_TYPE; info.Timing = 0
        info.Pos = Vector3f.new(x, y, z); info.Area = -1; info.LocalArea = 0; info.IsDispAllArea = true
    end)
    local okA, ui_icon = pcall(function()
        return this:call("addMapIconInfoList", info, 0, idx_obj:get_address() + INT_T_VOFF, -1, name_guid)
    end)
    return okA and ui_icon or nil
end

local function _dest_world_pos(dest)
    if dest == nil then return nil end
    local p = safe_get_field(dest, "Pos") or safe_call(dest, "get_Pos")
    if p == nil then return nil end
    local x, y, z
    pcall(function() x, y, z = p.x, p.y, p.z end)
    if x == nil then return nil end
    return x, y, z
end

local function add_labeled_markers_for_all_pins(this)
    local label_all = mod.label_pins == true
    _icon_init_helpers()
    if INT_T == nil or INT_T_VOFF == nil then return end
    local icon_count, icon_limit = 0, 0
    pcall(function() icon_count = this.MapIconInfoList:get_Count() end)
    pcall(function() icon_limit = this.MapIcon:get_Length() end)
    if icon_limit == 0 or icon_count >= icon_limit then return end
    local idx_obj = INT_T:create_instance():add_ref()
    local function add_qid_label(qid, x, y, z)
        if icon_count >= icon_limit then return end
        if not label_all then return end
        local name_guid = get_quest_name_guid(qid)
        if not name_guid then return end
        idx_obj:write_dword(INT_T_VOFF, icon_count)
        if _add_one_labeled_icon(this, x, y, z, name_guid, idx_obj) then
            icon_count = icon_count + 1
        end
    end
    for qid, pins in pairs(MAP_API.pinned_pos) do
        for _, p in ipairs(pins) do
            add_qid_label(qid, p.x, p.y, p.z)
        end
    end
    for qid, entry in pairs(MAP_API.pinned_data) do
        for _, dest in ipairs(entry) do
            local x, y, z = _dest_world_pos(dest)
            if x then add_qid_label(qid, x, y, z) end
        end
    end
end

local function install_icon_hook()
    if ICON_HOOK_INSTALLED then return true end
    local t2 = _td("app.ui040205")
    if t2 == nil then return false end
    local m = t2:get_method("setupMapIcon")
    if m == nil then return false end
    local ok = pcall(function()
        sdk.hook(m,
            function(args) UI_MAP = sdk.to_managed_object(args[2]) end,
            function(retval)
                if UI_MAP then
                    pcall(add_labeled_markers_for_all_pins, UI_MAP)
                    pcall(function() UI_MAP:call("updateMapIcon") end)
                end
                return retval
            end)
    end)
    if ok then ICON_HOOK_INSTALLED = true end
    local mD = t2:get_method("onDestroy")
    if mD then pcall(function()
        sdk.hook(mD, function() end, function(r) UI_MAP = nil; return r end)
    end) end
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
                sdk.hook(m_setup, function() end, function(r) pcall(reinject_all); return r end)
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
    if not _init_map_api_logged then
        _init_map_api_logged = true
        qt_verbose("init_map_api: ready — " .. MAP_API.status)
    end
    return true
end

clear_injected_markers = function()
    MAP_API.pinned_data = {}; MAP_API.pinned_pos = {}
    MAP_API.last_msg = "pins cleared"
    force_marker_refresh()
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

get_quest_resource = function(qlm, qid)
    local cat = safe_get_field(qlm, "_Catalog")
    if cat == nil then return nil end
    local vals = safe_call(cat, "getValues")
    if vals == nil then return nil end
    local sz = 0; pcall(function() sz = vals:get_size() end)
    for i = 0, sz - 1 do
        local ok, v = pcall(function() return vals:get_element(i) end)
        if ok and v then
            if to_int(safe_get_field(v, "_QuestId") or safe_call(v, "get_QuestId")) == qid then return v end
        end
    end
    return nil
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
    local entry = nil
    local function try_key(k)
        if entry or k == nil then return end
        pcall(function() entry = dict[k] end)
        if not entry and dict.get_Item then
            pcall(function() entry = dict:call("get_Item", k) end)
        end
    end
    try_key(qid)
    try_key(want)
    return entry
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

pin_quest = function(qid)
    if not init_map_api() then return false, "map api init failed" end
    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm == nil then return false, "QLM nil" end
    local list = get_marker_list()
    if list == nil then return false, "marker list nil" end

    local is_available = mod.acceptable_ids[qid] == true
    local added = 0

    -- 1. Manual position override (highest priority)
    if MANUAL_POS_OVERRIDES[qid] then
        local p = MANUAL_POS_OVERRIDES[qid]
        local marker = build_marker_at_pos(p.x, p.y, p.z, qid)
        if marker then
            pcall(function() list:call("Add", marker) end)
            MAP_API.pinned_pos[qid] = { { x = p.x, y = p.y, z = p.z, manual = true } }
            MAP_API.last_msg = string.format("pinned qid=%d (manual pos)", qid)
            mlog("[PIN] " .. MAP_API.last_msg)
            return true
        end
    end

    if is_available then
        -- 2. Manual giver override
        if MANUAL_GIVER_OVERRIDES[qid] then
            local cid = MANUAL_GIVER_OVERRIDES[qid]
            local wx, wy, wz = get_character_world_pos(cid)
            if wx then
                local marker = build_marker_at_pos(wx, wy, wz, qid)
                if marker then
                    pcall(function() list:call("Add", marker) end)
                    MAP_API.pinned_pos[qid] = { { x = wx, y = wy, z = wz, cid = cid } }
                    MAP_API.last_msg = string.format("pinned qid=%d cid=%d", qid, cid)
                    mlog("[PIN] " .. MAP_API.last_msg)
                    return true
                end
            end
        end

        -- 3. QD givers or runtime cast
        local cast = qd_givers_display_order(qid) or qd_givers(qid) or get_quest_cast_charaids(qid)
        if cast and #cast > 0 then
            local GENERIC = { [2891076981] = true, [260732951] = true }
            local elim_cids = {}
            local el = MAP_API.eliminated_pos[qid]
            if el then for _, p in ipairs(el) do local ek = cid_norm(p.cid); if ek then elim_cids[ek] = true end end end
            local multi = {}
            for _, c in ipairs(cast) do
                if not GENERIC[c] and not elim_cids[cid_norm(c)] then
                    local wx, wy, wz = get_character_world_pos(c)
                    if wx then multi[#multi+1] = { x = wx, y = wy, z = wz, cid = c } end
                end
            end
            if #multi > 0 then
                for _, p in ipairs(multi) do
                    local marker = build_marker_at_pos(p.x, p.y, p.z, qid)
                    if marker then
                        pcall(function() list:call("Add", marker) end)
                        added = added + 1
                    end
                end
                MAP_API.pinned_pos[qid] = multi
                MAP_API.last_msg = string.format("pinned qid=%d %d candidate(s)", qid, #multi)
                mlog("[PIN] " .. MAP_API.last_msg)
                return true
            end
        end
        return false, "no NPC found in world for this quest"
    else
        -- Ongoing: catalog destinations, then live journal InfoDict pins
        local dests = get_quest_destinations(qlm, qid) or get_live_info_destinations(qlm, qid)
        if not dests then return false, "no destinations (catalog or InfoDict)" end
        for _, dest in ipairs(dests) do
            local marker = build_marker(dest, qid)
            if marker then
                pcall(function() list:call("Add", marker) end)
                added = added + 1
            end
        end
        if added == 0 then return false, "no marker built" end
        MAP_API.pinned_data[qid] = dests
        MAP_API.last_msg = string.format("pinned qid=%d dest-mode %d markers", qid, added)
    end
    return true
end

unpin_quest = function(qid)
    MAP_API.pinned_data[qid] = nil; MAP_API.pinned_pos[qid] = nil
    MAP_API.last_msg = "unpinned qid=" .. qid
    force_marker_refresh()
    return true
end

local function sync_eliminated_to_prefs()
    ELIMINATED_OVERRIDES = {}
    for qid, list2 in pairs(MAP_API.eliminated_pos or {}) do
        local saved = {}
        for _, p in ipairs(list2) do
            if p.cid and p.cid > 0 then saved[#saved+1] = { cid=p.cid, x=p.x, y=p.y, z=p.z } end
        end
        if #saved > 0 then ELIMINATED_OVERRIDES[qid] = saved end
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
end

-- Pin every Ongoing quest regardless of active tab or filter.
local function pin_all_ongoing()
    pcall(init_map_api)
    local new_pins, skipped, failed = 0, 0, 0
    for _, q in ipairs(mod.quests or {}) do
        if (not q.voided) and q.category == "Ongoing" then
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
                        mlog("[PIN ONGOING] qid=" .. q.id ..
                            " pcall_ok=" .. tostring(ok_pin) ..
                            " ok=" .. tostring(pin_ok) ..
                            " err=" .. tostring(pin_msg))
                    end
                end
            end
        end
    end
    MAP_API.last_msg = string.format("Pin Ongoing: %d new, %d skipped, %d failed", new_pins, skipped, failed)
    mlog("[QT][map] " .. MAP_API.last_msg)
end

-- Pin every Available quest regardless of active tab or filter.
local function pin_all_available()
    pcall(init_map_api)
    local new_pins, skipped, failed = 0, 0, 0
    for _, q in ipairs(mod.quests or {}) do
        if (not q.voided) and q.category == "Available" then
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
                        mlog("[PIN AVAILABLE] qid=" .. q.id ..
                            " pcall_ok=" .. tostring(ok_pin) ..
                            " ok=" .. tostring(pin_ok) ..
                            " err=" .. tostring(pin_msg))
                    end
                end
            end
        end
    end
    MAP_API.last_msg = string.format("Pin Available: %d new, %d skipped, %d failed", new_pins, skipped, failed)
    mlog("[QT][map] " .. MAP_API.last_msg)
end

package.loaded["quest_tracker_map"] = M

M.API = MAP_API
M.init_map_api = init_map_api
M.clear_injected_markers = clear_injected_markers
M.get_quest_resource = get_quest_resource
M.get_quest_cast_charaids = get_quest_cast_charaids
M.force_marker_refresh = force_marker_refresh
M.pin_quest = pin_quest
M.unpin_quest = unpin_quest
M.unpin_candidate = unpin_candidate
M.restore_candidate = restore_candidate
M.restore_all_candidates = restore_all_candidates
M.pin_all = pin_all_in_current_filtered_tab
M.pin_all_ongoing = pin_all_ongoing
M.pin_all_available = pin_all_available
M.matches_filter = matches_filter
M.visible_for_current_tab = visible_for_current_tab

return M
