-------------------------------------------------------------------------------
--  UI/FactionList.lua -- the list down the left of the Journal's window on its Reputation
--  and PvP tabs (ns.Journal.FactionList), where the Dungeon List is on the first. The
--  Reputation tab's factions under their titles (new in Forever, the classic ones, the
--  Steamwheedle Cartel's towns); the PvP tab's rank, then the battleground factions of the
--  sides the faction switch lists. Each row: the one shown marked, NEW before the ones new
--  in Forever, your BiS among its rewards counted, and your standing in its colour over a
--  small bar; a check after its name at Exalted. A card on hover. Made by the window the
--  first time it opens.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Loot = J.Loot
local Rep = J.Reputation
local S = J.Settings

local St = J.Style
local BIS_RGB, BIS_CODE, TERRITORY_CODE, PLACE_DOT = St.BIS_RGB, St.BIS_CODE, St.TERRITORY_CODE, St.PLACE_DOT
local LIST_W, LIST_ROW, GROUP_H, STRIPE = St.LIST_W, St.LIST_ROW, St.GROUP_H, St.STRIPE
local NAME_SIZE, COUNT_SIZE, NEW_TAG_SIZE = St.LIST_NAME_SIZE, St.LIST_COUNT_SIZE, St.NEW_TAG_SIZE
local BAR, BAR_GAP, STANDING_W, ROUND = St.LIST_BAR, St.LIST_BAR_GAP, St.LIST_STANDING_W, St.ROUND
local TERRITORY_ICON, FACTION_ATLAS = St.TERRITORY_ICON, St.FACTION_ATLAS

local STAR_TAG = ("|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(St.STAR, BIS_RGB.r * 255,
    BIS_RGB.g * 255, BIS_RGB.b * 255)
local DONE = ("|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(St.CHECK, St.HAVE_RGB.r * 255,
    St.HAVE_RGB.g * 255, St.HAVE_RGB.b * 255)

-- A row as the Dungeon List's: the accent bar, NEW in its column, the name; then on the right
-- your BiS count, the standing and its bar, and a battleground faction's crest.
local ROW_W = LIST_W - BAR - BAR_GAP - 2
local SELECTED_BAR = 3
local NEW_LEFT, NAME_LEFT = 14, 40
local GAP, RIGHT = 8, 8
local PILL = 4              -- the standing's bar: as thick as a drop chance's
local ICON_DROP = 1         -- the crest level with the digits, as the Dungeon List's
local GROUP_GAP = 4
local UNMET = 0.45          -- a faction you have not met: its row this faint
-- The columns on the right, each at a fixed width so they line up down the list: the rewards
-- your standing has reached ("6/49") and the standing's name, both right-aligned.
local UNLOCKED_W, STANDING_NAME_W = 30, 56
local UNRELEASED = "Not in Forever yet"   -- closed until opened (openUnreleased)

local List = {}
J.FactionList = List

-- Each tab's titles, in order, and which a faction is under.
local GROUPS = {
    reputation = { "New in Forever", "Classic", "Cities", "Steamwheedle Cartel", UNRELEASED },
    pvp = { "Your Rank", "Battlegrounds" },
}

local function GroupOf(page)
    if page.rank then return "Your Rank" end
    if page.tab == "pvp" then return "Battlegrounds" end
    if page.unreleased then return UNRELEASED end
    return page.group or (page.new and "New in Forever" or "Classic")
end

local rows, headers = {}, {}   -- every row, both tabs'; each tab's titles by name
local onSelect, shownTab
local filters = {}             -- read when a count is shown (JournalFilters)
local order = {}               -- the shown rows' pages in order, for Up and Down; reused
local scroll, content

-------------------------------------------------------------------------------
--  A row's small standing bar: a track with round ends, and a fill with round ends
-------------------------------------------------------------------------------
local function Dot(row, layer, color)
    local dot = row:CreateTexture(nil, layer)
    dot:SetTexture(ROUND, nil, nil, "TRILINEAR")
    dot:SetSize(PILL, PILL)
    dot:SetVertexColor(color.r, color.g, color.b, 1)
    return dot
end

local function Pill(row, right)
    local track = ns.Solid(row, "BORDER", T.line, 1)
    track:SetPoint("RIGHT", right - PILL / 2, 0)
    track:SetSize(STANDING_W - PILL, PILL)
    Dot(row, "BORDER", T.line):SetPoint("CENTER", track, "LEFT")
    Dot(row, "BORDER", T.line):SetPoint("CENTER", track, "RIGHT")
    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetColorTexture(1, 1, 1, 1)
    row.fill:SetPoint("LEFT", track)
    row.fill:SetHeight(PILL)
    row.fillStart = Dot(row, "ARTWORK", T.fg)
    row.fillStart:SetPoint("CENTER", row.fill, "LEFT")
    row.fillEnd = Dot(row, "ARTWORK", T.fg)
    row.fillEnd:SetPoint("CENTER", row.fill, "RIGHT")
    row.track = track
end

local function SetPill(row, share, color)
    local any = share > 0
    row.fill:SetShown(any)
    row.fillStart:SetShown(any)
    row.fillEnd:SetShown(any)
    if not any then return end
    row.fill:SetWidth(math.max(0.1, (STANDING_W - PILL) * math.min(1, share)))
    row.fill:SetVertexColor(color.r, color.g, color.b, 1)
    row.fillStart:SetVertexColor(color.r, color.g, color.b, 1)
    row.fillEnd:SetVertexColor(color.r, color.g, color.b, 1)
end

-------------------------------------------------------------------------------
--  A row and its card
-------------------------------------------------------------------------------
local function RowEnter(row)
    local page = row.page
    if not row.selected then row.band:SetAlpha(0.05) end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(page.rank and "Your PvP Rank" or page.name)
    if page.rank then
        local info = Rep.Rank()
        if info then
            GameTooltip:AddLine("Rank " .. info.renownLevel .. PLACE_DOT .. Rep.RankTitle(info.renownLevel), 1, 1, 1)
        end
        GameTooltip:AddLine("Your rank this season, and what each rank gives.", T.muted.r, T.muted.g, T.muted.b,
            true)
        GameTooltip:Show()
        return
    end
    if page.new then GameTooltip:AddLine("New in WoW Forever", T.accent.r, T.accent.g, T.accent.b) end
    if page.side then
        GameTooltip:AddLine(TERRITORY_CODE[page.side] .. page.side .. "|r"
            .. (page.battleground and PLACE_DOT .. page.battleground or ""), 1, 1, 1)
    end
    if page.zone then GameTooltip:AddLine("Quartermaster in " .. page.zone, 1, 1, 1) end
    local reaction, value, max = Rep.Standing(page)
    if not reaction then
        GameTooltip:AddLine("Not met yet", T.muted.r, T.muted.g, T.muted.b)
    else
        local color = Rep.Color(reaction)
        GameTooltip:AddLine(Rep.Label(reaction) .. (reaction < Rep.EXALTED and ("  %s / %s"):format(BreakUpLargeNumbers(value),
            BreakUpLargeNumbers(max)) or ""), color.r, color.g, color.b)
    end
    Loot.ReadFilters(filters)
    local unlocked, total = Rep.Unlocked(page, reaction, filters)
    if total > 0 then
        GameTooltip:AddLine(("%d of its %d rewards for you unlocked"):format(unlocked, total), 1, 1, 1)
    else
        GameTooltip:AddLine("No rewards for you in this build yet", T.muted.r, T.muted.g, T.muted.b)
    end
    local bis, haveBis = Rep.Bis(page)
    if bis > 0 then
        GameTooltip:AddLine(("%s%d of your %d BiS among its rewards are yours|r"):format(BIS_CODE, haveBis, bis))
    end
    if page.unreleased then
        GameTooltip:AddLine("Its raids are not announced for WoW Forever yet.", T.muted.r, T.muted.g, T.muted.b, true)
    end
    GameTooltip:Show()
end

local function RowLeave(row)
    if not row.selected then row.band:SetAlpha(0) end
    GameTooltip:Hide()
end

local function RowClicked(row)
    onSelect(row.page)
end

local function Row(parent, page)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_W, LIST_ROW)
    row.page, row.group = page, GroupOf(page)
    row.tab = page.tab
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
    row.stripe:SetAllPoints()
    row.band = ns.Solid(row, "BACKGROUND", T.fg, 1)
    row.band:SetAllPoints()
    row.band:SetAlpha(0)
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(SELECTED_BAR)
    -- A battleground faction's crest at the right edge; the bar left of it, or at the edge.
    -- None on Reputation: only your side's cities are listed there.
    local right = -RIGHT
    if page.side and page.tab == "pvp" then
        local crest = row:CreateTexture(nil, "ARTWORK")
        crest:SetSize(TERRITORY_ICON, TERRITORY_ICON)
        crest:SetPoint("RIGHT", -RIGHT, -ICON_DROP)
        crest:SetAtlas(FACTION_ATLAS[page.side])
        right = right - TERRITORY_ICON - GAP
    end
    Pill(row, right)
    row.standing = ns.Font(row, COUNT_SIZE, nil, T.muted)
    row.standing:SetPoint("RIGHT", row.track, "LEFT", -GAP - PILL / 2, 0)
    row.standing:SetWidth(STANDING_NAME_W)
    row.standing:SetJustifyH("RIGHT")
    row.unlocked = ns.Font(row, COUNT_SIZE, nil, T.muted)
    row.unlocked:SetPoint("RIGHT", row.standing, "LEFT", -GAP, 0)
    row.unlocked:SetWidth(UNLOCKED_W)
    row.unlocked:SetJustifyH("RIGHT")
    row.bis = ns.Font(row, COUNT_SIZE, nil, BIS_RGB)
    row.bis:SetPoint("RIGHT", row.unlocked, "LEFT", -GAP, 0)
    row.name = ns.Font(row, NAME_SIZE)
    row.name:SetPoint("LEFT", NAME_LEFT, 0)
    row.name:SetPoint("RIGHT", row.bis, "LEFT", -GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.label = page.rank and "PvP Rank" or page.name
    row.name:SetText(row.label)
    if page.new then
        row.new = ns.Font(row, NEW_TAG_SIZE, nil, T.accent)
        row.new:SetText("NEW")
        row.new:SetPoint("BOTTOMLEFT", row.name, "BOTTOMLEFT", NEW_LEFT - NAME_LEFT, 0)
    end
    row:SetScript("OnClick", RowClicked)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

-- A title over a tab's rows, as the Dungeon List's. Only "Not in Forever yet" opens and
-- closes (closed at first, by a click anywhere on it, its count shown while closed), with the
-- Dungeon List's chevron: the others are short enough to show whole.
local function HeaderColor(header, color)
    header.label:SetTextColor(color.r, color.g, color.b)
    if header.arrow then header.arrow:SetVertexColor(color.r, color.g, color.b) end
end

local function HeaderClicked() S.Set("openUnreleased", not S.Get("openUnreleased")) end
local function HeaderEnter(header) HeaderColor(header, T.fg) end
local function HeaderLeave(header) HeaderColor(header, T.accentSoft) end

local function Header(parent, text)
    local folds = text == UNRELEASED
    local header = CreateFrame(folds and "Button" or "Frame", nil, parent)
    header:SetSize(ROW_W, GROUP_H)
    header.label = ns.Font(header, 10, nil, T.accentSoft)
    header.label:SetText(text:upper())
    if folds then
        header.arrow = J.View.Parts.Arrow(header, 10, T.accentSoft)
        header.arrow:SetPoint("BOTTOMLEFT", 3, 5)
        header.label:SetPoint("BOTTOMLEFT", 16, 4)
        header.count = ns.Font(header, 10, nil, T.muted)
        header.count:SetPoint("LEFT", header.label, "RIGHT", 8, 0)
        header:SetScript("OnClick", HeaderClicked)
        header:SetScript("OnEnter", HeaderEnter)
        header:SetScript("OnLeave", HeaderLeave)
    else
        header.label:SetPoint("BOTTOMLEFT", 3, 4)
    end
    local line = ns.Solid(header, "ARTWORK", T.line, 1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.Hairline(line, "h")
    return header
end

-------------------------------------------------------------------------------
--  The list
-------------------------------------------------------------------------------
-- Makes the list in parent, scrolling once it runs past the window. select(page) is called
-- when a row is clicked: a faction, or J.RANK.
---@param parent Frame
---@param select fun(page: JournalFaction|table)
function List.Build(parent, select)
    onSelect = select
    scroll = ns.UI.SlimScroll(parent, BAR, BAR_GAP)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMLEFT")
    scroll:SetWidth(ROW_W)
    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(ROW_W)
    scroll:SetScrollChild(content)
    for _, titles in pairs(GROUPS) do
        for _, title in ipairs(titles) do headers[title] = Header(content, title) end
    end
    rows[1] = Row(content, J.RANK)
    for _, tab in ipairs({ "reputation", "pvp" }) do
        for _, faction in ipairs(J.Factions(tab)) do rows[#rows + 1] = Row(content, faction) end
    end
end

local function Listed(row, tab)
    return row.tab == tab and Rep.Shown(row.page)
end

-- Lays out the tab's rows under their titles; a title with nothing under it is left out,
-- and the other tab's rows and titles are hidden.
---@param tab "reputation"|"pvp"
function List.Layout(tab)
    shownTab = tab
    for _, header in pairs(headers) do header:Hide() end
    for _, row in ipairs(rows) do row:Hide() end
    local y = 0
    for _, title in ipairs(GROUPS[tab]) do
        local count, header = 0, headers[title]
        local closed = title == UNRELEASED and not S.Get("openUnreleased")
        for _, row in ipairs(rows) do
            if row.group == title and Listed(row, tab) then
                if count == 0 then
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", 0, -y)
                    header:Show()
                    y = y + GROUP_H
                end
                count = count + 1
                if not closed then
                    row.stripe:SetShown(count % 2 == 0)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    row:Show()
                    row.top = y
                    y = y + LIST_ROW
                end
            end
        end
        if header.arrow then
            header.arrow:SetRotation(closed and 0 or -math.pi / 2)
            header.count:SetText(closed and count or "")
        end
        if count > 0 then y = y + GROUP_GAP end
    end
    content:SetHeight(math.max(1, y))
    scroll.bar:SetValue(0)
end

-- Scrolls just enough to show the row.
local function ShowRow(row)
    if not (row.top and row:IsShown()) then return end
    local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
    if row.top < offset then
        scroll.bar:SetValue(row.top)
    elseif row.top + LIST_ROW > offset + height then
        scroll.bar:SetValue(row.top + LIST_ROW - height)
    end
end

-- Each faction's unlocked count, kept until your standing or what is listed changes: the
-- filters that decide it (with Missing BiS Only, which follows your bags, it is counted each
-- time). The cache holds one record per faction, made once.
local counted = {}

local function SkillsKey()
    local key = 0
    for line in pairs(filters.skills) do key = key + line end
    return key
end

local function Unlocked(faction, reaction)
    if filters.missingBis or filters.upgradesOnly then return Rep.Unlocked(faction, reaction, filters) end
    local c = counted[faction]
    if not c then
        c = {}
        counted[faction] = c
    end
    local skills = SkillsKey()
    if c.total == nil or c.reaction ~= reaction or c.usable ~= filters.usableOnly or c.mine ~= filters.myRecipes
        or c.skills ~= skills then
        c.reaction, c.usable, c.mine, c.skills = reaction, filters.usableOnly, filters.myRecipes, skills
        c.unlocked, c.total = Rep.Unlocked(faction, reaction, filters)
    end
    return c.unlocked, c.total
end

-- The rank's row: your rank, and how far to the next, in the accent.
local function PaintRank(row)
    local info = Rep.Rank()
    local level = info and info.renownLevel or 0
    -- No rank yet: the game's own word for it (Civilian), as the rank's page title says.
    row.standing:SetText(level > 0 and "Rank " .. level or Rep.RankTitle(0))
    row.standing:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
    local share = 0
    if info then
        share = level >= info.maxLevel and 1 or info.renownReputationEarned / math.max(1, info.renownLevelThreshold)
    end
    SetPill(row, share, T.accent)
    row.bis:SetText("")
end

-- The one shown: the accent bar and a lighter band. Factions you have met in white, the
-- rest faint; your standing with each in its colour, the BiS among its rewards you still
-- miss in orange (a check once you have them all), and a check after the name at Exalted.
---@param selected? JournalFaction|table
function List.Paint(selected)
    if not shownTab then return end
    Loot.ReadFilters(filters)
    for _, row in ipairs(rows) do
        if row:IsShown() then
            local page = row.page
            local chosen = page == selected
            row.selected = chosen
            row.bar:SetShown(chosen)
            if chosen then ShowRow(row) end
            row.band:SetAlpha(chosen and 0.10 or 0)
            if page.rank then
                PaintRank(row)
                row.name:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
            else
                local reaction, value, max = Rep.Standing(page)
                local color = reaction and Rep.Color(reaction) or T.muted
                row.standing:SetText(reaction and Rep.Label(reaction) or "")
                local unlocked, total = Unlocked(page, reaction)
                -- Always, as 0/0 when the build has nothing for you yet: every row reads alike.
                row.unlocked:SetText(unlocked .. "/" .. total)
                row.standing:SetTextColor(color.r, color.g, color.b)
                SetPill(row, reaction and value / max or 0, color)
                local name = (chosen or reaction) and T.fg or T.muted
                row.name:SetTextColor(name.r, name.g, name.b)
                row:SetAlpha((reaction or chosen) and 1 or UNMET)
                local bis, haveBis = Rep.Bis(page)
                local missing = bis > 0 and bis - haveBis or -1
                if missing ~= row.missing then
                    row.missing = missing
                    row.bis:SetText(missing < 0 and "" or STAR_TAG .. (missing == 0 and DONE or missing))
                end
                local exalted = reaction == Rep.EXALTED
                if exalted ~= row.exalted then
                    row.exalted = exalted
                    row.name:SetText(exalted and row.label .. "  " .. DONE or row.label)
                end
            end
        end
    end
end

-- The row above (by -1) or below (1) the one shown, in the list's order, wrapping round.
---@param from JournalFaction|table
---@param by -1|1
---@return JournalFaction|table
function List.Next(from, by)
    local n, at = 0, nil
    for _, title in ipairs(GROUPS[shownTab]) do
        for _, row in ipairs(rows) do
            if row.group == title and row:IsShown() then
                n = n + 1
                order[n] = row.page
                if row.page == from then at = n end
            end
        end
    end
    if n == 0 then return from end
    if not at then return order[1] end
    return order[(at - 1 + by) % n + 1]
end

-- The first row of the tab, for a tab opened with nothing picked on it yet.
---@param tab "reputation"|"pvp"
function List.First(tab)
    for _, title in ipairs(GROUPS[tab]) do
        for _, row in ipairs(rows) do
            if row.group == title and Listed(row, tab) then return row.page end
        end
    end
end
