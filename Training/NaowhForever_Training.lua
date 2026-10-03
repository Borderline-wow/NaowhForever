-------------------------------------------------------------------------------
--  NaowhForever_Training.lua -- the Training Planner: every spell your class still has to
--  learn, what you can train now and what each level brings, with the trainer's prices. The
--  spells and base prices come from NaowhForever_TrainingData.lua; the trainer window
--  updates a price to what it actually asked, kept account-wide. This file sorts the spells
--  (ns.Training), keeps the talent builds saved or imported, and holds the settings page; the
--  window is NaowhForever_TrainingWindow.lua, the level-up toast and the panel beside the
--  trainer NaowhForever_TrainingTrainer.lua.
--
--  Off by default. While off it registers nothing but its login check.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local S = UI.ModuleSettings("training", { enabled = false, levelUpToast = true, trainerPanel = true,
    showLearned = false, miniShown = false })
ns.TrainingSettings = S

local Training = {}
ns.Training = Training

local SOON = 2            -- levels ahead that count as coming soon
Training.SOON = SOON

local function On()
    return S.Get("enabled")
end
Training.On = On

local function Account(key)
    local account = ns.AccountSettings()
    account[key] = account[key] or {}
    return account[key]
end

-- spellID -> copper, as a trainer last asked for it.
local function Prices()
    return Account("trainingPrices")
end

-- spellID -> true for the spells this character chose not to see in the lists.
local charKey
local function Ignored()
    local all = Account("trainingIgnored")
    charKey = charKey or UnitName("player") .. "-" .. GetRealmName()
    all[charKey] = all[charKey] or {}
    return all[charKey]
end

local function ClassSpells()
    local _, _, classID = UnitClass("player")
    return ns.TrainingData[classID] or {}
end
Training.ClassSpells = ClassSpells

local function ForMyRace(entry, race)
    if not entry.races then return true end
    for _, r in ipairs(entry.races) do
        if r == race then return true end
    end
    return false
end

local function Price(entry)
    return Prices()[entry[2]] or entry[3]
end
Training.Price = Price

-------------------------------------------------------------------------------
--  Sorting the class's spells
-------------------------------------------------------------------------------
-- Each spell this character can learn, under the first state that fits it, in level order:
-- now, rank (the rank before is not learned), soon, later, talent, ignored, learned. Also
-- every one of them by level (byLevel) with what is learned (known). A rank counts as learned once a
-- later rank is: some ranks replace the one before. level is the character's unless given:
-- PLAYER_LEVEL_UP says the new one before UnitLevel does.
local function Plan(level)
    local _, _, race = UnitRace("player")
    local ignored = Ignored()
    level = level or UnitLevel("player")
    local mine, after = {}, {}
    for _, entry in ipairs(ClassSpells()) do
        if ForMyRace(entry, race) then
            mine[#mine + 1] = entry
            if entry.needs then after[entry.needs] = entry[2] end
        end
    end
    local known = {}
    for i = #mine, 1, -1 do
        local spell = mine[i][2]
        known[spell] = C_SpellBook.IsSpellKnown(spell) or known[after[spell]] or false
    end
    local plan = { now = {}, rank = {}, soon = {}, later = {}, talent = {}, ignored = {}, learned = {},
        byLevel = {}, known = known, level = level }
    for _, entry in ipairs(mine) do
        local spell = entry[2]
        local group = plan.byLevel[entry[1]]
        if not group then
            group = {}
            plan.byLevel[entry[1]] = group
        end
        group[#group + 1] = entry
        if not known[spell] then
            local state = "now"
            if ignored[spell] then
                state = "ignored"
            elseif entry.talent and not C_SpellBook.IsSpellKnown(entry.talent) then
                state = "talent"
            elseif entry[1] > level + SOON then
                state = "later"
            elseif entry[1] > level then
                state = "soon"
            -- A rank before that no trainer sells (granted at level 1) is not in the list: ask the game.
            elseif entry.needs and not (known[entry.needs] or known[entry.needs] == nil
                and C_SpellBook.IsSpellKnown(entry.needs)) then
                state = "rank"
            end
            local list = plan[state]
            list[#list + 1] = entry
        else
            plan.learned[#plan.learned + 1] = entry
        end
    end
    return plan
end
Training.Plan = Plan

-------------------------------------------------------------------------------
--  What a rank adds
-------------------------------------------------------------------------------
-- Words that end the name of what a number measures ("16 to 24 Fire damage and ...").
local STOP = { ["and"] = true, ["over"] = true, ["for"] = true, ["to"] = true, ["of"] = true,
    ["by"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["per"] = true, ["every"] = true,
    ["at"] = true, ["in"] = true, ["with"] = true, ["your"] = true, ["target"] = true,
    ["target's"] = true }
-- What a number measures when it is a time or a distance: a rank changing those is not its point.
local NOT_POWER = { sec = true, seconds = true, min = true, minutes = true, hour = true, hours = true,
    yd = true, yards = true }

-- Up to two words right after a number, up to the first joining word: "Fire damage".
local function After(text)
    local kept = {}
    for word in text:gmatch("[%a']+") do
        if STOP[word:lower()] or #kept == 2 then break end
        kept[#kept + 1] = word
    end
    return table.concat(kept, " ")
end

-- Up to two words before a number, past the joining words next to it: "Intellect" in
-- "Increases the target's Intellect by 7".
local function Before(text)
    local words, kept = {}, {}
    for word in text:gmatch("[%a']+") do words[#words + 1] = word end
    for i = #words, 1, -1 do
        if STOP[words[i]:lower()] then
            if #kept > 0 then break end
        else
            table.insert(kept, 1, words[i])
            if #kept == 2 then break end
        end
    end
    return table.concat(kept, " ")
end

-- The numbers in a spell's description, in order, each { low, high, what, unit }: "causes
-- 16 to 24 Fire damage" is one, 16 to 24, what "Fire damage". what is the words after the
-- number, else the ones before it ("Intellect by 7"); unit is the word right after it.
local function Numbers(text)
    local out, pos = {}, 1
    while true do
        local s, e, low = text:find("(%d+%.?%d*)", pos)
        if not s then break end
        local high = low
        local _, rangeEnd, top = text:find("^ to (%d+%.?%d*)", e + 1)
        if rangeEnd then high, e = top, rangeEnd end
        local rest = text:sub(e + 1):match("^%%?%s*([^%.,;:%d]*)") or ""
        local before = text:sub(1, s - 1):match("([^%.,;:%d]*)$") or ""
        local what = After(rest)
        if what == "" then what = Before(before) end
        out[#out + 1] = { low = tonumber(low), high = tonumber(high), what = what,
            unit = (rest:match("^([%a]+)") or ""):lower() }
        pos = e + 1
    end
    return out
end

local function Range(n)
    if n.low == n.high then return ("%g"):format(n.low) end
    return ("%g-%g"):format(n.low, n.high)
end

-- What the new description adds over the old: { pct, from, to, what } for the first number
-- that grew and is not a time or a distance, or nil when the two do not line up.
function Training.Compare(old, new)
    local a, b = Numbers(old or ""), Numbers(new or "")
    if #a == 0 or #a ~= #b then return nil end
    for i = 1, #a do
        local was, now = a[i], b[i]
        local before, after = (was.low + was.high) / 2, (now.low + now.high) / 2
        if after > before and before > 0 and not NOT_POWER[now.unit] then
            return { pct = math.floor((after / before - 1) * 100 + 0.5), from = Range(was), to = Range(now),
                what = now.what }
        end
    end
end

-- spellID -> what it adds over the rank before (false: nothing to show). Descriptions the
-- client has not loaded yet are asked for; Training.OnChange runs when they arrive.
local upgrades, waiting = {}, {}

function Training.Upgrade(entry)
    local spell, before = entry[2], entry.needs or entry.talent
    if not before then return nil end
    if upgrades[spell] == nil then
        local old, new = C_Spell.GetSpellDescription(before), C_Spell.GetSpellDescription(spell)
        if old == "" or new == "" or not old or not new then
            for _, id in ipairs({ before, spell }) do
                if not waiting[id] then
                    waiting[id] = true
                    C_Spell.RequestLoadSpellData(id)
                end
            end
            return nil
        end
        upgrades[spell] = Training.Compare(old, new) or false
    end
    return upgrades[spell] or nil
end

function Training.Waiting()
    return next(waiting) ~= nil
end

function Training.Loaded(spell)
    waiting[spell] = nil
end

-------------------------------------------------------------------------------
--  Telling the window, the panels and the settings page
-------------------------------------------------------------------------------
local listeners = {}

function Training.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function Changed()
    for i = 1, #listeners do listeners[i]() end
    UI:RefreshPage(true)
end
Training.Changed = Changed

function Training.SetIgnored(spell, allRanks, on)
    local ignored = Ignored()
    local name = C_Spell.GetSpellName(spell)
    for _, entry in ipairs(ClassSpells()) do
        if entry[2] == spell or allRanks and C_Spell.GetSpellName(entry[2]) == name then
            ignored[entry[2]] = on or nil
        end
    end
    Changed()
end

-- What is left to pay on the road to 60: every spell still to learn but the skipped ones and
-- those waiting on a talent you may never take.
function Training.ToSixty(plan)
    return Training.Total(plan.now) + Training.Total(plan.rank) + Training.Total(plan.soon)
        + Training.Total(plan.later)
end

function Training.Total(entries)
    local total = 0
    for _, entry in ipairs(entries) do total = total + Price(entry) end
    return total
end

-- "1g 40s 5c" as text, each letter in its coin's colour, leaving out the coins that are zero.
-- Text stays sharp at any size; the game's coin icons blur when drawn large.
local COIN_COLORS = { g = "ffd100", s = "c7ccd3", c = "e0904f" }

function Training.Coins(copper)
    copper = math.floor(copper + 0.5)
    local parts = {}
    local function Add(n, unit)
        parts[#parts + 1] = n .. "|cff" .. COIN_COLORS[unit] .. unit .. "|r"
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then Add(g, "g") end
    if s > 0 then Add(s, "s") end
    if c > 0 or #parts == 0 then Add(c, "c") end
    return table.concat(parts, " ")
end

-------------------------------------------------------------------------------
--  Talent builds: Naowh's, then the ones saved or imported, kept account-wide
-------------------------------------------------------------------------------
local BUILD_PREFIX = "!NFB1!"
local MAX_POINTS = 51      -- one a level, 10 to 60
local ROW_POINTS = 5       -- points in a column for each row above a talent

local function Saved(classID)
    local all = Account("trainingBuilds")
    all[classID] = all[classID] or {}
    return all[classID]
end

-- A class's builds, each { name, spec, points }; saved ones have saved = true.
function Training.Builds(classID)
    local list = {}
    for _, build in ipairs(ns.TrainingBuilds[classID] or {}) do list[#list + 1] = build end
    for _, build in ipairs(Saved(classID)) do list[#list + 1] = build end
    return list
end

-- talent node -> your rank in it, from the active talent config; nil without one.
function Training.Ranks(talents)
    local config = C_ClassTalents.GetActiveConfigID()
    if not config then return nil end
    local ranks = {}
    for node in pairs(talents) do ranks[node] = C_Traits.GetNodeInfo(config, node).activeRank end
    return ranks
end

-- Why these points cannot be taken in this order, or nil when they can. tree is a class's
-- entry in ns.TrainingBuilds; the first point that breaks a rule is the one explained.
function Training.CheckBuild(tree, points)
    local count, spent = {}, {}
    for i, node in ipairs(points) do
        local talent = tree.talents[node]
        if not talent then return "That talent is not in this class's tree." end
        if i > MAX_POINTS then return "All " .. MAX_POINTS .. " points are spent." end
        local rank = (count[node] or 0) + 1
        if rank > talent[2] then return "Already at full rank." end
        local need = talent[6]
        if need and (count[need] or 0) < tree.talents[need][2] then
            return "Needs " .. (C_Spell.GetSpellName(tree.talents[need][1]) or "the talent above it") .. " at full rank first."
        end
        local col, row = talent[4], talent[3]
        if (spent[col] or 0) < ROW_POINTS * (row - 1) then
            return ("Needs %d points in %s first."):format(ROW_POINTS * (row - 1), tree.specs[col])
        end
        count[node], spent[col] = rank, (spent[col] or 0) + 1
    end
end

-- The column with the most points names a build's spec.
local function MainSpec(tree, points)
    local spent, best = {}, nil
    for _, node in ipairs(points) do
        local col = tree.talents[node][4]
        spent[col] = (spent[col] or 0) + 1
        if not best or spent[col] > spent[best] then best = col end
    end
    return best and tree.specs[best] or "No points yet"
end

local function Codec()
    return LibStub("LibSerialize"), LibStub("LibDeflate")
end

local function BuildName(text, default)
    return type(text) == "string" and text ~= "" and (text:sub(1, 40):gsub("|", "||")) or default
end

function Training.ExportBuild(classID, build)
    local LS, LD = Codec()
    return BUILD_PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({
        v = 1, class = classID, name = build.name, spec = build.spec, points = build.points,
    })))
end

-- Parsed as data, never run: the class must have a tree here, and its points pass
-- Training.CheckBuild.
local function DecodeBuild(text)
    local LS, LD = Codec()
    local body = type(text) == "string" and text:match("^%s*" .. BUILD_PREFIX:gsub("!", "%%!") .. "(%S+)%s*$")
    local packed = body and LD:DecodeForPrint(body)
    local raw = packed and LD:DecompressDeflate(packed)
    if not raw then return end
    local ok, data = LS:Deserialize(raw)
    if not (ok and type(data) == "table" and data.v == 1 and type(data.points) == "table") then return end
    local tree = ns.TrainingBuilds[data.class]
    if not tree then return end
    local points = {}
    for i, node in ipairs(data.points) do
        if i > MAX_POINTS then return end
        points[i] = node
    end
    if #points == 0 or Training.CheckBuild(tree, points) then return end
    return data.class, { name = BuildName(data.name, "Imported Build"), spec = BuildName(data.spec, "Imported"),
        points = points, saved = true }
end

-- onAdded(classID, index) once it is in, index in Training.Builds(classID).
function Training.ImportBuild(text, onAdded)
    local classID, build = DecodeBuild(text)
    if not classID then
        ns.Print("That is not a Naowh Forever talent build.")
        return
    end
    ns.Confirm(("Add the %s build %s (%d points)?"):format(GetClassInfo(classID), build.name, #build.points), function()
        local saved = Saved(classID)
        saved[#saved + 1] = build
        Changed()
        ns.Print("Imported " .. build.name .. ".")
        onAdded(classID, #(ns.TrainingBuilds[classID]) + #saved)
    end)
end

-- Your talents as a build, row by row: the game keeps which talents you have, not the order
-- you took them in. Returns your class and its index in Training.Builds, or nil.
function Training.SaveMyTalents(name)
    local _, _, classID = UnitClass("player")
    local tree = ns.TrainingBuilds[classID]
    local ranks = tree and Training.Ranks(tree.talents)
    if not ranks then return end
    local nodes = {}
    for node in pairs(tree.talents) do nodes[#nodes + 1] = node end
    table.sort(nodes, function(a, b)
        local rowA, rowB = tree.talents[a][3], tree.talents[b][3]
        if rowA ~= rowB then return rowA < rowB end
        return a < b
    end)
    local points = {}
    for _, node in ipairs(nodes) do
        for _ = 1, math.min(ranks[node], tree.talents[node][2]) do points[#points + 1] = node end
    end
    if #points == 0 then
        ns.Print("You have no talent points spent to save.")
        return
    end
    local saved = Saved(classID)
    saved[#saved + 1] = { name = BuildName(name, "My Talents"), spec = "Your talents", points = points, saved = true }
    Changed()
    return classID, #tree + #saved
end

-- A new saved build, empty or a copy of another. Returns its index in Training.Builds.
function Training.NewBuild(classID, name, from)
    local points = {}
    for i, node in ipairs(from and from.points or {}) do points[i] = node end
    local saved = Saved(classID)
    saved[#saved + 1] = { name = BuildName(name, "New Build"), spec = from and from.spec or "No points yet",
        points = points, saved = true }
    Changed()
    return #(ns.TrainingBuilds[classID]) + #saved
end

-- Editing a saved build: each returns why not, or nil once done.
function Training.AddPoint(tree, build, node)
    local points = build.points
    points[#points + 1] = node
    local why = Training.CheckBuild(tree, points)
    if why then
        points[#points] = nil
        return why
    end
    build.spec = MainSpec(tree, points)
    Changed()
end

-- Gives back node's latest point, unless a later point needs it.
function Training.RemovePoint(tree, build, node)
    local points = build.points
    for i = #points, 1, -1 do
        if points[i] == node then
            table.remove(points, i)
            local why = Training.CheckBuild(tree, points)
            if why then
                table.insert(points, i, node)
                return "A later point needs it. " .. why
            end
            build.spec = MainSpec(tree, points)
            Changed()
            return
        end
    end
    return "No points in it to give back."
end

function Training.UndoPoint(tree, build)
    build.points[#build.points] = nil
    build.spec = MainSpec(tree, build.points)
    Changed()
end

function Training.ClearPoints(build)
    wipe(build.points)
    build.spec = "No points yet"
    Changed()
end

function Training.DeleteBuild(classID, build)
    local saved = Saved(classID)
    for i, b in ipairs(saved) do
        if b == build then
            table.remove(saved, i)
            break
        end
    end
    Changed()
end

-------------------------------------------------------------------------------
--  At the trainer
-------------------------------------------------------------------------------
-- The trainer's list has names and required levels but no spell IDs, so a service is the
-- class spell of that name and level. Forever's trainer returns Blizzard's Mainline order:
-- name, kind, icon, level. A header has no level, so it matches nothing.
local function SpellsByService()
    local byKey = {}
    for _, entry in ipairs(ClassSpells()) do
        local name = C_Spell.GetSpellName(entry[2])
        if name then
            local key = name .. "|" .. entry[1]
            byKey[key] = byKey[key] or entry[2]
        end
    end
    return byKey
end

-- The class spell a trainer service teaches, or nil.
function Training.ServiceSpell(byKey, i)
    local name, _, _, level = GetTrainerServiceInfo(i)
    return name and byKey[name .. "|" .. (level or 0)]
end
Training.SpellsByService = SpellsByService

local function ScanTrainer()
    if IsTradeskillTrainer() then return end
    local byKey = SpellsByService()
    local prices, changed = Prices(), false
    for i = 1, GetNumTrainerServices() do
        local spell = Training.ServiceSpell(byKey, i)
        local cost = spell and GetTrainerServiceCost(i)
        if cost and prices[spell] ~= cost then
            prices[spell] = cost
            changed = true
        end
    end
    if changed then Changed() end
end

local scanQueued = false
local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0, function()
        scanQueued = false
        if On() then ScanTrainer() end
    end)
end

local events
local function Apply()
    if not On() then
        if events then events:UnregisterAllEvents() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
                QueueScan()
            else
                Changed()
            end
        end)
    end
    events:RegisterEvent("TRAINER_SHOW")
    events:RegisterEvent("TRAINER_UPDATE")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
end

S.OnChange(function(key)
    if key == "enabled" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)

-------------------------------------------------------------------------------
--  Settings page
-------------------------------------------------------------------------------
function ns.BuildTrainingSettingsPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "What you can train now and what each level brings, with the trainer's "
        .. "price and a road to 60. Opening your class trainer updates the prices to what it asks, "
        .. "reputation discounts included. Open it with /nftraining, its minimap or top bar "
        .. "button, or here.", y)
    y = y - h
    -- The planner opens in place of the options window, which would otherwise sit over it.
    _, h = W:Button(parent, "Open Training Planner", y, function()
        ns.StashOptionsWindow()
        ns.OpenTrainingWindow()
    end)
    y = y - h

    _, h = W:SectionHeader(parent, "ON THE WAY" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("levelUpToast", "Level-Up Toast",
            "When you level up with new spells to train, a toast says how many and what they cost, "
            .. "with a button to open the planner. Move it in Unlock Mode.", "enabled"),
        S.Toggle("trainerPanel", "Panel at the Trainer",
            "Beside your class trainer, the spells you can learn now, ticked, with their total "
            .. "and Learn All I Can Afford. Untick one to leave it.", "enabled")
    ); y = y - h
    return y
end
