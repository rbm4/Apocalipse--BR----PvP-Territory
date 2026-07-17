-- =======================================================
-- FILE: media/lua/client/AdminZoneCreator.lua
-- DESCR: Handles container context menu linking to reward crates
-- =======================================================

if isServer() then return end

require "FactionZones"

local function OnRightClickContext(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    
    local _access = player:getAccessLevel() or ""
    local isAdmin = _access:lower() == "admin"
    local isDebug = getCore() and getCore():getDebug() or false
    if isCoopHost and isCoopHost() then isAdmin = true end
    if isDebug then isAdmin = true end
    
    if not isAdmin then return end

    -- Scan clicked objects for a container (Crate, Fridge, Shelf, etc.)
    local clickedContainer = nil
    for _, obj in ipairs(worldobjects) do
        if obj:getContainer() then
            clickedContainer = obj
            break
        end
    end

    if clickedContainer then
        local option = context:addOption("Faction Control: Link Reward Crate", worldobjects, nil)
        local subMenu = context:getNew(context)
        context:addSubMenu(option, subMenu)
        
        local zonesExist = false
        
        local function linkCrate(zoneID, zoneName)
            local sq = clickedContainer:getSquare()
            if sq then
                local args = { zoneID = zoneID, x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                sendClientCommand(player, "FactionWar", "SetRewardContainer", args)
                player:Say("Reward Container Linked to zone '" .. zoneName .. "'!")
            end
        end

        -- Add dynamic zones from ClientCache
        if FactionZones and FactionZones.ClientCache then
            -- Sort zones by name for usability
            local sortedZones = {}
            for id, z in pairs(FactionZones.ClientCache) do
                table.insert(sortedZones, { id = id, name = z.name or id })
            end
            table.sort(sortedZones, function(a, b) return a.name < b.name end)
            
            for _, z in ipairs(sortedZones) do
                zonesExist = true
                subMenu:addOption(z.name, worldobjects, function() linkCrate(z.id, z.name) end)
            end
        end
        
        -- Add hardcoded zones
        if FactionZones and FactionZones.List then
            for _, z in ipairs(FactionZones.List) do
                zonesExist = true
                local zName = z.name or z.id
                subMenu:addOption(zName .. " (Default)", worldobjects, function() linkCrate(z.id, zName) end)
            end
        end
        
        if not zonesExist then
            local subOption = subMenu:addOption("No dynamic zones found", worldobjects, nil)
            subOption.notClickable = true
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(OnRightClickContext)