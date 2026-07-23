-- =======================================================
-- FILE 3: ZoneDebug.lua (CLIENT) - FIX & DEBUG
-- =======================================================

local lastZone = nil 
local DebugStatusCache = {}

local function CheckZoneMovement()
    pcall(function()
        if not FactionZones or type(FactionZones.getZoneAtXY) ~= "function" then return end
        local player = getPlayer()
        if not player then return end 

        local currentZone = FactionZones.getZoneAtXY(player:getX(), player:getY())
        
        -- [FIX] Compare IDs instead of tables to stop infinite looping
        local currentID = currentZone and currentZone.id
        local lastID = lastZone and lastZone.id

        if currentID ~= lastID then
            -- [DEBUG] Log zone transitions to console
            if currentZone then
                print("DEBUG: ENTERED ZONE " .. currentZone.name .. " (ID: " .. currentID .. ")")
            else
                print("DEBUG: LEFT ZONE")
            end

            if currentZone then
                -- 1. FETCH OWNER DATA FROM CACHE
                local zoneData = DebugStatusCache[currentZone.id]
                if not zoneData then
                    local modDataStatus = ModData.get("FactionWarZones")
                    if modDataStatus then zoneData = modDataStatus[currentZone.id] end
                end
                
                local owner = zoneData and zoneData.owner or "Neutral"
                
                -- 2. GET PLAYER FACTION (ROBUST DETECTION)
                local tag = "Nomad"
                if Faction and Faction.getPlayerFaction then
                    local fac = Faction.getPlayerFaction(player:getUsername())
                    if fac then
                        tag = fac:getTag()
                        if not tag or tag == "" then tag = fac:getName() end
                    end
                end
                
                -- Fallback
                if tag == "Nomad" and player.getFaction then
                    local f = player:getFaction()
                    if f then tag = f:getName() end
                end
                
                -- 3. DISPLAY TEXT (Duration 100 = 1.5 seconds)
                if tag == "Nomad" then
                    player:setHaloNote("Territorio de " .. owner, 200, 200, 200, 300)
                else
                    if owner == tag then
                         player:setHaloNote("Defendendo: " .. currentZone.name, 100, 100, 255, 300)
                    else
                         player:Say("Etrando no territorio de " .. owner .. "!")
                         player:setHaloNote("Capturando: " .. currentZone.name, 255, 0, 0, 300) 
                    end
                end
            else
                if lastZone then
                    player:setHaloNote("Saiu do Territorio", 200, 200, 200, 50)
                end
            end
            lastZone = currentZone
        end
    end)
end

Events.OnReceiveGlobalModData.Add(function(key, data)
    if key == "FactionWarZones" and data then
        DebugStatusCache = data
    end
end)

Events.OnPlayerUpdate.Add(CheckZoneMovement)
