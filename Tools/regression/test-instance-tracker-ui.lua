-- The run timer, the settings and the lists sit on the shared surfaces.
-- From the repo root:
--   lua5.1 Tools/regression/test-instance-tracker-ui.lua
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return source
end

local cases = 0
local function Check(ok, why)
    assert(ok, why)
    cases = cases + 1
end

local toc = Read("NaowhForever.toc")
local moduleToc = Read("NaowhForever_Utilities/NaowhForever_Utilities.toc")
local hostXml = Read("NaowhForever_Utilities/Utilities.xml")
local window = Read("Core/Options/Modules.lua")
local moduleXml = Read("NaowhForever_Utilities/InstanceTracker/InstanceTracker.xml")
local tracker = Read("NaowhForever_Utilities/InstanceTracker/InstanceTracker.lua")
local page = Read("NaowhForever_Utilities/InstanceTracker/UI/Pages.lua")
    .. Read("NaowhForever_Utilities/InstanceTracker/UI/SettingsPage.lua")
local lists = Read("NaowhForever_Utilities/InstanceTracker/UI/Window.lua")

Check(toc:find("InstanceTracker", 1, true) == nil,
    "the core toc does not load the tracker")
Check(moduleToc:match("## Interface:[^%c]*") == toc:match("## Interface:[^%c]*")
    and moduleToc:match("## Version:[^%c]*") == toc:match("## Version:[^%c]*"),
    "its TOC matches the core Interface and Version")
Check(moduleToc:find("## Dependencies: NaowhForever", 1, true) ~= nil
    and moduleToc:find("## Group: NaowhForever", 1, true) ~= nil,
    "Utilities depends on NaowhForever and is grouped with it")
Check(moduleToc:find("\nUtilities.xml", 1, true) ~= nil
    and hostXml:find('<Include file="InstanceTracker\\InstanceTracker.xml"/>', 1, true) ~= nil,
    "Utilities' TOC loads its XML, which loads the tracker's")
local trackerAt = moduleXml:find('file="InstanceTracker.lua"', 1, true)
local pagesAt = moduleXml:find('file="UI\\Pages.lua"', 1, true)
local windowAt = moduleXml:find('file="UI\\Window.lua"', 1, true)
local settingsAt = moduleXml:find('file="UI\\SettingsPage.lua"', 1, true)
Check(trackerAt and pagesAt and windowAt and settingsAt and trackerAt < pagesAt and pagesAt < windowAt
    and windowAt < settingsAt, "the tracker, then its pages, its window and its settings page")

Check(tracker:find("Parts.TrackerPanel(", 1, true) ~= nil, "the timer is a tracker panel")
Check(tracker:find('page = SETTINGS_PAGE, card = TIMER_CARD', 1, true) ~= nil,
    "the cog opens the Run Timer card")
Check(tracker:find('SETTINGS_PAGE = "Instance Tracker/Settings"', 1, true) ~= nil,
    "the mover opens the settings page")
Check(tracker:find("CreateFrame(\"Frame\", \"NaowhForeverInstanceTracker\"", 1, true) == nil,
    "the hand-built timer frame is gone")

Check(page:find('Settings.Page("Instance Tracker/Settings"', 1, true) ~= nil,
    "settings are a shared settings page")
Check(page:find('id = "timer"', 1, true) and page:find('switch = "showFrame"', 1, true),
    "Run Timer is the showFrame card")
Check(page:find("function ns.BuildInstanceTrackerPage", 1, true) == nil,
    "the hand-built Display page is gone")
Check(page:find("function ns.BuildInstanceHourPage", 1, true) ~= nil
    and page:find("function ns.BuildInstanceHistoryPage", 1, true) ~= nil,
    "the list builders stay for the module window")

local helps = 0
local function Help(help)
    helps = helps + 1
    Check(#help < 100, "help under 100 characters: " .. help)
    Check(help:find("%.%s") == nil, "help is one sentence: " .. help)
end
for help in page:gmatch('help = "([^"]*)"') do Help(help) end
for help in page:gmatch('Row%b()') do
    local text = help:match(', "([^"]+)"%s*%)$')
    if text then Help(text) end
end
Check(helps >= 18, "the settings cards carry help")
Check(page:find("windowAlpha", 1, true) == nil and lists:find("windowAlpha", 1, true) == nil
    and lists:find("Parts.Opacity", 1, true) == nil, "no window opacity: the window is always solid")

Check(lists:find("Parts.Window(", 1, true) ~= nil, "the lists sit in a module window")
Check(lists:find("BuildInstanceHourPage", 1, true) ~= nil
    and lists:find("BuildInstanceHistoryPage", 1, true) ~= nil,
    "This Hour and History are the window's tabs")
Check(lists:find("function ns.ToggleInstanceTrackerWindow", 1, true) ~= nil,
    "the slash command can open the window")

Check(window:find('addon = "NaowhForever_InstanceTracker", host = "NaowhForever_Utilities"', 1, true) ~= nil,
    "the module ships inside the Utilities addon")
Check(Read(".pkgmeta"):find("NaowhForever/NaowhForever_Utilities: NaowhForever_Utilities", 1, true) ~= nil,
    "packaged beside the core")
Check(window:find('name = "Instance Tracker"[^}]-open = "ToggleInstanceTrackerWindow"', 1) ~= nil,
    "the module opens its own window")
Check(window:find('open = "ToggleInstanceTrackerWindow"[^}]-name = "Settings"', 1) ~= nil,
    "options keeps a settings tab")
Check(window:find("BuildInstanceHourPage", 1, true) == nil
    and window:find("BuildInstanceHistoryPage", 1, true) == nil
    and window:find("BuildInstanceTrackerPage", 1, true) == nil,
    "the lists are not options tabs")

Check(tracker:find("C_Timer.NewTicker(1, Tick)", 1, true) ~= nil
    and tracker:find("C_Timer.NewTicker(1, UpdateFrame)", 1, true) == nil,
    "the one-second ticker is the light tick")
local tickAt = tracker:find("local function Tick()", 1, true)
local tick = tickAt and tracker:sub(tickAt, tracker:find("\nlocal function Build()", tickAt, true) - 1)
Check(tick ~= nil and tick:find("body.time:SetText", 1, true) ~= nil
    and tick:find("body.hour:SetText", 1, true) ~= nil,
    "the tick sets the clock and the hour line")
Check(tick ~= nil and tick:find(":Fit(", 1, true) == nil and tick:find(":Paint(", 1, true) == nil
    and tick:find("SetScale", 1, true) == nil and tick:find("Coins(", 1, true) == nil,
    "the tick does not fit, paint, scale, or rebuild the coin string")

print("OK " .. cases .. " instance tracker UI checks")
