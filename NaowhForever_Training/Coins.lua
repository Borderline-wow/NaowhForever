-- Coins.lua: an amount of money as the planner writes it, each coin's letter in its colour.
local ns = _G.NaowhForever

local Training = ns.Training
local C = Training.C

local GOLD, SILVER = C.COPPER_PER_GOLD, C.COPPER_PER_SILVER
local ROUND = C.ROUND
local COIN_COLORS = { g = "ffd100", s = "c7ccd3", c = "e0904f" }

local function Coin(text, n, unit)
    local coin = n .. "|cff" .. COIN_COLORS[unit] .. unit .. "|r"
    return text and text .. " " .. coin or coin
end

function Training.Coins(copper)
    copper = math.floor(copper + ROUND)
    local g, s, c = math.floor(copper / GOLD), math.floor(copper % GOLD / SILVER), copper % SILVER
    local text
    if g > 0 then text = Coin(nil, g, "g") end
    if s > 0 then text = Coin(text, s, "s") end
    if c > 0 or not text then text = Coin(text, c, "c") end
    return text
end
