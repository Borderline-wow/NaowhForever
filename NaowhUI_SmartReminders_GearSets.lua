-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_GearSets.lua -- the QoL gear sets: a bar of your equipment sets to
--  swap with a click, saving new ones from what you wear, and automatic swaps to a set while
--  mounted or resting that put your previous set back afterwards. Built on the client's own
--  equipment manager, so sets are the same ones the character sheet shows.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings
local T = ns.THEME

local bar, buttons, addButton, unlocked
local pending          -- set ID waiting for combat to end
local autoSet          -- the set an automatic swap put on

local function On()
    return S.Get("gearSets")
end

local function Sets()
    local sets = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name, icon, setID, isEquipped, numItems, _, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then
            sets[#sets + 1] = { id = setID, name = name, icon = icon, equipped = isEquipped,
                items = numItems, lost = numLost }
        end
    end
    table.sort(sets, function(a, b) return a.name < b.name end)
    return sets
end

local function EquippedSet()
    for _, set in ipairs(Sets()) do
        if set.equipped then return set.id end
    end
end

local function SetByName(name)
    if not name or name == "" then return end
    return C_EquipmentSet.GetEquipmentSetID(name)
end

-- Armor cannot change in combat, so a swap asked for then waits for it to end.
local function Equip(setID)
    if not setID then return end
    if InCombatLockdown() then
        pending = setID
        ns.Print("Gear set equips when combat ends.")
        return
    end
    pending = nil
    C_EquipmentSet.UseEquipmentSet(setID)
end

-- The set an automatic swap replaced, kept per character so logging out in town or mounted
-- still puts it back after the next login.
local function Saved()
    local account = ns.AccountSettings()
    account.gearReturn = account.gearReturn or {}
    return account.gearReturn, UnitName("player") .. "-" .. GetRealmName()
end

-- A set picked by hand is kept when the automatic swap ends.
local function EquipByHand(setID)
    local saved, key = Saved()
    saved[key] = nil
    Equip(setID)
end

-------------------------------------------------------------------------------
--  Dialogs
-------------------------------------------------------------------------------
function ns.NewGearSet()
    ns.PromptText("Name the new gear set", "", 16, function(name)
        if C_EquipmentSet.GetEquipmentSetID(name) then
            ns.Print("A gear set called " .. name .. " already exists.")
            return
        end
        C_EquipmentSet.CreateEquipmentSet(name)
    end)
end

function ns.SaveGearSet(setID, name)
    ns.Confirm("Save what you are wearing now into " .. name .. "?", function()
        C_EquipmentSet.SaveEquipmentSet(setID)
    end)
end

function ns.DeleteGearSet(setID, name)
    ns.Confirm("Delete the gear set " .. name .. "?", function()
        C_EquipmentSet.DeleteEquipmentSet(setID)
    end)
end

-------------------------------------------------------------------------------
--  The bar
-------------------------------------------------------------------------------
local function SetTooltip(btn)
    local set = btn.set
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:SetText(set.name, 1, 1, 1)
    if set.equipped then GameTooltip:AddLine("Equipped", 0.29, 0.87, 0.5) end
    if set.lost > 0 then GameTooltip:AddLine(set.lost .. " item(s) missing", 0.97, 0.44, 0.44) end
    GameTooltip:AddLine("Click to equip. Shift-click to save what you wear into it.", 0.6, 0.62, 0.65, true)
    GameTooltip:Show()
end

local function NewButton()
    local btn = CreateFrame("Button", nil, bar)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.border = ns.Border(btn, { r = 0, g = 0, b = 0 })
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        if IsShiftKeyDown() then ns.SaveGearSet(self.set.id, self.set.name) else EquipByHand(self.set.id) end
    end)
    btn:SetScript("OnEnter", SetTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function Layout()
    if not bar then return end
    local size = S.Get("gearBarSize")
    local sets = Sets()
    for i, set in ipairs(sets) do
        local btn = buttons[i] or NewButton()
        buttons[i] = btn
        btn.set = set
        btn:SetSize(size, size)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", (i - 1) * (size + 4), 0)
        btn.icon:SetTexture(set.icon)
        btn.icon:SetDesaturated(set.lost > 0)
        if set.equipped then btn.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) else btn.border:SetColor(0, 0, 0, 1) end
        btn:Show()
    end
    for i = #sets + 1, #buttons do buttons[i]:Hide() end
    addButton:SetSize(size, size)
    addButton:ClearAllPoints()
    addButton:SetPoint("LEFT", #sets * (size + 4), 0)
    bar:SetSize((#sets + 1) * (size + 4), size)
end

local function BuildBar()
    bar = CreateFrame("Frame", "NaowhForeverGearBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    buttons = {}
    addButton = ns.Button(bar, "+", 32, 32, ns.NewGearSet)
    ns.Tooltip(addButton, "New Gear Set", "Saves what you are wearing now as a new set.")
    bar.mover = ns.UI.AttachMover(bar, "Gear Sets", function(pos) S.Set("gearPos", pos) end)
    local pos = S.Get("gearPos")
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    end
end

-------------------------------------------------------------------------------
--  Automatic swaps
-------------------------------------------------------------------------------
-- The set that should be on right now: mounted beats resting.
local function WantedAuto()
    if IsMounted() then
        local id = SetByName(S.Get("gearMounted"))
        if id then return id end
    end
    if IsResting() then return SetByName(S.Get("gearResting")) end
end

local function AutoSwap()
    local want = WantedAuto()
    if want == autoSet then return end
    local saved, key = Saved()
    if want then
        if not autoSet and EquippedSet() ~= want then saved[key] = EquippedSet() end
        autoSet = want
        Equip(want)
    else
        autoSet = nil
        Equip(saved[key])
        saved[key] = nil
    end
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
function ns.BuildQoLGearSetsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Your equipment sets, the same ones the character sheet keeps. Swap "
        .. "from the bar, or let a set go on by itself while you ride or rest.", y); y = y - h

    local values, order = { [""] = "None" }, { "" }
    local sets = Sets()
    for _, set in ipairs(sets) do
        values[set.name] = set.name
        order[#order + 1] = set.name
    end

    _, h = W:SectionHeader(parent, "GEAR SETS" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("gearSets", "Gear Set Bar",
            "A button per set: click to equip, Shift-click to save what you wear into it, and + "
            .. "to save a new one. The set you wear is outlined. Move it in Unlock Mode."),
        S.Slider("gearBarSize", "Button Size", 20, 48, 1, nil, "gearSets")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("gearMounted", "Wear While Mounted", values, order,
            "Put on while you ride, and the set you had on goes back when you dismount.", "gearSets"),
        S.Dropdown("gearResting", "Wear While Resting", values, order,
            "Put on in cities and inns, and taken off again when you leave.", "gearSets")
    ); y = y - h
    _, h = W:Button(parent, "New Gear Set", y, ns.NewGearSet); y = y - h

    for _, set in ipairs(sets) do
        _, h = W:SectionHeader(parent, set.name:upper() .. (set.equipped and "  (EQUIPPED)" or ""), y); y = y - h
        _, h = W:Button(parent, "Equip " .. set.name, y, function() EquipByHand(set.id) end); y = y - h
        _, h = W:Button(parent, "Save Current Gear", y, function() ns.SaveGearSet(set.id, set.name) end); y = y - h
        _, h = W:Button(parent, "Delete", y, function() ns.DeleteGearSet(set.id, set.name) end); y = y - h
    end
    return y
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then Equip(pending) end
        AutoSwap()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_UPDATE_RESTING"
        or event == "PLAYER_ENTERING_WORLD" then
        AutoSwap()
    elseif event == "EQUIPMENT_SETS_CHANGED" and ns.UI.RefreshPage then
        ns.UI:RefreshPage(true)
    end
    Layout()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if bar and not unlocked then bar:Hide() end
        return
    end
    if not bar then BuildBar() end
    for _, e in ipairs({ "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED",
                         "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UPDATE_RESTING",
                         "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(e)
    end
    Layout()
    bar:Show()
    bar.mover:SetShown(unlocked == true)
    AutoSwap()
end

hooksecurefunc(S, "Set", function(key)
    if key:find("^gear") and key ~= "gearPos" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    if On() then Apply() end
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if bar then bar.mover:Hide() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
