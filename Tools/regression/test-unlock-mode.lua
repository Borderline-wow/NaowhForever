-- Run with Lua 5.1 from the repository root: The HUD Editor's movers, run against frame stubs
-- with real geometry. Drags, arrow keys, typed X and Y and Center save the element CENTER on
-- the screen centre; a drag lines up on guides; Anchor ties an element to another so it
-- follows from the side picked, keeping a typed gap; and the anchors and snap switch from
-- before are dropped without moving anything.
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
local combat, shift, alt = false, false, false
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
        b.label = b:CreateFontString()
        b._border = { SetColor = function(self, r, g, bl) self.color = { r, g, bl } end }
        b:SetScript("OnClick", onClick)
        return b
    end,
    SetButtonText = function(b, text) b.text_ = text end,
    Shared = { Parts = { HudText = function(fs) return fs end }, Style = { GUIDE_RGB = { r = 0.95, g = 0.64, b = 0.23 } } },
    UIFontPath = function() return "font" end,
    L = function(text) return text end,
    Color = function(_, text) return text end,
    Print = function(msg) printed[#printed + 1] = msg end,
    HideRaidReminderAnchorConfig = function() printed[#printed + 1] = "left HUD Editor" end,
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
    IsAltKeyDown = function() return alt end,
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

local function Display(label, w, h, x, y, ownAnchor)
    local frame = NewFrame("Frame", UIParent)
    frame:SetSize(w, h)
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    local saved = {}
    local mover = UI.AttachMover(frame, label, function(pos) saved[#saved + 1] = pos end, "QoL/General", nil, ownAnchor)
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
Check(keys and keys.keyboard and keys.events.PLAYER_REGEN_DISABLED, "HUD Editor takes the arrow keys and watches combat")

-- Hovering lights the mover up and leaves its size alone.
local dura, duraMover = Display("Durability", 40, 40, 500, 300)
Check(duraMover._border.color[1] == 0 and duraMover._border.color[2] == 0 and duraMover._border.color[3] == 0,
    "a mover at rest has a black edge")
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
-- leaves the HUD Editor for the element's page.
Click(swingMover, "LeftButton")
Check(tag.center:IsShown() and tag.settings:IsShown(), "the tag has Center and Settings")
Fire(tag.center, "OnClick")
Check(Near(Center(swing), 960) and Near(Last(swingSaved).x, 0) and Near(Last(swingSaved).y, 25),
    "Center moves it across to the middle and keeps its height")
Fire(tag.settings, "OnClick")
Check(not tag:IsShown() and printed[#printed] == "opened QoL/General",
    "Settings leaves the HUD Editor, then opens its page")
UI.BeginMoverMode()
local _, bareMover = Display("Loose", 60, 20, 300, 0)
bareMover._placement.page = nil
Click(bareMover, "LeftButton")
Check(tag.item == bareMover._placement and not tag.settings:IsShown(), "an element with no page has no Settings")
bareMover:Hide()
Check(not tag:IsShown(), "hiding the selected mover lets it go")

-- Guides: a drag within a few pixels of another element's edge, or of the screen centre, lands
-- on it, the guide drawn with the gap to that element; Alt, or the Guides switch off, lets it
-- go where it is dropped. Where the drag started shows as a faint outline until the drop.
local overlayFrame
local function Overlay()
    for _, fr in ipairs(made) do
        if fr.level == 220 and fr.allRel == UIParent then return fr end
    end
end
local function Shown(kind)
    local out = {}
    local o = Overlay()
    for _, fr in ipairs(made) do
        if fr.parent == o and fr.kind == kind and fr:IsShown() then out[#out + 1] = fr end
    end
    return out
end
local function Gaps()
    local out = {}
    for _, plate in ipairs(Shown("Frame")) do out[#out + 1] = plate.text:GetText() end
    return table.concat(out, " ")
end
local function DragBy(handle, frame, dx, dy, keep)
    local cx, cy = Center(frame)
    cursor.x, cursor.y = cx, cy
    UI.StartMoverDrag(handle)
    cursor.x, cursor.y = cx + dx, cy + dy
    Drive()
    if not keep then UI.StopMoverDrag(handle) end
end
-- swing is 100 x 40 at (0, 25) after Center; meter is 200 x 20 at (0, -200): line swing's left up
-- 4 pixels off meter's left, well off the screen centre.
local mL = meter:GetLeft()
swing:ClearAllPoints()
swing:SetPoint("CENTER", UIParent, "CENTER", -300, 25)
Flush()
DragBy(swingMover, swing, mL - swing:GetLeft() + 4, 0, true)
overlayFrame = Overlay()
Check(Near(swing:GetLeft(), mL), "a drag a few pixels off another element's edge lands on it")
local lines = Shown("Texture")
Check(#lines >= 5 and overlayFrame and overlayFrame.level > swingMover.level, "the guide is drawn, with the start's outline, over the movers")
Check(Gaps() == tostring(math.floor(swing:GetBottom() - meter:GetTop() + 0.5)), "with the gap to the element it lines up with")
UI.StopMoverDrag(swingMover)
Check(#Shown("Texture") == 0 and Gaps() == "", "the drop clears the guides and the outline")
Check(Near(Last(swingSaved).x, (mL + 50) - 960), "and saves where it landed")

DragBy(swingMover, swing, 0, 0, true)
cursor.x = cursor.x + (960 - Center(swing)) - 3
Drive()
Check(Near(Center(swing), 960), "the screen centre pulls it too")
UI.StopMoverDrag(swingMover)

alt = true
DragBy(swingMover, swing, mL - swing:GetLeft() + 4, 0)
alt = false
Check(Near(swing:GetLeft(), mL + 4), "with Alt held it stays where it is dropped")
settings.guides = false
DragBy(swingMover, swing, -8, 0, true)
Check(Near(swing:GetLeft(), mL - 4) and #Shown("Texture") == 4, "and with the Guides switch off, only the outline shows")
UI.StopMoverDrag(swingMover)
settings.guides = nil

-- Anchor on the tag: lit while it waits for a target, the next element clicked becomes the
-- target, and from then on the element follows it, keeping its gap.
local boss, bossMover = Display("Boss Bar", 100, 20, 0, 300)
local add, addMover, addSaved = Display("Add Bar", 60, 20, 20, 270)
Flush()
Click(addMover, "LeftButton")
Check(tag.anchor:IsShown() and tag.anchor:GetText() == "Anchor", "the tag has Anchor")
Fire(tag.anchor, "OnClick")
Check(tag.anchor._border.color[3] == T.accent.b and tag.anchor.label.color[3] == T.accent.b,
    "Anchor lights up while it waits for a target")
Click(bossMover, "LeftButton")
local link = settings.anchoredTo["Add Bar"]
Check(link and link.target == "Boss Bar" and link.side == "BOTTOM" and Near(link.x, 20) and Near(link.y, -10),
    "clicking another element anchors to its nearest side, where it is")
Check(tag.item == addMover._placement and tag.anchor:GetText() == "Unanchor"
    and tag.anchor._border.color[3] == 0, "the element stays selected and its button reads Unanchor")

UI.SelectMover(bossMover)
shift = true
Fire(keys, "OnKeyDown", "RIGHT")
shift = false
Check(Near(Center(add), 990) and Near(Last(addSaved).x, 30) and Near(Last(addSaved).y, 270),
    "moving the target takes the anchored element along and saves it")
local addSaves = #addSaved
cursor.x, cursor.y = Center(boss)
UI.StartMoverDrag(bossMover)
cursor.x = cursor.x + 50
Drive()
Check(Near(Center(add), 1040) and #addSaved == addSaves, "it follows a drag as it happens")
UI.StopMoverDrag(bossMover)
Check(Near(Last(addSaved).x, 80), "and is saved on the drop")
boss:SetHeight(40)
Flush()
Check(Near(add:GetTop(), boss:GetBottom() - 10), "a target that grows pushes it out, keeping the gap")

UI.SelectMover(addMover)
Fire(keys, "OnKeyDown", "DOWN")
Check(Near(link.y, -11), "moving the element itself keeps the anchor with the new gap")
boss:ClearAllPoints()
boss:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Flush()
Check(Near(add:GetTop(), boss:GetBottom() - 11) and Near(Last(addSaved).y, -41),
    "a target the module moves itself takes it along too")

UI.SelectMover(bossMover)
Fire(tag.anchor, "OnClick")
Click(addMover, "LeftButton")
Check(settings.anchoredTo["Boss Bar"] == nil and printed[#printed]:find("Boss Bar", 1, true),
    "an element cannot anchor to one that already follows it")
Fire(tag.anchor, "OnClick")
Fire(keys, "OnKeyDown", "ESCAPE")
Check(tag:IsShown() and tag.item == bossMover._placement and tag.anchor._border.color[3] == 0,
    "Escape calls a pick off and keeps the selection")
Fire(tag.anchor, "OnClick")
Click(bossMover, "LeftButton")
Check(settings.anchoredTo["Boss Bar"] == nil and tag.item == bossMover._placement, "so does clicking the element itself")
Fire(tag.anchor, "OnClick")
Fire(tag.anchor, "OnClick")
Check(tag.anchor._border.color[3] == 0, "and Anchor again")

-- The tag's second row while anchored: the side it sits off, and the gap, typed. A new side keeps
-- the gap; the anchor shows as a line from the target with the gap on it.
UI.SelectMover(addMover)
Check(tag.sides:IsShown() and tag.side.BOTTOM._border.color[3] == T.accent.b and tag.side.TOP._border.color[3] == 0,
    "an anchored element's tag shows its side, lit")
Check(tag.gap:GetText() == "11" and tag:GetHeight() > 30, "and the gap, on a second row")
local function AnchorGap() return Gaps() end
Check(AnchorGap() == "11", "the anchor is drawn from the target, its gap written on it")
Fire(tag.side.RIGHT, "OnClick")
Check(link.side == "RIGHT" and Near(add:GetLeft(), boss:GetRight() + 11) and Near(select(2, Center(add)), select(2, Center(boss))),
    "a new side moves it off that side, keeping the gap, centred along it")
Check(tag.side.RIGHT._border.color[3] == T.accent.b and tag.side.BOTTOM._border.color[3] == 0, "and lights it")
Check(Near(Last(addSaved).x, (boss:GetRight() + 11 + 30) - 960), "and saves it")
Type(tag.gap, "20")
Check(Near(add:GetLeft(), boss:GetRight() + 20) and tag.gap:GetText() == "20" and AnchorGap() == "20", "a typed gap moves it out")
Fire(tag.side.LEFT, "OnClick")
Check(Near(add:GetRight(), boss:GetLeft() - 20), "left keeps the gap too")
Fire(tag.side.TOP, "OnClick")
Check(Near(add:GetBottom(), boss:GetTop() + 20) and Near(Center(add), Center(boss)), "and so does top")
Fire(tag.side.BOTTOM, "OnClick")
Type(tag.gap, "11")
Check(Near(add:GetTop(), boss:GetBottom() - 11), "back under it")

UI.SelectMover(addMover)
local addSpot = { Center(add) }
Fire(tag.anchor, "OnClick")
Check(settings.anchoredTo["Add Bar"] == nil and tag.anchor:GetText() == "Anchor", "Unanchor lets go")
Check(not tag.sides:IsShown() and Gaps() == "", "and the side row and the anchor line go with it")
Fire(tag.anchor, "OnClick")
Fire(keys, "OnKeyDown", "ESCAPE")
boss:ClearAllPoints()
boss:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
Flush()
Check(Near(Center(add), addSpot[1]) and Near(select(2, Center(add)), addSpot[2]), "and it stays put after")

local _, fireMover = Display("Fire", 30, 30, -300, 0, true)
Click(fireMover, "LeftButton")
Check(not tag.anchor:IsShown() and tag.settings:IsShown(), "an element that holds its own spot has no Anchor")
UI.ClearMoverSelection()

-- Profile switches put anchored elements back on their targets, parents first.
settings.anchoredTo = {
    ["Add Bar"] = { target = "Boss Bar", side = "BOTTOM", x = 0, y = -5 },
    ["Fire"] = { target = "Boss Bar", side = "TOP", x = 0, y = 5 },
}
local login
for _, fr in ipairs(made) do
    if fr.events.PLAYER_LOGIN then login = fr end
end
settings.snap = false
ns.Apply()
Check(settings.snap == false, "nothing is dropped before the profile loads")
login.scripts.OnEvent(login, "PLAYER_LOGIN")
ns.Apply()
Flush()
Check(Near(add:GetTop(), boss:GetBottom() - 5) and Near(Center(add), 960), "a profile switch re-places anchored elements")
Check(Near(select(2, Center(fireMover._placement.frame)), 540), "but not one that holds its own spot")
settings.anchoredTo = nil
for _, m in ipairs({ bossMover, addMover, fireMover }) do m:Hide() end

-- Anchors and the snap switch saved before they were dropped: both go at login and on every
-- profile switch, and nothing moves, since each element's own position already holds where its
-- anchor put it.
settings.anchors = { ["Swing Timer"] = { target = "Threat Meter", side = "TOP", offsetX = 0, offsetY = 0 } }
settings.snap = false
local before, saves = { Center(swing) }, #swingSaved
ns.Apply()
Check(settings.anchors == nil and settings.snap == nil, "the profile's anchors and snap switch are dropped")
Check(Near(Center(swing), before[1]) and #swingSaved == saves, "without moving or saving anything")
settings.anchors = { ["Threat Meter"] = { target = "SCREEN_LEFT", side = "RIGHT" } }
ns.Apply()
Check(settings.anchors == nil, "and a switched-to profile's are dropped too")

print(("test-unlock-mode: %d checks passed"):format(checks))
