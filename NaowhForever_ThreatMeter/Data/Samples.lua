-- Samples.lua: the Threat Meter's sample groups for its previews, your own row first, someone holding aggro.
local ns = _G.NaowhForever

ns.ThreatMeter.SAMPLES = {
    solo = { title = "Defias Pillager",
        { you = true, threat = 1850, pullPct = 100, tanking = true } },
    tanking = { title = "Edwin VanCleef",
        { you = true, threat = 12400, pullPct = 100, tanking = true },
        { name = "Vashtir", class = "ROGUE", threat = 9100, pullPct = 67 },
        { name = "Elowen", class = "MAGE", threat = 7300, pullPct = 45 },
        { name = "Wolf", class = "HUNTER", pet = true, threat = 4200, pullPct = 31 },
        { name = "Aldric", class = "PRIEST", threat = 3100, pullPct = 19 } },
    pulling = { title = "Edwin VanCleef",
        { you = true, threat = 10560, pullPct = 96 },
        { name = "Gorrak", class = "WARRIOR", threat = 10000, pullPct = 100, tanking = true },
        { name = "Maren", class = "PRIEST", threat = 4400, pullPct = 34 },
        { name = "Talwyn", class = "HUNTER", threat = 3900, pullPct = 30 } },
}
