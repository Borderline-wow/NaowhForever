-- BuffReminders.lua: the Buffs & Consumables row of icons on screen, refreshed out of combat.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings
local D = ns.BuffReminderData
local R, Cell, Menu = A.Buffs, A.BuffCell, A.BuffMenu
local Left, Secret, GROUP_UNIT = R.Left, R.Secret, R.GROUP_UNIT

local QUEUE_DELAY = 0.3
local ELIXIR_ICON = 13454
local WAKE_PAD = 0.1
local WAKE_SAME = 0.01
local HOME_Y = 220
local CARD = A.PAGE .. ":buffs"
local TEXT_MOVER = "Buff Reminders"
local KEYS = {
    consumableEntries = true, enabled = true, food = true, elixirs = true, flasks = true, consumablesWhere = true,
    consumablesMinutes = true, onlyIfCarried = true, hideResting = true, scrolls = true,
    scrollsSkipActive = true, raidBuffs = true, raidBuffsOwn = true, raidBuffPicks = true, iconSize = true,
    buffsFont = true, buffsFontSize = true, buffsOutline = true,
}
local PREVIEW = {
    { spell = D.WELL_FED[1] }, { item = D.FLASKS.items[1] }, { item = ELIXIR_ICON },
    { item = D.SCROLLS[4].items[4], count = 2 }, { spell = D.RAID[1].spells[1], count = 3 },
}

local frame, unlocked, pending
local wakeTimer, wakeDue
local cells = {}
local events = CreateFrame("Frame")

local function OnCellHide(cell)
    if Menu.OwnedBy(cell) then Menu.Hide() end
end

local function GetCell(i)
    local cell = cells[i]
    if cell then return cell end
    cell = Cell.New(frame)
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", Menu.Open)
    cell:SetScript("OnLeave", Menu.Leave)
    cell:SetScript("OnHide", OnCellHide)
    cell.timer = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.timer:SetAllPoints()
    cell.timer:SetDrawEdge(false)
    cell.timer:SetReverse(true)
    cells[i] = cell
    return cell
end

local function ShowTimer(cell, aura)
    if aura and Left(aura) and not Secret(aura.duration) then
        cell.timer:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
        cell.timer:Show()
    else
        cell.timer:Hide()
    end
end

local function Show(list)
    local size = S.Get("iconSize")
    for i, entry in ipairs(list) do
        local cell = GetCell(i)
        Cell.Place(cell, frame, i, size, entry.icon, entry.count)
        cell.items = entry.items
        ShowTimer(cell, entry.aura)
        cell:Show()
    end
    for i = #list + 1, #cells do cells[i]:Hide() end
    Cell.Fit(frame, #list, size)
    local owner = Menu.Owner()
    if not owner then return end
    if owner:IsShown() and owner.items then Menu.Open(owner) else Menu.Hide() end
end

local function PreviewList()
    local list = {}
    for i, p in ipairs(PREVIEW) do
        list[i] = { icon = p.item and C_Item.GetItemIconByID(p.item) or C_Spell.GetSpellTexture(p.spell), count = p.count }
    end
    return list
end

local Refresh

local function StopWake()
    if wakeTimer then wakeTimer:Cancel() end
    wakeTimer, wakeDue = nil, nil
end

local function OnWake()
    wakeTimer, wakeDue = nil, nil
    Refresh()
end

local function ArmWake(seconds)
    local due = GetTime() + seconds
    if wakeTimer and math.abs(due - wakeDue) < WAKE_SAME then return end
    StopWake()
    wakeDue = due
    wakeTimer = C_Timer.NewTimer(seconds + WAKE_PAD, OnWake)
end

function Refresh()
    pending = nil
    if not frame then return end
    if unlocked then return Show(PreviewList()) end
    if not R.On() then return Show({}) end
    local list = R.Collect()
    if not list then return end
    Show(list)
    local wakeAt = R.WakeAt()
    if wakeAt then ArmWake(wakeAt) else StopWake() end
end

local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(QUEUE_DELAY, Refresh)
end

local function OnEvent(_, event, unit)
    if event == "UNIT_AURA" and (InCombatLockdown() or Secret(unit) or not GROUP_UNIT[unit]) then return end
    if event == "PLAYER_REGEN_DISABLED" then
        Menu.Hide()
        return
    end
    if event == "ITEM_DATA_LOAD_RESULT" and not R.Requested(unit) then return end
    Queue()
end

local function SavePosition(pos)
    S.Set("buffsPos", pos)
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverBuffReminders", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.mover = ns.UI.AttachMover(frame, TEXT_MOVER, SavePosition, A.PAGE, CARD)
end

local function Place()
    local pos = S.Get("buffsPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, HOME_Y)
    end
end

local function Listen()
    if S.Get("raidBuffs") then
        events:RegisterEvent("UNIT_AURA")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
    else
        events:RegisterUnitEvent("UNIT_AURA", "player")
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
end

local function Apply()
    Menu.Hide()
    events:UnregisterAllEvents()
    StopWake()
    if not (R.On() or unlocked) then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Place()
    frame.mover:SetShown(unlocked == true)
    frame:Show()
    if R.On() then Listen() end
    Refresh()
end

local function OnSet(key)
    if KEYS[key] then Apply() end
end

local function OnUnlock()
    unlocked = S.Get("enabled") == true
    Menu.unlocked = unlocked
    Apply()
end

local function OnLock()
    unlocked = false
    Menu.unlocked = false
    if frame then Apply() end
end

A.BuffPreview = PREVIEW

events:SetScript("OnEvent", OnEvent)
hooksecurefunc(S, "Set", OnSet)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", OnUnlock)
hooksecurefunc(ns, "HideUnlockMode", OnLock)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
