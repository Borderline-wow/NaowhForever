-------------------------------------------------------------------------------
--  NaowhForever_RankAlert.lua -- when a profession is ready for its next rank (Journeyman,
--  Expert, Artisan): your skill has reached what the rank asks while your cap is still the old
--  one. Shown in the profession window (ns.ProfessionRank.For) and once in chat per character.
--  Ranks and teachers come from RecipeData.lua, found through ns.RecipeFinder.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local T = ns.THEME

-- Classic's level requirements for the trained ranks; a rank's own `level` wins.
local RANK_LEVEL = { [150] = 10, [225] = 20, [300] = 35 }
local RANK_TITLE = { [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

local function On()
    return S.Get("enabled") and S.Get("rankAlert")
end

-- skillLine -> the cap of the last rank announced in chat, per character.
local charKey
local function Announced()
    local account = ns.AccountSettings()
    account.profRankAlerted = account.profRankAlerted or {}
    charKey = charKey or UnitName("player") .. "-" .. GetRealmName()
    account.profRankAlerted[charKey] = account.profRankAlerted[charKey] or {}
    return account.profRankAlerted[charKey]
end

-- Herbalism and Skinning have no recipes, so RecipeData has no entry for them. Their ranks
-- are Mining's (same skill and cost), and like Mining's every trainer teaches every rank; the
-- trainers come from the town map data. Built on first use.
local GATHERING = { [182] = "Herbalism Trainer", [393] = "Skinning Trainer" }
local gathered = {}

local function Data(line)
    if not line or not ns.RecipeData then return end
    if ns.RecipeData[line] then return ns.RecipeData[line] end
    local title, mining = GATHERING[line], ns.RecipeData[186]
    if not (title and mining and ns.TownNPCs) then return end
    if not gathered[line] then
        local trainers = {}
        for map, npcs in pairs(ns.TownNPCs) do
            for _, n in ipairs(npcs) do
                if n[3] == "profession" and n[5] == title then
                    trainers[#trainers + 1] = { n[8] or 0, n[4], n[7] or "AH", map, n[1], n[2] }
                end
            end
        end
        local ranks = {}
        for i, rank in ipairs(mining.ranks) do
            ranks[i] = { cap = rank.cap, skill = rank.skill, cost = rank.cost }
        end
        gathered[line] = { trainers = trainers, ranks = ranks }
    end
    return gathered[line]
end

local function NextRank(data, max)
    for _, rank in ipairs(data.ranks or {}) do
        if rank.cap > max then return rank end
    end
end

local function RankName(rank, prof)
    if rank.name then return rank.name end
    if RANK_TITLE[rank.cap] then return RANK_TITLE[rank.cap] .. " " .. prof end
    return ("the next rank of %s (cap %d)"):format(prof, rank.cap)
end

-- Who to see for a rank and what to tell you about them: a trainer, the vendor selling the
-- rank's book, or the quest giver who starts its quest. Nearest one your faction can use.
local function Where(data, rank)
    local RF = ns.RecipeFinder
    if rank.item then
        local npc = RF.Nearest(rank.vendors or {}, 1)[1]
        local name = C_Item.GetItemNameByID(rank.item)
        if not name then C_Item.RequestLoadItemDataByID(rank.item) end
        return npc, ("Buy and read %s%s|r (%s)"):format(RF.Hex(T.accent), name or "its book",
            RF.Money(npc and npc[7]))
    elseif rank.quest then
        local id = rank.quest[UnitFactionGroup("player") == "Horde" and "H" or "A"]
        local title = id and C_QuestLog.GetTitleForQuestID(id) or rank.questName or "its quest"
        return RF.Nearest(rank.teachers or {}, 1)[1], ("Do the quest %s%s|r"):format(RF.Hex(T.accent), title)
    end
    local list = rank.t and RF.Rows(rank.t, data) or data.trainers
    return RF.Nearest(list or {}, 1)[1], ("Train it for %s"):format(RF.Money(rank.cost))
end

-- The next rank of a profession when it can be learned now, else nil: { rankName, how, npc,
-- cap }. `npc` is a RecipeData row, nil when none is recorded for your faction.
local function For(line, skill, max, prof)
    local data = Data(line)
    local rank = data and (max or 0) > 0 and NextRank(data, max)
    if not rank or (skill or 0) < rank.skill then return end
    if UnitLevel("player") < (rank.level or RANK_LEVEL[rank.cap] or 0) then return end
    local npc, how = Where(data, rank)
    return { rankName = RankName(rank, prof or ""), how = how, npc = npc, cap = rank.cap }
end

ns.ProfessionRank = {
    For = function(line, skill, max, prof)
        if not On() then return end
        return For(line, skill, max, prof)
    end,
    Waypoint = function(npc)
        if npc and ns.PlaceWaypoint then ns.PlaceWaypoint(npc[2], npc[4], npc[5], npc[6]) end
    end,
}

-------------------------------------------------------------------------------
--  Chat
-------------------------------------------------------------------------------
-- `force` also repeats ranks already announced.
local function Check(force)
    if not ns.RecipeFinder then return end
    local announced, any = Announced(), false
    for _, index in pairs({ GetProfessions() }) do
        local name, _, skill, max, _, _, line = GetProfessionInfo(index)
        local a = For(line, skill, max, name)
        if a and (force or announced[line] ~= a.cap) then
            announced[line] = a.cap
            any = true
            ns.Print(("%s is ready for %s%s|r. %s%s. Open %s for a waypoint."):format(name,
                ns.RecipeFinder.Hex(T.accent), a.rankName, a.how, a.npc and (" from " .. a.npc[2]) or "", name))
        end
    end
    if any then
        pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN)
    elseif force then
        ns.Print("No profession is ready for its next rank yet.")
    end
end

-- /naowh profrank: every profession ready for its next rank, announced before or not.
function ns.ProfessionRankCheck()
    Check(true)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        if On() then Check(false) end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Queue)

local function Apply()
    events:UnregisterAllEvents()
    if ns.ProfWindowRefresh then ns.ProfWindowRefresh() end
    if not On() then return end
    events:RegisterEvent("SKILL_LINES_CHANGED")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    -- Logging in with a rank already due says so once the world has settled.
    C_Timer.After(5, Queue)
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "rankAlert" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
