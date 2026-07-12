-- Overlay visibility — require only from quest_tracker.lua (subfolder = not auto-run).
local M = package.loaded["quest_tracker/quest_tracker_overlay"]
if M then return M end

local Overlay = {}
local _HYST_FRAMES = 5

function Overlay.install(ctx)
    local mlog_boot = (ctx and (ctx.mlog_boot or ctx.mlog)) or function() end
    if not ctx or not ctx.mod then
        mlog_boot("[QT] FATAL overlay install: ctx.mod nil (orchestrator order bug)")
        return false
    end
    local mod = ctx.mod

    local function _is_load_screen()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if not gm then return false end
        local load_gui = false
        pcall(function() load_gui = gm:get_IsLoadGui() == true end)
        return load_gui
    end

    local function _is_paused_gui()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if not gm then return false end
        local paused = false
        pcall(function()
            if gm.isPausedGUI then paused = gm:isPausedGUI() == true
            elseif gm.call then paused = gm:call("isPausedGUI") == true end
        end)
        return paused
    end

    local function _want_draw()
        if not mod._game_ready or mod.show_window ~= true then return false end
        if _is_load_screen() then return false end
        if mod._qt_map_ui_active == true and mod.show_overlay_on_map == false then return false end
        return true
    end

    function mod._qt_overlay_tick()
        local want = _want_draw()
        if want == mod._qt_ov_hyst_want then
            mod._qt_ov_hyst_n = (mod._qt_ov_hyst_n or 0) + 1
        else
            mod._qt_ov_hyst_want = want
            mod._qt_ov_hyst_n = 1
        end
        if (mod._qt_ov_hyst_n or 0) >= _HYST_FRAMES then
            mod._qt_ov_draw_state = want
        end
        mod._qt_overlay_allow = (mod._qt_ov_draw_state == true)
        mod._qt_overlay_want = want
    end

    function mod._qt_overlay_should_draw()
        return mod._qt_overlay_allow == true
    end

    function mod._qt_overlay_log_sig()
        local load_gui = _is_load_screen() and 1 or 0
        local paused = _is_paused_gui() and 1 or 0
        local map_active = (mod._qt_map_ui_active == true) and 1 or 0
        local want = mod._qt_overlay_want and 1 or 0
        local allow = mod._qt_overlay_allow and 1 or 0
        local sig = string.format("%d:%d:%d:%d:%d", map_active, load_gui, paused, want, allow)
        if mod._qt_overlay_draw_sig ~= sig then
            mod._qt_overlay_draw_sig = sig
            if allow == 1 then
                if map_active == 1 then
                    mlog_boot("[QT] overlay draw MAP_ALLOW map=1 load=" .. tostring(load_gui) .. " paused=" .. tostring(paused))
                else
                    mlog_boot(string.format("[QT] overlay draw ALLOWED map=%d load=%d paused=%d",
                        map_active, load_gui, paused))
                end
            else
                mlog_boot(string.format("[QT] overlay draw SKIPPED map=%d load=%d paused=%d want=%d hyst=%d",
                    map_active, load_gui, paused, want, mod._qt_ov_hyst_n or 0))
            end
        end
    end

    function mod._qt_overlay_before_window()
        local need_focus = (mod._qt_map_ui_active == true) or _is_paused_gui()
        if need_focus and imgui.set_next_window_focus then
            pcall(imgui.set_next_window_focus)
        end
    end

    mlog_boot("[QT] overlay module: load_screen block only; pause/menu focus; hyst=" .. tostring(_HYST_FRAMES))
    return true
end

package.loaded["quest_tracker/quest_tracker_overlay"] = Overlay
return Overlay
