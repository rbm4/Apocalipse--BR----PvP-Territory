-- =======================================================
-- FactionControlRank.lua (SERVER)
-- Tracks faction control points from owned territory.
-- =======================================================
if not isServer() then
    return
end

local RANK_MODDATA_KEY = "FactionControlRank"
local RANK_EXPORT_FILE = "FactionControlRank.csv"
local MAX_EXPORTED_FACTIONS = 10

local function InitRankData()
    if not ModData then
        return nil
    end

    local rankData = ModData.get(RANK_MODDATA_KEY)
    if not rankData then
        rankData = {
            factions = {},
            ranking = {},
            lastUpdatedWorldAgeHours = 0
        }
        ModData.add(RANK_MODDATA_KEY, rankData)
        print("SERVER: FactionControlRank created.")
    end

    if not rankData.factions then
        rankData.factions = {}
    end
    if not rankData.ranking then
        rankData.ranking = {}
    end

    return rankData
end

local function IsValidFactionName(factionName)
    return factionName and factionName ~= "" and factionName ~= "Neutral" and factionName ~= "Nomad"
end

local function BuildRanking(rankData)
    local ranking = {}

    for factionName, points in pairs(rankData.factions or {}) do
        table.insert(ranking, {
            faction = factionName,
            points = tonumber(points) or 0,
            controlledZones = 0
        })
    end

    local allZoneStatus = ModData.get("FactionWarZones") or {}
    for _, zData in pairs(allZoneStatus) do
        if zData and IsValidFactionName(zData.owner) then
            local found = false
            for _, entry in ipairs(ranking) do
                if entry.faction == zData.owner then
                    entry.controlledZones = entry.controlledZones + 1
                    found = true
                    break
                end
            end
            if not found then
                table.insert(ranking, {
                    faction = zData.owner,
                    points = 0,
                    controlledZones = 1
                })
            end
        end
    end

    table.sort(ranking, function(a, b)
        if a.points == b.points then
            return a.faction < b.faction
        end
        return a.points > b.points
    end)

    return ranking
end

local function UpdateControlPoints()
    local rankData = InitRankData()
    if not rankData then
        return
    end

    local allZoneStatus = ModData.get("FactionWarZones") or {}
    local changed = false

    for _, zData in pairs(allZoneStatus) do
        if zData and IsValidFactionName(zData.owner) then
            rankData.factions[zData.owner] = (tonumber(rankData.factions[zData.owner]) or 0) + 1
            changed = true
        end
    end

    if changed then
        local gameTime = getGameTime()
        rankData.lastUpdatedWorldAgeHours = gameTime and gameTime:getWorldAgeHours() or rankData.lastUpdatedWorldAgeHours
        rankData.ranking = BuildRanking(rankData)
        ModData.add(RANK_MODDATA_KEY, rankData)
        if ModData.transmit then
            ModData.transmit(RANK_MODDATA_KEY)
        end
    end
end

local function EscapeCsv(value)
    local text = tostring(value or "")
    if string.find(text, '[,"\r\n]') then
        text = '"' .. string.gsub(text, '"', '""') .. '"'
    end
    return text
end

local function FlushRankFile()
    local rankData = InitRankData()
    if not rankData then
        return
    end

    rankData.ranking = BuildRanking(rankData)
    ModData.add(RANK_MODDATA_KEY, rankData)

    local writer = getFileWriter(RANK_EXPORT_FILE, true, false)
    if not writer then
        print("FACTION WAR: Could not open rank export file: " .. RANK_EXPORT_FILE)
        return
    end

    writer:writeln("rank,faction,points,controlledZones")
    for i, entry in ipairs(rankData.ranking) do
        if i > MAX_EXPORTED_FACTIONS then
            break
        end
        writer:writeln(table.concat({
            tostring(i),
            EscapeCsv(entry.faction),
            tostring(entry.points or 0),
            tostring(entry.controlledZones or 0)
        }, ","))
    end
    writer:close()

    print("FACTION WAR: Flushed top faction control ranks to " .. RANK_EXPORT_FILE)
end

Events.OnInitGlobalModData.Add(InitRankData)
Events.EveryOneMinute.Add(UpdateControlPoints)
Events.EveryHours.Add(FlushRankFile)
