-------------------------------------------------------------------------------
--  Reputation.lua -- what the Dungeon Journal's factions mean for you (ns.Journal.Reputation):
--  your standing with each, which of its rewards you have reached, what they cost, your BiS
--  and looks among them; and your PvP rank this season, its rewards and the season's end.
--  Rules only, no frames. Your standing is the game's (C_Reputation), read when asked; the
--  rank is the season's renown faction (C_MajorFactions), as the game's own rank panel reads it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings
local Loot = J.Loot

local GetFactionDataByID = C_Reputation.GetFactionDataByID
local GetItemCount = C_Item.GetItemCount
local GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local GetQuestIDForLogIndex = C_QuestLog.GetQuestIDForLogIndex
local AwardsReputation = C_QuestLog.DoesQuestAwardReputationWithFaction
local ReadyForTurnIn = C_QuestLog.ReadyForTurnIn
local ListBis, ListNewLooks = Loot.ListBis, Loot.ListNewLooks

local Rep = {}
J.Reputation = Rep

local EXALTED = 8                 -- the game's highest reaction (MAX_REPUTATION_REACTION)
Rep.EXALTED = EXALTED
local RANK_FACTION = 2800         -- the season's PvP rank, a renown faction
Rep.HONOR, Rep.RANK_POINTS = 1792, 3468   -- the currencies the rank page shows
local COPPER_PER_SILVER, COPPER_PER_GOLD = 100, 10000

-------------------------------------------------------------------------------
--  Standing
-------------------------------------------------------------------------------
-- Your standing: the game's reaction (4 Neutral to 8 Exalted), how far into it you are and
-- how far it goes (both 1 at Exalted, a full bar); nil when the game has nothing for the
-- faction yet.
---@param faction JournalFaction
---@return number? reaction
---@return number value
---@return number max
function Rep.Standing(faction)
    local data = GetFactionDataByID(faction.id)
    if not (data and data.reaction) then return nil, 0, 1 end
    local reaction = data.reaction
    if reaction >= EXALTED then return reaction, 1, 1 end
    local low = data.currentReactionThreshold or 0
    return reaction, data.currentStanding - low, math.max(1, (data.nextReactionThreshold or low + 1) - low)
end

-- "Revered", in the game's words for your gender. Made once per standing.
local labels = {}

---@param reaction number
---@return string
function Rep.Label(reaction)
    local label = labels[reaction]
    if not label then
        label = GetText("FACTION_STANDING_LABEL" .. reaction, UnitSex("player")) or tostring(reaction)
        labels[reaction] = label
    end
    return label
end

---@return { r: number, g: number, b: number }
function Rep.Color(reaction)
    return J.Style.STANDING_RGB[reaction] or J.Style.STANDING_RGB[4]
end

-- Whether the window lists the faction: a battleground's only while its side's half of the
-- faction switch is on, as a dungeon on that side's ground; a city only for its own side
-- (the Reputation tab has no switch).
function Rep.Shown(faction)
    if faction.rank then return true end
    if faction.side and faction.tab == "reputation" then return faction.side == UnitFactionGroup("player") end
    if faction.side == "Alliance" then return S.Get("showAlliance") end
    if faction.side == "Horde" then return S.Get("showHorde") end
    return true
end

-------------------------------------------------------------------------------
--  Its rewards
-------------------------------------------------------------------------------
-- How many of your BiS its rewards hold, and how many of those you have.
---@return number count
---@return number have
function Rep.Bis(faction)
    local count, have = 0, 0
    for _, tier in ipairs(faction.tiers) do count, have = ListBis(tier.items, count, have) end
    return count, have
end

-- How many looks you do not have yet among its rewards listed for you, and how many have a
-- look at all.
---@param filters JournalFilters
---@return number new
---@return number looks
function Rep.NewLooks(faction, filters)
    local new, looks = 0, 0
    for _, tier in ipairs(faction.tiers) do new, looks = ListNewLooks(tier.items, filters, new, looks) end
    return new, looks
end

---@return number? copper the item's price at a vendor, from the game's item table
function Rep.Price(faction, itemID)
    return faction.prices and faction.prices[itemID]
end

-- A price in short, rounded to its largest coin ("12", "4.5" and the gold coin; "35" and the
-- silver one), so the column stays narrow; the tooltip has it to the copper. Made once per
-- price: the data's prices are fixed.
local short = {}

---@param copper number
---@return string text
function Rep.PriceText(copper)
    local text = short[copper]
    if text then return text end
    local coin = J.Style.COIN_ICON
    local gold = copper / COPPER_PER_GOLD
    if gold >= 10 then
        text = math.floor(gold + 0.5) .. coin.g
    elseif gold >= 1 then
        local tenths = math.floor(gold * 10 + 0.5)
        text = (tenths % 10 == 0 and tostring(tenths / 10) or ("%.1f"):format(tenths / 10)) .. coin.g
    else
        text = math.max(1, math.floor(copper / COPPER_PER_SILVER + 0.5)) .. coin.s
    end
    short[copper] = text
    return text
end

-- Each standing's reputation, from its start to the next's, as the game counts it for every
-- faction here (Neutral 3,000, Friendly 6,000, Honored 12,000, Revered 21,000). The game only
-- says the one you are at; past it, these.
local BAND = { [1] = 36000, [2] = 3000, [3] = 3000, [4] = 3000, [5] = 6000, [6] = 12000, [7] = 21000 }

-- How much reputation until a standing: exact to the next one (the game's own count), else
-- that plus the standard size of each standing between, so about. 0 once it is reached; nil
-- when you have not met the faction.
---@return number? toGo
---@return boolean exact
function Rep.ToGo(standing, reaction, value, max)
    if not reaction then return nil, false end
    if reaction >= standing then return 0, true end
    local toGo = max - value
    for s = reaction + 1, standing - 1 do toGo = toGo + (BAND[s] or 0) end
    return toGo, standing == reaction + 1
end

-- "2,300 to go" or "about 14,300 to go".
function Rep.ToGoText(toGo, exact)
    return (exact and "" or "about ") .. BreakUpLargeNumbers(toGo) .. " to go"
end

-- How many of its rewards listed for you your standing has reached, and how many are listed.
---@param filters JournalFilters
---@return number unlocked
---@return number total
function Rep.Unlocked(faction, reaction, filters)
    local unlocked, total = 0, 0
    for _, tier in ipairs(faction.tiers) do
        local reached = reaction ~= nil and reaction >= tier.standing
        for _, id in ipairs(tier.items) do
            if Loot.Shown(id, filters) then
                total = total + 1
                if reached then unlocked = unlocked + 1 end
            end
        end
    end
    return unlocked, total
end

-------------------------------------------------------------------------------
--  Quests that raise it
-------------------------------------------------------------------------------
-- The game knows what a quest gives only once you have it, so the quests it can name are the
-- ones in your log. The repeatable hand-ins are kept by hand in the faction's data:
-- faction.turnins, each { name, rep (a hand-in's), takes (item, count, item, count...),
-- quests: one per side, each { questID, side, where it is handed in, map, x, y } }.

-- Whether the quest is one of the faction's hand-ins, which have lines of their own.
local function IsTurnIn(faction, questID)
    local turnins = faction.turnins
    if not turnins then return false end
    for i = 1, #turnins do
        local quests = turnins[i].quests
        for k = 1, #quests do
            if quests[k][1] == questID then return true end
        end
    end
    return false
end

-- The quests in your log that raise the faction, in log order, put in out (wiped first),
-- its hand-ins left out. Also returns a number that changes when one comes, goes or becomes
-- ready to hand in, so a quest log update that changes none of them redraws nothing.
---@param faction JournalFaction
---@param out number[]
---@return number[] out
---@return number signature
function Rep.LogQuests(faction, out)
    wipe(out)
    local signature = 0
    for i = 1, GetNumQuestLogEntries() do
        local id = GetQuestIDForLogIndex(i)
        if id and id > 0 and AwardsReputation(id, faction.id) and not IsTurnIn(faction, id) then
            out[#out + 1] = id
            signature = signature + id * (ReadyForTurnIn(id) and 2 or 1)
        end
    end
    return out, signature + #out
end

-- How many times your bags hold what a hand-in takes: the fewest any of its items allows.
---@param turnin table one of faction.turnins
---@return number
function Rep.TurnInsHeld(turnin)
    local takes, times = turnin.takes, nil
    for i = 1, #takes, 2 do
        local n = math.floor(GetItemCount(takes[i]) / takes[i + 1])
        if not times or n < times then times = n end
    end
    return times or 0
end

-------------------------------------------------------------------------------
--  The PvP rank
-------------------------------------------------------------------------------
---@return table? info the season's rank: renownLevel, renownReputationEarned,
---renownLevelThreshold, currentWeekProgressiveMaxLevel, maxLevel...; nil without one
function Rep.Rank()
    return C_MajorFactions.GetMajorFactionProgressionInfo(RANK_FACTION)
end

-- The rank's title in your side's words ("Sergeant", "Knight"), or the game's word for no
-- rank, as the game's own rank panel names them.
---@param rank number
---@return string
function Rep.RankTitle(rank)
    if not rank or rank <= 0 then return PVP_RANK_0_NAME end
    local side = UnitFactionGroup("player") == "Alliance" and 1 or 0
    return GetText("PVP_RANK_" .. (Enum.PvPRanks.Rank_1 + rank - 1) .. "_" .. side, UnitSex("player"))
end

---@return table[]? rewards what reaching the rank gives (MajorFactionRenownRewardInfo), new each call
function Rep.RankRewards(rank)
    return C_MajorFactions.GetRenownRewardsForLevel(RANK_FACTION, rank)
end

---@return number season the PvP season, 0 between seasons
---@return number seconds until it ends
function Rep.Season()
    return GetCurrentArenaSeason() or 0, C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd() or 0
end

---@return number quantity
---@return string? name
---@return number? icon
function Rep.Currency(id)
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then return 0 end
    return info.quantity or 0, info.name, info.iconFileID
end

-- "3 days", "5 hours", "20 minutes": how long until something, roughly.
---@param seconds number
---@return string
function Rep.Duration(seconds)
    local days = math.floor(seconds / 86400)
    if days >= 1 then return days == 1 and "1 day" or days .. " days" end
    local hours = math.floor(seconds / 3600)
    if hours >= 1 then return hours == 1 and "1 hour" or hours .. " hours" end
    local minutes = math.max(1, math.floor(seconds / 60))
    return minutes == 1 and "1 minute" or minutes .. " minutes"
end
