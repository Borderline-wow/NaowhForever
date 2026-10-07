-------------------------------------------------------------------------------
--  UI/Recent.lua -- Recent in the Journal's window (J.Recent): a skull on its title bar opens a
--  panel under it with this character's latest kills and its latest loot in the Journal's
--  dungeons and raids, side by side, each list with its Reset. A click on one shows its dungeon.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Kills = J.Kills
local Looted = J.Looted
local Parts = J.View.Parts

local St = J.Style
local BORDER_RGB, SKULL, KILL_DATE = St.BORDER_RGB, St.SKULL, St.KILL_DATE

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
local PANEL_W, PANEL_PAD, PANEL_DROP = 820, 8, 6

local Recent = {}
J.Recent = Recent

local latestKills, latestLoot = {}, {}   -- Kills.Latest's and Looted.Latest's lists, reused
local FightLength = Parts.FightLength
local OPEN_HINT = "Click to show the dungeon."
local panel, button, show

local Ago = ns.Shared.Ago

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
    panel:Hide()
    show(row.dungeon)
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
    row.itemIcon = CreateFrame("Frame", nil, row)
    row.itemIcon:SetSize(RECENT_ICON, RECENT_ICON)
    row.itemIcon:SetPoint("LEFT")
    row.itemIcon.texture = row.itemIcon:CreateTexture(nil, "ARTWORK")
    row.itemIcon.texture:SetAllPoints()
    ns.Border(row.itemIcon, BORDER_RGB)
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

local Fill

-- Forgets a column's list, once you say yes: the panel and the page show it gone.
local function Forget(question, forget)
    ns.Confirm(question, function()
        forget()
        if panel and panel:IsShown() then Fill() end
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
    ns.Hairline(divider, "v")
    return block
end

local function ShowKill(row, kill)
    row.kill, row.item, row.dungeon = kill, nil, kill.dungeon
    row.skull:Show()
    row.itemIcon:Hide()
    row.name:SetText(kill.boss.name)
    row.where:SetText(kill.dungeon.name)
    row.ago:SetText(Ago(kill.at))
    row:Show()
end

local function ShowItem(row, item)
    local dungeon = J.Get(item.dungeon)
    row.kill, row.item, row.dungeon = nil, item, dungeon
    row.skull:Hide()
    row.itemIcon:Show()
    row.itemIcon.texture:SetTexture(C_Item.GetItemIconByID(item.id))
    -- The link's name in its quality's colour, without the brackets chat puts round it.
    row.name:SetText((item.link:gsub("|h%[(.-)%]|h", "|h%1|h")))
    row.where:SetText(dungeon.name)
    row.ago:SetText(Ago(item.at))
    row:Show()
end

-- Fills both columns and sizes the panel to the taller one (at least one row, for the line
-- that says there is nothing yet).
function Fill()
    local block = panel.block
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
    local shown = math.max(#kills, #items, 1)
    panel:SetHeight(RECENT_HEAD + shown * RECENT_ROW + RECENT_FOOT + PANEL_PAD * 2)
end

local function MouseDown()
    if not (panel:IsMouseOver() or button:IsMouseOver()) then panel:Hide() end
end

local function PanelShown(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end

local function PanelHidden(self)
    self:UnregisterAllEvents()
    self:Hide()
end

local function Build(window)
    panel = CreateFrame("Frame", nil, window)
    panel:SetWidth(PANEL_W)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -PANEL_DROP)
    ns.Solid(panel, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(panel, BORDER_RGB)
    panel.block = MakeRecent(panel)
    panel.block:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
    panel.block:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_PAD)
    panel:SetScript("OnShow", PanelShown)
    panel:SetScript("OnHide", PanelHidden)
    panel:SetScript("OnEvent", MouseDown)
    panel:Hide()
end

local function Clicked(self)
    if not panel then Build(self:GetParent()) end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    GameTooltip:Hide()
    panel:Show()
    Fill()
end

local function Enter(self)
    Parts.LightBarIcon(self, true)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Recent", 1, 1, 1)
    GameTooltip:AddLine("This character's latest kills and loot.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

--- The title bar's Recent icon; onPick(dungeon) shows a dungeon in the window. Place it.
function Recent.Button(window, onPick)
    show = onPick
    button = Parts.BarIcon(window, SKULL, true)
    button:SetScript("OnClick", Clicked)
    button:SetScript("OnEnter", Enter)
    return button
end
