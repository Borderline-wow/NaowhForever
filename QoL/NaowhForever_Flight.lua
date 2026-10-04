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

local WIDTH, TRACK_H, DOT, PIN, NAME_SIZE, LAND = 420, 10, 14, 18, 14, 30
local HEIGHT = PIN + 2 * (NAME_SIZE + 8)
local SIDE_GAP = DOT / 2 + 8
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
local Look = {}

local function Mark(parent, texture, w, h, size)
    local m = { icon = parent:CreateTexture(nil, "OVERLAY"), label = ns.Font(parent, size or NAME_SIZE, "OUTLINE") }
    m.icon:SetTexture(texture)
    m.icon:SetSize(w, h or w)
    m.label:SetWordWrap(false)
    return m
end

function Look.New(f)
    f:SetSize(WIDTH, HEIGHT)

    local track = CreateFrame("StatusBar", nil, f)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(TRACK_H)
    track:SetStatusBarTexture(GRADIENT)
    track:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    track:SetMinMaxValues(0, 1)
    ns.Solid(track, "BACKGROUND", T.bg, 0.9):SetAllPoints()
    ns.Border(track, { r = 0, g = 0, b = 0 })
    f.track = track

    -- Marks sit above the track's border.
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel(track:GetFrameLevel() + 3)
    f.ends = { Mark(over, DOT_TEX, DOT), Mark(over, DOT_TEX, DOT) }
    for i, side in ipairs({ "LEFT", "RIGHT" }) do
        local m = f.ends[i]
        m.icon:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
        m.icon:SetPoint("CENTER", f, side)
        m.label:SetPoint("BOTTOM" .. side, m.icon, "TOP" .. side, 0, 6)
        m.label:SetWidth(WIDTH * 0.47)
        m.label:SetJustifyH(side)
    end
    f.you = Mark(over, WHITE, 2, PIN + 4, 12)
    f.you.icon:SetPoint("CENTER")
    f.you.label:SetPoint("BOTTOM", f.you.icon, "TOP", 0, 2)
    f.you.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
    f.you.label:SetText("You")

    -- The stops ride a strip clipped to the room between the two end dots.
    f.clip = CreateFrame("Frame", nil, f)
    f.clip:SetFrameLevel(over:GetFrameLevel())
    f.clip:SetClipsChildren(true)
    f.clip:SetPoint("BOTTOMLEFT", f, "LEFT", DOT / 2, -PIN / 2 - NAME_SIZE - 8)
    f.clip:SetPoint("TOPRIGHT", f, "RIGHT", -DOT / 2, PIN / 2 + 2)
    f.clip.pps = WIDTH / 2 / LOOKAHEAD
    f.clip.strip = CreateFrame("Frame", nil, f.clip)
    f.clip.strip:SetSize(1, 1)
    f.stops = {}

    f.time = ns.Font(f, 18, "OUTLINE", T.accentSoft)
    f.time:SetPoint("RIGHT", f, "LEFT", -SIDE_GAP, 0)

    f.land = CreateFrame("Button", nil, f)
    f.land:SetSize(LAND, LAND)
    f.land:SetPoint("LEFT", f, "RIGHT", SIDE_GAP, 0)
    f.land:SetNormalTexture(LAND_ICON)
    f.land:GetNormalTexture():SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    f.land:SetPushedTexture(LAND_ICON_DOWN)
    f.land:GetPushedTexture():SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    f.land:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end

-- The stops are placed along a strip by their arrival time; sliding the strip left as
-- time passes carries each one across the "you" post the moment it is reached.
function Look.Slide(f, fl, elapsed)
    local clip = f.clip
    clip.strip:ClearAllPoints()
    clip.strip:SetPoint("CENTER", f, "CENTER", -elapsed * clip.pps, 0)
    for k, m in ipairs(f.stops) do
        local p = fl.points[k + 1]
        local passed = m.icon:IsShown() and p.at <= elapsed
        m.icon:SetAlpha(passed and 0.4 or 1)
        m.label:SetAlpha(passed and 0.4 or 1)
    end
end

function Look.Layout(f, fl, land)
    local points = fl.points
    local n = points and #points or 0
    f.ends[1].label:SetText(n > 0 and points[1].name or fl.from or "")
    f.ends[2].label:SetText(n > 0 and points[n].name or fl.to or "In flight")

    -- Stops scroll only when every arrival time is known and there is one on the way.
    local scroll = fl.known and n > 2 and points[n].at and not fl.early
    f.clip:SetShown(scroll and true or false)
    f.you.icon:SetShown(scroll and true or false)
    f.you.label:SetShown(scroll and true or false)
    for k = 1, math.max(n - 2, #f.stops) do
        local m = f.stops[k]
        if scroll and k <= n - 2 then
            if not m then
                m = Mark(f.clip.strip, STOP_ICON, PIN)
                m.label:SetPoint("TOP", m.icon, "BOTTOM", 0, -4)
                f.stops[k] = m
            end
            m.icon:ClearAllPoints()
            m.icon:SetPoint("CENTER", f.clip.strip, "CENTER", points[k + 1].at * f.clip.pps, 0)
            m.label:SetText(points[k + 1].name)
            m.icon:Show()
            m.label:Show()
        elseif m then
            m.icon:Hide()
            m.label:Hide()
        end
    end
    -- An elapsed-only flight has no end to fill towards.
    f.track:SetValue(0)
    f.track:GetStatusBarTexture():SetAlpha(fl.known and 1 or 0)
    f.land:SetShown(land and true or false)
    f.land:SetEnabled(not fl.early)
    f.land:SetAlpha(fl.early and 0.4 or 1)
end

function Look.Progress(f, fl, elapsed)
    if fl.known and fl.known > 0 then
        f.time:SetText(Clock(fl.known - elapsed))
        f.track:SetValue(math.min(elapsed / fl.known, 1))
        if f.clip:IsShown() then Look.Slide(f, fl, elapsed) end
    else
        f.time:SetText(Clock(elapsed))
    end
end

local function Layout()
    Look.Layout(bar, flight, S.Get("flightEarlyLanding") and not flight.sample)
end

local function Update()
    if not (bar and flight and bar:IsShown()) then return end
    local elapsed = GetTime() - flight.start
    if flight.sample then elapsed = elapsed % flight.known end
    Look.Progress(bar, flight, elapsed)
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
    Look.New(bar)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
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
    end, "QoL/Leveling & Travel", "QoL/Leveling & Travel:flightTimer")
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

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local STAGE_H, STAGE_MARGIN = 150, 16
local PREVIEW_ELAPSED = 66
local PREVIEW = { from = "Darkshire", to = "Stormwind", known = 150,
    points = { { name = "Darkshire", at = 0 }, { name = "Lakeshire", at = 95 }, { name = "Stormwind", at = 150 } } }
local STATES = {
    { key = "flying", label = "Flying", tip = "Partway through a flight to Stormwind, 1:24 from landing." },
}

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.bar = CreateFrame("Frame", nil, preview)
    Look.New(preview.bar)
    preview.bar.land:EnableMouse(false)
    return preview
end

local function PaintPreview(preview)
    local f = preview.bar
    local land = S.Get("flightEarlyLanding") and true or false
    Look.Layout(f, PREVIEW, land)
    Look.Progress(f, PREVIEW, PREVIEW_ELAPSED)
    local left = SIDE_GAP + f.time:GetStringWidth()
    local right = land and SIDE_GAP + LAND or DOT / 2
    local width = left + WIDTH + right
    local scale = S.Get("flightTimerScale")
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2
    if roomW > 0 and width * scale > roomW then scale = roomW / width end
    if roomH > 0 and HEIGHT * scale > roomH then scale = roomH / HEIGHT end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", preview, "CENTER", (left - right) / 2, 0)
end

local function Summary(store)
    return ("Scale %d%%%s"):format(math.floor(store.Get("flightTimerScale") * 100 + 0.5),
        store.Get("flightEarlyLanding") and ", Land Early button" or "")
end

Settings.Page("QoL/Leveling & Travel", S):Card({
    id = "flightTimer", name = "Flight Timer", order = 40, switch = "flightTimer",
    help = "The route you are flying as a line between its two ends, the stops on the way sliding past "
        .. "you, and the time left to landing. Move it in Unlock Mode.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "flightEarlyLanding", label = "Land Early Button", toggle = true,
          help = "A button beside the timer that lands you at the next flight point. Blizzard's Request "
              .. "Stop button is hidden while it shows." },
        { key = "flightTimerScale", label = "Scale", slider = { 50, 200, 5 }, unit = "%", scale = 0.01 },
    },
})
