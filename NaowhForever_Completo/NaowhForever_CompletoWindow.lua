-------------------------------------------------------------------------------
--  NaowhForever_CompletoWindow.lua -- Completo's own window (/nfcompleto, its minimap and top
--  bar button, Open Quests on its settings page). The Quests tab starts on the zone you are
--  in: how many of its quests you have done, then its quests by level. A quest chain shows
--  as its first quest with the chain icon in front and how far along you are, its follow-up
--  quests indented under it. All Zones lists every zone by continent with its progress;
--  click one to open it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.CompletoSettings
local Q = ns.Completo.Quests
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 760, 720
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR, TAB_H, TAB_GAP = St.CONTENT_INSET, St.SCROLLBAR, St.TAB_H, St.TAB_GAP
local PAGE = "Completo/Quests"
local CARD = 6
local TABS_W = 130
local HERO_H = 84
local BAR_H = 4
local ROW_TOP, ROW_BOTTOM, LINE_GAP = 6, 8, 3
local LEVEL_W = 24
local TICK = 14
local PIN_RIGHT = 10
local STATUS_W = 120
local STATUS_GAP = 10
local ZONE_H = 44
local ZONE_BAR_W = 180
local SEARCH_W = 260
local SEARCH_MAX = 150          -- quests a search lists at most
-- The smallest the window drags down to: the tabs and the search box side by side, and a
-- handful of rows.
local MIN_W, MIN_H = 620, 420
local CHAIN = St.CHAIN
local CHAIN_ICON = 14
-- A chain's follow-up quests: indented STEP_INDENT, on a tree line down from under the chain
-- icon (TREE_X), reaching TREE_UP into the row above, its branch stopping TREE_GAP short of
-- the level; the last turns on a rounded corner (ELBOW, its texture's own size).
local STEP_INDENT = 26
local TREE_X, TREE_UP, TREE_GAP, TREE_ALPHA, ELBOW = St.INDENT + 7, 6, 4, 0.5, 8
local STRIPE, HOVER = 0.025, 0.04
local LOG_RGB = { r = 1, g = 0.82, b = 0 }
local REPEAT_RGB = { r = 0.35, g = 0.7, b = 1 }
local EVENTS = { "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }

local CONTINENTS = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }
local ELSEWHERE = "Elsewhere"

local TABS = {
    { key = "quests", label = "Quests", tip = "Every quest of every zone, and where you are in each chain." },
}

local window, scroll, view, kinds
local tab = "quests"
local zone              -- the zone open, or nil for All Zones

local function Opacity()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("windowAlpha", value / 100)
end

local function Percent(n, total)
    return total > 0 and math.floor(n / total * 100) or 0
end

local function Levels(low, high)
    if not low then return "" end
    if low == high then return ("Level %d"):format(low) end
    return ("Levels %d-%d"):format(low, high)
end

local function NewRowBase(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
    row.stripe:SetAllPoints()
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, HOVER)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.divider = ns.Solid(row, "BORDER", T.line, 0.6)
    row.divider:SetPoint("BOTTOMLEFT", St.INDENT, 0)
    row.divider:SetPoint("BOTTOMRIGHT")
    ns.Hairline(row.divider, "h")
    row:EnableMouse(true)
    return row
end

-------------------------------------------------------------------------------
--  The card on top: done of total, as a count and a bar
-------------------------------------------------------------------------------
local function NewHero(parent)
    local hero = CreateFrame("Frame", nil, parent)
    ns.Solid(hero, "BACKGROUND", T.fg, St.CARD_FILL):SetAllPoints()
    ns.Border(hero, St.BORDER_RGB)
    hero.kicker = ns.Font(hero, 10, nil, T.accentSoft)
    hero.kicker:SetPoint("TOPLEFT", 16, -14)
    hero.count = ns.Font(hero, 22, nil, T.fg)
    hero.count:SetPoint("TOPLEFT", hero.kicker, "BOTTOMLEFT", 0, -4)
    hero.about = ns.Font(hero, 12, nil, T.muted)
    hero.about:SetPoint("BOTTOMLEFT", hero.count, "BOTTOMRIGHT", 10, 3)
    hero.bar = Parts.ProgressLine(hero, BAR_H)
    hero.bar:SetPoint("TOPLEFT", hero.count, "BOTTOMLEFT", 0, -12)
    hero.bar:SetPoint("RIGHT", -16, 0)
    return hero
end

local function SetHero(hero, kicker, n, total, about)
    hero.kicker:SetText(kicker:upper())
    hero.count:SetText(("%d / %d"):format(n, total))
    hero.about:SetText(about)
    hero.bar:SetProgress(total > 0 and n / total or 0)
    return HERO_H
end

-------------------------------------------------------------------------------
--  A zone on All Zones: its name and levels, its count and bar; click to open it
-------------------------------------------------------------------------------
local function OpenZone(picked)
    zone = picked
    scroll:SetVerticalScroll(0)
    view:Redraw()
end

local function ZoneEnter(row)
    row.hover:Show()
    if not Parts.Tip(row, "ANCHOR_RIGHT") then return end
    local n, total = Q.ZoneProgress(row.zone)
    GameTooltip:SetText(row.zone.name, 1, 1, 1)
    GameTooltip:AddLine(("%d of %d quests done"):format(n, total), T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:AddLine("Click to see its quests.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function RowLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function ZoneMouseUp(row, button)
    if button == "LeftButton" then OpenZone(row.zone) end
end

local function NewZone(parent)
    local row = NewRowBase(parent)
    row.title = ns.Font(row, 13, nil, T.fg)
    row.title:SetPoint("TOPLEFT", St.INDENT, -ROW_TOP)
    row.levels = ns.Font(row, 11, nil, T.muted)
    row.levels:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -LINE_GAP)
    row.count = ns.Font(row, 12, nil, T.fg)
    row.count:SetPoint("TOPRIGHT", -PIN_RIGHT, -ROW_TOP)
    row.count:SetJustifyH("RIGHT")
    row.bar = Parts.ProgressLine(row, BAR_H)
    row.bar:SetPoint("TOPRIGHT", row.count, "BOTTOMRIGHT", 0, -8)
    row.bar:SetWidth(ZONE_BAR_W)
    row:SetScript("OnEnter", ZoneEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnMouseUp", ZoneMouseUp)
    return row
end

local function SetZone(row, z, stripe)
    row.zone = z
    row.stripe:SetShown(stripe)
    row.hover:Hide()
    local n, total, low, high = Q.ZoneProgress(z)
    row.title:SetText(z.name)
    row.levels:SetText(Levels(low, high))
    local finished = total > 0 and n == total
    local c = finished and St.HAVE_RGB or T.fg
    row.count:SetText(("%d / %d  (%d%%)"):format(n, total, Percent(n, total)))
    row.count:SetTextColor(c.r, c.g, c.b)
    row.bar:SetProgress(total > 0 and n / total or 0)
    return ZONE_H
end

-------------------------------------------------------------------------------
--  A quest: its level (a tick once done), its name, where it stands; a waypoint to whoever
--  gives it, and right-click for its Wowhead link. A chain's first quest has the chain icon
--  in front; its follow-up quests sit under it, indented on a tree line from that icon.
-------------------------------------------------------------------------------
local STATE = {
    done = { "Done", "muted" }, log = { "In your log", "log" }, low = { "Needs level %d", "red" },
    later = { "Needs an earlier quest", "muted" }, open = { "Not done", "fg" },
    held = { "Not offered yet", "muted" },
}

local function StateText(id, state)
    local entry = STATE[state]
    local text = entry[1]
    if state == "low" then text = text:format(Q.RequiredLevel(id)) end
    if state == "open" and Q.Repeatable(id) then return "Repeatable", REPEAT_RGB end
    local color = entry[2] == "log" and LOG_RGB or entry[2] == "red" and St.RED_RGB or T[entry[2]]
    return text, color
end

local function PinClicked(button)
    Q.Waypoint(button:GetParent().quest)
end

local function QuestEnter(row)
    row.hover:Show()
    if not Parts.Tip(row, "ANCHOR_RIGHT") then return end
    local id, m = row.quest, T.muted
    GameTooltip:SetText(Q.Name(id), 1, 1, 1)
    GameTooltip:AddDoubleLine("Level", Q.Level(id), m.r, m.g, m.b, 1, 1, 1)
    if Q.RequiredLevel(id) > 0 then
        GameTooltip:AddDoubleLine("Requires level", Q.RequiredLevel(id), m.r, m.g, m.b, 1, 1, 1)
    end
    local text, color = StateText(id, Q.State(id))
    GameTooltip:AddDoubleLine("Status", text, m.r, m.g, m.b, color.r, color.g, color.b)
    local chain = Q.Chain(id)
    if chain then
        local at, steps = Q.ChainAt(chain)
        local where = at > steps and "every step done" or ("on step %d"):format(at)
        GameTooltip:AddDoubleLine("Chain", ("%d steps, %s"):format(steps, where), m.r, m.g, m.b, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine((Q.Spot(id) and "Pin: waypoint    " or "") .. "Right-click: Wowhead link",
        T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function QuestMouseUp(row, button)
    if button == "RightButton" then Parts.CopyWowhead("quest", row.quest, Q.Name(row.quest)) end
end

local function NewQuest(parent)
    local row = NewRowBase(parent)
    row.pin = Parts.IconButton(row, PinClicked, St.PIN, 0, "Waypoint")
    row.pin.hint = "To who gives the quest."
    row.pin:SetPoint("RIGHT", -PIN_RIGHT, 0)
    row.chain = row:CreateTexture(nil, "ARTWORK")
    row.chain:SetTexture(CHAIN, nil, nil, "TRILINEAR")
    row.chain:SetSize(CHAIN_ICON, CHAIN_ICON)
    row.chain:SetPoint("TOPLEFT", St.INDENT, -(ROW_TOP + 1))
    row.chain:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    row.trunk = ns.Solid(row, "ARTWORK", T.accentSoft, TREE_ALPHA)
    ns.Hairline(row.trunk, "v")
    row.branch = ns.Solid(row, "ARTWORK", T.accentSoft, TREE_ALPHA)
    ns.Hairline(row.branch, "h")
    row.elbow = row:CreateTexture(nil, "ARTWORK")
    row.elbow:SetTexture(St.ELBOW)
    row.elbow:SetSize(ELBOW, ELBOW)
    row.elbow:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, TREE_ALPHA)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(St.TICK, nil, nil, "TRILINEAR")
    row.tick:SetSize(TICK, TICK)
    row.tick:SetVertexColor(St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b)
    row.level = ns.Font(row, 12)
    row.level:SetWidth(LEVEL_W)
    row.level:SetJustifyH("LEFT")
    row.title = ns.Font(row, 13, nil, T.fg)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.where = ns.Font(row, 11, nil, T.muted)
    row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -LINE_GAP)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)
    row.status = ns.Font(row, 11, nil, T.fg)
    row.status:SetPoint("RIGHT", row.pin, "LEFT", -STATUS_GAP, 0)
    row.status:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", QuestEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnMouseUp", QuestMouseUp)
    return row
end

-- The tree line of a chain's follow-up quest: down from under the chain icon (reaching into
-- the row above on the first), across to the quest's level, the last turning on a rounded
-- corner. middle: how far down the row its title's middle is.
local function SetTree(row, first, last, middle)
    row.trunk:ClearAllPoints()
    row.branch:ClearAllPoints()
    row.elbow:ClearAllPoints()
    local up = first and TREE_UP or 0
    local corner = last and ELBOW or 0
    row.trunk:SetPoint("TOPLEFT", TREE_X, up)
    if last then
        row.trunk:SetHeight(up + middle - ELBOW + 1)
    else
        row.trunk:SetPoint("BOTTOMLEFT", TREE_X, 0)
    end
    row.elbow:SetPoint("TOPLEFT", TREE_X, -(middle - ELBOW + 1))
    row.elbow:SetShown(last)
    row.branch:SetPoint("TOPLEFT", TREE_X + corner, -middle)
    row.branch:SetWidth(St.INDENT + STEP_INDENT - TREE_GAP - TREE_X - corner)
end

---@param part? string "head" for a chain's first quest, "step" for a follow-up, nil for a quest in no chain
---@param first? boolean a step: the chain's first follow-up
---@param last? boolean a step: its last
local function SetQuest(row, id, part, first, last, stripe)
    row.quest = id
    row.stripe:SetShown(stripe)
    row.hover:Hide()
    local step = part == "step"
    local left = St.INDENT + (part == "head" and CHAIN_ICON + 4 or step and STEP_INDENT or 0)
    row.chain:SetShown(part == "head")
    row.tick:ClearAllPoints()
    row.tick:SetPoint("TOPLEFT", left, -(ROW_TOP + 1))
    row.level:ClearAllPoints()
    row.level:SetPoint("TOPLEFT", left, -(ROW_TOP + 1))
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", left + LEVEL_W + 4, -ROW_TOP)
    local state = Q.State(id)
    local finished = state == "done"
    row.tick:SetShown(finished)
    row.level:SetShown(not finished)
    local level = Q.Level(id)
    row.level:SetText(level > 0 and level or "")
    local c = GetQuestDifficultyColor(level > 0 and level or UnitLevel("player"))
    row.level:SetTextColor(c.r, c.g, c.b)
    row.pin:SetShown(Q.Spot(id) ~= nil and not finished)
    local text, color = StateText(id, state)
    row.status:SetText(text)
    row.status:SetTextColor(color.r, color.g, color.b)
    local textW = row:GetWidth() - left - LEVEL_W - 4 - PIN_RIGHT - STATUS_W - STATUS_GAP
    row.title:SetWidth(textW)
    row.title:SetText(Q.Name(id))
    local tc = finished and T.muted or T.fg
    row.title:SetTextColor(tc.r, tc.g, tc.b)
    -- Under it: on a chain's first quest, how far along the chain you are; on a chain's quest
    -- found on its own (a search), its step in the chain; on a zone's page, its zone when
    -- that is not the one open.
    local sub = ""
    if part == "head" then
        local at, steps = Q.ChainAt(Q.Chain(id))
        sub = at > steps and ("Quest chain of %d, all done"):format(steps)
            or ("Quest chain of %d, on step %d"):format(steps, at)
    elseif not step and Q.Chain(id) then
        local at, steps = Q.ChainStep(id)
        sub = ("Step %d of %d in %s"):format(at, steps, Q.Chain(id).name)
    end
    local home = Q.Zone(id)
    if zone and home and home ~= zone then sub = sub .. (sub ~= "" and "  -  " or "") .. home.name end
    row.where:SetWidth(textW)
    row.where:SetText(sub)
    row.where:SetShown(sub ~= "")
    local titleH = math.ceil(row.title:GetStringHeight())
    local h = ROW_TOP + titleH + ROW_BOTTOM
    if sub ~= "" then h = h + LINE_GAP + math.ceil(row.where:GetStringHeight()) end
    row.trunk:SetShown(step)
    row.branch:SetShown(step)
    if step then SetTree(row, first, last, ROW_TOP + math.floor(titleH / 2)) else row.elbow:Hide() end
    return h
end

-------------------------------------------------------------------------------
--  The pages
-------------------------------------------------------------------------------
local Draw = {}
local byContinent = {}
local entries, follow = {}, {}   -- a zone's chains and quests; a chain's follow-up quests

-- A chain by its first quest's level and name, as a quest by its own.
local function EntryLevel(entry)
    if type(entry) == "table" then return entry.level, entry.name end
    return Q.Level(entry), Q.Name(entry)
end

local function EntryOrder(a, b)
    local la, na = EntryLevel(a)
    local lb, nb = EntryLevel(b)
    if la ~= lb then return la < lb end
    return na < nb
end

-- All Zones lists each continent's zones alphabetically, a leading "The" left out: The
-- Barrens among the B's.
local function SortName(z)
    return (z.name:gsub("^The ", ""))
end

local function ZoneOrder(a, b)
    return SortName(a) < SortName(b)
end

local function AllZones()
    zone = nil
    scroll:SetVerticalScroll(0)
    view:Redraw()
end

local function DrawAllZones(self)
    local n, total = Q.Progress()
    self:Add("hero", "All zones", n, total, ("%d%% of every zone quest for your character"):format(Percent(n, total)))
    self:Space(8)
    wipe(byContinent)
    for _, z in ipairs(Q.Zones()) do
        local _, zt = Q.ZoneProgress(z)
        if zt > 0 then
            local name = CONTINENTS[z.continent] or ELSEWHERE
            byContinent[name] = byContinent[name] or {}
            table.insert(byContinent[name], z)
        end
    end
    for _, name in ipairs({ CONTINENTS[0], CONTINENTS[1], ELSEWHERE }) do
        local list = byContinent[name]
        if list then
            table.sort(list, ZoneOrder)
            self:Section(name, #list)
            for i, z in ipairs(list) do self:Add("zone", z, i % 2 == 0) end
        end
    end
end

local function DrawZone(self)
    local hideDone = S.Get("hideDone")
    self:SectionLink(zone.name, "All Zones", AllZones)
    self:Space(8)
    local n, total, low, high = Q.ZoneProgress(zone)
    self:Add("hero", zone.name, n, total, Levels(low, high))
    self:Space(8)
    -- One list, lowest level first: a quest in no chain on its own; a chain as its first quest
    -- with every follow-up under it, the whole chain on one stripe.
    local chains, singles = Q.ZoneLists(zone)
    wipe(entries)
    for _, chain in ipairs(chains) do
        local at, steps = Q.ChainAt(chain)
        if not (hideDone and at > steps) then entries[#entries + 1] = chain end
    end
    for _, id in ipairs(singles) do
        if not (hideDone and Q.Done(id)) then entries[#entries + 1] = id end
    end
    table.sort(entries, EntryOrder)
    if #entries > 0 then self:Section("Quests", #entries) end
    for i, entry in ipairs(entries) do
        local stripe = i % 2 == 0
        if type(entry) == "table" then
            for _, id in ipairs(entry.steps[1]) do self:Add("quest", id, "head", nil, nil, stripe) end
            wipe(follow)
            for s = 2, #entry.steps do
                for _, id in ipairs(entry.steps[s]) do follow[#follow + 1] = id end
            end
            for f, id in ipairs(follow) do self:Add("quest", id, "step", f == 1, f == #follow, stripe) end
        else
            self:Add("quest", entry, nil, nil, nil, stripe)
        end
    end
    if #entries == 0 then
        self:Note(total > 0 and "Every quest here is done." or "No quests here for your character.")
    end
end

-- A zone picked from the search: the search is cleared, which redraws, on that zone.
local function OpenFound(picked)
    zone = picked
    window.search:SetText("")
    window.search:ClearFocus()
    scroll:SetVerticalScroll(0)
    view:Redraw()
end

-- Every quest whose name or quest giver holds the text, under its zone with a link to it.
local function DrawSearch(self, text)
    local zones, n = Q.Search(text, SEARCH_MAX)
    if n == 0 then
        self:Note(("No quest or quest giver for your character holds \"%s\"."):format(text))
        return
    end
    for _, entry in ipairs(zones) do
        self:Add("section", entry.zone.name, #entry.ids, nil, nil, "Open", OpenFound, entry.zone)
        for i, id in ipairs(entry.ids) do self:Add("quest", id, nil, nil, nil, i % 2 == 0) end
        self:Space(St.SECTION_SPACE)
    end
    if n > SEARCH_MAX then
        self:Note(("The first %d of %d; type more to narrow it down."):format(SEARCH_MAX, n))
    end
end

local function SearchText()
    return window.search and strtrim(window.search:GetText() or ""):lower() or ""
end

function Draw:Redraw()
    self:Clear()
    Q.Refresh()
    local text = SearchText()
    if text ~= "" then
        local open = zone
        zone = nil   -- every zone at once: no row names its zone as not the one open
        DrawSearch(self, text)
        zone = open
    elseif zone then
        DrawZone(self)
    else
        DrawAllZones(self)
    end
    self:Fit(EVENTS)
end

local function Kinds()
    if kinds then return kinds end
    kinds = Shared.View.NewKinds()
    kinds.hero = { New = NewHero, Set = SetHero }
    kinds.zone = { New = NewZone, Set = SetZone }
    kinds.quest = { New = NewQuest, Set = SetQuest }
    return kinds
end

local function PickTab(key)
    tab = key
    Parts.PaintTabs(window.tabs, tab)
    scroll:SetVerticalScroll(0)
    view:Redraw()
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "completoWindow")
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    local close = Parts.TitleBar(window, "Completo",
        "Everything there is to do, and how much of it you have done.", PAGE)
    local _, opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.opacity = opacity
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")

    local left, top = CARD + INSET, HEADER + CARD + PAD + 4
    window.tabs = Parts.Tabs(window, TABS_W, TABS, PickTab)
    window.tabs:SetPoint("TOPLEFT", left, -top)
    window.search = Parts.SearchBox(window, "Search quests or quest givers", function()
        if window:IsShown() then
            scroll:SetVerticalScroll(0)
            view:Redraw()
        end
    end)
    window.search:SetSize(SEARCH_W, St.SEARCH_H)
    window.search:SetPoint("RIGHT", window, "TOPRIGHT", -(CARD + INSET), -(top + TAB_H / 2))
    top = top + TAB_H + TAB_GAP + 8
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    view = Shared.View.New(scroll, Kinds(), Draw)
    scroll:SetScrollChild(view)
    -- Dragged bigger or smaller: the rows follow the new width, redrawn once it settles.
    local function FitView()
        local width = window:GetWidth() - left - CARD - SCROLLBAR - INSET
        if view:GetWidth() == width then return end
        view:SetWidth(width)
        if window:IsShown() then view:QueueRedraw() end
    end
    view:SetWidth(WIDTH - left - CARD - SCROLLBAR - INSET)
    Parts.Resizable(window, "completoWindowSize", MIN_W, MIN_H, FitView)
    FitView()
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
    Q.Refresh()
    local n, total = Q.Progress()
    window.note.text:SetText(("%d of %d zone quests done"):format(n, total))
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
    Parts.PaintTabs(window.tabs, tab)
end

S.OnChange(function(key)
    if not (window and window:IsShown()) then return end
    if key == "windowAlpha" then Paint() end
    if key == "windowScale" then window:SetScale(ns.UIScale() * S.Get("windowScale")) end
    if key == "hideDone" then view:Redraw() end
end)

hooksecurefunc(ns, "Apply", function()
    if window and window:IsShown() then
        window:SetScale(ns.UIScale() * S.Get("windowScale"))
        Paint()
        view:Redraw()
    end
end)

-- which: "quests" to open on that tab; else the one it was on. Opens on the zone you are in
-- when it has quests, else where it was.
function ns.OpenCompletoWindow(which)
    if which then tab = which end
    if not window then Build() end
    zone = Q.CurrentZone() or zone
    window:SetScale(ns.UIScale() * S.Get("windowScale"))
    window:Show()
    Paint()
    scroll:SetVerticalScroll(0)
    view:Redraw()
end

function ns.ToggleCompletoWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenCompletoWindow() end
end

-- Its key (Key Bindings > Naowh Forever > Open Completo), over the core's switched-off stub.
function NaowhForever_ToggleCompleto()
    ns.ToggleCompletoWindow()
end

-------------------------------------------------------------------------------
--  Shift-L by default. Bindings.xml has no default key, so it never binds while Completo is
--  off. Once per character, while Completo is on, Shift-L is bound to it if nothing else
--  has it and Completo has no key yet; else a line in chat says where to bind it. Never
--  again after that, so a key you change or clear stays as you left it.
-------------------------------------------------------------------------------
local ACTION, DEFAULT_KEY = "NAOWHFOREVER_COMPLETO", "SHIFT-L"

local function DefaultKey()
    if not S.Get("enabled") or InCombatLockdown() then return end
    local account = ns.AccountSettings()
    account.completoKeySet = account.completoKeySet or {}
    local char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    if account.completoKeySet[char] then return end
    account.completoKeySet[char] = true
    if GetBindingKey(ACTION) then return end
    local taken = GetBindingAction(DEFAULT_KEY)
    if taken == "" then
        SetBinding(DEFAULT_KEY, ACTION)
        SaveBindings(GetCurrentBindingSet())
        ns.Print("Shift-L now opens Completo. Change it in Completo's settings or Key Bindings.")
    else
        ns.Print(("Shift-L is already %s, so Completo has no key. Pick one in its settings."):format(
            GetBindingName(taken)))
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" then DefaultKey() end
end)

local keyBoot = CreateFrame("Frame")
keyBoot:RegisterEvent("PLAYER_LOGIN")
keyBoot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    DefaultKey()
end)
