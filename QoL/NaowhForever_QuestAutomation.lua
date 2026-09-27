-------------------------------------------------------------------------------
--  NaowhForever_QuestAutomation.lua -- the QoL quest automation: accepts quests, turns
--  them in, and picks quests out of an NPC's greeting or gossip. Hold Alt to skip it.
--  Also the saved reward picks: Alt-click a choice reward to keep it for that quest in the
--  profile, and it is selected (or taken by Auto Turn In) when the quest is handed in.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local function On(key)
    return S.Get("enabled") and S.Get(key)
end

-- Quest ID -> item ID, in the profile, so a shared profile carries its picks.
local function Picks()
    local db = S.DB()
    db.questRewards = db.questRewards or {}
    return db.questRewards
end

local function ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- The choice at the hand-in window that gives the saved item for this quest.
local function PickedChoice()
    local picked = On("questRewardPicks") and Picks()[GetQuestID()]
    if not picked then return end
    for i = 1, GetNumQuestChoices() do
        if ItemID(GetQuestItemLink("choice", i)) == picked then return i end
    end
end

local function SaveClick(self)
    if not (On("questRewardPicks") and IsAltKeyDown()) or IsShiftKeyDown() or IsControlKeyDown() then return end
    if self.type ~= "choice" or self.objectType ~= "item" then return end
    local link = QuestInfoFrame.questLog and GetQuestLogItemLink(self.type, self:GetID())
        or GetQuestItemLink(self.type, self:GetID())
    local itemID, questID = ItemID(link), self.questID
    if not (itemID and questID) then return end
    local picks = Picks()
    local title = C_QuestLog.GetTitleForQuestID(questID) or GetTitleText() or ""
    if picks[questID] == itemID then
        picks[questID] = nil
        ns.Print(("Cleared the saved reward for %s."):format(title))
        return
    end
    picks[questID] = itemID
    ns.Print(("%s is your reward for %s in this profile."):format(link, title))
    if not QuestInfoFrame.questLog and QuestInfoFrame.chooseItems then QuestInfoItem_OnClick(self) end
end

-- Every reward button, the log's and the hand-in window's, is handed out through here.
local hooked = {}
hooksecurefunc("QuestInfo_GetRewardButton", function(rewardsFrame, index)
    local button = rewardsFrame.RewardButtons[index]
    if button and not hooked[button] then
        hooked[button] = true
        button:HookScript("OnClick", SaveClick)
    end
end)

-- The reward panel lays out its buttons and clears the choice in its own OnShow, so the
-- saved pick is selected after it.
QuestFrameRewardPanel:HookScript("OnShow", function()
    local pick = PickedChoice()
    if not pick then return end
    for _, button in ipairs(QuestInfoRewardsFrame.RewardButtons) do
        if button:IsShown() and button.type == "choice" and button:GetID() == pick then
            QuestInfoItem_OnClick(button)
            return
        end
    end
end)

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
        -- A choice of rewards is left to the player unless the profile has a pick for it.
        if not On("questTurnIn") then return end
        local choices = GetNumQuestChoices()
        local pick = choices > 1 and PickedChoice()
        if choices <= 1 or pick then GetQuestReward(pick or choices) end
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
