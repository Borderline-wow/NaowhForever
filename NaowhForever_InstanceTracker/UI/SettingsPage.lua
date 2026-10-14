-- SettingsPage.lua: the Instance Tracker's settings page, declared as cards.
local ns = _G.NaowhForever
local S = ns.InstanceTrackerSettings

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local OFF = ns.L("Turn on Instance Tracker")
local WHERE = { { self = "Your Chat", group = "Group" }, { "self", "group" } }
local RAID_WHY = ns.L("Choose Group above")

local function Enabled()
    return S.Get("enabled") == true
end

local function Row(key, label, help)
    return { key = key, label = label, toggle = true, needs = Enabled, why = OFF, help = help }
end

local raid = Row("leavePrintRaid", "Send to Raid Chat", "Sends the summary to raid chat.")
raid.needs = function()
    if not Enabled() then
        raid.why = OFF
        return false
    end
    raid.why = RAID_WHY
    return S.Get("leaveWhere") == "group"
end

local function Headline()
    local IT = ns.InstanceTracker
    if not IT.Enabled() then return ns.L("Instance Tracker is off") end
    local open = IT.Open()
    if open and open.instance then return "In " .. IT.PlaceName(open.instance, open.difficulty) end
    local count, cap = IT.Hour()
    return string.format(ns.L("%d of %d instances on this account"), count, cap)
end

local function Detail()
    local IT = ns.InstanceTracker
    if not IT.Enabled() then return ns.L("Turn it on to record visits.") end
    local open = IT.Open()
    if open and open.instance then return IT.Duration(IT.Elapsed(open)) .. ns.L(" in this visit.") end
    local count, _, frees = IT.Hour()
    if count > 0 then return ns.L("The next one frees in ") .. IT.Duration(frees) .. "." end
    return ns.L("No new instances this hour.")
end

local function LeaveSummary(store)
    return store.Get("leaveWhere") == "group" and ns.L("Sent to the group") or ns.L("Your chat only")
end

local page = Settings.Page("Instance Tracker/Settings", S)

page:Window({
    text = "Open Instance Tracker",
    open = function() ns.OpenInstanceTrackerWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "hour", name = "This Hour", order = 10,
    help = "Warns in chat as you near the hourly instance cap.",
    rows = {
        { key = "hourlyWarn", label = "Warn when this many are left", slider = { 1, 5, 1 },
          needs = Enabled, why = OFF, help = "Sets how close to the cap the warning starts." },
    },
})

page:Card({
    id = "timer", name = "Run Timer", order = 20, switch = "showFrame",
    help = "Shows this visit's time, coins, and experience.",
    summary = function() return ns.L("Inside a dungeon or raid") end,
})

page:Card({
    id = "enter", name = "Chat on Enter", order = 30, switch = "enterChat",
    help = "Prints in your chat when you enter an instance.",
    summary = function() return ns.L("Your chat only") end,
})

page:Card({
    id = "alts", name = "Track Alts", order = 40, switch = "trackAlts",
    help = "Shows your other characters' visits.",
    summary = function() return ns.L("Other characters stay listed") end,
})

page:Card({
    id = "leave", name = "When You Leave", order = 50, switch = "leaveChat",
    help = "Prints a summary when you leave a dungeon.",
    summary = LeaveSummary,
    rows = {
        Settings.Group("Where"),
        { key = "leaveWhere", label = "Send It To", choice = WHERE, needs = Enabled, why = OFF,
          help = "Prints the summary in your chat or in the group." },
        raid,
        Settings.Group("Included"),
        Row("leaveTime", "Show Time", "Adds how long the visit lasted."),
        Row("leaveXP", "Show Experience", "Adds the experience gained."),
        Row("leaveGold", "Show Coins Looted", "Adds the coins looted."),
        Row("leaveDeaths", "Show Deaths", "Adds the deaths."),
        Row("leaveRep", "Show Reputation", "Adds the reputation gained."),
        Row("leaveAverage", "Show Average Experience", "Adds the average experience here."),
        Row("leaveRunsLevel", "Show Runs This Level", "Adds the visits at this level."),
        Row("leaveRunsToLevel", "Show Runs to Next Level", "Adds the visits until you level."),
        Row("leaveActivity", "Skip If Nothing Happened", "Skips the summary when the visit gained nothing."),
        Row("leaveRaids", "Include Raids", "Also prints the summary when you leave a raid."),
    },
})

page:Card({
    id = "reset", name = "When You Reset", order = 60, switch = "resetChat",
    help = "Posts the reset in group chat when you are leading.",
    summary = function() return ns.L("Posted in group chat") end,
})
