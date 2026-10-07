-------------------------------------------------------------------------------
--  NaowhForever_SummonEmote.lua -- the QoL summon emote: an /emote of your own when you start
--  casting a spell you listed, such as Ritual of Summoning, so the group knows to click.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local spells = {}
local lastEmote, pending = 0, nil

local function On()
    return S.Get("enabled") and S.Get("autoEmote")
end

local function InInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and kind ~= "none"
end

-- "698: prepares a ritual of summoning; 29893: prepares a soulwell"
local function ParseSpells()
    wipe(spells)
    for id, text in S.Get("autoEmoteList"):gmatch("(%d+)%s*:%s*([^;]+)") do
        text = strtrim(text)
        if text ~= "" then spells[tonumber(id)] = text end
    end
end

local function SendEmote(text)
    C_ChatInfo.SendChatMessage(text, "EMOTE")
    lastEmote = GetTime()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending and On() and InInstance() then
            C_Timer.After(0, function()
                if pending then SendEmote(pending) end
                pending = nil
            end)
        else
            pending = nil
        end
        return
    end
    local _, _, spellID = ...
    local text = spells[spellID]
    if not (text and On() and InInstance()) then return end
    if GetTime() - lastEmote < S.Get("autoEmoteCooldown") then return end
    if UnitAffectingCombat("player") then
        pending = text
    else
        SendEmote(text)
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    pending = nil
    if not On() then return end
    ParseSpells()
    events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^autoEmote") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

ns.Shared.Settings.Page("QoL/Combat", S):Card({
    id = "summonEmote", name = "Summon Emote", order = 110, switch = "autoEmote",
    help = "Sends an /emote of your own in a dungeon or raid when you start casting a summon.",
    rows = {
        { key = "autoEmoteCooldown", label = "Cooldown", slider = { 0, 30, 1 }, unit = "s",
          help = "The shortest time between two summon emotes." },
        { key = "autoEmoteList", label = "Summon Spells", text = true, wide = true,
          help = "Spell ID and emote, separated by semicolons, such as 698: prepares a ritual of summoning." },
    },
})
