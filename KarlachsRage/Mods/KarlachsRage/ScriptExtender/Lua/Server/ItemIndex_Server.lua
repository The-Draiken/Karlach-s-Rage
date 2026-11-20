local CHANNEL = ModuleUUID .. "_ItemIndex"

local EQUIP_SLOTS = {
    "Helmet",
    "Amulet",
    "Breast",
    "Cloak",
    "Belt",
    "Gloves",
    "Leggings",
    "Boots",
    "Ring",
    "Ring2",
    "Weapon",
    "Shield",
    "Melee Main Weapon",
    "Melee Offhand Weapon",
    "Ranged Main Weapon",
    "Ranged Offhand Weapon",
    "CampClothing",
    "CampShoes",
    "Underwear",
    "Instrument",
    "Torch",
    "Arrow",
}

local VANILLA_MOD_IDS = {
    "ed539163-bb70-431b-96a7-f5b2eda5376b",
    "b176a0ac-d79f-ed9d-5a87-5c2c80874e10",
    "e842840a-2449-588c-b0c4-22122cfce31b",
    "e0a4d990-7b9b-8fa9-d7c6-04017c6cf5b1",
    "ee4989eb-aab8-968f-8674-812ea2f4bfd7",
    "630daa32-70f8-3da5-41b9-154fe8410236",
    "ee5a55ff-eb38-0b27-c5b0-f358dc306d34",
    "3d0c5ff8-c95d-c907-ff3e-34b204f1c630",
    "991c9c7a-fb80-40cb-8f0d-b92d4e80e9b1",
    "28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8",
}

local equipSlotSet = {}
for _, slot in ipairs(EQUIP_SLOTS) do
    equipSlotSet[slot] = true
end

local vanillaModSet = {}
for _, modId in ipairs(VANILLA_MOD_IDS) do
    vanillaModSet[modId] = true
end

local function SafeField(stat, field)
    local ok, value = pcall(function()
        return stat[field]
    end)
    if ok then
        return value
    end
    return nil
end

local function SafeString(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    return tostring(value)
end

local function GetTranslated(handle)
    if not handle then
        return ""
    end

    local ok, value = pcall(Ext.Loca.GetTranslatedString, handle)
    if ok and type(value) == "string" then
        return value
    end

    return ""
end

local function TemplateDisplayName(rootTemplate)
    if not rootTemplate or not rootTemplate.DisplayName then
        return ""
    end

    local handle = rootTemplate.DisplayName.Handle
    if type(handle) == "table" and handle.Handle then
        return GetTranslated(handle.Handle)
    end

    return GetTranslated(handle)
end

local function IsVanilla(modId)
    if not modId or modId == "" then
        return true
    end
    return vanillaModSet[modId] == true
end

local function BuildItemIndex()
    local index = {}
    local seen = {}

    local function ProcessStat(statName)
        if seen[statName] then
            return
        end
        seen[statName] = true

        local stat = Ext.Stats.Get(statName)
        if not stat then
            return
        end

        local slot = SafeString(SafeField(stat, "Slot"))
        if not equipSlotSet[slot] then
            return
        end

        local rootTemplate
        local rootTemplateGuid = SafeString(SafeField(stat, "RootTemplate"))
        if rootTemplateGuid ~= "" and rootTemplateGuid ~= "00000000-0000-0000-0000-000000000000" then
            local okRoot, resolvedRoot = pcall(Ext.Template.GetRootTemplate, rootTemplateGuid)
            if okRoot then
                rootTemplate = resolvedRoot
            end
        end

        local displayName = TemplateDisplayName(rootTemplate)
        if displayName == "" then
            displayName = SafeString(SafeField(stat, "DisplayName") or SafeField(stat, "Name") or statName)
        end
        if displayName == "" then
            displayName = statName
        end

        local modId = SafeString(SafeField(stat, "ModId"))
        local icon = "Item_Unknown"
        if rootTemplate and type(rootTemplate.Icon) == "string" and rootTemplate.Icon ~= "" then
            icon = rootTemplate.Icon
        end

        local modName = ""
        local modAuthor = ""
        if modId ~= "" then
            local okMod, modInfo = pcall(Ext.Mod.GetMod, modId)
            if okMod and modInfo and modInfo.Info then
                modName = SafeString(modInfo.Info.Name)
                modAuthor = SafeString(modInfo.Info.Author)
            end
        end

        index[#index + 1] = {
            StatName = statName,
            DisplayName = displayName,
            Icon = icon,
            Source = IsVanilla(modId) and "vanilla" or "mod",
            Slot = slot,
            Rarity = SafeString(SafeField(stat, "Rarity")),
            PassivesOnEquip = SafeString(SafeField(stat, "PassivesOnEquip")),
            StatusOnEquip = SafeString(SafeField(stat, "StatusOnEquip")),
            Boosts = SafeString(SafeField(stat, "Boosts") or SafeField(stat, "DefaultBoosts")),
            ModId = modId,
            ModName = modName,
            ModAuthor = modAuthor,
        }
    end

    for _, statsType in ipairs({ "Armor", "Weapon", "Object" }) do
        local okStats, statNames = pcall(Ext.Stats.GetStats, statsType)
        if okStats and type(statNames) == "table" then
            for _, statName in ipairs(statNames) do
                if type(statName) == "string" and statName ~= "" then
                    ProcessStat(statName)
                end
            end
        end
    end

    table.sort(index, function(a, b)
        local aName = a.DisplayName or a.StatName or ""
        local bName = b.DisplayName or b.StatName or ""
        return aName < bName
    end)

    Mods.KarlachsRage = Mods.KarlachsRage or {}
    Mods.KarlachsRage.ItemIndex = index
    return index
end

local function BroadcastItemIndex()
    local index = Mods.KarlachsRage and Mods.KarlachsRage.ItemIndex
    if not index then
        index = BuildItemIndex()
    end

    if ChunkedNet and ChunkedNet.SendTableToAll then
        ChunkedNet.SendTableToAll(CHANNEL, index)
        return
    end

    local okJson, json = pcall(Ext.Json.Stringify, index)
    if okJson and type(json) == "string" then
        Ext.Net.BroadcastMessage(CHANNEL, json)
    end
end

Ext.RegisterNetListener(CHANNEL .. "_REQ", function(_, _, user)
    local index = Mods.KarlachsRage and Mods.KarlachsRage.ItemIndex
    if not index then
        index = BuildItemIndex()
    end

    if ChunkedNet and ChunkedNet.SendTableToUser then
        ChunkedNet.SendTableToUser(user, CHANNEL, index)
        return
    end

    local okJson, json = pcall(Ext.Json.Stringify, index)
    if okJson and type(json) == "string" then
        Ext.ServerNet.PostMessageToUser(user, CHANNEL, json)
    end
end)

Ext.Events.SessionLoaded:Subscribe(function()
    BuildItemIndex()
    BroadcastItemIndex()
end)

Ext.Events.ResetCompleted:Subscribe(function()
    BuildItemIndex()
    BroadcastItemIndex()
end)
