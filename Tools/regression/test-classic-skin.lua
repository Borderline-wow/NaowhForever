-- Run with Lua 5.1 from the repository root: the Classic+ skin's window frame. Outside the
-- window's own black edge, one-pixel rings of gold, bronze and a black rim; a gem on each
-- corner; and the title on a plate over the top edge, in the title font.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local missing = {}   -- texture paths this client lacks
local function New(kind)
    local o = { kind = kind, points = {}, textures = {}, strings = {} }
    return setmetatable(o, { __index = function(_, k)
        return function(self, ...)
            local args = { ... }
            if k == "SetPoint" then self.points[#self.points + 1] = args
            elseif k == "SetText" then self.text = args[1]
            elseif k == "GetText" then return self.text
            elseif k == "SetVertexColor" then self.color = args
            elseif k == "SetTexture" then
                self.texture = args[1]
                return not missing[args[1]]
            elseif k == "SetTexCoord" then self.coords = args
            elseif k == "SetDesaturated" then self.desaturated = args[1]
            elseif k == "SetFont" then self.font = args[1]
            elseif k == "SetWidth" then self.width = args[1]
            elseif k == "SetHeight" then self.height = args[1]
            elseif k == "GetFrameLevel" then return 5
            elseif k == "GetStringWidth" then return 100
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

local insets, borders, frames = {}, {}, {}
local ns = {
    THEME = { panel = { r = 0, g = 0, b = 0 } },
    Shared = { Parts = {} },
    UI = {},
    L = function(text) return text end,
    TitleFontPath = function() return "morpheus" end,
}
function ns.PixelInset(region, n, relativeTo) insets[#insets + 1] = { region = region, n = n, to = relativeTo } end
function ns.Border(frame, color) borders[#borders + 1] = { frame = frame, color = color } end
function ns.Solid(parent) return parent:CreateTexture() end

local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function(_, _, parent)
        local f = New("Frame")
        f.parent = parent
        frames[#frames + 1] = f
        return f
    end,
}, { __index = _G })
env._G = env
for _, path in ipairs({ "Shared/Style.lua", "Shared/UI/Window.lua" }) do
    local f = assert(io.open(path, "rb"))
    local chunk = assert(loadstring(f:read("*a"), path)); f:close()
    setfenv(chunk, env)
    chunk("NaowhForever", ns)
end
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local window = New("Frame")
Parts.ClassicTrim(window)
check("five rings round the window", #insets == 5)
for i, inset in ipairs(insets) do
    check("ring " .. i .. " steps one pixel further out", inset.n == -i and inset.to == window)
end
check("gold first, then bronze, then a black rim", borders[1].color == St.CLASSIC_GOLD_RGB
    and borders[2].color == St.CLASSIC_BRONZE_RGB and borders[4].color == St.CLASSIC_BRONZE_RGB
    and borders[5].color == St.BORDER_RGB)
local gems = frames[#frames]
local gold = 0
for _, t in ipairs(gems.textures) do
    check("a gem is the diamond", t.texture == St.GEM)
    if t.color[1] == St.CLASSIC_GOLD_RGB.r then gold = gold + 1 end
end
check("a gem on each corner, each on its black edge", #gems.textures == 8 and gold == 4)

local plate = Parts.TitlePlate(window, "Naowh Forever")
local title = plate.strings[1]
check("the title in capitals, in the title font", title.text == "NAOWH FOREVER" and title.font == "morpheus")
check("the plate over the middle of the top edge", plate.points[1][1] == "CENTER" and plate.points[1][2] == window
    and plate.points[1][3] == "TOP")
check("as wide as the title and its room", plate.width == 100 + 2 * St.CLASSIC_PLATE_PAD)

-- The game's full-colour icons in place of the line glyphs, only on Classic+.
local icon = New("Texture")
check("default skin: the glyph stays", Parts.ClassicIcon(icon, "map") == false and rawget(icon, "texture") == nil)
ns.classicSkin = true
check("Classic+: the game's icon for a glyph", Parts.ClassicIcon(icon, "map") == true
    and icon.texture == St.CLASSIC_ICON_PATH .. St.CLASSIC_ICONS.map)
check("cropped inside its edge, in its own colours", icon.coords[1] == St.CLASSIC_ICON_CROP
    and icon.coords[2] == 1 - St.CLASSIC_ICON_CROP and icon.desaturated == false and icon.color[1] == 1)
check("a name with no icon keeps its glyph", Parts.ClassicIcon(New("Texture"), "nothing") == false)
missing[St.CLASSIC_ICON_PATH .. St.CLASSIC_ICONS.hearth] = true
check("an icon this client lacks keeps its glyph", Parts.ClassicIcon(New("Texture"), "hearth") == false)
check("the Top Bar's launchers have icons", St.CLASSIC_ICONS.NaowhForeverJournal and St.CLASSIC_ICONS.friends)

print("classic skin: " .. checks .. " checks passed")
