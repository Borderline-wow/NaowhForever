-- Run with Lua 5.1 from the repository root: ns.Button on the Classic+ skin. Red, lit from the
-- top, in a gold rim with gold text; brighter under the mouse, turned over while pressed, and its
-- outer edge still the picked marker. On the default skin it is as it was.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end

local frames
local function New(kind)
    local o = { kind = kind, points = {}, scripts = {}, events = {} }
    return setmetatable(o, { __index = function(_, k)
        return function(self, ...)
            local args = { ... }
            if k == "SetScript" then self.scripts[args[1]] = args[2]
            elseif k == "GetScript" then return self.scripts[args[1]]
            elseif k == "RegisterEvent" then self.events[args[1]] = true
            elseif k == "SetGradient" then self.gradient = { args[2], args[3] }
            elseif k == "SetColorTexture" or k == "SetTextColor" then self.color = args
            elseif k == "GetFrameLevel" then return 1
            elseif k == "GetEffectiveScale" then return 1
            elseif k == "GetObjectType" then return self.kind
            elseif k == "IsMouseOver" then return self.mouseOver
            elseif k == "CreateTexture" then return New("Texture")
            elseif k == "CreateFontString" then return New("FontString")
            end
        end
    end })
end

local function Load(account)
    frames = {}
    local env = setmetatable({
        NaowhForeverDB = { account = account, profiles = {}, charActive = {} },
        CreateFrame = function(kind)
            local f = New(kind)
            frames[#frames + 1] = f
            return f
        end,
        CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
        PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end },
    }, { __index = _G })
    env._G = env
    for _, path in ipairs({ "Core/NaowhForever_Core.lua", "Shared/Shared.lua", "Shared/Style.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", env.NaowhForever)
    end
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
    end
    return env.NaowhForever
end

local function Is(color, rgb) return color.r == rgb.r and color.g == rgb.g and color.b == rgb.b end
local function Fill(bg, state) return Is(bg.gradient[2], state[1]) and Is(bg.gradient[1], state[2]) end

-- The default skin: the flat button, no press handling.
local ns = Load({})
local btn = ns.Button(New("Frame"), "Close", 80, 24)
check("default: no pressed look", btn.scripts.OnMouseDown == nil and rawget(btn._bg, "gradient") == nil)
check("default: the text in the theme's text colour", btn.label.color[1] == ns.THEME.fg.r)

-- Classic+.
ns = Load({ skin = "classic" })
local St = ns.Shared.Style
local states = St.CLASSIC_BUTTON_RGB
btn = ns.Button(New("Frame"), "Close", 80, 24)
local bg = btn._bg
check("red, lit from the top", Fill(bg, states.rest))
check("gold text", btn.label.color[1] == ns.THEME.accent.r and btn.label.color[2] == ns.THEME.accent.g)
btn.scripts.OnEnter(btn)
check("under the mouse: brighter", Fill(bg, states.hover))
btn.scripts.OnMouseDown(btn)
check("pressed: turned over", Fill(bg, states.down))
btn.mouseOver = true
btn.scripts.OnMouseUp(btn)
check("let go over it: bright again", Fill(bg, states.hover))
btn.mouseOver = false
btn.scripts.OnMouseDown(btn)
btn.scripts.OnMouseUp(btn)
check("let go off it: at rest", Fill(bg, states.rest))
btn.scripts.OnLeave(btn)
check("mouse gone: at rest", Fill(bg, states.rest))

-- The outer edge keeps marking a picked button, as callers set it.
ns.AccentBorder(btn)
check("a main action keeps its accent edge", btn._rest == ns.THEME.accent)

print("classic buttons: " .. checks .. " checks passed")
