-------------------------------------------------------------------------------
--  NaowhForever_XPTicker.lua -- the QoL XP per hour ticker: rate, time to level and session
--  stats, with optional level splits.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

-- Naowh's scheme: his blue for the labels, the theme's near-white for the values.
local DIM = "|cff9ca3af"

local ticker, clock, clockRate, unlocked
local sessionStart, sessionXP = 0, 0
-- Paused time is left out of the session clock and the level splits alike, and XP earned
-- while paused is not counted. pausedAt is the GetTime() the current pause began.
local paused, pausedAt, pausedTotal = false, nil, 0
local lastXP, lastXPMax
local cur, anchor

local function On()
    return S.Get("enabled") and S.Get("xpTicker")
end

local function AtMaxLevel()
    return UnitLevel("player") >= GetMaxLevelForPlayerExpansion() or IsXPUserDisabled()
end

local function Hidden()
    if unlocked then return false end
    return AtMaxLevel() or (S.Get("xpTickerHideResting") and IsResting())
end

local function Short(n)
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n))
end

local function Duration(seconds)
    if seconds >= 3600 then return ("%.1f hours"):format(seconds / 3600) end
    local m = math.max(math.floor(seconds / 60), 1)
    return m == 1 and "1 min" or (m .. " mins")
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60,
            seconds % 60)
    end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end


local function Line(label, value)
    return ns.Color("accent", label .. ":") .. " " .. ns.Color("fg", value)
end

-------------------------------------------------------------------------------
--  Level splits
-------------------------------------------------------------------------------
-- Split times are personal, so they live in the account store per character rather than
-- in a profile that can be exported and shared.
local function Splits()
    local account = ns.AccountSettings()
    account.levelSplits = account.levelSplits or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    account.levelSplits[key] = account.levelSplits[key] or { levels = {} }
    return account.levelSplits[key]
end

-- cur.base is the time on this level banked so far; anchor is the GetTime() it has run
-- from since, nil while paused. Offline time never counts.
local function LevelTime()
    return cur.base + (anchor and GetTime() - anchor or 0)
end

-- Keep only whole-level records in the display. A level first observed part-way
-- through is partial and must never be presented as a complete level time.
local function StartLevel(fromStart, level)
    cur = { level = level or UnitLevel("player"), base = 0, partial = not fromStart }
    anchor = not paused and GetTime() or nil
    Splits().current = cur
end

local function TrackSplits(newLevel)
    if not cur then
        local saved = Splits().current
        if saved and saved.level == UnitLevel("player") then
            cur, anchor = saved, not paused and GetTime() or nil
        else
            StartLevel(UnitXP("player") == 0)
        end
    end
    local level = newLevel or UnitLevel("player")
    if level > cur.level then
        Splits().levels[cur.level] = { total = not cur.partial and LevelTime() or nil }
        StartLevel(true, level)
    elseif not anchor and not paused then
        anchor = GetTime()
    end
end

local function SplitLines()
    local levels, keys = Splits().levels, {}
    for level, record in pairs(levels) do
        if type(level) == "number" and level < cur.level and record.total then
            keys[#keys + 1] = level
        end
    end
    table.sort(keys, function(a, b) return a > b end)
    local lines = {}
    for i = 1, math.min(#keys, S.Get("xpTickerHistoryCount") or 10) do
        local level = keys[i]
        lines[#lines + 1] = Line("Level " .. level, Clock(levels[level].total))
    end
    return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local function Update()
    if not ticker then return end
    if Hidden() then
        ticker:Hide()
        return
    end
    local now = GetTime()
    local elapsed = now - sessionStart - pausedTotal - (paused and now - pausedAt or 0)
    -- At least a minute, so the first kill after login does not read as millions an hour.
    local rate = sessionXP / (math.max(elapsed, 60) / 3600)
    local lines = { Line("XP/hr", Short(rate)) .. (paused and "  " .. DIM .. "(paused)|r" or "") }
    if S.Get("xpTickerLevel") then
        local left = UnitXPMax("player") - UnitXP("player")
        lines[#lines + 1] = Line("Ding", rate > 0 and Duration(left / rate * 3600) or "--")
    end
    if S.Get("xpTickerElapsed") then
        lines[#lines + 1] = Line("Time", Clock(elapsed))
    end

    ticker.text:SetText(table.concat(lines, "\n"))
    ticker.splits:SetText(S.Get("xpTickerSplits") and cur and SplitLines() or "")

    local width = math.max(ticker.text:GetStringWidth(), ticker.splits:GetStringWidth(), 80)
    local height = ticker.text:GetStringHeight()
    if ticker.splits:GetText() ~= "" then height = height + 4 + ticker.splits:GetStringHeight() end
    ticker:SetSize(width + 8, height + 8)
    ticker.controls.start:SetAlpha(paused and 1 or 0.4)
    ticker.controls.pause:SetAlpha(paused and 0.4 or 1)
    ticker:Show()
end

function ns.ResetXPTicker()
    sessionStart, sessionXP, pausedTotal = GetTime(), 0, 0
    if paused then pausedAt = sessionStart end
    Update()
    -- The XP Bar keeps its own session for its XP/Hour, so one Reset clears both.
    ns.ResetXPBarSession()
end

function ns.PauseXPTicker()
    if paused then return end
    paused, pausedAt = true, GetTime()
    if cur and anchor then cur.base, anchor = LevelTime(), nil end
    Update()
end

function ns.StartXPTicker()
    if not paused then return end
    pausedTotal = pausedTotal + GetTime() - pausedAt
    paused, pausedAt = false, nil
    if cur then anchor = GetTime() end
    Update()
end

function ns.XPTickerCommand(arg)
    local run = ({ start = ns.StartXPTicker, pause = ns.PauseXPTicker, reset = ns.ResetXPTicker })[arg]
    if run then run() else print(ns.Color("accent", "Naowh") .. ": /naowh xp start, pause or reset") end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGOUT" then
        if cur then cur.base = LevelTime() end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        local xp, max = UnitXP("player"), UnitXPMax("player")
        local gained = xp >= lastXP and xp - lastXP or (lastXPMax - lastXP) + xp
        lastXP, lastXPMax = xp, max
        if not paused then sessionXP = sessionXP + gained end
    end
    TrackSplits(event == "PLAYER_LEVEL_UP" and arg1 or nil)
    Update()
end)

local function Place()
    local pos = S.Get("xpTickerPos")
    ticker:ClearAllPoints()
    if pos then
        ticker:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        ticker:SetPoint("LEFT", UIParent, "CENTER", -811, 3)
    end
end

local function Apply()
    if not On() then
        if cur and anchor then cur.base, anchor = LevelTime(), nil end
        events:UnregisterAllEvents()
        if clock then clock:Cancel(); clock = nil end
        if ticker then ticker:Hide() end
        return
    end
    if not ticker then
        ticker = CreateFrame("Frame", "NaowhForeverXPTicker", UIParent)
        ticker:SetMovable(true)
        ticker:SetClampedToScreen(true)
        ticker.text = ns.Font(ticker, 14, "OUTLINE")
        ticker.text:SetPoint("TOPLEFT", 4, -4)
        ticker.text:SetJustifyH("LEFT")
        ticker.splits = ns.Font(ticker, 14, "OUTLINE")
        ticker.splits:SetPoint("TOPLEFT", ticker.text, "BOTTOMLEFT", 0, -4)
        ticker.splits:SetJustifyH("LEFT")
        ticker.mover = ns.UI.AttachMover(ticker, "XP per Hour", function(pos) S.Set("xpTickerPos", pos) end)
        -- Start, Pause and Reset under the ticker, shown while the mouse is over either.
        local controls = CreateFrame("Frame", nil, ticker)
        controls:SetSize(160, 20)
        controls:SetPoint("TOPLEFT", ticker, "BOTTOMLEFT", 0, -2)
        controls:Hide()
        local function HideSoon()
            C_Timer.After(0.3, function()
                if not (ticker:IsMouseOver() or controls:IsMouseOver()) then controls:Hide() end
            end)
        end
        for i, action in ipairs({ { "start", "Start", ns.StartXPTicker },
                                  { "pause", "Pause", ns.PauseXPTicker },
                                  { "reset", "Reset", ns.ResetXPTicker } }) do
            local btn = ns.Button(controls, action[2], 50, 18, action[3])
            btn:SetPoint("LEFT", (i - 1) * 54, 0)
            btn:HookScript("OnLeave", HideSoon)
            controls[action[1]] = btn
        end
        ticker.controls = controls
        ticker:EnableMouse(true)
        ticker:SetScript("OnEnter", function() controls:Show() end)
        ticker:SetScript("OnLeave", HideSoon)
        sessionStart, sessionXP = GetTime(), 0
    end
    local font, size = ns.UI.FontPath(S.Get("xpTickerFont")), S.Get("xpTickerFontSize")
    ticker.text:SetFont(font, size, "OUTLINE")
    ticker.splits:SetFont(font, math.max(10, math.floor(size * 0.6)), "OUTLINE")
    Place()
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    events:RegisterEvent("PLAYER_XP_UPDATE")
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("PLAYER_LOGOUT")
    TrackSplits()
    -- The rate falls and the clock runs while you stand still, so the text is redrawn on a
    -- slow clock too; a running split needs a one-second clock to read as a timer.
    local rate = S.Get("xpTickerSplits") and 1 or 5
    -- Nothing to count at max level, where the ticker stays hidden.
    if AtMaxLevel() and not unlocked then rate = nil end
    if clock and clockRate ~= rate then clock:Cancel(); clock = nil end
    if rate and not clock then clock, clockRate = C_Timer.NewTicker(rate, Update), rate end
    ticker.mover:SetShown(unlocked == true)
    Update()
end

hooksecurefunc(S, "Set", function(key, value)
    if key == "enabled" or (key:find("^xpTicker") and key ~= "xpTickerPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if ticker then
        ticker.mover:Hide()
        Apply()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
