-------------------------------------------------------------------------------
--  NaowhForever_QuestAutomation.lua -- the QoL quest automation: accepts, turns in and shares
--  quests, and selects reward picks saved by Alt-clicking a reward.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local function On(key)
    return S.Get("enabled") and S.Get(key)
end

local SKIP_HELD = { ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown }

-- Quest ID -> item ID, in the profile, so a shared profile carries its picks.
local function Picks()
    local db = S.DB()
    db.questRewards = db.questRewards or {}
    return db.questRewards
end

-- The item ID comes with the reward before the item is cached; its link may not.
local function ChoiceItemID(index)
    local _, _, _, _, _, itemID = GetQuestItemInfo("choice", index)
    return itemID
end

-- The choice at the hand-in window that gives the saved item for this quest.
local function PickedChoice()
    local picked = On("questRewardPicks") and Picks()[GetQuestID()]
    if not picked then return end
    for i = 1, GetNumQuestChoices() do
        if ChoiceItemID(i) == picked then return i end
    end
end

local function SaveClick(self)
    if not (On("questRewardPicks") and IsAltKeyDown()) or IsShiftKeyDown() or IsControlKeyDown() then return end
    if self.type ~= "choice" or self.objectType ~= "item" then return end
    local itemID, link
    if QuestInfoFrame.questLog then
        itemID = select(6, GetQuestLogChoiceInfo(self:GetID()))
        link = GetQuestLogItemLink(self.type, self:GetID())
    else
        itemID = ChoiceItemID(self:GetID())
        link = GetQuestItemLink(self.type, self:GetID())
    end
    local questID = self.questID
    if not (itemID and questID) then return end
    local picks = Picks()
    local title = C_QuestLog.GetTitleForQuestID(questID) or GetTitleText() or ""
    if picks[questID] == itemID then
        picks[questID] = nil
        ns.Print(("Cleared the saved reward for %s."):format(title))
        return
    end
    picks[questID] = itemID
    ns.Print(("%s is your reward for %s in this profile."):format(link or ("item " .. itemID), title))
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

-- Every layout of the rewards ends by clearing the choice: the reward panel's own OnShow,
-- and again on QUEST_ITEM_UPDATE as uncached items arrive. The saved pick is selected after.
hooksecurefunc("QuestInfo_ShowRewards", function()
    if QuestInfoFrame.questLog or not QuestFrameRewardPanel:IsShown() then return end
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

-- The quest in the last quest window, when a player offered it (shared it with you) rather
-- than an NPC: the group already has it, so accepting it does not share it again.
local sharedWithMe

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, questID)
    if event == "QUEST_DETAIL" then sharedWithMe = UnitIsPlayer("questnpc") and GetQuestID() or nil end
    if SKIP_HELD[S.Get("questSkipModifier")]() then return end
    if event == "QUEST_ACCEPTED" then
        local shared = questID == sharedWithMe
        -- The same call Blizzard's own Share button makes. It is blocked in combat, so a
        -- quest accepted mid-fight is not shared.
        if not shared and On("questShare") and IsInGroup() and not InCombatLockdown()
            and C_QuestLog.IsPushableQuest(questID) then
            QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
        end
    elseif event == "QUEST_DETAIL" then
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
    if On("questShare") then
        events:RegisterEvent("QUEST_ACCEPTED")
        events:RegisterEvent("QUEST_DETAIL")
    end
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
