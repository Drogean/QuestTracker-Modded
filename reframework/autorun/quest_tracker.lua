-- quest_tracker.lua — DD2 quest list UI orchestrator (v1.1.8)
-- Submodules: quest_tracker_prefs/sdk/gather, quest_tracker_steps(+resolve), plugins, window, map, cache

local MOD_NAME = "Quest Tracker Reduxx"
local MOD_VERSION = "1.2.8"

local DEFAULT_QUEST_WIN_W = 786
local DEFAULT_QUEST_WIN_H = 877
local DEFAULT_QUEST_WIN_Y = 945
local DEFAULT_QUEST_WIN_MARGIN_R = 0
local DEFAULT_QUEST_WIN_MARGIN_B = 72
local MIN_SAVE_WIN_W = 520
local MIN_SAVE_WIN_H = 280
local COL_NPC_ORANGE = 0xFF00A5FF
local COL_NPC_GOOD   = 0xFF33FF33

local QT_TIME_INTERVAL       = 5.0
local QT_STATE_PROBE_INTERVAL = 15.0
local QT_NPC_SCAN_INTERVAL   = 30.0
local QT_COMPLETION_SWEEP    = 45.0
local NPC_SCAN_CACHE_TTL     = 30.0

_G._qt_frame_gen = (_G._qt_frame_gen or 0) + 1
local _QT_FRAME_GEN = _G._qt_frame_gen
if _G._quest_tracker_loaded then
    if log and log.warn then log.warn("[" .. MOD_NAME .. "] reload v" .. MOD_VERSION .. " gen=" .. tostring(_QT_FRAME_GEN)) end
else
    _G._quest_tracker_loaded = true
end

local LOG_PATH   = "quest_tracker_log.txt"
local _log_ready = false

local function _log_needs_wipe()
    local f = io.open(LOG_PATH, "rb")
    if not f then return true end
    local head = f:read(128) or ""
    f:close()
    if head == "" then return true end
    return not head:find(MOD_VERSION, 1, true)
end

local function mlog_boot(...)
    local args, parts = {...}, {}
    for i = 1, select("#", ...) do parts[i] = tostring(args[i]) end
    local line = "[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. table.concat(parts, " ")
    pcall(function()
        if not _log_ready then
            _log_ready = true
            if _log_needs_wipe() then
                local fw = io.open(LOG_PATH, "wb")
                if fw then
                    fw:write("-- quest_tracker v" .. MOD_VERSION .. " started " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
                    fw:close()
                end
            end
        end
        local f = io.open(LOG_PATH, "ab")
        if f then f:write(line, "\n"); f:close() end
    end)
    if log and log.info then pcall(log.info, line) end
end

local mod
local function mlog(...)
    if type(mod) ~= "table" or not mod.debug_logging then return end
    mlog_boot(...)
end

if _log_needs_wipe() then
    mlog_boot("[QT] log wiped for new build v" .. MOD_VERSION .. " (file kept, contents cleared)")
end
mlog_boot("[" .. MOD_NAME .. "] ===== mod loaded v" .. MOD_VERSION .. " =====")
mlog_boot("[QT] via.gui.message text lookup: OFF (crash-safe; progress-first steps)")

local MANUAL_POS_OVERRIDES = {
    [10110] = { x = 493.9796600341797,   y = 27.427902221679688, z = -1025.0746459960938 },
    [10130] = { x = 496.31145095825195,  y = 24.031455993652344, z = -1054.4935245513916 },
    [10140] = { x = 493.6757583618164,   y = 27.427902221679688, z = -1024.9119186401367 },
    [10151] = { x = -1453.9278030395508, y = 101.23748588562012,  z = 300.42830657958984 },
    [20040] = { x = 208.3,               y = 141.4,              z = -2168.6 },
    [20060] = { x = -1454.6352767944336, y = 107.46630477905273,  z = 421.0796432495117 },
    [20080] = { x = -425.93798446655273, y = 4.689894199371338,  z = -643.8243865966797 },
    [20082] = { x = -416.230167388916,   y = 2.9613876342773438, z = -728.1577644348145 },
    [20090] = { x = 488.7228469848633,   y = 24.03145408630371,  z = -1063.8864059448242 },
    [20110] = { x = 388.38623809814453,  y = 33.34857177734375,   z = -1025.7169268131256 },
    [20130] = { x = 591.3,               y = 9.3,                z = -968.2 },
    [20200] = { x = -1226.0890998840332, y = 200.0381965637207,  z = -1696.9209213256836 },
    [20220] = { x = 493.5822525024414,   y = 27.427902221679688, z = -1024.993310213089 },
    [20240] = { x = 479.8509979248047,   y = 28.77345848083496,  z = -1020.0119707584381 },
    [20340] = { x = 560.8182220458984,   y = 23.017465591430664,  z = -1027.091487646103 },
    [20350] = { x = -1918.546501159668,  y = 234.49042510986328, z = -931.1457595825195 },
    [20390] = { x = 501.0633010864258,   y = 26.927902221679688,  z = -1032.420509338379 },
    [20420] = { x = -1278.8292846679688, y = 115.24274444580078,  z = 418.3339424133301 },
    [20440] = { x = -1235.3050537109375, y = 116.8261489868164,   z = 437.31350326538086 },
    [20450] = { x = -508.02643847465515, y = 125.331298828125,    z = -2200.9063472747803 },
    [20460] = { x = -278.0672073364258,  y = 18.997406005859375,  z = 1057.7830772399902 },
    [20470] = { x = 296.1302909851074,   y = 85.62184143066406,   z = 1340.941234588623 },
    [30010] = { x = 489.1841506958008,   y = 21.699199676513672, z = -1080.0725326538086 },
    [30040] = { x = 493.96543884277344,  y = 27.427902221679688, z = -1024.906347155571 },
    [30050] = { x = 377.1,               y = 70.1,               z = -887.4 },
    [30070] = { x = 480.5570602416992,   y = 24.031455993652344, z = -1072.866901397705 },
    [30090] = { x = -578.5190048217773,  y = 127.0729392170906,   z = -2219.5535011291504 },
    [30110] = { x = 99.80061149597168,   y = 157.997220993042,   z = -2122.4835624694824 },
    [30200] = { x = -269.24205780029297, y = 28.95209503173828,   z = 1114.0038223266602 },
    [30210] = { x = -1952.9680557250977, y = 258.339635848999,    z = -779.3873443603516 },
    [30220] = { x = -1020.84508228302,   y = 85.06685638427734,   z = 274.2882251739502 },
    [30240] = { x = 324.0470886230469,   y = 530.5744247436523,   z = 1668.7981867790222 },
}

-- Mercy: blob at dest + diamond at MANUAL_POS override
local HYBRID_AREA_QIDS = { [30210] = true }
-- True area quests only — yellow blob + diamond + label (Sculptor confirmed)
local BLOB_AREA_QIDS = { [20310] = true }

local ELIMINATED_OVERRIDES = {}

local MANUAL_GIVER_OVERRIDES = {
    [10090] = 189868107,  [10100] = 189868107,  [10120] = 189868107,
    [20010] = 3287815186, [20020] = 41790483,   [20030] = 527644994,
    [20050] = 2984506176, [20100] = 2954976292,
    [20120] = 920227254,  [20140] = 1488552131, [20150] = 3743885470,
    [20190] = 3689427708, [20230] = 3202987914, [20250] = 1191862039,
    [20270] = 3252066890, [20280] = 2151757684, [20290] = 1545619405,
    [20310] = 2884679268, [20330] = 4137867127, [20480] = 542068695,
    [30030] = 4006438697, [30041] = 1210835050, [30042] = 4267448965,
    [30050] = 1461307325, [30060] = 3560980369, [30080] = 1007143618,
    [30100] = 240278635,  [30120] = 1424070675, [30140] = 2145444378,
    [30150] = 678396953,  [30160] = 1603137626, [30170] = 1468499554,
    [30180] = 1210835050, [30230] = 43671194,
}

local BUNDLED_GIVER_OVERRIDES = {}
for k, v in pairs(MANUAL_GIVER_OVERRIDES) do BUNDLED_GIVER_OVERRIDES[k] = v end
local BUNDLED_POS_OVERRIDES = {}
for k, v in pairs(MANUAL_POS_OVERRIDES) do
    BUNDLED_POS_OVERRIDES[k] = { x = v.x, y = v.y, z = v.z }
end

local function is_bundled_giver(qid, cid) return BUNDLED_GIVER_OVERRIDES[qid] == cid end
local function is_bundled_pos(qid, p)
    local b = BUNDLED_POS_OVERRIDES[qid]
    if b == nil or p == nil then return false end
    return b.x == p.x and b.y == p.y and b.z == p.z
end

-- =========== USER STATE TABLES ===========
-- Declared here so save_prefs / load_prefs can reference them.
local mod  -- forward declare; assigned in MOD STATE (save_prefs must see this local)
local VOIDED_QUESTS    = {}   -- qid -> true (hidden by user)
local LOCKED_QUESTS    = {}   -- qid -> true (manually/auto locked, shown in red)
local QUEST_START_DAYS    = {}   -- qid -> in-game day when it first went Ongoing
local QUEST_START_HOURS   = {}   -- qid -> in-game hour when it first went Ongoing (0..23, used for hour-precision countdowns)
local LEARNED_CHARA_NAMES = {}   -- string(cid) -> friendly name learned at runtime (persisted in prefs)

-- Milestone-based lockouts (quests that must be done before a PoNR main quest).
local FEAST_MILESTONE = 10140
local BUNDLED_LOCKOUTS = {
    [20010] = { after = FEAST_MILESTONE }, [20020] = { after = FEAST_MILESTONE },
    [20030] = { after = FEAST_MILESTONE }, [20050] = { after = FEAST_MILESTONE },
    [20070] = { after = FEAST_MILESTONE }, [20190] = { after = FEAST_MILESTONE },
    [30010] = { after = FEAST_MILESTONE }, [30040] = { after = FEAST_MILESTONE },
    [30041] = { after = FEAST_MILESTONE },
}

local function merge_meta_feast_lockouts()
    if not QD or not QD.iter_meta_qids or not QD.is_must_before_feast or not QD.get_lockout_after then return end
    for _, qid in ipairs(QD.iter_meta_qids()) do
        local ok, must = pcall(QD.is_must_before_feast, qid)
        if ok and must then
            local ok2, la = pcall(QD.get_lockout_after, qid)
            if ok2 and la == FEAST_MILESTONE then
                BUNDLED_LOCKOUTS[qid] = { after = FEAST_MILESTONE }
            end
        end
    end
end


local PREFS_PATH = "quest_tracker_prefs.json"
local BAKED_LAYOUT_PATH = "quest_tracker_baked_layout.json"
local LAST_LAYOUT_PATH = "quest_tracker_last_layout.json"
local PERMANENT_LAYOUT_PATH = "quest_tracker_permanent_layout.json"
local PREF_KEYS  = {
    "show_window", "sort_mode", "highlight_recent", "tab", "label_pins", "debug_logging",
    "deep_sniff", "deep_sniff_heavy", "font_size",
    "layout_margin_r", "win_y", "win_w", "win_h", "win_alpha",
    "auto_pin_ongoing", "auto_pin_available",
    "time_longer_days", "time_faster_nights", "time_pause",
}

local function is_bundled_giver(qid, cid) return BUNDLED_GIVER_OVERRIDES[qid] == cid end
local function is_bundled_pos(qid, p)
    local b = BUNDLED_POS_OVERRIDES[qid]
    if b == nil or p == nil then return false end
    return b.x == p.x and b.y == p.y and b.z == p.z
end

local TAB_NAMES  = { "Available", "Ongoing", "Completed", "All", "Hidden" }
local SORT_NAMES = { "Last Updated", "Recent", "Distance" }
local FEAST_MILESTONE = 10140
local PONR_NAMES = {
    [10140] = "Feast of Deception",
    [10160] = "A New Godsway",
    [10170] = "The Guardian Gigantus",
    [10180] = "Legacy",
}

local ctx = {
    PREFS_PATH = PREFS_PATH,
    BAKED_LAYOUT_PATH = BAKED_LAYOUT_PATH,
    LAST_LAYOUT_PATH = LAST_LAYOUT_PATH,
    PERMANENT_LAYOUT_PATH = PERMANENT_LAYOUT_PATH,
    MIN_SAVE_WIN_W = MIN_SAVE_WIN_W,
    MIN_SAVE_WIN_H = MIN_SAVE_WIN_H,
    PREF_KEYS = PREF_KEYS,
    DEFAULT_QUEST_WIN_Y = DEFAULT_QUEST_WIN_Y,
    DEFAULT_QUEST_WIN_W = DEFAULT_QUEST_WIN_W,
    DEFAULT_QUEST_WIN_H = DEFAULT_QUEST_WIN_H,
    DEFAULT_QUEST_WIN_MARGIN_R = DEFAULT_QUEST_WIN_MARGIN_R,
    SORT_NAMES = SORT_NAMES,
    MANUAL_GIVER_OVERRIDES = MANUAL_GIVER_OVERRIDES,
    MANUAL_POS_OVERRIDES = MANUAL_POS_OVERRIDES,
    HYBRID_AREA_QIDS = HYBRID_AREA_QIDS,
    BLOB_AREA_QIDS = BLOB_AREA_QIDS,
    ELIMINATED_OVERRIDES = ELIMINATED_OVERRIDES,
    VOIDED_QUESTS = VOIDED_QUESTS,
    LOCKED_QUESTS = LOCKED_QUESTS,
    QUEST_START_DAYS = QUEST_START_DAYS,
    QUEST_START_HOURS = QUEST_START_HOURS,
    LEARNED_CHARA_NAMES = LEARNED_CHARA_NAMES,
    is_bundled_giver = is_bundled_giver,
    is_bundled_pos = is_bundled_pos,
    mlog_boot = mlog_boot,
}

mod = {
    show_window      = true,
    quests           = {},
    name_cache       = {},
    name_en_cache    = {},
    summary_cache    = {},
    last_refresh     = 0,
    refresh_interval = 5.0,
    last_autolock    = 0,
    filter_text      = "",
    tab              = 1,
    sort_mode        = 1,
    highlight_recent = true,
    label_pins       = true,
    debug_logging    = true,
    deep_sniff       = false,
    deep_sniff_heavy = false,
    _guid_lookup_ok  = false,
    auto_pin_ongoing  = false,
    auto_pin_available = false,
    time_longer_days = false,
    time_faster_nights = false,
    time_pause = false,
    font_size        = 28,
    win_alpha        = 0.4,
    layout_margin_r  = DEFAULT_QUEST_WIN_MARGIN_R,
    win_x            = 0,
    win_y            = DEFAULT_QUEST_WIN_Y,
    win_w            = DEFAULT_QUEST_WIN_W,
    win_h            = DEFAULT_QUEST_WIN_H,
    _game_ready      = false,
    _qt_shutdown     = false,
    state_counts     = {0, 0, 0, 0, 0},
    progressing_ids  = {},
    acceptable_ids   = {},
    completed_ids    = {},
    upcoming_ids     = {},
    recency_order    = {},
    newest_completed = nil,
    _prefs_dirty     = false,
    _live_in_game_day = 0,
    _row_cache = {},
    _row_static = {},
    _draw_quest_list = {},
    _npc_scan_cache = {},
}

ctx.mod = mod
ctx.mlog = mlog
ctx._QT_FRAME_GEN = _QT_FRAME_GEN
if _QT_FRAME_GEN > 1 then package.loaded["quest_tracker_prefs"] = nil end
local Prefs = require("quest_tracker_prefs")
Prefs.install(ctx)
ctx.load_prefs_early()
ctx.apply_prefs_to_mod()

if _QT_FRAME_GEN > 1 then
    mod._step_last_title = {}
    mod._steps_module_ok = nil
    mod._cache_module_ok = nil
    mod._row_static = {}
    mod._qt_fp = nil
    mlog("[QT] hot-reload: cleared step + static caches")
end

require("quest_tracker_sdk").install(ctx)

local ALL_IDS = nil
ctx.ALL_IDS = ALL_IDS

local QD_OK, QD = pcall(require, "quest_data_loader")
if QD_OK and QD then
    mlog("[QT] quest_data_loader: require OK")
    if QD.count_wiki_hint_quests then
        mod._cached_wiki_hint_n = QD.count_wiki_hint_quests()
        local n = mod._cached_wiki_hint_n
        if n < 5 then
            mlog("[QT] WARN wiki hints missing — install quest_tracker_wiki_hints.json under reframework/data/")
        else
            mlog("[QT] wiki hints loaded: " .. n .. " quests")
        end
    end
else
    QD = nil
    mlog_boot("[QT] quest_data_loader: require FAILED")
end
ctx.QD = QD
pcall(merge_meta_feast_lockouts)

local MAP_API = { ready = false, pinned_data = {}, pinned_pos = {}, eliminated_pos = {}, status = "map module failed", last_msg = "" }
local MapBridge = {
    init_map_api = function() return false end,
    clear_injected_markers = function() end,
    get_quest_resource = function() return nil end,
    get_quest_cast_charaids = function() return nil end,
    force_marker_refresh = function() end,
    pin_quest = function() return false end,
    unpin_quest = function() return false end,
    unpin_candidate = function() return false end,
    restore_candidate = function() return false end,
    restore_all_candidates = function() end,
}
ctx.MAP_API = MAP_API
ctx.MapBridge = MapBridge
ctx.TAB_NAMES = TAB_NAMES
ctx.FEAST_MILESTONE = FEAST_MILESTONE
ctx.PONR_NAMES = PONR_NAMES
ctx.BUNDLED_LOCKOUTS = BUNDLED_LOCKOUTS
ctx.BUNDLED_POS_OVERRIDES = BUNDLED_POS_OVERRIDES
ctx.COL_NPC_GOOD = COL_NPC_GOOD
ctx.COL_NPC_ORANGE = COL_NPC_ORANGE
ctx.NPC_SCAN_CACHE_TTL = NPC_SCAN_CACHE_TTL

local function _teleport_player_to(x, y, z)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return false end
    local mp = ctx._get_manual_player and ctx._get_manual_player()
    if not mp then return false end
    local ok = pcall(function()
        local p = mp:get_UniversalPosition()
        if p then p.x, p.y, p.z = x, y, z end
    end)
    return ok
end
ctx._teleport_player_to = _teleport_player_to

local Map
local _map_ok, MapMod = pcall(require, "quest_tracker_map")
ctx.Map = MapMod
require("quest_tracker_gather").install(ctx)
ALL_IDS = ctx.ALL_IDS

local TimeMod
do
    local ok_tm, TM = pcall(require, "quest_tracker_time")
    if ok_tm and TM and TM.install then
        TM.install({
            mod = mod,
            mlog = mlog,
            mlog_boot = mlog_boot,
            _QT_FRAME_GEN = _QT_FRAME_GEN,
            _get_game_clock_integers = ctx._get_game_clock_integers,
            _set_time_scale = ctx._set_time_scale,
            _get_time_scale = ctx._get_time_scale,
            _set_game_clock_integers = ctx._set_game_clock_integers,
            _tick_fast_forward = ctx._tick_fast_forward,
        })
        TimeMod = TM
    else
        mlog("[QT] WARN quest_tracker_time require failed: " .. tostring(TM))
    end
end
ctx.TimeMod = TimeMod

local function _qt_enter_shutdown()
    if mod._qt_shutdown_logged then return end
    mod._qt_shutdown = true
    mod._game_ready = false
    mod._qt_shutdown_logged = true
    mlog_boot("[QT] shutdown — hooks idle")
end

local function _check_game_ready()
    if mod._qt_shutdown then return false end
    if mod._game_ready then
        if ctx._get_manual_player then
            local mp = ctx._get_manual_player()
            if mp == nil then
                _qt_enter_shutdown()
                return false
            end
        end
        return true
    end
    if not ctx._get_manual_player then return false end
    local mp = ctx._get_manual_player()
    if mp == nil then return false end
    mod._game_ready = true
    mod._logic_force = true
    mlog_boot("[QT] game ready — logic enabled")
    return true
end
ctx._check_game_ready = _check_game_ready

if _map_ok and MapMod and MapMod.install then
    Map = MapMod
    local ok_inst = MapMod.install({
        mod = mod,
        mlog = mlog,
        mlog_boot = mlog_boot,
        qt_verbose = function(msg) mlog("[QT] " .. tostring(msg)) end,
        td = ctx.td,
        safe_get_field = ctx.safe_get_field,
        safe_call = ctx.safe_call,
        iter_list = ctx.iter_list,
        to_int = ctx.to_int,
        cid_eq = ctx.cid_eq,
        cid_norm = ctx.cid_norm,
        get_character_world_pos = ctx.get_character_world_pos,
        mark_prefs_dirty = ctx.mark_prefs_dirty,
        MANUAL_POS_OVERRIDES = MANUAL_POS_OVERRIDES,
        HYBRID_AREA_QIDS = HYBRID_AREA_QIDS,
        BLOB_AREA_QIDS = BLOB_AREA_QIDS,
        MANUAL_GIVER_OVERRIDES = MANUAL_GIVER_OVERRIDES,
        ELIMINATED_OVERRIDES = ELIMINATED_OVERRIDES,
        BUNDLED_GIVER_OVERRIDES = BUNDLED_GIVER_OVERRIDES,
        is_bundled_giver = is_bundled_giver,
        qd_givers = ctx.qd_givers,
        qd_givers_display_order = ctx.qd_givers_display_order,
        TAB_NAMES = TAB_NAMES,
    })
    if not ok_inst then mlog("[QT] WARN quest_tracker_map install returned false") end
    pcall(function() if MapMod.init_map_api then MapMod.init_map_api() end end)
    MAP_API = MapMod.API
    MapBridge.init_map_api = MapMod.init_map_api
    MapBridge.clear_injected_markers = MapMod.clear_injected_markers
    MapBridge.get_quest_resource = MapMod.get_quest_resource
    MapBridge.get_quest_cast_charaids = MapMod.get_quest_cast_charaids
    MapBridge.force_marker_refresh = MapMod.force_marker_refresh
    MapBridge.run_autopin_if_enabled = MapMod.run_autopin_if_enabled
    MapBridge.pin_quest = MapMod.pin_quest
    MapBridge.unpin_quest = MapMod.unpin_quest
    MapBridge.unpin_candidate = MapMod.unpin_candidate
    MapBridge.restore_candidate = MapMod.restore_candidate
    MapBridge.restore_all_candidates = MapMod.restore_all_candidates
else
    mlog("[QT] FATAL quest_tracker_map require failed: " .. tostring(MapMod))
end

local run_autolock = function() end
do
    local ok_al, AutoLock = pcall(require, "quest_tracker_autolock")
    if ok_al and AutoLock and AutoLock.install then
        local al_ctx = {
            mod = mod, mlog = mlog, QD = QD,
            LOCKED_QUESTS = LOCKED_QUESTS, VOIDED_QUESTS = VOIDED_QUESTS,
            BUNDLED_LOCKOUTS = BUNDLED_LOCKOUTS, MANUAL_GIVER_OVERRIDES = MANUAL_GIVER_OVERRIDES,
            mark_prefs_dirty = ctx.mark_prefs_dirty,
            qd_locked_if = function(qid)
                if not QD or not QD.get_locked_if_completed then return nil end
                local ok, v = pcall(QD.get_locked_if_completed, qid)
                return ok and type(v) == "table" and v or nil
            end,
            qd_givers_display_order = ctx.qd_givers_display_order,
            qd_givers = ctx.qd_givers,
            get_character_world_pos = ctx.get_character_world_pos,
        }
        AutoLock.install(al_ctx)
        run_autolock = al_ctx.run_autolock or run_autolock
        mlog("[QT] quest_tracker_autolock OK")
    else
        mlog("[QT] WARN quest_tracker_autolock require failed: " .. tostring(AutoLock))
    end
end

local StepsBridge = {}
do
    local ok_st, Steps = pcall(require, "quest_tracker_steps")
    if ok_st and Steps and Steps.reset then Steps.reset() end
    mod._steps_module_ok = false
    if ok_st and Steps and Steps.install then
        local st_ctx = {
            mod = mod, mlog = mlog, QD = QD,
            safe_get_field = ctx.safe_get_field, safe_call = ctx.safe_call,
            iter_list = ctx.iter_list, get_quest_resource = MapBridge.get_quest_resource,
            to_int = ctx.to_int,
            _guid_to_en_text = ctx._guid_to_en_text,
            _text_from_hex32 = ctx._text_from_hex32,
            _read_text_field = ctx._read_text_field,
            _name_for_qid = ctx._name_for_qid,
            resolve_meta = ctx.resolve_meta,
        }
        Steps.install(st_ctx)
        StepsBridge._resolve_ongoing_step = st_ctx._resolve_ongoing_step
        StepsBridge._quest_progress_done_count = st_ctx._quest_progress_done_count
        mod._quest_progress_done_count = st_ctx._quest_progress_done_count
        StepsBridge._is_flavor_text = st_ctx._is_flavor_text
        StepsBridge._get_live_quest_step = st_ctx._get_live_quest_step
        StepsBridge._text_blobs_for_step_match = st_ctx._text_blobs_for_step_match
        StepsBridge._quest_log_info_fingerprint = st_ctx._quest_log_info_fingerprint
        StepsBridge._text_from_dest = st_ctx._text_from_dest
        mod._steps_module_ok = true
        mlog_boot("[QT] quest_tracker_steps OK")
    else
        mlog("[QT] FATAL quest_tracker_steps require failed: " .. tostring(Steps))
        StepsBridge._resolve_ongoing_step = function() return nil, nil, false, false end
        StepsBridge._is_flavor_text = function() return false end
    end
end

local _qt_plugin_out = require("quest_tracker_plugins").install({
    mod = mod, mlog = mlog, mlog_boot = mlog_boot, QD = QD, StepsBridge = StepsBridge, Map = Map,
    ALL_IDS = ALL_IDS, dump_quest_id_enum = ctx.dump_quest_id_enum,
    TAB_NAMES = TAB_NAMES, BUNDLED_LOCKOUTS = BUNDLED_LOCKOUTS,
    QUEST_START_DAYS = QUEST_START_DAYS, QUEST_START_HOURS = QUEST_START_HOURS,
    LOCKED_QUESTS = LOCKED_QUESTS, VOIDED_QUESTS = VOIDED_QUESTS, MAP_API = MAP_API,
    gather = ctx.gather, rebuild = ctx.rebuild, matches_filter = ctx.matches_filter,
    resolve_meta = ctx.resolve_meta, init_map_api = MapBridge.init_map_api, run_autolock = run_autolock,
    save_prefs = ctx.save_prefs, qd_trigger = ctx.qd_trigger, qd_prereqs = ctx.qd_prereqs,
    qd_timing_note = ctx.qd_timing_note, qd_available_after = ctx.qd_available_after,
    qd_time_limit = ctx.qd_time_limit, qd_note = ctx.qd_note, qd_during_quest = ctx.qd_during_quest,
    qd_schedule = ctx.qd_schedule, is_must_before_feast = ctx.is_must_before_feast,
    get_primary_secondary_cids = ctx.get_primary_secondary_cids, _get_quest_start_pos = ctx._get_quest_start_pos,
    get_all_giver_cids = ctx.get_all_giver_cids, _build_npc_rows_for_cache = ctx._build_npc_rows_for_cache,
    friendly_chara_name = ctx.friendly_chara_name, _resolve_cid_name = ctx._resolve_cid_name,
    _hours_until_window_start = ctx._hours_until_window_start, _get_game_clock_integers = ctx._get_game_clock_integers,
    _get_game_hour_sched = ctx._get_game_hour_sched, _format_game_time_line = ctx._format_game_time_line,
    _flush_pos_cache = ctx._flush_pos_cache, td = ctx.td, call_method = ctx.call_method,
    safe_call = ctx.safe_call, safe_get_field = ctx.safe_get_field, iter_list = ctx.iter_list, iter_array = ctx.iter_array,
    to_int = ctx.to_int, _guid_to_en_text = ctx._guid_to_en_text, init_english_lookup = ctx.init_english_lookup,
    _text_from_hex32 = ctx._text_from_hex32, get_quest_resource = MapBridge.get_quest_resource,
    QT_TIME_INTERVAL = QT_TIME_INTERVAL, QT_STATE_PROBE_INTERVAL = QT_STATE_PROBE_INTERVAL,
    QT_NPC_SCAN_INTERVAL = QT_NPC_SCAN_INTERVAL, QT_COMPLETION_SWEEP = QT_COMPLETION_SWEEP,
})

require("quest_tracker_window").install({
    mod = mod, MOD_NAME = MOD_NAME, MOD_VERSION = MOD_VERSION, _QT_FRAME_GEN = _QT_FRAME_GEN,
    TAB_NAMES = TAB_NAMES, SORT_NAMES = SORT_NAMES, MAP_API = MAP_API, Map = Map,
    VOIDED_QUESTS = VOIDED_QUESTS, LOCKED_QUESTS = LOCKED_QUESTS,
    MANUAL_POS_OVERRIDES = MANUAL_POS_OVERRIDES, BUNDLED_POS_OVERRIDES = BUNDLED_POS_OVERRIDES,
    COL_NPC_ORANGE = COL_NPC_ORANGE,
    DEFAULT_QUEST_WIN_Y = DEFAULT_QUEST_WIN_Y,
    DEFAULT_QUEST_WIN_W = DEFAULT_QUEST_WIN_W, DEFAULT_QUEST_WIN_H = DEFAULT_QUEST_WIN_H,
    DEFAULT_QUEST_WIN_MARGIN_R = DEFAULT_QUEST_WIN_MARGIN_R,
    _check_game_ready = _check_game_ready,
    MIN_SAVE_WIN_W = MIN_SAVE_WIN_W, MIN_SAVE_WIN_H = MIN_SAVE_WIN_H,
    mlog = mlog, mlog_boot = mlog_boot, save_prefs = ctx.save_prefs, mark_prefs_dirty = ctx.mark_prefs_dirty,
    rebuild = ctx.rebuild, pin_all_in_current_filtered_tab = ctx.pin_all_in_current_filtered_tab,
    clear_injected_markers = MapBridge.clear_injected_markers, pin_quest = MapBridge.pin_quest, unpin_quest = MapBridge.unpin_quest,
    get_player_universal_pos = ctx.get_player_universal_pos, _teleport_player_to = _teleport_player_to,
    _draw_npc_rows_cached = ctx._draw_npc_rows_cached, _name_for_qid = ctx._name_for_qid,
    milestone_label = ctx.milestone_label, _format_hour_12 = ctx._format_hour_12,
    _start_fast_forward = ctx._start_fast_forward, _set_time_scale = ctx._set_time_scale,
    _tick_fast_forward = ctx._tick_fast_forward, TimeMod = TimeMod,
    _apply_saved_window_once = ctx._apply_saved_window_once,
    _clear_saved_window_position = ctx._clear_saved_window_position,
    _reset_window_layout = ctx._reset_window_layout,
    _refresh_display_cache = ctx._refresh_display_cache,
    _display_size = ctx._display_size,
    _sync_margin_from_viewport = ctx._sync_margin_from_viewport,
    _apply_layout_coords_to_mod = ctx._apply_layout_coords_to_mod,
    _qt_check_boot_layout_settled = ctx._qt_check_boot_layout_settled,
    _imgui_vec2 = ctx._imgui_vec2,
    safe_get_field = ctx.safe_get_field, to_int = ctx.to_int, is_bundled_pos = is_bundled_pos,
    _qt_force_refresh = _qt_plugin_out._qt_force_refresh, _qt_run_logic_tick = _qt_plugin_out._qt_run_logic_tick,
    qt_background_log_tick = _qt_plugin_out.qt_background_log_tick,
})

mod._logic_force = false
mod._last_state_probe = 0

re.on_config_save(function()
    if type(mod) ~= "table" or mod._qt_shutdown or not mod._game_ready then return end
    pcall(ctx.save_prefs)
end)

re.on_script_reset(function()
    if type(mod) ~= "table" then return end
    _qt_enter_shutdown()
end)

mlog_boot(string.format(
    "[QT] startup: state=%ds npc=%ds; Verbose=%s; Deep Sniff=%s",
    QT_STATE_PROBE_INTERVAL, QT_NPC_SCAN_INTERVAL,
    mod.debug_logging and "ON" or "OFF",
    mod.deep_sniff == true and "ON" or "OFF"))
if not mod._steps_module_ok or not mod._cache_module_ok then
    mlog_boot("[QT] *** MOD INCOMPLETE — reinstall via Fluffy ***")
end
