-------------------------------------------------------------------------------
--  NaowhForever_DiscoveryWindow.lua -- Discovery's own window (/nfdiscovery, its minimap and
--  top bar button, the tracker's title, Open Discovery on its settings page): your progress
--  toward the Friend of the Library rewards and who takes the books, then every book for your
--  faction by zone, where it is, whether you carry it, and a waypoint to it.
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
local PAGE = "Discovery/Settings"
local CARD = 6
local TABS_W = 220
local HERO_H = 96
local BAR_H = 6
local ROW_TOP, ROW_BOTTOM, LINE_GAP = 6, 8, 3
local LEVEL_W = 24
local TICK = 14
local PIN_RIGHT = 10
local STATUS_W = 110
local STATUS_GAP = 10
local STRIPE, HOVER = 0.025, 0.04
local TRACK_RGB = 0.16
local STORED_RGB = { r = 1, g = 0.82, b = 0 }
local MISSING_RGB = { r = 0.97, g = 0.44, b = 0.44 }
local EVENTS = { "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "PLAYERBANKSLOTS_CHANGED" }

local FILTERS = {
    { key = "find", label = "To Find", tip = "The books you have not handed in yet." },
    { key = "all", label = "All Books", tip = "Every book for your faction, handed in or not." },
}

local window, scroll, view, kinds
local filter = "find"

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
    hero.track = ns.Solid(hero, "ARTWORK", { r = TRACK_RGB, g = TRACK_RGB, b = TRACK_RGB }, 1)
    hero.track:SetPoint("TOPLEFT", hero.count, "BOTTOMLEFT", 0, -10)
    hero.track:SetPoint("RIGHT", -16, 0)
    hero.track:SetHeight(BAR_H)
    hero.fill = ns.Solid(hero, "ARTWORK", T.accent, 1)
    hero.fill:SetDrawLayer("ARTWORK", 1)
    hero.fill:SetPoint("TOPLEFT", hero.track, "TOPLEFT")
    hero.fill:SetHeight(BAR_H)
    hero.marks = {}
    for i, goal in ipairs(ns.LibraryGoals) do
        local mark = ns.Solid(hero, "OVERLAY", T.fg, 1)
        mark:SetSize(2, BAR_H + 6)
        local label = ns.Font(hero, 10, nil, T.muted)
        label:SetPoint("TOP", mark, "BOTTOM", 0, -2)
        label:SetText(goal.books)
        hero.marks[i] = { mark = mark, label = label, goal = goal }
    end
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
        or "Both rewards earned")
    local librarian = ns.LibraryTurnIns.librarian[Library.Side()]
    hero.who:SetText("Hand them to " .. ns.Color("fg", librarian.name) .. "\n" .. librarian.place)
    local width = hero:GetWidth() - 32
    local share = total > 0 and math.min(1, done / total) or 0
    hero.fill:SetWidth(math.max(1, width * share))
    hero.fill:SetShown(share > 0)
    for _, m in ipairs(hero.marks) do
        local x = total > 0 and width * math.min(1, m.goal.books / total) or 0
        m.mark:ClearAllPoints()
        m.mark:SetPoint("CENTER", hero.track, "LEFT", x, 0)
        local reached = done >= m.goal.books
        local c = reached and T.accent or T.fg
        m.mark:SetColorTexture(c.r, c.g, c.b, 1)
        local lc = reached and T.accentSoft or T.muted
        m.label:SetTextColor(lc.r, lc.g, lc.b)
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

local function Shows(book)
    return Library.ForMe(book) and (filter == "all" or not Library.Done(book))
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
        self:Note("Every book for your faction is handed in. Switch to All Books to see them.")
    end
    self:Fit(EVENTS)
end

local function Kinds()
    if kinds then return kinds end
    kinds = Shared.View.NewKinds()
    kinds.hero = { New = NewHero, Set = SetHero }
    kinds.book = { New = NewBook, Set = SetBook }
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

function ns.OpenDiscoveryWindow()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Paint()
    view:Redraw()
end

function ns.ToggleDiscoveryWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenDiscoveryWindow() end
end
