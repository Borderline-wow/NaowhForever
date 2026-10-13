-- Run with Lua 5.1 from the repository root: the profession window's docked Blizzard parts stay readable:
-- the Unlearn button shows a red cross even where its atlas is missing, and every tab gets one outline.
local f = assert(io.open(arg[1] or "NaowhForever_Professions/UI/Takeover.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

local ATLAS, FALLBACK = "Profession-button-red-crossmark", "Interface/RAIDFRAME/ReadyCheck-NotReady"
local function Env(atlasKnown)
    local made = 0
    local env = {
        UNLEARN_ATLAS = ATLAS, UNLEARN_FALLBACK = FALLBACK, UNLEARN_SIZE = 20, outlines = {},
        C_Texture = { GetAtlasInfo = function(name) return atlasKnown and name == ATLAS and {} or nil end },
        ns = { THEME = { accent = { r = 0, g = 0.57, b = 0.93 } },
            Border = function()
                made = made + 1
                local frame = { shown = true }
                frame.SetShown = function(self, on) self.shown = on end
                return { _frame = frame }
            end },
    }
    setmetatable(env, { __index = _G })
    local code = Slice("local function OutlineTab(", "\nlocal function DockTabs(") .. "\nreturn OutlineTab, ShowUnlearn"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    local Outline, Show = chunk()
    return env, Outline, Show, function() return made end
end
local function Icon()
    return { SetTexture = function(self, t) self.texture = t end,
        SetSize = function(self, w, h) self.w, self.h = w, h end,
        SetAlpha = function(self, a) self.alpha = a end }
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("an Unlearn button without its atlas gets the red cross texture", function()
    local _, _, Show = Env(false)
    local button = { Icon = Icon() }
    Show(button)
    assert(button.Icon.texture == FALLBACK and button.Icon.w == 20 and button.Icon.h == 20 and button.Icon.alpha == 1)
end)
Case("with its atlas it keeps it, at a size and strength that can be seen", function()
    local _, _, Show = Env(true)
    local button = { Icon = Icon() }
    Show(button)
    assert(button.Icon.texture == nil and button.Icon.w == 20 and button.Icon.alpha == 1)
end)
Case("a button with no icon is left alone", function()
    local _, _, Show = Env(true)
    Show({})
end)
Case("a tab is outlined once, hidden when undocked and shown again when docked", function()
    local env, Outline, _, made = Env(true)
    local tab = {}
    Outline(tab, true)
    Outline(tab, true)
    assert(made() == 1 and env.outlines[tab]._frame.shown == true, "one outline, shown")
    Outline(tab, false)
    assert(env.outlines[tab]._frame.shown == false, "hidden when undocked")
    Outline(tab, true)
    assert(made() == 1 and env.outlines[tab]._frame.shown == true, "shown again, not made twice")
    local never = {}
    Outline(never, false)
    assert(made() == 1 and env.outlines[never] == nil, "an undocked tab never gets one")
end)
Case("docking applies both: the tabs are outlined and the Unlearn button is restyled", function()
    local tabs = Slice("local function DockTabs(", "\nlocal function Place(")
    assert(tabs:find("OutlineTab(head, on)", 1, true) and tabs:find("OutlineTab(tab, on)", 1, true))
    assert(Slice("local function DockCards(", "\nlocal function DockBook(")
        :find("ShowUnlearn(blizz.UnlearnButton)", 1, true))
end)
print(count .. " profession tab icon regressions passed")
