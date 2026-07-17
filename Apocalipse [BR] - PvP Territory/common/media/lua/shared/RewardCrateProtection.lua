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
        local msg = getText("IGUI_RewardCrate_Protected")
        if not msg or msg == "IGUI_RewardCrate_Protected" then
            msg = "Reward crate cannot be moved or destroyed."
        end
        return msg
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

    -- Also prevent the moveable placement/pickup cursor from targeting reward crates.
    Events.OnGameStart.Add(function()
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
