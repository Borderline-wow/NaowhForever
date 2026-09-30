-- Run with Lua 5.1 from the repository root: every Reload UI the addon offers goes through
-- ns.ReloadUI, which does not try in combat (the game blocks an addon's reload there and
-- raises ADDON_ACTION_BLOCKED on Reload).
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local combat, reloads, printed = false, 0, {}
local frame = setmetatable({}, { __index = function() return function() end end })
local env = {
    CreateFrame = function() return frame end,
    NaowhForeverDB = { account = {}, profiles = {}, charActive = {} },
    InCombatLockdown = function() return combat end,
    ReloadUI = function() reloads = reloads + 1 end,
    print = function(msg) printed[#printed + 1] = msg end,
}
env._G = env
setmetatable(env, { __index = _G })
local core = assert(loadstring(Read("Core/NaowhForever_Core.lua"), "Core"))
setfenv(core, env)
core("NaowhForever")
local ns = env.NaowhForever

ns.ReloadUI()
check("out of combat it reloads", reloads == 1)
combat = true
ns.ReloadUI()
check("in combat it does not try", reloads == 1)
check("and says why", printed[#printed]:find("Can't reload in combat", 1, true) ~= nil)

-- No file calls the game's ReloadUI past it: the helper itself is the one call left.
local calls = {}
for line in io.lines("NaowhForever.toc") do
    local path = line:gsub("\r$", ""):match("^([^#%s]%S*%.lua)")
    if path and not path:find("^Libs") then
        path = path:gsub("\\", "/")
        for code in Read(path):gmatch("[^\n]+") do
            if not code:match("^%s*%-%-") and code:find("%f[%w_.]ReloadUI%f[^%w_]") then
                calls[#calls + 1] = path .. ": " .. code
            end
        end
    end
end
check("only ns.ReloadUI calls the game's ReloadUI: " .. table.concat(calls, " | "),
    #calls == 1 and calls[1]:find("^Core/NaowhForever_Core.lua:%s+ReloadUI%(%)") ~= nil)

print(("test-reload-in-combat: %d checks passed"):format(checks))
