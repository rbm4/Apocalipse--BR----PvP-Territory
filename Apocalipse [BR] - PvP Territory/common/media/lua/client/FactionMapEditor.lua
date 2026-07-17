-- =======================================================
-- FILE: media/lua/client/FactionMapEditor.lua
-- DESCR: Unified Faction & Territory Control Panel
-- =======================================================

if isServer() then return end

require "ISUI/Maps/ISWorldMap"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISLabel"
require "ISUI/ISModalRichText"
require "ISUI/ISTabPanel"
require "ISUI/ISTextBox"
require "FactionZones"

FactionMapWidget = ISPanel:derive("FactionMapWidget")
FactionControlPanelUI = ISCollapsableWindow:derive("FactionControlPanelUI")
FactionControlPanelInstance = nil

local LocalStatusCache = {}

-- Helper to check admin status
local function getIsAdmin()
    local player = getPlayer()
    if not player then return false end
    local access = player:getAccessLevel() or ""
    local isAdmin = access:lower() == "admin"
    local isDebug = getCore() and getCore():getDebug() or false
    if isCoopHost and isCoopHost() then isAdmin = true end
    if isDebug then isAdmin = true end
    return isAdmin
end
local function hasAdminAccessLevel()
    local player = getPlayer()
    if not player then return false end
    local access = player:getAccessLevel() or ""
    return access:lower() == "admin"
end

local ZONE_TYPE_TEXT_KEYS = {
    Standard = "IGUI_perks_FW_ZoneStandard",
    Armory = "IGUI_perks_FW_ZoneArmory",
    Hospital = "IGUI_perks_FW_ZoneHospital",
    Workshop = "IGUI_perks_FW_ZoneWorkshop",
    Bunker = "IGUI_perks_FW_ZoneBunker",
    Industrial = "IGUI_perks_FW_ZoneIndustrial",
    Estacao = "IGUI_perks_FW_ZoneEstacao",
    Umbrella = "IGUI_perks_FW_ZoneUmbrella",
    Posto = "IGUI_perks_FW_ZonePosto",
}

local function getZoneTypeText(zoneType)
    return getText(ZONE_TYPE_TEXT_KEYS[zoneType] or ZONE_TYPE_TEXT_KEYS.Standard)
end
-- Helper to resolve zone colors on the map
local function resolveColor(zoneData)
    local owner = zoneData and zoneData.owner or "Neutral"
    if owner == "Neutral" or owner == "Nomad" then
        return 0.5, 0.5, 0.5
    end
    if FactionColors and FactionColors[owner] then
        local c = FactionColors[owner]
        return c.r, c.g, c.b
    end
    if owner == "RED" then return 0.8, 0.1, 0.1
    elseif owner == "BLUE" then return 0.1, 0.1, 0.8
    end
    return 0.2, 0.8, 0.2
end


-- =======================================================
-- 1. Embedded Map Widget Control
-- =======================================================
function FactionMapWidget:new(x, y, width, height, editorUI)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.editorUI = editorUI
    o.dragging = false
    o.dragMoved = false
    o.drawingDrag = false
    return o
end

function FactionMapWidget:instantiate()
    self.javaObject = UIWorldMap.new(self)
    self.mapAPI = self.javaObject:getAPIv3()
    self.mapAPI:setMapItem(MapItem.getSingleton())
    
    self.javaObject:setX(self.x)
    self.javaObject:setY(self.y)
    self.javaObject:setWidth(self.width)
    self.javaObject:setHeight(self.height)
    self.javaObject:setAnchorLeft(self.anchorLeft or true)
    self.javaObject:setAnchorRight(self.anchorRight or false)
    self.javaObject:setAnchorTop(self.anchorTop or true)
    self.javaObject:setAnchorBottom(self.anchorBottom or false)
end

function FactionMapWidget:initDataAndStyle()
    local mapAPI = self.mapAPI
    MapUtils.initDefaultMapData(self)
    mapAPI:setBoundsFromWorld()
    MapUtils.initDefaultStreetData(self)
    MapUtils.initDefaultStyleV3(self)
    -- MapUtils.overlayPaper(self) -- Commented out to make the map brighter and less grey
    mapAPI:getSymbolsAPIv2():initDefaultAnnotations()
end

function FactionMapWidget:drawTextureAllPoint(texture, tlx, tly, trx, try, brx, bry, blx, bly, r,g,b,a)
    local ax = self:getAbsoluteX()
    local ay = self:getAbsoluteY()
    ISUIElement.drawTextureAllPoint(self, texture, tlx + ax, tly + ay, trx + ax, try + ay, brx + ax, bry + ay, blx + ax, bly + ay, r, g, b, a)
end

function FactionMapWidget:onMouseDown(x, y)
    if self.editorUI.drawingDrag then
        local wx = self.mapAPI:uiToWorldX(x, y)
        local wy = self.mapAPI:uiToWorldY(x, y)
        self.editorUI.startX = math.floor(wx)
        self.editorUI.startY = math.floor(wy)
        self.editorUI.endX = math.floor(wx)
        self.editorUI.endY = math.floor(wy)
        self.editorUI:updateCoordFields()
        self.drawingDrag = true
        return true
    end
    
    -- Panning
    self.dragging = true
    self.dragMoved = false
    self.dragStartX = x
    self.dragStartY = y
    self.dragStartCX = self.mapAPI:getCenterWorldX()
    self.dragStartCY = self.mapAPI:getCenterWorldY()
    self.dragStartZoomF = self.mapAPI:getZoomF()
    self.dragStartWorldX = self.mapAPI:uiToWorldX(x, y)
    self.dragStartWorldY = self.mapAPI:uiToWorldY(x, y)
    return true
end

function FactionMapWidget:onMouseMove(dx, dy)
    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()
    
    if self.editorUI.drawingDrag and self.drawingDrag then
        local wx = self.mapAPI:uiToWorldX(mouseX, mouseY)
        local wy = self.mapAPI:uiToWorldY(mouseX, mouseY)
        self.editorUI.endX = math.floor(wx)
        self.editorUI.endY = math.floor(wy)
        self.editorUI:updateCoordFields()
        return true
    end
    
    if self.dragging then
        if not self.dragMoved and math.abs(mouseX - self.dragStartX) <= 4 and math.abs(mouseY - self.dragStartY) <= 4 then
            return true
        end
        self.dragMoved = true
        local worldX = self.mapAPI:uiToWorldX(mouseX, mouseY, self.dragStartZoomF, self.dragStartCX, self.dragStartCY)
        local worldY = self.mapAPI:uiToWorldY(mouseX, mouseY, self.dragStartZoomF, self.dragStartCX, self.dragStartCY)
        self.mapAPI:centerOn(self.dragStartCX + self.dragStartWorldX - worldX, self.dragStartCY + self.dragStartWorldY - worldY)
    end
    return true
end

function FactionMapWidget:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function FactionMapWidget:onMouseUp(x, y)
    if self.editorUI.drawingDrag and self.drawingDrag then
        local wx = self.mapAPI:uiToWorldX(x, y)
        local wy = self.mapAPI:uiToWorldY(x, y)
        self.editorUI.endX = math.floor(wx)
        self.editorUI.endY = math.floor(wy)
        self.editorUI:updateCoordFields()
        self.drawingDrag = false
        self.editorUI.drawingDrag = false
        local player = getPlayer()
        if player then player:Say(getText("IGUI_FactionMapEditor_Say_CoordinatesUpdated")) end
        return true
    end
    
    self.dragging = false
    return true
end

function FactionMapWidget:onMouseUpOutside(x, y)
    self.drawingDrag = false
    self.dragging = false
    return true
end

function FactionMapWidget:onMouseWheel(del)
    self.mapAPI:zoomAt(self:getMouseX(), self:getMouseY(), del)
    return true
end

function FactionMapWidget:onRightMouseDown(x, y)
    return true
end

function FactionMapWidget:onRightMouseUp(x, y)
    if self.editorUI.drawingDrag or self.drawingDrag then
        self.editorUI.drawingDrag = false
        self.drawingDrag = false
        self.dragging = false
        local player = getPlayer()
        if player then player:Say(getText("IGUI_FactionMapEditor_Say_DrawingCancelled")) end
        return true
    end

    local wx = math.floor(self.mapAPI:uiToWorldX(x, y))
    local wy = math.floor(self.mapAPI:uiToWorldY(x, y))
    
    local player = getPlayer()
    if not player then return false end
    if not getIsAdmin() then return false end

    -- Screen coordinates of context menu
    local screenX = x + self:getAbsoluteX()
    local screenY = y + self:getAbsoluteY()
    local context = ISContextMenu.get(player:getPlayerNum(), screenX, screenY)
    
    local clickedZone = FactionZones.getZoneAt(wx, wy)
    if clickedZone then
        context:addOption(getText("IGUI_FactionMapEditor_Context_Zone") .. clickedZone.name, nil, nil)
        
        context:addOption("  " .. getText("IGUI_FactionMapEditor_RenameZone"), self.editorUI, function()
            self.editorUI:renameZoneByID(clickedZone)
        end)
        
        -- Change Type submenu
        local typeOption = context:addOption("  " .. getText("IGUI_FactionMapEditor_ChangeZoneType"), nil, nil)
        local typeMenu = context:getNew(context)
        context:addSubMenu(typeOption, typeMenu)
        typeMenu:addOption(getZoneTypeText("Armory"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Armory") end)
        typeMenu:addOption(getZoneTypeText("Hospital"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Hospital") end)
        typeMenu:addOption(getZoneTypeText("Workshop"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Workshop") end)
        typeMenu:addOption(getZoneTypeText("Standard"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Standard") end)
        typeMenu:addOption(getZoneTypeText("Bunker"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Bunker") end)
        typeMenu:addOption(getZoneTypeText("Industrial"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Industrial") end)
        typeMenu:addOption(getZoneTypeText("Estacao"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Estacao") end)
        typeMenu:addOption(getZoneTypeText("Umbrella"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Umbrella") end)
        typeMenu:addOption(getZoneTypeText("Posto"), clickedZone, function() self.editorUI:changeZoneTypeByID(clickedZone.id, "Posto") end)
        
        context:addOption("  " .. getText("IGUI_FactionMapEditor_DeleteZone"), self.editorUI, function()
            self.editorUI:deleteZoneByID(clickedZone)
        end)
    else
        context:addOption(getText("IGUI_FactionMapEditor_Context_Coordinates") .. wx .. ", " .. wy, nil, nil)
        
        context:addOption("  " .. getText("IGUI_FactionMapEditor_SetZoneStartHere"), self.editorUI, function()
            self.editorUI.startX = wx
            self.editorUI.startY = wy
            self.editorUI:updateCoordFields()
            player:Say(string.format(getText("IGUI_FactionMapEditor_Say_StartCoordinatesSet"), wx, wy))
        end)
        
        context:addOption("  " .. getText("IGUI_FactionMapEditor_SetZoneEndHere"), self.editorUI, function()
            self.editorUI.endX = wx
            self.editorUI.endY = wy
            self.editorUI:updateCoordFields()
            player:Say(string.format(getText("IGUI_FactionMapEditor_Say_EndCoordinatesSet"), wx, wy))
        end)
        
    end
    
    return true
end

function FactionMapWidget:drawZoneOnMapWidget(zone, whiteTex)
    if not zone then return end
    
    local x1 = tonumber(zone.x1) or 0
    local y1 = tonumber(zone.y1) or 0
    local x2 = tonumber(zone.x2) or 0
    local y2 = tonumber(zone.y2) or 0
    
    local p1x = self.mapAPI:worldToUIX(x1, y1)
    local p1y = self.mapAPI:worldToUIY(x1, y1)
    local p2x = self.mapAPI:worldToUIX(x2, y1)
    local p2y = self.mapAPI:worldToUIY(x2, y1)
    local p3x = self.mapAPI:worldToUIX(x2, y2)
    local p3y = self.mapAPI:worldToUIY(x2, y2)
    local p4x = self.mapAPI:worldToUIX(x1, y2)
    local p4y = self.mapAPI:worldToUIY(x1, y2)
    
    if not (p1x and p1y and p2x and p2y and p3x and p3y and p4x and p4y) then return end
    
    -- Resolve color
    local r, g, b = 0.5, 0.5, 0.5
    local owner = zone.owner or "Neutral"
    
    local zoneData = LocalStatusCache[zone.id]
    if zoneData then
        owner = zoneData.owner or owner
        if zoneData.col then
            r, g, b = zoneData.col.r, zoneData.col.g, zoneData.col.b
        end
    end
    
    if owner == "Neutral" or owner == "Nomad" then
        r, g, b = 0.5, 0.5, 0.5
    elseif owner == "RED" then
        r, g, b = 0.8, 0.1, 0.1
    elseif owner == "BLUE" then
        r, g, b = 0.1, 0.1, 0.8
    else
        r, g, b = 0.2, 0.8, 0.2
    end
    
    -- Draw filled area
    self:drawTextureAllPoint(whiteTex, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, r, g, b, 0.15)
    -- Draw outlines
    self:drawTextureAllPoint(whiteTex, p1x-1, p1y-1, p2x-1, p2y-1, p3x-1, p3y-1, p4x-1, p4y-1, r, g, b, 0.5)
    
    -- Draw name label
    local cx = (p1x + p2x + p3x + p4x) / 4
    local cy = (p1y + p2y + p3y + p4y) / 4
    local nameText = (zone.name or zone.id) .. " [" .. owner .. "]"
    
    self:drawTextCentre(nameText, cx + 1, cy - 6 + 1, 0, 0, 0, 1.0, UIFont.Small)
    self:drawTextCentre(nameText, cx, cy - 6, 1.0, r + 0.3, g + 0.3, b + 0.3, UIFont.Small)
end

function FactionMapWidget:prerender()
    ISPanel.prerender(self)
end

function FactionMapWidget:render()
    ISPanel.render(self)
    
    local whiteTex = Texture.getSharedTexture("media/ui/white.png") or Texture.getWhite()
    
    -- 1. Draw existing zones
    if whiteTex then
        if FactionZones and FactionZones.ClientCache then
            for id, zone in pairs(FactionZones.ClientCache) do
                self:drawZoneOnMapWidget(zone, whiteTex)
            end
        end
        if FactionZones and FactionZones.List then
            for _, zone in ipairs(FactionZones.List) do
                self:drawZoneOnMapWidget(zone, whiteTex)
            end
        end
    end
    
    -- 2. Draw instructions banner if in Drag Draw mode
    if self.editorUI.drawingDrag then
        local bannerW = self:getWidth() - 20
        local bannerH = 45
        local bannerX = 10
        local bannerY = 10
        
        self:drawRect(bannerX, bannerY, bannerW, bannerH, 0.85, 0.08, 0.08, 0.1)
        self:drawRect(bannerX, bannerY, bannerW, 2, 0.95, 0.2, 0.8, 0.2)
        self:drawRectBorder(bannerX, bannerY, bannerW, bannerH, 0.4, 0.3, 0.3, 0.3)
        
        self:drawTextCentre(getText("IGUI_FactionMapEditor_DrawZoneBanner"), self:getWidth() / 2, bannerY + 6, 0.2, 0.8, 0.2, 1.0, UIFont.Medium)
        self:drawTextCentre(getText("IGUI_FactionMapEditor_DrawZoneHint"), self:getWidth() / 2, bannerY + 24, 0.9, 0.9, 0.9, 1.0, UIFont.Small)
    end
    
    -- 3. Draw Start / End crosshairs
    if self.editorUI.startX and self.editorUI.startY then
        local sx = self.mapAPI:worldToUIX(self.editorUI.startX, self.editorUI.startY)
        local sy = self.mapAPI:worldToUIY(self.editorUI.startX, self.editorUI.startY)
        if sx and sy and sx >= 0 and sx <= self:getWidth() and sy >= 0 and sy <= self:getHeight() then
            self:drawRect(sx - 10, sy - 1, 20, 3, 0.9, 0.9, 0.1, 0.8)
            self:drawRect(sx - 1, sy - 10, 3, 20, 0.9, 0.9, 0.1, 0.8)
            self:drawTextCentre(getText("IGUI_FactionMapEditor_StartMarker"), sx, sy - 20, 0.9, 0.9, 0.1, 1.0, UIFont.Small)
        end
    end
    
    if self.editorUI.endX and self.editorUI.endY then
        local sx = self.mapAPI:worldToUIX(self.editorUI.endX, self.editorUI.endY)
        local sy = self.mapAPI:worldToUIY(self.editorUI.endX, self.editorUI.endY)
        if sx and sy and sx >= 0 and sx <= self:getWidth() and sy >= 0 and sy <= self:getHeight() then
            self:drawRect(sx - 10, sy - 1, 20, 3, 0.9, 0.1, 0.9, 0.8)
            self:drawRect(sx - 1, sy - 10, 3, 20, 0.9, 0.1, 0.9, 0.8)
            self:drawTextCentre(getText("IGUI_FactionMapEditor_EndMarker"), sx, sy - 20, 0.9, 0.1, 0.9, 1.0, UIFont.Small)
        end
    end
    
    -- 4. Draw preview selection box
    if self.editorUI.startX and self.editorUI.startY and self.editorUI.endX and self.editorUI.endY then
        local p1x = self.mapAPI:worldToUIX(self.editorUI.startX, self.editorUI.startY)
        local p1y = self.mapAPI:worldToUIY(self.editorUI.startX, self.editorUI.startY)
        local p2x = self.mapAPI:worldToUIX(self.editorUI.endX, self.editorUI.startY)
        local p2y = self.mapAPI:worldToUIY(self.editorUI.endX, self.editorUI.startY)
        local p3x = self.mapAPI:worldToUIX(self.editorUI.endX, self.editorUI.endY)
        local p3y = self.mapAPI:worldToUIY(self.editorUI.endX, self.editorUI.endY)
        local p4x = self.mapAPI:worldToUIX(self.editorUI.startX, self.editorUI.endY)
        local p4y = self.mapAPI:worldToUIY(self.editorUI.startX, self.editorUI.endY)
        
        if p1x and p1y and p2x and p2y and p3x and p3y and p4x and p4y and whiteTex then
            self:drawTextureAllPoint(whiteTex, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, 0.0, 1.0, 0.0, 0.25)
            self:drawTextureAllPoint(whiteTex, p1x-1, p1y-1, p2x-1, p2y-1, p3x-1, p3y-1, p4x-1, p4y-1, 0.0, 1.0, 0.0, 0.8)
            
            local wTiles = math.floor(math.abs(self.editorUI.endX - self.editorUI.startX))
            local hTiles = math.floor(math.abs(self.editorUI.endY - self.editorUI.startY))
            local sizeStr = string.format(getText("IGUI_FactionMapEditor_SelectedSize"), wTiles, hTiles, wTiles * hTiles)
            local midX = (p1x + p3x) / 2
            local midY = (p1y + p3y) / 2
            
            self:drawTextCentre(sizeStr, midX + 1, midY + 1, 0, 0, 0, 1.0, UIFont.Small)
            self:drawTextCentre(sizeStr, midX, midY, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        end
    end
end


-- =======================================================
-- 2. Unified Faction & Territory Control Panel UI
-- =======================================================
function FactionControlPanelUI:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("IGUI_FactionMapEditor_WindowTitle")
    o.pin = true
    o.startX = nil
    o.startY = nil
    o.endX = nil
    o.endY = nil
    o.drawingDrag = false
    
    -- Load faction state
    local player = getPlayer()
    local myFaction = "Nomad"
    local isLeader = false
    if player then
        local username = player:getUsername()
        if Faction and Faction.getPlayerFaction then
            local fac = Faction.getPlayerFaction(username)
            if fac then
                myFaction = fac:getName()
                if fac:getOwner() == username or player:getAccessLevel() == "Admin" then
                    isLeader = true
                end
            end
        end
    end
    o.myFactionName = myFaction
    o.isLeader = isLeader
    return o
end

function FactionControlPanelUI:initialise()
    ISCollapsableWindow.initialise(self)
    
    local pad = 10
    local width = self:getWidth()
    local height = self:getHeight()
    
    -- Setup main tab panel
    self.tabPanel = ISTabPanel:new(pad, 30, width - pad*2, height - 40)
    self.tabPanel:initialise()
    self:addChild(self.tabPanel)
    
    -- ====================================================
    -- TAB 1: DIPLOMACY & ZONES (Visible to ALL players)
    -- ====================================================
    self.diplomacyZonesView = ISPanel:new(0, 0, self.tabPanel:getWidth(), self.tabPanel:getHeight() - self.tabPanel.tabHeight)
    self.diplomacyZonesView:initialise()
    self.diplomacyZonesView.backgroundColor = {r=0.08, g=0.08, b=0.1, a=0.95}
    
    -- Left Section: Factions (Diplomacy)
    local colW = (self.diplomacyZonesView:getWidth() - pad*3) / 2
    local listH = self.diplomacyZonesView:getHeight() - 75
    
    local labelAlliances = ISLabel:new(pad, 10, 18, getText("IGUI_FactionMapEditor_AlliancesLabel"), 1, 1, 1, 1, UIFont.Small, true)
    labelAlliances:initialise()
    self.diplomacyZonesView:addChild(labelAlliances)
    
    self.factionList = ISScrollingListBox:new(pad, 30, colW, listH)
    self.factionList:initialise()
    self.factionList:instantiate()
    self.factionList.itemheight = 40
    self.factionList.selected = 0
    self.factionList.joypadParent = self
    self.factionList.font = UIFont.Small
    self.factionList.doDrawItem = self.drawFactionItem
    self.factionList.drawBorder = true
    self.diplomacyZonesView:addChild(self.factionList)
    
    self.actionBtn = ISButton:new(pad, 30 + listH + 8, colW * 0.48, 25, getText("IGUI_FactionMapEditor_Action"), self, self.onAction)
    self.actionBtn:initialise()
    self.actionBtn:instantiate()
    self.actionBtn:setEnable(false)
    self.diplomacyZonesView:addChild(self.actionBtn)
    
    self.declineBtn = ISButton:new(pad + colW * 0.52, 30 + listH + 8, colW * 0.48, 25, getText("IGUI_FactionMapEditor_DeclineInvite"), self, self.onDecline)
    self.declineBtn:initialise()
    self.declineBtn:instantiate()
    self.declineBtn:setVisible(false)
    self.diplomacyZonesView:addChild(self.declineBtn)
    
    -- Right Section: Zones Status
    local rightColX = pad * 2 + colW
    local labelZones = ISLabel:new(rightColX, 10, 18, getText("IGUI_FactionMapEditor_ZonesOverviewLabel"), 1, 1, 1, 1, UIFont.Small, true)
    labelZones:initialise()
    self.diplomacyZonesView:addChild(labelZones)
    
    self.zoneList = ISScrollingListBox:new(rightColX, 30, colW, listH)
    self.zoneList:initialise()
    self.zoneList:instantiate()
    self.zoneList.itemheight = 25
    self.zoneList.selected = 0
    self.zoneList.joypadParent = self
    self.zoneList.font = UIFont.Small
    self.zoneList.doDrawItem = self.drawZoneItemPlayer
    self.zoneList.drawBorder = true
    self.diplomacyZonesView:addChild(self.zoneList)
    
    self.tabPanel:addView(getText("IGUI_FactionMapEditor_Tab_DiplomacyZones"), self.diplomacyZonesView)
    
    -- ====================================================
    -- TAB 2: TERRITORY EDITOR (Visible only to admin access level)
    -- ====================================================
    if hasAdminAccessLevel() then
        self.editorView = ISPanel:new(0, 0, self.tabPanel:getWidth(), self.tabPanel:getHeight() - self.tabPanel.tabHeight)
        self.editorView:initialise()
        self.editorView.backgroundColor = {r=0.08, g=0.08, b=0.1, a=0.95}
        
        -- Map Widget (Left) - Upscaled to 600 width and 565 height
        local mapW = 600
        local mapH = self.editorView:getHeight() - pad*2
        self.mapWidget = FactionMapWidget:new(pad, pad, mapW, mapH, self)
        self.mapWidget:initialise()
        self.editorView:addChild(self.mapWidget)
        
        -- Control Tabs Panel (Right) - Positioned at X=620 with 350 width
        local controlX = pad * 2 + mapW
        local controlW = self.editorView:getWidth() - controlX - pad
        local controlH = self.editorView:getHeight() - pad*2
        
        self.editorControlTabPanel = ISTabPanel:new(controlX, pad, controlW, controlH)
        self.editorControlTabPanel:initialise()
        self.editorView:addChild(self.editorControlTabPanel)
        
        -- Sub-tab 1: Create Zone
        self.createZonePanel = ISPanel:new(0, 0, self.editorControlTabPanel:getWidth(), self.editorControlTabPanel:getHeight() - self.editorControlTabPanel.tabHeight)
        self.createZonePanel:initialise()
        self.createZonePanel.backgroundColor = {r=0.06, g=0.06, b=0.08, a=0.95}
        
        local labelX = 10
        local entryX = 120
        local entryW = controlW - entryX - 15
        local labelH = 18
        local spacingY = 32
        
        -- Zone Name
        local nameLabel = ISLabel:new(labelX, 15, labelH, getText("IGUI_FactionMapEditor_NameLabel"), 1, 1, 1, 1, UIFont.Small, true)
        nameLabel:initialise()
        self.createZonePanel:addChild(nameLabel)
        
        self.nameEntry = ISTextEntryBox:new(getText("IGUI_FactionMapEditor_DefaultZoneName"), entryX, 15, entryW, labelH)
        self.nameEntry:initialise()
        self.nameEntry:instantiate()
        self.createZonePanel:addChild(self.nameEntry)
        
        -- Zone Type
        local typeLabel = ISLabel:new(labelX, 15 + spacingY, labelH, getText("IGUI_FactionMapEditor_TypeLabel"), 1, 1, 1, 1, UIFont.Small, true)
        typeLabel:initialise()
        self.createZonePanel:addChild(typeLabel)
        
        self.typeCombo = ISComboBox:new(entryX, 15 + spacingY, entryW, labelH)
        self.typeCombo:initialise()
        self.typeCombo:instantiate()
        self.zoneTypeOptions = {"Standard", "Armory", "Hospital", "Workshop", "Bunker", "Industrial", "Estacao", "Umbrella", "Posto"}
        for _, zoneType in ipairs(self.zoneTypeOptions) do
            self.typeCombo:addOption(getZoneTypeText(zoneType))
        end
        self.createZonePanel:addChild(self.typeCombo)
        
        -- Z Elevation
        local zLabel = ISLabel:new(labelX, 15 + spacingY*2, labelH, getText("IGUI_FactionMapEditor_ElevationLabel"), 1, 1, 1, 1, UIFont.Small, true)
        zLabel:initialise()
        self.createZonePanel:addChild(zLabel)
        
        self.zEntry = ISTextEntryBox:new("0", entryX, 15 + spacingY*2, 50, labelH)
        self.zEntry:initialise()
        self.zEntry:instantiate()
        self.createZonePanel:addChild(self.zEntry)
        
        -- Start coords
        local startLabel = ISLabel:new(labelX, 15 + spacingY*3, labelH, getText("IGUI_FactionMapEditor_StartCoordsLabel"), 1, 1, 1, 1, UIFont.Small, true)
        startLabel:initialise()
        self.createZonePanel:addChild(startLabel)
        
        self.x1Entry = ISTextEntryBox:new("0", entryX, 15 + spacingY*3, 50, labelH)
        self.x1Entry:initialise()
        self.x1Entry:instantiate()
        self.createZonePanel:addChild(self.x1Entry)
        
        self.y1Entry = ISTextEntryBox:new("0", entryX + 55, 15 + spacingY*3, 50, labelH)
        self.y1Entry:initialise()
        self.y1Entry:instantiate()
        self.createZonePanel:addChild(self.y1Entry)
        
        -- End coords
        local endLabel = ISLabel:new(labelX, 15 + spacingY*4, labelH, getText("IGUI_FactionMapEditor_EndCoordsLabel"), 1, 1, 1, 1, UIFont.Small, true)
        endLabel:initialise()
        self.createZonePanel:addChild(endLabel)
        
        self.x2Entry = ISTextEntryBox:new("0", entryX, 15 + spacingY*4, 50, labelH)
        self.x2Entry:initialise()
        self.x2Entry:instantiate()
        self.createZonePanel:addChild(self.x2Entry)
        
        self.y2Entry = ISTextEntryBox:new("0", entryX + 55, 15 + spacingY*4, 50, labelH)
        self.y2Entry:initialise()
        self.y2Entry:instantiate()
        self.createZonePanel:addChild(self.y2Entry)
        
        -- Drag Draw Button
        self.btnDrawDrag = ISButton:new(labelX, 15 + spacingY*5.5, controlW - 20, 25, getText("IGUI_FactionMapEditor_DrawOnMapButton"), self, function()
            self.drawingDrag = true
            self.startX = nil
            self.startY = nil
            self.endX = nil
            self.endY = nil
            self.x1Entry:setText("0")
            self.y1Entry:setText("0")
            self.x2Entry:setText("0")
            self.y2Entry:setText("0")
            local player = getPlayer()
            if player then player:Say(getText("IGUI_FactionMapEditor_Say_DrawInstructions")) end
        end)
        self.btnDrawDrag:initialise()
        self.btnDrawDrag:instantiate()
        self.btnDrawDrag.backgroundColor = {r=0.2, g=0.4, b=0.6, a=1.0}
        self.createZonePanel:addChild(self.btnDrawDrag)
        
        -- Create Button
        self.btnCreate = ISButton:new(labelX, 15 + spacingY*6.8, controlW - 20, 25, getText("IGUI_FactionMapEditor_CreateZoneButton"), self, self.onCreateZone)
        self.btnCreate:initialise()
        self.btnCreate:instantiate()
        self.btnCreate.backgroundColor = {r=0.1, g=0.5, b=0.1, a=1.0}
        self.createZonePanel:addChild(self.btnCreate)
        
        self.editorControlTabPanel:addView(getText("IGUI_FactionMapEditor_Tab_CreateZone"), self.createZonePanel)
        
        -- Sub-tab 2: Manage Zones (Admin)
        self.manageZonesPanel = ISPanel:new(0, 0, self.editorControlTabPanel:getWidth(), self.editorControlTabPanel:getHeight() - self.editorControlTabPanel.tabHeight)
        self.manageZonesPanel:initialise()
        self.manageZonesPanel.backgroundColor = {r=0.06, g=0.06, b=0.08, a=0.95}
        
        self.adminZoneList = ISScrollingListBox:new(10, 10, controlW - 20, 260)
        self.adminZoneList:initialise()
        self.adminZoneList:instantiate()
        self.adminZoneList.itemheight = 25
        self.adminZoneList.selected = 0
        self.adminZoneList.joypadParent = self
        self.adminZoneList.font = UIFont.Small
        self.adminZoneList.doDrawItem = self.drawZoneItemAdmin
        self.adminZoneList.drawBorder = true
        self.manageZonesPanel:addChild(self.adminZoneList)
        
        -- Actions
        local btnW = controlW - 30
        local btnH = 22
        
        self.btnRename = ISButton:new(15, 285 + 26, btnW, btnH, getText("IGUI_FactionMapEditor_RenameZone"), self, self.onRenameZone)
        self.btnRename:initialise()
        self.btnRename:instantiate()
        self.manageZonesPanel:addChild(self.btnRename)
        
        self.btnDelete = ISButton:new(15, 285 + 52, btnW, btnH, getText("IGUI_FactionMapEditor_DeleteZone"), self, self.onDeleteZone)
        self.btnDelete:initialise()
        self.btnDelete:instantiate()
        self.btnDelete.backgroundColor = {r=0.6, g=0.1, b=0.1, a=1.0}
        self.manageZonesPanel:addChild(self.btnDelete)
        
        -- Label note for crate linking
        local noteY = 285 + 52 + 28
        self.lblLinkNote = ISLabel:new(15, noteY, 18, getText("IGUI_FactionMapEditor_CrateLinkNote"), 1, 0.9, 0.3, 1.0, UIFont.Small, true)
        self.lblLinkNote:initialise()
        self.manageZonesPanel:addChild(self.lblLinkNote)
        
        self.lblLinkNoteDetail = ISLabel:new(15, noteY + 16, 36, getText("IGUI_FactionMapEditor_CrateLinkNoteDetail"), 0.8, 0.8, 0.8, 1.0, UIFont.Small, true)
        self.lblLinkNoteDetail:initialise()
        self.manageZonesPanel:addChild(self.lblLinkNoteDetail)
        
        self.editorControlTabPanel:addView(getText("IGUI_FactionMapEditor_Tab_ManageZones"), self.manageZonesPanel)
        
        self.tabPanel:addView(getText("IGUI_FactionMapEditor_Tab_TerritoryEditor"), self.editorView)
    end
    
    self:populateList()
    self:populateZones()
    self:populateZonesListAdmin()
end

function FactionControlPanelUI:initMap()
    if self.mapWidget then
        self.mapWidget:initDataAndStyle()
        self.mapWidget.mapAPI:setBoolean("HideUnvisited", false)
        local player = getPlayer()
        if player then
            self.mapWidget.mapAPI:centerOn(player:getX(), player:getY())
        else
            self.mapWidget.mapAPI:centerOn(10000, 10000)
        end
        self.mapWidget.mapAPI:setZoom(19.0)
    end
end

function FactionControlPanelUI:updateCoordFields()
    if self.startX then self.x1Entry:setText(tostring(self.startX)) end
    if self.startY then self.y1Entry:setText(tostring(self.startY)) end
    if self.endX then self.x2Entry:setText(tostring(self.endX)) end
    if self.endY then self.y2Entry:setText(tostring(self.endY)) end
end

-- =======================================================
-- LIST DATA POPULATORS
-- =======================================================
function FactionControlPanelUI:populateList()
    self.factionList:clear()
    
    if not Faction or not Faction.getFactions then return end
    
    local allFactions = Faction.getFactions()
    if not allFactions then return end
    
    local onlinePlayers = getOnlinePlayers()
    local onlineMap = {}
    if onlinePlayers then
        for i=0, onlinePlayers:size()-1 do
            local p = onlinePlayers:get(i)
            onlineMap[p:getUsername()] = true
        end
    end
    
    local modDataAlliances = ModData.get("FactionAlliances") or {}
    local myAlliances = modDataAlliances[self.myFactionName] or {}
    
    local modDataInvites = ModData.get("FactionAllianceInvites") or {}
    local myInvites = modDataInvites[self.myFactionName] or {}

    for i=0, allFactions:size()-1 do
        local fac = allFactions:get(i)
        local facName = fac:getName()
        
        if facName ~= self.myFactionName then
            local ownerName = fac:getOwner()
            local isOnline = onlineMap[ownerName] == true
            local isAllied = myAlliances[facName] == true
            local isInvitedMe = myInvites[facName] == true
            local isInvitedThem = modDataInvites[facName] and modDataInvites[facName][self.myFactionName] == true
            
            self.factionList:addItem(facName, {
                name = facName,
                ownerName = ownerName,
                isOnline = isOnline,
                isAllied = isAllied,
                isInvitedMe = isInvitedMe,
                isInvitedThem = isInvitedThem
            })
        end
    end
end

function FactionControlPanelUI:populateZones()
    self.zoneList:clear()
    
    local zones = {}
    if FactionZones and FactionZones.ClientCache then
        for id, z in pairs(FactionZones.ClientCache) do
            table.insert(zones, {id=id, name=z.name or id})
        end
    end
    if FactionZones and FactionZones.List then
        for _, z in ipairs(FactionZones.List) do
            table.insert(zones, {id=z.id, name=z.name})
        end
    end
    
    local allZoneStatus = LocalStatusCache
    local isCacheEmpty = true
    for _ in pairs(allZoneStatus) do isCacheEmpty = false; break end
    
    if isCacheEmpty then
        if ModData then allZoneStatus = ModData.get("FactionWarZones") or {}
        else allZoneStatus = {} end
    end
    
    if #zones == 0 then
        self.zoneList:addItem(getText("IGUI_FactionMapEditor_NoDynamicZonesDefined"), nil)
        return
    end

    table.sort(zones, function(a, b) return a.name < b.name end)

    for i, zone in ipairs(zones) do
        local status = allZoneStatus and allZoneStatus[zone.id]
        local owner = (status and status.owner) or "Neutral"
        local col = (status and status.col) or {r=0.5, g=0.5, b=0.5}
        
        local zFull = nil
        if FactionZones.ClientCache and FactionZones.ClientCache[zone.id] then
            zFull = FactionZones.ClientCache[zone.id]
        end
        
        self.zoneList:addItem(zone.name, {
            id = zone.id,
            name = zone.name,
            owner = owner,
            col = col,
            isContested = (status and status.isContested),
            isProtected = (status and status.isProtected),
            x1 = zFull and tonumber(zFull.x1) or 0,
            y1 = zFull and tonumber(zFull.y1) or 0,
            x2 = zFull and tonumber(zFull.x2) or 0,
            y2 = zFull and tonumber(zFull.y2) or 0,
            z1 = zFull and tonumber(zFull.z1) or 0
        })
    end
end

local function setButtonEnabledSafe(button, enabled)
    if button and button.setEnable then
        button:setEnable(enabled)
    end
end
function FactionControlPanelUI:populateZonesListAdmin()
    if not getIsAdmin() or not self.adminZoneList then return end
    
    self.adminZoneList:clear()
    
    local zones = {}
    if FactionZones and FactionZones.ClientCache then
        for id, z in pairs(FactionZones.ClientCache) do
            table.insert(zones, {
                id = id,
                name = z.name or id,
                x1 = tonumber(z.x1) or 0,
                y1 = tonumber(z.y1) or 0,
                x2 = tonumber(z.x2) or 0,
                y2 = tonumber(z.y2) or 0,
                z1 = tonumber(z.z1) or 0,
                zoneType = z.zoneType or "Standard",
                owner = z.owner or "Neutral"
            })
        end
    end
    
    if #zones == 0 then
        self.adminZoneList:addItem(getText("IGUI_FactionMapEditor_NoDynamicZonesFound"), nil)
        setButtonEnabledSafe(self.btnTeleport, false)
        setButtonEnabledSafe(self.btnRename, false)
        setButtonEnabledSafe(self.btnDelete, false)
        return
    end
    
    table.sort(zones, function(a, b) return a.name < b.name end)
    
    for _, z in ipairs(zones) do
        self.adminZoneList:addItem(z.name .. " [" .. getZoneTypeText(z.zoneType) .. "] (" .. z.owner .. ")", z)
    end
    
    self.adminZoneList.selected = 1
    setButtonEnabledSafe(self.btnTeleport, true)
    setButtonEnabledSafe(self.btnRename, true)
    setButtonEnabledSafe(self.btnDelete, true)
end

-- =======================================================
-- LIST RENDERING CUSTOM DRAW METHODS
-- =======================================================
function FactionControlPanelUI:drawFactionItem(y, item, alt)
    local isSelected = self.selected == item.index
    
    if isSelected then
        self:drawRect(0, y, self:getWidth(), item.height, 0.3, 0.7, 0.35, 0.15)
    elseif alt then
        self:drawRect(0, y, self:getWidth(), item.height, 0.3, 0.6, 0.5, 0.05)
    end
    
    self:drawRectBorder(0, y, self:getWidth(), item.height, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    
    local nameText = item.item.name
    local detailText = getText("IGUI_FactionMapEditor_OwnerPrefix") .. (item.item.ownerName or getText("IGUI_FactionMapEditor_Unknown"))
    
    if item.item.isAllied then
        nameText = nameText .. " [" .. getText("IGUI_FactionMapEditor_Status_Allied") .. "]"
        self:drawText(nameText, 10, y + 2, 0.2, 1.0, 0.2, 1.0, UIFont.Medium)
    elseif item.item.isInvitedMe then
        nameText = nameText .. " [" .. getText("IGUI_FactionMapEditor_Status_InvitePending") .. "]"
        self:drawText(nameText, 10, y + 2, 1.0, 0.8, 0.2, 1.0, UIFont.Medium)
    elseif item.item.isInvitedThem then
        nameText = nameText .. " [" .. getText("IGUI_FactionMapEditor_Status_InviteSent") .. "]"
        self:drawText(nameText, 10, y + 2, 0.8, 0.8, 0.8, 1.0, UIFont.Medium)
    else
        self:drawText(nameText, 10, y + 2, 1.0, 1.0, 1.0, 1.0, UIFont.Medium)
    end
    
    if item.item.isOnline then
        detailText = detailText .. " (" .. getText("IGUI_FactionMapEditor_Online") .. ")"
        self:drawText(detailText, 10, y + 20, 0.2, 0.8, 0.2, 1.0, UIFont.Small)
    else
        detailText = detailText .. " (" .. getText("IGUI_FactionMapEditor_Offline") .. ")"
        self:drawText(detailText, 10, y + 20, 0.6, 0.6, 0.6, 1.0, UIFont.Small)
    end
    
    return y + item.height
end

function FactionControlPanelUI:drawZoneItemPlayer(y, item, alt)
    if alt then
        self:drawRect(0, y, self:getWidth(), item.height, 0.3, 0.6, 0.5, 0.05)
    end
    self:drawRectBorder(0, y, self:getWidth(), item.height, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    
    local z = item.item
    if not z then
        self:drawText(item.text, 10, y + 4, 0.5, 0.5, 0.5, 1.0, UIFont.Small)
        return y + item.height
    end
    
    local nameStr = z.name or z.id
    if #nameStr > 22 then nameStr = nameStr:sub(1,21) .. "..." end
    
    local col = z.col or {r=0.5, g=0.5, b=0.5}
    self:drawRect(10, y + 8, 8, 8, 1, col.r, col.g, col.b)
    
    self:drawText(nameStr, 25, y + 4, 1, 0.9, 0.9, 0.9, UIFont.Small)
    
    local label = z.owner or getText("IGUI_FactionMapEditor_Neutral")
    local lr, lg, lb = col.r + 0.2, col.g + 0.2, col.b + 0.2
    
    if z.isContested then
        label = getText("IGUI_FactionMapEditor_Contested")
        lr, lg, lb = 1.0, 0.8, 0.1
    elseif z.isProtected then
        label = getText("IGUI_FactionMapEditor_Protected")
        lr, lg, lb = 0.4, 0.6, 1.0
    elseif z.owner == "Neutral" or z.owner == "Nomad" then
        label = getText("IGUI_FactionMapEditor_Neutral")
        lr, lg, lb = 0.5, 0.5, 0.5
    end
    
    local labelW = getTextManager():MeasureStringX(UIFont.Small, label)
    self:drawText(label, self:getWidth() - labelW - 10, y + 4, 1, lr, lg, lb, UIFont.Small)
    
    return y + item.height
end

function FactionControlPanelUI:drawZoneItemAdmin(y, item, alt)
    local isSelected = self.selected == item.index
    
    if isSelected then
        self:drawRect(0, y, self:getWidth(), item.height, 0.35, 0.2, 0.7, 0.2)
    elseif alt then
        self:drawRect(0, y, self:getWidth(), item.height, 0.15, 0.2, 0.2, 0.25)
    end
    
    self:drawRectBorder(0, y, self:getWidth(), item.height, 0.5, 0.4, 0.4, 0.4)
    
    if item.item then
        local text = item.text
        local info = item.item
        self:drawText(text, 10, y + 4, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        
        local coordsStr = string.format(getText("IGUI_FactionMapEditor_CoordsRange"), info.x1, info.y1, info.x2, info.y2)
        local coordsW = getTextManager():MeasureStringX(UIFont.Small, coordsStr)
        self:drawText(coordsStr, self:getWidth() - coordsW - 10, y + 4, 0.6, 0.6, 0.6, 1.0, UIFont.Small)
    else
        self:drawText(item.text, 10, y + 4, 0.5, 0.5, 0.5, 1.0, UIFont.Small)
    end
    
    return y + item.height
end

-- =======================================================
-- UPDATE BUTTON CONTROLS LOGIC
-- =======================================================
function FactionControlPanelUI:update()
    ISCollapsableWindow.update(self)
    
    local selectedItem = self.factionList.items[self.factionList.selected]
    if selectedItem and self.isLeader then
        self.actionBtn:setEnable(true)
        local data = selectedItem.item
        
        if data.isAllied then
            self.actionBtn:setTitle(getText("IGUI_FactionMapEditor_RevokeAlliance"))
            self.declineBtn:setVisible(false)
        elseif data.isInvitedMe then
            self.actionBtn:setTitle(getText("IGUI_FactionMapEditor_AcceptInvite"))
            self.declineBtn:setVisible(true)
        elseif data.isInvitedThem then
            self.actionBtn:setTitle(getText("IGUI_FactionMapEditor_InviteSent"))
            self.actionBtn:setEnable(false)
            self.declineBtn:setVisible(false)
        else
            self.actionBtn:setTitle(getText("IGUI_FactionMapEditor_SendInvite"))
            self.declineBtn:setVisible(false)
        end
    else
        self.actionBtn:setEnable(false)
        if not self.isLeader then
            self.actionBtn:setTitle(getText("IGUI_FactionMapEditor_LeaderOnly"))
        else
            self.actionBtn:setTitle(getText("IGUI_FactionMapEditor_Action"))
        end
        self.declineBtn:setVisible(false)
    end
end

-- =======================================================
-- ACTIONS: DIPLOMACY ACTIONS
-- =======================================================
function FactionControlPanelUI:onAction()
    if not self.isLeader then return end
    local selectedItem = self.factionList.items[self.factionList.selected]
    if not selectedItem then return end
    
    local data = selectedItem.item
    local targetFac = data.name
    
    if data.isAllied then
        sendClientCommand(self.player, "FactionWar", "SetAlliance", {
            myFaction = self.myFactionName,
            targetFaction = targetFac,
            state = false
        })
        getPlayer():Say(string.format(getText("IGUI_FactionMapEditor_Say_RevokingAlliance"), targetFac))
    elseif data.isInvitedMe then
        sendClientCommand(self.player, "FactionWar", "SetAlliance", {
            myFaction = self.myFactionName,
            targetFaction = targetFac,
            state = true
        })
        getPlayer():Say(string.format(getText("IGUI_FactionMapEditor_Say_AcceptingAlliance"), targetFac))
    else
        sendClientCommand(self.player, "FactionWar", "SendAllianceInvite", {
            myFaction = self.myFactionName,
            targetFaction = targetFac
        })
    end
end

function FactionControlPanelUI:onDecline()
    if not self.isLeader then return end
    local selectedItem = self.factionList.items[self.factionList.selected]
    if not selectedItem then return end
    local data = selectedItem.item
    local targetFac = data.name
    
    sendClientCommand(self.player, "FactionWar", "DeclineAllianceInvite", {
        myFaction = self.myFactionName,
        targetFaction = targetFac
    })
end

function FactionControlPanelUI:onTeleportPlayerZone()
    local selected = self.zoneList.items[self.zoneList.selected]
    if not selected or not selected.item then return end
    self:teleportToZoneCoords(selected.item)
end

-- =======================================================
-- ACTIONS: ZONE EDITOR ACTIONS (ADMIN)
-- =======================================================
function FactionControlPanelUI:onCreateZone()
    local name = self.nameEntry:getText()
    if not name or name == "" then
        local player = getPlayer()
        if player then player:Say(getText("IGUI_FactionMapEditor_Say_EnterZoneName")) end
        return
    end
    
    local zoneType = self.zoneTypeOptions and self.zoneTypeOptions[self.typeCombo.selected] or "Standard"
    
    local x1 = tonumber(self.x1Entry:getText())
    local y1 = tonumber(self.y1Entry:getText())
    local x2 = tonumber(self.x2Entry:getText())
    local y2 = tonumber(self.y2Entry:getText())
    local z = tonumber(self.zEntry:getText()) or 0
    
    if not x1 or not y1 or not x2 or not y2 then
        local player = getPlayer()
        if player then player:Say(getText("IGUI_FactionMapEditor_Say_ValidCoordinates")) end
        return
    end
    
    local minX = math.floor(math.min(x1, x2))
    local minY = math.floor(math.min(y1, y2))
    local maxX = math.floor(math.max(x1, x2))
    local maxY = math.floor(math.max(y1, y2))
    
    local player = getPlayer()
    if not player then return end
    
    local args = {
        name = name,
        x1 = minX,
        y1 = minY,
        z1 = z,
        x2 = maxX,
        y2 = maxY,
        z2 = z,
        zoneType = zoneType
    }
    
    sendClientCommand(player, "FactionWar", "AddZone", args)
    player:Say(string.format(getText("IGUI_FactionMapEditor_Say_CreatingZone"), name))
    
    -- Clear coordinates inputs
    self.startX = nil
    self.startY = nil
    self.endX = nil
    self.endY = nil
    self.x1Entry:setText("0")
    self.y1Entry:setText("0")
    self.x2Entry:setText("0")
    self.y2Entry:setText("0")
end

function FactionControlPanelUI:onTeleportZone()
    local selected = self.adminZoneList.items[self.adminZoneList.selected]
    if not selected or not selected.item then return end
    self:teleportToZoneCoords(selected.item)
end

function FactionControlPanelUI:onRenameZone()
    local selected = self.adminZoneList.items[self.adminZoneList.selected]
    if not selected or not selected.item then return end
    self:renameZoneByID(selected.item)
end

function FactionControlPanelUI:onDeleteZone()
    local selected = self.adminZoneList.items[self.adminZoneList.selected]
    if not selected or not selected.item then return end
    self:deleteZoneByID(selected.item)
end

-- =======================================================
-- CONTEXT MENU AND MAP RIGHT-CLICK CALLABLE HELPERS
-- =======================================================
function FactionControlPanelUI:teleportToZoneCoords(zone)
    local player = getPlayer()
    if not player or not zone then return end
    
    local cx = math.floor((zone.x1 + zone.x2) / 2)
    local cy = math.floor((zone.y1 + zone.y2) / 2)
    
    player:setX(cx)
    player:setY(cy)
    player:setZ(zone.z1 or 0)
    player:Say(string.format(getText("IGUI_FactionMapEditor_Say_TeleportedToZone"), zone.name))
end

function FactionControlPanelUI:renameZoneByID(zone)
    local player = getPlayer()
    if not player or not zone then return end
    
    local modal = ISTextBox:new(0, 0, 280, 180, getText("IGUI_FactionMapEditor_RenameZonePrompt"), zone.name, self, self.onRenameConfirmAction, player:getPlayerNum(), zone)
    modal:initialise()
    modal:addToUIManager()
end

function FactionControlPanelUI:onRenameConfirmAction(button, zone)
    if button.internal == "OK" then
        local name = button.parent.entry:getText()
        local p = getPlayer()
        if p and name and name ~= "" then
            sendClientCommand(p, "FactionWar", "RenameZone", {id = zone.id, name = name, x1 = zone.x1, y1 = zone.y1, x2 = zone.x2, y2 = zone.y2})
            p:Say(string.format(getText("IGUI_FactionMapEditor_Say_RenamingZone"), name))
        end
    end
end

function FactionControlPanelUI:changeZoneTypeByID(zoneID, zoneType)
    local player = getPlayer()
    if not player then return end
    sendClientCommand(player, "FactionWar", "ChangeZoneType", {id = zoneID, zoneType = zoneType})
    player:Say(string.format(getText("IGUI_FactionMapEditor_Say_ChangedZoneType"), getZoneTypeText(zoneType)))
end

function FactionControlPanelUI:deleteZoneByID(zone)
    local player = getPlayer()
    if not player or not zone then return end
    
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local modal = ISModalRichText:new((screenW - 300) / 2, (screenH - 150) / 2, 300, 150, string.format(getText("IGUI_FactionMapEditor_DeleteZoneConfirm"), zone.name), true, self, self.onDeleteConfirmAction, player:getPlayerNum(), zone.id)
    modal:initialise()
    modal:addToUIManager()
end

function FactionControlPanelUI:onDeleteConfirmAction(button, zoneID)
    if button.internal == "YES" then
        local p = getPlayer()
        if p then
            sendClientCommand(p, "FactionWar", "DeleteZone", {id = zoneID})
            p:Say(getText("IGUI_FactionMapEditor_Say_ZoneDeleted"))
        end
    end
end

-- =======================================================
-- SYSTEM CONTROLS
-- =======================================================
function FactionControlPanelUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if FactionControlPanelInstance == self then
        FactionControlPanelInstance = nil
    end
end

function FactionControlPanelUI:prerender()
    ISCollapsableWindow.prerender(self)
    local tex = Texture.getSharedTexture("media/ui/liki_mark.png")
    if tex then
        self:drawTextureScaled(tex, 6, 2, 16, 16, 1.0, 1.0, 1.0, 1.0)
    end
end


-- =======================================================
-- SYSTEM EVENT SYNC LISTENERS
-- =======================================================
Events.OnReceiveGlobalModData.Add(function(key, data)
    if key == "FactionZoneDefinitions" then
        FactionZones.ClientCache = data or {}
        if FactionControlPanelInstance and FactionControlPanelInstance:getIsVisible() then
            FactionControlPanelInstance:populateZones()
            FactionControlPanelInstance:populateZonesListAdmin()
        end
    elseif key == "FactionWarZones" then
        LocalStatusCache = data or {}
        if FactionControlPanelInstance and FactionControlPanelInstance:getIsVisible() then
            FactionControlPanelInstance:populateZones()
            FactionControlPanelInstance:populateZonesListAdmin()
        end
    elseif (key == "FactionAlliances" or key == "FactionAllianceInvites") then
        if FactionControlPanelInstance and FactionControlPanelInstance:getIsVisible() then
            FactionControlPanelInstance:populateList()
        end
    end
end)


-- =======================================================
-- WORLD RIGHT CLICK Context menu trigger
-- =======================================================
function ToggleFactionControlPanel()
    local player = getPlayer()
    if not player then return end

    if FactionControlPanelInstance then
        FactionControlPanelInstance:close()
        return
    end

    -- Request latest data
    sendClientCommand(player, "FactionWar", "RequestData", {})
    
    local width = 1000
    local height = 650
    local x = (getCore():getScreenWidth() / 2) - (width / 2)
    local y = (getCore():getScreenHeight() / 2) - (height / 2)
    
    FactionControlPanelInstance = FactionControlPanelUI:new(x, y, width, height)
    FactionControlPanelInstance:initialise()
    FactionControlPanelInstance:addToUIManager()
    
    if FactionControlPanelInstance.initMap then
        FactionControlPanelInstance:initMap()
    end
end

local function OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    
    local optionName = getText("IGUI_FactionMapEditor_Context_Territories")
    if getIsAdmin() then
        optionName = getText("IGUI_FactionMapEditor_Context_FactionPanel")
    end
    
    context:addOption(optionName, worldobjects, function()
        ToggleFactionControlPanel()
    end)
end

Events.OnFillWorldObjectContextMenu.Add(OnFillWorldObjectContextMenu)

