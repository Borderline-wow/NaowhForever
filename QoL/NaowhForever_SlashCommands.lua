-------------------------------------------------------------------------------
--  NaowhForever_SlashCommands.lua -- the QoL custom slash commands: short commands of your
--  own that open a game window or run another slash command, arguments passed through.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI
local T = ns.THEME

local DEFAULTS = {
    { name = "cdm", frame = "CooldownViewerSettings", enabled = true },
    { name = "em", frame = "EditModeManagerFrame", enabled = true },
    { name = "kb", frame = "QuickKeybindFrame", enabled = true },
}

-- Windows worth a shortcut, and the Blizzard addon each loads from when it is not loaded
-- up front. Only the ones this client has are offered.
local FRAMES = {
    { "Achievements", "AchievementFrame", "Blizzard_AchievementUI" },
    { "Addon List", "AddonList" },
    { "Auction House", "AuctionHouseFrame", "Blizzard_AuctionHouseUI" },
    { "Calendar", "CalendarFrame", "Blizzard_Calendar" },
    { "Channels", "ChannelFrame", "Blizzard_Channels" },
    { "Chat Config", "ChatConfigFrame" },
    { "Click Binding", "ClickBindingFrame", "Blizzard_ClickBindingUI" },
    { "Collections", "CollectionsJournal", "Blizzard_Collections" },
    { "Communities", "CommunitiesFrame", "Blizzard_Communities" },
    { "Cooldown Viewer", "CooldownViewerSettings", "Blizzard_CooldownViewer" },
    { "Death Recap", "DeathRecapFrame", "Blizzard_DeathRecap" },
    { "Dress Up", "DressUpFrame" },
    { "Dungeon Journal", "EncounterJournal", "Blizzard_EncounterJournal" },
    { "Edit Mode", "EditModeManagerFrame", "Blizzard_EditMode" },
    { "Game Menu", "GameMenuFrame" },
    { "Group Finder", "PVEFrame" },
    { "Guild Bank", "GuildBankFrame", "Blizzard_GuildBankUI" },
    { "Help", "HelpFrame", "Blizzard_HelpFrame" },
    { "Loot History", "GroupLootHistoryFrame", "Blizzard_GroupLootHistoryFrame" },
    { "Macros", "MacroFrame", "Blizzard_MacroUI" },
    { "Pet Stable", "StableFrame", "Blizzard_StableUI" },
    { "Quick Keybind", "QuickKeybindFrame", "Blizzard_QuickKeybind" },
    { "Raid Manager", "CompactRaidFrameManager", "Blizzard_CompactRaidFrames" },
    { "Settings", "SettingsPanel" },
    { "Spellbook / Talents", "PlayerSpellsFrame", "Blizzard_PlayerSpells" },
    { "Stopwatch", "StopwatchFrame" },
    { "Time Manager", "TimeManagerFrame", "Blizzard_TimeManager" },
    { "World Map", "WorldMapFrame", "Blizzard_WorldMap" },
}

local ADDON_FOR, FRAME_NAME = {}, {}
for _, f in ipairs(FRAMES) do
    ADDON_FOR[f[2]] = f[3]
    FRAME_NAME[f[2]] = f[1]
end

local registered = {}

local function On()
    return S.Get("enabled") and S.Get("slashCommands")
end

local function Available(frame)
    if _G[frame] then return true end
    local addon = ADDON_FOR[frame]
    return addon ~= nil and C_AddOns.DoesAddOnExist(addon)
end

-- Copied into the profile on first use, so the defaults are never written into.
function ns.SlashCommandList()
    local db = S.DB()
    if type(db.slashList) ~= "table" then
        db.slashList = {}
        for i, cmd in ipairs(DEFAULTS) do db.slashList[i] = CopyTable(cmd) end
    end
    return db.slashList
end

local function SlashID(name)
    return "NAOWHFOREVER_" .. strupper(name)
end

local function RunCommand(command, args)
    if not command:match("^/") then command = "/" .. command end
    if args and args ~= "" then command = command .. " " .. args end
    local box = ChatFrame1EditBox or DEFAULT_CHAT_FRAME.editBox
    local original = box:GetText()
    box:SetText(command)
    ChatEdit_SendText(box)
    box:SetText(original)
end

local function ToggleFrame(name)
    if InCombatLockdown() then
        ns.Print("Windows cannot be opened or closed by a command in combat.")
        return
    end
    local addon = ADDON_FOR[name]
    if addon and not C_AddOns.IsAddOnLoaded(addon) then C_AddOns.LoadAddOn(addon) end
    local frame = _G[name]
    if type(frame) == "table" and frame.IsShown then frame:SetShown(not frame:IsShown()) end
end

local function Register(cmd)
    local name = strlower(cmd.name)
    local id = SlashID(name)
    local existing = _G["SLASH_" .. strupper(name) .. "1"]
    if existing and existing ~= _G["SLASH_" .. id .. "1"] then
        ns.Print("/" .. name .. " already belongs to another addon, so it was skipped.")
        return
    end
    _G["SLASH_" .. id .. "1"] = "/" .. name
    SlashCmdList[id] = function(msg)
        if cmd.command then RunCommand(cmd.command, msg) else ToggleFrame(cmd.frame) end
    end
    registered[name] = id
end

function ns.RefreshSlashCommands()
    for name, id in pairs(registered) do
        _G["SLASH_" .. id .. "1"] = nil
        SlashCmdList[id] = nil
        registered[name] = nil
    end
    if not On() then return end
    for _, cmd in ipairs(ns.SlashCommandList()) do
        if cmd.enabled and (cmd.command or Available(cmd.frame)) then Register(cmd) end
    end
end

-- What a command does, for its row on the options page.
function ns.SlashCommandSummary(cmd)
    if cmd.command then return "runs " .. cmd.command end
    local label = FRAME_NAME[cmd.frame] or cmd.frame
    if not Available(cmd.frame) then return "opens " .. label .. " (not in this game)" end
    return "opens " .. label
end

function ns.RemoveSlashCommand(name)
    name = strlower((strtrim(name):gsub("^/", "")))
    local list = ns.SlashCommandList()
    for i = #list, 1, -1 do
        if strlower(list[i].name) == name then
            table.remove(list, i)
            ns.RefreshSlashCommands()
            return true
        end
    end
    return false
end

function ns.RestoreSlashCommands()
    S.DB().slashList = nil
    ns.RefreshSlashCommands()
end

-------------------------------------------------------------------------------
--  Add dialog
-------------------------------------------------------------------------------
local ACTION_VALUES = { frame = "Open a Window", command = "Run a Command" }
local ACTION_ORDER = { "frame", "command" }

local function Label(panel, key, text, anchor)
    local fs = UI.KeepFont(panel, key, 12, nil, T.muted)
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    fs:SetWidth(340)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

function ns.ShowAddSlashCommand(onAdded)
    local dimmer, panel = ns.MakeModal(380, 290, "addSlashCommand")
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOPLEFT", 20, -16)
    head:SetText("Add Slash Command")

    local nameLabel = Label(panel, "nameLabel", "Command name, such as r for /r", head)
    local nameBox = UI.Keep(panel, "nameBox", ns.NewEditBox)
    nameBox:SetSize(340, 26)
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
    nameBox:SetMaxLetters(24)
    nameBox:SetText("")

    local action, frame = "frame", nil
    local frames, frameOrder = {}, {}
    for _, f in ipairs(FRAMES) do
        if Available(f[2]) then
            frames[f[2]] = f[1]
            frameOrder[#frameOrder + 1] = f[2]
        end
    end

    local ShowAction
    local actionLabel = Label(panel, "actionLabel", "It should", nameBox)
    local actionDD = UI.KeepDropdown(panel, "actionDD", 340, ACTION_VALUES, ACTION_ORDER,
        function() return action end, function(v)
            action = v
            ShowAction()
        end)
    actionDD:SetPoint("TOPLEFT", actionLabel, "BOTTOMLEFT", 0, -4)

    local targetLabel = Label(panel, "targetLabel", "", actionDD)
    local frameDD = UI.KeepDropdown(panel, "frameDD", 340, frames, frameOrder,
        function() return frame end, function(v) frame = v end)
    frameDD:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -4)
    local commandBox = UI.Keep(panel, "commandBox", ns.NewEditBox)
    commandBox:SetSize(340, 26)
    commandBox:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -4)
    commandBox:SetText("")

    function ShowAction()
        local isFrame = action == "frame"
        targetLabel:SetText(isFrame and "Window" or "Command to run, such as /reload. What you "
            .. "type after your command is added to it.")
        frameDD:SetShown(isFrame)
        commandBox:SetShown(not isFrame)
    end
    ShowAction()

    local function Save()
        local name = (strtrim(nameBox:GetText()):gsub("^/", ""))
        if name == "" or not name:match("^[%w_]+$") then
            ns.Print("A command name can only use letters, numbers and underscores.")
            return
        end
        local command = strtrim(commandBox:GetText())
        if action == "frame" and not frame then return ns.Print("Pick a window to open.") end
        if action == "command" and command == "" then return ns.Print("Type a command to run.") end
        local list = ns.SlashCommandList()
        for _, cmd in ipairs(list) do
            if strlower(cmd.name) == strlower(name) then
                return ns.Print("/" .. name .. " is already one of your commands.")
            end
        end
        list[#list + 1] = { name = strlower(name), enabled = true,
            frame = action == "frame" and frame or nil,
            command = action == "command" and command or nil }
        dimmer:Hide()
        ns.RefreshSlashCommands()
        if onAdded then onAdded() end
    end
    UI.KeepButton(panel, "save", "Save", 110, 26, Save):SetPoint("BOTTOM", panel, "BOTTOM", -60, 16)
    UI.KeepButton(panel, "cancel", "Cancel", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 60, 16)
    dimmer:Show()
    nameBox:SetFocus()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "slashCommands" then ns.RefreshSlashCommands() end
end)
hooksecurefunc(ns, "Apply", function() ns.RefreshSlashCommands() end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() ns.RefreshSlashCommands() end)
