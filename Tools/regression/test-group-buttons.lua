-- Run with Lua 5.1 from the repository root: Group Tools' on-screen Invite and Disband buttons.
-- Nothing is made while off; Invite runs the game's /invite from a secure button; the layout
-- stacks or lines up; secure changes wait for the end of a fight; Disband waits too.
local NOTHING = function() end
local frames, printed, disbanded = {}, {}, 0
local combat = false

local function Frame(kind, parent, template)
    local f = { kind = kind, parent = parent, template = template, scripts = {}, attrs = {}, events = {} }
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:find("^%u") then return NOTHING end
    end })
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:SetAttribute(k, v) self.attrs[k] = v end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(v) self.shown = v and true or false end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetPoint(...) self.point = { ... } end
    frames[#frames + 1] = f
    return f
end

local settings = { enabled = true }
local setHooks = {}
local S = { Get = function(k) return settings[k] end }
local ns = {
    QoLSettings = S,
    THEME = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end }),
    UI = { AttachMover = function(parent) return Frame("Mover", parent) end },
    Solid = function(parent) return Frame("Texture", parent) end,
    Border = function() return { SetColor = NOTHING } end,
    Font = function(parent) return Frame("FontString", parent) end,
    Print = function(m) printed[#printed + 1] = m end,
    DisbandGroup = function() disbanded = disbanded + 1 end,
    Apply = NOTHING, ShowRaidReminderAnchorConfig = NOTHING, HideRaidReminderAnchorConfig = NOTHING,
}
local env = setmetatable({
    NaowhForever = ns,
    UIParent = {},
    CreateFrame = function(kind, _, parent, template) return Frame(kind, parent, template) end,
    InCombatLockdown = function() return combat end,
    hooksecurefunc = function(t, _, fn)
        if t == S then setHooks[#setHooks + 1] = fn end
    end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile("QoL/NaowhForever_GroupButtons.lua"))
setfenv(chunk, env)
chunk()
local events, boot = frames[1], frames[2]

local function Set(k, v)
    settings[k] = v
    for _, fn in ipairs(setHooks) do fn(k) end
end

local function Bar()
    for _, f in ipairs(frames) do
        if f.invite then return f end
    end
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("off by default: nothing is made", function()
    boot.scripts.OnEvent(boot, "PLAYER_LOGIN")
    assert(Bar() == nil and #frames == 2)
end)

Case("on: Invite runs the game's /invite from a secure button, stacked over Disband", function()
    Set("groupButtons", true)
    local bar = Bar()
    assert(bar and bar.shown)
    assert(bar.invite.template == "SecureActionButtonTemplate")
    assert(bar.invite.attrs.type1 == "macro" and bar.invite.attrs.macrotext1 == "/invite")
    assert(bar.disband.template == nil, "Disband is the addon's own")
    assert(bar.w == 90 and bar.h == 52, "stacked: " .. bar.w .. "x" .. bar.h)
    assert(bar.disband.point[3] == "BOTTOMLEFT", "Disband under Invite")
end)

Case("side by side", function()
    Set("groupButtonsLayout", "row")
    local bar = Bar()
    assert(bar.w == 184 and bar.h == 24, "row: " .. bar.w .. "x" .. bar.h)
    assert(bar.disband.point[3] == "TOPRIGHT", "Disband right of Invite")
end)

Case("a change in combat waits for the fight to end", function()
    combat = true
    Set("groupButtonsLayout", "stacked")
    assert(Bar().w == 184 and events.events.PLAYER_REGEN_ENABLED, "nothing moved yet")
    combat = false
    events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
    assert(Bar().w == 90 and not events.events.PLAYER_REGEN_ENABLED, "applied after")
end)

Case("Disband waits for the end of a fight, then disbands", function()
    local bar = Bar()
    combat = true
    bar.disband.scripts.OnClick(bar.disband)
    assert(disbanded == 0 and printed[#printed]:find("fight is over"), "refused in combat")
    combat = false
    bar.disband.scripts.OnClick(bar.disband)
    assert(disbanded == 1)
end)

Case("turning it off hides it", function()
    Set("groupButtons", false)
    assert(Bar().shown == false)
end)

print(("test-group-buttons: %d cases passed"):format(count))
