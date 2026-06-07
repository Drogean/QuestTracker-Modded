# Generate slim quest_tracker.lua orchestrator v3.0.83
from pathlib import Path

ROOT = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun")
SRC = ROOT / "quest_tracker.lua.bak"
if not SRC.exists():
    SRC = ROOT / "quest_tracker.lua"
    SRC.write_bytes(ROOT.joinpath("quest_tracker.lua").read_bytes())
    bak = ROOT / "quest_tracker.lua.bak"
    if not bak.exists():
        bak.write_bytes(SRC.read_bytes())

lines = SRC.read_bytes().decode("utf-8", errors="replace").splitlines()

def sl(a, b):
    return "\n".join(lines[a - 1 : b])

ORCH = f'''-- quest_tracker.lua — DD2 quest list UI orchestrator (S2 split v3.0.83)
-- Submodules: quest_tracker_prefs/sdk/gather, quest_tracker_steps(+resolve), plugins, window, map, cache

local MOD_NAME = "Quest Tracker Reduxx"
local MOD_VERSION = "3.0.83"

local DEFAULT_QUEST_WIN_W = 674
local DEFAULT_QUEST_WIN_H = 1195
local DEFAULT_QUEST_WIN_X = 3150
local DEFAULT_QUEST_WIN_Y = 718
local DEFAULT_QUEST_WIN_MARGIN_R = 24
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
    local args, parts = {{...}}, {{}}
    for i = 1, select("#", ...) do parts[i] = tostring(args[i]) end
    local line = "[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. table.concat(parts, " ")
    pcall(function()
        if not _log_ready then
            _log_ready = true
            if _log_needs_wipe() then
                local fw = io.open(LOG_PATH, "wb")
                if fw then
                    fw:write("-- quest_tracker v" .. MOD_VERSION .. " started " .. os.date("%Y-%m-%d %H:%M:%S") .. "\\n")
                    fw:close()
                end
            end
        end
        local f = io.open(LOG_PATH, "ab")
        if f then f:write(line, "\\n"); f:close() end
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

{sl(86, 183)}

local PREFS_PATH = "quest_tracker_prefs.json"
local PREF_KEYS  = {{
    "show_window", "sort_mode", "highlight_recent", "tab", "label_pins", "debug_logging",
    "deep_sniff", "deep_sniff_heavy", "font_size",
    "win_x", "win_y", "win_w", "win_h", "win_alpha",
    "auto_pin_ongoing", "auto_pin_available",
}}

local function is_bundled_giver(qid, cid) return BUNDLED_GIVER_OVERRIDES[qid] == cid end
local function is_bundled_pos(qid, p)
    local b = BUNDLED_POS_OVERRIDES[qid]
    if b == nil or p == nil then return false end
    return b.x == p.x and b.y == p.y and b.z == p.z
end

local TAB_NAMES  = {{ "Available", "Ongoing", "Completed", "All", "Hidden" }}
local SORT_NAMES = {{ "Last Updated", "Recent", "Distance" }}
local FEAST_MILESTONE = 10140
local PONR_NAMES = {{
    [10140] = "Feast of Deception",
    [10160] = "A New Godsway",
    [10170] = "The Guardian Gigantus",
    [10180] = "Legacy",
}}

local ctx = {{
    PREFS_PATH = PREFS_PATH,
    PREF_KEYS = PREF_KEYS,
    DEFAULT_QUEST_WIN_X = DEFAULT_QUEST_WIN_X,
    DEFAULT_QUEST_WIN_Y = DEFAULT_QUEST_WIN_Y,
    DEFAULT_QUEST_WIN_W = DEFAULT_QUEST_WIN_W,
    DEFAULT_QUEST_WIN_H = DEFAULT_QUEST_WIN_H,
    SORT_NAMES = SORT_NAMES,
    MANUAL_GIVER_OVERRIDES = MANUAL_GIVER_OVERRIDES,
    MANUAL_POS_OVERRIDES = MANUAL_POS_OVERRIDES,
    ELIMINATED_OVERRIDES = ELIMINATED_OVERRIDES,
    VOIDED_QUESTS = VOIDED_QUESTS,
    LOCKED_QUESTS = LOCKED_QUESTS,
    QUEST_START_DAYS = QUEST_START_DAYS,
    QUEST_START_HOURS = QUEST_START_HOURS,
    LEARNED_CHARA_NAMES = LEARNED_CHARA_NAMES,
    is_bundled_giver = is_bundled_giver,
    is_bundled_pos = is_bundled_pos,
    mlog_boot = mlog_boot,
}}

local Prefs = require("quest_tracker_prefs")
Prefs.install(ctx)
ctx.load_prefs_early()

mod = {{
    show_window      = true,
    quests           = {{}},
    name_cache       = {{}},
    name_en_cache    = {{}},
    summary_cache    = {{}},
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
    font_size        = 28,
    win_alpha        = 0.4,
    win_x            = DEFAULT_QUEST_WIN_X,
    win_y            = DEFAULT_QUEST_WIN_Y,
    win_w            = DEFAULT_QUEST_WIN_W,
    win_h            = DEFAULT_QUEST_WIN_H,
    state_counts     = {{0, 0, 0, 0, 0}},
    progressing_ids  = {{}},
    acceptable_ids   = {{}},
    completed_ids    = {{}},
    upcoming_ids     = {{}},
    recency_order    = {{}},
    newest_completed = nil,
    _prefs_dirty     = false,
    _live_in_game_day = 0,
    _row_cache = {{}},
    _row_static = {{}},
    _draw_quest_list = {{}},
    _npc_scan_cache = {{}},
}}

ctx.mod = mod
ctx.mlog = mlog
Prefs.install(ctx)
ctx.apply_prefs_to_mod()

if _QT_FRAME_GEN > 1 then
    mod._step_last_title = {{}}
    mod._steps_module_ok = nil
    mod._cache_module_ok = nil
    mod._row_static = {{}}
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

local MAP_API = {{ ready = false, pinned_data = {{}}, pinned_pos = {{}}, eliminated_pos = {{}}, status = "map module failed", last_msg = "" }}
local MapBridge = {{
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
}}
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

local Map
local _map_ok, MapMod = pcall(require, "quest_tracker_map")
ctx.Map = MapMod
require("quest_tracker_gather").install(ctx)
ALL_IDS = ctx.ALL_IDS

if _map_ok and MapMod and MapMod.install then
    Map = MapMod
    local ok_inst = MapMod.install({{
        mod = mod,
        mlog = mlog,
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
        MANUAL_GIVER_OVERRIDES = MANUAL_GIVER_OVERRIDES,
        ELIMINATED_OVERRIDES = ELIMINATED_OVERRIDES,
        BUNDLED_GIVER_OVERRIDES = BUNDLED_GIVER_OVERRIDES,
        is_bundled_giver = is_bundled_giver,
        qd_givers = ctx.qd_givers,
        qd_givers_display_order = ctx.qd_givers_display_order,
        TAB_NAMES = TAB_NAMES,
    }})
    if not ok_inst then mlog("[QT] WARN quest_tracker_map install returned false") end
    MAP_API = MapMod.API
    MapBridge.init_map_api = MapMod.init_map_api
    MapBridge.clear_injected_markers = MapMod.clear_injected_markers
    MapBridge.get_quest_resource = MapMod.get_quest_resource
    MapBridge.get_quest_cast_charaids = MapMod.get_quest_cast_charaids
    MapBridge.force_marker_refresh = MapMod.force_marker_refresh
    MapBridge.pin_quest = MapMod.pin_quest
    MapBridge.unpin_quest = MapMod.unpin_quest
    MapBridge.unpin_candidate = MapMod.unpin_candidate
    MapBridge.restore_candidate = MapMod.restore_candidate
    MapBridge.restore_all_candidates = MapMod.restore_all_candidates
else
    mlog("[QT] FATAL quest_tracker_map require failed: " .. tostring(MapMod))
end

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

local run_autolock = function() end
do
    local ok_al, AutoLock = pcall(require, "quest_tracker_autolock")
    if ok_al and AutoLock and AutoLock.install then
        AutoLock.install({{
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
        }})
        run_autolock = AutoLock.run_autolock or run_autolock
        mlog("[QT] quest_tracker_autolock OK")
    else
        mlog("[QT] WARN quest_tracker_autolock require failed: " .. tostring(AutoLock))
    end
end

local StepsBridge = {{}}
do
    local ok_st, Steps = pcall(require, "quest_tracker_steps")
    if ok_st and Steps and Steps.reset then Steps.reset() end
    mod._steps_module_ok = false
    if ok_st and Steps and Steps.install then
        local st_ctx = {{
            mod = mod, mlog = mlog, QD = QD,
            safe_get_field = ctx.safe_get_field, safe_call = ctx.safe_call,
            iter_list = ctx.iter_list, get_quest_resource = MapBridge.get_quest_resource,
            to_int = ctx.to_int,
            _guid_to_en_text = ctx._guid_to_en_text,
            _text_from_hex32 = ctx._text_from_hex32,
            _read_text_field = ctx._read_text_field,
            _name_for_qid = ctx._name_for_qid,
            resolve_meta = ctx.resolve_meta,
        }}
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

local _qt_plugin_out = require("quest_tracker_plugins").install({{
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
}})

require("quest_tracker_window").install({{
    mod = mod, MOD_NAME = MOD_NAME, MOD_VERSION = MOD_VERSION, _QT_FRAME_GEN = _QT_FRAME_GEN,
    TAB_NAMES = TAB_NAMES, SORT_NAMES = SORT_NAMES, MAP_API = MAP_API, Map = Map,
    VOIDED_QUESTS = VOIDED_QUESTS, LOCKED_QUESTS = LOCKED_QUESTS,
    MANUAL_POS_OVERRIDES = MANUAL_POS_OVERRIDES, BUNDLED_POS_OVERRIDES = BUNDLED_POS_OVERRIDES,
    COL_NPC_ORANGE = COL_NPC_ORANGE, DEFAULT_QUEST_WIN_W = DEFAULT_QUEST_WIN_W,
    MIN_SAVE_WIN_W = MIN_SAVE_WIN_W, MIN_SAVE_WIN_H = MIN_SAVE_WIN_H,
    mlog = mlog, mlog_boot = mlog_boot, save_prefs = ctx.save_prefs, mark_prefs_dirty = ctx.mark_prefs_dirty,
    rebuild = ctx.rebuild, pin_all_in_current_filtered_tab = ctx.pin_all_in_current_filtered_tab,
    clear_injected_markers = MapBridge.clear_injected_markers, pin_quest = MapBridge.pin_quest, unpin_quest = MapBridge.unpin_quest,
    get_player_universal_pos = ctx.get_player_universal_pos, _teleport_player_to = _teleport_player_to,
    _draw_npc_rows_cached = ctx._draw_npc_rows_cached, _name_for_qid = ctx._name_for_qid,
    milestone_label = ctx.milestone_label, _format_hour_12 = ctx._format_hour_12,
    _start_fast_forward = ctx._start_fast_forward, _set_time_scale = ctx._set_time_scale,
    _tick_fast_forward = ctx._tick_fast_forward, _apply_saved_window_once = ctx._apply_saved_window_once,
    _clear_saved_window_position = ctx._clear_saved_window_position,
    safe_get_field = ctx.safe_get_field, to_int = ctx.to_int, is_bundled_pos = is_bundled_pos,
    _qt_force_refresh = _qt_plugin_out._qt_force_refresh, _qt_run_logic_tick = _qt_plugin_out._qt_run_logic_tick,
    qt_background_log_tick = _qt_plugin_out.qt_background_log_tick,
}})

mod._logic_force = true
mod._last_state_probe = 0
pcall(_qt_plugin_out._qt_run_logic_tick, os.clock())

re.on_frame(function()
    if not mod._qt_doze then return end
    local want = (mod._qt_doze.phase == "slow") and 30.0 or 120.0
    ctx._set_time_scale(want)
end)

mlog_boot(string.format(
    "[QT] startup: state=%ds npc=%ds; Verbose=%s (default ON); Deep Sniff=OFF unless you need it",
    QT_STATE_PROBE_INTERVAL, QT_NPC_SCAN_INTERVAL, mod.debug_logging and "ON" or "OFF"))
if not mod._steps_module_ok or not mod._cache_module_ok then
    mlog_boot("[QT] *** MOD INCOMPLETE — reinstall via Fluffy ***")
end
'''

# Fix double braces from f-string - replace {{ with { and }} with }
ORCH = ORCH.replace("{{", "{").replace("}}", "}")

# Fix mlog_boot broken escape
ORCH = ORCH.replace('fw:write("-- quest_tracker v" .. MOD_VERSION .. " started " .. os.date("%Y-%m-%d %H:%M:%S") .. "\\n")',
                    'fw:write("-- quest_tracker v" .. MOD_VERSION .. " started " .. os.date("%Y-%m-%d %H:%M:%S") .. "\\n")')

out = ROOT / "quest_tracker.lua"
out.write_text(ORCH, encoding="utf-8")
print("orchestrator lines", len(ORCH.splitlines()))
