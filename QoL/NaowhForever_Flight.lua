-------------------------------------------------------------------------------
--  NaowhForever_Flight.lua -- the QoL flight timer: a card with the route and the time left, a
--  track you ride along with the stops marked on it, the next stop, and Land Early and Games.
--  Also Flight Games (flightGame): the one choice of what opens by itself when a flight starts,
--  nothing, the Quiz or the Aim Trainer, migrated once from the old quizFlight and aimAutoFlight.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = St.ROUND
local MOUNT_ICONS = { Alliance = "Interface\\Icons\\Ability_Mount_Gryphon_01",
    Horde = "Interface\\Icons\\Ability_Mount_Wyvern_01" }
local ICON_CROP = 0.08
local BORDER_RGB = St.BORDER_RGB

local WIDTH, PAD, ROW_GAP, CARD_ALPHA = 380, 10, 6, St.HUD_CARD_ALPHA
local HEAD_H, ROUTE_SIZE, TIME_SIZE, TIME_ROOM = 22, 14, 20, 70
local TRACK_H, ZONE_H, MOUNT, STOP, STOP_HOLE = 6, 22, 20, 10, 6
local LABEL_SIZE, LABEL_H, LABEL_GAP, LABEL_SPACE = 11, 12, 3, 8
local FOOT_SIZE, NEXT_ROOM, BTN_W, BTN_H, BTN_GAP = 12, 90, 48, 22, 6
local CHEVRON_SIZE, TEXT_GAP, TEXT_DROP = 10, 5, 1
local TRAIL_W, TRAIL_ALPHA, FILL_MIN = 48, 0.45, 0.01
local HALOS = { { size = 32, alpha = 0.14 }, { size = 26, alpha = 0.22 } }
local SPAN = WIDTH - TRACK_H
local ZONE_TOP = PAD + HEAD_H + ROW_GAP
local LABEL_TOP = ZONE_TOP + ZONE_H + LABEL_GAP
local ROUTE_CAP = (WIDTH - TIME_ROOM - CHEVRON_SIZE - 2 * TEXT_GAP) / 2
local NEXT_CAP = WIDTH - 2 * (BTN_W + BTN_GAP) - NEXT_ROOM
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

local function Short(name)
    return name and name:match("^[^,]+") or name
end

local function Disc(parent, layer, sublevel, size, c, alpha)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(CIRCLE, nil, nil, "TRILINEAR")
    t:SetSize(size, size)
    t:SetVertexColor(c.r, c.g, c.b, alpha or 1)
    return t
end

local function HalfDisc(parent, layer, side, c)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(CIRCLE, nil, nil, "TRILINEAR")
    t:SetSize(TRACK_H / 2, TRACK_H)
    t:SetPoint(side)
    if side == "LEFT" then t:SetTexCoord(0, 0.5, 0, 1) else t:SetTexCoord(0.5, 1, 0, 1) end
    t:SetVertexColor(c.r, c.g, c.b, 1)
    return t
end

local function Fit(fs, cap)
    fs:SetWidth(0)
    if fs:GetStringWidth() > cap then fs:SetWidth(cap) end
end

local function NewStop(f)
    local m = {}
    m.ring = Disc(f.marks, "ARTWORK", 1, STOP, T.fg)
    m.edge = Disc(f.marks, "ARTWORK", 0, STOP, BORDER_RGB)
    ns.PixelInset(m.edge, -1, m.ring)
    m.hole = Disc(f.marks, "ARTWORK", 2, STOP_HOLE, T.bg)
    m.hole:SetPoint("CENTER", m.ring)
    m.label = ns.Font(f, LABEL_SIZE)
    m.label:SetWordWrap(false)
    return m
end

local function PaintStop(m, passed)
    local c = passed and T.accent or T.fg
    m.ring:SetVertexColor(c.r, c.g, c.b, 1)
    m.hole:SetShown(not passed)
    local t = passed and T.muted or T.fg
    m.label:SetTextColor(t.r, t.g, t.b, 1)
end

local function NewMount(f)
    local mount = CreateFrame("Frame", nil, f)
    mount:SetSize(MOUNT, MOUNT)
    mount:SetPoint("CENTER", f.fill, "RIGHT")
    mount:SetFrameLevel(f.track:GetFrameLevel() + 2)
    local icon = mount:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    local id = GetFileIDFromPath and GetFileIDFromPath(MOUNT_ICONS[UnitFactionGroup("player")] or MOUNT_ICONS.Alliance)
    if id and id > 0 then
        icon:SetTexture(id)
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    else
        icon:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    end
    local mask = mount:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)
    local ring = mount:CreateTexture(nil, "BACKGROUND")
    ns.PixelInset(ring, -1)
    ring:SetColorTexture(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
    local ringMask = mount:CreateMaskTexture()
    ringMask:SetAllPoints(ring)
    ringMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ring:AddMaskTexture(ringMask)
    return mount
end

local function NewTrack(f)
    local track = CreateFrame("Frame", nil, f)
    track:SetPoint("TOPLEFT", PAD, -(ZONE_TOP + (ZONE_H - TRACK_H) / 2))
    track:SetSize(WIDTH, TRACK_H)
    f.track = track
    HalfDisc(track, "BACKGROUND", "LEFT", T.line)
    HalfDisc(track, "BACKGROUND", "RIGHT", T.line)
    local body = track:CreateTexture(nil, "BACKGROUND")
    body:SetColorTexture(T.line.r, T.line.g, T.line.b, 1)
    body:SetPoint("TOPLEFT", TRACK_H / 2, 0)
    body:SetPoint("BOTTOMRIGHT", -TRACK_H / 2, 0)

    f.lit = { HalfDisc(track, "BORDER", "LEFT", T.accent) }
    f.fill = track:CreateTexture(nil, "BORDER")
    f.fill:SetTexture(WHITE)
    f.fill:SetPoint("LEFT", TRACK_H / 2, 0)
    f.fill:SetHeight(TRACK_H)
    f.fill:SetGradient("HORIZONTAL", CreateColor(T.accent.r, T.accent.g, T.accent.b, 1),
        CreateColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1))
    f.lit[2] = f.fill
    f.trail = track:CreateTexture(nil, "ARTWORK")
    f.trail:SetTexture(WHITE)
    f.trail:SetBlendMode("ADD")
    f.trail:SetPoint("RIGHT", f.fill, "RIGHT")
    f.trail:SetHeight(TRACK_H)
    f.trail:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, TRAIL_ALPHA))
    f.lit[3] = f.trail
    for i, halo in ipairs(HALOS) do
        local t = Disc(track, "ARTWORK", i, halo.size, T.accentSoft, halo.alpha)
        t:SetBlendMode("ADD")
        t:SetPoint("CENTER", f.fill, "RIGHT")
        f.lit[#f.lit + 1] = t
    end

    f.marks = CreateFrame("Frame", nil, f)
    f.marks:SetAllPoints(track)
    f.marks:SetFrameLevel(track:GetFrameLevel() + 1)
    f.mount = NewMount(f)
    f.lit[#f.lit + 1] = f.mount
end

function Look.New(f)
    f:SetSize(WIDTH + 2 * PAD, 2 * PAD + HEAD_H)
    ns.Solid(f, "BACKGROUND", T.bg, CARD_ALPHA):SetAllPoints()
    ns.Border(f, BORDER_RGB)

    f.time = ns.Font(f, TIME_SIZE, nil, T.accent)
    f.time:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -PAD, -PAD - HEAD_H)
    f.from = ns.Font(f, ROUTE_SIZE, nil, T.muted)
    f.from:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, -PAD - HEAD_H)
    f.from:SetWordWrap(false)
    f.arrow = Parts.Arrow(f, CHEVRON_SIZE, T.muted)
    f.arrow:SetPoint("LEFT", f.from, "RIGHT", TEXT_GAP, -TEXT_DROP)
    f.to = ns.Font(f, ROUTE_SIZE)
    f.to:SetWordWrap(false)

    NewTrack(f)
    f.stops = {}
    f.via = {}

    f.nextKey = ns.Font(f, FOOT_SIZE, nil, T.muted)
    f.nextName = ns.Font(f, FOOT_SIZE)
    f.nextName:SetWordWrap(false)
    f.nextName:SetPoint("LEFT", f.nextKey, "RIGHT", TEXT_GAP, 0)
    f.sep = ns.Font(f, FOOT_SIZE, nil, T.muted)
    f.sep:SetText(St.PLACE_DOT)
    f.sep:SetPoint("LEFT", f.nextName, "RIGHT", 0, 0)
    f.nextTime = ns.Font(f, FOOT_SIZE, nil, T.accentSoft)
    f.nextTime:SetPoint("LEFT", f.sep, "RIGHT", 0, 0)

    f.land = ns.Button(f, "Land", BTN_W, BTN_H)
    f.games = ns.Button(f, "Games", BTN_W, BTN_H)
end

local function ShowNext(f, m)
    local on = m and true or false
    if m then
        f.nextName:SetText(m.name)
        Fit(f.nextName, NEXT_CAP)
    end
    f.nextKey:SetShown(on)
    f.nextName:SetShown(on)
    f.sep:SetShown(on)
    f.nextTime:SetShown(on)
end

local function Placed(fl, n)
    if not (fl.known and fl.known > 0 and n > 2) then return false end
    for i = 2, n do
        if not fl.points[i].at then return false end
    end
    return true
end

local function LayoutStops(f, fl, n, placed)
    local points = fl.points
    local count = placed and n - 2 or 0
    local lastRight, labelled = -LABEL_SPACE, false
    for k = 1, math.max(count, #f.stops) do
        local m = f.stops[k]
        if k <= count then
            if not m then
                m = NewStop(f)
                f.stops[k] = m
            end
            local p = points[k + 1]
            local x = TRACK_H / 2 + math.min(p.at / fl.known, 1) * SPAN
            m.at, m.name = p.at, Short(p.name)
            m.ring:ClearAllPoints()
            m.ring:SetPoint("CENTER", f.track, "LEFT", x, 0)
            m.label:SetText(m.name)
            m.label:SetWidth(0)
            local half = m.label:GetStringWidth() / 2
            local cx = math.max(half, math.min(WIDTH - half, x))
            local room = cx - half >= lastRight + LABEL_SPACE
            if room then lastRight, labelled = cx + half, true end
            m.label:ClearAllPoints()
            m.label:SetPoint("TOP", f, "TOPLEFT", PAD + cx, -LABEL_TOP)
            m.ring:Show()
            m.edge:Show()
            m.label:SetShown(room)
            PaintStop(m, false)
        elseif m then
            m.ring:Hide()
            m.edge:Hide()
            m.hole:Hide()
            m.label:Hide()
        end
    end
    f.count = count
    return labelled
end

function Look.Layout(f, fl, land, games)
    local points = fl.points
    local n = points and #points or 0
    local from = Short(n > 0 and points[1].name or fl.from)
    f.from:SetText(from or "")
    Fit(f.from, ROUTE_CAP)
    f.from:SetShown(from and true or false)
    f.arrow:SetShown(from and true or false)
    f.to:SetText(Short(n > 0 and points[n].name or fl.to) or "In flight")
    Fit(f.to, ROUTE_CAP)
    f.to:ClearAllPoints()
    if from then
        f.to:SetPoint("LEFT", f.arrow, "RIGHT", TEXT_GAP, TEXT_DROP)
    else
        f.to:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, -PAD - HEAD_H)
    end

    local known = (fl.known and fl.known > 0) and true or false
    for _, part in ipairs(f.lit) do part:SetShown(known) end
    local placed = Placed(fl, n)
    local labelled = LayoutStops(f, fl, n, placed)

    local footTop = ZONE_TOP + ZONE_H + (labelled and LABEL_GAP + LABEL_H or 0) + ROW_GAP
    f.foot = placed and "next" or n > 2 and "via" or nil
    f.nextKey:ClearAllPoints()
    f.nextKey:SetPoint("LEFT", f, "TOPLEFT", PAD, -footTop - BTN_H / 2)
    ShowNext(f, nil)
    if f.foot == "via" then
        wipe(f.via)
        for i = 2, n - 1 do f.via[#f.via + 1] = Short(points[i].name) end
        f.nextKey:SetText("Via")
        f.nextName:SetText(table.concat(f.via, ", "))
        Fit(f.nextName, NEXT_CAP)
        f.nextKey:Show()
        f.nextName:Show()
    else
        f.nextKey:SetText("Next")
    end

    f.games:SetShown(games)
    f.games:ClearAllPoints()
    f.games:SetPoint("TOPRIGHT", f, "TOPLEFT", PAD + WIDTH, -footTop)
    f.land:SetShown(land)
    f.land:ClearAllPoints()
    if games then
        f.land:SetPoint("RIGHT", f.games, "LEFT", -BTN_GAP, 0)
    else
        f.land:SetPoint("TOPRIGHT", f, "TOPLEFT", PAD + WIDTH, -footTop)
    end
    f.land:SetEnabled(not fl.early)
    f.land:SetAlpha(fl.early and 0.4 or 1)
    local foot = f.foot or land or games
    f:SetHeight((foot and footTop + BTN_H or footTop - ROW_GAP) + PAD)

    f.sec, f.nextSec, f.shown, f.at, f.passed = nil, nil, nil, math.huge, 0
end

local function Advance(f, elapsed)
    if elapsed < f.at then
        for k = 1, f.count do PaintStop(f.stops[k], false) end
        f.passed = 0
    end
    f.at = elapsed
    local passed = f.passed
    while passed < f.count and f.stops[passed + 1].at <= elapsed do
        passed = passed + 1
        PaintStop(f.stops[passed], true)
    end
    f.passed = passed
    local m = passed < f.count and f.stops[passed + 1] or nil
    if m ~= f.shown then
        f.shown, f.nextSec = m, nil
        ShowNext(f, m)
    end
    if m then
        local left = m.at - elapsed
        local sec = math.floor(left + 0.5)
        if sec ~= f.nextSec then
            f.nextSec = sec
            f.nextTime:SetText(Clock(left))
        end
    end
end

function Look.Progress(f, fl, elapsed)
    local known = fl.known and fl.known > 0 and fl.known
    local shown = known and known - elapsed or elapsed
    local sec = math.floor(math.max(0, shown) + 0.5)
    if sec ~= f.sec then
        f.sec = sec
        f.time:SetText(Clock(shown))
    end
    if not known then return end
    local w = math.max(FILL_MIN, math.min(elapsed / known, 1) * SPAN)
    f.fill:SetWidth(w)
    f.trail:SetWidth(math.min(TRAIL_W, w))
    if f.foot == "next" then Advance(f, elapsed) end
end

local AIM_OFF = "Turn on the Aim Trainer in QoL > Travel"
local AIM_MODES = { { "gridshot", "Aim Trainer: Gridshot" }, { "hexakill", "Aim Trainer: Hexakill" },
    { "reflex", "Aim Trainer: Reflex" } }

local function PickQuiz()
    if ns.AimDismiss then ns.AimDismiss() end
    if ns.QuizPlay then ns.QuizPlay("flight") end
end

local function PickAim(m)
    if ns.QuizDismiss then ns.QuizDismiss() end
    if ns.AimPlay then ns.AimPlay(m, "flight") end
end

local function GamesMenu(_, root)
    root:CreateTitle("Pass the Flight")
    root:CreateButton("Quiz", PickQuiz)
    local aimOn = ns.AimTrainerOn and ns.AimTrainerOn()
    for _, entry in ipairs(AIM_MODES) do
        local button = root:CreateButton(entry[2], PickAim, entry[1])
        if not aimOn then
            button:SetEnabled(false)
            button:SetTooltip(function(tooltip) GameTooltip_SetTitle(tooltip, AIM_OFF) end)
        end
    end
end

local function PlayClicked()
    if InCombatLockdown() then return end
    MenuUtil.CreateContextMenu(bar.games, GamesMenu)
end

local function Layout()
    local land = S.Get("flightEarlyLanding") and not flight.sample
    local games = S.Get("enabled") and S.Get("flightGame") ~= "off" and not flight.sample
    Look.Layout(bar, flight, land and true or false, games and true or false)
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
    if ns.AimDismiss then ns.AimDismiss("flight") end
end

local FLIGHT_GAMES = { off = true, none = true, quiz = true, aim = true }

local function MigrateGame()
    local db = S.DB()
    if db.flightGameMigrated then return end
    db.flightGameMigrated = true
    if db.flightGame == nil and S.Raw("quizFlight") == false then
        db.flightGame = S.Raw("aimAutoFlight") == true and "aim" or "none"
    end
    db.quizFlight, db.aimAutoFlight = nil, nil
end

local function Game()
    MigrateGame()
    local game = S.Get("flightGame")
    return FLIGHT_GAMES[game] and game or "aim"
end

local function OfferGame()
    local game = Game()
    if game == "quiz" then
        if ns.QuizOffer then ns.QuizOffer("flight") end
    elseif game == "aim" then
        if ns.AimOffer then ns.AimOffer("flight") end
    end
end

local function Board(route)
    local key = route and RouteKey(route.from, route.to)
    flight = { from = route and route.from, to = route and route.to, start = GetTime(),
        points = route and route.points,
        known = route and route.estimate or key and Times()[key] }
    pending = nil
    if On() then Show() end
    FadeBlizzardStop()
    OfferGame()
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
    bar = CreateFrame("Frame", "NaowhForeverFlightTimer", UIParent)
    Look.New(bar)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar.land._onClick = function() TaxiRequestEarlyLanding() end
    ns.Tooltip(bar.land, "Land Early", "Land at the next flight point.")
    bar.games._onClick = PlayClicked
    ns.Tooltip(bar.games, "Games", "A game to pass the flight: the Quiz or the Aim Trainer. It closes when you land.")

    -- Smooth while shown; the poll ticker only watches for boarding and landing.
    bar:SetScript("OnUpdate", Update)
    -- The mover reports offsets in the timer's own scaled units; they are saved in screen
    -- units so the Scale slider resizes it in place.
    bar.mover = ns.UI.AttachMover(bar, "Flight Timer", function(pos)
        local scale = bar:GetScale()
        S.Set("flightTimerPos", { point = pos.point, relPoint = pos.relPoint,
            x = pos.x * scale, y = pos.y * scale })
    end, "QoL/Travel", "QoL/Travel:flightTimer")
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
    MigrateGame()
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
    if key == "enabled" or key == "flightTimer" or key == "flightEarlyLanding" or key == "flightGame"
        or key == "flightTimerScale" or key == "aimTrainer" then
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
    preview.bar.games:EnableMouse(false)
    return preview
end

local function PaintPreview(preview)
    local f = preview.bar
    local games = S.Get("enabled") and S.Get("flightGame") ~= "off"
    Look.Layout(f, PREVIEW, S.Get("flightEarlyLanding") and true or false, games and true or false)
    Look.Progress(f, PREVIEW, PREVIEW_ELAPSED)
    local w, h = f:GetWidth(), f:GetHeight()
    local scale = S.Get("flightTimerScale")
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2
    if roomW > 0 and w * scale > roomW then scale = roomW / w end
    if roomH > 0 and h * scale > roomH then scale = roomH / h end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
end

local function Summary(store)
    return ("Scale %d%%%s"):format(math.floor(store.Get("flightTimerScale") * 100 + 0.5),
        store.Get("flightEarlyLanding") and ", Land Early button" or "")
end

Settings.Page("QoL/Travel", S):Card({
    id = "flightTimer", name = "Flight Timer", order = 10, switch = "flightTimer",
    help = "Your flight on a card: time left, the stops on a track, and the next stop.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "flightEarlyLanding", label = "Land Early Button", toggle = true,
          help = "A Land button that lands you at the next flight point." },
        { key = "flightTimerScale", label = "Scale", slider = { 50, 200, 5 }, unit = "%", scale = 0.01 },
    },
})

local GAME_NAMES = { off = "Off", none = "Button only", quiz = "Quiz", aim = "Aim Trainer" }
local GAMES = { GAME_NAMES, { "off", "none", "quiz", "aim" } }

local function GamesSummary()
    local game = Game()
    if game == "off" then return "Off: no Games button" end
    if game == "none" then return "Games button, nothing opens by itself" end
    if game == "aim" and not (ns.AimTrainerOn and ns.AimTrainerOn()) then
        return "Aim Trainer, but it is off: nothing opens"
    end
    return GAME_NAMES[game] .. " when a flight starts"
end

Settings.Page("QoL/Travel", S):Card({
    id = "flightGames", name = "Flight Games", order = 15,
    help = "A game that opens when a flight starts and closes when you land.",
    summary = GamesSummary,
    rows = {
        { key = "flightGame", label = "On Flights", choice = GAMES,
          get = Game, set = function(v) S.Set("flightGame", v) end,
          help = "Off hides the Games button; Button only keeps it without opening anything. "
              .. "The Aim Trainer needs its own switch on." },
    },
})
