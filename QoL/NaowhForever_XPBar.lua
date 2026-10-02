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

local bar, clock, unlocked, questTimer
-- nil while the bar is off: XP is only counted while it is on, so the clock starts with it.
local sessionStart, sessionXP = nil, 0
local lastXP, lastXPMax
local questDone, questOpen = 0, 0
-- TIME_PLAYED_MSG totals and the GetTime() they arrived at, so the clock can run on.
local playedTotal, playedLevel, playedAt
local mutedChat = {}

-- The spots around the bar a text can go, each the setting that picks its text.
local SLOTS = {
    { key = "xpBarTopLeft", point = "BOTTOMLEFT", rel = "TOPLEFT", y = 4, justify = "LEFT" },
    { key = "xpBarTopRight", point = "BOTTOMRIGHT", rel = "TOPRIGHT", y = 4, justify = "RIGHT" },
    { key = "xpBarBottomLeft", point = "TOPLEFT", rel = "BOTTOMLEFT", y = -4, justify = "LEFT" },
    { key = "xpBarBottom", point = "TOP", rel = "BOTTOM", y = -4, justify = "CENTER" },
    { key = "xpBarBottomRight", point = "TOPRIGHT", rel = "BOTTOMRIGHT", y = -4, justify = "RIGHT" },
}

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
        return LABEL .. "Completed Quests:|r " .. (ns.ThemeTint("accentSoft", nil) and ns.Color("accentSoft") or QUEST_HEX) .. ("%.1f%%"):format(questDone / max * 100) .. "|r"
    elseif which == "rested" then
        return LABEL .. "Rested:|r " .. (ns.ThemeTint("accent", nil) and ns.Color("accent") or RESTED_HEX) .. ("%.1f%%"):format((GetXPExhaustion() or 0) / max * 100) .. "|r"
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
        none = "", level = "Level " .. UnitLevel("player"),
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
    ns.Solid(bar, "BACKGROUND", T.bg, 0.85):SetAllPoints()

    -- The track holds the fill and segments, the full width of the bar.
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetAllPoints()
    bar.track:SetClipsChildren(true)
    bar.track:SetFrameLevel(bar:GetFrameLevel() + 1)
    bar.fill = bar.track:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    -- The dark end follows a changed accent; the shipped blue stays as it was otherwise.
    local shifted = ns.ThemeTint("accent", nil)
    local from = shifted and CreateColor(shifted.r * 0.55, shifted.g * 0.55, shifted.b * 0.55, 1) or FILL_FROM
    bar.fill:SetGradient("HORIZONTAL", from, CreateColor(T.accent.r, T.accent.g, T.accent.b, 1))
    -- Quest XP is the logo's gold; a theme changes it to its lighter accent, which reads
    -- apart from the fill's accent.
    local quest = ns.ThemeTint("accentSoft", QUEST)
    bar.done = ns.Solid(bar.track, "ARTWORK", quest, 1)
    bar.open = ns.Solid(bar.track, "ARTWORK", quest, 0.4)
    -- Rested sits just ahead of the fill: a deeper shade of a changed accent, the royal blue otherwise.
    local rested = shifted and { r = shifted.r * 0.7, g = shifted.g * 0.7, b = shifted.b * 0.7 } or RESTED
    bar.rested = ns.Solid(bar.track, "ARTWORK", rested, 1)
    bar.rested:SetDrawLayer("ARTWORK", 0)
    bar.done:SetDrawLayer("ARTWORK", 1)
    bar.open:SetDrawLayer("ARTWORK", 1)

    -- Above the track, whose own frame would otherwise cover the border.
    ns.Border(bar)._frame:SetFrameLevel(bar:GetFrameLevel() + 4)

    local text = CreateFrame("Frame", nil, bar)
    text:SetAllPoints()
    text:SetFrameLevel(bar:GetFrameLevel() + 5)
    bar.level = ns.Font(text, 14, "OUTLINE")
    bar.level:SetPoint("LEFT", bar.track, "LEFT", 8, 0)
    bar.level:SetJustifyH("LEFT")
    bar.value = ns.Font(text, 14, "OUTLINE")
    bar.value:SetPoint("CENTER", bar.track, "CENTER")
    bar.pct = ns.Font(text, 14, "OUTLINE")
    bar.pct:SetPoint("RIGHT", bar.track, "RIGHT", -8, 0)
    bar.pct:SetJustifyH("RIGHT")
    bar.slots = {}
    for i, slot in ipairs(SLOTS) do
        local fs = ns.Font(bar, 13, "OUTLINE")
        fs:SetPoint(slot.point, bar, slot.rel, 0, slot.y)
        fs:SetJustifyH(slot.justify)
        fs:SetWordWrap(false)
        bar.slots[i] = fs
    end

    bar.mover = ns.UI.AttachMover(bar, "XP Bar", function(pos) S.Set("xpBarPos", pos) end)
end

local function Apply()
    ConvertOldTexts()
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
    if not sessionStart then sessionStart, sessionXP = time(), 0 end

    local w, h = S.Get("xpBarWidth"), S.Get("xpBarHeight")
    bar:SetSize(w, h)
    local size = math.max(10, math.floor(h * 0.55))
    for _, fs in ipairs({ bar.level, bar.value, bar.pct }) do
        fs:SetFont(ns.UIFontPath(), size, "OUTLINE")
    end
    for _, fs in ipairs({ bar.level, bar.value, bar.pct }) do
        fs:SetWidth(math.max(1, w / 3 - 16))
        fs:SetWordWrap(false)
    end
    -- Texts sharing a row split its width, so a long one cuts off instead of running into
    -- its neighbour.
    local used = {}
    for i, slot in ipairs(SLOTS) do used[i] = (S.Get(slot.key) or "none") ~= "none" end
    local top = (used[1] and used[2]) and 2 or 1
    local bottom = used[4] and ((used[3] or used[5]) and 3 or 1) or ((used[3] and used[5]) and 2 or 1)
    for i, fs in ipairs(bar.slots) do
        fs:SetWidth(math.max(1, w / (i <= 2 and top or bottom) - 8))
    end
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

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^xpBar") and key ~= "xpBarPos") then Apply() end
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
