-- =======================================================
-- FILE: media/lua/client/FactionMoodle.lua
-- DESCR: Fake Moodle UI for Faction Buffs
-- =======================================================

local FactionMoodle = ISUIElement:derive("FactionMoodle")

function FactionMoodle:new()
    local core = getCore()
    local w = 32
    local h = 32
    -- Position it where the Faction UI used to be
    local x = core:getScreenWidth() - 200
    local y = 120 
    
    local o = ISUIElement:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    
    o.textureIcon = getTexture("media/ui/Moodle_FactionZone.png")
    o.textureBkg = getTexture("media/ui/Moodle_Bkg_Good_1.png")
    o.tick = 0
    o.moving = false
    return o
end

function FactionMoodle:render()
    if not FactionBuffsActive then return end
    
    -- Wobble effect like a real moodle
    self.tick = self.tick + 1
    local yOffset = math.sin(self.tick / 15) * 2
    
    if self.textureBkg then
        self:drawTexture(self.textureBkg, 0, yOffset, 1, 1, 1, 1)
    else
        self:drawRect(0, yOffset, 32, 32, 1, 0.2, 0.8, 0.2)
    end
    
    if self.textureIcon then
        self:drawTexture(self.textureIcon, 0, yOffset, 1, 1, 1, 1)
    end
    
    if self:isMouseOver() then
        local zoneType = FactionBuffZoneType or "Standard"
        local zoneTextKeys = {
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
        local descTextKeys = {
            Standard = "IGUI_FactionMoodle_Desc_Standard",
            Armory = "IGUI_FactionMoodle_Desc_Armory",
            Hospital = "IGUI_FactionMoodle_Desc_Hospital",
            Workshop = "IGUI_FactionMoodle_Desc_Workshop",
            Bunker = "IGUI_FactionMoodle_Desc_Bunker",
            Industrial = "IGUI_FactionMoodle_Desc_Industrial",
            Estacao = "IGUI_FactionMoodle_Desc_Estacao",
            Umbrella = "IGUI_FactionMoodle_Desc_Umbrella",
            Posto = "IGUI_FactionMoodle_Desc_Posto",
        }
        local text = getText(zoneTextKeys[zoneType] or zoneTextKeys.Standard)
        local desc = getText(descTextKeys[zoneType] or descTextKeys.Standard)
        
        local tw = getTextManager():MeasureStringX(UIFont.Small, text)
        local dw = getTextManager():MeasureStringX(UIFont.Small, desc)
        local tooltipW = math.max(tw, dw) + 16
        local tooltipH = 34
        
        -- Draw tooltip to the left of the moodle
        local tx = -tooltipW - 8
        local ty = yOffset
        
        self:drawRect(tx, ty, tooltipW, tooltipH, 0.8, 0, 0, 0)
        self:drawRectBorder(tx, ty, tooltipW, tooltipH, 1, 0.5, 0.5, 0.5)
        self:drawText(text, tx + 8, ty + 2, 1, 0.3, 1, 0.3, UIFont.Small)
        self:drawText(desc, tx + 8, ty + 16, 1, 1, 1, 1, UIFont.Small)
    end
end

function FactionMoodle:onMouseDown(x, y)
    self.moving = true
    self.dragStartX = x
    self.dragStartY = y
    return true
end

function FactionMoodle:onMouseMove(dx, dy)
    if self.moving then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function FactionMoodle:onMouseUp(x, y)
    self.moving = false
end

function FactionMoodle:onMouseUpOutside(x, y)
    self.moving = false
end

Events.OnGameStart.Add(function()
    local moodle = FactionMoodle:new()
    moodle:initialise()
    moodle:instantiate()
    moodle:addToUIManager()
end)

FactionBuffsActive = false
FactionBuffZoneType = nil

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "FW_Buffs" or command ~= "Status" then
        return
    end

    args = args or {}
    FactionBuffsActive = args.active == true
    FactionBuffZoneType = args.zoneType or "Standard"
end)
