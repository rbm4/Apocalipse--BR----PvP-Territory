-- =======================================================
-- FactionWarConquestDeaths.lua (SERVER)
-- Tracks temporary conquest-presence exclusions after death.
-- =======================================================
if not isServer() then
    return {}
end

if FactionWarConquestDeaths then
    return FactionWarConquestDeaths
end

local ConquestDeaths = {}
FactionWarConquestDeaths = ConquestDeaths

local MODDATA_KEY = "FactionWarConquestDeaths"
local COOLDOWN_SECONDS = 30 * 60
local HALO_THROTTLE_SECONDS = 10
local haloCooldowns = {}
local recentDeathKeys = {}

local function nowSeconds()
    if getTimestamp then
        return getTimestamp()
    end
    if getTimeInMillis then
        return math.floor(getTimeInMillis() / 1000)
    end
    return math.floor(os.time())
end

local function getData()
    local data = ModData.get(MODDATA_KEY)
    if not data then
        data = {}
        ModData.add(MODDATA_KEY, data)
    end
    return data
end

local function getUsername(player)
    if player and player.getUsername then
        return player:getUsername()
    end
    return nil
end

local function getSteamID(player)
    if player and player.getSteamID then
        local ok, steamID = pcall(function()
            return player:getSteamID()
        end)
        if ok and steamID then
            return tostring(steamID)
        end
    end
    return nil
end

local function getFactionName(player)
    if not player then
        return "Nomad"
    end
    local username = getUsername(player)
    if username and Faction and Faction.getPlayerFaction then
        local fac = Faction.getPlayerFaction(username)
        if fac then
            local tag = fac:getTag()
            if tag and tag ~= "" then
                return tag
            end
            local name = fac:getName()
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

local function getConquestZoneAtXY(x, y)
    if FactionZones and FactionZones.List then
        for _, zone in ipairs(FactionZones.List) do
            local inX = (x >= zone.x1 and x <= zone.x2)
            local inY = (y >= zone.y1 and y <= zone.y2)
            if inX and inY then
                return zone
            end
        end
    end

    local customZones = ModData.get("FactionZoneDefinitions") or {}
    for id, zone in pairs(customZones) do
        local x1 = tonumber(zone.x1)
        local y1 = tonumber(zone.y1)
        local x2 = tonumber(zone.x2)
        local y2 = tonumber(zone.y2)
        local z1 = tonumber(zone.z1)
        local z2 = tonumber(zone.z2)
        if x1 and y1 and x2 and y2 then
            local inX = (x >= x1 and x <= x2)
            local inY = (y >= y1 and y <= y2)
            if inX and inY then
                return {
                    id = id,
                    name = zone.name,
                    x1 = x1,
                    y1 = y1,
                    x2 = x2,
                    y2 = y2,
                    z1 = z1,
                    z2 = z2
                }
            end
        end
    end

    return nil
end

local function isActiveConquest(status)
    if not status then
        return false
    end
    return (tonumber(status.progress) or 0) > 0
        or status.attacker ~= nil
        or status.isContested == true
        or status.wasUnderAttack == true
end

function ConquestDeaths.cleanup()
    local data = getData()
    local now = nowSeconds()
    local changed = false

    for zoneID, zoneEntries in pairs(data) do
        if type(zoneEntries) == "table" then
            for username, entry in pairs(zoneEntries) do
                if type(entry) ~= "table" or (tonumber(entry.expiresAt) or 0) <= now then
                    zoneEntries[username] = nil
                    changed = true
                end
            end
        else
            data[zoneID] = nil
            changed = true
        end
    end

    if changed then
        ModData.add(MODDATA_KEY, data)
    end
end

function ConquestDeaths.isPlayerExcluded(player, zoneID)
    local username = getUsername(player)
    if not username or not zoneID then
        return false
    end

    local data = getData()
    local zoneEntries = data[tostring(zoneID)]
    local entry = zoneEntries and zoneEntries[username]
    if not entry then
        return false
    end

    if (tonumber(entry.expiresAt) or 0) <= nowSeconds() then
        zoneEntries[username] = nil
        ModData.add(MODDATA_KEY, data)
        return false
    end

    return true
end

function ConquestDeaths.showCooldownHalo(player, zoneID)
    local username = getUsername(player)
    if not username or not zoneID then
        return
    end

    local now = nowSeconds()
    local haloKey = tostring(zoneID) .. ":" .. username
    if haloCooldowns[haloKey] and (now - haloCooldowns[haloKey]) < HALO_THROTTLE_SECONDS then
        return
    end
    haloCooldowns[haloKey] = now

    local data = getData()
    local entry = data[tostring(zoneID)] and data[tostring(zoneID)][username]
    local remaining = 0
    if entry then
        remaining = math.max(1, math.ceil(((tonumber(entry.expiresAt) or now) - now) / 60))
    end

    if sendServerCommand then
        sendServerCommand(player, "FW_Msg", "ConquestDeathCooldown", {
            remaining = remaining
        })
    end
end

function ConquestDeaths.recordPlayerDeath(player)
    if not player or not player.getX then
        return
    end

    local username = getUsername(player)
    if not username then
        return
    end

    local now = nowSeconds()
    local deathKey = username .. ":" .. tostring(math.floor(now / 2))
    if recentDeathKeys[deathKey] then
        return
    end
    recentDeathKeys[deathKey] = true

    local zone = getConquestZoneAtXY(player:getX(), player:getY())
    if not zone or not zone.id then
        return
    end

    local allZoneStatus = ModData.get("FactionWarZones") or {}
    local status = allZoneStatus[zone.id] or allZoneStatus[tostring(zone.id)]
    if not isActiveConquest(status) then
        return
    end

    local data = getData()
    local zoneID = tostring(zone.id)
    data[zoneID] = data[zoneID] or {}
    data[zoneID][username] = {
        username = username,
        steamID = getSteamID(player),
        faction = getFactionName(player),
        zoneID = zoneID,
        zoneName = zone.name,
        diedAt = now,
        expiresAt = now + COOLDOWN_SECONDS
    }

    ModData.add(MODDATA_KEY, data)
    print("FACTION WAR: " .. username .. " excluded from conquest presence in " .. tostring(zone.name) .. " for 30 minutes after death.")
end

local function OnPlayerDeath(player)
    ConquestDeaths.recordPlayerDeath(player)
end

Events.OnPlayerDeath.Add(OnPlayerDeath)
Events.OnCharacterDeath.Add(function(character)
    if character and character.getUsername then
        ConquestDeaths.recordPlayerDeath(character)
    end
end)
Events.EveryOneMinute.Add(ConquestDeaths.cleanup)

return ConquestDeaths
