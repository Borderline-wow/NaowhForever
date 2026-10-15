-- Run with Lua 5.1 from the repository root: the settings fold with a switch on its title (Widgets:SwitchFold):
-- the switch is the title's own, the fold is a FoldHeader that opens when the switch is turned on, a fold with
-- nothing under it has no chevron, and a group title inside a shut fold goes with it.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end

local function New(kind, parent)
    local o = { kind = kind, parent = parent, points = {}, scripts = {}, events = {}, children = {},
        shown = true, w = 0, h = 0 }
    if parent and rawget(parent, "children") then table.insert(parent.children, o) end
    return setmetatable(o, { __index = function(_, k)
        if not k:match("^%u") then return nil end
        return function(self, ...)
            local args = { ... }
            if k == "SetScript" then self.scripts[args[1]] = args[2]
            elseif k == "HookScript" then self.scripts[args[1]] = args[2]
            elseif k == "SetPoint" then self.points[#self.points + 1] = args
            elseif k == "ClearAllPoints" then self.points = {}
            elseif k == "RegisterEvent" then self.events[args[1]] = true
            elseif k == "SetShown" then self.shown = args[1] and true or false
            elseif k == "Show" then self.shown = true
            elseif k == "Hide" then self.shown = false
            elseif k == "IsShown" then return self.shown
            elseif k == "SetSize" then self.w, self.h = args[1], args[2]
            elseif k == "SetHeight" then self.h = args[1]
            elseif k == "SetWidth" then self.w = args[1]
            elseif k == "GetHeight" then return self.h
            elseif k == "GetWidth" then return self.w
            elseif k == "SetRotation" then self.rotation = args[1]
            elseif k == "GetText" then return self.text or ""
            elseif k == "SetText" then self.text = args[1]
            elseif k == "GetFrameLevel" then return 1
            elseif k == "GetStringWidth" then return 20
            elseif k == "GetEffectiveScale" then return 1
            elseif k == "GetObjectType" then return self.kind
            elseif k == "CreateTexture" then return New("Texture", self)
            elseif k == "CreateFontString" then return New("FontString", self)
            end
        end
    end })
end

local env = setmetatable({
    NaowhForeverDB = { account = {}, profiles = {}, charActive = {} },
    CreateFrame = function(kind, _, parent) return New(kind, parent) end,
    CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
    PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end },
    UIParent = New("Frame"),
}, { __index = _G })
env._G = env
local frames = {}
env.CreateFrame = function(kind, _, parent)
    local f = New(kind, parent)
    frames[#frames + 1] = f
    return f
end
for _, path in ipairs({ "Core/Core.lua", "Shared/Shared.lua", "Shared/Style.lua", "Core/Options/Widgets.lua" }) do
    local chunk = assert(loadstring(Read(path), path))
    setfenv(chunk, env)
    chunk("NaowhForever", env.NaowhForever)
end
for _, f in ipairs(frames) do
    if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
end
local ns = env.NaowhForever
local UI, W = ns.UI, ns.UI.Widgets
local refreshes = 0
function UI:RefreshPage() refreshes = refreshes + 1 end

local function Page()
    local parent = New("Frame")
    parent:SetWidth(600)
    UI.BeginReusableRows(parent)
    return parent
end

local on, sets = false, {}
local cfg = { get = function() return on end, set = function(v) sets[#sets + 1] = v end,
    tooltip = "Does a thing.", rows = true }

-- the switch is the title's own, and says what it does
do
    local parent = Page()
    local f, h = W:SwitchFold(parent, "Mouse Thing", 0, cfg)
    check("a header of the usual height", h > 0 and f._label ~= nil and f._label.text == "Mouse Thing")
    check("with a switch of its own", f.switch ~= nil and f.switch.scripts.OnClick ~= nil)
    check("and the tooltip on it", f.switch._tipTitle == "Mouse Thing" and f.switch._tipBody == "Does a thing.")
    f.switch.scripts.OnClick(f.switch)
    check("clicking it sets the opposite of what it reads", #sets == 1 and sets[1] == true)
    on = true
    f.switch._refreshValue()
    f.switch.scripts.OnClick(f.switch)
    check("and back", sets[2] == false)
end

-- it folds what follows like any fold: shut to start, and kept how it was left
do
    local parent = Page()
    local f = W:SwitchFold(parent, "Folding Thing", 0, cfg)
    check("with something to fold: a chevron and a hit", f.arrow.shown == true and f.hit.shown == true)
    check("shut to start", parent._nsuiCollapsed == true)
    local shut, height = W:GroupHeader(parent, "INSIDE", -40)
    check("a title inside it is gone with the rest, and the fold stays shut",
        height == 0 and shut.shown == false and parent._nsuiCollapsed == true)
    local before = refreshes
    f.hit.scripts.OnClick(f.hit)
    check("a click on the title asks for the page again", refreshes == before + 1)
    parent = Page()
    W:SwitchFold(parent, "Folding Thing", 0, cfg)
    check("and it is open now", parent._nsuiCollapsed == nil)
    local _, open = W:GroupHeader(parent, "INSIDE", -40)
    check("so a title inside it is there", open > 0)
    W:SwitchFold(parent, "Another Thing", -80, cfg)
    check("another fold has its own state", parent._nsuiCollapsed == true)
    W:EndFold(parent)
    check("and the end of a fold lets the rows after it show", parent._nsuiCollapsed == nil)
end

-- turning the switch on opens the fold, and a search opens it whatever was left
do
    local parent = Page()
    local f = W:SwitchFold(parent, "Switched Thing", 0, cfg)
    check("shut", parent._nsuiCollapsed == true)
    on = false
    f.switch._refreshValue()
    f.switch.scripts.OnClick(f.switch)
    parent = Page()
    W:SwitchFold(parent, "Switched Thing", 0, cfg)
    check("turned on: open", parent._nsuiCollapsed == nil)
    parent = Page()
    W:SwitchFold(parent, "Searched Thing", 0, { get = cfg.get, set = cfg.set, rows = true, open = true })
    check("held open by a search", parent._nsuiCollapsed == nil)
end

-- with nothing under it there is nothing to fold, whatever was left shut
do
    local parent = Page()
    W:SwitchFold(parent, "Bare Shut Thing", 0, { get = cfg.get, set = cfg.set, rows = false })
    check("with nothing under it, shut or not: nothing is held back", parent._nsuiCollapsed == nil)
end

-- the switch reads again each time the page is drawn
do
    local reads = 0
    local watched = { get = function() reads = reads + 1; return on end, set = cfg.set, rows = true }
    local parent = Page()
    W:SwitchFold(parent, "Read Thing", 0, watched)
    local first = reads
    UI.BeginReusableRows(parent)
    W:SwitchFold(parent, "Read Thing", 0, watched)
    check("the page drawn again: the switch is read again, not left as it was", reads > first)
end

-- with nothing under it there is nothing to fold
do
    local parent = Page()
    local f = W:SwitchFold(parent, "Bare Thing", 0, { get = cfg.get, set = cfg.set, rows = false })
    check("no chevron and no hit", f.arrow.shown == false and f.hit.shown == false)
    check("and nothing shut", parent._nsuiCollapsed == nil)
    check("the switch is still there", f.switch ~= nil and f.switch.shown ~= false)
    local flip = New("Frame")
    flip:SetWidth(600)
    UI.BeginReusableRows(flip)
    local again = W:SwitchFold(flip, "Bare Thing", 0, { get = cfg.get, set = cfg.set, rows = true })
    check("when something follows it again, it folds", again.arrow.shown == true and again.hit.shown == true)
end

-- on the Forever skin a folding header is a card's list bar: the switch at its left, as a card's,
-- its name after the switch, and the bar's sign only when something folds under it
do
    ns.foreverSkin = true
    ns.Shared.Parts = ns.Shared.Parts or {}
    ns.Shared.Parts.ForeverBar = function(bar)
        bar.sign = New("Texture", bar)
        return bar
    end
    ns.Shared.Parts.PaintForeverBar = function(bar, open, openable) bar.open, bar.openable = open, openable end
    ns.Shared.Parts.ForeverCheck = function(t)
        return New("Texture", t), New("Texture", t), { r = 0, g = 0, b = 0 }
    end
    local f = W:SwitchFold(Page(), "Skinned Thing", 0, { get = cfg.get, set = cfg.set })
    local at = f.switch.points[#f.switch.points]
    local name = f.bar and f.bar.name.points[#f.bar.name.points]
    check("the header is a list bar", f.bar ~= nil and not f.arrow.shown)
    check("the switch at the bar's left, its name after it", at and at[1] == "LEFT" and at[2] == f.bar
        and name and name[2] == f.switch and name[3] == "RIGHT")
    check("no rows under it: no sign on the bar", f.bar.openable == false)
    local folds = W:SwitchFold(Page(), "Skinned Folds", 0, cfg)
    check("rows under it: the bar's sign", folds.bar.openable == true)
    ns.foreverSkin = nil
    local plain = W:SwitchFold(Page(), "Plain Thing", 0, cfg)
    local lead = plain.switch.points[#plain.switch.points]
    check("and without the skin it follows the title", plain.bar == nil and lead[2] == plain._label)
end

print("PASS switch fold: " .. checks .. " checks")
