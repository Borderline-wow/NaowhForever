-- The settings search: the row widgets' scan mode (real Widgets.lua), the index and matching
-- (real Search.lua) and the list of pages the scan leaves out (read from Window.lua).
-- Run with Lua 5.1 from the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end

-- Widgets.lua and Search.lua, loaded the way the client does, into one namespace.
local frames = 0
local ns
ns = { THEME = { bg = {}, panel = {}, line = {}, fg = {}, muted = {}, accent = {}, grey = {} },
    L = function(text) return ns.translations and ns.translations[text] or text end,
    Color = function(_, text) return text or "" end }
local env = { _G = { NaowhForever = ns }, LibStub = false,
    CreateFrame = function() frames = frames + 1; return {} end }
setmetatable(env, { __index = _G })
local function Load(path)
    local chunk = assert(loadstring(Read(path), path))
    setfenv(chunk, env)
    chunk()
end
Load("Core/NaowhForever_Widgets.lua")
Load("Core/NaowhForever_Search.lua")
local UI = ns.UI
local W = UI.Widgets

-- Scan mode: rows say what they are called and build nothing.
do
    UI.searchScan = { section = "", items = {} }
    local scan = UI.searchScan
    local row, h = W:SectionHeader({}, "TIMING   |cff9a9ea6UNTESTED|r", -6)
    Check(row == nil and type(h) == "number" and scan.section:find("TIMING", 1, true), "a header sets the section")
    row, h = W:DualRow({}, -46,
        { type = "toggle", text = "Show Timer", tooltip = "Draws the timer." },
        { type = "slider", text = "Timer Size", tooltip = function() return "dynamic" end })
    Check(row == nil and type(h) == "number", "a row returns no frame and a height")
    W:DualRow({}, -96, { type = "dropdown", text = "Font" }, { type = "label", text = "Move in Unlock Mode" })
    W:DualRow({}, -146, { type = "toggle", text = "Alone" })
    W:DualRow({}, -196, { type = "label", text = "" }, { type = "toggle", text = "" })
    W:DualRow({}, -226, { type = "dropdown", text = "Look" }, { type = "palette", text = "", colors = function() error("never runs") end })
    W:Button({}, "Reset Timer", -246, function() error("never runs") end)
    W:ColorPicker({}, "Timer Color", -296, function() end, function() end)
    Check(select(2, W:Note({}, "A long note.", -346)) ~= nil, "a note returns a height and is not recorded")
    local labels = {}
    for i, item in ipairs(scan.items) do labels[i] = item.label end
    Check(table.concat(labels, ",") == "Show Timer,Timer Size,Font,Alone,Look,Reset Timer,Timer Color",
        "labels are recorded in order, without label captions or empty text")
    Check(scan.items[1].tooltip == "Draws the timer." and scan.items[2].tooltip == nil, "string tooltips only")
    Check(scan.items[1].section:find("TIMING", 1, true), "each item knows its section")
    Check(frames == 0, "scan mode builds no frames")
    UI.searchScan = nil
end

-- Plain: what a section header reads as.
Check(UI.Search.Plain("UNLEARNED RECIPES   |cff9a9ea6UNTESTED|r") == "UNLEARNED RECIPES", "status tag stripped")
Check(UI.Search.Plain("BAR|cffff6060 NOT POSSIBLE YET|r") == "BAR", "colour and status stripped")
Check(UI.Search.Plain("  FONT ") == "FONT", "trimmed")

-- The index, over pages that stand in for the real ones.
local scanFlagSeenByBuilder
local function Builder(section, rows)
    return function(parent, y)
        local Widgets = UI.Widgets
        scanFlagSeenByBuilder = UI.searchScan ~= nil
        Widgets:SectionHeader(parent, section, y)
        for _, r in ipairs(rows) do Widgets:DualRow(parent, y, r[1], r[2]) end
        return y
    end
end
ns.BuildTimers = Builder("TIMERS", { { { type = "toggle", text = "Timer Sound", tooltip = "Plays a sound." },
    { type = "slider", text = "Timer Size" } } })
ns.BuildAlerts = Builder("ALERTS", { { { type = "toggle", text = "Alert Sound", tooltip = "Timer alert volume." } } })
ns.BuildBroken = function(parent, y)
    UI.Widgets:DualRow(parent, y, { type = "toggle", text = "Said Before Failing" })
    error("this builder makes its own frames")
end
ns.BuildEditor = Builder("EDITOR", { { { type = "toggle", text = "Editor Setting" } } })
ns.BuildSeen = function() error("must not run") end
local pages = {
    { key = "Settings", name = "Settings", title = "Settings", build = "BuildAlerts" },
    { key = "Meter/Bars", name = "Bars", module = { name = "Meter" }, build = "BuildTimers" },
    { key = "Meter/Odd", name = "Odd", module = { name = "Meter" }, build = "BuildBroken" },
    { key = "Meter/Editor", name = "Editor", module = { name = "Meter" }, build = "BuildEditor", noscan = true },
    { key = "Meter/Soon", name = "Soon", module = { name = "Meter" }, build = "BuildSeen", soon = "later" },
    { key = "Meter/Gone", name = "Gone", module = { name = "Meter" }, build = "BuildMissing" },
}
function UI.SearchPages() return pages end

local index = UI.Search.Build()
Check(scanFlagSeenByBuilder == true, "the builder ran with the scan on")
Check(UI.searchScan == nil, "the scan flag is cleared, failing builders included")
Check(#UI.Search.failed == 1 and UI.Search.failed[1] == "Meter/Odd", "the page whose builder failed is listed")
local function Find(label)
    for _, e in ipairs(index) do if e.label == label then return e end end
end
Check(Find("Timer Size").crumb == "Meter > Bars" and Find("Timer Size").key == "Meter/Bars", "breadcrumb and key")
Check(Find("Alert Sound").crumb == "Settings", "a window page's breadcrumb is its name")
Check(Find("Said Before Failing") ~= nil, "what a page said before it failed is kept")
Check(Find("Editor Setting") == nil, "noscan pages are not scanned")
local pageEntries = 0
for _, e in ipairs(index) do if not e.label then pageEntries = pageEntries + 1 end end
Check(pageEntries == #pages, "every page can be found by name")
Check(frames == 0, "building the index created no frames")

-- Matching.
local function Labels(query, limit)
    local out = {}
    for i, e in ipairs(UI.Search.Match(index, query, limit)) do out[i] = e.label or ("[" .. e.crumb .. "]") end
    return table.concat(out, "|")
end
Check(Labels("timer size") == "Timer Size", "every word must match")
Check(Labels("TIMER SIZE") == "Timer Size", "case does not matter")
Check(Labels("sound") == "Alert Sound|Timer Sound", "results keep page order on a tie")
Check(Labels("volume") == "Alert Sound", "the tooltip is searched")
Check(Labels("timers") == "Timer Sound|Timer Size", "the section name counts")
Check(Labels("zzz") == "", "no match, no results")
Check(Labels("   ") == "", "blanks match nothing")
Check(Labels("meter") == "Timer Sound|Timer Size|Said Before Failing|[Meter > Bars]|[Meter > Odd]|[Meter > Editor]|[Meter > Soon]|[Meter > Gone]",
    "a module name finds its settings first, then its pages")
Check(Labels("editor") == "[Meter > Editor]", "a page that is not scanned is found by name")
Check(Labels("bars timer") == "Timer Sound|Timer Size", "tab and label words combine")

-- A setting outranks a page with the same score, and results are capped.
do
    local ranked = UI.Search.Match(index, "alerts")
    Check(ranked[1].label == "Alert Sound", "the setting in the ALERTS section comes first")
    Check(#UI.Search.Match(index, "e", 3) == 3, "the cap applies")
end

-- Translated names are searchable too.
do
    ns.translations = { Meter = "Anzeige", Bars = "Balken" }
    local translated = UI.Search.Build()
    ns.translations = nil
    local found = UI.Search.Match(translated, "balken")
    Check(#found > 0 and found[1].crumb == "Anzeige > Balken", "ns.L names are matched and shown")
end

-- The pages the scan leaves out are exactly the ones the audit found unsafe.
do
    local expected = { ["Patch Notes"] = true, ["Profiles"] = true, ["QoL/Tools"] = true,
        ["Discovery/Books"] = true, ["Blessings/Bar"] = true, ["Blessings/Assignments"] = true,
        ["BiS List/List"] = true, ["AuraBuffs/Poison & Dispel"] = true, ["Top Bar/Bar"] = true,
        ["Smart Reminders/Setup"] = true, ["Smart Reminders/Cooldown Presets"] = true,
        ["Smart Reminders/Dungeon Bosses"] = true, ["Smart Reminders/Raid Bosses"] = true }
    local module, total, seen = nil, 0, {}
    for line in Read("Core/NaowhForever_Window.lua"):gmatch("[^\n]+") do
        local systemName = line:match('^    { name = "([^"]+)", build = ')
        local moduleName = not systemName and line:match('^    { name = "([^"]+)"')
        local tabName = line:match('^          { name = "([^"]+)"')
        local name
        if systemName then name = systemName
        elseif moduleName then module = moduleName
        elseif tabName then name = module .. "/" .. tabName end
        if name then
            total = total + 1
            local noscan = line:find("noscan = true", 1, true) ~= nil
            seen[name] = noscan
            Check(noscan == (expected[name] == true), name .. ": noscan is " .. tostring(expected[name] == true))
        end
    end
    Check(total == 42, "the window lists 42 pages (" .. total .. "): decide noscan for a new one")
    for name in pairs(expected) do Check(seen[name] ~= nil, "the audited page still exists: " .. name) end
end

-- The rows the search jumps to carry their label.
do
    local widgets = Read("Core/NaowhForever_Widgets.lua")
    Check(widgets:find("row._searchL, row._searchR = leftCfg.text, rightCfg and rightCfg.text", 1, true),
        "DualRow tags its row")
    local window = Read("Core/NaowhForever_Window.lua")
    Check(window:find("row._searchL == label or row._searchR == label", 1, true), "the jump finds the row by label")
    Check(window:find("UI.AttachSearch(top", 1, true), "the window attaches the search box")
end


-- Features (W:Feature): a setting under one carries it, so the jump can open it.
do
    UI.searchScan = { section = "", items = {}, page = "QoL/Loot" }
    local scan = UI.searchScan
    local row, h = W:Feature({}, -6, { type = "toggle", text = "Restock Reminder", tooltip = "Reminds you." })
    Check(row == nil and type(h) == "number", "a feature returns no frame and a height")
    W:DualRow({}, -56, { type = "toggle", text = "Ammo" }, { type = "slider", text = "Ammo to Carry" })
    W:EndFeature({})
    W:DualRow({}, -106, { type = "toggle", text = "Faster Loot" })
    W:Feature({}, -156, { type = "label", text = "Appearance" }, "appearance")
    W:DualRow({}, -206, { type = "slider", text = "Font Size" })
    W:SectionHeader({}, "OTHER", -256)
    W:DualRow({}, -296, { type = "toggle", text = "After Header" })
    local by = {}
    for _, item in ipairs(scan.items) do by[item.label] = item end
    Check(by["Restock Reminder"] and by["Restock Reminder"].feature == nil, "a feature's own row is not under itself")
    Check(by["Ammo"].feature == "QoL/Loot:Restock Reminder" and by["Ammo to Carry"].featureName == "Restock Reminder",
        "rows after a feature carry it")
    Check(by["Faster Loot"].feature == nil, "EndFeature ends it")
    Check(by["Appearance"] ~= nil and by["Font Size"].feature == "QoL/Loot:appearance", "a label feature, by its key")
    Check(by["After Header"].feature == nil, "a section header ends it")
    Check(frames == 0, "scanning features builds no frames")
    UI.searchScan = nil
end

do
    ns.BuildFeatured = function(parent, y)
        UI.Widgets:Feature(parent, y, { type = "toggle", text = "Pet Tracker" })
        UI.Widgets:DualRow(parent, y, { type = "toggle", text = "Warn While Passive" })
        return y
    end
    local saved = pages
    pages = { { key = "QoL/Alerts", name = "Alerts", module = { name = "QoL" }, build = "BuildFeatured" } }
    local hit = UI.Search.Match(UI.Search.Build(), "passive")[1]
    pages = saved
    Check(hit.feature == "QoL/Alerts:Pet Tracker" and hit.crumb == "QoL > Alerts > Pet Tracker",
        "an entry knows its feature, and the breadcrumb names it")
    local window = Read("Core/NaowhForever_Window.lua")
    Check(window:find("UI.OpenFeature(feature)", 1, true), "the jump opens the feature first")
    local widgets = Read("Core/NaowhForever_Widgets.lua")
    Check(widgets:find("UI.searchOpen and UI.searchOpen[id]", 1, true), "a feature holding a match opens while typing")
end
print("PASS settings search: " .. cases .. " checks")
