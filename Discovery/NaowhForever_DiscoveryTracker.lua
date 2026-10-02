-------------------------------------------------------------------------------
--  NaowhForever_DiscoveryTracker.lua -- the library book tracker: in a zone with books you
--  still need, a small window lists them with a waypoint for each. It pops up on entering
--  such a zone; Always Show keeps it up in every zone.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.DiscoverySettings
local L = ns.Library
local T = ns.THEME

local GOLD = "|cffffd100"
local BLACK = { r = 0, g = 0, b = 0 }
local BAR_BG = { r = 0x14 / 255, g = 0x16 / 255, b = 0x19 / 255 }
local READY = { r = 0x19 / 255, g = 1, b = 0x19 / 255 }

-- NUDGE lifts the text inside its row: the font leaves room above its capitals.
local PANEL_W, BODY_W, PIN, INSET, GAP, NUDGE = 300, 284, 18, 4, 5, 2

local panel, zoneEvents, shownEvents
local dismissedZone   -- the zone the X closed it in, until you leave
local pickedZone      -- the zone the dropdown is listing, while it shows

local function On()
    return S.Get("enabled") and S.Get("tracker")
end

local function SetPinTexture(tex)
    for _, atlas in ipairs({ "Waypoint-MapPin-ChatIcon", "Waypoint-MapPin-Untracked" }) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            tex:SetAtlas(atlas)
            return
        end
    end
    tex:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
end

local function BarTooltip(bar)
    local done, total = L.Progress()
    GameTooltip:SetOwner(bar, "ANCHOR_LEFT")
    GameTooltip:SetText("Library Books")
    GameTooltip:AddLine(("%d of %d books handed in"):format(done, total), 1, 1, 1)
    for _, goal in ipairs(ns.LibraryGoals) do
        local state, r, g, b
        if C_QuestLog.IsQuestFlaggedCompleted(goal.quest) then
            state, r, g, b = "Claimed", 0.61, 0.64, 0.69
        elseif done >= goal.books then
            state, r, g, b = "Ready to hand in", READY.r, READY.g, READY.b
        else
            state, r, g, b = ("%d to go"):format(goal.books - done), 1, 1, 1
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(("%s (%d)"):format(goal.name, goal.books), state, 0.3, 0.71, 0.96, r, g, b)
        local names = {}
        for _, reward in ipairs(goal.rewards) do
            names[#names + 1] = C_Item.GetItemNameByID(reward[1]) or reward[2]
        end
        GameTooltip:AddLine(table.concat(names, " or "), 0.61, 0.64, 0.69, true)
    end
    local librarian = ns.LibraryTurnIns.librarian[L.Side()]
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Hand in to " .. librarian.name .. ", " .. librarian.place, 0.3, 0.7, 0.95, true)
    local bags, bank = 0, 0
    for _, book in ipairs(ns.LibraryBooks) do
        local stored = L.ForMe(book) and L.Stored(book)
        if stored == "bags" then bags = bags + 1 elseif stored == "bank" then bank = bank + 1 end
    end
    if bags > 0 then GameTooltip:AddLine(bags .. " waiting in your bags", 1, 0.82, 0) end
    if bank > 0 then GameTooltip:AddLine(bank .. " waiting in your bank", 1, 0.82, 0) end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function BuildPanel()
    panel = CreateFrame("Frame", "NaowhForeverLibraryBooks", UIParent)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:SetWidth(PANEL_W)
    ns.Solid(panel, "BACKGROUND", BLACK, 0.7):SetAllPoints()
    ns.Border(panel, BLACK)

    panel.title = ns.Font(panel, 14, "OUTLINE", T.accent)
    panel.title:SetPoint("TOPLEFT", 8, -8)
    panel.title:SetPoint("RIGHT", -28, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    -- The X closes it until you change zone, and switches Always Show off, so switching that
    -- back on is how to bring it back.
    panel.close = ns.Button(panel, "X", 18, 18, function()
        dismissedZone = L.PlayerZone()
        panel:Hide()
        if S.Get("trackerAlways") then
            S.Set("trackerAlways", false)
            ns.UI:RefreshPage(true)
        end
    end)
    panel.close:SetPoint("TOPRIGHT", -5, -5)
    local titleBtn = CreateFrame("Button", nil, panel)
    titleBtn:SetPoint("TOPLEFT", panel.title, "TOPLEFT", -4, 4)
    titleBtn:SetPoint("BOTTOMRIGHT", panel.title, "BOTTOMRIGHT", 0, -4)
    titleBtn:SetScript("OnClick", function() ns.OpenOptionsWindow("Discovery/Books") end)
    titleBtn:SetScript("OnEnter", function(self)
        local c = T.accentSoft
        panel.title:SetTextColor(c.r, c.g, c.b, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Library Books")
        GameTooltip:AddLine("Click to open the Books page.", 0.3, 0.7, 0.95)
        GameTooltip:Show()
    end)
    titleBtn:SetScript("OnLeave", function()
        local c = T.accent
        panel.title:SetTextColor(c.r, c.g, c.b, 1)
        GameTooltip:Hide()
    end)

    local bar = CreateFrame("StatusBar", nil, panel)
    -- As tall as the dropdown under it, and spaced like it.
    bar:SetSize(BODY_W, 24)
    bar:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    ns.Solid(bar, "BACKGROUND", ns.ThemeTint("panel", BAR_BG), 1):SetAllPoints()
    ns.Border(bar, BLACK)
    bar.text = ns.Font(bar, 12, "OUTLINE")
    bar.text:SetPoint("CENTER", 0, 0)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", BarTooltip)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    panel.bar = bar

    -- With Always Show, in a zone with no books left: pick another zone to list. Its zones
    -- are handed to it on every redraw.
    panel.picker = ns.UI.BuildDropdownControl(panel, BODY_W, panel:GetFrameLevel() + 3, {}, {},
        function() return pickedZone end,
        function(id) S.Set("trackerZone", id) end)
    panel.picker:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    panel.picker:Hide()

    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetWidth(BODY_W)
    panel.rows = {}

    panel.mover = ns.UI.AttachMover(panel, "Library Books", function(pos) S.Set("trackerPos", pos) end)
    local pos = S.Get("trackerPos")
    if pos then
        panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, -120)
    end
    panel:Hide()
end

local function RowTooltip(row)
    local entry = row.entry
    if not (entry and entry.tip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    entry.tip()
    GameTooltip:Show()
end

local function PinClick(pin)
    local entry = pin:GetParent().entry
    if entry and entry.waypoint then entry.waypoint() end
end

local function PinTooltip(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_LEFT")
    GameTooltip:SetText("Waypoint")
    GameTooltip:AddLine("Click to mark it on your map.", 0.3, 0.7, 0.95)
    GameTooltip:Show()
end

local function Row(i)
    local row = panel.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.body)
    row:SetWidth(BODY_W)
    row.text = ns.Font(row, 12, nil)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row.sub = ns.Font(row, 12, nil, T.muted)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(true)
    row.pin = CreateFrame("Button", nil, row)
    row.pin:SetSize(PIN, PIN)
    row.pin.tex = row.pin:CreateTexture(nil, "ARTWORK")
    row.pin.tex:SetAllPoints()
    SetPinTexture(row.pin.tex)
    row.pin:SetScript("OnClick", PinClick)
    row.pin:SetScript("OnEnter", PinTooltip)
    row.pin:SetScript("OnLeave", GameTooltip_Hide)
    row.stripe = ns.Solid(row, "BACKGROUND", ns.ThemeTint("panel", BAR_BG), 1)
    row.stripe:SetAllPoints()
    for _, e in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local edge = ns.Solid(row, "ARTWORK", BLACK, 1)
        edge:SetPoint(e[1])
        edge:SetPoint(e[2])
        if e[3] then edge:SetHeight(1) else edge:SetWidth(1) end
    end
    row.divider = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.divider:SetPoint("TOPLEFT", row, "BOTTOMLEFT")
    row.divider:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT")
    row.divider:SetHeight(1)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    panel.rows[i] = row
    return row
end

-- entries: { text, sub?, waypoint?, tip? }. Every row leaves room for the pin, so the names
-- line up whether or not a row has one.
local function Layout(entries)
    local y = 0
    local x = INSET + PIN + 3
    for i, entry in ipairs(entries) do
        local row = Row(i)
        row.entry = entry
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", x, NUDGE - 1 - GAP)
        row.text:SetWidth(BODY_W - x - INSET)
        row.text:SetText(entry.text)
        local h = math.ceil(row.text:GetStringHeight()) + 3 + GAP * 2
        row.sub:ClearAllPoints()
        row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
        row.sub:SetWidth(BODY_W - x - INSET)
        row.sub:SetText(entry.sub or "")
        row.sub:SetShown(entry.sub ~= nil)
        if entry.sub then h = h + math.ceil(row.sub:GetStringHeight()) + 3 end
        row.pin:ClearAllPoints()
        row.pin:SetPoint("TOPLEFT", INSET, NUDGE + 1 - GAP)
        row.pin:SetShown(entry.waypoint ~= nil)
        row:EnableMouse(entry.tip ~= nil)
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
        row:Show()
        local divided = entries[i + 1] ~= nil
        row.divider:SetShown(divided)
        y = y + h + (divided and 1 or 0)
    end
    for i = #entries + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.body:SetHeight(math.max(y, 1))
    return y
end

-------------------------------------------------------------------------------
--  What it lists
-------------------------------------------------------------------------------
-- Books looted and not handed in, counted per person who takes them and where they are
-- kept: out["librarian/bags"] and so on.
local function CarriedByTurnIn()
    local out = {}
    for _, book in ipairs(ns.LibraryBooks) do
        local stored = L.ForMe(book) and L.Stored(book)
        if stored then
            local key = (book.turnIn or "librarian") .. "/" .. stored
            out[key] = (out[key] or 0) + 1
        end
    end
    return out
end

local function RenderBar()
    local bar = panel.bar
    local done, total = L.Progress()
    local goal = L.NextGoal()
    local accent = T.accent
    if goal then
        local ready = done >= goal.books
        bar:SetMinMaxValues(0, goal.books)
        bar:SetValue(math.min(done, goal.books))
        local c = ready and READY or accent
        bar:SetStatusBarColor(c.r, c.g, c.b, 0.85)
        bar.text:SetText(ready and (goal.name .. " ready to hand in")
            or ("%d / %d  %s"):format(done, goal.books, goal.name))
    else
        bar:SetMinMaxValues(0, math.max(total, 1))
        bar:SetValue(done)
        bar:SetStatusBarColor(READY.r, READY.g, READY.b, 0.85)
        bar.text:SetText(("%d / %d books handed in"):format(done, total))
    end
end

-- Every zone with a book still to find, in the data's order (by set), with how many:
-- { uiMapID, count } pairs.
local function ZonesLeft()
    local out, seen = {}, {}
    for _, book in ipairs(ns.LibraryBooks) do
        for _, spot in ipairs(book.spots) do
            local id = spot[1]
            if not seen[id] then
                seen[id] = true
                local n = #L.OnMap(id)
                if n > 0 then out[#out + 1] = { id, n } end
            end
        end
    end
    return out
end

-- Points the dropdown at the zones left and returns the one to list: the saved pick while
-- it still has books, else the first.
local function Pick(left)
    local saved, values, order = S.Get("trackerZone"), {}, {}
    pickedZone = nil
    for _, z in ipairs(left) do
        values[z[1]] = L.ZoneName(z[1]) .. "  " .. ns.Color("muted", "(" .. z[2] .. ")")
        order[#order + 1] = z[1]
        if z[1] == saved then pickedZone = saved end
    end
    pickedZone = pickedZone or left[1][1]
    panel.picker._values, panel.picker._order = values, order
    panel.picker._refreshLabel()
    return pickedZone
end

-- zone is where you stand; left, when given, is the zones for the dropdown, and the list is
-- the picked zone's instead of yours.
local function Render(zone, left)
    local listZone = left and Pick(left) or zone
    panel.picker:SetShown(left ~= nil)
    panel.body:ClearAllPoints()
    panel.body:SetPoint("TOPLEFT", left and panel.picker or panel.bar, "BOTTOMLEFT", 0, -6)
    local entries = {}
    local carried = CarriedByTurnIn()
    for _, kind in ipairs({ "librarian", "trainer" }) do
        for _, place in ipairs({ "bags", "bank" }) do
            local n = carried[kind .. "/" .. place]
            if n then
                local npc = ns.LibraryTurnIns[kind][L.Side()]
                entries[#entries + 1] = {
                    text = GOLD .. (n == 1 and "1 book" or (n .. " books")) .. " in your " .. place .. "|r",
                    sub = "Hand in to " .. npc.name .. ", " .. npc.place,
                    waypoint = function() ns.PlaceWaypoint(npc.name, npc.map, npc.x, npc.y) end,
                }
            end
        end
    end
    for _, item in ipairs(L.OnMap(listZone)) do
        local book, spot = item[1], item[2]
        local sub = L.Where(spot)
        if book.turnIn == "trainer" then sub = sub .. " - mage trainer" end
        entries[#entries + 1] = {
            text = L.Title(book), sub = sub,
            waypoint = function()
                ns.PlaceWaypoint(book.name, spot[1], spot[2], spot[3], spot[4] and (" (" .. spot[4] .. ")"))
            end,
            tip = function()
                GameTooltip:SetText(book.name)
                if spot[5] then GameTooltip:AddLine(spot[5], 1, 1, 1, true) end
                local npc = L.TurnIn(book)
                GameTooltip:AddLine("Hand in to " .. npc.name .. ", " .. npc.place, 0.3, 0.7, 0.95, true)
            end,
        }
    end
    for _, item in ipairs(L.DoneOnMap(listZone)) do
        entries[#entries + 1] = { text = L.Title(item[1]) }
    end
    if #entries == 0 then
        entries[1] = { text = ns.Color("muted", "No books left to find here.") }
    end
    panel.title:SetText("Library Books  " .. ns.Color("muted", L.ZoneName(zone)))
    RenderBar()
    local listH = Layout(entries)
    -- 8 above the title, 6 above and below the bar and the dropdown, 8 under the list.
    local pickerH = left and (panel.picker:GetHeight() + 6) or 0
    panel:SetHeight(8 + math.ceil(panel.title:GetStringHeight()) + 6 + panel.bar:GetHeight() + 6
        + pickerH + listH + 8)
end

-------------------------------------------------------------------------------
--  When it shows
-------------------------------------------------------------------------------
local shownZone   -- the zone it popped up in; it stays up there until you leave or close it
local lastZone    -- the zone of the last redraw, so entering a zone selects it once

local function Hide()
    shownZone = nil
    if shownEvents then shownEvents:UnregisterAllEvents() end
    if panel then panel:Hide() end
end

-- Without Always Show it pops up on entering a zone with books to find and stays for as
-- long as you are in that zone, even once they are looted. With it, it shows in every zone
-- with the dropdown, until the X or the toggle switches it off. Entering a zone with books
-- selects it; a zone picked from the dropdown after that sticks until you enter another.
local function Refresh()
    if not On() then return Hide() end
    local zone = L.PlayerZone()
    if zone ~= dismissedZone then dismissedZone = nil end
    local here = zone and #L.OnMap(zone) > 0
    local always = S.Get("trackerAlways")
    local entered = zone ~= lastZone
    lastZone = zone
    if always and here and entered and S.Get("trackerZone") ~= zone then
        S.Set("trackerZone", zone)   -- redraws through the Set hook
        return
    end
    local left = zone and always and ZonesLeft() or nil
    if left and #left == 0 then left = nil end
    local stay = panel and panel:IsShown() and shownZone == zone
    local show = zone and not dismissedZone and (always or here or stay)
    if not show then return Hide() end
    if not panel then BuildPanel() end
    Render(zone, left)
    panel:Show()
    shownZone = zone
    -- Looting a book fills your bags; handing one in completes its quest.
    shownEvents:RegisterEvent("BAG_UPDATE_DELAYED")
    shownEvents:RegisterEvent("QUEST_TURNED_IN")
end

-- Loot and turn-ins can fire several events at once; gather them into one redraw.
local redrawQueued
local function QueueRefresh()
    if redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0.2, function()
        redrawQueued = false
        Refresh()
    end)
end

local function Apply()
    if On() then
        if not zoneEvents then
            zoneEvents = CreateFrame("Frame")
            zoneEvents:SetScript("OnEvent", QueueRefresh)
            shownEvents = CreateFrame("Frame")
            shownEvents:SetScript("OnEvent", QueueRefresh)
        end
        zoneEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    elseif zoneEvents then
        zoneEvents:UnregisterAllEvents()
    end
    Refresh()
end

local OWN_KEYS = { enabled = true, tracker = true, trackerAlways = true, trackerZone = true }

hooksecurefunc(S, "Set", function(key, value)
    if not OWN_KEYS[key] then return end
    -- Switching Always Show back on brings the tracker back here, whatever the X closed.
    -- Switching it off closes it, unless the zone you are in has books to find.
    if key == "trackerAlways" then
        -- Switching it on selects the zone you are in, as entering it would.
        if value then dismissedZone, lastZone = nil, nil else shownZone = nil end
    end
    Apply()
end)
hooksecurefunc(ns, "Apply", Apply)

-- Unlock Mode shows it wherever you are, on your zone or the first zone with books for you.
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not On() then return end
    if not panel then BuildPanel() end
    local zone = L.PlayerZone()
    if not zone or #L.OnMap(zone) == 0 then
        zone = L.Side() == "H" and 1413 or 1436
    end
    Render(zone)
    panel.mover:Show()
    panel:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if panel then
        panel.mover:Hide()
        Refresh()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
