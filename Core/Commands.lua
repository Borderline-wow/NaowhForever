-- Commands.lua: /nf and each module's own command, the key binding names and the compartment entry.
local ns = _G.NaowhForever
local O = ns.Options

local MODULES, OpenModule, DisplayName = O.MODULES, O.OpenModule, O.DisplayName

local COMMAND_PREFIX = "/nf"
local SLASH_KEY = "NAOWHFOREVER"
local MODULE_ARGS = { bars = "ActionBarsCommand" }
local TIP_TITLE = { r = 1, g = 0.82, b = 0 }
local TIP_TEXT = { r = 1, g = 1, b = 1 }
local TEXT_BRAND = "Naowh Forever"
local TEXT_CLICK = "Click to open settings."
local TEXT_SWITCHED_OFF = "%s is switched off. Turn it on under Settings > Modules."
local TEXT_HELP_TITLE = "Commands:"
local TEXT_HELP_MODULE = "%s%s: opens %s"
local TEXT_HELP_ALIAS = "%s%s or %s%s: opens %s"
local TEXT_HELP_BADGES = "/nf badges id: your badge claim code"
local HELP_LINES = {
    "/nf: opens the settings",
    "/nf help: this list",
    "/nf move (or /nf hud): opens or closes the HUD Editor",
    "/nf bars save, restore, test or delete <name>: your action bar sets; /nf bars list lists them",
    "/nf xp start, pause or reset: the XP ticker",
    "/nf lockouts: your raid and dungeon lockouts",
    "/nf ranks: higher ranks to put on your bars",
    "/nf trainer: a waypoint to your nearest class trainer",
    "/nf profrank: your professions' next ranks",
    "/nf scrap: the Scrap List",
    "/nf quiz: the WoW quiz",
    "/nf setup: the onboarding",
}

function _G.NaowhForever_OnCompartmentClick()
    ns.ToggleOptionsWindow()
end

function _G.NaowhForever_OnCompartmentEnter(_, button)
    local title, text = ns.ThemeTint("accent", TIP_TITLE), ns.ThemeTint("fg", TIP_TEXT)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(TEXT_BRAND, title.r, title.g, title.b)
    GameTooltip:AddLine(ns.L(TEXT_CLICK), text.r, text.g, text.b)
    GameTooltip:Show()
end

function _G.NaowhForever_OnCompartmentLeave()
    GameTooltip:Hide()
end

function _G.NaowhForever_ToggleHudEditor()
    if ns.IsUnlockModeActive() then ns.HideUnlockMode() else ns.ShowUnlockMode() end
end

local function PrintHelp()
    ns.Print(TEXT_HELP_TITLE)
    for _, line in ipairs(HELP_LINES) do print(line) end
    for _, mod in ipairs(MODULES) do
        if mod.alias then
            print(TEXT_HELP_ALIAS:format(COMMAND_PREFIX, mod.command, COMMAND_PREFIX, mod.alias, DisplayName(mod)))
        elseif mod.command then
            print(TEXT_HELP_MODULE:format(COMMAND_PREFIX, mod.command, DisplayName(mod)))
        end
    end
    if ns.FEATURE_BADGES == ns.BADGES_LIVE then print(TEXT_HELP_BADGES) end
end

BINDING_HEADER_NAOWHFOREVER = "Naowh Forever"
BINDING_NAME_NAOWHFOREVER_JOURNAL = "Open Dungeon Journal"
BINDING_NAME_NAOWHFOREVER_BOSSLOOT = "Boss Loot at Cursor"
BINDING_NAME_NAOWHFOREVER_BIS = "Open BiS List"
BINDING_NAME_NAOWHFOREVER_GROUPINSPECT = "Open Group Inspect"
BINDING_NAME_NAOWHFOREVER_COMPLETO = "Open Completo"
BINDING_NAME_NAOWHFOREVER_BAGSPACE_PICKUP = "Pick Up Cheapest Item"
BINDING_NAME_NAOWHFOREVER_HUD = "Open or Close the HUD Editor"
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
    if cmd == "help" or cmd == "?" then
        PrintHelp()
    elseif cmd == "move" or cmd == "hud" then
        NaowhForever_ToggleHudEditor()
    elseif cmd == "quiz" and ns.ToggleQuiz then
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
    SlashCmdList[key] = function(msg)
        local run = MODULE_ARGS[mod.command]
        msg = strtrim(msg or "")
        if run and msg ~= "" and ns[run] then return ns[run](msg) end
        OpenModule(mod)
    end
end

for _, mod in ipairs(MODULES) do
    if mod.command then AddModuleCommand(mod) end
end
