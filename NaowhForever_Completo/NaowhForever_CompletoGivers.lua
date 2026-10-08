-------------------------------------------------------------------------------
--  NaowhForever_CompletoGivers.lua -- learns from the quest givers you speak to which quests
--  they really offer you. The data cannot know every prerequisite (a quest that needs another
--  first, outside its chain, or a reputation), so a quest it says you could take, but whose
--  giver does not have it for you, is held back: no ! on the map, "Not offered yet" in the
--  window, until you level up or hand in a quest in its zone (Q.NotOffered).
--
--  The giver's own list says what is on offer: the gossip window's (GOSSIP_SHOW), the quest
--  greeting's (QUEST_GREETING), or the one quest an NPC with nothing else opens straight away
--  (QUEST_DETAIL). Off while Completo is: no events until it is on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.CompletoSettings
local Q = ns.Completo.Quests

local offered = {}   -- questID -> true, what the giver in front of you has; reused
local listed         -- the GUID of the last giver whose whole list you saw

-- The giver's quests the data says you could take: each one on offer or held back.
local function Learn(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local zone = Q.CurrentZone()
    if not zone then return end
    Q.Refresh()
    -- Givers leave grey quests out of their list unless low level quests are tracked.
    local trivial = not C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests)
    for _, id in ipairs(Q.GiverQuests(UnitName(unit), zone.map)) do
        if Q.Expected(id) == "open" and (trivial or not Q.Trivial(id)) then
            Q.SetOffered(id, offered[id] == true)
        end
    end
end

local function FromGossip()
    wipe(offered)
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if quest.questID then offered[quest.questID] = true end
    end
    listed = UnitGUID("npc")
    Learn("npc")
end

-- The greeting names its quests; the ID is GetAvailableQuestInfo's fifth answer where the
-- client gives it, else the quest is found by its title among the giver's.
local function FromGreeting()
    wipe(offered)
    local titles = {}
    for i = 1, GetNumAvailableQuests() do
        local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
        if id then offered[id] = true else titles[GetAvailableTitle(i) or ""] = true end
    end
    if next(titles) then
        local zone = Q.CurrentZone()
        for _, id in ipairs(zone and Q.GiverQuests(UnitName("npc"), zone.map) or {}) do
            if titles[Q.Name(id)] then offered[id] = true end
        end
    end
    listed = UnitGUID("npc")
    Learn("npc")
end

-- An NPC with one quest and nothing else opens it straight away: that is all it has for you.
-- Not when it comes from a list you just saw (that list said it all), a player sharing it or
-- an item.
local function FromDetail()
    local guid = UnitGUID("questnpc")
    if not guid or guid == listed then return end
    wipe(offered)
    offered[GetQuestID()] = true
    Learn("questnpc")
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, questID)
    if event == "GOSSIP_SHOW" then
        FromGossip()
    elseif event == "QUEST_GREETING" then
        FromGreeting()
    elseif event == "QUEST_DETAIL" then
        FromDetail()
    elseif event == "QUEST_TURNED_IN" then
        Q.CountTurnIn(questID)
    end
end)

local EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_TURNED_IN" }

local function Apply()
    events:UnregisterAllEvents()
    if not S.Get("enabled") then return end
    for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
