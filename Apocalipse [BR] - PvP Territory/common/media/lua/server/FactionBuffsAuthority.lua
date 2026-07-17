-- =======================================================
-- FILE: media/lua/server/FactionBuffsAuthority.lua
-- DESCR: Server-authoritative stat and XP processing for faction territory buffs
-- =======================================================

if isClient() then return end

local MODULE = "FW_Buffs"
local COMMAND_REQUEST_TICK = "RequestAuthorityTick"
local REWARD_COOLDOWN_MS = 10000
local lastRewardAtByUsername = {}
local DEBUG_PREFIX = "FACTION BUFFS AUTH:"

print(DEBUG_PREFIX .. " FactionBuffsAuthority.lua loaded")

local function debugLog(message)
    print(DEBUG_PREFIX .. " " .. tostring(message))
end

local function sendBuffStatus(player, active, zoneType, reason)
    if sendServerCommand and player then
        sendServerCommand(player, MODULE, "Status", {
            active = active == true,
            zoneType = zoneType or "Standard",
            reason = reason or ""
        })
    end
end

local ZONE_TRAINING = {
    Standard = {
        zonePerk = function() return Perks.FW_ZoneStandard end,
        vanilla = {
            { perk = function() return Perks.Fitness end, multiplier = 1.0 },
            { perk = function() return Perks.Strength end, multiplier = 1.0 },
        }
    },
    Armory = {
        zonePerk = function() return Perks.FW_ZoneArmory end,
        vanilla = {
            { perk = function() return Perks.Aiming end, multiplier = 1.5 },
            { perk = function() return Perks.Reloading end, multiplier = 1.5 },
        }
    },
    Hospital = {
        zonePerk = function() return Perks.FW_ZoneHospital end,
        vanilla = {
            { perk = function() return Perks.Doctor end, multiplier = 1.5 },
        }
    },
    Workshop = {
        zonePerk = function() return Perks.FW_ZoneWorkshop end,
        vanilla = {
            { perk = function() return Perks.Woodwork end, multiplier = 1.5 },
            { perk = function() return Perks.Mechanics end, multiplier = 1.5 },
            { perk = function() return Perks.MetalWelding end, multiplier = 1.5 },
        }
    },
    Bunker = {
        zonePerk = function() return Perks.FW_ZoneBunker end,
        vanilla = {
            { perk = function() return Perks.Combat end, multiplier = 1.5 },
            { perk = function() return Perks.Firearm end, multiplier = 1.5 },
        }
    },
    Industrial = {
        zonePerk = function() return Perks.FW_ZoneIndustrial end,
        vanilla = {
            { perk = function() return Perks.Glassmaking end, multiplier = 1.5 },
            { perk = function() return Perks.Maintenance end, multiplier = 1.5 },
            { perk = function() return Perks.Strength end, multiplier = 1.5 },
        }
    },
    Estacao = {
        zonePerk = function() return Perks.FW_ZoneEstacao end,
        vanilla = {
            { perk = function() return Perks.Nimble end, multiplier = 1.5 },
            { perk = function() return Perks.Sneak end, multiplier = 1.5 },
        }
    },
    Umbrella = {
        zonePerk = function() return Perks.FW_ZoneUmbrella end,
        vanilla = {
            { perk = function() return Perks.Electricity end, multiplier = 1.5 },
            { perk = function() return Perks.Doctor end, multiplier = 1.5 },
            { perk = function() return Perks.MetalWelding end, multiplier = 1.5 },
        }
    },
    Posto = {
        zonePerk = function() return Perks.FW_ZonePosto end,
        vanilla = {
            { perk = function() return Perks.Mechanics end, multiplier = 1.5 },
        }
    },
}

local function isPlayerInZone(player, zone)
    if not player or not zone then
        return false
    end

    local x1 = tonumber(zone.x1)
    local y1 = tonumber(zone.y1)
    local x2 = tonumber(zone.x2)
    local y2 = tonumber(zone.y2)
    local z1 = tonumber(zone.z1)
    local z2 = tonumber(zone.z2)
    if not x1 or not y1 or not x2 or not y2 then
        return false
    end

    local x = player:getX()
    local y = player:getY()
    local z = player:getZ()
    local inX = x >= x1 and x <= x2
    local inY = y >= y1 and y <= y2
    local inZ = true
    if z1 and z2 then
        inZ = z >= z1 and z <= z2
    end

    return inX and inY and inZ
end

local function getServerZoneAt(player)
    if FactionZones and FactionZones.List then
        for _, zone in ipairs(FactionZones.List) do
            if isPlayerInZone(player, zone) then
                return zone
            end
        end
    end

    if not ModData then
        return nil
    end

    local definitions = ModData.get("FactionZoneDefinitions") or {}
    for id, zone in pairs(definitions) do
        if isPlayerInZone(player, zone) then
            return {
                id = id,
                name = zone.name,
                x1 = zone.x1,
                y1 = zone.y1,
                x2 = zone.x2,
                y2 = zone.y2,
                z1 = zone.z1,
                z2 = zone.z2,
                zoneType = zone.zoneType or "Standard"
            }
        end
    end

    return nil
end

local function getZoneOwner(zoneID)
    if not ModData then
        return nil
    end

    local status = ModData.get("FactionWarZones")
    if status and status[zoneID] then
        return status[zoneID].owner
    end

    local definitions = ModData.get("FactionZoneDefinitions")
    if definitions and definitions[zoneID] then
        return definitions[zoneID].owner
    end

    return nil
end

local function areFactionsAllied(fac1, fac2)
    if not fac1 or not fac2 or fac1 == "Nomad" or fac2 == "Nomad" or fac1 == "Neutral" or fac2 == "Neutral" then
        return false
    end
    if fac1 == fac2 then
        return true
    end
    if not ModData then
        return false
    end

    local alliances = ModData.get("FactionAlliances") or {}
    return alliances[fac1] and alliances[fac1][fac2] == true
end

local function getPlayerFactionName(player)
    if not player then
        return "Nomad"
    end

    local username = player:getUsername()
    if Faction and Faction.getPlayerFaction then
        local faction = Faction.getPlayerFaction(username)
        if faction then
            local tag = faction:getTag()
            if tag and tag ~= "" then
                return tag
            end

            local name = faction:getName()
            if name and name ~= "" then
                return name
            end
        end
    end

    if player.getFaction then
        local faction = player:getFaction()
        if faction then
            local name = faction:getName()
            if name and name ~= "" then
                return name
            end
        end
    end

    return "Nomad"
end

local function canRewardNow(player)
    local username = player:getUsername() or tostring(player)
    local now = getTimestampMs and getTimestampMs() or 0
    local lastRewardAt = lastRewardAtByUsername[username] or 0

    if now > 0 and now - lastRewardAt < REWARD_COOLDOWN_MS then
        return false
    end

    lastRewardAtByUsername[username] = now
    return true
end

local function addTrainingXp(player, perk, amount)
    if not perk or amount <= 0 then
        return
    end

    if addXpNoMultiplier then
        addXpNoMultiplier(player, perk, amount)
    else
        player:getXp():AddXP(perk, amount)
    end
end

local function applySurvivalBuffs(player, zoneType)
    local stats = player:getStats()
    local enduRegen = 0.0007
    local stressDecay = 0.002
    local hungerDecay = 0.00002

    if zoneType == "Hospital" then
        enduRegen = 0.002
        local bodyDamage = player:getBodyDamage()
        if bodyDamage:getOverallBodyHealth() < 100 then
            bodyDamage:AddGeneralHealth(0.5)
        end
    end

    if stats:get(CharacterStat.ENDURANCE) < 1.0 then
        stats:set(CharacterStat.ENDURANCE, stats:get(CharacterStat.ENDURANCE) + enduRegen)
    end
    if stats:get(CharacterStat.STRESS) > 0 then
        stats:set(CharacterStat.STRESS, stats:get(CharacterStat.STRESS) - stressDecay)
    end
    if stats:get(CharacterStat.HUNGER) > 0 then
        stats:set(CharacterStat.HUNGER, stats:get(CharacterStat.HUNGER) - hungerDecay)
    end
end

local function applyTrainingXp(player, zoneType)
    local xpAmount = (SandboxVars.FactionWar and SandboxVars.FactionWar.PassiveXPAmount) or 0.2
    if xpAmount <= 0 then
        return
    end

    local training = ZONE_TRAINING[zoneType] or ZONE_TRAINING.Standard
    if training.zonePerk then
        addTrainingXp(player, training.zonePerk(), xpAmount)
    end

    for _, reward in ipairs(training.vanilla or {}) do
        addTrainingXp(player, reward.perk(), xpAmount * (reward.multiplier or 1.0))
    end

    print("FACTION BUFFS AUTH: +" .. tostring(xpAmount) .. " base zone XP applied to " .. tostring(player:getUsername()) .. " in " .. tostring(zoneType) .. " zone.")
end

local function processAuthorityTick(player)
    if not player or player:isDead() then
        debugLog("skipped: no player or dead player")
        return
    end

    if not canRewardNow(player) then
        debugLog("skipped cooldown for " .. tostring(player:getUsername()))
        return
    end

    local zone = getServerZoneAt(player)
    if not zone then
        debugLog("inactive: no server zone for " .. tostring(player:getUsername()) .. " at x=" .. tostring(math.floor(player:getX())) .. " y=" .. tostring(math.floor(player:getY())) .. " z=" .. tostring(player:getZ()))
        sendBuffStatus(player, false, nil, "no-zone")
        return
    end

    local owner = getZoneOwner(zone.id)
    if not owner or owner == "Neutral" then
        debugLog("inactive: zone=" .. tostring(zone.id) .. " owner=" .. tostring(owner))
        sendBuffStatus(player, false, zone.zoneType, "neutral-or-missing-owner")
        return
    end

    local playerFaction = getPlayerFactionName(player)
    local allied = areFactionsAllied(playerFaction, owner)
    debugLog("zone=" .. tostring(zone.id) .. " owner=[" .. tostring(owner) .. "] playerFaction=[" .. tostring(playerFaction) .. "] allied=[" .. tostring(allied) .. "]")
    if owner ~= playerFaction and not allied then
        sendBuffStatus(player, false, zone.zoneType, "faction-mismatch")
        return
    end

    local zoneType = zone.zoneType or "Standard"
    applySurvivalBuffs(player, zoneType)
    applyTrainingXp(player, zoneType)
    sendBuffStatus(player, true, zoneType, "applied")
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= COMMAND_REQUEST_TICK then
        return
    end

    debugLog("received RequestAuthorityTick from " .. tostring(player and player:getUsername()))
    processAuthorityTick(player)
end

Events.OnClientCommand.Add(onClientCommand)

