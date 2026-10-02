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
    "AuraBuffs/NaowhForever_Campfire.lua", "QoL/NaowhForever_LootFeed.lua" }
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

-- The TopBar's clock and tooltips: the greys and whites they always were, or the player's
-- Secondary Text and Text when the theme changed those.
do
    local source = Read("TopBar/NaowhForever_TopBar.lua")
    local toneSource = assert(source:match("(local shades = {}\nlocal function Tone%(key, v%).-\nend)"))
    local function ToneFor(account)
        local chunk = assert(loadstring(toneSource .. "\nreturn Tone"))
        setfenv(chunk, setmetatable({ ns = LoadCore(account) }, { __index = _G }))
        return chunk()
    end
    local function Rgb(...) return { ... } end
    local ns = LoadCore(ACCENT_PRESET)
    local Tone = ToneFor({})
    Check(Same(Rgb(Tone("fg", 1)), { 1, 1, 1 }), "topbar: white is white with the default theme")
    Check(Same(Rgb(Tone("muted", 0.7)), { 0.7, 0.7, 0.7 }) and Same(Rgb(Tone("muted", 0.5)), { 0.5, 0.5, 0.5 })
        and Same(Rgb(Tone("muted", 0.6)), { 0.6, 0.6, 0.6 }), "topbar: the three greys are unchanged with the default theme")
    Tone = ToneFor(ACCENT_PRESET)
    Check(Same(Rgb(Tone("fg", 1)), { ns.THEME.fg.r, ns.THEME.fg.g, ns.THEME.fg.b }), "topbar: a theme's Text replaces the white")
    Check(Same(Rgb(Tone("muted", 0.7)), { ns.THEME.muted.r, ns.THEME.muted.g, ns.THEME.muted.b })
        and Same(Rgb(Tone("muted", 0.5)), { ns.THEME.muted.r, ns.THEME.muted.g, ns.THEME.muted.b }),
        "topbar: a theme's Secondary Text replaces every grey")
    Tone = ToneFor({ themePreset = "custom", themeColors = { bg = { r = 1, g = 0, b = 0 } } })
    Check(Same(Rgb(Tone("fg", 1)), { 1, 1, 1 }) and Same(Rgb(Tone("muted", 0.7)), { 0.7, 0.7, 0.7 }),
        "topbar: a theme that left Text and Secondary Text alone keeps white and grey")

    local greyLine = assert(source:match('(local grey = ns%.ThemeTint%("muted", nil%) and [^\n]*)'))
    local function Grey(account)
        local chunk = assert(loadstring(greyLine .. "\nreturn grey"))
        local core = LoadCore(account)
        setfenv(chunk, setmetatable({ ns = core }, { __index = _G }))
        return chunk(), core
    end
    Check(Grey({}) == "|cff808080", "topbar: the AFK and DND tags keep their grey with the default theme")
    local tag, core = Grey(ACCENT_PRESET)
    Check(tag == core.Color("muted"), "topbar: the AFK and DND tags follow Secondary Text")
    Check(not source:find("SetTextColor(1, 1, 1)", 1, true), "topbar: no fixed white clock text is left")
end

-- The launcher tooltips: the game's gold title and white lines, or the theme's Accent and Text.
do
    local source = Read("Core/NaowhForever_Window.lua")
    local TIP_TITLE, TIP_TEXT = Const(source, "TIP_TITLE"), Const(source, "TIP_TEXT")
    Check(IsRGB(TIP_TITLE, 1, 0.82, 0) and IsRGB(TIP_TEXT, 1, 1, 1), "launcher tooltip literals are the originals")
    local code = assert(source:match("(local function TipTitle%(tooltip, text%).-\nend\nlocal function TipLine%(tooltip, text%).-\nend)"))
    local function Tips(account)
        local lines = {}
        local tooltip = { AddLine = function(_, text, r, g, b) lines[#lines + 1] = { text, r, g, b } end }
        local chunk = assert(loadstring(code .. "\nTipTitle(tooltip, 'T') TipLine(tooltip, 'L')"))
        local core = LoadCore(account)
        setfenv(chunk, setmetatable({ ns = core, tooltip = tooltip, TIP_TITLE = TIP_TITLE, TIP_TEXT = TIP_TEXT }, { __index = _G }))
        chunk()
        return lines, core.THEME
    end
    local lines = Tips({})
    Check(Same(lines[1], { "T", 1, 0.82, 0 }) and Same(lines[2], { "L", 1, 1, 1 }), "launcher tooltip: the default theme keeps the gold title and white lines")
    local t
    lines, t = Tips(ACCENT_PRESET)
    Check(Same(lines[1], { "T", t.accent.r, t.accent.g, t.accent.b }), "launcher tooltip: the title follows Accent")
    Check(Same(lines[2], { "L", t.fg.r, t.fg.g, t.fg.b }), "launcher tooltip: the lines follow Text")
    Check(not source:find('tooltip:AddLine(mod.name)', 1, true) and not source:find('tooltip:AddLine("Naowh Forever")', 1, true),
        "launcher tooltip: no untinted title is left")
end

-- The FPS / MS readout's labels follow Text; its numbers keep their status colors.
do
    local source = Read("TopBar/NaowhForever_TopBar.lua")
    Check(source:find('bar.sys.text:SetTextColor(Tone("fg", 1))', 1, true), "topbar: the FPS / MS labels are set from Text")
end

-- The Loot Feed: the dark style's fill follows Background, the light style's fill and edge
-- follow Panels and Borders & Lines (same opacity), the glow follows Accent; nothing changes
-- with the default theme.
do
    local source = Read("QoL/NaowhForever_LootFeed.lua")
    local DARK_BG, LIGHT_BG, LIGHT_EDGE, GLOW =
        Const(source, "DARK_BG"), Const(source, "LIGHT_BG"), Const(source, "LIGHT_EDGE"), Const(source, "GLOW")
    Check(IsRGB(DARK_BG, 0.05, 0.05, 0.06) and IsRGB(LIGHT_BG, 0.32, 0.23, 0.14), "loot feed fill literals are the originals")
    Check(IsRGB(LIGHT_EDGE, 0.12, 0.08, 0.04) and IsRGB(GLOW, 1, 0.8, 0.3), "loot feed edge and glow literals are the originals")
    local block = assert(source:match('(if st == STYLES%.dark then\n.-\n    end)\n    row%.glow:SetShown'))
    local STYLES = { dark = { bg = { 0.05, 0.05, 0.06, 0.8 }, edge = { 0, 0, 0, 1 } },
        light = { bg = { 0.32, 0.23, 0.14, 0.7 }, edge = { 0.12, 0.08, 0.04, 1 } } }
    local function Row(account, style)
        local fill, edge
        Run(block, { ns = LoadCore(account), st = STYLES[style], STYLES = STYLES, unpack = unpack,
            DARK_BG = DARK_BG, LIGHT_BG = LIGHT_BG, LIGHT_EDGE = LIGHT_EDGE,
            row = { bg = { SetColorTexture = function(_, ...) fill = { ... } end },
                border = { SetColor = function(_, ...) edge = { ... } end } } })
        return fill, edge
    end
    local ns = LoadCore(ACCENT_PRESET)
    local T = ns.THEME
    local fill, edge = Row({}, "dark")
    Check(Same(fill, { 0.05, 0.05, 0.06, 0.8 }) and Same(edge, { 0, 0, 0, 1 }), "loot feed dark: the default theme is as before")
    fill, edge = Row({}, "light")
    Check(Same(fill, { 0.32, 0.23, 0.14, 0.7 }) and Same(edge, { 0.12, 0.08, 0.04, 1 }), "loot feed light: the default theme is as before")
    fill, edge = Row(ACCENT_PRESET, "dark")
    Check(Same(fill, { T.bg.r, T.bg.g, T.bg.b, 0.8 }) and Same(edge, { 0, 0, 0, 1 }), "loot feed dark: the Background, edge still black")
    fill, edge = Row(ACCENT_PRESET, "light")
    Check(Same(fill, { T.panel.r, T.panel.g, T.panel.b, 0.7 }), "loot feed light: the Panels color at the same opacity")
    Check(Same(edge, { T.line.r, T.line.g, T.line.b, 1 }), "loot feed light: the Borders & Lines color")
    fill, edge = Row({ themePreset = "custom", themeColors = { bg = { r = 1, g = 0, b = 0 } } }, "light")
    Check(Same(fill, { 0.32, 0.23, 0.14, 0.7 }) and Same(edge, { 0.12, 0.08, 0.04, 1 }),
        "loot feed light: a theme that left Panels and lines alone keeps the brown")

    local glowStmt = assert(source:match('(local glow = ns%.ThemeTint%("accent", GLOW%)\n[^\n]*SetGradient[^\n]*)'))
    local function Glow(account)
        local from, to
        local function CreateColor(r, g, b, a) return { r, g, b, a } end
        Run(glowStmt, { ns = LoadCore(account), GLOW = GLOW, CreateColor = CreateColor,
            row = { glow = { SetGradient = function(_, _, a, b) from, to = a, b end } } })
        return from, to
    end
    local from, to = Glow({})
    Check(Same(from, { 1, 0.8, 0.3, 0.7 }) and Same(to, { 1, 0.8, 0.3, 0 }), "loot feed glow: the default theme keeps its gold")
    from, to = Glow(ACCENT_PRESET)
    Check(Same(from, { T.accent.r, T.accent.g, T.accent.b, 0.7 }) and Same(to, { T.accent.r, T.accent.g, T.accent.b, 0 }),
        "loot feed glow: the accent, fading out")
end

-- The XP bar's rested segment and its text follow a changed accent; quest gold stays gold.
do
    local source = Read("QoL/NaowhForever_XPBar.lua")
    local RESTED = assert(loadstring("return " .. assert(source:match("\nlocal RESTED%s+= (%b{})"))))()
    Check(IsRGB(RESTED, 0x1e / 255, 0x40 / 255, 0xaf / 255), "xpbar rested literal is the original")
    local line = assert(source:match('(local rested = shifted and [^\n]*)'))
    local function Rested(account)
        local chunk = assert(loadstring('local shifted = ns.ThemeTint("accent", nil)\n' .. line .. "\nreturn rested"))
        setfenv(chunk, setmetatable({ ns = LoadCore(account), RESTED = RESTED }, { __index = _G }))
        return chunk()
    end
    Check(Rested({}) == RESTED, "xpbar: the default theme keeps the royal blue")
    local a = AccentOf(ACCENT_PRESET)
    local on = Rested(ACCENT_PRESET)
    Check(on.r == a.r * 0.7 and on.g == a.g * 0.7 and on.b == a.b * 0.7, "xpbar: rested is a deeper shade of the accent")
    local expr = assert(source:match('(ns%.ThemeTint%("accent", nil%) and ns%.Color%("accent"%) or RESTED_HEX)'))
    local function Text(account)
        local chunk = assert(loadstring("return " .. expr))
        setfenv(chunk, setmetatable({ ns = LoadCore(account), RESTED_HEX = "|cff6b8cff" }, { __index = _G }))
        return chunk()
    end
    Check(Text({}) == "|cff6b8cff", "xpbar: the rested text keeps its blue by default")
    Check(Text(ACCENT_PRESET) == "|cff5b8cff", "xpbar: the rested text follows the accent")

    -- Quest XP: the logo's gold by default, the lighter accent in a theme.
    local QUEST = assert(loadstring("return " .. assert(source:match("\nlocal QUEST%s+= (%b{})"))))()
    Check(IsRGB(QUEST, 0xf2 / 255, 0xa9 / 255, 0x00 / 255), "xpbar quest literal is the original")
    local questLine = assert(source:match('(local quest = ns%.ThemeTint%("accentSoft", QUEST%))'))
    local function Quest(account)
        local chunk = assert(loadstring(questLine .. "\nreturn quest"))
        local ns = LoadCore(account)
        setfenv(chunk, setmetatable({ ns = ns, QUEST = QUEST }, { __index = _G }))
        return chunk(), ns.THEME.accentSoft
    end
    Check(Quest({}) == QUEST, "xpbar: the default theme keeps the quest gold")
    local color, soft = Quest(ACCENT_PRESET)
    Check(color == soft, "xpbar: a theme's quest segment is its lighter accent")
    local qexpr = assert(source:match('(ns%.ThemeTint%("accentSoft", nil%) and ns%.Color%("accentSoft"%) or QUEST_HEX)'))
    local function QuestText(account)
        local chunk = assert(loadstring("return " .. qexpr))
        setfenv(chunk, setmetatable({ ns = LoadCore(account), QUEST_HEX = "|cfff2a900" }, { __index = _G }))
        return chunk()
    end
    Check(QuestText({}) == "|cfff2a900", "xpbar: the quest text keeps its gold by default")
    Check(QuestText(ACCENT_PRESET) == "|cff91b2ff", "xpbar: the quest text follows the lighter accent")
end

-- Apply Theme to Bar Colours (Swing Timer): off by default, the picked colors; on, the theme's
-- Accent, lighter Accent and a deeper Accent for the main hand, off hand and ranged bars.
do
    local path = "SwingTimer/NaowhForever_SwingTimer.lua"
    local source = Read(path)
    local helper = assert(source:match("(local function ThemedBar%(key%).-\nend\n\nlocal function Color%(key%).-\nend)"), path .. ": Color")
    local PICKED = { mhColor = { r = 0.9, g = 0.7, b = 0.27 }, ohColor = { r = 0.9, g = 0.45, b = 0.27 }, rColor = { r = 0.27, g = 0.73, b = 0.9 } }
    local function Bar(account, key, themed)
        local core = LoadCore(account)
        local env = { T = core.THEME, S = { Get = function(k)
            if k == "themeColors" then return themed end
            return PICKED[k]
        end } }
        local chunk = assert(loadstring(helper .. "\nreturn Color(...)"))
        setfenv(chunk, setmetatable(env, { __index = _G }))
        return { chunk(key) }, core.THEME
    end
    local got = Bar(ACCENT_PRESET, "mhColor", false)
    Check(Same(got, { 0.9, 0.7, 0.27, 1 }), "swing timer: the picked color while Apply Theme is off")
    local t
    got, t = Bar(ACCENT_PRESET, "mhColor", true)
    Check(Same(got, { t.accent.r, t.accent.g, t.accent.b, 1 }), "swing timer: main hand is the Accent")
    got = Bar(ACCENT_PRESET, "ohColor", true)
    Check(Same(got, { t.accentSoft.r, t.accentSoft.g, t.accentSoft.b, 1 }), "swing timer: off hand is the lighter Accent")
    got = Bar(ACCENT_PRESET, "rColor", true)
    Check(Same(got, { t.accent.r * 0.6, t.accent.g * 0.6, t.accent.b * 0.6, 1 }), "swing timer: ranged is a deeper Accent")
    PICKED.queueColor = { r = 1, g = 0.7, b = 0.2 }
    got = Bar(ACCENT_PRESET, "queueColor", true)
    Check(Same(got, { 1, 0.7, 0.2, 1 }), "swing timer: the queued attack color is not themed")
    Check(source:find('S.Toggle("themeColors", "Apply Theme to Bar Colours"', 1, true), "swing timer: the switch beside Ranged")
end

print("PASS theme HUD: " .. cases .. " checks")
