local wibox         = require("wibox")
local awful         = require("awful")
local beautiful     = require("beautiful")
local naughty       = require("naughty")
local gears         = require("gears")
local module_path = (...):match ("(.+/)[^/]+$") or ""

local wireless = {}
local function worker(args)
    local args = args or {}

    widgets_table = {}
    local connected = false

    -- Settings
    local ICON_DIR      = awful.util.getdir("config").."/"..module_path.."/net_widgets/icons/"
    local interface     = args.interface or "wlan0"
    local timeout       = args.timeout or 5
    local font          = args.font or beautiful.font
    local popup_signal  = args.popup_signal or false
    local popup_position = args.popup_position or naughty.config.defaults.position
    local onclick       = args.onclick
    local widget 	= args.widget == nil and wibox.layout.fixed.horizontal() or args.widget == false and nil or args.widget
    local indent 	= args.indent or 3
    local hide_when_rfkill_blocked = args.hide_when_rfkill_blocked or false

    local net_icon = wibox.widget.imagebox()
    net_icon:set_image(ICON_DIR.."wireless_na.png")
    local net_text = wibox.widget.textbox()
    net_text.font = font
    net_text:set_text(" N/A ")
    local signal_level = 0
    local rfkill_blocked = false
    local no_internet = false
    local function net_update()
	awful.spawn.easy_async("awk 'NR==3 {printf \"%3.0f\" ,($3/70)*100}' /proc/net/wireless",
        function(stdout, stderr, reason, exit_code)
          signal_level = tonumber( stdout )
        end)
    awful.spawn.easy_async_with_shell("rfkill list wifi | grep -q 'Soft blocked: yes'",
        function(stdout, stderr, reason, exit_code)
            if exit_code == 0 then
                rfkill_blocked = true
            else
                rfkill_blocked = false
            end
        end)
    awful.spawn.easy_async_with_shell("nc -z 8.8.8.8 53 >/dev/null 2>&1",
        function(_, _, _, exit_code)
            if not (exit_code == 0) then
                no_internet = true
            else
                no_internet = false
            end
        end)
        if hide_when_rfkill_blocked and rfkill_blocked then
            net_text.visible = false
            net_icon.visible = false
        elseif signal_level == nil then
            net_text.visible = true
            net_icon.visible = true
            connected = false
            net_text:set_text(" N/A ")
            net_icon:set_image(ICON_DIR.."wireless_na.png")
        else
            net_text.visible = true
            net_icon.visible = true
            connected = true
            net_text:set_text(string.format("%"..indent.."d%%", signal_level))
            if no_internet then
                net_icon:set_image(ICON_DIR.."wireless_noconnect.png")
            elseif signal_level < 25 then
                net_icon:set_image(ICON_DIR.."wireless_0.png")
            elseif signal_level < 50 then
                net_icon:set_image(ICON_DIR.."wireless_1.png")
            elseif signal_level < 75 then
                net_icon:set_image(ICON_DIR.."wireless_2.png")
            else
                net_icon:set_image(ICON_DIR.."wireless_3.png")
            end
        end
    end

    net_update()
    local timer = gears.timer.start_new( timeout, function () net_update()
      return true end )

    widgets_table["imagebox"]	= net_icon
    widgets_table["textbox"]	= net_text
    if widget then
	    widget:add(net_icon)
	    -- Hide the text when we want to popup the signal instead
	    if not popup_signal then
		    widget:add(net_text)
	    end
	    wireless:attach(widget,{onclick = onclick})
    end



    function text_grabber()
        local msg = ""
        if connected then
            local mac     = "N/A"
            local essid   = "N/A"
            local bitrate = "N/A"
            local inet    = "N/A"

            -- Use iw/ip
            f = io.popen("iw dev "..interface.." link")
            for line in f:lines() do
                -- Connected to 00:01:8e:11:45:ac (on wlp1s0)
                mac     = string.match(line, "Connected to ([0-f:]+)") or mac
                -- SSID: 00018E1145AC
                essid   = string.match(line, "SSID: (.+)") or essid
                -- tx bitrate: 36.0 MBit/s
                bitrate = string.match(line, "tx bitrate: (.+/s)") or bitrate
            end
            f:close()

            f = io.popen("ip addr show "..interface)
            for line in f:lines() do
                inet    = string.match(line, "inet (%d+%.%d+%.%d+%.%d+)") or inet
            end
            f:close()

            signal = ""
            if popup_signal and signal_level then
                signal = "├Strength\t"..signal_level.."\n"
            end
            msg =
                "<span font_desc=\""..font.."\">"..
                "┌["..interface.."]\n"..
                "├ESSID:\t\t"..essid.."\n"..
                "├IP:\t\t"..inet.."\n"..
                "├BSSID\t\t"..mac.."\n"..
                ""..signal..
                "└Bit rate:\t"..bitrate.."</span>"


        else
            msg = "Wireless network is disconnected"
        end

        return msg
    end
    return widget or widgets_table
end

function wireless:attach(widget, args)
    local args = args or {}
    local onclick = args.onclick
    -- Bind onclick event function
    if onclick then
	    widget:buttons(awful.util.table.join(
	    awful.button({}, 1, function() awful.util.spawn(onclick) end)
	    ))
    end
    local wireless_t = awful.tooltip {
      objects = { widget },
      border_width = 1,
      timer_function = function()
          return text_grabber()
      end
    }
    return widget
end

return setmetatable(wireless, {__call = function(_,...) return worker(...) end})
