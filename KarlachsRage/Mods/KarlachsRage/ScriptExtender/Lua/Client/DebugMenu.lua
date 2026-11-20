-- MCM "Debug" tab: lets the player manually end Karlach's rage progression.
-- The server only honours the request when Karlach is out of combat.

local DEBUG_END_REQ = ModuleUUID .. "_Debug_EndRage"
local DEBUG_END_RES = ModuleUUID .. "_Debug_EndRage_Result"

local resultText = nil

Ext.RegisterNetListener(DEBUG_END_RES, function(_, payload)
    if resultText then
        resultText.Label = tostring(payload or "")
    end
end)

if Mods and Mods.BG3MCM and Mods.BG3MCM.IMGUIAPI then
    Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Debug", function(tabHeader)
        tabHeader:AddText("If Karlach's rage keeps progressing after combat has ended, use this to stop it.")
        tabHeader:AddText("Only works outside combat.")

        local button = tabHeader:AddButton("End Karlach's Rage")
        resultText = tabHeader:AddText("")

        button.OnClick = function()
            resultText.Label = "Sending request..."
            Ext.Net.PostMessageToServer(DEBUG_END_REQ, "")
        end
    end)
end
