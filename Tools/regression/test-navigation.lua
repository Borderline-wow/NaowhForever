-- Exercise the real window, widgets and search using addon-owned sample settings.
-- Geometry is a test double; this does not emulate the game's renderer or taint rules.
local frames, timers = {}, {}
local methods = {}
local NOTHING_NS = setmetatable({}, { __index = function() return function() end end })
local env = setmetatable({}, { __index = function(_, k)
    local v = _G[k]
    if v ~= nil then return v end
    if type(k) == "string" and k:find("^C_") then return NOTHING_NS end
end })
env._G = env
local function New(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, points = {}, scripts = {},
        children = {}, visible = true, width = 0, height = 0, level = parent and parent.level + 1 or 0 },
        { __index = methods })
    frames[#frames + 1] = f
    if parent then parent.children[#parent.children + 1] = f end
    if name then env[name] = f end
    return f
end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point
    elseif relative == nil then relative, relativePoint, x, y = self.parent, point, 0, 0
    elseif type(relativePoint) == "number" then x, y, relativePoint = relativePoint, x, point end
    self.points[point] = { relative or self.parent, relativePoint or point, x or 0, y or 0 }
end
function methods:ClearAllPoints() self.points = {}; self.all = nil end
function methods:SetAllPoints(f) self.all = f or self.parent end
function methods:GetWidth()
    if self.all then return self.all:GetWidth() end
    local left, right = self.points.TOPLEFT or self.points.BOTTOMLEFT or self.points.LEFT,
        self.points.TOPRIGHT or self.points.BOTTOMRIGHT or self.points.RIGHT
    if left and right and left[1] == right[1] then return left[1]:GetWidth() + right[3] - left[3] end
    if self.kind == "FontString" and self.width == 0 then return self:GetStringWidth() end
    return self.width
end
function methods:GetHeight()
    if self.all then return self.all:GetHeight() end
    local top, bottom = self.points.TOPLEFT or self.points.TOPRIGHT or self.points.TOP,
        self.points.BOTTOMLEFT or self.points.BOTTOMRIGHT or self.points.BOTTOM
    if top and bottom and top[1] == bottom[1] then return top[1]:GetHeight() + top[4] - bottom[4] end
    if self.kind == "FontString" and self.height == 0 then return self:GetStringHeight() end
    return self.height
end
function methods:SetScript(k, v) self.scripts[k] = v end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k, v)
    local prior = self.scripts[k]
    self.scripts[k] = function(...) if prior then prior(...) end; v(...) end
end
function methods:Show()
    local was = self.visible; self.visible = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local was = self.visible; self.visible = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(on) if on then self:Show() else self:Hide() end end
function methods:IsShown() return self.visible and (not self.parent or self.parent:IsShown()) end
function methods:SetParent(p) self.parent = p end
function methods:GetParent() return self.parent end
function methods:GetChildren() return unpack(self.children) end
function methods:CreateTexture() return New("Texture", nil, self) end
function methods:GetObjectType() return self.kind end
-- One unit is one screen pixel here, so ns.Hairline and ns.PixelInset keep the layout's numbers.
function methods:GetEffectiveScale() return 1 end
env.PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end }
function methods:IsVisible() return self:IsShown() end
function methods:IsMouseOver() return false end
function methods:CreateFontString() return New("FontString", nil, self) end
function methods:SetFont(path, size, flags) self.font, self.size, self.flags = path, size, flags end
function methods:SetText(t)
    self.text = tostring(t or "")
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text or "" end
function methods:GetStringWidth() return #(self.text or "") * (self.size or 12) * 0.52 end
function methods:GetStringHeight() return self.size or 12 end
function methods:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
methods.SetColorTexture = methods.SetTextColor
methods.SetVertexColor = methods.SetTextColor
function methods:SetTexture(path) self.texture = path end
function methods:SetAlpha(a) self.alpha = a end
function methods:SetBlendMode(mode) self.blend = mode end
function methods:SetRotation(r) self.rotation = r end
function methods:SetJustifyH(j) self.justify = j end
function methods:SetFrameLevel(v) self.level = v end
function methods:GetFrameLevel() return self.level end
function methods:SetScrollChild(f) self.child = f; f:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0) end
function methods:SetVerticalScroll(v)
    self.scroll = v
    if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, v) end
end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetVerticalScrollRange() return math.max(0, (self.child and self.child:GetHeight() or 0) - self:GetHeight()) end
function methods:GetPoint()
    local p, v = next(self.points)
    if p then return p, unpack(v) end
end
function methods:SetValue(v) self.value = v end
function methods:GetValue() return self.value or 0 end
function methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function methods:GetMinMaxValues() return self.min, self.max end
function methods:GetEffectiveScale() return 1 end
function methods:GetScale() return 1 end
function methods:EnableMouse(v) self.mouse = v end
function methods:ClearFocus() self.focus = false end
function methods:SetFocus() self.focus = true end
function methods:HasFocus() return self.focus == true end
for _, name in ipairs({ "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "UnregisterAllEvents",
    "SetCursorPosition", "SetFontObject", "SetAutoFocus", "SetMultiLine", "SetMaxLetters", "SetNumeric", "SetTextInsets", "SetWordWrap", "SetSpacing",
    "SetFrameStrata", "SetScale", "SetMovable", "SetClampedToScreen", "EnableKeyboard", "SetPropagateKeyboardInput",
    "RegisterForDrag", "RegisterForClicks", "SetResizable", "SetResizeBounds", "SetNormalTexture", "SetHighlightTexture",
    "SetPushedTexture", "SetTexCoord", "SetTexelSnappingBias", "SetSnapToPixelGrid", "SetOrientation", "SetValueStep",
    "SetObeyStepOnDrag", "EnableMouseWheel", "UpdateScrollChildRect", "SetToplevel",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetHitRectInsets", "HighlightText",
    "StartMoving", "StopMovingOrSizing", "StartSizing" }) do methods[name] = function() end end
function methods:SetThumbTexture(t) self.thumbTexture = t end
env.CreateFrame = New
local VERBS = { "^Set", "^Get", "^Register", "^Unregister", "^Enable", "^Disable", "^Clear", "^Update",
    "^Start", "^Stop", "^Add", "^Remove", "^Play", "^Lock", "^Unlock" }
setmetatable(methods, { __index = function(_, k)
    if type(k) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
        if k:find(verb) then return function() end end
    end
end })
env.UIParent = New("Frame"); env.UIParent:SetSize(1920, 1080)
env.C_Timer = { After = function(_, f) timers[#timers + 1] = f end,
    NewTicker = function() return { Cancel = function() end } end }
-- missingAddOns: not loaded this session. disabled: switched off for the next reload.
local missingAddOns, disabled = {}, {}
env.C_AddOns = { GetAddOnMetadata = function() return "test" end,
    IsAddOnLoaded = function(name) return not missingAddOns[name] end,
    GetAddOnEnableState = function(name) return (missingAddOns[name] or disabled[name]) and 0 or 2 end,
    DisableAddOn = function(name) disabled[name] = true end,
    EnableAddOn = function(name) disabled[name] = nil end }
env.SlashCmdList = {}
env.InCombatLockdown = function() return false end
env.LibStub = function() return nil end
env.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
env.UnitName = function() return "Preview" end
env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
env.GetRealmName = function() return "Preview" end
env.GetTime = function() return 0 end
env.UNKNOWNOBJECT = "Unknown"
env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local function Load(path)
    local f = assert(loadfile(path)); setfenv(f, env); f("NaowhForever")
end
Load("Core/NaowhForever_Core.lua")
local ns = env.NaowhForever
local account, settings = {}, {}
ns.AccountSettings = function() return account end
ns.SettingsRoot = function() return settings end
ns.RegisterReapply = function() end
ns.QueueReapply = function() end
Load("Core/NaowhForever_Widgets.lua")
Load("Core/NaowhForever_UnlockMode.lua")
Load("Core/NaowhForever_Window.lua")
Load("Core/NaowhForever_Search.lua")
for _, path in ipairs(dofile("Tools/regression/toc_files.lua")("^Shared/.*%.lua$")) do Load(path) end
Load("QoL/NaowhForever_QoL.lua")
env.GameTooltip = New("Frame")
env.GameTooltip.GetOwner = function() return nil end
for _, name in ipairs({ "UnitGroupRolesAssigned", "GetShapeshiftFormID", "GetShapeshiftForm", "IsInGroup",
    "IsInRaid", "IsInInstance", "UnitExists", "UnitAffectingCombat", "IsStealthed", "IsResting", "IsMounted",
    "UnitOnTaxi", "UnitIsDeadOrGhost", "GetPartyAssignment", "GetPlayerAuraBySpellID", "UnitIsUnit" }) do
    env[name] = function() return nil end
end
env.GetNumGroupMembers = function() return 0 end
env.GetNumSubgroupMembers = function() return 0 end
env.GetNumShapeshiftForms = function() return 0 end
env.UnitHealth = function() return 1 end
env.UnitHealthMax = function() return 1 end
env.RegisterUnitWatch = function() end
env.RegisterStateDriver = function() end
env.UnregisterStateDriver = function() end
env.GetFramerate = function() return 60 end
env.GetNetStats = function() return 0, 0, 30, 30 end
env.IsInGuild = function() return false end
env.BNGetNumFriends = function() return 0, 0 end
env.date = os.date
env.UnregisterUnitWatch = function() end
env.Mixin = function(object, ...)
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do object[k] = v end
    end
    return object
end
env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, SetRGBA = function() end } end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.hooksecurefunc = function(target, key, fn)
    if type(target) == "table" then
        local prior = target[key]
        target[key] = function(...) if prior then prior(...) end; fn(...) end
    end
end
for _, path in ipairs({ "TopBar/NaowhForever_TopBar.lua", "QoL/NaowhForever_DeathRelease.lua",
    "QoL/NaowhForever_StealthReminder.lua", "QoL/NaowhForever_CoTank.lua" }) do Load(path) end
local UI = ns.UI
ns.BuildQoLInterfacePage = function(parent, y) return y end
for _, name in ipairs({ "JournalSettings", "DiscoverySettings", "ProfessionSettings", "MacroSettings", "AuraBuffSettings",
    "ThreatMeterSettings", "SwingTimerSettings", "TopBarSettings", "ActionBarSettings", "TrainingSettings" }) do
    ns[name] = UI.ModuleSettings(name, { enabled = false })
end
ns.DB = function() return settings end
ns.SetEnabled = function(v) settings.enabled = v end
local function Flush()
    while #timers > 0 do local q = timers; timers = {}; for _, fn in ipairs(q) do fn() end end
end
local function Text(text)
    for _, f in ipairs(frames) do if f.text == text and f:IsShown() then return f end end
end
local function Button(text)
    local label = assert(Text(text), "missing visible label: " .. text)
    local f = label.parent
    while f and not f.scripts.OnClick do f = f.parent end
    return assert(f, "missing button: " .. text)
end
local cases = 0
local function Check(ok, why) assert(ok, why); cases = cases + 1 end
local function Click(button) button.scripts.OnClick(button) end
ns.OpenOptionsWindow()
local function Head(name)
    local label = Text(name)
    local head = label and label.parent
    return head and head.card and head or nil
end
Check(Text("Quality of Life / Interface") ~= nil and Head("Top Bar") ~= nil, "opens to QoL Interface, the Top Bar's card first")
Check(Text("ADVENTURE") and Text("COMBAT") and Text("UTILITIES"), "grouped navigation")
Check(not Text("Custom Reminders"), "unfinished module is absent from navigation")
Check(Button("Quality of Life").switch == nil, "navigation does not toggle modules")
for _, name in ipairs({ "Quality of Life", "Dungeon Journal", "Discovery", "BiS List", "Professions",
    "Gear & Trinkets", "Blessings", "AuraBuffs", "Threat Meter", "Swing Timer", "Smart Reminders",
    "Macros", "Action Bars" }) do
    Check(Button(name).icon ~= nil, name .. " is listed with its glyph")
end
Check(Head("Top Bar").card.uid == "QoL/Interface:topBar", "Top Bar is a card on QoL Interface, not its own module")
local moduleList = Button("Action Bars").parent
local moduleScroll = moduleList.parent
local mainWindow = moduleScroll.parent.parent
local originalHeight = mainWindow:GetHeight()
mainWindow:SetHeight(790)
moduleScroll.scripts.OnSizeChanged(moduleScroll)
Check(moduleScroll:GetVerticalScrollRange() == 0, "all modules fit in the default 790-high window")
Check(not moduleScroll.ScrollBar:IsShown(), "navigation scrollbar hides when everything fits")
local lastModule = Button("Action Bars")
Check(-lastModule.points.TOPLEFT[4] + lastModule:GetHeight() <= moduleScroll:GetHeight(),
    "Action Bars fits fully above the fixed footer")
mainWindow:SetHeight(620)
moduleScroll.scripts.OnSizeChanged(moduleScroll)
Check(moduleScroll.ScrollBar:IsShown(), "short windows display a navigation scrollbar")
moduleScroll.scripts.OnMouseWheel(moduleScroll, -100)
Check(moduleScroll:GetVerticalScroll() == 0 and moduleScroll.scripts.OnUpdate, "the wheel glides instead of jumping")
for _ = 1, 100 do
    if not moduleScroll.scripts.OnUpdate then break end
    moduleScroll.scripts.OnUpdate(moduleScroll, 0.016)
end
Check(not moduleScroll.scripts.OnUpdate, "the glide stops once it lands")
Check(moduleScroll:GetVerticalScroll() == moduleScroll:GetVerticalScrollRange(), "wheel reaches the last module")
Check(moduleScroll.ScrollBar:GetValue() == moduleScroll:GetVerticalScroll(), "scrollbar follows wheel scrolling")
moduleScroll.ScrollBar.scripts.OnValueChanged(moduleScroll.ScrollBar, 20)
Check(moduleScroll:GetVerticalScroll() == 20, "dragging the scrollbar moves navigation")
mainWindow:SetHeight(originalHeight)
moduleScroll.scripts.OnSizeChanged(moduleScroll)
Check(moduleScroll:GetVerticalScroll() == 0 and not moduleScroll.ScrollBar:IsShown(),
    "growing the window clears the scroll offset and hides the scrollbar")

-- The page scrollbar drags itself: the thumb follows the cursor from where it was grabbed.
local pageScroll
for _, f in ipairs(frames) do if f.bar and f.parent == mainWindow then pageScroll = f end end
local pageBar = pageScroll.bar
local pageThumb, grip = pageBar.thumbTexture
for _, f in ipairs(pageBar.children) do if f.scripts.OnMouseDown then grip = f end end
Check(pageBar.mouse == false and grip.mouse, "the page scrollbar's own Slider drag is off, its grip takes the mouse")
local cursorY, buttonDown = 0, true
env.GetCursorPosition = function() return 0, cursorY end
env.IsMouseButtonDown = function() return buttonDown end
local BAR_TOP, THUMB_H, RANGE = 1000, 100, 1000
local travel = pageBar:GetHeight() - THUMB_H
pageThumb:SetHeight(THUMB_H)
pageBar:SetMinMaxValues(0, RANGE)
pageBar:SetValue(0)
pageThumb.GetCenter = function() return 0, BAR_TOP - THUMB_H / 2 - pageBar:GetValue() / RANGE * travel end
pageScroll.child:SetHeight(pageScroll:GetHeight() + RANGE)
pageScroll.scripts.OnMouseWheel(pageScroll, -1)
Check(pageScroll.scripts.OnUpdate ~= nil, "the page wheel glides")
cursorY = BAR_TOP - THUMB_H / 2 + 10
grip.scripts.OnMouseDown(grip, "LeftButton")
Check(pageScroll.scripts.OnUpdate == nil, "grabbing the scrollbar stops a wheel glide")
Check(pageBar:GetValue() == 0, "grabbing the thumb does not move it")
cursorY = cursorY - travel / 2
grip.scripts.OnUpdate(grip)
Check(pageBar:GetValue() == RANGE / 2, "dragging down scrolls down, in step with the cursor")
cursorY = cursorY + travel / 4
grip.scripts.OnUpdate(grip)
Check(pageBar:GetValue() == RANGE / 4, "dragging up scrolls back up")
buttonDown = false
grip.scripts.OnUpdate(grip)
Check(grip.scripts.OnUpdate == nil, "letting go ends the drag")
buttonDown = true
cursorY = BAR_TOP - pageBar:GetHeight()
grip.scripts.OnMouseDown(grip, "LeftButton")
Check(pageBar:GetValue() == RANGE, "a press on the track brings the thumb to the cursor")
grip.scripts.OnMouseUp(grip, "LeftButton")
pageBar:SetValue(0)
pageScroll:SetVerticalScroll(0)

ns.OpenOptionsWindow("QoL/Combat"); Flush()
local S = ns.QoLSettings
Check(Head("Stealth Reminder") and Head("Co-Tank Frame") and Head("Death Release Protection"),
    "each feature on the page is a card")
Check(not Text("Out of Stealth Colour") and not Text("Max Icons"), "cards start closed: their settings do not show")
local function Setting(label)
    local text = Text(label)
    return text and text.parent.setting and text.parent or nil
end
local coTank = Head("Co-Tank Frame")
coTank.switch.scripts.OnClick(coTank.switch); Flush()
Check(S.Get("coTank") and Setting("Max Icons") ~= nil, "turning a card on opens it")
Check(Setting("Max Icons").label.alpha == 1, "its settings are on while it is on")
local debuffs = Setting("Co-Tank Debuffs")
debuffs.controls.toggle.scripts.OnClick(debuffs.controls.toggle); Flush()
Check(not S.Get("coTankDebuffs") and Setting("Max Icons").label.alpha < 1, "a setting is dimmed while what it needs is off")
Check(Setting("Max Icons").why.text == "Needs Co-Tank Debuffs", "and says what it needs")
Setting("Co-Tank Debuffs").controls.toggle.scripts.OnClick(Setting("Co-Tank Debuffs").controls.toggle); Flush()
Check(S.Get("coTankDebuffs") and Setting("Max Icons").label.alpha == 1, "on again, it is back")
S.Set("coTankWidth", 222); Flush()
Check(Setting("Width").dot.visible and Text("Reset Co-Tank Frame") ~= nil, "a changed setting has its dot, and its card a reset")
local reset = Text("Reset Co-Tank Frame").parent
reset.scripts.OnClick(reset); Flush()
Check(S.Get("coTankWidth") == S.Default("coTankWidth") and not Text("Reset Co-Tank Frame"),
    "the reset puts the card's settings back")
coTank = Head("Co-Tank Frame")
coTank.switch.scripts.OnClick(coTank.switch); Flush()
Check(not S.Get("coTank") and Setting("Width").label.alpha < 1, "turned off, the card stays open with its settings dimmed")
coTank = Head("Co-Tank Frame")
coTank.scripts.OnClick(coTank); Flush()
Check(not Text("Max Icons"), "a click on its head closes it")
Check(S.Get("coTankDebuffs"), "closing it keeps its settings")
UI.searchOpen = { ["QoL/Combat:stealthReminder"] = true }
UI:RefreshPage(true); Flush()
Check(Setting("Out of Stealth Colour") ~= nil, "a card holding a search's hits opens while searching")
UI.searchOpen = nil
UI:RefreshPage(true); Flush()
Check(not Text("Out of Stealth Colour"), "and closes again after it")
UI.GoToSetting("QoL/Combat", "Out of Stealth Colour", "QoL/Combat:stealthReminder"); Flush()
Check(Setting("Out of Stealth Colour") ~= nil, "a search's jump opens the card and shows the setting")
ns.OpenOptionsWindow("QoL/Interface"); Flush()
local topBar = Head("Top Bar")
if not Text("24-Hour Clock") then Click(topBar); Flush() end
Check(not Text("Normal") and not Text("Faded") and not Text("In Combat"), "with nothing to compare, the studio shows no moments")
local barStore = topBar.card.store
barStore.Set("mouseover", true); barStore.Set("hideInCombat", true); Flush()
Check(Text("Normal") and Text("Faded") and Text("In Combat"), "an open card with a studio shows its moments")
Click(Button("Faded")); Flush()
-- A slider being dragged holds the page's redraw (it would hide the slider and end the drag),
-- and the page catches up once it is let go.
UI.sliderDrag = {}
barStore.Set("mouseoverAlpha", 30)
local held = timers; timers = {}
for _, fn in ipairs(held) do fn() end
Check(#timers > 0, "a slider being dragged holds the settings page's redraw")
UI.sliderDrag = nil
Flush()
Check(#timers == 0, "and the page draws again once it is let go")
barStore.Set("mouseoverAlpha", 40); Flush()
local studio
for _, f in ipairs(frames) do if f.previews and f:IsShown() then studio = f end end
local preview = studio and studio.previews[topBar.card]
Check(preview and preview.alpha == 0.4, "faded, the preview is at Faded Opacity, drawn again as the setting changes")
Check(Text("Drag to move, x to remove, + to add.") ~= nil, "the preview says how to edit the bar")
barStore.Set("hideInCombat", true)
Click(Button("In Combat")); Flush()
Check(preview.alpha == 0 and preview.sys.alpha == 1, "in combat it hides with Hide In Combat, its FPS / MS up")
barStore.Set("hideInCombat", false); barStore.Set("mouseover", false); Flush()
Click(Head("Top Bar")); Flush()
local found = 0
for _, target in ipairs(UI.Search.Collect()) do
    if target.page == "QoL/Interface" and target.label == "Faded Opacity" and target.card == "QoL/Interface:topBar" then
        found = found + 1
    end
end
Check(found == 1, "the search lists the declared settings, each once")
local strip = Button("Interface").parent
local tabs = 0
for _, child in ipairs(strip.children) do
    if child.scripts.OnClick then
        tabs = tabs + 1
        Check(child.points.LEFT and child.points.LEFT[4] == 0, "QoL categories share one row")
    end
end
Check(tabs == 9, "every QoL category has a tab")
Check(strip.buttons and strip:GetWidth() <= 1440 - 240 - 56, "the tabs are the boxed switch, inside the content width")
Click(Button("Combat")); Flush()
Check(Text("Quality of Life / Combat") ~= nil, "category navigation works")
Click(Button("Swing Timer")); Flush()
Check(Text("Swing Timer / Settings") and not Text("Interface"), "each module shows only its own page")
Click(Button("Threat Meter")); Flush()
Check(Text("Threat Meter / Settings") and not Text("Interface") and not Text("Cursor"),
    "single-page module shows no tab row")
Click(Button("Quality of Life")); Flush()
Check(Text("Quality of Life / Combat") ~= nil, "returning to a module remembers its page")
local count = #frames
for _ = 1, 8 do UI:RefreshPage(true); Flush() end
Check(#frames == count, "refreshes reuse controls without accumulating frames")
local root = env.NaowhForeverOptions
root:Hide(); UI:RefreshPage(true)
local hiddenCount = #frames
Check(#frames == hiddenCount, "hidden refresh does not build controls")
ns.OpenOptionsWindow("QoL/Combat"); Flush()
Check(Text("Death Release Protection") ~= nil, "reopening rebuilds the visible page")
local header = Text("Enable QoL").parent
local switch
for _, child in ipairs(header.children) do if child._get then switch = child end end
Check(switch and switch._get() == true, "header switch reads the current module")
ns.QoLSettings.Set("deathReleaseHold", 2)
switch.scripts.OnClick(); Flush()
Check(ns.QoLSettings.Get("enabled") == false and ns.QoLSettings.Get("deathReleaseHold") == 2,
    "module switch preserves feature settings")
Click(Button("Threat Meter")); Flush()
Check(switch._get() == false, "same switch rebinds to the newly selected module")
switch.scripts.OnClick(); Flush()
Check(ns.ThreatMeterSettings.Get("enabled") == true and ns.QoLSettings.Get("enabled") == false,
    "switch changes only the selected module")
Click(Button("Quality of Life")); Flush()
settings = { qol = { enabled = true, deathReleaseHold = 1.5 } }
UI:RefreshPage(true); Flush()
Check(switch._get() == true and ns.QoLSettings.Get("deathReleaseHold") == 1.5,
    "profile replacement refreshes controls against the new settings")
local beforeWidth = Head("Death Release Protection"):GetWidth()
root:SetWidth(1640); UI:RefreshPage(true); Flush()
Check(Head("Death Release Protection"):GetWidth() > beforeWidth, "cards grow with the window")
root:SetWidth(1440); UI:RefreshPage(true); Flush()
Check(Head("Death Release Protection"):GetWidth() == beforeWidth, "and shrink with it")
local pages = UI.SearchPages
UI.SearchPages = function()
    for _, page in ipairs(pages()) do if page.key == "QoL/Combat" then return { page } end end
end
local hit = UI.Search.Find(UI.Search.Collect(), "Out of Stealth Colour")[1]
Check(hit and hit.card == "QoL/Combat:stealthReminder" and hit.trail:find("Stealth Reminder", 1, true),
    "a setting is found in its card, the card named in its trail")
local debuffHit = UI.Search.Find(UI.Search.Collect(), "Co-Tank Debuffs")[1]
Check(debuffHit and debuffHit.card == "QoL/Combat:coTank", "a setting's card is the one it opens")
local iconHit = UI.Search.Find(UI.Search.Collect(), "Max Icons")[1]
UI.GoToSetting("QoL/Combat", "Max Icons", iconHit.card); Flush()
Check(Text("Co-Tank Debuffs") and Text("Max Icons"), "the jump opens its card")
UI.SearchPages = pages
for _, page in ipairs(UI.SearchPages()) do Check(not page.soon, "unfinished pages are not search results") end

-- The search bar: Ctrl+F opens it under the header, typing finds, Enter and Shift+Enter step
-- through the matches, each landing on its page and row, and Escape closes it and clears the mark.
do
    local ctrl, shift = false, false
    env.IsControlKeyDown = function() return ctrl end
    env.IsShiftKeyDown = function() return shift end
    ns.OpenOptionsWindow("QoL/Interface"); Flush()
    Check(Button("Search  " .. ns.Color("muted", "Ctrl+F")) ~= nil, "the header has the Search button")
    Check(not Text("SEARCH"), "the bar starts closed")
    local pageHeader = Text("Quality of Life / Interface").parent
    local pageTop = pageHeader.points.TOPLEFT[4]
    ctrl = true
    root.scripts.OnKeyDown(root, "F"); Flush()
    ctrl = false
    Check(Text("SEARCH") ~= nil and root:IsShown(), "Ctrl+F opens the search bar")
    local bar = Text("SEARCH").parent
    Check(bar.points.TOPLEFT and bar.points.TOPLEFT[4] == -64, "it sits right under the window's header")
    Check(pageHeader.points.TOPLEFT[4] == pageTop - bar:GetHeight(), "and pushes the page down")
    Check(Text("Setting, card or page") ~= nil, "its box says what it finds")
    local input
    for _, child in ipairs(bar.children) do if child.scripts.OnEnterPressed then input = child end end
    Check(input and input:HasFocus(), "the cursor is in its box")

    local function Chips()
        local out = {}
        for _, child in ipairs(bar.children) do
            if child.index and child:IsShown() then out[#out + 1] = child end
        end
        return out
    end
    local expected = UI.Search.Find(UI.Search.Collect(), "max icons")
    input:SetText("max icons"); Flush()
    Check(Text("1 of " .. #expected) ~= nil, "the counter says which match is on show, of how many")
    Check(#Chips() == #expected, "a chip for each match")
    Check(Text("Quality of Life / Combat") ~= nil, "the first match's page opens")
    Check(Setting("Max Icons") and Setting("Max Icons").found:IsShown(), "its row carries the search's mark")
    Check(UI.searchOpen and UI.searchOpen["QoL/Combat:coTank"], "its card is held open while the bar is up")
    local chipText = Chips()[1].tag.text .. Chips()[1].text.text
    Check(Chips()[1].tag.text == "QOL" and not chipText:find(">", 1, true), "a chip starts with its module's tag, no >")

    local all = UI.Search.Find(UI.Search.Collect(), "colour")
    input:SetText("colour"); Flush()
    Check(#all > 2 and Text("1 of " .. #all), "typing again starts over")
    input.scripts.OnEnterPressed(input); Flush()
    Check(Text("2 of " .. #all) and UI.searchFocus.label == all[2].label, "Enter steps to the next match")
    shift = true
    input.scripts.OnEnterPressed(input); Flush()
    input.scripts.OnEnterPressed(input); Flush()
    shift = false
    Check(Text(#all .. " of " .. #all) and UI.searchFocus.label == all[#all].label,
        "Shift+Enter steps back, round to the last")
    local lit
    for _, c in ipairs(Chips()) do if c.index == #all then lit = c end end
    Check(lit ~= nil, "the chips keep the current match in view")
    local chip = Chips()[1]
    chip.scripts.OnClick(chip); Flush()
    Check(Text(chip.index .. " of " .. #all) and UI.searchFocus.label == all[chip.index].label,
        "a chip jumps to its match")

    input:SetText("zzzz"); Flush()
    Check(Text("No match") and #Chips() == 0 and UI.searchFocus == nil, "nothing found, nothing marked")

    input:SetText("max icons"); Flush()
    root.scripts.OnKeyDown(root, "ESCAPE"); Flush()
    Check(root:IsShown() and not bar.visible, "Escape closes the bar, not the window")
    Check(UI.searchFocus == nil and UI.searchOpen == nil, "and clears the marks")
    Check(Setting("Max Icons") and not Setting("Max Icons").found:IsShown(), "the row loses its mark")
    Check(Text("Max Icons") ~= nil, "the card holding the last match stays open")
    Check(input:GetText() == "" and Text("1 of 1") == nil, "and the bar starts empty next time")
    Check(pageHeader.points.TOPLEFT[4] == pageTop, "the page moves back up")

    root.scripts.OnKeyDown(root, "F"); Flush()
    Check(not bar.visible, "F alone does nothing")
    ctrl = true
    root.scripts.OnKeyDown(root, "F"); Flush()
    ctrl = false
    input.scripts.OnEscapePressed(input); Flush()
    Check(not bar.visible and root:IsShown(), "Escape in the box closes the bar too")
    root.scripts.OnKeyDown(root, "ESCAPE"); Flush()
    Check(not root:IsShown(), "with the bar closed, Escape closes the window")
    ns.OpenOptionsWindow("QoL/Combat"); Flush()
end

-- A confirm: No, Escape and a newer confirm taking its place all count as no; Yes does not.
do
    local yes, no = 0, 0
    local function Ask() ns.Confirm("Sure?", function() yes = yes + 1 end, function() no = no + 1 end) end
    Ask(); Click(Button("Yes")); Flush()
    Check(yes == 1 and no == 0, "Yes confirms without counting as no")
    Ask(); Click(Button("No")); Flush()
    Check(yes == 1 and no == 1, "No cancels")
    Ask()
    local dimmer = Text("Sure?").parent.parent
    dimmer.scripts.OnKeyDown(dimmer, "ESCAPE"); Flush()
    Check(yes == 1 and no == 2 and not dimmer:IsShown(), "Escape cancels")
    Ask(); Ask()
    Check(no == 3, "a confirm taking another's place cancels that one")
    Click(Button("No")); Flush()
    Check(no == 4 and yes == 1, "and the new one still answers once")
end

-- A module shipped as its own addon: switching it off disables the addon, with every module
-- linked to it, once the player confirms.
local confirmText, confirmYes, reloadText
ns.Confirm = function(text, yes) confirmText, confirmYes = text, yes end
ns.ConfirmReload = function(text) reloadText = text end
Click(Button("Dungeon Journal")); Flush()
switch.scripts.OnClick(); Flush()
Check(ns.JournalSettings.Get("enabled") == true and confirmText == nil, "switching an addon module on needs no reload")
switch.scripts.OnClick(); Flush()
Check(confirmText and confirmText:find("BiS List", 1, true) and confirmText:find("both", 1, true),
    "switching the journal off says BiS List goes with it")
Check(next(disabled) == nil, "nothing is disabled before the player confirms")
confirmYes()
Check(disabled.NaowhForever_DungeonJournal and disabled.NaowhForever_BiS, "confirming disables both addons")
Check(reloadText and reloadText:find("reload", 1, true), "then offers the reload")
Check(ns.JournalSettings.Get("enabled") == true, "the module's own switch is kept for when it comes back")
Check(switch._get() == false, "the switch reads off while the disable waits for its reload")
switch.scripts.OnClick(); Flush()
Check(not disabled.NaowhForever_DungeonJournal and not disabled.NaowhForever_BiS and switch._get() == true,
    "switching it back on before the reload cancels the disable, for both")
confirmText = nil
Click(Button("Professions")); Flush()
switch.scripts.OnClick(); Flush()
switch.scripts.OnClick(); Flush()
Check(confirmText and confirmText:find("Training Planner", 1, true), "Professions takes Training Planner with it")
confirmYes()
Check(disabled.NaowhForever_Professions and disabled.NaowhForever_Training and not disabled.NaowhForever_BiS,
    "and only the modules that need it")
missingAddOns.NaowhForever_Professions = true
for _, page in ipairs(UI.SearchPages()) do
    Check(not (page.module and page.module.name == "Professions"), "a module addon that is not loaded is not searched")
end
ns.OpenOptionsWindow("Professions/Settings"); Flush()
Check(Text("MODULES") ~= nil, "a link to a module that is off lands on Settings, where it is turned back on")
missingAddOns.NaowhForever_Professions = nil

ns.OpenOptionsWindow("Blessings/Settings"); Flush()
Check(Text("Blessings / Settings") ~= nil, "existing module/tab deep links still work")
ns.OpenOptionsWindow("QoL/Combat"); Flush()
local Settings = ns.Shared.Settings
local function British(text) return not (text and text:find("Color", 1, true)) end
for key, page in pairs(Settings.pages) do
    for _, card in ipairs(page.items) do
        if not card.window then
            local where = key .. " > " .. card.name
            Check(card.help and card.help ~= "", where .. " has its help")
            Check(British(card.name) and British(card.help), where .. " spells Colour the house's way")
            if type(card.switch) == "string" then
                Check(card.store.Default(card.switch) ~= nil, where .. ": its switch has a default")
            end
            local labels = {}
            for _, row in ipairs(Settings.Rows(card)) do
                if row.kind ~= "group" then
                    local what = where .. " > " .. tostring(row.label)
                    Check(row.label and not labels[row.label], what .. " has a name of its own on the card")
                    labels[row.label] = true
                    Check(British(row.label) and British(row.help), what .. " spells Colour the house's way")
                    if row.key and row.store == card.store then
                        Check(card.store.Default(row.key) ~= nil, what .. ": " .. row.key .. " has a default")
                    end
                    local needs = type(row.needs) == "string" and { row.needs } or type(row.needs) == "table" and row.needs or {}
                    for _, need in ipairs(needs) do
                        Check(row.store.Default(need) ~= nil, what .. " needs a real setting: " .. need)
                    end
                end
            end
        end
    end
end
print(cases .. " navigation checks passed")
-- Available only to an offline renderer that loads this test environment.
local capture = rawget(_G, "NAVIGATION_CAPTURE")
if capture then capture(env, frames, ns, Flush) end
