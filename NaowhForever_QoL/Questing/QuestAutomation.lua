-- QuestAutomation.lua: the QoL quest automation: accept, turn in and share quests, and saved reward picks.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local CHOICE_ITEM_ID = 6
local SKIP_HELD = { ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown }
local AUTO_EVENTS = { "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_GREETING", "GOSSIP_SHOW" }
local SKIP = { { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" }, { "ALT", "CTRL", "SHIFT" } }
local DOING = { { "questAccept", "accepts" }, { "questTurnIn", "turns in" }, { "questGossip", "picks from NPCs" },
    { "questShare", "shares" } }

local TEXT_CLEARED = "Cleared the saved reward for %s."
local TEXT_SAVED = "%s is your reward for %s in this profile."
local TEXT_ITEM = "item "
local TEXT_BY_HAND = "All by hand"

local hooked = {}
local sharedWithMe
local events = CreateFrame("Frame")

local function On(key)
    return S.Get("enabled") and S.Get(key)
end

local function Picks()
    local db = S.DB()
    db.questRewards = db.questRewards or {}
    return db.questRewards
end

local function ChoiceItemID(index)
    local _, _, _, _, _, itemID = GetQuestItemInfo("choice", index)
    return itemID
end

local function PickedChoice()
    local picked = On("questRewardPicks") and Picks()[GetQuestID()]
    if not picked then return end
    for i = 1, GetNumQuestChoices() do
        if ChoiceItemID(i) == picked then return i end
    end
end

local function ClickedReward(button)
    if QuestInfoFrame.questLog then
        return select(CHOICE_ITEM_ID, GetQuestLogChoiceInfo(button:GetID())),
            GetQuestLogItemLink(button.type, button:GetID())
    end
    return ChoiceItemID(button:GetID()), GetQuestItemLink(button.type, button:GetID())
end

local function SaveClick(self)
    if not (On("questRewardPicks") and IsAltKeyDown()) or IsShiftKeyDown() or IsControlKeyDown() then return end
    if self.type ~= "choice" or self.objectType ~= "item" then return end
    local itemID, link = ClickedReward(self)
    local questID = self.questID
    if not (itemID and questID) then return end
    local picks = Picks()
    local title = C_QuestLog.GetTitleForQuestID(questID) or GetTitleText() or ""
    if picks[questID] == itemID then
        picks[questID] = nil
        ns.Print(TEXT_CLEARED:format(title))
        return
    end
    picks[questID] = itemID
    ns.Print(TEXT_SAVED:format(link or (TEXT_ITEM .. itemID), title))
    if not QuestInfoFrame.questLog and QuestInfoFrame.chooseItems then QuestInfoItem_OnClick(self) end
end

local function OnRewardButton(rewardsFrame, index)
    local button = rewardsFrame.RewardButtons[index]
    if button and not hooked[button] then
        hooked[button] = true
        button:HookScript("OnClick", SaveClick)
    end
end

local function OnShowRewards()
    if QuestInfoFrame.questLog or not QuestFrameRewardPanel:IsShown() then return end
    local pick = PickedChoice()
    if not pick then return end
    for _, button in ipairs(QuestInfoRewardsFrame.RewardButtons) do
        if button:IsShown() and button.type == "choice" and button:GetID() == pick then
            QuestInfoItem_OnClick(button)
            return
        end
    end
end

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

local HANDLERS = {}

function HANDLERS.QUEST_ACCEPTED(questID)
    local shared = questID == sharedWithMe
    if not shared and On("questShare") and IsInGroup() and not InCombatLockdown()
        and C_QuestLog.IsPushableQuest(questID) then
        QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
    end
end

function HANDLERS.QUEST_DETAIL()
    if not On("questAccept") then return end
    if QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
end

function HANDLERS.QUEST_ACCEPT_CONFIRM()
    if not On("questAccept") then return end
    ConfirmAcceptQuest()
    StaticPopup_Hide("QUEST_ACCEPT")
end

function HANDLERS.QUEST_PROGRESS()
    if On("questTurnIn") and IsQuestCompletable() then CompleteQuest() end
end

function HANDLERS.QUEST_COMPLETE()
    if not On("questTurnIn") then return end
    local choices = GetNumQuestChoices()
    local pick = choices > 1 and PickedChoice()
    if choices <= 1 or pick then GetQuestReward(pick or choices) end
end

function HANDLERS.QUEST_GREETING()
    if On("questGossip") then PickFromGreeting() end
end

function HANDLERS.GOSSIP_SHOW()
    if On("questGossip") then PickFromGossip() end
end

local function OnEvent(_, event, questID)
    if event == "QUEST_DETAIL" then sharedWithMe = UnitIsPlayer("questnpc") and GetQuestID() or nil end
    if SKIP_HELD[S.Get("questSkipModifier")]() then return end
    HANDLERS[event](questID)
end

local function Apply()
    events:UnregisterAllEvents()
    if On("questShare") then
        events:RegisterEvent("QUEST_ACCEPTED")
        events:RegisterEvent("QUEST_DETAIL")
    end
    if not (On("questAccept") or On("questTurnIn")) then return end
    for _, event in ipairs(AUTO_EVENTS) do events:RegisterEvent(event) end
end

local function QuestSummary(store)
    local text
    for _, pair in ipairs(DOING) do
        if store.Get(pair[1]) then text = text and (text .. ", " .. pair[2]) or pair[2] end
    end
    if not text then return TEXT_BY_HAND end
    return text:sub(1, 1):upper() .. text:sub(2)
end

hooksecurefunc("QuestInfo_GetRewardButton", OnRewardButton)
hooksecurefunc("QuestInfo_ShowRewards", OnShowRewards)
events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^quest") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local page = ns.Shared.Settings.Page("QoL/Questing & Group", S)

page:Card({
    id = "quests", name = "Quests", order = 10,
    help = "Accepts, hands in and shares quests for you, and remembers the reward you saved for a "
        .. "quest. Hold the Skip Modifier to deal with one quest yourself.",
    summary = QuestSummary,
    rows = {
        { key = "questAccept", label = "Accept Quests", toggle = true,
          help = "Accepts a quest as soon as its text opens. Hold the Skip Modifier to read it first." },
        { key = "questTurnIn", label = "Hand In Quests", toggle = true,
          help = "Hands in finished quests. A quest with a choice of rewards waits for you to pick "
              .. "one, unless you saved a reward for it. Hold the Skip Modifier to skip it." },
        { key = "questGossip", label = "Pick Quests From NPCs", toggle = true,
          help = "When an NPC offers several things, goes straight to a finished quest to hand in, "
              .. "or the first quest on offer. Works with the two options above." },
        { key = "questRewardPicks", label = "Saved Quest Rewards", toggle = true,
          help = "Alt-click a reward you can choose, in the quest log or at the quest giver, to save "
              .. "it for that quest in this profile; Alt-click it again to clear it. It is selected "
              .. "when you hand the quest in, and Hand In Quests takes it for you." },
        { key = "questShare", label = "Share Quests With Group", toggle = true,
          help = "While you are in a group, shares each quest you accept from an NPC with the "
              .. "others, if the quest can be shared. A quest someone shared with you is not "
              .. "shared again. Hold the Skip Modifier as you accept to keep it to yourself." },
        { key = "questSkipModifier", label = "Skip Modifier", choice = SKIP,
          help = "Hold it to skip Accept Quests, Hand In Quests, Pick Quests From NPCs and sharing for that quest." },
    },
})
