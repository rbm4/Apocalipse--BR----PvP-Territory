-- =======================================================
-- FILE: media/lua/client/FactionWar_PryCompat.lua
-- DESCR: Adds compatibility for pry mechanics
-- Prevents prying doors/windows/vehicles in enemy Faction Zones.
-- =======================================================

local function getZoneAt(x, y, z)
    if not FactionZones then return nil end
    local zones = {}
    if FactionZones.List then
        for _, zDef in ipairs(FactionZones.List) do table.insert(zones, zDef) end
    end
    if FactionZones.ClientCache then
        for _, zDef in pairs(FactionZones.ClientCache) do table.insert(zones, zDef) end
    end

    for _, zone in ipairs(zones) do
        local x1 = tonumber(zone.x1) or 0
        local y1 = tonumber(zone.y1) or 0
        local x2 = tonumber(zone.x2) or 0
        local y2 = tonumber(zone.y2) or 0
        
        local minX = math.min(x1, x2)
        local maxX = math.max(x1, x2)
        local minY = math.min(y1, y2)
        local maxY = math.max(y1, y2)

        local inZ = true
        if zone.z1 and zone.z2 then
            local z1 = tonumber(zone.z1) or 0
            local z2 = tonumber(zone.z2) or 0
            local minZ = math.min(z1, z2)
            local maxZ = math.max(z1, z2)
            inZ = (z >= minZ and z <= maxZ)
        end

        if x >= minX and x <= maxX and y >= minY and y <= maxY and inZ then
            return zone
        end
    end
    return nil
end

local function GetRealFaction(player)
    if not player then return "Nomad" end
    local username = player:getUsername()
    if Faction and Faction.getPlayerFaction then
        local fac = Faction.getPlayerFaction(username)
        if fac then
            local tag = fac:getTag()
            if tag and tag ~= "" then return tag end
            local name = fac:getName()
            if name and name ~= "" then return name end
        end
    end
    if player.getFaction then
        local faction = player:getFaction()
        if faction then
            local name = faction:getName()
            if name and name ~= "" then return name end
        end
    end
    return "Nomad"
end

local function IsEnemyZone(sq, player)
    if not sq or not player then return false end
    
    local zone = getZoneAt(sq:getX(), sq:getY(), sq:getZ())
    if not zone then return false end

    local owner = "Neutral"
    if ModData and ModData.get then
        local statusData = ModData.get("FactionWarZones")
        if statusData and statusData[zone.id] then
            owner = statusData[zone.id].owner or "Neutral"
        end
    end
    
    local myFaction = GetRealFaction(player)
    if owner ~= "Neutral" and owner ~= myFaction then
        -- Check if allied
        local isAllied = false
        if ModData and ModData.get then
            local alliances = ModData.get("FactionAlliances") or {}
            if alliances[myFaction] and alliances[myFaction][owner] then
                isAllied = true
            end
        end
        
        if not isAllied then
            return true -- It is an enemy zone!
        end
    end
    return false
end

local function InitCompat()
    -- 1. Patch canPryWorldTarget
    if CSR_Utils and type(CSR_Utils.canPryWorldTarget) == "function" then
        local original_canPryWorldTarget = CSR_Utils.canPryWorldTarget
        CSR_Utils.canPryWorldTarget = function(target, player)
            if target and player then
                local sq = target:getSquare()
                if IsEnemyZone(sq, player) then
                    return false, "Cannot pry in enemy Faction Zone"
                end
            end
            return original_canPryWorldTarget(target, player)
        end
        print("FactionWar: Pry mechanics patched.")
    end

    -- 2. Patch PryOpenAction
    if CSR_PryOpenAction and type(CSR_PryOpenAction.isValid) == "function" then
        local original_isValid = CSR_PryOpenAction.isValid
        CSR_PryOpenAction.isValid = function(self)
            if self.target and self.character then
                local sq = self.target:getSquare()
                if IsEnemyZone(sq, self.character) then
                    return false
                end
            end
            return original_isValid(self)
        end
    end

    -- 3. Patch PryVehicleDoorAction
    if CSR_PryVehicleDoorAction and type(CSR_PryVehicleDoorAction.isValid) == "function" then
        local original_veh_isValid = CSR_PryVehicleDoorAction.isValid
        CSR_PryVehicleDoorAction.isValid = function(self)
            if self.vehicle and self.character then
                local sq = self.vehicle:getSquare()
                if IsEnemyZone(sq, self.character) then
                    return false
                end
            end
            return original_veh_isValid(self)
        end
    end
end

Events.OnGameStart.Add(InitCompat)
