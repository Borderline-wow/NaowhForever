-- The search bar's list and matching (real Search.lua over the real settings declarations in
-- Shared/Settings/Settings.lua), and that the old builder scan is gone.
-- Run with Lua 5.1 from the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end

local frames = 0
local ns
ns = { THEME = { bg = {}, panel = {}, line = {}, fg = {}, muted = {}, accent = {}, grey = {} },
    L = function(text) return ns.translations and ns.translations[text] or text end,
    Color = function(_, text) return text or "" end, Shared = {}, UI = {} }
local env = { _G = { NaowhForever = ns }, CreateFrame = function() frames = frames + 1; return {} end }
setmetatable(env, { __index = _G })
local function Load(path)
    local chunk = assert(loadstring(Read(path), path))
    setfenv(chunk, env)
    chunk()
end
Load("Shared/Settings/Settings.lua")
Load("Core/NaowhForever_Search.lua")
local UI, Settings = ns.UI, ns.Shared.Settings

local store = { Get = function() end, Set = function() end, Default = function() end, OnChange = function() end }
local bars = Settings.Page("Meter/Bars", store)
bars:Card({ id = "timer", name = "Swing Timer", help = "A bar for your next swing.", rows = {
    Settings.Group("Look"),
    { key = "size", label = "Bar Size", slider = { 1, 10, 1 }, help = "How tall the bar is." },
    { key = "sound", label = "Timer Sound", toggle = true, help = "Plays a ping on a parry." },
} })
bars:Card({ id = "alert", name = "Parry Alert", help = "Flashes when you parry.", rows = {
    { key = "alertSound", label = "Alert Sound", toggle = true },
    { key = "colour", label = "Alert Colour", colour = true },
} })
Settings.Page("Meter/Other", store):Card({ id = "misc", name = "Odds and Ends", rows = {
    { key = "naowh", label = "Naowh's Tips", toggle = true },
} })

local meter = { name = "Meter" }
local pages = {
    { key = "Settings", name = "Settings", title = "Settings" },
    { key = "Meter/Bars", name = "Bars", module = meter },
    { key = "Meter/Other", name = "Other", module = meter },
}
meter.tabs = { pages[2], pages[3] }
function UI.SearchPages() return pages end

local list = UI.Search.Collect()
Check(frames == 0, "collecting builds no frames")
local function Names(query)
    local out = {}
    for i, t in ipairs(UI.Search.Find(list, query)) do out[i] = t.label or ("[" .. t.trail .. "]") end
    return table.concat(out, "|")
end

-- What each target says about itself.
local first, size
for _, t in ipairs(list) do
    if t.label == "Swing Timer" then first = t end
    if t.label == "Bar Size" then size = t end
end
Check(first.card == "Meter/Bars:timer" and first.page == "Meter/Bars", "a card is a target, with its page")
Check(size.card == "Meter/Bars:timer" and size.tag == "Meter" and size.trail == "Bars / Swing Timer",
    "a setting knows its module, tab and card")
Check(list[1].page == "Settings" and list[1].tag == "Settings" and list[1].trail == "" and not list[1].label,
    "a window page is a target, named by itself")
local trails = table.concat({ list[1].trail, size.trail }, "")
Check(not trails:find(">", 1, true), "no > in a trail")

-- Matching: every typed word starts a word of the target's own.
Check(Names("bar size") == "Bar Size", "every word must match")
Check(Names("BAR SIZE") == "Bar Size", "case does not matter")
Check(Names("siz") == "Bar Size", "a word's start is enough")
Check(Names("ize") == "", "but not its middle")
Check(Names("sound") == "Timer Sound|Alert Sound", "matches come in window order")
Check(Names("ping") == "Timer Sound", "a setting's help counts")
Check(Names("look") == "Bar Size|Timer Sound", "and its group")
Check(Names("parry") == "Timer Sound|Parry Alert|Alert Sound|Alert Colour",
    "a card's name finds the card and the settings in it")
Check(Names("meter") == "[Bars]|[Other]", "a module's name finds its pages")
Check(Names("bars timer") == "", "page and setting words do not mix")
Check(Names("naowh's") == "Naowh's Tips" and Names("naowh") == "Naowh's Tips", "punctuation splits words")
Check(Names("zzz") == "" and Names("   ") == "", "nothing typed or nothing found, no matches")

-- Translated names are found and shown.
do
    ns.translations = { Meter = "Anzeige", Bars = "Balken" }
    local translated = UI.Search.Collect()
    ns.translations = nil
    local hit = UI.Search.Find(translated, "balken")[1]
    Check(hit and hit.tag == "Anzeige" and hit.trail == "Balken", "ns.L names are matched and shown")
end

-- The builder scan, its row tags and the jump's glow are gone for good.
do
    local widgets = Read("Core/NaowhForever_Widgets.lua")
    local window = Read("Core/NaowhForever_Window.lua")
    Check(not widgets:find("searchScan", 1, true) and not widgets:find("_searchL", 1, true), "no scan in the widgets")
    Check(not window:find("noscan", 1, true) and not window:find("Flash", 1, true), "no scan flags or glow in the window")
    Check(window:find("searchBar = UI.AttachSearchBar(window", 1, true), "the window attaches the search bar")
end
print("PASS search bar: " .. cases .. " checks")
