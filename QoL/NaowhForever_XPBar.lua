-------------------------------------------------------------------------------
--  NaowhForever_XPBar.lua -- the QoL XP bar, with completed quest XP and rested drawn on it and
--  a choice of texts around it. Replaces Blizzard's experience bar while on. Its Played text
--  comes from Shared.Played.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Played = ns.Shared.Played

-- Naowh's blue for the fill, his logo's gold for quest XP, a darker blue for rested.
local FILL_FROM = CreateColor(0x00 / 255, 0x4f / 255, 0x85 / 255, 1)
local QUEST     = { r = 0xf2 / 255, g = 0xa9 / 255, b = 0x00 / 255 }
local RESTED    = { r = 0x1e / 255, g = 0x40 / 255, b = 0xaf / 255 }
local QUEST_HEX, RESTED_HEX = "|cfff2a900", "|cff6b8cff"
local OPEN_ALPHA = 0.4  -- incomplete quests: the completed quests colour, faded
local BG_ALPHA = 0.85
local FILL_DARK = 0.55  -- how dark the fill's left end is against its colour
local RESTED_DARK = 0.7 -- how dark rested is against a theme's changed accent

-- The colours a player picked (Colours, under XP Bar) win; unset ones follow the theme, and
-- the shipped colours above while the theme leaves the accent alone. Text in a quest or
-- rested colour follows the bar.
local COLOR_KEYS = { "xpBarFillColor", "xpBarQuestColor", "xpBarRestedColor", "xpBarBgColor" }
local questHex, restedHex = QUEST_HEX, RESTED_HEX

local function FillGradient()
    local c = S.Get("xpBarFillColor")
    if c then
        return CreateColor(c.r * FILL_DARK, c.g * FILL_DARK, c.b * FILL_DARK, 1), CreateColor(c.r, c.g, c.b, 1)
    end
    -- The dark end follows a changed accent; the shipped blue stays as it was otherwise.
    local shifted = ns.ThemeTint("accent", nil)
    local from = shifted and CreateColor(shifted.r * FILL_DARK, shifted.g * FILL_DARK, shifted.b * FILL_DARK, 1)
        or FILL_FROM
    return from, CreateColor(T.accent.r, T.accent.g, T.accent.b, 1)
end

-- Quest XP is the logo's gold; a theme changes it to its lighter accent, which reads apart
-- from the fill's accent.
local function QuestDefault()
    return ns.ThemeTint("accentSoft", QUEST)
end

-- Rested sits just ahead of the fill: a deeper shade of a changed accent, the royal blue
-- otherwise.
local function RestedDefault()
    local shifted = ns.ThemeTint("accent", nil)
    return shifted and { r = shifted.r * RESTED_DARK, g = shifted.g * RESTED_DARK, b = shifted.b * RESTED_DARK }
        or RESTED
end

-- Colours a bar: the live one and the settings preview alike.
local function PaintBar(b)
    b.fill:SetGradient("HORIZONTAL", FillGradient())
    local q = S.Get("xpBarQuestColor") or QuestDefault()
    local r = S.Get("xpBarRestedColor") or RestedDefault()
    local bg = S.Get("xpBarBgColor") or T.bg
    b.done:SetColorTexture(q.r, q.g, q.b, 1)
    if b.open then b.open:SetColorTexture(q.r, q.g, q.b, OPEN_ALPHA) end
    b.rested:SetColorTexture(r.r, r.g, r.b, 1)
    b.bg:SetColorTexture(bg.r, bg.g, bg.b, BG_ALPHA)
end

-- The rested text keeps its lighter blue by default, which reads better than the bar's own.
local function UpdateTextColors()
    local q, r = S.Get("xpBarQuestColor"), S.Get("xpBarRestedColor")
    if q then
        questHex = ns.Color(q)
    else
        questHex = ns.ThemeTint("accentSoft", nil) and ns.Color("accentSoft") or QUEST_HEX
    end
    if r then
        restedHex = ns.Color(r)
    else
        restedHex = ns.ThemeTint("accent", nil) and ns.Color("accent") or RESTED_HEX
    end
end

-- The colour each swatch stands for while nothing is picked.
function ns.XPBarDefaultColor(key)
    if key == "xpBarFillColor" then return T.accent end
    if key == "xpBarQuestColor" then return QuestDefault() end
    if key == "xpBarRestedColor" then return RestedDefault() end
    return T.bg
end

-- What a colour swatch on the settings page shows: the pick, else the default in use.
function ns.XPBarColor(key)
    return S.Get(key) or ns.XPBarDefaultColor(key)
end

function ns.ResetXPBarColors()
    ns.Confirm("Put the XP Bar colours back to their defaults?", function()
        local db = S.DB()
        for _, k in ipairs(COLOR_KEYS) do db[k] = nil end
        S.Set("xpBarFillColor", nil)
        -- So the swatches show the defaults again.
        ns.UI:RefreshPage(true)
    end)
end
-- Narrower and the texts around the bar no longer fit, even at their smallest size. The
-- Width slider starts here; a width saved before it did is raised to it.
ns.XPBarMinWidth = 400

local bar, clock, unlocked, questTimer
-- nil while the bar is off: XP is only counted while it is on, so the clock starts with it.
local sessionStart, sessionXP = nil, 0
local lastXP, lastXPMax
local questDone, questOpen = 0, 0

-- The spots around the bar a text can go, each the setting that picks its text.
-- In reading order, which is also the order that keeps a text shown twice (OneEach).
local SIDE_GAP = 6 -- between the bar and a text beside it
local SLOTS = {
    { key = "xpBarTopLeft", label = "Top Left", point = "BOTTOMLEFT", rel = "TOPLEFT", y = 4,
      justify = "LEFT" },
    { key = "xpBarTop", label = "Top", point = "BOTTOM", rel = "TOP", y = 4,
      justify = "CENTER" },
    { key = "xpBarTopRight", label = "Top Right", point = "BOTTOMRIGHT", rel = "TOPRIGHT", y = 4,
      justify = "RIGHT" },
    { key = "xpBarLeft", label = "Left", point = "RIGHT", rel = "LEFT", x = -SIDE_GAP, y = 0,
      justify = "RIGHT" },
    { key = "xpBarRight", label = "Right", point = "LEFT", rel = "RIGHT", x = SIDE_GAP, y = 0,
      justify = "LEFT" },
    { key = "xpBarBottomLeft", label = "Bottom Left", point = "TOPLEFT", rel = "BOTTOMLEFT", y = -4,
      justify = "LEFT" },
    { key = "xpBarBottom", label = "Bottom", point = "TOP", rel = "BOTTOM", y = -4,
      justify = "CENTER" },
    { key = "xpBarBottomRight", label = "Bottom Right", point = "TOPRIGHT", rel = "BOTTOMRIGHT",
      y = -4, justify = "RIGHT" },
}
-- Where each spot sits in SLOTS.
local TOP_LEFT, TOP, TOP_RIGHT, LEFT, RIGHT, BOTTOM_LEFT, BOTTOM, BOTTOM_RIGHT = 1, 2, 3, 4, 5, 6, 7, 8
local BESIDE = { LEFT, RIGHT }

-- The three texts inside the bar, left to right.
-- point is the bar edge (or centre) each one sits at, dir the way it is set in from that edge.
local INSIDE = {
    { key = "xpBarLeftText", label = "Left Text", point = "LEFT", dir = 1, justify = "LEFT" },
    { key = "xpBarCenterText", label = "Center Text", point = "CENTER", dir = 0, justify = "CENTER" },
    { key = "xpBarRightText", label = "Right Text", point = "RIGHT", dir = -1, justify = "RIGHT" },
}

-- Choices that are one text written differently, by the text they show.
local SAME_TEXT = { levelshort = "level", levelnum = "level" }

local function TextOf(which)
    return SAME_TEXT[which] or which
end

-- Each text shows in one spot at most, inside the bar and around it alike. Picking one for a
-- spot clears whichever spot of the same group had it, in any of its forms.
local function Claim(spots, key, which)
    if which == "none" then return end
    local db, text = S.DB(), TextOf(which)
    for _, spot in ipairs(spots) do
        if spot.key ~= key and TextOf(S.Get(spot.key)) == text then db[spot.key] = "none" end
    end
end

-- A profile saved with a text in two spots keeps it in the first, in reading order.
local function OneEach(spots)
    local db, seen = S.DB(), {}
    for _, spot in ipairs(spots) do
        local which = S.Get(spot.key)
        if which and which ~= "none" then
            local text = TextOf(which)
            if seen[text] then db[spot.key] = "none" else seen[text] = true end
        end
    end
end

-- The switches the spots replaced, each with the texts it showed and the spots they move to.
-- The old defaults were Played and Leveling on, Session and Completed off.
local OLD_TEXTS = {
    { key = "xpBarPlayed", default = true, texts = { { "xpBarTopLeft", "played" } } },
    { key = "xpBarSession", default = false, texts = { { "xpBarTopRight", "session" } } },
    { key = "xpBarLeveling", default = true,
      texts = { { "xpBarBottomLeft", "leveling" }, { "xpBarBottomRight", "xphour" } } },
    { key = "xpBarCompleted", default = false,
      texts = { { "xpBarBottom", "completed" }, { "xpBarBottom", "rested" } } },
}

local function On()
    return S.Get("enabled") and S.Get("xpBar")
end

local function AtMaxLevel()
    return UnitLevel("player") >= GetMaxLevelForPlayerExpansion() or IsXPUserDisabled()
end

local function Short(n)
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n))
end

-- A whole number with thousands separators, 95,612.
local function Grouped(n)
    n = math.floor(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function Duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local d, h, m = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24,
        math.floor(seconds / 60) % 60
    if d > 0 then return ("%dd %dh %dm"):format(d, h, m) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

-------------------------------------------------------------------------------
--  Blizzard's experience bar
-------------------------------------------------------------------------------
-- Faded out rather than hidden or unregistered. Edit Mode stacks the bottom action bars on
-- these containers, and a Show/Hide from addon code taints that layout: the next re-layout in
-- combat (the pet or stance bar changing) is then blocked. Retail-engine clients track XP in
-- the status tracking containers, older ones in MainMenuExpBar. Only the container holding
-- the XP bar fades: at max level the same container carries the watched reputation instead.
local hideBlizzard = false
local hooked = {}

local function BlizzardBars()
    local manager = StatusTrackingBarManager
    if manager and manager.barContainers then return manager.barContainers end
    local list = {}
    for _, name in ipairs({ "MainMenuExpBar", "ExhaustionTick" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

local function ShowsXP(frame)
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    return frame.shownBarIndex == nil or not enum or frame.shownBarIndex == enum.Experience
end

local function Refresh(frame)
    frame:SetAlpha(hideBlizzard and ShowsXP(frame) and 0 or 1)
end

local function SetBlizzardHidden(hide)
    if hide == hideBlizzard then return end
    hideBlizzard = hide
    for _, frame in ipairs(BlizzardBars()) do
        if not hooked[frame] then
            hooked[frame] = true
            frame:HookScript("OnShow", function(self)
                if hideBlizzard and ShowsXP(self) then Refresh(self) end
            end)
            -- The container swaps bars without hiding when XP is switched back on at max level.
            if frame.ApplyPendingBarToShow then
                hooksecurefunc(frame, "ApplyPendingBarToShow", function(self)
                    if hideBlizzard then Refresh(self) end
                end)
            end
            -- The container's own fade-in animation runs after those hooks and ends at full
            -- alpha, which is how the bar came back after a /reload. Animations do not go
            -- through SetAlpha, so it is caught here instead, only while the frame is shown
            -- and only when its alpha has crept back up.
            frame:HookScript("OnUpdate", function(self)
                if hideBlizzard and self:GetAlpha() > 0 and ShowsXP(self) then self:SetAlpha(0) end
            end)
        end
        Refresh(frame)
    end
end

-------------------------------------------------------------------------------
--  Quest XP
-------------------------------------------------------------------------------
local function ScanQuests()
    questTimer = nil
    questDone, questOpen = 0, 0
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and GetQuestLogRewardXP) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            local xp = GetQuestLogRewardXP(info.questID) or 0
            if C_QuestLog.IsComplete(info.questID) then
                questDone = questDone + xp
            else
                questOpen = questOpen + xp
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Session
-------------------------------------------------------------------------------
-- Kept per character in the account store, so a /reload carries on the session unless
-- Reset on Reload is ticked. A fresh login always starts a new one.
local function SessionStore()
    local account = ns.AccountSettings()
    account.xpBarSessions = account.xpBarSessions or {}
    return account.xpBarSessions, UnitName("player") .. "-" .. GetRealmName()
end

local function SaveSession()
    local store, key = SessionStore()
    store[key] = sessionStart and { start = sessionStart, xp = sessionXP } or nil
end

local function LoadSession(isReload)
    local store, key = SessionStore()
    local saved = store[key]
    if isReload and saved and saved.start and not S.Get("xpBarResetOnReload") then
        sessionStart, sessionXP = saved.start, saved.xp or 0
    end
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local function Segment(tex, from, width, total)
    local w = math.min(width, total - from)
    if w < 0.5 then tex:Hide() return from end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", from, 0)
    tex:SetPoint("BOTTOMLEFT", from, 0)
    tex:SetWidth(w)
    tex:Show()
    return from + w
end

-- max is Update's, never 0: the game reports 0 for a moment after login or a reload, before
-- the character's data has loaded.
local function SlotText(which, maxed, max)
    local LABEL, VALUE = ns.Color("muted"), ns.Color("fg")
    local elapsed = time() - sessionStart
    if which == "played" then
        local total = Played.Total()
        if not total then return "" end
        return LABEL .. "Played:|r " .. VALUE .. Duration(total) .. "|r - "
            .. LABEL .. "This Level:|r " .. VALUE .. Duration(Played.Level()) .. "|r"
    elseif which == "session" then
        return LABEL .. "Session:|r " .. VALUE .. Duration(elapsed) .. "|r"
    elseif maxed then
        return ""
    elseif which == "completed" then
        return LABEL .. "Completed Quests:|r " .. questHex .. ("%.1f%%"):format(questDone / max * 100) .. "|r"
    elseif which == "completedxp" then
        return LABEL .. "Completed Quests:|r " .. questHex .. Grouped(questDone) .. "|r"
    elseif which == "rested" then
        return LABEL .. "Rested:|r " .. restedHex .. ("%.1f%%"):format((GetXPExhaustion() or 0) / max * 100) .. "|r"
    end
    local rate = sessionXP / (math.max(elapsed, 60) / 3600)
    if which == "leveling" then
        local left = math.max(max - UnitXP("player"), 0)
        return LABEL .. "Time to Level:|r " .. VALUE .. (rate > 0 and Duration(left / rate * 3600) or "--") .. "|r"
    elseif which == "xphour" then
        return LABEL .. "XP/Hour:|r " .. VALUE .. Short(rate) .. "|r"
    end
    return ""
end

-- A profile that changed the old switches gets the same texts in the spots, once. With both
-- Completed Quests and Rested on there is one spot left, so Rested is dropped.
local function ConvertOldTexts()
    local db = S.DB()
    local saved = false
    for _, old in ipairs(OLD_TEXTS) do
        if db[old.key] ~= nil then saved = true end
    end
    if not saved then return end
    local picked = false
    for _, slot in ipairs(SLOTS) do
        if db[slot.key] ~= nil then picked = true end
    end
    if not picked then
        for _, slot in ipairs(SLOTS) do db[slot.key] = "none" end
        for _, old in ipairs(OLD_TEXTS) do
            local on = db[old.key]
            if on == nil then on = old.default end
            if on then
                for _, t in ipairs(old.texts) do
                    if db[t[1]] == "none" then db[t[1]] = t[2] end
                end
            end
        end
    end
    for _, old in ipairs(OLD_TEXTS) do db[old.key] = nil end
end

local TEXT_GAP = 8       -- between two texts in a row
local SLOT_FONT = 13     -- the texts around the bar, when they fit
local SLOT_FONT_MIN = 8  -- the smallest they shrink to before they cut off

-- How wide a text is in full, with a pixel spare so rounding never cuts it off.
local function Natural(fs)
    local text = fs:GetText()
    if not text or text == "" then return 0 end
    local width = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    return math.ceil(width) + 1
end

-- The width a row needs to show every text in full: the texts side by side, a gap between
-- each two that are showing.
local function RowNeed(nl, nm, nr)
    local shown = (nl > 0 and 1 or 0) + (nm > 0 and 1 or 0) + (nr > 0 and 1 or 0)
    return nl + nm + nr + math.max(0, shown - 1) * TEXT_GAP
end

-- Texts in a row share the bar's width. The side texts start at the bar's ends. The middle one
-- is centred while it has room there, and slides away from a long side text when it has not,
-- placed through placeMid(midIndex, offset from the centre). Each text gets the room it needs
-- when the row fits; when it still does not at the smallest size, the row is split evenly, the
-- middle centred, and long texts cut off, rather than running into each other.
local function FitRow(w, left, mid, right, placeMid, midIndex)
    local nl, nr, nm = Natural(left), Natural(right), Natural(mid)
    if nm > 0 then
        if nl == 0 and nr == 0 then
            mid:SetWidth(math.max(1, w))
            placeMid(midIndex, 0)
        elseif RowNeed(nl, nm, nr) <= w then
            local from = nl > 0 and nl + TEXT_GAP or 0
            local to = w - (nr > 0 and nr + TEXT_GAP or 0)
            local centre = math.min(math.max(w / 2, from + nm / 2), to - nm / 2)
            mid:SetWidth(nm)
            placeMid(midIndex, centre - w / 2)
            left:SetWidth(math.max(1, centre - nm / 2 - TEXT_GAP))
            right:SetWidth(math.max(1, w - centre - nm / 2 - TEXT_GAP))
        else
            local third = math.max(1, w / 3 - TEXT_GAP)
            left:SetWidth(third)
            mid:SetWidth(third)
            right:SetWidth(third)
            placeMid(midIndex, 0)
        end
    elseif nl + nr + TEXT_GAP <= w then
        left:SetWidth(math.max(1, w - nr - TEXT_GAP))
        right:SetWidth(math.max(1, w - nl - TEXT_GAP))
    else
        left:SetWidth(math.max(1, w / 2 - TEXT_GAP))
        right:SetWidth(math.max(1, w / 2 - TEXT_GAP))
    end
end

-- The largest size up to base at which the row fits. Text width grows with its size, so what
-- each text measures now is scaled back to base first.
local function AtFull(fs, base)
    return Natural(fs) * base / (fs._fitSize or base)
end

local function RowSize(w, left, mid, right, base)
    local need = RowNeed(AtFull(left, base), AtFull(mid, base), AtFull(right, base))
    if need <= w then return base end
    return math.max(SLOT_FONT_MIN, math.floor(base * w / need))
end

local function SetSlotSize(fs, size)
    local font = ns.UIFontPath()
    if fs._fitSize == size and fs._fitFont == font then return end
    fs._fitSize, fs._fitFont = size, font
    fs:SetFont(font, size, "OUTLINE")
end

-- One row of slots (left, middle, right indexes): its own size, then its room.
local function FitSlotRow(slots, w, placeMid, l, m, r)
    local size = RowSize(w, slots[l], slots[m], slots[r], SLOT_FONT)
    SetSlotSize(slots[l], size)
    SetSlotSize(slots[m], size)
    SetSlotSize(slots[r], size)
    FitRow(w, slots[l], slots[m], slots[r], placeMid, m)
end

-- slots is in SLOTS order. The rows above and below the bar each shrink only as far as their
-- own texts need. The texts beside the bar have nothing to share their room with, so they keep
-- the full size and take what they need. placeMid(index, offset) moves a row's middle text.
local function FitSlots(slots, w, placeMid)
    FitSlotRow(slots, w, placeMid, TOP_LEFT, TOP, TOP_RIGHT)
    FitSlotRow(slots, w, placeMid, BOTTOM_LEFT, BOTTOM, BOTTOM_RIGHT)
    for _, i in ipairs(BESIDE) do
        SetSlotSize(slots[i], SLOT_FONT)
        slots[i]:SetWidth(math.max(1, Natural(slots[i])))
    end
end

-- The three texts inside the bar (left, centre, right), set in from its ends. Their size
-- follows the bar's height, made smaller only when the row would not fit at it.
local INSIDE_INSET = 8 -- from the bar's ends
local function InsideFont(h)
    return math.max(10, math.floor(h * 0.55))
end

local function FitInside(texts, w, h, placeMid)
    local row = w - INSIDE_INSET * 2
    local size = RowSize(row, texts[1], texts[2], texts[3], InsideFont(h))
    for _, fs in ipairs(texts) do SetSlotSize(fs, size) end
    FitRow(row, texts[1], texts[2], texts[3], placeMid, 2)
end

-- True when any text in the list differs from the last time it was asked; all are checked so
-- each remembers its own.
local function TextsChanged(list)
    local changed = false
    for i = 1, #list do
        local fs = list[i]
        local text = fs:GetText()
        if text ~= fs._fitText then
            fs._fitText = text
            changed = true
        end
    end
    return changed
end

local function InsideText(which, level, xp, max, maxed, pct, rested)
    if which == "level" then return "Level " .. level end
    if which == "levelshort" then return "Lvl " .. level end
    if which == "levelnum" then return tostring(level) end
    if which == "xp" then return maxed and "Max Level" or (xp .. " / " .. max) end
    if which == "percent" then return ("%.1f%%"):format(pct) end
    if which == "rested" then return ("Rested %.1f%%"):format(rested / max * 100) end
    return ""
end

local Look = {}

function Look.New(b)
    -- Coloured by PaintBar.
    b.bg = ns.Solid(b, "BACKGROUND", T.bg, BG_ALPHA)
    b.bg:SetAllPoints()

    -- The track holds the fill and segments, the full width of the bar.
    b.track = CreateFrame("Frame", nil, b)
    b.track:SetAllPoints()
    b.track:SetClipsChildren(true)
    b.track:SetFrameLevel(b:GetFrameLevel() + 1)
    b.fill = b.track:CreateTexture(nil, "ARTWORK")
    b.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.done = ns.Solid(b.track, "ARTWORK", QUEST, 1)
    b.open = ns.Solid(b.track, "ARTWORK", QUEST, OPEN_ALPHA)
    b.rested = ns.Solid(b.track, "ARTWORK", RESTED, 1)
    b.rested:SetDrawLayer("ARTWORK", 0)
    b.done:SetDrawLayer("ARTWORK", 1)
    b.open:SetDrawLayer("ARTWORK", 1)

    -- Above the track, whose own frame would otherwise cover the border.
    ns.Border(b)._frame:SetFrameLevel(b:GetFrameLevel() + 4)

    local text = CreateFrame("Frame", nil, b)
    text:SetAllPoints()
    text:SetFrameLevel(b:GetFrameLevel() + 5)
    b.level = ns.Font(text, 14, "OUTLINE")
    b.level:SetPoint("LEFT", b.track, "LEFT", INSIDE_INSET, 0)
    b.level:SetJustifyH("LEFT")
    b.value = ns.Font(text, 14, "OUTLINE")
    b.value:SetPoint("CENTER", b.track, "CENTER")
    b.pct = ns.Font(text, 14, "OUTLINE")
    b.pct:SetPoint("RIGHT", b.track, "RIGHT", -INSIDE_INSET, 0)
    b.pct:SetJustifyH("RIGHT")
    b.inside = { b.level, b.value, b.pct }
    for _, fs in ipairs(b.inside) do fs:SetWordWrap(false) end
    b.placeInside = function(_, dx)
        b.value:ClearAllPoints()
        b.value:SetPoint("CENTER", b.track, "CENTER", dx, 0)
    end
    b.slots = {}
    for i, slot in ipairs(SLOTS) do
        local fs = ns.Font(b, SLOT_FONT, "OUTLINE")
        fs:SetPoint(slot.point, b, slot.rel, slot.x or 0, slot.y)
        fs:SetJustifyH(slot.justify)
        fs:SetWordWrap(false)
        b.slots[i] = fs
    end
    b.placeMid = function(i, dx)
        local fs, slot = b.slots[i], SLOTS[i]
        fs:ClearAllPoints()
        fs:SetPoint(slot.point, b, slot.rel, dx, slot.y)
    end
end

function Look.Size(b, w, h)
    b:SetSize(w, h)
    -- At the height's size, so the first fit measures from it; Update shrinks them if needed.
    for _, fs in ipairs(b.inside) do SetSlotSize(fs, InsideFont(h)) end
    -- Their size was just reset, so the next Update fits them again.
    b._fitW = nil
end

function Look.Segments(b, total, pct, done, open, rested, max, maxed)
    local x = Segment(b.fill, 0, total * pct / 100, total)
    if maxed then
        b.done:Hide(); b.open:Hide(); b.rested:Hide()
        return
    end
    x = Segment(b.done, x, total * done / max, total)
    if S.Get("xpBarIncomplete") then
        Segment(b.open, x, total * open / max, total)
    else
        b.open:Hide()
    end
    -- Rested runs from the end of your XP like Blizzard's, the full height of the bar and
    -- drawn over the quest segments, so a bar full of quest XP cannot push it off the
    -- end. At least 3px, so a sliver of rest still reads.
    local from = total * pct / 100
    local w = math.min(math.max(total * rested / max, 3), total - from)
    if rested > 0 and w >= 1 then
        b.rested:ClearAllPoints()
        b.rested:SetPoint("TOPLEFT", from, 0)
        b.rested:SetPoint("BOTTOMLEFT", from, 0)
        b.rested:SetWidth(w)
        b.rested:Show()
    else
        b.rested:Hide()
    end
end

function Look.Texts(b, level, xp, max, maxed, pct, rested)
    for i, spot in ipairs(INSIDE) do
        b.inside[i]:SetText(InsideText(S.Get(spot.key), level, xp, max, maxed, pct, rested))
    end
end

-- Measuring and placing the texts only when one of them, or the bar, has changed.
function Look.Fit(b, total, h)
    local insideChanged = TextsChanged(b.inside)
    local slotsChanged = TextsChanged(b.slots)
    local font = ns.UIFontPath()
    if insideChanged or slotsChanged or b._fitW ~= total or b._fitH ~= h or b._fitFont ~= font then
        b._fitW, b._fitH, b._fitFont = total, h, font
        FitInside(b.inside, total, h, b.placeInside)
        FitSlots(b.slots, total, b.placeMid)
    end
end

local function ShowsText(which)
    for _, slot in ipairs(SLOTS) do
        if S.Get(slot.key) == which then return true end
    end
    return false
end

local function Update()
    if not bar then return end
    local maxed = AtMaxLevel()
    if not unlocked and maxed and not S.Get("xpBarMaxLevel") then
        bar:Hide()
        return
    end

    local xp, max = UnitXP("player"), math.max(UnitXPMax("player"), 1)
    local pct = maxed and 100 or xp / max * 100
    local rested = GetXPExhaustion() or 0
    Look.Texts(bar, UnitLevel("player"), xp, max, maxed, pct, rested)

    -- The whole bar is the track: a full bar is 100%.
    local total = bar:GetWidth()
    Look.Segments(bar, total, pct, questDone, questOpen, rested, max, maxed)

    for i, slot in ipairs(SLOTS) do
        bar.slots[i]:SetText(SlotText(S.Get(slot.key), maxed, max))
    end
    Look.Fit(bar, total, bar:GetHeight())
    bar:Show()
end

local function QueueQuestScan()
    if questTimer then return end
    questTimer = C_Timer.NewTimer(0.3, function() ScanQuests(); Update() end)
end

local function PlayedChanged()
    if bar and On() then Update() end
end

function ns.ResetXPBarSession()
    if not sessionStart then return end
    sessionStart, sessionXP = time(), 0
    SaveSession()
    Update()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        SaveSession()
        return
    end
    if event == "QUEST_LOG_UPDATE" then
        QueueQuestScan()
        return
    end
    -- The bar takes the mouse only while Ctrl is down, for its reset click; otherwise a click
    -- or a camera drag that starts over it goes through to the world.
    if event == "MODIFIER_STATE_CHANGED" then
        bar:EnableMouse(IsControlKeyDown())
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        QueueQuestScan()
    elseif event == "PLAYER_XP_UPDATE" then
        local xp, max = UnitXP("player"), UnitXPMax("player")
        local gained = xp >= lastXP and xp - lastXP or (lastXPMax - lastXP) + xp
        lastXP, lastXPMax = xp, max
        sessionXP = sessionXP + gained
    end
    Update()
end)

local function Place()
    local pos = S.Get("xpBarPos")
    bar:ClearAllPoints()
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
    end
end

local function Create()
    bar = CreateFrame("Frame", "NaowhForeverXPBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(false)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and IsControlKeyDown() then ns.ResetXPTicker() end
    end)
    Look.New(bar)

    bar.mover = ns.UI.AttachMover(bar, "XP Bar", function(pos) S.Set("xpBarPos", pos) end, "QoL/XP",
        "QoL/XP:xpBar")
end

local function Apply()
    ConvertOldTexts()
    OneEach(SLOTS)
    OneEach(INSIDE)
    UpdateTextColors()
    if not On() then
        events:UnregisterAllEvents()
        events:RegisterEvent("PLAYER_LOGOUT")
        Played.Drop("xpBar")
        if clock then clock:Cancel(); clock = nil end
        if bar then bar:Hide() end
        SetBlizzardHidden(false)
        sessionStart, sessionXP = nil, 0
        return
    end
    if not bar then Create() end
    PaintBar(bar)
    if not sessionStart then sessionStart, sessionXP = time(), 0 end

    Look.Size(bar, math.max(S.Get("xpBarWidth"), ns.XPBarMinWidth), S.Get("xpBarHeight"))
    Place()

    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
                         "PLAYER_UPDATE_RESTING", "QUEST_LOG_UPDATE",
                         "DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "PLAYER_LOGOUT", "MODIFIER_STATE_CHANGED" }) do
        events:RegisterEvent(e)
    end
    if ShowsText("played") then Played.Want("xpBar") else Played.Drop("xpBar") end
    if not clock then clock = C_Timer.NewTicker(1, Update) end

    SetBlizzardHidden(true)
    ScanQuests()
    bar.mover:SetShown(unlocked == true)
    Update()
end

-------------------------------------------------------------------------------
--  Settings preview
-------------------------------------------------------------------------------
-- The choices for the texts in and around the bar.
local BAR_TEXTS = {
    values = { none = "None", level = "Level", levelshort = "Level (Lvl 20)", levelnum = "Level (20)",
        xp = "Current / Max XP", percent = "XP Percent", rested = "Rested Percent" },
    order = { "none", "level", "levelshort", "levelnum", "xp", "percent", "rested" },
}
local SLOT_TEXTS = {
    values = { none = "None", played = "Played Time", session = "Session Time",
        completed = "Completed Quests (%)", completedxp = "Completed Quests (XP)",
        rested = "Rested Experience", leveling = "Time to Level", xphour = "XP per Hour" },
    order = { "none", "played", "session", "completed", "completedxp", "rested", "leveling", "xphour" },
}

local PREVIEW_PAD = 12         -- around the preview's contents
local PREVIEW_NOTE_H = 16      -- the line that says the spots can be clicked
local PREVIEW_SLOT_H = 18      -- a row of texts above or below the bar
local PREVIEW_SLOT_GAP = 4     -- the live bar's slot.y
local PREVIEW_BAR_MAX = 48     -- the Height slider's top, so the preview never changes height
local PREVIEW_FALLBACK_W = 870 -- the options page's content width, before layout has run
local PREVIEW_H = PREVIEW_PAD * 2 + PREVIEW_NOTE_H + (PREVIEW_SLOT_H + PREVIEW_SLOT_GAP) * 2 + PREVIEW_BAR_MAX

local SAMPLE_LEVEL, SAMPLE_MAX, SAMPLE_XP = 24, 23200, 9512
local SAMPLE_DONE, SAMPLE_OPEN, SAMPLE_RESTED = 2784, 1856, 3596
local SAMPLE_PLAYED, SAMPLE_THIS_LEVEL, SAMPLE_SESSION = 368520, 12540, 4320
local SAMPLE_TO_LEVEL, SAMPLE_RATE = 9600, 8100
local STATES = {
    { key = "levelling", label = "Levelling", tip = "Partway through a level, with quests to hand in." },
    { key = "rested", label = "Rested", tip = "With rested experience ahead of the fill." },
}

local function PreviewSlotText(which, rested)
    local LABEL, VALUE = ns.Color("muted"), ns.Color("fg")
    if which == "played" then
        return LABEL .. "Played:|r " .. VALUE .. Duration(SAMPLE_PLAYED) .. "|r - " .. LABEL .. "This Level:|r "
            .. VALUE .. Duration(SAMPLE_THIS_LEVEL) .. "|r"
    elseif which == "session" then
        return LABEL .. "Session:|r " .. VALUE .. Duration(SAMPLE_SESSION) .. "|r"
    elseif which == "completed" then
        return LABEL .. "Completed Quests:|r " .. questHex .. ("%.1f%%"):format(SAMPLE_DONE / SAMPLE_MAX * 100) .. "|r"
    elseif which == "completedxp" then
        return LABEL .. "Completed Quests:|r " .. questHex .. Grouped(SAMPLE_DONE) .. "|r"
    elseif which == "rested" then
        return LABEL .. "Rested:|r " .. restedHex .. ("%.1f%%"):format(rested / SAMPLE_MAX * 100) .. "|r"
    elseif which == "leveling" then
        return LABEL .. "Time to Level:|r " .. VALUE .. Duration(SAMPLE_TO_LEVEL) .. "|r"
    elseif which == "xphour" then
        return LABEL .. "XP/Hour:|r " .. VALUE .. Short(SAMPLE_RATE) .. "|r"
    end
    return ""
end

local PREVIEW_HOVER_ALPHA = 0.15
local ZONE_PAD = 4             -- a clickable spot reaches this far past its text
local SLOT_HINT = "|n|nCompleted Quests (both), Rested Experience, Time to Level and XP per Hour are "
    .. "hidden at max level."

-- Blizzard's menu, anchored under the spot, as the settings dropdowns open it.
local function OpenChoices(zone)
    if zone._menu and zone._menu:IsShown() then
        zone._menu:Close()
        zone._menu = nil
        return
    end
    if not (MenuUtil and MenuUtil.CreateRootMenuDescription and MenuVariants
        and Menu and Menu.GetManager and AnchorUtil) then return end
    local desc = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
    if not desc then return end
    if desc.CreateTitle then desc:CreateTitle(zone._label) end
    -- Where each text sits now, so picking one that is shown elsewhere says it will move.
    local shownAt = {}
    for _, spot in ipairs(zone._spots) do
        if spot.key ~= zone._key then shownAt[TextOf(S.Get(spot.key) or "none")] = spot.label end
    end
    local muted = ns.Color("muted")
    for _, k in ipairs(zone._choices.order) do
        local key = k
        local name = zone._choices.values[key]
        local at = key ~= "none" and shownAt[TextOf(key)]
        if at then name = name .. " " .. muted .. "(on " .. at .. ")|r" end
        desc:CreateRadio(name,
            function() return S.Get(zone._key) == key end,
            function()
                Claim(zone._spots, zone._key, key)
                S.Set(zone._key, key)
            end)
    end
    zone._menu = Menu.GetManager():OpenMenu(zone, desc,
        AnchorUtil.CreateAnchor("TOPLEFT", zone, "BOTTOMLEFT", 0, -2))
end

local function ChoiceName(zone)
    return zone._choices.values[S.Get(zone._key)] or zone._choices.values.none
end

-- A clickable spot over one of the preview's texts. spot is one entry of spots (INSIDE or
-- SLOTS), the group whose texts it shares. It sits under the text, so its hover tints behind it.
local function NewZone(parent, fs, spot, spots, choices, hint)
    local zone = CreateFrame("Button", nil, parent)
    zone._fs, zone._label, zone._key, zone._spots, zone._choices = fs, spot.label, spot.key, spots, choices
    zone._hint = hint or ""
    zone.hover = ns.Solid(zone, "BACKGROUND", T.accent, PREVIEW_HOVER_ALPHA)
    zone.hover:SetAllPoints()
    zone.hover:Hide()
    zone.border = ns.Border(zone, T.accent)
    zone.border._frame:Hide()
    -- Answering this keeps the menu manager from closing the menu before OnMouseDown toggles it.
    zone.HandlesGlobalMouseEvent = function(_, button, event)
        return event == "GLOBAL_MOUSE_DOWN" and button == "LeftButton"
    end
    zone:SetScript("OnMouseDown", OpenChoices)
    zone:SetScript("OnEnter", function(self)
        self.hover:Show()
        self.border._frame:Show()
        ns.UI.ShowWidgetTooltip(self, self._label .. ": " .. ChoiceName(self) .. "|nClick to change."
            .. self._hint, { anchor = "cursor", justify = "LEFT" })
    end)
    zone:SetScript("OnLeave", function(self)
        self.hover:Hide()
        self.border._frame:Hide()
        ns.UI.HideWidgetTooltip()
    end)
    zone:SetScript("OnHide", function(self)
        if self._menu then self._menu:Close(); self._menu = nil end
    end)
    return zone
end

-- As wide as what the spot shows, on the side its text is set to, so spots in a row never
-- cover each other.
local function HugText(zone, h)
    local fs = zone._fs
    local w = math.min(Natural(fs), fs:GetWidth()) + ZONE_PAD * 2
    local justify = fs:GetJustifyH()
    local point = justify == "LEFT" and "LEFT" or justify == "RIGHT" and "RIGHT" or "CENTER"
    local dx = point == "LEFT" and -ZONE_PAD or point == "RIGHT" and ZONE_PAD or 0
    zone:ClearAllPoints()
    zone:SetPoint(point, fs, point, dx, 0)
    zone:SetSize(w, h)
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.note = ns.Font(preview, 12, nil, T.muted)
    preview.note:SetPoint("TOPLEFT", PREVIEW_PAD, -PREVIEW_PAD)
    preview.note:SetText("Click a text on the bar, or a spot around it, to change what it shows.")
    local b = CreateFrame("Frame", nil, preview)
    preview.bar = b
    -- Above the spots around it, whose texts it draws.
    b:SetFrameLevel(preview:GetFrameLevel() + 2)
    Look.New(b)
    preview.inside, preview.slots = {}, {}
    for i, spot in ipairs(INSIDE) do
        local zone = NewZone(b, b.inside[i], spot, INSIDE, BAR_TEXTS)
        -- Over the fill, under the bar's border and texts.
        zone:SetFrameLevel(b:GetFrameLevel() + 3)
        preview.inside[i] = zone
    end
    for i, slot in ipairs(SLOTS) do
        local zone = NewZone(preview, b.slots[i], slot, SLOTS, SLOT_TEXTS, SLOT_HINT)
        zone:SetFrameLevel(preview:GetFrameLevel() + 1)
        preview.slots[i] = zone
    end
    return preview
end

-- An empty spot shows its name, so there is something to click.
local function Placeholder(fs, spot)
    if S.Get(spot.key) == "none" or not S.Get(spot.key) then
        fs:SetText(ns.Color("muted") .. "+ " .. spot.label .. "|r")
    end
end

local function PaintPreview(preview, state)
    UpdateTextColors()
    local b = preview.bar
    local rested = state == "rested" and SAMPLE_RESTED or 0
    for i, slot in ipairs(SLOTS) do
        b.slots[i]:SetText(PreviewSlotText(S.Get(slot.key), rested))
        Placeholder(b.slots[i], slot)
    end
    local beside = 0
    for _, i in ipairs(BESIDE) do
        SetSlotSize(b.slots[i], SLOT_FONT)
        beside = math.max(beside, Natural(b.slots[i]))
    end
    local avail = preview:GetWidth()
    if avail <= 0 then avail = PREVIEW_FALLBACK_W end
    local w = math.max(1, math.min(math.max(S.Get("xpBarWidth"), ns.XPBarMinWidth),
        avail - PREVIEW_PAD * 2 - (beside + SIDE_GAP) * 2))
    local h = S.Get("xpBarHeight")
    PaintBar(b)
    Look.Size(b, w, h)
    b:ClearAllPoints()
    b:SetPoint("TOP", preview, "TOP", 0, -(PREVIEW_PAD + PREVIEW_NOTE_H + PREVIEW_SLOT_H + PREVIEW_SLOT_GAP
        + (PREVIEW_BAR_MAX - h) / 2))
    local pct = SAMPLE_XP / SAMPLE_MAX * 100
    Look.Segments(b, w, pct, SAMPLE_DONE, SAMPLE_OPEN, rested, SAMPLE_MAX, false)
    Look.Texts(b, SAMPLE_LEVEL, SAMPLE_XP, SAMPLE_MAX, false, pct, rested)
    for i, spot in ipairs(INSIDE) do Placeholder(b.inside[i], spot) end
    Look.Fit(b, w, h)
    for _, zone in ipairs(preview.inside) do HugText(zone, h) end
    for _, zone in ipairs(preview.slots) do HugText(zone, PREVIEW_SLOT_H) end
end

-- Width, height and which text is in each spot back to their defaults. Where the bar sits,
-- its colours and its switches stay as they are.
function ns.ResetXPBarLayout()
    ns.Confirm("Put the XP Bar's size and texts back to their defaults?", function()
        local db = S.DB()
        db.xpBarWidth, db.xpBarHeight = nil, nil
        for _, spot in ipairs(SLOTS) do db[spot.key] = nil end
        for _, spot in ipairs(INSIDE) do db[spot.key] = nil end
        S.Set("xpBarWidth", nil)
        -- So the sliders show the defaults again.
        ns.UI:RefreshPage(true)
    end)
end

local Group = ns.Shared.Settings.Group
local SAME_COLOUR = 1 / 255
local BAR_TEXT_HELP = "A text on the bar: click it on the preview to change it. Each text shows in one "
    .. "place on the bar: picking one shown elsewhere moves it there."
local SLOT_TEXT_HELP = "A text around the bar: click it on the preview to change it. Each text shows in "
    .. "one place around it: picking one shown elsewhere moves it there. Completed Quests (both), Rested Experience, Time to Level and "
    .. "XP per Hour are hidden at max level."

local function SetColour(key, r, g, b)
    local d = ns.XPBarDefaultColor(key)
    if math.abs(r - d.r) <= SAME_COLOUR and math.abs(g - d.g) <= SAME_COLOUR and math.abs(b - d.b) <= SAME_COLOUR then
        if S.Get(key) ~= nil then S.Set(key, nil) end
    else
        S.Set(key, { r = r, g = g, b = b })
    end
end

local function ColourRow(key, label, help)
    return { key = key, label = label, colour = true, help = help,
        get = function()
            local c = ns.XPBarColor(key)
            return c.r, c.g, c.b, 1
        end,
        set = function(r, g, b) SetColour(key, r, g, b) end }
end

-- The texts are picked on the preview, so their rows are not drawn; they are still declared
-- for the search, the changed count and the card's Reset.
local function Hidden(row)
    row.hidden = true
    return row
end

local function TextRow(spot, spots, choices, help)
    local key = spot.key
    return { key = key, label = spot.label, choice = choices, help = help, hidden = true,
        get = function() return S.Get(key) end,
        set = function(which)
            Claim(spots, key, which)
            S.Set(key, which)
        end }
end

local ROWS = {
    Group("Size"),
    { key = "xpBarWidth", label = "Width", slider = { ns.XPBarMinWidth, 1200, 10 } },
    { key = "xpBarHeight", label = "Height", slider = { 14, 48, 1 } },
    { label = "Reset Size & Texts", buttonText = "Reset", button = ns.ResetXPBarLayout,
      help = "Width, height and the text in each spot back to their defaults. Where the bar sits, its "
          .. "colours and its switches stay as they are." },
    Group("Show"),
    { key = "xpBarMaxLevel", label = "Show at Max Level", toggle = true,
      help = "Keeps the bar up at max level, with your played time and session." },
    { key = "xpBarIncomplete", label = "Incomplete Quests", toggle = true,
      help = "The XP of quests still in progress, as a faded segment after the completed ones." },
    { key = "xpBarResetOnReload", label = "Reset Session on Reload", toggle = true,
      help = "Starts the session time and XP/Hour again on a /reload. Off: a /reload carries on the "
          .. "session. A fresh login always starts a new one." },
    Group("Colours"),
    ColourRow("xpBarFillColor", "Fill Colour", "Your experience. Its left end is a darker shade."),
    ColourRow("xpBarQuestColor", "Completed Quests Colour",
        "The XP of completed quests, and their text. Incomplete quests show it faded."),
    ColourRow("xpBarRestedColor", "Rested Colour", "Rested experience, and its text."),
    ColourRow("xpBarBgColor", "Background Colour", "Behind the fill."),
    { label = "Reset Colours", buttonText = "Reset Colours", button = ns.ResetXPBarColors,
      help = "The four colours back to their defaults, which follow the theme." },
    Hidden(Group("Text")),
}
for _, spot in ipairs(INSIDE) do ROWS[#ROWS + 1] = TextRow(spot, INSIDE, BAR_TEXTS, BAR_TEXT_HELP) end
ROWS[#ROWS + 1] = Hidden(Group("Around the Bar"))
for _, slot in ipairs(SLOTS) do ROWS[#ROWS + 1] = TextRow(slot, SLOTS, SLOT_TEXTS, SLOT_TEXT_HELP) end

local function Summary(store)
    return ("%d by %d%s"):format(math.max(store.Get("xpBarWidth"), ns.XPBarMinWidth), store.Get("xpBarHeight"),
        store.Get("xpBarMaxLevel") and ", shown at max level" or "")
end

ns.Shared.Settings.Page("QoL/XP", S):Card({
    id = "xpBar", name = "XP Bar", order = 10, switch = "xpBar",
    help = "Your level, experience and percentage on one bar, with the XP of completed quests and rested "
        .. "experience drawn past the fill. Replaces Blizzard's experience bar while it is on. Move it in "
        .. "Unlock Mode. Ctrl + right-click the bar to reset the session time and XP/Hour.",
    summary = Summary,
    studio = { height = PREVIEW_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = ROWS,
})

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^xpBar") and key ~= "xpBarPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(Played, "Answered", PlayedChanged)
hooksecurefunc(Played, "LeveledUp", PlayedChanged)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if bar then
        bar.mover:Hide()
        Apply()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self, _, isLogin, isReload)
    if not (isLogin or isReload) then return end
    self:UnregisterAllEvents()
    LoadSession(isReload)
    Apply()
end)
