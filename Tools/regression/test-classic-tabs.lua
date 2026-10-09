-- Run with Lua 5.1 from the repository root: tabs, section headers and settings cards on the
-- Classic+ skin. The picked tab is lit bronze under a gold line along its top and the others
-- read in gold; a section header has a gold gem and a gold rule that fades out; cards get the
-- bronze line of the game's option boxes. The default skin is untouched.
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
        CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
        PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end },
        UIParent = New("Frame"),
    }, { __index = _G })
    env._G = env
    for _, path in ipairs({ "Core/NaowhForever_Core.lua", "Shared/Shared.lua", "Shared/Style.lua",
        "Core/NaowhForever_Widgets.lua", "Shared/Parts.lua", "Shared/Window.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", env.NaowhForever)
    end
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
    end
    return env.NaowhForever
end

local function Tabs(ns)
    local bar = ns.Shared.Parts.Tabs(New("Frame"), 300, { { key = "a", label = "A" }, { key = "b", label = "B" } },
        function() end)
    ns.Shared.Parts.PaintTabs(bar, "a")
    return bar
end

-- Default skin.
local ns = Load({})
local bar = Tabs(ns)
check("default: the picked tab's line along the bottom", bar.buttons[1].line.points[1][1] == "BOTTOMLEFT")
check("default: the others in the muted colour", bar.buttons[2].text.color[1] == ns.THEME.muted.r)

-- Classic+.
ns = Load({ skin = "classic" })
local St = ns.Shared.Style
bar = Tabs(ns)
local picked, other = bar.buttons[1], bar.buttons[2]
check("the picked tab lit bronze from the top", picked.fill.gradient and picked.fill.gradient[2].r == St.CLASSIC_TAB_RGB[1].r
    and picked.fill.gradient[1].r == St.CLASSIC_TAB_RGB[2].r and picked.fill.shown)
check("under a gold line along its top", picked.line.points[1][1] == "TOPLEFT" and picked.line.color[1] == St.CLASSIC_GOLD_RGB.r)
check("the others in gold, unlit", other.text.color[1] == ns.THEME.accent.r and not other.fill.shown)
check("the picked one in the text colour", picked.text.color[1] == ns.THEME.fg.r)

local function Holds(frame, rgb)
    for _, c in ipairs(frame.children) do
        if c.kind == "Texture" and c.color and c.color[1] == rgb.r and c.color[2] == rgb.g then return true end
        if c.kind == "Frame" and Holds(c, rgb) then return true end
    end
    return false
end
local card = New("Frame")
ns.Shared.Parts.ClassicBox(card)
check("an option box's bronze line inside the edge", Holds(card, St.CLASSIC_BRONZE_RGB))

local parent = New("Frame")
local header = ns.UI.Widgets:SectionHeader(parent, "COLORS", 0)
local gem, gold, rule = nil, nil, nil
for _, c in ipairs(header.children) do
    if c.texture == St.GEM then gem = c end
    if c.kind == "FontString" and c.color and c.color[1] == ns.THEME.accent.r then gold = c end
    if c.gradient then rule = c end
end
check("a section header: a gem, its name in gold, a fading gold rule", gem and gold and rule
    and rule.gradient[1].a == 1 and rule.gradient[2].a == 0)

print("classic tabs: " .. checks .. " checks passed")
