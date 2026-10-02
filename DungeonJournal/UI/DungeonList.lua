-------------------------------------------------------------------------------
--  UI/DungeonList.lua -- the dungeon list down the left of the Journal's window
--  (ns.Journal.DungeonList): every dungeon, grouped by how it sits with your level (for your
--  level, coming up, behind you), each group opening and closing on a click on its title;
--  the one shown marked, the one you are in dotted, NEW before the ones new in Forever, your
--  BiS there counted, and a card on hover. Dungeons of a faction the window's switch hides
--  are left out. Made by the window the first time it opens.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Loot = J.Loot
local Quests = J.Quests
local S = J.Settings

local St = J.Style
local BIS_RGB, BIS_CODE, LOOK_CODE, TERRITORY_CODE = St.BIS_RGB, St.BIS_CODE, St.LOOK_CODE, St.TERRITORY_CODE
local LIST_W, LIST_ROW, GROUP_H, UNUSABLE, STRIPE = St.LIST_W, St.LIST_ROW, St.GROUP_H, St.UNUSABLE, St.STRIPE
local NAME_SIZE, COUNT_SIZE, NEW_TAG_SIZE = St.LIST_NAME_SIZE, St.LIST_COUNT_SIZE, St.NEW_TAG_SIZE
local BAR, BAR_GAP = St.LIST_BAR, St.LIST_BAR_GAP
local PEOPLE = St.PEOPLE
local SIZE_ICON, SIZE_GAP = 12, 3   -- the group icon before a raid's size, and its gap
local TERRITORY_ICON, TERRITORY_GAP, FACTION_ATLAS, CONTESTED = St.TERRITORY_ICON, St.TERRITORY_GAP,
    St.FACTION_ATLAS, St.CONTESTED

-- Your BiS there: the orange star before the count, at the text's height.
local STAR_TAG = ("|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(St.STAR, BIS_RGB.r * 255,
    BIS_RGB.g * 255, BIS_RGB.b * 255)
-- All of it had: a green check, as the page's header has.
local DONE = ("|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(St.CHECK, St.HAVE_RGB.r * 255,
    St.HAVE_RGB.g * 255, St.HAVE_RGB.b * 255)

-- A row, left to right: the accent bar (the one shown), the dot (the one you are in), NEW in
-- its own column so every name starts at NAME_LEFT, the name; then on the right your BiS
-- count, the levels and whose ground it is on.
local ROW_W = LIST_W - BAR - BAR_GAP - 2   -- the list's width less its scrollbar
local SELECTED_BAR = 3
local HERE_DOT, HERE_LEFT = 5, 6
local NEW_LEFT = 14
local NAME_LEFT = 40
local NAME_GAP, BIS_GAP, ICON_RIGHT = 8, 8, 8
-- The levels' digits sit under the middle of their font string (the Naowh font leaves room
-- above its capitals): the territory icon goes this much under it, level with them.
local ICON_DROP = 1
-- Contested ground's swords in the contested gold, as its name is coloured in the tooltip.
local CONTESTED_RGB = { r = 0xe6 / 255, g = 0xcc / 255, b = 0x80 / 255 }

local List = {}
J.DungeonList = List

-- The groups, in order: the dungeons for your level, those still ahead of you, the raids,
-- and the dungeons you have outgrown. Each stays open or closed as you left it; the setting
-- names keep the order they were made in (closedGroup3 is Behind you, 4 the raids).
local GROUPS = { "For your level", "Coming up", "Raids", "Behind you" }
local CLOSED_KEYS = { "closedGroup1", "closedGroup2", "closedGroup4", "closedGroup3" }
local FOR_YOUR_LEVEL, COMING_UP, RAIDS, BEHIND_YOU = 1, 2, 3, 4
local GROUP_GAP = 4

local rows, groups = {}, {}
local onSelect           -- the window's: shows the dungeon clicked
local filters = {}       -- read when a count is shown (JournalFilters)
local scroll, content    -- the list scrolls once it runs past the window

-- Which group a dungeon is in, for your level now.
local function Group(dungeon)
    if dungeon.raid then return RAIDS end
    local levels = J.Levels(dungeon)
    local level = UnitLevel("player")
    if not levels or level < levels[1] then return COMING_UP end
    if level > levels[2] then return BEHIND_YOU end
    return FOR_YOUR_LEVEL
end

local function Closed(g)
    return S.Get(CLOSED_KEYS[g]) == true
end

-- "13-18" left of the territory icon, lined up to the pixel (Parts.Cells); returns the
-- leftmost cell, for the BiS count to follow.
local function LevelCells(row, text, icon)
    local cells = J.View.Parts.Cells(row, COUNT_SIZE, T.muted, #text)
    cells[1]:SetPoint("RIGHT", icon, "LEFT", -TERRITORY_GAP, ICON_DROP)
    return cells:SetText(text)
end

-------------------------------------------------------------------------------
--  A dungeon's row and its card
-------------------------------------------------------------------------------
-- Where it is and whose ground, the levels, your quests there, what it holds for you, or
-- that there is no boss data for it yet.
local function RowEnter(row)
    local dungeon = row.dungeon
    if not row.selected then row.band:SetAlpha(0.05) end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(dungeon.name)
    if dungeon.new then GameTooltip:AddLine("New in WoW Forever", T.accent.r, T.accent.g, T.accent.b) end
    if dungeon.zone then
        local territory = dungeon.territory or "Contested"
        GameTooltip:AddLine(dungeon.zone .. "  " .. TERRITORY_CODE[territory] .. territory .. "|r", 1, 1, 1)
    end
    if dungeon.raid then
        GameTooltip:AddLine(("A raid for %d players"):format(dungeon.raid), 1, 1, 1)
    else
        local range = J.LevelRange(dungeon)
        if range then GameTooltip:AddLine("Level " .. range, 1, 1, 1) end
    end
    if not J.HasBosses(dungeon) then
        GameTooltip:AddLine("No boss data for it yet.", T.muted.r, T.muted.g, T.muted.b, true)
    else
        if dungeon.quests then
            local toPickUp, inLog = Quests.Count(dungeon.quests)
            if toPickUp > 0 then
                GameTooltip:AddLine(("%d |4quest:quests; to pick up"):format(toPickUp), 1, 1, 1)
            end
            if inLog > 0 then GameTooltip:AddLine(("%d in your log"):format(inLog), 1, 1, 1) end
        end
        Loot.ReadFilters(filters)
        local bis, haveBis = Loot.DungeonBis(dungeon, filters)
        if bis > 0 then
            GameTooltip:AddLine(("%s%d of your %d BiS here are yours|r"):format(BIS_CODE, haveBis, bis))
        end
        if filters.showAppearance then
            local looks = Loot.DungeonNewLooks(dungeon, filters)
            if looks > 0 then GameTooltip:AddLine(("%s%d new |4look:looks;|r"):format(LOOK_CODE, looks)) end
        end
    end
    GameTooltip:Show()
end

-- Whose ground it is on, at the row's right edge: the faction's crest, or crossed swords in
-- gold for contested ground.
local function TerritoryIcon(row, territory)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TERRITORY_ICON, TERRITORY_ICON)
    icon:SetPoint("RIGHT", -ICON_RIGHT, -ICON_DROP)
    if FACTION_ATLAS[territory] then
        icon:SetAtlas(FACTION_ATLAS[territory])
    else
        icon:SetTexture(CONTESTED)
        icon:SetVertexColor(CONTESTED_RGB.r, CONTESTED_RGB.g, CONTESTED_RGB.b)
    end
    return icon
end

local function RowLeave(row)
    if not row.selected then row.band:SetAlpha(0) end
    GameTooltip:Hide()
end

local function RowClicked(row)
    onSelect(row.dungeon)
end

local function Row(parent, dungeon)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_W, LIST_ROW)
    row.dungeon = dungeon
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
    row.stripe:SetAllPoints()
    row.band = ns.Solid(row, "BACKGROUND", T.fg, 1)
    row.band:SetAllPoints()
    row.band:SetAlpha(0)
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(SELECTED_BAR)
    row.here = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.here:SetSize(HERE_DOT, HERE_DOT)
    row.here:SetPoint("LEFT", HERE_LEFT, 0)

    row.territory = TerritoryIcon(row, dungeon.territory or "Contested")
    -- A dungeon's levels; a raid's size instead, after the group icon (raids are all level 60).
    local range = dungeon.raid and tostring(dungeon.raid) or J.LevelRange(dungeon)
    local leftmost = range and LevelCells(row, range, row.territory)
    if dungeon.raid and leftmost then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(PEOPLE)
        icon:SetSize(SIZE_ICON, SIZE_ICON)
        icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
        icon:SetPoint("RIGHT", leftmost, "LEFT", -SIZE_GAP, -ICON_DROP)
        leftmost = icon
    end
    row.bis = ns.Font(row, COUNT_SIZE, nil, BIS_RGB)
    if leftmost then
        row.bis:SetPoint("RIGHT", leftmost, "LEFT", -BIS_GAP, 0)
    else
        row.bis:SetPoint("RIGHT", row.territory, "LEFT", -BIS_GAP, ICON_DROP)
    end
    row.name = ns.Font(row, NAME_SIZE)
    row.name:SetPoint("LEFT", NAME_LEFT, 0)
    row.name:SetPoint("RIGHT", row.bis, "LEFT", -NAME_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetText(dungeon.name)
    -- NEW in the accent, small, in its column before the name and on the name's baseline
    -- (the bottoms of the two lines, so their letters stand on one line).
    if dungeon.new then
        row.new = ns.Font(row, NEW_TAG_SIZE, nil, T.accent)
        row.new:SetText("NEW")
        row.new:SetPoint("BOTTOMLEFT", row.name, "BOTTOMLEFT", NEW_LEFT - NAME_LEFT, 0)
    end
    row:SetScript("OnClick", RowClicked)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

-------------------------------------------------------------------------------
--  A group's title: the chevron (down while open, right while closed), its name, and while
--  closed how many dungeons are in it. A click anywhere on it opens or closes it.
-------------------------------------------------------------------------------
local function GroupColor(header, color)
    header.label:SetTextColor(color.r, color.g, color.b)
    header.arrow:SetVertexColor(color.r, color.g, color.b)
end

local function GroupClicked(header)
    S.Set(CLOSED_KEYS[header.group], not Closed(header.group))
end

local function GroupEnter(header) GroupColor(header, T.fg) end
local function GroupLeave(header) GroupColor(header, T.accentSoft) end

local function GroupHeader(parent, text, g)
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(ROW_W, GROUP_H)
    header.group = g
    header.arrow = J.View.Parts.Arrow(header, 10, T.accentSoft)
    header.arrow:SetPoint("BOTTOMLEFT", 3, 5)
    header.label = ns.Font(header, 10, nil, T.accentSoft)
    header.label:SetPoint("BOTTOMLEFT", 16, 4)
    header.label:SetText(text:upper())
    header.count = ns.Font(header, 10, nil, T.muted)
    header.count:SetPoint("LEFT", header.label, "RIGHT", 8, 0)
    local line = ns.Solid(header, "ARTWORK", T.line, 1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    header:SetScript("OnClick", GroupClicked)
    header:SetScript("OnEnter", GroupEnter)
    header:SetScript("OnLeave", GroupLeave)
    return header
end

-------------------------------------------------------------------------------
--  The list
-------------------------------------------------------------------------------
-- Makes the list in parent, in a frame that scrolls once it runs past the window (a closed
-- group makes room); the bar hides while it all fits. select(dungeon) is called when a
-- dungeon is clicked.
---@param parent Frame
---@param select fun(dungeon: JournalDungeon)
function List.Build(parent, select)
    onSelect = select
    scroll = ns.UI.SlimScroll(parent, BAR, BAR_GAP)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMLEFT")
    scroll:SetWidth(ROW_W)
    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(ROW_W)
    scroll:SetScrollChild(content)
    for g, text in ipairs(GROUPS) do groups[g] = GroupHeader(content, text, g) end
    for i, dungeon in ipairs(J.Dungeons()) do rows[i] = Row(content, dungeon) end
end

-- Scrolls just enough to show the row: Up and Down step through dungeons past the edge.
local function ShowRow(row)
    if not (row.top and row:IsShown()) then return end
    local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
    if row.top < offset then
        scroll.bar:SetValue(row.top)
    elseif row.top + LIST_ROW > offset + height then
        scroll.bar:SetValue(row.top + LIST_ROW - height)
    end
end

-- Lays the rows out under their group titles; a group with no dungeon listed is left out,
-- and a closed one shows only its title, with how many dungeons it holds.
function List.Layout()
    local y = 0
    for g, header in ipairs(groups) do
        local count, closed = 0, Closed(g)
        for _, row in ipairs(rows) do
            local listed = Group(row.dungeon) == g and J.FactionShown(row.dungeon)
            if listed then
                if count == 0 then
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", 0, -y)
                    y = y + GROUP_H
                end
                count = count + 1
            end
            if Group(row.dungeon) == g then
                row:SetShown(listed and not closed)
                if listed and not closed then
                    -- Striped every other row within its group, so each group starts plain.
                    row.stripe:SetShown(count % 2 == 0)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    row.top = y
                    y = y + LIST_ROW
                end
            end
        end
        header:SetShown(count > 0)
        header.arrow:SetRotation(closed and 0 or -math.pi / 2)
        header.count:SetText(closed and count or "")
        if count > 0 then y = y + GROUP_GAP end
    end
    content:SetHeight(math.max(1, y))
end

-- Whether you are done with the dungeon: every count it has (its quests, your BiS, and with
-- Appearances its looks) complete, and at least one to count.
local function Finished(dungeon, bis, haveBis)
    local any = false
    local done, total = Quests.Progress(dungeon.quests)
    if total > 0 then
        if done < total then return false end
        any = true
    end
    if bis > 0 then
        if haveBis < bis then return false end
        any = true
    end
    if filters.showAppearance then
        local new, looks = Loot.DungeonNewLooks(dungeon, filters)
        if new > 0 then return false end
        any = any or looks > 0
    end
    return any
end

-- The one shown: the accent bar and a lighter band. For your level: white, the rest muted.
-- The one you are in: a dot before its name. The BiS there you still miss, in orange, so the
-- list says where your gear is, and a check once you have them all; a check after its name
-- once you are done with it. Each text changes only when what it says does.
---@param selected? JournalDungeon
function List.Paint(selected)
    local here = J.Current()
    local current = here and here[1]
    Loot.ReadFilters(filters)
    for _, row in ipairs(rows) do
        local dungeon = row.dungeon
        local chosen = dungeon == selected
        row.selected = chosen
        row.bar:SetShown(chosen)
        if chosen then ShowRow(row) end
        row.band:SetAlpha(chosen and 0.10 or 0)
        local color = (chosen or Group(dungeon) == FOR_YOUR_LEVEL) and T.fg or T.muted
        row.name:SetTextColor(color.r, color.g, color.b)
        row:SetAlpha((J.HasBosses(dungeon) or chosen) and 1 or UNUSABLE)
        row.here:SetShown(dungeon == current)
        local bis, haveBis = Loot.DungeonBis(dungeon, filters)
        -- None here: nothing; all yours: the check; else how many you still miss.
        local missing = bis > 0 and bis - haveBis or -1
        if missing ~= row.missing then
            row.missing = missing
            row.bis:SetText(missing < 0 and "" or STAR_TAG .. (missing == 0 and DONE or missing))
        end
        local finished = Finished(dungeon, bis, haveBis)
        if finished ~= row.finished then
            row.finished = finished
            row.name:SetText(finished and dungeon.name .. "  " .. DONE or dungeon.name)
        end
    end
end

-- The dungeon above (by -1) or below (1) the one shown, in level order, wrapping round,
-- past those of a faction the switch hides.
---@param from JournalDungeon
---@param by -1|1
---@return JournalDungeon
function List.Next(from, by)
    local dungeons = J.Dungeons()
    local n = #dungeons
    for i, dungeon in ipairs(dungeons) do
        if dungeon == from then
            for step = 1, n do
                local after = dungeons[(i - 1 + by * step) % n + 1]
                if J.FactionShown(after) then return after end
            end
            return from
        end
    end
    return dungeons[1]
end
