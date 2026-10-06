-------------------------------------------------------------------------------
--  View/BossPanel.lua -- a boss's history on this character, opened from the skull or the
--  loot bag on its card: one timeline, newest first. Each kill with when and how long it
--  took, who was with you, and what dropped: each item with who won it and everyone's rolls,
--  and anything you picked up without a roll. Loot that no counted kill came before (a boss the game does not report,
--  a kill from before the Journal counted) stands in the timeline on its own. Your group is
--  listed as it stood: tanks, healers, then damage, you first in your role, each in their
--  class colour. In a side panel beside the window (Parts.SidePanel). Made the first time it
--  is opened.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Kills, Looted, Team = J.Kills, J.Looted, J.Team

local St = J.Style
local SECTION_SPACE, KILL_DATE, ROLE_ATLAS = St.SECTION_SPACE, St.KILL_DATE, St.ROLE_ATLAS
local BADGE, BORDER_RGB, CARD_PAD, CARD_GAP = St.BADGE, St.BORDER_RGB, St.CARD_PAD, St.CARD_GAP
local BAG, CHECK, HAVE_RGB, ICON, GOLD_CODE = St.BAG, St.CHECK, St.HAVE_RGB, St.ICON, St.GOLD_CODE
local STRIPE = St.STRIPE

local View = J.View
local Parts, Kinds = View.Parts, View.Kinds
local FightLength = Parts.FightLength

local BossPanel = {}
View.BossPanel = BossPanel

-- A kill's card: its header (a badge with which kill it was, when, how long it took), then
-- GROUP and LOOT, each a small label over its rows.
local HEAD_H = 34          -- the header, from the card's top
local HEAD_ICON = 14       -- the loot bag in the badge of loot with no kill
local LABEL_H = 22         -- GROUP and LOOT
local TEAM_LINE = 18       -- a line of the group
local TEAM_PAD = 4         -- under the group
local MEMBER_GAP = 14      -- between two members on a line
local ROLE_GAP = 4         -- a role's icon to the name
-- The name's letters sit under the middle of their font string (the Naowh font leaves room
-- above its capitals): the role icon goes this much under it, level with them, as the
-- skull does by its count.
local ROLE_DROP = 1
local ROLE_ICON = 14
local ROLLS_GAP = 8        -- the item's icon to its rolls, as to its name
local ROLLS_PAD = 6        -- under an item's rolls
local GRID_LINE = 18       -- a line of the rolls' grid
local GRID_INSET = 6       -- a line's band to the text in it, on the left
local GRID_GAP = 16        -- between its two columns
local CELL_GAP = 6         -- a roller's name to their roll
local ROLL_ICON = 14       -- what they rolled, as the game's loot history shows it
local ROLL_GAP = 4         -- the roll's icon to its number, and the check to the icon
local CHECK_ICON = 12      -- the winner's check
local LOOT_WINDOW = 15 * 60   -- seconds after a kill its loot is counted as its own

-- Enum.EncounterLootDropRollState as the game's loot history shows it: its own icons for
-- Need (main or off spec), Transmog, Greed and Pass; none for no roll.
local ROLL_ATLAS = { [0] = "lootroll-icon-need", [1] = "lootroll-icon-need", [2] = "lootroll-icon-transmog",
    [3] = "lootroll-icon-greed", [5] = "lootroll-icon-pass" }
local YOU = ns.Color("muted", " (you)")

local panel, view
local shown = {}   -- the boss shown, and its dungeon when the card knew it

-------------------------------------------------------------------------------
--  Row kinds: a kill's header, a label, a member of your group, and an item's rolls
-------------------------------------------------------------------------------
-- A badge as a boss card's: the kill's number (the 3rd kill), or a loot bag for loot with
-- no kill; when, in the text colour; and how long it took on the right.
Kinds.historyHead = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.badge = CreateFrame("Frame", nil, row)
        row.badge:SetSize(BADGE, BADGE)
        row.badge:SetPoint("LEFT")
        ns.Solid(row.badge, "BACKGROUND", T.bg, 0.8):SetAllPoints()
        ns.Border(row.badge, BORDER_RGB)
        row.number = ns.Font(row.badge, 11, nil, T.fg)
        row.number:SetPoint("CENTER")
        row.bag = row.badge:CreateTexture(nil, "ARTWORK")
        row.bag:SetTexture(BAG)
        row.bag:SetSize(HEAD_ICON, HEAD_ICON)
        row.bag:SetPoint("CENTER")
        row.bag:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
        row.right = ns.Font(row, 11, nil, T.muted)
        row.right:SetPoint("RIGHT")
        row.left = ns.Font(row, 13, nil, T.fg)
        row.left:SetPoint("LEFT", row.badge, "RIGHT", 8, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        return row
    end,
    ---@param number? number which kill it was; nil for loot with no kill
    ---@param left string
    ---@param right? string
    Set = function(row, number, left, right)
        row.number:SetText(number or "")
        row.bag:SetShown(number == nil)
        row.left:SetText(left)
        row.right:SetText(right or "")
        return HEAD_H
    end,
}

-- GROUP or LOOT: small, muted and in capitals over what follows, with a count after it.
Kinds.label = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = ns.Font(row, 10, nil, T.muted)
        row.text:SetPoint("BOTTOMLEFT", 0, 6)
        return row
    end,
    Set = function(row, text, count)
        row.text:SetText(text:upper() .. (count and "  " .. count or ""))
        return LABEL_H
    end,
}

-- A class's colour for a name: the game's, else the text colour.
local function ClassColor(class)
    return class and C_ClassColor.GetClassColor(class) or T.fg
end

-- Your group in the order it stands, side by side: each member's role icon and name in their
-- class colour, you marked. Each member is placed whole, the icon with its name, and the next
-- line starts when one does not fit (a big group); the game's own wrapping could part them.
local function NewMember(row)
    local member = {}
    member.name = ns.Font(row, 12)
    member.role = row:CreateTexture(nil, "ARTWORK")
    member.role:SetSize(ROLE_ICON, ROLE_ICON)
    member.role:SetPoint("RIGHT", member.name, "LEFT", -ROLE_GAP, -ROLE_DROP)
    row.members[#row.members + 1] = member
    return member
end

Kinds.team = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.members = {}
        return row
    end,
    ---@param members JournalMember[]
    Set = function(row, members)
        local width, x, y = row:GetWidth(), 0, 0
        for i, member in ipairs(members) do
            local placed = row.members[i] or NewMember(row)
            local atlas = ROLE_ATLAS[member.role]
            placed.role:SetShown(atlas ~= nil)
            if atlas then placed.role:SetAtlas(atlas) end
            local color = ClassColor(member.class)
            placed.name:SetText(member.me and member.name .. YOU or member.name)
            placed.name:SetTextColor(color.r, color.g, color.b)
            placed.name:Show()
            local icon = atlas and ROLE_ICON + ROLE_GAP or 0
            local w = icon + math.ceil(placed.name:GetStringWidth())
            if x > 0 and x + w > width then x, y = 0, y + TEAM_LINE end
            placed.name:ClearAllPoints()
            placed.name:SetPoint("TOPLEFT", x + icon, -y)
            x = x + w + MEMBER_GAP
        end
        for i = #members + 1, #row.members do
            row.members[i].name:Hide()
            row.members[i].role:Hide()
        end
        return y + TEAM_LINE + TEAM_PAD
    end,
}

-- Under an item, in line with its name: everyone's roll in two columns, the best first as the
-- game lists them, each name in its class colour and its roll on the right of its cell; the
-- winner's in green after a check, and you marked. Every other line has a faint band, the
-- first one included, as the dungeon list's rows do; each line's text sits in the middle of
-- its band.
-- The faint band of a striped item's rows (view.striped), to the card's edges as the item
-- row's own.
local function Stripe(row)
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
    row.stripe:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
    row.stripe:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
end

local function Band(row, line)
    local band = row.bands[line]
    if not band then
        band = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
        band:SetHeight(GRID_LINE)
        row.bands[line] = band
    end
    return band
end

-- A cell, from the right: the number rolled (in cells, so they line up to the pixel), the
-- roll's icon, the winner's check, and the name.
local function NewCell(row)
    local cell = {}
    cell.number = Parts.Cells(row, 11, T.muted, 3)
    cell.icon = row:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ROLL_ICON, ROLL_ICON)
    cell.check = row:CreateTexture(nil, "ARTWORK")
    cell.check:SetTexture(CHECK)
    cell.check:SetSize(CHECK_ICON, CHECK_ICON)
    cell.check:SetVertexColor(HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b)
    cell.check:SetPoint("RIGHT", cell.icon, "LEFT", -ROLL_GAP, 0)
    cell.name = ns.Font(row, 11)
    cell.name:SetJustifyH("LEFT")
    cell.name:SetWordWrap(false)
    cell.name:SetPoint("RIGHT", cell.check, "LEFT", -CELL_GAP, 0)
    row.cells[#row.cells + 1] = cell
    return cell
end

Kinds.rollGrid = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.cells, row.bands = {}, {}
        Stripe(row)
        return row
    end,
    ---@param list JournalRoll[]
    ---@param isMe fun(name: string): boolean
    Set = function(row, list, isMe)
        row.stripe:SetShown(row:GetParent().striped)
        local left = ICON + ROLLS_GAP
        local column = (row:GetWidth() - left - GRID_INSET * 2 - GRID_GAP) / 2
        local lines = math.ceil(#list / 2)
        for line = 1, math.max(lines, #row.bands) do
            local band = Band(row, line)
            band:ClearAllPoints()
            band:SetPoint("TOPLEFT", left, -(line - 1) * GRID_LINE)
            band:SetPoint("TOPRIGHT", 0, -(line - 1) * GRID_LINE)
            band:SetShown(line <= lines and line % 2 == 1)
        end
        for i, roll in ipairs(list) do
            local cell = row.cells[i] or NewCell(row)
            local band = row.bands[math.ceil(i / 2)]
            local x = GRID_INSET + ((i - 1) % 2) * (column + GRID_GAP)
            local number = cell.number
            number[1]:ClearAllPoints()
            number[1]:SetPoint("RIGHT", band, "LEFT", x + column, 0)
            number:SetText(roll.roll or "")
            local result = roll.winner and HAVE_RGB or T.muted
            number:SetTextColor(result.r, result.g, result.b)
            -- The icon in a column of its own, three digits from the edge, so the icons line up.
            cell.icon:ClearAllPoints()
            cell.icon:SetPoint("RIGHT", band, "LEFT", x + column - number.widths.digit * 3 - ROLL_GAP, 0)
            local atlas = ROLL_ATLAS[roll.state]
            cell.icon:SetShown(atlas ~= nil)
            if atlas then cell.icon:SetAtlas(atlas) end
            cell.check:SetShown(roll.winner)
            cell.name:ClearAllPoints()
            cell.name:SetPoint("LEFT", band, "LEFT", x, 0)
            cell.name:SetPoint("RIGHT", cell.check, "LEFT", -CELL_GAP, 0)
            local color = ClassColor(roll.class)
            cell.name:SetText(isMe(roll.name) and roll.name .. YOU or roll.name)
            cell.name:SetTextColor(color.r, color.g, color.b)
            cell.name:Show()
        end
        for i = #list + 1, #row.cells do
            local cell = row.cells[i]
            cell.name:Hide()
            cell.icon:Hide()
            cell.check:Hide()
            cell.number:SetText("")
        end
        return lines * GRID_LINE + ROLLS_PAD
    end,
}

-- Under an item, in line with its name: a line about it, when no one rolled.
Kinds.rolls = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        Stripe(row)
        row.text = ns.Font(row, 11, nil, T.muted)
        row.text:SetPoint("TOPLEFT", ICON + ROLLS_GAP, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        return row
    end,
    Set = function(row, text)
        row.stripe:SetShown(row:GetParent().striped)
        row.text:SetWidth(row:GetWidth() - ICON - ROLLS_GAP)
        row.text:SetText(text)
        return math.ceil(row.text:GetStringHeight()) + ROLLS_PAD
    end,
}

-------------------------------------------------------------------------------
--  The timeline: each kill, with the loot that came after it
-------------------------------------------------------------------------------
---@class JournalHistoryEntry  One line of the timeline, built per draw.
---@field at number
---@field kill? number its place in the kill record's lists; nil for loot on its own
---@field items JournalLootRecord[] what was looted from it

local entries, spare = {}, {}   -- the timeline, and entries from the last draw, reused
local items = {}                -- every item kept from the boss, newest first

local function Entry(at, kill)
    local entry = table.remove(spare) or { items = {} }
    entry.at, entry.kill = at, kill
    wipe(entry.items)
    entries[#entries + 1] = entry
    return entry
end

local function Newer(a, b)
    return a.at > b.at
end

-- The kill an item was looted from: the latest one before it, within LOOT_WINDOW.
local function KillBefore(at)
    local best
    for _, entry in ipairs(entries) do
        if entry.kill and entry.at <= at and at - entry.at <= LOOT_WINDOW and (not best or entry.at > best.at) then
            best = entry
        end
    end
    return best
end

local function Build(boss, record)
    for i = #entries, 1, -1 do
        spare[#spare + 1] = entries[i]
        entries[i] = nil
    end
    local at = record and record.at or {}
    for i = 1, #at do
        if type(at[i]) == "number" then Entry(at[i], i) end
    end
    Looted.AllFrom(boss, items)
    for i = #items, 1, -1 do   -- oldest first, so each kill's items stay in the order they came
        local item = items[i]
        local entry = KillBefore(item.at) or Entry(item.at, nil)
        entry.items[#entry.items + 1] = item
    end
    table.sort(entries, Newer)
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
local members, rolls, byName = {}, {}, {}   -- reused by every draw
local dropIDs, dropRolls, dropped = {}, {}, {}   -- a kill's drops: their item IDs, rolls, and a set of the IDs

local function ItemID(link)
    return tonumber(link:match("|Hitem:(%d+)"))
end

-- Your group as it was kept; byName then holds each member, for the rolls' colours.
local function DrawTeam(team)
    Team.Read(team, members)
    wipe(byName)
    view:Add("label", "Group", #members > 0 and #members or nil)
    if #members == 0 then
        view:Add("rolls", "Not kept for this one.")
        return
    end
    for _, member in ipairs(members) do byName[member.name] = member end
    view:Add("team", members)
end

-- Whether the roller was you: the team says, else your name now.
local function IsMe(name)
    local member = byName[name]
    if member then return member.me end
    return name == UnitName("player")
end

-- An item's rolls: the grid, with each roller's class from the team when the roll kept none;
-- a line when everyone passed, or when no one rolled (picked up without a roll).
local function DrawRolls(text)
    Team.ReadRolls(text, rolls)
    if #rolls == 0 then
        view:Add("rolls", "Picked up without a roll")
        return
    end
    local won = false
    for _, roll in ipairs(rolls) do
        local member = byName[roll.name]
        roll.class = roll.class or (member and member.class)
        won = won or roll.winner
    end
    if not won then view:Add("rolls", "Everyone passed") end
    view:Add("rollGrid", rolls, IsMe)
end

local function KeepDrop(link, rollText)
    local id = ItemID(link)
    if not id then return end
    dropIDs[#dropIDs + 1], dropRolls[#dropRolls + 1] = id, rollText
    dropped[id] = true
end

-- What dropped (dropsText, the kill's own, from the game's loot history), each with who won
-- it; then what you picked up that the history does not list (an item under the group's roll
-- threshold, or loot with no kill).
local function DrawLoot(dropsText, own)
    wipe(dropIDs)
    wipe(dropRolls)
    wipe(dropped)
    Kills.EachDrop(dropsText, KeepDrop)
    local count = #dropIDs
    for _, item in ipairs(own) do
        if not dropped[item.id] then count = count + 1 end
    end
    if count == 0 then return end
    view:Add("label", "Loot", count)
    -- Every other item on a faint band, the first one included, its rolls with it.
    local n = 0
    for i, id in ipairs(dropIDs) do
        n = n + 1
        view.striped = n % 2 == 1
        view:Add("item", id, nil, nil, false)
        DrawRolls(dropRolls[i])
    end
    for _, item in ipairs(own) do
        if not dropped[item.id] then
            n = n + 1
            view.striped = n % 2 == 1
            view:Add("item", item.id, nil, nil, false)
            DrawRolls(item.rolls)
        end
    end
    view.striped = false
end

-- A kill, or loot with none, as a card like a boss's on the page: its rows inside, and the
-- card sized to them once they are drawn.
local function DrawEntry(entry, record, bestAt)
    local top, width = view.cursor, view:GetWidth()
    local card = view:Acquire("card")
    card:SetFrameLevel(view:GetFrameLevel())
    card.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
    view.left, view.width = CARD_PAD, width - CARD_PAD * 2
    local i = entry.kill
    if i then
        local took = type(record.took) == "table" and record.took[i]
        -- Which kill it was: the latest is the count, each before it one less.
        -- The fastest kill says so, in gold.
        local length = type(took) == "number" and "took " .. FightLength(took) or nil
        if length and entry.at == bestAt then length = GOLD_CODE .. "Record|r  " .. length end
        view:Add("historyHead", record.n - (#record.at - i), date(KILL_DATE, entry.at), length)
        local teams = type(record.team) == "table" and record.team or nil
        -- Older kills kept no team: the loot's, when it did.
        local first = entry.items[1]
        DrawTeam(teams and teams[i] or (first and first.team))
        DrawLoot(type(record.drops) == "table" and record.drops[i] or nil, entry.items)
    else
        view:Add("historyHead", nil, date(KILL_DATE, entry.at), "looted")
        DrawTeam(entry.items[1].team)
        DrawLoot(nil, entry.items)
    end
    view:Space(CARD_PAD)
    view.left, view.width = 0, width
    card:SetHeight(view.cursor - top)
    view:Space(CARD_GAP)
end

-- Why a boss's kills are not counted: the game does not say which creature died, only
-- which encounter ended; and a raid not open yet has no encounters named.
---@param dungeon? JournalDungeon
function BossPanel.NotCounted(dungeon)
    if dungeon and dungeon.raid and dungeon.note then
        return "The game does not name this fight yet: its kills count once the raid opens."
    end
    return "In a dungeon the game keeps secret which creature died, and only names boss fights. "
        .. "This one is no boss fight to the game, so its kills cannot be counted."
end

local function Draw()
    local boss = shown.boss
    Kills.Gather(boss)
    local record = Kills.Record(boss)
    panel.title:SetText(boss.name:upper())
    view:Begin(nil, nil, nil)
    view.showChance = false   -- what dropped, not how often it does
    view.bare = true          -- the boss's loot on the page says what each item is to you
    Build(boss, record)
    if not Kills.Counted(boss) then view:Note(BossPanel.NotCounted(shown.dungeon)) end
    view:Section("Kills", record and record.n or 0)
    view:Space(SECTION_SPACE)
    if #entries == 0 then
        view:Note("Nothing yet on this character. Kills and loot count while the Dungeon Journal is on.")
    end
    local bestAt
    if record then bestAt = select(2, Kills.Best(record)) end
    for _, entry in ipairs(entries) do DrawEntry(entry, record, bestAt) end
    if record and record.n > #record.at and type(record.first) == "number" then
        view:Note(("The latest %d kills. First counted: %s."):format(#record.at, date(KILL_DATE, record.first)))
    end
    view:Space(SECTION_SPACE)
    view:Finish()
end

-- Opens the boss's history beside the frame holding from; opened again on the same boss,
-- it closes.
---@param boss JournalBoss
---@param from Frame
---@param dungeon? JournalDungeon the boss's
function BossPanel.Show(boss, from, dungeon)
    if not panel then
        panel = Parts.SidePanel({})
        view = panel.view
        -- Its own redraw: it shows a boss's history, not a dungeon.
        view.Redraw = Draw
    end
    if panel:IsShown() and shown.boss == boss then
        panel:Hide()
        return
    end
    shown.boss, shown.dungeon = boss, dungeon
    Parts.ShowBeside(panel, from)
    Draw()
end

-- Draws it again when it is open: kills or loot forgotten, or counted, under it.
function BossPanel.Refresh()
    if panel and panel:IsShown() then Draw() end
end
