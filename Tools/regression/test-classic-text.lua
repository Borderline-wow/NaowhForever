-- Run with Lua 5.1 from the repository root: text on the Classic+ skin. Body text in the game's
-- Arial Narrow, headings (buttons, tabs, titles, names) in its Friz Quadrata, HUD text on its
-- default font in Friz too, headings a size up on a shadow, windows on the game's rock, and the
-- help card drawn like the game's tooltip. A picked Addon Font
-- is used for all of it, and the default skin is untouched.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end

local frames
local function New(kind, parent)
    local o = { kind = kind, parent = parent, points = {}, scripts = {}, events = {}, children = {},
        shown = true, w = 0, h = 0 }
    if parent and rawget(parent, "children") then table.insert(parent.children, o) end
    return setmetatable(o, { __index = function(_, k)
        if not k:match("^%u") then return nil end
        return function(self, ...)
            local args = { ... }
            if k == "SetScript" then self.scripts[args[1]] = args[2]
            elseif k == "SetPoint" then self.points[#self.points + 1] = args
            elseif k == "ClearAllPoints" then self.points = {}
            elseif k == "RegisterEvent" then self.events[args[1]] = true
            elseif k == "SetGradient" then self.gradient = { args[2], args[3] }
            elseif k == "SetColorTexture" or k == "SetTextColor" or k == "SetVertexColor" then self.color = args
            elseif k == "SetTexture" then self.texture = args[1]
            elseif k == "SetFont" then self.font, self.size = args[1], args[2]
            elseif k == "SetShadowOffset" then self.shadow = args
            elseif k == "SetFrameStrata" then self.strata = args[1]
            elseif k == "SetShown" then self.shown = args[1] and true or false
            elseif k == "Show" then self.shown = true
            elseif k == "Hide" then self.shown = false
            elseif k == "IsShown" then return self.shown
            elseif k == "SetSize" then self.w, self.h = args[1], args[2]
            elseif k == "SetHeight" then self.h = args[1]
            elseif k == "SetWidth" then self.w = args[1]
            elseif k == "GetHeight" then return self.h
            elseif k == "GetWidth" then return self.w
            elseif k == "GetText" then return self.text or ""
            elseif k == "SetText" then self.text = args[1]
            elseif k == "GetFrameLevel" then return 1
            elseif k == "GetStringWidth" then return 20
            elseif k == "GetStringHeight" then return 12
            elseif k == "GetEffectiveScale" then return 1
            elseif k == "GetObjectType" then return self.kind
            elseif k == "CreateTexture" then return New("Texture", self)
            elseif k == "CreateFontString" then return New("FontString", self)
            end
        end
    end })
end

local function Load(account)
    frames = {}
    local env = setmetatable({
        NaowhForeverDB = { account = account, profiles = {}, charActive = {} },
        CreateFrame = function(kind, _, parent)
            local f = New(kind, parent)
            frames[#frames + 1] = f
            return f
        end,
        CreateColor = function(r, g, b, a)
            local color = { r = r, g = g, b = b, a = a }
            function color:SetRGBA(r2, g2, b2, a2) self.r, self.g, self.b, self.a = r2, g2, b2, a2 end
            return color
        end,
        PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end },
        LibStub = function()
            local lsm = { LOCALE_BIT_ruRU = 1, LOCALE_BIT_western = 2 }
            function lsm:Register() end
            function lsm:Fetch(_, name)
                return ({ ["Friz Quadrata TT"] = "friz", ["Arial Narrow"] = "arial", Naowh = "naowh",
                    Morpheus = "morpheus", Expressway = "expressway" })[name]
            end
            return lsm
        end,
        UIParent = New("Frame"),
    }, { __index = _G })
    env._G = env
    for _, path in ipairs({ "Core/Core.lua", "Shared/Shared.lua", "Shared/Style.lua",
        "Core/Options/Widgets.lua", "Shared/UI/Parts.lua", "Shared/UI/Marks.lua", "Shared/UI/Text.lua", "Shared/UI/Hud.lua",
        "Shared/UI/Timer.lua", "Shared/UI/Share.lua", "Shared/UI/Panels.lua", "Shared/UI/Window.lua", "Shared/UI/Tabs.lua",
        "Shared/UI/SettingsCard.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", env.NaowhForever)
    end
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
    end
    return env.NaowhForever
end

local function Card(ns)
    ns.UI.ShowWidgetTooltip(New("Frame"), "Help")
    for _, f in ipairs(frames) do
        if f.strata == "TOOLTIP" then return f end
    end
end

-- Default skin.
local ns = Load({})
check("default: headings and text in Naowh", ns.Font(New("Frame"), 12, nil, nil, true).font == "naowh"
    and ns.Font(New("Frame"), 12).font == "naowh" and ns.UI.FontPath("") == "naowh")
check("default: the help card on the panel colour", Card(ns).children[1].color[1] == ns.THEME.panel.r)
local heading = ns.Font(New("Frame"), 14, nil, nil, true)
check("default: a heading at its size, no shadow", heading.size == 14 and rawget(heading, "shadow") == nil)
check("default: no pattern behind a window", ns.Shared.Parts.Backdrop(New("Frame")).pattern == nil)

-- Classic+.
ns = Load({ skin = "classic" })
local St = ns.Shared.Style
check("headings in Friz Quadrata", ns.Font(New("Frame"), 12, nil, nil, true).font == "friz")
check("text in Arial Narrow", ns.Font(New("Frame"), 12).font == "arial")
check("HUD text on its default font in Friz", ns.UI.FontPath("") == "friz" and ns.UI.FontPath("Expressway") == "expressway")
heading = ns.Font(New("Frame"), 14, nil, nil, true)
check("a heading a size up, on a black shadow", heading.size == 14 + St.CLASSIC_HEADING_STEP
    and heading.shadow[1] == St.CLASSIC_HEADING_SHADOW and heading.shadow[2] == -St.CLASSIC_HEADING_SHADOW)
check("body text at its size", ns.Font(New("Frame"), 14).size == 14)
local backdrop = ns.Shared.Parts.Backdrop(New("Frame"))
backdrop:Paint(0.5)
check("the game's rock behind a window, darkened, fading with its opacity", backdrop.pattern.texture == St.CLASSIC_PATTERN
    and backdrop.pattern.color[1] == St.CLASSIC_PATTERN_SHADE and backdrop.pattern.color[4] == St.CLASSIC_PATTERN_ALPHA * 0.5)
local card = Card(ns)
check("the help card dark blue, like the game's tooltip", card.children[1].color[1] == St.CLASSIC_TIP_RGB.r
    and card.children[1].color[4] == St.CLASSIC_TIP_ALPHA)

-- A picked Addon Font is used for headings and text alike.
ns = Load({ skin = "classic", uiFont = "Expressway" })
check("a picked Addon Font for both", ns.Font(New("Frame"), 12, nil, nil, true).font == "expressway"
    and ns.Font(New("Frame"), 12).font == "expressway")

print("classic text: " .. checks .. " checks passed")
