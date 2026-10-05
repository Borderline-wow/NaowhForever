-- Run with Lua 5.1 from the repository root: Unlock Mode's placement controls, cut out of
-- Core/NaowhForever_Widgets.lua and run against frame stubs. No position box is drawn, and
-- selecting, nudging, dragging and combat still work and save.
local f = assert(io.open("Core/NaowhForever_Widgets.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local body = assert(source:match("\n(local placement = .-)\n%-%- Font dropdown data"), "placement section")

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local made = { frames = {}, textures = 0, fonts = 0 }
local Frame = {}
Frame.__index = Frame
local function NewFrame(parent)
    local fr = setmetatable({ parent = parent, scripts = {}, hooks = {}, shown = true, points = {}, events = {} }, Frame)
    made.frames[#made.frames + 1] = fr
    return fr
end
local function Region()
    return setmetatable({}, { __index = function() return function() end end })
end
function Frame:CreateTexture() made.textures = made.textures + 1; self.drawn = true; return Region() end
function Frame:CreateFontString() made.fonts = made.fonts + 1; self.drawn = true; return Region() end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn) self.hooks[name] = fn end
function Frame:Show() self.shown = true end
function Frame:Hide()
    local was = self.shown
    self.shown = false
    if was and self.hooks.OnHide then self.hooks.OnHide(self) end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x or 0, y or 0 }
end
function Frame:SetAllPoints() self.points = { { "TOPLEFT", self.parent, "TOPLEFT", 0, 0 } } end
function Frame:GetPoint(i)
    local p = self.points[i]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:GetWidth() return self.w or 0 end
function Frame:GetHeight() return self.h or 0 end
function Frame:GetLeft() return 100 end
function Frame:GetBottom() return 200 end
function Frame:GetCenter() return 150, 220 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameLevel() return 1 end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:EnableKeyboard(v) self.keyboard = v end
function Frame:EnableMouse(v) self.mouse = v end
function Frame:SetPropagateKeyboardInput(v) self.propagate = v end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:IsProtected() return false end
for _, name in ipairs({ "SetFrameStrata", "SetFrameLevel", "RegisterForDrag" }) do
    Frame[name] = function() end
end

local UIParent = NewFrame()
UIParent.w, UIParent.h = 1920, 1080
local combat, shift = false, false
local env = setmetatable({
    UI = {}, T = { accent = {}, accentSoft = {} }, BLACK = {},
    ns = {
        Solid = function(parent) return parent:CreateTexture() end,
        Border = function(frame) return NewFrame(frame) end,
        Font = function(parent) return parent:CreateFontString() end,
        HideRaidReminderAnchorConfig = function() end,
        OpenOptionsWindow = function() end,
    },
    UIParent = UIParent,
    CreateFrame = function(_, _, parent) return NewFrame(parent) end,
    InCombatLockdown = function() return combat end,
    IsShiftKeyDown = function() return shift end,
    GetCurrentKeyBoardFocus = function() return nil end,
    MenuUtil = { CreateContextMenu = function() end },
}, { __index = _G })
local chunk = assert(loadstring(body))
setfenv(chunk, env)
chunk()
local UI = env.UI

Check(not source:find("placement.hud", 1, true), "the position box is gone from Widgets.lua")

local display = NewFrame(UIParent)
display:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 1118, 1117)
local saved = {}
local mover = UI.AttachMover(display, "Campfire", function(pos) saved[#saved + 1] = pos end, "QoL/General")
mover:Show()

local before = { frames = #made.frames, textures = made.textures, fonts = made.fonts }
UI.BeginMoverMode()
Check(made.fonts == before.fonts, "Unlock Mode draws no text of its own")
local keys
for i = before.frames + 1, #made.frames do
    if made.frames[i].scripts.OnKeyDown then keys = made.frames[i] end
end
Check(keys ~= nil, "a frame takes the arrow keys")
Check(not keys.drawn and not keys.mouse, "the key frame draws nothing and takes no clicks")
Check(keys.events.PLAYER_REGEN_DISABLED and keys.events.PLAYER_REGEN_ENABLED, "combat is still watched")

UI.SelectMover(mover)
Check(made.fonts == before.fonts, "selecting a display draws no text")
local outline
for i = before.frames + 1, #made.frames do
    local fr = made.frames[i]
    if fr ~= keys and fr.w and fr.w > 1 and fr.h and fr.h > 1 and fr.shown then outline = fr end
end
Check(outline ~= nil, "the outline still shows around the selected display")

keys.scripts.OnKeyDown(keys, "RIGHT")
local last = saved[#saved]
Check(last and last.point == "LEFT" and last.relPoint == "BOTTOMLEFT" and last.x == 1119 and last.y == 1117,
    "an arrow nudges by 1 and saves")
Check(keys.propagate == false, "a used arrow key is not passed on")
shift = true
keys.scripts.OnKeyDown(keys, "UP")
shift = false
last = saved[#saved]
Check(last.x == 1119 and last.y == 1127, "Shift + arrow nudges by 10 and saves")

local count = #saved
mover.scripts.OnDragStart()
Check(display.moving, "dragging moves the display")
display:ClearAllPoints()
display:SetPoint("CENTER", UIParent, "CENTER", -40, 25)
mover.scripts.OnDragStop()
last = saved[#saved]
Check(#saved == count + 1 and last.point == "CENTER" and last.x == -40 and last.y == 25,
    "a drag saves where it was dropped")

combat = true
keys.scripts.OnEvent(keys, "PLAYER_REGEN_DISABLED")
Check(not keys:IsShown(), "the key frame stops in combat")
count = #saved
keys.scripts.OnKeyDown(keys, "LEFT")
Check(#saved == count, "no nudge in combat")
combat = false
keys.scripts.OnEvent(keys, "PLAYER_REGEN_ENABLED")
Check(keys:IsShown(), "Unlock Mode carries on after combat")
UI.SelectMover(mover)
keys.scripts.OnKeyDown(keys, "LEFT")
Check(#saved == count + 1, "nudges work again after combat")

UI.EndMoverMode()
Check(not keys:IsShown() and keys.keyboard == false, "leaving Unlock Mode stops the keys")
Check(made.fonts == before.fonts, "nothing in Unlock Mode drew text")

print(("test-unlock-mode: %d checks passed"):format(checks))
