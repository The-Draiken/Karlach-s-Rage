KarlachsRageConfig = KarlachsRageConfig or {}
local CFG = KarlachsRageConfig

local GLOBAL_FILE = "KarlachsRage/GlobalConfig.json"

local function ReadGlobal()
    if not (Ext and Ext.IO and Ext.IO.LoadFile) then
        return nil
    end

    local ok, content = pcall(Ext.IO.LoadFile, GLOBAL_FILE, "user")
    if not ok or not content or content == "" then
        return nil
    end

    local okParse, decoded = pcall(Ext.Json.Parse, content)
    if okParse and type(decoded) == "table" then
        return decoded
    end

    return nil
end

local function WriteGlobal(tbl)
    if not (Ext and Ext.IO and Ext.IO.SaveFile) then
        return false
    end

    local okJson, content = pcall(Ext.Json.Stringify, tbl or {})
    if not okJson or not content then
        return false
    end

    local okSave = pcall(Ext.IO.SaveFile, GLOBAL_FILE, content, "user")
    if not okSave then
        okSave = pcall(Ext.IO.SaveFile, GLOBAL_FILE, content)
    end

    return okSave == true
end

local function NormalizeImmuneStatNames(entries)
    local normalized = {}
    if type(entries) ~= "table" then
        return normalized
    end

    for key, value in pairs(entries) do
        if type(key) == "number" then
            if type(value) == "string" and value ~= "" then
                normalized[value] = true
            end
        elseif type(key) == "string" and key ~= "" then
            normalized[key] = value == true
        end
    end

    return normalized
end

local function Snapshot()
    return {
        ImmuneStatNames = CFG.ImmuneStatNames,
    }
end

local function Apply(snapshot)
    if type(snapshot) ~= "table" then
        return
    end

    if type(snapshot.ImmuneStatNames) == "table" then
        CFG.ImmuneStatNames = NormalizeImmuneStatNames(snapshot.ImmuneStatNames)
    end
end

local function GetItemStatName(itemGuid)
    if not (Ext and Ext.Entity and Ext.Entity.Get) or not itemGuid or itemGuid == "" then
        return nil
    end

    local entity = Ext.Entity.Get(itemGuid)
    if entity and entity.Data and type(entity.Data.StatsId) == "string" and entity.Data.StatsId ~= "" then
        return entity.Data.StatsId
    end

    return nil
end

function CFG.LoadFromGlobal()
    local snapshot = ReadGlobal()
    if snapshot then
        Apply(snapshot)
    end
end

function CFG.SaveToGlobal()
    return WriteGlobal(Snapshot())
end

function CFG.EnsureDefaults()
    CFG.ImmuneStatNames = NormalizeImmuneStatNames(CFG.ImmuneStatNames)
end

function CFG.UpdateFromMCM(settingId, value)
    if settingId ~= "immune_stat_list" then
        return
    end

    local entries = {}
    if type(value) == "string" and value ~= "" then
        local normalized = value:gsub(",", " ")
        for token in string.gmatch(normalized, "%S+") do
            if token ~= "" then
                entries[#entries + 1] = token
            end
        end
    end

    CFG.SetImmuneList(entries)
end

function CFG.SetImmuneList(entries)
    CFG.ImmuneStatNames = {}
    if type(entries) ~= "table" then
        return
    end

    for _, statName in ipairs(entries) do
        if type(statName) == "string" and statName ~= "" then
            CFG.ImmuneStatNames[statName] = true
        end
    end
end

function CFG.BuildImmuneList()
    local list = {}
    if type(CFG.ImmuneStatNames) == "table" then
        for statName, enabled in pairs(CFG.ImmuneStatNames) do
            if enabled == true and type(statName) == "string" and statName ~= "" then
                list[#list + 1] = statName
            end
        end
    end

    table.sort(list)
    return list
end

function CFG.IsStatImmune(statName)
    return type(statName) == "string"
        and statName ~= ""
        and type(CFG.ImmuneStatNames) == "table"
        and CFG.ImmuneStatNames[statName] == true
end

function CFG.IsItemImmune(itemGuid)
    local statName = GetItemStatName(itemGuid)
    return CFG.IsStatImmune(statName)
end

CFG.LoadFromGlobal()
CFG.EnsureDefaults()
