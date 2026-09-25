local f = assert(io.open(arg[1] or "NaowhForever_Trainer.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

-- Spells by id: name and rank. The spellbook's best rank of each is `known`.
local SPELLS = {
    [2050] = { "Lesser Heal", 1 }, [2052] = { "Lesser Heal", 2 }, [2053] = { "Lesser Heal", 3 },
    [2054] = { "Heal", 1 }, [2055] = { "Heal", 2 }, [6063] = { "Heal", 3 }, [6064] = { "Heal", 4 },
    [585] = { "Smite", 1 }, [591] = { "Smite", 2 }, [598] = { "Smite", 3 },
}
local function Fixture(bars, known, kept)
    local env = {
        KEYBOARD_SLOTS = 180,
        GetActionInfo = function(slot) if bars[slot] then return "spell", bars[slot] end end,
        C_Spell = {
            GetSpellName = function(id) return SPELLS[id][1] end,
            GetSpellSubtext = function(id) return "Rank " .. SPELLS[id][2] end,
        },
        C_GamepadUI = {
            GetFirstGamepadActionStorageSlotIndex = function() return 181 end,
            IsValidGamepadActionStorageSlotIndex = function(slot) return slot <= 190 end,
        },
        HighestRanks = function()
            local best = {}
            for _, id in ipairs(known) do best[SPELLS[id][1]] = { rank = SPELLS[id][2], spellID = id } end
            return best
        end,
        Kept = function() return kept or {} end,
    }
    setmetatable(env, { __index = _G })
    local code = "local " .. Slice("function RankOf(", "\n---") .. "local "
        .. Slice("function CheckSlot(", "\n-- The spell names in a list")
        .. "\nreturn Upgrades"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    return chunk()
end
local function Slots(ups)
    local out = {}
    for _, up in ipairs(ups) do out[#out + 1] = up.slot .. ">" .. up.spellID end
    table.sort(out)
    return table.concat(out, " ")
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("a lone lower rank is swapped for the highest known", function()
    assert(Slots(Fixture({ [1] = 2055 }, { 6064 })()) == "1>6064")
end)
Case("a downrank beside the main copy stays; only the main copy is swapped", function()
    assert(Slots(Fixture({ [1] = 2054, [2] = 2055 }, { 6064 })()) == "2>6064")
end)
Case("nothing swaps when the top rank is already on the bars", function()
    assert(Slots(Fixture({ [1] = 2054, [2] = 6064 }, { 6064 })()) == "")
end)
Case("the same highest rank on several slots, keyboard and controller, all swap", function()
    assert(Slots(Fixture({ [1] = 2055, [185] = 2055, [3] = 2054 }, { 6064 })()) == "185>6064 1>6064")
end)
Case("each spell is judged on its own", function()
    local ups = Fixture({ [1] = 2050, [2] = 2052, [3] = 585, [4] = 2055 }, { 2053, 598, 6064 })()
    assert(Slots(ups) == "2>2053 3>598 4>6064")
end)
Case("kept spells are still listed, flagged", function()
    local ups = Fixture({ [1] = 2054, [2] = 2055 }, { 6064 }, { Heal = true })()
    assert(#ups == 1 and ups[1].slot == 2 and ups[1].kept == true)
end)
Case("spells not in the spellbook and empty slots are ignored", function()
    assert(Slots(Fixture({ [1] = 2055 }, { 598 })()) == "")
end)
print(count .. " trainer rank regressions passed")
