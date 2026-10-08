-- Top Bar and Blizzard's top-centre display (battleground scores): PlaceWidgets cut out of
-- TopBar.lua and run against stub frames. Run from the repo root.
local f = assert(io.open(arg[1] or "TopBar/NaowhForever_TopBar.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local body = assert(source:match("\n(local WIDGETS_Y.-\nlocal function PlaceWidgets%(%)\n.-\nend\n)"), "PlaceWidgets")

-- A 1920x1080 screen at scale 1.
local UIParent = { GetTop = function() return 1080 end, GetRight = function() return 1920 end,
    GetEffectiveScale = function() return 1 end }

local function Region(left, right, top, bottom)
    return { left = left, right = right, top = top, bottom = bottom, shown = true, scale = 1,
        GetLeft = function(self) return self.left end, GetRight = function(self) return self.right end,
        GetTop = function(self) return self.top end, GetBottom = function(self) return self.bottom end,
        IsShown = function(self) return self.shown end,
        GetEffectiveScale = function(self) return self.scale end }
end

-- The bar across the top centre, 30 tall, its FPS / MS readout under it.
local bar = Region(800, 1120, 1080, 1050)
bar.sys = Region(930, 990, 1048, 1030)

-- Blizzard's container where its XML puts it, counting the times it is moved.
local widgets = { points = { "TOP", UIParent, "TOP", 0, -15 }, moves = 0, scale = 1 }
function widgets:GetPoint() return unpack(self.points) end
function widgets:GetNumPoints() return 1 end
function widgets:GetEffectiveScale() return self.scale end
function widgets:ClearAllPoints() self.points = {} end
function widgets:SetPoint(...) self.points = { ... }; self.moves = self.moves + 1 end

local function Load(container)
    return assert(loadstring("local bar, UIParent, UIWidgetTopCenterContainerFrame = ...\n" .. body
        .. "\nreturn PlaceWidgets"))(bar, UIParent, container)
end
local Place = Load(widgets)
local function At(y)
    local p = widgets.points
    return p[1] == "TOP" and p[2] == UIParent and p[3] == "TOP" and p[4] == 0 and p[5] == y
end

Place()
check("bar at the top: the scores go below it and its FPS / MS", At(-54))
Place()
check("placed again with nothing changed: not moved", widgets.moves == 1)

bar.sys.shown = false
Place()
check("no FPS / MS: just below the bar", At(-34))
bar.sys.shown = true

widgets.scale = 1.25
Place()
check("the display's own scale is allowed for", At(-44))
widgets.scale = 1

bar.shown = false
Place()
check("the bar off: back where the game had it", At(-15))
bar.shown = true

bar.left, bar.right, bar.top, bar.bottom = 0, 320, 300, 270
bar.sys.top, bar.sys.bottom = 268, 250
Place()
check("the bar moved to the bottom left: the scores stay at the top", At(-15))

bar.left, bar.right, bar.top, bar.bottom = 800, 1120, 600, 570
bar.sys.top, bar.sys.bottom = 568, 550
Place()
check("the bar in the middle of the screen: the scores stay at the top", At(-15))

bar.left, bar.right, bar.top, bar.bottom = 800, 1120, 1080, 1050
bar.sys.top, bar.sys.bottom = 1048, 1030
widgets.points = { "TOP", UIParent, "TOP", 0, -200 }
local moves = widgets.moves
Place()
check("placed by another addon: left where it is", At(-200) and widgets.moves == moves)
widgets.points = { "TOPLEFT", UIParent, "TOPLEFT", 40, -40 }
Place()
check("anchored some other way: left where it is", widgets.points[1] == "TOPLEFT" and widgets.moves == moves)

widgets.points = { "TOP", UIParent, "TOP", 0, -15 }
Place()
check("back at the game's spot, it is placed again", At(-54))

check("a client without the display: no error", pcall(Load(nil)))

print("PASS top bar widgets: " .. checks .. " checks")
