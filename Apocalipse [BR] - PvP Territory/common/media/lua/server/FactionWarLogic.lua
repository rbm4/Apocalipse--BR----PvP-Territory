-- =======================================================
-- FILE 2: FactionWarLogic.lua (SERVER) - UPDATE 4
-- =======================================================
if not isServer() then
    return
end

local RegionManagerServer = require "RegionManager_Server"

local tickCounter = 0
local syncTimer = 0
local zonesToProcess = {} -- GLOBAL CACHE
local alertCooldowns = {} -- Rate-limit capture alerts: {zoneID = worldAgeHours}

-- 1. INITIALIZE DATA
local function InitFactionData()
    if not ModData then
        return
    end
    if not RegionManagerServer then
        RegionManagerServer = require "RegionManager_Server"
    end
    if not ModData.get("FactionWarZones") then
        ModData.add("FactionWarZones", {})
        print("SERVER: FactionWarZones created.")
    end
    if not ModData.get("FactionZoneDefinitions") then
        ModData.add("FactionZoneDefinitions", {})
        print("SERVER: FactionZoneDefinitions created.")
    end
    if not ModData.get("FactionLastSeen") then
        ModData.add("FactionLastSeen", {})
        print("SERVER: FactionLastSeen created.")
    end
    if not ModData.get("FactionAlliances") then
        ModData.add("FactionAlliances", {})
        print("SERVER: FactionAlliances created.")
    end
    if not ModData.get("FactionAllianceInvites") then
        ModData.add("FactionAllianceInvites", {})
        print("SERVER: FactionAllianceInvites created.")
    end
    if not ModData.get("FactionWarPayday") then
        ModData.add("FactionWarPayday", {
            lastPaidDay = -1
        })
        print("SERVER: FactionWarPayday created.")
    end
end
InitFactionData()

local function AreFactionsAllied(fac1, fac2)
    if not fac1 or not fac2 or fac1 == "Nomad" or fac2 == "Nomad" or fac1 == "Neutral" or fac2 == "Neutral" then
        return false
    end
    if fac1 == fac2 then
        return true
    end
    local alliances = ModData.get("FactionAlliances") or {}
    if alliances[fac1] and alliances[fac1][fac2] then
        return true
    end
    return false
end

local function CountActiveAlliances(alliances, factionName, ignoredFaction)
    local count = 0
    local list = alliances and alliances[factionName]
    if not list then
        return 0
    end
    for alliedFaction, state in pairs(list) do
        if state == true and alliedFaction ~= ignoredFaction then
            count = count + 1
        end
    end
    return count
end

local function CanCreateAlliance(alliances, factionA, factionB)
    if not factionA or not factionB or factionA == factionB then
        return false
    end
    if CountActiveAlliances(alliances, factionA, factionB) > 0 then
        return false
    end
    if CountActiveAlliances(alliances, factionB, factionA) > 0 then
        return false
    end
    return true
end

-- 2. REFRESH LIST (Fixes "Zone Not Detected")
local function RefreshZoneList()
    zonesToProcess = {}

    -- 1. Hardcoded Zones
    if FactionZones and FactionZones.List then
        for _, z in ipairs(FactionZones.List) do
            table.insert(zonesToProcess, z)
        end
    end

    -- 2. Custom Zones
    local customZones = ModData.get("FactionZoneDefinitions") or {}
    for id, z in pairs(customZones) do
        -- Force number conversion
        local x1 = tonumber(z.x1)
        local y1 = tonumber(z.y1)
        local x2 = tonumber(z.x2)
        local y2 = tonumber(z.y2)
        local z1 = tonumber(z.z1)
        local z2 = tonumber(z.z2)

        if x1 and y1 and x2 and y2 then
            local capTime = (SandboxVars.FactionWar and SandboxVars.FactionWar.CaptureTime) or 100

            table.insert(zonesToProcess, {
                id = id,
                name = z.name,
                x1 = x1,
                y1 = y1,
                x2 = x2,
                y2 = y2,
                z1 = z1,
                z2 = z2,
                captureTime = capTime,
                owner = z.owner or "Neutral",
                lootX = z.lootX,
                lootY = z.lootY,
                lootZ = z.lootZ,
                zoneType = z.zoneType or "Standard"
            })

            -- [DEBUG] Print loaded crate info
            if z.lootX then
                print("SERVER DEBUG: Zone '" .. z.name .. "' loaded with LINKED CRATE at " .. z.lootX .. "," .. z.lootY)
            else
                print("SERVER DEBUG: Zone '" .. z.name .. "' loaded (NO CRATE LINKED)")
            end
        end
    end
    print("SERVER: Refreshed Zone List. Total Zones Active: " .. #zonesToProcess)
end

-- 3. HELPER: Get Faction Tag
local function GetRealFaction(player)
    if not player then
        return "Nomad"
    end
    local username = player:getUsername()

    -- 1. Try Java Faction class (MP standard)
    if Faction and Faction.getPlayerFaction then
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

    -- 2. Try player object faction property
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

-- 4. HELPER: Get Color
local function GetFactionColorRaw(factionName)
    if factionName == "Nomad" or factionName == "Neutral" then
        return {
            r = 0.5,
            g = 0.5,
            b = 0.5
        }
    end

    local r, g, b = 0.8, 0.1, 0.1 -- Default Red

    pcall(function()
        if Faction and Faction.getFactions then
            local factions = Faction.getFactions()
            if factions then
                for i = 0, factions:size() - 1 do
                    local fac = factions:get(i)
                    if fac:getName() == factionName or fac:getTag() == factionName then
                        if fac.getTagColor then
                            local col = fac:getTagColor()
                            if col then
                                r, g, b = col:getR(), col:getG(), col:getB()
                            end
                        end
                    end
                end
            end
        end
    end)

    return {
        r = r,
        g = g,
        b = b
    }
end

-- Helper to split a string by semicolons/commas into a list of items
local function ParseCustomItems(itemString)
    local items = {}
    if not itemString or itemString == "" then
        return items
    end
    for item in string.gmatch(itemString, "[^;,]+") do
        item = item:match("^%s*(.-)%s*$") -- Trim spaces
        if item ~= "" then
            table.insert(items, item)
        end
    end
    return items
end

-- Helper to identify which zone a player is currently in on the server
local function GetZoneForPlayer(player)
    local x = player:getX()
    local y = player:getY()
    local z = player:getZ()
    for _, zone in ipairs(zonesToProcess) do
        local inX = (x >= zone.x1 and x <= zone.x2)
        local inY = (y >= zone.y1 and y <= zone.y2)
        local inZ = true
        if zone.z1 and zone.z2 then
            inZ = (z >= zone.z1 and z <= zone.z2)
        end
        if inX and inY and inZ then
            return zone
        end
    end
    return nil
end

-- 5. CAPTURE & LOOT LOGIC LOOP
local function CheckZoneCaptureProgress()
    if #zonesToProcess == 0 then
        RefreshZoneList()
    end

    local allZoneStatus = ModData.get("FactionWarZones")
    if not allZoneStatus then
        allZoneStatus = {}
    end

    local dataChanged = false

    -- [SETTINGS] Load Sandbox Vars & Convert Dropdowns
    local sb = SandboxVars.FactionWar
    local doAnnounce = (sb and sb.AnnounceCapture)

    local Multipliers = {
        [1] = 0.25, -- Very Slow
        [2] = 0.50, -- Slow
        [3] = 1.00, -- Normal
        [4] = 2.00, -- Fast
        [5] = 4.00 -- Blitz
    }

    local capIndex = (sb and sb.CapturePointsPerTick) or 3
    local decIndex = (sb and sb.DecaySpeed) or 3

    local pointsPerTick = Multipliers[capIndex] or 1.0
    local decaySpeed = Multipliers[decIndex] or 1.0

    -- [OPTIMIZATION] Pre-scan online players once per tick and calculate zone occupation counts,
    -- while simultaneously updating faction activity timers in real-time.
    local zoneFactionPlayers = {}
    local lastSeenData = ModData.get("FactionLastSeen") or {}
    local lastSeenChanged = false
    local worldAge = getGameTime():getWorldAgeHours()

    local onlinePlayers = getOnlinePlayers()
    if onlinePlayers then
        for i = 0, onlinePlayers:size() - 1 do
            local player = onlinePlayers:get(i)
            if player and type(player.getX) == "function" and not player:isDead() and player:getHealth() > 0 then
                -- Track player faction online activity in real-time (helps offline protection accuracy)
                local myFaction = GetRealFaction(player)
                if myFaction and myFaction ~= "Nomad" then
                    if not lastSeenData[myFaction] or (worldAge - lastSeenData[myFaction]) > 0.1 then
                        lastSeenData[myFaction] = worldAge
                        lastSeenChanged = true
                    end
                end

                local zone = GetZoneForPlayer(player)
                if zone then
                    local zoneID = zone.id
                    if not zoneFactionPlayers[zoneID] then
                        zoneFactionPlayers[zoneID] = {}
                    end
                    local factionKey = myFaction or "Nomad"
                    zoneFactionPlayers[zoneID][factionKey] = (zoneFactionPlayers[zoneID][factionKey] or 0) + 1

                    if tickCounter % 50 == 0 then
                        print("DEBUG DETECT: Player '" .. player:getUsername() .. "' INSIDE " .. zone.name)
                    end
                end
            end
        end
    end

    if lastSeenChanged then
        ModData.add("FactionLastSeen", lastSeenData)
        if ModData.transmit then
            ModData.transmit("FactionLastSeen")
        end
    end

    for _, zone in ipairs(zonesToProcess) do
        local zoneID = zone.id

        -- Init Status
        if not allZoneStatus[zoneID] then
            local startColor = GetFactionColorRaw(zone.owner or "Neutral")
            allZoneStatus[zoneID] = {
                owner = zone.owner or "Neutral",
                progress = 0,
                name = zone.name,
                col = startColor
            }
            dataChanged = true
        end
        local data = allZoneStatus[zoneID]

        local playersInZone = zoneFactionPlayers[zoneID] or {}

        local defenderName = data.owner or "Neutral"
        local attackerName = nil
        local attackersCount = 0

        for faction, count in pairs(playersInZone) do
            if faction ~= defenderName and faction ~= "Nomad" and count > 0 then
                if not AreFactionsAllied(faction, defenderName) then
                    attackerName = faction
                    attackersCount = attackersCount + count
                end
            end
        end

        -- Check defenders (owner + allies)
        local defendersCount = playersInZone[defenderName] or 0
        for faction, count in pairs(playersInZone) do
            if faction ~= defenderName and faction ~= "Nomad" and count > 0 then
                if AreFactionsAllied(faction, defenderName) then
                    defendersCount = defendersCount + count
                end
            end
        end

        local isContested = (defendersCount > 0 and attackerName ~= nil)

        -- If multiple attackers from different non-allied factions are in the zone, it's also contested
        local otherAttackers = 0
        for faction, count in pairs(playersInZone) do
            if faction ~= defenderName and faction ~= "Nomad" and count > 0 then
                if not AreFactionsAllied(faction, defenderName) then
                    otherAttackers = otherAttackers + 1
                end
            end
        end
        if otherAttackers > 1 then
            isContested = true
        end

        -- Update isContested in sync data
        if data.isContested ~= isContested then
            data.isContested = isContested
            dataChanged = true
        end

        -- [NEW] Offline Protection Logic
        local isProtected = false
        if sb and sb.OfflineProtection ~= false and defenderName ~= "Neutral" then
            local defenderOnline = false
            if onlinePlayers then
                for i = 0, onlinePlayers:size() - 1 do
                    local p = onlinePlayers:get(i)
                    local f = GetRealFaction(p)
                    if f == defenderName then
                        defenderOnline = true
                        break
                    end
                end
            end
            if not defenderOnline then
                isProtected = true

                -- [NEW] Check Expiry Timer
                local expiryHours = sb.OfflineProtectionExpiry or 24
                if expiryHours > 0 then
                    local lastSeenData = ModData.get("FactionLastSeen") or {}
                    local lastSeen = lastSeenData[defenderName] or getGameTime():getWorldAgeHours()
                    local hoursInactive = getGameTime():getWorldAgeHours() - lastSeen

                    if hoursInactive >= expiryHours then
                        isProtected = false -- Protection expired!
                    end
                end
            end
        end

        if data.isProtected ~= isProtected then
            data.isProtected = isProtected
            dataChanged = true
        end

        -- Capture / Decay
        if attackerName and not isContested and not isProtected then
            local oldProgress = data.progress

            -- Apply Multiplier
            data.progress = data.progress + (attackersCount * pointsPerTick)
            data.progress = math.min(data.progress, zone.captureTime)

            if data.progress ~= oldProgress then
                dataChanged = true
            end

            if data.attacker ~= attackerName then
                data.attacker = attackerName
                dataChanged = true
            end

            -- -------------------------------------------------------
            -- [PHASE 1] CAPTURE ALERT: Notify Defenders
            -- Rate limited to once per 60 real seconds (worldAge hours)
            -- -------------------------------------------------------
            if not data.wasUnderAttack then
                local worldAge = getGameTime():getWorldAgeHours()
                local lastAlert = alertCooldowns[zoneID] or -999
                -- 60 seconds = 1/60 of an in-game hour (approx)
                if (worldAge - lastAlert) > (1 / 60) then
                    alertCooldowns[zoneID] = worldAge
                    if onlinePlayers then
                        for i = 0, onlinePlayers:size() - 1 do
                            local p = onlinePlayers:get(i)
                            local pFac = GetRealFaction(p)
                            if pFac == defenderName then
                                local msg = getText("IGUI_FactionWar_ZoneUnderAttack")
                                if not msg or msg == "IGUI_FactionWar_ZoneUnderAttack" then
                                    msg = "Alerta! %1 Esta sob ataque de %2!"
                                end
                                p:setHaloNote(msg:gsub("%%1", zone.name):gsub("%%2", attackerName), 255, 50, 50, 600)
                            end
                        end
                    end
                    -- Also broadcast a server-wide styled chat alert
                    if doAnnounce and defenderName ~= "Neutral" then
                        local msgTemplate = getText("IGUI_FactionWar_RadioAlertAttack")
                        if not msgTemplate or msgTemplate == "IGUI_FactionWar_RadioAlertAttack" then
                            msgTemplate = "[GUERRA DE FACCAO] %1 esta atacando a zona de %2: %3!"
                        end
                        local msg = msgTemplate:gsub("%%1", attackerName):gsub("%%2", defenderName):gsub("%%3",
                            zone.name)
                        sendServerCommand("FW_Msg", "RadioMsg", {
                            text = msg
                        })
                    end
                end
                data.wasUnderAttack = true
                dataChanged = true
            end

            if data.progress >= zone.captureTime then
                print("DEBUG WIN: Zone " .. zone.name .. " FLIPPED to " .. tostring(attackerName))

                -- [PHASE 2] RADIO-STYLE CAPTURE ANNOUNCEMENT
                local prevOwner = defenderName
                local flipMsg
                if prevOwner == "Neutral" then
                    local tpl = getText("IGUI_FactionWar_ZoneCapturedNeutral")
                    if not tpl or tpl == "IGUI_FactionWar_ZoneCapturedNeutral" then
                        tpl = "[ZONE CAPTURED] %1 has claimed %2!"
                    end
                    flipMsg = tpl:gsub("%%1", attackerName):gsub("%%2", zone.name)
                else
                    local tpl = getText("IGUI_FactionWar_ZoneCapturedEnemy")
                    if not tpl or tpl == "IGUI_FactionWar_ZoneCapturedEnemy" then
                        tpl = "[ZONE CAPTURED] %1 has seized %2 from %3!"
                    end
                    flipMsg = tpl:gsub("%%1", attackerName):gsub("%%2", zone.name):gsub("%%3", prevOwner)
                end
                sendServerCommand("FW_Msg", "RadioMsg", {
                    text = flipMsg
                })

                data.owner = attackerName
                data.progress = 0
                data.attacker = nil
                data.col = GetFactionColorRaw(attackerName)
                data.lastLootTime = -100 -- Reset loot timer on capture
                data.wasUnderAttack = false
                alertCooldowns[zoneID] = nil
                dataChanged = true
            end

        elseif not isContested and data.progress > 0 then
            local oldProgress = data.progress

            -- Apply Decay Multiplier
            data.progress = data.progress - decaySpeed
            if data.progress < 0 then
                data.progress = 0
            end

            if data.progress ~= oldProgress then
                dataChanged = true
            end

            if data.attacker ~= nil then
                data.attacker = nil
                dataChanged = true
            end

            -- Reset attack state if zone is no longer under attack
            if data.wasUnderAttack then
                data.wasUnderAttack = false
                dataChanged = true
            end
        elseif not attackerName then
            -- Nobody attacking - clear attack flag
            if data.wasUnderAttack then
                data.wasUnderAttack = false
                dataChanged = true
            end
            if data.attacker ~= nil then
                data.attacker = nil
                dataChanged = true
            end
        end

        -- Color Safety Check
        if not data.col then
            data.col = GetFactionColorRaw(data.owner)
            dataChanged = true
        end

        -- [NEW] REWARD CRATE REFILL LOGIC (FIXED)
        if data.owner ~= "Neutral" and zone.lootX then
            local worldAge = getGameTime():getWorldAgeHours()

            -- [FIX] -100 means "Loot is extremely overdue, spawn immediately!"
            if not data.lastLootTime then
                data.lastLootTime = -100
            end

            -- [DEBUG] Print status every 10 seconds
            if tickCounter % 600 == 0 then
                print("DEBUG LOOT: Zone " .. zone.name .. " owned by " .. data.owner .. ". Hours since loot: " ..
                          (worldAge - data.lastLootTime))
            end

            -- Check if 24 hours passed since last fill
            if (worldAge - data.lastLootTime) >= 24 then
                local sq = getCell():getGridSquare(zone.lootX, zone.lootY, zone.lootZ or 0)
                if sq then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local container = objs:get(i):getContainer()
                        if container then
                            -- [NEW] Advanced Custom Item Check (Supports multiple items split by commas or semicolons)
                            local customItem = sb.CustomCrateItem
                            local customList = ParseCustomItems(customItem)
                            local lootItem = "Base.Bullets9mmBox"

                            local isCustom = (#customList > 0)

                            if not isCustom then
                                if zone.zoneType == "Armory" then
                                    lootItem = "Base.Bullets9mmBox"
                                elseif zone.zoneType == "Hospital" then
                                    lootItem = "Base.FirstAidKit"
                                elseif zone.zoneType == "Workshop" then
                                    lootItem = "Base.NailsBox"
                                else
                                    local sType = sb.SalaryItemType or 1
                                    local itemMap = {
                                        [1] = "Base.Bullets9mmBox",
                                        [2] = "Base.ShotgunShellsBox",
                                        [3] = "Base.CannedCornBeef",
                                        [4] = "Base.FirstAidKit",
                                        [5] = "Base.NailsBox"
                                    }
                                    lootItem = itemMap[sType] or "Base.Bullets9mmBox"
                                end
                            end

                            -- FILL THE CRATE
                            -- Use the dedicated CrateLootAmount sandbox var (default: 15)
                            local crateCount = (sb.CrateLootAmount and sb.CrateLootAmount > 0) and sb.CrateLootAmount or
                                                   15
                            for _ = 1, crateCount do
                                if isCustom then
                                    lootItem = customList[ZombRand(#customList) + 1]
                                end
                                container:AddItem(lootItem)
                            end

                            -- Bonus variety items based on zone type
                            if sb.CrateBonusLoot ~= false then
                                if zone.zoneType == "Armory" then
                                    local armoryLoot = {"Base.Shotgun", "Base.Pistol", "Base.AssaultRifle",
                                                        "Base.ShotgunShellsBox", "Base.556Box", "Base.308Box",
                                                        "Base.9mmClip", "Base.M14Clip", "Base.ScopeSmall", "Base.Sling"}
                                    for _ = 1, ZombRand(4, 10) do
                                        container:AddItem(armoryLoot[ZombRand(#armoryLoot) + 1])
                                    end
                                elseif zone.zoneType == "Hospital" then
                                    local medicalLoot = {"Base.Bandage", "Base.Painkillers", "Base.Antibiotics",
                                                         "Base.FirstAidKit", "Base.Disinfectant", "Base.AlcoholWipes",
                                                         "Base.SutureNeedle", "Base.Tweezers"}
                                    for _ = 1, ZombRand(5, 13) do
                                        container:AddItem(medicalLoot[ZombRand(#medicalLoot) + 1])
                                    end
                                elseif zone.zoneType == "Workshop" then
                                    local toolsLoot = {"Base.DuctTape", "Base.Woodglue", "Base.Screws", "Base.Twine",
                                                       "Base.NailsBox", "Base.Hammer", "Base.Screwdriver", "Base.Saw",
                                                       "Base.WeldingMask", "Base.BlowTorch", "Base.Wire"}
                                    for _ = 1, ZombRand(5, 11) do
                                        container:AddItem(toolsLoot[ZombRand(#toolsLoot) + 1])
                                    end
                                else
                                    local standardLoot = {"Base.Bandage", "Base.Painkillers", "Base.Soda",
                                                          "Base.CannedBeans", "Base.CannedCorn", "Base.WaterBottle",
                                                          "Base.Cigarettes", "Base.Lighter"}
                                    for _ = 1, ZombRand(4, 9) do
                                        container:AddItem(standardLoot[ZombRand(#standardLoot) + 1])
                                    end
                                end
                            end

                            data.lastLootTime = worldAge
                            dataChanged = true
                            print(
                                "FACTION WAR: Restocked Reward Crate in " .. zone.name .. " (" .. crateCount .. "x " ..
                                    lootItem .. " + bonus items)")
                            break
                        end
                    end
                end
            end
        end
    end

    -- Save
    if dataChanged and ModData.transmit then
        ModData.add("FactionWarZones", allZoneStatus)
        ModData.transmit("FactionWarZones")
    end
end

-- 6. EVENTS
Events.OnTick.Add(function()
    local gameTime = getGameTime()
    if not gameTime then
        return
    end

    tickCounter = tickCounter + 1

    -- Check every ~1 second
    if tickCounter >= 60 then
        local status, err = pcall(CheckZoneCaptureProgress)
        if not status then
            print("FactionWar Error: " .. tostring(err))
        end
        tickCounter = 0
    end

    syncTimer = syncTimer + 1
    if syncTimer >= 300 then
        if ModData.transmit then
            RefreshZoneList()
            if ModData.get("FactionZoneDefinitions") then
                ModData.transmit("FactionZoneDefinitions")
            end
            if ModData.get("FactionWarZones") then
                ModData.transmit("FactionWarZones")
            end
        end
        syncTimer = 0
    end
end)

-- 7. CLIENT COMMANDS
local function OnClientCommand(module, command, player, args)
    if module ~= "FactionWar" then
        return
    end

    local access = player:getAccessLevel()
    local isAdmin = not (not access or access == "None" or access == "" or access == "none" or access == "Player")
    local isDebug = getCore() and getCore():getDebug() or false
    if isCoopHost and isCoopHost() then
        isAdmin = true
    end
    if isDebug then
        isAdmin = true
    end

    if command == "AddZone" then
        if not isAdmin then
            return
        end
        local id = "Custom_" .. tostring(os.time()) .. "_" .. tostring(ZombRand(1000))
        local customZones = ModData.get("FactionZoneDefinitions")
        if not customZones then
            customZones = {}
        end

        local x1 = tonumber(args.x1) or 0
        local y1 = tonumber(args.y1) or 0
        local x2 = tonumber(args.x2) or 0
        local y2 = tonumber(args.y2) or 0
        local z1 = tonumber(args.z1) or 0
        local z2 = tonumber(args.z2) or 0

        local minX = math.min(x1, x2)
        local maxX = math.max(x1, x2)
        local minY = math.min(y1, y2)
        local maxY = math.max(y1, y2)
        local minZ = math.min(z1, z2)
        local maxZ = math.max(z1, z2)

        local regionDef = {
            id = id,
            name = args.name,
            x1 = minX,
            y1 = minY,
            x2 = maxX,
            y2 = maxY,
            z = minZ,
            enabled = true,
            categories = {},
            customProperties = {
                pvpEnabled = true,
                announceEntry = false,
                announceExit = false
            }
        }

        RegionManagerServer.addHotRegion(player, regionDef)

        customZones[id] = {
            id = id,
            name = args.name,
            x1 = minX,
            y1 = minY,
            z1 = minZ,
            x2 = maxX,
            y2 = maxY,
            z2 = maxZ,
            captureTime = 100,
            owner = "Neutral",
            progress = 0,
            zoneType = args.zoneType or "Standard" -- [PHASE 4] Zone Types
        }

        if ModData.add then
            ModData.add("FactionZoneDefinitions", customZones)
            ModData.transmit("FactionZoneDefinitions")
        end

        RefreshZoneList()
        player:Say("Zona Salva! ID: " .. id)
    end

    if command == "DeleteZone" then
        if not isAdmin then
            return
        end
        local idToDelete = args.id
        local customZones = ModData.get("FactionZoneDefinitions")

        if customZones and customZones[idToDelete] then
            local zName = customZones[idToDelete].name
            customZones[idToDelete] = nil

            local statusData = ModData.get("FactionWarZones")
            if statusData and statusData[idToDelete] then
                statusData[idToDelete] = nil
                ModData.add("FactionWarZones", statusData)
                ModData.transmit("FactionWarZones")
            end

            ModData.add("FactionZoneDefinitions", customZones)
            ModData.transmit("FactionZoneDefinitions")

            RefreshZoneList()
            local regionDef = {
                originalId = idToDelete
            }
            RegionManagerServer.deleteHotRegion(player,regionDef)
            player:Say("Zona '" .. zName .. "' Deletada.")
        else
            player:Say("Error: Zone ID nao encontrado.")
        end
    end

    if command == "RenameZone" then
        if not isAdmin then
            return
        end
        local id = args.id
        local newName = args.name
        local customZones = ModData.get("FactionZoneDefinitions")

        local regionDef = {
            id = id,
            name = newName,
            x1 = args.x1,
            y1 = args.y1,
            x2 = args.x2,
            y2 = args.y2,
            z = 0,
            enabled = true,
            categories = {},
            customProperties = {
                pvpEnabled = true,
                announceEntry = false,
                announceExit = false
            }
        }

        RegionManagerServer.updateHotRegion(player, regionDef)

        if customZones and customZones[id] then
            local oldName = customZones[id].name
            customZones[id].name = newName
            ModData.add("FactionZoneDefinitions", customZones)
            ModData.transmit("FactionZoneDefinitions")

            local statusData = ModData.get("FactionWarZones")
            if statusData and statusData[id] then
                statusData[id].name = newName
                ModData.add("FactionWarZones", statusData)
                ModData.transmit("FactionWarZones")
            end

            RefreshZoneList()
            player:Say("Zona renomeada de '" .. oldName .. "' para '" .. newName .. "'")
        end
    end

    if command == "ChangeZoneType" then
        if not isAdmin then
            return
        end
        local id = args.id
        local newType = args.zoneType
        local customZones = ModData.get("FactionZoneDefinitions")

        if customZones and customZones[id] then
            customZones[id].zoneType = newType
            ModData.add("FactionZoneDefinitions", customZones)
            ModData.transmit("FactionZoneDefinitions")

            RefreshZoneList()
            player:Say("Zone '" .. customZones[id].name .. "' type changed to " .. newType)
        end
    end

    -- [NEW] LINK REWARD CRATE COMMAND
    if command == "SetRewardContainer" then
        if not isAdmin then
            return
        end
        local customZones = ModData.get("FactionZoneDefinitions")
        local zID = args.zoneID

        if customZones and customZones[zID] then
            customZones[zID].lootX = args.x
            customZones[zID].lootY = args.y
            customZones[zID].lootZ = args.z

            ModData.add("FactionZoneDefinitions", customZones)
            ModData.transmit("FactionZoneDefinitions")
            RefreshZoneList() -- Refresh server cache immediately

            player:Say("Container Linkado para " .. customZones[zID].name)
            print("SERVER: Container Linkado para " .. customZones[zID].name)
        end
    end

    if command == "SendAllianceInvite" then
        local myFaction = args.myFaction
        local targetFaction = args.targetFaction
        if not myFaction or not targetFaction then
            return
        end

        local alliances = ModData.get("FactionAlliances") or {}
        if not CanCreateAlliance(alliances, myFaction, targetFaction) then
            player:Say("Alliance limit reached. Each faction can only have one ally.")
            print("FACTION WAR: Blocked alliance invite from " .. myFaction .. " to " .. targetFaction .. " due to one-ally limit")
            return
        end

        local invites = ModData.get("FactionAllianceInvites") or {}
        if not invites[targetFaction] then
            invites[targetFaction] = {}
        end
        invites[targetFaction][myFaction] = true

        ModData.add("FactionAllianceInvites", invites)
        if ModData.transmit then
            ModData.transmit("FactionAllianceInvites")
        end

        player:Say("Sent alliance invite to " .. targetFaction)
        print("FACTION WAR: " .. myFaction .. " sent alliance invite to " .. targetFaction)
    end

    if command == "SetAlliance" then
        local myFaction = args.myFaction
        local targetFaction = args.targetFaction
        local state = args.state -- true to ally, false to unally

        if not myFaction or not targetFaction then
            return
        end

        local alliances = ModData.get("FactionAlliances") or {}
        if state and not CanCreateAlliance(alliances, myFaction, targetFaction) then
            player:Say("Alliance limit reached. Each faction can only have one ally.")
            print("FACTION WAR: Blocked alliance between " .. myFaction .. " and " .. targetFaction .. " due to one-ally limit")
            return
        end

        if not alliances[myFaction] then
            alliances[myFaction] = {}
        end
        alliances[myFaction][targetFaction] = state

        -- Make it symmetric
        if not alliances[targetFaction] then
            alliances[targetFaction] = {}
        end
        alliances[targetFaction][myFaction] = state

        ModData.add("FactionAlliances", alliances)
        if ModData.transmit then
            ModData.transmit("FactionAlliances")
        end

        -- Clear any pending invites
        local invites = ModData.get("FactionAllianceInvites") or {}
        local invitesChanged = false
        if invites[myFaction] and invites[myFaction][targetFaction] then
            invites[myFaction][targetFaction] = nil
            invitesChanged = true
        end
        if invites[targetFaction] and invites[targetFaction][myFaction] then
            invites[targetFaction][myFaction] = nil
            invitesChanged = true
        end
        if invitesChanged then
            ModData.add("FactionAllianceInvites", invites)
            if ModData.transmit then
                ModData.transmit("FactionAllianceInvites")
            end
        end

        if state then
            player:Say("We have set an alliance with " .. targetFaction)
            print("FACTION WAR: " .. myFaction .. " allied with " .. targetFaction)
        else
            player:Say("Alliance ended with " .. targetFaction)
            print("FACTION WAR: " .. myFaction .. " ended alliance with " .. targetFaction)
        end
    end

    if command == "DeclineAllianceInvite" then
        local myFaction = args.myFaction
        local targetFaction = args.targetFaction
        if not myFaction or not targetFaction then
            return
        end

        local invites = ModData.get("FactionAllianceInvites") or {}
        if invites[myFaction] and invites[myFaction][targetFaction] then
            invites[myFaction][targetFaction] = nil
            ModData.add("FactionAllianceInvites", invites)
            if ModData.transmit then
                ModData.transmit("FactionAllianceInvites")
            end
            player:Say("Declined alliance invite from " .. targetFaction)
            print("FACTION WAR: " .. myFaction .. " declined alliance invite from " .. targetFaction)
        end
    end

    if command == "RequestData" then
        if ModData.transmit then
            if ModData.get("FactionZoneDefinitions") then
                ModData.transmit("FactionZoneDefinitions")
            end
            if ModData.get("FactionWarZones") then
                ModData.transmit("FactionWarZones")
            end
            if ModData.get("FactionAlliances") then
                ModData.transmit("FactionAlliances")
            end
            if ModData.get("FactionAllianceInvites") then
                ModData.transmit("FactionAllianceInvites")
            end
        end
    end
end

-- =======================================================
-- REWARD SYSTEM: DAILY FACTION SALARY (9:00 AM)
-- =======================================================
local function DistributeDailySalary()
    local gameTime = getGameTime()
    if gameTime:getHour() ~= 9 then
        return
    end -- Only run at 9 AM

    -- Prevent double payout on server restarts or time skips within the same hour
    local worldAge = gameTime:getWorldAgeHours()
    local currentDay = math.floor(worldAge / 24)

    local paydayData = ModData.get("FactionWarPayday") or {
        lastPaidDay = -1
    }
    if paydayData.lastPaidDay == currentDay then
        return
    end

    local allZoneStatus = ModData.get("FactionWarZones") or {}
    local onlinePlayers = getOnlinePlayers()

    -- 1. GET SETTINGS FROM SANDBOX
    local sb = SandboxVars.FactionWar
    local rewardAmt = (sb and sb.SalaryAmount) or 1

    -- [NEW] Advanced Custom Item Check (Supports multiple items split by commas or semicolons)
    local customItem = sb.CustomSalaryItem
    local customList = ParseCustomItems(customItem)
    local rewardItem = "Base.Bullets9mmBox"

    local isCustom = (#customList > 0)
    if not isCustom then
        local itemMap = {
            [1] = "Base.Bullets9mmBox",
            [2] = "Base.ShotgunShellsBox",
            [3] = "Base.CannedCornBeef",
            [4] = "Base.FirstAidKit",
            [5] = "Base.NailsBox"
        }
        rewardItem = itemMap[sb.SalaryItemType] or "Base.Bullets9mmBox"
    end

    -- 2. Count Zones per Faction
    local factionCounts = {}
    for _, zData in pairs(allZoneStatus) do
        if zData.owner and zData.owner ~= "Neutral" then
            factionCounts[zData.owner] = (factionCounts[zData.owner] or 0) + 1
        end
    end

    -- 3. Pay Online Players
    if onlinePlayers then
        for i = 0, onlinePlayers:size() - 1 do
            local player = onlinePlayers:get(i)
            local myFaction = GetRealFaction(player)

            if myFaction and myFaction ~= "Nomad" and factionCounts[myFaction] then
                local zoneCount = factionCounts[myFaction]
                local inv = player:getInventory()

                local totalPay = zoneCount * rewardAmt

                for k = 1, totalPay do
                    local chosenItem = rewardItem
                    if isCustom then
                        chosenItem = customList[ZombRand(#customList) + 1]
                    end
                    inv:AddItem(chosenItem)
                end

                local payMsg = getText("IGUI_FactionWar_FactionPayday")
                if not payMsg or payMsg == "IGUI_FactionWar_FactionPayday" then
                    payMsg = "FACTION PAYDAY: Received %1 items!"
                end
                player:Say(payMsg:gsub("%%1", tostring(totalPay)))
            end
        end
    end

    paydayData.lastPaidDay = currentDay
    ModData.add("FactionWarPayday", paydayData)
    if ModData.transmit then
        ModData.transmit("FactionWarPayday")
    end

    print("SERVER: Distributed Daily Faction Salaries.")
end

-- =======================================================
-- ABANDONMENT SYSTEM: CLEAR INACTIVE FACTIONS
-- =======================================================
local function CheckFactionAbandonment()
    local sb = SandboxVars.FactionWar
    local timeoutHours = (sb and sb.AbandonmentTimeout) or 168 -- Default 7 days
    if timeoutHours <= 0 then
        return
    end

    local worldAge = getGameTime():getWorldAgeHours()
    local lastSeenData = ModData.get("FactionLastSeen") or {}
    local allZoneStatus = ModData.get("FactionWarZones") or {}
    local dataChanged = false

    -- 1. Track online factions now to update lastSeen
    local onlinePlayers = getOnlinePlayers()
    if onlinePlayers then
        for i = 0, onlinePlayers:size() - 1 do
            local p = onlinePlayers:get(i)
            local f = GetRealFaction(p)
            if f and f ~= "Nomad" then
                lastSeenData[f] = worldAge
                dataChanged = true
            end
        end
    end

    -- 2. Check each faction that owns territory
    for zoneID, zData in pairs(allZoneStatus) do
        local owner = zData.owner
        if owner and owner ~= "Neutral" and owner ~= "Nomad" then
            local lastSeen = lastSeenData[owner] or worldAge
            local hoursInactive = worldAge - lastSeen

            if hoursInactive >= timeoutHours then
                print("FACTION WAR: Zone '" .. zData.name .. "' abandoned by " .. owner .. " (Inactive for " ..
                          hoursInactive .. " hours)")
                zData.owner = "Neutral"
                zData.progress = 0
                zData.col = {
                    r = 0.5,
                    g = 0.5,
                    b = 0.5
                }
                dataChanged = true

                local tpl = getText("IGUI_FactionWar_ZoneAbandoned")
                if not tpl or tpl == "IGUI_FactionWar_ZoneAbandoned" then
                    tpl = "[ZONE ABANDONED] %1 is no longer claimed by %2 due to inactivity."
                end
                local msg = tpl:gsub("%%1", zData.name):gsub("%%2", owner)
                sendServerCommand("FW_Msg", "RadioMsg", {
                    text = msg
                })
            end
        end
    end

    if dataChanged then
        ModData.add("FactionLastSeen", lastSeenData)
        ModData.add("FactionWarZones", allZoneStatus)
        ModData.transmit("FactionLastSeen")
        ModData.transmit("FactionWarZones")
    end
end

Events.EveryHours.Add(CheckFactionAbandonment)
Events.EveryHours.Add(DistributeDailySalary)
Events.OnClientCommand.Add(OnClientCommand)

-- =======================================================
-- HOTFIX: Inventory Sync
-- =======================================================
local function FixInventorySync()
    print("FIX CARGADO PAPU")
    local players = getOnlinePlayers()
    if not players then
        return
    end
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player then
            local inv = player:getInventory()
            if inv then
                inv:setDirty(true)
                inv:requestSync()
            end
        end
    end
end
Events.EveryHours.Add(FixInventorySync)
