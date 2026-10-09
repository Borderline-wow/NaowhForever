-- TrackerAuto.lua: Open Tracker in Dungeons and Show Outside Dungeons: the quest tracker opened on a loading screen.
local ns = _G.NaowhForever

local J = ns.Journal
local S = J.Settings
local Tracker = J.QuestTracker

local autoFrame

local function QuestsFor()
    local level = UnitLevel("player")
    local forLevel
    for _, dungeon in ipairs(J.Dungeons()) do
        local data = dungeon.quests
        if data then
            local toPickUp, inLog = J.Quests.Count(data)
            if inLog > 0 then return dungeon end
            local levels = not forLevel and toPickUp > 0 and J.Levels(dungeon)
            if levels and level >= levels[1] and level <= levels[2] then forLevel = dungeon end
        end
    end
    return forLevel
end

local function OpenOutside()
    if not S.Get("trackerOutside") or Tracker.closedOutside then return end
    local pick = QuestsFor()
    if pick then Tracker.Show(pick) end
end

local function OpenInside(dungeon)
    if not S.Get("trackerAuto") or dungeon == Tracker.closedIn then return end
    local data = dungeon.quests
    if not data then return end
    local toPickUp, inLog = J.Quests.Count(data)
    if toPickUp + inLog > 0 then Tracker.Show(dungeon) end
end

local function OnEnterWorld()
    local here = J.Current()
    local dungeon = here and here[1]
    if dungeon ~= Tracker.closedIn then Tracker.closedIn = nil end
    if dungeon then Tracker.closedOutside = nil end
    if Tracker.IsShown() and (not dungeon or Tracker.Showing() == dungeon) then return end
    if dungeon then OpenInside(dungeon) else OpenOutside() end
end

local function SyncAuto()
    local on = S.Get("enabled") and (S.Get("trackerAuto") or S.Get("trackerOutside"))
    if not (on or autoFrame) then return end
    if not autoFrame then
        autoFrame = CreateFrame("Frame")
        autoFrame:SetScript("OnEvent", OnEnterWorld)
    end
    if not on then
        autoFrame:UnregisterAllEvents()
        return
    end
    autoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    OnEnterWorld()
end

local function OnSettingChanged(key)
    if key == "enabled" or key == "trackerAuto" or key == "trackerOutside" then SyncAuto() end
end

hooksecurefunc(ns, "Apply", SyncAuto)
S.OnChange(OnSettingChanged)
