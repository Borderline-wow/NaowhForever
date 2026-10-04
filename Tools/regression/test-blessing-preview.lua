-- Run with Lua 5.1 from the repository root: the Blessing Bar card's preview edits the bar. The
-- x hides the aura or Righteous Fury button and the + brings it back, the wheel sets Button Size
-- (Shift: Button Spacing) within the sliders' ranges, dragging the gap sets the Aura / Class Gap,
-- a paladin's right-click on a class and click on the aura open the bar's own menus and write
-- the plan, nothing is editable while Blessings is off, and hovering or the wheel makes no garbage.
-- The preview is plain frames, never the bar's secure buttons. Frames here are stubs: this does
-- not emulate the game's renderer, menus or taint rules.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end
local Measure = dofile("Tools/regression/measure.lua")(check)

local methods = {}
local frameMeta = { __index = function(_, k)
    local m = methods[k]
    if m then return m end
    if type(k) == "string" and k:find("^[A-Z]") then return methods.Nothing end
end }
local function New(kind, parent)
    return setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, w = 0, h = 0,
        level = parent and parent.level + 1 or 0 }, frameMeta)
end
function methods.Nothing() end
function methods:SetScript(k, v) self.scripts[k] = v end
function methods:HookScript(k, v)
    local prior = self.scripts[k]
    self.scripts[k] = prior and function(...) prior(...); v(...) end or v
end
function methods:Show() self.shown = true end
function methods:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(on) if on then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:SetWidth(w) self.w = w end
function methods:SetAllPoints() self.all = true end
function methods:GetWidth() if self.all then return self.parent:GetWidth() end return self.w end
function methods:GetHeight() if self.all then return self.parent:GetHeight() end return self.h end
function methods:SetPoint(_, relative, _, x) self.anchor, self.x = relative, x end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(v) self.level = v end
function methods:GetEffectiveScale() return 1 end
function methods:IsMouseOver() return self.over == true end
function methods:EnableMouseWheel(on) self.wheel = on end
function methods:SetText(t) self.text = t end
function methods:SetTexture(t) self.texture = t end
function methods:CreateTexture() return New("Texture", self) end
function methods:CreateFontString() return New("FontString", self) end

local settings = {}
local defaults = { blessings = true, blessBarSize = 30, blessSpacing = 6, blessGroupSpacing = 6,
    blessTimerSize = 14, blessShowLabels = true, blessTimers = true, blessShowAura = true, blessShowFury = false }
local sets = 0
local S = {}
function S.Get(k) local v = settings[k]; if v == nil then return defaults[k] end return v end
function S.Set(k, v) settings[k] = v; sets = sets + 1 end

local THEME = { fg = { r = 1, g = 1, b = 1 }, muted = { r = 0.6, g = 0.6, b = 0.6 },
    accent = { r = 0, g = 0.57, b = 0.93 }, bg = { r = 0, g = 0, b = 0 } }
local cards = {}
local account = {}
local refreshed = 0
local ns = {
    QoLSettings = S, THEME = THEME,
    Apply = function() end, ShowRaidReminderAnchorConfig = function() end, HideRaidReminderAnchorConfig = function() end,
    AccountSettings = function() return account end,
    OpenBlessingsWindow = function() end,
    PixelInset = function() end, Border = function() end, UIFontPath = function() return "font" end,
    Font = function(parent) return New("FontString", parent) end,
    Solid = function(parent) return New("Texture", parent) end,
    Color = function(_, text) return text end,
    Tooltip = function(frame, title, body) frame.tipTitle, frame.tipBody = title, body end,
    UI = { RefreshPage = function() refreshed = refreshed + 1 end },
    Shared = {
        Style = { PLUS = "plus", CROSS = "cross", OPACITY_MIN = 20 },
        Settings = {
            Group = function(name) return { group = name } end,
            Page = function()
                return { Window = function() end, Card = function(_, card) cards[card.id] = card end }
            end,
        },
    },
}

local class = "WARRIOR"
local menu
local function Root()
    local root = { items = {} }
    local function Add(kind, label, a, b) root.items[#root.items + 1] = { kind = kind, label = label, a = a, b = b } end
    function root:CreateTitle(label) Add("title", label) end
    function root:CreateRadio(label, isSelected, select) Add("radio", label, isSelected, select) end
    function root:CreateButton(label, click) Add("button", label, click) end
    function root:CreateCheckbox(label, isChecked, toggle) Add("checkbox", label, isChecked, toggle) end
    function root:CreateDivider() Add("divider") end
    return root
end
local function Pick(label)
    for _, item in ipairs(menu.items) do
        if item.label == label then
            if item.kind == "radio" then item.b() else item.a() end
            return true
        end
    end
end

local shift, cursorX, templated = false, 0, 0
local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function(kind, _, parent, template)
        if template then templated = templated + 1 end
        return New(kind, parent)
    end,
    hooksecurefunc = function() end,
    C_Timer = { After = function() end },
    C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function(id) return id end },
    C_SpellBook = { IsSpellKnown = function() return true end },
    UnitClass = function() return "Class", class end,
    UnitName = function() return "Glyadin" end,
    GetRealmName = function() return "Forever" end,
    LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PRIEST = "Priest", ROGUE = "Rogue", MAGE = "Mage" },
    MenuUtil = { CreateContextMenu = function(owner, generate)
        menu = Root()
        menu.owner = owner
        generate(owner, menu)
    end },
    IsShiftKeyDown = function() return shift end,
    GetCursorPosition = function() return cursorX, 0 end,
}, { __index = _G })
env._G = env

local function Load(path)
    local fn = assert(loadfile(path))
    setfenv(fn, env)
    fn("NaowhForever", ns)
end
Load("Blessings/NaowhForever_Blessings.lua")
Load("Blessings/NaowhForever_BlessingsPage.lua")
local B = ns.Blessings
local studio = assert(cards.bar and cards.bar.studio, "the Blessing Bar card has a preview")

local function Stage()
    local stage = New("Frame")
    stage:SetSize(600, 160)
    return stage
end

-- A warrior's view: the bar as a sample, still editable for its look.
local preview = studio.new(Stage())
studio.paint(preview, "group")
check("the preview is plain frames, no secure template", templated == 0)
check("the aura button shows, Righteous Fury is off by default", preview.aura.shown and not preview.fury.shown)
check("a + slot brings Righteous Fury back", preview.plus.shown and preview.plus.tipBody:find("Righteous Fury"))
check("the note says how to edit", preview.hint.text:find("Shift%-wheel") and preview.hint.text:find("x hides"))
check("the aura's tooltip is the bar's own, then what it does here",
    preview.aura.tipTitle == "Aura" and preview.aura.tipBody:find(B.AURA_TIP, 1, true) == 1)
check("a class's tooltip says what left-click does on the bar",
    preview.cells[1].tipTitle == "Warrior" and preview.cells[1].tipBody:find("the next Warrior who needs it", 1, true))

preview.aura.scripts.OnEnter(preview.aura)
check("hovering the aura shows its x", preview.remove.shown and preview.remove.owner == preview.aura)
preview.aura.scripts.OnLeave(preview.aura)
check("leaving it hides the x", not preview.remove.shown)
preview.aura.scripts.OnEnter(preview.aura)
preview.remove.scripts.OnClick(preview.remove)
check("its x turns the Aura Button setting off", S.Get("blessShowAura") == false)
studio.paint(preview, "group")
check("the aura button is gone", not preview.aura.shown)
check("with both hidden the + offers both", preview.plus.shown and preview.plus.tipBody:find("Choose"))
preview.plus.scripts.OnClick(preview.plus)
check("the + opens a menu of both", menu and menu.owner == preview.plus and #menu.items == 3)
check("picking one brings it back", Pick("Aura Button") and S.Get("blessShowAura") == true)
settings.blessShowFury = true
studio.paint(preview, "group")
check("with nothing hidden there is no + slot", not preview.plus.shown)
settings.blessShowFury = false
studio.paint(preview, "group")
preview.plus.scripts.OnClick(preview.plus)
check("with one hidden the + brings it straight back", S.Get("blessShowFury") == true)
settings.blessShowFury = nil

-- The wheel: size, Shift for spacing, never past the sliders' ends.
studio.paint(preview, "group")
local wheel = preview.cells[2].scripts.OnMouseWheel
wheel(preview.cells[2], 1)
check("wheel up grows the buttons", S.Get("blessBarSize") == 31)
wheel(preview.cells[2], -1)
check("wheel down shrinks them", S.Get("blessBarSize") == 30)
settings.blessBarSize = 70
sets = 0
wheel(preview.cells[2], 1)
check("never past the slider's top, and nothing written", S.Get("blessBarSize") == 70 and sets == 0)
shift = true
wheel(preview.bar, 1)
check("Shift-wheel changes the spacing", S.Get("blessSpacing") == 7 and S.Get("blessBarSize") == 70)
settings.blessSpacing = 0
wheel(preview.bar, -1)
check("spacing stops at the slider's bottom", S.Get("blessSpacing") == 0)
shift = false
settings.blessBarSize, settings.blessSpacing = nil, nil

-- Dragging the gap after the aura sets the Aura / Class Gap.
studio.paint(preview, "group")
local grip = preview.grip
check("the gap after the aura can be dragged", grip.shown and grip.anchor == preview.bar)
check("the grip spans the gap after the + slot and the aura", grip.w == 12 and grip.x == 66)
cursorX = 100
grip.scripts.OnMouseDown(grip, "LeftButton")
check("a drag runs only while dragging", grip.scripts.OnUpdate ~= nil)
cursorX = 110
grip.scripts.OnUpdate(grip)
check("dragging right widens the gap", S.Get("blessGroupSpacing") == 16)
cursorX = 1000
grip.scripts.OnUpdate(grip)
check("the gap stops at the slider's top", S.Get("blessGroupSpacing") == 40)
grip.scripts.OnMouseUp(grip, "LeftButton")
check("letting go stops the drag", grip.scripts.OnUpdate == nil and not grip.dragging)
settings.blessGroupSpacing = nil

-- Hovering and the wheel make no garbage.
studio.paint(preview, "group")
local aura = preview.aura
Measure("hovering the aura", 0.5, function()
    aura.scripts.OnEnter(aura)
    aura.scripts.OnLeave(aura)
end)
Measure("the wheel", 0.5, function()
    wheel(aura, 1)
    wheel(aura, -1)
end)

-- Off: nothing in the preview edits.
settings.blessings = false
studio.paint(preview, "group")
local wheels = true
for _, f in ipairs(preview.wheels) do if f.wheel then wheels = false end end
check("off: the wheel is free for the page", wheels)
check("off: no + and no gap to drag", not preview.plus.shown and not preview.grip.shown)
check("off: the note says why", preview.hint.text:find("Turn on Blessings"))
preview.aura.scripts.OnEnter(preview.aura)
check("off: no x", not preview.remove.shown)
settings.blessings = nil

-- A paladin: the preview shows their plan and edits it through the bar's own menus.
class = "PALADIN"
local mine = studio.new(Stage())
studio.paint(mine, "group")
check("an unplanned class shows the question mark", mine.cells[1].icon.texture == 134400)
local warrior = mine.cells[1]
menu = nil
warrior.scripts.OnClick(warrior, "LeftButton")
check("left-click opens nothing in the preview", menu == nil)
warrior.scripts.OnClick(warrior, "RightButton")
check("right-click opens the class's blessing menu", menu and menu.items[1].label == "Warrior")
local players = false
for _, item in ipairs(menu.items) do if item.label == "Players" then players = true end end
check("without the bar's player list", not players and Pick("Assignments") ~= nil)
warrior.scripts.OnClick(warrior, "RightButton")
check("choosing a blessing writes the plan", Pick("Spell 20217") and B.Store().classes.WARRIOR == "kings")
check("and refreshes the page", refreshed > 0)
studio.paint(mine, "group")
check("the preview shows the new blessing", warrior.icon.texture == 20217)
mine.aura.scripts.OnClick(mine.aura, "LeftButton")
check("clicking the aura opens the aura menu", menu and menu.items[1].label == "Aura")
check("choosing one sets your aura", Pick("Spell 7294") and B.Store().aura == "retribution")
studio.paint(mine, "group")
check("the preview shows your aura", mine.aura.icon.texture == 7294)

print(("test-blessing-preview: %d checks passed"):format(checks))
