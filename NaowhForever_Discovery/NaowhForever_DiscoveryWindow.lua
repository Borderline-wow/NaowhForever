-------------------------------------------------------------------------------
--  NaowhForever_DiscoveryWindow.lua -- Discovery's own window (/nfdiscovery, its minimap and
--  top bar button, the tracker's title, Open Discovery on its settings page): your progress
--  toward the Friend of the Library rewards and who takes the books, then every book for your
--  faction by zone, where it is, whether you carry it, and a waypoint to it. The progress is a
--  road, as the Training Planner's: a short stripe for every book, blue for those handed in,
--  YOU over where you are, and a dot at each reward quest (10, 20, 25) with its choice of
--  rewards under it. A Sleeping Bag tab lists the Cozy Sleeping Bag's hidden chain instead:
--  how far along you are and its reward, then every step, what to click, where and how to get
--  there, with a waypoint.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.DiscoverySettings
local Library = ns.Library
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 760, 720
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR, TAB_H, TAB_GAP = St.CONTENT_INSET, St.SCROLLBAR, St.TAB_H, St.TAB_GAP
local PAGE = "Discovery/Library Books"
local CARD = 6
local TABS_W = 260
local HERO_H = 166
local BAR_H = 4                 -- the road's stripes
local SEGMENT_GAP = 2           -- between two books' stripes
local YOU_GAP = 4               -- the YOU tag over the road, as the Training Planner's
local DOT = 12                  -- a reward quest's dot on it
local DOT_EDGE = 2
local REWARD = 26               -- a reward's icon, under its dot
local REWARD_GAP = 4
local ROW_TOP, ROW_BOTTOM, LINE_GAP = 6, 8, 3
local LEVEL_W = 24
local TICK = 14
local PIN_RIGHT = 10
local STATUS_W = 110
local STATUS_GAP = 10
local STRIPE, HOVER = 0.025, 0.04
local STORED_RGB = { r = 1, g = 0.82, b = 0 }
local MISSING_RGB = { r = 0.97, g = 0.44, b = 0.44 }
local EVENTS = { "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYERBANKSLOTS_CHANGED" }

local FILTERS = {
    { key = "books", label = "Library Books", tip = "Every book for your faction, a tick on those handed in." },
    { key = "bag", label = "Sleeping Bag", tip = "The Cozy Sleeping Bag's hidden quest chain, step by step." },
}

local window, scroll, view, kinds
local filter = "books"

local function Opacity()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("windowAlpha", value / 100)
end

local function Status(book)
    if Library.Done(book) then return "Handed in", T.muted end
    local stored = Library.Stored(book)
    if stored == "bags" then return "In bags", STORED_RGB end
    if stored == "bank" then return "In bank", STORED_RGB end
    return "Missing", MISSING_RGB
end

local function LibrarianClicked()
    Library.WaypointNpc(ns.LibraryTurnIns.librarian[Library.Side()])
end

-------------------------------------------------------------------------------
--  The road: your books to every reward
-------------------------------------------------------------------------------
-- A reward quest's state, in words and colour (Library.GoalState).
local GOAL_STATE = {
    claimed = { "Handed in", T.muted }, ready = { "Ready to hand in", St.HAVE_RGB },
    level = { "Enough books; at level %d", STORED_RGB }, ahead = { "%d to go", T.fg },
}

local function DotEnter(dot)
    local goal, done = dot.goal, dot.done
    GameTooltip:SetOwner(dot, "ANCHOR_TOP")
    GameTooltip:SetText(goal.name, 1, 1, 1)
    GameTooltip:AddLine(("%d books"):format(goal.books), T.muted.r, T.muted.g, T.muted.b)
    if goal.level then
        GameTooltip:AddLine(("Needs level %d"):format(goal.level), T.muted.r, T.muted.g, T.muted.b)
    end
    local state = Library.GoalState(goal, done)
    local words, c = GOAL_STATE[state][1], GOAL_STATE[state][2]
    if state == "level" then words = words:format(goal.level) end
    if state == "ahead" then words = words:format(goal.books - done) end
    GameTooltip:AddLine(words, c.r, c.g, c.b)
    if goal.reported then
        GameTooltip:AddLine("The book count is what players report; not confirmed yet.", T.muted.r, T.muted.g,
            T.muted.b, true)
    end
    GameTooltip:AddLine("Pick one of the rewards under it.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, true)
    GameTooltip:Show()
end

local function RewardEnter(icon)
    GameTooltip:SetOwner(icon, "ANCHOR_TOP")
    GameTooltip:SetItemByID(icon.item)
    GameTooltip:Show()
end

local function Disc(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetTexture(St.ROUND, "CLAMP", "CLAMP", "TRILINEAR")
    tex:SetTexelSnappingBias(0)
    tex:SetSnapToPixelGrid(false)
    return tex
end

-- A reward quest on the road: its dot, its count under the line, its rewards under that.
local function NewMilestone(hero, goal)
    local m = { goal = goal }
    m.dot = CreateFrame("Frame", nil, hero)
    m.dot:SetSize(DOT, DOT)
    m.dot:SetFrameLevel(hero:GetFrameLevel() + 2)
    m.dot.edge = Disc(m.dot, "ARTWORK", 1)
    m.dot.edge:SetAllPoints()
    m.dot.fill = Disc(m.dot, "ARTWORK", 2)
    m.dot.fill:SetPoint("TOPLEFT", DOT_EDGE, -DOT_EDGE)
    m.dot.fill:SetPoint("BOTTOMRIGHT", -DOT_EDGE, DOT_EDGE)
    m.dot.goal = goal
    m.dot:EnableMouse(true)
    m.dot:SetScript("OnEnter", DotEnter)
    m.dot:SetScript("OnLeave", GameTooltip_Hide)
    m.label = ns.Font(hero, 10, nil, T.muted)
    m.label:SetPoint("TOP", m.dot, "BOTTOM", 0, -3)
    m.label:SetText(goal.books)
    m.icons = {}
    for i, reward in ipairs(goal.rewards) do
        local icon = Parts.ItemIcon(hero, REWARD)
        icon.texture:SetTexture(C_Item.GetItemIconByID(reward[1]) or 134400)
        icon.item = reward[1]
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", RewardEnter)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        m.icons[i] = icon
    end
    return m
end

local function NewHero(parent)
    local hero = CreateFrame("Frame", nil, parent)
    ns.Solid(hero, "BACKGROUND", T.fg, St.CARD_FILL):SetAllPoints()
    ns.Border(hero, St.BORDER_RGB)
    hero.kicker = ns.Font(hero, 10, nil, T.accentSoft)
    hero.kicker:SetPoint("TOPLEFT", 16, -14)
    hero.kicker:SetText("FRIEND OF THE LIBRARY")
    hero.count = ns.Font(hero, 22, nil, T.fg)
    hero.count:SetPoint("TOPLEFT", hero.kicker, "BOTTOMLEFT", 0, -4)
    hero.goal = ns.Font(hero, 12, nil, T.muted)
    hero.goal:SetPoint("BOTTOMLEFT", hero.count, "BOTTOMRIGHT", 10, 3)
    -- Where the road runs, unseen: its stripes and dots are placed along it.
    hero.track = CreateFrame("Frame", nil, hero)
    hero.track:SetPoint("TOPLEFT", hero.count, "BOTTOMLEFT", 0, -26)
    hero.track:SetPoint("RIGHT", -16, 0)
    hero.track:SetHeight(BAR_H)
    hero.segments = {}
    hero.you = ns.Font(hero, 11, nil, T.accent)
    hero.you:SetText("YOU")
    hero.marks = {}
    for i, goal in ipairs(ns.LibraryGoals) do hero.marks[i] = NewMilestone(hero, goal) end
    hero.pin = Parts.IconButton(hero, LibrarianClicked, St.PIN, 0, "Waypoint")
    hero.pin.hint = "To who takes the books."
    hero.pin:SetPoint("TOPRIGHT", -10, -14)
    hero.who = ns.Font(hero, 11, nil, T.muted)
    hero.who:SetPoint("TOPRIGHT", hero.pin, "TOPLEFT", -4, 0)
    hero.who:SetJustifyH("RIGHT")
    return hero
end

local function SetHero(hero)
    local done, total = Library.Progress()
    local goal = Library.NextGoal()
    hero.count:SetText(("%d / %d"):format(done, total))
    hero.goal:SetText(goal and ("%d to go for %s"):format(math.max(0, goal.books - done), goal.name)
        or "Every reward earned")
    local librarian = ns.LibraryTurnIns.librarian[Library.Side()]
    hero.who:SetText("Hand them to " .. ns.Color("fg", librarian.name) .. "\n" .. librarian.place)
    local width = hero:GetWidth() - 32
    -- A stripe per book, a small gap between two: blue for those handed in, grey for the rest.
    local step = total > 0 and width / total or 0
    for i = 1, total do
        local seg = hero.segments[i]
        if not seg then
            seg = hero:CreateTexture(nil, "ARTWORK")
            seg:SetHeight(BAR_H)
            hero.segments[i] = seg
        end
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", hero.track, "LEFT", (i - 1) * step, 0)
        seg:SetWidth(math.max(1, step - SEGMENT_GAP))
        if i <= done then
            seg:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
        else
            seg:SetColorTexture(T.line.r, T.line.g, T.line.b, 1)
        end
        seg:Show()
    end
    for i = total + 1, #hero.segments do hero.segments[i]:Hide() end
    -- YOU over the end of the last book handed in (the road's start before the first).
    hero.you:ClearAllPoints()
    hero.you:SetPoint("BOTTOM", hero.track, "LEFT", math.max(0, done * step - SEGMENT_GAP / 2), DOT / 2 + YOU_GAP)
    for _, m in ipairs(hero.marks) do
        local x = total > 0 and width * math.min(1, m.goal.books / total) or 0
        m.dot.done = done
        m.dot:ClearAllPoints()
        m.dot:SetPoint("CENTER", hero.track, "LEFT", x, 0)
        -- Handed in: filled grey. Ready (or waiting on your level): filled accent. Ahead: a ring.
        local state = Library.GoalState(m.goal, done)
        local edge, inside = T.muted, T.bg
        if state == "claimed" then
            edge, inside = T.line, T.line
        elseif state == "ready" or state == "level" then
            edge, inside = T.accent, T.accent
        end
        m.dot.edge:SetVertexColor(edge.r, edge.g, edge.b, 1)
        m.dot.fill:SetVertexColor(inside.r, inside.g, inside.b, 1)
        local lc = state == "ahead" and T.muted or T.accentSoft
        m.label:SetTextColor(lc.r, lc.g, lc.b)
        -- The rewards in a row under its count, centred on the dot; once handed in, the one you
        -- have in colour and the others greyed.
        local n = #m.icons
        local rowW = n * REWARD + (n - 1) * REWARD_GAP
        for i, icon in ipairs(m.icons) do
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", m.label, "BOTTOM", -rowW / 2 + (i - 1) * (REWARD + REWARD_GAP), -6)
            local owned = C_Item.GetItemCount(icon.item, true) > 0
            local grey = state == "claimed" and not owned
            icon.texture:SetDesaturated(grey)
            icon.texture:SetAlpha(grey and 0.5 or 1)
        end
    end
    return HERO_H
end

local function Share(owner, row)
    local spot = row.spot
    if spot then Parts.SharePlace(owner, "Share where it is", row.book.name, spot[1], spot[2], spot[3], spot[4]) end
end

local function PinClicked(button, mouse)
    local row = button:GetParent()
    if mouse == "RightButton" then return Share(button, row) end
    Library.WaypointBook(row.book, row.spot)
end

local function BookEnter(row)
    row.hover:Show()
    if not Parts.Tip(row, "ANCHOR_RIGHT") then return end
    local book, m = row.book, T.muted
    GameTooltip:SetText(book.name, 1, 1, 1)
    if row.spot then
        GameTooltip:AddLine(Library.ZoneName(row.spot[1]) .. ", " .. Library.Where(row.spot), m.r, m.g, m.b, true)
    end
    local npc = Library.TurnIn(book)
    GameTooltip:AddDoubleLine("Hand in to", npc.name, m.r, m.g, m.b, 1, 1, 1)
    local text, color = Status(book)
    GameTooltip:AddDoubleLine("Status", text, m.r, m.g, m.b, color.r, color.g, color.b)
    if row.spot and not Library.Done(book) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Pin: waypoint    Right-click: Share", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    end
    GameTooltip:Show()
end

local function BookLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function BookMouseUp(row, button)
    if button == "RightButton" then Share(row, row) end
end

local function NewBook(parent)
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
    row.pin = Parts.IconButton(row, PinClicked, St.PIN, 0, "Waypoint")
    row.pin.hint = "Right-click to share it in chat."
    row.pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.pin:SetPoint("RIGHT", -PIN_RIGHT, 0)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(St.TICK, nil, nil, "TRILINEAR")
    row.tick:SetSize(TICK, TICK)
    row.tick:SetPoint("TOPLEFT", St.INDENT, -(ROW_TOP + 1))
    row.tick:SetVertexColor(St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b)
    row.level = ns.Font(row, 12)
    row.level:SetPoint("TOPLEFT", St.INDENT, -(ROW_TOP + 1))
    row.level:SetWidth(LEVEL_W)
    row.level:SetJustifyH("LEFT")
    row.title = ns.Font(row, 13, nil, T.fg)
    row.title:SetPoint("TOPLEFT", St.INDENT + LEVEL_W + 4, -ROW_TOP)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.where = ns.Font(row, 11, nil, T.muted)
    row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -LINE_GAP)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(true)
    row.status = ns.Font(row, 11, nil, T.fg)
    row.status:SetPoint("RIGHT", row.pin, "LEFT", -STATUS_GAP, 0)
    row.status:SetJustifyH("RIGHT")
    row.bag = row:CreateTexture(nil, "ARTWORK")
    row.bag:SetTexture(St.BAG, nil, nil, "TRILINEAR")
    row.bag:SetSize(TICK, TICK)
    row.bag:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", BookEnter)
    row:SetScript("OnLeave", BookLeave)
    row:SetScript("OnMouseUp", BookMouseUp)
    return row
end

local function SetBook(row, book, spot, sub, stripe)
    row.book, row.spot = book, spot
    row.stripe:SetShown(stripe)
    row.hover:Hide()
    local done = Library.Done(book)
    row.pin:SetShown(spot ~= nil and not done)
    row.tick:SetShown(done)
    row.level:SetShown(not done)
    local c = GetQuestDifficultyColor(book.tier)
    row.level:SetText(book.tier)
    row.level:SetTextColor(c.r, c.g, c.b)
    local text, color = Status(book)
    row.status:SetText(text)
    row.status:SetTextColor(color.r, color.g, color.b)
    row.bag:SetShown(Library.Carried(book))
    row.bag:SetVertexColor(color.r, color.g, color.b)
    local textW = row:GetWidth() - St.INDENT - LEVEL_W - 4 - PIN_RIGHT - STATUS_W
    row.title:SetWidth(textW)
    row.title:SetText(book.name)
    local tc = done and T.muted or T.fg
    row.title:SetTextColor(tc.r, tc.g, tc.b)
    row.where:SetWidth(textW)
    row.where:SetText(sub)
    return ROW_TOP + math.ceil(row.title:GetStringHeight()) + LINE_GAP + math.ceil(row.where:GetStringHeight())
        + ROW_BOTTOM
end

-------------------------------------------------------------------------------
--  The Sleeping Bag tab
-------------------------------------------------------------------------------
local Bag = ns.SleepingBagChain

-- Its card: how far along you are, the level it needs, and the bag itself.
local function NewBagHero(parent)
    local hero = CreateFrame("Frame", nil, parent)
    ns.Solid(hero, "BACKGROUND", T.fg, St.CARD_FILL):SetAllPoints()
    ns.Border(hero, St.BORDER_RGB)
    hero.kicker = ns.Font(hero, 10, nil, T.accentSoft)
    hero.kicker:SetPoint("TOPLEFT", 16, -14)
    hero.kicker:SetText("SLEEPING BAG")
    hero.count = ns.Font(hero, 22, nil, T.fg)
    hero.count:SetPoint("TOPLEFT", hero.kicker, "BOTTOMLEFT", 0, -4)
    hero.next = ns.Font(hero, 12, nil, T.muted)
    hero.next:SetPoint("BOTTOMLEFT", hero.count, "BOTTOMRIGHT", 10, 3)
    hero.about = ns.Font(hero, 11, nil, T.muted)
    hero.about:SetPoint("TOPLEFT", hero.count, "BOTTOMLEFT", 0, -8)
    hero.about:SetPoint("RIGHT", -80, 0)
    hero.about:SetJustifyH("LEFT")
    hero.about:SetWordWrap(true)
    hero.reward = Parts.ItemIcon(hero, 36)
    hero.reward:SetPoint("TOPRIGHT", -16, -16)
    hero.reward.item = ns.SleepingBag.item
    hero.reward.texture:SetTexture(C_Item.GetItemIconByID(ns.SleepingBag.item) or 134400)
    hero.reward:EnableMouse(true)
    hero.reward:SetScript("OnEnter", RewardEnter)
    hero.reward:SetScript("OnLeave", GameTooltip_Hide)
    return hero
end

local function SetBagHero(hero)
    local steps = Bag.Steps()
    local step, at = Bag.Current()
    local done = (at or #steps + 1) - 1
    hero.count:SetText(("%d / %d"):format(done, #steps))
    hero.next:SetText(step and ("Next: %s"):format(Bag.Name(step)) or "You have the Cozy Sleeping Bag")
    local about = "A hidden quest chain across Azeroth: click each thing in the world in turn. It gives a lot "
        .. "of experience, and ends in the Cozy Sleeping Bag; rest in it for a bonus to experience."
    if not Bag.Level() then
        about = about .. ns.Color("fg", (" Needs level %d."):format(ns.SleepingBag.level))
    end
    hero.about:SetText(about)
    return 26 + math.ceil(hero.count:GetStringHeight()) + 8 + math.ceil(hero.about:GetStringHeight()) + 16
end

local function StepPin(button, mouse)
    local row = button:GetParent()
    if mouse == "RightButton" then
        local step = row.step
        return Parts.SharePlace(button, "Share where it is", step.object, step.map, step.x, step.y, step.place)
    end
    Bag.Waypoint(row.step)
end

local function StepEnter(row)
    row.hover:Show()
    if not Parts.Tip(row, "ANCHOR_RIGHT") then return end
    local step, m = row.step, T.muted
    GameTooltip:SetText(Bag.Name(step), 1, 1, 1)
    GameTooltip:AddLine(Bag.Where(step), m.r, m.g, m.b, true)
    if step.tip then GameTooltip:AddLine(step.tip, 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Pin: waypoint    Right-click it: Share", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function NewStep(parent)
    local row = NewBook(parent)
    row:SetScript("OnEnter", StepEnter)
    row:SetScript("OnMouseUp", nil)
    row.pin:SetScript("OnClick", StepPin)
    return row
end

-- A step: its number (a tick once done), what to click and where with how to get there, and
-- where it stands on the right.
local function SetStep(row, step, number, state, stripe)
    row.step = step
    row.stripe:SetShown(stripe)
    row.hover:Hide()
    local done = state == "done"
    row.pin:SetShown(not done)
    row.tick:SetShown(done)
    row.level:SetShown(not done)
    row.level:SetText(number)
    row.level:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
    local words = state == "done" and "Done" or state == "now" and "Next" or state == "optional" and "Optional"
        or "Later"
    local color = state == "now" and St.HAVE_RGB or T.muted
    row.status:SetText(words)
    row.status:SetTextColor(color.r, color.g, color.b)
    row.bag:Hide()
    local textW = row:GetWidth() - St.INDENT - LEVEL_W - 4 - PIN_RIGHT - STATUS_W
    row.title:SetWidth(textW)
    row.title:SetText(Bag.Name(step))
    local tc = done and T.muted or T.fg
    row.title:SetTextColor(tc.r, tc.g, tc.b)
    row.where:SetWidth(textW)
    row.where:SetText(Bag.Where(step) .. (step.tip and not done and ("\n" .. step.tip) or ""))
    return ROW_TOP + math.ceil(row.title:GetStringHeight()) + LINE_GAP + math.ceil(row.where:GetStringHeight())
        + ROW_BOTTOM
end

local function DrawBag(self)
    self:Add("bagHero")
    self:Space(8)
    local steps = Bag.Steps()
    local _, at = Bag.Current()
    self:Section("Steps", #steps)
    for i, step in ipairs(steps) do
        local state = (not at or i < at) and "done" or i == at and "now" or "later"
        self:Add("step", step, i, state, i % 2 == 0)
    end
    local side = ns.SleepingBag.optional
    self:Section("Optional")
    local sideDone = C_QuestLog.IsQuestFlaggedCompleted(side.done)
    self:Add("step", side, "", sideDone and "done" or "optional", false)
    self:Fit(EVENTS)
end

local function Shows(book)
    return Library.ForMe(book)
end

local Draw = {}

local zoneBooks = {}

local function ZoneOrder()
    local order, seen = {}, {}
    for _, book in ipairs(ns.LibraryBooks) do
        for _, spot in ipairs(book.spots) do
            if not seen[spot[1]] then
                seen[spot[1]] = true
                order[#order + 1] = spot[1]
            end
        end
    end
    return order
end

local zones

function Draw:Redraw()
    zones = zones or ZoneOrder()
    self:Clear()
    if filter == "bag" then return DrawBag(self) end
    self:Add("hero")
    self:Space(8)
    local shown = 0
    for i = 1, #zones do
        local mapID = zones[i]
        wipe(zoneBooks)
        for _, book in ipairs(ns.LibraryBooks) do
            if Shows(book) then
                for _, spot in ipairs(book.spots) do
                    if spot[1] == mapID then
                        zoneBooks[#zoneBooks + 1] = book
                        zoneBooks[#zoneBooks + 1] = spot
                    end
                end
            end
        end
        local n = #zoneBooks / 2
        if n > 0 then
            self:Section(Library.ZoneName(mapID), n)
            for j = 1, n do
                local book, spot = zoneBooks[j * 2 - 1], zoneBooks[j * 2]
                local sub = Library.Where(spot) .. "  -  " .. Library.TurnIn(book).name
                self:Add("book", book, spot, sub, j % 2 == 0)
            end
            shown = shown + n
        end
    end
    local unplaced = 0
    for _, book in ipairs(ns.LibraryBooks) do
        if book.unplaced and Shows(book) then
            unplaced = unplaced + 1
            if unplaced == 1 then self:Section("Not found yet") end
            self:Add("book", book, nil, "Nobody has found this one on Forever yet.", unplaced % 2 == 0)
        end
    end
    if shown + unplaced == 0 then
        self:Note("No books for your faction yet.")
    end
    self:Fit(EVENTS)
end

local function Kinds()
    if kinds then return kinds end
    kinds = Shared.View.NewKinds()
    kinds.hero = { New = NewHero, Set = SetHero }
    kinds.book = { New = NewBook, Set = SetBook }
    kinds.bagHero = { New = NewBagHero, Set = SetBagHero }
    kinds.step = { New = NewStep, Set = SetStep }
    return kinds
end

local function PickFilter(key)
    filter = key
    Parts.PaintTabs(window.filters, filter)
    scroll:SetVerticalScroll(0)
    view:Redraw()
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "discoveryWindow")
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    local close = Parts.TitleBar(window, "Discovery",
        "Library books to find around Azeroth, and who to hand them to.", PAGE)
    local _, opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.opacity = opacity
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")

    local left, top = CARD + INSET, HEADER + CARD + PAD + 4
    window.filters = Parts.Tabs(window, TABS_W, FILTERS, PickFilter)
    window.filters:SetPoint("TOPLEFT", left, -top)
    top = top + TAB_H + TAB_GAP + 8
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    view = Shared.View.New(scroll, Kinds(), Draw)
    view:SetWidth(WIDTH - left - CARD - SCROLLBAR - INSET)
    scroll:SetScrollChild(view)
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
    local _, total = Library.Progress()
    window.note.text:SetText(total .. " books for your faction")
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
    Parts.PaintTabs(window.filters, filter)
end

S.OnChange(function(key)
    if key == "windowAlpha" and window and window:IsShown() then Paint() end
end)

hooksecurefunc(ns, "Apply", function()
    if window and window:IsShown() then
        Paint()
        view:Redraw()
    end
end)

-- tab: "books" or "bag" to open it on that tab; else the one it was on.
function ns.OpenDiscoveryWindow(tab)
    if tab then filter = tab end
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Paint()
    view:Redraw()
end

function ns.ToggleDiscoveryWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenDiscoveryWindow() end
end
