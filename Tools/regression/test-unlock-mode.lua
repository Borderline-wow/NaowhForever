-- Run with Lua 5.1 from the repository root: Move Elements' movers, run against frame stubs
-- with real geometry. Drags, arrow keys, typed X and Y and Center save the element CENTER on
-- the screen centre, and anchors and the snap switch from before are dropped without moving
-- anything.
local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end
local function Near(a, b) return a and b and math.abs(a - b) < 0.01 end

local W, H = 1920, 1080
local FRACTION = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 },
    CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
local NOOP = function() end

local made = {}
local Frame = {}
-- Methods the code only calls for looks (SetFrameStrata, SetAlpha...) do nothing.
local FrameMeta = { __index = function(_, k)
    if Frame[k] then return Frame[k] end
    if type(k) == "string" and k:match("^%u") then return NOOP end
end }
local UIParent

local function NewFrame(kind, parent)
    local f = setmetatable({ kind = kind, parent = parent, scripts = {}, hooks = {}, shown = true, points = {},
        events = {}, level = 1, w = 0, h = 0 }, FrameMeta)
    made[#made + 1] = f
    return f
end

-- Left, bottom, right, top on the screen.
local function Rect(f)
    if f == UIParent then return 0, 0, W, H end
    if f.allRel then return Rect(f.allRel) end
    local p = f.points[1]
    if not p then return end
    local rl, rb, rr, rt = Rect(p[2])
    if not rl then return end
    local ax = rl + (rr - rl) * FRACTION[p[3]][1] + p[4]
    local ay = rb + (rt - rb) * FRACTION[p[3]][2] + p[5]
    local w, h = f:GetWidth(), f:GetHeight()
    local l, b = ax - w * FRACTION[p[1]][1], ay - h * FRACTION[p[1]][2]
    return l, b, l + w, b + h
end

local function Fire(f, name, ...)
    if f.scripts[name] then f.scripts[name](f, ...) end
    for _, fn in ipairs(f.hooks[name] or {}) do fn(f, ...) end
end

function Frame:SetScript(name, fn) self.scripts[name] = fn; self.hooks[name] = nil end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    Fire(self, "OnShow")
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    Fire(self, "OnHide")
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent == UIParent or self.parent:IsVisible()) end
function Frame:IsMouseOver() return self.mouseOver == true end
function Frame:ClearAllPoints() self.points = {}; self.allRel = nil end
function Frame:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
    self.allRel = nil
    self.points[#self.points + 1] = { point, rel or self.parent, relPoint or point, x or 0, y or 0 }
    local a, b = self.points[1], self.points[2]
    if b and a[1] == "TOPLEFT" and b[1] == "BOTTOMRIGHT" and a[2] == b[2] then self:SetAllPoints(a[2]) end
end
function Frame:SetAllPoints(rel) self.points = {}; self.allRel = rel or self.parent end
function Frame:GetNumPoints()
    if self.allRel then return 2 end
    return #self.points
end
function Frame:GetPoint(i)
    if self.allRel then
        if i == 2 then return "BOTTOMRIGHT", self.allRel, "BOTTOMRIGHT", 0, 0 end
        return "TOPLEFT", self.allRel, "TOPLEFT", 0, 0
    end
    local p = self.points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Frame:SetSize(w, h)
    local changed = w ~= self.w or h ~= self.h
    self.w, self.h = w, h
    if changed then Fire(self, "OnSizeChanged", w, h) end
end
function Frame:SetWidth(w) self:SetSize(w, self.h) end
function Frame:SetHeight(h) self:SetSize(self.w, h) end
function Frame:GetWidth()
    if self.allRel then return self.allRel:GetWidth() end
    return self.w
end
function Frame:GetHeight()
    if self.allRel then return self.allRel:GetHeight() end
    return self.h
end
function Frame:GetLeft() local l = Rect(self); return l end
function Frame:GetBottom() local _, b = Rect(self); return b end
function Frame:GetRight() local _, _, r = Rect(self); return r end
function Frame:GetTop() local _, _, _, t = Rect(self); return t end
function Frame:GetCenter()
    local l, b, r, t = Rect(self)
    if l then return (l + r) / 2, (b + t) / 2 end
end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameLevel() return self.level end
function Frame:SetFrameLevel(v) self.level = v end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:EnableKeyboard(v) self.keyboard = v end
function Frame:SetPropagateKeyboardInput(v) self.propagate = v end
function Frame:IsProtected() return self.protected == true end
function Frame:SetText(text) self.text_ = text end
function Frame:GetText() return self.text_ end
function Frame:HasFocus() return false end
function Frame:CreateTexture() return NewFrame("Texture", self) end
function Frame:CreateLine() return NewFrame("Line", self) end
function Frame:CreateFontString() return NewFrame("FontString", self) end
function Frame:GetStringWidth() return #(self.text_ or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end

UIParent = NewFrame("Frame")
UIParent.w, UIParent.h = W, H
function UIParent:GetWidth() return W end
function UIParent:GetHeight() return H end

local timers = {}
local function Flush()
    for _ = 1, 20 do
        if #timers == 0 then return end
        local run = timers
        timers = {}
        for _, fn in ipairs(run) do fn() end
    end
end

local cursor = { x = 0, y = 0 }
local combat, shift = false, false
local settings = {}
local printed = {}
local T = { accent = { r = 0, g = 0.5, b = 1 }, accentSoft = { r = 0.3, g = 0.7, b = 1 }, fg = { r = 1, g = 1, b = 1 },
    muted = { r = 0.6, g = 0.6, b = 0.6 }, line = { r = 0.2, g = 0.2, b = 0.2 }, grey = { r = 0.2, g = 0.2, b = 0.2 },
    panel = { r = 0.1, g = 0.1, b = 0.1 }, bg = { r = 0, g = 0, b = 0 } }
local ns = {
    THEME = T,
    UnlockModeSettings = {
        DB = function() return settings end,
        Get = function(k) return settings[k] end,
        Set = function(k, v) settings[k] = v end,
    },
    Solid = function(parent) return parent:CreateTexture() end,
    Border = function(frame)
        local b = { _frame = NewFrame("Frame", frame) }
        function b.SetColor(_, r, g, bl, a) b.color = { r, g, bl, a } end
        return b
    end,
    Font = function(parent) return parent:CreateFontString() end,
    NewEditBox = function(parent)
        local box = NewFrame("EditBox", parent)
        box.border = { SetColor = NOOP }
        function box:SetFocus() self.focus = true end
        function box:HasFocus() return self.focus == true end
        function box:ClearFocus()
            if not self.focus then return end
            self.focus = false
            Fire(self, "OnEditFocusLost")
        end
        return box
    end,
    Tooltip = NOOP,
    Button = function(parent, text, w, h, onClick)
        local b = NewFrame("Button", parent)
        b:SetSize(w, h)
        b.text_ = text
        b:SetScript("OnClick", onClick)
        return b
    end,
    Shared = { Parts = { HudText = function(fs) return fs end } },
    UIFontPath = function() return "font" end,
    L = function(text) return text end,
    Color = function(_, text) return text end,
    Print = function(msg) printed[#printed + 1] = msg end,
    HideRaidReminderAnchorConfig = function() printed[#printed + 1] = "left Move Elements" end,
    OpenOptionsWindow = function(page) printed[#printed + 1] = "opened " .. page end,
    Apply = NOOP,
}
local UI = {}
ns.UI = UI

local env = setmetatable({
    NaowhForever = ns,
    UIParent = UIParent,
    CreateFrame = function(kind, _, parent) return NewFrame(kind, parent) end,
    PixelUtil = {
        GetPixelToUIUnitFactor = function() return 1 end,
        GetNearestPixelSize = function(v, scale) return math.floor(v * scale + 0.5) / scale end,
    },
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    InCombatLockdown = function() return combat end,
    IsShiftKeyDown = function() return shift end,
    GetCurrentKeyBoardFocus = function() return nil end,
    GetCursorPosition = function() return cursor.x, cursor.y end,
    GetTime = function() return 0 end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    hooksecurefunc = function(tbl, name, fn)
        local orig = tbl[name]
        tbl[name] = function(...)
            orig(...)
            fn(...)
        end
    end,
}, { __index = _G })
env._G = env
local f = assert(io.open("Core/NaowhForever_UnlockMode.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local chunk = assert(loadstring(source, "Core/NaowhForever_UnlockMode.lua"))
setfenv(chunk, env)
chunk()

local function Display(label, w, h, x, y)
    local frame = NewFrame("Frame", UIParent)
    frame:SetSize(w, h)
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    local saved = {}
    local mover = UI.AttachMover(frame, label, function(pos) saved[#saved + 1] = pos end, "QoL/General")
    mover:Show()
    return frame, mover, saved
end

local function Center(frame) return frame:GetCenter() end
local function Last(saved) return saved[#saved] end

local function Click(handle, button)
    Fire(handle, "OnMouseDown", button)
    Fire(handle, "OnMouseUp", button)
end

-- The drag driver's frame update.
local function Drive()
    for _, fr in ipairs(made) do
        if fr.scripts.OnUpdate and fr.kind == "Frame" and fr.parent == nil then fr.scripts.OnUpdate(fr, 0) end
    end
end

local meter, meterMover, meterSaved = Display("Threat Meter", 200, 20, 0, -200)
local swing, swingMover, swingSaved = Display("Swing Timer", 100, 40, -40, 25)
UI.BeginMoverMode()
local keys
for _, fr in ipairs(made) do
    if fr.scripts.OnKeyDown then keys = fr end
end
Check(keys and keys.keyboard and keys.events.PLAYER_REGEN_DISABLED, "Move Elements takes the arrow keys and watches combat")

-- Hovering lights the mover up and leaves its size alone.
local dura, duraMover = Display("Durability", 40, 40, 500, 300)
Fire(duraMover, "OnEnter")
Flush()
Check(duraMover._placement.hovered and duraMover:GetWidth() == 40 and duraMover:GetLeft() == dura:GetLeft(),
    "hovering lights a mover without growing it")
Fire(duraMover, "OnLeave")
duraMover:Hide()

-- Arrow keys move it a pixel, Shift + arrow 10, saved CENTER on the screen centre.
UI.SelectMover(swingMover)
Fire(keys, "OnKeyDown", "RIGHT")
Check(Near(Center(swing), 921), "an arrow nudges it a pixel")
Check(Last(swingSaved).point == "CENTER" and Last(swingSaved).relPoint == "CENTER" and Near(Last(swingSaved).x, -39)
    and Near(Last(swingSaved).y, 25), "and saves it CENTER on the screen centre")
shift = true
Fire(keys, "OnKeyDown", "UP")
shift = false
Check(Near(Last(swingSaved).y, 35), "Shift + arrow nudges by 10")
for _ = 1, 10 do Fire(keys, "OnKeyDown", "DOWN") end
Check(Near(Last(swingSaved).y, 25), "and back")
Check(settings.anchors == nil, "nothing is anchored")

-- The X and Y tag on the selected mover: its centre from the screen centre, kept up by the
-- arrow keys, and typed to move it. Just below the mover, above it at the screen's bottom.
local function Tag()
    for _, fr in ipairs(made) do
        if fr.x and fr.y and fr.x.axis == "X" then return fr end
    end
end
local tag = Tag()
local function Reads(x, y) return tag.x:GetText() == x and tag.y:GetText() == y end
local function Type(box, text)
    box:SetFocus()
    box:SetText(text)
    Fire(box, "OnEnterPressed")
end
local function Below(handle) return tag:IsShown() and tag:GetTop() < handle:GetBottom() and tag:GetTop() > handle:GetBottom() - 10 end
Check(tag and tag.parent == UIParent and tag:GetPoint() == "TOP" and select(2, tag:GetPoint()) == swingMover and Below(swingMover),
    "the tag sits just below the selected mover")
Check(Reads("-39", "25"), "and shows its centre from the screen centre")
Fire(keys, "OnKeyDown", "LEFT")
Check(Reads("-40", "25") and Below(swingMover), "an arrow key updates it and it moves along")
Type(tag.x, "25")
Check(Near(Center(swing), 985) and Near(Last(swingSaved).x, 25) and Reads("25", "25"), "a typed X moves it there and saves it")
Type(tag.y, "abc")
Check(Reads("25", "25") and not tag.y:HasFocus(), "what is not a number goes back")

UI.SelectMover(meterMover)
Check(select(2, tag:GetPoint()) == meterMover and Reads("0", "-200"), "selecting another element moves the tag to it")
cursor.x, cursor.y = 960, 340
UI.StartMoverDrag(meterMover)
cursor.x, cursor.y = 1000, 330
Drive()
Check(Reads("40", "-210") and Below(meterMover), "and it follows a drag as it happens")
UI.StopMoverDrag(meterMover)
Check(Last(meterSaved).point == "CENTER" and Near(Last(meterSaved).x, 40) and Near(Last(meterSaved).y, -210),
    "the drop saves it CENTER on the screen centre")
Check(Near(Center(swing), 985), "and nothing else moves with it")
Type(tag.x, "0")
Type(tag.y, "-200")
Check(Near(Center(meter), 960) and Near(select(2, Center(meter)), 340) and Near(Last(meterSaved).y, -200),
    "typed numbers move it there and save it")
Type(tag.y, "-525")
Check(tag:GetPoint() == "BOTTOM" and tag:GetBottom() > meterMover:GetTop() and tag:GetBottom() < meterMover:GetTop() + 10,
    "with no room below it flips above the mover")
Type(tag.y, "-200")
Check(tag:GetPoint() == "TOP" and Below(meterMover), "and back below with room again")
Click(meterMover, "RightButton")
Check(Below(meterMover) and meterMover._placement.selected, "a right-click does nothing")
Fire(keys, "OnKeyDown", "ESCAPE")
Check(not tag:IsShown(), "Escape lets the selection go and the tag with it")

-- The tag's Center and Settings: Center moves it across to the middle and saves it, Settings
-- leaves Move Elements for the element's page.
Click(swingMover, "LeftButton")
Check(tag.center:IsShown() and tag.settings:IsShown(), "the tag has Center and Settings")
Fire(tag.center, "OnClick")
Check(Near(Center(swing), 960) and Near(Last(swingSaved).x, 0) and Near(Last(swingSaved).y, 25),
    "Center moves it across to the middle and keeps its height")
Fire(tag.settings, "OnClick")
Check(not tag:IsShown() and printed[#printed] == "opened QoL/General",
    "Settings leaves Move Elements, then opens its page")
UI.BeginMoverMode()
local _, bareMover = Display("Loose", 60, 20, 300, 0)
bareMover._placement.page = nil
Click(bareMover, "LeftButton")
Check(tag.item == bareMover._placement and not tag.settings:IsShown(), "an element with no page has no Settings")
bareMover:Hide()
Check(not tag:IsShown(), "hiding the selected mover lets it go")

-- A drag goes where the cursor takes it: nothing pulls it onto another element's edge.
local sx, sy = Center(swing)
local mL = meter:GetLeft()
cursor.x, cursor.y = sx, sy
UI.StartMoverDrag(swingMover)
cursor.x, cursor.y = sx + (mL - swing:GetLeft()) + 4, sy
Drive()
UI.StopMoverDrag(swingMover)
Check(Near(swing:GetLeft(), mL + 4), "a drag near another element's edge stays where it is dropped")

-- Anchors and the snap switch saved before they were dropped: both go at login and on every
-- profile switch, and nothing moves, since each element's own position already holds where its
-- anchor put it.
settings.anchors = { ["Swing Timer"] = { target = "Threat Meter", side = "TOP", offsetX = 0, offsetY = 0 } }
settings.snap = false
local before, saves = { Center(swing) }, #swingSaved
local login
for _, fr in ipairs(made) do
    if fr.events.PLAYER_LOGIN then login = fr end
end
login.scripts.OnEvent(login, "PLAYER_LOGIN")
Check(settings.anchors ~= nil, "nothing is dropped before the profile loads")
ns.Apply()
Check(settings.anchors == nil and settings.snap == nil, "the profile's anchors and snap switch are dropped")
Check(Near(Center(swing), before[1]) and #swingSaved == saves, "without moving or saving anything")
settings.anchors = { ["Threat Meter"] = { target = "SCREEN_LEFT", side = "RIGHT" } }
ns.Apply()
Check(settings.anchors == nil, "and a switched-to profile's are dropped too")

print(("test-unlock-mode: %d checks passed"):format(checks))
