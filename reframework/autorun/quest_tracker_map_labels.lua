-- quest_tracker_map_labels.lua — map text labels
-- GOLDEN: v1.4.0 lifecycle + v1.2.7 TU API (call6_false). No invent ladder / UniqId / color.
local LABELS_MOD_VER = "1.4.58"
local M = package.loaded["quest_tracker_map_labels"]
if M and M._labels_mod_ver == LABELS_MOD_VER then return M end
M = { _labels_mod_ver = LABELS_MOD_VER }

local mod, mlog, mlog_boot, safe_get_field, safe_call, iter_list, to_int, td
local MAP_API = nil

local ICON_ICON_TYPE = 25
local INT_T, INT_T_VOFF
local _label_cap_logged = false
local _label_add_fail_logged = {}
local _guid_miss_logged = {}
local _oor_logged = {}

local function _mlog_map(...)
    if mlog_boot then mlog_boot(...)
    elseif mlog then mlog(...) end
end

-- #region agent log
local _DBG62_PATH = "c:/Users/jzafi/Desktop/New folder/OTHERMODS/QuestTracker-Modded/debug-62ebea.log"
local _DBG62_PATH_GAME = "C:/Program Files (x86)/Steam/steamapps/common/Dragons Dogma 2/reframework/data/debug-62ebea.log"
local function _dbg62(hyp, loc, msg, data_tbl)
    local parts = {}
    if type(data_tbl) == "table" then
        for k, v in pairs(data_tbl) do
            local vs = tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", " ")
            parts[#parts + 1] = string.format('"%s":"%s"', tostring(k), vs)
        end
    end
    local payload = string.format(
        '{"sessionId":"62ebea","hypothesisId":"%s","location":"%s","message":"%s","data":{%s},"timestamp":%d}\n',
        tostring(hyp), tostring(loc), tostring(msg):gsub('"', "'"), table.concat(parts, ","),
        math.floor((os.clock() or 0) * 1000)
    )
    for _, p in ipairs({ _DBG62_PATH, _DBG62_PATH_GAME }) do
        pcall(function()
            local f = io.open(p, "a")
            if f then f:write(payload); f:close() end
        end)
    end
    _mlog_map(string.format("[QT][dbg62] hyp=%s %s %s", tostring(hyp), tostring(msg), table.concat(parts, " ")))
end
-- #endregion

local function _td(name)
    if type(td) == "function" then return td(name) end
    return sdk.find_type_definition(name)
end

function M.install(ctx, map_api)
    if type(ctx) ~= "table" or type(map_api) ~= "table" then return false end
    mod = ctx.mod
    mlog = ctx.mlog
    mlog_boot = ctx.mlog_boot
    safe_get_field = ctx.safe_get_field
    safe_call = ctx.safe_call
    iter_list = ctx.iter_list
    to_int = ctx.to_int
    td = ctx.td
    MAP_API = map_api
    if mlog_boot then
        mlog_boot("[QT][map][labels] module installed v" .. LABELS_MOD_VER .. " (TU6 call6_false)")
    end
    return true
end

function M.on_layer_change()
    if MAP_API then
        MAP_API._qt_injected_labels = {}
        MAP_API._qt_injected_label_idxs = {}
        MAP_API._label_invoke_win = nil
    end
    _label_add_fail_logged = {}
    _label_cap_logged = false
    _guid_miss_logged = {}
    _oor_logged = {}
end

function M.reset_probe()
end

function M.probe_api()
    if MAP_API == nil or MAP_API._add_map_icon_probed then return end
    MAP_API._add_map_icon_probed = true
    local t = _td("app.ui040205")
    if t == nil then return end
    local counts = {}
    pcall(function()
        for _, m in ipairs(t:get_methods() or {}) do
            local n = m:get_name()
            if n == "addMapIconInfoList" then
                local pc = -1
                pcall(function() pc = m:get_num_params() end)
                counts[#counts + 1] = tostring(pc)
            end
        end
    end)
    _mlog_map(string.format("[QT][map] addMapIconInfoList overloads params=%s", table.concat(counts, ",")))
    -- #region agent log
    _dbg62("A", "map_labels:probe_api", "overload_param_counts", {
        params = table.concat(counts, ","),
    })
    -- #endregion
end

function M.install_vanilla_sniff()
end

local function _icon_init_helpers()
    if INT_T == nil then
        INT_T = sdk.find_type_definition("System.Int32")
        if INT_T then
            local f = INT_T:get_field("m_value")
            if f then INT_T_VOFF = f:get_offset_from_base() end
        end
    end
end

-- Catalog helper used by map.lua pin paths (Original QT).
function M.get_quest_resource(qlm, qid)
    if qlm == nil or qid == nil then return nil end
    local cat = safe_get_field(qlm, "_Catalog")
    if cat == nil then return nil end
    local vals = safe_call(cat, "getValues")
    if vals == nil then return nil end
    local sz = 0
    pcall(function() sz = vals:get_size() end)
    for i = 0, sz - 1 do
        local ok, v = pcall(function() return vals:get_element(i) end)
        if ok and v then
            if to_int(safe_get_field(v, "_QuestId") or safe_call(v, "get_QuestId")) == qid then return v end
        end
    end
    return nil
end

local function _guid_from_object(obj)
    if obj == nil then return nil end
    for _, key in ipairs({ "QuestNameId", "_QuestNameId", "NameId", "_NameId", "TitleId", "_TitleId" }) do
        local g = safe_get_field(obj, key) or (safe_call and safe_call(obj, "get_" .. key))
        if g and type(g) ~= "string" and type(g) ~= "number" and type(g) ~= "boolean" then return g end
    end
    return nil
end

local function _guid_scan_type_fields(obj)
    if obj == nil then return nil end
    local ok_t, tdef = pcall(function() return obj:get_type_definition() end)
    if not ok_t or tdef == nil then return nil end
    -- Name/Title only. Never scan "Message*" — that grabbed wrong quest banners
    -- (Candle pin labeled "Crossing in Shadow", Test3 screenshot).
    for _, f in ipairs(tdef:get_fields()) do
        local ok_static, is_st = pcall(function() return f:is_static() end)
        if ok_static and not is_st then
            local fn = f:get_name()
            if fn:find("NameId", 1, true) or fn:find("QuestName", 1, true) or fn:find("Title", 1, true) then
                if not fn:find("Message", 1, true) then
                    local ok_v, v = pcall(function() return f:get_data(obj) end)
                    if ok_v and v ~= nil and type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" then
                        return v
                    end
                end
            end
        end
    end
    return nil
end

local function _log_catalog_fields_once(qid, res)
    MAP_API._catalog_fields_logged = MAP_API._catalog_fields_logged or {}
    if MAP_API._catalog_fields_logged[qid] then return end
    MAP_API._catalog_fields_logged[qid] = true
    local names = {}
    pcall(function()
        local tdef = res:get_type_definition()
        if tdef == nil then return end
        for _, f in ipairs(tdef:get_fields()) do
            local ok_static, is_st = pcall(function() return f:is_static() end)
            if ok_static and not is_st then
                names[#names + 1] = f:get_name()
                if #names >= 24 then break end
            end
        end
    end)
    -- #region agent log
    _dbg62("H2", "map_labels:catalog_fields", "catalog_field_names", {
        qid = tostring(qid), fields = table.concat(names, ","),
    })
    -- #endregion
    _mlog_map(string.format("[QT][map] catalog fields qid=%d %s", qid, table.concat(names, ",")))
end

local function _name_guid_from_quest_manager(qid)
    local qm = sdk.get_managed_singleton("app.QuestManager")
    if qm == nil then return nil end
    local qcd = safe_get_field(qm, "QuestCatalogDict")
    if qcd == nil then return nil end
    local direct = safe_call(qcd, "get_Item", qid) or safe_call(qcd, "TryGetValue", qid)
    if direct then
        local g = _guid_from_object(direct) or _guid_scan_type_fields(direct)
        if g then return g end
    end
    local vals = safe_call(qcd, "getValues")
    if vals == nil then return nil end
    local cdsz = 0
    pcall(function() cdsz = vals:get_size() end)
    for k = 0, cdsz - 1 do
        local ok, cd = pcall(function() return vals:get_element(k) end)
        if ok and cd then
            local ctx = safe_get_field(cd, "ContextData")
            if ctx then
                local arr = safe_get_field(ctx, "ContextDataArray")
                if arr then
                    local asz = 0
                    pcall(function() asz = arr:get_size() end)
                    for j = 0, asz - 1 do
                        local okE, e = pcall(function() return arr:get_element(j) end)
                        if okE and e and to_int(safe_get_field(e, "_IDValue")) == qid then
                            return _guid_from_object(e) or _guid_scan_type_fields(e)
                                or _guid_from_object(cd) or _guid_scan_type_fields(cd)
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Vanilla: QuestLogManager:getQuestLog(qid).QuestNameId first.
-- Fallback: catalog field scan + QuestManager deep scan for Available.
function M.get_quest_name_guid(qid)
    if qid == nil then return nil end
    MAP_API._name_guid_cache = MAP_API._name_guid_cache or {}
    if MAP_API._name_guid_cache[qid] then return MAP_API._name_guid_cache[qid] end

    local qlm = sdk.get_managed_singleton("app.QuestLogManager")
    if qlm ~= nil then
        local vi = safe_call(qlm, "getQuestLog", qid)
        if vi ~= nil then
            local g = _guid_from_object(vi) or _guid_scan_type_fields(vi)
            if g ~= nil then
                MAP_API._name_guid_cache[qid] = g
                _mlog_map(string.format("[QT][map] name_guid qid=%d source=QuestNameId", qid))
                return g
            end
        end
        local res = M.get_quest_resource(qlm, qid)
        if res then
            local g = _guid_from_object(res) or _guid_scan_type_fields(res)
            if g ~= nil then
                MAP_API._name_guid_cache[qid] = g
                _mlog_map(string.format("[QT][map] name_guid qid=%d source=catalog.scan", qid))
                return g
            end
            _log_catalog_fields_once(qid, res)
        else
            -- #region agent log
            _dbg62("H2", "map_labels:guid_catalog", "catalog_miss", {
                qid = tostring(qid),
            })
            -- #endregion
        end
    end

    local qm_g = _name_guid_from_quest_manager(qid)
    if qm_g then
        MAP_API._name_guid_cache[qid] = qm_g
        _mlog_map(string.format("[QT][map] name_guid qid=%d source=QuestManager", qid))
        return qm_g
    end

    if mod and mod._qt_name_guid_cache and mod._qt_name_guid_cache[qid] then
        MAP_API._name_guid_cache[qid] = mod._qt_name_guid_cache[qid]
        _mlog_map(string.format("[QT][map] name_guid fallback qid=%d source=meta_cache", qid))
        return MAP_API._name_guid_cache[qid]
    end

    if not _guid_miss_logged[qid] then
        _guid_miss_logged[qid] = true
        _mlog_map(string.format("[QT][map] name_guid miss qid=%d", qid))
    end
    return nil
end

-- v1.4.0 shape + TU 6th arg false (v1.2.7 proven). Success = UI icon AND list grows.
local function _add_one_labeled_icon(this, x, y, z, name_guid, idx_obj, qid, icon_idx)
    local t2 = _td("app.GuiManager.MapIconInfo")
    if t2 == nil then return nil end
    local ok, info = pcall(function() return t2:create_instance():add_ref() end)
    if not ok or info == nil then return nil end

    -- Log-only range probe (never hard-skip). Hugo OOR must not kill add.
    local in_range = nil
    pcall(function() in_range = this:isInDispRange(Vector3f.new(x, y, z)) end)
    if in_range == nil then
        pcall(function() in_range = this:call("isInDispRange", Vector3f.new(x, y, z)) end)
    end
    if in_range == false and qid and not _oor_logged[qid] then
        _oor_logged[qid] = true
        _mlog_map(string.format("[QT][map] label oor note qid=%d (still adding)", qid))
        -- #region agent log
        _dbg62("B", "map_labels:oor_note", "label_oor_log_only", {
            qid = tostring(qid),
            xyz = string.format("%.0f,%.0f,%.0f", x or 0, y or 0, z or 0),
        })
        -- #endregion
    end

    pcall(function()
        info.IsEnable = true
        info.IsNavi = false
        info.IconId = 0
        info.SortNo = 0
        info.IconType = ICON_ICON_TYPE
        info.Timing = 0
        info.Pos = Vector3f.new(x, y, z)
        info.Area = -1
        info.LocalArea = 0
        info.IsDispAllArea = true
    end)

    local info_it_pre = "?"
    pcall(function()
        info_it_pre = tostring(info.IconType or safe_get_field(info, "IconType"))
    end)

    local count_b = -1
    pcall(function() count_b = this.MapIconInfoList:get_Count() end)
    local idx_addr = idx_obj:get_address() + INT_T_VOFF
    local path = "call6_false"

    -- #region agent log
    _dbg62("C", "map_labels:tu6_pre", "label_pre", {
        qid = tostring(qid or -1), count = tostring(count_b),
        xyz = string.format("%.0f,%.0f,%.0f", x or 0, y or 0, z or 0),
        guid_type = type(name_guid), info_it = info_it_pre,
        in_range = tostring(in_range), path = path,
    })
    -- #endregion

    local okA, ui_icon = pcall(function()
        return this:call("addMapIconInfoList", info, 0, idx_addr, -1, name_guid, false)
    end)

    local count_a = -1
    pcall(function() count_a = this.MapIconInfoList:get_Count() end)
    local grew = (type(count_b) == "number" and type(count_a) == "number" and count_a > count_b)

    if okA and ui_icon ~= nil and grew then
        if qid then
            MAP_API._qt_injected_labels = MAP_API._qt_injected_labels or {}
            MAP_API._qt_injected_labels[qid] = MAP_API._qt_injected_labels[qid] or {}
            MAP_API._qt_injected_labels[qid][#MAP_API._qt_injected_labels[qid] + 1] = ui_icon
            MAP_API._qt_injected_label_idxs = MAP_API._qt_injected_label_idxs or {}
            MAP_API._qt_injected_label_idxs[#MAP_API._qt_injected_label_idxs + 1] = {
                idx = icon_idx, qid = qid, ref = ui_icon,
            }
        end
        MAP_API._label_invoke_win = path
        local guid_s, slot_it, ui_it = "?", "?", "?"
        pcall(function() guid_s = tostring(name_guid:ToString()) end)
        pcall(function()
            local slot = this.MapIconInfoList:get_Item(count_b)
            if slot == nil then slot = this.MapIconInfoList:call("get_Item", count_b) end
            if slot then
                local it = slot.IconType or safe_get_field(slot, "IconType")
                slot_it = tostring(it)
            end
        end)
        pcall(function()
            local it = ui_icon.IconType or safe_get_field(ui_icon, "IconType")
            ui_it = tostring(it)
        end)
        -- #region agent log
        _dbg62("E", "map_labels:tu6_ok", "label_ok", {
            qid = tostring(qid or -1), path = path,
            count = string.format("%d->%d", count_b, count_a),
            has_Icon = tostring(ui_icon.Icon ~= nil),
            slot_it = slot_it, ui_it = ui_it,
            info_it = info_it_pre, guid = guid_s:sub(1, 36),
        })
        -- #endregion
        _mlog_map(string.format("[QT][map] label add OK qid=%d idx=%d path=%s count %d→%d slot_IT=%s ui_IT=%s info_IT=%s",
            qid or -1, icon_idx or -1, path, count_b, count_a, slot_it, ui_it, info_it_pre))
        return ui_icon
    end

    local err = (not okA) and tostring(ui_icon)
        or ((ui_icon == nil) and "nil_ui_icon")
        or (not grew and "count_stale")
        or "unknown"
    -- #region agent log
    _dbg62("C", "map_labels:tu6_fail", "label_fail", {
        qid = tostring(qid or -1), path = path, err = err,
        count = string.format("%d->%d", count_b, count_a),
        info_it = info_it_pre, has_ui = tostring(ui_icon ~= nil),
    })
    -- #endregion
    if qid and not _label_add_fail_logged[qid] then
        _label_add_fail_logged[qid] = true
        _mlog_map(string.format("[QT][map] label add FAIL qid=%d err=%s path=%s count %d→%d",
            qid, err, path, count_b, count_a))
    end
    return nil
end

function M.count_wanted_labels()
    if not MAP_API then return 0 end
    local seen, want = {}, 0
    for qid in pairs(MAP_API.pinned_label_pos or {}) do
        if not seen[qid] then seen[qid] = true; want = want + 1 end
    end
    for qid in pairs(MAP_API.pinned_pos or {}) do
        if not seen[qid] then seen[qid] = true; want = want + 1 end
    end
    return want
end

function M.add_labeled_markers_for_all_pins(this)
    if mod == nil or mod.label_pins ~= true then return 0 end
    if this == nil or MAP_API == nil then return 0 end
    _icon_init_helpers()
    if INT_T == nil or INT_T_VOFF == nil then return 0 end

    local icon_count = 0
    local icon_limit = 0
    pcall(function() icon_count = this.MapIconInfoList:get_Count() end)
    pcall(function() icon_limit = this.MapIcon:get_Length() end)
    if icon_limit == 0 or icon_count >= icon_limit then
        if not _label_cap_logged then
            _label_cap_logged = true
            _mlog_map(string.format("[QT][map] label cap hit count=%d limit=%d skipped=%d",
                icon_count, icon_limit, M.count_wanted_labels()))
        end
        return 0
    end

    local added = 0
    local idx_obj = INT_T:create_instance():add_ref()
    local labeled = {}

    -- One banner per qid. Prefer pinned_label_pos; skip pinned_pos if already labeled.
    for qid, anchor in pairs(MAP_API.pinned_label_pos or {}) do
        if icon_count >= icon_limit then break end
        local name_guid = M.get_quest_name_guid(qid)
        if name_guid ~= nil and anchor then
            idx_obj:write_dword(INT_T_VOFF, icon_count)
            if _add_one_labeled_icon(this, anchor.x, anchor.y, anchor.z, name_guid, idx_obj, qid, icon_count) ~= nil then
                icon_count = icon_count + 1
                added = added + 1
                labeled[qid] = true
                if HYBRID_AREA_QIDS and HYBRID_AREA_QIDS[qid] then
                    _mlog_map(string.format("[QT][map] hybrid %d anchor=(%.0f,%.0f,%.0f) label_icon=ok",
                        qid, anchor.x, anchor.y, anchor.z))
                end
            elseif HYBRID_AREA_QIDS and HYBRID_AREA_QIDS[qid] then
                _mlog_map(string.format("[QT][map] hybrid %d anchor=(%.0f,%.0f,%.0f) label_icon=fail",
                    qid, anchor.x, anchor.y, anchor.z))
            end
        elseif not _label_add_fail_logged[qid] then
            _label_add_fail_logged[qid] = true
            local reason = (name_guid == nil) and "name_guid_nil" or "xyz_nil"
            _mlog_map(string.format("[QT][map] label FAIL qid=%d reason=%s count=%d limit=%d",
                qid, reason, icon_count, icon_limit))
            -- #region agent log
            _dbg62("H2", "map_labels:guid_miss", "label_skip_no_guid", {
                qid = tostring(qid), reason = reason,
            })
            -- #endregion
        end
    end
    for qid, pins in pairs(MAP_API.pinned_pos or {}) do
        if labeled[qid] then
            -- already labeled via pinned_label_pos
        elseif icon_count >= icon_limit then
            break
        else
            local name_guid = M.get_quest_name_guid(qid)
            if name_guid ~= nil and pins then
                for _, p in ipairs(pins) do
                    if icon_count >= icon_limit then break end
                    idx_obj:write_dword(INT_T_VOFF, icon_count)
                    if _add_one_labeled_icon(this, p.x, p.y, p.z, name_guid, idx_obj, qid, icon_count) ~= nil then
                        icon_count = icon_count + 1
                        added = added + 1
                        labeled[qid] = true
                        break
                    end
                end
            elseif not _label_add_fail_logged[qid] then
                _label_add_fail_logged[qid] = true
                _mlog_map(string.format("[QT][map] label FAIL qid=%d reason=name_guid_nil count=%d limit=%d",
                    qid, icon_count, icon_limit))
                -- #region agent log
                _dbg62("H2", "map_labels:guid_miss", "label_skip_no_guid", {
                    qid = tostring(qid), reason = "name_guid_nil",
                })
                -- #endregion
            end
        end
    end
    return added
end

-- Soft-clear tracked label refs only. Never touch QuestTargetMarkerList here.
function M.wipe_injected(ui)
    if not MAP_API then return 0 end
    MAP_API._qt_injected_labels = {}
    MAP_API._qt_injected_label_idxs = {}
    MAP_API._name_guid_cache = {}
    return 0
end

local HYBRID_AREA_QIDS = nil
function M.set_hybrid_qids(tbl) HYBRID_AREA_QIDS = tbl end

package.loaded["quest_tracker_map_labels"] = M
return M
