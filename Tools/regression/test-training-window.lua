-- Run with Lua 5.1 from the repository root: the Training Planner's window, built on the
-- Shared kit, opened and drawn against stubs. Every tab and view is drawn and every control
-- in it clicked once, so a missing field or a bad call fails here instead of in game.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

-------------------------------------------------------------------------------
--  Stubs: a frame keeps its scripts, size, text and shown state; Show runs OnShow; every
--  other method does nothing.
-------------------------------------------------------------------------------
local NOTHING = function() end
local Frame
local frames = {}
local METHODS = {
    SetScript = function(f, script, fn) f.scripts[script] = fn end,
    GetScript = function(f, script) return f.scripts[script] end,
    HookScript = function(f, script, fn) f.scripts[script] = fn end,
    GetParent = function(f) return rawget(f, "parent") end,
    SetWidth = function(f, w) f.w = w end,
    SetHeight = function(f, h) f.h = h end,
    SetSize = function(f, w, h) f.w, f.h = w, h end,
    GetWidth = function(f) return rawget(f, "w") or 600 end,
    GetHeight = function(f) return rawget(f, "h") or 24 end,
    SetText = function(f, text) f.text = text end,
    GetText = function(f) return rawget(f, "text") or "" end,
    GetStringWidth = function() return 40 end,
    GetStringHeight = function() return 12 end,
    GetLeft = function() return 100 end,
    GetTop = function() return 900 end,
    GetPoint = function() return "TOPLEFT", nil, "BOTTOMLEFT", 100, 900 end,
    Show = function(f)
        local was = rawget(f, "shown")
        f.shown = true
        if was == false and f.scripts.OnShow then f.scripts.OnShow(f) end
    end,
    Hide = function(f) f.shown = false end,
    SetShown = function(f, shown) f.shown = shown and true or false end,
    IsShown = function(f) return rawget(f, "shown") ~= false end,
    IsVisible = function(f) return rawget(f, "shown") ~= false end,
    IsMouseOver = function() return false end,
    CreateTexture = function(f) return Frame(f) end,
    CreateFontString = function(f) return Frame(f) end,
}
local META = { __index = function(_, key)
    if METHODS[key] then return METHODS[key] end
    if type(key) == "string" and key:find("^%u") then return NOTHING end
end }
function Frame(parent)
    local f = setmetatable({ scripts = {}, parent = parent }, META)
    frames[#frames + 1] = f
    return f
end

local function Click(f, button)
    assert(f.scripts.OnClick, "clickable")(f, button or "LeftButton")
end

local WHITE = { r = 1, g = 1, b = 1 }
local account, printed = {}, {}
local settings = {}
local listeners = {}
local UI = {
    CONTENT_PAD = 10,
    STATUS = { untested = "" },
    Keep = function(parent, key, make)
        local kept = rawget(parent, key)
        if not kept then kept = make(parent); parent[key] = kept end
        return kept
    end,
    RefreshPage = NOTHING,
    CloseOnEscape = NOTHING,
    SlimScroll = function(parent) return Frame(parent) end,
    BuildSliderCore = function(parent)
        local slider = Frame(parent)
        for _, k in ipairs({ "rail", "fill", "thumb", "valueBox", "valueFill" }) do slider[k] = Frame(slider) end
        slider.valueBorder = { _frame = Frame(slider) }
        slider._refreshValue = NOTHING
        return slider
    end,
    ModuleSettings = function(_, defaults)
        local S = {}
        function S.Get(k) if settings[k] == nil then return defaults[k] end return settings[k] end
        function S.Set(k, v)
            settings[k] = v
            for _, fn in ipairs(listeners) do fn(k) end
        end
        function S.OnChange(fn) listeners[#listeners + 1] = fn end
        function S.Toggle(key, text) return { type = "toggle", key = key, text = text } end
        return S
    end,
    Widgets = {
        SectionHeader = function() return nil, 30 end,
        DualRow = function() return nil, 50 end,
        Note = function() return nil, 20 end,
        Button = function() return nil, 30 end,
    },
}
local ns = {
    THEME = setmetatable({}, { __index = function() return WHITE end }),
    UI = UI,
    Color = function(_, text) return tostring(text) end,
    Font = function(parent) return Frame(parent) end,
    Solid = function(parent) return Frame(parent) end,
    Border = function(parent) return { SetColor = NOTHING, _frame = Frame(parent) } end,
    AccentBorder = function(b) return b end,
    Button = function(parent, _, _, _, onClick)
        local b = Frame(parent)
        b.label, b._border, b._rest, b._onClick = Frame(b), { SetColor = NOTHING }, WHITE, onClick
        b.scripts.OnClick = function() if b._onClick then b._onClick() end end
        return b
    end,
    SetButtonText = NOTHING,
    Tooltip = NOTHING,
    Hairline = NOTHING,
    PixelInset = NOTHING,
    NewSearchBox = function(parent, _, onChange)
        local box = Frame(parent)
        box.hint, box.border = Frame(box), { SetColor = NOTHING }
        box.SetText = function(self, text)
            self.text = text
            onChange(text)
        end
        return box
    end,
    UIFontPath = function() return "font" end,
    UIScale = function() return 1 end,
    AccountSettings = function() return account end,
    Print = function(m) printed[#printed + 1] = m end,
    Confirm = function(_, yes) yes() end,
    PromptText = function(_, _, _, accept) accept("Mine") end,
    ShowCopyBox = NOTHING,
    StashOptionsWindow = NOTHING,
    OpenOptionsWindow = NOTHING,
    Apply = NOTHING,
}
local env = setmetatable({
    NaowhForever = ns,
    UIParent = Frame(),
    GameTooltip = Frame(),
    GameTooltip_Hide = NOTHING,
    CreateFrame = function(_, _, parent) return Frame(parent) end,
    CreateColor = function() return { SetRGBA = NOTHING } end,
    hooksecurefunc = NOTHING,
    InCombatLockdown = function() return false end,
    IsMouseButtonDown = function() return false end,
    IsModifiedClick = function() return false end,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    UnitClass = function() return "Mage", "MAGE", 8 end,
    UnitRace = function() return "Human", "Human", 1 end,
    UnitLevel = function() return 20 end,
    UnitName = function() return "Me" end,
    GetRealmName = function() return "Realm" end,
    GetMoney = function() return 12345 end,
    GetClassInfo = function(id) return "Class " .. id, "MAGE" end,
    RAID_CLASS_COLORS = setmetatable({}, { __index = function()
        return { WrapTextInColorCode = function(_, text) return text end }
    end }),
    C_Spell = {
        GetSpellName = function(id) return "Spell " .. id end,
        GetSpellTexture = function() return 1 end,
        GetSpellSubtext = function() return "Rank 1" end,
        GetSpellDescription = function() return "Deals 10 to 12 Fire damage." end,
        RequestLoadSpellData = NOTHING,
        GetSpellLink = function() return "link" end,
    },
    C_SpellBook = { IsSpellKnown = function() return false end },
    C_Item = {},
    C_ClassTalents = { GetActiveConfigID = function() return 1 end, HasUnspentTalentPoints = function() return true end },
    C_Traits = { GetNodeInfo = function() return { activeRank = 0 } end, PurchaseRank = function() return true end,
        CommitConfig = function() return true end },
    C_Timer = { After = function(_, fn) fn() end },
    PixelUtil = { SetPoint = NOTHING, SetSize = NOTHING },
    MenuUtil = { CreateContextMenu = NOTHING },
    LibStub = function()
        local same = function(_, v) return v end
        return { Serialize = function() return "S" end, Deserialize = function(_, v) return true, v end, CompressDeflate = same,
            DecompressDeflate = same, EncodeForPrint = same, DecodeForPrint = same }
    end,
}, { __index = _G })
env._G = env

Load({
    "Shared/Shared.lua", "Shared/Data/Forever.lua", "Shared/Style.lua", "Shared/Items.lua", "Shared/Places.lua",
    "Shared/Parts.lua", "Shared/Window.lua", "Shared/View.lua", "Shared/Kinds.lua",
    "Training/NaowhForever_TrainingData.lua", "Training/NaowhForever_TrainingBuilds.lua",
    "Training/NaowhForever_Training.lua", "Training/NaowhForever_TrainingWindow.lua",
}, env)

-------------------------------------------------------------------------------
--  Opening it, and every part of it
-------------------------------------------------------------------------------
ns.OpenTrainingWindow()
local window
for _, f in ipairs(frames) do
    if rawget(f, "positionKey") == "trainingWindow" then window = f end
end
check("the window is made by the kit", window and window.backdrop and window.switch)
check("it shows", window:IsShown())
check("its subtitle says who you are", window.subtitle:GetText() == "Mage, level 20")
check("the Spells tab shows the next visit and the road", window.hero:IsShown() and window.road:IsShown())
check("and its own controls", window.search:IsShown() and not window.import:IsShown())

ns.OpenTrainingWindow(20)
check("a level opens on Spells with All Levels", window.back:IsShown())
Click(window.back)
window.search:SetText("spell")
settings.showLearned = true
for _, fn in ipairs(listeners) do fn("showLearned") end
settings.windowAlpha = 0.5
for _, fn in ipairs(listeners) do fn("windowAlpha") end
window.search:SetText("")

window.switch.onPick("builds")
check("Builds hides the next visit and the road", not window.hero:IsShown() and not window.road:IsShown())
check("and shows its own controls", window.import:IsShown() and window.new:IsShown() and not window.search:IsShown())
local rows, picked = 0, 0
for _, f in ipairs(frames) do
    if rawget(f, "bar") and rawget(f, "picked") ~= nil and f:IsShown() then
        rows = rows + 1
        if f.picked then picked = picked + 1 end
    end
end
check("the builds are a list down the left, one of them picked", rows > 0 and picked == 1)

-- Every button the Builds tab drew, clicked: the class row, the build cards and theirs.
local function Clickables()
    local list = {}
    for _, f in ipairs(frames) do
        if f.scripts.OnClick and rawget(f, "shown") ~= false and f ~= window then list[#list + 1] = f end
    end
    return list
end
Click(window.new)
check("New Build opens the editor with an empty build", account.trainingBuilds and #account.trainingBuilds[8] == 1)
for _, f in ipairs(Clickables()) do
    if rawget(f, "spell") then Click(f) end
end
check("clicking talents takes points", #account.trainingBuilds[8][1].points > 0)
Click(window.save)
Click(window.import)
for _ = 1, 2 do
    for _, f in ipairs(Clickables()) do Click(f) end
end
check("following a build is kept for the character", account.trainingFollow ~= nil)
window.switch.onPick("spells")
check("back on Spells", window.hero:IsShown())

-- The mini bar, and the settings page with the kit's module card.
settings.enabled = true
settings.miniShown = true
for _, fn in ipairs(listeners) do fn("miniShown") end
local page = Frame()
local y = ns.BuildTrainingSettingsPage(page, 0)
check("the settings page builds", type(y) == "number" and y < 0)
check("with the module card", rawget(page, "trainingCard") ~= nil)

print(("test-training-window: %d checks passed"):format(checks))
