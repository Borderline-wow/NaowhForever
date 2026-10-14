-- Run with Lua 5.1 from the repository root: the game's full-color icons in place of the line
-- glyphs, on the Forever skin only.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local missing = {}   -- texture paths this client lacks
local function New(kind)
    local o = { kind = kind, points = {}, textures = {}, strings = {} }
    return setmetatable(o, { __index = function(_, k)
        return function(self, ...)
            local args = { ... }
            if k == "SetPoint" then self.points[#self.points + 1] = args
            elseif k == "SetVertexColor" then self.color = args
            elseif k == "SetTexture" then
                self.texture = args[1]
                return not missing[args[1]]
            elseif k == "SetTexCoord" then self.coords = args
            elseif k == "SetDesaturated" then self.desaturated = args[1]
            elseif k == "CreateTexture" then
                local t = New("Texture")
                self.textures[#self.textures + 1] = t
                return t
            elseif k == "CreateFontString" then
                local t = New("FontString")
                self.strings[#self.strings + 1] = t
                return t
            end
        end
    end })
end

local ns = {
    THEME = { panel = { r = 0, g = 0, b = 0 } },
    Shared = { Parts = {} },
    UI = {},
    L = function(text) return text end,
}

local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function() return New("Frame") end,
}, { __index = _G })
env._G = env
for _, path in ipairs({ "Shared/Style.lua", "Shared/UI/Window.lua" }) do
    local f = assert(io.open(path, "rb"))
    local chunk = assert(loadstring(f:read("*a"), path)); f:close()
    setfenv(chunk, env)
    chunk("NaowhForever", ns)
end
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local icon = New("Texture")
check("default skin: the glyph stays", Parts.ClassicIcon(icon, "map") == false and rawget(icon, "texture") == nil)
ns.foreverSkin = true
check("Forever: the game's icon for a glyph", Parts.ClassicIcon(icon, "map") == true
    and icon.texture == St.CLASSIC_ICON_PATH .. St.CLASSIC_ICONS.map)
check("cropped inside its edge, in its own colors", icon.coords[1] == St.CLASSIC_ICON_CROP
    and icon.coords[2] == 1 - St.CLASSIC_ICON_CROP and icon.desaturated == false and icon.color[1] == 1)
check("a name with no icon keeps its glyph", Parts.ClassicIcon(New("Texture"), "nothing") == false)
missing[St.CLASSIC_ICON_PATH .. St.CLASSIC_ICONS.hearth] = true
check("an icon this client lacks keeps its glyph", Parts.ClassicIcon(New("Texture"), "hearth") == false)
check("the Top Bar's launchers have icons", St.CLASSIC_ICONS.NaowhForeverJournal and St.CLASSIC_ICONS.friends)

print("forever icons: " .. checks .. " checks passed")
