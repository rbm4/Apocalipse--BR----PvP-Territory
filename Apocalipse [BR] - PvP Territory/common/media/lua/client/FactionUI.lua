-- =======================================================
-- FILE: media/lua/client/FactionUI.lua
-- =======================================================

FactionProgressBar = ISUIElement:derive("FactionProgressBar")
local LocalStatusCache = {} 

function FactionProgressBar:new()
    local core = getCore()
    local screenW = core:getScreenWidth()
    
    local barW = 400
    local barH = 35
    local x = (screenW / 2) - (barW / 2)
    local y = 60 
    
    local o = ISUIElement:new(x, y, barW, barH)
    setmetatable(o, self)
    self.__index = self
    
    o.borderColor = {r=0, g=0, b=0, a=0}
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    
    -- [UI DEPTH FIX]
    -- stayOnBack ensures it renders behind inventory/character windows
    -- setWantEvents(false) ensures it doesn't "eat" mouse clicks
    o.stayOnBack = true
    
    -- [FIX] Track the last known owner to detect flips
    self.lastOwner = nil
    
    return o
end

function FactionProgressBar:render()
    local player = getPlayer()
    if not player then return end
    if type(player.getX) ~= "function" then return end
    
    -- 1. Get Zone
    if not FactionZones or not FactionZones.getZoneAtXY then return end
    local zone = FactionZones.getZoneAtXY(player:getX(), player:getY())
    
    if not zone then 
        self.renderedProgress = nil
        self.lastZoneID = nil
        self.lastOwner = nil
        return 
    end 

    -- 2. Get Data
    local zoneData = LocalStatusCache[zone.id]
    if not zoneData then
        local modDataStatus = ModData.get("FactionWarZones")
        if modDataStatus then zoneData = modDataStatus[zone.id] end
    end
    
    local targetProgress = zoneData and zoneData.progress or 0
    
    -- [SETTINGS] READ FROM SANDBOX (This fixes the UI speed mismatch)
    local maxTime = (SandboxVars.FactionWar and SandboxVars.FactionWar.CaptureTime) or 100
    
    local owner = zoneData and zoneData.owner or "Neutral"
    local col = zoneData and zoneData.col

    -- [FIX] Initialize lastOwner if nil
    if self.lastOwner == nil then self.lastOwner = owner end

    -- =========================================================
    -- [FIX] ANIMATION LOGIC
    -- =========================================================
    
    -- 1. If we switched zones, SNAP.
    if self.lastZoneID ~= zone.id then
        self.renderedProgress = targetProgress
        self.lastZoneID = zone.id
        self.lastOwner = owner
    end

    -- 2. If OWNER CHANGED (Win/Loss), SNAP! 
    -- This prevents the bar from sliding down from 100% to 0%
    if self.lastOwner ~= owner then
        self.renderedProgress = targetProgress
        self.lastOwner = owner
    end

    -- Initialize if nil
    if not self.renderedProgress then self.renderedProgress = targetProgress end

    -- 3. Standard Smoothing (Only if owner hasn't changed)
    local diff = targetProgress - self.renderedProgress
    if math.abs(diff) > 0.01 then
        self.renderedProgress = self.renderedProgress + (diff * 0.1) -- Faster smooth (0.1)
    else
        self.renderedProgress = targetProgress
    end
    
    -- Calc Percent
    local pct = self.renderedProgress / maxTime
    if pct > 1 then pct = 1 end
    if pct < 0 then pct = 0 end
    
    -- =========================================================
    
    -- 3. Draw Background
    local width = self:getWidth()
    local height = self:getHeight()
    self:drawRect(0, 0, width, height, 0.5, 0, 0, 0)
    self:drawRectBorder(0, 0, width, height, 1, 1, 1, 1)

    -- 4. Colors
    local r, g, b = 0.5, 0.5, 0.5 
    -- Use targetProgress for color logic to be snappy
    if zoneData and zoneData.isProtected then
        r, g, b = 0.4, 0.4, 0.4 -- Greyed out for protected
    elseif targetProgress > 0 and targetProgress < maxTime then
        r, g, b = 0.9, 0.9, 0.1 -- Active Conflict (Yellow)
    elseif col then
        r, g, b = col.r, col.g, col.b
    elseif owner ~= "Neutral" then
        r, g, b = 0.8, 0.1, 0.1 
    end

    -- 5. Draw Bar
    if pct > 0 then
        self:drawRect(2, 2, (width - 4) * pct, height - 4, 0.8, r, g, b)
    end

    -- 6. Draw Title Line
    local titleText = ""
    if owner == "Neutral" then
        titleText = zone.name .. " (Neutral)"
    else
        titleText = zone.name .. " [" .. owner .. "]"
    end

    local myFaction = "Nomad"
    if Faction and Faction.getPlayerFaction then
        local fac = Faction.getPlayerFaction(player:getUsername())
        if fac then
            myFaction = fac:getTag()
            if not myFaction or myFaction == "" then myFaction = fac:getName() end
        end
    end
    if myFaction == "Nomad" and player.getFaction then
        local f = player:getFaction()
        if f then myFaction = f:getName() end
    end

    local statusText = titleText
    if zoneData and zoneData.isProtected and myFaction ~= "Nomad" and myFaction ~= owner then
        statusText = "[PROTECAO OFFLINE ATIVADA]"
    elseif zoneData and zoneData.isContested then
        statusText = "CONSTESTADA"
    elseif pct > 0 and pct < 1 and owner == self.lastOwner then
        local percentNum = math.floor(pct * 100)
        local attacker = zoneData and zoneData.attacker
        if zoneData and zoneData.isReversing and zoneData.reverseAttacker then
            statusText = tostring(zoneData.reverseAttacker) .. " removendo " .. tostring(attacker or "faccao") .. ": " .. percentNum .. "%"
        elseif attacker and attacker ~= "Nomad" and attacker ~= "Neutral" then
            statusText = "Capturando " .. attacker .. ": " .. percentNum .. "%"
        else
            statusText = "Captura: " .. percentNum .. "%"
        end
    end

    local textY = (height - getTextManager():getFontHeight(UIFont.Medium)) / 2
    self:drawTextCentre(statusText, width / 2 + 1, textY + 1, 1, 0, 0, 0, UIFont.Medium)
    self:drawTextCentre(statusText, width / 2, textY, 1, 1, 1, 1, UIFont.Medium)

end

Events.OnReceiveGlobalModData.Add(function(key, data)
    if key == "FactionWarZones" and data then
        LocalStatusCache = data
    end
end)

-- [PHASE 2] Receive radio-style messages from the server
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "FW_Msg" then return end
    if command == "RadioMsg" and args and args.text then
        -- Print to chat as a styled server message
        if getPlayerChatUI then
            local chatUI = getPlayerChatUI(0)
            if chatUI then chatUI:addLineInChat(nil, args.text) end
        end
        -- Also show as a halo note on the local player
        local player = getPlayer()
        if player then
            player:setHaloNote(args.text, 255, 220, 50, 500)
        end
    elseif command == "ConquestDeathCooldown" then
        local player = getPlayer()
        if player then
            local remaining = args and tonumber(args.remaining) or 30
            local msg = getText("IGUI_FactionWar_ConquestDeathCooldown")
            if not msg or msg == "IGUI_FactionWar_ConquestDeathCooldown" then
                msg = "You died during this conquest. Your presence will not count for %1 more minutes."
            end
            player:setHaloNote(msg:gsub("%%1", tostring(remaining)), 255, 80, 80, 500)
        end
    end
end)

function FactionUI_Init()
    if not FactionProgressBar then return end
    local overlay = FactionProgressBar:new()
    if overlay then 
        overlay:addToUIManager() 
        if ModData.request then ModData.request("FactionWarZones") end
    end
end

Events.OnGameStart.Add(FactionUI_Init)
