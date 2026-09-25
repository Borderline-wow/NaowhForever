-------------------------------------------------------------------------------
--  NaowhForever_Flight.lua -- the QoL flight timer: where you are flying, how
--  long it has taken, and a reminder quote from a streamer while you wait.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PLACEHOLDER = "Interface\\Icons\\INV_Misc_QuestionMark"
local LOGO = "Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga"

-- Streamer art goes in Media\Streamers as a square power-of-two .tga (128x128 is plenty);
-- point `icon` at it once the streamer has said yes to their face being used.
ns.FLIGHT_QUOTES = {
    { name = "Asmongold", icon = PLACEHOLDER, quotes = {
        "Clean your desk.",
        "Throw out the empty cans.",
        "Open a window, get some air in here.",
        "Take the plates back to the kitchen.",
        "When did you last eat something green?",
    } },
    { name = "Xaryu", icon = PLACEHOLDER, quotes = {
        "Grab some water.",
        "Sit up straight.",
        "Stretch your wrists.",
        "Stand up and stretch your legs.",
        "Look away from the screen for a bit.",
    } },
    { name = "Naowh", icon = LOGO, quotes = {
        "Check your bags before the next pull.",
        "Refill your water, not just your mana.",
        "Blink a few times, your eyes will thank you.",
        "Relax your shoulders.",
        "Text someone back.",
    } },
}

local QUOTE_SECONDS = 45
-- Yards per second, fitted to measured Classic flight times.
local FLIGHT_SPEED = 30.4

local bar, poll, unlocked, Apply
local pending   -- { from, to, at }: a flight bought but not boarded yet
local flight    -- { from, to, start, known }
local quoteAt, lastQuote

local function On()
    return S.Get("enabled") and S.Get("flightTimer")
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function Times()
    local account = ns.AccountSettings()
    account.flightTimes = account.flightTimes or {}
    return account.flightTimes
end

local function RouteKey(from, to)
    if from and to then return from .. "|" .. to end
end

local function CurrentNodeName()
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
    end
end

-- Frequent Flier, node 110300 of the Adventure Legacy tree (1188), makes flight path
-- mounts 20% faster. Legacy perks are bought per character.
local function SpeedMultiplier()
    local node = C_Traits.GetNodeInfo(C_Traits.GetConfigIDByTreeID(1188), 110300)
    return node.activeRank > 0 and 1.2 or 1
end

-- Seconds to the map's slot, summed over every hop; nil when a hop is missing from the
-- route data, and the learned time for the route is used instead.
local function EstimateSeconds(slot)
    local idBySlot = {}
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())) do
        idBySlot[node.slotIndex] = node.nodeID
    end
    local yards = 0
    for hop = 1, GetNumRoutes(slot) do
        local from = idBySlot[TaxiGetNodeSlot(slot, hop, true)]
        local to = idBySlot[TaxiGetNodeSlot(slot, hop, false)]
        local hopYards = from and to and ns.FLIGHT_ROUTES[from * 10000 + to]
        if not hopYards then return nil end
        yards = yards + hopYards
    end
    if yards == 0 then return nil end
    return yards / (FLIGHT_SPEED * SpeedMultiplier())
end

-- A new face and line, never the same line twice in a row.
local function NextQuote()
    local list = ns.FLIGHT_QUOTES
    local who, line
    repeat
        who = list[math.random(#list)]
        line = who.quotes[math.random(#who.quotes)]
    until line ~= lastQuote or #list * #who.quotes < 2
    lastQuote = line
    bar.icon:SetTexture(who.icon or PLACEHOLDER)
    bar.quote:SetText("\"" .. line .. "\"  |cff0091ed- " .. who.name .. "|r")
    quoteAt = GetTime()
end

local function Update()
    if not (bar and flight and bar:IsShown()) then return end
    local elapsed = GetTime() - flight.start
    if flight.known then
        bar.time:SetText(Clock(math.max(flight.known - elapsed, 0)))
        bar.progress:SetValue(math.min(elapsed / flight.known, 1))
    else
        bar.time:SetText(Clock(elapsed))
    end
    if S.Get("flightQuotes") and GetTime() - quoteAt >= QUOTE_SECONDS then NextQuote() end
end

local function Layout()
    local quotes = S.Get("flightQuotes")
    bar.icon:SetShown(quotes)
    bar.quote:SetShown(quotes)
    bar.title:SetPoint("TOPLEFT", quotes and 62 or 8, -8)
    bar.progress:SetShown(flight ~= nil and flight.known ~= nil)
    bar:SetHeight(quotes and 64 or 36)
end

local function Show()
    Layout()
    bar.title:SetText(flight.to and ("Flying to " .. flight.to) or "In flight")
    if S.Get("flightQuotes") then NextQuote() end
    Update()
    bar:Show()
end

local function StopPoll()
    if poll then poll:Cancel(); poll = nil end
end

local function Land()
    local elapsed = GetTime() - flight.start
    local key = RouteKey(flight.from, flight.to)
    -- A flight shorter than ten seconds was cut short or never really left.
    if key and elapsed > 10 then Times()[key] = math.floor(elapsed + 0.5) end
    flight = nil
    StopPoll()
    bar:Hide()
    if unlocked then Apply() end
    if ns.QuizDismiss then ns.QuizDismiss("flight") end
end

local function Board(route)
    local key = route and RouteKey(route.from, route.to)
    flight = { from = route and route.from, to = route and route.to, start = GetTime(),
        known = route and route.estimate or key and Times()[key] }
    pending = nil
    if On() then Show() end
    if ns.QuizOffer then ns.QuizOffer("flight") end
end

-- Only runs between buying a flight and landing: the client has no landing event, and
-- boarding lags the purchase by a moment.
local function Tick()
    if flight and not flight.sample then
        if not UnitOnTaxi("player") then Land() else Update() end
    elseif pending then
        if UnitOnTaxi("player") then
            Board(pending)
        elseif GetTime() - pending.at > 10 then
            pending = nil
            StopPoll()
        end
    else
        StopPoll()
    end
end

local function StartPoll()
    if not poll then poll = C_Timer.NewTicker(0.5, Tick) end
end

local function Build()
    bar = CreateFrame("Frame", "NaowhForeverFlightTimer", UIParent)
    bar:SetSize(340, 64)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    ns.Solid(bar, "BACKGROUND", T.bg, 0.85):SetAllPoints()
    ns.Border(bar)

    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(48, 48)
    bar.icon:SetPoint("LEFT", 8, 0)
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    bar.title = ns.Font(bar, 14, "OUTLINE")
    bar.title:SetPoint("TOPLEFT", 62, -8)
    bar.title:SetPoint("RIGHT", -60, 0)
    bar.title:SetJustifyH("LEFT")
    bar.title:SetWordWrap(false)

    bar.time = ns.Font(bar, 14, "OUTLINE", T.accentSoft)
    bar.time:SetPoint("TOPRIGHT", -8, -8)

    bar.progress = CreateFrame("StatusBar", nil, bar)
    bar.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.progress:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    bar.progress:SetMinMaxValues(0, 1)
    bar.progress:SetHeight(3)
    bar.progress:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -4)
    bar.progress:SetPoint("RIGHT", -8, 0)
    ns.Solid(bar.progress, "BACKGROUND", T.line):SetAllPoints()

    bar.quote = ns.Font(bar, 12, nil, T.muted)
    bar.quote:SetPoint("BOTTOMLEFT", 62, 8)
    bar.quote:SetPoint("RIGHT", -8, 0)
    bar.quote:SetJustifyH("LEFT")
    bar.quote:SetMaxLines(2)

    bar.mover = ns.UI.AttachMover(bar, "Flight Timer", function(pos) S.Set("flightTimerPos", pos) end)
    bar:Hide()
end

local function Place()
    local pos = S.Get("flightTimerPos")
    bar:ClearAllPoints()
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

hooksecurefunc("TakeTaxiNode", function(index)
    pending = { from = CurrentNodeName(), to = TaxiNodeName(index), at = GetTime(),
        estimate = EstimateSeconds(index) }
    StartPoll()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
    -- A reload mid-flight: the route is unknown, so it only counts up and is not learned.
    if UnitOnTaxi("player") and not flight then
        Board(nil)
        StartPoll()
    end
end)

function Apply()
    if not bar then Build() end
    Place()
    if unlocked then
        bar.mover:Show()
        if not flight then
            flight = { to = "Ironforge", start = GetTime(), known = 120, sample = true }
            Show()
        end
    elseif flight and flight.sample then
        flight = nil
        bar:Hide()
    end
    if flight and not flight.sample then
        if On() then Show() else bar:Hide() end
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "flightTimer" or key == "flightQuotes" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
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
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
