-- The RestedXP themes and hooks (RXPThemes/NaowhForever_RXPThemes.lua), run against the real Core. Run with
-- Lua 5.1 from the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end
local coreSource = Read("Core/NaowhForever_Core.lua")
local moduleSource = Read("RXPThemes/NaowhForever_RXPThemes.lua")

local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end
local function Same(got, want)
    for i = 1, #want do if got[i] ~= want[i] then return false end end
    return #got == #want
end
local function Hex(c)
    return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- A stand-in for LibSharedMedia: the fonts it holds, by name.
local function MediaStub(fonts)
    local lsm = { LOCALE_BIT_ruRU = 1, LOCALE_BIT_western = 2 }
    function lsm:Register(kind, name, path)
        if kind == "font" and not fonts[name] then fonts[name] = path end
    end
    function lsm:Fetch(_, name) return fonts[name] end
    return lsm
end

-- installed: whether RestedXP Guides exists. existing: what another addon already put in the table.
-- fonts: when given, LibSharedMedia is there and holds these fonts.
local function Load(account, installed, existing, fonts)
    local frames = {}
    local function Region()
        local r = {}
        function r:SetAllPoints() self.allPoints = true end
        function r:SetColorTexture(...) self.rgba = { ... } end
        function r:SetGradient(orientation, low, high) self.gradient = { orientation, low, high } end
        function r:SetBlendMode(mode) self.blend = mode end
        function r:AddMaskTexture(mask) self.masks = self.masks or {}; self.masks[#self.masks + 1] = mask end
        function r:SetTexture(path, wrapH, wrapV) self.path, self.wrapH, self.wrapV = path, wrapH, wrapV end
        function r:SetRotation(radians) self.rotation = radians end
        return r
    end
    local function NewFrame(_, _, parent)
        local f = { events = {}, parent = parent }
        setmetatable(f, { __index = function() return function() end end })
        function f:SetScript(name, fn) self[name] = fn end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetFrameLevel(level) self.level = level end
        function f:CreateTexture() self.colorRegion = Region(); return self.colorRegion end
        function f:CreateMaskTexture() self.maskRegion = Region(); return self.maskRegion end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        frames[#frames + 1] = f
        return f
    end
    local hooked = {}
    local env = { CreateFrame = NewFrame, RXPGuides_Themes = existing, hooked = hooked,
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
        CreateColor = function(r, g, b, a) return { r, g, b, a } end,
        hooksecurefunc = function(tbl, name, fn) hooked[#hooked + 1] = { tbl, name, fn } end,
        C_AddOns = { DoesAddOnExist = function(name) return installed and name == "RXPGuides" end },
        NaowhForeverDB = { account = account, profiles = {}, charActive = {} } }
    env._G = env
    env.InCombatLockdown = function() return env.inCombat == true end
    if fonts then
        local lsm = MediaStub(fonts)
        env.LibStub = function(name) if name == "LibSharedMedia-3.0" then return lsm end end
    end
    setmetatable(env, { __index = _G })
    local core = assert(loadstring(coreSource, "Core"))
    setfenv(core, env)
    core("NaowhForever")
    local coreFrames = #frames
    local module = assert(loadstring(moduleSource, "RXPThemes"))
    setfenv(module, env)
    module("NaowhForever")
    assert(#frames == coreFrames + 1, "the module makes one frame")
    return env, env.NaowhForever, frames, frames[#frames]
end

-- The game tells every frame that listens, in the order they registered.
local function Fire(frames, name)
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.OnEvent then f.OnEvent(f, "ADDON_LOADED", name) end
    end
end
-- Only the module's own frame: Core has login work of its own, which is not under test.
local function Login(boot)
    if boot.events.PLAYER_LOGIN and boot.OnEvent then boot.OnEvent(boot, "PLAYER_LOGIN") end
end
local function CombatEnds(env, boot)
    env.inCombat = false
    if boot.events.PLAYER_REGEN_ENABLED and boot.OnEvent then boot.OnEvent(boot, "PLAYER_REGEN_ENABLED") end
end
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- NaowhUI, then the presets as Core lists them, so a preset added there needs no new count here.
local KEYS, NAMES = { "" }, { [""] = "NaowhUI" }
do
    local _, coreNs = Load({}, false)
    for _, key in ipairs(coreNs.THEME_PRESET_ORDER) do
        KEYS[#KEYS + 1] = key
        NAMES[key] = coreNs.THEME_PRESETS[key].name
    end
end
local FIXED = #KEYS            -- NaowhUI and every preset
local REGISTERED = FIXED + 1   -- and Naowh (current)
local LAST = KEYS[#KEYS]
local function NameOf(key) return "NaowhForever:" .. (key == "" and "default" or key) end
local RXP_OWN = { "RXP Blue", "RXP Red", "RXP Gold", "DarkMode", "RXP Green", "Custom" }
local TEX = "Interface/AddOns/RXPGuides/Textures/"
local WHITE = "Interface/BUTTONS/WHITE8X8"
-- Written out apart from the module, so a wrong path there cannot hide behind itself.
local BORDER = "Interface\\AddOns\\NaowhForever\\Media\\rxp_frame.tga"

-- Off by default: nothing is written, whatever else is going on.
do
    local env, ns, frames, boot = Load({}, true)
    Check(boot.events.ADDON_LOADED, "the module waits for its addon to load")
    Fire(frames, "SomeOtherAddon")
    Check(env.RXPGuides_Themes == nil and boot.events.ADDON_LOADED, "another addon loading changes nothing")
    Fire(frames, "NaowhForever")
    Check(env.RXPGuides_Themes == nil, "off by default: RestedXP's table is not even created")
    Check(next(boot.events) == nil, "the event is unregistered once our addon has loaded")
    Check(ns.RXPThemesEnabled() == false and ns.RXPThemesAvailable() == true, "off, and RestedXP is seen")

    env, ns, frames = Load({ rxpThemes = true }, false)
    Fire(frames, "NaowhForever")
    Check(env.RXPGuides_Themes == nil, "on, but RestedXP Guides is not installed: nothing is written")
    Check(ns.RXPThemesAvailable() == false, "not installed")
end

-- On, with RestedXP installed: the fixed themes, from the palettes the Theme row previews, and the current one.
do
    local env, ns, frames, boot = Load({ rxpThemes = true }, true)
    Fire(frames, "NaowhForever")
    local list = env.RXPGuides_Themes
    Check(type(list) == "table" and Count(list) == REGISTERED, "NaowhUI, every preset and the current theme are registered")
    Check(boot.events.PLAYER_LOGIN and not boot.events.ADDON_LOADED, "then it waits for login, for the arrow")
    Login(boot)
    Check(next(boot.events) == nil, "and is unregistered after login")
    local seen = {}
    for _, key in ipairs(KEYS) do
        local theme = list[NameOf(key)]
        Check(theme and theme.name == NameOf(key), key .. ": registered under its own name")
        seen[theme.name] = true
        Check(theme.displayName == NAMES[key] and theme.author == "Naowh Forever", key .. ": name and author")
        local p = ns.ThemePalette(key)   -- bg, panel, line, fg, muted, accent
        Check(Same(theme.background, { p[2].r, p[2].g, p[2].b, 1 }), key .. ": the window is the Panels color")
        Check(Same(theme.bottomFrameBG, { p[2].r, p[2].g, p[2].b, 1 }), key .. ": the quest panels are the Panels color too")
        Check(Same(theme.dividerColor, { p[3].r, p[3].g, p[3].b, 0.6 }), key .. ": the rule between list rows is Borders & Lines at 60%")
        Check(Same(theme.bottomFrameHighlight, { p[6].r, p[6].g, p[6].b, 0.5 }), key .. ": the Accent at half opacity")
        Check(Same(theme.mapPins, { p[6].r, p[6].g, p[6].b, 1 }), key .. ": map pins in the Accent")
        Check(Same(theme.chromeColor, { p[5].r, p[5].g, p[5].b, 0.7 }), key .. ": the cog, grip and scroll thumb are Secondary Text at 70%")
        Check(Same(theme.textColor, { p[4].r, p[4].g, p[4].b }), key .. ": Text")
        Check(theme.tooltip == "|cff" .. Hex(theme.mapPins), key .. ": the tooltip color is the Accent")
        Check(theme.texturePath == TEX .. "DarkMode/", key .. ": RestedXP's own DarkMode logo and icons")
        Check(theme.edges.edge == BORDER and theme.edges.guideName == BORDER, key .. ": Naowh's 1px black window borders")
        Check(not theme.edges.edge:find("RXPGuides", 1, true), key .. ": none of RestedXP's own frame images")
        Check(theme.bgTextures.edge == WHITE and theme.bgTextures.bottom == WHITE and theme.bgTextures.guideName == WHITE,
            key .. ": every frame, the title bar and footer too, has a fill to color")
    end
    Check(Count(seen) == FIXED, "every theme has its own name")
    for _, own in ipairs(RXP_OWN) do
        Check(not list[own] and not seen[own], "RestedXP's own theme " .. own .. " is never overwritten")
    end

    local default, midnight = list["NaowhForever:default"], list["NaowhForever:midnight"]
    Check(Hex(default.background) == "1a1c1f" and Hex(default.bottomFrameBG) == "1a1c1f", "NaowhUI: Panels for the window and the quest panels")
    Check(Hex(default.dividerColor) == "2e3136" and Hex(midnight.dividerColor) == "2a3550", "the rules: NaowhUI's and Midnight's Borders & Lines")
    Check(Hex(default.mapPins) == "0091ed" and default.tooltip == "|cff0091ed", "NaowhUI: the blue Accent")
    Check(Hex(default.textColor) == "f0f1f3", "NaowhUI: Text")
    Check(Hex(midnight.background) == "151c30" and Hex(midnight.mapPins) == "5b8cff", "Midnight: Panels and Accent")
end

-- Another addon's themes stay, and the same table is used.
do
    local other = { name = "RoseGold", author = "Bypass" }
    local existing = { RoseGold = other }
    local env, _, frames = Load({ rxpThemes = true }, true, existing)
    Fire(frames, "NaowhForever")
    Check(env.RXPGuides_Themes == existing and existing.RoseGold == other, "the table and the other addon's theme are kept")
    Check(Count(existing) == REGISTERED + 1, "theirs and all of ours")
end

-- The player's own theme never leaks into the fixed ones.
do
    for _, account in ipairs({
        { rxpThemes = true, themePreset = "crimson" },
        { rxpThemes = true, themePreset = "custom",
          themeColors = { bg = { r = 1, g = 0, b = 0 }, accent = { r = 0, g = 1, b = 0 } } } }) do
        local env, ns, frames = Load(account, true)
        Fire(frames, "NaowhForever")   -- Core applies the player's theme first, then the module registers
        local list = env.RXPGuides_Themes
        Check(Count(list) == REGISTERED, "still the same themes")
        Check(ns.THEME.accent.r ~= 0 or ns.THEME.accent.g ~= 0x91 / 255, "the player's theme is applied to the addon itself")
        Check(Hex(list["NaowhForever:default"].mapPins) == "0091ed" and Hex(list["NaowhForever:default"].background) == "1a1c1f",
            "NaowhUI is still the default theme's colors")
        Check(Hex(list["NaowhForever:crimson"].mapPins) == "ef4b56", "Crimson is still Crimson")
    end
end

-- Naowh (current): the player's own theme, a preset or Custom colors, in one more entry.
do
    local function Current(account)
        local env, ns, frames = Load(account, true)
        Fire(frames, "NaowhForever")
        return env.RXPGuides_Themes["NaowhForever:current"], env.RXPGuides_Themes, ns
    end
    local theme = Current({ rxpThemes = true })
    Check(theme and theme.name == "NaowhForever:current" and theme.displayName == "Naowh (current)"
        and theme.author == "Naowh Forever", "registered under its own name")
    Check(Hex(theme.background) == "1a1c1f" and Hex(theme.mapPins) == "0091ed" and Hex(theme.dividerColor) == "2e3136"
        and Hex(theme.textColor) == "f0f1f3", "with Naowh's default theme: NaowhUI's colors")
    Check(theme.edges.edge == BORDER and theme.texturePath == TEX .. "DarkMode/", "and the 1px black frame")

    local list
    theme, list = Current({ rxpThemes = true, themePreset = "crimson" })
    Check(Hex(theme.background) == "201316" and Hex(theme.bottomFrameBG) == "201316" and Hex(theme.mapPins) == "ef4b56"
        and Hex(theme.dividerColor) == "3d2429" and Hex(theme.textColor) == "f6eff0", "with a preset picked: that preset's colors")
    Check(theme.edges.edge == BORDER and theme.edges.guideName == BORDER, "and the same black frame")
    Check(Hex(list["NaowhForever:crimson"].mapPins) == "ef4b56" and Hex(list["NaowhForever:default"].mapPins) == "0091ed",
        "while the fixed themes are what they were")

    theme, list = Current({ rxpThemes = true, themePreset = "custom",
        themeColors = { bg = { r = 1, g = 0, b = 0 }, accent = { r = 0, g = 1, b = 0 }, fg = { r = 0, g = 0, b = 1 } } })
    Check(Hex(theme.background) == "1a1c1f" and Hex(theme.bottomFrameBG) == "1a1c1f", "with Custom colors: Panels as shipped, for both")
    local panelTheme = Current({ rxpThemes = true, themePreset = "custom", themeColors = { panel = { r = 0, g = 1, b = 0 } } })
    Check(Same(panelTheme.background, { 0, 1, 0, 1 }) and Same(panelTheme.bottomFrameBG, { 0, 1, 0, 1 }), "a Custom Panels pick colors both")
    Check(Same(theme.mapPins, { 0, 1, 0, 1 }) and Same(theme.bottomFrameHighlight, { 0, 1, 0, 0.5 }) and theme.tooltip == "|cff00ff00",
        "and the Accent")
    Check(Same(theme.textColor, { 0, 0, 1 }), "and the Text")
    Check(Hex(theme.dividerColor) == "2e3136", "a color not picked is the addon's own")
    Check(theme.edges.edge == BORDER, "with the black frame")
    Check(Hex(list["NaowhForever:default"].background) == "1a1c1f" and Hex(list["NaowhForever:midnight"].background) == "151c30",
        "and the fixed themes are untouched")

    local env, _, frames = Load({ rxpThemes = true, rxpFont = false, rxpTextColor = false }, true)
    Fire(frames, "NaowhForever")
    local plain = env.RXPGuides_Themes["NaowhForever:current"]
    Check(plain.font == nil and plain.textColor == nil, "the font and the text color switches are honored here too")
end

-- RestedXP Theme: written to RestedXP's own setting when the player picks, and at no other time.
do
    local CURRENT = "NaowhForever:current"
    local NAMES_IN = { CURRENT, "NaowhForever:default", "NaowhForever:crimson", "NaowhForever:slate" }
    -- RestedXP as far as this needs it: its settings, its themes, and a reload that records the theme it showed.
    local function Rxp(active, registered, live)
        local rxp = { settings = { profile = { activeTheme = active, enableThemeLiveReload = live ~= false } },
            reloads = {}, themes = {} }
        if registered then
            for _, name in ipairs(NAMES_IN) do rxp.themes[name] = { name = name } end
        end
        function rxp:ReloadTheme()
            self.reloads[#self.reloads + 1] = self.settings.profile.activeTheme
        end
        return rxp
    end
    local function Session(account, rxp)
        local env, ns, frames, boot = Load(account, true)
        Fire(frames, "NaowhForever")
        env.RXP = rxp
        return env, ns, boot
    end

    -- the choices
    local account = {}
    local _, ns = Load(account, true)
    local values, order = ns.RXPThemeChoices()
    local inOrder = #order == REGISTERED + 1 and order[1] == "" and order[2] == "current"
    for i, key in ipairs(KEYS) do
        if order[i + 2] ~= (key == "" and "default" or key) then inOrder = false end
    end
    Check(inOrder and order[#order] == LAST, "the choices: RestedXP's own, the current theme, NaowhUI, then the presets in their order")
    Check(values[""] == "RestedXP (default)" and values.current == "Current Theme" and values.default == "NaowhUI"
        and values.midnight == "Midnight" and values.rosenoir == "Rose Noir" and values.cottoncandy == "Cotton Candy",
        "the presets named as in Naowh's own Theme dropdown")

    -- without RestedXP up: nothing to read or set
    Check(ns.RXPThemeChoice() == "" and ns.RXPThemesReady() == false, "no RestedXP: no choice, and not ready")
    ns.SetRXPThemeChoice("crimson")
    Check(next(account) == nil, "and a pick stores nothing of ours")

    -- ready: RestedXP's settings and reload, and our themes in its list
    local _, readyNs = Session({}, Rxp("RXP Blue", true))
    Check(readyNs.RXPThemesReady() == true, "RestedXP up with our themes: ready")
    for _, broken in ipairs({ {}, Rxp("RXP Blue", false),
            { settings = { profile = {} }, themes = { [CURRENT] = {} } },
            { settings = { profile = {} }, themes = { [NAMES_IN[2]] = {} } },
            { settings = {}, themes = { [NAMES_IN[2]] = {} }, ReloadTheme = function() end } }) do
        local _, brokenNs, brokenBoot = Session({ rxpThemes = true }, broken)
        Check(brokenNs.RXPThemesReady() == false, "not ready without the settings, the reload or our themes")
        Login(brokenBoot)
        brokenNs.SetRXPThemeChoice("current")
        brokenNs.SetRXPThemeChoice("")
    end
    Check(true, "RestedXP without the settings, themes or reload: no error")

    -- the choice reads what RestedXP is on
    local function ChoiceOf(active, registered)
        local _, choiceNs = Session({}, Rxp(active, registered))
        return choiceNs.RXPThemeChoice()
    end
    Check(ChoiceOf("RXP Blue", true) == "" and ChoiceOf("RXP Gold", true) == "", "on a theme of RestedXP's: RestedXP (default)")
    Check(ChoiceOf(CURRENT, true) == "current" and ChoiceOf("NaowhForever:default", true) == "default"
        and ChoiceOf("NaowhForever:crimson", true) == "crimson", "on one of ours: that one")
    Check(ChoiceOf(CURRENT, false) == "" and ChoiceOf("NaowhForever:bogus", true) == "" and ChoiceOf(5, true) == ""
        and ChoiceOf(nil, true) == "", "one that is not in its list, or not a theme: RestedXP (default)")

    -- a pick puts RestedXP on the theme through its own reload, which does not say a reload is needed
    local rxp = Rxp("RXP Blue", true)
    local _, pickedNs = Session({ rxpThemes = true }, rxp)
    Check(pickedNs.SetRXPThemeChoice("current") == nil, "the current theme picked: nothing more is needed")
    Check(rxp.settings.profile.activeTheme == CURRENT and #rxp.reloads == 1 and rxp.reloads[1] == CURRENT
        and pickedNs.RXPThemeChoice() == "current", "RestedXP is on it, through one reload that saw it")
    pickedNs.SetRXPThemeChoice("current")
    Check(#rxp.reloads == 1, "the same pick again does not reload")
    pickedNs.SetRXPThemeChoice("slate")
    Check(rxp.settings.profile.activeTheme == "NaowhForever:slate" and #rxp.reloads == 2, "another theme: it takes over")
    pickedNs.SetRXPThemeChoice("default")
    Check(rxp.settings.profile.activeTheme == "NaowhForever:default" and #rxp.reloads == 3, "NaowhUI too")
    pickedNs.SetRXPThemeChoice("")
    Check(rxp.settings.profile.activeTheme == "Default" and #rxp.reloads == 4 and pickedNs.RXPThemeChoice() == "",
        "RestedXP (default): RestedXP's own theme, which it knows as Default")
    pickedNs.SetRXPThemeChoice("")
    Check(#rxp.reloads == 4, "and again: nothing to do")
    pickedNs.SetRXPThemeChoice("bogus")
    pickedNs.SetRXPThemeChoice(5)
    Check(rxp.settings.profile.activeTheme == "Default" and #rxp.reloads == 4, "an unknown theme is not picked")
    rxp.themes[CURRENT] = nil
    pickedNs.SetRXPThemeChoice("current")
    Check(rxp.settings.profile.activeTheme == "Default" and #rxp.reloads == 4, "nor one that RestedXP does not have")
    Check(rxp.settings.profile.enableThemeLiveReload == true, "RestedXP's live reload setting is never written")

    -- RestedXP (default) leaves a theme the player chose in RestedXP alone
    rxp = Rxp("RXP Gold", true)
    _, pickedNs = Session({ rxpThemes = true }, rxp)
    pickedNs.SetRXPThemeChoice("")
    Check(rxp.settings.profile.activeTheme == "RXP Gold" and #rxp.reloads == 0, "RestedXP (default) on one of RestedXP's own: left as it is")

    -- with RestedXP's live reload off, a reload is what shows the theme
    rxp = Rxp("RXP Blue", true, false)
    _, pickedNs = Session({ rxpThemes = true }, rxp)
    Check(pickedNs.SetRXPThemeChoice("crimson") == "reload", "live reload off: a reload is needed")
    Check(rxp.settings.profile.activeTheme == "NaowhForever:crimson" and #rxp.reloads == 0
        and rxp.settings.profile.enableThemeLiveReload == false, "the theme is set, RestedXP's reload is not run, and its setting is as it was")
    Check(pickedNs.SetRXPThemeChoice("") == "reload" and rxp.settings.profile.activeTheme == "Default", "also back to RestedXP's own")
    Check(pickedNs.SetRXPThemeChoice("") == nil, "and nothing to do says nothing")

    -- no login writes the choice: the player's choice is RestedXP's own setting
    rxp = Rxp("RXP Blue", true)
    local _, _, boot = Session({ rxpThemes = true, rxpTheme = "crimson" }, rxp)
    Login(boot)
    Check(rxp.settings.profile.activeTheme == "RXP Blue" and #rxp.reloads == 0, "login leaves RestedXP's theme as it is")
    rxp = Rxp("NaowhForever:slate", true)
    _, _, boot = Session({ rxpThemes = true }, rxp)
    Login(boot)
    Check(rxp.settings.profile.activeTheme == "NaowhForever:slate" and #rxp.reloads == 0, "also on one of ours")

    -- in combat the reload (which scales RestedXP's protected target frame) waits for the end of it
    rxp = Rxp("RXP Blue", true)
    local pickEnv, pickNs, pickBoot = Session({ rxpThemes = true }, rxp)
    pickEnv.inCombat = true
    Check(pickNs.SetRXPThemeChoice("current") == nil, "picked in combat: nothing more is needed")
    pickNs.SetRXPThemeChoice("slate")
    Check(rxp.settings.profile.activeTheme == "NaowhForever:slate" and #rxp.reloads == 0, "RestedXP is set, and not reloaded")
    Check(pickBoot.events.PLAYER_REGEN_ENABLED == true, "the end of combat is waited for")
    CombatEnds(pickEnv, pickBoot)
    Check(#rxp.reloads == 1 and rxp.reloads[1] == "NaowhForever:slate", "which reloads once, on the last pick")
    Check(pickBoot.events.PLAYER_REGEN_ENABLED == nil, "and the end of combat is not listened for after that")

    rxp = Rxp(CURRENT, true)
    local idleEnv, idleNs, idleBoot = Session({ rxpThemes = true }, rxp)
    idleEnv.inCombat = true
    idleNs.SetRXPThemeChoice("current")
    idleNs.SetRXPThemeChoice("bogus")
    rxp.themes["NaowhForever:slate"] = nil
    idleNs.SetRXPThemeChoice("slate")
    Check(idleBoot.events.PLAYER_REGEN_ENABLED == nil, "in combat with nothing to do: the end of combat is not waited for")
    rxp = Rxp("RXP Blue", true, false)
    idleEnv, idleNs, idleBoot = Session({ rxpThemes = true }, rxp)
    idleEnv.inCombat = true
    Check(idleNs.SetRXPThemeChoice("slate") == "reload" and idleBoot.events.PLAYER_REGEN_ENABLED == nil,
        "live reload off in combat: the reload is for later, with nothing to wait for")

    -- an error inside RestedXP's reload is not swallowed
    rxp = Rxp("RXP Blue", true)
    function rxp:ReloadTheme() error("boom") end
    local _, failNs = Session({ rxpThemes = true }, rxp)
    Check(not pcall(failNs.SetRXPThemeChoice, "current"), "an error in RestedXP's reload is raised")
end

-- Load order: RestedXP imports the global list as it starts, which is after us unless it loads first.
do
    local function Up(active, saved, live)
        local rxp = { activeTheme = { name = active }, themes = { ["RXP Blue"] = { name = "RXP Blue" } }, registered = {},
            reloads = {}, settings = { profile = { activeTheme = saved, enableThemeLiveReload = live ~= false } } }
        function rxp:RegisterTheme(theme)
            self.registered[#self.registered + 1] = theme.name
            self.themes[theme.name] = theme
        end
        function rxp:ReloadTheme()   -- RestedXP's own does nothing with its live reload setting off
            if self.settings.profile.enableThemeLiveReload then self.reloads[#self.reloads + 1] = self.settings.profile.activeTheme end
        end
        return rxp
    end
    local function Early(account, rxp, installed)
        local env, ns, frames, boot = Load(account, installed ~= false)
        env.RXP = rxp
        Fire(frames, "NaowhForever")
        return env, ns, boot
    end

    local rxp = Up("RXP Blue", "RXP Blue")
    local env, _, boot = Early({ rxpThemes = true }, rxp)
    table.sort(rxp.registered)
    local want = { "NaowhForever:current" }
    for _, key in ipairs(KEYS) do want[#want + 1] = NameOf(key) end
    table.sort(want)
    Check(table.concat(rxp.registered, ",") == table.concat(want, ","),
        "RestedXP up already: NaowhUI, the presets and the current theme go in through RegisterTheme")
    Check(rxp.themes["NaowhForever:crimson"].author == "Naowh Forever" and rxp.themes["NaowhForever:crimson"].mapPins,
        "as whole themes")
    Check(env.RXPGuides_Themes == nil, "and the global list is not used")
    Login(boot)
    Check(#rxp.reloads == 0, "RestedXP on its own theme: no reload at login")

    rxp = Up("RXP Blue", "RXP Blue")
    env = Early({}, rxp)
    Check(#rxp.registered == 0 and env.RXPGuides_Themes == nil, "themes off: nothing goes in")
    rxp = Up("RXP Blue", "RXP Blue")
    env = Early({ rxpThemes = true }, rxp, false)
    Check(#rxp.registered == 0 and env.RXPGuides_Themes == nil, "RestedXP not installed: nothing goes in")

    -- still starting (its table is there, its first theme is not): the global list, which it imports
    rxp = Up("RXP Blue", "NaowhForever:crimson")
    rxp.activeTheme = nil
    env, _, boot = Early({ rxpThemes = true }, rxp)
    Check(#rxp.registered == 0 and Count(env.RXPGuides_Themes) == REGISTERED, "RestedXP not started yet: the global list, as before")
    Login(boot)
    Check(#rxp.reloads == 0, "and no reload: it imports them itself")

    -- up before us and saved on one of our themes: it had fallen back, so it is reloaded onto it once
    rxp = Up("RXP Blue", "NaowhForever:crimson")
    _, _, boot = Early({ rxpThemes = true }, rxp)
    Check(#rxp.reloads == 0, "the reload waits for login")
    Login(boot)
    Check(#rxp.reloads == 1 and rxp.reloads[1] == "NaowhForever:crimson" and rxp.settings.profile.activeTheme == "NaowhForever:crimson",
        "saved on a theme of ours that it fell back from: reloaded onto it, with its own setting as it was")
    rxp = Up("RXP Blue", "NaowhForever:crimson")
    _, _, boot = Early({ rxpThemes = true }, rxp)
    rxp.activeTheme = rxp.themes["NaowhForever:crimson"]
    Login(boot)
    Check(#rxp.reloads == 0, "already on it: no reload")
    rxp = Up("RXP Blue", "RXP Gold")
    _, _, boot = Early({ rxpThemes = true }, rxp)
    Login(boot)
    Check(#rxp.reloads == 0, "saved on a theme of RestedXP's: no reload")
    rxp = Up("RXP Blue", "NaowhForever:bogus")
    _, _, boot = Early({ rxpThemes = true }, rxp)
    Login(boot)
    Check(#rxp.reloads == 0, "saved on one of ours that is not there: no reload")
    rxp = Up("RXP Blue", "NaowhForever:crimson", false)
    _, _, boot = Early({ rxpThemes = true }, rxp)
    Login(boot)
    Check(#rxp.reloads == 0, "RestedXP's live reload off: RestedXP's own reload does nothing, and none is forced")

    rxp = Up("RXP Blue", "NaowhForever:crimson")
    local combatEnv
    combatEnv, _, boot = Early({ rxpThemes = true }, rxp)
    combatEnv.inCombat = true
    Login(boot)
    Check(#rxp.reloads == 0 and boot.events.PLAYER_REGEN_ENABLED == true and not boot.events.PLAYER_LOGIN, "login in combat: the reload waits for its end")
    CombatEnds(combatEnv, boot)
    Check(#rxp.reloads == 1 and next(boot.events) == nil, "and happens once")
end

-- The font and the text color.
do
    local NAOWH = "Interface\\AddOns\\NaowhForever\\Media\\Fonts\\Naowh.ttf"
    local function Fonts(account, fonts)
        local env, ns, frames = Load(account, true, nil, fonts)
        Fire(frames, "NaowhForever")
        return env.RXPGuides_Themes, ns
    end
    local function AllHave(list, path)
        for _, key in ipairs(KEYS) do
            if list[NameOf(key)].font ~= path then return false end
        end
        return list["NaowhForever:current"].font == path
    end

    local list = Fonts({ rxpThemes = true }, {})
    Check(AllHave(list, NAOWH), "the Addon Font by default is the Naowh font, in every theme")
    list = Fonts({ rxpThemes = true, uiFont = "Fira" }, { Fira = "Fonts\\Fira.ttf" })
    Check(AllHave(list, "Fonts\\Fira.ttf"), "a font picked as the Addon Font is the one in every theme")
    local _, ns = Fonts({ rxpThemes = true }, {})
    list = Fonts({ rxpThemes = true, uiFont = ns.BLIZZARD_FONT }, {})
    Check(AllHave(list, "Fonts\\FRIZQT__.TTF"), "Blizzard Default is the game's own font")
    list = Fonts({ rxpThemes = true, uiFont = "Gone" }, {})
    Check(AllHave(list, NAOWH), "a font that is not there falls back to the Naowh font, as in the addon")
    list = Fonts({ rxpThemes = true }, nil)
    Check(AllHave(list, "Fonts\\FRIZQT__.TTF"), "without LibSharedMedia, the game's own font")

    -- Asked this early, a font from an addon that loads later is not there yet; the addon's own answer must not
    -- be spoiled by that, or its windows would lose the player's font for the whole session.
    local fonts = {}
    local env, laterNs, frames = Load({ rxpThemes = true, uiFont = "Later" }, true, nil, fonts)
    Fire(frames, "NaowhForever")
    fonts.Later = "Fonts\\Later.ttf"
    Check(laterNs.UIFontPath() == "Fonts\\Later.ttf", "the addon's own font is still found once the later addon has loaded")
    Check(env.RXPGuides_Themes[NameOf("")].font == NAOWH, "while the RestedXP theme took the fallback at the time")

    local plain = Fonts({ rxpThemes = true, rxpFont = false }, {})
    local plainFont = true
    for _, key in ipairs(KEYS) do
        if plain[NameOf(key)].font ~= nil or plain[NameOf(key)].textColor == nil then plainFont = false end
    end
    Check(plainFont, "the font switched off: no font in any theme, and the text color is still there")
    local plainText = Fonts({ rxpThemes = true, rxpTextColor = false }, {})
    local noText = true
    for _, key in ipairs(KEYS) do
        if plainText[NameOf(key)].textColor ~= nil or plainText[NameOf(key)].font ~= NAOWH then noText = false end
    end
    Check(noText, "the text color switched off: none in any theme, and the font is still there")

    local colors = Fonts({ rxpThemes = true }, {})
    Check(Hex(colors[NameOf("")].textColor) == "f0f1f3" and Hex(colors[NameOf("crimson")].textColor) == "f6eff0",
        "the basic text color: NaowhUI's and Crimson's Text")
end

-- The waypoint arrow.
do
    local IMAGE = "Interface/AddOns/RXPGuides/Textures/DarkMode/rxp_navigation_arrow-1"
    local function Arrow()
        local a = { orientation = 1.25, sets = {}, tints = {} }
        a.texture = { path = IMAGE }
        function a.texture:GetTexture() return self.path end
        function a.texture:SetTexture(path) self.path = path; a.sets[#a.sets + 1] = path end
        function a.texture:SetVertexColor(...) a.tints[#a.tints + 1] = { ... } end
        function a.texture:SetRotation() end   -- RestedXP's own call, which the hook follows
        a.texture.points = "all"               -- how RestedXP makes it: SetAllPoints()
        function a.texture:ClearAllPoints() self.points = {} end
        function a.texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function a.texture:SetAllPoints() self.points = "all" end
        function a:GetSize() return a.w or 32, a.h or 32 end
        a.text = { point = { "TOP", a, "BOTTOM", 0, -5 } }   -- as RestedXP anchors it
        function a.text:GetPoint() return unpack(self.point) end
        function a.text:SetPoint(...) self.point = { ... } end
        a.text.hides, a.text.shows = 0, 0
        function a.text:Hide() self.hidden = true; self.hides = self.hides + 1 end
        function a.text:Show() self.hidden = false; self.shows = self.shows + 1 end
        function a:HookScript(name, fn) a.scripts = a.scripts or {}; a.scripts[name] = fn end
        function a:GetFrameLevel() return 3 end
        function a.UpdateVisuals() end
        return a
    end
    local function Start(account, active)
        local env, _, frames, boot = Load(account, true)
        env.RXPG_ARROW = Arrow()
        Fire(frames, "NaowhForever")
        local list = env.RXPGuides_Themes
        env.RXP = { activeTheme = active and list[active] or { name = "RXP Blue" } }
        return env, frames, boot, list
    end
    local function Layers(frames, arrow)
        local out = {}
        for _, f in ipairs(frames) do
            if f.parent == arrow then out[#out + 1] = f end
        end
        return out
    end

    local env, frames, boot, list = Start({ rxpThemes = true }, "NaowhForever:rosenoir")
    local arrow = env.RXPG_ARROW
    Check(#env.hooked == 0 and #Layers(frames, arrow) == 0, "nothing is hooked or built before login")
    Login(boot)
    Check(#env.hooked == 2 and env.hooked[1][1] == arrow and env.hooked[1][2] == "UpdateVisuals",
        "RestedXP's UpdateVisuals is hooked")
    Check(env.hooked[2][1] == arrow.texture and env.hooked[2][2] == "SetRotation", "and so is its arrow's SetRotation")
    local layers = Layers(frames, arrow)
    Check(#layers == 1, "one layer, a child of the arrow")
    local layer = layers[1]
    Check(layer.level == 4 and layer.shown == true, "above the arrow, and shown")
    local color, mask = layer.colorRegion, layer.maskRegion
    Check(color.blend == "ADD" and Same(color.rgba, { 1, 1, 1, 1 }), "an added layer, white until its gradient colors it")
    local function Close(got, want)
        for i = 1, 4 do if math.abs(got[i] - want[i]) > 1e-9 then return false end end
        return true
    end
    local function Gradient(accent)
        return { accent[1] * 0.72, accent[2] * 0.72, accent[3] * 0.72, 0.9 },
            { accent[1] + (1 - accent[1]) * 0.22, accent[2] + (1 - accent[2]) * 0.22,
              accent[3] + (1 - accent[3]) * 0.22, 0.9 }
    end
    local deep, light = Gradient(list["NaowhForever:rosenoir"].mapPins)
    Check(color.gradient[1] == "VERTICAL" and Close(color.gradient[2], deep) and Close(color.gradient[3], light),
        "Rose Noir's Accent, deeper at the bottom and lighter at the top")
    Check(Hex(color.gradient[2]) == "b84475" and Hex(color.gradient[3]) == "ff82b6", "and those are the colors, pinned")
    Check(color.masks and color.masks[1] == mask, "clipped by the mask")
    Check(mask.path == IMAGE and mask.wrapH == "CLAMPTOBLACKADDITIVE" and mask.wrapV == "CLAMPTOBLACKADDITIVE",
        "the mask is the arrow's own image")
    Check(mask.rotation == 1.25, "turned the way the arrow is")
    env.hooked[2][3](arrow.texture, 0.5)
    Check(mask.rotation == 0.5, "and it turns with the arrow")
    Check(arrow.texture.path == IMAGE, "RestedXP's own image is untouched")

    env.RXP.activeTheme = { name = "DarkMode" }
    env.hooked[1][3](arrow)
    Check(layer.shown == false and #Layers(frames, arrow) == 1, "a theme of RestedXP's: the layer is hidden, not rebuilt")
    env.RXP.activeTheme = list["NaowhForever:midnight"]
    arrow.texture.path = "Interface/AddOns/RXPGuides/Textures/Other/rxp_navigation_arrow-1"
    env.hooked[1][3](arrow)
    deep, light = Gradient(list["NaowhForever:midnight"].mapPins)
    Check(layer.shown == true and Close(color.gradient[2], deep) and Close(color.gradient[3], light)
        and mask.path == arrow.texture.path and #Layers(frames, arrow) == 1,
        "back to one of ours: shown, in Midnight's Accent, from the arrow's image of the moment")

    env, frames, boot = Start({ rxpThemes = true }, nil)
    Login(boot)
    Check(#env.hooked == 1 and #Layers(frames, env.RXPG_ARROW) == 0, "RestedXP's own theme: no layer is built")
    env.RXP.activeTheme = { name = "xNaowhForever:default", mapPins = { 1, 0, 0, 1 } }
    env.hooked[1][3]()
    Check(#Layers(frames, env.RXPG_ARROW) == 0, "only a name that starts with ours counts")

    local off, _, offBoot = Start({}, nil)
    Check(next(offBoot.events) == nil and #off.hooked == 0, "off: no event left, nothing hooked")
    Login(offBoot)
    Check(#off.hooked == 0, "off: login does nothing")

    local e2, _, f2, b2 = Load({ rxpThemes = true }, true)
    Fire(f2, "NaowhForever"); Login(b2)
    Check(#e2.hooked == 0 and next(b2.events) == nil, "no arrow frame: nothing to do")
    e2, _, f2, b2 = Load({ rxpThemes = true }, true)
    e2.RXPG_ARROW = { UpdateVisuals = function() end }
    Fire(f2, "NaowhForever"); Login(b2)
    Check(#e2.hooked == 0, "no arrow texture: nothing is hooked")
    e2, _, f2, b2 = Load({ rxpThemes = true }, true)
    e2.RXPG_ARROW = Arrow()
    Fire(f2, "NaowhForever"); Login(b2)
    Check(#e2.hooked == 1 and #Layers(f2, e2.RXPG_ARROW) == 0, "no RXP table: hooked, and nothing built")
    e2, _, f2, b2 = Load({ rxpThemes = true }, true)
    local fixed = Arrow()
    fixed.texture.SetRotation = nil
    e2.RXPG_ARROW = fixed
    Fire(f2, "NaowhForever")
    e2.RXP = { activeTheme = e2.RXPGuides_Themes["NaowhForever:default"] }
    Login(b2)
    Check(#e2.hooked == 1 and #Layers(f2, fixed) == 0, "an arrow that cannot be turned: no layer")
    e2, _, f2, b2 = Load({ rxpThemes = true }, false)
    e2.RXPG_ARROW = Arrow()
    Fire(f2, "NaowhForever"); Login(b2)
    Check(#e2.hooked == 0, "RestedXP not installed: nothing is hooked")

    local account = {}
    local _, styleNs = Load(account, true)
    Check(styleNs.RXPArrowStyle() == "layer" and account.rxpArrow == nil, "the arrow is a layer by default")
    styleNs.SetRXPArrowStyle("image")
    Check(account.rxpArrow == "image" and styleNs.RXPArrowStyle() == "image", "the image style is stored")
    styleNs.SetRXPArrowStyle("off")
    Check(account.rxpArrow == "off" and styleNs.RXPArrowStyle() == "off", "so is off")
    styleNs.SetRXPArrowStyle("layer")
    Check(account.rxpArrow == nil and styleNs.RXPArrowStyle() == "layer", "the default is stored as nothing")
    styleNs.SetRXPArrowStyle("bogus")
    Check(account.rxpArrow == nil, "an unknown style is not stored")
    account.rxpArrow = "junk"
    Check(styleNs.RXPArrowStyle() == "layer", "an unknown saved style reads as the layer")

    local OURS = "Interface\\AddOns\\NaowhForever\\Media\\rxp_arrow.tga"
    local imageEnv, imageFrames, imageBoot, imageList = Start({ rxpThemes = true, rxpArrow = "image" }, "NaowhForever:rosenoir")
    local drawn = imageEnv.RXPG_ARROW
    Login(imageBoot)
    Check(#imageEnv.hooked == 1 and #Layers(imageFrames, drawn) == 0, "image: only UpdateVisuals is hooked, and no layer is built")
    Check(drawn.texture.path == OURS and #drawn.sets == 1, "image: Naowh's arrow image is on the arrow")
    local tint = drawn.tints[#drawn.tints]
    Check(Hex(tint) == "ff5fa2" and tint[4] == 1, "image: in Rose Noir's Accent")
    imageEnv.RXP.activeTheme = { name = "DarkMode" }
    drawn.texture.path = IMAGE
    imageEnv.hooked[1][3](drawn)
    Check(#drawn.sets == 1 and drawn.texture.path == IMAGE, "a theme of RestedXP's: its image is left on the arrow")
    Check(Same(drawn.tints[#drawn.tints], { 1, 1, 1, 1 }), "and the tint is cleared")
    imageEnv.RXP.activeTheme = imageList["NaowhForever:midnight"]
    imageEnv.hooked[1][3](drawn)
    tint = drawn.tints[#drawn.tints]
    Check(drawn.texture.path == OURS and #drawn.sets == 2 and Hex(tint) == "5b8cff", "back to one of ours: the image and Midnight's Accent")

    local styles = imageEnv.NaowhForever
    styles.SetRXPArrowStyle("layer")
    Check(drawn.texture.path == IMAGE and Same(drawn.tints[#drawn.tints], { 1, 1, 1, 1 }),
        "to the layer: RestedXP's own image is back, untinted")
    local switched = Layers(imageFrames, drawn)
    Check(#switched == 1 and switched[1].shown == true, "and the layer is built and shown")
    styles.SetRXPArrowStyle("off")
    Check(switched[1].shown == false and drawn.texture.path == IMAGE, "to off: the layer is hidden, and the arrow is RestedXP's")
    local setsBefore = #drawn.sets
    styles.SetRXPArrowStyle("image")
    Check(drawn.texture.path == OURS and #drawn.sets == setsBefore + 1 and switched[1].shown == false,
        "back to the image: ours is on, and the layer stays hidden")
    styles.SetRXPArrowStyle("off")
    Check(drawn.texture.path == IMAGE, "off hands RestedXP's image back again")

    local shapeAccount = {}
    local _, shapeNs = Load(shapeAccount, true)
    Check(shapeNs.RXPArrowShape() == "kite" and shapeNs.RXPArrowGlow() == false and shapeAccount.rxpArrowShape == nil
        and shapeAccount.rxpArrowGlow == nil, "a kite without a glow by default")
    shapeNs.SetRXPArrowShape("wide")
    Check(shapeAccount.rxpArrowShape == "wide" and shapeNs.RXPArrowShape() == "wide", "the wide kite is stored")
    shapeNs.SetRXPArrowShape("kite")
    Check(shapeAccount.rxpArrowShape == nil and shapeNs.RXPArrowShape() == "kite", "the default shape is stored as nothing")
    shapeNs.SetRXPArrowShape("round")
    Check(shapeAccount.rxpArrowShape == nil, "an unknown shape is not stored")
    shapeAccount.rxpArrowShape = "junk"
    Check(shapeNs.RXPArrowShape() == "kite", "an unknown saved shape reads as the kite")
    shapeNs.SetRXPArrowGlow(true)
    Check(shapeAccount.rxpArrowGlow == true and shapeNs.RXPArrowGlow() == true, "the glow is stored")
    shapeNs.SetRXPArrowGlow(false)
    Check(shapeAccount.rxpArrowGlow == nil and shapeNs.RXPArrowGlow() == false, "no glow is stored as nothing")
    shapeAccount.rxpArrowGlow = "yes"
    Check(shapeNs.RXPArrowGlow() == false, "only true turns the glow on")

    local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
    styles.SetRXPArrowStyle("image")
    for _, want in ipairs({ { "kite", false, "rxp_arrow.tga" }, { "kite", true, "rxp_arrow_glow.tga" },
            { "wide", false, "rxp_arrow_wide.tga" }, { "wide", true, "rxp_arrow_wide_glow.tga" } }) do
        styles.SetRXPArrowShape(want[1])
        styles.SetRXPArrowGlow(want[2])
        Check(drawn.texture.path == MEDIA .. want[3], want[1] .. (want[2] and " with" or " without") .. " a glow: " .. want[3])
    end
    Check(Hex(drawn.tints[#drawn.tints]) == "5b8cff", "and it keeps the Accent")
    styles.SetRXPArrowShape("kite")
    styles.SetRXPArrowGlow(false)
    Check(drawn.texture.path == MEDIA .. "rxp_arrow.tga", "back to the kite without a glow")
    styles.SetRXPArrowShape("wide")
    Check(drawn.texture.path == MEDIA .. "rxp_arrow_wide.tga", "a new shape on its own changes the arrow")
    styles.SetRXPArrowGlow(true)
    Check(drawn.texture.path == MEDIA .. "rxp_arrow_wide_glow.tga", "a new glow on its own changes the arrow")
    styles.SetRXPArrowShape("kite")
    Check(drawn.texture.path == MEDIA .. "rxp_arrow_glow.tga", "and the shape back on its own")
    styles.SetRXPArrowGlow(false)
    styles.SetRXPArrowStyle("layer")
    local setsNow = #drawn.sets
    styles.SetRXPArrowShape("kite")
    styles.SetRXPArrowGlow(false)
    Check(#drawn.sets == setsNow and drawn.texture.path == IMAGE, "with the layer as the style, a new shape or glow leaves RestedXP's image alone")
    styles.SetRXPArrowStyle("off")
    setsNow = #drawn.sets
    styles.SetRXPArrowShape("wide")
    Check(#drawn.sets == setsNow and drawn.texture.path == IMAGE, "and so does RestedXP's own arrow")
    styles.SetRXPArrowShape("kite")

    -- Naowh's arrow is drawn larger than the frame RestedXP gives its own: 0.9 times, and 0.9 / 0.76 times with a glow
    -- (whose kite fills 76% of the image), around the same center. Anything else gets RestedXP's anchors back.
    local function Spread(frame)
        local pts = frame.texture.points
        if pts == "all" then return "all" end
        local tl, br = pts[1], pts[2]
        if #pts ~= 2 or tl[1] ~= "TOPLEFT" or tl[2] ~= frame or tl[3] ~= "TOPLEFT" or br[1] ~= "BOTTOMRIGHT"
                or br[2] ~= frame or br[3] ~= "BOTTOMRIGHT" then return nil end
        return tl[4], tl[5], br[4], br[5]
    end
    local function Near(a, b) return math.abs(a - b) < 1e-9 end
    local function Overflow(frame, scale)
        local x1, y1, x2, y2 = Spread(frame)
        if type(x1) ~= "number" then return false end
        local d = 32 * (scale - 1) / 2
        return Near(x1, -d) and Near(y1, d) and Near(x2, d) and Near(y2, -d)
    end
    local sizeEnv, _, sizeBoot = Start({ rxpThemes = true, rxpArrow = "image" }, "NaowhForever:rosenoir")
    local sized = sizeEnv.RXPG_ARROW
    Check(Spread(sized) == "all", "before login, RestedXP's own anchors")
    Login(sizeBoot)
    Check(Overflow(sized, 0.9), "the Naowh arrow image is 0.9 times the frame, around the same center")
    sizeEnv.NaowhForever.SetRXPArrowGlow(true)
    Check(Overflow(sized, 0.9 / 0.76), "with a glow, larger still, so the kite stays the same size")
    sizeEnv.NaowhForever.SetRXPArrowShape("wide")
    Check(Overflow(sized, 0.9 / 0.76), "and the shape does not change that")
    sizeEnv.NaowhForever.SetRXPArrowGlow(false)
    Check(Overflow(sized, 0.9), "without it, back to 0.9")
    sized.w, sized.h = 64, 64
    sized.scripts.OnSizeChanged()
    local x1 = Spread(sized)
    Check(type(x1) == "number" and Near(x1, -64 * (0.9 - 1) / 2), "RestedXP's Arrow Size resizing the frame: the image follows it")
    sized.w, sized.h = 32, 32
    sized.scripts.OnSizeChanged()
    sizeEnv.NaowhForever.SetRXPArrowStyle("layer")
    Check(Spread(sized) == "all", "with the layer as the style, RestedXP's own anchors are back")
    sized.w, sized.h = 64, 64
    sized.scripts.OnSizeChanged()
    Check(Spread(sized) == "all", "and a resize does not move them")
    sizeEnv.NaowhForever.SetRXPArrowStyle("image")
    sizeEnv.NaowhForever.SetRXPArrowStyle("off")
    Check(Spread(sized) == "all", "nor does RestedXP's own arrow")

    -- the size: a percent of RestedXP's frame, 90 by default, in steps of 5 from 60 to 200
    local sizeAccount = {}
    local _, sizeNs = Load(sizeAccount, true)
    local lo, hi, step = sizeNs.RXPArrowSizeRange()
    Check(lo == 60 and hi == 200 and step == 5, "from 60 to 200 percent in steps of 5")
    Check(sizeNs.RXPArrowSize() == 90 and sizeAccount.rxpArrowSize == nil, "90 by default")
    sizeNs.SetRXPArrowSize(150)
    Check(sizeAccount.rxpArrowSize == 150 and sizeNs.RXPArrowSize() == 150, "a size is stored")
    sizeNs.SetRXPArrowSize(90)
    Check(sizeAccount.rxpArrowSize == nil, "the default is stored as nothing")
    sizeNs.SetRXPArrowSize(153)
    Check(sizeAccount.rxpArrowSize == 155, "rounded to a step")
    sizeNs.SetRXPArrowSize(10)
    Check(sizeAccount.rxpArrowSize == 60, "kept above the smallest")
    sizeNs.SetRXPArrowSize(900)
    Check(sizeAccount.rxpArrowSize == 200, "and below the largest")
    sizeNs.SetRXPArrowSize("bogus")
    Check(sizeAccount.rxpArrowSize == nil, "something that is not a number is not stored")
    sizeAccount.rxpArrowSize = "junk"
    Check(sizeNs.RXPArrowSize() == 90, "and an unreadable saved size reads as 90")
    sizeAccount.rxpArrowSize = 7
    Check(sizeNs.RXPArrowSize() == 60, "a saved size out of range is brought back into it")
    sizeAccount.rxpArrowSize = 153
    Check(sizeNs.RXPArrowSize() == 155, "and a saved size between steps is rounded to one")

    -- it sizes the image at once, with or without a glow, as the kite is the same size either way
    sized.w, sized.h = 32, 32
    sizeEnv.NaowhForever.SetRXPArrowStyle("image")
    sizeEnv.NaowhForever.SetRXPArrowSize(150)
    Check(Overflow(sized, 1.5), "150 percent: the image is 1.5 times the frame")
    sizeEnv.NaowhForever.SetRXPArrowGlow(true)
    Check(Overflow(sized, 1.5 / 0.76), "and with a glow, larger by what the glow takes")
    sizeEnv.NaowhForever.SetRXPArrowGlow(false)
    sizeEnv.NaowhForever.SetRXPArrowSize(60)
    Check(Overflow(sized, 0.6), "60 percent: smaller than the frame, around the same center")
    sizeEnv.NaowhForever.SetRXPArrowSize(90)
    Check(Overflow(sized, 0.9), "and back to 90")
    sizeEnv.NaowhForever.SetRXPArrowStyle("layer")
    sizeEnv.NaowhForever.SetRXPArrowSize(200)
    Check(Spread(sized) == "all", "with the layer as the style, a size leaves RestedXP's anchors alone")
    sizeEnv.NaowhForever.SetRXPArrowSize(90)

    -- the distance text goes lower by what the image reaches below the frame, and 4 more; RestedXP's -5 comes back
    local function TextAt(frame)
        local t = frame.text.point
        return t[1] == "TOP" and t[2] == frame and t[3] == "BOTTOM" and t[4] == 0 and t[5]
    end
    local function Lower(frame, below, gap) return Near(TextAt(frame), -(5 + below + (gap or 4))) end
    sized.w, sized.h = 32, 32
    local sz = sizeEnv.NaowhForever
    sz.SetRXPArrowStyle("image")
    sz.SetRXPArrowSize(90)
    Check(Lower(sized, 0), "an image smaller than the frame: the text is 4 lower")
    sz.SetRXPArrowSize(150)
    Check(Lower(sized, 8), "150 percent reaches 8 below the frame: the text is that much and 4 lower")
    sz.SetRXPArrowGlow(true)
    Check(Lower(sized, 16 * (1.5 / 0.76 - 1)), "and with a glow, by what the larger image reaches")
    sz.SetRXPArrowGlow(false)
    sized.w, sized.h = 64, 64
    sized.scripts.OnSizeChanged()
    Check(Lower(sized, 16), "RestedXP's Arrow Size resizing the frame: the text follows")
    sized.w, sized.h = 32, 32
    sz.SetRXPArrowSize(90)
    sz.SetRXPArrowGap(10)
    Check(Lower(sized, 0, 10), "a gap of 10 puts the text 10 lower instead of 4")
    sz.SetRXPArrowGap(0)
    Check(Lower(sized, 0, 0), "and a gap of 0 only the image's own overflow")
    sz.SetRXPArrowGap(4)
    sz.SetRXPArrowStyle("layer")
    sz.SetRXPArrowGap(12)
    Check(TextAt(sized) == -5, "with the layer as the style, a gap leaves RestedXP's own place for the text alone")
    sz.SetRXPArrowGap(4)
    Check(TextAt(sized) == -5, "and so does the style itself")
    sz.SetRXPArrowStyle("image")
    sz.SetRXPArrowStyle("off")
    Check(TextAt(sized) == -5, "and with RestedXP's own arrow")
    sz.SetRXPArrowSize(90)

    -- the gap: pixels between the image and the text, 4 by default, from 0 to 20
    local gapAccount = {}
    local _, gapNs = Load(gapAccount, true)
    local gapLo, gapHi = gapNs.RXPArrowGapRange()
    Check(gapLo == 0 and gapHi == 20, "from 0 to 20 pixels")
    Check(gapNs.RXPArrowGap() == 4 and gapAccount.rxpArrowGap == nil, "4 by default")
    gapNs.SetRXPArrowGap(9)
    Check(gapAccount.rxpArrowGap == 9 and gapNs.RXPArrowGap() == 9, "a gap is stored")
    gapNs.SetRXPArrowGap(0)
    Check(gapAccount.rxpArrowGap == 0 and gapNs.RXPArrowGap() == 0, "0 is a gap like any other")
    gapNs.SetRXPArrowGap(4)
    Check(gapAccount.rxpArrowGap == nil, "the default is stored as nothing")
    gapNs.SetRXPArrowGap(7.4)
    Check(gapAccount.rxpArrowGap == 7, "rounded to a whole pixel")
    gapNs.SetRXPArrowGap(-3)
    Check(gapAccount.rxpArrowGap == 0, "kept above 0")
    gapNs.SetRXPArrowGap(99)
    Check(gapAccount.rxpArrowGap == 20, "and below 20")
    gapNs.SetRXPArrowGap("bogus")
    Check(gapAccount.rxpArrowGap == nil, "something that is not a number is not stored")
    gapAccount.rxpArrowGap = "junk"
    Check(gapNs.RXPArrowGap() == 4, "and an unreadable saved gap reads as 4")
    gapAccount.rxpArrowGap = 80
    Check(gapNs.RXPArrowGap() == 20, "a saved gap out of range is brought back into it")
    gapAccount.rxpArrowGap = 7.4
    Check(gapNs.RXPArrowGap() == 7, "and a saved gap that is not whole is rounded")

    -- the text under the arrow: shown by default; switched off, hidden with any arrow style while one of ours is active
    local textAccount = {}
    local _, textNs = Load(textAccount, true)
    Check(textNs.RXPArrowTextEnabled() == true and textAccount.rxpArrowText == nil, "the arrow text is on by default")
    textNs.SetRXPArrowText(false)
    Check(textNs.RXPArrowTextEnabled() == false and textAccount.rxpArrowText == false, "off is saved as false")
    textNs.SetRXPArrowText(true)
    Check(textAccount.rxpArrowText == nil, "on is saved as nothing")
    for _, style in ipairs({ "layer", "image", "off" }) do
        local textEnv, _, textBoot = Start({ rxpThemes = true, rxpArrow = style }, "NaowhForever:rosenoir")
        local line = textEnv.RXPG_ARROW.text
        Login(textBoot)
        Check(line.hides == 0 and line.hidden == nil, style .. ": the text is left alone while it is on")
        textEnv.NaowhForever.SetRXPArrowText(false)
        Check(line.hidden == true, style .. ": switched off, the text goes at once")
        textEnv.NaowhForever.SetRXPArrowText(false)
        Check(line.hides == 1, style .. ": and is not hidden again")
        textEnv.NaowhForever.SetRXPArrowText(true)
        Check(line.hidden == false and line.shows == 1, style .. ": switched on, it is back")
        textEnv.NaowhForever.SetRXPArrowText(true)
        Check(line.shows == 1, style .. ": and not shown again")
    end
    local hiddenEnv, _, hiddenBoot = Start({ rxpThemes = true, rxpArrowText = false }, "NaowhForever:rosenoir")
    local hiddenLine = hiddenEnv.RXPG_ARROW.text
    Login(hiddenBoot)
    Check(hiddenLine.hidden == true, "switched off from the start: hidden at login")
    hiddenEnv.RXP.activeTheme = { name = "DarkMode" }
    hiddenEnv.hooked[1][3](hiddenEnv.RXPG_ARROW)
    Check(hiddenLine.hidden == false, "a theme of RestedXP's: its text is shown")
    hiddenEnv.RXP.activeTheme = hiddenEnv.RXPGuides_Themes["NaowhForever:midnight"]
    hiddenEnv.hooked[1][3](hiddenEnv.RXPG_ARROW)
    Check(hiddenLine.hidden == true, "and one of ours again: hidden again")
    local ownEnv, _, ownBoot = Start({ rxpThemes = true, rxpArrowText = false }, nil)
    Login(ownBoot)
    Check(ownEnv.RXPG_ARROW.text.hides == 0 and ownEnv.RXPG_ARROW.text.hidden == nil, "RestedXP's own theme: the text is never touched")

    local wideEnv, _, wideBoot = Start({ rxpThemes = true, rxpArrow = "image", rxpArrowShape = "wide", rxpArrowGlow = true },
        "NaowhForever:rosenoir")
    Login(wideBoot)
    Check(wideEnv.RXPG_ARROW.texture.path == MEDIA .. "rxp_arrow_wide_glow.tga", "saved wide with a glow: that image at login")

    local quietEnv, quietFrames, quietBoot = Start({ rxpThemes = true, rxpArrow = "off" }, "NaowhForever:rosenoir")
    Login(quietBoot)
    Check(#quietEnv.hooked == 1 and #Layers(quietFrames, quietEnv.RXPG_ARROW) == 0 and #quietEnv.RXPG_ARROW.sets == 0
        and #quietEnv.RXPG_ARROW.tints == 0, "off: RestedXP's own arrow, untouched")

    for _, style in ipairs({ "layer", "image", "off" }) do
        local e3, f3, b3 = Start({ rxpThemes = true, rxpArrow = style }, nil)
        Login(b3)
        Check(#Layers(f3, e3.RXPG_ARROW) == 0 and #e3.RXPG_ARROW.sets == 0 and #e3.RXPG_ARROW.tints == 0,
            style .. ": with RestedXP's own theme the arrow is left alone")
    end
end

-- The title bar and footer.
do
    local function Banner()
        local b = { alphas = {} }
        function b:SetTexture() end   -- RestedXP's own call, which the hook follows
        function b:SetAlpha(alpha) self.alphas[#self.alphas + 1] = alpha; self.alpha = alpha end
        return b
    end
    local function Start(account, active)
        local env, _, frames, boot = Load(account, true)
        env.RXPFrame = { GuideName = { bg = Banner() }, Footer = { bg = Banner() } }
        Fire(frames, "NaowhForever")
        env.RXP = { activeTheme = active and env.RXPGuides_Themes[active] or { name = "RXP Blue" } }
        return env, boot
    end
    local function Hook(env, banner)
        for _, h in ipairs(env.hooked) do
            if h[1] == banner and h[2] == "SetTexture" then return h[3] end
        end
    end

    local env, boot = Start({ rxpThemes = true }, "NaowhForever:crimson")
    local title, footer = env.RXPFrame.GuideName.bg, env.RXPFrame.Footer.bg
    Check(#env.hooked == 0 and #title.alphas == 0 and #footer.alphas == 0, "nothing is hooked or hidden before login")
    Login(boot)
    Check(#env.hooked == 2 and Hook(env, title) and Hook(env, footer), "both banners' SetTexture are hooked")
    Check(title.alpha == 0 and footer.alpha == 0, "and both are hidden at once")
    title.alpha = 1
    Hook(env, title)(title, TEX .. "DarkMode/rxp-banner")
    Check(title.alpha == 0 and footer.alpha == 0, "RestedXP sets its banner again: hidden again")
    env.RXP.activeTheme = { name = "DarkMode" }
    Hook(env, title)(title)
    Check(title.alpha == 1 and footer.alpha == 1, "a theme of RestedXP's: the banners are shown")
    local sets = #title.alphas + #footer.alphas
    Hook(env, footer)(footer)
    Check(#title.alphas + #footer.alphas == sets, "and not set again while they are RestedXP's")
    env.RXP.activeTheme = env.RXPGuides_Themes["NaowhForever:midnight"]
    Hook(env, footer)(footer)
    Check(title.alpha == 0 and footer.alpha == 0, "back to one of ours: hidden again")

    local own, ownBoot = Start({ rxpThemes = true }, nil)
    Login(ownBoot)
    local ownTitle, ownFooter = own.RXPFrame.GuideName.bg, own.RXPFrame.Footer.bg
    Check(Hook(own, ownTitle) and Hook(own, ownFooter), "RestedXP's own theme: the banners are hooked")
    Check(#ownTitle.alphas == 0 and #ownFooter.alphas == 0, "but never touched")
    Hook(own, ownTitle)(ownTitle)
    own.RXP.activeTheme = { name = "xNaowhForever:crimson", mapPins = { 1, 0, 0, 1 } }
    Hook(own, ownFooter)(ownFooter)
    Check(#ownTitle.alphas == 0 and #ownFooter.alphas == 0, "not when RestedXP sets them again, and only a name that starts with ours counts")
    own.RXP.activeTheme = own.RXPGuides_Themes["NaowhForever:slate"]
    Hook(own, ownFooter)(ownFooter)
    Check(ownTitle.alpha == 0 and ownFooter.alpha == 0, "one of ours picked later: hidden")

    local off, offBoot = Start({}, nil)
    Login(offBoot)
    Check(#off.hooked == 0 and #off.RXPFrame.GuideName.bg.alphas == 0 and #off.RXPFrame.Footer.bg.alphas == 0,
        "off: nothing is hooked, nothing is hidden")

    local function Bare(window, active)
        local e, _, f, b = Load({ rxpThemes = true }, true)
        e.RXPFrame = window
        Fire(f, "NaowhForever")
        e.RXP = { activeTheme = active and e.RXPGuides_Themes[active] or nil }
        Login(b)
        return e
    end
    Check(#Bare(nil).hooked == 0 and #Bare({}).hooked == 0, "no window, or one without bars: nothing is hooked")
    Check(#Bare({ GuideName = {}, Footer = {} }).hooked == 0, "bars without banners: nothing is hooked")
    local half = { GuideName = { bg = Banner() }, Footer = { bg = {} } }
    Check(#Bare(half, "NaowhForever:crimson").hooked == 1 and half.GuideName.bg.alpha == 0,
        "the banner that is there is hooked and hidden; the other is skipped")
    local mute = { GuideName = { bg = { SetTexture = function() end } } }
    Check(#Bare(mute, "NaowhForever:crimson").hooked == 1, "a banner that cannot be hidden is hooked and left alone")
end

-- The corner grip image: three diagonal lines, the shortest in the corner.
do
    local f = assert(io.open("Media/rxp_grip.tga", "rb"))
    local data = f:read("*a")
    f:close()
    Check(data:byte(13) + data:byte(14) * 256 == 64 and data:byte(15) + data:byte(16) * 256 == 64 and data:byte(17) == 32, "the grip image is 64 by 64, 32 bits")
    local function A(x, y) return data:byte(18 + ((63 - y) * 64 + x) * 4 + 4) end
    Check(A(36, 36) == 255 and A(44, 44) == 255 and A(53, 53) == 255, "three lines across the diagonal")
    Check(A(40, 40) == 0 and A(49, 49) == 0 and A(5, 5) == 0 and A(5, 60) == 0 and A(60, 5) == 0, "with gaps between them, and the far corner empty")
end

-- The cog, the corner grip and the scroll bar.
do
    local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
    local function Texture(path, w, h)
        local t = { paints = 0, path = path, size = { w or 18, h or 24 }, alpha = 1 }
        function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a }; self.paints = self.paints + 1 end
        function t:SetTexture(p) self.path = p end
        function t:GetTexture() return self.path end
        function t:SetColorTexture(r, g, b, a) self.solid = { r, g, b, a } end
        function t:SetSize(w2, h2) self.size = { w2, h2 } end
        function t:GetSize() return self.size[1], self.size[2] end
        function t:SetAlpha(a) self.alpha = a end
        return t
    end
    local function Button(path)
        local normal = Texture(path)
        return { normal = normal, GetNormalTexture = function() return normal end }
    end
    local function Arrow() return { Normal = Texture(), Highlight = Texture(), Pushed = Texture(), Disabled = Texture() } end
    local function Window()
        return { Footer = { cog = Button("rxp cog"), icon = Button("blizzard grabber") },
            ScrollFrame = { ScrollBar = { ScrollUpButton = Arrow(), ScrollDownButton = Arrow(), thumb = Texture("rxp knob"),
                GetThumbTexture = function(self) return self.thumb end } },
            UpdateScrollBar = function() end }
    end
    local function Start(account, active, window)
        local env, _, frames, boot = Load(account, true)
        env.RXPFrame = window or Window()
        Fire(frames, "NaowhForever")
        env.RXP = { activeTheme = active and env.RXPGuides_Themes[active] or { name = "RXP Blue" } }
        Login(boot)
        return env, env.RXPFrame
    end
    local function Hook(env, window)
        for _, h in ipairs(env.hooked) do
            if h[1] == window and h[2] == "UpdateScrollBar" then return h[3] end
        end
    end
    local function Same3(c, r, g, b) return c and math.abs(c[1] - r) < 1e-6 and math.abs(c[2] - g) < 1e-6 and math.abs(c[3] - b) < 1e-6 and c[4] == 1 end
    local function Same4(c, t) return c and c[1] == t[1] and c[2] == t[2] and c[3] == t[3] and c[4] == t[4] end
    local function Faded(arrow, alpha)
        return arrow.Normal.alpha == alpha and arrow.Highlight.alpha == alpha and arrow.Pushed.alpha == alpha and arrow.Disabled.alpha == alpha
    end

    local env, window = Start({ rxpThemes = true }, "NaowhForever:crimson")
    local theme = env.RXPGuides_Themes["NaowhForever:crimson"]
    local thin = theme.chromeColor
    local cog, grip = window.Footer.cog.normal, window.Footer.icon.normal
    local bar = window.ScrollFrame.ScrollBar
    local up, down, thumb = bar.ScrollUpButton, bar.ScrollDownButton, bar.thumb
    Check(Hook(env, window), "RestedXP's UpdateScrollBar is hooked")
    Check(cog.path == MEDIA .. "cog.tga" and Same4(cog.color, thin), "the cog: Naowh's, in Secondary Text")
    Check(grip.path == MEDIA .. "rxp_grip.tga" and Same4(grip.color, thin), "the corner grip: Naowh's, in Secondary Text")
    Check(thumb.solid and thumb.solid[1] == thin[1] and thumb.solid[2] == thin[2] and thumb.solid[3] == thin[3] and thumb.solid[4] == 0.7
        and thumb.size[1] == 8 and thumb.size[2] == 40, "the scroll thumb: a thin bar in Secondary Text")
    Check(Faded(up, 0) and Faded(down, 0), "the scroll arrows are gone")
    thumb.solid, cog.color = nil, nil
    Hook(env, window)()
    Check(thumb.solid and cog.color, "RestedXP sets its images again: painted again")

    env.RXP.activeTheme = { name = "DarkMode" }
    Hook(env, window)()
    Check(Same3(cog.color, 1, 1, 1) and Same3(grip.color, 1, 1, 1) and grip.path == "blizzard grabber",
        "a theme of RestedXP's: the cog and grip are not tinted, and the grip is the game's again")
    Check(Faded(up, 1) and Faded(down, 1) and thumb.size[1] == 18 and thumb.size[2] == 24, "the arrows are back, and the thumb is its own size")
    local paints = cog.paints + grip.paints
    Hook(env, window)()
    Check(cog.paints + grip.paints == paints and Faded(up, 1), "and not touched again while they are RestedXP's")
    env.RXP.activeTheme = env.RXPGuides_Themes["NaowhForever:midnight"]
    Hook(env, window)()
    Check(cog.color[1] ~= 1 and Faded(down, 0) and thumb.size[1] == 8 and grip.path == MEDIA .. "rxp_grip.tga",
        "back to one of ours: Naowh's look again")

    local own, ownWindow = Start({ rxpThemes = true }, nil)
    local ownBar = ownWindow.ScrollFrame.ScrollBar
    Check(Hook(own, ownWindow) and ownWindow.Footer.cog.normal.paints == 0 and Faded(ownBar.ScrollUpButton, 1) and ownBar.thumb.solid == nil
        and ownBar.thumb.size[1] == 18 and ownWindow.Footer.icon.normal.path == "blizzard grabber", "RestedXP's own theme: hooked, and nothing touched")
    local off, offWindow = Start({}, nil)
    Check(#off.hooked == 0 and offWindow.Footer.cog.normal.paints == 0, "off: nothing is hooked or touched")

    local function Bare(frame)
        local e, _, f, b = Load({ rxpThemes = true }, true)
        e.RXPFrame = frame
        Fire(f, "NaowhForever")
        e.RXP = { activeTheme = e.RXPGuides_Themes["NaowhForever:crimson"] }
        Login(b)
        return e
    end
    Check(#Bare(nil).hooked == 0 and #Bare({}).hooked == 0, "no window, or one without the scroll bar update: nothing is hooked")
    local partial = { Footer = { cog = {}, icon = { GetNormalTexture = function() end } }, ScrollFrame = {}, UpdateScrollBar = function() end }
    Check(#Bare(partial).hooked == 1, "buttons and a bar that are missing or bare: skipped without an error")
    local mute = Window()
    mute.Footer.cog = { GetNormalTexture = function() return {} end }
    mute.ScrollFrame.ScrollBar.thumb = {}
    Check(#Bare(mute).hooked == 1, "images that cannot be changed: left alone")
end

-- The quest list rules.
do
    local function Rule(layer)
        local t = { layer = layer, points = {}, paints = 0, hides = 0 }
        function t:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function t:SetHeight(height) self.height = height end
        function t:SetColorTexture(...) self.rgba = { ... }; self.paints = self.paints + 1 end
        function t:Show() self.shown = true end
        function t:Hide() self.shown = false; self.hides = self.hides + 1 end
        return t
    end
    local function Row()
        local row = { textures = {} }
        function row:CreateTexture(_, layer)
            local t = Rule(layer)
            self.textures[#self.textures + 1] = t
            return t
        end
        return row
    end
    local function Start(account, active, rows)
        local env, _, frames, boot = Load(account, true)
        local pool = {}
        for i = 1, rows do pool[i] = Row() end
        env.RXPFrame = { ScrollChild = { framePool = pool } }
        Fire(frames, "NaowhForever")
        env.RXP = { SetStep = function() end,
            activeTheme = active and env.RXPGuides_Themes[active] or { name = "RXP Blue" } }
        return env, boot, pool
    end
    local function Hook(env)
        for _, h in ipairs(env.hooked) do
            if h[1] == env.RXP and h[2] == "SetStep" then return h[3] end
        end
    end

    local env, boot, pool = Start({ rxpThemes = true }, "NaowhForever:crimson", 2)
    Check(#env.hooked == 0 and #pool[1].textures == 0, "nothing is hooked or drawn before login")
    Login(boot)
    Check(#env.hooked == 1 and Hook(env), "SetStep is hooked")
    for i, row in ipairs(pool) do
        local rule = row.textures[1]
        Check(#row.textures == 1 and rule.layer == "ARTWORK" and rule.height == 1 and rule.shown == true,
            "row " .. i .. ": one 1px rule, shown")
        local left, right = rule.points[1], rule.points[2]
        Check(#rule.points == 2 and left[1] == "BOTTOMLEFT" and left[2] == row and left[3] == "BOTTOMLEFT" and left[4] == 0
            and left[5] == -3 and right[1] == "BOTTOMRIGHT" and right[2] == row and right[3] == "BOTTOMRIGHT"
            and right[4] == 0 and right[5] == -3, "row " .. i .. ": along the far edge of the 3px gap below the row")
        Check(Hex(rule.rgba) == "3d2429" and rule.rgba[4] == 0.6, "row " .. i .. ": Crimson's Borders & Lines at 60%")
    end

    pool[3] = Row()
    Hook(env)()
    Check(#pool[3].textures == 1 and pool[3].textures[1].shown == true, "a new row gets its rule")
    Check(#pool[1].textures == 1 and pool[1].textures[1].paints == 2, "the first row is drawn again, but keeps its one rule")
    local before = pool[1].textures[1].paints
    Hook(env)()
    Hook(env)()
    Check(pool[1].textures[1].paints == before and pool[3].textures[1].paints == 1, "nothing changed: nothing is drawn")

    env.RXP.activeTheme = env.RXPGuides_Themes["NaowhForever:midnight"]
    Hook(env)()
    Check(#pool[2].textures == 1 and Hex(pool[2].textures[1].rgba) == "2a3550", "another of ours: the same rule in Midnight's Borders & Lines")

    env.RXP.activeTheme = { name = "DarkMode" }
    Hook(env)()
    Check(pool[1].textures[1].shown == false and pool[3].textures[1].shown == false, "a theme of RestedXP's: no rules")
    local hides = pool[1].textures[1].hides
    Hook(env)()
    Check(pool[1].textures[1].hides == hides, "and they are not hidden again")
    env.RXP.activeTheme = env.RXPGuides_Themes["NaowhForever:midnight"]
    Hook(env)()
    Check(pool[1].textures[1].shown == true and #pool[1].textures == 1, "back to one of ours: shown again, not made again")

    local own, ownBoot, ownPool = Start({ rxpThemes = true }, nil, 2)
    Login(ownBoot)
    Check(Hook(own) and #ownPool[1].textures == 0, "RestedXP's own theme: hooked, no rules made")
    own.RXP.activeTheme = { name = "xNaowhForever:crimson", dividerColor = { 1, 0, 0, 1 } }
    Hook(own)()
    Check(#ownPool[1].textures == 0, "only a name that starts with ours counts")
    own.RXP.activeTheme = own.RXPGuides_Themes["NaowhForever:slate"]
    Hook(own)()
    Check(#ownPool[1].textures == 1 and ownPool[2].textures[1].shown == true, "one of ours picked later: the rules appear")

    local off, offBoot, offPool = Start({}, nil, 2)
    Login(offBoot)
    Check(#off.hooked == 0 and #offPool[1].textures == 0, "off: nothing is hooked, nothing is drawn")

    local function Bare(window, rxp)
        local e, _, f, b = Load({ rxpThemes = true }, true)
        e.RXPFrame = window
        Fire(f, "NaowhForever")
        e.RXP = rxp and { SetStep = rxp.SetStep, activeTheme = e.RXPGuides_Themes["NaowhForever:crimson"] } or nil
        Login(b)
        return e
    end
    Check(#Bare(nil, {}).hooked == 0, "no window and no SetStep: nothing is hooked")
    Check(#Bare({}, { SetStep = function() end }).hooked == 1, "a window without a list: hooked, nothing drawn, no error")
    Check(#Bare({ ScrollChild = {} }, { SetStep = function() end }).hooked == 1, "a list without rows: no error")
    local empty = { ScrollChild = { framePool = {} } }
    Check(#Bare(empty, { SetStep = function() end }).hooked == 1, "an empty list: no error")
    local plain = { ScrollChild = { framePool = { {} } } }
    Check(#Bare(plain, { SetStep = function() end }).hooked == 1, "a row that cannot make a texture is skipped")
end

-- The two looks that can be switched off.
do
    for _, option in ipairs({ { "RXPFontEnabled", "SetRXPFont", "rxpFont" },
            { "RXPTextColorEnabled", "SetRXPTextColor", "rxpTextColor" } }) do
        local get, set, key = option[1], option[2], option[3]
        local account = {}
        local _, ns = Load(account, true)
        Check(ns[get]() == true and account[key] == nil, get .. ": on by default")
        ns[set](false)
        Check(ns[get]() == false and account[key] == false, get .. ": off is saved as false")
        ns[set](true)
        Check(ns[get]() == true and account[key] == nil, get .. ": on is saved as nothing")
        account[key] = 0
        Check(ns[get]() == true, get .. ": only false turns it off")
    end
end

-- The setting.
do
    local account = {}
    local _, ns = Load(account, true)
    Check(ns.RXPThemesEnabled() == false and account.rxpThemes == nil, "off by default")
    ns.SetRXPThemes(true)
    Check(account.rxpThemes == true and ns.RXPThemesEnabled() == true, "on is stored")
    ns.SetRXPThemes(false)
    Check(account.rxpThemes == nil and ns.RXPThemesEnabled() == false, "off clears it")
    account.rxpThemes = "yes"
    Check(ns.RXPThemesEnabled() == false, "only true turns it on")
end

-- The frame image: a unit of black next to RestedXP's fill, which its backdrop starts 4, 2, 2 and 4 units in.
do
    local f = assert(io.open("Media/rxp_frame.tga", "rb"))
    local data = f:read("*a")
    f:close()
    local w, h = data:byte(13) + data:byte(14) * 256, data:byte(15) + data:byte(16) * 256
    Check(w == 256 and h == 32 and data:byte(17) == 32, "the frame image is 256 by 32, 32 bits")
    -- cells: left, right, top, bottom, then the corners; y runs down
    local function A(cell, x, y) return data:byte(18 + ((h - 1 - y) * w + cell * 32 + x) * 4 + 4) end
    local function On(cell, x, y) return A(cell, x, y) == 255 end
    local function Off(cell, x, y) return A(cell, x, y) == 0 end
    local function Half(cell, x, y) local a = A(cell, x, y) return a > 90 and a < 170 end
    for y = 0, h - 1 do
        Check(Off(0, 5, y) and Half(0, 12, y) and On(0, 13, y) and On(0, 15, y) and Off(0, 16, y), "left piece")
        Check(Off(1, 22, y) and On(1, 23, y) and On(1, 25, y) and Half(1, 26, y) and Off(1, 27, y), "right piece")
        Check(Off(2, 3, y) and Half(2, 5, y) and On(2, 6, y) and On(2, 8, y) and Off(2, 9, y), "top piece")
        Check(Off(3, 15, y) and On(3, 16, y) and On(3, 18, y) and Half(3, 19, y) and Off(3, 25, y), "bottom piece")
    end
    Check(On(4, 14, 31) and On(4, 31, 7) and On(4, 14, 7) and Off(4, 8, 7) and Off(4, 14, 3) and Off(4, 25, 20), "top left")
    Check(On(5, 24, 31) and On(5, 0, 7) and On(5, 24, 7) and Off(5, 29, 7) and Off(5, 24, 3) and Off(5, 10, 20), "top right")
    Check(On(6, 14, 0) and On(6, 31, 17) and On(6, 14, 17) and Off(6, 8, 17) and Off(6, 14, 22) and Off(6, 25, 5), "bottom left")
    Check(On(7, 24, 0) and On(7, 0, 17) and On(7, 24, 17) and Off(7, 29, 17) and Off(7, 24, 22) and Off(7, 10, 5), "bottom right")
end

print("PASS rxp themes: " .. cases .. " checks")
