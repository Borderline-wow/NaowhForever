-- Run with Lua 5.1 from the repository root: which settings card opens by itself (Settings.IsOpen).
-- Every card starts folded, a page's only card and a first card with a live preview too, unless the
-- card says open = true (Damage Meter, Glimmer and Top Bar). A card someone opened or folded stays as
-- they left it.
local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local ns = { THEME = {}, L = function(text) return text end, Color = function(_, text) return text end,
    Shared = { Style = dofile("Tools/regression/shared_style.lua") }, UI = {} }
local env = setmetatable({ _G = { NaowhForever = ns } }, { __index = _G })
local chunk = assert(loadfile("Shared/Settings/Settings.lua"))
setfenv(chunk, env)
chunk()

local Settings = ns.Shared.Settings
local store = { Get = function() end, Set = function() end }
local studio = { height = 10, states = {}, new = function() end, paint = function() end }
local function Row(key) return { key = key, label = key, toggle = true } end

local preview = Settings.Page("Test/Preview", store):Card({ id = "a", name = "A", order = 1, studio = studio, rows = { Row("a") } })
Settings.Page("Test/Preview", store):Card({ id = "b", name = "B", order = 2, rows = { Row("b") } })
Check(not Settings.IsOpen(preview), "a first card with a live preview starts folded")

local only = Settings.Page("Test/Only", store):Card({ id = "a", name = "A", rows = { Row("a") } })
Check(not Settings.IsOpen(only), "and so does a page's only card")

local first = Settings.Page("Test/Open", store):Card({ id = "a", name = "A", order = 1, studio = studio, open = true,
    rows = { Row("a") } })
local second = Settings.Page("Test/Open", store):Card({ id = "b", name = "B", order = 2, rows = { Row("b") } })
Check(Settings.IsOpen(first), "a card that says open opens by itself")
Check(not Settings.IsOpen(second), "and the rest of its page stays folded")

Settings.SetOpen(first, false)
Check(not Settings.IsOpen(first), "once folded it stays folded")
Settings.SetOpen(second, true)
Check(Settings.IsOpen(second), "and a card someone opened stays open")

local declared = {}
for _, file in ipairs({ "NaowhForever_QoL/Combat/DamageMeterSkin.lua", "NaowhForever_QoL/Glimmer/UI/SettingsPage.lua",
    "NaowhForever_TopBar/UI/SettingsPage.lua", "NaowhForever_QoL/Cursor/Crosshair.lua" }) do
    local handle = assert(io.open(file, "rb"))
    local text = handle:read("*a")
    handle:close()
    for id, spec in text:gmatch('id = "([%w]+)", name = [^\n]-(open = true)') do declared[id] = spec end
end
Check(declared.damageMeterSkin and declared.look and declared.topBar, "Damage Meter, Glimmer and Top Bar open by themselves")
Check(not declared.crosshair, "the Crosshair does not")

print(("test-card-collapsed: %d checks passed"):format(checks))
