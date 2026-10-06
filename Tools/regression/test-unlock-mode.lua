-- Run with Lua 5.1 from the repository root: Unlock Mode and its anchors, run against frame
-- stubs with real geometry. Anchoring snaps an element flush to the side picked, nudges and
-- drags move it by its offsets, it follows its target, screen edges hold their distance, and
-- loops are refused.
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
local settings = { anchors = {} }
local printed, tooltip = {}, nil
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
    Shared = { Parts = { HudText = function(fs) return fs end } },
    UIFontPath = function() return "font" end,
    L = function(text) return text end,
    Color = function(_, text) return text end,
    Print = function(msg) printed[#printed + 1] = msg end,
    HideRaidReminderAnchorConfig = NOOP,
    OpenOptionsWindow = NOOP,
    Apply = NOOP,
}
local UI = {
    COGS_ICON = "cog",
    CHEVRON = "chevron",
    ShowWidgetTooltip = function(_, text) tooltip = text end,
    HideWidgetTooltip = function() tooltip = nil end,
}
ns.UI = UI

local env = setmetatable({
    NaowhForever = ns,
    UIParent = UIParent,
    CreateFrame = function(kind, _, parent) return NewFrame(kind, parent) end,
    PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end },
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
local watcherFor
local function Last(saved) return saved[#saved] end

-- A shown menu's row by its text.
local function MenuRow(text)
    for _, fr in ipairs(made) do
        if fr.rows and fr:IsShown() then
            for _, row in ipairs(fr.rows) do
                if row:IsShown() and row.label and row.label:GetText() == text then return row end
            end
        end
    end
end

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

-- Hover long enough for the row to grow in all the way.
local function Hover(item)
    item.mouseOver = true
    Fire(item, "OnEnter")
    Flush()
    for _, fr in ipairs(made) do
        if fr.parent == item and fr.scripts.OnUpdate then fr.scripts.OnUpdate(fr, 1) end
    end
end

local meter, meterMover, meterSaved = Display("Threat Meter", 200, 20, 0, -200)
local swing, swingMover, swingSaved = Display("Swing Timer", 100, 40, -40, 25)
UI.BeginMoverMode()
local keys
for _, fr in ipairs(made) do
    if fr.scripts.OnKeyDown then keys = fr end
end
Check(keys and keys.keyboard and keys.events.PLAYER_REGEN_DISABLED, "Unlock Mode takes the arrow keys and watches combat")

-- The hover row: the name moves up and "Anchor" shows under it, with the cog.
Hover(swingMover)
local link = swingMover._placement.link
Check(link:IsShown() and link.label:GetText() == "Anchor", "hovering shows the Anchor link")
Check(swingMover._placement.cog:IsShown(), "and the cog")
Check(swingMover:GetHeight() > swing:GetHeight() and Near(select(2, swingMover:GetCenter()), select(2, swing:GetCenter())),
    "a mover too small for its row grows around its centre")
swingMover._placement.Collapse(true)
Check(swingMover:GetLeft() == swing:GetLeft() and swingMover:GetTop() == swing:GetTop() and swingMover:GetHeight() == 40,
    "and covers its element again after")
Hover(swingMover)

-- Anchor: pick mode, then the target, then the side. A new anchor sits flush on that side,
-- centred on the other axis.
Fire(link, "OnClick")
Check(not link:IsShown(), "picking hides the link row")
local pickText
for _, fr in ipairs(made) do
    if fr.kind == "FontString" and fr.parent == swingMover and fr:GetText() == "Click any element\nto anchor to it" then pickText = fr end
end
Check(pickText and pickText:IsShown(), "the mover asks for the element to anchor to")
Click(meterMover, "LeftButton")
Check(MenuRow("Anchor to Left") and MenuRow("Anchor to Right") and MenuRow("Anchor to Top") and MenuRow("Anchor to Bottom"),
    "clicking the target offers its four sides")
Check(not MenuRow("Remove Anchor"), "nothing to remove yet")
Fire(MenuRow("Anchor to Top"), "OnClick")
Flush()
local cx, cy = Center(swing)
Check(Near(cx, 960) and Near(cy, 370), "Anchor to Top puts it flush on top, centred")
local info = settings.anchors["Swing Timer"]
Check(info and info.target == "Threat Meter" and info.side == "TOP" and info.offsetX == 0 and info.offsetY == 0,
    "the anchor is kept with no offset")
Check(Last(swingSaved).point == "CENTER" and Near(Last(swingSaved).x, 0) and Near(Last(swingSaved).y, -170),
    "its spot is saved too, CENTER on the screen centre")
Check(swingMover._placement.chain:IsShown(), "an anchored element shows the chain by its name")
Check(link.label:GetText() == "Anchored", "the link reads Anchored")

-- Arrow keys move an anchored element by its offsets, one pixel at a time.
UI.SelectMover(swingMover)
Fire(keys, "OnKeyDown", "RIGHT")
Check(info.offsetX == 1 and Near(Center(swing), 961), "an arrow nudges the offset by a pixel")
shift = true
Fire(keys, "OnKeyDown", "UP")
shift = false
Check(info.offsetY == 100, "Shift + arrow nudges by 100")
Fire(keys, "OnKeyDown", "DOWN")
for _ = 1, 99 do Fire(keys, "OnKeyDown", "DOWN") end
Check(info.offsetY == 0, "and back")

-- The toolbar's position readout: anchored, the offsets from its target, kept up by the arrow
-- keys, and typed to move it.
local readout = UI.PositionReadout(UIParent)
local function Reads(x, y) return readout.x:GetText() == x and readout.y:GetText() == y end
local function Type(box, text)
    box:SetFocus()
    box:SetText(text)
    Fire(box, "OnEnterPressed")
end
Check(readout.name:GetText() == "Swing Timer" and readout.where:GetText() == "Offset from Threat Meter" and Reads("1", "0"),
    "the readout shows the selected element's offsets from its target")
Fire(keys, "OnKeyDown", "LEFT")
Check(Reads("0", "0"), "an arrow key updates it")
Type(readout.x, "25")
Check(info.offsetX == 25 and Near(Center(swing), 985) and Reads("25", "0"), "a typed X moves it by its offset")
Type(readout.y, "abc")
Check(info.offsetY == 0 and Reads("25", "0") and not readout.y:HasFocus(), "what is not a number goes back")
Type(readout.x, "1")

-- Not anchored: its centre from the screen's, live while it is dragged.
UI.SelectMover(meterMover)
Check(readout.name:GetText() == "Threat Meter" and readout.where:GetText() == "From the screen center" and Reads("0", "-200"),
    "an element with no anchor reads its centre from the screen centre")
cursor.x, cursor.y = 960, 340
UI.StartMoverDrag(meterMover)
cursor.x, cursor.y = 1000, 330
Drive()
Check(Reads("40", "-210"), "and follows a drag as it happens")
UI.StopMoverDrag(meterMover)
Type(readout.x, "0")
Type(readout.y, "-200")
Check(Near(Center(meter), 960) and Near(select(2, Center(meter)), 340) and Near(Last(meterSaved).y, -200),
    "typed numbers move it there and save it")
Check(Near(Center(swing), 961), "and what is anchored to it follows")
UI.ClearMoverSelection()
Check(readout.name:GetText() == "Nothing selected" and not readout.boxes:IsShown(), "with nothing selected the boxes hide")

-- Dragging the target: the anchored element follows the whole way.
cursor.x, cursor.y = 960, 340
UI.StartMoverDrag(meterMover)
cursor.x, cursor.y = 1060, 390
Drive()
local mx, my = Center(meter)
Check(Near(mx, 1060) and Near(my, 390), "the target moves with the cursor")
Check(Near(Center(swing), 1061), "its anchored element follows while it is dragged")
UI.StopMoverDrag(meterMover)
Check(Near(Last(meterSaved).x, 100) and Near(Last(meterSaved).y, -150), "the drop saves the target's spot")

-- Dragging the anchored element keeps the anchor and its side; the offset is where it landed.
cursor.x, cursor.y = 1061, 420
UI.StartMoverDrag(swingMover)
cursor.x, cursor.y = 1091, 420
Drive()
Check(readout.x:GetText() == "31" and readout.y:GetText() == "0", "the readout shows the offset it will keep, live")
UI.StopMoverDrag(swingMover)
info = settings.anchors["Swing Timer"]
Check(info.target == "Threat Meter" and info.side == "TOP" and Near(info.offsetX, 31) and Near(info.offsetY, 0),
    "a drag rewrites the offsets, not the anchor")

-- A target that changes size pushes its anchored element out.
meter:SetSize(200, 60)
Flush()
Check(Near(select(2, Center(swing)), 390 + 30 + 20), "a target that grows pushes it out")

-- Loops are refused: the target already follows the element.
Hover(meterMover)
Fire(meterMover._placement.link, "OnClick")
Click(swingMover, "LeftButton")
Check(tooltip == "This would create a circular anchor" and not MenuRow("Anchor to Top"), "a loop is refused")
Check(not settings.anchors["Threat Meter"], "and nothing is anchored")
Flush()

-- The cog menu: who it is anchored to, and its offsets typed in pixels.
Click(swingMover, "RightButton")
Check(MenuRow("Anchored to: Threat Meter") and MenuRow("Offset X") and MenuRow("Offset Y"), "the cog menu shows the anchor")
Check(MenuRow("Element Options") and MenuRow("Center on Screen") and MenuRow("Relative to Screen"),
    "with Element Options, Center on Screen and Relative to Screen")
local box = MenuRow("Offset X").box
Check(box:GetText() == "31", "Offset X reads the offset in pixels")
box:SetText("40")
Fire(box, "OnEnterPressed")
Check(Near(info.offsetX, 40) and Near(Center(swing), 1100), "typing an offset moves it there")

-- Clicking Anchored lets go; the element stays where it is.
Fire(keys, "OnKeyDown", "ESCAPE")
Check(not MenuRow("Offset X"), "Escape closes the menu")
local before = Center(swing)
Fire(link, "OnClick")
Check(not settings.anchors["Swing Timer"] and Near(Center(swing), before), "clicking Anchored unanchors it in place")
Check(not swingMover._placement.chain:IsShown(), "and the chain goes")
Check(Last(swingSaved).point == "CENTER" and Near(Last(swingSaved).x, before - 960), "and saves where it is")
Check(link.label:GetText() == "Anchor", "the link reads Anchor again")

-- Relative to Screen: the element stays put and keeps its distance to that edge.
Click(swingMover, "RightButton")
Fire(MenuRow("Relative to Screen"), "OnEnter")
Check(MenuRow("Left") and MenuRow("Right") and MenuRow("Top") and MenuRow("Bottom") and MenuRow("Center"),
    "Relative to Screen offers the four edges and Center")
Check(MenuRow("Center").label.color[3] == T.accent.b and MenuRow("Left").label.color[3] == T.fg.b,
    "Center is the current one while nothing is anchored")
local x0, y0 = Center(swing)
Fire(MenuRow("Right"), "OnClick")
info = settings.anchors["Swing Timer"]
Check(info.target == "SCREEN_RIGHT" and info.side == "LEFT" and Near(info.offsetX, x0 + 50 - W), "Right holds the distance to the right edge")
Check(Near(Center(swing), x0), "without moving it")
Click(swingMover, "RightButton")
Fire(MenuRow("Relative to Screen"), "OnEnter")
Fire(MenuRow("Top"), "OnClick")
Check(info.edge and info.edge.key == "SCREEN_TOP" and Near(info.edge.offset, y0 + 20 - H), "Top holds the other axis")
W, H = 2560, 1440
for _, fr in ipairs(made) do
    if fr.allRel == UIParent and fr.scripts.OnSizeChanged then fr.scripts.OnSizeChanged(fr) end
end
Flush()
local x1, y1 = Center(swing)
Check(Near(x1 + 50, W - (1920 - x0 - 50)) and Near(y1 + 20, H - (1080 - y0 - 20)), "a bigger screen keeps it in the corner")
Click(swingMover, "RightButton")
Fire(MenuRow("Relative to Screen"), "OnEnter")
Fire(MenuRow("Center"), "OnClick")
Check(not settings.anchors["Swing Timer"] and Near(Center(swing), x1), "Center lets go of the screen")
W, H = 1920, 1080

-- Center on Screen: the X centre goes to the middle.
Click(swingMover, "RightButton")
Fire(MenuRow("Center on Screen"), "OnClick")
Check(Near(Center(swing), 960), "Center on Screen centres it across")

-- A picked snap target is what a drag lines up with, even with another element nearer.
local nx, ny = Center(swing)
local _, nearMover = Display("Durability", 40, 40, nx - W / 2 + 90, ny - H / 2 + 50)
Click(swingMover, "RightButton")
Fire(MenuRow("Select Snap Target"), "OnClick")
Click(meterMover, "LeftButton")
Check(swingMover._placement.snapTarget == "Threat Meter", "clicking an element makes it the snap target")
Click(swingMover, "RightButton")
Check(MenuRow("Snap Target: Threat Meter"), "the cog menu names it")
Fire(keys, "OnKeyDown", "ESCAPE")
local mL = meter:GetLeft()
local sx, sy = Center(swing)
cursor.x, cursor.y = sx, sy
UI.StartMoverDrag(swingMover)
cursor.x = sx + (mL - swing:GetLeft()) + 4
Drive()
UI.StopMoverDrag(swingMover)
Check(Near(swing:GetLeft(), mL), "a drag near its edge snaps to the snap target")
nearMover:Hide()

-- A mover laid over something other than its frame (a reminder's sample hangs below its small
-- anchor frame): anchoring reads what is seen.
local anchorFrame = NewFrame("Frame", UIParent)
anchorFrame:SetSize(10, 10)
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 500, 0)
local reminderSaved = {}
local reminderMover = UI.AttachMover(anchorFrame, "Reminder Bar", function(pos) reminderSaved[#reminderSaved + 1] = pos end)
local sample = NewFrame("Frame", anchorFrame)
sample:SetSize(120, 50)
sample:SetPoint("TOP", anchorFrame, "TOP", 0, 0)
reminderMover:ClearAllPoints()
reminderMover:SetAllPoints(sample)
reminderMover:Show()
settings.anchors["Reminder Bar"] = { target = "Threat Meter", side = "TOP" }
watcherFor = nil
for _, fr in ipairs(made) do
    if fr.events.PLAYER_ENTERING_WORLD then watcherFor = fr end
end
watcherFor.scripts.OnEvent(watcherFor, "PLAYER_ENTERING_WORLD")
Flush()
Check(Near(sample:GetBottom(), meter:GetTop()) and Near(select(1, sample:GetCenter()), select(1, meter:GetCenter())),
    "the sample, not the frame behind it, sits flush on its target")
Check(Last(reminderSaved).point == "CENTER", "and the frame's spot is saved")
sample:SetSize(120, 80)
reminderMover:SetAllPoints(sample)
Fire(reminderMover, "OnSizeChanged")
Flush()
Check(Near(sample:GetBottom(), meter:GetTop()), "a sample that grows is put back flush")
settings.anchors["Reminder Bar"] = nil
reminderMover:Hide()

-- A module's own drag of an anchored element keeps the anchor with the new gap.
settings.anchors["Swing Timer"] = { target = "Threat Meter", side = "BOTTOM", offsetX = 0, offsetY = 0 }
UI.ReapplyAnchors()
local sx0, sy0 = Center(swing)
swing:ClearAllPoints()
swing:SetPoint("CENTER", UIParent, "CENTER", sx0 - W / 2 + 25, sy0 - H / 2)
swing:StopMovingOrSizing()
Flush()
info = settings.anchors["Swing Timer"]
Check(info and Near(info.offsetX, 25) and Near(Center(swing), sx0 + 25), "a module drag keeps the anchor with the new offset")

-- While a module's grip resizes it, the anchor leaves it be; letting go keeps the new gap.
swing:StartSizing("BOTTOMRIGHT")
local gx, gt = swing:GetLeft(), swing:GetTop()
swing:ClearAllPoints()
swing:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", gx, gt)
swing:SetSize(160, 40)
Flush()
Check(Near(swing:GetLeft(), gx), "a grip resize from its corner is not fought")
swing:StopMovingOrSizing()
Flush()
Check(settings.anchors["Swing Timer"] and Near(settings.anchors["Swing Timer"].offsetX, 55), "and letting go keeps the new gap")
swing:SetSize(100, 40)
Flush()

-- A nudge waits while the target is missing, instead of piling up.
settings.anchors["Swing Timer"] = { target = "Gone", side = "BOTTOM", offsetX = 0, offsetY = 0 }
UI.SelectMover(swingMover)
Fire(keys, "OnKeyDown", "RIGHT")
Check(settings.anchors["Swing Timer"].offsetX == 0, "no nudge while the target is missing")
settings.anchors["Swing Timer"] = nil
UI.ClearMoverSelection()

-- Closing the cog menu with the cursor elsewhere shrinks the mover back.
Hover(swingMover)
Click(swingMover, "RightButton")
swingMover.mouseOver = false
Fire(swingMover, "OnLeave")
Flush()
Check(swingMover._placement.hoverConfirmed, "the open menu keeps it grown")
Fire(keys, "OnKeyDown", "ESCAPE")
Check(not swingMover._placement.hoverConfirmed and not swingMover._placement.hovered, "closing the menu lets it go")

-- At login and after a profile switch every anchor is re-applied, parents first.
settings.anchors["Swing Timer"] = { target = "Threat Meter", side = "BOTTOM", offsetX = 0, offsetY = -10 }
UI.EndMoverMode()
meter:ClearAllPoints()
meter:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
Flush()
local watcher
for _, fr in ipairs(made) do
    if fr.events.PLAYER_ENTERING_WORLD then watcher = fr end
end
watcher.scripts.OnEvent(watcher, "PLAYER_ENTERING_WORLD")
Flush()
cx, cy = Center(swing)
Check(Near(cx, 660) and Near(cy, 540 - 30 - 10 - 20), "a login places it under its target")
meter:ClearAllPoints()
meter:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
Flush()
Check(Near(Center(swing), 760), "a target its module moves takes it along")

-- In combat a protected element waits.
swing.protected, combat = true, true
meter:ClearAllPoints()
meter:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Flush()
Check(Near(Center(swing), 760), "a protected element does not move in combat")
combat = false
watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_ENABLED")
Flush()
Check(Near(Center(swing), 960), "and catches up after it")

print(("test-unlock-mode: %d checks passed"):format(checks))
