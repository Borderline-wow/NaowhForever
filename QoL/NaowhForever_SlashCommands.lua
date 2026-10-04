-------------------------------------------------------------------------------
--  NaowhForever_SlashCommands.lua -- the QoL custom slash commands: your own short commands that
--  open a game window or run another slash command.
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

local function FindInList(list, command)
    if type(list) ~= "table" then return end
    for key, handler in pairs(list) do
        local i = 1
        local alias = _G["SLASH_" .. key .. i]
        while alias do
            if strupper(alias) == command then return handler end
            i = i + 1
            alias = _G["SLASH_" .. key .. i]
        end
    end
end

-- Whenever chat text is parsed, the game moves SlashCmdList's entries into
-- hash_SlashCmdList and a table behind SlashCmdList's metatable, so look in all three.
local function FindHandler(command)
    local handler = hash_SlashCmdList[command] or FindInList(SlashCmdList, command)
    if handler then return handler end
    local meta = getmetatable(SlashCmdList)
    return meta and FindInList(meta.__index, command)
end

-- Calls the command's handler directly. Sending it through the chat box ran the game's chat
-- code from the addon, and the player's next chat message was blocked.
local function RunCommand(command, args)
    if not command:match("^/") then command = "/" .. command end
    if args and args ~= "" then command = command .. " " .. args end
    local name = command:match("^/%S+")
    if not name then return end
    local key = strupper(name)
    -- /cast, /use, /target and the other macro commands only run from the chat box or a macro.
    if IsSecureCmd(key) then
        ns.Print(name .. " can't be run from a custom command. Put it in a macro instead.")
        return
    end
    local msg = strtrim(command:sub(#name + 1))
    local handler = FindHandler(key)
    if not handler then
        local emote = hash_EmoteTokenList[key]
        if emote then
            C_ChatInfo.PerformEmote(emote, msg)
        else
            ns.Print(name .. " isn't a command this can run.")
        end
        return
    end
    -- The game blocks ReloadUI from addon code.
    if handler == SlashCmdList.RELOAD then
        ns.Print("A custom command can't reload. Type /reload.")
        return
    end
    handler(msg, nil)
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
        -- The chat box caches handlers here the first time any slash command is typed.
        hash_SlashCmdList["/" .. strupper(name)] = nil
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
        targetLabel:SetText(isFrame and "Window" or "Command to run, such as /dance. What you "
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

local EDITOR_W, EDITOR_PAD, EDITOR_TOP, EDITOR_ROW, EDITOR_FOOT = 460, 20, 52, 30, 62
local EDITOR_NAME_W, EDITOR_GAP, EDITOR_REMOVE_W, EDITOR_BUTTON_H = 90, 10, 76, 22
local FOOT_BUTTON_W, FOOT_RESTORE_W, FOOT_BUTTON_H, FOOT_Y = 100, 150, 26, 16

local function Edited()
    ns.RefreshSlashCommands()
    UI:RefreshPage(true)
end

function ns.ShowSlashCommandEditor()
    local list = ns.SlashCommandList()
    local dimmer, panel = ns.MakeModal(EDITOR_W, EDITOR_TOP + math.max(1, #list) * EDITOR_ROW + EDITOR_FOOT,
        "slashCommandEditor")
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOPLEFT", EDITOR_PAD, -16)
    head:SetText("Custom Slash Commands")

    if #list == 0 then
        local none = UI.KeepFont(panel, "none", 12, nil, T.muted)
        none:SetPoint("TOPLEFT", EDITOR_PAD, -EDITOR_TOP)
        none:SetText("No commands yet. Add one, or restore the defaults.")
    end
    for i, cmd in ipairs(list) do
        local y = -(EDITOR_TOP + (i - 1) * EDITOR_ROW)
        local toggle = UI.KeepToggle(panel, "toggle", function() return cmd.enabled end, function(v)
            cmd.enabled = v
            Edited()
        end)
        toggle:SetPoint("TOPLEFT", EDITOR_PAD, y)
        local name = UI.KeepFont(panel, "name", 13)
        name:SetPoint("LEFT", toggle, "RIGHT", EDITOR_GAP, 0)
        name:SetText("/" .. cmd.name)
        local remove = UI.KeepButton(panel, "remove", "Remove", EDITOR_REMOVE_W, EDITOR_BUTTON_H, function()
            if ns.RemoveSlashCommand(cmd.name) then UI:RefreshPage(true) end
            ns.ShowSlashCommandEditor()
        end)
        remove:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -EDITOR_PAD, y + (EDITOR_BUTTON_H - toggle:GetHeight()) / 2)
        local what = UI.KeepFont(panel, "what", 12, nil, T.muted)
        what:SetPoint("LEFT", toggle, "RIGHT", EDITOR_GAP + EDITOR_NAME_W, 0)
        what:SetPoint("RIGHT", remove, "LEFT", -EDITOR_GAP, 0)
        what:SetJustifyH("LEFT")
        what:SetWordWrap(false)
        what:SetText(ns.SlashCommandSummary(cmd))
    end

    UI.KeepButton(panel, "add", "Add", FOOT_BUTTON_W, FOOT_BUTTON_H, function()
        ns.ShowAddSlashCommand(function()
            UI:RefreshPage(true)
            ns.ShowSlashCommandEditor()
        end)
    end):SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", EDITOR_PAD, FOOT_Y)
    UI.KeepButton(panel, "restore", "Restore Defaults", FOOT_RESTORE_W, FOOT_BUTTON_H, function()
        ns.Confirm("Replace your commands with the defaults?", function()
            ns.RestoreSlashCommands()
            UI:RefreshPage(true)
            ns.ShowSlashCommandEditor()
        end)
    end):SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", EDITOR_PAD + FOOT_BUTTON_W + EDITOR_GAP, FOOT_Y)
    UI.KeepButton(panel, "close", "Close", FOOT_BUTTON_W, FOOT_BUTTON_H, function() dimmer:Hide() end)
        :SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -EDITOR_PAD, FOOT_Y)
    dimmer:Show()
end

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local function Summary()
    local list, on = ns.SlashCommandList(), 0
    for _, cmd in ipairs(list) do
        if cmd.enabled then on = on + 1 end
    end
    return ("%d %s, %d on"):format(#list, #list == 1 and "command" or "commands", on)
end

Settings.Page("QoL/System", S):Card({
    id = "slashCommands", name = "Custom Slash Commands", order = 20, switch = "slashCommands",
    help = "Short commands of your own that open a game window or run another command. A name another "
        .. "addon already uses is skipped.",
    summary = Summary,
    rows = {
        { label = "Edit Commands", buttonText = "Edit...", button = ns.ShowSlashCommandEditor,
          help = "Add or remove your commands, turn each one on or off, or restore the defaults." },
    },
})

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "slashCommands" then ns.RefreshSlashCommands() end
end)
hooksecurefunc(ns, "Apply", function() ns.RefreshSlashCommands() end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() ns.RefreshSlashCommands() end)
