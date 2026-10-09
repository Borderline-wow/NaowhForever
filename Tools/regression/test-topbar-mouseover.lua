-- Top Bar Show On Mouseover: UpdateHover cut out of NaowhForever_TopBar/UI/Bar.lua and run against stub frames.
-- The Top Bar's files as TopBar.xml lists them, read as one source.
local parts = {}
for _, path in ipairs(dofile("Tools/regression/toc_files.lua")("^NaowhForever_TopBar/.*%.lua$")) do
    local f = assert(io.open(path, "rb"))
    parts[#parts + 1] = f:read("*a"):gsub("\r\n", "\n")
    f:close()
end
local source = table.concat(parts, "\n")
local PERCENT = assert(tonumber(source:match("\n    PERCENT = (%d+),")), "PERCENT")
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local defaults = assert(source:match("mouseover = false, mouseoverAlpha = (%d+),"), "mouseoverAlpha default")
check("Faded Opacity defaults to 0, the old fully hidden fade", tonumber(defaults) == 0)
check("the slider is on its card, under Show On Mouseover",
    source:find('{ key = "mouseoverAlpha", label = "Faded Opacity", slider = ALPHA_RANGE, unit = "%", needs = "mouseover",', 1, true) ~= nil
    and source:find("\nlocal ALPHA_RANGE = ns.Shared.Style.ALPHA_RANGE\n", 1, true) ~= nil)
local alphaRange = dofile("Tools/regression/shared_style.lua").ALPHA_RANGE
check("the slider runs 0 to 100 in steps of 5", alphaRange[1] == 0 and alphaRange[2] == 100 and alphaRange[3] == 5)

local body = assert(source:match("\nlocal function UpdateHover%(%)\n(.-)\nend\n"), "UpdateHover")
local function Frame(over) return { over = over, alpha = 1,
    IsMouseOver = function(self) return self.over end,
    SetAlpha = function(self, a) self.alpha = a end } end

local function Run(settings, barOver, sysOver, unlocked)
    local bar, sys = Frame(barOver), Frame(sysOver)
    bar.sys = sys
    local chunk = assert(loadstring("local bar, unlocked, S, PERCENT = ...\n" .. body))
    chunk(bar, unlocked, { Get = function(k) return settings[k] end }, PERCENT)
    return bar.alpha, sys.alpha
end

local a, b = Run({ mouseover = false, mouseoverAlpha = 40 }, false, false)
check("off: bar and readout fully shown", a == 1 and b == 1)
a, b = Run({ mouseover = true, mouseoverAlpha = 0 }, false, false)
check("on at 0%: both invisible while the mouse is away", a == 0 and b == 0)
a, b = Run({ mouseover = true, mouseoverAlpha = 40 }, false, false)
check("on at 40%: both fade to the same opacity", a == 0.4 and b == 0.4)
a, b = Run({ mouseover = true, mouseoverAlpha = 40 }, true, false)
check("hovering the bar shows both", a == 1 and b == 1)
a, b = Run({ mouseover = true, mouseoverAlpha = 40 }, false, true)
check("hovering the readout shows both", a == 1 and b == 1)
a, b = Run({ mouseover = true, mouseoverAlpha = 40 }, false, false, true)
check("Unlock Mode shows both", a == 1 and b == 1)

print("PASS top bar mouseover: " .. checks .. " checks")
