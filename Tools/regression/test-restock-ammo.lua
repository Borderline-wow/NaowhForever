-- Run with Lua 5.1 from the repository root: the Restock Reminder's Hunter Ammo option reads the
-- equipped ammo against its own warning amount, and only for a hunter with the option on.
local f = assert(io.open(arg[1] or "NaowhForever_QoL/Loot/Restock.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

local ARROWS = 2512
local function Fixture(class, settings, have, wanted)
    local env = {
        PLAYER_CLASS = class, AMMO_SLOT = 0, TEXT_SHORT = "%s  %d / %d",
        S = { Get = function(key) return settings[key] end },
        ItemName = function(id) return "item" .. id end,
        Wanted = function() return wanted or {} end,
        GetInventoryItemID = function() return ARROWS end,
        C_Item = { GetItemCount = function() return have end },
    }
    setmetatable(env, { __index = _G })
    local code = Slice("local function HunterAmmoOn()", "\nlocal function ItemName(")
        .. Slice("local function ReagentLines(", "\nlocal function BagLines(")
        .. "\nreturn ReagentLines, HunterAmmoLines"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    local Reagents, Ammo = chunk()
    local lines = {}
    Reagents(lines)
    Ammo(lines)
    return table.concat(lines, "|")
end
local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

local ON = { restockHunterAmmo = true, restockHunterAmmoBelow = 500 }
Case("at or below its own amount, the equipped ammo is reminded", function()
    assert(Fixture("HUNTER", ON, 500) == "item2512  500 / 500")
    assert(Fixture("HUNTER", ON, 120) == "item2512  120 / 500")
end)
Case("above its own amount, nothing", function()
    assert(Fixture("HUNTER", ON, 501) == "")
end)
Case("it replaces the carry target for that ammo, not for other reagents", function()
    local wanted = { [ARROWS] = 1000, [999] = 20 }
    assert(Fixture("HUNTER", ON, 600, wanted) == "")
    assert(Fixture("HUNTER", { restockHunterAmmo = false }, 600, wanted) == "item2512  600 / 1000")
end)
Case("off, or not a hunter, adds nothing", function()
    assert(Fixture("HUNTER", { restockHunterAmmo = false, restockHunterAmmoBelow = 500 }, 10) == "")
    assert(Fixture("WARRIOR", ON, 10) == "")
end)

-- Synthetic item IDs exercise subclass detection without assuming a Forever item catalog.
local THROWN, BOW = 900001, 900002
local function WantedFor(class, settings, inventory)
    local env = setmetatable({
        PLAYER_CLASS = class, AMMO_SLOT = 0, RANGED_SLOT = 18,
        WEAPON_CLASS = 2, THROWN_SUBCLASS = 16, THROWN_CLASSES = { ROGUE = true, WARRIOR = true },
        FAMILIES = {}, S = { Get = function(key) return settings[key] end },
        GetInventoryItemID = function(_, slot) return inventory[slot] end,
        C_Item = { GetItemInfoInstant = function(id)
            return id, nil, nil, nil, nil, 2, id == THROWN and 16 or 2
        end },
    }, { __index = _G })
    local start = source:find("local function CarriedAmmo()", 1, true) and "local function CarriedAmmo()"
        or "local function Wanted()"
    local chunk = assert(loadstring(Slice(start, "\nlocal function FoodLevel(")
        .. "\nreturn Wanted()"))
    setfenv(chunk, env)
    return chunk()
end
local saved = { restockAmmo = true, restockAmmoTarget = 700 }
Case("rogue and warrior count their equipped thrown weapon using the saved carry target", function()
    for _, class in ipairs({ "ROGUE", "WARRIOR" }) do
        local want = WantedFor(class, saved, { [18] = THROWN, [0] = ARROWS })
        assert(want[THROWN] == 700 and want[ARROWS] == nil)
    end
end)
Case("a bow keeps legacy ammo-slot behavior; an empty slot contributes nothing", function()
    assert(WantedFor("ROGUE", saved, { [18] = BOW, [0] = ARROWS })[ARROWS] == 700)
    assert(next(WantedFor("WARRIOR", saved, {})) == nil)
end)
Case("hunters retain ammo-slot targets; thrown restocking respects the existing toggle", function()
    assert(WantedFor("HUNTER", saved, { [18] = BOW, [0] = ARROWS })[ARROWS] == 700)
    assert(next(WantedFor("ROGUE", { restockAmmo = false }, { [18] = THROWN })) == nil)
end)
print(count .. " total restock ammo regressions passed")
