-- Top Bar FPS / MS readout: its colours and text, and what the ticker's second costs. Cut out of
-- TopBar.lua and run on stubs that make no garbage. Run from the repo root.
local f = assert(io.open(arg[1] or "TopBar/NaowhForever_TopBar.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end
local Measure = dofile("Tools/regression/measure.lua")(check)

local function Slice(a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local code = table.concat({
    "local bar, S, On, Look = ...",
    Slice("local function Hex(r, g, b)", "\n-------------------------------------------------------------------------------\n--  Tooltips"),
    Slice("local SYSTEM_TEXT", "\nlocal NO_COORDS"),
    Slice("local function UpdateSystem()", "\nlocal function UpdateResting()"),
    "return { UpdateSystem = UpdateSystem, FpsRGB = FpsRGB, MsRGB = MsRGB }",
}, "\n")

local fps, ms, writes = 144, 38, 0
local text = {
    SetText = function(self, v) self.value = v; writes = writes + 1 end,
    GetStringWidth = function() return 120 end,
}
local sys = {
    text = text,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetWidth = function(self, w) self.w = w end,
}
local settings = { showSystem = true }
local S = { Get = function(k) return settings[k] end }
local chunk = assert(loadstring(code))
setfenv(chunk, setmetatable({
    GetFramerate = function() return fps end,
    GetNetStats = function() return 0, 0, ms, 90 end,
}, { __index = _G }))
local api = chunk({ sys = sys }, S, function() return true end, {})

api.UpdateSystem()
check("the readout's text", text.value == "FPS: |cff40ff40144|r  MS: |cff40ff4038|r")
check("sized to its text and shown", sys.w == 130 and sys.shown)
fps, ms = 45, 160
api.UpdateSystem()
check("bands change colour", text.value == "FPS: |cffffff4045|r  MS: |cffff5940160|r")
local r, g, b = api.FpsRGB(20)
check("the tooltip's colours are the readout's", r == 1 and g == 0.35 and b == 0.25)
r, g, b = api.MsRGB(100)
check("the tooltip's latency colour", r == 1 and g == 1 and b == 0.25)

writes = 0
api.UpdateSystem()
check("the same numbers are not written again", writes == 0)
fps = 46
api.UpdateSystem()
check("a new number is", writes == 1 and text.value:find("FPS: |cffffff4046|r", 1, true) == 1)
settings.showSystem = false
api.UpdateSystem()
check("switched off, it hides", not sys.shown)
settings.showSystem = true
writes = 0
api.UpdateSystem()
check("shown again, it is written again", writes == 1 and sys.shown)

Measure("a second of the ticker, numbers unchanged", 0.01, api.UpdateSystem)

check("the badge and resting events are registered only while the bar is up",
    source:find("for i = 1, #BAR_EVENTS do events:RegisterEvent(BAR_EVENTS[i]) end", 1, true) ~= nil
    and not source:find('events:RegisterEvent("FRIENDLIST_UPDATE")', 1, true))
check("GameTooltip is hooked with the bar's first tooltip, not at load",
    not source:find("\nGameTooltip:HookScript", 1, true))

print("PASS top bar readout: " .. checks .. " checks")
