-- Run with Lua 5.1 from the repository root: the XP Ticker's card. The real Core, Shared style,
-- parts and window parts and the ticker's own file are loaded against stubs, and the ticker and
-- its settings preview are checked: the card (theme background, black border), the rate with its
-- unit on one line, the empty session ("--", "no XP yet", no Ding), the footer (Ding and
-- the session time on one line, the level percent at its right), the level in progress as it
-- runs (marked + when not timed from its ding) over the completed levels, the icon
-- buttons beside the rate shown on hover, the card's tooltip, the Background choice (the card, a
-- soft fade, or none: the shared HUD backdrop, the stronger shadow and no outline unless asked for,
-- the old on/off setting saved as Card or Soft), the font settings (Font, Font Size and Outline, the
-- old Outlined Text toggle saved as Outline or Shadow), the card's standard groups, the preview's states and edits,
-- theme colors, the saved place, and no garbage or text work on an unchanged update. Then its colors with meaning: the level progress
-- line with rested XP ahead of it, the rate in the accent only while earning, its trend arrow,
-- Ding turning soft blue near a level, and paused muting the rate and the line. And level history
-- kept per character by GUID: three characters sharing a first name, the old name-keyed entry
-- taken over once by the one whose level fits, kept in place, and a GUID not known yet at login.
-- Then played time through Shared.Played (the row, the muted /played request, the levels reached
-- saved from it) and Compare Characters (the gap to each character on the account, the mark
-- against the fastest, the tooltip's list, and no garbage per update).
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local NOTHING = function() end
local Frame
local created = {}
local textsSet = 0
local METHODS = {
    SetScript = function(f, script, fn) f.scripts[script] = fn end,
    HookScript = function(f, script, fn) f.hooks[script] = fn end,
    RegisterEvent = function(f, event) f.events[event] = true end,
    UnregisterEvent = function(f, event) f.events[event] = nil end,
    IsEventRegistered = function(f, event) return f.events[event] == true end,
    UnregisterAllEvents = function(f) for event in pairs(f.events) do f.events[event] = nil end end,
    SetSize = function(f, w, h) f.w, f.h = w, h end,
    SetWidth = function(f, w) f.w = w end,
    SetHeight = function(f, h) f.h = h end,
    GetWidth = function(f) return rawget(f, "w") or 100 end,
    GetHeight = function(f) return rawget(f, "h") or 40 end,
    SetPoint = function(f, p1, p2, p3, p4, p5) f.p1, f.p2, f.p3, f.p4, f.p5 = p1, p2, p3, p4, p5 end,
    SetFont = function(f, path, size, flags) f.font, f.size, f.flags = path, size, flags end,
    SetTextColor = function(f, r, g, b) f.r, f.g, f.b = r, g, b end,
    SetColorTexture = function(f, r, g, b, a) f.r, f.g, f.b, f.a = r, g, b, a end,
    SetTexture = function(f, tex) f.tex = tex end,
    SetTexCoord = function(f, l, r, t, b) f.l, f.r2, f.t, f.b2 = l, r, t, b end,
    SetVertexColor = function(f, r, g, b, a) f.vr, f.vg, f.vb, f.va = r, g, b, a end,
    SetValue = function(f, v) f.value = v end,
    SetStatusBarColor = function(f, r, g, b, a) f.sr, f.sg, f.sb, f.sa = r, g, b, a end,
    GetStatusBarTexture = function(f)
        local tex = rawget(f, "barTex")
        if not tex then tex = Frame(f, nil, "Texture"); f.barTex = tex end
        return tex
    end,
    SetGradient = function(f, dir, from, to) f.dir, f.from, f.to = dir, from, to end,
    SetShadowColor = function(f, r, g, b, a) f.shadow = { r, g, b, a } end,
    SetShadowOffset = function(f, x, y) f.offset = { x, y } end,
    SetText = function(f, text) f.text = text; textsSet = textsSet + 1 end,
    GetText = function(f) return rawget(f, "text") or "" end,
    GetStringWidth = function(f) return #(rawget(f, "text") or "") * (rawget(f, "size") or 12) * 0.5 end,
    GetStringHeight = function(f) return rawget(f, "size") or 12 end,
    Show = function(f) f.shown = true end,
    Hide = function(f) f.shown = false end,
    SetShown = function(f, shown) f.shown = shown and true or false end,
    IsShown = function(f) return f.shown ~= false end,
    EnableMouse = function(f, on) f.mouse = on end,
    EnableMouseWheel = function(f, on) f.wheel = on end,
    IsMouseOver = function(f) return f.over == true end,
    GetFrameLevel = function() return 1 end,
    GetEffectiveScale = function() return 1 end,
    GetParent = function(f) return f.parent end,
    GetObjectType = function(f) return f.kind or "Frame" end,
    CreateFontString = function(f) return Frame(f, nil, "FontString") end,
    CreateTexture = function(f) return Frame(f, nil, "Texture") end,
}
local META = { __index = function(_, key)
    if METHODS[key] then return METHODS[key] end
    if type(key) == "string" and key:find("^%u") then return NOTHING end
end }
function Frame(parent, name, kind)
    local f = setmetatable({ scripts = {}, hooks = {}, events = {}, parent = parent, name = name, kind = kind }, META)
    created[#created + 1] = f
    return f
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end

local now = 1000
local xp, xpMax, rested = 500, 1000, nil
local MAIN = "Player-4613-006EB819"
local guid, level = MAIN, 20
local tick
local requests, timers = 0, {}
local chat = {}
local function RunTimers()
    local list = {}
    for i = 1, #timers do list[i] = timers[i] end
    for i = #timers, 1, -1 do timers[i] = nil end
    for i = 1, #list do list[i]() end
end
local menu, menuOpen
local tip = { lines = {} }
local function TipRecord(kind)
    return function(_, left, right) tip.lines[#tip.lines + 1] = { kind = kind, left = left, right = right } end
end
local GameTooltip = {
    SetOwner = function(_, owner)
        tip.owner, tip.shown = owner, false
        for i = #tip.lines, 1, -1 do tip.lines[i] = nil end
    end,
    SetText = TipRecord("title"), AddLine = TipRecord("line"), AddDoubleLine = TipRecord("double"),
    Show = function() tip.shown = true end,
    Hide = function() tip.shown, tip.owner = false, nil end,
    IsOwned = function(_, owner) return tip.owner == owner end,
}
local function TipRight(left)
    for _, line in ipairs(tip.lines) do
        if line.left == left then return line.right or "" end
    end
end

local function Boot(account, settings, who)
    for i = #created, 1, -1 do created[i] = nil end
    if who then guid, level = who.guid, who.level else guid, level = MAIN, 20 end
    now, tick, menu, menuOpen = 1000, nil, nil, false
    tip.owner, tip.shown = nil, false
    xp, xpMax, rested = 500, 1000, nil
    requests = 0
    for i = #timers, 1, -1 do timers[i] = nil end
    chat[1], chat[2] = Frame(), Frame()
    chat[1].events.TIME_PLAYED_MSG = true
    local env = {
        CreateFrame = function(_, name, parent) return Frame(parent, name) end,
        NaowhForeverDB = { account = account or {}, profiles = {}, charActive = {} },
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
        UIParent = Frame(),
        PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end },
        GetTime = function() return now end,
        UnitLevel = function() return level end,
        UnitGUID = function() return guid end,
        UnitXP = function() return xp end,
        UnitXPMax = function() return xpMax end,
        GetXPExhaustion = function() return rested end,
        CreateColor = function(r, g, b, a)
            return { r = r, g = g, b = b, a = a, SetRGBA = function(c, r2, g2, b2, a2) c.r, c.g, c.b, c.a = r2, g2, b2, a2 end }
        end,
        UnitName = function() return "Die" end,
        GetRealmName = function() return "Realm" end,
        GetMaxLevelForPlayerExpansion = function() return 60 end,
        IsXPUserDisabled = function() return false end,
        IsResting = function() return false end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end,
            NewTicker = function(_, fn) tick = fn; return { Cancel = NOTHING } end },
        RequestTimePlayed = function() requests = requests + 1 end,
        NUM_CHAT_WINDOWS = 2, ChatFrame1 = chat[1], ChatFrame2 = chat[2],
        UnitClass = function() return "Warrior", "WARRIOR", 1 end,
        RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } },
        MenuUtil = { CreateContextMenu = function(owner, gen) menu = { owner = owner, gen = gen } end },
        Menu = { GetManager = function() return { IsAnyMenuOpen = function() return menuOpen end } end },
        GameTooltip = GameTooltip,
        hooksecurefunc = function(t, k, fn)
            local old = t[k]
            t[k] = function(...) local r = old(...); fn(...); return r end
        end,
    }
    env._G = env
    setmetatable(env, { __index = _G })
    local core = assert(loadstring(Read("Core/NaowhForever_Core.lua"), "Core"))
    setfenv(core, env)
    core("NaowhForever")
    local ns = env.NaowhForever
    ns.ApplyThemeColors()
    Load({ "Shared/Shared.lua", "Shared/Style.lua", "Shared/Parts.lua", "Shared/Window.lua", "Shared/Played.lua" }, env)

    local defaults = { enabled = true, xpTicker = true, xpTickerLevel = true, xpTickerElapsed = true,
        xpTickerHideResting = false, xpTickerFont = "", xpTickerFontSize = 24, xpTickerOutline = "",
        xpTickerSplits = true, xpTickerHistoryCount = 10, xpTickerBackground = "card",
        xpTickerPlayed = true, xpTickerPace = false, xpTickerSplitPlayed = true }
    local db = settings or {}
    ns.QoLSettings = {
        Get = function(k) if db[k] == nil then return defaults[k] end return db[k] end,
        Set = function(k, v) db[k] = v end,
        DB = function() return db end,
    }
    ns.UI = { FontPath = function(name) return name ~= "" and "font:" .. name or "naowh" end,
        AttachMover = function(parent) return Frame(parent) end }
    ns.Apply, ns.ResetXPBarSession = NOTHING, NOTHING
    ns.ShowRaidReminderAnchorConfig, ns.HideRaidReminderAnchorConfig = NOTHING, NOTHING
    Load({ "Shared/Settings/Settings.lua" }, env)
    local first = #created + 1
    Load({ "QoL/NaowhForever_XPTicker.lua" }, env)
    local card = ns.Shared.Settings.pages["QoL/XP"].cards.xpTicker

    for i = first, #created do
        local f = created[i]
        if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
    end
    local ticker
    for _, f in ipairs(created) do
        if f.name == "NaowhForeverXPTicker" then ticker = f end
    end
    local events, played
    for _, f in ipairs(created) do
        if f.events.PLAYER_XP_UPDATE then events = f end
        if f.events.TIME_PLAYED_MSG and f ~= chat[1] and f ~= chat[2] then played = f end
    end
    return { ns = ns, S = ns.QoLSettings, ticker = ticker, card = card, T = ns.THEME, events = events,
        account = env.NaowhForeverDB.account, db = db, played = played }
end

local St
local function Shadowed(fs)
    return fs.offset[1] == St.HUD_SHADOW_X and fs.offset[2] == St.HUD_SHADOW_Y
        and fs.shadow[1] == St.HUD_SHADOW_RGB.r and fs.shadow[4] == St.HUD_SHADOW_ALPHA
end
local function Plain(fs) return fs.flags == "" and Shadowed(fs) end
local function Outlined(fs) return fs.flags == "OUTLINE" and fs.offset[1] == 0 and fs.shadow[4] == 0 end
local function SoftShadow(fs)
    return fs.flags == "" and fs.offset[1] == St.HUD_SHADOW_X and fs.offset[2] == St.HUD_SHADOW_Y
        and fs.shadow[1] == St.HUD_SHADOW_RGB.r and fs.shadow[4] == St.HUD_SOFT_SHADOW_ALPHA
end
local function BareShadow(fs)
    return fs.flags == "" and fs.offset[1] == St.HUD_BARE_SHADOW_X and fs.offset[2] == St.HUD_BARE_SHADOW_Y
        and fs.shadow[1] == St.HUD_SHADOW_RGB.r and fs.shadow[4] == St.HUD_BARE_SHADOW_ALPHA
end
local function Shown(region) return region.shown ~= false end
local function CardShown(f) return Shown(f.backdrop.fill) and Shown(f.backdrop.border._frame) end
local function CardHidden(f) return f.backdrop.fill.shown == false and f.backdrop.border._frame.shown == false end
local function SoftShown(f, on)
    local soft = f.backdrop.soft
    if not soft then return not on end
    for _, tex in ipairs(soft) do
        if Shown(tex) ~= on then return false end
    end
    return true
end
local function Is(fs, c) return fs.r == c.r and fs.g == c.g and fs.b == c.b end
local function All(t, test)
    for _, fs in ipairs(t.texts) do
        if not test(fs) then return false end
    end
    return true
end

do
    local s = Boot()
    local ns, t, T = s.ns, s.ticker, s.T
    St = ns.Shared.Style
    check("the ticker is built on login", t and t.shown)
    local fill = t.backdrop and t.backdrop.fill
    check("the card is the shared HUD backdrop", fill and t.backdrop.SetMode and t.backdrop.mode == "card")
    check("the card is the theme's background", Shown(fill) and Is(fill, T.bg))
    check("at the card alpha the Flight Timer uses", fill.a == St.HUD_CARD_ALPHA and St.HUD_CARD_ALPHA == 0.85
        and Read("QoL/NaowhForever_Flight.lua"):find("CARD_ALPHA = 380, 10, 6, St.HUD_CARD_ALPHA", 1, true))
    check("with the black border", Shown(t.backdrop.border._frame))
    check("no soft fade made until it is picked", t.backdrop.soft == nil)
    check("the progress line's track on the card", Shown(t.line.track))

    check("no XP yet: the rate a muted --", t.rate.text == "--" and Is(t.rate, T.muted) and t.rate.size == 24)
    check("the rate at the card's top left", t.rate.p1 == "TOPLEFT" and t.rate.p2 == 8 and t.rate.p3 == -8)
    check("no XP yet: no XP yet in place of the unit", t.unit.text == "no XP yet" and Is(t.unit, T.muted))
    check("the unit beside the rate, on its baseline", t.unit.p1 == "BOTTOMLEFT" and t.unit.p2 == t.rate
        and t.unit.p3 == "BOTTOMRIGHT" and t.unit.p4 == 4 and math.abs(t.unit.p5 - (24 - 12) * 0.2) < 1e-9)
    check("the unit at the row size", t.unit.size == 12)
    check("no Ding without a rate", not t.ding.on and t.ding.label.shown == false and t.dot.shown == false)
    check("the session time alone at the footer's left", t.time.on and t.time.value.text == "0:00"
        and t.time.value.p1 == "TOPLEFT" and t.time.value.p4 == 8)
    check("the level percent at the footer's right", t.percent.text == "50%" and Is(t.percent, T.muted)
        and t.percent.p1 == "TOPRIGHT" and t.percent.p4 == -8 and t.percent.p5 == t.time.value.p5)
    check("no history rows without completed levels", not t.history[1].on)
    check("the level in progress over the footer", t.current.on and t.current.label.text == "Level 20"
        and t.current.label.p5 > t.percent.p5)
    check("timed from part way: marked +", t.current.value.text == "0:00+")
    check("all muted", Is(t.current.label, T.muted) and Is(t.current.value, T.muted))
    check("a short card: the rate, played, this level, the footer", t.h == 8 + 24 + 6 + 12 + 3 + 12 + 6 + 12 + 8)

    xp = 700
    s.events.scripts.OnEvent(s.events, "PLAYER_XP_UPDATE")
    check("XP in: the rate in the accent", t.rate.text == "12.0k" and Is(t.rate, T.accent))
    check("XP in: the unit", t.unit.text == "xp/hr" and Is(t.unit, T.muted))
    check("Ding and the time share the footer", t.ding.on and t.ding.label.text == "Ding"
        and t.ding.value.text == "1m" and t.dot.shown and t.time.value.text == "0:00")
    check("Ding's label muted on the left", Is(t.ding.label, T.muted) and t.ding.label.p1 == "TOPLEFT"
        and t.ding.label.p4 == 8)
    check("its value after it, then a dot, then the time", t.ding.value.p1 == "LEFT" and t.ding.value.p2 == t.ding.label
        and t.dot.p2 == t.ding.value and t.time.value.p1 == "LEFT" and t.time.value.p2 == t.dot)
    check("the dot muted", Is(t.dot, T.muted) and t.dot.text == ns.Shared.Style.PLACE_DOT)
    check("the time in the text color", Is(t.time.value, T.fg))
    check("the percent follows XP", t.percent.text == "70%")
    check("footer rows at the row size", t.ding.label.size == 12 and t.time.value.size == 12 and t.percent.size == 12)

    check("the text has no outline, the soft shadow", All(t, Plain))
    check("no hand-written color codes", not Read("QoL/NaowhForever_XPTicker.lua"):find("|cff", 1, true))

    local c = t.controls
    check("the buttons beside the rate, centred on it", c.parent == t and c.p1 == "RIGHT" and c.p2 == t
        and c.p3 == "TOPRIGHT" and c.p4 == -6 and c.p5 == -(8 + 24 / 2))
    check("two icon buttons: pause and reset", t.toggle.parent == c and t.reset.parent == c
        and t.toggle.icon.tex == St.PAUSE and t.reset.icon.tex == St.RESET)
    check("with tooltips", t.toggle.tip == "Pause" and t.toggle.hint and t.reset.tip == "Reset" and t.reset.hint)
    check("house icons", St.PLAY:find("Media\\play$") and St.PAUSE:find("Media\\pause$")
        and St.RESET:find("Media\\reset$"))
    for _, file in ipairs({ "play", "pause", "reset" }) do
        local f = io.open("Media/" .. file .. ".tga", "rb")
        check(file .. " icon exists", f)
        f:close()
    end
    check("hidden until hovered", c.shown == false)
    check("room for the buttons right of the rate", t.w >= 8 + t.rate.text:len() * 12 + 4 + c.w + 6)
    check("the buttons inside the card", 8 + 12 - c.h / 2 >= 0 and t.h >= 8 + 12 + c.h / 2)
    t.scripts.OnEnter(t)
    check("shown on hover", c.shown)
    check("no tooltip with Compare Characters off: the card already shows its numbers", not tip.shown)
    t.over = true
    t.scripts.OnLeave(t)
    check("still shown moving onto a button", c.shown)
    t.over = false
    t.toggle.hooks.OnLeave(t.toggle)
    check("hidden once the mouse leaves the card", c.shown == false and not tip.shown)
    menuOpen = true
    t.scripts.OnEnter(t)
    check("no tooltip while a menu is open", not tip.shown)
    t.scripts.OnLeave(t)
    menuOpen = false

    t.toggle.scripts.OnClick(t.toggle)
    check("the pause button pauses", t.unit.text == "paused" and t.toggle.icon.tex == St.PLAY and t.toggle.tip == "Start")
    t.toggle.scripts.OnClick(t.toggle)
    check("and starts again", t.unit.text == "xp/hr" and t.toggle.icon.tex == St.PAUSE)
    ns.XPTickerCommand("pause")
    check("/naowh xp pause still works", t.unit.text == "paused")
    ns.XPTickerCommand("start")
    check("/naowh xp start still works", t.unit.text == "xp/hr")
    now = now + 125
    tick()
    check("the clock runs", t.time.value.text == "2:05")
    t.reset.scripts.OnClick(t.reset)
    check("the reset button starts the session again", t.time.value.text == "0:00")
    now = now + 30
    tick()
    ns.XPTickerCommand("reset")
    check("/naowh xp reset still works", t.time.value.text == "0:00")

    s.S.Set("xpTickerFont", "Expressway")
    s.S.Set("xpTickerFontSize", 12)
    check("a picked font and size apply", t.rate.font == "font:Expressway" and t.rate.size == 12)
    check("the unit and rows follow", t.unit.font == "font:Expressway" and t.unit.size == 9
        and t.time.value.size == 9 and t.percent.font == "font:Expressway")
    local small = t.w
    s.S.Set("xpTickerFontSize", 32)
    check("the card is sized from the font size", t.w > small and t.rate.size == 32 and t.time.value.size == 16)
    check("still no outline", All(t, Plain))

    s.S.Set("xpTickerOutline", "OUTLINE")
    check("Outline outlines the card's text", All(t, Outlined) and CardShown(t))
    s.S.Set("xpTickerOutline", "THICKOUTLINE")
    check("Thick Outline too", t.rate.flags == "THICKOUTLINE" and t.time.value.flags == "THICKOUTLINE"
        and t.rate.shadow[4] == 0)
    s.S.Set("xpTickerOutline", "")
    check("Shadow brings the shadow back", All(t, Plain))

    s.S.Set("xpTickerBackground", "soft")
    local soft = t.backdrop.soft
    check("Soft: no card and no border", CardHidden(t))
    check("Soft: nine pieces of the round shade", soft and #soft == 9 and SoftShown(t, true))
    local corners, spans, flat = 0, 0, 0
    for _, tex in ipairs(soft) do
        check("Soft: the shade texture, in the theme's background", tex.tex == St.SOFT_SHADE
            and tex.vr == T.bg.r and tex.vg == T.bg.g and tex.vb == T.bg.b and tex.va == St.HUD_SOFT_ALPHA)
        if tex.l ~= tex.r2 and tex.t ~= tex.b2 then corners = corners + 1
        elseif tex.l == tex.r2 and tex.t == tex.b2 then flat = flat + 1
        else spans = spans + 1 end
    end
    check("Soft: four round corners, four fading sides, one middle", corners == 4 and spans == 4 and flat == 1)
    check("Soft: the corners reach out past the card", soft[1].p1 == "TOPLEFT" and soft[1].p2 == t
        and soft[1].p4 == -(St.HUD_SOFT_FADE - St.HUD_SOFT_INSET) and soft[1].w == St.HUD_SOFT_FADE)
    check("Soft: a low alpha, clear at its edge", St.HUD_SOFT_ALPHA > 0 and St.HUD_SOFT_ALPHA < St.HUD_CARD_ALPHA
        and St.HUD_SOFT_INSET < St.HUD_SOFT_FADE)
    check("Soft: no outline, the stronger soft shadow", All(t, SoftShadow))
    check("Soft: the progress line without its track", t.line.track.shown == false)
    s.S.Set("xpTickerOutline", "OUTLINE")
    check("Soft: Outline still outlines on request", All(t, Outlined))
    s.S.Set("xpTickerOutline", "")

    s.S.Set("xpTickerBackground", "none")
    check("None: no card", CardHidden(t))
    check("None: no fade", SoftShown(t, false) and t.backdrop.soft == soft)
    check("None: no outline, the strongest shadow", All(t, BareShadow))
    check("None: the line's fill without its track", t.line.track.shown == false and t.line.fill)
    s.S.Set("xpTickerOutline", "OUTLINE")
    check("None: Outline on request", All(t, Outlined))
    s.S.Set("xpTickerOutline", "")

    s.S.Set("xpTickerBackground", "card")
    check("Card: the card is back", CardShown(t) and SoftShown(t, false) and All(t, Plain) and Shown(t.line.track))
    s.S.Set("xpTickerBackground", "fancy")
    check("an unknown value is the card", t.backdrop.mode == "card" and CardShown(t))
    s.S.Set("xpTickerBackground", "card")

    xp = 800
    s.events.scripts.OnEvent(s.events, "PLAYER_XP_UPDATE")
    check("Ding shown again once XP comes in", t.ding.on and t.time.value.p2 == t.dot)
    s.S.Set("xpTickerLevel", false)
    check("Show Ding Time off hides it", not t.ding.on and t.ding.label.shown == false and t.dot.shown == false)
    check("the time moves to the footer's left", t.time.on and t.time.value.p1 == "TOPLEFT" and t.time.value.p4 == 8)
    s.S.Set("xpTickerElapsed", false)
    check("Show Time off leaves the percent alone", not t.time.on and t.time.value.shown == false
        and t.percent.shown ~= false)
    s.S.Set("xpTickerElapsed", true)
    s.S.Set("xpTickerLevel", true)

    local rows, labels, groups, groupOf, group = {}, {}, {}, {}, nil
    for _, r in ipairs(s.card.rows) do
        if r.key then rows[r.key] = r end
        if r.label then labels[r.label] = r end
        if r.group then
            group = r.group
            groups[#groups + 1] = group
        elseif r.key then
            groupOf[r.key] = group
        end
    end
    check("the standard groups after its own", table.concat(groups, ", ")
        == "Shown, Level History, Text, Background, Visibility")
    check("Font, Font Size and Outline under Text", groupOf.xpTickerFont == "Text"
        and groupOf.xpTickerFontSize == "Text" and groupOf.xpTickerOutline == "Text")
    check("Font Size keeps its range", rows.xpTickerFontSize.slider[1] == 8 and rows.xpTickerFontSize.slider[2] == 32)
    check("Hide While Resting under Visibility", groupOf.xpTickerHideResting == "Visibility")
    local bg, outline = rows.xpTickerBackground, rows.xpTickerOutline
    local Parts = ns.Shared.Parts
    check("Background is a choice on the card", bg and bg.choice == Parts.HUD_BACKGROUNDS and bg.label == "Background")
    check("Card, Soft and None, in that order", table.concat(bg.choice[2], ",") == "card,soft,none"
        and bg.choice[1].card == "Card" and bg.choice[1].soft == "Soft" and bg.choice[1].none == "None")
    check("Outline is the shared choice, in every mode", outline and outline.choice == Parts.HUD_OUTLINES
        and outline.label == "Outline" and outline.needs == nil)
    for _, r in ipairs({ bg, outline }) do
        check(r.label .. ": one short sentence", r.help and #r.help < 100 and not r.help:find("%. %u"))
    end
    bg.set("soft")
    check("the row sets the mode", s.S.Get("xpTickerBackground") == "soft" and bg.get() == "soft"
        and t.backdrop.mode == "soft")
    outline.set("OUTLINE")
    check("the row sets the outline", s.S.Get("xpTickerOutline") == "OUTLINE" and All(t, Outlined))
    outline.set("")
    bg.set("card")
    local qol = Read("QoL/NaowhForever_QoL.lua")
    check("Background is Card by default", qol:find('xpTickerBackground = "card"', 1, true))
    check("no outline by default", qol:find('xpTickerOutline = ""', 1, true))
    check("the Color spelling in player text", not Read("QoL/NaowhForever_XPTicker.lua"):find("[Cc]olour"))
    check("Reset XP per Hour is still on the card", labels["Reset XP per Hour"])
end

do
    local splits = { ["Die-Realm"] = { current = { level = 20, base = 0 },
        levels = { [19] = { total = 2391 }, [18] = { total = 2248 }, [17] = {} } } }
    local s = Boot({ levelSplits = splits })
    local t = s.ticker
    check("completed levels as rows, newest first", t.history[1].on and t.history[1].label.text == "Level 19"
        and t.history[2].label.text == "Level 18" and not t.history[3].on)
    check("their times on the right", t.history[1].value.text == "39:51" and t.history[1].value.p1 == "TOPRIGHT")
    check("history at the row size", t.history[1].label.size == 12 and t.history[1].label.size == t.time.value.size)
    check("between the rate and the footer", t.history[1].label.p5 < -32 and t.history[2].label.p5 > t.percent.p5)
    s.S.Set("xpTickerHistoryCount", 1)
    check("Levels Shown caps them", t.history[1].on and not t.history[2].on)

    check("the level in progress first, timed from its ding", t.current.on and t.current.label.text == "Level 20"
        and t.current.value.text == "0:00" and t.current.label.p5 > t.history[1].label.p5)
    local before = textsSet
    tick()
    tick()
    check("an unchanged update sets no text", textsSet == before)
    now = now + 1
    tick()
    check("a new second sets two texts, the clocks", textsSet == before + 2)
    now = now + 124
    tick()
    check("this level counts up", t.current.value.text == "2:05" and t.time.value.text == "2:05")
    s.ns.PauseXPTicker()
    now = now + 30
    tick()
    check("and stops while paused", t.current.value.text == "2:05")
    s.ns.StartXPTicker()
    for _ = 1, 50 do tick() end
    collectgarbage("collect")
    collectgarbage("stop")
    local mem = collectgarbage("count")
    for _ = 1, 2000 do tick() end
    local grown = collectgarbage("count") - mem
    collectgarbage("restart")
    check(("no garbage per update (%.3f KB over 2000)"):format(grown), grown < 0.05)
end

do
    local s = Boot()
    local studio, T = s.card.studio, s.T
    local keys = {}
    for _, state in ipairs(studio.states) do keys[#keys + 1] = state.key end
    check("preview states: Levelling, Starting, Paused, Resting",
        table.concat(keys, ",") == "levelling,starting,paused,resting")
    local preview = studio.new(Frame())
    local p = preview.ticker
    studio.paint(preview, "levelling")
    local pbg = p.backdrop.fill
    check("the preview draws the card", Shown(pbg) and Is(pbg, T.bg) and pbg.a == St.HUD_CARD_ALPHA)
    check("levelling: the rate and rows", p.rate.text == "48.2k" and p.unit.text == "xp/hr"
        and p.ding.value.text == "8m" and p.time.value.text == "1:12:40" and p.percent.text == "62%")
    check("levelling: sample history", p.history[1].label.text == "Level 22" and p.history[5].on)
    check("levelling: a sample level in progress", p.current.on and p.current.label.text == "Level 23"
        and p.current.value.text == "14:02")
    check("the preview's buttons do nothing", p.toggle.mouse == false and p.reset.mouse == false)
    studio.paint(preview, "starting")
    check("starting: no rate yet", p.rate.text == "--" and p.unit.text == "no XP yet" and not p.ding.on
        and p.time.value.text == "3:12")
    check("starting: a level timed from part way", p.current.value.text == "9:47+")
    studio.paint(preview, "paused")
    check("paused: the unit and the play icon", p.unit.text == "paused" and p.toggle.icon.tex == St.PLAY)
    studio.paint(preview, "resting")
    check("resting: shown while Hide While Resting is off", p.shown ~= false and preview.note.text == "")
    s.S.Set("xpTickerHideResting", true)
    studio.paint(preview, "resting")
    check("resting: hidden with a note when it is on", p.shown == false and preview.note.text ~= "")
    s.S.Set("xpTickerHideResting", false)
    studio.paint(preview, "levelling")
    check("the preview has the hint", preview.hint.text:find("Wheel", 1, true))

    p.scripts.OnMouseWheel(p, 1)
    check("the wheel makes the text bigger", s.S.Get("xpTickerFontSize") == 25)
    p.scripts.OnMouseWheel(p, -1)
    check("and smaller", s.S.Get("xpTickerFontSize") == 24)
    local dingHit
    for _, hit in ipairs(preview.hits) do
        if hit.row == p.ding then dingHit = hit end
    end
    check("a row can be clicked", dingHit and dingHit.shown and dingHit.key == "xpTickerLevel")
    dingHit.over = true
    dingHit.scripts.OnMouseUp(dingHit, "LeftButton")
    check("clicking Ding hides it", s.S.Get("xpTickerLevel") == false)
    studio.paint(preview, "levelling")
    check("and the preview drops it", not p.ding.on and dingHit.shown == false)
    p.scripts.OnMouseUp(p, "RightButton")
    check("right-click opens a menu", menu and menu.owner == p)
    local items, section = {}, nil
    local root = {
        CreateTitle = function(_, title) section = title end, CreateDivider = NOTHING,
        CreateCheckbox = function(_, label, _, set, data) items[label] = { set = set, data = data } end,
        -- Background and Outline both have a None; the outline one is filed as "Outline None".
        CreateRadio = function(_, label, picked, set, data)
            local key = section == "Outline" and items[label] and "Outline " .. label or label
            items[key] = { picked = picked, set = set, data = data }
        end,
        CreateButton = function(_, label, fn) items[label] = { fn = fn } end,
    }
    menu.gen(p, root)
    check("the menu has the backgrounds, the outlines and Reset", items.Card and items.Soft and items.None
        and items["Outline None"] and items.Shadow and items.Outline and items["Thick Outline"] and items["Reset XP per Hour"]
        and items["Show Ding Time"])
    check("the menu's Shadow picked", items.Shadow.picked(items.Shadow.data) and not items.Outline.picked(items.Outline.data))
    items.Outline.set(items.Outline.data)
    studio.paint(preview, "levelling")
    check("Outline from the menu, in the preview too", s.S.Get("xpTickerOutline") == "OUTLINE" and All(p, Outlined))
    items.Shadow.set(items.Shadow.data)
    studio.paint(preview, "levelling")
    check("the menu's Card picked", items.Card.picked(items.Card.data) and not items.Soft.picked(items.Soft.data))
    items["Show Ding Time"].set(items["Show Ding Time"].data)
    check("and turns rows back on", s.S.Get("xpTickerLevel") == true)
    items.Soft.set(items.Soft.data)
    studio.paint(preview, "levelling")
    check("Soft from the menu, in the preview too", s.S.Get("xpTickerBackground") == "soft" and CardHidden(p)
        and SoftShown(p, true) and All(p, SoftShadow) and items.Soft.picked(items.Soft.data))
    items.None.set(items.None.data)
    studio.paint(preview, "levelling")
    check("None in the preview", CardHidden(p) and SoftShown(p, false) and All(p, BareShadow)
        and p.line.track.shown == false)
    items.Card.set(items.Card.data)
    studio.paint(preview, "levelling")
    check("and the card back in the preview", CardShown(p) and SoftShown(p, false) and All(p, Plain))

    s.S.Set("xpTicker", false)
    studio.paint(preview, "levelling")
    check("no edits while it is off", not preview.editable and not preview.hint.text:find("Wheel", 1, true))
    p.scripts.OnMouseWheel(p, 1)
    check("the wheel does nothing then", s.S.Get("xpTickerFontSize") == 24)
end

do
    local s = Boot({ themePreset = "slate" })
    local ns, t, T = s.ns, s.ticker, s.T
    check("a theme preset changes the colors", ns.Color("muted") ~= "|cff9a9ea6")
    check("the card follows the theme", Is(t.backdrop.fill, T.bg) and Is(t.unit, T.muted) and Is(t.rate, T.muted)
        and Is(t.ding.label, T.muted) and Is(t.time.value, T.fg) and Is(t.percent, T.muted))
end

do
    local s = Boot(nil, { xpTickerOutline = true })
    check("a saved Outlined Text loads outlined", All(s.ticker, Outlined))
    check("and is saved as Outline", s.db.xpTickerOutline == "OUTLINE")
    s = Boot(nil, { xpTickerOutline = false })
    check("Outlined Text off is saved as Shadow", s.db.xpTickerOutline == "" and All(s.ticker, Plain))
end

do
    local s = Boot(nil, { xpTickerBackground = true })
    check("an old Background on is saved as Card", s.db.xpTickerBackground == "card"
        and s.ticker.backdrop.mode == "card" and All(s.ticker, Plain))
    s = Boot(nil, { xpTickerBackground = false })
    local t = s.ticker
    check("an old Background off is saved as Soft", s.db.xpTickerBackground == "soft" and t.backdrop.mode == "soft")
    check("with the soft shadow, no longer outlined", All(t, SoftShadow))
    s.ns.Apply()
    s.S.Set("xpTickerFontSize", 20)
    check("the migration runs once: Soft stays Soft", s.db.xpTickerBackground == "soft")
    s.S.Set("xpTickerBackground", "none")
    check("and a later pick is kept", s.db.xpTickerBackground == "none" and t.backdrop.mode == "none")
    s = Boot(nil, { xpTickerBackground = false, xpTickerOutline = true })
    check("an old off with Outlined Text keeps its outline", s.db.xpTickerBackground == "soft"
        and All(s.ticker, Outlined))
    s = Boot()
    check("nothing saved: nothing written", s.db.xpTickerBackground == nil and s.ticker.backdrop.mode == "card")
    s = Boot(nil, { xpTicker = false, xpTickerBackground = false })
    check("migrated while XP per Hour is off too, with nothing built", s.db.xpTickerBackground == "soft"
        and s.ticker == nil)
end

do
    local s = Boot(nil, { xpTickerBackground = "soft" })
    local t = s.ticker
    for _ = 1, 50 do tick() end
    collectgarbage("collect")
    collectgarbage("stop")
    local mem = collectgarbage("count")
    for _ = 1, 2000 do tick() end
    local grown = collectgarbage("count") - mem
    collectgarbage("restart")
    check(("Soft: no garbage per update (%.3f KB over 2000)"):format(grown), grown < 0.05 and t.backdrop.mode == "soft")
    s.S.Set("xpTickerBackground", "none")
    collectgarbage("collect")
    collectgarbage("stop")
    mem = collectgarbage("count")
    for _ = 1, 2000 do tick() end
    grown = collectgarbage("count") - mem
    collectgarbage("restart")
    check(("None: no garbage per update (%.3f KB over 2000)"):format(grown), grown < 0.05)
end

do
    local s = Boot()
    local t = s.ticker
    check("Level History on: the level in progress", t.current.on and t.current.value.text == "0:00+")
    s.S.Set("xpTickerSplits", false)
    check("Level History off: no level in progress", not t.current.on and t.current.label.shown == false
        and t.current.value.shown == false)
    local short = t.h
    s.S.Set("xpTickerSplits", true)
    check("and back on with it, the card a row taller", t.current.on and t.h == short + 3 + 12)
    xp, xpMax = 0, 2000
    s.events.scripts.OnEvent(s.events, "PLAYER_LEVEL_UP", 21)
    check("a ding starts the next level, timed from its start", t.current.label.text == "Level 21"
        and t.current.value.text == "0:00")
    now = now + 61
    tick()
    check("which counts up", t.current.value.text == "1:01")
    for _ = 1, 50 do tick() end
    collectgarbage("collect")
    collectgarbage("stop")
    local mem = collectgarbage("count")
    for _ = 1, 2000 do tick() end
    local grown = collectgarbage("count") - mem
    collectgarbage("restart")
    check(("the running level makes no garbage within a second (%.3f KB)"):format(grown), grown < 0.05)
end

do
    local DUDU, PRI = "Player-4613-006EB8A0", "Player-4613-006EB8B1"
    local old = { current = { level = 20, base = 600, partial = false },
        levels = { [19] = { total = 2391 }, [18] = { total = 2248 } } }
    local account = { levelSplits = { ["Die-Realm"] = old } }

    local s = Boot(account, nil, { guid = MAIN, level = 20 })
    local all = s.account.levelSplits
    local mine = all[MAIN]
    check("kept under the character's GUID", mine and mine ~= old and mine.levels ~= old.levels)
    check("the first to log in whose level fits takes over the old entry", mine.migrated == true
        and mine.levels[19].total == 2391 and mine.levels[18].total == 2248 and mine.current.level == 20)
    check("its history shows", s.ticker.history[1].label.text == "Level 19" and s.ticker.history[2].on)
    check("the old entry stays, marked taken", all["Die-Realm"] == old and old.claimedBy == MAIN
        and old.levels[19].total == 2391 and old.current.base == 600)
    xp, xpMax = 0, 2000
    s.events.scripts.OnEvent(s.events, "PLAYER_LEVEL_UP", 21)
    check("a ding writes to the GUID entry only", mine.levels[20] and old.levels[20] == nil
        and old.current.level == 20)

    s = Boot(account, nil, { guid = DUDU, level = 20 })
    local dudu = all[DUDU]
    check("a second Die starts clean, even at the same level", dudu and not dudu.migrated
        and next(dudu.levels) == nil and not s.ticker.history[1].on)
    Boot(account, nil, { guid = PRI, level = 12 })
    check("a third Die starts clean", all[PRI] and not all[PRI].migrated and next(all[PRI].levels) == nil)
    check("each its own level", all[PRI].current.level == 12 and all[DUDU].current.level == 20)

    s = Boot(account, nil, { guid = MAIN, level = 21 })
    check("logging in again keeps the entry", all[MAIN] == mine and mine.levels[19].total == 2391
        and mine.levels[20] and s.ticker.history[1].label.text == "Level 20")
    check("nothing lost: the old entry as it was", old.levels[19].total == 2391 and old.levels[18].total == 2248
        and old.claimedBy == MAIN)

    local lone = { current = { level = 30, base = 0 }, levels = { [29] = { total = 999 } } }
    s = Boot({ levelSplits = { ["Die-Realm"] = lone } }, nil, { guid = DUDU, level = 31 })
    check("an old entry at another level is left alone", not s.account.levelSplits[DUDU].migrated
        and lone.claimedBy == nil and not s.ticker.history[1].on)
    s = Boot({ levelSplits = { ["Die-Realm"] = lone } }, nil, { guid = PRI, level = 30 })
    check("and taken by the character it fits", s.account.levelSplits[PRI].migrated
        and s.ticker.history[1].label.text == "Level 29")

    s = Boot({ levelSplits = { ["Die-Realm"] = { levels = { [5] = { total = 300 } } } } }, nil, { guid = MAIN, level = 6 })
    check("an old entry with no level in progress is taken too", s.account.levelSplits[MAIN].migrated
        and s.ticker.history[1].label.text == "Level 5")

    s = Boot({}, nil, { guid = nil, level = 20 })
    local t = s.ticker
    check("no GUID at login: the card still shows", t and t.shown and t.rate.text == "--")
    check("no history kept under a name meanwhile", s.account.levelSplits == nil and not t.current.on)
    guid = MAIN
    xp = 600
    s.events.scripts.OnEvent(s.events, "PLAYER_XP_UPDATE")
    check("once the GUID is known, kept under it", s.account.levelSplits[MAIN] and t.current.on
        and t.current.label.text == "Level 20")
end

do
    local pos = { point = "TOPLEFT", relPoint = "CENTER", x = -500, y = 120 }
    local s = Boot(nil, { xpTickerPos = pos })
    local t = s.ticker
    check("the card sits at the saved place", t.p1 == "TOPLEFT" and t.p3 == "CENTER" and t.p4 == -500 and t.p5 == 120)
end

local function Same(a, b) return math.abs(a.r - b.r) < 1e-6 and math.abs(a.g - b.g) < 1e-6 and math.abs(a.b - b.b) < 1e-6 end
local function LineIn(line, c) return Same(line.fill.barTex.to, c) end
local function AheadIn(line, c) return Same({ r = line.ahead.sr, g = line.ahead.sg, b = line.ahead.sb }, c) end

do
    local s = Boot()
    local ns, t, T, ev = s.ns, s.ticker, s.T, s.events
    local line = t.line
    check("a progress line from the shared parts", line and line.SetProgress and ns.Shared.Parts.ProgressLine)
    check("along the card's bottom edge, inside the border", line.parent == t.inner and line.p1 == "BOTTOMRIGHT"
        and t.inner.parent == t)
    check("2px high", line.h == 2)
    check("it shows XP to the next level", line.fill.value == 0.5 and line.ahead.value == 0.5)
    check("the fill in the accent, a gradient into it", LineIn(line, T.accent) and line.fill.barTex.dir == "HORIZONTAL"
        and not Same(line.fill.barTex.from, T.accent))
    check("rested ahead of it in the soft accent, fainter", AheadIn(line, T.accentSoft) and line.ahead.sa < 1)

    check("the rate muted at 0", Is(t.rate, T.muted))
    check("no Ding at 0", not t.ding.on)
    xp, rested = 700, 200
    ev.scripts.OnEvent(ev, "PLAYER_XP_UPDATE")
    check("the line follows XP", line.fill.value == 0.7)
    check("and rested", math.abs(line.ahead.value - 0.9) < 1e-9)
    rested = 900
    ev.scripts.OnEvent(ev, "PLAYER_XP_UPDATE")
    check("rested stops at the end of the level", line.ahead.value == 1)
    xp = 900
    tick()
    check("the clock does not move the line", line.fill.value == 0.7)
    xp = 700

    check("the rate in the accent while earning", t.rate.text ~= "0" and Is(t.rate, T.accent))
    check("the only bright number: the rest in the text color", Is(t.time.value, T.fg))
    check("Ding under 10 minutes in the soft accent", t.ding.value.text == "1m" and Is(t.ding.value, T.accentSoft))
    xpMax = 100000
    tick()
    check("Ding further off in the text color", t.ding.value.text:find("h$") and Is(t.ding.value, T.fg))
    xpMax = 1000

    check("the unit muted while running", Is(t.unit, T.muted) and t.unit.text == "xp/hr")
    ns.PauseXPTicker()
    check("paused: the unit says so", t.unit.text == "paused")
    check("paused: the rate muted", Is(t.rate, T.muted))
    check("paused: the line muted", LineIn(line, T.muted) and AheadIn(line, T.muted))
    ns.StartXPTicker()
    check("running again: the colors are back", t.unit.text == "xp/hr" and Is(t.rate, T.accent)
        and LineIn(line, T.accent) and AheadIn(line, T.accentSoft))

    check("no trend arrow at first", t.trend.shown == false)
    now = now + 180
    tick()
    check("still none after one window", t.trend.shown == false)
    xp = 1000 - 1
    ev.scripts.OnEvent(ev, "PLAYER_XP_UPDATE")
    now = now + 180
    tick()
    check("an up arrow while the rate climbs", t.trend.shown and t.trend.tex == ns.Shared.Style.UP
        and t.trend.t == 0 and t.trend.vr == St.HAVE_RGB.r and t.trend.vg == St.HAVE_RGB.g)
    check("after the unit", t.trend.p1 == "LEFT" and t.trend.p2 == t.unit)
    now = now + 900
    tick()
    check("a down arrow while it falls", t.trend.shown and t.trend.t == 1 and t.trend.vr == St.RED_RGB.r)
    ns.PauseXPTicker()
    check("no arrow while paused", t.trend.shown == false)
    ns.StartXPTicker()
    ns.ResetXPTicker()
    check("a reset clears it", t.trend.shown == false)

    for _ = 1, 50 do tick() end
    collectgarbage("collect")
    collectgarbage("stop")
    local mem = collectgarbage("count")
    for _ = 1, 1000 do
        tick()
        ev.scripts.OnEvent(ev, "PLAYER_XP_UPDATE")
    end
    local grown = collectgarbage("count") - mem
    collectgarbage("restart")
    check(("no garbage per update or XP event (%.3f KB)"):format(grown), grown < 0.05)
    local source = Read("QoL/NaowhForever_XPTicker.lua")
    check("no hand-written colors", not source:find("SetTextColor%(%d") and not source:find("SetVertexColor%(%d"))
end

do
    local s = Boot()
    local studio, T = s.card.studio, s.T
    local preview = studio.new(Frame())
    local p = preview.ticker
    studio.paint(preview, "levelling")
    check("preview: sample progress with rested", p.line.fill.value == 0.62 and math.abs(p.line.ahead.value - 0.77) < 1e-9)
    check("preview: the rate in the accent with an up arrow", Is(p.rate, T.accent) and p.trend.shown and p.trend.t == 0)
    check("preview: Ding close, in the soft accent", p.ding.value.text == "8m" and Is(p.ding.value, T.accentSoft))
    studio.paint(preview, "paused")
    check("preview paused: paused unit, muted rate and line, no arrow", p.unit.text == "paused" and Is(p.rate, T.muted)
        and LineIn(p.line, T.muted) and p.trend.shown == false)
    studio.paint(preview, "resting")
    check("preview resting: more rested, the rate falling", math.abs(p.line.ahead.value - 0.92) < 1e-9
        and p.trend.shown and p.trend.t == 1 and Is(p.rate, T.accent))
end

local function TipSection(heading)
    local out, inside = {}, false
    for _, line in ipairs(tip.lines) do
        if inside then out[#out + 1] = line end
        if line.left and line.left:find(heading, 1, true) == 1 then inside = true end
    end
    return out, inside
end
local function Garbage(n, fn)
    for _ = 1, 50 do fn() end
    collectgarbage("collect")
    collectgarbage("stop")
    local mem = collectgarbage("count")
    for _ = 1, n do fn() end
    local grown = collectgarbage("count") - mem
    collectgarbage("restart")
    return grown
end
local function Names(lines)
    local names = {}
    for i, line in ipairs(lines) do names[i] = line.left end
    return table.concat(names, ",")
end

do
    local s = Boot()
    local t, T, pf = s.ticker, s.T, s.played
    check("Show Played Time on by default", s.S.Get("xpTickerPlayed") == true
        and Read("QoL/NaowhForever_QoL.lua"):find("xpTickerPlayed = true, xpTickerPace = false", 1, true))
    check("a Played row under the rate", t.played.on and t.played.label.text == "Played"
        and t.played.label.p5 <= -(8 + 24) and Is(t.played.label, T.muted))
    check("over the level in progress", t.current.on and t.played.label.p5 > t.current.label.p5)
    check("its value on the right", t.played.value.p1 == "TOPRIGHT" and t.played.value.p4 == -8
        and t.played.value.size == 12)
    check("-- in muted before the answer", t.played.value.text == "--" and Is(t.played.value, T.muted))
    check("one /played asked for, through the shared helper", requests == 1 and pf and pf.events.PLAYER_LEVEL_UP)
    check("the chat print muted for it", chat[1].events.TIME_PLAYED_MSG == nil and chat[2].events.TIME_PLAYED_MSG == nil)
    s.S.Set("xpTickerFontSize", 24)
    check("asked once, not on every Apply", requests == 1)

    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 100000, 600)
    check("the answer shows, with days past 24 hours", t.played.value.text == "1d 3h 46m" and Is(t.played.value, T.fg))
    RunTimers()
    check("the chat frames get the event back", chat[1].events.TIME_PLAYED_MSG == true
        and chat[2].events.TIME_PLAYED_MSG == nil)
    local mine = s.account.levelSplits[MAIN]
    check("the answer saves the time this level was reached", mine.reached[20] == 100000 - 600
        and mine.reached[1] == 0)
    check("with the name and the class", mine.name == "Die" and mine.class == "WARRIOR")
    local sets = 0
    t.played.value.SetText = function(fs, text) sets = sets + 1; fs.text = text end
    now = now + 5
    tick()
    check("past a day: no text set within the minute", t.played.value.text == "1d 3h 46m" and sets == 0)
    now = now + 55
    tick()
    check("and it ticks on from the answer", t.played.value.text == "1d 3h 47m")
    t.scripts.OnEnter(t)
    check("no tooltip while Compare Characters is off", not tip.shown)
    t.scripts.OnLeave(t)
    check("no pace mark while it is off", t.paceIcon.shown == false and t.paceText.shown == false)

    now = now + 100
    level, xp, xpMax = 21, 0, 2000
    pf.scripts.OnEvent(pf, "PLAYER_LEVEL_UP", 21)
    s.events.scripts.OnEvent(s.events, "PLAYER_LEVEL_UP", 21)
    check("a ding saves the played time it came at", mine.reached[21] == 100000 + 160 and mine.reached[20] == 99400)
    tick()
    check("the total runs on through the ding", t.played.value.text == "1d 3h 49m")
    s.S.Set("xpTickerFontSize", 23)
    check("no new /played after a ding it heard", requests == 1)

    local tall = t.h
    s.S.Set("xpTickerPlayed", false)
    check("Show Played Time off hides the row", not t.played.on and t.played.label.shown == false
        and t.played.value.shown == false and t.h == tall - t.played.label.size - 3)
    check("and stops listening for /played", pf.events.TIME_PLAYED_MSG == nil and pf.events.PLAYER_LEVEL_UP == nil)
    s.S.Set("xpTickerPlayed", true)
    check("back on: listening again, no new /played", pf.events.TIME_PLAYED_MSG and requests == 1 and t.played.on)
    now = now + 10
    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 200000, 50)
    check("a /played you type updates it, its print left alone", t.played.value.text == "2d 7h 33m"
        and chat[1].events.TIME_PLAYED_MSG == true and #timers == 0)
    check("and overwrites the level reached", mine.reached[21] == 200000 - 50)

    local cardRows = {}
    for _, r in ipairs(s.card.rows) do
        if r.key then cardRows[r.key] = r end
    end
    local played, pace = cardRows.xpTickerPlayed, cardRows.xpTickerPace
    check("Show Played Time on the card", played and played.toggle and played.label == "Show Played Time"
        and played.help == "Your total played time on this character, from level 1.")
    check("Compare Characters on the card", pace and pace.toggle and pace.label == "Compare Characters"
        and pace.help == "Shows if you're ahead of or behind your other characters, and colors past levels by it.")
    for _, r in ipairs({ played, pace }) do
        check(r.label .. ": one short sentence", #r.help < 100 and not r.help:find("%. %u"))
    end
    check("the card's help mentions played time", s.card.help:find("played time", 1, true))
    check("the summary names it", s.card.summary(s.S):find("played time", 1, true))
    s.S.Set("xpTickerPace", true)
    check("and the comparison", s.card.summary(s.S):find("against your characters", 1, true))
    s.S.Set("xpTickerSplits", false)
    s.S.Set("xpTickerPlayed", false)
    s.S.Set("xpTickerPace", false)
    check("nothing extra: rate and time to level", s.card.summary(s.S) == "Rate and time to level")
end

do
    local s = Boot(nil, { xpTicker = false })
    check("XP per Hour off: no /played asked for", requests == 0 and s.played == nil)
    s = Boot(nil, { xpTickerPlayed = false })
    check("Played and Compare off: no /played, nothing listening", requests == 0 and s.played == nil
        and not s.ticker.played.on and chat[1].events.TIME_PLAYED_MSG == true)
    s = Boot(nil, { xpTickerPlayed = false, xpTickerPace = true })
    check("Compare alone still asks for /played", requests == 1 and s.played)
    s = Boot()
    level = 60
    s.S.Set("xpTickerFontSize", 25)
    check("at max level: the card hides and stops listening", s.ticker.shown == false
        and s.played.events.TIME_PLAYED_MSG == nil)
end

do
    local ALPHA, BRAVO, CHARLIE = "Player-4613-0000000A", "Player-4614-0000000B", "Player-4613-0000000C"
    local splits = {
        [MAIN] = { levels = {}, reached = { [1] = 0, [20] = 1 } },
        [ALPHA] = { name = "Alpha", class = "MAGE", reached = { [1] = 0, [20] = 54000, [21] = 56560 } },
        [BRAVO] = { name = "Bravo", class = "PRIEST", reached = { [1] = 0, [20] = 55000, [21] = 57960 } },
        [CHARLIE] = { name = "Charlie", class = "ROGUE", reached = { [1] = 0, [20] = 55300 } },
        ["Player-4613-0000000D"] = { name = "Delta", class = "MAGE", reached = { [1] = 0, [30] = 90000 } },
        ["Player-4613-0000000E"] = { name = "Echo", reached = "junk" },
        ["Player-4613-0000000F"] = { name = "Foxtrot", levels = {} },
        ["Die-Realm"] = { name = "Old", reached = { [20] = 1, [21] = 2 }, levels = {} },
    }
    local s = Boot({ levelSplits = splits })
    local t, T, pf = s.ticker, s.T, s.played
    check("Compare Characters off by default", s.S.Get("xpTickerPace") == false)
    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 56000, 1000)
    tick()
    check("off: no mark", t.paceIcon.shown == false and t.paceText.shown == false)
    s.S.Set("xpTickerPace", true)
    check("on: a mark against the fastest, Alpha, 12m behind", t.paceIcon.shown and t.paceText.shown
        and t.paceText.text == "12m")
    check("the shared arrow turned down, in red", t.paceIcon.tex == St.UP and t.paceIcon.t == 1
        and t.paceIcon.vr == St.RED_RGB.r and Is(t.paceText, St.RED_RGB))
    check("after the Played label", t.paceIcon.p1 == "LEFT" and t.paceIcon.p2 == t.played.label
        and t.paceText.p2 == t.paceIcon)
    check("the card wide enough for it", t.w >= 8 * 2 + t.played.label.text:len() * 6 + t.paceText.text:len() * 6)
    check("the old name-keyed entry never counts", t.paceText.text == "12m")

    t.scripts.OnEnter(t)
    local lines, found = TipSection("Your characters at level 20 (50%)")
    check("tooltip: the heading with your progress", found)
    check("tooltip: only your characters, not what the card shows", tip.lines[1].left == "XP per Hour"
        and TipRight("Session") == nil and TipRight("Rate") == nil and TipRight("Played") == nil)
    check("tooltip: fastest first, You in its place, the rest skipped", Names(lines) == "Alpha,You,Charlie,Bravo")
    local alpha, you, charlie, bravo = lines[1], lines[2], lines[3], lines[4]
    check("their played time at your point, and how far behind you are",
        alpha.right == "15:21:20" .. St.PLACE_DOT .. s.ns.Color(St.RED_RGB, "12m behind"))
    check("or ahead", bravo.right == "15:41:20" .. St.PLACE_DOT .. s.ns.Color(St.HAVE_RGB, "8m ahead"))
    check("one not past this level yet: compared at level 20", charlie.right
        == "15:21:40 at level 20" .. St.PLACE_DOT .. s.ns.Color(St.HAVE_RGB, "5m ahead"))
    check("You with your own time", you.right == "15:33:20")
    t.scripts.OnLeave(t)

    local recorded = {}
    local add = GameTooltip.AddDoubleLine
    GameTooltip.AddDoubleLine = function(_, left, right, r, g, b)
        recorded[left] = { r = r, g = g, b = b }
        add(_, left, right)
    end
    t.scripts.OnEnter(t)
    check("names in their class color", recorded.Alpha.r == 0.25 and recorded.Alpha.b == 0.92)
    check("You in the accent", recorded.You.r == T.accent.r and recorded.You.g == T.accent.g)
    check("a class with no color in the text color", recorded.Bravo.r == T.fg.r)
    t.scripts.OnLeave(t)
    GameTooltip.AddDoubleLine = add

    now = now + 60
    tick()
    check("the gap grows as you take longer", t.paceText.text == "13m")
    splits[ALPHA] = nil
    tick()
    check("ahead of everyone: the arrow up, in green", t.paceText.text == "5m" and t.paceIcon.t == 0
        and t.paceIcon.vr == St.HAVE_RGB.r and Is(t.paceText, St.HAVE_RGB))

    local before = textsSet
    local grown = Garbage(2000, tick)
    check(("Compare on: no garbage per update (%.3f KB over 2000)"):format(grown), grown < 0.05)
    check("and no text set while nothing changed", textsSet == before)

    s.S.Set("xpTickerPlayed", false)
    check("no mark without the Played row", t.paceIcon.shown == false and t.paceText.shown == false)
    t.scripts.OnEnter(t)
    check("the tooltip still compares", select(2, TipSection("Your characters at level 20")))
    t.scripts.OnLeave(t)
end

do
    local s = Boot({ levelSplits = { [MAIN] = { levels = {} } } }, { xpTickerPace = true })
    local t, pf = s.ticker, s.played
    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 5000, 100)
    tick()
    check("under a day: h:mm:ss", t.played.value.text == "1:23:20")
    now = now + 1
    tick()
    check("ticking each second", t.played.value.text == "1:23:21")
    check("no one to compare with: no mark", t.paceIcon.shown == false)
    t.scripts.OnEnter(t)
    local last = tip.lines[#tip.lines]
    check("and a muted line saying so", last.kind == "line"
        and last.left == "None of your other characters has reached level 20 yet.")
    t.scripts.OnLeave(t)
end

do
    local splits = { [MAIN] = { levels = {} } }
    for k = -6, 6 do
        if k ~= 0 then
            splits[("Player-4613-%08d"):format(k + 100)] = { name = ("Char%02d"):format(k + 7), class = "MAGE",
                reached = { [20] = 56000 + k * 60 - 500, [21] = 56000 + k * 60 + 500 } }
        end
    end
    local s = Boot({ levelSplits = splits }, { xpTickerPace = true })
    local t, pf = s.ticker, s.played
    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 56000, 1000)
    t.scripts.OnEnter(t)
    check("twelve characters: eight lines, the closest around you",
        Names(TipSection("Your characters at level 20")) == "Char03,Char04,Char05,Char06,You,Char08,Char09,Char10")
    t.scripts.OnLeave(t)
    check("the fastest marked: 6m behind Char01", t.paceText.text == "6m" and t.paceIcon.t == 1)
end

do
    local s = Boot(nil, { xpTickerPace = true })
    local studio, T = s.card.studio, s.T
    local preview = studio.new(Frame())
    local p = preview.ticker
    studio.paint(preview, "levelling")
    check("preview: a sample played time", p.played.on and p.played.value.text == "1d 4h 12m")
    check("preview: a sample pace mark, ahead", p.paceIcon.shown and p.paceText.text == "12m" and p.paceIcon.t == 0
        and Is(p.paceText, St.HAVE_RGB))
    p.scripts.OnEnter(p)
    check("preview tooltip: sample characters",
        Names(TipSection("Your characters at level 23 (62%)")) == "You,Thornwick,Maelis,Brakka")
    p.scripts.OnLeave(p)
    local playedHit
    for _, hit in ipairs(preview.hits) do
        if hit.row == p.played then playedHit = hit end
    end
    check("the Played row can be clicked", playedHit and playedHit.shown and playedHit.key == "xpTickerPlayed")
    playedHit.over = true
    playedHit.scripts.OnMouseUp(playedHit, "LeftButton")
    check("clicking it hides it", s.S.Get("xpTickerPlayed") == false)
    studio.paint(preview, "levelling")
    check("and the preview drops it, with its mark", not p.played.on and p.paceIcon.shown == false
        and playedHit.shown == false)
    p.scripts.OnMouseUp(p, "RightButton")
    local items = {}
    local root = {
        CreateTitle = NOTHING, CreateDivider = NOTHING, CreateRadio = NOTHING, CreateButton = NOTHING,
        CreateCheckbox = function(_, label, _, set, data) items[label] = { set = set, data = data } end,
    }
    menu.gen(p, root)
    check("the menu has Show Played Time and Compare Characters", items["Show Played Time"]
        and items["Compare Characters"])
    items["Show Played Time"].set(items["Show Played Time"].data)
    items["Compare Characters"].set(items["Compare Characters"].data)
    studio.paint(preview, "levelling")
    check("from the menu: Played back, Compare off", p.played.on and p.paceIcon.shown == false
        and s.S.Get("xpTickerPace") == false)
    p.scripts.OnEnter(p)
    check("preview: no tooltip with Compare off", not tip.shown)
    p.scripts.OnLeave(p)
    studio.paint(preview, "starting")
    check("preview starting: played shown too", p.played.value.text == "1d 4h 12m" and Is(p.played.value, T.fg))
end

do
    local ALPHA, BRAVO = "Player-4613-0000000A", "Player-4614-0000000B"
    local splits = {
        [MAIN] = { current = { level = 20, base = 0 },
            levels = { [19] = { total = 2000 }, [18] = { total = 1500 }, [17] = { total = 1000 }, [16] = { total = 900 } },
            reached = { [1] = 0, [18] = 60000, [19] = 61500, [20] = 90000 } },
        [ALPHA] = { name = "Alpha", class = "MAGE", reached = { [18] = 10000, [19] = 11400 },
            levels = { [19] = { total = 2500 } } },
        [BRAVO] = { name = "Bravo", class = "PRIEST", levels = { [19] = { total = 2000 }, [17] = { total = 1200 } } },
        ["Die-Realm"] = { levels = { [16] = { total = 1 } } },
    }
    local s = Boot({ levelSplits = splits })
    local t, T, h = s.ticker, s.T, s.ticker.history
    check("history rows, newest first", h[1].label.text == "Level 19" and h[4].label.text == "Level 16")
    check("Compare off: the level times in the normal color", Is(h[1].value, T.fg) and Is(h[2].value, T.fg)
        and Is(h[3].value, T.fg) and Is(h[4].value, T.fg))
    s.S.Set("xpTickerPace", true)
    check("as fast as the fastest: green", Is(h[1].value, St.HAVE_RGB))
    check("slower than one (their ding to ding): red", Is(h[2].value, St.RED_RGB))
    check("faster than their split: green", Is(h[3].value, St.HAVE_RGB))
    check("no one else has it, the old name entry skipped: normal", Is(h[4].value, T.fg))
    check("the labels stay muted", Is(h[1].label, T.muted) and Is(h[2].label, T.muted))
    splits[BRAVO].levels[17].total = 100
    tick()
    check("not worked out again every second", Is(h[3].value, St.HAVE_RGB))
    s.S.Set("xpTickerFontSize", 24)
    check("but on a setting change", Is(h[3].value, St.RED_RGB))
    splits[BRAVO].levels[17].total = 1200
    s.events.scripts.OnEvent(s.events, "PLAYER_LEVEL_UP", 20)
    check("and on a ding", Is(h[3].value, St.HAVE_RGB))

    check("Show Played at Ding on by default", s.S.Get("xpTickerSplitPlayed") == true
        and Read("QoL/NaowhForever_QoL.lua"):find("xpTickerSplitPlayed = true", 1, true))
    check("the played time at each ding, muted", h[1].played.text == "1d 1h 0m" and h[2].played.text == "17:05:00"
        and h[3].played.text == "16:40:00" and Is(h[1].played, T.muted) and h[1].played.shown)
    check("-- where it was not known yet", h[4].played.text == "--")
    check("the second column right-aligned at the card's edge", h[1].played.p1 == "TOPRIGHT" and h[1].played.p4 == -8
        and h[4].played.p4 == -8 and h[1].played.p5 == h[1].value.p5)
    local offset = -8 - (8 * 6 + 16)
    check("the level times lined up left of it, at the widest", h[1].value.p4 == offset and h[2].value.p4 == offset
        and h[4].value.p4 == offset and h[1].value.p1 == "TOPRIGHT")
    check("the level in progress lined up with them, no second column", t.current.value.p4 == offset
        and t.current.played == nil)
    check("the card wide enough for both", t.w >= 2 * 8 + h[1].label.text:len() * 6 + 16 + 4 * 6 + 16 + 8 * 6)
    s.S.Set("xpTickerSplitPlayed", false)
    check("off: the second column hidden, the times back at the edge", h[1].played.shown == false
        and h[4].played.shown == false and h[1].value.p4 == -8 and t.current.value.p4 == -8)
    s.S.Set("xpTickerSplitPlayed", true)

    local cardRows = {}
    for _, r in ipairs(s.card.rows) do
        if r.key then cardRows[r.key] = r end
    end
    local at = cardRows.xpTickerSplitPlayed
    check("Show Played at Ding on the card, under Level History", at and at.toggle and at.needs == "xpTickerSplits"
        and at.label == "Show Played at Ding" and #at.help < 100 and not at.help:find("%. %u"))
    check("Compare's help, still one sentence", #cardRows.xpTickerPace.help < 100
        and not cardRows.xpTickerPace.help:find("%. %u"))

    local grown = Garbage(2000, tick)
    check(("history colors and columns: no garbage per update (%.3f KB)"):format(grown), grown < 0.05)
end

do
    local s = Boot()
    local t, pf = s.ticker, s.played
    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 86398, 100)
    local wide = t.w
    now = now + 10
    pf.scripts.OnEvent(pf, "TIME_PLAYED_MSG", 50, 10)
    check("a shorter value does not shrink the card", t.played.value.text == "0:50" and t.w == wide)
    s.S.Set("xpTickerPace", true)
    local drop = math.floor(12 * 0.1 + 0.5)
    check("the pace arrow dropped level with the letters, its text back up", t.paceIcon.p5 == -drop
        and t.paceText.p5 == drop and drop == 1)
end

do
    local s = Boot(nil, { xpTickerPace = true })
    local studio, T = s.card.studio, s.T
    local preview = studio.new(Frame())
    local p = preview.ticker
    studio.paint(preview, "levelling")
    local h = p.history
    check("preview: green and red past levels", Is(h[1].value, St.HAVE_RGB) and Is(h[2].value, St.RED_RGB)
        and Is(h[4].value, St.RED_RGB) and Is(h[5].value, St.HAVE_RGB))
    check("preview: the played column", h[1].played.text == "1d 3h 58m" and h[5].played.text == "1d 0h 53m"
        and h[1].played.shown)
    s.S.Set("xpTickerPace", false)
    studio.paint(preview, "levelling")
    check("preview without Compare: no colors", Is(h[1].value, T.fg) and Is(h[2].value, T.fg))
    s.S.Set("xpTickerSplitPlayed", false)
    studio.paint(preview, "levelling")
    check("preview without Show Played at Ding: no column", h[1].played.shown == false)
    p.scripts.OnMouseUp(p, "RightButton")
    local items = {}
    menu.gen(p, { CreateTitle = NOTHING, CreateDivider = NOTHING, CreateRadio = NOTHING, CreateButton = NOTHING,
        CreateCheckbox = function(_, label, _, set, data) items[label] = { set = set, data = data } end })
    check("the menu has Show Played at Ding", items["Show Played at Ding"])
    items["Show Played at Ding"].set(items["Show Played at Ding"].data)
    check("and turns it back on", s.S.Get("xpTickerSplitPlayed") == true)
end

do
    local bar = Read("QoL/NaowhForever_XPBar.lua")
    check("the XP Bar asks through the shared helper", bar:find('Played.Want("xpBar")', 1, true)
        and bar:find("Played.Total()", 1, true) and not bar:find("RequestTimePlayed", 1, true)
        and not bar:find("TIME_PLAYED_MSG", 1, true))
end

print(("PASS xp ticker: %d checks"):format(checks))
