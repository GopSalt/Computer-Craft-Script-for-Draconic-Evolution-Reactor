
os.loadAPI("lib/f.lua")
os.loadAPI("lib/button.lua")
local f = _G["f.lua"] or _G["f"] or f
local button = _G["button.lua"] or _G["button"] or button

-- Reactor Safety Thresholds
local targetStrength = 50
local maxTemp = 7750
local safeTemp = 3000
local lowFieldPer = 15
local activateOnCharge = true

local version = 1.3

-- Configuration Variables
local autoInputGate = 1
local curInputGate = 222000
local targetGeneration = 0
local userTargetGeneration = 0
local autoOutputGate = 0
local fuelBlocks = 8
local autoCoreMode = 0
local coreHigh = 95
local coreLow = 20

local isThrottled = false
local savedTarget = 0

-- Runtime Variables
local lastTemp = 0
local currentTempRise = 0
local action = "None since reboot"
local actioncolor = colors.gray
local emergencyCharge = false
local emergencyTemp = false
local currentMenu = "main"

-- Peripherals
monitor = nil
reactor = nil
fluxgate = nil
inputFluxgate = nil
energyPylon = nil
bufferPylon = nil
mon = nil
monX = 0
monY = 0

-- Core Logic
function detectFlowGates()
    local gates = {peripheral.find("flow_gate")}
    if #gates < 2 then error("Error: Less than 2 flow gates detected!") end
    local inG, outG
    for _, name in pairs(peripheral.getNames()) do
        if peripheral.getType(name) == "flow_gate" then
            local gate = peripheral.wrap(name)
            if gate.getSignalLowFlow() == 10 then inG = gate else outG = gate end
        end
    end
    return inG, outG
end

function setupFlowGates()
    if not fs.exists("flowgate_names.txt") then
        local inG, outG = detectFlowGates()
        if not inG or not outG then error("Set input gate to 10 RF/t!") end
        local f = fs.open("flowgate_names.txt", "w")
        f.writeLine(peripheral.getName(inG))
        f.writeLine(peripheral.getName(outG))
        f.close()
        return inG, outG
    end
    local f = fs.open("flowgate_names.txt", "r")
    local inN, outN = f.readLine(), f.readLine()
    f.close()
    if peripheral.isPresent(inN) and peripheral.isPresent(outN) then
        return peripheral.wrap(inN), peripheral.wrap(outN)
    else
        fs.delete("flowgate_names.txt")
        return setupFlowGates()
    end
end

function save_config()
    local sw = fs.open("reactorconfig.txt", "w")
    sw.writeLine(autoInputGate); sw.writeLine(curInputGate)
    sw.writeLine(userTargetGeneration); sw.writeLine(autoOutputGate)
    sw.writeLine(fuelBlocks); sw.writeLine(autoCoreMode)
    sw.writeLine(coreHigh); sw.writeLine(coreLow)
    sw.writeLine(tostring(isThrottled)); sw.writeLine(savedTarget)
    sw.close()
end

function load_config()
    if not fs.exists("reactorconfig.txt") then return end
    local sr = fs.open("reactorconfig.txt", "r")
    local function readN() local l = sr.readLine() return l and tonumber(l) end
    autoInputGate = readN() or 1; curInputGate = readN() or 222000
    userTargetGeneration = readN() or 0; targetGeneration = userTargetGeneration
    autoOutputGate = readN() or 0; fuelBlocks = readN() or 8
    autoCoreMode = readN() or 0; coreHigh = readN() or 95; coreLow = readN() or 20
    local throttleLine = sr.readLine(); isThrottled = (throttleLine == "true")
    savedTarget = readN() or userTargetGeneration
    sr.close()
    if isThrottled then targetGeneration = 0 end
end

-- UI Helpers
function drawSolidBox(m, x, y, w, h, color)
    f.draw_line(m, x, y, w, color)
    f.draw_line(m, x, y + h - 1, w, color)
    f.draw_line_y(m, x, y, y + h - 1, color)
    f.draw_line_y(m, x + w - 1, y, y + h - 1, color)
end

local lastValues = {}
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

function reactorControl()
    local init = reactor.getReactorInfo()
    if init then lastTemp = init.temperature end
    while true do
        local ri = reactor.getReactorInfo()
        if not ri then sleep(1) goto continue end
        local tR = ri.temperature - lastTemp
        lastTemp = ri.temperature; currentTempRise = tR

        local fuelP = 100 - (math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000) * 0.01)
        local stability = (fuelBlocks / 8) * math.max(0.1, fuelP / 100)

        if ri.status == "warming_up" then
            inputFluxgate.setSignalLowFlow(900000)
            fluxgate.setSignalLowFlow(0)
            if activateOnCharge then reactor.activateReactor() end
        elseif ri.status == "cooling" or ri.status == "stopping" then
            inputFluxgate.setSignalLowFlow(autoInputGate == 1 and math.ceil(ri.fieldDrainRate / (1 - (targetStrength / 100))) or curInputGate)
            fluxgate.setSignalLowFlow(0)
        elseif ri.status == "cold" then
            inputFluxgate.setSignalLowFlow(0)
            fluxgate.setSignalLowFlow(0)
        elseif ri.status == "running" then
            inputFluxgate.setSignalLowFlow(autoInputGate == 1 and math.ceil(ri.fieldDrainRate / (1 - (targetStrength / 100))) or curInputGate)
            if energyPylon and autoCoreMode == 1 then
                local cP = (energyPylon.getEnergyStored() / energyPylon.getMaxEnergyStored()) * 100
                if cP > coreHigh and targetGeneration > 0 then targetGeneration = 0
                elseif cP < coreLow and targetGeneration == 0 and not isThrottled then targetGeneration = userTargetGeneration end
            end
            if isThrottled then targetGeneration = 0 end
            local curG = fluxgate.getSignalLowFlow()
            if ri.generationRate < targetGeneration then
                local baseA = 5
                if ri.temperature < 4000 then baseA = 100 * stability
                elseif ri.temperature < 7500 then baseA = (100 * stability) - ((ri.temperature - 4000) / 3500 * (100 * stability - 5)) end
                if tR < baseA then
                    local mS = math.floor(50000 * stability * (ri.temperature > 4000 and math.max(0.01, (7500-ri.temperature)/3500) or 1))
                    local newG = curG + math.max(5, math.min(mS, math.floor((targetGeneration - ri.generationRate) / 10)))
                    if newG > targetGeneration then newG = targetGeneration end
                    fluxgate.setSignalLowFlow(newG)
                elseif tR > baseA + 0.5 then
                    fluxgate.setSignalLowFlow(math.max(0, curG - math.max(5000, math.floor((tR - baseA) * 10000))))
                end
            elseif ri.generationRate > targetGeneration + 500 then
                local newG = math.max(0, curG - math.max(500, math.floor((ri.generationRate - targetGeneration) / 5)))
                if newG < targetGeneration and targetGeneration > 0 then newG = targetGeneration end
                fluxgate.setSignalLowFlow(newG)
            end
        end
        local fStr = (ri.fieldStrength / ri.maxFieldStrength) * 100
        local upsP = bufferPylon and (bufferPylon.getEnergyStored() / bufferPylon.getMaxEnergyStored() * 100) or 100

        if fuelP <= 5 then emergencyShutdown("FUEL LOW")
        elseif upsP < 50 and ri.status == "running" then emergencyShutdown("UPS BUFFER LOW")
        elseif fStr <= lowFieldPer and ri.status == "running" then emergencyShutdown("FIELD CRITICAL")
        elseif ri.temperature > maxTemp then emergencyShutdown("OVERHEAT")
        elseif ri.temperature + (tR * 15) > maxTemp - 100 and ri.status == "running" and tR > 0 then emergencyShutdown("PRED OVERHEAT") end
        sleep(0.1)
        ::continue::
    end
end

function emergencyShutdown(msg)
    fluxgate.setSignalLowFlow(0); reactor.stopReactor()
    action = msg; ActionMenu()
end

function updateReactorInfo()
    local ri = reactor.getReactorInfo()
    if not ri then return end
    local fuelP = 100 - (math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000) * 0.01)
    local fieldP = (ri.fieldStrength / ri.maxFieldStrength) * 100
    local satP = (ri.energySaturation / ri.maxEnergySaturation) * 100
    local gH = 14; local gY = 5
    f.progress_bar_y(mon, 7, gY, gH, ri.temperature, maxTemp, colors.green, colors.gray)
    f.draw_text(mon, 6, gY+gH+1, "TEMP", colors.white, colors.black)
    f.draw_text(mon, 5, gY+gH+2, math.floor(ri.temperature).."C", colors.green, colors.black)
    f.progress_bar_y(mon, 16, gY, gH, fieldP, 100, colors.blue, colors.gray)
    f.draw_text(mon, 15, gY+gH+1, "FIELD", colors.white, colors.black)
    f.draw_text(mon, 15, gY+gH+2, math.floor(fieldP).."%", colors.blue, colors.black)
    f.progress_bar_y(mon, 25, gY, gH, fuelP, 100, colors.orange, colors.gray)
    f.draw_text(mon, 24, gY+gH+1, "FUEL", colors.white, colors.black)
    f.draw_text(mon, 24, gY+gH+2, math.floor(fuelP).."%", colors.orange, colors.black)

    local cx = 35; local statusD = {running={"ONLINE",colors.green},cold={"OFFLINE",colors.gray},warming_up={"CHARGING",colors.orange},cooling={"COOLING",colors.blue},stopping={"SHUTDOWN",colors.red}}
    local s = statusD[ri.status] or statusD.stopping
    drawUpdatedValue(cx, 5, "System State:", s[1], s[2])
    drawUpdatedValue(cx, 7, "Generation:", f.format_int(ri.generationRate).." RF/t", colors.lime)
    drawUpdatedValue(cx, 8, "Thermal Trend:", string.format("%.3f C/t", currentTempRise), colors.white)
    drawUpdatedValue(cx, 10, "Containment Field:", string.format("%.2f%%", fieldP), colors.blue)
    f.progress_bar(mon, cx, 11, monX - cx - 5, fieldP, 100, colors.blue, colors.gray)
    drawUpdatedValue(cx, 13, "Energy Saturation:", string.format("%.2f%%", satP), colors.cyan)
    f.progress_bar(mon, cx, 14, monX - cx - 5, satP, 100, colors.cyan, colors.gray)
    if energyPylon then
        local cE = energyPylon.getEnergyStored(); local cP = (cE / energyPylon.getMaxEnergyStored()) * 100
        drawUpdatedValue(cx, 16, "Storage Core:", format_compact(cE).." ("..math.floor(cP).."%)", colors.yellow)
        f.progress_bar(mon, cx, 17, monX - cx - 5, cP, 100, colors.yellow, colors.gray)
    end
    if bufferPylon then
        local bE = bufferPylon.getEnergyStored(); local bP = (bE / bufferPylon.getMaxEnergyStored()) * 100
        drawUpdatedValue(cx, 18, "UPS Buffer:", format_compact(bE).." ("..math.floor(bP).."%)", bP > 50 and colors.green or colors.red)
    end
    local tD = (isThrottled) and "THROTTLED (0)" or ((autoCoreMode == 1 and targetGeneration == 0) and "AUTO-THROTTLED" or f.format_int(userTargetGeneration))
    drawUpdatedValue(cx, 19, "Target Load:", tD, colors.white)
    drawUpdatedValue(cx, 20, "Flow (Out/In):", format_compact(fluxgate.getSignalLowFlow()).." / "..format_compact(inputFluxgate.getSignalLowFlow()), colors.lightBlue)

    if rednet.isOpen() then
        rednet.broadcast({
            type = "reactor_status",
            status = ri.status, temp = ri.temperature, maxTemp = maxTemp,
            fieldP = fieldP, fuelP = fuelP, satP = satP,
            genRate = ri.generationRate, tempRise = currentTempRise,
            isThrottled = isThrottled, target = targetGeneration,
            outFlow = fluxgate.getSignalLowFlow(), inFlow = inputFluxgate.getSignalLowFlow(),
            coreE = energyPylon and energyPylon.getEnergyStored() or 0,
            coreMax = energyPylon and energyPylon.getMaxEnergyStored() or 0,
            upsE = bufferPylon and bufferPylon.getEnergyStored() or 0,
            upsMax = bufferPylon and bufferPylon.getMaxEnergyStored() or 0
        }, "draconic_control")
    end
end

function reactorInfoScreen()
    mon.monitor.clear()
    drawSolidBox(mon, 1, 1, monX, monY, colors.gray)
    drawSolidBox(mon, 2, 3, 30, monY - 19, colors.gray) -- Gauges
    drawSolidBox(mon, 33, 3, monX - 34, monY - 19, colors.gray) -- Status
    drawSolidBox(mon, 2, monY - 15, monX - 2, 15, colors.gray) -- Interface
    f.draw_text(mon, 4, 3, " GAUGES ", colors.yellow, colors.black)
    f.draw_text(mon, 35, 3, " REACTOR STATUS ", colors.yellow, colors.black)
    button.setMonitor(monitor); buttonMain()
    while true do updateReactorInfo(); sleep(0.5) end
end

function clearMenuArea(title)
    for i = monY - 14, monY - 2 do
        mon.monitor.setCursorPos(3, i); mon.monitor.setBackgroundColor(colors.black)
        mon.monitor.write(string.rep(" ", monX - 5))
    end
    button.clearTable()
    f.draw_line(mon, 5, monY - 15, 30, colors.gray) -- Clean up ghost characters on border
    f.draw_text(mon, 5, monY - 15, " "..(title or "INTERFACE").." ", colors.yellow, colors.black)
end

function buttonMain()
    clearMenuArea("MAIN CONTROL INTERFACE")
    local by = monY - 12
    button.setButton("b1", "SYSTEM CONTROLS", buttonControls, 5, by, 30, by+3, 0, 0, colors.blue)
    button.setButton("b2", "OUTPUT CONFIG", outputMenu, 35, by, 60, by+3, 0, 0, colors.blue)
    button.setButton("b3", "CORE SETTINGS", settingsMenu, 65, by, 90, by+3, 0, 0, colors.blue)
    button.screen()
end

function buttonControls()
    clearMenuArea("SYSTEM CONTROLS")
    local by = monY - 12
    button.setButton("t", "TOGGLE POWER", function()
        local ri = reactor.getReactorInfo()
        if ri.status == "running" then reactor.stopReactor() else reactor.chargeReactor() end
    end, 5, by, 30, by+3, 0, 0, colors.blue)
    button.setButton("r", "REBOOT", os.reboot, 35, by, 50, by+3, 0, 0, colors.red)
    button.setButton("x", "BACK", buttonMain, monX-20, by, monX-5, by+3, 0, 0, colors.gray)
    button.screen()
end

function outputMenu()
    clearMenuArea("OUTPUT CONFIGURATION")
    local by = monY - 12
    button.setButton("at", autoOutputGate==1 and "AUTO: ON" or "AUTO: OFF", function() autoOutputGate=autoOutputGate==1 and 0 or 1; save_config(); outputMenu() end, 5, by, 25, by+4, 0, 0, autoOutputGate==1 and colors.green or colors.red)
    local vals = {1000, 10000, 100000, 1000000}
    for i, v in ipairs(vals) do
        local x = 28 + (i-1)*12
        button.setButton("m"..i, "-"..format_compact(v), function() if autoOutputGate==1 then userTargetGeneration=math.max(0,userTargetGeneration-v); targetGeneration=userTargetGeneration else fluxgate.setSignalLowFlow(math.max(0,fluxgate.getSignalLowFlow()-v)) end; save_config() end, x, by, x+10, by+1, 0, 0, colors.blue)
        button.setButton("p"..i, "+"..format_compact(v), function() if autoOutputGate==1 then userTargetGeneration=userTargetGeneration+v; targetGeneration=userTargetGeneration else fluxgate.setSignalLowFlow(fluxgate.getSignalLowFlow()+v) end; save_config() end, x, by+3, x+10, by+4, 0, 0, colors.blue)
    end
    button.setButton("x", "BACK", buttonMain, monX-15, by, monX-5, by+4, 0, 0, colors.gray); button.screen()
end

function settingsMenu()
    clearMenuArea("CORE & FUEL SETTINGS")
    local by = monY - 13
    f.draw_text(mon, 5, by, "Fuel: "..fuelBlocks.." Blocks", colors.white, colors.black)
    button.setButton("f-", "-", function() fuelBlocks=math.max(1,fuelBlocks-1); save_config(); settingsMenu() end, 25, by, 28, by+1, 0, 0, colors.red)
    button.setButton("f+", "+", function() fuelBlocks=math.min(8,fuelBlocks+1); save_config(); settingsMenu() end, 30, by, 33, by+1, 0, 0, colors.green)
    button.setButton("ct", autoCoreMode==1 and "SMART: ON" or "SMART: OFF", function() autoCoreMode=autoCoreMode==1 and 0 or 1; if autoCoreMode==0 then targetGeneration=userTargetGeneration end; save_config(); settingsMenu() end, 5, by+3, 20, by+5, 0, 0, autoCoreMode==1 and colors.green or colors.red)
    if autoCoreMode == 1 then
        f.draw_text(mon, 23, by+3, "H:"..coreHigh.."% L:"..coreLow.."%", colors.white, colors.black)
        button.setButton("h-", "-", function() coreHigh=math.max(coreLow+5,coreHigh-5); save_config(); settingsMenu() end, 40, by+3, 43, by+4, 0, 0, colors.red)
        button.setButton("h+", "+", function() coreHigh=math.min(100,coreHigh+5); save_config(); settingsMenu() end, 45, by+3, 48, by+4, 0, 0, colors.green)
        button.setButton("l-", "-", function() coreLow=math.max(0,coreLow-5); save_config(); settingsMenu() end, 51, by+3, 54, by+4, 0, 0, colors.red)
        button.setButton("l+", "+", function() coreLow=math.min(coreHigh-5,coreLow+5); save_config(); settingsMenu() end, 56, by+3, 59, by+4, 0, 0, colors.green)
    end
    button.setButton("x", "BACK", buttonMain, monX-12, by+6, monX-5, by+8, 0, 0, colors.gray); button.screen()
end

function ActionMenu()
    clearMenuArea("ATTENTION REQUIRED")
    f.draw_text(mon, 10, monY-10, action, colors.red, colors.black)
    button.setButton("x", "DISMISS", buttonMain, monX-20, monY-8, monX-5, monY-5, 0, 0, colors.gray); button.screen()
end

function rednetListener()
    while true do
        local id, msg, prot = rednet.receive("draconic_control")
        if type(msg) == "table" and msg.command then
            if msg.command == "TOGGLE_THROTTLE" then
                isThrottled = not isThrottled
                if isThrottled then
                    savedTarget = userTargetGeneration
                    userTargetGeneration = 0
                else
                    userTargetGeneration = savedTarget
                end
                targetGeneration = userTargetGeneration
                save_config()
            elseif msg.command == "TOGGLE_POWER" then
                local ri = reactor.getReactorInfo()
                if ri and ri.status == "running" then reactor.stopReactor() elseif ri then reactor.chargeReactor() end
            end
        end
    end
end

function setupPylons()
    if fs.exists("pylon_names.txt") then
        local f = fs.open("pylon_names.txt", "r")
        local mainN = f.readLine()
        local bufN = f.readLine()
        f.close()
        local mainP, bufP
        if mainN and mainN ~= "none" and peripheral.isPresent(mainN) then mainP = peripheral.wrap(mainN) end
        if bufN and bufN ~= "none" and peripheral.isPresent(bufN) then bufP = peripheral.wrap(bufN) end
        if mainP or bufP then return mainP, bufP end
        fs.delete("pylon_names.txt")
    end

    local pNames = {}
    for _, name in pairs(peripheral.getNames()) do
        local pt = peripheral.getType(name)
        if pt == "draconic_rf_storage" or pt == "energy_pylon" then
            table.insert(pNames, name)
        end
    end

    if #pNames == 0 then return nil, nil end
    if #pNames == 1 then return peripheral.wrap(pNames[1]), nil end

    term.clear()
    term.setCursorPos(1,1)
    print("=== PYLON SETUP ===")
    print("Multiple Energy Pylons detected!")
    for i, name in ipairs(pNames) do
        local p = peripheral.wrap(name)
        local stored = p.getEnergyStored()
        print(i..": "..name.." ("..format_compact(stored).." RF)")
    end
    print("\nEnter number for MAIN pylon (0 for none):")
    local mainIdx = tonumber(read()) or 1
    print("Enter number for BUFFER (UPS) pylon (0 for none):")
    local bufIdx = tonumber(read()) or 0

    local mainN = (mainIdx > 0 and mainIdx <= #pNames) and pNames[mainIdx] or "none"
    local bufN = (bufIdx > 0 and bufIdx <= #pNames) and pNames[bufIdx] or "none"

    local f = fs.open("pylon_names.txt", "w")
    f.writeLine(mainN)
    f.writeLine(bufN)
    f.close()

    return (mainN ~= "none" and peripheral.wrap(mainN) or nil), (bufN ~= "none" and peripheral.wrap(bufN) or nil)
end

-- Init
load_config()
for _, name in pairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and peripheral.wrap(name).isWireless() then
        rednet.open(name); break
    end
end
monitor = f.periphSearch("monitor"); reactor = f.periphSearch("draconic_reactor")
energyPylon, bufferPylon = setupPylons()
inputFluxgate, fluxgate = setupFlowGates()
monX, monY = monitor.getSize(); mon = {monitor = monitor, X = monX, Y = monY}
f.firstSet(mon); monitor.setTextScale(0.5)
parallel.waitForAny(reactorInfoScreen, reactorControl, button.clickEvent, rednetListener)
