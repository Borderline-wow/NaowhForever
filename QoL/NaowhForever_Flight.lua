-------------------------------------------------------------------------------
--  NaowhForever_Flight.lua -- the QoL flight timer: the route as a track with its stops sliding
--  past, and the time left.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local GRADIENT = "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DOT_TEX = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"
local STOP_ICON = "Interface\\Minimap\\Tracking\\FlightMaster"
-- Blizzard's own button for leaving a flight uses this art.
local LAND_ICON = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up"
local LAND_ICON_DOWN = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Down"

local WIDTH, TRACK_H, DOT, PIN, NAME_SIZE = 420, 10, 14, 18, 14
local HEIGHT = PIN + 2 * (NAME_SIZE + 8)
-- A stop slides in at the track's right end this many seconds before it is reached.
local LOOKAHEAD = 60
-- Yards per second, fitted to measured Classic flight times.
local FLIGHT_SPEED = 30.4

local bar, poll, unlocked, Apply, FadeBlizzardStop
local stopFaded = false
local pending   -- { from, to, points, estimate, at }: a flight bought but not boarded yet
local flight    -- { from, to, start, known, points, early, sample }

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
-- mounts 20% faster. Legacy perks are bought per character; a character without the tree
-- has no config for it.
local function SpeedMultiplier()
    local config = C_Traits.GetConfigIDByTreeID(1188)
    local node = config and C_Traits.GetNodeInfo(config, 110300)
    return node and node.activeRank > 0 and 1.2 or 1
end

-- Every node on the way to the map's slot, start first, each with the seconds it takes to
-- reach it. From the first hop missing from the route data on, `at` is nil, and the
-- learned time for the route stands in for the whole flight.
local function Route(slot)
    local idBySlot = {}
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())) do
        idBySlot[node.slotIndex] = node.nodeID
    end
    local speed = FLIGHT_SPEED * SpeedMultiplier()
    local points = { { name = TaxiNodeName(TaxiGetNodeSlot(slot, 1, true)), at = 0 } }
    local yards = 0
    for hop = 1, GetNumRoutes(slot) do
        local toSlot = TaxiGetNodeSlot(slot, hop, false)
        local from = idBySlot[TaxiGetNodeSlot(slot, hop, true)]
        local to = idBySlot[toSlot]
        local hopYards = from and to and ns.FLIGHT_ROUTES[from * 10000 + to]
        yards = yards and hopYards and yards + hopYards
        points[#points + 1] = { name = TaxiNodeName(toSlot), at = yards and yards / speed }
    end
    local last = points[#points].at
    return points, last and last > 0 and last or nil
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local function Mark(parent, texture, w, h, size)
    local m = { icon = parent:CreateTexture(nil, "OVERLAY"), label = ns.Font(parent, size or NAME_SIZE, "OUTLINE") }
    m.icon:SetTexture(texture)
    m.icon:SetSize(w, h or w)
    m.label:SetWordWrap(false)
    return m
end

-- The stops are placed along a strip by their arrival time; sliding the strip left as
-- time passes carries each one across the "you" post the moment it is reached.
local function Slide(elapsed)
    local clip = bar.clip
    clip.strip:ClearAllPoints()
    clip.strip:SetPoint("CENTER", bar, "CENTER", -elapsed * clip.pps, 0)
    for k, m in ipairs(bar.stops) do
        local p = flight.points[k + 1]
        local passed = m.icon:IsShown() and p.at <= elapsed
        m.icon:SetAlpha(passed and 0.4 or 1)
        m.label:SetAlpha(passed and 0.4 or 1)
    end
end

local function Layout()
    local points = flight.points
    local n = points and #points or 0
    bar.ends[1].label:SetText(n > 0 and points[1].name or flight.from or "")
    bar.ends[2].label:SetText(n > 0 and points[n].name or flight.to or "In flight")

    -- Stops scroll only when every arrival time is known and there is one on the way.
    local scroll = flight.known and n > 2 and points[n].at and not flight.early
    bar.clip:SetShown(scroll and true or false)
    bar.you.icon:SetShown(scroll and true or false)
    bar.you.label:SetShown(scroll and true or false)
    for k = 1, math.max(n - 2, #bar.stops) do
        local m = bar.stops[k]
        if scroll and k <= n - 2 then
            if not m then
                m = Mark(bar.clip.strip, STOP_ICON, PIN)
                m.label:SetPoint("TOP", m.icon, "BOTTOM", 0, -4)
                bar.stops[k] = m
            end
            m.icon:ClearAllPoints()
            m.icon:SetPoint("CENTER", bar.clip.strip, "CENTER", points[k + 1].at * bar.clip.pps, 0)
            m.label:SetText(points[k + 1].name)
            m.icon:Show()
            m.label:Show()
        elseif m then
            m.icon:Hide()
            m.label:Hide()
        end
    end
    -- An elapsed-only flight has no end to fill towards.
    bar.track:SetValue(0)
    bar.track:GetStatusBarTexture():SetAlpha(flight.known and 1 or 0)
    bar.land:SetShown(S.Get("flightEarlyLanding") and not flight.sample)
    bar.land:SetEnabled(not flight.early)
    bar.land:SetAlpha(flight.early and 0.4 or 1)
end

local function Update()
    if not (bar and flight and bar:IsShown()) then return end
    local elapsed = GetTime() - flight.start
    if flight.sample then elapsed = elapsed % flight.known end
    if flight.known then
        bar.time:SetText(Clock(flight.known - elapsed))
        bar.track:SetValue(math.min(elapsed / flight.known, 1))
        if bar.clip:IsShown() then Slide(elapsed) end
    else
        bar.time:SetText(Clock(elapsed))
    end
end

local function Show()
    Layout()
    Update()
    bar:Show()
end

local function StopPoll()
    if poll then poll:Cancel(); poll = nil end
end

local function Land()
    local elapsed = GetTime() - flight.start
    local key = RouteKey(flight.from, flight.to)
    -- A flight shorter than ten seconds was cut short or never really left, and one
    -- landed early did not fly the route.
    if key and elapsed > 10 and not flight.early then Times()[key] = math.floor(elapsed + 0.5) end
    flight = nil
    StopPoll()
    bar:Hide()
    FadeBlizzardStop()
    if unlocked then Apply() end
    if ns.QuizDismiss then ns.QuizDismiss("flight") end
end

local function Board(route)
    local key = route and RouteKey(route.from, route.to)
    flight = { from = route and route.from, to = route and route.to, start = GetTime(),
        points = route and route.points,
        known = route and route.estimate or key and Times()[key] }
    pending = nil
    if On() then Show() end
    FadeBlizzardStop()
    if ns.QuizOffer then ns.QuizOffer("flight") end
end

-- Landing early stops at the next node on the way, so the route and the time end there.
local function Retarget()
    if not flight or flight.early or flight.sample then return end
    flight.early = true
    local points, elapsed = flight.points, GetTime() - flight.start
    for i, p in ipairs(points or {}) do
        if p.at and p.at > elapsed then
            for j = #points, i + 1, -1 do points[j] = nil end
            flight.known = p.at
            break
        end
    end
    if bar and bar:IsShown() then Show() end
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
    -- An invisible box around the whole display, so Unlock Mode has something to grab;
    -- the track is the line through its middle.
    bar = CreateFrame("Frame", "NaowhForeverFlightTimer", UIParent)
    bar:SetSize(WIDTH, HEIGHT)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)

    local track = CreateFrame("StatusBar", nil, bar)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(TRACK_H)
    track:SetStatusBarTexture(GRADIENT)
    track:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    track:SetMinMaxValues(0, 1)
    ns.Solid(track, "BACKGROUND", T.bg, 0.9):SetAllPoints()
    ns.Border(track, { r = 0, g = 0, b = 0 })
    bar.track = track

    -- Marks sit above the track's border.
    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints()
    over:SetFrameLevel(track:GetFrameLevel() + 3)
    bar.ends = { Mark(over, DOT_TEX, DOT), Mark(over, DOT_TEX, DOT) }
    for i, side in ipairs({ "LEFT", "RIGHT" }) do
        local m = bar.ends[i]
        m.icon:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
        m.icon:SetPoint("CENTER", bar, side)
        m.label:SetPoint("BOTTOM" .. side, m.icon, "TOP" .. side, 0, 6)
        m.label:SetWidth(WIDTH * 0.47)
        m.label:SetJustifyH(side)
    end
    bar.you = Mark(over, WHITE, 2, PIN + 4, 12)
    bar.you.icon:SetPoint("CENTER")
    bar.you.label:SetPoint("BOTTOM", bar.you.icon, "TOP", 0, 2)
    bar.you.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
    bar.you.label:SetText("You")

    -- The stops ride a strip clipped to the room between the two end dots.
    bar.clip = CreateFrame("Frame", nil, bar)
    bar.clip:SetFrameLevel(over:GetFrameLevel())
    bar.clip:SetClipsChildren(true)
    bar.clip:SetPoint("BOTTOMLEFT", bar, "LEFT", DOT / 2, -PIN / 2 - NAME_SIZE - 8)
    bar.clip:SetPoint("TOPRIGHT", bar, "RIGHT", -DOT / 2, PIN / 2 + 2)
    bar.clip.pps = WIDTH / 2 / LOOKAHEAD
    bar.clip.strip = CreateFrame("Frame", nil, bar.clip)
    bar.clip.strip:SetSize(1, 1)
    bar.stops = {}

    bar.time = ns.Font(bar, 18, "OUTLINE", T.accentSoft)
    bar.time:SetPoint("RIGHT", bar, "LEFT", -DOT / 2 - 8, 0)

    bar.land = CreateFrame("Button", nil, bar)
    bar.land:SetSize(30, 30)
    bar.land:SetPoint("LEFT", bar, "RIGHT", DOT / 2 + 8, 0)
    bar.land:SetNormalTexture(LAND_ICON)
    bar.land:GetNormalTexture():SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    bar.land:SetPushedTexture(LAND_ICON_DOWN)
    bar.land:GetPushedTexture():SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    bar.land:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    bar.land:SetScript("OnClick", function() TaxiRequestEarlyLanding() end)
    ns.Tooltip(bar.land, "Land Early", "Land at the next flight point.")

    -- Smooth while shown; the poll ticker only watches for boarding and landing.
    bar:SetScript("OnUpdate", Update)
    -- The mover reports offsets in the timer's own scaled units; they are saved in screen
    -- units so the Scale slider resizes it in place.
    bar.mover = ns.UI.AttachMover(bar, "Flight Timer", function(pos)
        local scale = bar:GetScale()
        S.Set("flightTimerPos", { point = pos.point, relPoint = pos.relPoint,
            x = pos.x * scale, y = pos.y * scale })
    end)
    bar:Hide()
end

local function Place()
    local pos, scale = S.Get("flightTimerPos"), bar:GetScale()
    bar:ClearAllPoints()
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x / scale, pos.y / scale)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -140 / scale)
    end
end

hooksecurefunc("TakeTaxiNode", function(index)
    local points, estimate = Route(index)
    pending = { from = CurrentNodeName(), to = TaxiNodeName(index), points = points,
        estimate = estimate, at = GetTime() }
    StartPoll()
end)

-- Blizzard's own leave button lands early the same way.
hooksecurefunc("TaxiRequestEarlyLanding", Retarget)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent(event)
        FadeBlizzardStop()
    -- A reload mid-flight: the route is unknown, so it only counts up and is not learned.
    elseif UnitOnTaxi("player") and not flight then
        Board(nil)
        StartPoll()
    end
end)

-- Blizzard's Request Stop is its vehicle leave button. It sits in the action bar's
-- protected layout, so it is faded rather than hidden, and only outside combat.
function FadeBlizzardStop()
    local fade = (On() and S.Get("flightEarlyLanding") and flight and not flight.sample) == true
    if fade == stopFaded then return end
    if InCombatLockdown() then events:RegisterEvent("PLAYER_REGEN_ENABLED") return end
    stopFaded = fade
    MainMenuBarVehicleLeaveButton:SetAlpha(fade and 0 or 1)
    MainMenuBarVehicleLeaveButton:EnableMouse(not fade)
end

-- A two-stop route to place and size the display by in Unlock Mode, looping.
local SAMPLE = { { name = "Ironforge", at = 0 }, { name = "Thorium Point", at = 50 },
    { name = "Morgan's Vigil", at = 95 }, { name = "Lakeshire", at = 150 } }

function Apply()
    if not bar then Build() end
    bar:SetScale(S.Get("flightTimerScale"))
    Place()
    if unlocked then
        bar.mover:Show()
        if not flight then
            flight = { start = GetTime(), known = 150, points = SAMPLE, sample = true }
            Show()
        end
    elseif flight and flight.sample then
        flight = nil
        bar:Hide()
    end
    if flight and not flight.sample then
        if On() then Show() else bar:Hide() end
    end
    FadeBlizzardStop()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "flightTimer" or key == "flightEarlyLanding" or key == "flightTimerScale" then
        Apply()
    end
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
