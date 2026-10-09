-- Sets.lua: saving, importing, renaming and deleting a bar set, /nf bars, and the module's public API (ns.ActionBarSets).
local ns = _G.NaowhForever

local A = ns.ActionBars
local S = A.Settings
local Capture = A.Capture
local Import = A.Import
local Pending = A.Pending

local Plural = A.Plural

local TEXT_OFF = "Action Bars is switched off."
local TEXT_IN_COMBAT = "Bar sets can be %s out of combat."
local TEXT_SAVED = "Saved your bars, macros and keybinds as %s."
local TEXT_NO_SET = "No bar set called %s for your class."
local TEXT_IMPORTED = "%s %s: %s."
local TEXT_IMPORTED_VERB, TEXT_TESTED_VERB = "Imported", "Test import of"
local TEXT_ACTIONS = "%d of %d actions"
local TEXT_NO_ROOM = "   No room for %s: %s"
local TEXT_SLOT = "Slot %d: %s"
local TEXT_WOULD_BE_EMPTY = "   These slots would be left empty:"
local TEXT_WERE_EMPTY = "   These slots were left empty:"
local TEXT_SLOT_LINE = "      "
local TEXT_LATER = "   Spells you learn later go into their slots then."
local TEXT_DELETED = "Deleted the bar set %s."
local TEXT_TAKEN = "There is already a bar set called %s."
local TEXT_SETS = "Bar sets: "
local TEXT_NO_SETS = "No bar sets saved for your class."
local TEXT_DELETE = "Delete the bar set %s?"
local TEXT_HEADLINE_NONE = "No bar sets saved for your %s yet"
local TEXT_HEADLINE = "%d bar set%s saved for your %s"
local TEXT_DETAIL_OFF = "Turn on Action Bars to save and import your bars."
local TEXT_DETAIL_LAST = "This character last used %s. Import any set from the window, out of combat."
local TEXT_DETAIL = "Save your bars from the window, or with /nf bars save and a name."

local COMMANDS = { save = true, import = true, restore = true, test = true, delete = true }

local function Ready(what)
    if not S.Get("enabled") then ns.Print(TEXT_OFF) return false end
    if InCombatLockdown() then ns.Print(TEXT_IN_COMBAT:format(what)) return false end
    return true
end

local function Save(name, choices)
    if not Ready("saved") then return end
    local key = A.Find(name) or name
    local sets = A.Sets()
    sets[key] = Capture.Snapshot(choices or (sets[key] and sets[key].choices))
    A.SetLast(key)
    ns.Print(TEXT_SAVED:format(key))
    A.Refresh()
    return key
end

local function Count(fates, fate)
    local n = 0
    for _, m in ipairs(fates) do if m.fate == fate then n = n + 1 end end
    return n
end

local function Summary(result)
    local parts = { TEXT_ACTIONS:format(result.placed, result.actions) }
    local made = Count(result.macros, "new")
    if made > 0 then parts[#parts + 1] = Plural(made, "new macro") end
    if result.bound then parts[#parts + 1] = Plural(result.bound, "keybind") end
    return table.concat(parts, ", ")
end

local function PrintFull(result)
    local full = {}
    for _, m in ipairs(result.macros) do
        if m.fate == "full" then full[#full + 1] = m.name end
    end
    if #full > 0 then print(TEXT_NO_ROOM:format(Plural(#full, "macro"), table.concat(full, ", "))) end
end

local function PrintEmpty(result, test)
    local failed = {}
    for _, slot in ipairs(Capture.Slots()) do
        local row = result.slots[slot]
        if row.state == "later" or row.state == "gone" then
            failed[#failed + 1] = TEXT_SLOT:format(slot, Import.Describe(row.entry))
        end
    end
    if #failed == 0 then return end
    print(test and TEXT_WOULD_BE_EMPTY or TEXT_WERE_EMPTY)
    for _, line in ipairs(failed) do print(TEXT_SLOT_LINE .. line) end
end

local function ImportSet(name, test)
    if not Ready("imported") then return end
    local key = A.Find(name)
    if not key then ns.Print(TEXT_NO_SET:format(name)) return end
    local result = Import.Run(A.Sets()[key], test)
    local pending = not test and Pending.Remember(key, result)
    if not test then A.SetLast(key) end
    ns.Print(TEXT_IMPORTED:format(test and TEXT_TESTED_VERB or TEXT_IMPORTED_VERB, key, Summary(result)))
    PrintFull(result)
    PrintEmpty(result, test)
    if pending then print(TEXT_LATER) end
    A.Refresh()
    return result
end

local function Delete(key)
    A.Sets()[key] = nil
    ns.Print(TEXT_DELETED:format(key))
    A.Refresh()
end

local function Rename(key, new)
    if new == key then return end
    if A.Find(new) and A.Find(new) ~= key then ns.Print(TEXT_TAKEN:format(new)) return end
    local sets = A.Sets()
    local set = sets[key]
    sets[key] = nil
    sets[new] = set
    for _, last in pairs(A.Account("barSetLast")) do
        if last.class == A.Class() and last.name == key then last.name = new end
    end
    A.Refresh()
end

local function ConfirmDelete(key)
    ns.Confirm(TEXT_DELETE:format(key), function() Delete(key) end)
end

local function SetCount()
    local n = 0
    for _ in pairs(A.Sets()) do n = n + 1 end
    return n
end

local function Headline()
    local n = SetCount()
    local class = UnitClass("player")
    if n == 0 then return TEXT_HEADLINE_NONE:format(class) end
    return TEXT_HEADLINE:format(n, n == 1 and "" or "s", class)
end

local function Detail()
    if not A.On() then return TEXT_DETAIL_OFF end
    local last = A.Last()
    if last and last.class == A.Class() and A.Sets()[last.name] then return TEXT_DETAIL_LAST:format(last.name) end
    return TEXT_DETAIL
end

local function List()
    local names = A.SortedNames()
    ns.Print(#names > 0 and (TEXT_SETS .. table.concat(names, ", ")) or TEXT_NO_SETS)
end

local function DeleteNamed(name)
    local key = A.Find(name)
    if key then ConfirmDelete(key) else ns.Print(TEXT_NO_SET:format(name)) end
end

local function SaveOnLogout()
    if not (S.Get("enabled") and S.Get("saveOnLogout")) then return end
    local last = A.Last()
    local key = last and last.name
    local sets = A.Sets()
    if key and sets[key] then sets[key] = Capture.Snapshot(sets[key].choices) end
end

local function OnEvent(_, event)
    if event == "PLAYER_LOGIN" then
        Pending.Watch()
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
        Pending.events:RegisterEvent("SPELLS_CHANGED")
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        Pending.SpellsReady(event)
    else
        SaveOnLogout()
    end
end

A.Rename, A.Delete, A.ConfirmDelete = Rename, Delete, ConfirmDelete

function ns.ActionBarsCommand(text)
    local cmd, name = strtrim(text or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "list" then
        List()
    elseif name == "" or not COMMANDS[cmd] then
        ns.OpenActionBarsWindow()
    elseif cmd == "save" then
        Save(name)
    elseif cmd == "import" or cmd == "restore" then
        ImportSet(name)
    elseif cmd == "test" then
        ImportSet(name, true)
    else
        DeleteNamed(name)
    end
end

ns.ActionBarSets = {
    Headline = Headline, Detail = Detail, BARS = A.BARS, Find = A.Find,
    Get = function(key) return A.Sets()[key] end,
    SlotList = Capture.Slots, Capture = Capture.Capture, CaptureMacros = Capture.CaptureMacros,
    CaptureBindings = Capture.CaptureBindings, MacroKey = Capture.MacroKey, Describe = Import.Describe,
    Save = Save, Import = ImportSet,
    Preview = function(key) return Import.Run(A.Sets()[key], true) end,
}

Pending.events:RegisterEvent("PLAYER_LOGIN")
Pending.events:RegisterEvent("PLAYER_LOGOUT")
Pending.events:SetScript("OnEvent", OnEvent)

S.OnChange(function(key)
    if key == "enabled" or key == "fillLater" then Pending.Watch() end
end)
