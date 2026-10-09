-- LowHealth.lua: the Low Health icon on screen, shown by the game itself below the threshold, in combat too.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings
local St = A.Style
local Low, Look = A.LowHealth, A.LowHealthLook

local HOME_Y = -180
local GLOW_RGBA, GLOW_THICKNESS = St.LOW_GLOW_RGBA, St.LOW_GLOW_THICKNESS
local CARD = A.PAGE .. ":lowHealth"
local TEXT_MOVER = "Low Health"
local GLOW_LIB = "LibCustomGlow-1.0"

local frame, curve, unlocked
local shownItem, wasLow, glowing
local events = CreateFrame("Frame")

local function UpdateItem()
    local id = Low.PickItem()
    local count = id and C_Item.GetItemCount(id) or 0
    if id == shownItem and frame.itemShown then
        Look.Count(frame, count)
        return
    end
    shownItem, frame.itemShown = id, true
    Look.Item(frame, id, count)
end

local function SetGlow(on)
    on = on and true or false
    if on == glowing then return end
    glowing = on
    local LCG = LibStub(GLOW_LIB, true)
    if not LCG then return end
    if on then
        LCG.PixelGlow_Start(frame, GLOW_RGBA, nil, nil, nil, GLOW_THICKNESS)
    else
        LCG.PixelGlow_Stop(frame)
    end
end

local function CheckSound()
    local pct = UnitHealthPercent("player", true)
    if issecretvalue and issecretvalue(pct) then
        SetGlow(S.Get("lowHealthGlow"))
        return
    end
    local low = pct < Low.Below()
    SetGlow(low and S.Get("lowHealthGlow"))
    if low and not wasLow and S.Get("lowHealthSound") then
        ns.UI._PlayLSMSound(ns.UI.SoundPathFor(S.Get("lowHealthSoundKey")))
    end
    wasLow = low
end

local function UpdateAlpha()
    if unlocked then
        frame:SetAlpha(1)
    elseif UnitIsDeadOrGhost("player") then
        frame:SetAlpha(0)
        SetGlow(false)
        wasLow = false
    else
        frame:SetAlpha(UnitHealthPercent("player", true, curve))
        CheckSound()
    end
end

local function SavePosition(pos)
    S.Set("lowHealthPos", pos)
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverLowHealth", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetAlpha(0)
    Look.New(frame)
    frame.mover = ns.UI.AttachMover(frame, TEXT_MOVER, SavePosition, A.PAGE, CARD)
end

local function Place()
    local pos = S.Get("lowHealthPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, HOME_Y)
    end
end

local function OnEvent(_, event)
    if event == "BAG_UPDATE_DELAYED" then UpdateItem() else UpdateAlpha() end
end

local function Listen()
    events:RegisterUnitEvent("UNIT_HEALTH", "player")
    events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    events:RegisterEvent("PLAYER_DEAD")
    events:RegisterEvent("PLAYER_ALIVE")
    events:RegisterEvent("PLAYER_UNGHOST")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
end

local function Apply()
    events:UnregisterAllEvents()
    if not (Low.On() or unlocked) then
        if frame then
            frame:Hide()
            SetGlow(false)
        end
        return
    end
    if not frame then Build() end
    local size = S.Get("lowHealthIconSize")
    frame:SetSize(size, size)
    Look.Style(frame)
    Place()
    curve = Low.Curve(curve)
    frame.itemShown = nil
    UpdateItem()
    SetGlow(unlocked and S.Get("lowHealthGlow"))
    frame.mover:SetShown(unlocked == true)
    frame:Show()
    if Low.On() then Listen() end
    UpdateAlpha()
end

local function OnSet(key)
    if key == "enabled" or (key:find("^lowHealth") and key ~= "lowHealthPos") then Apply() end
end

local function OnUnlock()
    unlocked = S.Get("enabled") == true
    Apply()
end

local function OnLock()
    unlocked = false
    if frame then Apply() end
end

events:SetScript("OnEvent", OnEvent)
hooksecurefunc(S, "Set", OnSet)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", OnUnlock)
hooksecurefunc(ns, "HideUnlockMode", OnLock)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
