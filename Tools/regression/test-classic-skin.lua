-- Run with Lua 5.1 from the repository root: the Classic+ skin's window frame. Outside the
-- window's own black edge, one-pixel rings of gold, bronze and a black rim; a gem on each
-- corner; and the title on a plate over the top edge, in the title font.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function New(kind)
    local o = { kind = kind, points = {}, textures = {}, strings = {} }
    return setmetatable(o, { __index = function(_, k)
        return function(self, ...)
            local args = { ... }
            if k == "SetPoint" then self.points[#self.points + 1] = args
            elseif k == "SetText" then self.text = args[1]
            elseif k == "GetText" then return self.text
            elseif k == "SetVertexColor" then self.color = args
            elseif k == "SetTexture" then self.texture = args[1]
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
for _, path in ipairs({ "Shared/Style.lua", "Shared/Window.lua" }) do
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

print("classic skin: " .. checks .. " checks passed")
