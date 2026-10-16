-- Run with Lua 5.1 from the repository root: the Shopping List's Consumables button keeps its
-- label only while the title, the subtitle and the whole button fit in the title bar, so a longer
-- translation drops the label at a width where English keeps it. Without its label the button is
-- as wide as it is tall. It is measured when the window shows and as it is resized while shown.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local source = Read("NaowhForever_Professions/UI/ShoppingWindow.lua")
local first = assert(source:find("local function FitPicker()", 1, true))
local sized = assert(source:find("local function OnSized(", first, true))
local last = assert(source:find("\nend\n", sized, true))
local chunk = "local window, side, picker, pickerFullWidth, events\n" .. source:sub(first, last + 4)
    .. "return function(w, s, p, full, e) window, side, picker, pickerFullWidth, events = w, s, p, full, e end,"
    .. " OnShow, OnSized"

local TITLE_LEFT, BAR_RIGHT, BAR_GAP = 52, 44, 12
local FULL_W, ICON_W = 100, 22

local window = { width = 380, shown = false }
function window:IsShown() return self.shown end

local function Text(width)
    local fs = { width = width }
    function fs:GetUnboundedStringWidth() return self.width end
    return fs
end
window.title = Text(90)
function window.title:GetLeft() return TITLE_LEFT end
window.subtitle = Text(170)

local picker = { width = FULL_W, label = { shown = true } }
function picker.label:SetShown(shown) self.shown = shown end
function picker:SetWidth(width) self.width = width end
function picker:GetHeight() return ICON_W end
function picker:GetRight() return window.width - BAR_RIGHT end

local side = {}
function side:SetWidth(width) self.width = width end

local env = {
    St = { BAR_GAP = BAR_GAP },
    INSET = 8, SCROLLBAR = 10, SCROLL_GAP = 4,
    EVENTS = {},
    RenderWindow = function() end,
}
env._G = env
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local Set, OnShow, OnSized = fn()
Set(window, side, picker, FULL_W, {})

local function Size(width)
    window.width = width
    OnSized(window, width)
end

-- Room at 380: 380 - 52 - 44 = 284; the subtitle, the gap and the whole button take 282.
Size(380)
check("before the first show nothing is measured", picker.label.shown and picker.width == FULL_W)
window.shown = true
OnShow()
check("at the default width English keeps its label", picker.label.shown and picker.width == FULL_W)

window.subtitle.width = 230
OnShow()
check("a longer subtitle that does not fit drops the label", not picker.label.shown)
check("and the button shrinks to its icon", picker.width == ICON_W)

Size(438)
check("widened until it just fits, the label comes back", picker.label.shown and picker.width == FULL_W)
Size(437)
check("one pixel short, it goes again", not picker.label.shown and picker.width == ICON_W)
check("the list still follows the width", side.width == 437 - 8 - 10 - 4)

window.subtitle.width = 100
window.title.width = 260
Size(437)
check("a title wider than the subtitle is measured too", not picker.label.shown)
Size(500)
check("and fits once there is room for it", picker.label.shown)

window.shown = false
Size(320)
check("a hidden window is not measured", picker.label.shown and picker.width == FULL_W)

print(("shopping title bar: %d checks passed"):format(checks))
