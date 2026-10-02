-- ns.Color must produce the same |cffRRGGBB escapes the code wrote by hand before it.
-- Run with Lua 5.1 from the repository root: lua5.1 Tools/regression/test-theme-color.lua .
local root = arg[1] or "."
local file = assert(io.open(root .. "/Core/NaowhForever_Core.lua", "rb"))
local source = file:read("*a"); file:close()

local frame = setmetatable({}, { __index = function() return function() end end })
local env = { CreateFrame = function() return frame end }
env._G = env
setmetatable(env, { __index = _G })
local chunk = assert(loadstring(source, "Core"))
setfenv(chunk, env)
chunk("NaowhForever")
local ns = env.NaowhForever

local cases = 0
local function Eq(got, want)
    assert(got == want, "expected " .. tostring(want) .. ", got " .. tostring(got))
    cases = cases + 1
end

-- The values the code used as literals: accent #0091ed, muted #9a9ea6, fg #f0f1f3, and the
-- lighter accent #4db5f5.
Eq(ns.Color("accent"), "|cff0091ed")
Eq(ns.Color("muted"), "|cff9a9ea6")
Eq(ns.Color("fg"), "|cfff0f1f3")
Eq(ns.Color("accentSoft"), "|cff4db5f5")
Eq(ns.Color("accent", "Naowh"), "|cff0091edNaowh|r")
Eq(ns.Color("muted", "UNTESTED"), "|cff9a9ea6UNTESTED|r")
Eq(ns.Color("fg", ""), "|cfff0f1f3|r")
Eq(ns.Color("accentSoft", "(this quest)"), "|cff4db5f5(this quest)|r")

-- A number is text like any other, a cached key answers the same twice, and a bare {r,g,b}
-- table works without a key.
Eq(ns.Color("accent", 42), "|cff0091ed42|r")
Eq(ns.Color("accent"), ns.Color("accent"))
Eq(ns.Color({ r = 1, g = 0, b = 0 }, "x"), "|cffff0000x|r")

print("PASS ns.Color matches the accent, muted, fg and accentSoft literals (" .. cases .. " checks)")
