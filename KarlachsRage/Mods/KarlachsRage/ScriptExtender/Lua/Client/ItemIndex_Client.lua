local CHANNEL = ModuleUUID .. "_ItemIndex"

local function OnItemIndexReceived(payload)
    if payload == nil then
        return
    end

    local ok, decoded = pcall(function()
        if type(payload) == "string" then
            return Ext.Json.Parse(payload)
        end
        return payload
    end)
    if not ok or type(decoded) ~= "table" then
        return
    end

    Mods.KarlachsRage = Mods.KarlachsRage or {}
    Mods.KarlachsRage.ItemIndex = decoded
end

Ext.Events.SessionLoaded:Subscribe(function()
    if ChunkedNet and ChunkedNet.Client and ChunkedNet.Client.RegisterNetListeners then
        ChunkedNet.Client.RegisterNetListeners()
        ChunkedNet.Client.RegisterHandler(CHANNEL, function(jsonStr)
            OnItemIndexReceived(jsonStr)
        end)
    end

    Ext.RegisterNetListener(CHANNEL, function(_, payload)
        OnItemIndexReceived(payload)
    end)

    Ext.Net.PostMessageToServer(CHANNEL .. "_REQ", "")
end)
