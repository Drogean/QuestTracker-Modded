-- qt_timesniffer.lua — detects in-game time jumps from any source:
--   oxcart doze-off, inn sleeping, our own quest-tracker fast-forward, etc.
-- Logs every jump to quest_tracker_log.txt so you can see cumulative skipped time.
-- Loaded automatically by REFramework alongside quest_tracker.lua.

local LOG_PATH   = "quest_tracker_log.txt"
local LOG_MAX    = 200000

local function ts_log(msg)
    pcall(function()
        local f = io.open(LOG_PATH, "rb")
        if f then
            local sz = f:seek("end") or 0; f:close()
            if sz > LOG_MAX then
                local out = io.open(LOG_PATH, "wb")
                if out then
                    out:write("-- quest_tracker_log truncated (size cap) " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
                    out:close()
                end
            end
        end
        local out = io.open(LOG_PATH, "ab")
        if out then
            out:write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] [timesniffer] " .. msg .. "\n")
            out:close()
        end
    end)
    print("[timesniffer] " .. msg)
end

-- Read InGameHour from app.TimeManager, with two API-style fallbacks.
local function get_game_hour()
    local tm = sdk.get_managed_singleton("app.TimeManager")
    if not tm then return nil end

    local h
    local ok, v = pcall(function() return tm:call("get_InGameHour") end)
    if ok and type(v) == "number" then h = v end
    if h == nil then
        ok, v = pcall(function() return tm:get_field("InGameHour") end)
        if ok and type(v) == "number" then h = v end
    end
    return h
end

local _prev_h          = nil   -- last seen integer hour
local _total_skipped   = 0     -- session accumulator (hours)
local _session_jumps   = 0     -- number of detected jumps

-- Minimum jump size to count as a "skip" rather than normal hourly progression.
-- Normal time passes 1 hour at a time. Oxcart/inn skip 4-12 hours.
-- Our own 120x skip can do multiple hours per frame too, so we count those here.
local MIN_JUMP_HOURS = 2

local SNIFF_INTERVAL = 5.0
local _last_sniff = 0

re.on_frame(function()
    local now = os.clock()
    if (now - _last_sniff) < SNIFF_INTERVAL then return end
    _last_sniff = now
    local h = get_game_hour()
    if not h then return end
    local h_int = math.floor(h)
    if _prev_h ~= nil and h_int ~= _prev_h then
        local diff = h_int - _prev_h
        if diff < 0 then diff = diff + 24 end
        if diff >= MIN_JUMP_HOURS then
            _total_skipped = _total_skipped + diff
            _session_jumps = _session_jumps + 1
            ts_log(string.format(
                "TIME JUMP #%d: %02d:00 → %02d:00  (+%d h)  |  session total: %d h",
                _session_jumps, _prev_h, h_int, diff, _total_skipped))
        end
    end
    _prev_h = h_int
end)

ts_log(string.format("qt_timesniffer loaded  (poll=%ds, min_jump=%dh)", SNIFF_INTERVAL, MIN_JUMP_HOURS))
