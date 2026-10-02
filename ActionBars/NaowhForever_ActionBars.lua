-------------------------------------------------------------------------------
--  NaowhForever_ActionBars.lua -- the Action Bars module: every action bar slot saved
--  under a name and put back later, out of combat. Sets belong to a class and are shared by
--  every character of that class on the account.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local S = UI.ModuleSettings("actionBars", {
    enabled = true, highestRank = false, recreateMacros = false, saveOnLogout = false,
})
ns.ActionBarSettings = S

local KEYBOARD_SLOTS = 180
local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local MACRO_ICON = 134400

local function Account(key)
    local account = ns.AccountSettings()
    account[key] = account[key] or {}
    return account[key]
end

local function Class()
    local _, class = UnitClass("player")
    return class
end

local function Sets()
    local all = Account("barSets")
    all[Class()] = all[Class()] or {}
    return all[Class()]
end

local function CharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- The set this character saved or restored last, which Save on Logout writes back to. The
-- class is kept with it, since set names only mean something within a class.
local function SetLast(name)
    Account("barSetLast")[CharKey()] = { class = Class(), name = name }
end

-- Set names match without case, so slash commands find them however they are typed.
local function Find(name)
    local sets = Sets()
    if sets[name] then return name end
    local lower = name:lower()
    for key in pairs(sets) do
        if key:lower() == lower then return key end
    end
end

local function SortedNames()
    local names = {}
    for name in pairs(Sets()) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local function Slots()
    local list = {}
    for slot = 1, KEYBOARD_SLOTS do list[#list + 1] = slot end
    local slot = math.max(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex(), KEYBOARD_SLOTS + 1)
    while C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot) do
        list[#list + 1] = slot
        slot = slot + 1
    end
    return list
end

-- name -> spellID of the highest rank of each active spell in the spellbook.
local function HighestRanks()
    local best, rank = {}, {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.isGuild then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, PLAYER_BANK)
                if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
                    local r = tonumber(item.subName and item.subName:match("%d+")) or 0
                    if not rank[item.name] or r > rank[item.name] then
                        best[item.name], rank[item.name] = item.actionID, r
                    end
                end
            end
        end
    end
    return best
end

-------------------------------------------------------------------------------
--  Saving
-------------------------------------------------------------------------------
-- A macro slot's id is the spell or item it shows, not the macro, so the macro is found by
-- the name the slot carries.
local function Capture()
    local slots = {}
    for _, slot in ipairs(Slots()) do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" then
            slots[slot] = { kind = "spell", id = id, name = C_Spell.GetSpellName(id) }
        elseif kind == "macro" then
            local name = C_ActionBar.GetActionText(slot)
            local index = name and GetMacroIndexByName(name) or 0
            if index > 0 then
                local _, icon, body = GetMacroInfo(index)
                slots[slot] = { kind = "macro", name = name, icon = icon, body = body,
                    perCharacter = index > Constants.MacroConsts.MAX_ACCOUNT_MACROS }
            end
        elseif kind then
            slots[slot] = { kind = kind, id = id }
        end
    end
    return slots
end

local function Ready(what)
    if not S.Get("enabled") then ns.Print("Action Bars is switched off.") return false end
    if InCombatLockdown() then ns.Print(("Bar sets can be %s out of combat."):format(what)) return false end
    return true
end

local function Save(name)
    if not Ready("saved") then return end
    local key = Find(name) or name
    Sets()[key] = { saved = time(), slots = Capture() }
    SetLast(key)
    ns.Print(("Saved your bars as %s."):format(key))
    if UI.RefreshPage then UI:RefreshPage(true) end
end

-------------------------------------------------------------------------------
--  Restoring
-------------------------------------------------------------------------------
local function Describe(entry)
    if entry.kind == "spell" then return entry.name or ("spell " .. entry.id) end
    if entry.kind == "macro" then return "macro " .. entry.name end
    if entry.kind == "item" then return C_Item.GetItemNameByID(entry.id) or ("item " .. entry.id) end
    return ("%s %s"):format(entry.kind, tostring(entry.id))
end

local RESTORABLE = { spell = true, macro = true, item = true, equipmentset = true }

-- plan holds the macros a test restore would make, since a test does not make them.
local function MacroRoom(perCharacter, plan)
    local account, character = GetNumMacros()
    if plan then account, character = account + plan.account, character + plan.character end
    local max = Constants.MacroConsts
    if perCharacter then return character < max.MAX_CHARACTER_MACROS end
    return account < max.MAX_ACCOUNT_MACROS
end

-- A spell falls back to the highest rank known when the saved rank is not, so a set made at
-- a higher level still restores. A test passes a plan: a missing macro that would be made
-- again counts as placed.
local function PickUp(entry, best, plan)
    ClearCursor()
    if entry.kind == "spell" then
        local top = entry.name and best[entry.name]
        if top and S.Get("highestRank") then C_Spell.PickupSpell(top) end
        if not GetCursorInfo() then C_Spell.PickupSpell(entry.id) end
        if not GetCursorInfo() and top then C_Spell.PickupSpell(top) end
    elseif entry.kind == "macro" then
        local index = GetMacroIndexByName(entry.name)
        if index == 0 and S.Get("recreateMacros") and MacroRoom(entry.perCharacter, plan) then
            if plan then
                local kind = entry.perCharacter and "character" or "account"
                plan[kind] = plan[kind] + 1
                return true
            end
            CreateMacro(entry.name, entry.icon or MACRO_ICON, entry.body or "", entry.perCharacter)
            index = GetMacroIndexByName(entry.name)
        end
        if index > 0 then PickupMacro(index) end
    elseif entry.kind == "item" then
        C_Item.PickupItem(entry.id)
    elseif entry.kind == "equipmentset" then
        local setID = type(entry.id) == "number" and entry.id or C_EquipmentSet.GetEquipmentSetID(entry.id)
        if setID then C_EquipmentSet.PickupEquipmentSet(setID) end
    end
    return GetCursorInfo() ~= nil
end

-- Every slot ends as it was saved: a slot the set leaves empty is cleared, and so is one
-- whose action cannot come back. A slot saved holding something no set can restore (a
-- mount, a pet, a flyout) is left as it is.
local function Restore(name, test)
    if not Ready("restored") then return end
    local key = Find(name)
    if not key then ns.Print(("No bar set called %s for your class."):format(name)) return end
    local saved, best, failed = Sets()[key].slots, HighestRanks(), {}
    local plan = test and { account = 0, character = 0 } or nil
    for _, slot in ipairs(Slots()) do
        local entry = saved[slot]
        if not entry or RESTORABLE[entry.kind] then
            if entry and PickUp(entry, best, plan) then
                if not test then PlaceAction(slot) end
            else
                if entry then failed[#failed + 1] = ("Slot %d: %s"):format(slot, Describe(entry)) end
                if not test and GetActionInfo(slot) then PickupAction(slot) end
            end
            ClearCursor()
        end
    end
    if not test then SetLast(key) end
    if #failed == 0 then
        ns.Print(test and ("%s would restore every slot."):format(key) or ("Restored %s."):format(key))
    else
        ns.Print(test and ("%s would leave %d slot(s) empty:"):format(key, #failed)
            or ("Restored %s, %d slot(s) left empty:"):format(key, #failed))
        for _, line in ipairs(failed) do print("   " .. line) end
    end
end

local function Delete(key)
    Sets()[key] = nil
    ns.Print(("Deleted the bar set %s."):format(key))
    if UI.RefreshPage then UI:RefreshPage(true) end
end

local function Rename(key, new)
    if new == key then return end
    if Find(new) and Find(new) ~= key then ns.Print(("There is already a bar set called %s."):format(new)) return end
    local sets = Sets()
    local set = sets[key]
    sets[key] = nil
    sets[new] = set
    for _, last in pairs(Account("barSetLast")) do
        if last.class == Class() and last.name == key then last.name = new end
    end
    if UI.RefreshPage then UI:RefreshPage(true) end
end

local function PromptSave()
    ns.PromptText("Name for your current bars", "", 40, function(name)
        local key = Find(name)
        if key then
            ns.Confirm(("Replace %s with the bars you have now?"):format(key), function() Save(key) end)
        else
            Save(name)
        end
    end)
end

-------------------------------------------------------------------------------
--  Options and slash command
-------------------------------------------------------------------------------
local function SetMenu(key)
    MenuUtil.CreateContextMenu(UIParent, function(_, root)
        root:CreateButton("Test Restore", function() Restore(key, true) end)
        root:CreateButton("Save Current Bars Here", function()
            ns.Confirm(("Replace %s with the bars you have now?"):format(key), function() Save(key) end)
        end)
        root:CreateButton("Rename", function()
            ns.PromptText("New name for " .. key, key, 40, function(new) Rename(key, new) end)
        end)
        root:CreateButton("Delete", function()
            ns.Confirm(("Delete the bar set %s?"):format(key), function() Delete(key) end)
        end)
    end)
end

function ns.BuildActionBarsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Save every action bar slot under a name and put it all back later, "
        .. "for a different spec, a dungeon set-up or a fresh character. Sets are shared by every "
        .. "character of your class on this account. Saving and restoring work out of combat.", y)
    y = y - h

    _, h = W:SectionHeader(parent, "BAR SETS", y); y = y - h
    _, h = W:Button(parent, "Save Current Bars", y, PromptSave); y = y - h
    local names = SortedNames()
    if #names == 0 then
        _, h = W:Note(parent, "No bar sets saved for your class yet.", y)
        y = y - h
    end
    for _, key in ipairs(names) do
        local set = Sets()[key]
        _, h = W:DualRow(parent, y,
            { type = "button", text = key, buttonText = "Restore",
              onClick = function() Restore(key) end },
            { type = "button", text = "Saved " .. date("%d %b %Y", set.saved), buttonText = "More",
              onClick = function() SetMenu(key) end }
        ); y = y - h
    end

    _, h = W:SectionHeader(parent, "RESTORING", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("highestRank", "Highest Rank",
            "Restores the highest rank you know of each spell instead of the rank that was saved. "
            .. "Off, a rank you no longer have still falls back to your highest.", "enabled"),
        S.Toggle("recreateMacros", "Recreate Deleted Macros",
            "A macro in the set that you have since deleted is made again from what was saved, "
            .. "if you have room for it.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("saveOnLogout", "Save on Logout",
            "When you log out, the set this character saved or restored last is saved again "
            .. "with your bars as they are.", "enabled"),
        { type = "label", text = "" }
    ); y = y - h
    return y
end

-- /nf bars save|restore|test|delete <name>, /nf bars list; on its own it opens the page.
function ns.ActionBarsCommand(text)
    local cmd, name = strtrim(text or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "list" then
        local names = SortedNames()
        ns.Print(#names > 0 and ("Bar sets: " .. table.concat(names, ", ")) or "No bar sets saved for your class.")
    elseif name == "" or not (cmd == "save" or cmd == "restore" or cmd == "test" or cmd == "delete") then
        ns.OpenOptionsWindow("Action Bars/Sets")
    elseif cmd == "save" then
        Save(name)
    elseif cmd == "restore" then
        Restore(name)
    elseif cmd == "test" then
        Restore(name, true)
    else
        local key = Find(name)
        if key then Delete(key) else ns.Print(("No bar set called %s for your class."):format(name)) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function()
    if not (S.Get("enabled") and S.Get("saveOnLogout")) then return end
    local last = Account("barSetLast")[CharKey()]
    local key = last and last.name
    if key and Sets()[key] then Sets()[key] = { saved = time(), slots = Capture() } end
end)
