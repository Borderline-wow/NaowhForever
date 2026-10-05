-- Run with Lua 5.1 from the repository root: the Professions window can be dragged. Until it
-- has been, it opens on Blizzard's window as before; once it has, it opens where it was left
-- and Blizzard's invisible window is pinned under it, never in combat.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local source = Read("Professions/NaowhForever_Professions.lua")
local first = assert(source:find("local Drag = {}", 1, true))
local save = assert(source:find("function Drag.Save()", first, true))
local last = assert(source:find("\nend\n", save, true))
local chunk = "local win\n" .. source:sub(first, last + 4)
    .. "return function(w) win = w end, Drag"

local function Frame(name)
    local f = { name = name, points = {}, shown = true }
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:IsShown() return self.shown end
    function f:GetLeft() return self.left end
    function f:GetTop() return self.top end
    return f
end

local settings, combat = {}, false
local pf, ui, win = Frame("pf"), Frame("UIParent"), Frame("win")
local env = {
    S = { Get = function(k) return settings[k] end, Set = function(k, v) settings[k] = v end },
    InCombatLockdown = function() return combat end,
    ProfessionsFrame = pf,
    UIParent = ui,
}
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local SetWin, Drag = fn()
SetWin(win)
local Follow, PlaceWindow, SavePosition = Drag.Follow, Drag.Place, Drag.Save
local function Pending() return Drag.pending end

-- Never dragged: on Blizzard's window, and Blizzard's window is left to the panel manager.
PlaceWindow()
check("undragged window sits on Blizzard's", win.points[1][2] == pf and win.points[1][1] == "TOPLEFT")
Follow()
check("undragged leaves Blizzard's window alone", #pf.points == 0)

-- Dragged: the position is kept and the window opens there.
win.left, win.top = 300, 700
SavePosition()
check("position saved", settings.windowPos.x == 300 and settings.windowPos.y == 700)
PlaceWindow()
check("dragged window sits where it was left",
    win.points[1][2] == ui and win.points[1][4] == 300 and win.points[1][5] == 700)
Follow()
check("Blizzard's window pinned under it", #pf.points == 1 and pf.points[1][2] == win)

-- In combat nothing moves; the pin waits for combat to end.
pf.points = { { "TOPLEFT", ui, "TOPLEFT", 16, -116 } }
combat = true
Follow()
check("no move in combat", pf.points[1][2] == ui)
check("pin queued", Pending())
combat = false
Follow()
check("pinned after combat", pf.points[1][2] == win and not Pending())

-- A hidden window (module off, or a profession it does not show) does not pull Blizzard's.
pf.points = { { "TOPLEFT", ui, "TOPLEFT", 16, -116 } }
win.shown = false
Follow()
check("hidden window leaves Blizzard's alone", pf.points[1][2] == ui)

print(("profession window drag: %d checks passed"):format(checks))
