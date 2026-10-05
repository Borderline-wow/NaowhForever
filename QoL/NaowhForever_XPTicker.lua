-------------------------------------------------------------------------------
--  NaowhForever_XPTicker.lua -- the QoL XP per hour ticker: a small card with the rate, time to
--  level, session time and recent level times, and its settings card with a live preview.
--  Level times are kept per character by GUID; a character's first login after that change takes
--  over the old entry under its first name and realm, once, if no one else has and its level fits.
--  Its Background is the card, a soft fade or none (Parts.HudBackdrop); the old on/off setting is
--  read as Card for on and Soft for off, and saved that way on the next Apply.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style
local CharacterData = ns.Shared.CharacterData
local SPLITS_KEY = "levelSplits"

local OUTLINE = "OUTLINE"
local PAD, UNIT_GAP, LABEL_GAP, HEAD_GAP, COL_GAP = 8, 4, 4, 10, 16
local SECTION_GAP, ROW_GAP, CONTROL_GAP, CONTROLS_INSET = 6, 3, 2, 6
local ROW_SHARE, ROW_MIN, HISTORY_MAX = 0.5, 9, 10
local DESCENT_SHARE, PERCENT_ROUNDING = 0.2, 1e-9
local WIDTH_PER_SIZE, WIDTH_STEP = 6, 8
local LINE_H, TREND_SHARE, TREND_MIN, TREND_GAP = 2, 0.5, 8, 4
local TREND_WINDOW, TREND_MIN_SHARE, DING_SOON = 180, 0.05, 600
local UNIT, PAUSED, EMPTY, NONE = "xp/hr", "paused", "no XP yet", "--"
local DING, LEVEL, PERCENT, DOT, PARTIAL = "Ding", "Level %d", "%d%%", St.PLACE_DOT, "+"
local TIP_TITLE, TIP_RESTED, TIP_PAUSED = "XP per Hour", "%s" .. St.PLACE_DOT .. "rested +%s", "Paused"
local TIP_SESSION, TIP_GAINED, TIP_RATE, TIP_DING = "Session", "XP gained", "Rate", "Ding in"
local TIP_LEVEL_TIME, TIP_PARTIAL = "This level", "Timed from part way through the level."
local PAUSE_TIP, PAUSE_HINT = "Pause", "Stops the clock and the XP count."
local START_TIP, START_HINT = "Start", "Carries on from where you paused."
local RESET_TIP, RESET_HINT = "Reset", "Starts the session again from zero."

local ticker, clock, clockRate, unlocked
local sessionStart, sessionXP = 0, 0
local paused, pausedAt, pausedTotal = false, nil, 0
local lastXP, lastXPMax
local cur, anchor
local historyKeys = {}
local running = { level = 0, time = 0, partial = false }
local trendBase, trendAt, trendDir = 0, 0, 0
local LEGACY_BACKGROUND = { [true] = "card", [false] = "soft" }

local function On()
    return S.Get("enabled") and S.Get("xpTicker")
end

local function Background()
    local mode = S.Get("xpTickerBackground")
    return LEGACY_BACKGROUND[mode] or mode
end

local function MigrateBackground()
    local db = S.DB()
    local mode = LEGACY_BACKGROUND[db.xpTickerBackground]
    if mode then db.xpTickerBackground = mode end
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
    if seconds >= 3600 then return ("%.1fh"):format(seconds / 3600) end
    return math.max(math.floor(seconds / 60), 1) .. "m"
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60,
            seconds % 60)
    end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local Look = {}
local percents = {}

local function Percent(share)
    local n = math.max(0, math.floor(share * 100 + PERCENT_ROUNDING))
    local text = percents[n]
    if not text then
        text = PERCENT:format(n)
        percents[n] = text
    end
    return text
end

local function NewText(f, color)
    local fs = ns.Font(f, ROW_MIN, nil, color)
    f.texts[#f.texts + 1] = fs
    return fs
end

local function NewRow(f, label, valueColor)
    local row = { label = NewText(f, T.muted), value = NewText(f, valueColor or T.fg), on = false }
    row.value:SetJustifyH("RIGHT")
    row.label:Hide()
    row.value:Hide()
    if label then row.label:SetText(label) end
    return row
end

local function TipLine(left, right)
    local m, c = T.muted, T.fg
    GameTooltip:AddDoubleLine(left, right, m.r, m.g, m.b, c.r, c.g, c.b)
end

local function ShowTip(f)
    if not Parts.Tip(f, "ANCHOR_TOP") then return end
    GameTooltip:SetText(TIP_TITLE, T.fg.r, T.fg.g, T.fg.b)
    if f.level then
        local percent = Percent(f.progress)
        if f.restedShare > 0 then percent = TIP_RESTED:format(percent, Percent(f.restedShare)) end
        TipLine(LEVEL:format(f.level), percent)
    end
    local run = f.running
    if run then TipLine(TIP_LEVEL_TIME, Clock(run.time) .. (run.partial and PARTIAL or "")) end
    if f.elapsed then
        TipLine(TIP_SESSION, Clock(f.elapsed))
        TipLine(TIP_GAINED, Short(f.xp))
        TipLine(TIP_RATE, f.rateValue > 0 and Short(f.rateValue) .. " " .. UNIT or NONE)
        if f.dingValue then TipLine(TIP_DING, Duration(f.dingValue)) end
    end
    if run and run.partial then GameTooltip:AddLine(TIP_PARTIAL, T.muted.r, T.muted.g, T.muted.b, true) end
    if f.paused then GameTooltip:AddLine(TIP_PAUSED, T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:Show()
end

local function CardEnter(f)
    f.controls:Show()
    ShowTip(f)
end

local function CardLeave(f)
    if not f:IsMouseOver() then f.controls:Hide() end
    if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
end

local function ButtonLeave(button)
    CardLeave(button.card)
end

local function Tone(fs, color)
    if fs.tone == color then return end
    fs.tone = color
    fs:SetTextColor(color.r, color.g, color.b)
end

local function NewButton(f, texture, tip, hint)
    local button = Parts.BarButton(f.controls, texture, tip, hint)
    button.card = f
    button:HookScript("OnLeave", ButtonLeave)
    return button
end

function Look.New(f)
    f.texts = {}
    f.backdrop = Parts.HudBackdrop(f)
    f.rate = NewText(f, T.fg)
    f.rate:SetPoint("TOPLEFT", PAD, -PAD)
    f.unit = NewText(f, T.muted)
    f.unit:SetText(UNIT)
    f.trend = f:CreateTexture(nil, "OVERLAY")
    f.trend:SetTexture(St.UP)
    f.trend:SetPoint("LEFT", f.unit, "RIGHT", TREND_GAP, 0)
    f.trend:Hide()
    f.trendDir = 0
    f.current = NewRow(f, nil, T.muted)
    f.history = {}
    for i = 1, HISTORY_MAX do f.history[i] = NewRow(f) end
    f.ding = NewRow(f, DING)
    f.ding.value:SetJustifyH("LEFT")
    f.ding.value:SetPoint("LEFT", f.ding.label, "RIGHT", LABEL_GAP, 0)
    f.dot = NewText(f, T.muted)
    f.dot:SetText(DOT)
    f.dot:SetPoint("LEFT", f.ding.value, "RIGHT")
    f.dot:Hide()
    f.time = { value = NewText(f, T.fg), on = false }
    f.time.value:Hide()
    f.percent = NewText(f, T.muted)
    f.percent:SetJustifyH("RIGHT")

    f.controls = CreateFrame("Frame", nil, f)
    f.toggle = NewButton(f, St.PAUSE, PAUSE_TIP, PAUSE_HINT)
    f.toggle:SetPoint("LEFT")
    f.reset = NewButton(f, St.RESET, RESET_TIP, RESET_HINT)
    f.reset:SetPoint("LEFT", f.toggle, "RIGHT", CONTROL_GAP, 0)
    f.controls:SetSize(f.toggle:GetWidth() + CONTROL_GAP + f.reset:GetWidth(), f.toggle:GetHeight())
    f.controls:Hide()
    f.inner = ns.PixelInset(CreateFrame("Frame", nil, f), 1)
    f.line = Parts.ProgressLine(f.inner, LINE_H)
    f.line:SetPoint("BOTTOMLEFT")
    f.line:SetPoint("BOTTOMRIGHT")
    f.line:Paint(T.accent, T.accentSoft)
    f:EnableMouse(true)
    f:SetScript("OnEnter", CardEnter)
    f:SetScript("OnLeave", CardLeave)
end

local function RowFont(row, font, size, flags)
    if row.label then row.label:SetFont(font, size, flags) end
    row.value:SetFont(font, size, flags)
end

function Look.Fonts(f)
    local font, size = ns.UI.FontPath(S.Get("xpTickerFont")), S.Get("xpTickerFontSize")
    local mode = f.backdrop:SetMode(Background())
    local outlined = S.Get("xpTickerOutline") and true or false
    local flags = outlined and OUTLINE or ""
    local small = math.max(ROW_MIN, math.floor(size * ROW_SHARE))
    f.rate:SetFont(font, size, flags)
    f.unit:SetFont(font, small, flags)
    f.unit:ClearAllPoints()
    f.unit:SetPoint("BOTTOMLEFT", f.rate, "BOTTOMRIGHT", UNIT_GAP, (size - small) * DESCENT_SHARE)
    f.trendSize = math.max(TREND_MIN, math.floor(size * TREND_SHARE))
    f.trend:SetSize(f.trendSize, f.trendSize)
    RowFont(f.current, font, small, flags)
    for i = 1, HISTORY_MAX do RowFont(f.history[i], font, small, flags) end
    RowFont(f.ding, font, small, flags)
    RowFont(f.time, font, small, flags)
    f.dot:SetFont(font, small, flags)
    f.percent:SetFont(font, small, flags)
    local shadow = not outlined and mode
    for i = 1, #f.texts do Parts.HudText(f.texts[i], shadow) end
    f.line.track:SetShown(mode == "card")
    f.controls:ClearAllPoints()
    f.controls:SetPoint("RIGHT", f, "TOPRIGHT", -CONTROLS_INSET, -(PAD + size / 2))
    f.minW = size * WIDTH_PER_SIZE
    f.arranged = nil
end

local function PlaceRow(f, row, y)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
    return y + row.label:GetStringHeight()
end

local function ShowRow(row, on)
    row.on = on
    if row.label then row.label:SetShown(on) end
    row.value:SetShown(on)
end

local function PlaceFooter(f, showDing, showTime, y)
    ShowRow(f.ding, showDing)
    ShowRow(f.time, showTime)
    f.dot:SetShown(showDing and showTime)
    f.ding.label:ClearAllPoints()
    f.ding.label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    f.time.value:ClearAllPoints()
    if showDing then
        f.time.value:SetPoint("LEFT", f.dot, "RIGHT")
    else
        f.time.value:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    end
    f.percent:ClearAllPoints()
    f.percent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
    return y + f.percent:GetStringHeight()
end

local function Arrange(f, showDing, showTime, showCurrent, count)
    local key = (showDing and 1 or 0) + (showTime and 2 or 0) + (showCurrent and 4 or 0) + count * 8
    if f.arranged == key then return false end
    f.arranged = key
    local rateH = f.rate:GetStringHeight()
    local y = math.ceil(PAD + math.max(rateH, (rateH + f.controls:GetHeight()) / 2))
    local gap = SECTION_GAP
    ShowRow(f.current, showCurrent)
    if showCurrent then y, gap = PlaceRow(f, f.current, y + gap), ROW_GAP end
    for i = 1, HISTORY_MAX do
        local row = f.history[i]
        ShowRow(row, i <= count)
        if i <= count then
            y, gap = PlaceRow(f, row, y + gap), ROW_GAP
        end
    end
    y = PlaceFooter(f, showDing, showTime, y + SECTION_GAP)
    f.height = math.ceil(y) + PAD
    return true
end

local function RowWidth(w, row)
    if not row.on then return w end
    return math.max(w, row.label:GetStringWidth() + COL_GAP + row.value:GetStringWidth())
end

local function FooterWidth(f)
    local w = 0
    if f.ding.on then w = f.ding.label:GetStringWidth() + LABEL_GAP + f.ding.value:GetStringWidth() end
    if f.ding.on and f.time.on then w = w + f.dot:GetStringWidth() end
    if f.time.on then w = w + f.time.value:GetStringWidth() end
    return w + COL_GAP + f.percent:GetStringWidth()
end

function Look.Fit(f)
    if not f.height then return end
    local head = f.rate:GetStringWidth() + UNIT_GAP + f.unit:GetStringWidth()
        + (f.trendDir ~= 0 and TREND_GAP + f.trendSize or 0)
    local w = math.max(f.minW, head + HEAD_GAP + f.controls:GetWidth(), FooterWidth(f))
    w = RowWidth(w, f.current)
    for i = 1, HISTORY_MAX do w = RowWidth(w, f.history[i]) end
    f:SetSize(math.ceil(w / WIDTH_STEP) * WIDTH_STEP + 2 * PAD, f.height)
end

local function SetValue(fs, text)
    if fs.drawn == text then return false end
    fs.drawn = text
    fs:SetText(text)
    return true
end

local function ShowPaused(f, isPaused)
    if f.paused == isPaused then return end
    f.paused = isPaused
    local toggle = f.toggle
    toggle.icon:SetTexture(isPaused and St.PLAY or St.PAUSE)
    toggle.tip = isPaused and START_TIP or PAUSE_TIP
    toggle.hint = isPaused and START_HINT or PAUSE_HINT
    f.line:Paint(isPaused and T.muted or T.accent, isPaused and T.muted or T.accentSoft)
end

local function ShowTrend(f, dir)
    if f.trendDir == dir then return false end
    f.trendDir = dir
    local trend = f.trend
    trend:SetShown(dir ~= 0)
    if dir > 0 then
        trend:SetTexCoord(0, 1, 0, 1)
        trend:SetVertexColor(St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b)
    elseif dir < 0 then
        trend:SetTexCoord(0, 1, 1, 0)
        trend:SetVertexColor(St.RED_RGB.r, St.RED_RGB.g, St.RED_RGB.b)
    end
    return true
end

function Look.Progress(f, value, rested, level)
    f.line:SetProgress(value, rested)
    f.level, f.progress, f.restedShare = level, value, math.max(0, rested or 0)
    if SetValue(f.percent, Percent(value)) then Look.Fit(f) end
end

local function ShowCurrent(row, run)
    local changed = false
    if row.level ~= run.level then
        row.level = run.level
        row.label:SetText(LEVEL:format(run.level))
        changed = true
    end
    local sec, partial = math.max(0, math.floor(run.time + 0.5)), run.partial == true
    if row.sec ~= sec or row.partial ~= partial then
        row.sec, row.partial = sec, partial
        row.value:SetText(partial and Clock(sec) .. PARTIAL or Clock(sec))
        changed = true
    end
    return changed
end

function Look.Paint(f, rate, ding, elapsed, isPaused, keys, levels, trend, xp, run)
    isPaused = isPaused and true or false
    f.rateValue, f.dingValue, f.elapsed, f.xp, f.running = rate, ding, elapsed, xp, run
    local empty = rate <= 0
    local changed = SetValue(f.rate, empty and NONE or Short(rate))
    if SetValue(f.unit, isPaused and PAUSED or empty and EMPTY or UNIT) then changed = true end
    ShowPaused(f, isPaused)
    local earning = not empty and not isPaused
    Tone(f.rate, earning and T.accent or T.muted)
    if ShowTrend(f, earning and trend or 0) then changed = true end
    local showDing = (S.Get("xpTickerLevel") and ding) and true or false
    local showTime = S.Get("xpTickerElapsed") and true or false
    if showDing then
        if SetValue(f.ding.value, Duration(ding)) then changed = true end
        Tone(f.ding.value, ding < DING_SOON and T.accentSoft or T.fg)
    end
    if showTime then
        local sec = math.max(0, math.floor(elapsed + 0.5))
        if f.time.sec ~= sec then
            f.time.sec = sec
            f.time.value:SetText(Clock(sec))
            changed = true
        end
    end
    local showCurrent = (run and S.Get("xpTickerSplits")) and true or false
    if showCurrent and ShowCurrent(f.current, run) then changed = true end
    local count = math.min(#keys, S.Get("xpTickerHistoryCount") or HISTORY_MAX, HISTORY_MAX)
    for i = 1, count do
        local row, level = f.history[i], keys[i]
        local total = levels[level].total
        if row.level ~= level then
            row.level = level
            row.label:SetText(LEVEL:format(level))
            changed = true
        end
        if row.total ~= total then
            row.total = total
            row.value:SetText(Clock(total))
            changed = true
        end
    end
    if Arrange(f, showDing, showTime, showCurrent, count) then changed = true end
    if changed then Look.Fit(f) end
end

local function NameEntry()
    local name, realm = UnitName("player"), GetRealmName()
    if not (name and realm) then return end
    local all = ns.AccountSettings()[SPLITS_KEY]
    local old = type(all) == "table" and all[name .. "-" .. realm]
    return type(old) == "table" and old or nil
end

local function Inherit(mine, old, guid)
    local c = old.current
    if old.claimedBy or (type(c) == "table" and c.level ~= UnitLevel("player")) then return end
    old.claimedBy = guid
    if type(old.levels) == "table" then
        for level, record in pairs(old.levels) do
            if type(level) == "number" and type(record) == "table" then
                mine.levels[level] = { total = record.total }
            end
        end
    end
    if type(c) == "table" then mine.current = { level = c.level, base = c.base, partial = c.partial } end
    mine.migrated = true
end

local function Splits()
    local mine = CharacterData(SPLITS_KEY)
    if mine then
        if type(mine.levels) ~= "table" then mine.levels = {} end
        return mine
    end
    mine = CharacterData(SPLITS_KEY, true)
    if not mine then return end
    mine.levels = {}
    local old = NameEntry()
    if old then Inherit(mine, old, UnitGUID("player")) end
    return mine
end

local function LevelTime()
    return cur.base + (anchor and GetTime() - anchor or 0)
end

local function StartLevel(splits, fromStart, level)
    cur = { level = level or UnitLevel("player"), base = 0, partial = not fromStart }
    anchor = not paused and GetTime() or nil
    splits.current = cur
end

local function TrackSplits(newLevel)
    local splits = Splits()
    if not splits then return end
    if not cur then
        local saved = splits.current
        if saved and saved.level == UnitLevel("player") then
            cur, anchor = saved, not paused and GetTime() or nil
        else
            StartLevel(splits, UnitXP("player") == 0)
        end
    end
    local level = newLevel or UnitLevel("player")
    if level > cur.level then
        splits.levels[cur.level] = { total = not cur.partial and LevelTime() or nil }
        StartLevel(splits, true, level)
    elseif not anchor and not paused then
        anchor = GetTime()
    end
end

local function Newest(a, b)
    return a > b
end

local function History()
    wipe(historyKeys)
    local splits = cur and S.Get("xpTickerSplits") and Splits()
    if not splits then return historyKeys end
    local levels = splits.levels
    for level, record in pairs(levels) do
        if type(level) == "number" and level < cur.level and record.total then
            historyKeys[#historyKeys + 1] = level
        end
    end
    table.sort(historyKeys, Newest)
    return historyKeys, levels
end

local function Update()
    if not ticker then return end
    if Hidden() then
        ticker:Hide()
        return
    end
    local now = GetTime()
    local elapsed = now - sessionStart - pausedTotal - (paused and now - pausedAt or 0)
    local rate = sessionXP / (math.max(elapsed, 60) / 3600)
    local ding
    if rate > 0 then
        ding = (UnitXPMax("player") - UnitXP("player")) / rate * 3600
    end
    if not paused and now - trendAt >= TREND_WINDOW then
        local diff = rate - trendBase
        trendDir = (trendBase > 0 and math.abs(diff) > trendBase * TREND_MIN_SHARE) and (diff > 0 and 1 or -1) or 0
        trendBase, trendAt = rate, now
    end
    local keys, levels = History()
    local run
    if cur then
        running.level, running.time, running.partial = cur.level, LevelTime(), cur.partial == true
        run = running
    end
    Look.Paint(ticker, rate, ding, elapsed, paused, keys, levels, trendDir, sessionXP, run)
    ticker:Show()
end

local function Progress()
    if not ticker then return end
    local max = UnitXPMax("player")
    if max <= 0 then return end
    Look.Progress(ticker, UnitXP("player") / max, (GetXPExhaustion() or 0) / max, UnitLevel("player"))
end

function ns.ResetXPTicker()
    sessionStart, sessionXP, pausedTotal = GetTime(), 0, 0
    trendBase, trendAt, trendDir = 0, sessionStart, 0
    if paused then pausedAt = sessionStart end
    Update()
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

local function TogglePause()
    if paused then ns.StartXPTicker() else ns.PauseXPTicker() end
end

local function ResetClicked()
    ns.ResetXPTicker()
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
        Progress()
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
    MigrateBackground()
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
        ticker.toggle:SetScript("OnClick", TogglePause)
        ticker.reset:SetScript("OnClick", ResetClicked)
        ticker.mover = ns.UI.AttachMover(ticker, "XP per Hour", function(pos) S.Set("xpTickerPos", pos) end,
            "QoL/XP", "QoL/XP:xpTicker")
        sessionStart, sessionXP = GetTime(), 0
        trendAt = sessionStart
    end
    Look.Fonts(ticker)
    Place()
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    events:RegisterEvent("PLAYER_XP_UPDATE")
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("PLAYER_LOGOUT")
    TrackSplits()
    Progress()
    local rate = S.Get("xpTickerSplits") and 1 or 5
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
local STAGE_H, STAGE_MARGIN, TEXT_ROOM = 210, 16, 44
local NOTE_Y, NOTE_SIZE, NOTE_GAP = 8, 11, 4
local HOVER_ALPHA, HIT_PAD = 0.12, 1
local SIZE_RANGE = { 8, 32, 1 }
local SAMPLE_RATE, SAMPLE_DING, SAMPLE_TIME = 48200, 8 * 60, 72 * 60 + 40
local SAMPLE_PROGRESS, SAMPLE_RESTED, SAMPLE_RESTING_RESTED = 0.62, 0.15, 0.3
local SAMPLE_PAUSED_TIME, SAMPLE_RESTING_RATE, SAMPLE_RESTING_DING = 41 * 60 + 5, 31600, 35 * 60
local SAMPLE_LEVEL, SAMPLE_START_TIME, SECONDS_PER_HOUR = 23, 3 * 60 + 12, 3600
local SAMPLE_RUN = { level = SAMPLE_LEVEL, time = 14 * 60 + 2, partial = false }
local SAMPLE_START_RUN = { level = SAMPLE_LEVEL, time = 9 * 60 + 47, partial = true }
local SAMPLE_KEYS = { 22, 21, 20, 19, 18 }
local SAMPLE_LEVELS = { [22] = { total = 3125 }, [21] = { total = 2864 }, [20] = { total = 2702 },
    [19] = { total = 2391 }, [18] = { total = 2248 } }
local NO_KEYS = {}
local HINT = "Wheel: text size. Click a line to hide it. Right-click for more."
local OFF_HINT = "Turn on XP per Hour to edit it here."
local HIDDEN_NOTE = "Hide While Resting is on: hidden in cities and inns."
local STATES = {
    { key = "levelling", label = "Levelling", tip = "Out in the world, earning experience." },
    { key = "starting", label = "Starting", tip = "A new session, before any experience." },
    { key = "paused", label = "Paused", tip = "Paused from its header: the clock and the count stop." },
    { key = "resting", label = "Resting", tip = "In a city or an inn." },
}
local BACKGROUNDS = Parts.HUD_BACKGROUNDS
local LINE_TOGGLES = {
    { "xpTickerLevel", "Show Ding Time" },
    { "xpTickerElapsed", "Show Time" },
    { "xpTickerSplits", "Level History" },
}

local function Toggled(key)
    return S.Get(key) == true
end

local function Toggle(key)
    S.Set(key, not S.Get(key))
end

local function AddToggles(root, list)
    for i = 1, #list do root:CreateCheckbox(list[i][2], Toggled, Toggle, list[i][1]) end
end

local function PickedBackground(mode)
    return Background() == mode
end

local function SetBackground(mode)
    S.Set("xpTickerBackground", mode)
end

local function CardMenu(_, root)
    root:CreateTitle("XP per Hour")
    AddToggles(root, LINE_TOGGLES)
    root:CreateDivider()
    root:CreateTitle("Background")
    local order = BACKGROUNDS[2]
    for i = 1, #order do root:CreateRadio(BACKGROUNDS[1][order[i]], PickedBackground, SetBackground, order[i]) end
    root:CreateCheckbox("Outlined Text", Toggled, Toggle, "xpTickerOutline")
    root:CreateDivider()
    root:CreateButton("Reset XP per Hour", ResetClicked)
end

local function Wheel(f, delta)
    if not f.preview.editable then return end
    local size = S.Get("xpTickerFontSize")
    local v = math.max(SIZE_RANGE[1], math.min(SIZE_RANGE[2], size + delta * SIZE_RANGE[3]))
    if v ~= size then S.Set("xpTickerFontSize", v) end
end

local function CardUp(f, button)
    if f.preview.editable and button == "RightButton" then MenuUtil.CreateContextMenu(f, CardMenu) end
end

local function HitEnter(hit)
    CardEnter(hit.card)
    if hit.card.preview.editable then hit.wash:Show() end
end

local function HitLeave(hit)
    hit.wash:Hide()
    CardLeave(hit.card)
end

local function HitUp(hit, button)
    if not hit.card.preview.editable then return end
    if button == "RightButton" then
        CardUp(hit.card, button)
    elseif button == "LeftButton" and hit:IsMouseOver() then
        Toggle(hit.key)
    end
end

local function HitWheel(hit, delta)
    Wheel(hit.card, delta)
end

local function NewHit(preview, row, key)
    local f = preview.ticker
    local hit = CreateFrame("Frame", nil, f)
    hit:SetPoint("TOPLEFT", row.label or row.value, "TOPLEFT", -HIT_PAD, HIT_PAD)
    hit:SetPoint("BOTTOMRIGHT", row.value, "BOTTOMRIGHT", HIT_PAD, -HIT_PAD)
    hit.wash = ns.Solid(hit, "BACKGROUND", T.accent, HOVER_ALPHA)
    hit.wash:SetAllPoints()
    hit.wash:Hide()
    hit.card, hit.row, hit.key = f, row, key
    hit:EnableMouse(true)
    hit:EnableMouseWheel(true)
    hit:SetScript("OnEnter", HitEnter)
    hit:SetScript("OnLeave", HitLeave)
    hit:SetScript("OnMouseUp", HitUp)
    hit:SetScript("OnMouseWheel", HitWheel)
    hit:Hide()
    preview.hits[#preview.hits + 1] = hit
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.area = CreateFrame("Frame", nil, preview)
    preview.area:SetPoint("TOPLEFT", STAGE_MARGIN, -STAGE_MARGIN)
    preview.area:SetPoint("BOTTOMRIGHT", -STAGE_MARGIN, TEXT_ROOM)
    local f = CreateFrame("Frame", nil, preview)
    preview.ticker, f.preview = f, preview
    Look.New(f)
    f.toggle:EnableMouse(false)
    f.reset:EnableMouse(false)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", Wheel)
    f:SetScript("OnMouseUp", CardUp)
    preview.hits = {}
    NewHit(preview, f.ding, "xpTickerLevel")
    NewHit(preview, f.time, "xpTickerElapsed")
    NewHit(preview, f.current, "xpTickerSplits")
    for i = 1, HISTORY_MAX do NewHit(preview, f.history[i], "xpTickerSplits") end
    preview.hint = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.hint:SetPoint("BOTTOMLEFT", STAGE_MARGIN, NOTE_Y)
    preview.hint:SetPoint("BOTTOMRIGHT", -STAGE_MARGIN, NOTE_Y)
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", preview.hint, "TOP", 0, NOTE_GAP)
    return preview
end

local function FitPreview(preview)
    local f, area = preview.ticker, preview.area
    local w, h = f:GetWidth(), f:GetHeight()
    local roomW, roomH = area:GetWidth(), area:GetHeight()
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h > 0 and h * scale > roomH then scale = roomH / h end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", area, "CENTER", 0, 0)
end

local function PaintPreview(preview, state)
    local f = preview.ticker
    Look.Fonts(f)
    local keys = S.Get("xpTickerSplits") and SAMPLE_KEYS or NO_KEYS
    if state == "paused" then
        Look.Paint(f, SAMPLE_RATE, SAMPLE_DING, SAMPLE_PAUSED_TIME, true, keys, SAMPLE_LEVELS, 1,
            SAMPLE_RATE * SAMPLE_PAUSED_TIME / SECONDS_PER_HOUR, SAMPLE_RUN)
        Look.Progress(f, SAMPLE_PROGRESS, SAMPLE_RESTED, SAMPLE_LEVEL)
    elseif state == "resting" then
        Look.Paint(f, SAMPLE_RESTING_RATE, SAMPLE_RESTING_DING, SAMPLE_TIME, false, keys, SAMPLE_LEVELS, -1,
            SAMPLE_RESTING_RATE * SAMPLE_TIME / SECONDS_PER_HOUR, SAMPLE_RUN)
        Look.Progress(f, SAMPLE_PROGRESS, SAMPLE_RESTING_RESTED, SAMPLE_LEVEL)
    elseif state == "starting" then
        Look.Paint(f, 0, nil, SAMPLE_START_TIME, false, keys, SAMPLE_LEVELS, 0, 0, SAMPLE_START_RUN)
        Look.Progress(f, SAMPLE_PROGRESS, SAMPLE_RESTED, SAMPLE_LEVEL)
    else
        Look.Paint(f, SAMPLE_RATE, SAMPLE_DING, SAMPLE_TIME, false, keys, SAMPLE_LEVELS, 1,
            SAMPLE_RATE * SAMPLE_TIME / SECONDS_PER_HOUR, SAMPLE_RUN)
        Look.Progress(f, SAMPLE_PROGRESS, SAMPLE_RESTED, SAMPLE_LEVEL)
    end
    FitPreview(preview)
    local hidden = state == "resting" and S.Get("xpTickerHideResting") and true or false
    f:SetShown(not hidden)
    preview.note:SetText(hidden and HIDDEN_NOTE or "")
    local editable = (On() and not hidden) and true or false
    preview.editable = editable
    preview.hint:SetText(editable and HINT or hidden and "" or OFF_HINT)
    local hits = preview.hits
    for i = 1, #hits do
        local hit = hits[i]
        hit:SetShown(editable and hit.row.on)
        if not editable then hit.wash:Hide() end
    end
end

local function Summary(store)
    if store.Get("xpTickerSplits") then
        return ("Rate, time to level, this level and the last %d"):format(store.Get("xpTickerHistoryCount"))
    end
    return "Rate and time to level"
end

ns.Shared.Settings.Page("QoL/XP", S):Card({
    id = "xpTicker", name = "XP per Hour", order = 20, switch = "xpTicker",
    help = "Your experience per hour on a small card, with time to level, session length and recent level "
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
          help = "The level you are on as it runs, then completed levels, newest first." },
        { key = "xpTickerHistoryCount", label = "Levels Shown", slider = { 1, HISTORY_MAX, 1 }, needs = "xpTickerSplits",
          help = "The most recent completed levels." },
        Group("Look"),
        { key = "xpTickerBackground", label = "Background", choice = BACKGROUNDS, get = Background,
          set = SetBackground, help = "A card behind the text, a soft dark fade, or nothing at all." },
        { key = "xpTickerOutline", label = "Outlined Text", toggle = true,
          help = "A thick black outline round the text, in place of the soft shadow." },
        { key = "xpTickerFont", label = "Font", font = true },
        { key = "xpTickerFontSize", label = "Font Size", slider = SIZE_RANGE },
        { label = "Reset XP per Hour", buttonText = "Reset", button = ns.ResetXPTicker,
          help = "Starts the session again: its time, XP and rate. The XP Bar's XP/Hour starts again with it." },
    },
})
