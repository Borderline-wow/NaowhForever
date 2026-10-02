-- HUD frames that follow the theme through ns.ThemeTint: with the default theme they paint the
-- exact literals they always did, with a preset or Custom the player's colors. The real Core is loaded, and the
-- statements that paint the TopBar pills and the Campfire plate are cut out of their real
-- files and run. Run with Lua 5.1 from the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local coreSource = Read("Core/NaowhForever_Core.lua")
local function LoadCore(account)
    local frames = {}
    local function NewFrame()
        local f = { events = {} }
        setmetatable(f, { __index = function() return function() end end })
        function f:SetScript(name, fn) self[name] = fn end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterAllEvents() self.events = {} end
        frames[#frames + 1] = f
        return f
    end
    local env = { CreateFrame = NewFrame,
        NaowhForeverDB = { account = account, profiles = {}, charActive = {} } }
    env._G = env
    setmetatable(env, { __index = _G })
    local chunk = assert(loadstring(coreSource, "Core"))
    setfenv(chunk, env)
    chunk("NaowhForever")
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.OnEvent then f.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
    end
    return env.NaowhForever
end

local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end
local function Same(got, want)
    for i = 1, #want do if got[i] ~= want[i] then return false end end
    return #got == #want
end
local function Const(source, name)
    local body = assert(source:match("\nlocal " .. name .. " = (%b{})"), name .. " is missing")
    return assert(loadstring("return " .. body))()
end
local function IsRGB(t, r, g, b) return t.r == r and t.g == g and t.b == b end
local function Run(text, env)
    local chunk = assert(loadstring(text))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    chunk()
end

local PICKS = { themePreset = "custom", themeColors = {
    bg = { r = 0.1, g = 0.2, b = 0.3 }, panel = { r = 0.4, g = 0.5, b = 0.6 },
    line = { r = 0.7, g = 0.8, b = 0.9 } } }

-- Every ThemeTint call is inside a function, so it is read when a frame is built or
-- refreshed and never at file load.
local files = { "ThreatMeter/NaowhForever_ThreatMeter.lua", "TopBar/NaowhForever_TopBar.lua",
    "AuraBuffs/NaowhForever_Campfire.lua" }
for _, path in ipairs(files) do
    local source = Read(path)
    local count = 0
    for line in source:gmatch("[^\n]+") do
        if line:find("ns.ThemeTint(", 1, true) then
            count = count + 1
            Check(line:match("^%s+%S") ~= nil, path .. ": ThemeTint is not at file scope")
        end
    end
    Check(count > 0, path .. ": uses ThemeTint")
end

-- Campfire plate.
do
    local source = Read("AuraBuffs/NaowhForever_Campfire.lua")
    local PLATE = Const(source, "PLATE")
    Check(IsRGB(PLATE, 0.14, 0.15, 0.16), "plate literal is the original")
    local stmt = assert(source:match('(local plate = ns%.ThemeTint%("panel", PLATE%)\n[^\n]*)'))
    local function Paint(account)
        local painted
        local plate = { SetColorTexture = function(_, ...) painted = { ... } end }
        Run(stmt, { ns = LoadCore(account), PLATE = PLATE, icon = { plate = plate } })
        return painted
    end
    Check(Same(Paint({}), { 0.14, 0.15, 0.16, 1 }), "plate: off is the original literal")
    Check(Same(Paint({ themeColors = PICKS.themeColors }), { 0.14, 0.15, 0.16, 1 }),
        "plate: picks saved but no Custom theme is the original literal")
    Check(Same(Paint(PICKS), { 0.4, 0.5, 0.6, 1 }), "plate: on follows Panels")
    Check(Same(Paint({ themePreset = "custom", themeColors = { bg = PICKS.themeColors.bg } }),
        { 0.14, 0.15, 0.16, 1 }), "plate: no Panels pick keeps the literal")
    Check(source:find("SetColorTexture(0, 0, 0, 1)", 1, true), "campfire ring stays black")
end

-- TopBar pills, with the player's opacity on top.
do
    local source = Read("TopBar/NaowhForever_TopBar.lua")
    local PILL_BG = Const(source, "PILL_BG")
    Check(IsRGB(PILL_BG, 0.03, 0.03, 0.04), "pill literal is the original")
    local stmt = assert(source:match(
        '(local pill = ns%.ThemeTint%("bg", PILL_BG%)\n[^\n]*ipairs%(bar%.segs%)[^\n]*end)'))
    local function Paint(account)
        local painted = {}
        local segs = {}
        for i = 1, 3 do
            segs[i] = { SetColorTexture = function(_, ...) painted[i] = { ... } end }
        end
        Run(stmt, { ns = LoadCore(account), PILL_BG = PILL_BG, bar = { segs = segs },
            S = { Get = function() return 85 end } })
        return painted
    end
    local off = Paint({})
    Check(Same(off[1], { 0.03, 0.03, 0.04, 0.85 }) and Same(off[3], { 0.03, 0.03, 0.04, 0.85 }),
        "pills: off is the original literal and the player's opacity")
    Check(Same(Paint({ themeColors = PICKS.themeColors })[2], { 0.03, 0.03, 0.04, 0.85 }),
        "pills: picks saved but no Custom theme is the original literal")
    local on = Paint(PICKS)
    Check(Same(on[1], { 0.1, 0.2, 0.3, 0.85 }) and Same(on[3], { 0.1, 0.2, 0.3, 0.85 }),
        "pills: on follows Background and keeps the opacity")
end

-- ThreatMeter: the literals, the token each surface follows, and what stays as it was.
do
    local source = Read("ThreatMeter/NaowhForever_ThreatMeter.lua")
    Check(IsRGB(Const(source, "WINDOW_BG"), 0.025, 0.04, 0.055), "window literal is the original")
    Check(IsRGB(Const(source, "WINDOW_EDGE"), 0.10, 0.19, 0.24), "border literal is the original")
    Check(IsRGB(Const(source, "HEADER_BG"), 0.04, 0.075, 0.095), "header literal is the original")
    Check(IsRGB(Const(source, "ROW_BG"), 0.065, 0.085, 0.105), "row literal is the original")
    Check(source:find('ns.Solid(frame, "BACKGROUND", ns.ThemeTint("bg", WINDOW_BG), 1)', 1, true),
        "window follows Background")
    Check(source:find('ns.Border(frame, ns.ThemeTint("line", WINDOW_EDGE))', 1, true),
        "border follows Borders & Lines")
    Check(source:find('ns.Solid(frame.header, "BACKGROUND", ns.ThemeTint("panel", HEADER_BG), 1)', 1, true),
        "header follows Panels")
    Check(source:find('local rowBg = ns.ThemeTint("panel", ROW_BG)', 1, true), "rows follow Panels")
    Check(source:find("row.bg:SetColorTexture(0.04, 0.19, 0.25, 1)", 1, true),
        "the own-row highlight keeps its tint")
end

-- The accent-tinted HUD surfaces: the shipped blue with the default theme, the accent otherwise.
local ACCENT_PRESET = { themePreset = "midnight" }
local function AccentOf(account) return LoadCore(account).THEME.accent end

do
    local source = Read("QoL/NaowhForever_GcdTracker.lua")
    local GCD_BLUE = Const(source, "GCD_BLUE")
    Check(IsRGB(GCD_BLUE, 0.01, 0.56, 0.91), "gcd literal is the original")
    local glow = assert(source:match('(local blue = ns%.ThemeTint%("accent", GCD_BLUE%)\n[^\n]*f%.glow:SetColorTexture[^\n]*)'))
    local border = assert(source:match('(local blue = ns%.ThemeTint%("accent", GCD_BLUE%)\n[^\n]*f%.border:SetColorTexture[^\n]*)'))
    local function Paint(account)
        local out = {}
        local f = { glow = { SetColorTexture = function(_, ...) out.glow = { ... } end },
            border = { SetColorTexture = function(_, ...) out.border = { ... } end } }
        local ns = LoadCore(account)
        Run(glow, { ns = ns, GCD_BLUE = GCD_BLUE, f = f })
        Run(border, { ns = ns, GCD_BLUE = GCD_BLUE, f = f })
        return out
    end
    local off = Paint({})
    Check(Same(off.glow, { 0.01, 0.56, 0.91, 0.7 }) and Same(off.border, { 0.01, 0.56, 0.91, 0.8 }),
        "gcd: the default theme is the original blue")
    local a = AccentOf(ACCENT_PRESET)
    local on = Paint(ACCENT_PRESET)
    Check(Same(on.glow, { a.r, a.g, a.b, 0.7 }) and Same(on.border, { a.r, a.g, a.b, 0.8 }),
        "gcd: a theme's accent, with the same alphas")
    Check(Same(Paint({ themePreset = "custom", themeColors = { bg = PICKS.themeColors.bg } }).glow,
        { 0.01, 0.56, 0.91, 0.7 }), "gcd: an unpicked accent keeps the blue")
end

do
    local source = Read("BiS/NaowhForever_BiS.lua")
    local BIS_GLOW = Const(source, "BIS_GLOW")
    Check(IsRGB(BIS_GLOW, 0, 0.57, 0.93), "bis glow literal is the original")
    local stmt = assert(source:match('(local glow = ns%.ThemeTint%("accent", BIS_GLOW%)\n[^\n]*PixelGlow_Start%(frame, { glow%.r, glow%.g, glow%.b, 1 }, 12, nil, nil, 2, 0, 0, nil, "NaowhBiS"%))'))
    local function Glow(account)
        local color
        Run(stmt, { ns = LoadCore(account), BIS_GLOW = BIS_GLOW, frame = {},
            LCG = { PixelGlow_Start = function(_, c) color = c end } })
        return color
    end
    Check(Same(Glow({}), { 0, 0.57, 0.93, 1 }), "bis: the default theme is the original glow")
    local a = AccentOf(ACCENT_PRESET)
    Check(Same(Glow(ACCENT_PRESET), { a.r, a.g, a.b, 1 }), "bis: a theme's accent")
end

do
    local source = Read("ThreatMeter/NaowhForever_ThreatMeter.lua")
    local block = assert(source:match('(if own then\n%s+local mark = ns%.ThemeTint%("accent", nil%).-\n        end)'))
    local function Row(account)
        local color
        Run(block, { ns = LoadCore(account), own = true,
            row = { bg = { SetColorTexture = function(_, ...) color = { ... } end } } })
        return color
    end
    Check(Same(Row({}), { 0.04, 0.19, 0.25, 1 }), "threat: the default theme keeps the own-row tint")
    local a = AccentOf(ACCENT_PRESET)
    Check(Same(Row(ACCENT_PRESET), { a.r * 0.27, a.g * 0.27, a.b * 0.27, 1 }), "threat: a theme darkens its accent")
end

do
    local source = Read("QoL/NaowhForever_XPBar.lua")
    local stmt = assert(source:match('(local shifted = ns%.ThemeTint%("accent", nil%)\n[^\n]*\n[^\n]*SetGradient[^\n]*)'))
    local function Fill(account)
        local from, to
        local function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        local FILL_FROM = CreateColor(0x00 / 255, 0x4f / 255, 0x85 / 255, 1)
        local ns = LoadCore(account)
        Run(stmt, { ns = ns, T = ns.THEME, CreateColor = CreateColor, FILL_FROM = FILL_FROM,
            bar = { fill = { SetGradient = function(_, _, a, b) from, to = a, b end } } })
        return from, to, FILL_FROM
    end
    local from, to, shipped = Fill({})
    Check(from == shipped and to.r == 0 and to.g == 0x91 / 255 and to.b == 0xed / 255,
        "xpbar: the default theme is the original gradient")
    local a = AccentOf(ACCENT_PRESET)
    from, to = Fill(ACCENT_PRESET)
    Check(from.r == a.r * 0.55 and from.b == a.b * 0.55 and to.r == a.r and to.g == a.g,
        "xpbar: a theme's accent, darkened at the low end")
end

print("PASS theme HUD: " .. cases .. " checks")
