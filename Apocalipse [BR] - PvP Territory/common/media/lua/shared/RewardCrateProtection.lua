-- =======================================================
-- FILE: RewardCrateProtection.lua (SHARED)
-- DESCR: Protects reward crates linked via SetRewardContainer
--        from player pickup, player sledgehammer destruction
--        and zombie thumping. Halo note is shown when a player
--        tries to move or destroy a protected crate.
-- =======================================================

local RewardCrateProtection = {}

-- O(1) coordinate-key lookup for reward crate locations.
RewardCrateProtection.crateKeys = {}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function refreshKeys()
    RewardCrateProtection.crateKeys = {}
    if not ModData then return end
    local zones = ModData.get("FactionZoneDefinitions")
    if not zones then return end
    for _, zone in pairs(zones) do
        if zone and zone.lootX then
            RewardCrateProtection.crateKeys[key(zone.lootX, zone.lootY, zone.lootZ)] = true
        end
    end
end

local function isProtectedSquare(x, y, z)
    return RewardCrateProtection.crateKeys[key(x, y, z)] == true
end

local function hardenCrate(obj)
    if not obj then return end
    local modData = obj:getModData()
    if modData.isRewardCrate then return end

    -- Zombie / melee protection: make the object non-thumpable.
    if obj.setIsThumpable then
        obj:setIsThumpable(false)
    end
    -- Prevent dismantling.
    if obj.setIsDismantable then
        obj:setIsDismantable(false)
    end
    -- Keep health high even if damage somehow gets applied.
    if obj.setMaxHealth then
        obj:setMaxHealth(999999)
    end
    if obj.setHealth then
        obj:setHealth(999999)
    end
    if obj.setThumpDmg then
        obj:setThumpDmg(999999)
    end

    modData.isRewardCrate = true
    obj:transmitModData()
end

local function hardenAllContainersOnSquare(sq)
    if not sq then return end
    for i = 0, sq:getObjects():size() - 1 do
        local obj = sq:getObjects():get(i)
        if obj and obj:getContainer() then
            hardenCrate(obj)
        end
    end
end

-- -------------------------------------------------------
-- SERVER / NON-CLIENT: harden crate when linked and on load
-- -------------------------------------------------------
if not isClient() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= "FactionWar" or command ~= "SetRewardContainer" then return end
        if not args then return end
        refreshKeys()
        local sq = getCell():getGridSquare(args.x, args.y, args.z)
        hardenAllContainersOnSquare(sq)
    end)

    Events.OnLoad.Add(refreshKeys)
    Events.OnServerStarted.Add(refreshKeys)
    Events.EveryTenMinutes.Add(refreshKeys)
end

-- Re-harden crates whenever their square is loaded. Runs on both sides.
Events.LoadGridsquare.Add(function(sq)
    if isProtectedSquare(sq:getX(), sq:getY(), sq:getZ()) then
        hardenAllContainersOnSquare(sq)
    end
end)

-- -------------------------------------------------------
-- CLIENT / NON-SERVER: block pickup/destroy context options
-- -------------------------------------------------------
if not isServer() then
    local function getBlockedMessage()
        return getText("IGUI_RewardCrate_Protected")
    end

    local function blockOption(option, playerNum)
        if not option then return end
        option.onSelect = function(target, param1, param2, param3, param4)
            local player = getSpecificPlayer(playerNum)
            if player then
                player:setHaloNote(getBlockedMessage(), 255, 50, 50, 600)
            end
            -- Intentionally do not call the original onSelect.
        end
        if option.func then
            option.func = option.onSelect
        end
    end

    local function isObjectOnProtectedSquare(obj)
        if not obj or not obj.getSquare then return false end
        local sq = obj:getSquare()
        if not sq then return false end
        refreshKeys()
        return isProtectedSquare(sq:getX(), sq:getY(), sq:getZ())
    end

    local function isSquareProtectedByRewardCrate(square)
        if not square then return false end
        refreshKeys()
        return isProtectedSquare(square:getX(), square:getY(), square:getZ())
    end

    local function showBlockedHalo(character)
        if character then
            character:setHaloNote(getBlockedMessage(), 255, 50, 50, 600)
        end
    end

    local function isProtectedMoveableAction(self)
        if not self then return false end
        if self.square and isSquareProtectedByRewardCrate(self.square) then return true end
        if self.object and isObjectOnProtectedSquare(self.object) then return true end
        if self.item and isObjectOnProtectedSquare(self.item) then return true end
        if self.thumpable and isObjectOnProtectedSquare(self.thumpable) then return true end
        if self.currentObject and isObjectOnProtectedSquare(self.currentObject) then return true end
        if self.currentSquare and isSquareProtectedByRewardCrate(self.currentSquare) then return true end
        return false
    end

    local function isProtectedDisassembleData(data)
        if not data then return false end
        if data.square and isSquareProtectedByRewardCrate(data.square) then return true end
        if data.object and isObjectOnProtectedSquare(data.object) then return true end
        return isProtectedMoveableAction(data)
    end

    local function getPlayerFromMenuData(data)
        if not data then return getPlayer() end
        return data.playerObj or data.player or data.character or getPlayer()
    end

    local function isDestructiveMoveableMode(mode)
        return mode == "scrap"
            or mode == "dismantle"
            or mode == "disassemble"
            or mode == "destroy"
            or mode == "pickup"
            or mode == "pickUp"
    end

    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
        if test then return end
        refreshKeys()
        if not worldObjects or #worldObjects == 0 then return end

        local protected = false
        for _, obj in ipairs(worldObjects) do
            local sq = obj:getSquare()
            if sq and isProtectedSquare(sq:getX(), sq:getY(), sq:getZ()) then
                protected = true
                break
            end
        end
        if not protected then return end

        -- Block the "Destroy" sledgehammer option (exact match).
        local destroyOpt = context:getOptionFromName(getText("ContextMenu_Destroy"))
        if destroyOpt then
            blockOption(destroyOpt, playerNum)
        end

        -- Block dismantle/disassemble moveable options when shown directly on the tile.
        local destructiveOptionNames = {
            getText("ContextMenu_Dismantle"),
            getText("ContextMenu_Disassemble"),
            getText("ContextMenu_DisassembleItem"),
        }
        for _, optName in ipairs(destructiveOptionNames) do
            if optName then
                local opt = context:getOptionFromName(optName)
                if opt then
                    blockOption(opt, playerNum)
                end
            end
        end

        -- Block any pickup / grab option by name prefix.
        local pickupPrefix = getText("IGUI_Pickup") -- "Pick up"
        local grabText = getText("ContextMenu_Grab") -- "Grab"
        for _, opt in ipairs(context.options) do
            local name = opt.name
            if name then
                if name == grabText or (pickupPrefix and name:find(pickupPrefix, 1, true)) then
                    blockOption(opt, playerNum)
                end
            end
        end
    end)

    Events.EveryTenMinutes.Add(refreshKeys)

    -- Timed-action guards catch actions that bypass context-menu filtering.
    Events.OnGameStart.Add(function()
        pcall(require, "TimedActions/ISDismantleAction")
        pcall(require, "TimedActions/ISDestroyStuffAction")
        pcall(require, "Moveables/ISMoveablesAction")
        pcall(require, "Moveables/ISMoveableSpriteProps")
        pcall(require, "BuildingObjects/ISDestroyCursor")
        pcall(require, "ISUI/ISDisassembleMenu")
        pcall(require, "Context/World/ISContextDisassemble")

        if ISDismantleAction and ISDismantleAction.isValid then
            local oldDismantleIsValid = ISDismantleAction.isValid
            ISDismantleAction.isValid = function(self)
                if isProtectedMoveableAction(self) then
                    showBlockedHalo(self.character)
                    return false
                end
                return oldDismantleIsValid(self)
            end
        end

        if ISDestroyStuffAction and ISDestroyStuffAction.isValid then
            local oldDestroyStuffIsValid = ISDestroyStuffAction.isValid
            ISDestroyStuffAction.isValid = function(self)
                if isProtectedMoveableAction(self) then
                    showBlockedHalo(self.character)
                    return false
                end
                return oldDestroyStuffIsValid(self)
            end
        end

        if ISMoveablesAction and ISMoveablesAction.isValid then
            local oldMoveablesIsValid = ISMoveablesAction.isValid
            ISMoveablesAction.isValid = function(self)
                if isDestructiveMoveableMode(self.mode) and isProtectedMoveableAction(self) then
                    showBlockedHalo(self.character)
                    return false
                end
                return oldMoveablesIsValid(self)
            end
        end

        if ISMoveablesAction and ISMoveablesAction.perform then
            local oldMoveablesPerform = ISMoveablesAction.perform
            ISMoveablesAction.perform = function(self)
                if isDestructiveMoveableMode(self.mode) and isProtectedMoveableAction(self) then
                    showBlockedHalo(self.character)
                    return
                end
                return oldMoveablesPerform(self)
            end
        end

        if ISMoveablesAction and ISMoveablesAction.complete then
            local oldMoveablesComplete = ISMoveablesAction.complete
            ISMoveablesAction.complete = function(self)
                if isDestructiveMoveableMode(self.mode) and isProtectedMoveableAction(self) then
                    showBlockedHalo(self.character)
                    return false
                end
                return oldMoveablesComplete(self)
            end
        end

        if ISMoveableSpriteProps then
            if ISMoveableSpriteProps.canPickUpMoveableInternal then
                local oldCanPickUpMoveableInternal = ISMoveableSpriteProps.canPickUpMoveableInternal
                ISMoveableSpriteProps.canPickUpMoveableInternal = function(self, character, square, object, isMulti)
                    if isSquareProtectedByRewardCrate(square) or isObjectOnProtectedSquare(object) then
                        return false
                    end
                    return oldCanPickUpMoveableInternal(self, character, square, object, isMulti)
                end
            end

            if ISMoveableSpriteProps.pickUpMoveableInternal then
                local oldPickUpMoveableInternal = ISMoveableSpriteProps.pickUpMoveableInternal
                ISMoveableSpriteProps.pickUpMoveableInternal = function(self, character, square, object, sprInstance, spriteName, createItem, rotating)
                    if isSquareProtectedByRewardCrate(square) or isObjectOnProtectedSquare(object) then
                        showBlockedHalo(character)
                        return nil
                    end
                    return oldPickUpMoveableInternal(self, character, square, object, sprInstance, spriteName, createItem, rotating)
                end
            end

            if ISMoveableSpriteProps.pickUpMoveableViaCursor then
                local oldPickUpMoveableViaCursor = ISMoveableSpriteProps.pickUpMoveableViaCursor
                ISMoveableSpriteProps.pickUpMoveableViaCursor = function(self, character, square, origSpriteName, moveCursor)
                    if isSquareProtectedByRewardCrate(square) then
                        showBlockedHalo(character)
                        return
                    end
                    return oldPickUpMoveableViaCursor(self, character, square, origSpriteName, moveCursor)
                end
            end

            if ISMoveableSpriteProps.canScrapObjectInternal then
                local oldCanScrapObjectInternal = ISMoveableSpriteProps.canScrapObjectInternal
                ISMoveableSpriteProps.canScrapObjectInternal = function(self, result, object)
                    if isObjectOnProtectedSquare(object) then
                        if result then
                            result.canScrap = false
                        end
                        return false
                    end
                    return oldCanScrapObjectInternal(self, result, object)
                end
            end

            if ISMoveableSpriteProps.scrapObjectInternal then
                local oldScrapObjectInternal = ISMoveableSpriteProps.scrapObjectInternal
                ISMoveableSpriteProps.scrapObjectInternal = function(self, character, scrapDef, square, object, scrapResult, chance, perkName)
                    if isSquareProtectedByRewardCrate(square) or isObjectOnProtectedSquare(object) then
                        showBlockedHalo(character)
                        return 0
                    end
                    return oldScrapObjectInternal(self, character, scrapDef, square, object, scrapResult, chance, perkName)
                end
            end

            if ISMoveableSpriteProps.scrapObjectViaCursor then
                local oldScrapObjectViaCursor = ISMoveableSpriteProps.scrapObjectViaCursor
                ISMoveableSpriteProps.scrapObjectViaCursor = function(self, character, square, origSpriteName, moveCursor)
                    if isSquareProtectedByRewardCrate(square) then
                        showBlockedHalo(character)
                        return
                    end
                    return oldScrapObjectViaCursor(self, character, square, origSpriteName, moveCursor)
                end
            end

            if ISMoveableSpriteProps.startScrapAction then
                local oldStartScrapAction = ISMoveableSpriteProps.startScrapAction
                ISMoveableSpriteProps.startScrapAction = function(self, action)
                    if isProtectedMoveableAction(action) then
                        showBlockedHalo(action and action.character)
                        return false
                    end
                    return oldStartScrapAction(self, action)
                end
            end
        end

        if sledgeDestroy then
            local oldSledgeDestroy = sledgeDestroy
            sledgeDestroy = function(object)
                if isObjectOnProtectedSquare(object) then
                    showBlockedHalo(getPlayer())
                    return
                end
                return oldSledgeDestroy(object)
            end
        end

        if ISDisassembleMenu and ISDisassembleMenu.disassemble then
            local oldDisassembleMenuDisassemble = ISDisassembleMenu.disassemble
            ISDisassembleMenu.disassemble = function(playerObj, data)
                if isProtectedDisassembleData(data) then
                    showBlockedHalo(playerObj)
                    return
                end
                return oldDisassembleMenuDisassemble(playerObj, data)
            end
        end

        if ISWorldMenuElements and ISWorldMenuElements.ContextDisassemble then
            local oldContextDisassembleFactory = ISWorldMenuElements.ContextDisassemble
            ISWorldMenuElements.ContextDisassemble = function(...)
                local element = oldContextDisassembleFactory(...)
                if element and element.disassemble and not element.rewardCrateProtectionPatched then
                    local oldContextDisassemble = element.disassemble
                    element.disassemble = function(data, optionData)
                        if isProtectedDisassembleData(optionData) then
                            showBlockedHalo(getPlayerFromMenuData(data))
                            return
                        end
                        return oldContextDisassemble(data, optionData)
                    end
                    element.rewardCrateProtectionPatched = true
                end
                return element
            end
        end

        if ISDestroyCursor then
            if ISDestroyCursor.canDestroy then
                local oldCanDestroy = ISDestroyCursor.canDestroy
                ISDestroyCursor.canDestroy = function(self, object)
                    if isObjectOnProtectedSquare(object) then
                        return false
                    end
                    return oldCanDestroy(self, object)
                end
            end

            if ISDestroyCursor.isValid then
                local oldDestroyIsValid = ISDestroyCursor.isValid
                ISDestroyCursor.isValid = function(self, square)
                    if isSquareProtectedByRewardCrate(square) then
                        return false
                    end
                    return oldDestroyIsValid(self, square)
                end
            end

            if ISDestroyCursor.create then
                local oldDestroyCreate = ISDestroyCursor.create
                ISDestroyCursor.create = function(self, x, y, z, north, sprite)
                    local sq = getCell():getGridSquare(x, y, z)
                    if isSquareProtectedByRewardCrate(sq) then
                        showBlockedHalo(self.character)
                        return
                    end
                    return oldDestroyCreate(self, x, y, z, north, sprite)
                end
            end
        end

        -- Also prevent the moveable placement/pickup cursor from targeting reward crates.
        if ISMoveableCursor and ISMoveableCursor.isValid then
            local oldIsValid = ISMoveableCursor.isValid
            ISMoveableCursor.isValid = function(self, square)
                if not square then return oldIsValid(self, square) end
                refreshKeys()
                for i = 0, square:getObjects():size() - 1 do
                    local obj = square:getObjects():get(i)
                    if obj and obj:getContainer() then
                        local sq = obj:getSquare()
                        if sq and isProtectedSquare(sq:getX(), sq:getY(), sq:getZ()) then
                            return false
                        end
                    end
                end
                return oldIsValid(self, square)
            end
        end
    end)
end
