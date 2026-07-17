-- =======================================================
-- FILE: media/lua/client/FactionHUD.lua
-- DESCR: Handles the Faction UI Keybind
-- Note: The visual UI has been moved to FactionDiplomacyUI.lua
-- =======================================================

-- -------------------------------------------------------
-- KEYBIND TOGGLE
-- -------------------------------------------------------
if not keyBinding then keyBinding = {} end
table.insert(keyBinding, { value = "[Faction_War]", key = 0 })
table.insert(keyBinding, { value = "Toggle_Faction_Zones", key = 0 })

Events.OnKeyPressed.Add(function(key)
    local core = getCore()
    if key == core:getKey("Toggle_Faction_Zones") then
        if ToggleFactionWindow then
            ToggleFactionWindow()
        end
    end
end)
