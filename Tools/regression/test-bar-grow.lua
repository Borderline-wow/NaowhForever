-- Growth Direction on the shared item bar and the Gear Set and Trinket bars: Right, Left, Up and
-- Down place buttons from the matching corner, the saved Horizontal and Vertical still mean Right
-- and Down, and every bar's default is the way it grew before. Run with Lua 5.1 from the repo root.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function Button(parent)
    local b = { parent = parent }
    function b:SetPoint(...) self.point = { ... } end
    function b:ClearAllPoints() self.point = nil end
    function b:SetSize(w, h) self.w, self.h = w, h end
    function b:GetParent() return self.parent end
    return b
end

local ns = { THEME = {}, Shared = { Style = dofile("Tools/regression/shared_style.lua") } }
local env = setmetatable({ NaowhForever = ns }, { __index = _G })
env._G = env
local function Load(path, ...)
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk(...)
end

Load("Shared/UI/ItemBar.lua")
local ItemBar = ns.Shared.ItemBar

check("Horizontal and Row mean Right", ItemBar.GrowOf("horizontal") == "RIGHT" and ItemBar.GrowOf("row") == "RIGHT")
check("Vertical and Stacked mean Down", ItemBar.GrowOf("vertical") == "DOWN" and ItemBar.GrowOf("stacked") == "DOWN")
check("the four directions are themselves", ItemBar.GrowOf("LEFT") == "LEFT" and ItemBar.GrowOf("UP") == "UP")
check("only Up and Down are vertical", ItemBar.Vertical("UP") and ItemBar.Vertical("DOWN")
    and not ItemBar.Vertical("LEFT") and not ItemBar.Vertical("RIGHT"))

local choice = ItemBar.GrowChoice()
check("the choice lists Right, Left, Up, Down", choice[2][1] == "RIGHT" and choice[2][2] == "LEFT"
    and choice[2][3] == "UP" and choice[2][4] == "DOWN" and choice[1].DOWN == "Down")
choice = ItemBar.GrowChoice("row", "stacked")
check("a bar's saved Right and Down keep their names", choice[2][1] == "row" and choice[2][4] == "stacked"
    and choice[1].row == "Right" and choice[1].stacked == "Down")

local parent = {}
local button = Button(parent)
local function At(grow, index)
    ItemBar.Place(button, parent, index, 30, 4, grow, ItemBar.ONE_LINE)
    return button.point
end
local p = At("RIGHT", 3)
check("right: from the top left", p[1] == "TOPLEFT" and p[4] == 68 and p[5] == 0)
p = At("LEFT", 3)
check("left: from the top right", p[1] == "TOPRIGHT" and p[4] == -68 and p[5] == 0)
p = At("UP", 3)
check("up: from the bottom left", p[1] == "BOTTOMLEFT" and p[4] == 0 and p[5] == 68)
p = At("DOWN", 3)
check("down: from the top left", p[1] == "TOPLEFT" and p[4] == 0 and p[5] == -68)

local w, h = ItemBar.Size(3, 30, 4, "LEFT", ItemBar.ONE_LINE)
check("a row is as wide as its buttons", w == 98 and h == 30)
w, h = ItemBar.Size(3, 30, 4, "UP", ItemBar.ONE_LINE)
check("a column is as tall as its buttons", w == 30 and h == 98)

local G = { C = { TRINKET_SLOTS = { 13, 14 } }, Style = { ICON_CROP = 0, ICON_INSET = 1, EMPTY_ICON = 1, BLACK = {} } }
ns.GearSets = G
env.GetInventoryItemTexture = function() return 1 end
Load("NaowhForever_Combat/GearSets/View/Look.lua")
local Look = G.Look

local frame, add = Button(), Button()
local set = { icon = 1, lost = 0, equipped = false }
local function SetButton(grow, i)
    local b = Button(frame)
    b.icon = { SetTexture = function() end, SetDesaturated = function() end }
    b.border = { SetColor = function() end }
    b.Show = function() end
    Look.SetButton(b, set, i, 32, 4, grow)
    return b.point
end
p = SetButton("RIGHT", 2)
check("gear bar, right: today's row", p[1] == "TOPLEFT" and p[4] == 36 and p[5] == 0)
p = SetButton("LEFT", 2)
check("gear bar, left: from the right edge", p[1] == "TOPRIGHT" and p[4] == -36)
p = SetButton("DOWN", 2)
check("gear bar, down: a column", p[1] == "TOPLEFT" and p[4] == 0 and p[5] == -36)

Look.Fit(frame, add, 2, 32, 4, "RIGHT")
check("gear bar, right: the + after the sets, today's size", add.point[4] == 72 and frame.w == 108 and frame.h == 32)
Look.Fit(frame, add, 2, 32, 4, "UP")
check("gear bar, up: the + above the sets", add.point[1] == "BOTTOMLEFT" and add.point[5] == 72
    and frame.w == 32 and frame.h == 108)

local slots = { Button(frame), Button(frame) }
for _, slot in ipairs(slots) do slot.icon = { SetTexture = function() end } end
Look.Trinkets(frame, slots, 36, 4, "RIGHT")
check("trinkets, right: today's row", frame.w == 76 and frame.h == 36 and slots[2].point[1] == "TOPLEFT"
    and slots[2].point[4] == 40)
Look.Trinkets(frame, slots, 36, 4, "LEFT")
check("trinkets, left: the second sits left of the first", slots[1].point[1] == "TOPRIGHT" and slots[2].point[4] == -40)

local defaults = io.open("Core/Settings.lua", "rb"):read("*a")
for _, key in ipairs({ "foodBarGrow", "gearBarGrow", "trinketGrow" }) do
    check(key .. " defaults to Right", defaults:find(key .. ' = "RIGHT"', 1, true) ~= nil)
end
check("Blessings keeps its Horizontal default", defaults:find('blessLayout = "horizontal"', 1, true) ~= nil)
check("Group Buttons keeps its Stacked default", defaults:find('groupButtonsLayout = "stacked"', 1, true) ~= nil)

print("test-bar-grow: " .. checks .. " checks passed")
