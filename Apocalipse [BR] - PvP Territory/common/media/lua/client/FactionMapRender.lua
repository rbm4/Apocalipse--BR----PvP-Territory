require "ISUI/Maps/ISWorldMap"
require "FactionZones"

local ZONE_DATA_KEY = "FactionZoneDefinitions"
local LocalMapStatusCache = {}

-- Track when we last requested data (to avoid spamming)
local lastRequestTime = 0
local function RequestFWData()
    print("[FactionWar] Requesting ModData from server...")
    if ModData and ModData.request then
        ModData.request(ZONE_DATA_KEY)
        ModData.request("FactionWarZones")
    end
end

-- =======================================================
-- 1. Request Data - multiple hooks for dedicated server reliability
-- =======================================================
Events.OnGameStart.Add(RequestFWData)
Events.OnCreatePlayer.Add(function() RequestFWData() end)

-- Key fix for dedicated servers: connected event fires AFTER the server
-- is actually ready to respond to ModData requests
if Events.OnConnectedToServer then
    Events.OnConnectedToServer.Add(function()
        -- Small delay: wait 2 seconds after connect before requesting
        -- (server may not have loaded our mod data yet)
        lastRequestTime = -999
        RequestFWData()
    end)
end

if not ISWorldMap then return end

-- =======================================================
-- [FIX] Ensure we don't hook multiple times on reload
-- =======================================================
if not ISWorldMap.oldRender_FactionWar then
    ISWorldMap.oldRender_FactionWar = ISWorldMap.render
end

-- =======================================================
-- HELPER: Resolve the color for a zone
-- Returns r, g, b (all 0-1 range)
-- Priority: synced col table -> owner name lookup -> neutral grey
-- =======================================================
local function resolveColor(zoneData)
    local owner = zoneData and zoneData.owner or "Neutral"
    if owner == "Neutral" or owner == "Nomad" then
        return 0.5, 0.5, 0.5  -- grey
    end

    -- 1. Try Live Java Faction Color (Solves dynamic color changes)
    if Faction and Faction.getFactions then
        local factions = Faction.getFactions()
        if factions then
            for i=0, factions:size()-1 do
                local fac = factions:get(i)
                if fac:getName() == owner or fac:getTag() == owner then
                    if fac.getTagColor then
                        local col = fac:getTagColor()
                        if col then
                            return col:getR(), col:getG(), col:getB()
                        end
                    end
                end
            end
        end
    end

    -- 2. Fallback: server synced a col table
    if zoneData and zoneData.col then
        local c = zoneData.col
        if c.r and c.g and c.b then
            return c.r, c.g, c.b
        end
    end

    -- 3. Try the global FactionColors table (defined in FactionZones.lua)
    if FactionColors and FactionColors[owner] then
        local c = FactionColors[owner]
        return c.r or 0.8, c.g or 0.1, c.b or 0.1
    end

    -- Last resort: distinguish factions by hashing the name so two factions
    -- don't both end up the same default red.
    local hash = 0
    for i = 1, #owner do
        hash = (hash * 31 + owner:byte(i)) % 360
    end
    -- Convert a hue (0-360) to RGB
    local h = hash / 360
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end
    local q = 0.7  -- saturation
    local p = 0.3
    return hue2rgb(p, q, h + 1/3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1/3)
end

-- =======================================================
-- CORE: Draw one zone on the map
-- =======================================================
local function drawZone(self, zone, allZoneStatus)
    if not zone then return end

    -- ---- Resolve status data ----
    local zoneData = allZoneStatus[zone.id]

    -- If we have no data yet for this zone, request a sync from server
    -- (only do this once per zone per map open, not every frame)
    if not zoneData and not zone._dataMissing then
        zone._dataMissing = true
        if ModData and ModData.request then
            ModData.request("FactionWarZones")
        end
    end

    local r, g, b = resolveColor(zoneData)

    -- ---- Map coordinates (4 corners of the zone) ----
    local p1x = self.mapAPI:worldToUIX(zone.x1, zone.y1)
    local p1y = self.mapAPI:worldToUIY(zone.x1, zone.y1)
    
    local p2x = self.mapAPI:worldToUIX(zone.x2, zone.y1)
    local p2y = self.mapAPI:worldToUIY(zone.x2, zone.y1)
    
    local p3x = self.mapAPI:worldToUIX(zone.x2, zone.y2)
    local p3y = self.mapAPI:worldToUIY(zone.x2, zone.y2)
    
    local p4x = self.mapAPI:worldToUIX(zone.x1, zone.y2)
    local p4y = self.mapAPI:worldToUIY(zone.x1, zone.y2)

    if not (p1x and p1y and p2x and p2y and p3x and p3y and p4x and p4y) then return end

    -- ---- Draw the zone area as a 4-point polygon ----
    -- This ensures it maps perfectly to the isometric ground in side-view mode
    local whiteTex = Texture.getSharedTexture("media/ui/white.png") or Texture.getWhite()
    if not whiteTex then return end
    
    self:drawTextureAllPoint(whiteTex, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, r, g, b, 0.15)
    
    -- Draw a slightly darker border
    self:drawTextureAllPoint(whiteTex, p1x-1, p1y-1, p2x-1, p2y-1, p3x-1, p3y-1, p4x-1, p4y-1, r * 1.3, g * 1.3, b * 1.3, 0.6)
    -- Draw main filled polygon again
    self:drawTextureAllPoint(whiteTex, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, r, g, b, 0.15)

    -- ---- Zone label (name + owner) ----
    local zoneData2 = zoneData  -- already resolved above
    local owner = zoneData2 and zoneData2.owner or "Neutral"
    
    local myFaction = "Nomad"
    local playerObj = getPlayer()
    if playerObj then
        local username = playerObj:getUsername()
        if Faction and Faction.getPlayerFaction then
            local fac = Faction.getPlayerFaction(username)
            if fac then
                myFaction = fac:getTag()
                if not myFaction or myFaction == "" then myFaction = fac:getName() end
            end
        end
        if myFaction == "Nomad" and playerObj.getFaction then
            local f = playerObj:getFaction()
            if f then myFaction = f:getName() end
        end
    end

    local isAllied = false
    if myFaction ~= "Nomad" and owner ~= "Neutral" and owner ~= myFaction then
        if ModData and ModData.get then
            local alliances = ModData.get("FactionAlliances") or {}
            if alliances[myFaction] and alliances[myFaction][owner] then
                isAllied = true
            end
        end
    end

    local labelText = (zone.name or "Zone") .. " [" .. owner .. "]"
    if isAllied then
        labelText = labelText .. " (Ally)"
    end

    -- Calculate center point for text
    local labelX = (p1x + p2x + p3x + p4x) / 4
    local labelY = (p1y + p2y + p3y + p4y) / 4 - 6
    
    local textR, textG, textB = 1.0, 1.0, 1.0
    if owner ~= "Neutral" and owner ~= "Nomad" then
        textR = math.min(1.0, r + 0.3)
        textG = math.min(1.0, g + 0.3)
        textB = math.min(1.0, b + 0.3)
    end

    self:drawTextCentre(labelText, labelX + 1, labelY + 1, 0.9, 0, 0, 0, UIFont.Small)
    self:drawTextCentre(labelText, labelX,     labelY,     1.0, textR, textG, textB, UIFont.Small)
end

-- =======================================================
-- 2. Map Render Hook
-- =======================================================
local function FactionWar_MapRender(self)
    if not self.mapAPI then return end

    if not self.mapAPI then return end
    
    if not FactionZones or not FactionColors then 
        if not self._fwErrPrinted then
            print("[FactionWar] ERROR: FactionZones or FactionColors missing in map render!")
            self._fwErrPrinted = true
        end
        return 
    end

    -- ---- Resolve the active zone status table ----
    -- Prefer the live cache (updated by ModData sync); fall back to direct get
    local allZoneStatus = LocalMapStatusCache

    local isCacheEmpty = true
    for _ in pairs(allZoneStatus) do isCacheEmpty = false; break end

    if isCacheEmpty and ModData and ModData.get then
        allZoneStatus = ModData.get("FactionWarZones") or {}
    end

    -- ---- Fallback: populate ClientCache from ModData directly if empty ----
    -- This handles dedicated servers where the OnReceiveGlobalModData event
    -- fired before ISWorldMap was ready, or was blocked by another mod (e.g. PhunLib)
    local clientCacheEmpty = true
    if FactionZones.ClientCache then
        for _ in pairs(FactionZones.ClientCache) do clientCacheEmpty = false; break end
    end

    if clientCacheEmpty and ModData and ModData.get then
        local defs = ModData.get(ZONE_DATA_KEY)
        if defs then
            FactionZones.ClientCache = defs
            clientCacheEmpty = false
        else
            -- Re-request from server (throttled: once every ~5 seconds of map being open)
            lastRequestTime = (lastRequestTime or 0) + 1
            if lastRequestTime >= 300 then
                RequestFWData()
                lastRequestTime = 0
            end
        end
    end

    -- ---- Draw Hardcoded Zones ----
    if FactionZones.List then
        for _, zone in ipairs(FactionZones.List) do
            local ok, err = pcall(drawZone, self, zone, allZoneStatus)
            if not ok then print("[FactionWar] Map draw error (hardcoded): " .. tostring(err)) end
        end
    end

    -- ---- Draw Dynamic (Admin-created) Zones ----
    if FactionZones.ClientCache then
        for id, zone in pairs(FactionZones.ClientCache) do
            zone.id = id
            local ok, err = pcall(drawZone, self, zone, allZoneStatus)
            if not ok then print("[FactionWar] Map draw error (dynamic): " .. tostring(err)) end
        end
    end
end

-- Robust override injection (delayed to ensure we wrap over other mods)
local function InjectMapRender()
    if ISWorldMap and ISWorldMap.render then
        local original_render = ISWorldMap.render
        ISWorldMap.render = function(self, ...)
            original_render(self, ...)
            FactionWar_MapRender(self)
        end
    end
end
Events.OnGameStart.Add(InjectMapRender)

-- =======================================================
-- 3. Data Sync Listener
-- =======================================================
Events.OnReceiveGlobalModData.Add(function(key, data)
    if key == ZONE_DATA_KEY then
        -- Zone Definitions (coords) arrived - update client cache
        FactionZones.ClientCache = data or {}

    elseif key == "FactionWarZones" and data then
        -- Zone Status (owner + color) arrived - replace the whole cache
        LocalMapStatusCache = data

        -- Clear the "data missing" flag so zones will get a fresh color
        if FactionZones then
            if FactionZones.List then
                for _, z in ipairs(FactionZones.List) do
                    z._dataMissing = nil
                end
            end
            if FactionZones.ClientCache then
                for _, z in pairs(FactionZones.ClientCache) do
                    z._dataMissing = nil
                end
            end
        end
    end
end)
