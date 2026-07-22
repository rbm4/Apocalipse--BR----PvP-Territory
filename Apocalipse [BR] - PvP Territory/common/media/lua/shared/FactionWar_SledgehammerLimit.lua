-- =======================================================
-- FILE: FactionWar_SledgehammerLimit.lua (SHARED)
-- DESCR: Limits enemy/nomad demolition inside controlled
--        territory zones to 3 successful destroys per
--        player per real-time 24 hour window, and blocks
--        pickup/moveable theft in those same zones.
-- =======================================================

require "FactionZones"

local MODULE = "FactionWarSledgehammerLimit"
local DATA_KEY = "FactionWarSledgehammerLimits"
local LIMIT = 3
local WINDOW_HOURS = 24
local recentDestroyRecords = {}

local function getRealTimeHours()
    if getTimestamp then
        return getTimestamp() / 3600
    end
    if getTimeInMillis then
        return getTimeInMillis() / 3600000
    end
    return os.time() / 3600
end

local function getRealFaction(player)
    if not player then return "Nomad" end

    local username = player.getUsername and player:getUsername() or nil
    if username and Faction and Faction.getPlayerFaction then
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

local function getSquareFromObject(obj)
    if obj and obj.getSquare then
        return obj:getSquare()
    end
    return nil
end

local function getSquareFromAction(action)
    if not action then return nil end
    if action.square then return action.square end
    if action.currentSquare then return action.currentSquare end
    if action.object then return getSquareFromObject(action.object) end
    if action.item then return getSquareFromObject(action.item) end
    if action.thumpable then return getSquareFromObject(action.thumpable) end
    if action.currentObject then return getSquareFromObject(action.currentObject) end
    return nil
end

local function getZoneAtSquare(square)
    if not square then
        return nil
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    if FactionZones and FactionZones.getZoneAt then
        local zone = FactionZones.getZoneAt(x, y, z)
        if zone then
            return zone
        end
    end

    if ModData and ModData.get then
        local customZones = ModData.get("FactionZoneDefinitions") or {}
        for id, zone in pairs(customZones) do
            local x1 = tonumber(zone.x1)
            local y1 = tonumber(zone.y1)
            local x2 = tonumber(zone.x2)
            local y2 = tonumber(zone.y2)
            local z1 = tonumber(zone.z1)
            local z2 = tonumber(zone.z2)
            if x1 and y1 and x2 and y2 then
                local minX = math.min(x1, x2)
                local maxX = math.max(x1, x2)
                local minY = math.min(y1, y2)
                local maxY = math.max(y1, y2)
                local inZ = true
                if z1 and z2 then
                    inZ = z >= math.min(z1, z2) and z <= math.max(z1, z2)
                end
                if x >= minX and x <= maxX and y >= minY and y <= maxY and inZ then
                    return {
                        id = id,
                        name = zone.name,
                        x1 = x1,
                        y1 = y1,
                        x2 = x2,
                        y2 = y2,
                        z1 = z1,
                        z2 = z2,
                        owner = zone.owner,
                        zoneType = zone.zoneType or "Standard"
                    }
                end
            end
        end
    end

    return nil
end

local function getZoneId(zone)
    if not zone then return nil end
    if zone.id and zone.id ~= "" then return tostring(zone.id) end
    if zone.name and zone.name ~= "" then return tostring(zone.name) end
    return tostring(zone.x1) .. "," .. tostring(zone.y1) .. "," .. tostring(zone.x2) .. "," .. tostring(zone.y2)
end

local function getZoneOwner(zone)
    local zoneId = getZoneId(zone)
    if ModData and ModData.get and zoneId then
        local statusData = ModData.get("FactionWarZones")
        if statusData and statusData[zoneId] and statusData[zoneId].owner then
            return statusData[zoneId].owner
        end
    end
    return (zone and zone.owner) or "Neutral"
end

local function isControlledByOtherFaction(zone, player)
    local owner = getZoneOwner(zone)
    if not owner or owner == "" or owner == "Neutral" or owner == "Nomad" then
        return false
    end
    return getRealFaction(player) ~= owner
end

local function getEnemyTerritoryState(player, square)
    local zone = getZoneAtSquare(square)
    if not zone or not isControlledByOtherFaction(zone, player) then
        return nil
    end

    return {
        zone = zone,
        zoneId = getZoneId(zone),
        owner = getZoneOwner(zone)
    }
end

local function getLimitsData()
    if not ModData then return nil end
    local data = ModData.get(DATA_KEY)
    if not data then
        ModData.add(DATA_KEY, {})
        data = ModData.get(DATA_KEY)
    end
    return data
end

local function getPlayerKey(player)
    if not player then return nil end
    if player.getUsername then
        local username = player:getUsername()
        if username and username ~= "" then return username end
    end
    if player.getDisplayName then
        return player:getDisplayName()
    end
    return nil
end

local function getEntry(playerKey, zoneId, now)
    local data = getLimitsData()
    if not data or not playerKey or not zoneId then return nil end

    local key = playerKey .. "|" .. zoneId
    local entry = data[key]
    if not entry or not entry.windowStart or (now - entry.windowStart) >= WINDOW_HOURS then
        entry = {
            windowStart = now,
            count = 0
        }
        data[key] = entry
    end
    return entry, data, key
end

local function getLimitState(player, square)
    local zone = getZoneAtSquare(square)
    if not zone or not isControlledByOtherFaction(zone, player) then
        return nil
    end

    local playerKey = getPlayerKey(player)
    local zoneId = getZoneId(zone)
    if not playerKey or not zoneId then
        return nil
    end

    local now = getRealTimeHours()
    local entry = getEntry(playerKey, zoneId, now)
    if not entry then return nil end

    local resetIn = WINDOW_HOURS - (now - (entry.windowStart or now))
    if resetIn < 0 then resetIn = 0 end

    return {
        zone = zone,
        zoneId = zoneId,
        playerKey = playerKey,
        owner = getZoneOwner(zone),
        count = entry.count or 0,
        resetIn = resetIn
    }
end

local function isBlocked(player, square)
    local state = getLimitState(player, square)
    return state and state.count >= LIMIT, state
end

local function showBlockedHalo(player, state)
    if not player then return end
    local hoursLeft = 1
    if state and state.resetIn then
        hoursLeft = math.max(1, math.ceil(state.resetIn))
    end
    player:setHaloNote(getText("IGUI_FactionWar_SledgehammerLimitReached", tostring(LIMIT), tostring(LIMIT), tostring(hoursLeft)), 255, 50, 50, 700)
end

local function showPickupBlockedHalo(player)
    if not player then return end
    player:setHaloNote(getText("IGUI_FactionWar_EnemyTerritoryPickupBlocked"), 255, 50, 50, 700)
end

local function isRewardCrateObject(object)
    if not object or not object.getModData then return false end
    local modData = object:getModData()
    return modData and modData.isRewardCrate == true
end

local function recordLocalDestroy(player, square)
    local state = getLimitState(player, square)
    if not state then return end

    local now = getRealTimeHours()
    local entry, data = getEntry(state.playerKey, state.zoneId, now)
    if not entry or not data then return end

    entry.count = math.min(LIMIT, (entry.count or 0) + 1)
    entry.owner = state.owner
    entry.lastDestroy = now
end

local function getRecordKey(player, square)
    if not player or not square then return nil end
    local playerKey = getPlayerKey(player)
    if not playerKey then return nil end
    return playerKey .. "|" .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
end

local function recordDestroy(player, square)
    local state = getLimitState(player, square)
    if not state then return end

    local now = getRealTimeHours()
    local recordKey = getRecordKey(player, square)
    if recordKey and recentDestroyRecords[recordKey] and (now - recentDestroyRecords[recordKey]) < (2 / 3600) then
        return
    end
    if recordKey then
        recentDestroyRecords[recordKey] = now
    end

    recordLocalDestroy(player, square)
    if isClient() and sendClientCommand then
        sendClientCommand(player, MODULE, "RecordDestroy", {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            zoneId = state.zoneId
        })
    elseif not isClient() and ModData and ModData.transmit then
        ModData.transmit(DATA_KEY)
    end
end

local function blockOption(option, playerNum, state)
    if not option then return end
    option.notAvailable = true
    if ISToolTip then
        option.toolTip = option.toolTip or ISToolTip:new()
        option.toolTip.description = getText("IGUI_FactionWar_SledgehammerLimitReached", tostring(LIMIT), tostring(LIMIT), tostring(math.max(1, math.ceil((state and state.resetIn) or WINDOW_HOURS))))
    end
    option.onSelect = function()
        showBlockedHalo(getSpecificPlayer(playerNum), state)
    end
    if option.func then
        option.func = option.onSelect
    end
end

local function blockPickupOption(option, playerNum)
    if not option then return end
    option.notAvailable = true
    if ISToolTip then
        option.toolTip = option.toolTip or ISToolTip:new()
        option.toolTip.description = getText("IGUI_FactionWar_EnemyTerritoryPickupBlocked")
    end
    option.onSelect = function()
        showPickupBlockedHalo(getSpecificPlayer(playerNum))
    end
    if option.func then
        option.func = option.onSelect
    end
end

if not isClient() then
    local function initData()
        getLimitsData()
        if ModData and ModData.transmit then
            ModData.transmit(DATA_KEY)
        end
    end

    Events.OnLoad.Add(initData)
    Events.OnServerStarted.Add(initData)

    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= MODULE or command ~= "RecordDestroy" then return end
        if not player or not args then return end

        local x = tonumber(args.x)
        local y = tonumber(args.y)
        local z = tonumber(args.z)
        if not x or not y or not z then return end

        local square = getCell():getGridSquare(x, y, z)
        local state = getLimitState(player, square)
        if not state then return end
        if args.zoneId and tostring(args.zoneId) ~= state.zoneId then return end

        recordLocalDestroy(player, square)
        if ModData and ModData.transmit then
            ModData.transmit(DATA_KEY)
        end
    end)
end

if not isServer() then
    local function getPlayerFromAction(action)
        return action and (action.character or action.playerObj or action.player) or getPlayer()
    end

    local function shouldBlockAction(action)
        return isBlocked(getPlayerFromAction(action), getSquareFromAction(action))
    end

    local function shouldBlockPickupAction(action)
        return getEnemyTerritoryState(getPlayerFromAction(action), getSquareFromAction(action)) ~= nil
    end

    local function completeWithRecord(action, originalComplete)
        local player = getPlayerFromAction(action)
        local square = getSquareFromAction(action)
        local blocked, state = isBlocked(player, square)
        if blocked then
            showBlockedHalo(player, state)
            return false
        end

        local result = originalComplete(action)
        if result ~= false then
            recordDestroy(player, square)
        end
        return result
    end

    local function completeWithoutRecord(action, originalComplete)
        local player = getPlayerFromAction(action)
        local square = getSquareFromAction(action)
        local blocked, state = isBlocked(player, square)
        if blocked then
            showBlockedHalo(player, state)
            return false
        end
        return originalComplete(action)
    end

    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
        if test then return end
        local player = getSpecificPlayer(playerNum)
        if not player or not worldObjects then return end

        local blockedState = nil
        for _, obj in ipairs(worldObjects) do
            local square = obj and obj.getSquare and obj:getSquare() or nil
            local blocked, state = isBlocked(player, square)
            if blocked then
                blockedState = state
                break
            end
        end
        if not blockedState then return end

        local optionNames = {
            getText("ContextMenu_Destroy"),
            getText("ContextMenu_Dismantle"),
            getText("ContextMenu_Disassemble"),
            getText("ContextMenu_DisassembleItem")
        }
        for _, optionName in ipairs(optionNames) do
            local option = context:getOptionFromName(optionName)
            if option then
                blockOption(option, playerNum, blockedState)
            end
        end
    end)

    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
        if test then return end
        local player = getSpecificPlayer(playerNum)
        if not player or not worldObjects then return end

        local pickupBlocked = false
        for _, obj in ipairs(worldObjects) do
            local square = obj and obj.getSquare and obj:getSquare() or nil
            if getEnemyTerritoryState(player, square) then
                pickupBlocked = true
                break
            end
        end
        if not pickupBlocked then return end

        local pickupPrefix = getText("IGUI_Pickup")
        local grabText = getText("ContextMenu_Grab")
        for _, option in ipairs(context.options) do
            local name = option.name
            if name and (name == grabText or (pickupPrefix and name:find(pickupPrefix, 1, true))) then
                blockPickupOption(option, playerNum)
            end
        end
    end)

    Events.OnGameStart.Add(function()
        pcall(require, "TimedActions/ISDismantleAction")
        pcall(require, "TimedActions/ISDestroyStuffAction")
        pcall(require, "Moveables/ISMoveablesAction")
        pcall(require, "Moveables/ISMoveableSpriteProps")
        pcall(require, "Moveables/ISMoveableCursor")
        pcall(require, "BuildingObjects/ISDestroyCursor")

        if ISDestroyStuffAction and ISDestroyStuffAction.isValid then
            local oldDestroyIsValid = ISDestroyStuffAction.isValid
            ISDestroyStuffAction.isValid = function(self)
                local blocked, state = shouldBlockAction(self)
                if blocked then
                    showBlockedHalo(getPlayerFromAction(self), state)
                    return false
                end
                return oldDestroyIsValid(self)
            end
        end

        if ISDestroyStuffAction and ISDestroyStuffAction.complete then
            local oldDestroyComplete = ISDestroyStuffAction.complete
            ISDestroyStuffAction.complete = function(self)
                return completeWithoutRecord(self, oldDestroyComplete)
            end
        end

        if ISDestroyStuffAction and ISDestroyStuffAction.perform then
            local oldDestroyPerform = ISDestroyStuffAction.perform
            ISDestroyStuffAction.perform = function(self)
                local blocked, state = shouldBlockAction(self)
                if blocked then
                    showBlockedHalo(getPlayerFromAction(self), state)
                    return
                end
                return oldDestroyPerform(self)
            end
        end

        if sledgeDestroy then
            local oldSledgeDestroy = sledgeDestroy
            sledgeDestroy = function(object)
                local square = getSquareFromObject(object)
                local player = getPlayer()
                local protectedRewardCrate = isRewardCrateObject(object)
                local blocked, state = isBlocked(player, square)
                if blocked then
                    showBlockedHalo(player, state)
                    return
                end

                local result = oldSledgeDestroy(object)
                if not protectedRewardCrate then
                    recordDestroy(player, square)
                end
                return result
            end
        end

        if ISDismantleAction and ISDismantleAction.isValid then
            local oldDismantleIsValid = ISDismantleAction.isValid
            ISDismantleAction.isValid = function(self)
                local blocked, state = shouldBlockAction(self)
                if blocked then
                    showBlockedHalo(getPlayerFromAction(self), state)
                    return false
                end
                return oldDismantleIsValid(self)
            end
        end

        if ISDismantleAction and ISDismantleAction.complete then
            local oldDismantleComplete = ISDismantleAction.complete
            ISDismantleAction.complete = function(self)
                return completeWithRecord(self, oldDismantleComplete)
            end
        end

        if ISDismantleAction and ISDismantleAction.perform then
            local oldDismantlePerform = ISDismantleAction.perform
            ISDismantleAction.perform = function(self)
                local player = getPlayerFromAction(self)
                local square = getSquareFromAction(self)
                local blocked, state = isBlocked(player, square)
                if blocked then
                    showBlockedHalo(player, state)
                    return
                end
                local result = oldDismantlePerform(self)
                if not ISDismantleAction.complete then
                    recordDestroy(player, square)
                end
                return result
            end
        end

        if ISMoveablesAction and ISMoveablesAction.isValid then
            local oldMoveablesIsValid = ISMoveablesAction.isValid
            ISMoveablesAction.isValid = function(self)
                local mode = self and self.mode
                if mode == "pickup" or mode == "pickUp" then
                    if shouldBlockPickupAction(self) then
                        showPickupBlockedHalo(getPlayerFromAction(self))
                        return false
                    end
                end
                if mode == "scrap" or mode == "dismantle" or mode == "disassemble" or mode == "destroy" then
                    local blocked, state = shouldBlockAction(self)
                    if blocked then
                        showBlockedHalo(getPlayerFromAction(self), state)
                        return false
                    end
                end
                return oldMoveablesIsValid(self)
            end
        end

        if ISMoveablesAction and ISMoveablesAction.complete then
            local oldMoveablesComplete = ISMoveablesAction.complete
            ISMoveablesAction.complete = function(self)
                local mode = self and self.mode
                if mode == "pickup" or mode == "pickUp" then
                    if shouldBlockPickupAction(self) then
                        showPickupBlockedHalo(getPlayerFromAction(self))
                        return false
                    end
                end
                if mode == "scrap" or mode == "dismantle" or mode == "disassemble" or mode == "destroy" then
                    return completeWithRecord(self, oldMoveablesComplete)
                end
                return oldMoveablesComplete(self)
            end
        end

        if ISMoveablesAction and ISMoveablesAction.perform then
            local oldMoveablesPerform = ISMoveablesAction.perform
            ISMoveablesAction.perform = function(self)
                local mode = self and self.mode
                if mode == "pickup" or mode == "pickUp" then
                    if shouldBlockPickupAction(self) then
                        showPickupBlockedHalo(getPlayerFromAction(self))
                        return
                    end
                    return oldMoveablesPerform(self)
                end
                if mode == "scrap" or mode == "dismantle" or mode == "disassemble" or mode == "destroy" then
                    local player = getPlayerFromAction(self)
                    local square = getSquareFromAction(self)
                    local blocked, state = isBlocked(player, square)
                    if blocked then
                        showBlockedHalo(player, state)
                        return
                    end
                    local result = oldMoveablesPerform(self)
                    if not ISMoveablesAction.complete then
                        recordDestroy(player, square)
                    end
                    return result
                end
                return oldMoveablesPerform(self)
            end
        end

        if ISMoveableSpriteProps then
            if ISMoveableSpriteProps.canPickUpMoveableInternal then
                local oldCanPickUpMoveableInternal = ISMoveableSpriteProps.canPickUpMoveableInternal
                ISMoveableSpriteProps.canPickUpMoveableInternal = function(self, character, square, object, isMulti)
                    if getEnemyTerritoryState(character, square or getSquareFromObject(object)) then
                        return false
                    end
                    return oldCanPickUpMoveableInternal(self, character, square, object, isMulti)
                end
            end

            if ISMoveableSpriteProps.pickUpMoveableInternal then
                local oldPickUpMoveableInternal = ISMoveableSpriteProps.pickUpMoveableInternal
                ISMoveableSpriteProps.pickUpMoveableInternal = function(self, character, square, object, sprInstance, spriteName, createItem, rotating)
                    if getEnemyTerritoryState(character, square or getSquareFromObject(object)) then
                        showPickupBlockedHalo(character)
                        return nil
                    end
                    return oldPickUpMoveableInternal(self, character, square, object, sprInstance, spriteName, createItem, rotating)
                end
            end

            if ISMoveableSpriteProps.pickUpMoveableViaCursor then
                local oldPickUpMoveableViaCursor = ISMoveableSpriteProps.pickUpMoveableViaCursor
                ISMoveableSpriteProps.pickUpMoveableViaCursor = function(self, character, square, origSpriteName, moveCursor)
                    if getEnemyTerritoryState(character, square) then
                        showPickupBlockedHalo(character)
                        return
                    end
                    return oldPickUpMoveableViaCursor(self, character, square, origSpriteName, moveCursor)
                end
            end
        end

        if ISMoveableCursor and ISMoveableCursor.isValid then
            local oldMoveableCursorIsValid = ISMoveableCursor.isValid
            ISMoveableCursor.isValid = function(self, square)
                local character = self and (self.character or self.player)
                if getEnemyTerritoryState(character, square) then
                    return false
                end
                return oldMoveableCursorIsValid(self, square)
            end
        end

        if ISDestroyCursor then
            if ISDestroyCursor.canDestroy then
                local oldCanDestroy = ISDestroyCursor.canDestroy
                ISDestroyCursor.canDestroy = function(self, object)
                    local blocked = isBlocked((self and self.character) or getPlayer(), getSquareFromObject(object))
                    if blocked then
                        return false
                    end
                    return oldCanDestroy(self, object)
                end
            end

            if ISDestroyCursor.isValid then
                local oldCursorIsValid = ISDestroyCursor.isValid
                ISDestroyCursor.isValid = function(self, square)
                    local blocked = isBlocked((self and self.character) or getPlayer(), square)
                    if blocked then
                        return false
                    end
                    return oldCursorIsValid(self, square)
                end
            end

            if ISDestroyCursor.create then
                local oldCursorCreate = ISDestroyCursor.create
                ISDestroyCursor.create = function(self, x, y, z, north, sprite)
                    local square = getCell():getGridSquare(x, y, z)
                    local player = (self and self.character) or getPlayer()
                    local blocked, state = isBlocked(player, square)
                    if blocked then
                        showBlockedHalo(player, state)
                        return
                    end
                    local result = oldCursorCreate(self, x, y, z, north, sprite)
                    recordDestroy(player, square)
                    return result
                end
            end
        end
    end)
end
