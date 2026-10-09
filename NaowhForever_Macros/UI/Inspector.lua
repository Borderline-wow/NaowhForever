-- Inspector.lua: the panes beside Naowh's Forge's editor: what the macro does, a condition builder, the commands and the icons.
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local M = ns.Macros
local St = M.Style
local P = M.Parts
local F = M.Forge
local Parts = ns.Shared.Parts
local Text = ns.MacroText

local PAD, BUTTON_H, BLACK = St.PAD, St.BUTTON_H, St.BORDER_RGB
local SMALL_SIZE, NOTE_SIZE, TEXT_SIZE = St.SMALL_SIZE, St.NOTE_SIZE, St.TEXT_SIZE
local WIDTH = St.INSPECTOR_W - 2 * PAD
local PANE_GAP = 12
local HEAD_H = 22
local MENU_LEVEL, LABEL_GAP = 2, 4
local NUMBER_BOX, NUMBER_RISE, TEXT_INDENT, LINE_SPACING = 20, 1, 30, 2
local SAID_MIN_H, SAID_GAP = 18, 10
local FLAG_H, FLAG_GAP, FLAG_TOP, FLAG_STEP, FLAG_COLS = 24, 6, 10, 30, 2
local PREVIEW_GAP, READS_GAP, INSERT_W = 14, 8, 96
local BRACKETS_RGB = { r = 0.95, g = 0.83, b = 0.42 }
local COMMAND_RGB = { r = 0.42, g = 0.77, b = 1 }
local COMMAND_H, COMMAND_INSET_X, COMMAND_INSET_Y = 34, 8, 4
local TITLE_H, GROUP_GAP = 18, 8
local ICON_COLS, ICON_ROWS, ICON_SIZE, ICON_GAP = 7, 6, 36, 6
local ICONS_PER_PAGE = ICON_COLS * ICON_ROWS
local STAR_SIZE, STAR_NUDGE, STAR = 12, 1, "*"

local TEXT_EXPLAIN_HINT = "What this macro does, line by line."
local TEXT_SAYS_NOTHING = "Write a line and this says what it does."
local TEXT_ON, TEXT_HOLDING, TEXT_INSERT = "On", "Holding", "Insert"
local TEXT_READS_AS = "Reads as: "
local TEXT_SAMPLE = "/cast %s the spell"
local TEXT_ICON_HINT = "Right-click to star an icon. Scroll for more."
local TEXT_PAGE = "Page %d of %d"

local TABS = {
    { key = "explain", label = "Explain" }, { key = "conditions", label = "Conditions" },
    { key = "commands", label = "Commands" }, { key = "icons", label = "Icons" },
}

local CONDITION_UNITS = { [""] = "Your target", ["@mouseover"] = "Your mouseover", ["@focus"] = "Your focus",
    ["@player"] = "Yourself", ["@targettarget"] = "Your target's target", ["@cursor"] = "The cursor" }
local CONDITION_UNIT_ORDER = { "", "@mouseover", "@focus", "@player", "@targettarget", "@cursor" }
local CONDITION_MODS = { [""] = "Any key", ["mod:shift"] = "Shift", ["mod:ctrl"] = "Ctrl", ["mod:alt"] = "Alt",
    nomod = "No modifier" }
local CONDITION_MOD_ORDER = { "", "mod:shift", "mod:ctrl", "mod:alt", "nomod" }
local CONDITION_FLAGS = { { "harm", "Hostile" }, { "help", "Friendly" }, { "exists", "Exists" },
    { "nodead", "Alive" }, { "combat", "In combat" }, { "nocombat", "Out of combat" } }
local FLAG_ROWS = math.ceil(#CONDITION_FLAGS / FLAG_COLS)

local COMMANDS = {
    { "Casting", { { "/cast", "Cast a spell, with conditions" }, { "/castsequence", "One spell per press, in order" },
        { "/stopcasting", "Stop your current cast" }, { "/use", "Use an item, or a slot: 13, 14" } } },
    { "Targeting", { { "/target", "Target a unit by name" }, { "/focus", "Set your focus" },
        { "/assist", "Take your target's target" }, { "/cleartarget", "Clear your target" } } },
    { "Combat", { { "/startattack", "Start auto attack" }, { "/stopattack", "Stop auto attack" },
        { "/petattack", "Send your pet in" }, { "/tm 8", "Skull on your target" },
        { "/cancelaura", "Remove a buff from you" } } },
    { "On the button", { { "#showtooltip", "Show the spell on the button" } } },
}

local inspector, panes
local built = { unit = "", mod = "", flags = {} }
local iconPage = 1
local view, flagButtons, iconButtons = {}, {}, {}
local iconList, bracketParts = {}, {}

local function Insert(text)
    F.window.code:SetFocus()
    F.window.code:Insert(text)
end

local function Refresh()
    inspector.Refresh()
end

local function Favorites()
    local account = ns.AccountSettings()
    account.macroFavoriteIcons = account.macroFavoriteIcons or {}
    return account.macroFavoriteIcons
end

local function Brackets()
    wipe(bracketParts)
    if built.unit ~= "" then bracketParts[#bracketParts + 1] = built.unit end
    for _, flag in ipairs(CONDITION_FLAGS) do
        if built.flags[flag[1]] then bracketParts[#bracketParts + 1] = flag[1] end
    end
    if built.mod ~= "" then bracketParts[#bracketParts + 1] = built.mod end
    return "[" .. table.concat(bracketParts, ",") .. "]"
end

local function Show(key)
    Parts.PaintTabs(inspector.tabs, key)
    for k, pane in pairs(panes) do pane:SetShown(k == key) end
    inspector.shown = key
    inspector.Refresh()
end

local function Pane()
    local pane = CreateFrame("Frame", nil, inspector)
    pane:SetPoint("TOPLEFT", inspector.tabs, "BOTTOMLEFT", 0, -PANE_GAP)
    pane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    pane:Hide()
    return pane
end

local function NewSaidRow()
    local row = CreateFrame("Frame", nil, panes.explain)
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(NUMBER_BOX, NUMBER_BOX)
    row.box:SetPoint("TOPLEFT", 0, NUMBER_RISE)
    ns.Solid(row.box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(row.box, BLACK)
    row.number = P.Text(row.box, SMALL_SIZE, T.muted)
    row.number:SetPoint("CENTER")
    row.text = P.Text(row, TEXT_SIZE)
    row.text:SetPoint("TOPLEFT", TEXT_INDENT, 0)
    row.text:SetWidth(WIDTH - TEXT_INDENT)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row.text:SetSpacing(LINE_SPACING)
    return row
end

local function BuildExplain()
    panes.explain = Pane()
    local hint = P.Text(panes.explain, SMALL_SIZE, T.muted)
    hint:SetPoint("TOPLEFT")
    hint:SetText(TEXT_EXPLAIN_HINT)
    view.rows = P.Pool(NewSaidRow)
end

local function UnitPicked() return built.unit end
local function PickUnit(v) built.unit = v; Refresh() end
local function ModPicked() return built.mod end
local function PickMod(v) built.mod = v; Refresh() end

local function FlagToggle(flag)
    return function()
        built.flags[flag] = not built.flags[flag] or nil
        Refresh()
    end
end

local function InsertBrackets()
    Insert(Brackets() .. " ")
end

local function Label(pane, text)
    local label = P.Text(pane, SMALL_SIZE, T.muted)
    label:SetText(text)
    return label
end

local function Dropdown(pane, values, order, get, set)
    return UI.BuildDropdownControl(pane, WIDTH, pane:GetFrameLevel() + MENU_LEVEL, values, order, get, set)
end

local function BuildFlags(pane, under)
    for i, flag in ipairs(CONDITION_FLAGS) do
        local b = ns.Button(pane, flag[2], (WIDTH - FLAG_GAP) / FLAG_COLS, FLAG_H, FlagToggle(flag[1]))
        local col, row = (i - 1) % FLAG_COLS, math.floor((i - 1) / FLAG_COLS)
        b:SetPoint("TOPLEFT", under, "BOTTOMLEFT", col * (WIDTH / FLAG_COLS + FLAG_GAP / 2), -FLAG_TOP - row * FLAG_STEP)
        b.flag = flag[1]
        flagButtons[i] = b
    end
end

local function BuildConditions()
    local pane = Pane()
    panes.conditions = pane
    local onLabel = Label(pane, TEXT_ON)
    onLabel:SetPoint("TOPLEFT")
    local unitDrop = Dropdown(pane, CONDITION_UNITS, CONDITION_UNIT_ORDER, UnitPicked, PickUnit)
    unitDrop:SetPoint("TOPLEFT", onLabel, "BOTTOMLEFT", 0, -LABEL_GAP)
    BuildFlags(pane, unitDrop)
    local modLabel = Label(pane, TEXT_HOLDING)
    modLabel:SetPoint("TOPLEFT", unitDrop, "BOTTOMLEFT", 0, -FLAG_TOP - FLAG_ROWS * FLAG_STEP - LABEL_GAP)
    local modDrop = Dropdown(pane, CONDITION_MODS, CONDITION_MOD_ORDER, ModPicked, PickMod)
    modDrop:SetPoint("TOPLEFT", modLabel, "BOTTOMLEFT", 0, -LABEL_GAP)
    view.preview = P.Text(pane, TEXT_SIZE, BRACKETS_RGB)
    view.preview:SetPoint("TOPLEFT", modDrop, "BOTTOMLEFT", 0, -PREVIEW_GAP)
    view.preview:SetPoint("RIGHT")
    view.preview:SetJustifyH("LEFT")
    view.reads = P.Text(pane, NOTE_SIZE, T.muted)
    view.reads:SetPoint("TOPLEFT", view.preview, "BOTTOMLEFT", 0, -READS_GAP)
    view.reads:SetPoint("RIGHT")
    view.reads:SetJustifyH("LEFT")
    local insert = ns.AccentBorder(ns.Button(pane, TEXT_INSERT, INSERT_W, BUTTON_H, InsertBrackets))
    insert:SetPoint("BOTTOMLEFT")
end

local function CommandClick(b)
    Insert("\n" .. b.command .. " ")
end

local function NewCommandRow()
    local b = CreateFrame("Button", nil, panes.commands)
    b:SetHeight(COMMAND_H)
    P.ListRow(b)
    b.code = P.Text(b, TEXT_SIZE, COMMAND_RGB)
    b.code:SetPoint("TOPLEFT", COMMAND_INSET_X, -COMMAND_INSET_Y)
    b.text = P.Text(b, SMALL_SIZE, T.muted)
    b.text:SetPoint("BOTTOMLEFT", COMMAND_INSET_X, COMMAND_INSET_Y)
    b:SetScript("OnClick", CommandClick)
    return b
end

local function NewCommandTitle()
    return P.Text(panes.commands, SMALL_SIZE, T.accentSoft)
end

local function BuildCommands()
    panes.commands = Pane()
    view.commandRows = P.Pool(NewCommandRow)
    view.commandTitles = P.Pool(NewCommandTitle)
end

local function PickIcon(fileID)
    local draft = F.draft
    draft.icon, draft.picked = fileID, true
    local index = F.Current()
    if index and not InCombatLockdown() then
        EditMacro(index, draft.savedName, draft.icon, draft.saved)
    end
    F.Render()
end

local function IconClick(b, button)
    if not b.fileID then return end
    if button == "RightButton" then
        Favorites()[b.fileID] = not Favorites()[b.fileID] or nil
    else
        PickIcon(b.fileID)
    end
    Refresh()
end

local function IconWheel(_, delta)
    iconPage = math.max(1, iconPage - delta)
    Refresh()
end

local function NewIconButton(pane, i)
    local b = CreateFrame("Button", nil, pane)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = P.Icon(b, ICON_SIZE - St.ICON_EDGES)
    b.icon.edge:SetPoint("TOPLEFT")
    b.star = P.Text(b, STAR_SIZE, St.TIP_RGB)
    b.star:SetPoint("TOPRIGHT", STAR_NUDGE, STAR_NUDGE)
    b.star:SetText(STAR)
    local col, row = (i - 1) % ICON_COLS, math.floor((i - 1) / ICON_COLS)
    b:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_GAP), -HEAD_H - row * (ICON_SIZE + ICON_GAP))
    b:SetScript("OnClick", IconClick)
    return b
end

local function BuildIcons()
    local pane = Pane()
    panes.icons = pane
    for i = 1, ICONS_PER_PAGE do iconButtons[i] = NewIconButton(pane, i) end
    view.pageLabel = P.Text(pane, SMALL_SIZE, T.muted)
    view.pageLabel:SetPoint("TOPLEFT")
    local hint = P.Text(pane, SMALL_SIZE, T.muted)
    hint:SetPoint("BOTTOMLEFT")
    hint:SetText(TEXT_ICON_HINT)
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", IconWheel)
end

local function SaidRow(y)
    local row = view.rows.Take()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    return row
end

local function DrawExplain()
    view.rows.Release()
    local y = -HEAD_H
    local sentences = Text.Explain(F.Code())
    for i, sentence in ipairs(sentences) do
        local row = SaidRow(y)
        row.number:SetText(i)
        row.box:Show()
        row.text:SetText(sentence)
        local h = math.max(SAID_MIN_H, row.text:GetStringHeight())
        row:SetHeight(h)
        y = y - h - SAID_GAP
    end
    if #sentences > 0 then return end
    local row = SaidRow(y)
    row.box:Hide()
    row.text:SetText(ns.Color("muted", TEXT_SAYS_NOTHING))
    row:SetHeight(SAID_MIN_H)
end

local function DrawConditions()
    for _, b in ipairs(flagButtons) do
        b._rest = built.flags[b.flag] and T.accent or BLACK
        b._border:SetColor(b._rest.r, b._rest.g, b._rest.b, 1)
    end
    local brackets = Brackets()
    view.preview:SetText(brackets)
    view.reads:SetText(TEXT_READS_AS .. (Text.Explain(TEXT_SAMPLE:format(brackets))[1] or ""))
end

local function DrawCommands()
    view.commandRows.Release()
    view.commandTitles.Release()
    local y, n = 0, 0
    for _, group in ipairs(COMMANDS) do
        local title = view.commandTitles.Take()
        title:SetPoint("TOPLEFT", 0, y)
        title:SetText(group[1]:upper())
        y = y - TITLE_H
        for _, command in ipairs(group[2]) do
            n = n + 1
            local b = view.commandRows.Take()
            b:SetPoint("TOPLEFT", 0, y)
            b:SetPoint("RIGHT")
            b.code:SetText(command[1])
            b.text:SetText(command[2])
            b.stripe:SetShown(n % 2 == 0)
            P.Pick(b, false)
            b.command = command[1]
            y = y - COMMAND_H
        end
        y = y - GROUP_GAP
    end
end

local function IconList()
    wipe(iconList)
    local favorites = Favorites()
    for fileID in pairs(favorites) do iconList[#iconList + 1] = fileID end
    table.sort(iconList)
    for _, fileID in ipairs(ns.MacroIconList()) do
        if not favorites[fileID] then iconList[#iconList + 1] = fileID end
    end
    return iconList, favorites
end

local function DrawIcons()
    local list, favorites = IconList()
    local pages = math.max(1, math.ceil(#list / ICONS_PER_PAGE))
    iconPage = math.min(iconPage, pages)
    view.pageLabel:SetText(TEXT_PAGE:format(iconPage, pages))
    for i, b in ipairs(iconButtons) do
        local fileID = list[(iconPage - 1) * ICONS_PER_PAGE + i]
        b.fileID = fileID
        b:SetShown(fileID ~= nil)
        if fileID then
            b.icon:SetTexture(fileID)
            b.star:SetShown(favorites[fileID] == true)
        end
    end
end

local DRAW = { explain = DrawExplain, conditions = DrawConditions, commands = DrawCommands, icons = DrawIcons }

local function InspectorRefresh()
    if not F.draft then return end
    local draw = DRAW[inspector.shown]
    if draw then draw() end
end

function F.BuildInspector(parent)
    inspector = CreateFrame("Frame", nil, parent)
    inspector:SetAllPoints()
    F.window.inspector = inspector
    panes = {}
    inspector.Show = Show
    inspector.Refresh = InspectorRefresh
    inspector.tabs = Parts.Tabs(inspector, WIDTH, TABS, Show)
    inspector.tabs:SetPoint("TOPLEFT", PAD, -PAD)
    BuildExplain()
    BuildConditions()
    BuildCommands()
    BuildIcons()
    Show("explain")
end
