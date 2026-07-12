-- quest_tracker_window_child.lua — ImGui child-window begin/end stack helpers
local M = package.loaded["quest_tracker_window_child"]
if M then return M end
M = {}

function M.install(ctx)
    local mod = ctx.mod
    local mlog_boot = ctx.mlog_boot
    local _imgui_vec2 = ctx._imgui_vec2

    local function _parse_vec2(v, fb_x, fb_y)
        if type(v) == "number" then return v, fb_y end
        if v == nil then return fb_x, fb_y end
        local x, y = fb_x, fb_y
        pcall(function()
            if type(v.x) == "number" then x = v.x end
            if type(v.y) == "number" then y = v.y end
        end)
        return x, y
    end

    local api = {}

    function api.begin()
        mod._qt_quest_child_begun = false
        mod._qt_quest_child_open = false
        if not imgui.begin_child_window then return false end

        local avail_h = nil
        if imgui.get_content_region_avail then
            local ok_a, a = pcall(imgui.get_content_region_avail)
            if ok_a then _, avail_h = _parse_vec2(a, -1, -1) end
        end
        if avail_h and avail_h < 64 then
            if not mod._qt_child_deferred_logged then
                mod._qt_child_deferred_logged = true
                mlog_boot(string.format("[QT] child deferred reason=avail_h=%.0f min=64", avail_h))
            end
            return false
        end

        local ok, open = pcall(function()
            if _imgui_vec2 then
                return imgui.begin_child_window("##qtquestscroll", _imgui_vec2(0, -40), true)
            end
            return imgui.begin_child_window("##qtquestscroll", 0, -40, true)
        end)
        if ok then
            mod._qt_quest_child_begun = true
            if open then
                mod._qt_quest_child_open = true
                mod._qt_child_deferred_logged = nil
                mod._qt_child_begin_fail_logged = nil
                mod._qt_list_child_fail_logged = nil
                return true
            end
            if not mod._qt_child_begin_fail_logged then
                mod._qt_child_begin_fail_logged = true
                mlog_boot("[QT] draw child begin open=false (end_child stack_safe)")
            end
            return false
        end
        if not mod._qt_child_begin_fail_logged then
            mod._qt_child_begin_fail_logged = true
            mlog_boot("[QT] draw child begin FAIL pcall err=" .. tostring(open))
        end
        return false
    end

    function api.end_child()
        if mod._qt_quest_child_begun then
            mod._qt_quest_child_begun = false
            mod._qt_quest_child_open = false
            if imgui.end_child_window then pcall(imgui.end_child_window) end
        end
    end

    function api.ensure_closed()
        if mod._qt_quest_child_begun then api.end_child() end
    end

    mlog_boot("[QT][child] module installed")
    return api
end

package.loaded["quest_tracker_window_child"] = M
return M
