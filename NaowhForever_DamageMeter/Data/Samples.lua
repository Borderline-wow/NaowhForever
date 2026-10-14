-- Samples.lua: the sample group the preview and Unlock Mode show (DM.SAMPLE).
local ns = _G.NaowhForever

local OWN = 2

ns.DamageMeter.SAMPLE = {
    durationSeconds = 205,
    fightName = "Training Dummy",
    maxAmount = 100,
    totalAmount = 660,
    combatSources = {
        { name = "Aldrin", classFilename = "MAGE", totalAmount = 100, amountPerSecond = 41, isLocalPlayer = false,
          deathTimeSeconds = 28 },
        { name = "You", classFilename = "ROGUE", totalAmount = 91, amountPerSecond = 37, isLocalPlayer = true,
          deathTimeSeconds = 55 },
        { name = "Brenna", classFilename = "WARLOCK", totalAmount = 84, amountPerSecond = 34, isLocalPlayer = false,
          deathTimeSeconds = 80 },
        { name = "Corvus", classFilename = "HUNTER", totalAmount = 77, amountPerSecond = 31, isLocalPlayer = false,
          deathTimeSeconds = 112 },
        { name = "Dara", classFilename = "WARRIOR", totalAmount = 62, amountPerSecond = 25, isLocalPlayer = false,
          deathTimeSeconds = 140 },
        { name = "Edric", classFilename = "PALADIN", totalAmount = 48, amountPerSecond = 20, isLocalPlayer = false,
          deathTimeSeconds = 171 },
        { name = "Fenna", classFilename = "PRIEST", totalAmount = 31, amountPerSecond = 13, isLocalPlayer = false,
          deathTimeSeconds = 198 },
    },
}

function ns.DamageMeter.Sample()
    local _, class = UnitClass("player")
    if type(class) == "string" and class ~= "" then
        ns.DamageMeter.SAMPLE.combatSources[OWN].classFilename = class
    end
    return ns.DamageMeter.SAMPLE
end
