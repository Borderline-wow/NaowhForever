-- Trainer.lua: the prices a class trainer asks, read at its window, and the module's events.
local ns = _G.NaowhForever

local Training = ns.Training
local S = Training.Settings
local ClassSpells = Training.ClassSpells
local Prices = Training.Prices
local Changed = Training.Changed

local LEVEL, SPELL = Training.C.ENTRY_LEVEL, Training.C.ENTRY_SPELL
local FOLLOW_EVENTS = { "TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_REGEN_ENABLED" }

local scanQueued = false
local events

local function SpellsByService()
    local byKey = {}
    for _, entry in ipairs(ClassSpells()) do
        local name = C_Spell.GetSpellName(entry[SPELL])
        if name then
            local key = name .. "|" .. entry[LEVEL]
            byKey[key] = byKey[key] or entry[SPELL]
        end
    end
    return byKey
end

local function ServiceSpell(byKey, i)
    local name, _, _, level = GetTrainerServiceInfo(i)
    return name and byKey[name .. "|" .. (level or 0)]
end

local function ScanTrainer()
    if IsTradeskillTrainer() then return end
    local byKey = SpellsByService()
    local prices, changed = Prices(), false
    for i = 1, GetNumTrainerServices() do
        local spell = ServiceSpell(byKey, i)
        local cost = spell and GetTrainerServiceCost(i)
        if cost and prices[spell] ~= cost then
            prices[spell] = cost
            changed = true
        end
    end
    if changed then Changed() end
end

local function RunScan()
    scanQueued = false
    if Training.On() then ScanTrainer() end
end

local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0, RunScan)
end

local function OnEvent(_, event)
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        QueueScan()
    elseif event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" or event == "PLAYER_REGEN_ENABLED" then
        Training.LearnFollowed()
    else
        Changed()
    end
end

local function Apply()
    if not Training.On() then
        if events then events:UnregisterAllEvents() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("TRAINER_SHOW")
    events:RegisterEvent("TRAINER_UPDATE")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    local follow = Training.Followed() ~= nil
    for _, event in ipairs(FOLLOW_EVENTS) do
        if follow then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
    if follow then Training.LearnFollowed() end
end

local function OnSettingChanged(key)
    if key == "enabled" then Apply() end
end

local function OnLogin(self)
    self:UnregisterAllEvents()
    Apply()
end

Training.SpellsByService = SpellsByService
Training.ServiceSpell = ServiceSpell
Training.Apply = Apply

S.OnChange(OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", OnLogin)
