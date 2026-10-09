-- Upgrades.lua: what a spell's rank adds over the rank before, read from the two descriptions.
local ns = _G.NaowhForever

local Training = ns.Training

local SPELL = Training.C.ENTRY_SPELL
local MAX_WORDS = 2
local PERCENT, ROUND = Training.C.PERCENT, Training.C.ROUND
local STOP = { ["and"] = true, ["over"] = true, ["for"] = true, ["to"] = true, ["of"] = true,
    ["by"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["per"] = true, ["every"] = true,
    ["at"] = true, ["in"] = true, ["with"] = true, ["your"] = true, ["target"] = true,
    ["target's"] = true }
local NOT_POWER = { sec = true, seconds = true, min = true, minutes = true, hour = true, hours = true,
    yd = true, yards = true }

local upgrades, waiting = {}, {}

local function After(text)
    local kept = {}
    for word in text:gmatch("[%a']+") do
        if STOP[word:lower()] or #kept == MAX_WORDS then break end
        kept[#kept + 1] = word
    end
    return table.concat(kept, " ")
end

local function Before(text)
    local words, kept = {}, {}
    for word in text:gmatch("[%a']+") do words[#words + 1] = word end
    for i = #words, 1, -1 do
        if STOP[words[i]:lower()] then
            if #kept > 0 then break end
        else
            table.insert(kept, 1, words[i])
            if #kept == MAX_WORDS then break end
        end
    end
    return table.concat(kept, " ")
end

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

function Training.Compare(old, new)
    local a, b = Numbers(old or ""), Numbers(new or "")
    if #a == 0 or #a ~= #b then return nil end
    for i = 1, #a do
        local was, now = a[i], b[i]
        local before, after = (was.low + was.high) / 2, (now.low + now.high) / 2
        if after > before and before > 0 and not NOT_POWER[now.unit] then
            return { pct = math.floor((after / before - 1) * PERCENT + ROUND), from = Range(was), to = Range(now),
                what = now.what }
        end
    end
end

local function Ask(ids)
    for _, id in ipairs(ids) do
        if not waiting[id] then
            waiting[id] = true
            C_Spell.RequestLoadSpellData(id)
        end
    end
end

function Training.Upgrade(entry)
    local spell, before = entry[SPELL], entry.needs or entry.talent
    if not before then return nil end
    if upgrades[spell] == nil then
        local old, new = C_Spell.GetSpellDescription(before), C_Spell.GetSpellDescription(spell)
        if old == "" or new == "" or not old or not new then
            Ask({ before, spell })
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
