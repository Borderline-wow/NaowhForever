-------------------------------------------------------------------------------
--  NaowhForever_Waypoints.lua -- Waypoint Pin: the spot the game is guiding you to, marked in
--  the world with its name, distance and walking time, an arrow at the screen's edge while it
--  is off screen, a navigator bar, and a moment on arrival. It follows the game's navigation
--  frame (C_Navigation), so quests, your corpse and map pins get it as well as
--  ns.PlaceWaypoint's spots, which it names.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
local SHAPES = {
    hex = { fill = MEDIA .. "waypoint_hex", ring = MEDIA .. "waypoint_hex_ring" },
    diamond = { fill = MEDIA .. "waypoint_diamond", ring = MEDIA .. "waypoint_diamond_ring" },
    dot = { fill = MEDIA .. "circle_mask", ring = MEDIA .. "circle_ring" },
}
local CHEVRON, CHECK, CROSS = MEDIA .. "chevron", MEDIA .. "check", MEDIA .. "cross"

local PIN, MARK, ARROW = 36, 12, 18          -- the pin, the mark in its middle, the edge arrow in it
local FILL_ALPHA = 0.2                       -- the pin's tint inside its outline
local CARD_W, CARD_PAD, CARD_GAP, STRIP = 180, 8, 8, 2
local NAME_SIZE, NOTE_SIZE, DIST_SIZE, TIME_SIZE, LINE_GAP, TIME_GAP = 14, 11, 18, 11, 3, 8
local CARD_H = 2 * CARD_PAD + STRIP + NAME_SIZE + LINE_GAP + DIST_SIZE
local CARD_ICON, ICON_GAP, ICON_CROP = NAME_SIZE + LINE_GAP + DIST_SIZE, 8, 0.08   -- a module's icon, beside the name
local BEAM_W, BEAM_H, BEAM_ALPHA = 2, 80, 0.55
local GROUND_W, GROUND_H = 44, 12
local EDGE_INSET = 70                        -- the edge arrow from the screen's edge
local BEHIND = math.rad(30)                  -- either side of straight down that counts as behind you
local BEHIND_Y, BEHIND_SIZE = 60, 13         -- the cue above the screen's bottom, its text
local FAR, FAR_SCALE = 400, 0.65             -- yards at which the pin is smallest, and how small
local FADE_FLOOR = 0.25                      -- the pin's alpha at your feet with Fade Up Close on
local RUN_SPEED = 7                          -- yards a second on foot, while standing still
local NAV_W, NAV_H, NAV_PAD, NAV_ICON, NAV_ARROW = 320, 40, 10, 20, 14
local NAV_NAME, NAV_SUB, NAV_DIST = 14, 11, 16
local NAV_Y = -70                            -- the navigator under the screen's top, until moved
local ARRIVED_HOLD = ns.WAYPOINT_HOLD        -- seconds the arrival shows
local REACHED, LEAVE = 5, 7                  -- yards: a target the game keeps tracking goes, and comes back

local function On()
    return S.Get("enabled") and S.Get("waypoints")
end
ns.WaypointPinOn = On

local function Yards(yards)
    return BreakUpLargeNumbers(math.floor(yards + 0.5)) .. " yd"
end

local function Walk(seconds)
    seconds = math.floor(seconds + 0.5)
    return ("about %d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function Trilinear(texture, path)
    texture:SetTexture(path, nil, nil, "TRILINEAR")
    return texture
end

-------------------------------------------------------------------------------
--  Look: the pin with its card, and the navigator. The settings preview draws the same.
-------------------------------------------------------------------------------
local Look = {}

local function Card(parent, width)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, CARD_H)
    Parts.HudBackdrop(card)
    local strip = ns.Solid(card, "ARTWORK", T.accent, 1)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(STRIP)
    return card
end

function Look.NewPin(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(PIN, PIN)
    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetAllPoints()
    pin.ring = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    pin.ring:SetAllPoints()
    pin.mark = Trilinear(pin:CreateTexture(nil, "ARTWORK", nil, 2), St.ROUND)
    pin.mark:SetSize(MARK, MARK)
    pin.mark:SetPoint("CENTER")
    pin.check = Trilinear(pin:CreateTexture(nil, "ARTWORK", nil, 2), CHECK)
    pin.check:SetSize(PIN * 0.6, PIN * 0.6)
    pin.check:SetPoint("CENTER")
    pin.check:SetVertexColor(T.bg.r, T.bg.g, T.bg.b)
    pin.arrow = Trilinear(pin:CreateTexture(nil, "ARTWORK", nil, 2), CHEVRON)
    pin.arrow:SetSize(ARROW, ARROW)
    pin.arrow:SetPoint("CENTER")
    pin.beam = ns.Solid(pin, "BACKGROUND", T.accent, BEAM_ALPHA)
    pin.beam:SetSize(BEAM_W, BEAM_H)
    pin.beam:SetPoint("TOP", pin, "BOTTOM")
    pin.ground = Trilinear(pin:CreateTexture(nil, "BACKGROUND"), SHAPES.dot.ring)
    pin.ground:SetSize(GROUND_W, GROUND_H)
    pin.ground:SetPoint("CENTER", pin.beam, "BOTTOM")

    local card = Card(pin, CARD_W)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(CARD_ICON, CARD_ICON)
    card.icon:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + STRIP))
    card.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    card.name = Parts.HudText(ns.Font(card, NAME_SIZE))
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    card.note = Parts.HudText(ns.Font(card, NOTE_SIZE, nil, T.muted))
    card.note:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -LINE_GAP)
    card.note:SetPoint("RIGHT", card.name, "RIGHT")
    card.note:SetJustifyH("LEFT")
    card.note:SetWordWrap(false)
    card.dist = Parts.HudText(ns.Font(card, DIST_SIZE, nil, T.accent))
    card.time = Parts.HudText(ns.Font(card, TIME_SIZE, nil, T.muted))
    card.time:SetPoint("BOTTOMLEFT", card.dist, "BOTTOMRIGHT", TIME_GAP, 0)
    pin.card = card
    return pin
end

-- o: shape, name, note and icon (each optional), yards, seconds (nil hides the walking time),
-- mode ("world", "edge" or "arrived"), angle (edge: radians from the screen's centre, 0 to the
-- right), card, beam.
function Look.PaintPin(pin, o)
    local a = T.accent
    local shape = SHAPES[o.shape] or SHAPES.hex
    local arrived, edge = o.mode == "arrived", o.mode == "edge"
    Trilinear(pin.fill, shape.fill):SetVertexColor(a.r, a.g, a.b, arrived and 1 or FILL_ALPHA)
    Trilinear(pin.ring, shape.ring):SetVertexColor(a.r, a.g, a.b, 1)
    pin.mark:SetVertexColor(a.r, a.g, a.b, 1)
    pin.mark:SetShown(o.mode == "world")
    pin.check:SetShown(arrived)
    pin.arrow:SetShown(edge)
    pin.arrow:SetRotation(o.angle or 0)
    pin.beam:SetShown(o.beam and not edge)
    pin.ground:SetShown(o.beam and not edge)
    pin.ground:SetVertexColor(a.r, a.g, a.b, 1)

    local card = pin.card
    card:SetShown(o.card)
    if not o.card then return end
    card.icon:SetShown(o.icon ~= nil)
    if o.icon then card.icon:SetTexture(o.icon) end
    card.name:ClearAllPoints()
    if o.icon then
        card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", ICON_GAP, 0)
    else
        card.name:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + STRIP))
    end
    card.name:SetPoint("RIGHT", -CARD_PAD, 0)
    card.name:SetText(o.name)
    card.note:SetShown(o.note ~= nil)
    card.note:SetText(o.note or "")
    card.dist:ClearAllPoints()
    card.dist:SetPoint("TOPLEFT", o.note and card.note or card.name, "BOTTOMLEFT", 0, -LINE_GAP)
    card:SetHeight(CARD_H + (o.note and NOTE_SIZE + LINE_GAP or 0))
    card.dist:SetText(arrived and "Arrived" or Yards(o.yards))
    card.time:SetText(o.seconds and not arrived and Walk(o.seconds) or "")
    -- Over the pin in the world; toward the screen's middle at an edge, so it stays on screen.
    card:ClearAllPoints()
    local cos, sin = math.cos(o.angle or 0), math.sin(o.angle or 0)
    if not edge then
        card:SetPoint("BOTTOM", pin, "TOP", 0, CARD_GAP)
    elseif math.abs(cos) >= math.abs(sin) then
        if cos > 0 then card:SetPoint("RIGHT", pin, "LEFT", -CARD_GAP, 0) else card:SetPoint("LEFT", pin, "RIGHT", CARD_GAP, 0) end
    elseif sin > 0 then
        card:SetPoint("TOP", pin, "BOTTOM", 0, -CARD_GAP)
    else
        card:SetPoint("BOTTOM", pin, "TOP", 0, CARD_GAP)
    end
end

function Look.NewNav(parent, onClear)
    local nav = CreateFrame("Frame", nil, parent)
    nav:SetSize(NAV_W, NAV_H)
    Parts.HudBackdrop(nav)
    local strip = ns.Solid(nav, "ARTWORK", T.accent, 1)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(STRIP)
    nav.fill = nav:CreateTexture(nil, "ARTWORK")
    nav.fill:SetSize(NAV_ICON, NAV_ICON)
    nav.fill:SetPoint("LEFT", NAV_PAD, 0)
    nav.ring = nav:CreateTexture(nil, "ARTWORK", nil, 1)
    nav.ring:SetAllPoints(nav.fill)
    nav.icon = nav:CreateTexture(nil, "ARTWORK")
    nav.icon:SetAllPoints(nav.fill)
    nav.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    nav.clear = Parts.IconButton(nav, onClear, CROSS, 0, "Clear the waypoint")
    nav.clear:SetPoint("RIGHT", -NAV_PAD / 2, 0)
    nav.dist = Parts.HudText(ns.Font(nav, NAV_DIST, nil, T.accent))
    nav.dist:SetPoint("RIGHT", nav.clear, "LEFT", -NAV_PAD / 2, 0)
    nav.arrow = Trilinear(nav:CreateTexture(nil, "ARTWORK"), CHEVRON)
    nav.arrow:SetSize(NAV_ARROW, NAV_ARROW)
    nav.arrow:SetPoint("RIGHT", nav.dist, "LEFT", -NAV_PAD / 2, 0)
    nav.name = Parts.HudText(ns.Font(nav, NAV_NAME))
    nav.name:SetPoint("TOPLEFT", nav.fill, "TOPRIGHT", NAV_PAD, 2)
    nav.name:SetPoint("RIGHT", nav.arrow, "LEFT", -NAV_PAD / 2, 0)
    nav.name:SetJustifyH("LEFT")
    nav.name:SetWordWrap(false)
    nav.sub = Parts.HudText(ns.Font(nav, NAV_SUB, nil, T.muted))
    nav.sub:SetPoint("TOPLEFT", nav.name, "BOTTOMLEFT", 0, -1)
    nav.sub:SetPoint("RIGHT", nav.name, "RIGHT")
    nav.sub:SetJustifyH("LEFT")
    nav.sub:SetWordWrap(false)
    return nav
end

-- o: shape, name, sub, icon (optional, in place of the shape), yards, mode, angle (radians from
-- the screen's centre, 0 to the right).
function Look.PaintNav(nav, o)
    local a = T.accent
    local shape = SHAPES[o.shape] or SHAPES.hex
    Trilinear(nav.fill, shape.fill):SetVertexColor(a.r, a.g, a.b, FILL_ALPHA)
    Trilinear(nav.ring, shape.ring):SetVertexColor(a.r, a.g, a.b, 1)
    nav.fill:SetShown(o.icon == nil)
    nav.ring:SetShown(o.icon == nil)
    nav.icon:SetShown(o.icon ~= nil)
    if o.icon then nav.icon:SetTexture(o.icon) end
    nav.name:SetText(o.name)
    nav.sub:SetText(o.sub or "")
    nav.arrow:SetShown(o.mode ~= "arrived" and o.angle ~= nil)
    nav.arrow:SetRotation(o.angle or 0)
    nav.dist:SetText(o.mode == "arrived" and "Arrived" or Yards(o.yards))
end

-------------------------------------------------------------------------------
--  Following the game's navigation frame
-------------------------------------------------------------------------------
local pin, nav, cue, driver, navFrame, unlocked, gameHidden, warned
local arrived, arrivals = false, 0
local reached   -- close to a target the game keeps tracking
local lastX, lastY   -- where the pin last stood, in UIParent units, for an arrival
local shown = {}
local painted   -- what the texts and look were last drawn for; the place and arrows move every frame
local knownSpeed = 0   -- your last readable speed: it reads secret at times, as in restricted content
local NavSample = { name = "Mage Trainer", sub = "Thunder Bluff", yards = 312, mode = "world", angle = math.pi / 2 }

-- A placed spot's note as a line of its own: " (entrance)" is "Entrance".
local function NoteText(note)
    if not note then return nil end
    local text = note:match("^%s*%((.-)%)%s*$") or note:match("^%s*(.-)%s*$")
    if text == "" then return nil end
    return text:sub(1, 1):upper() .. text:sub(2)
end

-- What the game is guiding you to: its name, its zone, and the note and icon a spot
-- ns.PlaceWaypoint set was given.
local function Target(kind)
    local types = Enum.SuperTrackingType
    if kind == types.UserWaypoint then
        local point, placed = C_Map.GetUserWaypoint(), ns.placedWaypoint
        local info = point and C_Map.GetMapInfo(point.uiMapID)
        local where = info and info.name
        if placed and point and placed.map == point.uiMapID
            and math.abs(placed.x - point.position.x * 100) < 0.05
            and math.abs(placed.y - point.position.y * 100) < 0.05 then
            return placed.title, where, NoteText(placed.note), placed.icon, true
        end
        return "Map Pin", where
    elseif kind == types.Quest then
        return C_QuestLog.GetTitleForQuestID(C_SuperTrack.GetSuperTrackedQuestID()) or "Quest"
    elseif kind == types.Corpse then
        return "Your Corpse"
    end
    return "Waypoint"
end

local function Build()
    pin = Look.NewPin(UIParent)
    pin:SetFrameStrata("LOW")
    pin:Hide()
    -- Clearing the waypoint also ends a route it is on.
    nav = Look.NewNav(UIParent, ns.ClearWaypoint)
    nav:SetFrameStrata("MEDIUM")
    nav:SetClampedToScreen(true)
    nav.mover = ns.UI.AttachMover(nav, "Waypoint Navigator", function(pos)
        S.Set("waypointNavPos", { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y })
    end, "QoL/Interface", "QoL/Interface:waypoints")
    nav:Hide()
    cue = CreateFrame("Frame", nil, UIParent)
    cue:SetSize(NAV_W, BEHIND_Y)
    cue:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BEHIND_Y)
    cue.arrow = Trilinear(cue:CreateTexture(nil, "ARTWORK"), CHEVRON)
    cue.arrow:SetSize(ARROW, ARROW)
    cue.arrow:SetPoint("TOP")
    cue.arrow:SetRotation(-math.pi / 2)
    cue.arrow:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
    cue.text = Parts.HudText(ns.Font(cue, BEHIND_SIZE))
    cue.text:SetPoint("TOP", cue.arrow, "BOTTOM", 0, -2)
    cue.text:SetText("Behind you")
    cue:Hide()
    driver = CreateFrame("Frame")
end

local function PlaceNav()
    local pos = S.Get("waypointNavPos")
    nav:ClearAllPoints()
    if pos then
        nav:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        nav:SetPoint("TOP", UIParent, "TOP", 0, NAV_Y)
    end
end

local function Update()
    if not C_Navigation.HasValidScreenPosition() then
        pin:Hide()
        cue:Hide()
        return
    end
    local yards = C_Navigation.GetDistance()
    local cx, cy = UIParent:GetCenter()
    local nx, ny = navFrame:GetCenter()
    local dx, dy = nx - cx, ny - cy
    local angle = math.atan2(dy, dx)
    local clamped = C_Navigation.WasClampedToScreen()
    local mode = clamped and "edge" or "world"
    local behind = mode == "edge" and math.abs(angle + math.pi / 2) < BEHIND

    local scale = S.Get("waypointScale")
    local near = S.Get("waypointFadeNear")
    local alpha = 1
    if mode == "world" then
        scale = scale * (1 - (1 - FAR_SCALE) * math.min(yards / FAR, 1))
        if near > 0 and yards < near then alpha = FADE_FLOOR + (1 - FADE_FLOOR) * yards / near end
    end
    pin:SetScale(scale)
    pin:SetAlpha(alpha)

    -- Offsets are in the pin's own scaled units.
    local side
    if mode == "edge" then
        local hw, hh = UIParent:GetWidth() / 2 - EDGE_INSET, UIParent:GetHeight() / 2 - EDGE_INSET
        local t = math.min(hw / math.max(math.abs(dx), 1), hh / math.max(math.abs(dy), 1))
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", UIParent, "CENTER", dx * t / scale, dy * t / scale)
        pin.onNav = false
        side = math.abs(dx) >= math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "top" or "bottom")
        lastX, lastY = cx + dx * t, cy + dy * t
    else
        -- A map pin's or corpse's navigation point is the spot on the ground: the ring at the line's
        -- foot goes there and the pin stands above it. A quest giver's is over their head, where the
        -- pin goes as it is.
        local lift = shown.beam and PIN / 2 + BEAM_H or 0
        if not pin.onNav then
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", navFrame, "CENTER", 0, lift)
            pin.onNav = true
        end
        lastX, lastY = nx, ny + lift * scale
    end
    -- The game clears a map pin on arrival, but a quest stays tracked at the quest giver.
    if shown.ground or yards > LEAVE then
        reached = false
    elseif yards <= REACHED then
        reached = true
    end
    pin:SetShown(not (behind or reached) and (mode ~= "edge" or S.Get("waypointEdge")))
    cue:SetShown(behind and not reached and S.Get("waypointEdge"))

    local speed = GetUnitSpeed("player")
    if not (issecretvalue and issecretvalue(speed)) then knownSpeed = speed end
    local seconds = S.Get("waypointTime") and yards / (knownSpeed > 0 and knownSpeed or RUN_SPEED) or nil
    shown.angle = angle
    local key = ("%s %s %d %d"):format(mode, side or "", yards + 0.5, (seconds or -1) + 0.5)
    if key ~= painted then
        painted = key
        shown.yards, shown.seconds, shown.mode = yards, seconds, mode
        Look.PaintPin(pin, shown)
        if nav:IsShown() then Look.PaintNav(nav, shown) end
    else
        pin.arrow:SetRotation(angle)
        nav.arrow:SetRotation(angle)
    end
end

local function Retitle()
    painted = nil
    local where, placed
    local kind, types = C_SuperTrack.GetHighestPrioritySuperTrackingType(), Enum.SuperTrackingType
    shown.name, where, shown.note, shown.icon, placed = Target(kind)
    shown.sub = shown.note and where and (shown.note .. St.PLACE_DOT .. where) or shown.note or where
    -- A stop on a route: the route and how far along it, in the navigator.
    local route, at, n = ns.WaypointRoute()
    shown.onRoute = placed and route ~= nil
    if shown.onRoute then shown.sub = ("%s%s%d of %d"):format(route, St.PLACE_DOT, at, n) end
    shown.shape = S.Get("waypointShape")
    shown.ground = kind == types.UserWaypoint or kind == types.Corpse
    shown.card, shown.beam = S.Get("waypointCard"), S.Get("waypointBeam") and shown.ground
    pin.onNav, reached = false, false
end

-- With no waypoint, Layout Mode still shows the navigator, on a sample, to place it by.
local function Detach()
    navFrame = nil
    if not driver then return end
    driver:SetScript("OnUpdate", nil)
    if arrived then return end
    pin:Hide()
    cue:Hide()
    if unlocked and On() then
        PlaceNav()
        Look.PaintNav(nav, NavSample)
        nav:Show()
    else
        nav:Hide()
    end
end

local function Attach()
    -- A new waypoint ends an arrival still showing.
    if arrived then
        arrived = false
        arrivals = arrivals + 1
    end
    navFrame = C_Navigation.GetFrame()
    if not navFrame then Detach() return end
    if not driver then Build() end
    PlaceNav()
    Retitle()
    lastX, lastY = nil, nil
    nav:SetShown(S.Get("waypointNav") or unlocked)
    driver:SetScript("OnUpdate", Update)
    Update()
end

-- The arrival holds where the pin last stood for ARRIVED_HOLD. The game clears a waypoint you
-- set as you reach it, its navigation frame going too, before or after this event.
local function Arrived()
    if not (driver and lastX) then return end
    arrived = true
    arrivals = arrivals + 1
    local this = arrivals
    driver:SetScript("OnUpdate", nil)
    local scale = S.Get("waypointScale")
    pin:SetScale(scale)
    pin:SetAlpha(1)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lastX / scale, lastY / scale)
    pin.onNav = false
    shown.mode = "arrived"
    if shown.onRoute then
        local route, _, _, nextTitle = ns.WaypointRoute()
        shown.note = nextTitle and ("Next: " .. nextTitle) or (route .. " done")
        shown.sub = shown.note
    end
    Look.PaintPin(pin, shown)
    pin:Show()
    cue:Hide()
    if S.Get("waypointNav") then
        Look.PaintNav(nav, shown)
        nav:Show()
    end
    ns.UI._PlayLSMSound(ns.UI.SoundPathFor(S.Get("waypointSound")))
    C_Timer.After(ARRIVED_HOLD, function()
        if this ~= arrivals then return end
        arrived = false
        if navFrame then Attach() else Detach() end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, isWaypoint)
    if event == "NAVIGATION_FRAME_CREATED" then
        Attach()
    elseif event == "NAVIGATION_FRAME_DESTROYED" then
        Detach()
    elseif event == "NAVIGATION_DESTINATION_REACHED" then
        -- isWaypoint: a stop on the way there (a zone's exit), not the spot itself.
        if not isWaypoint then Arrived() end
    -- Nothing tracked: cleared, or reached. A clear can leave the navigation frame up with no
    -- NAVIGATION_FRAME_DESTROYED, which left the navigator showing; the name stays for an arrival.
    elseif not C_SuperTrack.GetHighestPrioritySuperTrackingType() then
        if navFrame then Detach() end
    -- Tracking again on a frame that stayed: it is not created again.
    elseif not navFrame then
        if C_Navigation.GetFrame() then Attach() end
    elseif not arrived then
        Retitle()
    end
end)

-- The game's own marker keeps setting its frame's alpha, so its parts are faded instead.
local GAME_PARTS = { "Icon", "Arrow", "DistanceText", "IconBorder" }
local function FadeGameMarker()
    local hide = (On() and S.Get("waypointHideGame")) == true
    if hide == gameHidden or not SuperTrackedFrame then return end
    gameHidden = hide
    for _, key in ipairs(GAME_PARTS) do SuperTrackedFrame[key]:SetAlpha(hide and 0 or 1) end
end

local function Apply()
    FadeGameMarker()
    if not On() then
        events:UnregisterAllEvents()
        arrived = false
        arrivals = arrivals + 1
        Detach()
        return
    end
    if not C_Navigation then
        if not warned then ns.Print("Waypoint Pin needs the game's navigation, which this client does not have.") end
        warned = true
        return
    end
    events:RegisterEvent("NAVIGATION_FRAME_CREATED")
    events:RegisterEvent("NAVIGATION_FRAME_DESTROYED")
    events:RegisterEvent("NAVIGATION_DESTINATION_REACHED")
    events:RegisterEvent("SUPER_TRACKING_CHANGED")
    events:RegisterEvent("USER_WAYPOINT_UPDATED")
    if not driver then Build() end
    if C_Navigation.GetFrame() then Attach() else Detach() end
    if unlocked then nav.mover:Show() end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (type(key) == "string" and key:find("^waypoint") and key ~= "waypointNavPos") then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    if unlocked and not driver then Build() end
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if nav then
        nav.mover:Hide()
        Apply()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local STAGE_H = 190
local SAMPLE = { name = "Mage Trainer", yards = 312, seconds = 45 }
local STATES = {
    { key = "world", label = "On Screen", tip = "The spot ahead of you, 312 yards away." },
    { key = "edge", label = "Off Screen", tip = "The spot off to your right." },
    { key = "arrived", label = "Arrived", tip = "You reached it." },
}

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.pin = Look.NewPin(preview)
    return preview
end

local function PaintPreview(preview, state)
    local o = preview.o or {}
    preview.o = o
    o.name, o.yards = SAMPLE.name, SAMPLE.yards
    o.seconds = S.Get("waypointTime") and SAMPLE.seconds or nil
    o.shape, o.card, o.beam = S.Get("waypointShape"), S.Get("waypointCard"), S.Get("waypointBeam")
    o.mode, o.angle = state, 0
    local sample = preview.pin
    sample:SetScale(S.Get("waypointScale"))
    sample:ClearAllPoints()
    if state == "edge" then
        sample:SetPoint("RIGHT", preview, "RIGHT", -PIN, 0)
    else
        sample:SetPoint("CENTER", preview, "CENTER", 0, -CARD_H / 2)
    end
    Look.PaintPin(sample, o)
end

local SHAPE_CHOICES = { { hex = "Hex", diamond = "Diamond", dot = "Dot" }, { "hex", "diamond", "dot" } }

Settings.Page("QoL/Interface", S):Card({
    id = "waypoints", name = "Waypoint Pin", order = 42, switch = "waypoints",
    help = "Marks the spot you are heading to in the world, with its distance.",
    summary = function(store) return SHAPE_CHOICES[1][store.Get("waypointShape")] .. " pin" end,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "waypointShape", label = "Pin Shape", choice = SHAPE_CHOICES },
        { key = "waypointScale", label = "Pin Size", slider = { 50, 150, 5 }, unit = "%", scale = 0.01 },
        { key = "waypointCard", label = "Name and Distance", toggle = true,
          help = "A card over the pin with what it is and how far." },
        { key = "waypointTime", label = "Walking Time", toggle = true, needs = "waypointCard",
          help = "How long it takes to get there at your speed." },
        { key = "waypointBeam", label = "Line to the Ground", toggle = true,
          help = "A line from the pin down to a map pin's or corpse's spot." },
        { key = "waypointFadeNear", label = "Fade Up Close", slider = { 0, 100, 5 }, unit = "yd",
          help = "Fades the pin as you get this close, so it does not cover what you came for." },
        { key = "waypointEdge", label = "Edge Arrow Off Screen", toggle = true,
          help = "Keeps the pin at the edge of the screen, pointing the way, when the spot is off it." },
        { key = "waypointNav", label = "Navigator Bar", toggle = true,
          help = "A bar with the name, a turn arrow and the distance, while a waypoint is set." },
        { key = "waypointSound", label = "Arrival Sound", sound = true },
        { key = "waypointHideGame", label = "Hide the Game's Marker", toggle = true,
          help = "Hides the game's own marker so only the pin shows." },
    },
})
