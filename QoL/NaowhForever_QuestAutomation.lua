-------------------------------------------------------------------------------
--  NaowhForever_QuestAutomation.lua -- the QoL quest automation: accepts quests, turns
--  them in, and picks quests out of an NPC's greeting or gossip. Hold Alt to skip it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local function On(key)
    return S.Get("enabled") and S.Get(key)
end

-- An NPC with several quests lists them first; the first finished one is turned in, else
-- the first on offer is opened.
local function PickFromGreeting()
    if On("questTurnIn") then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then return SelectActiveQuest(i) end
        end
    end
    if On("questAccept") and GetNumAvailableQuests() > 0 then
        SelectAvailableQuest(1)
    end
end

local function PickFromGossip()
    if On("questTurnIn") then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
            if quest.isComplete and quest.questID then
                return C_GossipInfo.SelectActiveQuest(quest.questID)
            end
        end
    end
    if On("questAccept") then
        local quest = C_GossipInfo.GetAvailableQuests()[1]
        if quest and quest.questID then C_GossipInfo.SelectAvailableQuest(quest.questID) end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if IsAltKeyDown() then return end
    if event == "QUEST_DETAIL" then
        if not On("questAccept") then return end
        if QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if not On("questAccept") then return end
        ConfirmAcceptQuest()
        StaticPopup_Hide("QUEST_ACCEPT")
    elseif event == "QUEST_PROGRESS" then
        if On("questTurnIn") and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        -- A choice of rewards is left to the player.
        if On("questTurnIn") and GetNumQuestChoices() <= 1 then
            GetQuestReward(GetNumQuestChoices())
        end
    elseif event == "QUEST_GREETING" then
        if On("questGossip") then PickFromGreeting() end
    elseif event == "GOSSIP_SHOW" then
        if On("questGossip") then PickFromGossip() end
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (On("questAccept") or On("questTurnIn")) then return end
    for _, event in ipairs({ "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS",
        "QUEST_COMPLETE", "QUEST_GREETING", "GOSSIP_SHOW" }) do
        events:RegisterEvent(event)
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^quest") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
