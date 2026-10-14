-- Naowh's step icons for RestedXP (Core/Integrations/RestedXP/Icons.lua), run against the real Core with
-- RestedXP's icon table stood in for by a plain one. Run with Lua 5.1 from the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end
local coreSource = Read("Core/Core.lua")
local featuresSource = Read("Core/Features.lua")
local themesSource = Read("Core/Integrations/RestedXP/Themes.lua")
local settingsSource = Read("Core/Integrations/RestedXP/WindowSettings.lua")
local iconsSource = Read("Core/Integrations/RestedXP/Icons.lua")

local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end

local ART = "Interface\\AddOns\\NaowhForever\\Core\\Integrations\\RestedXP\\Media\\Icons\\"

local function Frame()
    local f = { events = {}, scripts = {} }
    setmetatable(f, { __index = function(_, key)
        if type(key) == "string" and key:find("^%u") then return function() end end
    end })
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    return f
end

-- The game with our addon loaded: opts.loaded is RestedXP being up already, opts.installed its being there at all.
local function World(account, opts)
    opts = opts or {}
    local w = { frames = {} }
    local env = {}
    env._G = env
    env.UIParent = Frame()
    env.CreateFrame = function()
        local f = Frame()
        w.frames[#w.frames + 1] = f
        return f
    end
    env.C_AddOns = {
        DoesAddOnExist = function(name) return opts.installed ~= false and name == "RXPGuides" end,
        IsAddOnLoaded = function(name) return opts.loaded == true and name == "RXPGuides" end,
    }
    env.C_Timer = { After = function() end }
    env.hooksecurefunc = function() end
    env.NaowhForeverDB = { account = account, profiles = {}, charActive = {} }
    setmetatable(env, { __index = _G })
    for _, part in ipairs({ { coreSource, "Core" }, { featuresSource, "Features" } }) do
        local chunk = assert(loadstring(part[1], part[2]))
        setfenv(chunk, env)
        chunk("NaowhForever")
    end
    local ns = env.NaowhForever
    for _, part in ipairs({ { themesSource, "Themes" }, { settingsSource, "WindowSettings" }, { iconsSource, "Icons" } }) do
        local chunk = assert(loadstring(part[1], part[2]))
        setfenv(chunk, env)
        chunk("NaowhForever")
    end
    w.env, w.ns = env, ns
    w.watcher = w.frames[#w.frames]
    return w
end

-- RestedXP's table as it is when its files have loaded
local function Icons()
    return {
        accept = "|TInterface/GossipFrame/AvailableQuestIcon:0|t",
        turnin = "|TInterface/GossipFrame/ActiveQuestIcon:0|t",
        ["goto"] = "|TInterface/MINIMAP/POIICONS:0:0:0:0:128:128:63:72:0:4|t",
        groundgoto = "|TInterface/MINIMAP/POIICONS:0:0:0:0:128:128:63:72:0:4|t",
        flygoto = "|TInterface/MINIMAP/POIICONS:0:0:0:0:128:128:63:72:0:4|t",
        explore = "|TInterface/MINIMAP/POIICONS:0:0:0:0:128:128:63:72:0:4|t",
        acceptmultiple = "|TInterface/GossipFrame/AvailableQuestIcon:0|t",
        vendor = "|TInterface/GossipFrame/BankerGossipIcon:0|t",
        custom = "|TInterface/Anywhere/Else:0|t",
        scenario = 12345,
    }
end

local function Boot(w, name) w.watcher.scripts.OnEvent(w.watcher, "ADDON_LOADED", name) end

local function Expected(style, glyph, r, g, b)
    return ("|T%s%s\\%s.tga:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(ART, style, glyph, r, g, b)
end

-- off to start: nothing is listened for, and nothing is changed
do
    local w = World({})
    w.env.RXP = { icons = Icons() }
    Check(w.ns.RXPIconStyle() == "", "no style to start")
    Check(next(w.watcher.events) == "ADDON_LOADED", "waiting for the addon to load")
    Boot(w, "NaowhForever")
    Check(next(w.watcher.events) == nil, "off: it listens for nothing")
    Boot(w, "RXPGuides")
    w.ns.RXPIconsApply()
    Check(w.env.RXP.icons["goto"]:find("POIICONS", 1, true) and w.env.RXP.icons.accept:find("GossipFrame", 1, true),
        "and RestedXP's icons are as they were")
end

-- a style, with RestedXP loading after: its icons are replaced as it loads, tinted with the accent
do
    local w = World({ rxpWindow = true, rxpIconStyle = "line" })
    w.ns.THEME.accent = { r = 0.5, g = 0.25, b = 1 }
    w.ns.THEME.accentSoft = { r = 0, g = 1, b = 0.5 }
    w.ns.THEME.fg = { r = 0.2, g = 0.4, b = 0.6 }
    w.env.RXP = { icons = Icons() }
    Boot(w, "NaowhForever")
    Check(w.watcher.events.ADDON_LOADED == true, "a style: it waits for RestedXP to load")
    Boot(w, "SomeOtherAddon")
    Check(w.env.RXP.icons.accept:find("GossipFrame", 1, true) and w.watcher.events.ADDON_LOADED == true,
        "another addon loading changes nothing")
    Boot(w, "RXPGuides")
    local icons = w.env.RXP.icons
    Check(icons.accept == Expected("line", "accept", 128, 64, 255), "accept: Naowh's, in the accent")
    Check(icons.turnin == Expected("line", "turnin", 128, 64, 255), "turnin")
    Check(icons.vendor == Expected("line", "vendor", 128, 64, 255), "vendor: in the accent too")
    local gotoIcon = Expected("line", "goto", 128, 64, 255)
    Check(icons["goto"] == gotoIcon and icons.groundgoto == gotoIcon and icons.flygoto == gotoIcon
        and icons.explore == gotoIcon,
        "the icons RestedXP made from goto are goto's too, in the same color")
    Check(icons.acceptmultiple == icons.accept, "and acceptmultiple is accept's")
    Check(icons.custom == "|TInterface/Anywhere/Else:0|t" and icons.scenario == 12345,
        "a key that is not ours, and one that is not text, are left alone")
    Check(icons.fp == nil and icons.hs == nil, "a key RestedXP does not have is not added")
    Check(next(w.watcher.events) == nil, "and it listens for nothing more")
    local before = icons.accept
    w.ns.RXPIconsApply()
    Check(icons.accept == before, "applied again it is the same")
end

-- RestedXP loaded before us, and the filled style: done at once
do
    local w = World({ rxpWindow = true, rxpIconStyle = "filled" }, { loaded = true })
    w.ns.THEME.accent = { r = 1, g = 1, b = 1 }
    w.env.RXP = { icons = Icons() }
    Boot(w, "NaowhForever")
    Check(w.env.RXP.icons.accept == Expected("filled", "accept", 255, 255, 255), "RestedXP up already: done at once")
    Check(next(w.watcher.events) == nil, "and it listens for nothing")
end

-- no RestedXP: nothing is listened for
do
    local w = World({ rxpWindow = true, rxpIconStyle = "line" }, { installed = false })
    Boot(w, "NaowhForever")
    Check(next(w.watcher.events) == nil, "RestedXP not installed: it listens for nothing")
end

-- a table that raises as it is written raises, so the game reports it
do
    local locked = setmetatable({}, { __index = function() return "|Tx:0|t" end,
        __newindex = function() error("locked") end })
    local raising = World({ rxpWindow = true, rxpIconStyle = "line" })
    raising.env.RXP = { icons = locked }
    Boot(raising, "NaowhForever")
    local ok, problem = pcall(Boot, raising, "RXPGuides")
    Check(not ok and tostring(problem):find("locked", 1, true), "a table that raises: the error is the game's to show")
end

-- the setting: only a style is kept
do
    local account = {}
    account.rxpWindow = true
    local w = World(account)
    w.ns.SetRXPIconStyle("filled")
    Check(account.rxpIconStyle == "filled" and w.ns.RXPIconStyle() == "filled", "a style is kept")
    w.ns.SetRXPIconStyle("rainbow")
    Check(account.rxpIconStyle == nil and w.ns.RXPIconStyle() == "", "one that is not a style is not")
    w.ns.SetRXPIconStyle("line")
    w.ns.SetRXPIconStyle("")
    Check(account.rxpIconStyle == nil, "and RestedXP's own is not stored")
    account.rxpIconStyle = "junk"
    Check(w.ns.RXPIconStyle() == "", "a saved value that is not a style is RestedXP's own")
end

-- the style is the window's: with it off there is none, and it comes back as the window does
do
    local account = { rxpWindow = true, rxpIconStyle = "line" }
    local w = World(account)
    Check(w.ns.RXPIconStyle() == "line", "the window on: the style as it is kept")
    w.ns.RXPWindowEnabled = function() return false end
    Check(w.ns.RXPIconStyle() == "" and account.rxpIconStyle == "line",
        "the window not wished for: RestedXP's own, and the style kept")
    w.ns.RXPWindowEnabled = function() return true end
    Check(w.ns.RXPIconStyle() == "line", "and wished for: the style is back")
    w.env.RXP = { icons = Icons() }
    w.ns.RXPWindowEnabled = function() return false end
    Boot(w, "NaowhForever")
    Check(next(w.watcher.events) == nil and w.env.RXP.icons.accept:find("GossipFrame", 1, true),
        "the window off at load: nothing is listened for and RestedXP's icons stay")
end

-- a glyph's file, for what RestedXP draws itself (the placeholders of its target buttons)
do
    local w = World({ rxpWindow = true, rxpIconStyle = "filled" })
    Check(w.ns.RXPIconTexture("gossip") == ART .. "filled\\gossip.tga" and w.ns.RXPIconTexture("combat") == ART .. "filled\\combat.tga",
        "a glyph of ours: its file in the style picked")
    Check(w.ns.RXPIconTexture("nothing") == nil and w.ns.RXPIconTexture(5) == nil and w.ns.RXPIconTexture(nil) == nil,
        "one that is not ours, or not text: none")
    w.ns.SetRXPIconStyle("line")
    Check(w.ns.RXPIconTexture("gossip") == ART .. "line\\gossip.tga", "and in the other style")
    w.ns.SetRXPIconStyle(nil)
    Check(w.ns.RXPIconTexture("gossip") == nil, "no style: none, and RestedXP's own is left")
    w.ns.RXPWindowEnabled = function() return false end
    w.ns.SetRXPIconStyle("line")
    Check(w.ns.RXPIconTexture("gossip") == nil, "and with the window not wished for")
end

-- the color: the window's accent, the theme's to start, and what the Naowh window asks of a line of text
do
    local account = {}
    local w = World(account)
    local T = w.ns.THEME
    T.accent = { r = 0.5, g = 0.25, b = 1 }
    local function Is(r, g, b)
        local cr, cg, cb = w.ns.RXPIconColor()
        return math.abs(cr - r) < 1e-9 and math.abs(cg - g) < 1e-9 and math.abs(cb - b) < 1e-9
    end
    Check(Is(0.5, 0.25, 1), "the theme's accent to start")
    T.accent = { r = 0.9, g = 0.1, b = 0.1 }
    Check(Is(0.9, 0.1, 0.1), "and it follows the theme")
    local asked
    w.ns.RXPWindowColor = function(name)
        asked = name
        return 0, 1, 0, 1
    end
    Check(Is(0, 1, 0) and asked == "accent", "with the window there: its Accent Color")
    w.ns.RXPWindowColor = function() return 1, 0, 0, 1 end

    local text = ("|T%saccept.tga:0|t"):format(ART .. "filled\\")
    local path, r, g, b = w.ns.RXPIconLook(text)
    Check(path == ART .. "filled\\accept.tga" and r == 1 and g == 0 and b == 0,
        "an icon of ours: its file, and the color as it is now")
    w.ns.RXPWindowColor = function() return 0, 0, 1, 1 end
    local _, _, _, blue = w.ns.RXPIconLook(text)
    Check(blue == 1, "and as it is changed")
    Check(w.ns.RXPIconLook("|TInterface/GossipFrame/AvailableQuestIcon:0|t") == nil
        and w.ns.RXPIconLook("") == nil and w.ns.RXPIconLook(nil) == nil and w.ns.RXPIconLook(12) == nil,
        "RestedXP's own, and what is not text, are not ours")
    Check(w.ns.RXPIconLook(("|T%srainbow\\accept.tga:0|t"):format(ART)) == nil, "a style that is not one is not ours")
    local _, tr, tg, tb = w.ns.RXPIconLook(("|T%sline\\goto.tga:0|t"):format(ART))
    local _, cr, cg, cb = w.ns.RXPIconLook(("|T%sline\\clock.tga:0|t"):format(ART))
    Check(tr == 0 and tg == 0 and tb == 1 and cr == 0 and cg == 0 and cb == 1, "every glyph has it: travel's and the rest's too")
end

-- the icons inside a guide's text: the two RestedXP puts in most of its lines
do
    local w = World({ rxpWindow = true, rxpIconStyle = "line" })
    local T = w.ns.THEME
    T.accent = { r = 0.5, g = 0.25, b = 1 }
    T.accentSoft = { r = 0, g = 1, b = 0.5 }
    local bubble = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"
    local line = bubble .. " Talk to |cffffd100Shindrell|r"
    Check(w.ns.RXPIconText(line) == Expected("line", "gossip", 128, 64, 255) .. " Talk to |cffffd100Shindrell|r",
        "the speech bubble in a line is ours, in the quest color, and the rest is as it was")
    Check(w.ns.RXPIconText("|TInterface\\worldmap\\ChatBubble_64Grey.blp:20|t x")
        == Expected("line", "gossip", 128, 64, 255) .. " x", "whatever its case and slashes")
    Check(w.ns.RXPIconText("|TInterface/cursor/crosshair/interact.blp:20|t Use")
        == Expected("line", "interact", 128, 64, 255) .. " Use", "and so is the interact cursor")
    Check(w.ns.RXPIconText(bubble .. bubble) == Expected("line", "gossip", 128, 64, 255):rep(2),
        "each one in a line is")
    local other = "|T134419:0|t Kill |T133970:0|t"
    Check(w.ns.RXPIconText(other) == other, "an icon that is not one of them is left alone")
    Check(w.ns.RXPIconText("|TInterface/Anywhere/Else.blp:20|t") == "|TInterface/Anywhere/Else.blp:20|t",
        "and a path we do not know")
    Check(w.ns.RXPIconText("") == "" and w.ns.RXPIconText(nil) == nil and w.ns.RXPIconText(5) == 5,
        "what is not text comes back as it was")
    w.ns.SetRXPIconStyle(nil)
    Check(w.ns.RXPIconText(line) == line, "no style: the line is as RestedXP has it")
    w.ns.SetRXPIconStyle("filled")
    T.accent = { r = 1, g = 1, b = 1 }
    Check(w.ns.RXPIconText(bubble) == Expected("filled", "gossip", 255, 255, 255), "the other style, and as the theme is")
end

-- every glyph there is a key for has its file, in both styles
do
    local w = World({})
    local seen, count = {}, 0
    for key, glyph in pairs(w.ns.RXPIconGlyphs()) do
        Check(type(key) == "string" and type(glyph) == "string", "a key and a glyph name: " .. tostring(key))
        for _, style in ipairs({ "line", "filled" }) do
            local path = w.ns.RXPIconPath(style, glyph):gsub("^Interface\\AddOns\\NaowhForever\\", ""):gsub("\\", "/")
            local f = io.open(path, "rb")
            Check(f ~= nil, "the file is there: " .. path)
            local data = f:read("*a"); f:close()
            Check(#data == 18 + 64 * 64 * 4, "a 64 by 64 32-bit image: " .. path)
            count = count + 1
        end
        seen[glyph] = true
    end
    for _, glyph in pairs(w.ns.RXPIconInline()) do
        for _, style in ipairs({ "line", "filled" }) do
            local path = w.ns.RXPIconPath(style, glyph):gsub("^Interface\\AddOns\\NaowhForever\\", ""):gsub("\\", "/")
            local f = io.open(path, "rb")
            Check(f ~= nil, "the file is there: " .. path)
            f:close()
        end
        seen[glyph] = true
    end
    local glyphs = 0
    for _ in pairs(seen) do glyphs = glyphs + 1 end
    Check(glyphs == 29 and count >= 56, "29 glyphs, each in two styles")
end

print("PASS rxp icons: " .. cases .. " checks")
