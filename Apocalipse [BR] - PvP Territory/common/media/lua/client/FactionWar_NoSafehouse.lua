require "FactionZones"

-- Prevents buildings inside territory zones from being claimed as safehouses.

local function getBlockedMessage()
    if getTextOrNull then
        local text = getTextOrNull("IGUI_FactionWar_NoSafehouse")
        if text then return text end
    end
    return "This building cannot be claimed as a safehouse."
end

local function isInTerritoryZone(x, y, z)
    if not FactionZones or not FactionZones.getZoneAt then
        return false
    end
    return FactionZones.getZoneAt(x, y, z) ~= nil
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local sq = player:getCurrentSquare()
    if not sq then return end

    if not isInTerritoryZone(sq:getX(), sq:getY(), sq:getZ()) then return end

    local claimText = getText("ContextMenu_SafehouseClaim")
    local option = context:getOptionFromName(claimText)
    if option then
        option.notAvailable = true
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = getBlockedMessage()
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
