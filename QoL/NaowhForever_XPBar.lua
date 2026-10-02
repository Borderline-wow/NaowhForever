-------------------------------------------------------------------------------
--  NaowhForever_XPBar.lua -- the QoL XP bar, with completed quest XP and rested drawn on it and
--  a choice of texts around it. Replaces Blizzard's experience bar while on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

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
-- TIME_PLAYED_MSG totals and the GetTime() they arrived at, so the clock can run on.
local playedTotal, playedLevel, playedAt
local mutedChat = {}

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
--  Played time
-------------------------------------------------------------------------------
-- RequestTimePlayed prints to every chat frame; they are muted for our own request only
-- and given the event back on the next frame, or after a few seconds if no answer comes.
local function RestoreChat()
    for _, cf in ipairs(mutedChat) do cf:RegisterEvent("TIME_PLAYED_MSG") end
    wipe(mutedChat)
end

local function RequestPlayed()
    if #mutedChat > 0 then return end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            mutedChat[#mutedChat + 1] = cf
        end
    end
    RequestTimePlayed()
    C_Timer.After(5, RestoreChat)
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
        if not playedTotal then return "" end
        local since = GetTime() - playedAt
        return LABEL .. "Played:|r " .. VALUE .. Duration(playedTotal + since) .. "|r - "
            .. LABEL .. "This Level:|r " .. VALUE .. Duration(playedLevel + since) .. "|r"
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
    local values = {
        none = "", level = "Level " .. UnitLevel("player"), levelshort = "Lvl " .. UnitLevel("player"),
        levelnum = tostring(UnitLevel("player")),
        xp = maxed and "Max Level" or (xp .. " / " .. max),
        percent = ("%.1f%%"):format(pct),
        rested = ("Rested %.1f%%"):format((GetXPExhaustion() or 0) / max * 100),
    }
    bar.level:SetText(values[S.Get("xpBarLeftText") or "level"] or "")
    bar.value:SetText(values[S.Get("xpBarCenterText") or "xp"] or "")
    bar.pct:SetText(values[S.Get("xpBarRightText") or "percent"] or "")

    -- The whole bar is the track: a full bar is 100%.
    local total = bar:GetWidth()

    local x = Segment(bar.fill, 0, total * pct / 100, total)
    if maxed then
        bar.done:Hide(); bar.open:Hide(); bar.rested:Hide()
    else
        x = Segment(bar.done, x, total * questDone / max, total)
        if S.Get("xpBarIncomplete") then
            Segment(bar.open, x, total * questOpen / max, total)
        else
            bar.open:Hide()
        end
        -- Rested runs from the end of your XP like Blizzard's, the full height of the bar and
        -- drawn over the quest segments, so a bar full of quest XP cannot push it off the
        -- end. At least 3px, so a sliver of rest still reads.
        local rested = GetXPExhaustion() or 0
        local from = total * pct / 100
        local w = math.min(math.max(total * rested / max, 3), total - from)
        if rested > 0 and w >= 1 then
            bar.rested:ClearAllPoints()
            bar.rested:SetPoint("TOPLEFT", from, 0)
            bar.rested:SetPoint("BOTTOMLEFT", from, 0)
            bar.rested:SetWidth(w)
            bar.rested:Show()
        else
            bar.rested:Hide()
        end
    end

    for i, slot in ipairs(SLOTS) do
        bar.slots[i]:SetText(SlotText(S.Get(slot.key), maxed, max))
    end
    -- Measuring and placing the texts only when one of them, or the bar, has changed.
    local insideChanged = TextsChanged(bar.inside)
    local slotsChanged = TextsChanged(bar.slots)
    local h, font = bar:GetHeight(), ns.UIFontPath()
    if insideChanged or slotsChanged or bar._fitW ~= total or bar._fitH ~= h or bar._fitFont ~= font then
        bar._fitW, bar._fitH, bar._fitFont = total, h, font
        FitInside(bar.inside, total, h, bar.placeInside)
        FitSlots(bar.slots, total, bar.placeMid)
    end
    bar:Show()
end

local function QueueQuestScan()
    if questTimer then return end
    questTimer = C_Timer.NewTimer(0.3, function() ScanQuests(); Update() end)
end

function ns.ResetXPBarSession()
    if not sessionStart then return end
    sessionStart, sessionXP = time(), 0
    SaveSession()
    Update()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
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
    if event == "TIME_PLAYED_MSG" then
        playedTotal, playedLevel, playedAt = arg1, arg2, GetTime()
        C_Timer.After(0, RestoreChat)
    elseif event == "PLAYER_LEVEL_UP" then
        if playedTotal then
            playedTotal, playedLevel, playedAt = playedTotal + GetTime() - playedAt, 0, GetTime()
        end
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
    -- Coloured by PaintBar.
    bar.bg = ns.Solid(bar, "BACKGROUND", T.bg, BG_ALPHA)
    bar.bg:SetAllPoints()

    -- The track holds the fill and segments, the full width of the bar.
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetAllPoints()
    bar.track:SetClipsChildren(true)
    bar.track:SetFrameLevel(bar:GetFrameLevel() + 1)
    bar.fill = bar.track:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.done = ns.Solid(bar.track, "ARTWORK", QUEST, 1)
    bar.open = ns.Solid(bar.track, "ARTWORK", QUEST, OPEN_ALPHA)
    bar.rested = ns.Solid(bar.track, "ARTWORK", RESTED, 1)
    bar.rested:SetDrawLayer("ARTWORK", 0)
    bar.done:SetDrawLayer("ARTWORK", 1)
    bar.open:SetDrawLayer("ARTWORK", 1)

    -- Above the track, whose own frame would otherwise cover the border.
    ns.Border(bar)._frame:SetFrameLevel(bar:GetFrameLevel() + 4)

    local text = CreateFrame("Frame", nil, bar)
    text:SetAllPoints()
    text:SetFrameLevel(bar:GetFrameLevel() + 5)
    bar.level = ns.Font(text, 14, "OUTLINE")
    bar.level:SetPoint("LEFT", bar.track, "LEFT", INSIDE_INSET, 0)
    bar.level:SetJustifyH("LEFT")
    bar.value = ns.Font(text, 14, "OUTLINE")
    bar.value:SetPoint("CENTER", bar.track, "CENTER")
    bar.pct = ns.Font(text, 14, "OUTLINE")
    bar.pct:SetPoint("RIGHT", bar.track, "RIGHT", -INSIDE_INSET, 0)
    bar.pct:SetJustifyH("RIGHT")
    bar.inside = { bar.level, bar.value, bar.pct }
    for _, fs in ipairs(bar.inside) do fs:SetWordWrap(false) end
    bar.placeInside = function(_, dx)
        bar.value:ClearAllPoints()
        bar.value:SetPoint("CENTER", bar.track, "CENTER", dx, 0)
    end
    bar.slots = {}
    for i, slot in ipairs(SLOTS) do
        local fs = ns.Font(bar, SLOT_FONT, "OUTLINE")
        fs:SetPoint(slot.point, bar, slot.rel, slot.x or 0, slot.y)
        fs:SetJustifyH(slot.justify)
        fs:SetWordWrap(false)
        bar.slots[i] = fs
    end
    bar.placeMid = function(i, dx)
        local fs, slot = bar.slots[i], SLOTS[i]
        fs:ClearAllPoints()
        fs:SetPoint(slot.point, bar, slot.rel, dx, slot.y)
    end

    bar.mover = ns.UI.AttachMover(bar, "XP Bar", function(pos) S.Set("xpBarPos", pos) end)
end

local function Apply()
    ConvertOldTexts()
    OneEach(SLOTS)
    OneEach(INSIDE)
    UpdateTextColors()
    if not On() then
        events:UnregisterAllEvents()
        events:RegisterEvent("PLAYER_LOGOUT")
        if clock then clock:Cancel(); clock = nil end
        if bar then bar:Hide() end
        SetBlizzardHidden(false)
        sessionStart, sessionXP = nil, 0
        return
    end
    if not bar then Create() end
    PaintBar(bar)
    if not sessionStart then sessionStart, sessionXP = time(), 0 end

    local w, h = math.max(S.Get("xpBarWidth"), ns.XPBarMinWidth), S.Get("xpBarHeight")
    bar:SetSize(w, h)
    -- At the height's size, so the first fit measures from it; Update shrinks them if needed.
    for _, fs in ipairs(bar.inside) do SetSlotSize(fs, InsideFont(h)) end
    -- Their size was just reset, so the next Update fits them again.
    bar._fitW = nil
    Place()

    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
                         "PLAYER_UPDATE_RESTING", "QUEST_LOG_UPDATE", "TIME_PLAYED_MSG",
                         "DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "PLAYER_LOGOUT", "MODIFIER_STATE_CHANGED" }) do
        events:RegisterEvent(e)
    end
    if ShowsText("played") and not playedTotal then RequestPlayed() end
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
local PREVIEW_NOTE_H = 16
local PREVIEW_SLOT_H = 18      -- a row of texts above or below the bar
local PREVIEW_SLOT_GAP = 4     -- the live bar's slot.y
local PREVIEW_BAR_MAX = 48     -- the Height slider's top, so the preview never changes height
local PREVIEW_FALLBACK_W = 870 -- the options page's content width, before layout has run
local PREVIEW_HOVER_ALPHA = 0.15
local PREVIEW_H = PREVIEW_PAD * 2 + PREVIEW_NOTE_H + (PREVIEW_SLOT_H + PREVIEW_SLOT_GAP) * 2
    + PREVIEW_BAR_MAX

local preview

-- What a slot shows: the live text while the bar runs, else a made-up example.
local function PreviewSlotText(which, max)
    if sessionStart then
        local live = SlotText(which, AtMaxLevel(), max)
        if live ~= "" then return live end
    end
    local LABEL, VALUE = ns.Color("muted"), ns.Color("fg")
    local samples = {
        played = LABEL .. "Played:|r " .. VALUE .. "4d 6h 22m|r - " .. LABEL .. "This Level:|r "
            .. VALUE .. "3d 11h 39m|r",
        session = LABEL .. "Session:|r " .. VALUE .. "1h 12m|r",
        completed = LABEL .. "Completed Quests:|r " .. questHex .. "12.0%|r",
        completedxp = LABEL .. "Completed Quests:|r " .. questHex .. "2,784|r",
        rested = LABEL .. "Rested:|r " .. restedHex .. "15.5%|r",
        leveling = LABEL .. "Time to Level:|r " .. VALUE .. "2h 40m|r",
        xphour = LABEL .. "XP/Hour:|r " .. VALUE .. "8.1k|r",
    }
    return samples[which] or ""
end

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

-- spot is one entry of spots (INSIDE or SLOTS), the group whose texts it shares.
local function NewZone(parent, spot, spots, choices, inset)
    local zone = CreateFrame("Button", nil, parent)
    zone:EnableMouse(true)
    zone._label, zone._key, zone._spots, zone._choices = spot.label, spot.key, spots, choices
    local justify = spot.justify
    zone.hover = ns.Solid(zone, "BACKGROUND", T.accent, PREVIEW_HOVER_ALPHA)
    zone.hover:SetAllPoints()
    zone.hover:Hide()
    zone.border = ns.Border(zone, T.accent)
    zone.border._frame:Hide()
    zone.text = ns.Font(zone, SLOT_FONT, "OUTLINE")
    zone.text:SetPoint("LEFT", inset, 0)
    zone.text:SetPoint("RIGHT", -inset, 0)
    zone.text:SetJustifyH(justify)
    zone.text:SetWordWrap(false)
    -- Answering this keeps the menu manager from closing the menu before OnMouseDown toggles it.
    zone.HandlesGlobalMouseEvent = function(_, button, event)
        return event == "GLOBAL_MOUSE_DOWN" and button == "LeftButton"
    end
    zone:SetScript("OnMouseDown", OpenChoices)
    zone:SetScript("OnEnter", function(self)
        self.hover:Show()
        self.border._frame:Show()
        ns.UI.ShowWidgetTooltip(self, self._label .. ": " .. ChoiceName(self) .. "|nClick to change."
            .. (self._hint or ""),
            { anchor = "cursor", justify = "LEFT" })
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

local function NewPreview(parent)
    local f = CreateFrame("Frame", nil, parent)
    ns.Solid(f, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(f, { r = 0, g = 0, b = 0 })
    f.note = ns.Font(f, 12, nil, T.muted)
    f.note:SetPoint("TOPLEFT", PREVIEW_PAD, -PREVIEW_PAD)
    f.note:SetText("Click a text on the bar, or a spot around it, to change what it shows.")

    local b = CreateFrame("Frame", nil, f)
    f.bar = b
    b.bg = ns.Solid(b, "BACKGROUND", T.bg, BG_ALPHA)
    b.bg:SetAllPoints()
    b.track = CreateFrame("Frame", nil, b)
    b.track:SetAllPoints()
    b.track:SetClipsChildren(true)
    b.fill = b.track:CreateTexture(nil, "ARTWORK")
    b.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.done = ns.Solid(b.track, "ARTWORK", QUEST, 1)
    b.done:SetDrawLayer("ARTWORK", 1)
    b.rested = ns.Solid(b.track, "ARTWORK", RESTED, 1)
    b.rested:SetDrawLayer("ARTWORK", 0)
    ns.Border(b)._frame:SetFrameLevel(b:GetFrameLevel() + 4)

    f.inside = {}
    for i, spot in ipairs(INSIDE) do
        local zone = NewZone(b, spot, INSIDE, BAR_TEXTS, 0)
        zone:SetFrameLevel(b:GetFrameLevel() + 5)
        f.inside[i] = zone
    end
    f.slots = {}
    for i, slot in ipairs(SLOTS) do
        local zone = NewZone(f, slot, SLOTS, SLOT_TEXTS, 0)
        zone._hint = "|n|nCompleted Quests (both), Rested Experience, Time to Level and XP per "
            .. "Hour are hidden at max level."
        f.slots[i] = zone
    end
    -- What the fitting measures and sizes: each spot's text, its width applied to the spot
    -- around it, so a spot is as wide as what it shows.
    local function Fit(zone)
        local fs = zone.text
        return {
            GetText = function() return fs:GetText() end,
            GetStringWidth = function() return fs:GetStringWidth() end,
            GetUnboundedStringWidth = fs.GetUnboundedStringWidth
                and function() return fs:GetUnboundedStringWidth() end or nil,
            SetWidth = function(_, width) zone:SetWidth(width) end,
            SetFont = function(_, ...) fs:SetFont(...) end,
        }
    end
    f.fits, f.insideFits = {}, {}
    for i, zone in ipairs(f.slots) do f.fits[i] = Fit(zone) end
    for i, zone in ipairs(f.inside) do
        f.insideFits[i] = Fit(zone)
        f.insideFits[i]._fitSize = SLOT_FONT -- NewZone's size, until the first fit sets theirs
    end
    f:SetHeight(PREVIEW_H)
    f:SetScript("OnSizeChanged", function(self) self:Refresh() end)

    function f:Refresh()
        UpdateTextColors()
        local maxed = AtMaxLevel()
        local xp, max = UnitXP("player"), math.max(UnitXPMax("player"), 1)
        local muted = ns.Color("muted")
        -- The texts first: the bar is drawn narrower when the ones beside it need the room.
        for _, zone in ipairs(self.slots) do
            local which = S.Get(zone._key) or "none"
            zone.text:SetText(which == "none" and (muted .. "+ " .. zone._label .. "|r")
                or PreviewSlotText(which, max))
        end
        local beside = 0
        for _, i in ipairs(BESIDE) do beside = math.max(beside, Natural(self.fits[i])) end

        local avail = self:GetWidth()
        if avail <= 0 then avail = self:GetParent():GetWidth() - ns.UI.CONTENT_PAD * 2 end
        if avail <= 0 then avail = PREVIEW_FALLBACK_W end
        local w = math.min(math.max(S.Get("xpBarWidth"), ns.XPBarMinWidth),
            avail - PREVIEW_PAD * 2 - (beside + SIDE_GAP) * 2)
        local h = S.Get("xpBarHeight")
        local pv = self.bar
        PaintBar(pv)
        pv:SetSize(w, h)
        pv:ClearAllPoints()
        -- Centred in the room the tallest bar would take.
        pv:SetPoint("TOP", self, "TOP", 0, -(PREVIEW_PAD + PREVIEW_NOTE_H + PREVIEW_SLOT_H
            + PREVIEW_SLOT_GAP + (PREVIEW_BAR_MAX - h) / 2))

        local pct = maxed and 1 or xp / max
        local x = Segment(pv.fill, 0, w * pct, w)
        Segment(pv.done, x, maxed and 0 or w * questDone / max, w)
        Segment(pv.rested, w * pct, maxed and 0 or w * (GetXPExhaustion() or 0) / max, w)

        local values = {
            none = "", level = "Level " .. UnitLevel("player"), levelshort = "Lvl " .. UnitLevel("player"),
            levelnum = tostring(UnitLevel("player")),
            xp = maxed and "Max Level" or (xp .. " / " .. max),
            percent = ("%.1f%%"):format(pct * 100),
            rested = ("Rested %.1f%%"):format((GetXPExhaustion() or 0) / max * 100),
        }
        for i, zone in ipairs(self.inside) do
            local spot = INSIDE[i]
            zone:ClearAllPoints()
            zone:SetPoint(spot.point, pv, spot.point, spot.dir * INSIDE_INSET, 0)
            zone:SetHeight(h)
            local which = S.Get(zone._key) or "none"
            zone.text:SetText(which == "none" and (muted .. "+ " .. zone._label .. "|r") or values[which])
        end
        FitInside(self.insideFits, w, h, function(_, dx)
            local zone = self.inside[2]
            zone:ClearAllPoints()
            zone:SetPoint("CENTER", pv, "CENTER", dx, 0)
        end)
        -- Sized like the live bar's texts; an empty spot's placeholder counts as its text.
        for i, zone in ipairs(self.slots) do
            local slot = SLOTS[i]
            zone:ClearAllPoints()
            zone:SetPoint(slot.point, pv, slot.rel, slot.x or 0, slot.y)
            zone:SetHeight(PREVIEW_SLOT_H)
        end
        FitSlots(self.fits, w, function(i, dx)
            local zone, slot = self.slots[i], SLOTS[i]
            zone:ClearAllPoints()
            zone:SetPoint(slot.point, pv, slot.rel, dx, slot.y)
        end)
    end
    return f
end

-- The spots the preview stands for, so the settings search finds them and jumps to it.
local SEARCH_LABELS, SEARCH_SET = {}, {}
for _, spots in ipairs({ INSIDE, SLOTS }) do
    for _, spot in ipairs(spots) do
        SEARCH_LABELS[#SEARCH_LABELS + 1] = spot.label
        SEARCH_SET[spot.label] = true
    end
end
local SEARCH_TIP = "A text on or around the XP Bar. Click it on the preview to pick what it shows."

-- The preview under the XP Bar switch on the settings page. Hidden with the feature's options
-- while they are folded away, and built only when the page first shows it.
function ns.BuildXPBarPreview(parent, y)
    if ns.UI.searchScan then
        ns.UI.ScanLabels(SEARCH_LABELS, SEARCH_TIP)
        return nil, 0
    end
    local f = ns.UI.Keep(parent, "xpBarPreview", NewPreview)
    if parent._nsuiCollapsed then
        f:Hide()
        return f, 0
    end
    preview = f
    f._searchLabels, f._searchF = SEARCH_SET, parent._nsuiFeatureId
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", ns.UI.CONTENT_PAD, y)
    f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -ns.UI.CONTENT_PAD, y)
    f:Refresh()
    return f, PREVIEW_H + PREVIEW_PAD
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

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^xpBar") and key ~= "xpBarPos") then Apply() end
    if preview and preview:IsVisible() and key:find("^xpBar") then preview:Refresh() end
end)
hooksecurefunc(ns, "Apply", Apply)
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
