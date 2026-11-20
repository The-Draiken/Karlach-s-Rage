local function IsSafeIcon(icon)
    return type(icon) == "string" and icon ~= "" and string.match(icon, "^%d+_Head_") == nil
end

local IMMUNE_REQ = ModuleUUID .. "_ImmuneStats_Request"
local IMMUNE_SET = ModuleUUID .. "_ImmuneStats_Set"
local IMMUNE_UPD = ModuleUUID .. "_ImmuneStats_Update"

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

local equipSlotSet = {}
for _, slot in ipairs(EQUIP_SLOTS) do
    equipSlotSet[slot] = true
end

local immuneSet = {}
local itemIndex = nil

local function SafeString(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    return tostring(value)
end

local function BuildClientImmuneList()
    local entries = {}
    for statName, enabled in pairs(immuneSet) do
        if enabled == true and type(statName) == "string" and statName ~= "" then
            entries[#entries + 1] = statName
        end
    end
    table.sort(entries)
    return entries
end

local function SyncImmuneSet(list)
    for statName in pairs(immuneSet) do
        immuneSet[statName] = nil
    end

    if type(list) ~= "table" then
        return
    end

    for _, statName in ipairs(list) do
        if type(statName) == "string" and statName ~= "" then
            immuneSet[statName] = true
        end
    end
end

local function PushToServer()
    local okJson, json = pcall(Ext.Json.Stringify, BuildClientImmuneList())
    if okJson and type(json) == "string" then
        Ext.Net.PostMessageToServer(IMMUNE_SET, json)
    end
end

local function AddItemTooltip(image, entry)
    if not image or not image.Tooltip or type(entry) ~= "table" then
        return
    end

    local tip = image:Tooltip()
    tip:AddImage(entry.Icon or "Item_Unknown", { 32, 32 })
    tip:AddText(string.format("%s (%s)", entry.DisplayName or entry.StatName or "Unknown", entry.StatName or ""))

    if entry.Slot and entry.Slot ~= "" then
        tip:AddText("Slot: " .. tostring(entry.Slot))
    end
    if entry.Rarity and entry.Rarity ~= "" then
        tip:AddText("Rarity: " .. tostring(entry.Rarity))
    end
    if entry.PassivesOnEquip and entry.PassivesOnEquip ~= "" then
        tip:AddText("Passives: " .. tostring(entry.PassivesOnEquip))
    end
    if entry.StatusOnEquip and entry.StatusOnEquip ~= "" then
        tip:AddText("Status On Equip: " .. tostring(entry.StatusOnEquip))
    end
    if entry.Boosts and entry.Boosts ~= "" then
        tip:AddText("Boosts: " .. tostring(entry.Boosts))
    end

    if entry.ModName and entry.ModName ~= "" then
        local author = entry.ModAuthor or ""
        tip:AddText(string.format("From mod '%s' by %s", entry.ModName, author))
    elseif entry.Source == "vanilla" then
        tip:AddText("From base game")
    end
end

local function EnsureItemIndex()
    if itemIndex ~= nil then
        return
    end

    local served = Mods and Mods.KarlachsRage and Mods.KarlachsRage.ItemIndex
    if type(served) == "table" and #served > 0 then
        itemIndex = served
        return
    end

    itemIndex = {}
    local seen = {}

    local function SafeField(stat, field)
        local ok, value = pcall(function()
            return stat[field]
        end)
        if ok then
            return value
        end
        return nil
    end

    local function AddStatsToIndex(statsType)
        local okStats, statNames = pcall(Ext.Stats.GetStats, statsType)
        if not okStats or type(statNames) ~= "table" then
            return
        end

        for _, statName in ipairs(statNames) do
            if type(statName) == "string" and statName ~= "" and not seen[statName] then
                seen[statName] = true
                local stat = Ext.Stats.Get(statName)
                if stat then
                    local slot = SafeString(SafeField(stat, "Slot"))
                    if equipSlotSet[slot] then
                        itemIndex[#itemIndex + 1] = {
                            StatName = statName,
                            DisplayName = SafeString(SafeField(stat, "DisplayName") or SafeField(stat, "Name") or statName),
                            Icon = "Item_Unknown",
                            Source = "vanilla",
                            Slot = slot,
                            Rarity = SafeString(SafeField(stat, "Rarity")),
                            PassivesOnEquip = SafeString(SafeField(stat, "PassivesOnEquip")),
                            StatusOnEquip = SafeString(SafeField(stat, "StatusOnEquip")),
                            Boosts = SafeString(SafeField(stat, "Boosts") or SafeField(stat, "DefaultBoosts")),
                            ModId = SafeString(SafeField(stat, "ModId")),
                            ModName = "",
                            ModAuthor = "",
                        }
                    end
                end
            end
        end
    end

    AddStatsToIndex("Armor")
    AddStatsToIndex("Weapon")
    AddStatsToIndex("Object")

    table.sort(itemIndex, function(a, b)
        local aName = a.DisplayName or a.StatName or ""
        local bName = b.DisplayName or b.StatName or ""
        return aName < bName
    end)
end

Ext.RegisterNetListener(IMMUNE_UPD, function(_, payload)
    local ok, decoded = pcall(Ext.Json.Parse, payload or "[]")
    if ok and type(decoded) == "table" then
        SyncImmuneSet(decoded)
    end
end)

Ext.Events.SessionLoaded:Subscribe(function()
    Ext.Net.PostMessageToServer(IMMUNE_REQ, "")
end)

if Mods and Mods.BG3MCM and Mods.BG3MCM.IMGUIAPI then
    Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Immune Items", function(tabHeader)
        EnsureItemIndex()

        local entriesByModId = {}
        local modIdByName = {}

        for _, entry in ipairs(itemIndex or {}) do
            local modId = entry.ModId or ""
            local modName = "Base Game"
            if modId ~= "" then
                modName = entry.ModName ~= "" and entry.ModName or "Unknown Mod"
            end

            entriesByModId[modId] = entriesByModId[modId] or {}
            modIdByName[modName] = modId
            table.insert(entriesByModId[modId], entry)
        end

        local modNames = {}
        for modId, entries in pairs(entriesByModId) do
            table.sort(entries, function(a, b)
                local aName = a.DisplayName or a.StatName or ""
                local bName = b.DisplayName or b.StatName or ""
                return aName < bName
            end)

            local modName = "Base Game"
            if modId ~= "" then
                for candidateName, candidateId in pairs(modIdByName) do
                    if candidateId == modId then
                        modName = candidateName
                        break
                    end
                end
            end

            modNames[#modNames + 1] = modName
        end
        table.sort(modNames)

        tabHeader:AddText("Search items by name or StatName, then toggle them to protect them from Karlach's rage destruction.")

        local searchInput = tabHeader:AddInputText("")
        searchInput.Hint = "Search item name or StatName"
        searchInput.AutoSelectAll = true
        searchInput.EscapeClearsAll = true

        tabHeader:AddText("Or list all equipment from a specific mod")
        local modCombo = tabHeader:AddCombo("")
        modCombo.WidthFitPreview = true
        modCombo.Options = modNames

        local resultsTable = tabHeader:AddTable("KarlachsRageImmuneItems", 2)
        resultsTable.Hideable = true
        resultsTable.Visible = false
        resultsTable.ScrollY = true
        resultsTable.RowBg = true
        resultsTable:AddColumn("Item", "WidthStretch")
        resultsTable:AddColumn("Protected")

        local headerRow = resultsTable:AddRow()
        headerRow.Headers = true
        headerRow:AddCell():AddText("Item")
        headerRow:AddCell():AddText("Protected")

        local function ClearResults()
            for index = #resultsTable.Children, 2, -1 do
                resultsTable:RemoveChild(resultsTable.Children[index])
            end
        end

        local function DisplayEntries(entries)
            ClearResults()
            if not entries or #entries == 0 then
                resultsTable.Visible = false
                return
            end

            resultsTable.Visible = true
            for _, entry in ipairs(entries) do
                local row = resultsTable:AddRow()

                local nameCell = row:AddCell()
                if IsSafeIcon(entry.Icon) then
                    local icon = nameCell:AddImage(entry.Icon, { 32, 32 })
                    icon.SameLine = true
                    AddItemTooltip(icon, entry)
                end
                nameCell:AddText(string.format("%s (%s)", entry.DisplayName or entry.StatName, entry.StatName or "")).SameLine = true

                local immuneCell = row:AddCell()
                local checked = immuneSet[entry.StatName] == true
                local checkbox = immuneCell:AddCheckbox("##KarlachsRageImmune_" .. tostring(entry.StatName or ""), checked)
                checkbox.OnChange = function()
                    if checkbox.Checked then
                        immuneSet[entry.StatName] = true
                    else
                        immuneSet[entry.StatName] = nil
                    end
                    PushToServer()
                end
            end
        end

        local function RefreshResults()
            local searchText = string.lower(searchInput.Text or "")
            if searchText ~= "" then
                modCombo.SelectedIndex = -1
                local matches = {}
                for _, entry in ipairs(itemIndex or {}) do
                    local displayName = string.lower(entry.DisplayName or "")
                    local statName = string.lower(entry.StatName or "")
                    if string.find(displayName, searchText, 1, true) or string.find(statName, searchText, 1, true) then
                        matches[#matches + 1] = entry
                    end
                end
                DisplayEntries(matches)
                return
            end

            local selectedIndex = modCombo.SelectedIndex
            if selectedIndex and selectedIndex >= 0 then
                local modName = modCombo.Options[selectedIndex + 1]
                local modId = modIdByName[modName]
                DisplayEntries(entriesByModId[modId] or {})
                return
            end

            DisplayEntries({})
        end

        searchInput.OnChange = function()
            RefreshResults()
        end

        modCombo.OnChange = function()
            searchInput.Text = ""
            RefreshResults()
        end

        RefreshResults()
    end)
end
