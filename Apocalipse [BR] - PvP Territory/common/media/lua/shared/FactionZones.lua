-- =======================================================
-- FILE 1: FactionZones.lua (SHARED) - CLIENT CACHE BRIDGE
-- =======================================================
FactionColors = {
    Neutral = {r=0.5, g=0.5, b=0.5, a=0.3},
    RED = {r=0.8, g=0.1, b=0.1, a=0.3},
    BLUE = {r=0.1, g=0.1, b=0.8, a=0.3},
}

FactionZones = {}
FactionZones.ClientCache = {} 

-- EXPERT TIP: We define the list empty by default for the release.
-- We keep the "Sunset Motel" commented out below as a template/debug tool.
FactionZones.List = {
    --[[ 
    {
        id = "Muldraugh_Motel",
        name = "Sunset Motel",
        x1 = 10598, y1 = 9741,
        x2 = 10711, y2 = 9855,
        captureTime = 100, -- Updated to 100 for smoother UI
        progress = 0,
        owner = "Neutral"
    }
    --]]
}

function FactionZones.getZoneAt(x, y, z)
    -- 1. Check Hardcoded List (If any exist)
    if FactionZones.List then
        for _, zone in ipairs(FactionZones.List) do
            local inX = (x >= zone.x1 and x <= zone.x2)
            local inY = (y >= zone.y1 and y <= zone.y2)
            -- Z is optional. If zone has z1/z2, check it. Otherwise ignore.
            local inZ = true
            if z and zone.z1 and zone.z2 then
                inZ = (z >= zone.z1 and z <= zone.z2)
            end

            if inX and inY and inZ then
                return zone
            end
        end
    end

    -- 2. Check Global Client Cache (Custom Zones)
    if FactionZones.ClientCache then
        for id, zone in pairs(FactionZones.ClientCache) do
            local x1 = tonumber(zone.x1)
            local y1 = tonumber(zone.y1)
            local x2 = tonumber(zone.x2)
            local y2 = tonumber(zone.y2)
            local z1 = tonumber(zone.z1) -- Optional Z
            local z2 = tonumber(zone.z2) -- Optional Z
            
            if x1 and y1 and x2 and y2 then
                local inX = (x >= x1 and x <= x2)
                local inY = (y >= y1 and y <= y2)
                local inZ = true
                if z and z1 and z2 then
                    inZ = (z >= z1 and z <= z2)
                end

                if inX and inY and inZ then
                    return {
                        id = id,
                        name = zone.name,
                        x1 = x1, y1 = y1,
                        x2 = x2, y2 = y2,
                        z1 = z1, z2 = z2,
                        captureTime = zone.captureTime,
                        owner = zone.owner,
                        zoneType = zone.zoneType or "Standard" -- [PHASE 4] Expose type
                    }
                end
            end
        end
    end

    return nil
end

function FactionZones.getZoneAtXY(x, y)
    return FactionZones.getZoneAt(x, y, nil)
end
