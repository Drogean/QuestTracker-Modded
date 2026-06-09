-- quest_tracker_time.lua — day/night time scale tools (require from quest_tracker.lua)

local TIME_MOD_VER = "1.1.1-amend"
local NIGHT_SCALE = 4.0
local M = package.loaded["quest_tracker_time"]
if M and M._time_mod_ver == TIME_MOD_VER then return M end
M = { _time_mod_ver = TIME_MOD_VER }

local mod, mlog, mlog_boot, _QT_FRAME_GEN
local _get_game_clock_integers, _set_time_scale, _get_time_scale, _set_game_clock_integers
local _tick_fast_forward

local _idle_restored = true
local _last_log_key = nil
local _pause_logged = false
local _pause_frozen = nil
local _watchdog_last = 0
local _late_frame_hooked = false

local function _mlog_time(msg)
    if mlog_boot then mlog_boot(msg)
    elseif mlog then mlog(msg) end
end

local function _scale_matches(want, live)
    if live == nil then return false end
    if want < 0.01 then return live < 0.02 end
    return math.abs(live - want) <= 0.01
end

local function _controls_active()
    if not mod then return false end
    if mod.time_pause then return true end
    if mod._qt_doze then return true end
    if mod.time_longer_days then return true end
    if mod.time_faster_nights then return true end
    return false
end

local function _get_tm()
    return sdk.get_managed_singleton("app.TimeManager")
end

local function _tm_period_flag(tm, names)
    if not tm then return false end
    for _, n in ipairs(names) do
        local v = nil
        pcall(function() v = tm:call(n) end)
        if v == true then return true end
        pcall(function() v = tm:call(n .. "()") end)
        if v == true then return true end
    end
    return false
end

local function _game_period(tm)
    tm = tm or _get_tm()
    if tm then
        if _tm_period_flag(tm, { "isNight", "IsNight" }) then return "night" end
        if _tm_period_flag(tm, { "isDawn", "IsDawn" }) then return "dawn" end
        if _tm_period_flag(tm, { "isNoon", "IsNoon" }) then return "noon" end
        if _tm_period_flag(tm, { "isDusk", "IsDusk" }) then return "dusk" end
    end
    local _, h = _get_game_clock_integers()
    if h == nil then return nil end
    if h >= 20 or h < 4 then
        if mod and not mod._qt_period_fallback_logged then
            mod._qt_period_fallback_logged = true
            _mlog_time(string.format("[QT][time] period fallback h=%d → night", h))
        end
        return "night"
    end
    if mod and not mod._qt_period_fallback_logged then
        mod._qt_period_fallback_logged = true
        _mlog_time(string.format("[QT][time] period fallback h=%d → day", h))
    end
    return "noon"
end

local function _is_game_night(tm)
    return _game_period(tm) == "night"
end

local function _resolve_scale()
    if mod.time_pause then return 0.0001, "paused" end
    if mod._qt_doze then
        local want = (mod._qt_doze.phase == "slow") and 30.0 or 120.0
        return want, "doze"
    end
    local tm = _get_tm()
    local _, h = _get_game_clock_integers()
    if h == nil and not tm then return nil, nil end
    if _is_game_night(tm) and mod.time_faster_nights then return NIGHT_SCALE, "night" end
    if not _is_game_night(tm) and mod.time_longer_days then return 0.5, "day" end
    return 1.0, "normal"
end

local function _capture_pause_freeze()
    local d, h, mi = _get_game_clock_integers()
    if h == nil or mi == nil then return end
    _pause_frozen = { d = d or 0, h = h, mi = mi }
end

local function _enforce_pause_freeze()
    if not _pause_frozen or type(_set_game_clock_integers) ~= "function" then return end
    local d, h, mi = _get_game_clock_integers()
    if h == nil or mi == nil then return end
    local fd, fh, fmi = _pause_frozen.d, _pause_frozen.h, _pause_frozen.mi
    if d > fd or (d == fd and (h > fh or (h == fh and mi > fmi))) then
        pcall(_set_game_clock_integers, fd, fh, fmi)
        if not mod._qt_time_freeze_logged then
            mod._qt_time_freeze_logged = true
            _mlog_time(string.format("[QT][time] pause freeze clock h=%d m=%d", fh, fmi))
        end
    end
end

local function _apply_scale(want)
    if type(_set_time_scale) ~= "function" then return nil end
    local ok, live = _set_time_scale(want)
    if not ok then mod._qt_time_scale_unreliable = true end
    return live
end

local function _log_scale_state(scale, kind)
    local _, h, mi = _get_game_clock_integers()
    if h == nil then return end
    mi = mi or 0
    if kind == "paused" then
        if not _pause_logged then
            _pause_logged = true
            _mlog_time(string.format("[QT][time] paused h=%d m=%d", h, mi))
        end
        return
    end
    _pause_logged = false
    local period = _game_period(_get_tm())
    local key = string.format("%.4f:%s:%s", scale, period or "?", kind)
    if key == _last_log_key then return end
    _last_log_key = key
    if kind == "doze" then return end
    if kind == "night" then
        _mlog_time(string.format("[QT][time] scale=%.1f game_night h=%d period=%s", scale, h, period or "?"))
    elseif kind == "day" then
        _mlog_time(string.format("[QT][time] phase=day scale=%.1f h=%d period=%s", scale, h, period or "?"))
    elseif kind == "normal" and (mod.time_longer_days or mod.time_faster_nights) then
        _mlog_time(string.format("[QT][time] phase=%s scale=%.1f h=%d period=%s", period or "day", scale, h, period or "?"))
    end
end

local function _maybe_watchdog(want)
    local now = os.clock()
    if now - _watchdog_last < 30.0 then return end
    _watchdog_last = now
    local live = type(_get_time_scale) == "function" and _get_time_scale() or nil
    local _, h, mi = _get_game_clock_integers()
    local live_s = live and string.format("%.4f", live) or "nil"
    _mlog_time(string.format("[QT][time] watchdog want=%.4f live=%s h=%s m=%s",
        want or 0, live_s, tostring(h), tostring(mi)))
end

function M.install(ctx)
    if type(ctx) ~= "table" then return false end
    mod = ctx.mod
    mlog = ctx.mlog
    mlog_boot = ctx.mlog_boot
    _QT_FRAME_GEN = ctx._QT_FRAME_GEN
    _get_game_clock_integers = ctx._get_game_clock_integers
    _set_time_scale = ctx._set_time_scale
    _get_time_scale = ctx._get_time_scale
    _set_game_clock_integers = ctx._set_game_clock_integers
    _tick_fast_forward = ctx._tick_fast_forward
    if not _late_frame_hooked then
        _late_frame_hooked = true
        re.on_frame(function()
            if _QT_FRAME_GEN and _G._qt_frame_gen ~= _QT_FRAME_GEN then return end
            M.late_tick()
        end)
    end
    _mlog_time("[QT][time] module ok")
    return true
end

function M.on_toggle()
    if not mod then return end
    _idle_restored = false
    _last_log_key = nil
    _pause_logged = false
    mod._qt_time_freeze_logged = nil
    mod._qt_time_scale_unreliable = nil
    if mod.time_pause then
        _capture_pause_freeze()
    else
        _pause_frozen = nil
    end
    _mlog_time(string.format("[QT][time] longer_days=%s faster_nights=%s pause=%s",
        mod.time_longer_days and "ON" or "OFF",
        mod.time_faster_nights and "ON" or "OFF",
        mod.time_pause and "ON" or "OFF"))
end

function M.get_status_line()
    if not mod or not _controls_active() then return nil end
    local _, h, mi = _get_game_clock_integers()
    h = h or 0
    mi = mi or 0
    if mod.time_pause then
        return string.format("Time: PAUSED (h=%d m=%d)", h, mi), 0xFF66FF66
    end
    if mod._qt_doze then return "Time: fast-forward", 0xFF66FF66 end
    local scale, kind = _resolve_scale()
    if not scale then return nil end
    local period = _game_period(_get_tm())
    if kind == "night" then
        return string.format("Time: %.0fx night (game dark)", scale), 0xFF66FF66
    end
    if kind == "day" then
        if period == "dusk" then
            return string.format("Time: %.1fx day (dusk — dark at 8pm)", scale), 0xFF66FF66
        end
        return string.format("Time: %.1fx day (before dark)", scale), 0xFF66FF66
    end
    if mod.time_longer_days or mod.time_faster_nights then
        if _is_game_night(_get_tm()) then
            return string.format("Time: %.1fx (game dark — enable faster nights)", scale), 0xFF66FF66
        end
        if period == "dusk" then
            return string.format("Time: %.1fx (dusk — dark at 8pm)", scale), 0xFF66FF66
        end
        return string.format("Time: %.1fx (before dark)", scale), 0xFF66FF66
    end
    return nil
end

function M.tick()
    if not mod or mod._qt_shutdown then return end
    if type(_set_time_scale) ~= "function" then return end

    if mod.time_pause and not _pause_frozen then
        _capture_pause_freeze()
    elseif not mod.time_pause then
        _pause_frozen = nil
        mod._qt_time_freeze_logged = nil
    end

    if mod._qt_doze and not mod.time_pause and type(_tick_fast_forward) == "function" then
        pcall(_tick_fast_forward)
    end

    if not _controls_active() then
        if not _idle_restored then
            _idle_restored = true
            _last_log_key = nil
            _pause_logged = false
            _pause_frozen = nil
            mod._qt_time_scale_unreliable = nil
            pcall(_set_time_scale, 1.0)
        end
        return
    end
    _idle_restored = false

    local scale, kind = _resolve_scale()
    if scale == nil then return end
    _apply_scale(scale)
    _log_scale_state(scale, kind)
    if mod.time_pause then
        local live = type(_get_time_scale) == "function" and _get_time_scale() or nil
        if mod._qt_time_scale_unreliable or not _scale_matches(scale, live) then
            _enforce_pause_freeze()
        end
    end
end

function M.late_tick()
    if not mod or mod._qt_shutdown then return end
    if type(_set_time_scale) ~= "function" then return end

    if not _controls_active() then return end

    local want, kind = _resolve_scale()
    if want == nil then return end

    local live = type(_get_time_scale) == "function" and _get_time_scale() or nil
    if not _scale_matches(want, live) then
        _apply_scale(want)
        live = type(_get_time_scale) == "function" and _get_time_scale() or nil
    end

    if mod.time_pause then
        if mod._qt_time_scale_unreliable or not _scale_matches(want, live) then
            _enforce_pause_freeze()
        end
    end

    _maybe_watchdog(want)
end

return M
