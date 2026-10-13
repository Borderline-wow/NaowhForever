-- Run with Lua 5.1 from the repository root: UI.SlimScroll cut out of Widgets.lua and run against stub
-- frames. Its bar belongs to the scroll's parent, so two scrolls in one window (Discovery's) must
-- each keep the bar to their own visibility, or a hidden scroll's bar sits over the visible one's.
local f = assert(io.open("Core/Options/Widgets.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local body = assert(source:match("\n(local function OnPixel%(.-\n)local function SharedMedia"), "SlimScroll")

local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function Frame()
    local fr = { scripts = {}, hooks = {}, shown = true, value = 0, min = 0, max = 0, height = 100, range = 0 }
    function fr:SetScript(event, fn) self.scripts[event] = fn end
    function fr:HookScript(event, fn) self.hooks[event] = self.hooks[event] or {}; table.insert(self.hooks[event], fn) end
    function fr:GetScript(event) return self.scripts[event] end
    function fr:SetShown(shown) self.shown = shown and true or false end
    function fr:Show() self.shown = true; self:Fire("OnShow") end
    function fr:Hide() self.shown = false; self:Fire("OnHide") end
    function fr:IsShown() return self.shown end
    function fr:GetHeight() return self.height end
    function fr:GetVerticalScrollRange() return self.range end
    function fr:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function fr:GetMinMaxValues() return self.min, self.max end
    function fr:SetValue(v) self.value = v end
    function fr:GetValue() return self.value end
    function fr:SetVerticalScroll(v) self.scroll = v end
    function fr:Fire(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, fn in ipairs(self.hooks[event] or {}) do fn(self, ...) end
    end
    return setmetatable(fr, { __index = function() return function() return fr end end })
end

local env = setmetatable({
    UI = {},
    CreateFrame = Frame,
    SCROLL = { slimW = 6, slimGap = 6, trackAlpha = 0.6, thumbAlpha = 0.8, minThumb = 24, sync = 0.5 },
    SCROLL_STEP = 60, GLIDE_RATE = 14, GLIDE_DONE = 0.5, ROUND = 0.5,
    T = { line = {}, muted = {}, accent = {} },
    ns = { Solid = function() return Frame() end, OnePixel = function() return 1 end },
}, { __index = _G })
local chunk = assert(loadstring(body))
setfenv(chunk, env)
chunk()

local window = Frame()
local books = env.UI.SlimScroll(window)
local quests = env.UI.SlimScroll(window)
books.range, quests.range = 300, 500

books:Fire("OnScrollRangeChanged", 0, 300)
check("a scroll with room shows its bar", books.bar.shown)
check("and gives it the range", select(2, books.bar:GetMinMaxValues()) == 300)

books:Hide()
quests:Fire("OnScrollRangeChanged", 0, 500)
check("hiding a scroll hides its bar", not books.bar.shown)
check("the other scroll's bar is the one in view", quests.bar.shown)

quests:Hide()
books:Show()
check("showing it again brings its bar back", books.bar.shown and not quests.bar.shown)

books.range = 0
books:Hide()
books:Show()
check("a scroll with no room shows no bar", not books.bar.shown)

print(("test-slim-scroll: %d checks passed"):format(checks))
