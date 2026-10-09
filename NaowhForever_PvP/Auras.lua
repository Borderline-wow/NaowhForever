-- Auras.lua: PvP Auras shown, hidden and kept up to date: your target's and your focus's panels, their events and Unlock Mode.
local ns = _G.NaowhForever

local P = ns.PvP
local S = P.Settings
local Panel = P.Panel

local DISPLAYS = P.Displays

local unlocked
local absorbUnits = {}
local events = CreateFrame("Frame")

local function On()
    return S.Get("enabled") == true and S.Get("auras") == true
end

local function FocusIsTarget()
    if not (UnitExists("focus") and UnitExists("target")) then return false end
    local same = UnitIsUnit("focus", "target")
    return P.Readable(same) and same == true
end

local function UpdateFocusFade()
    for _, d in ipairs(DISPLAYS) do
        if d.nameKey and d.holder then
            d.holder:SetAlpha((FocusIsTarget() and not unlocked) and 0 or 1)
        end
    end
end

local function ShowDisplay(d)
    events:RegisterEvent(d.changed)
    if not d.holder then Panel.Build(d) end
    Panel.Rows(d)
    Panel.Layout(d)
    Panel.Place(d)
    d.container:SetEnabled(true)
    d.holder:Show()
    d.absorb:SetShown(S.Get("absorb") == true)
    if S.Get("absorb") then absorbUnits[#absorbUnits + 1] = d.unit end
    Panel.UpdateAbsorb(d)
    Panel.UpdateHeader(d)
    d.holder.mover:SetShown(unlocked == true)
end

local function Apply()
    if not On() and not Panel.Built() then
        events:UnregisterAllEvents()
        return
    end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    events:UnregisterAllEvents()
    if not On() then
        for _, d in ipairs(DISPLAYS) do Panel.Hide(d) end
        return
    end
    P.RefreshLists()
    wipe(absorbUnits)
    for _, d in ipairs(DISPLAYS) do
        if P.DisplayOn(d) then ShowDisplay(d) else Panel.Hide(d) end
    end
    UpdateFocusFade()
    if absorbUnits[1] then events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", absorbUnits[1], absorbUnits[2]) end
    Panel.ResizeButtons()
end

local function OnAbsorbChanged(unit)
    for _, d in ipairs(DISPLAYS) do
        if d.unit == unit then Panel.UpdateAbsorb(d) end
    end
end

local function OnUnitChanged(event)
    for _, d in ipairs(DISPLAYS) do
        if event == d.changed and d.container then
            d.container:UpdateAllAuras()
            Panel.UpdateAbsorb(d)
            Panel.UpdateHeader(d)
            UpdateFocusFade()
            return true
        end
    end
end

local function OnEvent(self, event, unit)
    if event == "UNIT_ABSORB_AMOUNT_CHANGED" then return OnAbsorbChanged(unit) end
    if OnUnitChanged(event) then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if Panel.ResizePending() then Panel.ResizeButtons() end
    Apply()
end

local function OnSettingChanged(key)
    if key ~= "pos" and key ~= "focusPos" then Apply() end
end

local function OnUnlock()
    unlocked = S.Get("enabled") == true
    Apply()
end

local function OnLock()
    unlocked = false
    Apply()
end

events:SetScript("OnEvent", OnEvent)
S.OnChange(OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", OnUnlock)
hooksecurefunc(ns, "HideUnlockMode", OnLock)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
