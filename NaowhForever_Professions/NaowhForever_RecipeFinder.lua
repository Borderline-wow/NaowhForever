-------------------------------------------------------------------------------
--  NaowhForever_RecipeFinder.lua -- the recipes you have not learned yet, and for each the
--  skill it needs, what it costs and where it comes from: the nearest trainers, the vendor
--  selling its manual, or the mobs that drop it. Visiting a profession trainer records what
--  its recipes really need and cost. Data: RecipeData.lua.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local T = ns.THEME

local NEAREST = 3
local GREEN = { r = 0.35, g = 1, b = 0.35 }
local ORANGE = { r = 1, g = 0.6, b = 0.2 }

local list, state = {}, nil
local current, EMPTY, skillOf = {}, {}, {}
local learnedNow

local function On()
    return S.Get("enabled") and S.Get("recipeFinder")
end

local function Faction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

local function ForMe(fac)
    return fac == "-" or fac:find(Faction(), 1, true) ~= nil
end

local function Money(copper)
    if not copper or copper <= 0 then return "free" end
    return GetMoneyString and GetMoneyString(copper, true) or C_CurrencyInfo.GetCoinTextureString(copper)
end

local function ZoneName(map)
    local info = C_Map.GetMapInfo(map)
    return info and info.name or "?"
end

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

-------------------------------------------------------------------------------
--  Profession state
-------------------------------------------------------------------------------
local function Match(p)
    if not p then return end
    if ns.RecipeData[p.professionID] then return p.professionID end
    if ns.RecipeData[p.parentProfessionID] then return p.parentProfessionID end
    for id, data in pairs(ns.RecipeData) do
        if p.professionName and p.professionName == C_Spell.GetSpellName(data.skillSpell) then return id end
    end
end

-- Only your own profession: a linked or guild recipe list, or an NPC's crafting window, is
-- somebody else's recipes.
local function ReadProfession()
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then return end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return end
    local child, base = C_TradeSkillUI.GetChildProfessionInfo(), C_TradeSkillUI.GetBaseProfessionInfo()
    local id = Match(child) or Match(base)
    if not id then return end
    local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
    return id, src.skillLevel or 0, src.maxSkillLevel or 0
end

local function Learned(spell)
    local known = learnedNow and learnedNow[spell]
    if known then return true end
    if known == nil then
        local info = C_TradeSkillUI.GetRecipeInfo(spell)
        if info and info.learned then return true end
    end
    return C_SpellBook.IsSpellKnown(spell)
end

-- What profession trainers actually ask, read off their window: Forever lowered many trainer
-- requirements and Wowhead still lists the older ones. Account-wide, spellID -> { skill, cost }.
local function Overrides()
    local account = ns.AccountSettings()
    account.profTrainerReq = account.profTrainerReq or {}
    return account.profTrainerReq
end

local function Skill(r)
    local o = Overrides()[r.spell]
    return o and o[1] or r.skill
end

local function Cost(r)
    local o = Overrides()[r.spell]
    return o and o[2] or r.cost
end

-- "ready": learnable now. "later": your cap allows it, your skill does not yet.
-- "rank": your cap is below it, so the next profession rank comes first.
local function Status(r)
    local need = Skill(r)
    if state.skill >= need then return "ready" end
    if state.max < need then return "rank" end
    return "later"
end

local function NextRank()
    for _, rank in ipairs(state.data.ranks) do
        if rank.cap > state.max then return rank end
    end
end

-------------------------------------------------------------------------------
--  Nearest NPCs
-------------------------------------------------------------------------------
local function WorldPos(map, x, y)
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if ok and cont and pos then return cont, pos end
end

local function NearestFirst(a, b)
    if a.dist ~= b.dist then return a.dist < b.dist end
    return a.npc[2] < b.npc[2]
end

-- The NPCs your faction can use, nearest first. Anything on another continent (or while
-- you are somewhere with no map position) sorts after, alphabetically.
local function Nearest(npcs, n)
    local map = C_Map.GetBestMapForUnit("player")
    local here = map and C_Map.GetPlayerMapPosition(map, "player")
    local cont, pos
    if here then cont, pos = WorldPos(map, here:GetXY()) end
    local out = {}
    for _, npc in ipairs(npcs) do
        if ForMe(npc[3]) then
            local dist = math.huge
            if cont and npc[4] > 0 then
                local c, p = WorldPos(npc[4], npc[5] / 100, npc[6] / 100)
                if c == cont then
                    local x1, y1 = pos:GetXY()
                    local x2, y2 = p:GetXY()
                    dist = (x1 - x2) ^ 2 + (y1 - y2) ^ 2
                end
            end
            out[#out + 1] = { npc = npc, dist = dist }
        end
    end
    table.sort(out, NearestFirst)
    local picked = {}
    for i = 1, math.min(n or #out, #out) do picked[i] = out[i].npc end
    return picked
end

-------------------------------------------------------------------------------
--  Detail text
-------------------------------------------------------------------------------
-- An uncached item name reads "its manual" until the item loads; the window redraws on
-- ITEM_DATA_LOAD_RESULT.
local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if name then return Hex(T.accent) .. name .. "|r" end
    if ns.ProfRequestItem then
        ns.ProfRequestItem(itemID)
    else
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return "its manual"
end

local function Para(out, text)
    out[#out + 1] = { text = text, para = true }
end

local function NpcLine(out, npc, extra)
    out[#out + 1] = {
        text = ("%s - %s %.1f, %.1f%s"):format(npc[2], ZoneName(npc[4]), npc[5], npc[6], extra or ""),
        npc = npc,
    }
end

-- Trainer lists in the data are indices into the profession's trainers, so each NPC is written
-- out once; rank books, quest givers and vendors are full rows.
local function Rows(list, data)
    if not list or type(list[1]) ~= "number" then return list or {} end
    local trainers = (data or state.data).trainers
    local rows = {}
    for i, index in ipairs(list) do rows[i] = trainers[index] end
    return rows
end

local function QuestTitle(id, fallback)
    return id and C_QuestLog.GetTitleForQuestID(id) or fallback or "?"
end

local function DescribeRank(rank, r, out)
    if rank.item then
        Para(out, ("Your cap is %d.\nFirst read %s (needs skill %d):"):format(
            state.max, ItemName(rank.item), rank.skill))
        for _, v in ipairs(Nearest(rank.vendors, 1)) do NpcLine(out, v, "  " .. Money(v[7])) end
    elseif rank.quest then
        local title = QuestTitle(rank.quest[Faction()], rank.questName)
        Para(out, ("Your cap is %d.\nFirst do the quest %s%s|r (%sskill %d):"):format(state.max,
            Hex(T.accent), title, rank.level and ("level " .. rank.level .. ", ") or "", rank.skill))
        for _, v in ipairs(Nearest(rank.teachers, 1)) do NpcLine(out, v) end
    else
        Para(out, ("Your cap is %d.\nFirst train %s (%s, needs skill %d):"):format(
            state.max, rank.name, Money(rank.cost), rank.skill))
        for _, v in ipairs(Nearest(rank.t and Rows(rank.t) or state.data.trainers, 1)) do NpcLine(out, v) end
    end
end

local function DescribeQuests(out, quests, recipe)
    local mine = {}
    for _, q in ipairs(quests) do
        if ForMe(q.side or "AH") then mine[#mine + 1] = q end
    end
    if #mine == 0 then
        Para(out, (recipe and ("Recipe: " .. ItemName(recipe) .. "\n") or "")
            .. "A quest reward for the other faction; try the Auction House.")
        return
    end
    local names = {}
    for i, q in ipairs(mine) do names[i] = Hex(T.accent) .. QuestTitle(q.id, q.name) .. "|r" end
    Para(out, (recipe and ("Recipe: " .. ItemName(recipe) .. "\n") or "")
        .. "A reward from the quest " .. table.concat(names, " or ") .. ":")
    for _, q in ipairs(mine) do
        if q.npc then NpcLine(out, q.npc, "  (quest giver)") end
    end
end

local function Describe(r)
    local out = {}
    local data = state.data
    if Status(r) == "rank" then
        local rank = NextRank()
        if rank then DescribeRank(rank, r, out) end
    end

    if r.source == "trainer" then
        Para(out, ("Trainer: %s.%s Nearest:"):format(Money(Cost(r)),
            r.quest and (" Also a reward from the quest " .. Hex(T.accent) .. r.quest .. "|r.") or ""))
        for _, v in ipairs(Nearest(r.t and Rows(r.t) or data.trainers, NEAREST)) do NpcLine(out, v) end
    elseif r.source == "teacher" then
        Para(out, "Taught for free by the Artisan doctor:")
        for _, rank in ipairs(data.ranks) do
            if rank.teachers then
                for _, v in ipairs(Nearest(rank.teachers, 1)) do NpcLine(out, v) end
            end
        end
    elseif r.source == "vendor" then
        local sellers = Nearest(r.vendors)
        if #sellers == 0 then
            Para(out, ("Recipe: %s\nOnly the other faction sells it; try the Auction House."):format(
                ItemName(r.recipe)))
        else
            local price = sellers[1][7] and ("Sold for " .. Money(sellers[1][7])) or "Sold"
            Para(out, ("Recipe: %s\n%s%s by:"):format(ItemName(r.recipe), price,
                r.rep and (" (needs " .. r.rep .. ")") or ""))
            for i = 1, math.min(NEAREST, #sellers) do NpcLine(out, sellers[i]) end
        end
    elseif r.source == "drop" and r.bosses then
        Para(out, ("Recipe: %s\nDrops from:"):format(ItemName(r.recipe)))
        for _, b in ipairs(r.bosses) do
            out[#out + 1] = { text = ("%s - %s"):format(b[1], b[2] and C_Map.GetAreaInfo(b[2]) or "?") }
        end
    elseif r.source == "drop" and r.world then
        Para(out, ("Recipe: %s\nA world drop%s. Also try the Auction House."):format(ItemName(r.recipe),
            r.world > 1 and (", from mobs around level " .. r.world) or ""))
    elseif r.source == "drop" then
        local extra = {}
        if r.chests then extra[#extra + 1] = "chests and lockboxes" end
        if r.fished then extra[#extra + 1] = "fishing" end
        if r.pickpocket then extra[#extra + 1] = "pickpocketing" end
        local from = (r.mobs or 0) > 0 and ("A world drop from %d kinds of mob"):format(r.mobs) or "Found"
        Para(out, ("Recipe: %s\n%s%s.%s"):format(ItemName(r.recipe), from,
            #extra > 0 and ((r.mobs or 0) > 0 and ", " or " through ") .. table.concat(extra, ", ") or "",
            #(r.drops or {}) > 0 and " Best odds:" or ""))
        for _, d in ipairs(r.drops or {}) do
            local level = d[3] == d[4] and tostring(d[3]) or (d[3] .. "-" .. d[4])
            out[#out + 1] = { text = ("%s (%s) - %s, %.1f%%"):format(d[1], level,
                C_Map.GetAreaInfo(d[2]) or "?", d[5]) }
        end
    elseif r.source == "quest" then
        DescribeQuests(out, r.quests, r.recipe)
    else
        Para(out, (r.recipe and ("Recipe: " .. ItemName(r.recipe) .. "\n") or "")
            .. "Where it comes from is not recorded yet; try the Auction House.")
    end
    return out
end

-------------------------------------------------------------------------------
--  The unlearned list
-------------------------------------------------------------------------------
local function RowColor(r)
    local st = Status(r)
    if st == "ready" then return GREEN end
    if st == "rank" then return ORANGE end
    return T.muted
end

local SOURCE_TAG = { trainer = "Trainer", teacher = "Trainer", vendor = "Vendor", drop = "Drop",
    quest = "Quest", unknown = "?" }

local function BySkill(x, y)
    local sx, sy = skillOf[x], skillOf[y]
    if sx ~= sy then return sx < sy end
    return x.spell < y.spell
end

-- False when the open profession has no data, or is not your own.
local function Compute()
    local id, skill, max = ReadProfession()
    wipe(list)
    if not id then
        state = nil
        return false
    end
    state = current
    state.id, state.data, state.skill, state.max = id, ns.RecipeData[id], skill, max
    for _, r in ipairs(state.data.recipes) do
        if not Learned(r.spell) then
            list[#list + 1] = r
            skillOf[r] = Skill(r)
        end
    end
    table.sort(list, BySkill)
    return true
end

ns.RecipeFinder = {
    Unlearned = function(learned)
        learnedNow = learned
        local ok = On() and Compute()
        learnedNow = nil
        if not ok then return EMPTY end
        return list
    end,
    Color = function(r) return RowColor(r) end,
    Status = function(r) return Status(r) end,
    Requirement = function(r)
        local profName = C_Spell.GetSpellName(state.data.skillSpell) or "First Aid"
        return ("%sRequires %s %d|r   %s(you: %d/%d)|r"):format(Hex(RowColor(r)), profName, Skill(r),
            Hex(T.muted), state.skill, state.max)
    end,
    Describe = function(r) return Describe(r) end,
    Tag = function(r) return SOURCE_TAG[r.source] or "?" end,
    Skill = function(r) return Skill(r) end,
    -- For the rank banner: the open profession's skill line, skill and cap (nil when it is
    -- not your own), NPC rows nearest first, trainer indices to rows, and formatting.
    Current = function() return ReadProfession() end,
    Nearest = Nearest,
    Rows = Rows,
    Money = Money,
    ZoneName = ZoneName,
    Hex = Hex,
}

-- At a profession trainer: remember what each recipe on offer really needs and costs.
-- Matched by name within the trainer's profession, since the service list has no spell IDs.
local function ScanTrainer()
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    local byName, lineOf = {}, {}
    for line, data in pairs(ns.RecipeData) do
        lineOf[C_Spell.GetSpellName(data.skillSpell) or ""] = line
        for _, r in ipairs(data.recipes) do
            local name = C_Spell.GetSpellName(r.spell)
            if name then
                byName[name] = byName[name] or {}
                byName[name][#byName[name] + 1] = { r = r, line = line }
            end
        end
    end
    local overrides, changed = Overrides(), false
    for i = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(i)
        local skillName, rank = GetTrainerServiceSkillReq(i)
        if name and category ~= "header" and rank and byName[name] then
            local line = lineOf[skillName or ""]
            for _, m in ipairs(byName[name]) do
                if not line or m.line == line then
                    local cost = GetTrainerServiceCost(i)
                    local old = overrides[m.r.spell]
                    if not old or old[1] ~= rank or old[2] ~= cost then
                        overrides[m.r.spell] = { rank, cost }
                        changed = true
                    end
                end
            end
        end
    end
    if changed and ns.ProfWindowRefresh then ns.ProfWindowRefresh(true) end
end

local trainerQueued = false
local function QueueTrainerScan()
    if trainerQueued then return end
    trainerQueued = true
    C_Timer.After(0.2, function()
        trainerQueued = false
        ScanTrainer()
    end)
end

-- /naowh recipes: what the profession API reports on this client, to check the finder's
-- reading of it.
function ns.RecipeFinderDebug()
    local function Dump(label, p)
        if not p then
            ns.Print(label .. ": nil")
            return
        end
        ns.Print(("%s: id=%s parent=%s name=%s skill=%s/%s"):format(label, tostring(p.professionID),
            tostring(p.parentProfessionID), tostring(p.professionName), tostring(p.skillLevel),
            tostring(p.maxSkillLevel)))
    end
    Dump("child", C_TradeSkillUI.GetChildProfessionInfo())
    Dump("base", C_TradeSkillUI.GetBaseProfessionInfo())
    local id, skill, max = ReadProfession()
    ns.Print(("matched=%s skill=%s/%s"):format(tostring(id), tostring(skill), tostring(max)))
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
    local apiUnlearned = 0
    for _, rid in ipairs(ids) do
        local info = C_TradeSkillUI.GetRecipeInfo(rid)
        if info and not info.learned then apiUnlearned = apiUnlearned + 1 end
    end
    ns.Print(("API recipes: %d (%d unlearned)"):format(#ids, apiUnlearned))
    if id then
        local learned = 0
        for _, r in ipairs(ns.RecipeData[id].recipes) do
            if Learned(r.spell) then learned = learned + 1 end
        end
        ns.Print(("Data recipes: %d, %d learned"):format(#ns.RecipeData[id].recipes, learned))
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", QueueTrainerScan)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then return end
    events:RegisterEvent("TRAINER_SHOW")
    events:RegisterEvent("TRAINER_UPDATE")
end

-- The Unlearned Recipes switch changes what the window lists.
hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "recipeFinder" then
        Apply()
        if ns.ProfWindowRefresh then ns.ProfWindowRefresh(true) end
    end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
