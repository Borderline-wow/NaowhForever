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
    function fr:SetHeight(h) self.setHeight = h end
    function fr:SetScrollChild(child) self.child = child end
    function fr:UpdateScrollChildRect()
        local child = rawget(self, "child")
        local range = child and math.max(0, child.height - self.height) or self.range
        if range ~= self.range then
            self.range = range
            if rawget(self, "lazy") then return end
            self:Fire("OnScrollRangeChanged", 0, range)
        end
    end
    function fr:GetVerticalScrollRange() return self.range end
    function fr:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function fr:GetMinMaxValues() return self.min, self.max end
    function fr:SetValue(v)
        if v ~= self.value then self.moves = (rawget(self, "moves") or 0) + 1 end
        self.value = v
    end
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

-- Forever's Lua raises on 0 / 0, which is what a scroll shown before it has a height used to compute.
local fresh = env.UI.SlimScroll(window)
fresh.height, fresh.range, fresh.bar.setHeight = 0, 0, false
fresh:Hide()
fresh:Show()
check("a scroll shown before it has a height leaves its thumb alone", fresh.bar.setHeight == false and not fresh.bar.shown)

-- The game's scroll frame may not report a new range until something scrolls it (Discovery's
-- tabs grew their content after showing and kept no bar until the mouse wheel moved them).
local lazy = env.UI.SlimScroll(window)
lazy.lazy = true
local content = Frame()
content.height = 0
lazy:SetScrollChild(content)
lazy:Show()
check("an empty scroll shows no bar", not lazy.bar.shown)
content.height = 400
lazy.bar.moves = 0
content:Fire("OnSizeChanged")
check("content growing after show brings the bar without a wheel", lazy.bar.shown
    and select(2, lazy.bar:GetMinMaxValues()) == 300)
check("its value moves once, so the game places the thumb, and comes back to the top",
    lazy.bar.moves > 0 and lazy.bar:GetValue() == 0)
lazy.bar.moves = 0
content.height = 500
content:Fire("OnSizeChanged")
check("a bar already in use is not nudged when its range changes", lazy.bar.moves == 0)
content.height = 50
content:Fire("OnSizeChanged")
check("and content shrinking takes it away again", not lazy.bar.shown)

print(("test-slim-scroll: %d checks passed"):format(checks))
