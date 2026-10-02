-- Run with Lua 5.1 from the repository root: Reload UI buttons run the game's own /reload.
-- The game blocks an addon's reload (ADDON_ACTION_BLOCKED on Reload), so no file calls
-- ReloadUI; a Reload UI button gets a secure /reload macro button laid over it on hover, on
-- UIParent by screen position (never anchored to the addon's windows), out of combat only.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

-- A frame that records what the code under test does to it. Methods it does not record
-- (capitalised, like the game's) do nothing; any other field is simply unset.
local Frame = {}
local function noop() end
Frame.__index = function(_, key)
    return Frame[key] or (key:match("^%u") and noop or nil)
end
function Frame.new(template)
    return setmetatable({ template = template, attributes = {}, scripts = {}, hooks = {},
        events = {}, shown = true }, Frame)
end
function Frame:SetAttribute(k, v) self.attributes[k] = v end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn) self.hooks[name] = fn end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:ClearAllPoints() self.point = nil end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:GetEffectiveScale() return 1 end
function Frame:CreateTexture() return Frame.new() end
function Frame:CreateFontString() return Frame.new() end

local combat, printed, made = false, {}, {}
local UIParent = Frame.new()
local env = {
    CreateFrame = function(_, _, _, template)
        local f = Frame.new(template)
        made[#made + 1] = f
        return f
    end,
    UIParent = UIParent,
    NaowhForeverDB = { account = {}, profiles = {}, charActive = {} },
    InCombatLockdown = function() return combat end,
    print = function(msg) printed[#printed + 1] = msg end,
}
env._G = env
setmetatable(env, { __index = _G })
local core = assert(loadstring(Read("Core/NaowhForever_Core.lua"), "Core"))
setfenv(core, env)
core("NaowhForever")
local ns = env.NaowhForever

-- The button a player sees, 120 x 26 at (300, 200) on screen.
local btn = Frame.new()
function btn:GetLeft() return 300 end
function btn:GetBottom() return 200 end
function btn:GetWidth() return 120 end
function btn:GetHeight() return 26 end
ns.MakeReloadButton(btn)
ns.MakeReloadButton(btn)
check("a Reload UI button is hooked once", btn.hooks.OnEnter ~= nil)

btn.hooks.OnEnter(btn)
local cover
for _, f in ipairs(made) do
    if f.template == "SecureActionButtonTemplate" then cover = f end
end
check("hovering lays a secure button over it", cover ~= nil and cover.shown)
check("that runs the game's own /reload", cover.attributes.type == "macro"
    and cover.attributes.macrotext == "/reload")
check("placed on UIParent by position, not anchored to the window", cover.point[2] == UIParent
    and cover.point[4] == 300 and cover.point[5] == 200 and cover.w == 120 and cover.h == 26)

check("it hides as combat starts", cover.events.PLAYER_REGEN_DISABLED)
cover.scripts.OnEvent(cover, "PLAYER_REGEN_DISABLED")
check("hidden", not cover.shown)

combat = true
btn.hooks.OnEnter(btn)
check("in combat it is not laid over the button", not cover.shown)
btn._onClick()
check("and the button says to type /reload", printed[#printed]:find("Type /reload", 1, true) ~= nil)

-- No file calls the game's ReloadUI: the game would block it.
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
check("no file calls ReloadUI: " .. table.concat(calls, " | "), #calls == 0)

print(("test-reload-button: %d checks passed"):format(checks))
