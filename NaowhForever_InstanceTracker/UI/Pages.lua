-- Pages.lua: This Hour and History, the lists in the Instance Tracker's window.
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

local LINE_H = 20
local LINE_FONT = 12
local LINE_INSET = 4
local FALLBACK_W = 960
local GROUP_GAP = 6

local function HourPaint(left, text)
    local colors = ns.InstanceTracker
    return ns.Color(left <= 0 and colors.CapRGB or colors.WarnRGB, text)
end

local function Line(parent, y, text)
    if UI.searchScan then return y - LINE_H end
    local row = UI.Keep(parent, "line", function(p)
        local f = CreateFrame("Frame", nil, p)
        f:SetHeight(LINE_H)
        f.text = ns.Font(f, LINE_FONT, nil, T.fg)
        f.text:SetPoint("LEFT", LINE_INSET, 0)
        f.text:SetPoint("RIGHT", -LINE_INSET, 0)
        f.text:SetJustifyH("LEFT")
        f.text:SetWordWrap(false)
        return f
    end)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y)
    row:SetHeight(LINE_H)
    row.text:SetFont(UI.FontPath(""), LINE_FONT, "")
    row.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    row.text:SetText(text)
    return y - LINE_H
end

local function WrapLine(parent, y, text)
    if UI.searchScan then return y - LINE_H end
    local row = UI.Keep(parent, "wrap", function(p)
        local f = CreateFrame("Frame", nil, p)
        f.text = ns.Font(f, LINE_FONT, nil, T.fg)
        f.text:SetJustifyH("LEFT")
        f.text:SetWordWrap(true)
        return f
    end)
    local width = parent:GetWidth() or 0
    if width <= 0 then width = FALLBACK_W end
    width = width - UI.CONTENT_PAD * 2
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    row:SetWidth(width)
    row.text:SetFont(UI.FontPath(""), LINE_FONT, "")
    row.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", LINE_INSET, -LINE_INSET)
    row.text:SetWidth(math.max(1, width - LINE_INSET * 2))
    row.text:SetText(text)
    local textH = math.ceil(row.text:GetStringHeight())
    if textH < LINE_FONT then textH = LINE_FONT end
    local h = textH + LINE_INSET * 2
    if h < LINE_H then h = LINE_H end
    row:SetHeight(h)
    return y - h
end

local function OffText()
    if ns.InstanceTracker.Enabled() then return "" end
    return ns.L("Instance Tracker is off, so nothing new is recorded. ")
end

local function ClassName(name, class)
    if ns.ClassColoredName then return ns.ClassColoredName(name, class) end
    return name or "?"
end

local function CharLine(char)
    local who = ClassName(char.name, char.class)
    local extra = (char.level or "?") .. "   " .. (char.realm or "")
    if char.mine then
        extra = extra .. "   (you)"
    elseif type(char.seen) == "number" then
        extra = extra .. "   " .. date("%m/%d %H:%M", char.seen)
    end
    return who .. "   " .. ns.Color("muted", extra)
end

local function JoinMuted(parts)
    if #parts == 0 then return end
    return "    " .. ns.Color("muted", table.concat(parts, "   "))
end

local function SheetLine(char)
    local parts = {}
    if type(char.durability) == "number" then
        parts[#parts + 1] = char.durability .. ns.L("% durability")
    end
    return JoinMuted(parts)
end

local function RestLine(char)
    local parts = {}
    if type(char.xpMax) == "number" and char.xpMax > 0 and type(char.xp) == "number" then
        parts[#parts + 1] = BreakUpLargeNumbers(char.xp) .. "/"
            .. BreakUpLargeNumbers(char.xpMax) .. " XP"
    end
    if type(char.rested) == "number" and char.rested > 0 then
        parts[#parts + 1] = "rested " .. BreakUpLargeNumbers(char.rested)
    end
    return JoinMuted(parts)
end

local function RunLine(run)
    local IT = ns.InstanceTracker
    local span = IT.Duration((run.left or run.entered or 0) - (run.entered or 0))
    local when = date("%m/%d %H:%M", run.entered or time())
    local who = ClassName(run.name or "?", run.class)
    local text = string.format("%s   %s   %s   %s   %s   %s XP", when, who,
        IT.PlaceName(run.instance, run.difficulty), span, IT.Coins(run.loot),
        BreakUpLargeNumbers(run.xp or 0))
    if (run.deaths or 0) > 0 then
        local word = run.deaths == 1 and "death" or "deaths"
        text = text .. "   " .. ns.Color("muted", run.deaths .. " " .. word)
    end
    return text
end

local function RepText(rep)
    local text = ns.InstanceTracker.Reputation(rep)
    if not text then return end
    return "    " .. ns.Color("muted", text)
end

local function RepLine(parent, y, rep)
    local text = RepText(rep)
    if not text then return y end
    return WrapLine(parent, y, text)
end

function ns.BuildInstanceHourPage(parent, y)
    local W, IT = UI.Widgets, ns.InstanceTracker
    local _, h
    _, h = W:Note(parent, OffText()
        .. ns.L("New dungeon and raid instances "
        .. "on this account count toward one 10-per-hour cap. "
        .. "Walking back into one you have not reset does not count. The chat warning is set "
        .. "under Instance Tracker settings."), y); y = y - h
    _, h = W:SectionHeader(parent, "THIS HOUR", y); y = y - h

    local count, cap, frees = IT.Hour()
    local summary = string.format(ns.L("Account this hour: %d of %d"), count, cap)
    if count > 0 then summary = summary .. ns.L("   next frees in ") .. IT.Duration(frees) end
    local left = cap - count
    if count > 0 and left <= IT.WarnDistance() then
        summary = HourPaint(left, summary)
    end
    y = Line(parent, y, summary)
    local hourRows = IT.HourEntries()
    if #hourRows == 0 then
        _, h = W:Note(parent, "No new instances this hour.", y); y = y - h
    else
        for i = 1, #hourRows do
            local row = hourRows[i]
            y = Line(parent, y, string.format(ns.L("%s   frees in %s"), row.name or "",
                IT.Duration(IT.EntryLeft(row))))
        end
        y = y - GROUP_GAP
    end

    _, h = W:SectionHeader(parent, "CHARACTERS", y); y = y - h
    _, h = W:Note(parent, "A character shows up here after you log into it with Instance Tracker on. "
        .. "Track Alts shows the others: rested experience and durability, "
        .. "from the last time that character was logged in.", y); y = y - h

    local chars = ns.InstanceTracker.Characters()
    if #chars == 0 then
        _, h = W:Note(parent, "No characters recorded yet.", y); y = y - h
        return y
    end
    for i = 1, #chars do
        local char = chars[i]
        y = Line(parent, y, CharLine(char))
        local sheet = SheetLine(char)
        if sheet then y = Line(parent, y, sheet) end
        local rest = RestLine(char)
        if rest then y = Line(parent, y, rest) end
        y = y - GROUP_GAP
    end
    return y
end

function ns.BuildInstanceHistoryPage(parent, y)
    local W, IT = UI.Widgets, ns.InstanceTracker
    local _, h
    _, h = W:Note(parent, OffText()
        .. ns.L("Each dungeon or raid visit while Instance Tracker is on: how long you were "
        .. "inside, the coins you looted and the experience you gained. Reputation gained "
        .. "is listed under the visit. Coming back to the same group within "
        .. "the hour, before you reset it, continues that visit, and the time outside "
        .. "is not counted. Other characters stay saved, and show here when Track Alts is on. "
        .. "Repairs and vendor sales are not counted. "
        .. "Older visits drop off the end of the list."), y); y = y - h
    _, h = W:Button(parent, "Clear History", y, function()
        ns.Confirm(ns.L("Clear instance history?"), function()
            IT.ClearHistory()
            UI:RefreshPage(true)
        end)
    end); y = y - h
    _, h = W:SectionHeader(parent, "VISITS", y); y = y - h

    local open = IT.Open()
    if open and open.instance then
        local elapsed = IT.Duration(IT.Elapsed(open))
        y = Line(parent, y, ns.L("In progress   ") .. ClassName(open.name or "?", open.class)
            .. "   " .. IT.PlaceName(open.instance, open.difficulty) .. "   " .. elapsed
            .. "   " .. IT.Coins(open.loot) .. "   " .. BreakUpLargeNumbers(open.xp or 0) .. " XP")
        y = RepLine(parent, y, open.rep)
        y = y - GROUP_GAP
    end

    local runs = IT.Runs()
    if #runs == 0 and not open then
        _, h = W:Note(parent, "No visits recorded yet.", y); y = y - h
        return y
    end
    local shown = math.min(#runs, IT.PAGE_RUNS)
    for i = 1, shown do
        y = Line(parent, y, RunLine(runs[i]))
        y = RepLine(parent, y, runs[i].rep)
    end
    if #runs > shown then
        _, h = W:Note(parent, ns.L("Showing the latest %d of %d."):format(shown, #runs), y)
        y = y - h
    end
    return y
end
