-- Offline behavior checks for the Flight Timer's Request Stop fade, its display, and Flight Games
-- (what opens on a flight, and the one-time move from the old toggles), and its look; these do
-- not emulate client taint or rendering.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end
local function fixture(settings)
    local s = { now = 0, frames = {}, tickers = {}, taxi = false, combat = false, settings = settings or {},
        offers = {}, dismissed = {} }
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
        function f:SetText(v) self.text = v end
        function f:GetStringWidth() return 40 end
        function f:SetAlpha(a) self.alpha = a end
        function f:SetFont(path, size, flags) self.font = path .. " " .. size .. " " .. flags end
        function f:SetTexture(path) self.texture = path end
        function f:SetTextColor(r) self.red = r end
        s.frames[#s.frames + 1] = f
        return f
    end
    local leave = frame()
    leave.alpha, leave.mouse, leave.mouseCalls = 1, true, 0
    function leave:SetAlpha(a) self.alpha = a end
    function leave:EnableMouse(v) self.mouse = v; self.mouseCalls = self.mouseCalls + 1 end
    s.leave = leave
    local defaults = { enabled = true, flightTimer = true, flightEarlyLanding = false, flightTimerScale = 1,
        flightTimerAlpha = 1, flightGame = 'aim', flightTimerFont = '', flightTimerOutline = 'NONE', flightTimerTexture = '' }
    local S = { Get = function(k) if s.settings[k] ~= nil then return s.settings[k] end return defaults[k] end,
        Set = function(k, v) s.settings[k] = v end, DB = function() return s.settings end,
        Raw = function(k) return s.settings[k] end }
    local ns = { QoLSettings = S, THEME = { accent = {}, bg = {}, muted = { r = 0.5 }, accentSoft = {}, fg = { r = 1 },
            line = {} },
        Font = function() return frame() end, Solid = function() return frame() end,
        Border = function() return { _frame = frame() } end,
        Button = function(_, text)
            local b = frame()
            b.name, b.label = text, frame()
            b._bg, b._border = frame(), { _frame = frame() }
            return b
        end,
        AccentBorder = function(f) return f end, PixelInset = function() end,
        Tooltip = function() end, AccountSettings = function() return {} end, FLIGHT_ROUTES = {},
        Apply = function() end, ShowRaidReminderAnchorConfig = function() end, HideRaidReminderAnchorConfig = function() end,
        UI = { AttachMover = function() return frame() end, FontPath = function(name) return 'font:' .. name end,
            TexturePath = function(name, own) if name == '' then return own end return 'lsm:' .. name end },
        Shared = { Style = { ROUND = 'round', BORDER_RGB = { r = 0, g = 0, b = 0 }, PLACE_DOT = ' . ' },
            Parts = { Arrow = function() return frame() end, HudText = function(fs, shadow) fs.shadow = shadow end } },
        QuizOffer = function(reason) s.offers[#s.offers + 1] = 'quiz:' .. reason end,
        AimOffer = function(reason) s.offers[#s.offers + 1] = 'aim:' .. reason end,
        QuizDismiss = function(reason) s.dismissed.quiz = reason end,
        AimDismiss = function(reason) s.dismissed.aim = reason end }
    local env = { _G = { NaowhForever = ns }, UIParent = frame(), CreateFrame = frame,
        MainMenuBarVehicleLeaveButton = leave,
        GetTime = function() return s.now end, UnitOnTaxi = function() return s.taxi end,
        InCombatLockdown = function() return s.combat end,
        TakeTaxiNode = function() end, TaxiRequestEarlyLanding = function() s.landRequests = (s.landRequests or 0) + 1 end,
        CreateColor = function() return {} end, UnitFactionGroup = function() return 'Alliance' end,
        GetFileIDFromPath = function() return 1 end,
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
    function s.find(pred)
        for _, f in ipairs(s.frames) do if pred(f) then return f end end
    end
    function s.text(v) return s.find(function(f) return rawget(f, 'text') == v end) end
    function s.button(label) return s.find(function(f) return rawget(f, 'name') == label end) end
    function s.tick()
        local bar = s.find(function(f) return f.scripts.OnUpdate end)
        bar.scripts.OnUpdate(bar)
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
do
    local s = fixture({ flightEarlyLanding = true })
    s.ns.ShowRaidReminderAnchorConfig()
    local key, name = s.text('Next'), s.text('Thorium Point')
    check('the sample flight names its next stop', key and key.shown and name and name.shown)
    check('with the time to it', s.text('0:50') and s.text('2:30'))
    check('the sample has no Land or Games button', not s.button('Land').shown and not s.button('Games').shown)
    s.now = 60
    s.tick()
    check('a passed stop hands over to the next one', s.text('Morgan\'s Vigil').shown and s.text('0:35'))
    check('the time left counts down', s.text('1:30'))
    s.now = 160
    s.tick()
    check('the looping sample starts its stops again', s.text('Thorium Point') and s.text('0:40'))
end
do
    local s = fixture({ flightEarlyLanding = true })
    s.board()
    local land, games = s.button('Land'), s.button('Games')
    check('a flight shows the Land and Games buttons', land.shown and games.shown)
    land._onClick()
    check('Land asks to land early', s.landRequests == 1)
    check('an unknown route is just in flight', s.text('In flight'))
    s.now = 5
    s.tick()
    check('an unknown route counts up', s.text('0:05'))
    check('with no next stop', not s.text('Next') or not s.text('Next').shown)
end
do
    local s = fixture()
    s.board()
    check('by default a flight offers the Aim Trainer, once', #s.offers == 1 and s.offers[1] == 'aim:flight')
    s.land()
    check('landing closes what a flight opened', s.dismissed.quiz == 'flight' and s.dismissed.aim == 'flight')
end
do
    local s = fixture({ flightGame = 'quiz' })
    s.board()
    check('Quiz: a flight offers only the Quiz', #s.offers == 1 and s.offers[1] == 'quiz:flight')
end
do
    local s = fixture({ flightGame = 'none' })
    s.board()
    check('Nothing: a flight offers no game', #s.offers == 0)
    check('Nothing: the Games button still shows', s.button('Games').shown)
end
do
    local s = fixture({ flightGame = 'bogus' })
    s.board()
    check('an unknown choice falls back to the Aim Trainer', #s.offers == 1 and s.offers[1] == 'aim:flight')
end
do
    local s = fixture({ quizFlight = false, aimAutoFlight = true })
    check('Quiz While Flying off and Open on Flights on become Aim Trainer', s.settings.flightGame == 'aim'
        and s.settings.flightGameMigrated == true and s.settings.quizFlight == nil and s.settings.aimAutoFlight == nil)
    s.board()
    check('and a flight offers the Aim Trainer', #s.offers == 1 and s.offers[1] == 'aim:flight')
end
do
    local s = fixture({ quizFlight = false, aimAutoFlight = false })
    check('Quiz While Flying off alone becomes Nothing', s.settings.flightGame == 'none')
end
do
    local s = fixture({ quizFlight = true, aimAutoFlight = true })
    check('Quiz While Flying on keeps the default', s.settings.flightGame == nil
        and s.settings.quizFlight == nil and s.settings.aimAutoFlight == nil)
end
do
    local s = fixture()
    check('a fresh profile is only marked as migrated', s.settings.flightGame == nil
        and s.settings.flightGameMigrated == true)
end
do
    local s = fixture({ flightGameMigrated = true, quizFlight = false })
    check('the migration runs once', s.settings.flightGame == nil and s.settings.quizFlight == false)
    s.ns.Apply()
    check('and not again on Apply', s.settings.flightGame == nil)
end
do
    local s = fixture({ flightGame = 'quiz', quizFlight = false })
    check('a choice already made is kept', s.settings.flightGame == 'quiz' and s.settings.quizFlight == nil)
end
do
    local function read(path)
        local f = assert(io.open(path, 'rb'))
        local text = f:read('*a')
        f:close()
        return text
    end
    local qol, quiz = read('QoL/NaowhForever_QoL.lua'), read('QoL/NaowhForever_Quiz.lua')
    check('Flight Games defaults to the Aim Trainer', qol:find('flightGame = "aim"', 1, true) ~= nil)
    check('the old flight toggles are gone', not qol:find('quizFlight', 1, true) and not qol:find('aimAutoFlight', 1, true)
        and not quiz:find('quizFlight', 1, true))
end
do -- the look: today's card by default, then Font, Outline, Bar Texture and Background Opacity
    local s = fixture({ flightEarlyLanding = true })
    s.board()
    local bar = s.find(function(f) return f.scripts.OnUpdate end)
    local land = s.button('Land')
    check('default: the Addon Font, no outline or shadow', bar.time.font == 'font: 20 ' and bar.time.shadow == false
        and bar.to.font == 'font: 14 ')
    check('default: the flat fill and a solid card', bar.fill.texture == 'Interface\\Buttons\\WHITE8X8'
        and bar.bg.alpha == 1 and land._bg.alpha == 1 and bar.from.red == 0.5)
    s.set('flightTimerFont', 'Arial')
    s.set('flightTimerOutline', 'OUTLINE')
    s.set('flightTimerTexture', 'Smooth')
    check('Font, Outline and Bar Texture apply', bar.time.font == 'font:Arial 20 OUTLINE'
        and bar.nextKey.font == 'font:Arial 12 OUTLINE' and bar.fill.texture == 'lsm:Smooth')
    s.set('flightTimerAlpha', 0.3)
    check('Background Opacity fades the card and its buttons', bar.bg.alpha == 0.3 and bar.border._frame.alpha == 0.3
        and land._bg.alpha == 0.3 and land._border._frame.alpha == 0.3)
    check('an outline needs no shadow; muted labels go bright', bar.time.shadow == false and bar.from.red == 1)
    s.set('flightTimerOutline', 'NONE')
    check('plain text over a faded card gets a shadow', bar.time.shadow == 'none' and bar.time.font == 'font:Arial 20 ')
    s.set('flightTimerAlpha', 1)
    check('and loses it on a solid card', bar.time.shadow == false and bar.from.red == 0.5)
    s.set('flightTimerOutline', '')
    check('Shadow keeps one on a solid card', bar.time.shadow == 'card')
end

print(checks .. ' flight request-stop checks passed')
