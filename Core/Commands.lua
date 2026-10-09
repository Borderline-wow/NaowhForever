-- Commands.lua: /nf and each module's own command, the key binding names and the compartment entry.
local ns = _G.NaowhForever
local O = ns.Options

local MODULES, OpenModule = O.MODULES, O.OpenModule

local COMMAND_PREFIX = "/nf"
local SLASH_KEY = "NAOWHFOREVER"
local TEXT_SWITCHED_OFF = "%s is switched off. Turn it on under Settings > Modules."

function _G.NaowhForever_OnCompartmentClick()
    ns.ToggleOptionsWindow()
end

BINDING_HEADER_NAOWHFOREVER = "Naowh Forever"
BINDING_NAME_NAOWHFOREVER_JOURNAL = "Open Dungeon Journal"
BINDING_NAME_NAOWHFOREVER_BOSSLOOT = "Boss Loot at Cursor"
BINDING_NAME_NAOWHFOREVER_BIS = "Open BiS List"
BINDING_NAME_NAOWHFOREVER_GROUPINSPECT = "Open Group Inspect"
BINDING_NAME_NAOWHFOREVER_COMPLETO = "Open Completo"
BINDING_NAME_NAOWHFOREVER_BAGSPACE_PICKUP = "Pick Up Cheapest Item"
_G["BINDING_NAME_CLICK NaowhForeverBlessNext:LeftButton"] = "Next Blessing"
_G["BINDING_NAME_CLICK NaowhForeverBlessNextGreater:LeftButton"] = "Next Greater Blessing"
_G["BINDING_NAME_CLICK NaowhForeverFoodBarFood:LeftButton"] = "Use Best Food"
_G["BINDING_NAME_CLICK NaowhForeverFoodBarDrink:LeftButton"] = "Use Best Drink"

local function SwitchedOff(name)
    return function() ns.Print(TEXT_SWITCHED_OFF:format(name)) end
end
NaowhForever_ToggleJournal = SwitchedOff("Dungeon Journal")
NaowhForever_BossLoot = SwitchedOff("Dungeon Journal")
NaowhForever_ToggleBis = SwitchedOff("BiS List")
NaowhForever_ToggleGroupInspect = SwitchedOff("Group Inspect")
NaowhForever_ToggleCompleto = SwitchedOff("Completo")
NaowhForever_BagSpacePickUp = SwitchedOff("Quality of Life")

SLASH_NAOWHFOREVER1 = "/naowh"
SLASH_NAOWHFOREVER2 = "/nao"
SLASH_NAOWHFOREVER3 = "/nf"
SlashCmdList["NAOWHFOREVER"] = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "quiz" and ns.ToggleQuiz then
        ns.ToggleQuiz()
    elseif cmd == "xp" and ns.XPTickerCommand then
        ns.XPTickerCommand(arg)
    elseif cmd == "dungeon" and ns.ToggleJournalWindow then
        ns.ToggleJournalWindow()
    elseif cmd == "group" and ns.ToggleGroupInspect then
        ns.ToggleGroupInspect()
    elseif cmd == "bars" and ns.ActionBarsCommand then
        ns.ActionBarsCommand(strtrim(msg):match("^%S+%s*(.-)$"))
    elseif cmd == "lockouts" and ns.LockoutsCommand then
        ns.LockoutsCommand()
    elseif cmd == "ranks" and ns.TrainerRankCheck then
        ns.TrainerRankCheck()
    elseif cmd == "trainer" and ns.Training then
        ns.Training.WaypointToTrainer()
    elseif cmd == "profrank" and ns.ProfessionRankCheck then
        ns.ProfessionRankCheck()
    elseif cmd == "recipes" and ns.RecipeFinderDebug then
        ns.RecipeFinderDebug()
    elseif cmd == "townaudit" and ns.TownAudit then
        ns.TownAudit()
    elseif cmd == "itemprobe" and ns.JournalItemProbe then
        ns.JournalItemProbe()
    elseif (cmd == "mappins" or cmd == "mapcheck") and ns.DungeonMapCommand then
        ns.DungeonMapCommand(cmd)
    elseif cmd == "badges" and ns.BadgesCommand then
        ns.BadgesCommand(arg)
    elseif cmd == "scrap" and ns.ToggleScrapList then
        ns.ToggleScrapList()
    elseif (cmd == "setup" or cmd == "welcome") and ns.ShowSetup then
        ns.ShowSetup()
    else
        ns.ToggleOptionsWindow()
    end
end

local function AddModuleCommand(mod)
    local key = SLASH_KEY .. mod.command:upper()
    _G["SLASH_" .. key .. "1"] = COMMAND_PREFIX .. mod.command
    if mod.alias then _G["SLASH_" .. key .. "2"] = COMMAND_PREFIX .. mod.alias end
    SlashCmdList[key] = function() OpenModule(mod) end
end

for _, mod in ipairs(MODULES) do
    if mod.command then AddModuleCommand(mod) end
end
