local IMMUNE_REQ = ModuleUUID .. "_ImmuneStats_Request"
local IMMUNE_SET = ModuleUUID .. "_ImmuneStats_Set"
local IMMUNE_UPD = ModuleUUID .. "_ImmuneStats_Update"

local function GetImmuneList()
    if KarlachsRageConfig and KarlachsRageConfig.BuildImmuneList then
        local ok, list = pcall(KarlachsRageConfig.BuildImmuneList)
        if ok and type(list) == "table" then
            return list
        end
    end

    return {}
end

local function SendImmuneList(user)
    local okJson, json = pcall(Ext.Json.Stringify, GetImmuneList())
    if not okJson or type(json) ~= "string" then
        return
    end

    if user == nil then
        Ext.Net.BroadcastMessage(IMMUNE_UPD, json)
    else
        Ext.ServerNet.PostMessageToUser(user, IMMUNE_UPD, json)
    end
end

local function BroadcastImmuneList()
    SendImmuneList(nil)
end

Ext.RegisterNetListener(IMMUNE_REQ, function(_, _, user)
    if user ~= nil then
        SendImmuneList(user)
    end
end)

Ext.RegisterNetListener(IMMUNE_SET, function(_, payload)
    local ok, decoded = pcall(function()
        return Ext.Json.Parse(payload or "[]")
    end)
    if not ok or type(decoded) ~= "table" then
        return
    end

    local entries = {}
    for _, value in ipairs(decoded) do
        if type(value) == "string" and value ~= "" then
            entries[#entries + 1] = value
        end
    end

    if KarlachsRageConfig and KarlachsRageConfig.SetImmuneList then
        local okSet = pcall(KarlachsRageConfig.SetImmuneList, entries)
        if okSet and KarlachsRageConfig.SaveToGlobal then
            pcall(KarlachsRageConfig.SaveToGlobal)
        end
    end

    if MCM and type(MCM.Set) == "function" then
        local joined = table.concat(entries, " ")
        pcall(function()
            MCM.Set("immune_stat_list", joined, ModuleUUID)
        end)
    end

    BroadcastImmuneList()
end)

Ext.Events.SessionLoaded:Subscribe(function()
    BroadcastImmuneList()
end)

Ext.Events.ResetCompleted:Subscribe(function()
    BroadcastImmuneList()
end)
