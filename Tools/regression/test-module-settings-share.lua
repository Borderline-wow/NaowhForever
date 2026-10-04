-- Run with Lua 5.1 from the repository root: every module's settings travel in a profile
-- string (ns.ExportModuleSettings / ns.ImportModuleSettings in Core/NaowhForever_Widgets.lua):
-- set values and positions go out and come back; lists, unknown keys, wrong types and
-- unknown modules do not.
local f = assert(io.open("Core/NaowhForever_Widgets.lua", "rb"))
local src = f:read("*a"):gsub("\r\n", "\n")
f:close()

local first = assert(src:find("local moduleDefaults = {}", 1, true))
local last = assert(src:find("    local function Row(cfg, k, on)", first, true))
local code = src:sub(first, last - 1) .. "    return S\nend\n"

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local root = {}
local ns = { SettingsRoot = function() return root end }
local env = setmetatable({ ns = ns, UI = {} }, { __index = _G })
local chunk = assert(loadstring(code))
setfenv(chunk, env)
chunk()
local UI = env.UI

local S = UI.ModuleSettings("topBar", {
    enabled = false, clockSize = 20, fill = { r = 1, g = 0, b = 0 }, layout = { left = { "friends" } },
    sets = {},
})
local Q = UI.ModuleSettings("qol", { mouseRing = false })
UI.ModuleSettings("qol", { xpBar = true })

S.Set("enabled", true)
S.Set("clockSize", 26)
S.Set("fill", { r = 0, g = 1, b = 0 })
S.Set("layout", { left = { "guild" }, right = { "hearth" } })
S.Set("sets", { { name = "Mine" } })
S.Set("topBarPos", { point = "TOP", relPoint = "TOP", x = 0, y = -4 })
S.Set("scratch", "kept here only")
Q.Set("xpBar", false)

local out = ns.ExportModuleSettings(root)
check("set values go out", out.topBar.enabled == true and out.topBar.clockSize == 26)
check("colours and layouts go out", out.topBar.fill.g == 1 and out.topBar.layout.right[1] == "hearth")
check("Unlock Mode positions go out", out.topBar.topBarPos.y == -4)
check("lists a module keeps stay home", out.topBar.sets == nil)
check("keys with no default stay home", out.topBar.scratch == nil)
check("a second store under one key shares it", out.qol.xpBar == false)
check("the export is a copy", out.topBar.fill ~= root.topBar.fill)

local other = {}
ns.ImportModuleSettings(other, out)
check("an import lands every value", other.topBar.clockSize == 26 and other.topBar.fill.g == 1
    and other.topBar.layout.left[1] == "guild" and other.qol.xpBar == false)
check("an import lands positions", other.topBar.topBarPos.point == "TOP")

local bad = {}
ns.ImportModuleSettings(bad, {
    topBar = { clockSize = "huge", enabled = 1, fill = "red", sets = { {} }, junk = true,
        evilPos = function() end },
    nobody = { x = 1 },
})
check("wrong types are refused", bad.topBar.clockSize == nil and bad.topBar.enabled == nil and bad.topBar.fill == nil)
check("lists and unknown keys are refused", bad.topBar.sets == nil and bad.topBar.junk == nil
    and bad.topBar.evilPos == nil)
check("unknown modules are refused", bad.nobody == nil)
check("nothing to share is nil", ns.ExportModuleSettings({}) == nil)

print(("test-module-settings-share: %d checks passed"):format(checks))
