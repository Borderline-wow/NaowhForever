-------------------------------------------------------------------------------
--  UI/SettingsPage.lua -- the Dungeon Journal's page in the options window: a card that
--  says where you stand and opens the Journal, then its switches, then this character's
--  latest kills and loot. What it lists and shows
--  comes from J.OPTION_GROUPS, the same list the window's Filters menu is built from, so
--  the two always match; either one changes the other. Page builder only, resolved by the
--  options window at open time.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings
local Loot = J.Loot
local Quests = J.Quests
local Kills = J.Kills
local Looted = J.Looted

local St = J.Style
local BORDER_RGB, CARD_FILL, OPACITY_MIN, LOGO = St.BORDER_RGB, St.WINDOW_CARD_FILL, St.OPACITY_MIN, St.LOGO
local SKULL, KILL_DATE = St.SKULL, St.KILL_DATE

local CARD_H = 76
local CARD_PAD = 16
local ICON = 52
local BUTTON_W, BUTTON_H = 190, 30
local LINE_GAP = 6

local RECENT_ROWS = 5      -- the most kills, and items, listed
local RECENT_ROW = 26      -- one of them
local RECENT_HEAD = 30     -- a column's title, above them
local RECENT_FOOT = 8      -- below the last one
local RECENT_INSET = 20    -- a column's edge to its text, as in the switches' rows
local RECENT_ICON = 16     -- the skull, or the item's icon
local RECENT_GAP = 8       -- the icon to the name
-- On the right, in columns of their own so they line up from row to row: the dungeon from a
-- fixed place, and how long ago against the edge ("30 Sep 2026" is the widest).
local WHERE_W, AGO_W, COLUMN_GAP = 150, 76, 12
local RESET_W, RESET_H = 64, 20   -- a column's Reset button, at its top right
local RESET_TOP = 6

-- The Journal opens in place of the options window, which would otherwise sit over it.
local function OpenJournal()
    ns.StashOptionsWindow()
    ns.OpenJournalWindow()
end

local function OpenAt(dungeon)
    ns.StashOptionsWindow()
    ns.OpenJournalWindow(dungeon)
end

-------------------------------------------------------------------------------
--  The card: where you stand, and the button to open the Journal
-------------------------------------------------------------------------------
-- The dungeon for you right now: the one you are in, else the first dungeon (not a raid)
-- whose range holds your level; nil when none does.
local function ForYou()
    local here = J.Current()
    if here then return here[1], true end
    local level = UnitLevel("player")
    for _, dungeon in ipairs(J.Dungeons()) do
        local levels = not dungeon.raid and J.Levels(dungeon)
        if levels and level >= levels[1] and level <= levels[2] then return dungeon, false end
    end
end

local function Headline(dungeon, inside)
    if not dungeon then return "Every dungeon and raid: what drops, your quests, and more." end
    local name = ns.Color("accentSoft", dungeon.name)
    if inside then return ("You are in %s."):format(name) end
    return ("%s is for your level (%s)."):format(name, J.LevelRange(dungeon))
end

-- Your quests there, as the Journal counts them; nil when there are none.
local function QuestLine(dungeon)
    if not (dungeon and dungeon.quests) then return end
    local toPickUp, inLog = Quests.Count(dungeon.quests)
    if toPickUp + inLog == 0 then return end
    local parts = {}
    if toPickUp > 0 then parts[#parts + 1] = ("%d to pick up"):format(toPickUp) end
    if inLog > 0 then parts[#parts + 1] = ("%d in your log"):format(inLog) end
    return "Your quests there: " .. table.concat(parts, ", ") .. "."
end

local function MakeCard(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(CARD_H)
    ns.Solid(card, "BACKGROUND", T.fg, CARD_FILL):SetAllPoints()
    ns.Border(card, BORDER_RGB)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("LEFT", CARD_PAD, 0)
    card.icon:SetTexture(LOGO, nil, nil, "TRILINEAR")
    card.open = ns.AccentBorder(ns.Button(card, "Open Dungeon Journal", BUTTON_W, BUTTON_H, OpenJournal))
    card.open:SetPoint("RIGHT", -CARD_PAD, 0)
    card.headline = ns.Font(card, 15, nil, T.fg)
    card.detail = ns.Font(card, 12, nil, T.muted)
    for _, line in ipairs({ card.headline, card.detail }) do
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:SetPoint("RIGHT", card.open, "LEFT", -CARD_PAD, 0)
    end
    return card
end

-- Lays the card's lines out: one, or two with your quests, as a block centred beside the
-- logo.
local function FillCard(card)
    local dungeon, inside = ForYou()
    local quests = QuestLine(dungeon)
    card.headline:SetText(Headline(dungeon, inside))
    card.detail:SetText(quests or "")
    card.detail:SetShown(quests ~= nil)
    local height = quests and 15 + LINE_GAP + 12 or 15
    card.headline:ClearAllPoints()
    card.headline:SetPoint("TOPLEFT", card.icon, "RIGHT", CARD_PAD, height / 2)
    card.headline:SetPoint("RIGHT", card.open, "LEFT", -CARD_PAD, 0)
    card.detail:ClearAllPoints()
    card.detail:SetPoint("TOPLEFT", card.headline, "BOTTOMLEFT", 0, -LINE_GAP)
    card.detail:SetPoint("RIGHT", card.open, "LEFT", -CARD_PAD, 0)
end

local function Card(parent, y)
    local UI = ns.UI
    -- The settings search builds no frames: it only needs the rows below.
    if UI.searchScan then return y - CARD_H - CARD_PAD end
    local card = UI.Keep(parent, "journalCard", MakeCard)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y - CARD_PAD)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y - CARD_PAD)
    FillCard(card)
    return y - CARD_H - CARD_PAD
end

-------------------------------------------------------------------------------
--  Recent: this character's latest kills, and its latest loot in the Journal's dungeons and
--  raids, side by side. A click opens the dungeon in the Journal.
-------------------------------------------------------------------------------
local latestKills, latestLoot = {}, {}   -- Kills.Latest's and Looted.Latest's lists, reused
local FightLength = J.View.Parts.FightLength
local OPEN_HINT = "Click to open the dungeon in the Journal."

-- How long ago: "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago", else the date.
local function Ago(when)
    local seconds = time() - when
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%d min ago"):format(math.floor(seconds / 60)) end
    if seconds < 86400 then return ("%d h ago"):format(math.floor(seconds / 3600)) end
    local days = math.floor(seconds / 86400)
    if days == 1 then return "yesterday" end
    if days < 7 then return ("%d days ago"):format(days) end
    return date("%d %b %Y", when)
end

local function RecentEnter(row)
    local muted = T.muted
    row.hover:Show()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local kill, item = row.kill, row.item
    if kill then
        GameTooltip:SetText(kill.boss.name, 1, 1, 1)
        GameTooltip:AddDoubleLine(date(KILL_DATE, kill.at), kill.took and "took " .. FightLength(kill.took) or "",
            1, 1, 1, muted.r, muted.g, muted.b)
    else
        GameTooltip:SetHyperlink(item.link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(item.boss and "From " .. item.boss or "Looted", date(KILL_DATE, item.at),
            1, 1, 1, muted.r, muted.g, muted.b)
    end
    GameTooltip:AddLine(row.dungeon.name, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:AddLine(OPEN_HINT, muted.r, muted.g, muted.b)
    GameTooltip:Show()
end

local function RecentLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function RecentClick(row)
    OpenAt(row.dungeon)
end

local function RecentRow(column, index)
    local row = CreateFrame("Button", nil, column)
    row:SetHeight(RECENT_ROW)
    row:SetPoint("TOPLEFT", RECENT_INSET, -(RECENT_HEAD + (index - 1) * RECENT_ROW))
    row:SetPoint("RIGHT", -RECENT_INSET, 0)
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.05)
    row.hover:SetPoint("TOPLEFT", -RECENT_INSET / 2, 0)
    row.hover:SetPoint("BOTTOMRIGHT", RECENT_INSET / 2, 0)
    row.hover:Hide()
    row.skull = row:CreateTexture(nil, "ARTWORK")
    row.skull:SetTexture(SKULL)
    row.skull:SetSize(RECENT_ICON, RECENT_ICON)
    row.skull:SetPoint("LEFT")
    row.skull:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    -- An item's icon, in the house's black edge.
    row.icon = CreateFrame("Frame", nil, row)
    row.icon:SetSize(RECENT_ICON, RECENT_ICON)
    row.icon:SetPoint("LEFT")
    row.icon.texture = row.icon:CreateTexture(nil, "ARTWORK")
    row.icon.texture:SetAllPoints()
    ns.Border(row.icon, BORDER_RGB)
    row.ago = ns.Font(row, 12, nil, T.muted)
    row.ago:SetPoint("RIGHT")
    row.ago:SetWidth(AGO_W)
    row.ago:SetJustifyH("RIGHT")
    row.where = ns.Font(row, 12, nil, T.muted)
    row.where:SetPoint("RIGHT", row.ago, "LEFT", -COLUMN_GAP, 0)
    row.where:SetWidth(WHERE_W)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)
    row.name = ns.Font(row, 13, nil, T.fg)
    row.name:SetPoint("LEFT", RECENT_ICON + RECENT_GAP, 0)
    row.name:SetPoint("RIGHT", row.where, "LEFT", -COLUMN_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", RecentEnter)
    row:SetScript("OnLeave", RecentLeave)
    row:SetScript("OnClick", RecentClick)
    return row
end

-- Forgets a column's list, once you say yes: the page and the Journal's window show it gone.
local function Forget(question, forget)
    ns.Confirm(question, function()
        forget()
        ns.UI:RefreshPage(true)
        ns.RedrawJournalWindow()
    end)
end

local function ForgetKills()
    Forget("Forget this character's kills? Every boss's kill count starts again from 0.", Kills.Forget)
end

local function ForgetLoot()
    Forget("Forget what this character has looted? This list and the item on each boss start again.",
        Looted.Forget)
end

local function RecentColumn(block, title, empty, reset)
    local column = CreateFrame("Frame", nil, block)
    column.reset = ns.Button(column, "Reset", RESET_W, RESET_H, reset)
    column.reset:SetPoint("TOPRIGHT", -RECENT_INSET, -RESET_TOP)
    -- The title in the button's height, so the two are level.
    column.title = ns.Font(column, 12, nil, T.muted)
    column.title:SetPoint("LEFT", RECENT_INSET, 0)
    column.title:SetPoint("TOP", column.reset, "TOP")
    column.title:SetPoint("BOTTOM", column.reset, "BOTTOM")
    column.title:SetText(title)
    column.rows = {}
    for i = 1, RECENT_ROWS do column.rows[i] = RecentRow(column, i) end
    -- Where the first row would be, while there is none.
    column.empty = ns.Font(column, 12, nil, T.muted)
    column.empty:SetPoint("LEFT", column.rows[1], "LEFT")
    column.empty:SetPoint("RIGHT", column.rows[1], "RIGHT")
    column.empty:SetJustifyH("LEFT")
    column.empty:SetText(empty)
    return column
end

local function MakeRecent(parent)
    local block = CreateFrame("Frame", nil, parent)
    block.kills = RecentColumn(block, "Kills", "No kills counted yet. They count while the Journal is on.",
        ForgetKills)
    block.kills:SetPoint("TOPLEFT")
    block.kills:SetPoint("BOTTOMRIGHT", block, "BOTTOM")
    block.loot = RecentColumn(block, "Loot", "Nothing looted yet. Loot counts in its dungeons and raids.",
        ForgetLoot)
    block.loot:SetPoint("TOPLEFT", block, "TOP")
    block.loot:SetPoint("BOTTOMRIGHT")
    local divider = ns.Solid(block, "ARTWORK", T.line, 0.6)
    divider:SetPoint("TOP", 0, -RECENT_INSET / 2)
    divider:SetPoint("BOTTOM", 0, RECENT_FOOT)
    divider:SetWidth(1)
    return block
end

local function ShowKill(row, kill)
    row.kill, row.item, row.dungeon = kill, nil, kill.dungeon
    row.skull:Show()
    row.icon:Hide()
    row.name:SetText(kill.boss.name)
    row.where:SetText(kill.dungeon.name)
    row.ago:SetText(Ago(kill.at))
    row:Show()
end

local function ShowItem(row, item)
    local dungeon = J.Get(item.dungeon)
    row.kill, row.item, row.dungeon = nil, item, dungeon
    row.skull:Hide()
    row.icon:Show()
    row.icon.texture:SetTexture(C_Item.GetItemIconByID(item.id))
    -- The link's name in its quality's colour, without the brackets chat puts round it.
    row.name:SetText((item.link:gsub("|h%[(.-)%]|h", "|h%1|h")))
    row.where:SetText(dungeon.name)
    row.ago:SetText(Ago(item.at))
    row:Show()
end

-- Fills both columns; returns how many rows the taller one has (at least one, for the line
-- that says there is nothing yet).
local function FillRecent(block)
    local kills = Kills.Latest(RECENT_ROWS, latestKills)
    local rows = block.kills.rows
    for i = 1, RECENT_ROWS do
        if kills[i] then ShowKill(rows[i], kills[i]) else rows[i]:Hide() end
    end
    block.kills.empty:SetShown(#kills == 0)
    block.kills.reset:SetShown(#kills > 0)

    local items = Looted.Latest(RECENT_ROWS, latestLoot)
    rows = block.loot.rows
    for i = 1, RECENT_ROWS do
        if items[i] then ShowItem(rows[i], items[i]) else rows[i]:Hide() end
    end
    block.loot.empty:SetShown(#items == 0)
    block.loot.reset:SetShown(#items > 0)
    return math.max(#kills, #items, 1)
end

local function Recent(parent, y)
    local UI = ns.UI
    local _, h = UI.Widgets:SectionHeader(parent, "RECENT" .. UI.STATUS.untested, y); y = y - h
    if UI.searchScan then return y end
    local block = UI.Keep(parent, "journalRecent", MakeRecent)
    local height = RECENT_HEAD + FillRecent(block) * RECENT_ROW + RECENT_FOOT
    block:SetHeight(height)
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    block:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y)
    return y - height
end

-------------------------------------------------------------------------------
--  The switches
-------------------------------------------------------------------------------
local function BisOff()
    return not Loot.BisOn()
end

-- One of J.OPTION_GROUPS as a settings row: the same words as the Filters menu.
local function OptionRow(option)
    if not option then return nil end
    if not option.needsBis then return S.Toggle(option.key, option.label, option.tooltip) end
    local row = S.Toggle(option.key, option.label, option.tooltip .. " " .. J.NEEDS_BIS)
    row.disabled = BisOff
    return row
end

local function OpacityGet()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

local function OpacitySet(value)
    S.Set("windowAlpha", value / 100)
end

-- Which side's dungeons are listed: the faction switch beside the window's search, as a
-- dropdown. Both settings are kept, so the switch and this always agree; the one turned on
-- is set first, so the list is never left with neither.
local FACTION_VALUES = { both = "Both Factions", Alliance = "Alliance Ground", Horde = "Horde Ground" }
local FACTION_ORDER = { "both", "Alliance", "Horde" }

local function FactionGet()
    local alliance, horde = S.Get("showAlliance"), S.Get("showHorde")
    if alliance and horde then return "both" end
    return alliance and "Alliance" or "Horde"
end

local function FactionSet(value)
    if value == "Horde" then
        S.Set("showHorde", true); S.Set("showAlliance", false)
    else
        S.Set("showAlliance", true); S.Set("showHorde", value ~= "Alliance")
    end
end

local FACTION_ROW = {
    type = "dropdown", text = "Dungeons Listed", values = FACTION_VALUES, order = FACTION_ORDER,
    tooltip = "The dungeons on whose ground the list shows. Contested ones and the raids are "
        .. "always listed. Also the switch beside the Journal's search.",
    getValue = FactionGet, setValue = FactionSet,
}

local OPACITY_ROW = {
    type = "slider", text = "Window Opacity", min = OPACITY_MIN, max = 100, step = 5,
    tooltip = "How solid the Journal's window is, in percent. Also on its title bar.",
    getValue = OpacityGet, setValue = OpacitySet,
}

local SHARE_TIP = "Click the group icon on a dungeon quest you do not have: the members on it are "
    .. "asked one at a time, and the first running Naowh Forever shares it (with the whole group, "
    .. "as the game shares quests). You and they are told in chat; they can ask you the same way. "
    .. "Off, you neither ask nor answer."

local KEY_ROW = {
    type = "label", text = "Boss Loot at Cursor",
    tooltip = "Hover a boss, or target one, and press this key: what it drops, at your cursor. "
        .. "Press it again to close it.",
}

function ns.BuildJournalSettingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h, row
    y = Card(parent, y)

    for g, group in ipairs(J.OPTION_GROUPS) do
        _, h = W:SectionHeader(parent, group.title:upper() .. UI.STATUS.untested, y); y = y - h
        local options = group.options
        for i = 1, #options, 2 do
            -- What it lists ends on a lone switch: the faction dropdown sits beside it.
            local right = OptionRow(options[i + 1]) or (g == 1 and FACTION_ROW) or nil
            _, h = W:DualRow(parent, y, OptionRow(options[i]), right); y = y - h
        end
    end

    _, h = W:SectionHeader(parent, "WHERE IT SHOWS" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("mapPanel", "Beside the World Map",
            "Inside a dungeon, opening the world map (M) shows its bosses and loot beside it.",
            "enabled"),
        OPACITY_ROW
    ); y = y - h
    row, h = W:DualRow(parent, y, KEY_ROW,
        S.Toggle("shareRequests", "Quest Share Requests", SHARE_TIP, "enabled")); y = y - h
    if row then   -- nil while the settings search scans this page
        UI.KeyField(row._leftRegion, "NAOWHFOREVER_BOSSLOOT", KEY_ROW.text)
    end
    return Recent(parent, y)
end

-- A switch changed somewhere else (the window's Filters menu, its opacity): the page shows
-- the same settings, so it is drawn again if it is open. RefreshPage does nothing while the
-- options window is shut, and runs once per frame however many change.
S.OnChange(function()
    ns.UI:RefreshPage(true)
end)
