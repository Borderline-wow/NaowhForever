-- Run with Lua 5.1 from the repository root: the settings controls on the Classic+ skin. A
-- switch is a sunken check box with the game's tick, a slider a dark groove filled bronze to gold
-- with a gem to drag, and dropdowns and text boxes are cut into the panel. The default skin is
-- untouched.
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
        return function(self, ...)
            local args = { ... }
            if k == "SetScript" then self.scripts[args[1]] = args[2]
            elseif k == "SetPoint" then self.points[#self.points + 1] = args
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
        "Core/NaowhForever_Widgets.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", env.NaowhForever)
    end
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
    end
    return env.NaowhForever
end

local function Find(list, test)
    for _, x in ipairs(list) do if test(x) then return x end end
end
-- ns.Sunken's edge: a frame holding two lit lines.
local function SunkenOn(frame, St)
    return Find(frame.children, function(c)
        local lit = 0
        for _, t in ipairs(c.children) do
            if t.kind == "Texture" and t.color and t.color[1] == St.CLASSIC_BEVEL_RGB.r then lit = lit + 1 end
        end
        return lit == 2
    end) ~= nil
end

-- Default skin.
local ns = Load({})
local on = true
local t = ns.UI.BuildToggleControl(New("Frame"), nil, function() return on end, function(v) on = v end)
check("default: the switch's track and knob", #t.children == 2 and t.children[1].texture:find("toggle_track", 1, true))

-- Classic+.
ns = Load({ skin = "classic" })
local St = ns.Shared.Style
on = true
local paint
t, paint = ns.UI.BuildToggleControl(New("Frame"), nil, function() return on end, function(v) on = v end)
local box = Find(t.children, function(c) return c.kind == "Frame" end)
local tick = Find(box.children, function(c) return c.texture == St.CLASSIC_CHECK end)
check("a check box at the switch's right end, as high as the switch", box.points[1][1] == "RIGHT" and box.w == 20)
check("sunken into the panel", SunkenOn(box, St))
check("on: the game's tick", tick and tick.shown)
t.scripts.OnClick(t)
check("a click turns it off and hides the tick", on == false and not tick.shown)
paint(true)
check("Paint still shows a state", tick.shown)

local value = 50
local track = ns.UI.BuildSliderCore(New("Frame"), 200, 4, 12, 40, 20, 12, 1, 0, 100, 1,
    function() return value end, function(v) value = v end)
check("the fill runs bronze to gold", track.fill.gradient and track.fill.gradient[2].r == St.CLASSIC_FILL_RGB[1].r
    and track.fill.gradient[1].r == St.CLASSIC_FILL_RGB[2].r)
check("a gold gem to drag", track.thumb.texture == St.GEM and track.thumb.color[1] == St.CLASSIC_GOLD_RGB.r)
check("its groove and value box cut into the panel", Find(track.children, function(c) return c.kind == "Frame" and SunkenOn(c, St) end) ~= nil
    and SunkenOn(track.valueBox, St))

local dd = ns.UI.BuildDropdownControl(New("Frame"), 160, nil, { a = "A" }, { "a" }, function() return "a" end, function() end)
check("a dropdown cut into the panel", SunkenOn(dd, St))
local edit = ns.NewEditBox(New("Frame"))
check("a text box cut into the panel", SunkenOn(edit, St))

print("classic controls: " .. checks .. " checks passed")
