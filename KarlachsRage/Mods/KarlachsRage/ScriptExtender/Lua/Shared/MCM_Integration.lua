if not (KarlachsRageConfig and MCM and type(MCM.Get) == "function") then
    return
end

local IMMUNE_UPD = ModuleUUID .. "_ImmuneStats_Update"
local SETTING_ID = "immune_stat_list"

local function ParseImmuneList(raw)
    local entries = {}
    if type(raw) ~= "string" or raw == "" then
        return entries
    end

    raw = raw:gsub(",", " ")
    for token in string.gmatch(raw, "%S+") do
        local cleaned = token:match("^%s*(.-)%s*$") or token
        if cleaned ~= "" then
            entries[#entries + 1] = cleaned
        end
    end

    return entries
end

local function BroadcastCurrentImmuneList()
    if not (Ext and Ext.Net and type(Ext.Net.BroadcastMessage) == "function") then
        return
    end

    local okList, list = pcall(function()
        return KarlachsRageConfig.BuildImmuneList()
    end)
    if not okList or type(list) ~= "table" then
        return
    end

    local okJson, json = pcall(Ext.Json.Stringify, list)
    if okJson and type(json) == "string" then
        pcall(function()
            Ext.Net.BroadcastMessage(IMMUNE_UPD, json)
        end)
    end
end

local function SyncAllSettingsFromMCM()
    local ok, value = pcall(function()
        return MCM.Get(SETTING_ID, ModuleUUID)
    end)
    if not ok then
        value = nil
    end

    local parsed = ParseImmuneList(value)
    if #parsed > 0 then
        KarlachsRageConfig.SetImmuneList(parsed)
    else
        local existing = KarlachsRageConfig.BuildImmuneList and KarlachsRageConfig.BuildImmuneList() or {}
        if type(existing) == "table" and #existing > 0 and type(MCM.Set) == "function" then
            local joined = table.concat(existing, " ")
            pcall(function()
                MCM.Set(SETTING_ID, joined, ModuleUUID)
            end)
        end
    end

    if KarlachsRageConfig.SaveToGlobal then
        KarlachsRageConfig.SaveToGlobal()
    end
end

local function ApplySingleSetting(payload)
    if not payload then
        return
    end

    local modUUID = payload.modUUID or payload.modGUID
    if modUUID ~= ModuleUUID or payload.settingId ~= SETTING_ID then
        return
    end

    KarlachsRageConfig.SetImmuneList(ParseImmuneList(payload.value))
    if KarlachsRageConfig.SaveToGlobal then
        KarlachsRageConfig.SaveToGlobal()
    end
    BroadcastCurrentImmuneList()
end

Ext.Events.SessionLoaded:Subscribe(function()
    SyncAllSettingsFromMCM()
end)

if Ext and Ext.ModEvents and Ext.ModEvents.BG3MCM then
    local events = Ext.ModEvents.BG3MCM

    if events["MCM_Setting_Saved"] then
        events["MCM_Setting_Saved"]:Subscribe(function(payload)
            ApplySingleSetting(payload)
        end)
    end

    if events["MCM_Setting_Reset"] then
        events["MCM_Setting_Reset"]:Subscribe(function(payload)
            if not payload then
                return
            end

            local modUUID = payload.modUUID or payload.modGUID
            if modUUID ~= ModuleUUID then
                return
            end

            local ok, value = pcall(function()
                return MCM.Get(SETTING_ID, ModuleUUID)
            end)
            if ok then
                ApplySingleSetting({
                    modUUID = ModuleUUID,
                    settingId = SETTING_ID,
                    value = value,
                })
            end
        end)
    end
end

Ext.RegisterNetListener("MCM_Saved_Setting", function(_, payload)
    local ok, data = pcall(function()
        return Ext.Json.Parse(payload or "{}")
    end)
    if not ok or type(data) ~= "table" then
        return
    end

    if data.modGUID and not data.modUUID then
        data.modUUID = data.modGUID
    end

    ApplySingleSetting(data)
end)
