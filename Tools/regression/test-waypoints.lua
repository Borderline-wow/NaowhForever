-- Run with Lua 5.1 from the repository root: the Waypoint Pin against stubs of the game's
-- navigation. Off by default and idle while off; on, it follows the navigation frame with the
-- name ns.PlaceWaypoint gave the spot, moves to the screen's edge or the behind-you cue while
-- the spot is off screen, shows the arrival where the pin stood even once the game has cleared
-- the waypoint, ignores stops on the way, and fades the game's own marker only while it is on.
-- These do not emulate rendering or the 3D projection.
local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local W, H = 1920, 1080
local NOOP = function() end
local made = {}
local Frame = {}
local FrameMeta = { __index = function(_, k)
    if Frame[k] then return Frame[k] end
    if type(k) == "string" and k:match("^%u") then return NOOP end
end }

local function NewFrame(kind, parent)
    local f = setmetatable({ kind = kind, parent = parent, scripts = {}, events = {}, shown = true, alpha = 1 }, FrameMeta)
    made[#made + 1] = f
    return f
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:IsShown() return self.shown end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:SetScale(v) self.scale = v end
function Frame:ClearAllPoints() self.point, self.points = nil, {} end
function Frame:SetPoint(...)
    self.point = { ... }
    self.points = self.points or {}
    self.points[#self.points + 1] = self.point
end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetRotation(r) self.rotation = r end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetHeight(h) self.height = h end
function Frame:CreateTexture() return NewFrame("Texture", self) end
function Frame:CreateFontString() return NewFrame("FontString", self) end

local UIParent = NewFrame("Frame")
function UIParent:GetWidth() return W end
function UIParent:GetHeight() return H end
function UIParent:GetCenter() return W / 2, H / 2 end

local settings = {}
local defaults = { enabled = true, waypoints = false, waypointShape = "hex", waypointScale = 1, waypointCard = true,
    waypointTime = true, waypointBeam = true, waypointFadeNear = 40, waypointEdge = true, waypointNav = true,
    waypointSound = "none", waypointHideGame = true }
local S = {}
function S.Get(k) if settings[k] ~= nil then return settings[k] end return defaults[k] end
function S.Set(k, v) settings[k] = v end

local nav = { frame = nil, valid = true, clamped = false, distance = 312, x = 1100, y = 700 }
local navFrame = NewFrame("NavFrame")
function navFrame:GetCenter() return nav.x, nav.y end
local userWaypoint, cleared, superCleared = nil, 0, 0
local timers, played, printed = {}, {}, {}
local speed = 0
local tracking = 1   -- Enum.SuperTrackingType.UserWaypoint

local gameMarker = {}
for _, key in ipairs({ "Icon", "Arrow", "DistanceText", "IconBorder" }) do gameMarker[key] = NewFrame("Texture") end

local function Theme() return { r = 0, g = 0.57, b = 0.93 } end
local routeInfo   -- { title, at, n, next } while a route is followed
local ns = {
    QoLSettings = S,
    WAYPOINT_HOLD = 4,
    WaypointRoute = function() if routeInfo then return unpack(routeInfo) end end,
    THEME = { accent = Theme(), accentSoft = Theme(), fg = Theme(), muted = Theme(), bg = Theme() },
    Font = function(parent) return parent:CreateFontString() end,
    Solid = function(parent) return parent:CreateTexture() end,
    Print = function(msg) printed[#printed + 1] = msg end,
    ClearWaypoint = function()
        userWaypoint = nil
        cleared, superCleared = cleared + 1, superCleared + 1
    end,
    Apply = NOOP, ShowRaidReminderAnchorConfig = NOOP, HideRaidReminderAnchorConfig = NOOP,
    UI = {
        AttachMover = function(frame) return NewFrame("Mover", frame) end,
        _PlayLSMSound = function(path) if path then played[#played + 1] = path end end,
        SoundPathFor = function(key) if key ~= "none" then return "sound:" .. key end end,
    },
    Shared = {
        Style = { ROUND = "round", PLACE_DOT = " . " },
        Parts = {
            HudBackdrop = NOOP,
            HudText = function(fs) return fs end,
            IconButton = function(parent, onClick)
                local b = NewFrame("Button", parent)
                b.click = onClick
                return b
            end,
        },
    },
}

local env = setmetatable({
    NaowhForever = ns,
    UIParent = UIParent,
    CreateFrame = function(kind, _, parent) return NewFrame(kind, parent) end,
    C_Navigation = {
        GetFrame = function() return nav.frame end,
        HasValidScreenPosition = function() return nav.valid end,
        WasClampedToScreen = function() return nav.clamped end,
        GetDistance = function() return nav.distance end,
    },
    C_SuperTrack = {
        GetHighestPrioritySuperTrackingType = function() return tracking end,
        GetSuperTrackedQuestID = function() return 7 end,
        ClearAllSuperTracked = function() superCleared = superCleared + 1 end,
    },
    C_Map = {
        GetUserWaypoint = function() return userWaypoint end,
        ClearUserWaypoint = function() userWaypoint = nil; cleared = cleared + 1 end,
        GetMapInfo = function() return { name = "Thunder Bluff" } end,
    },
    C_QuestLog = { GetTitleForQuestID = function() return "The Barrens Oases" end },
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end },
    Enum = { SuperTrackingType = { Quest = 0, UserWaypoint = 1, Corpse = 2 } },
    SuperTrackedFrame = gameMarker,
    GetUnitSpeed = function() return speed end,
    issecretvalue = function(v) return v == "secret" end,
    GetTime = function() return 0 end,
    BreakUpLargeNumbers = function(n)
        local s = tostring(n)
        while true do
            local k
            s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
            if k == 0 then return s end
        end
    end,
    hooksecurefunc = function(tbl, name, fn)
        local orig = tbl[name]
        tbl[name] = function(...)
            orig(...)
            fn(...)
        end
    end,
}, { __index = _G })
env._G = env
local f = assert(io.open("QoL/NaowhForever_Waypoints.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local chunk = assert(loadstring(source, "QoL/NaowhForever_Waypoints.lua"))
setfenv(chunk, env)
chunk()

local function Find(pred)
    for _, fr in ipairs(made) do
        if pred(fr) then return fr end
    end
end
local boot = Find(function(fr) return fr.events.PLAYER_LOGIN end)
boot.scripts.OnEvent(boot, "PLAYER_LOGIN")
local events = Find(function(fr) return fr.scripts.OnEvent and fr ~= boot end)

-- Off by default: nothing listens and nothing is built.
Check(next(events.events) == nil, "off by default, no events")
Check(not Find(function(fr) return fr.card end), "and no pin built")
Check(gameMarker.Icon.alpha == 1, "and the game's marker untouched")

-- On with no waypoint: it listens, shows nothing, and fades the game's marker.
S.Set("waypoints", true)
Check(events.events.NAVIGATION_FRAME_CREATED and events.events.NAVIGATION_DESTINATION_REACHED, "on, it listens")
local pin = Find(function(fr) return fr.card end)
local navBar = Find(function(fr) return fr.mover end)
local driver = Find(function(fr) return fr.kind == "Frame" and fr.parent == nil and fr ~= UIParent and fr ~= boot
    and fr ~= events end)
Check(pin and not pin:IsShown() and not navBar:IsShown(), "with no waypoint nothing shows")
Check(gameMarker.Icon.alpha == 0 and gameMarker.DistanceText.alpha == 0, "the game's marker is faded")

-- A spot from ns.PlaceWaypoint: followed on the navigation frame, named as it was placed.
ns.placedWaypoint = { title = "Mage Trainer", map = 88, x = 46.2, y = 49.8 }
userWaypoint = { uiMapID = 88, position = { x = 0.462, y = 0.498 } }
nav.frame = navFrame
events.scripts.OnEvent(events, "NAVIGATION_FRAME_CREATED")
Check(pin:IsShown() and pin.point[2] == navFrame and pin.point[5] == 36 / 2 + 80,
    "the pin stands its line's length above the navigation point, the ring on the spot")
S.Set("waypointBeam", false)
Check(pin.point[2] == navFrame and pin.point[5] == 0, "with no line it sits on the spot")
S.Set("waypointBeam", nil)
Check(pin.card.name.text == "Mage Trainer" and pin.card.dist.text == "312 yd", "named as placed, with its distance")
Check(pin.card.time.text == "about 0:45", "standing still, the walking time is at running pace")
speed = 14
driver.scripts.OnUpdate(driver, 0)
Check(pin.card.time.text == "about 0:22", "moving, at your own speed")
speed = "secret"
driver.scripts.OnUpdate(driver, 0)
Check(pin.card.time.text == "about 0:22", "a speed that reads secret keeps the last readable one")
speed = 14
Check(navBar:IsShown() and navBar.name.text == "Mage Trainer" and navBar.sub.text == "Thunder Bluff",
    "the navigator names it and its zone")
Check(navBar.dist.text == "312 yd" and pin.scale < 1 and pin.scale > 0.65, "and shrinks the pin with distance")
Check(not pin.card.note.shown and not pin.card.icon.shown and navBar.fill.shown, "no note or icon: neither shows")
local plainH = pin.card.height
-- A note and an icon from the module that placed it: a line under the name, the icon beside it
-- and in the navigator in place of the shape.
ns.placedWaypoint.note, ns.placedWaypoint.icon = " (weapon Master)", 132
events.scripts.OnEvent(events, "USER_WAYPOINT_UPDATED")
driver.scripts.OnUpdate(driver, 0)
Check(pin.card.note.shown and pin.card.note.text == "Weapon Master" and pin.card.height > plainH,
    "the note on its own line, the card taller")
Check(pin.card.icon.shown and pin.card.icon.texture == 132 and pin.card.name.points[1][2] == pin.card.icon, "the icon beside the name")
Check(navBar.sub.text == "Weapon Master . Thunder Bluff" and navBar.icon.shown and navBar.icon.texture == 132
    and not navBar.fill.shown, "the navigator: note and zone, the icon in place of the shape")
ns.placedWaypoint.note, ns.placedWaypoint.icon = nil, nil
events.scripts.OnEvent(events, "USER_WAYPOINT_UPDATED")
driver.scripts.OnUpdate(driver, 0)
Check(not pin.card.note.shown and pin.card.height == plainH, "and back without them")
nav.distance = 20
driver.scripts.OnUpdate(driver, 0)
Check(pin.alpha < 1 and pin.alpha >= 0.25, "it fades up close")
nav.distance = 1240
driver.scripts.OnUpdate(driver, 0)
Check(pin.card.dist.text == "1,240 yd", "long distances read with a comma")

-- Off screen to the right: at the edge, the arrow pointing right, the card toward the middle.
nav.clamped, nav.x, nav.y = true, 2400, 540
driver.scripts.OnUpdate(driver, 0)
Check(pin.point[2] == UIParent and pin.point[4] == W / 2 - 70 and pin.point[5] == 0, "clamped right, it sits at the edge")
Check(pin.arrow.shown and pin.arrow.rotation == 0 and not pin.beam.shown, "with the arrow out and no line down")
Check(pin.card.point[1] == "RIGHT" and pin.card.point[3] == "LEFT", "the card on the screen's side of it")
S.Set("waypointScale", 1.5)
driver.scripts.OnUpdate(driver, 0)
Check(math.abs(pin.point[4] * pin.scale - (W / 2 - 70)) < 0.01, "a bigger pin still sits on the edge")
S.Set("waypointScale", nil)
-- Off the bottom edge, but not behind: the card goes above the pin, on screen.
nav.x, nav.y = 960 + 1000 * math.cos(math.rad(-50)), 540 + 1000 * math.sin(math.rad(-50))
driver.scripts.OnUpdate(driver, 0)
Check(pin:IsShown() and pin.card.point[1] == "BOTTOM" and pin.card.point[3] == "TOP", "on the bottom edge the card is above it")
nav.x, nav.y = 1200, 1600
driver.scripts.OnUpdate(driver, 0)
Check(pin.card.point[1] == "TOP" and pin.card.point[3] == "BOTTOM", "on the top edge, below it")
-- Behind the camera (straight down): the behind-you cue instead.
nav.x, nav.y = 960, -900
driver.scripts.OnUpdate(driver, 0)
local cue = Find(function(fr) return fr.text and fr.arrow and not fr.card and not fr.mover end)
Check(not pin:IsShown() and cue:IsShown() and cue.text.text == "Behind you", "behind you, the cue shows instead")
S.Set("waypointEdge", false)
driver.scripts.OnUpdate(driver, 0)
Check(not cue:IsShown(), "and not with Edge Arrow off")
S.Set("waypointEdge", nil)
nav.clamped, nav.x, nav.y = false, 1100, 700
driver.scripts.OnUpdate(driver, 0)
Check(pin:IsShown() and pin.point[2] == navFrame, "back on screen, back on the navigation frame")

-- A stop on the way there (a zone's exit) is not the arrival.
S.Set("waypointSound", "naowh")
local timersBefore = #timers
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", true)
driver.scripts.OnUpdate(driver, 0)
Check(pin.card.dist.text ~= "Arrived" and #timers == timersBefore and #played == 0, "a stop on the way is not an arrival")
local stoodScale = pin.scale

-- Reaching a waypoint you set: the game clears its tracking and the frame goes before the
-- event reaches us. The arrival still shows, named, where the pin stood, then goes.
tracking = nil
events.scripts.OnEvent(events, "SUPER_TRACKING_CHANGED")
nav.frame = nil
events.scripts.OnEvent(events, "NAVIGATION_FRAME_DESTROYED")
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
Check(pin:IsShown() and pin.card.dist.text == "Arrived" and pin.check.shown and pin.card.name.text == "Mage Trainer",
    "the arrival shows, still named, after the game cleared it")
Check(pin.point[2] == UIParent and pin.point[3] == "BOTTOMLEFT" and pin.point[4] == 1100
    and math.abs(pin.point[5] - (700 + (36 / 2 + 80) * stoodScale)) < 1e-6,
    "where the pin stood")
Check(navBar:IsShown() and navBar.dist.text == "Arrived" and played[#played] == "sound:naowh", "on the bar too, with the sound")
timers[#timers].fn()
Check(not pin:IsShown() and not navBar:IsShown() and driver.scripts.OnUpdate == nil, "then it goes, and it is idle")
-- The other order: the arrival first, then the game clears it. The arrival stays up.
tracking = 1
nav.frame = navFrame
events.scripts.OnEvent(events, "NAVIGATION_FRAME_CREATED")
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
tracking = nil
events.scripts.OnEvent(events, "SUPER_TRACKING_CHANGED")
nav.frame = nil
events.scripts.OnEvent(events, "NAVIGATION_FRAME_DESTROYED")
Check(pin:IsShown() and pin.card.dist.text == "Arrived" and navBar:IsShown(), "cleared after the arrival, it stays up")
timers[#timers].fn()
Check(not pin:IsShown() and not navBar:IsShown(), "until its time is up")

-- A stop on a route: the navigator says which, and the arrival names the next stop, or says the
-- route is done on its last.
tracking = 1
ns.placedWaypoint = { title = "Mage Trainer", map = 88, x = 46.2, y = 49.8 }
userWaypoint = { uiMapID = 88, position = { x = 0.462, y = 0.498 } }
routeInfo = { "Training run", 2, 4, "Weapon Master" }
nav.frame = navFrame
events.scripts.OnEvent(events, "NAVIGATION_FRAME_CREATED")
Check(navBar.sub.text == "Training run . 2 of 4", "the navigator shows the route and the stop")
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
Check(pin.card.note.text == "Next: Weapon Master" and navBar.sub.text == "Next: Weapon Master", "the arrival names the next stop")
timers[#timers].fn()
routeInfo = { "Training run", 4, 4, nil }
events.scripts.OnEvent(events, "USER_WAYPOINT_UPDATED")
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
Check(pin.card.note.text == "Training run done", "the last stop says the route is done")
timers[#timers].fn()
routeInfo = nil
-- A spot the route did not place (a quest) is not shown as a stop.
tracking = 0
routeInfo = { "Training run", 2, 4, "Weapon Master" }
events.scripts.OnEvent(events, "NAVIGATION_FRAME_CREATED")
Check(navBar.sub.text == "", "a quest is not a stop on it")
routeInfo = nil

-- A quest the game keeps tracking: the arrival shows, then the pin follows it again. An older
-- arrival's timer does nothing.
nav.frame = navFrame
events.scripts.OnEvent(events, "NAVIGATION_FRAME_CREATED")
Check(pin.card.name.text == "The Barrens Oases", "a quest is named from the quest log")
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
local first = timers[#timers]
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
first.fn()
Check(pin.card.dist.text == "Arrived" and driver.scripts.OnUpdate == nil, "an older arrival's timer does nothing")
timers[#timers].fn()
Check(pin:IsShown() and pin.point[2] == navFrame and driver.scripts.OnUpdate ~= nil, "then it follows the quest again")

-- A new waypoint during an arrival ends it.
events.scripts.OnEvent(events, "NAVIGATION_DESTINATION_REACHED", false)
first = timers[#timers]
events.scripts.OnEvent(events, "NAVIGATION_FRAME_CREATED")
Check(driver.scripts.OnUpdate ~= nil and pin.card.dist.text ~= "Arrived", "a new waypoint ends the arrival")
first.fn()
Check(driver.scripts.OnUpdate ~= nil, "and its timer does nothing")

-- The navigator's clear button clears the waypoint and the game's tracking.
navBar.clear.click()
Check(cleared == 1 and superCleared == 1, "the navigator clears the waypoint")
-- The game can keep its navigation frame after a clear and send no NAVIGATION_FRAME_DESTROYED.
tracking = nil
events.scripts.OnEvent(events, "SUPER_TRACKING_CHANGED")
Check(not navBar:IsShown() and not pin:IsShown() and driver.scripts.OnUpdate == nil,
    "with nothing tracked the navigator goes, though the frame stayed")
tracking = 1
events.scripts.OnEvent(events, "SUPER_TRACKING_CHANGED")
Check(navBar:IsShown() and driver.scripts.OnUpdate ~= nil, "tracking again on that frame brings it back")

-- Off again: idle, and the game's marker back.
S.Set("waypoints", false)
Check(next(events.events) == nil and not pin:IsShown() and driver.scripts.OnUpdate == nil, "off, it stops listening")
Check(gameMarker.Icon.alpha == 1 and gameMarker.IconBorder.alpha == 1, "and the game's marker is back")
Check(#printed == 0, "nothing printed")

print(("test-waypoints: %d checks passed"):format(checks))
