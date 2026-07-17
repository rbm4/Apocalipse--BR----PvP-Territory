-- =======================================================
-- FILE: media/lua/client/FactionBuffs.lua
-- DESCR: Passive Buffs & XP Training in Friendly Territory
-- =======================================================

local buffTickTimer = 0
local LocalBuffsStatusCache = {}
local debugCounter = 0
local DEBUG_PREFIX = "DEBUG BUFFS:"

print(DEBUG_PREFIX .. " FactionBuffs.lua loaded")

local function debugLog(message, force)
    if force or debugCounter % 5 == 0 then
        print(DEBUG_PREFIX .. " " .. tostring(message))
    end
end

local function countEntries(tbl)
    local count = 0
    if tbl then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
end

-- Helper to get data safely
local function getZoneOwner(zoneID)
    local data = LocalBuffsStatusCache
    if data and data[zoneID] then return data[zoneID].owner, "LocalBuffsStatusCache" end
    
    if not ModData then return nil, "ModData unavailable" end
    local fallback = ModData.get("FactionWarZones")
    if fallback and fallback[zoneID] then return fallback[zoneID].owner, "ModData.get(FactionWarZones)" end
    return nil, "not found"
end

Events.OnReceiveGlobalModData.Add(function(key, data)
    if key == "FactionWarZones" and data then
        LocalBuffsStatusCache = data
        print(DEBUG_PREFIX .. " received FactionWarZones entries=" .. tostring(countEntries(data)))
    end
end)

local function AreFactionsAllied(fac1, fac2)
    if not fac1 or not fac2 or fac1 == "Nomad" or fac2 == "Nomad" or fac1 == "Neutral" or fac2 == "Neutral" then return false end
    if fac1 == fac2 then return true end
    if not ModData then return false end
    local alliances = ModData.get("FactionAlliances") or {}
    if alliances[fac1] and alliances[fac1][fac2] then return true end
    return false
end

-- Global flag for UI to read if buffs are active
FactionBuffsActive = false
FactionBuffZoneType = nil

local function ApplyFactionBenefits(player)
    debugCounter = debugCounter + 1
    FactionBuffsActive = false
    FactionBuffZoneType = nil

    if not player then
        debugLog("skipped: no player")
        return
    end
    if player:isDead() then
        debugLog("skipped: player is dead")
        return
    end

    -- 1. Check Zone
    if not FactionZones or not FactionZones.getZoneAt then
        debugLog("skipped: FactionZones.getZoneAt unavailable", true)
        return
    end
    local zone = FactionZones.getZoneAt(player:getX(), player:getY(), player:getZ())
    if not zone then
        debugLog("no zone at x=" .. tostring(math.floor(player:getX())) .. " y=" .. tostring(math.floor(player:getY())) .. " z=" .. tostring(player:getZ()))
        return
    end 
    debugLog("zone found id=" .. tostring(zone.id) .. " name=" .. tostring(zone.name) .. " type=" .. tostring(zone.zoneType))
    
    -- 2. Check Ownership
    local owner, ownerSource = getZoneOwner(zone.id)
    if not owner or owner == "Neutral" then
        debugLog("skipped: owner=" .. tostring(owner) .. " source=" .. tostring(ownerSource) .. " zoneID=" .. tostring(zone.id), true)
        return
    end
    local username = player:getUsername()

    -- 3. Check Player Faction (ROBUST DETECTION)
    local playerFaction = "Nomad"
    if Faction and Faction.getPlayerFaction then
        local fac = Faction.getPlayerFaction(username)
        if fac then
            local tag = fac:getTag()
            if tag and tag ~= "" then 
                playerFaction = tag 
            else
                playerFaction = fac:getName()
            end
        end
    end
    
    -- Fallback to player object if Java Faction failed
    if playerFaction == "Nomad" and player.getFaction then
        local f = player:getFaction()
        if f then playerFaction = f:getName() end
    end

    local allied = AreFactionsAllied(playerFaction, owner)
    print(DEBUG_PREFIX .. " ZoneOwner=[" .. tostring(owner) .. "] MyFaction=[" .. tostring(playerFaction) .. "] OwnerSource=[" .. tostring(ownerSource) .. "] Allied=[" .. tostring(allied) .. "]")

    -- 4. APPLY BENEFITS
    if owner == playerFaction or allied then
        FactionBuffsActive = true
        FactionBuffZoneType = zone.zoneType or "Standard"

        -- Ask the server to validate position/faction and apply authoritative XP/stats.
        if sendClientCommand then
            sendClientCommand(player, "FW_Buffs", "RequestAuthorityTick", {})
        else
            print(DEBUG_PREFIX .. " sendClientCommand unavailable; server-authoritative buff request was not sent")
        end

        print("DEBUG XP: Requested server-authoritative faction buff tick in " .. tostring(zone.zoneType) .. " zone.")

        if ZombRand(5) == 0 then
             local msg = getText("IGUI_FactionWar_Training")
             if not msg or msg == "IGUI_FactionWar_Training" then msg = "Training in Progress... (+XP)" end
             player:setHaloNote(msg, 0, 255, 0, 300)
        end
    else
        debugLog("no benefits: owner/player faction mismatch")
    end
end

-- Run logic every 120 ticks (approx 2 seconds at 60 FPS)
Events.OnTick.Add(function()
    buffTickTimer = buffTickTimer + 1
    if buffTickTimer >= 1420 then
        local player = getPlayer()
        if player then 
            ApplyFactionBenefits(player)
        end
        buffTickTimer = 0
    end
end)

if ModData and ModData.request then
    ModData.request("FactionWarZones")
    print(DEBUG_PREFIX .. " requested FactionWarZones ModData")
end
