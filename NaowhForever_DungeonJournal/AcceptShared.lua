-- AcceptShared.lua: Accept Shared Dungeon Quests: a dungeon quest a group member shares is accepted as it opens.
local ns = _G.NaowhForever

local J = ns.Journal
local S = J.Settings
local ID = J.C.QUEST.ID

local SKIP_HELD = { ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown }

local acceptFrame, dungeonQuestIDs

local function AddIDs(list)
    if not list then return end
    for _, step in ipairs(list) do
        if type(step) == "table" then
            for _, id in ipairs(step) do dungeonQuestIDs[id] = true end
        else
            dungeonQuestIDs[step] = true
        end
    end
end

local function GatherIDs()
    dungeonQuestIDs = {}
    for _, dungeon in ipairs(J.QuestData) do
        for _, quest in ipairs(dungeon.quests) do
            dungeonQuestIDs[quest[ID]] = true
            AddIDs(quest.alt)
            AddIDs(quest.steps)
            AddIDs(quest.lead)
        end
    end
    for _, list in pairs(J.QuestChains) do AddIDs(list) end
end

local function OnQuestDetail()
    local qol = ns.QoLSettings
    local held = SKIP_HELD[qol.Get("questSkipModifier")]
    if (held and held()) or not UnitIsPlayer("questnpc") or not dungeonQuestIDs[GetQuestID()] then return end
    if qol.Get("enabled") and qol.Get("questAccept") then return end
    if QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
end

local function SyncAccept()
    local on = S.Get("enabled") == true and S.Get("acceptShared") == true
    if not (on or acceptFrame) then return end
    if not acceptFrame then
        GatherIDs()
        acceptFrame = CreateFrame("Frame")
        acceptFrame:SetScript("OnEvent", OnQuestDetail)
    end
    if on then
        acceptFrame:RegisterEvent("QUEST_DETAIL")
    else
        acceptFrame:UnregisterAllEvents()
    end
end

local function OnSettingChanged(key)
    if key == "enabled" or key == "acceptShared" then SyncAccept() end
end

S.OnChange(OnSettingChanged)
hooksecurefunc(ns, "Apply", SyncAccept)
