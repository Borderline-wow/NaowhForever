-------------------------------------------------------------------------------
--  NaowhForever_Core.lua -- theme, chrome primitives, DB and profile plumbing.
--  Standalone addon: no EllesmereUI dependency.
--  ns.FEATURE_BADGES: 0 hides supporter badges, badge settings and support mentions until they
--  launch; the team's badges still show, on their defaults.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- Must match the addon folder; the DB and saved positions key off it.
-- Renamed with the addon (was NaowhSmartReminders, and NaowhUI_TankReminder before that).
local MODULE_KEY = "NaowhForever"

local ns = {}
_G.NaowhForever = ns
ns.MODULE_KEY = MODULE_KEY

local locale = _G.NaowhForeverLocale or {}
function ns.L(key, ...)
    local text = locale[key]
    if text == nil or text == true then text = key end
    if select("#", ...) > 0 then return text:format(...) end
    return text
end

-- Bumped by hand on every code change sent to a tester and printed beside the TOC version,
-- which only moves on release. A report naming a stamp the reporter was not sent comes from
-- a client that was not reloaded after the files changed.
ns.CODE_BUILD = "1.0.1"

ns.FEATURE_BADGES = 0

-- Naowh's own scheme: dark grey with his blue (#0091ed) as the single accent.
ns.THEME = {
    bg     = { r = 0x0e / 255, g = 0x0f / 255, b = 0x11 / 255 },  -- window backdrop
    panel  = { r = 0x1a / 255, g = 0x1c / 255, b = 0x1f / 255 },  -- panels, modals, controls
    line   = { r = 0x2e / 255, g = 0x31 / 255, b = 0x36 / 255 },  -- borders, dividers, tracks
    fg     = { r = 0xf0 / 255, g = 0xf1 / 255, b = 0xf3 / 255 },  -- primary text
    muted  = { r = 0x9a / 255, g = 0x9e / 255, b = 0xa6 / 255 },  -- secondary text
    grey   = { r = 0x34 / 255, g = 0x37 / 255, b = 0x3d / 255 },  -- selected-row neutral fill
    accent     = { r = 0x00 / 255, g = 0x91 / 255, b = 0xed / 255 },
    accentSoft = { r = 0x4d / 255, g = 0xb5 / 255, b = 0xf5 / 255 },
}

-- Theme presets for Settings > COLORS: the six tokens a player can change, per preset. The
-- default theme is not listed; it is ns.THEME above, untouched. Each preset keeps fg at 4.5:1
-- and muted and accent at 3:1 against its own bg and panel (Tools/regression checks it).
ns.THEME_EDITABLE = { "bg", "panel", "line", "fg", "muted", "accent" }
ns.THEME_PRESET_ORDER = { "midnight", "slate", "obsidian", "aubergine", "forest", "crimson", "rosenoir",
    "cottoncandy", "classic" }
ns.THEME_PRESETS = {
    midnight = { name = "Midnight",
        bg     = { r = 0x0b / 255, g = 0x10 / 255, b = 0x20 / 255 },
        panel  = { r = 0x15 / 255, g = 0x1c / 255, b = 0x30 / 255 },
        line   = { r = 0x2a / 255, g = 0x35 / 255, b = 0x50 / 255 },
        fg     = { r = 0xee / 255, g = 0xf2 / 255, b = 0xff / 255 },
        muted  = { r = 0x9b / 255, g = 0xa7 / 255, b = 0xc8 / 255 },
        accent = { r = 0x5b / 255, g = 0x8c / 255, b = 0xff / 255 } },
    slate = { name = "Slate",
        bg     = { r = 0x12 / 255, g = 0x16 / 255, b = 0x1c / 255 },
        panel  = { r = 0x1e / 255, g = 0x24 / 255, b = 0x2d / 255 },
        line   = { r = 0x36 / 255, g = 0x40 / 255, b = 0x4d / 255 },
        fg     = { r = 0xf0 / 255, g = 0xf3 / 255, b = 0xf5 / 255 },
        muted  = { r = 0x9a / 255, g = 0xa7 / 255, b = 0xb4 / 255 },
        accent = { r = 0x2b / 255, g = 0xb8 / 255, b = 0xa8 / 255 } },
    obsidian = { name = "Obsidian",
        bg     = { r = 0x07 / 255, g = 0x07 / 255, b = 0x08 / 255 },
        panel  = { r = 0x13 / 255, g = 0x14 / 255, b = 0x17 / 255 },
        line   = { r = 0x2b / 255, g = 0x2d / 255, b = 0x32 / 255 },
        fg     = { r = 0xf5 / 255, g = 0xf5 / 255, b = 0xf4 / 255 },
        muted  = { r = 0xa1 / 255, g = 0xa1 / 255, b = 0xa6 / 255 },
        accent = { r = 0xf5 / 255, g = 0xa5 / 255, b = 0x24 / 255 } },
    aubergine = { name = "Aubergine",
        bg     = { r = 0x13 / 255, g = 0x0d / 255, b = 0x18 / 255 },
        panel  = { r = 0x1f / 255, g = 0x16 / 255, b = 0x26 / 255 },
        line   = { r = 0x3a / 255, g = 0x2c / 255, b = 0x46 / 255 },
        fg     = { r = 0xf3 / 255, g = 0xee / 255, b = 0xf7 / 255 },
        muted  = { r = 0xa8 / 255, g = 0x9b / 255, b = 0xb8 / 255 },
        accent = { r = 0xb5 / 255, g = 0x7b / 255, b = 0xff / 255 } },
    forest = { name = "Forest",
        bg     = { r = 0x0c / 255, g = 0x13 / 255, b = 0x10 / 255 },
        panel  = { r = 0x16 / 255, g = 0x20 / 255, b = 0x19 / 255 },
        line   = { r = 0x2c / 255, g = 0x3b / 255, b = 0x31 / 255 },
        fg     = { r = 0xee / 255, g = 0xf4 / 255, b = 0xef / 255 },
        muted  = { r = 0x9a / 255, g = 0xae / 255, b = 0x9f / 255 },
        accent = { r = 0x36 / 255, g = 0xc5 / 255, b = 0x8a / 255 } },
    crimson = { name = "Crimson",
        bg     = { r = 0x14 / 255, g = 0x0a / 255, b = 0x0c / 255 },
        panel  = { r = 0x20 / 255, g = 0x13 / 255, b = 0x16 / 255 },
        line   = { r = 0x3d / 255, g = 0x24 / 255, b = 0x29 / 255 },
        fg     = { r = 0xf6 / 255, g = 0xef / 255, b = 0xf0 / 255 },
        muted  = { r = 0xac / 255, g = 0x9a / 255, b = 0x9e / 255 },
        accent = { r = 0xef / 255, g = 0x4b / 255, b = 0x56 / 255 } },
    rosenoir = { name = "Rose Noir",
        bg     = { r = 0x1a / 255, g = 0x0b / 255, b = 0x14 / 255 },
        panel  = { r = 0x27 / 255, g = 0x12 / 255, b = 0x1d / 255 },
        line   = { r = 0x4a / 255, g = 0x24 / 255, b = 0x38 / 255 },
        fg     = { r = 0xfd / 255, g = 0xee / 255, b = 0xf5 / 255 },
        muted  = { r = 0xc9 / 255, g = 0xa3 / 255, b = 0xb6 / 255 },
        accent = { r = 0xff / 255, g = 0x5f / 255, b = 0xa2 / 255 } },
    cottoncandy = { name = "Cotton Candy",
        bg     = { r = 0x1c / 255, g = 0x18 / 255, b = 0x32 / 255 },
        panel  = { r = 0x27 / 255, g = 0x22 / 255, b = 0x45 / 255 },
        line   = { r = 0x46 / 255, g = 0x3f / 255, b = 0x70 / 255 },
        fg     = { r = 0xf8 / 255, g = 0xf2 / 255, b = 0xff / 255 },
        muted  = { r = 0xbb / 255, g = 0xb2 / 255, b = 0xdc / 255 },
        accent = { r = 0xf7 / 255, g = 0x8f / 255, b = 0xc8 / 255 } },
    classic = { name = "Classic",
        bg     = { r = 0x15 / 255, g = 0x10 / 255, b = 0x0b / 255 },
        panel  = { r = 0x22 / 255, g = 0x1a / 255, b = 0x12 / 255 },
        line   = { r = 0x4d / 255, g = 0x3c / 255, b = 0x26 / 255 },
        fg     = { r = 0xf4 / 255, g = 0xe8 / 255, b = 0xcc / 255 },
        muted  = { r = 0xa8 / 255, g = 0x9a / 255, b = 0x7c / 255 },
        accent = { r = 0xd6 / 255, g = 0x8e / 255, b = 0x35 / 255 } },
}

-- A |cffRRGGBB escape from a THEME key (or an {r,g,b} table). With text it wraps it and
-- closes with |r; without, it returns the bare prefix for strings built in pieces.
local colorPrefix = {}
function ns.Color(token, text)
    local prefix = colorPrefix[token]
    if not prefix then
        local c = type(token) == "table" and token or ns.THEME[token]
        prefix = ("|cff%02x%02x%02x"):format(
            math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
        if type(token) == "string" then colorPrefix[token] = prefix end
    end
    if text == nil then return prefix end
    return prefix .. text .. "|r"
end

function ns.PlainText(text, max)
    if type(text) ~= "string" then return nil end
    if max and #text > max then text = text:sub(1, max) end
    return (text:gsub("%c", " "):gsub("||", "\1"):gsub("|", "||"):gsub("\1", "||"))
end

-- Player colors from Settings > COLORS, saved for this computer. They are written into the
-- THEME tables above in place, once per load and before any window is built, so every
-- file's `local T = ns.THEME` sees them; a new pick takes effect after a reload.
local themeShipped = {}

local function Channel(v)
    v = tonumber(v)
    if not v then return nil end
    return math.min(1, math.max(0, v))
end

local function Pick(source, key)
    local c = type(source) == "table" and source[key]
    if type(c) ~= "table" then return nil end
    local r, g, b = Channel(c.r), Channel(c.g), Channel(c.b)
    if r and g and b then return r, g, b end
end

-- The colors in force: a preset's table, or the player's own picks for Custom. Anything else,
-- an unknown preset name included, is the default theme and applies nothing.
local function ThemeSource()
    local account = ns.AccountSettings()
    local preset = account.themePreset
    if preset == "custom" then return account.themeColors end
    return type(preset) == "string" and ns.THEME_PRESETS[preset] or nil
end

local function Paint(key, r, g, b)
    local t = ns.THEME[key]
    if not themeShipped[key] then themeShipped[key] = { r = t.r, g = t.g, b = t.b } end
    t.r, t.g, t.b = r, g, b
end

-- The lighter accent and the selection fill are not picked: they follow the accent and the
-- line, a fixed step toward white, and only when those two were changed.
local function Lightened(t, amount)
    return t.r + (1 - t.r) * amount, t.g + (1 - t.g) * amount, t.b + (1 - t.b) * amount
end

-- A pick that matches the shipped color is not a change: Custom starts as a copy of the
-- palette, and the color picker hands back what it opened with, so neither may count as one.
local function Shipped(key, r, g, b)
    local t = themeShipped[key] or ns.THEME[key]
    local near = 1 / 255
    return math.abs(r - t.r) <= near and math.abs(g - t.g) <= near and math.abs(b - t.b) <= near
end

function ns.ApplyThemeColors()
    local source = ThemeSource()
    if not source then return end
    for _, key in ipairs(ns.THEME_EDITABLE) do
        local r, g, b = Pick(source, key)
        if r and not Shipped(key, r, g, b) then Paint(key, r, g, b) end
    end
    if themeShipped.accent then Paint("accentSoft", Lightened(ns.THEME.accent, 0.33)) end
    if themeShipped.line then Paint("grey", Lightened(ns.THEME.line, 0.03)) end
    for key in pairs(colorPrefix) do colorPrefix[key] = nil end
end

-- The selection in the Theme dropdown: a preset key, "custom", or "" for the default theme.
function ns.ThemePresetKey()
    local preset = ns.AccountSettings().themePreset
    if preset == "custom" or (type(preset) == "string" and ns.THEME_PRESETS[preset]) then
        return preset
    end
    return ""
end

local function HasPicks(colors)
    for _, key in ipairs(ns.THEME_EDITABLE) do
        if Pick(colors, key) then return true end
    end
    return false
end

-- The six colors of a preset, or of the default theme for "" or any unknown name, as picks.
local function PalettePicks(name)
    local from = ns.THEME_PRESETS[name]
    local picks = {}
    for _, key in ipairs(ns.THEME_EDITABLE) do
        local r, g, b = Pick(from, key)
        if not r then
            local t = themeShipped[key] or ns.THEME[key]
            r, g, b = t.r, t.g, t.b
        end
        picks[key] = { r = r, g = g, b = b }
    end
    return picks
end

-- Custom starts from the palette the player was looking at, unless they have picks saved
-- from before, which stay.
function ns.SetThemePreset(name)
    local account = ns.AccountSettings()
    local previous = ns.ThemePresetKey()
    if name == "custom" then
        if previous ~= "custom" and not HasPicks(account.themeColors) then
            account.themeColors = PalettePicks(previous)
        end
        account.themePreset = "custom"
    elseif type(name) == "string" and ns.THEME_PRESETS[name] then
        account.themePreset = name
    else
        account.themePreset = nil
    end
end

-- Replaces the Custom picks with a preset's colors ("" for the default theme's): the way
-- back to a good palette after some experimenting.
function ns.CopyThemeToCustom(name)
    ns.AccountSettings().themeColors = PalettePicks(name)
end

-- The six colors the Theme row previews for a selection ("" for the default theme, a preset
-- key, or "custom"): background, panels, borders, text, secondary text, accent.
function ns.ThemePalette(key)
    local out = {}
    for i, token in ipairs(ns.THEME_EDITABLE) do
        local r, g, b
        if key == "custom" then
            r, g, b = ns.ThemeSwatchColor(token)
        else
            local c = PalettePicks(key)[token]
            r, g, b = c.r, c.g, c.b
        end
        out[i] = { r = r, g = g, b = b }
    end
    return out
end

-- What a swatch shows: the saved pick, else the color the addon ships with.
function ns.ThemeSwatchColor(key)
    local r, g, b = Pick(ns.AccountSettings().themeColors, key)
    if r then return r, g, b end
    local t = themeShipped[key] or ns.THEME[key]
    return t.r, t.g, t.b
end

-- For a surface that ships its own shade instead of the token (a HUD panel with a tint):
-- the token while the theme has changed `key`, else the shipped literal untouched. Read when
-- a frame is built or refreshed, never at file load.
function ns.ThemeTint(key, literal)
    if themeShipped[key] then return ns.THEME[key] end
    return literal
end

-- A secret-tainted message is silently dropped by the display, so a combat diagnostic can
-- vanish as if the code never ran. tostring() on a secret returns a secret string that taints
-- whatever it is joined to, so issecretvalue() must be asked before the value is coerced.
local PRINT_LOGO_DROP = 1
ns.PRINT_LOGO = ("|TInterface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga:0:0:0:%d|t"):format(-PRINT_LOGO_DROP)

function ns.Print(msg)
    if issecretvalue and issecretvalue(msg) then
        msg = ns.Color("accent", "(withheld: this line contained a secret value)")
    end
    print(ns.PRINT_LOGO .. " " .. ns.Color("accent", "Naowh") .. " Forever: " .. tostring(msg))
end

-- Libs/ is not in git; the packager adds it. An install from the repository's source zip has
-- none, and features then fail one by one with Lua errors, so say so once at login.
local LIBRARIES = { "CallbackHandler-1.0", "LibDataBroker-1.1", "LibDBIcon-1.0", "LibSharedMedia-3.0",
    "LibCustomGlow-1.0", "LibGetFrame-1.0", "LibDeflate", "LibSerialize" }
local WARNING = { r = 1, g = 0.35, b = 0.35 }
local libCheck = CreateFrame("Frame")
libCheck:RegisterEvent("PLAYER_LOGIN")
libCheck:SetScript("OnEvent", function()
    local missing = {}
    for _, name in ipairs(LIBRARIES) do
        if not (LibStub and LibStub(name, true)) then missing[#missing + 1] = name end
    end
    if #missing == 0 then return end
    ns.Print(ns.Color(WARNING, "Libraries missing (" .. table.concat(missing, ", ") .. "), so parts of "
        .. "the addon will not work. Download Naowh Forever from the Releases page or the Naowh "
        .. "Discord, not with the green Code button on GitHub."))
end)

-------------------------------------------------------------------------------
--  Reload UI
-------------------------------------------------------------------------------
-- The game blocks an addon's own reload, even from a click (ADDON_ACTION_BLOCKED), but runs
-- /reload from a secure macro button. A protected frame inside our windows would lock them in
-- combat, so one button lives on UIParent, laid over the hovered Reload UI button by screen
-- position (never anchored) and hidden as combat starts.
local reloader

local function Reloader()
    if reloader then return reloader end
    reloader = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    reloader:SetFrameStrata("TOOLTIP")
    reloader:RegisterForClicks("AnyUp", "AnyDown")
    reloader:SetAttribute("type", "macro")
    reloader:SetAttribute("macrotext", "/reload")
    local glow = reloader:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, 0.08)
    reloader:SetScript("OnLeave", function(self)
        if not InCombatLockdown() then self:Hide() end
    end)
    reloader:RegisterEvent("PLAYER_REGEN_DISABLED")
    reloader:SetScript("OnEvent", reloader.Hide)
    reloader:Hide()
    return reloader
end

-- Lays the secure button over btn while the mouse is on it: OnEnter, out of combat.
local function CoverWithReload(btn)
    if InCombatLockdown() then return end
    local cover = Reloader()
    local scale = btn:GetEffectiveScale() / UIParent:GetEffectiveScale()
    cover:ClearAllPoints()
    cover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btn:GetLeft() * scale, btn:GetBottom() * scale)
    cover:SetSize(btn:GetWidth() * scale, btn:GetHeight() * scale)
    cover:Show()
end

-- What the button itself does when clicked: only reached when no cover lay over it.
local function ReloadBlocked()
    ns.Print("Can't reload from a button in combat. Type /reload.")
end

-- Makes btn (an ns.Button) a Reload UI button. Once per button.
function ns.MakeReloadButton(btn)
    btn._onClick = ReloadBlocked
    if not btn._reload then
        btn._reload = true
        btn:HookScript("OnEnter", CoverWithReload)
    end
    return btn
end

function ns.ReloadButton(parent, text, w, h)
    return ns.MakeReloadButton(ns.Button(parent, text, w, h))
end

-------------------------------------------------------------------------------
--  House chrome
-------------------------------------------------------------------------------
-- The UI font: the Naowh face, bundled so it works without NaowhUI_Media. Registered under
-- the same name and locale mask NaowhUI_Media uses; when that addon is installed its entry
-- wins (Register never overwrites), and its Asia variant then covers the CJK clients this
-- file leaves on the client default. Resolved once -- nothing builds UI before login.
local NAOWH_FONT = "Interface\\AddOns\\NaowhForever\\Media\\Fonts\\Naowh.ttf"
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM then
    LSM:Register("font", "Naowh", NAOWH_FONT, LSM.LOCALE_BIT_ruRU + LSM.LOCALE_BIT_western)
    LSM:Register("statusbar", "Naowh Gradient", "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga")
end

-- The three fonts on the Settings page, saved for this computer. Addon Font is this addon's
-- own text: nil is Naowh, BLIZZARD_FONT the game's. Game Font and Combat Text Font are off
-- (Blizzard's fonts left alone) for nil or BLIZZARD_FONT. Anything else is a SharedMedia
-- font name; one that has gone missing falls back to Naowh.
ns.BLIZZARD_FONT = "__blizzard"
local function FontPath(name)
    if name == nil or name == ns.BLIZZARD_FONT or not LSM then return nil end
    return LSM:Fetch("font", name, true) or LSM:Fetch("font", "Naowh", true)
end

local uiFontPath
-- The Naowh font starts a capital with a straight left side (N, L, D, B...) 75/1000 of its
-- size in from where the text begins (Media/Fonts/Naowh.ttf: 75 units of 1000). Lines of
-- different sizes set at one x so look a pixel ragged, the big ones further in; moving each
-- line left by its size's inset puts their letters on one edge.
local STEM_INSET = 0.075

---@param size number the font size
---@return number inset how far in its capitals start, in the same units
function ns.FontInset(size)
    return size * STEM_INSET
end

--- The Addon Font as a file path, looked up each time; UIFontPath keeps its first answer.
---@return string
function ns.AddonFontPath()
    return FontPath(ns.AccountSettings().uiFont or "Naowh") or STANDARD_TEXT_FONT
end

function ns.UIFontPath()
    if not uiFontPath then uiFontPath = ns.AddonFontPath() end
    return uiFontPath
end

-- Game Font and Combat Text Font on the whole game UI. Only font objects and the three path
-- globals are touched, never a frame, so it is taint-free but has no undo: a change takes a
-- reload. The path globals are read when the world loads, so they are set on ADDON_LOADED and
-- again at login for fonts from later addons. Combat text inherits SystemFont_World, which
-- Game Font changes, so it is set after.
local gameFontEvents = CreateFrame("Frame")
gameFontEvents:RegisterEvent("ADDON_LOADED")
gameFontEvents:RegisterEvent("PLAYER_LOGIN")
gameFontEvents:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= ADDON_NAME then return end
    if event == "ADDON_LOADED" then ns.ApplyThemeColors() end
    local account = ns.AccountSettings()
    local game, combat = FontPath(account.gameFont), FontPath(account.combatFont)
    if not (game or combat) then
        self:UnregisterAllEvents()
        return
    end
    if game then STANDARD_TEXT_FONT, UNIT_NAME_FONT = game, game end
    if combat then DAMAGE_TEXT_FONT = combat end
    if event == "ADDON_LOADED" then return end
    self:UnregisterAllEvents()
    local combatObjects = { CombatTextFont, CombatTextFontOutline }
    local combatFonts = {}
    for i, obj in ipairs(combatObjects) do combatFonts[i] = { obj:GetFont() } end
    if game then
        local fonts = GetFonts()
        for i = 1, #fonts do
            local obj = _G[fonts[i]]
            if type(obj) == "table" and obj.GetFont then
                local _, size, flags = obj:GetFont()
                if size and size > 0 then obj:SetFont(game, size, flags) end
            end
        end
    end
    for i, obj in ipairs(combatObjects) do
        local path, size, flags = unpack(combatFonts[i])
        if size and size > 0 then obj:SetFont(combat or path, size, flags) end
    end
end)

function ns.Font(parent, size, flags, color)
    local c = color or ns.THEME.fg
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.UIFontPath(), size, flags or "")
    fs:SetTextColor(c.r, c.g, c.b, 1)
    return fs
end

-------------------------------------------------------------------------------
--  Whole screen pixels
-------------------------------------------------------------------------------
-- At most UI scales one unit is less than a screen pixel, and the client snaps every edge to
-- a pixel: a line one unit thick, or an icon one unit in from its black backing, then rounds
-- to nothing on some sides and not others (a button's border missing its left edge). These
-- size and place them in screen pixels instead, worked out from the region's own scale, and
-- again whenever its frame shows or the scale changes.
local fitters = setmetatable({}, { __mode = "k" })   -- frame -> { region -> fit(onePixel) }

local function OnePixel(region)
    return PixelUtil.GetPixelToUIUnitFactor() / region:GetEffectiveScale()
end
ns.OnePixel = OnePixel

local function FitOwner(owner)
    for region, fit in pairs(fitters[owner]) do fit(OnePixel(region)) end
end

local function Register(region, fit)
    local owner = region:GetObjectType() == "Texture" and region:GetParent() or region
    if not fitters[owner] then
        fitters[owner] = setmetatable({}, { __mode = "k" })
        -- A child frame of ours shows with its owner. Hooking the owner's own OnShow is not
        -- enough: a module setting OnShow with SetScript after its lines are made drops the hook.
        local watch = CreateFrame("Frame", nil, owner)
        watch:SetScript("OnShow", function() FitOwner(owner) end)
    end
    fitters[owner][region] = fit
    fit(OnePixel(region))
end

-- A line one screen pixel thick: axis "h" for a horizontal one, "v" for a vertical one.
function ns.Hairline(tex, axis)
    Register(tex, function(px)
        if axis == "h" then tex:SetHeight(px) else tex:SetWidth(px) end
    end)
    return tex
end

-- The region filling relativeTo (its parent unless given) less n screen pixels on every side;
-- a negative n reaches out past it.
function ns.PixelInset(region, n, relativeTo)
    Register(region, function(px)
        local d = n * px
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", relativeTo or region:GetParent(), "TOPLEFT", d, -d)
        region:SetPoint("BOTTOMRIGHT", relativeTo or region:GetParent(), "BOTTOMRIGHT", -d, d)
    end)
    return region
end

-- After the UI scale or the window scale changes, for whatever is up already.
function ns.RefitPixels()
    for owner in pairs(fitters) do
        if owner:IsVisible() then FitOwner(owner) end
    end
end

local pixelEvents = CreateFrame("Frame")
pixelEvents:RegisterEvent("UI_SCALE_CHANGED")
pixelEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
pixelEvents:SetScript("OnEvent", function() ns.RefitPixels() end)

-- Four 1px edges on a child frame one level up, so the border draws over the panel's own
-- background but under its content. Returns { _frame, SetColor } -- _frame so a caller can
-- hide the whole border (the learn-tag does), SetColor for hover restyles.
function ns.Border(frame, color, alpha)
    local c = color or ns.THEME.line
    local a = alpha or 1
    local bf = CreateFrame("Frame", nil, frame)
    bf:SetAllPoints()
    bf:SetFrameLevel(math.min(frame:GetFrameLevel() + 1, 9999))
    local edges = {}
    for i = 1, 4 do
        local t = bf:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(c.r, c.g, c.b, a)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); ns.Hairline(edges[1], "h")
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); ns.Hairline(edges[2], "h")
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); ns.Hairline(edges[3], "v")
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); ns.Hairline(edges[4], "v")
    return {
        _frame = bf,
        SetColor = function(_, r, g, b, a2)
            for i = 1, 4 do edges[i]:SetColorTexture(r, g, b, a2 or 1) end
        end,
    }
end

function ns.Solid(parent, layer, color, alpha)
    local c = color or ns.THEME.panel
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c.r, c.g, c.b, alpha or 1)
    return t
end

-- For a clamped frame the player drags: up to 90% of it can go off the sides and bottom,
-- but the top edge stays on screen so its title bar can always be grabbed again.
local OFFSCREEN = 0.9

local function ClampOffscreen(frame, w, h)
    frame:SetClampRectInsets(w * OFFSCREEN, -w * OFFSCREEN, 0, h * OFFSCREEN)
end

function ns.AllowOffscreen(frame)
    ClampOffscreen(frame, frame:GetWidth(), frame:GetHeight())
    frame:HookScript("OnSizeChanged", ClampOffscreen)
end

-- NaowhUI's 1px black border on buttons and input boxes, lit blue on hover.
local BLACK = { r = 0, g = 0, b = 0 }

-- btn.label is exposed so a reused button can be re-labelled on each open, and btn._onClick
-- so it can be pointed at a new action.
function ns.Button(parent, text, w, h, onClick)
    local T = ns.THEME
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    local bg = ns.Solid(btn, "BACKGROUND", T.panel, 0.9)
    bg:SetAllPoints()
    local border = ns.Border(btn, BLACK)
    -- The border and the colour it rests at, so a caller can restyle a button (AccentButton).
    btn._border, btn._rest = border, BLACK
    btn._bg = bg
    local lbl = ns.Font(btn, 12, nil)
    lbl:SetPoint("CENTER")
    lbl:SetText(ns.L(text))
    btn.label = lbl
    btn._onClick = onClick
    btn:SetScript("OnClick", function() if btn._onClick then btn._onClick() end end)
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 1)
        border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 0.9)
        border:SetColor(btn._rest.r, btn._rest.g, btn._rest.b, 1)
    end)
    return btn
end

-- An ns.Button edged in the accent: the window's main action (Unlock Mode, Close, Open
-- Dungeon Journal). Theme colour, read when the button is made.
function ns.AccentBorder(frame)
    if not (frame and frame._border) then return frame end
    local accent = ns.THEME.accent
    frame._rest = accent
    frame._border:SetColor(accent.r, accent.g, accent.b, 1)
    return frame
end

function ns.SetButtonText(btn, text)
    if not (btn and btn.label) then return end
    btn.label:SetText(ns.L(text))
end

-- "Protection" alone names two classes. GetSpecializationInfoByID's seventh return is the
-- localized class name, which Blizzard's ClubFinder pairs it with.
function ns.SpecName(specID)
    local id = tonumber(specID)
    if not id then return tostring(specID) end
    local ok, _, name, _, _, _, _, className = pcall(GetSpecializationInfoByID, id)
    if not (ok and name) then return "Spec " .. id end
    if className and className ~= "" then return name .. " " .. className end
    return name
end

-- Composed at hover time: a function body can answer from data that loaded after the row was
-- built (spell text loads async).
local function ComposeTooltip(frame)
    local b = frame._tipBody
    if type(b) == "function" then b = b() end
    if b and b ~= "" then
        return ns.Color("accent", frame._tipTitle) .. "\n" .. b
    end
    return frame._tipTitle
end

-- The text lives on the frame and the hooks go on once, so a reused frame takes new text
-- without stacking hooks. ns.UI is resolved at hover time: the Widgets file loads after this.
function ns.Tooltip(frame, title, body)
    frame._tipTitle, frame._tipBody = title, body
    if frame._tipHooked then return end
    frame._tipHooked = true
    -- Hooked, not set: SetScript replaced ns.Button's own hover highlight.
    frame:HookScript("OnEnter", function(self)
        local UI = ns.UI
        if UI and UI.ShowWidgetTooltip then
            UI.ShowWidgetTooltip(self, function() return ComposeTooltip(self) end,
                { anchor = "cursor", justify = "LEFT" })
        end
    end)
    frame:HookScript("OnLeave", function()
        local UI = ns.UI
        if UI and UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
    end)
end

-- Stacking for our modals, which nest on one strata. Frame:Raise() orders against all of
-- UIParent's children, so its level is unbounded; a private counter starting low keeps each new
-- modal above the last at a level this file controls. The 150 ceiling predates MenuUtil menus
-- and stays because bounded is the point.
local nextModalLevel = 10

-- One shell per key, reused on every open (with UI.Keep): WoW frames are never freed, so new
-- frames per open leaked every earlier copy. Opening a key that is already up closes it first.
-- Nested dialogs use different keys, so a parent is never closed to open its child.
local shells = {}

-- A dimmed modal shell: click-off to dismiss, house border and panel fill. Returns the
-- dimmer (show/hide this) and the panel to fill. `key` names the dialog; pass one unless
-- several copies are genuinely meant to coexist. dimmer.onClose, set by the caller after
-- opening, runs once when this open closes.
function ns.MakeModal(width, height, key)
    local shell = key and shells[key]
    if shell then
        shell.dimmer:Hide()
        shell.dimmer.onClose = nil
        local panel = shell.panel
        panel:SetSize(width, height)
        panel:SetScale(ns.UIScale())
        panel:ClearAllPoints()
        panel:SetPoint("CENTER")
        ns.UI.BeginReusableRows(panel)
        return shell.dimmer, panel
    end
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    -- Mouse stays off the full-screen anchor so the Dungeon Journal and everything underneath
    -- stays clickable; only the panel captures the mouse.
    dimmer:EnableMouse(false)
    local panel = CreateFrame("Frame", nil, dimmer)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetScale(ns.UIScale())
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    local bg = ns.Solid(panel, "BACKGROUND", ns.THEME.panel, 1)
    bg:SetAllPoints()
    ns.Border(panel)

    -- Not saved: re-centred on every open.
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Not UISpecialFrames: that needs a global name per frame, and these are nameless and stack.
    -- ESCAPE closes only this one, so a second press reaches the modal underneath.
    -- SetPropagateKeyboardInput is protected, so in combat the keyboard is not taken at all;
    -- taking it without propagation control would swallow every keybind. ESC then cannot
    -- close the modal; its close button still does.
    dimmer:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:Hide()
            self:SetPropagateKeyboardInput(false)
            -- Restored once this key is consumed: a cached modal shown again in combat
            -- cannot change it, and would swallow every keybind while open.
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    dimmer:SetScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(true)
        end
        -- Wound back so the panel level (this + 5) stays under 200, the hardcoded dropdown
        -- level; past it, dropdowns rendered behind their panel. Nesting never gets deep.
        if nextModalLevel > 150 then nextModalLevel = 10 end
        nextModalLevel = nextModalLevel + 10
        self:SetFrameLevel(nextModalLevel)
        panel:SetFrameLevel(nextModalLevel + 5)
    end)
    dimmer:Hide()
    dimmer:SetScript("OnHide", function(self)
        local fn = self.onClose
        self.onClose = nil
        if fn then fn() end
    end)

    ns.UI.BeginReusableRows(panel)
    if key then shells[key] = { dimmer = dimmer, panel = panel } end
    return dimmer, panel
end

-- A text box on the house background and border, for dialogs to keep with UI.Keep.
function ns.NewEditBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(6, 6, 0, 0)
    ns.Solid(box, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    box._border = ns.Border(box, BLACK)
    -- Public for a caller that styles its own box (the accent while typing).
    box.border = box._border
    box:HookScript("OnEnter", function()
        local a = ns.THEME.accent
        box._border:SetColor(a.r, a.g, a.b, 1)
    end)
    box:HookScript("OnLeave", function() box._border:SetColor(0, 0, 0, 1) end)
    return box
end

-- A search field: hint text while empty, a clear button while not, Escape clears it. Made
-- the way the Professions search is; onChange gets the text on every edit.
function ns.NewSearchBox(parent, hint, onChange)
    local T = ns.THEME
    local box = ns.NewEditBox(parent)
    box.hint = ns.Font(box, 12, nil, T.muted)
    box.hint:SetPoint("LEFT", 6, 0)
    box.hint:SetText(ns.L(hint))
    box:SetTextInsets(6, 22, 0, 0)
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -2, 0)
    clear.text = ns.Font(clear, 13, nil, T.muted)
    clear.text:SetPoint("CENTER")
    clear.text:SetText("X")
    clear:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
    end)
    clear:SetScript("OnEnter", function() clear.text:SetTextColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
    clear:SetScript("OnLeave", function() clear.text:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1) end)
    clear:Hide()
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        clear:SetShown(text ~= "")
        if onChange then onChange(text) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end

-- maxLetters 0 allows any length, for pasting import strings.
function ns.PromptText(title, text, maxLetters, onAccept)
    local UI = ns.UI
    local dimmer, panel = ns.MakeModal(360, 130, "promptText")
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", 0, -14)
    head:SetWidth(330)
    head:SetText(title)
    -- A title that wraps pushes the box and buttons down, so the panel grows with it.
    panel:SetHeight(math.max(130, head:GetStringHeight() + 110))
    local box = UI.Keep(panel, "box", ns.NewEditBox)
    box:SetPoint("TOP", head, "BOTTOM", 0, -12)
    box:SetSize(320, 28)
    box:SetMaxLetters(maxLetters or 60)
    box:SetText(text or "")
    local function Accept()
        local value = strtrim(box:GetText())
        if value == "" then return end
        dimmer:Hide()
        onAccept(value)
    end
    UI.KeepButton(panel, "save", "Save", 96, 26, Accept):SetPoint("BOTTOM", panel, "BOTTOM", -52, 14)
    UI.KeepButton(panel, "cancel", "Cancel", 96, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 52, 14)
    box:SetScript("OnEnterPressed", Accept)
    box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    dimmer:Show()
    box:SetFocus()
    box:HighlightText()
end

-- The game cannot put text on the clipboard for an addon: this box shows it selected, for
-- Ctrl+C. onClose, when given, runs once it is closed.
function ns.ShowCopyBox(title, text, onClose)
    local UI, T = ns.UI, ns.THEME
    local dimmer, panel = ns.MakeModal(520, 260, "copyBox")
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE", T.accent)
    head:SetPoint("TOPLEFT", 14, -12)
    head:SetText(title)
    local hint = UI.KeepFont(panel, "hint", 11, nil, T.muted)
    hint:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    hint:SetText("Ctrl+A, Ctrl+C to copy")
    UI.KeepButton(panel, "close", "X", 22, 22, function() dimmer:Hide() end):SetPoint("TOPRIGHT", -8, -8)

    local scroll = UI.Keep(panel, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        ns.Solid(sf, "BACKGROUND", T.bg, 1):SetAllPoints()
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlight")
        eb:SetWidth(460)
        eb:SetTextInsets(4, 4, 4, 4)
        sf:SetScrollChild(eb)
        sf.box = eb
        return sf
    end)
    scroll:SetPoint("TOPLEFT", 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)
    local box = scroll.box
    box:SetText(text)
    box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    dimmer.onClose = function()
        box:ClearFocus()
        if onClose then onClose() end
    end
    dimmer:Show()
    box:SetFocus()
    box:HighlightText()
end

-- Confirm for a reload: Reload UI runs the game's own /reload (see Reload UI above).
local CONFIRM_W, CONFIRM_WIDE = 96, 150
local CONFIRM_H, CONFIRM_ROOM = 110, 74

function ns.ConfirmReload(text)
    local UI = ns.UI
    local dimmer, panel = ns.MakeModal(340, 110, "confirmReload")
    local head = UI.KeepFont(panel, "head", 13, nil)
    head:SetPoint("TOP", 0, -18)
    head:SetWidth(310)
    head:SetText(text)
    ns.MakeReloadButton(UI.KeepButton(panel, "yes", "Reload UI", 96, 26))
        :SetPoint("BOTTOM", panel, "BOTTOM", -52, 14)
    UI.KeepButton(panel, "no", "Later", 96, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 52, 14)
    dimmer:Show()
end

function ns.Confirm(text, onYes, onNo, yesText, noText)
    local UI = ns.UI
    local dimmer, panel = ns.MakeModal(340, CONFIRM_H, "confirm")
    local head = UI.KeepFont(panel, "head", 13, nil)
    head:SetPoint("TOP", 0, -18)
    head:SetWidth(310)
    head:SetText(text)
    panel:SetHeight(math.max(CONFIRM_H, head:GetStringHeight() + CONFIRM_ROOM))
    local w = (yesText or noText) and CONFIRM_WIDE or CONFIRM_W
    UI.KeepButton(panel, "yes", yesText or "Yes", w, 26, function()
        dimmer.onClose = nil
        dimmer:Hide()
        onYes()
    end):SetPoint("BOTTOM", panel, "BOTTOM", -(w / 2 + 4), 14)
    UI.KeepButton(panel, "no", noText or "No", w, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", w / 2 + 4, 14)
    -- No, Escape and a newer confirm taking this one's place all count as no.
    dimmer.onClose = onNo
    dimmer:Show()
end

-------------------------------------------------------------------------------
--  SavedVariables and profiles
-------------------------------------------------------------------------------
-- The addon's own DB. Profiles are account-wide with a per-character active pointer;
-- SettingsRoot hands back the active profile's root, and ns.DB layers its defaults onto
-- root.tankReminder from there. A switch hands ns.DB a different table identity, which is
-- what re-runs its weak-keyed defaults fill.
local activeRoot, provisional

local function CharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function DB()
    local sv = _G.NaowhForeverDB
    if type(sv) ~= "table" then
        -- Settings from before the rename. The client only loads them when the old
        -- NaowhSmartReminders.lua SavedVariables file is copied over as NaowhForever.lua.
        -- A new install starts from Naowh's Minimalist preset (NaowhForever_Presets.lua).
        sv = type(_G.NaowhUI_SmartRemindersDB) == "table" and _G.NaowhUI_SmartRemindersDB
            or { dbVersion = 1, profiles = { Default = ns.STARTER.profile }, account = ns.STARTER.account }
        _G.NaowhForeverDB = sv
        _G.NaowhUI_SmartRemindersDB = nil
    end
    if type(sv.profiles) ~= "table" then sv.profiles = {} end
    if type(sv.charActive) ~= "table" then sv.charActive = {} end
    return sv
end

function ns.SettingsRoot()
    if activeRoot then return activeRoot end
    local sv = DB()
    -- Forever returns "Unknown" for the player's name until late in loading; resolving
    -- then would file the character under a key it never uses again.
    if UnitName("player") == UNKNOWNOBJECT then
        local default = sv.defaultProfile or "Default"
        if type(sv.profiles[default]) ~= "table" then sv.profiles[default] = {} end
        provisional = sv.profiles[default]
        return provisional
    end
    local name = sv.charActive[CharKey()]
    if type(name) ~= "string" or type(sv.profiles[name]) ~= "table" then
        -- No assignment, or a deleted profile: the account default, which a newly made
        -- profile claims, so a first login afterwards joins the rest.
        name = type(name) == "string" and name or sv.defaultProfile or "Default"
        if type(sv.profiles[name]) ~= "table" and type(sv.defaultProfile) == "string" then
            name = sv.defaultProfile
        end
        sv.charActive[CharKey()] = name
    end
    if type(sv.profiles[name]) ~= "table" then sv.profiles[name] = {} end
    activeRoot = sv.profiles[name]
    return activeRoot
end

-------------------------------------------------------------------------------
--  Smart Reminders' settings (ns.DB). In the core so they are there while its addon is
--  off: profiles carry them, and the class macros and consumables are kept in them.
-------------------------------------------------------------------------------
-- Flat scalars only: a nested default would hand out a live reference to DEFAULTS itself.
-- Everything ships off by the owner's direction; until enabled, no events or frames exist.
local DEFAULTS = {
    enabled   = false,
    showIcon  = false,
    showText  = false,
    showBar   = false,
    soundOn   = false,
    soundKey  = "none",
    fallbackOn = false,
    coveredSkip = false,
    coveredCastWindow = 6,   -- how long your own cast counts as cover
    leadTime   = 3,     -- seconds before impact that the alert fires
    lingerSec  = 3,     -- display duration; early dismissal on cast is opt-in
    cdmGlow    = false, -- glow the called defensive on the Cooldown Manager bar
    voiceOn   = false,
    voiceNone = "Call for external",
    externalChat = false,
    voiceVol  = 100,
    iconSize  = 64,
    -- 21 matches the old derived floor(iconSize * 0.34) at the default iconSize of 64.
    textSize   = 21,
    textSide   = "BOTTOM",   -- TOP, BOTTOM, LEFT or RIGHT
    -- bossSource ("timeline", "bigwigs" or "dbm") has no default: unset follows the
    -- installed boss mod, see ns.BossSource().
    -- pos = { point, relPoint, x, y } once moved in Unlock Mode; nil = default centre.
}

-- Profile tables already migrated and default-filled. Keyed by table so nothing lands in
-- SavedVariables; per table, not once at init, because SettingsRoot() follows profile switches.
local prepared = setmetatable({}, { __mode = "k" })

function ns.DB()
    local root = ns.SettingsRoot()
    if type(root.tankReminder) ~= "table" then root.tankReminder = {} end
    local t = root.tankReminder
    if prepared[t] then return t end
    prepared[t] = true
    -- Migration: the pre-presets flat list per spec becomes that spec's "Default" preset.
    if type(t.lists) == "table" and next(t.lists) ~= nil and type(t.presets) ~= "table" then
        t.presets = {}
        t.activePreset = t.activePreset or {}
        for specKey, list in pairs(t.lists) do
            t.presets[specKey] = { p1 = { name = "Default", list = list } }
            t.activePreset[specKey] = "p1"
        end
        t.lists = nil
    end
    -- The text used to be positioned on its own; it rides the icon now.
    t.textPos = nil
    -- Broadcasts outside any encounter used to be catalogued under "0", which nothing reads.
    if type(t.bwCatalogue) == "table" then t.bwCatalogue["0"] = nil end
    -- Older builds pre-filled the callout editor with "Use <name>", so saved callouts still
    -- carry the prefix the spoken default dropped.
    if type(t.callouts) == "table" then
        for id, text in pairs(t.callouts) do
            local bare = type(text) == "string" and text:match("^[Uu]se%s+(.+)$")
            if bare then t.callouts[id] = bare end
        end
    end
    -- Call Together was briefly stored as a chain to the entry below; nothing reads it now.
    if type(t.presets) == "table" then
        for _, specPresets in pairs(t.presets) do
            if type(specPresets) == "table" then
                for _, p in pairs(specPresets) do
                    if type(p) == "table" then p.chain = nil end
                end
            end
        end
    end
    for k, v in pairs(DEFAULTS) do if t[k] == nil then t[k] = v end end
    return t
end

-- For the pack exporter. `pos` is not in DEFAULTS, so the exporter takes it separately.
function ns.SettingKeys()
    local out = {}
    for k in pairs(DEFAULTS) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function ns.SettingDefault(key)
    return DEFAULTS[key]
end

-- Account-wide, outside the profiles: the window scale follows the monitor, so it must not
-- travel in an exported pack or change on a profile switch.
function ns.AccountSettings()
    local sv = DB()
    if type(sv.account) ~= "table" then sv.account = {} end
    return sv.account
end

-- A personal opt-out, not part of any shared profile or reminder pack.
function ns.HealerRemindersEnabled()
    return ns.AccountSettings().healerRemindersEnabled ~= false
end

function ns.IsReminderEnabled(reminder, preview)
    return reminder ~= nil and (preview or reminder.enabled ~= false)
        and (reminder.healerReminder ~= true or ns.HealerRemindersEnabled())
end

function ns.SetHealerRemindersEnabled(enabled)
    ns.AccountSettings().healerRemindersEnabled = enabled and true or false
    if ns.ApplyReminderFilter then ns.ApplyReminderFilter() end
end

-- Stored as a percent, used as a multiplier. Clamped on read as well as on write: a zero
-- or negative scale hides the window with no way left to open the control that fixes it.
function ns.UIScale()
    local pct = tonumber(ns.AccountSettings().windowScale) or 100
    if pct < 50 then pct = 50 elseif pct > 200 then pct = 200 end
    return pct / 100
end

-- Anything read while the name was still "Unknown" got the account default. Once the name
-- is known, a character on another profile has everything reapplied from its own.
local nameWatch = CreateFrame("Frame")
nameWatch:RegisterEvent("PLAYER_LOGIN")
nameWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
nameWatch:RegisterUnitEvent("UNIT_NAME_UPDATE", "player")
nameWatch:SetScript("OnEvent", function(self)
    if UnitName("player") == UNKNOWNOBJECT then return end
    self:UnregisterAllEvents()
    if provisional and ns.SettingsRoot() ~= provisional then ns.QueueReapply() end
    provisional = nil
end)

-- The player's spec ID (0 before it is known) and whether it is a tank spec.
function ns.CurrentSpec()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return 0, false end
    local id, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(index)
    return id or 0, role == "TANK"
end

-- Spec-bound profiles (Profiles page) switch at login and on a spec change.
local specWatch = CreateFrame("Frame")
specWatch:RegisterEvent("PLAYER_LOGIN")
specWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
specWatch:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
specWatch:SetScript("OnEvent", function() ns.ApplySpecProfile((ns.CurrentSpec())) end)

local function ApplyNow() ns.Apply() end

local reapplyEvents = CreateFrame("Frame")
reapplyEvents:RegisterEvent("PLAYER_LOGIN")
reapplyEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
reapplyEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
reapplyEvents:RegisterEvent("SPELLS_CHANGED")
reapplyEvents:RegisterEvent("TRAIT_CONFIG_UPDATED")
reapplyEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, ApplyNow)
    else
        ns.QueueReapply()
    end
end)

-- The spoken voice, picked on the Smart Reminders page and used by every module that speaks.
-- "Game Default" stores no id and follows Blizzard's Text to Speech panel; an uninstalled
-- stored voice falls back rather than going silent. Cached because GetTtsVoices builds a
-- table per call. Blizzard's TTS panel raises no event on a voice change, so closing it or
-- Settings drops the cache; not combat start, where re-reading stalled every pull.
do
    local cachedWant, cachedID

    function ns.InvalidateTTSVoice()
        cachedWant, cachedID = nil, nil
    end

    local voiceWatch = CreateFrame("Frame")
    voiceWatch:RegisterEvent("PLAYER_LOGIN")
    voiceWatch:RegisterEvent("VOICE_CHAT_TTS_VOICES_UPDATE")
    voiceWatch:SetScript("OnEvent", function(self, event)
        if event == "VOICE_CHAT_TTS_VOICES_UPDATE" then return ns.InvalidateTTSVoice() end
        self:UnregisterEvent("PLAYER_LOGIN")
        for _, panel in ipairs({ _G.SettingsPanel, _G.TextToSpeechFrame }) do
            panel:HookScript("OnHide", ns.InvalidateTTSVoice)
        end
    end)

    function ns.TTSVoiceID()
        local want = ns.DB().ttsVoiceID
        if cachedID and cachedWant == want then return cachedID end
        if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return 0 end
        local voices = C_VoiceChat.GetTtsVoices()
        local resolved
        if want and voices then
            for i = 1, #voices do
                if voices[i].voiceID == want then
                    resolved = want
                    break
                end
            end
        end
        if not resolved and TextToSpeech_GetSelectedVoice then
            local ok, voice = pcall(TextToSpeech_GetSelectedVoice, Enum.TtsVoiceType.Standard)
            if ok and voice and voice.voiceID then resolved = voice.voiceID end
        end
        if not resolved then
            resolved = (voices and voices[1] and voices[1].voiceID) or 0
        end
        -- The voice list can be empty early in a session; do not cache a guess from it.
        if voices and #voices > 0 then cachedWant, cachedID = want, resolved end
        return resolved
    end
end

-- Game Default is keyed "" since a dropdown cannot carry nil as a value.
function ns.TTSVoiceChoices()
    local values, order = { [""] = "Game Default" }, { "" }
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local voices = C_VoiceChat.GetTtsVoices()
        for i = 1, #(voices or {}) do
            local v = voices[i]
            if v and v.voiceID and v.name then
                values[v.voiceID] = v.name
                order[#order + 1] = v.voiceID
            end
        end
    end
    return values, order
end

function ns.ActiveProfileName()
    if ns.SettingsRoot() == provisional then return DB().defaultProfile or "Default" end
    return DB().charActive[CharKey()]
end

-- Every character logged in with the addon loaded, and its profile now. One never logged into
-- is not in charActive and cannot be named in advance.
function ns.KnownCharacters()
    local sv = DB()
    local out = {}
    for char, profile in pairs(sv.charActive) do
        out[#out + 1] = { char = char, profile = profile }
    end
    table.sort(out, function(a, b) return a.char:lower() < b.char:lower() end)
    return out
end

function ns.ListProfiles()
    local out = {}
    for name in pairs(DB().profiles) do out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-- Spec -> profile, account-wide so it survives a profile switch. Written by a whole-file
-- import told to, and by a manual switch.
function ns.SpecProfileMap()
    local sv = DB()
    if type(sv.specProfile) ~= "table" then sv.specProfile = {} end
    return sv.specProfile
end

function ns.SetSpecProfile(specID, name)
    if not specID or specID == 0 then return end
    ns.SpecProfileMap()[tostring(specID)] = name
end

-- Off unless asked for: switching profile on a spec change unasked reads as a bug.
function ns.AutoSpecProfile(set)
    local sv = DB()
    if set ~= nil then sv.autoSpecProfile = set and true or nil end
    return sv.autoSpecProfile == true
end

-- Returns true when it actually switched.
function ns.ApplySpecProfile(specID)
    if not ns.AutoSpecProfile() then return false end
    if not specID or specID == 0 then return false end
    local sv = DB()
    local want = ns.SpecProfileMap()[tostring(specID)]
    -- A map entry pointing at a profile that has since been deleted is ignored rather than
    -- recreating it: the player deleted it on purpose.
    if not want or type(sv.profiles[want]) ~= "table" then return false end
    if sv.charActive[CharKey()] == want then return false end
    return (ns.SwitchProfile(want)) and true or false
end

-- Any profile's stored settings, for the exporter; read-only, the caller copies. nil for a
-- profile never written to.
function ns.ProfileSettings(name)
    local p = DB().profiles[name]
    return type(p) == "table" and type(p.tankReminder) == "table" and p.tankReminder or nil
end

-- Creates the profile if it is new. Used by a whole-file import, which has to land several
-- profiles at once without switching to each in turn.
function ns.EnsureProfile(name)
    local sv = DB()
    if type(sv.profiles[name]) ~= "table" then sv.profiles[name] = {} end
    if type(sv.profiles[name].tankReminder) ~= "table" then
        sv.profiles[name].tankReminder = {}
    end
    return sv.profiles[name].tankReminder
end

function ns.ProfileRoot(name)
    ns.EnsureProfile(name)
    return DB().profiles[name]
end

function ns.SwitchProfile(name)
    local sv = DB()
    if type(sv.profiles[name]) ~= "table" then return false, "no such profile" end
    sv.charActive[CharKey()] = name
    activeRoot = nil
    -- A manual switch teaches the map, so auto switching does not undo it at the next spec
    -- change. Recorded even with auto off, so turning it on later already knows.
    local spec = ns.CurrentSpec and ns.CurrentSpec()
    if spec and spec > 0 then ns.SetSpecProfile(spec, name) end
    ns.QueueReapply()
    return true
end

-- allowExisting: the caller already confirmed replacing a profile of this name.
local function ValidName(name, allowExisting)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil, "the name is empty" end
    if not allowExisting and DB().profiles[name] then return nil, "that name is taken" end
    return name
end

function ns.ProfileExists(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    return name ~= "" and type(DB().profiles[name]) == "table"
end

-- Point the whole account at one profile: every character now, and any logged into later.
function ns.SetAccountProfile(name)
    local sv = DB()
    if type(sv.profiles[name]) ~= "table" then return false, "no such profile" end
    sv.defaultProfile = name
    for char in pairs(sv.charActive) do sv.charActive[char] = name end
    sv.charActive[CharKey()] = name
    -- A spec map still pointing at the old profile put every alt straight back on it after an
    -- account-wide import. Auto switching is turned off, the map kept intact for turning it
    -- back on; the caller is told so it can say so.
    local turnedOff = sv.autoSpecProfile == true
    sv.autoSpecProfile = nil
    activeRoot = nil
    ns.QueueReapply()
    return true, turnedOff
end

-- A new profile becomes the account's, as asked for. Switching a character afterwards moves
-- only that one, until the next profile is made.
function ns.CreateProfile(name, overwrite)
    local err
    name, err = ValidName(name, overwrite)
    if not name then return false, err end
    local sv = DB()
    sv.profiles[name] = {}
    sv.defaultProfile = name
    for char in pairs(sv.charActive) do sv.charActive[char] = name end
    activeRoot = nil
    ns.QueueReapply()
    return true
end

local function DeepCopy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return out
end

function ns.CopyProfile(src, name, overwrite)
    local sv = DB()
    if type(sv.profiles[src]) ~= "table" then return false, "no such profile" end
    local err
    name, err = ValidName(name, overwrite)
    if not name then return false, err end
    sv.profiles[name] = DeepCopy(sv.profiles[src])
    -- Overwriting the profile in use replaces the table the cached root points at.
    if name == sv.charActive[CharKey()] then
        activeRoot = nil
        ns.QueueReapply()
    end
    return true
end

-- The live reset (alert, slot cache, events) only runs for the profile in use; any other just
-- has its stored settings cleared.
function ns.ResetProfileNamed(name)
    local sv = DB()
    if type(sv.profiles[name]) ~= "table" then return false, "no such profile" end
    if name == sv.charActive[CharKey()] then
        if ns.Reset then ns.Reset() else ns.SettingsRoot().tankReminder = nil end
        return true
    end
    sv.profiles[name].tankReminder = nil
    return true
end

function ns.DeleteProfile(name)
    local sv = DB()
    if type(sv.profiles[name]) ~= "table" then return false, "no such profile" end
    local count = 0
    for _ in pairs(sv.profiles) do count = count + 1 end
    if count <= 1 then return false, "the last profile cannot be deleted" end
    local wasMine = sv.charActive[CharKey()] == name
    sv.profiles[name] = nil
    -- "Default" may not exist once profiles are renamed. A replacement becomes the default
    -- too, or a later first login would start on a new, empty Default.
    local fallback = sv.defaultProfile or "Default"
    if type(sv.profiles[fallback]) ~= "table" then
        fallback = next(sv.profiles)
        sv.defaultProfile = fallback
    end
    for char, active in pairs(sv.charActive) do
        if active == name then sv.charActive[char] = fallback end
    end
    if wasMine then
        activeRoot = nil
        ns.QueueReapply()
    end
    return true
end

-------------------------------------------------------------------------------
--  Re-apply on anything that swaps the active settings out from under us
-------------------------------------------------------------------------------
-- Coalesced: one click can request several reapplies.
local reapplyPending

-- Re-applies the active profile. Empty here: every module that needs it hooks it. Core calls
-- it a second after login and queues it again on a new world, spec, spells or talents, so the
-- modules paint without Smart Reminders, which used to call it and no longer ships.
function ns.Apply() end

function ns.QueueReapply()
    -- Invalidate old-profile work immediately, even if two switches share a frame.
    if ns.PruneCustomReminderTimers then ns.PruneCustomReminderTimers() end
    if ns.PrunePendingBWFires then ns.PrunePendingBWFires() end
    if reapplyPending then return end
    reapplyPending = true
    C_Timer.After(0, function()
        reapplyPending = false
        ns.Apply()
        -- Profile changes do not reopen the options window, so its OnShow preview
        -- callback will not run. Restore it after Apply has rebuilt/hidden the slots.
        if ns.RefreshDefensivePreview then ns.RefreshDefensivePreview() end
    end)
end
