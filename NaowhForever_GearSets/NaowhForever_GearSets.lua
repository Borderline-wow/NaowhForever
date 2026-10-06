-------------------------------------------------------------------------------
--  NaowhForever_GearSets.lua -- the QoL gear sets: a bar of your equipment sets to
--  swap with a click, saving new ones from what you wear, and automatic swaps to a set while
--  mounted or resting that put your previous set back afterwards. Built on the client's own
--  equipment manager, so sets are the same ones the character sheet shows. Also the trinket
--  bar, and the module's settings page (Gear & Trinkets/Settings); the sets themselves are in
--  the Gear Sets window (NaowhForever_GearSetsWindow.lua).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local bar, buttons, addButton, unlocked
local BUTTON_GAP = 4
local EMPTY_ICON = 134400
local TRINKET_SLOTS = { 13, 14 }

local Look = {}
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

ns.GearSets = { Sets = Sets, EquipByHand = EquipByHand, Look = Look }

-------------------------------------------------------------------------------
--  Dialogs
-------------------------------------------------------------------------------
local ICON_COLS, ICON_ROWS, ICON_SIZE, ICON_GAP = 10, 6, 36, 4

-- The icon grid and its scrollbar, built once. What changes per open -- the icon list, the
-- action -- is kept on the grid.
local function BuildIconGrid(panel)
    local grid = CreateFrame("Frame", nil, panel)
    grid:SetAllPoints()
    local slider = CreateFrame("Slider", nil, grid)
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPRIGHT", -12, -44)
    slider:SetSize(8, ICON_ROWS * (ICON_SIZE + ICON_GAP) - ICON_GAP)
    ns.Solid(slider, "BACKGROUND", T.bg, 1):SetAllPoints()
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    thumb:SetSize(8, 24)
    slider:SetThumbTexture(thumb)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    grid.slider = slider

    grid.cells = {}
    for i = 1, ICON_COLS * ICON_ROWS do
        local cell = CreateFrame("Button", nil, grid)
        cell:SetSize(ICON_SIZE, ICON_SIZE)
        cell:SetPoint("TOPLEFT", 14 + ((i - 1) % ICON_COLS) * (ICON_SIZE + ICON_GAP),
            -44 - math.floor((i - 1) / ICON_COLS) * (ICON_SIZE + ICON_GAP))
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        ns.PixelInset(cell.icon, 1)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = ns.Border(cell, { r = 0, g = 0, b = 0 })
        cell:SetScript("OnEnter", function() border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
        cell:SetScript("OnLeave", function() border:SetColor(0, 0, 0, 1) end)
        cell:SetScript("OnClick", function(self)
            local icon = grid.provider:GetIconForSaving(self.index)
            local onPick = grid.onPick
            grid.dimmer:Hide()
            onPick(icon)
        end)
        grid.cells[i] = cell
    end

    function grid:Refresh()
        local first = math.floor(slider:GetValue()) * ICON_COLS
        for i, cell in ipairs(self.cells) do
            local index = first + i
            if index <= self.count then
                cell.index = index
                cell.icon:SetTexture(self.provider:GetIconByIndex(index))
                cell:Show()
            else
                cell:Hide()
            end
        end
    end
    slider:SetScript("OnValueChanged", function() grid:Refresh() end)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta) slider:SetValue(slider:GetValue() - delta * 3) end)
    return grid
end

-- The client's own icon list, the one its equipment manager offers, with the icons of what
-- you wear first. The provider holds every macro icon while open, so it is released on close.
local function PickIcon(title, onPick)
    local UI = ns.UI
    local width = ICON_COLS * (ICON_SIZE + ICON_GAP) + 40
    local dimmer, panel = ns.MakeModal(width, ICON_ROWS * (ICON_SIZE + ICON_GAP) + 100, "gearIcon")
    local provider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Equipment)
    dimmer.onClose = function()
        provider:Release()
        dimmer.gearProvider = nil
    end
    dimmer.gearProvider = provider
    -- Hiding the UI (Alt-Z, a cinematic) hides the dialog too, which releases the icons, so
    -- it stays closed when the UI comes back.
    if not dimmer._gearHooked then
        dimmer._gearHooked = true
        dimmer:HookScript("OnShow", function(self)
            if not self.gearProvider then self:Hide() end
        end)
    end

    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", 0, -14)
    head:SetText(title)

    local grid = UI.Keep(panel, "grid", BuildIconGrid)
    grid:SetAllPoints()
    grid.provider, grid.onPick, grid.dimmer = provider, onPick, dimmer
    grid.count = provider:GetNumIcons()
    grid.slider:SetMinMaxValues(0, math.max(0, math.ceil(grid.count / ICON_COLS) - ICON_ROWS))
    grid.slider:SetValue(0)
    grid:Refresh()

    UI.KeepButton(panel, "cancel", "Cancel", 96, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
    dimmer:Show()
end

function ns.NewGearSet()
    ns.PromptText("Name the new gear set", "", 16, function(name)
        if C_EquipmentSet.GetEquipmentSetID(name) then
            ns.Print("A gear set called " .. name .. " already exists.")
            return
        end
        PickIcon("Pick an icon for " .. name, function(icon)
            C_EquipmentSet.CreateEquipmentSet(name, icon)
        end)
    end)
end

function ns.ChangeGearSetIcon(setID, name)
    PickIcon("Pick an icon for " .. name, function(icon)
        C_EquipmentSet.ModifyEquipmentSet(setID, name, icon)
    end)
end

-- The auto-swap choices hold the set's name, so they follow it to the new one.
function ns.RenameGearSet(setID, name)
    ns.PromptText("Rename " .. name, name, 16, function(newName)
        if newName == name then return end
        local other = C_EquipmentSet.GetEquipmentSetID(newName)
        if other and other ~= setID then
            ns.Print("A gear set called " .. newName .. " already exists.")
            return
        end
        local _, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        C_EquipmentSet.ModifyEquipmentSet(setID, newName, icon)
        for _, key in ipairs({ "gearMounted", "gearResting" }) do
            if S.Get(key) == name then S.Set(key, newName) end
        end
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
    if set.lost > 0 then GameTooltip:AddLine(("%d item%s missing"):format(set.lost, set.lost == 1 and "" or "s"), 0.97, 0.44, 0.44) end
    GameTooltip:AddLine("Click to equip. Shift-click to save what you wear into it. Ctrl-click to "
        .. "rename it. Right-click to change its icon.", 0.6, 0.62, 0.65, true)
    GameTooltip:Show()
end

local function NewButton()
    local btn = CreateFrame("Button", nil, bar)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(btn.icon, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.border = ns.Border(btn, { r = 0, g = 0, b = 0 })
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ns.ChangeGearSetIcon(self.set.id, self.set.name)
        elseif IsShiftKeyDown() then
            ns.SaveGearSet(self.set.id, self.set.name)
        elseif IsControlKeyDown() then
            ns.RenameGearSet(self.set.id, self.set.name)
        else
            EquipByHand(self.set.id)
        end
    end)
    btn:SetScript("OnEnter", SetTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

function Look.SetButton(btn, set, i, size)
    btn:SetSize(size, size)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", (i - 1) * (size + BUTTON_GAP), 0)
    btn.icon:SetTexture(set.icon)
    btn.icon:SetDesaturated(set.lost > 0)
    if set.equipped then btn.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) else btn.border:SetColor(0, 0, 0, 1) end
    btn:Show()
end

function Look.Fit(frame, add, count, size)
    add:SetSize(size, size)
    add:ClearAllPoints()
    add:SetPoint("LEFT", count * (size + BUTTON_GAP), 0)
    frame:SetSize((count + 1) * (size + BUTTON_GAP), size)
end

function Look.Trinkets(frame, slots, size, gap)
    frame:SetSize(size * 2 + gap, size)
    for i, button in ipairs(slots) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", (i - 1) * (size + gap), 0)
        button.icon:SetTexture(GetInventoryItemTexture("player", TRINKET_SLOTS[i]) or EMPTY_ICON)
    end
end

local function Layout()
    if not bar then return end
    local size = S.Get("gearBarSize")
    local sets = Sets()
    for i, set in ipairs(sets) do
        local btn = buttons[i] or NewButton()
        buttons[i] = btn
        btn.set = set
        Look.SetButton(btn, set, i, size)
    end
    for i = #sets + 1, #buttons do buttons[i]:Hide() end
    Look.Fit(bar, addButton, #sets, size)
end

local function BuildBar()
    bar = CreateFrame("Frame", "NaowhForeverGearBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    buttons = {}
    addButton = ns.Button(bar, "+", 32, 32, ns.NewGearSet)
    ns.Tooltip(addButton, "New Gear Set", "Saves what you are wearing now as a new set.")
    bar.mover = ns.UI.AttachMover(bar, "Gear Sets", function(pos) S.Set("gearPos", pos) end, "Gear & Trinkets/Settings",
        "Gear & Trinkets/Settings:gearBar")
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
--  Wiring
-------------------------------------------------------------------------------
-- A set swap fires PLAYER_EQUIPMENT_CHANGED once per slot; one redraw covers the burst.
local layoutQueued
local function LayoutSoon()
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        Layout()
    end)
end

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
    LayoutSoon()
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
    bar:SetShown(S.Get("gearBarVisible") == true)
    bar.mover:SetShown(unlocked == true)
    AutoSwap()
end

hooksecurefunc(S, "Set", function(key)
    if key:find("^gear") and key ~= "gearPos" and key ~= "gearWindowAlpha" then Apply() end
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


-------------------------------------------------------------------------------
-- Two independent trinket slots. Equipment changes require an out-of-combat click.
-------------------------------------------------------------------------------
do
    local trinkets, picker, moving
    local function ClosePicker()
        if picker then picker:Hide() end
    end
    local function Choose(anchor, inventorySlot)
        if InCombatLockdown() then return end
        ClosePicker()
        if not picker then
            picker = CreateFrame("Frame", nil, UIParent)
            picker:SetFrameStrata("DIALOG")
            picker:SetClampedToScreen(true)
            ns.Solid(picker, "BACKGROUND", T.bg, 1):SetAllPoints()
            ns.Border(picker)
            picker.buttons = {}
            picker.close = ns.Button(picker, "Close", 80, 22, ClosePicker)
            picker.close:SetPoint("BOTTOM", 0, 5)
        end
        local items, seen = {}, {}
        for bag = 0, NUM_BAG_SLOTS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local id = C_Container.GetContainerItemID(bag, slot)
                if id and not seen[id] then
                    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
                    if equipLoc == "INVTYPE_TRINKET" then
                        seen[id] = true
                        items[#items + 1] = id
                    end
                end
            end
        end
        if #items == 0 then ns.Print("No spare trinkets in your bags.") return end
        for i, id in ipairs(items) do
            local button = picker.buttons[i]
            if not button then
                button = CreateFrame("Button", nil, picker)
                button:SetSize(36, 36)
                button.icon = button:CreateTexture(nil, "ARTWORK")
                button.icon:SetAllPoints()
                ns.Border(button, { r = 0, g = 0, b = 0 })
                button:SetScript("OnClick", function(self)
                    if InCombatLockdown() then return end
                    -- Re-check the bags: they may have changed since the chooser opened.
                    for bag = 0, NUM_BAG_SLOTS do
                        for slot = 1, C_Container.GetContainerNumSlots(bag) do
                            if C_Container.GetContainerItemID(bag, slot) == self.itemID then
                                C_Item.EquipItemByName(self.itemID, self.inventorySlot)
                                ClosePicker()
                                return
                            end
                        end
                    end
                    ClosePicker()
                end)
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
                picker.buttons[i] = button
            end
            button.itemID, button.inventorySlot = id, inventorySlot
            button.icon:SetTexture(C_Item.GetItemIconByID(id))
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 6 + ((i - 1) % 6) * 40, -6 - math.floor((i - 1) / 6) * 40)
            button:Show()
        end
        for i = #items + 1, #picker.buttons do picker.buttons[i]:Hide() end
        picker:SetSize(math.min(#items, 6) * 40 + 8, math.ceil(#items / 6) * 40 + 34)
        picker:ClearAllPoints()
        picker:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 5)
        picker:Show()
    end
    local function ApplyTrinkets()
        if InCombatLockdown() then return end
        ClosePicker()
        local on = S.Get("gearSets") and S.Get("trinketBar")
        if not on then
            if trinkets then trinkets:Hide() end
            return
        end
        if not trinkets then
            trinkets = CreateFrame("Frame", "NaowhForeverTrinkets", UIParent)
            trinkets:SetMovable(true)
            trinkets:SetClampedToScreen(true)
            trinkets.buttons = {}
            for i = 1, 2 do
                local slot = i + 12
                local button = CreateFrame("Button", nil, trinkets, "SecureActionButtonTemplate")
                button:RegisterForClicks("AnyUp", "AnyDown")
                button:SetAttribute("item1", tostring(slot))
                button.icon = button:CreateTexture(nil, "ARTWORK")
                ns.PixelInset(button.icon, 1)
                ns.Border(button, { r = 0, g = 0, b = 0 })
                button:SetScript("PostClick", function(self, mouse, down)
                    if mouse == "RightButton" and not down then Choose(self, slot) end
                end)
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if GetInventoryItemID("player", slot) then
                        GameTooltip:SetInventoryItem("player", slot)
                    else
                        GameTooltip:SetText("Trinket " .. i .. " - Empty")
                    end
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
                trinkets.buttons[i] = button
            end
            trinkets.mover = ns.UI.AttachMover(trinkets, "Trinkets", function(pos) S.Set("trinketPos", pos) end, "Gear & Trinkets/Settings", "Gear & Trinkets/Settings:trinketBar")
        end
        trinkets:ClearAllPoints()
        local pos = S.Get("trinketPos")
        if pos then trinkets:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        else trinkets:SetPoint("CENTER", UIParent, "CENTER", 0, -160) end
        Look.Trinkets(trinkets, trinkets.buttons, S.Get("trinketSize"), S.Get("trinketSpacing"))
        for i, button in ipairs(trinkets.buttons) do
            -- The secure item action errors on an empty slot (nil link into C_Item.IsEquippableItem).
            button:SetAttribute("type1", GetInventoryItemID("player", i + 12) and "item" or nil)
        end
        trinkets.mover:SetShown(moving == true)
        trinkets:Show()
    end
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_EQUIPMENT_CHANGED" }) do
        watcher:RegisterEvent(event)
    end
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then ClosePicker() else ApplyTrinkets() end
    end)
    hooksecurefunc(S, "Set", function(key)
        if key == "gearSets" or key:find("^trinket") and key ~= "trinketPos" then ApplyTrinkets() end
    end)
    hooksecurefunc(ns, "Apply", ApplyTrinkets)
    hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function() moving = true; ApplyTrinkets() end)
    hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function() moving = false; ApplyTrinkets() end)
end

-------------------------------------------------------------------------------
--  Settings page
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local GEAR_OFF = "Turn on Gear & Trinkets"
local PREVIEW_NOTE_GAP = 10
local NO_SETS = "No gear sets yet: + saves what you wear as one."
local PREVIEW_STATE = { { key = "bar", label = "Bar" } }

local function GearOn() return S.Get("gearSets") == true end

local function PreviewButton(parent)
    local btn = CreateFrame("Frame", nil, parent)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(btn.icon, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.border = ns.Border(btn, { r = 0, g = 0, b = 0 })
    return btn
end

local function NewBarPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.row = CreateFrame("Frame", nil, preview)
    preview.row:SetPoint("CENTER")
    preview.buttons = {}
    local add = CreateFrame("Frame", nil, preview.row)
    ns.Solid(add, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(add, { r = 0, g = 0, b = 0 })
    add.text = ns.Font(add, 14, nil, T.fg)
    add.text:SetPoint("CENTER")
    add.text:SetText("+")
    preview.add = add
    preview.note = ns.Font(preview, 12, nil, T.muted)
    preview.note:SetPoint("TOP", preview.row, "BOTTOM", 0, -PREVIEW_NOTE_GAP)
    preview.note:SetText(NO_SETS)
    return preview
end

local function PaintBarPreview(preview)
    local size = S.Get("gearBarSize")
    local sets = Sets()
    for i, set in ipairs(sets) do
        local btn = preview.buttons[i] or PreviewButton(preview.row)
        preview.buttons[i] = btn
        Look.SetButton(btn, set, i, size)
    end
    for i = #sets + 1, #preview.buttons do preview.buttons[i]:Hide() end
    Look.Fit(preview.row, preview.add, #sets, size)
    preview.note:SetShown(#sets == 0)
end

local function NewTrinketPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.row = CreateFrame("Frame", nil, preview)
    preview.row:SetPoint("CENTER")
    preview.slots = { PreviewButton(preview.row), PreviewButton(preview.row) }
    return preview
end

local function PaintTrinketPreview(preview)
    Look.Trinkets(preview.row, preview.slots, S.Get("trinketSize"), S.Get("trinketSpacing"))
end

local function SetChoices()
    local values, order = { [""] = "None" }, { "" }
    for _, set in ipairs(Sets()) do
        values[set.name] = set.name
        order[#order + 1] = set.name
    end
    return values, order
end

local function Headline()
    local sets = Sets()
    if #sets == 0 then return "No gear sets yet" end
    for _, set in ipairs(sets) do
        if set.equipped then
            return ("%d gear %s, wearing %s"):format(#sets, #sets == 1 and "set" or "sets", ns.Color("accentSoft", set.name))
        end
    end
    return ("%d gear %s"):format(#sets, #sets == 1 and "set" or "sets")
end

local function Detail()
    return "The same sets as the character sheet's: equip, save, rename or delete them in the Gear Sets window."
end

local function SwapSummary(store)
    local mounted, resting = store.Get("gearMounted"), store.Get("gearResting")
    if mounted ~= "" and resting ~= "" then return mounted .. " mounted, " .. resting .. " resting" end
    if mounted ~= "" then return mounted .. " while mounted" end
    if resting ~= "" then return resting .. " while resting" end
    return "None"
end

local function SizeSummary(key)
    return function(store) return store.Get(key) .. " px" end
end

local function WindowSummary(store)
    return ("%d%% opacity"):format(math.floor((store.Get("gearWindowAlpha") or 1) * 100 + 0.5))
end

local page = Settings.Page("Gear & Trinkets/Settings", S)

page:Window({
    text = "Open Gear Sets",
    open = function() ns.OpenGearSetsWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "gearBar", name = "Gear Set Bar", order = 10, switch = "gearBarVisible",
    help = "A button per set: click to equip, Shift-click to save what you wear into it, Ctrl-click to rename "
        .. "it, right-click to change its icon, and + to save a new one. The set you wear is outlined. Move it "
        .. "in Move Elements.",
    summary = SizeSummary("gearBarSize"),
    studio = { height = 100, states = PREVIEW_STATE, new = NewBarPreview, paint = PaintBarPreview },
    rows = {
        { key = "gearBarSize", label = "Button Size", slider = { 20, 48, 1 }, unit = " px", needs = GearOn,
          why = GEAR_OFF, help = "How big each set's button is." },
    },
})

page:Card({
    id = "autoSwap", name = "Automatic Swaps", order = 20,
    help = "A set that goes on by itself while you ride or rest, and the set you had on goes back afterwards.",
    summary = SwapSummary,
    rows = {
        { key = "gearMounted", label = "Wear While Mounted", choice = SetChoices, needs = GearOn, why = GEAR_OFF,
          help = "Put on while you ride, and the set you had on goes back when you dismount." },
        { key = "gearResting", label = "Wear While Resting", choice = SetChoices, needs = GearOn, why = GEAR_OFF,
          help = "Put on in cities and inns, and taken off again when you leave." },
    },
})

page:Card({
    id = "trinketBar", name = "Trinket Bar", order = 30, switch = "trinketBar",
    help = "Your two trinket slots, movable: left-click to use one, right-click to equip a trinket from your "
        .. "bags outside combat. Move it with Move Elements.",
    summary = SizeSummary("trinketSize"),
    studio = { height = 110, states = PREVIEW_STATE, new = NewTrinketPreview, paint = PaintTrinketPreview },
    rows = {
        { key = "trinketSize", label = "Icon Size", slider = { 20, 70, 1 }, unit = " px", needs = GearOn,
          why = GEAR_OFF, help = "How big each trinket is." },
        { key = "trinketSpacing", label = "Spacing", slider = { 0, 30, 1 }, unit = " px", needs = GearOn,
          why = GEAR_OFF, help = "The gap between the two." },
    },
})

page:Card({
    id = "window", name = "Window", order = 40,
    help = "The Gear Sets window, with every set and what you can do with it.",
    summary = WindowSummary,
    rows = {
        { key = "gearWindowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the Gear Sets window is, in percent. Also on its title bar." },
    },
})
