-- Exercise the real window, widgets and search using addon-owned sample settings.
-- Geometry is a test double; this does not emulate the game's renderer or taint rules.
local frames, timers = {}, {}
local methods = {}
local env = setmetatable({}, { __index = _G })
env._G = env
local function New(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, points = {}, scripts = {},
        children = {}, shown = true, width = 0, height = 0, level = parent and parent.level + 1 or 0 },
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
    local was = self.shown; self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local was = self.shown; self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(on) if on then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function methods:SetParent(p) self.parent = p end
function methods:GetParent() return self.parent end
function methods:GetChildren() return unpack(self.children) end
function methods:CreateTexture() return New("Texture", nil, self) end
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
    "SetObeyStepOnDrag", "SetThumbTexture", "EnableMouseWheel", "UpdateScrollChildRect", "SetToplevel",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetHitRectInsets", "HighlightText",
    "StartMoving", "StopMovingOrSizing", "StartSizing" }) do methods[name] = function() end end
env.CreateFrame = New
env.UIParent = New("Frame"); env.UIParent:SetSize(1920, 1080)
env.C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
env.C_AddOns = { GetAddOnMetadata = function() return "test" end }
env.SlashCmdList = {}
env.InCombatLockdown = function() return false end
env.LibStub = false
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
Load("Core/NaowhForever_Window.lua")
Load("Core/NaowhForever_Search.lua")
Load("QoL/NaowhForever_QoL.lua")
local UI = ns.UI
ns.BuildQoLInterfacePage = function(parent, y) return y end
for _, name in ipairs({ "JournalSettings", "DiscoverySettings", "ProfessionSettings", "MacroSettings", "AuraBuffSettings",
    "ThreatMeterSettings", "SwingTimerSettings", "TopBarSettings", "ActionBarSettings" }) do
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
ns.OpenOptionsWindow()
Check(Text("Top Bar / Bar") ~= nil, "opens to the Top Bar")
Check(Text("ADVENTURE") and Text("COMBAT") and Text("UTILITIES"), "grouped navigation")
Check(not Text("Custom Reminders"), "unfinished module is absent from navigation")
Check(Button("Quality of Life").switch == nil, "navigation does not toggle modules")
for _, name in ipairs({ "Quality of Life", "Dungeon Journal", "Discovery", "BiS List", "Professions",
    "Gear & Trinkets", "Blessings", "AuraBuffs", "Threat Meter", "Swing Timer", "Smart Reminders",
    "Macros", "Action Bars", "Top Bar" }) do
    Check(Button(name).icon ~= nil, name .. " is listed with its glyph")
end
local moduleList = Button("Top Bar").parent
local moduleScroll = moduleList.parent
local mainWindow = moduleScroll.parent.parent
local originalHeight = mainWindow:GetHeight()
mainWindow:SetHeight(790)
moduleScroll.scripts.OnSizeChanged(moduleScroll)
Check(moduleScroll:GetVerticalScrollRange() == 0, "all modules fit in the default 790-high window")
Check(not moduleScroll.ScrollBar:IsShown(), "navigation scrollbar hides when everything fits")
local lastModule = Button("Top Bar")
Check(-lastModule.points.TOPLEFT[4] + lastModule:GetHeight() <= moduleScroll:GetHeight(),
    "Top Bar fits fully above the fixed footer")
mainWindow:SetHeight(620)
moduleScroll.scripts.OnSizeChanged(moduleScroll)
Check(moduleScroll.ScrollBar:IsShown(), "short windows display a navigation scrollbar")
moduleScroll.scripts.OnMouseWheel(moduleScroll, -100)
Check(moduleScroll:GetVerticalScroll() == moduleScroll:GetVerticalScrollRange(), "wheel reaches the last module")
Check(moduleScroll.ScrollBar:GetValue() == moduleScroll:GetVerticalScroll(), "scrollbar follows wheel scrolling")
moduleScroll.ScrollBar.scripts.OnValueChanged(moduleScroll.ScrollBar, 20)
Check(moduleScroll:GetVerticalScroll() == 20, "dragging the scrollbar moves navigation")
mainWindow:SetHeight(originalHeight)
moduleScroll.scripts.OnSizeChanged(moduleScroll)
Check(moduleScroll:GetVerticalScroll() == 0 and not moduleScroll.ScrollBar:IsShown(),
    "growing the window clears the scroll offset and hides the scrollbar")

ns.OpenOptionsWindow("QoL/General"); Flush()
Check(not Text("Appearance & text"), "disabled stealth starts collapsed")
Check(not Text("Co-Tank Debuffs"), "collapsed co-tank frame hides its debuff section")
local function FeatureSwitch(label)
    for _, row in ipairs(frames) do
        if row._feature and row._searchL == label then return row._leftRegion._control end
    end
end
local coTankSwitch = assert(FeatureSwitch("Co-Tank Frame"))
coTankSwitch.scripts.OnClick(); Flush()
Check(Text("Co-Tank Debuffs") and not Text("Max Icons"), "enabling frame reveals nested debuff header")
local debuffSwitch = assert(FeatureSwitch("Co-Tank Debuffs"))
Check(ns.QoLSettings.Get("coTankDebuffs"), "saved debuff preference remains enabled")
debuffSwitch.scripts.OnClick(); Flush()
Check(not ns.QoLSettings.Get("coTankDebuffs") and not Text("Max Icons"), "disabling debuffs closes their controls")
debuffSwitch.scripts.OnClick(); Flush()
Check(Text("Max Icons") ~= nil, "enabling debuffs opens their controls")
coTankSwitch.scripts.OnClick(); Flush()
Check(not Text("Co-Tank Debuffs") and not Text("Max Icons"), "disabling frame hides both nested levels")
Check(ns.QoLSettings.Get("coTankDebuffs"), "disabling frame preserves debuff preference")

local stealthSwitch
for _, row in ipairs(frames) do
    if row._feature and row._searchL == "Stealth Reminder" then
        stealthSwitch = row._leftRegion._control
        break
    end
end
Check(stealthSwitch ~= nil, "feature toggle is available while collapsed")
stealthSwitch.scripts.OnClick(); Flush()
Check(ns.QoLSettings.Get("stealthReminder") and Text("Appearance & text"), "turning on expands the feature")
stealthSwitch.scripts.OnClick(); Flush()
Check(not ns.QoLSettings.Get("stealthReminder") and not Text("Appearance & text"),
    "turning off collapses the feature")
stealthSwitch.scripts.OnClick(); Flush()
UI.searchOpen = { ["QoL/General:Enable Stealth Reminder"] = true }
stealthSwitch.scripts.OnClick(); Flush()
Check(not Text("Appearance & text"), "turning off also collapses a search-expanded feature")
UI.searchOpen = nil
UI.OpenFeature("QoL/General:Enable Stealth Reminder")
UI:RefreshPage(true); Flush()
Check(Text("Appearance & text") and not Text("Out of Stealth Colour"), "appearance starts closed")
UI.GoToSetting("QoL/General", "Out of Stealth Colour", "QoL/General:QoL/General:Enable Stealth Reminder:appearance")
Check(Text("Out of Stealth Colour") ~= nil, "search jump reveals nested controls")
local generalTab = Button("General")
local strip = generalTab.parent
local lastTab = generalTab
for _, tab in ipairs(strip.children) do
    Check(tab.points.TOPLEFT[4] == 0, "QoL categories share one row")
    if tab.points.TOPLEFT[3] > lastTab.points.TOPLEFT[3] then lastTab = tab end
end
Check(#strip.children == 12, "every QoL category has a tab")
Check(lastTab.points.TOPLEFT[3] + lastTab:GetWidth() <= strip:GetWidth() - 30,
    "the last QoL tab stops short of the scrollbar at the default width")
Button("Interface").scripts.OnClick(); Flush()
Check(Text("Quality of Life / Interface") ~= nil, "category navigation works")
Button("Swing Timer").scripts.OnClick(); Flush()
Check(Text("Bars") and Text("Timing Aids") and not Text("General"), "each module shows only its own tabs")
Button("Top Bar").scripts.OnClick(); Flush()
Check(not Text("General") and not Text("Bar"), "single-page module shows no tab row")
Button("Quality of Life").scripts.OnClick(); Flush()
Check(Text("Quality of Life / Interface") ~= nil, "returning to a module remembers its page")
Button("General").scripts.OnClick(); Flush()
local count = #frames
for _ = 1, 8 do UI:RefreshPage(true); Flush() end
Check(#frames == count, "refreshes reuse controls without accumulating frames")
local root = env.NaowhForeverOptions
root:Hide(); UI:RefreshPage(true)
local hiddenCount = #frames
Check(#frames == hiddenCount, "hidden refresh does not build controls")
ns.OpenOptionsWindow("QoL/General"); Flush()
Check(Text("Death Release Protection") ~= nil, "reopening rebuilds the visible page")
local header = Text("Enable QoL").parent
local switch
for _, child in ipairs(header.children) do if child._get then switch = child end end
Check(switch and switch._get() == true, "header switch reads the current module")
ns.QoLSettings.Set("deathReleaseHold", 2)
switch.scripts.OnClick(); Flush()
Check(ns.QoLSettings.Get("enabled") == false and ns.QoLSettings.Get("deathReleaseHold") == 2,
    "module switch preserves feature settings")
Button("Top Bar").scripts.OnClick(); Flush()
Check(switch._get() == false, "same switch rebinds to the newly selected module")
switch.scripts.OnClick(); Flush()
Check(ns.TopBarSettings.Get("enabled") == true and ns.QoLSettings.Get("enabled") == false,
    "switch changes only the selected module")
Button("Quality of Life").scripts.OnClick(); Flush()
settings = { qol = { enabled = true, deathReleaseHold = 1.5 } }
UI:RefreshPage(true); Flush()
Check(switch._get() == true and ns.QoLSettings.Get("deathReleaseHold") == 1.5,
    "profile replacement refreshes controls against the new settings")
local beforeWidth = Text("Only In a Group").parent:GetWidth()
root:SetWidth(1640); UI:RefreshPage(true); Flush()
Check(Text("Only In a Group").parent:GetWidth() > beforeWidth, "cached regions grow on resize")
root:SetWidth(1440); UI:RefreshPage(true); Flush()
Check(Text("Only In a Group").parent:GetWidth() == beforeWidth, "cached regions shrink on resize")
local pages = UI.SearchPages
UI.SearchPages = function()
    for _, page in ipairs(pages()) do if page.key == "QoL/General" then return { page } end end
end
local hit = UI.Search.Match(UI.Search.Build(), "Out of Stealth Colour")[1]
Check(hit and hit.feature, "nested appearance controls are indexed")
local opened = { [hit.feature] = true }
UI.MarkFeatureParents(opened)
Check(opened["QoL/General:Enable Stealth Reminder"], "search marking includes the parent feature")
local debuffHit = UI.Search.Match(UI.Search.Build(), "Co-Tank Debuffs")[1]
Check(debuffHit and debuffHit.feature == "QoL/General:Co-Tank Frame",
    "search for nested header opens its parent")
local iconHit = UI.Search.Match(UI.Search.Build(), "Max Icons")[1]
Check(iconHit and iconHit.feature, "nested debuff options remain searchable")
UI.GoToSetting("QoL/General", "Max Icons", iconHit.feature); Flush()
Check(Text("Co-Tank Debuffs") and Text("Max Icons"), "search jump reveals both co-tank levels")
UI.SearchPages = pages
for _, page in ipairs(UI.SearchPages()) do Check(not page.soon, "unfinished pages are not search results") end
ns.OpenOptionsWindow("BiS List/List"); Flush()
Check(Text("BiS List / List") ~= nil, "existing module/tab deep links still work")
ns.OpenOptionsWindow("QoL/General"); Flush()
print(cases .. " navigation checks passed")
-- Available only to an offline renderer that loads this test environment.
local capture = rawget(_G, "NAVIGATION_CAPTURE")
if capture then capture(env, frames, ns, Flush) end
