os.loadAPI("lib/f.lua")
os.loadAPI("lib/button.lua")
local f = _G["f.lua"] or _G["f"] or f
local button = _G["button.lua"] or _G["button"] or button

-- Initialization
local monitor = f.periphSearch("monitor")
if not monitor then error("Monitor not found!") end

local modemFound = false
for _, name in pairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and peripheral.wrap(name).isWireless() then
        rednet.open(name)
        modemFound = true
        break
    end
end
if not modemFound then error("Wireless/Ender Modem not found!") end

local monX, monY = monitor.getSize()
local mon = {monitor = monitor, X = monX, Y = monY}
f.firstSet(mon)
monitor.setTextScale(0.5)

-- State
local rData = nil
local lastValues = {}
local uiInitialized = false

function drawSolidBox(m, x, y, w, h, color)
    f.draw_line(m, x, y, w, color)
    f.draw_line(m, x, y + h - 1, w, color)
    f.draw_line_y(m, x, y, y + h - 1, color)
    f.draw_line_y(m, x + w - 1, y, y + h - 1, color)
end

function drawUpdatedValue(x, y, label, value, color)
    if lastValues[label] ~= value then
        mon.monitor.setBackgroundColor(colors.black)
        mon.monitor.setCursorPos(x, y)
        local clearLen = (monX - 2) - x
        if clearLen > 0 then
            mon.monitor.write(string.rep(" ", clearLen))
        end
        
        f.draw_text(mon, x, y, label, colors.white, colors.black)
        
        local valStr = tostring(value)
        local rightX = monX - string.len(valStr) - 2
        
        if rightX > x + string.len(label) then
            f.draw_text_right(mon, 2, y, valStr, color, colors.black)
        else
            f.draw_text(mon, x + string.len(label) + 1, y, valStr, color, colors.black)
        end
        
        lastValues[label] = value
    end
end

function format_compact(num)
    if num >= 10^12 then return string.format("%.1fT", num / 10^12) end
    if num >= 10^9 then return string.format("%.1fG", num / 10^9) end
    if num >= 10^6 then return string.format("%.1fM", num / 10^6) end
    if num >= 10^3 then return string.format("%.1fK", num / 10^3) end
    return tostring(num)
end

function drawDashboard()
    if not rData then
        f.draw_text(mon, 10, 10, "WAITING FOR REACTOR DATA...", colors.yellow, colors.black)
        return
    end

    if not uiInitialized then
        mon.monitor.clear()
        setupUI()
        lastValues = {}
        uiInitialized = true
    end

    local gH = 14; local gY = 5
    f.progress_bar_y(mon, 7, gY, gH, rData.temp, rData.maxTemp, colors.green, colors.gray)
    f.draw_text(mon, 6, gY+gH+1, "TEMP", colors.white, colors.black)
    f.draw_text(mon, 5, gY+gH+2, math.floor(rData.temp).."C", colors.green, colors.black)
    
    f.progress_bar_y(mon, 16, gY, gH, rData.fieldP, 100, colors.blue, colors.gray)
    f.draw_text(mon, 15, gY+gH+1, "FIELD", colors.white, colors.black)
    f.draw_text(mon, 15, gY+gH+2, math.floor(rData.fieldP).."%", colors.blue, colors.black)
    
    f.progress_bar_y(mon, 25, gY, gH, rData.fuelP, 100, colors.orange, colors.gray)
    f.draw_text(mon, 24, gY+gH+1, "FUEL", colors.white, colors.black)
    f.draw_text(mon, 24, gY+gH+2, math.floor(rData.fuelP).."%", colors.orange, colors.black)

    local cx = 35
    local statusD = {running={"ONLINE",colors.green},cold={"OFFLINE",colors.gray},warming_up={"CHARGING",colors.orange},cooling={"COOLING",colors.blue},stopping={"SHUTDOWN",colors.red}}
    local s = statusD[rData.status] or statusD.stopping
    drawUpdatedValue(cx, 5, "System State:", s[1], s[2])
    drawUpdatedValue(cx, 7, "Generation:", f.format_int(rData.genRate).." RF/t", colors.lime)
    drawUpdatedValue(cx, 8, "Thermal Trend:", string.format("%.3f C/t", rData.tempRise), colors.white)
    
    drawUpdatedValue(cx, 10, "Containment Field:", string.format("%.2f%%", rData.fieldP), colors.blue)
    f.progress_bar(mon, cx, 11, monX - cx - 5, rData.fieldP, 100, colors.blue, colors.gray)
    
    drawUpdatedValue(cx, 13, "Energy Saturation:", string.format("%.2f%%", rData.satP), colors.cyan)
    f.progress_bar(mon, cx, 14, monX - cx - 5, rData.satP, 100, colors.cyan, colors.gray)
    
    if rData.coreMax > 0 then
        local cP = (rData.coreE / rData.coreMax) * 100
        drawUpdatedValue(cx, 16, "Storage Core:", format_compact(rData.coreE).." ("..math.floor(cP).."%)", colors.yellow)
        f.progress_bar(mon, cx, 17, monX - cx - 5, cP, 100, colors.yellow, colors.gray)
    end
    
    if rData.upsMax and rData.upsMax > 0 then
        local bP = (rData.upsE / rData.upsMax) * 100
        drawUpdatedValue(cx, 18, "UPS Buffer:", format_compact(rData.upsE).." ("..math.floor(bP).."%)", bP > 50 and colors.green or colors.red)
    end
    
    local tD = (rData.isThrottled) and "THROTTLED (0)" or ((rData.target == 0 and true) and "AUTO-THROTTLED" or f.format_int(rData.target))
    drawUpdatedValue(cx, 19, "Target Load:", tD, colors.white)
    drawUpdatedValue(cx, 20, "Flow (Out/In):", format_compact(rData.outFlow).." / "..format_compact(rData.inFlow), colors.lightBlue)
end

function setupUI()
    mon.monitor.clear()
    drawSolidBox(mon, 1, 1, monX, monY, colors.gray)
    drawSolidBox(mon, 2, 3, 30, monY - 4, colors.gray) -- Gauges
    drawSolidBox(mon, 33, 3, monX - 34, monY - 4, colors.gray) -- Status
    f.draw_text(mon, 4, 3, " GAUGES ", colors.yellow, colors.black)
    f.draw_text(mon, 35, 3, " REMOTE REACTOR STATUS ", colors.yellow, colors.black)
    
    button.setMonitor(monitor)
    button.setButton("throttle", "TOGGLE THROTTLE", function()
        rednet.broadcast({command = "TOGGLE_THROTTLE"}, "draconic_control")
    end, 3, monY - 3, 25, monY - 1, 0, 0, colors.orange)
    
    button.setButton("power", "START/STOP", function()
        rednet.broadcast({command = "TOGGLE_POWER"}, "draconic_control")
    end, 28, monY - 3, 45, monY - 1, 0, 0, colors.red)
    
    button.screen()
end

function uiLoop()
    setupUI()
    while true do
        drawDashboard()
        sleep(0.5)
    end
end

function netLoop()
    while true do
        local id, msg, prot = rednet.receive("draconic_control")
        if type(msg) == "table" and msg.type == "reactor_status" then
            rData = msg
            if rData.isThrottled then
                button.setButton("throttle", "THROTTLE: ON", function() rednet.broadcast({command = "TOGGLE_THROTTLE"}, "draconic_control") end, 3, monY - 3, 25, monY - 1, 0, 0, colors.red)
            else
                button.setButton("throttle", "THROTTLE: OFF", function() rednet.broadcast({command = "TOGGLE_THROTTLE"}, "draconic_control") end, 3, monY - 3, 25, monY - 1, 0, 0, colors.green)
            end
            button.screen()
        end
    end
end

parallel.waitForAny(uiLoop, netLoop, button.clickEvent)