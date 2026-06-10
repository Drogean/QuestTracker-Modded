-- quest_tracker_plugins.lua — load cache/diag/sniff/journal (own file = own 200-local budget)
local M = package.loaded["quest_tracker_plugins"]
if M then return M end
M = {}

function M.install(ctx)
    local mod = ctx.mod
    local mlog = ctx.mlog
    local mlog_boot = ctx.mlog_boot
    local QD = ctx.QD
    local StepsBridge = ctx.StepsBridge
    local Map = ctx.Map
    local ALL_IDS = ctx.ALL_IDS
    local dump_quest_id_enum = ctx.dump_quest_id_enum

    local noop = function() end
    local out = {
        _qt_force_refresh = noop,
        _qt_run_logic_tick = noop,
        _qt_refresh_row_caches = noop,
        qt_background_log_tick = noop,
    }

    local function ensure_all_ids()
        if ALL_IDS == nil then ALL_IDS = dump_quest_id_enum() end
        return ALL_IDS
    end

    local resolve_step = (StepsBridge and StepsBridge._resolve_ongoing_step)
        or function() return nil, nil, false, false end
    local is_flavor = (StepsBridge and StepsBridge._is_flavor_text) or function() return false end
    local fp_step = (StepsBridge and StepsBridge._quest_log_info_fingerprint) or function() return "" end

    -- Single ctx table — shared by cache/diag/sniff/journal (S4)
    local plugin_ctx = {
        mod = mod, mlog = mlog, mlog_boot = mlog_boot, QD = QD,
        TAB_NAMES = ctx.TAB_NAMES,
        BUNDLED_LOCKOUTS = ctx.BUNDLED_LOCKOUTS,
        QUEST_START_DAYS = ctx.QUEST_START_DAYS,
        QUEST_START_HOURS = ctx.QUEST_START_HOURS,
        LOCKED_QUESTS = ctx.LOCKED_QUESTS,
        VOIDED_QUESTS = ctx.VOIDED_QUESTS,
        MAP_API = ctx.MAP_API,
        gather = ctx.gather, rebuild = ctx.rebuild,
        matches_filter = ctx.matches_filter,
        resolve_meta = ctx.resolve_meta,
        init_map_api = ctx.init_map_api,
        run_autolock = ctx.run_autolock,
        save_prefs = ctx.save_prefs,
        qd_trigger = ctx.qd_trigger,
        qd_prereqs = ctx.qd_prereqs,
        qd_timing_note = ctx.qd_timing_note,
        qd_available_after = ctx.qd_available_after,
        qd_time_limit = ctx.qd_time_limit,
        qd_note = ctx.qd_note,
        qd_during_quest = ctx.qd_during_quest,
        qd_schedule = ctx.qd_schedule,
        is_must_before_feast = ctx.is_must_before_feast,
        _resolve_ongoing_step = resolve_step,
        _is_flavor_text = is_flavor,
        _quest_log_info_fingerprint = fp_step,
        get_primary_secondary_cids = ctx.get_primary_secondary_cids,
        _get_quest_start_pos = ctx._get_quest_start_pos,
        get_all_giver_cids = ctx.get_all_giver_cids,
        _build_npc_rows_for_cache = ctx._build_npc_rows_for_cache,
        friendly_chara_name = ctx.friendly_chara_name,
        _resolve_cid_name = ctx._resolve_cid_name,
        _hours_until_window_start = ctx._hours_until_window_start,
        _get_game_clock_integers = ctx._get_game_clock_integers,
        _get_game_hour_sched = ctx._get_game_hour_sched,
        _format_game_time_line = ctx._format_game_time_line,
        _flush_pos_cache = ctx._flush_pos_cache,
        ensure_all_ids = ensure_all_ids,
        td = ctx.td, call_method = ctx.call_method,
        safe_call = ctx.safe_call, safe_get_field = ctx.safe_get_field,
        iter_list = ctx.iter_list, iter_array = ctx.iter_array, to_int = ctx.to_int,
        _guid_to_en_text = ctx._guid_to_en_text,
        init_english_lookup = ctx.init_english_lookup,
        _text_from_hex32 = ctx._text_from_hex32,
        get_quest_resource = ctx.get_quest_resource,
        QT_TIME_INTERVAL = ctx.QT_TIME_INTERVAL,
        QT_STATE_PROBE_INTERVAL = ctx.QT_STATE_PROBE_INTERVAL,
        QT_NPC_SCAN_INTERVAL = ctx.QT_NPC_SCAN_INTERVAL,
        QT_COMPLETION_SWEEP = ctx.QT_COMPLETION_SWEEP,
        auto_pin_fn_ongoing = Map and Map.pin_all_ongoing or nil,
        auto_pin_fn_available = Map and Map.pin_all_available or nil,
        run_autopin_if_enabled = Map and Map.run_autopin_if_enabled or nil,
        on_journal_qid_changed = Map and Map.on_journal_qid_changed or nil,
        on_journal_progress_bump = Map and Map.on_journal_progress_bump or nil,
        _get_live_quest_step = StepsBridge and StepsBridge._get_live_quest_step or nil,
        _text_blobs_for_step_match = StepsBridge and StepsBridge._text_blobs_for_step_match or nil,
        _text_from_dest = StepsBridge and StepsBridge._text_from_dest or nil,
    }

    local ok_ca, Cache = pcall(require, "quest_tracker_cache")
    if ok_ca and Cache and Cache.install then
        Cache.install(plugin_ctx)
        mod._refresh_one_row = plugin_ctx._refresh_one_row
        mod._qt_schedule_cache_refresh = plugin_ctx._qt_schedule_cache_refresh
        out._qt_force_refresh = plugin_ctx._qt_force_refresh
        out._qt_run_logic_tick = plugin_ctx._qt_run_logic_tick
        out._qt_refresh_row_caches = plugin_ctx._qt_refresh_row_caches
        out.qt_background_log_tick = plugin_ctx.qt_background_log_tick
        mod._cache_module_ok = true
        if type(plugin_ctx._qt_run_logic_tick) ~= "function" then
            mlog_boot("[QT] FATAL cache install: _qt_run_logic_tick nil — quest rows will not refresh")
        end
        mlog_boot("[QT] quest_tracker_cache OK")

        local ok_dg, Diag = pcall(require, "quest_tracker_diag")
        if ok_dg and Diag and Diag.install and mod._steps_module_ok and StepsBridge then
            Diag.install(plugin_ctx)
            mod._log_quest_expand = plugin_ctx.log_quest_expand
            mlog("[QT] quest_tracker_diag OK")
        end

        local ok_sf, Sniff = pcall(require, "quest_tracker_sniff")
        if ok_sf and Sniff and Sniff.install and StepsBridge then
            Sniff.install(plugin_ctx)
            mod._sniff_on_frame = plugin_ctx.sniff_on_frame
            mod._sniff_dump_qid = plugin_ctx.sniff_dump_qid
            mod._sniff_install = plugin_ctx.sniff_install_hooks
            mod._journal_poll_on_frame = plugin_ctx.journal_poll_on_frame
            mod._journal_install_hooks = plugin_ctx.install_journal_hooks
            mlog_boot("[QT] quest_tracker_sniff OK (journal hooks install when you open quest menu)")
            if mod.deep_sniff == true then
                if mod._sniff_install then pcall(mod._sniff_install) end
                if mod._journal_install_hooks then pcall(mod._journal_install_hooks) end
                if Map and Map.resniff_map_ui then pcall(Map.resniff_map_ui) end
                mlog_boot("[QT][sniff] boot install deep_sniff=ON from prefs")
            end
        end

        local ok_jr, Journal = pcall(require, "quest_tracker_journal")
        if ok_jr and Journal and Journal.install then
            Journal.install(plugin_ctx)
            mlog("[QT] quest_tracker_journal OK")
        else
            mlog("[QT] quest_tracker_journal FAILED: " .. tostring(Journal))
        end
    else
        mod._cache_module_ok = false
        mlog("[QT] FATAL quest_tracker_cache require failed: " .. tostring(Cache))
        mod._refresh_one_row = noop
        mod._qt_schedule_cache_refresh = noop
    end

    return out
end

package.loaded["quest_tracker_plugins"] = M
return M
