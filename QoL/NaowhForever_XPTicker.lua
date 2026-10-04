-------------------------------------------------------------------------------
--  NaowhForever_XPTicker.lua -- the QoL XP per hour ticker: rate, time to level and session
--  stats, with optional level splits.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

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

local Look = {}

function Look.New(f)
    f.text = ns.Font(f, 14, "OUTLINE")
    f.text:SetPoint("TOPLEFT", 4, -4)
    f.text:SetJustifyH("LEFT")
    f.splits = ns.Font(f, 14, "OUTLINE")
    f.splits:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -4)
    f.splits:SetJustifyH("LEFT")
end

function Look.Fonts(f)
    local font, size = ns.UI.FontPath(S.Get("xpTickerFont")), S.Get("xpTickerFontSize")
    f.text:SetFont(font, size, "OUTLINE")
    f.splits:SetFont(font, math.max(10, math.floor(size * 0.6)), "OUTLINE")
end

function Look.Text(rate, ding, elapsed, isPaused)
    local lines = { Line("XP/hr", Short(rate)) .. (isPaused and "  " .. DIM .. "(paused)|r" or "") }
    if S.Get("xpTickerLevel") then
        lines[#lines + 1] = Line("Ding", ding and Duration(ding) or "--")
    end
    if S.Get("xpTickerElapsed") then
        lines[#lines + 1] = Line("Time", Clock(elapsed))
    end
    return table.concat(lines, "\n")
end

function Look.History(keys, levels)
    local lines = {}
    for i = 1, math.min(#keys, S.Get("xpTickerHistoryCount") or 10) do
        local level = keys[i]
        lines[#lines + 1] = Line("Level " .. level, Clock(levels[level].total))
    end
    return table.concat(lines, "\n")
end

function Look.Fit(f)
    local width = math.max(f.text:GetStringWidth(), f.splits:GetStringWidth(), 80)
    local height = f.text:GetStringHeight()
    if f.splits:GetText() ~= "" then height = height + 4 + f.splits:GetStringHeight() end
    f:SetSize(width + 8, height + 8)
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
    return Look.History(keys, levels)
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
    local ding
    if rate > 0 and S.Get("xpTickerLevel") then
        ding = (UnitXPMax("player") - UnitXP("player")) / rate * 3600
    end
    ticker.text:SetText(Look.Text(rate, ding, elapsed, paused))
    ticker.splits:SetText(S.Get("xpTickerSplits") and cur and SplitLines() or "")
    Look.Fit(ticker)
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
        Look.New(ticker)
        ticker.mover = ns.UI.AttachMover(ticker, "XP per Hour", function(pos) S.Set("xpTickerPos", pos) end,
            "QoL/XP", "QoL/XP:xpTicker")
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
    Look.Fonts(ticker)
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

local Group = ns.Shared.Settings.Group
local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 190, 10, 11, 16
local SAMPLE_RATE, SAMPLE_DING, SAMPLE_TIME = 48200, 23 * 60, 72 * 60 + 40
local SAMPLE_KEYS = { 22, 21, 20, 19, 18 }
local SAMPLE_LEVELS = { [22] = { total = 3125 }, [21] = { total = 2864 }, [20] = { total = 2702 },
    [19] = { total = 2391 }, [18] = { total = 2248 } }
local STATES = {
    { key = "levelling", label = "Levelling", tip = "Out in the world, earning experience." },
    { key = "resting", label = "Resting", tip = "In a city or an inn, where Hide While Resting hides it.",
      needs = "xpTickerHideResting" },
}

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.ticker = CreateFrame("Frame", nil, preview)
    Look.New(preview.ticker)
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function Fit(preview)
    local f = preview.ticker
    local w, h = f:GetWidth(), f:GetHeight()
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h > 0 and h * scale > roomH then scale = roomH / h end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", preview, "CENTER", 0, NOTE_Y / scale)
end

local function PaintPreview(preview, state)
    local f = preview.ticker
    Look.Fonts(f)
    f.text:SetText(Look.Text(SAMPLE_RATE, SAMPLE_DING, SAMPLE_TIME, false))
    f.splits:SetText(S.Get("xpTickerSplits") and Look.History(SAMPLE_KEYS, SAMPLE_LEVELS) or "")
    Look.Fit(f)
    Fit(preview)
    local hidden = state == "resting" and S.Get("xpTickerHideResting")
    f:SetShown(not hidden)
    preview.note:SetText(hidden and "Hide While Resting is on: hidden in cities and inns." or "")
end

local function Summary(store)
    if store.Get("xpTickerSplits") then
        return ("Rate, time to level and the last %d levels"):format(store.Get("xpTickerHistoryCount"))
    end
    return "Rate and time to level"
end

ns.Shared.Settings.Page("QoL/XP", S):Card({
    id = "xpTicker", name = "XP per Hour", order = 20, switch = "xpTicker",
    help = "Your experience per hour on screen, with time to level, session length and recent level "
        .. "times. Hidden at max level. Hover it for Start, Pause and Reset (also /naowh xp start, pause "
        .. "or reset). Move it in Unlock Mode.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Shown"),
        { key = "xpTickerLevel", label = "Show Ding Time", toggle = true,
          help = "How long the next level takes at your current rate." },
        { key = "xpTickerElapsed", label = "Show Time", toggle = true, help = "How long this session has run." },
        { key = "xpTickerHideResting", label = "Hide While Resting", toggle = true, help = "Hidden in cities and inns." },
        Group("Level History"),
        { key = "xpTickerSplits", label = "Level History", toggle = true,
          help = "Completed levels, newest first. No placeholder rows." },
        { key = "xpTickerHistoryCount", label = "Levels Shown", slider = { 1, 10, 1 }, needs = "xpTickerSplits",
          help = "The most recent completed levels." },
        Group("Text"),
        { key = "xpTickerFont", label = "Font", font = true },
        { key = "xpTickerFontSize", label = "Font Size", slider = { 8, 32, 1 } },
        { label = "Reset XP per Hour", buttonText = "Reset", button = ns.ResetXPTicker,
          help = "Starts the session again: its time, XP and rate. The XP Bar's XP/Hour starts again with it." },
    },
})
