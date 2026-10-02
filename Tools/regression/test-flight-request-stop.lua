-- Offline behavior checks; these do not emulate client taint or rendering.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end
local function fixture(settings)
    local s = { now = 0, frames = {}, tickers = {}, taxi = false, combat = false, settings = settings or {} }
    local any = setmetatable({}, { __index = function(t) return function() return t end end })
    local function frame()
        local f = { events = {}, scripts = {}, shown = false }
        setmetatable(f, { __index = function() return function() return any end end })
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(k) self.events[k] = true end
        function f:UnregisterEvent(k) self.events[k] = nil end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:SetShown(v) self.shown = v and true or false end
        function f:IsShown() return self.shown end
        function f:GetScale() return 1 end
        function f:GetFrameLevel() return 1 end
        function f:CreateTexture() return frame() end
        s.frames[#s.frames + 1] = f
        return f
    end
    local leave = frame()
    leave.alpha, leave.mouse, leave.mouseCalls = 1, true, 0
    function leave:SetAlpha(a) self.alpha = a end
    function leave:EnableMouse(v) self.mouse = v; self.mouseCalls = self.mouseCalls + 1 end
    s.leave = leave
    local defaults = { enabled = true, flightTimer = true, flightEarlyLanding = false, flightTimerScale = 1 }
    local S = { Get = function(k) if s.settings[k] ~= nil then return s.settings[k] end return defaults[k] end,
        Set = function(k, v) s.settings[k] = v end }
    local ns = { QoLSettings = S, THEME = { accent = {}, bg = {}, muted = {}, accentSoft = {} },
        Font = function() return frame() end, Solid = function() return frame() end, Border = function() end,
        Tooltip = function() end, AccountSettings = function() return {} end, FLIGHT_ROUTES = {},
        Apply = function() end, ShowRaidReminderAnchorConfig = function() end, HideRaidReminderAnchorConfig = function() end,
        UI = { AttachMover = function() return frame() end } }
    local env = { _G = { NaowhForever = ns }, UIParent = frame(), CreateFrame = frame,
        MainMenuBarVehicleLeaveButton = leave,
        GetTime = function() return s.now end, UnitOnTaxi = function() return s.taxi end,
        InCombatLockdown = function() return s.combat end,
        TakeTaxiNode = function() end, TaxiRequestEarlyLanding = function() end,
        C_Timer = { NewTicker = function(_, fn) local t = { fn = fn }; function t:Cancel() self.cancelled = true end
            s.tickers[#s.tickers + 1] = t; return t end },
    }
    env.hooksecurefunc = function(t, k, fn)
        if type(t) == 'string' then t, k, fn = env, t, k end
        local old = t[k]; t[k] = function(...) old(...); fn(...) end
    end
    setmetatable(env, { __index = _G })
    local chunk = assert(loadfile('QoL/NaowhForever_Flight.lua')); setfenv(chunk, env); chunk()
    function s.fire(event)
        local all = {}; for i, f in ipairs(s.frames) do all[i] = f end
        for _, f in ipairs(all) do if f.events[event] then f.scripts.OnEvent(f, event) end end
    end
    s.ns = ns
    function s.set(k, v) S.Set(k, v) end
    function s.board() s.taxi = true; s.fire('PLAYER_ENTERING_WORLD') end
    function s.land()
        s.taxi = false
        for _, t in ipairs(s.tickers) do if not t.cancelled then t.fn() end end
    end
    s.fire('PLAYER_LOGIN'); s.fire('PLAYER_ENTERING_WORLD')
    return s
end

do
    local s = fixture()
    check('login leaves the button alone', s.leave.alpha == 1 and s.leave.mouseCalls == 0)
    s.board()
    check('without Land Early the button stays', s.leave.alpha == 1 and s.leave.mouse)
    s.land()
    check('landing without Land Early touches nothing', s.leave.mouseCalls == 0)
end
do
    local s = fixture({ flightEarlyLanding = true })
    check('no flight, no fade', s.leave.alpha == 1)
    s.board()
    check('flying with Land Early fades the button', s.leave.alpha == 0 and not s.leave.mouse)
    s.land()
    check('landing restores the button', s.leave.alpha == 1 and s.leave.mouse)
end
do
    local s = fixture({ flightEarlyLanding = true })
    s.board()
    s.set('flightEarlyLanding', false)
    check('turning Land Early off mid-flight restores', s.leave.alpha == 1 and s.leave.mouse)
    s.set('flightEarlyLanding', true)
    check('turning it back on fades again', s.leave.alpha == 0)
    s.set('flightTimer', false)
    check('turning the timer off restores', s.leave.alpha == 1 and s.leave.mouse)
end
do
    local s = fixture({ flightEarlyLanding = true })
    s.board()
    s.combat = true
    s.land()
    check('a combat landing leaves the protected button alone', s.leave.alpha == 0 and not s.leave.mouse)
    s.combat = false
    s.fire('PLAYER_REGEN_ENABLED')
    check('combat end restores the button', s.leave.alpha == 1 and s.leave.mouse)
    s.fire('PLAYER_REGEN_ENABLED')
    check('the combat-end listener is one-shot', s.leave.mouseCalls == 2)
end
do
    local s = fixture({ flightEarlyLanding = true })
    s.ns.ShowRaidReminderAnchorConfig()
    check('the Unlock Mode sample flight does not fade', s.leave.alpha == 1 and s.leave.mouseCalls == 0)
    s.ns.HideRaidReminderAnchorConfig()
    check('leaving Unlock Mode touches nothing', s.leave.mouseCalls == 0)
end
print(checks .. ' flight request-stop checks passed')
