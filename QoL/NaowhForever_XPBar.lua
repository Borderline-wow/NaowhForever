-------------------------------------------------------------------------------
--  NaowhForever_XPBar.lua -- the QoL XP bar: level, experience and percentage on one
--  bar, with the XP of completed quests drawn as segments past the fill, rested
--  experience over them from the end of your XP, and optional played, session and
--  levelling lines underneath. Replaces Blizzard's experience bar while it is on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

-- Naowh's blue for the fill, deepening to the left; the gold of his logo for quest XP; a
-- deep royal blue for rested, darker than where the fill ends so the two read apart. Its
-- text is a lighter shade of the same blue, which the dark background can carry.
local FILL_FROM = CreateColor(0x00 / 255, 0x4f / 255, 0x85 / 255, 1)
local FILL_TO   = CreateColor(T.accent.r, T.accent.g, T.accent.b, 1)
local QUEST     = { r = 0xf2 / 255, g = 0xa9 / 255, b = 0x00 / 255 }
local RESTED    = { r = 0x1e / 255, g = 0x40 / 255, b = 0xaf / 255 }
local QUEST_HEX, RESTED_HEX, VALUE = "|cfff2a900", "|cff6b8cff", "|cfff0f1f3"
local LABEL = "|cff9a9ea6"

local bar, clock, unlocked, questTimer
-- nil while the bar is off: XP is only counted while it is on, so the clock starts with it.
local sessionStart, sessionXP = nil, 0
local lastXP, lastXPMax
local questDone, questOpen = 0, 0
-- TIME_PLAYED_MSG totals and the GetTime() they arrived at, so the clock can run on.
local playedTotal, playedLevel, playedAt
local mutedChat = {}

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
-- Hidden rather than unregistered, so switching the bar off gives the default one back
-- without a reload. Retail-engine clients track XP in the status tracking containers,
-- older ones in MainMenuExpBar. Only the container holding the XP bar is hidden: at max
-- level the same container carries the watched reputation instead.
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
    return frame.shownBarIndex == nil or frame.shownBarIndex == StatusTrackingBarInfo.BarsEnum.Experience
end

local function Refresh(frame)
    if InCombatLockdown() and frame:IsProtected() then return end
    if hideBlizzard and ShowsXP(frame) then
        frame:Hide()
    elseif frame.UpdateShownState then
        frame:UpdateShownState()
    elseif not hideBlizzard then
        frame:Show()
    end
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
local function SubLines(maxed, max)
    local lines = {}
    local function Add(...) lines[#lines + 1] = table.concat({ ... }, " - ") end
    local elapsed = time() - sessionStart

    if not maxed and S.Get("xpBarCompleted") then
        local rested = GetXPExhaustion() or 0
        Add(LABEL .. "Completed Quests:|r " .. QUEST_HEX .. ("%.1f%%"):format(questDone / max * 100) .. "|r",
            LABEL .. "Rested Experience:|r " .. RESTED_HEX .. ("%.1f%%"):format(rested / max * 100) .. "|r")
    end
    if not maxed and S.Get("xpBarLeveling") then
        local rate = sessionXP / (math.max(elapsed, 60) / 3600)
        local left = math.max(max - UnitXP("player"), 0)
        Add(LABEL .. "Time to Level:|r " .. VALUE .. (rate > 0 and Duration(left / rate * 3600) or "--") .. "|r",
            LABEL .. "XP/Hour:|r " .. VALUE .. Short(rate) .. "|r")
    end
    if S.Get("xpBarPlayed") and playedTotal then
        local since = GetTime() - playedAt
        Add(LABEL .. "Played:|r " .. VALUE .. Duration(playedTotal + since) .. "|r",
            LABEL .. "This Level:|r " .. VALUE .. Duration(playedLevel + since) .. "|r")
    end
    if S.Get("xpBarSession") then
        Add(LABEL .. "Session:|r " .. VALUE .. Duration(elapsed) .. "|r")
    end
    return table.concat(lines, "\n")
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
    bar.level:SetText("Level " .. UnitLevel("player"))
    if maxed then
        bar.value:SetText("Max Level")
        bar.pct:SetText("100%")
    else
        bar.value:SetText(xp .. " / " .. max)
        local withQuests = questDone > 0
            and (" (%.1f%%)"):format(math.min((xp + questDone) / max * 100, 100)) or ""
        bar.pct:SetText(("%.1f%%"):format(pct) .. withQuests)
    end

    -- The whole bar is the track: a full bar is 100%.
    local total = bar:GetWidth()

    local x = Segment(bar.fill, 0, total * pct / 100, total)
    if maxed then
        bar.done:Hide(); bar.open:Hide(); bar.rested:Hide()
    else
        x = Segment(bar.done, x, total * questDone / max, total)
        if S.Get("xpBarIncomplete") then
            x = Segment(bar.open, x, total * questOpen / max, total)
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

    bar.sub:SetText(SubLines(maxed, max))
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
    ns.Solid(bar, "BACKGROUND", T.bg, 0.85):SetAllPoints()

    -- The track holds the fill and segments, the full width of the bar.
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetAllPoints()
    bar.track:SetClipsChildren(true)
    bar.fill = bar.track:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.fill:SetGradient("HORIZONTAL", FILL_FROM, FILL_TO)
    bar.done = ns.Solid(bar.track, "ARTWORK", QUEST, 1)
    bar.open = ns.Solid(bar.track, "ARTWORK", QUEST, 0.4)
    bar.rested = ns.Solid(bar.track, "OVERLAY", RESTED, 1)

    -- Above the track, whose own frame would otherwise cover the border.
    ns.Border(bar)._frame:SetFrameLevel(bar:GetFrameLevel() + 4)

    local text = CreateFrame("Frame", nil, bar)
    text:SetAllPoints()
    text:SetFrameLevel(bar:GetFrameLevel() + 5)
    bar.level = ns.Font(text, 14, "OUTLINE")
    bar.level:SetPoint("LEFT", bar.track, "LEFT", 8, 0)
    bar.value = ns.Font(text, 14, "OUTLINE")
    bar.value:SetPoint("CENTER", bar.track, "CENTER")
    bar.pct = ns.Font(text, 14, "OUTLINE")
    bar.pct:SetPoint("RIGHT", bar.track, "RIGHT", -8, 0)
    bar.sub = ns.Font(bar, 13, "OUTLINE")
    bar.sub:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    bar.sub:SetJustifyH("CENTER")
    bar.sub:SetSpacing(2)

    bar.mover = ns.UI.AttachMover(bar, "XP Bar", function(pos) S.Set("xpBarPos", pos) end)
end

local function Apply()
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
    Place()

    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
                         "PLAYER_UPDATE_RESTING", "QUEST_LOG_UPDATE", "TIME_PLAYED_MSG",
                         "DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "PLAYER_LOGOUT" }) do
        events:RegisterEvent(e)
    end
    if S.Get("xpBarPlayed") and not playedTotal then RequestPlayed() end
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
