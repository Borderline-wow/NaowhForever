-- ModuleState.lua: keeps this character's AddOn list the same as the profile's module switches (ns.ReconcileModules, ns.SetModuleState).
local ns = _G.NaowhForever
local Setup = ns.Setup

local LOGIN_DELAY = 8
local TEXT_MATCHED = ns.L("Your modules were changed to match your profile. Reload now?")

local modules, byAddon = {}, {}
for id, item in pairs(Setup.ITEMS) do
    local m = { id = id, addon = item.addon, db = item.db, key = item.key }
    modules[#modules + 1], byAddon[item.addon] = m, m
end

local watch

local function Explicit(m)
    local values = ns.SettingsRoot()[m.db]
    if type(values) == "table" and type(values[m.key]) == "boolean" then return values[m.key] end
end

local function StoreOf(addon)
    for _, switch in ipairs(ns.ModuleSwitches()) do
        if switch.addon == addon then return switch.store, switch.key end
    end
end

local function SetListed(addon, on, me)
    if on then C_AddOns.EnableAddOn(addon, me) else C_AddOns.DisableAddOn(addon, me) end
end

local function Prompt()
    if not InCombatLockdown() then return ns.ConfirmReload(TEXT_MATCHED) end
    if not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            Prompt()
        end)
    end
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function ns.SetModuleState(addon, on)
    local m = byAddon[addon]
    SetListed(addon, on, UnitGUID("player"))
    if m then
        m.store = StoreOf(addon)
        return Setup.SetSwitch(m, on)
    end
    local store, key = StoreOf(addon)
    if on and store then store.Set(key, true) end
end

function ns.ReconcileModules(quiet)
    local account = ns.AccountSettings()
    local me = UnitGUID("player")
    if not account.onboardingSeen or not me then return 0 end
    if type(account.moduleList) ~= "table" then account.moduleList = {} end
    local was = account.moduleList[me]
    local present, listed, want = {}, {}, {}
    for _, m in ipairs(modules) do
        if C_AddOns.DoesAddOnExist(m.addon) then
            present[#present + 1] = m
            local on = C_AddOns.GetAddOnEnableState(m.addon, me) > 0
            local profile, before = Explicit(m), was and was[m.addon]
            listed[m.addon] = on
            if before == nil then
                want[m.id] = on and profile ~= false
            elseif on ~= before then
                want[m.id] = on
            elseif profile ~= nil then
                want[m.id] = profile
            else
                want[m.id] = on
            end
        end
    end
    Setup.Settle(want, present)
    local changed, now = 0, {}
    for _, m in ipairs(present) do
        local on, profile = want[m.id], Explicit(m)
        if on ~= listed[m.addon] then
            SetListed(m.addon, on, me)
            changed = changed + 1
        end
        local switchedOn = profile
        if switchedOn == nil then switchedOn = ns.FEATURES[m.db][m.key] end
        if on and profile == false or not on and switchedOn then
            m.store = StoreOf(m.addon)
            Setup.SetSwitch(m, on)
        end
        now[m.addon] = on
    end
    account.moduleList[me] = now
    if changed > 0 and not quiet then Prompt() end
    return changed
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(LOGIN_DELAY, function() ns.ReconcileModules() end)
end)
