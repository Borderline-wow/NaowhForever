-------------------------------------------------------------------------------
--  NaowhForever_BuffReminders.lua -- the AuraBuffs Buffs & Consumables reminders:
--  a row of icons for missing food, flask and elixir buffs, scrolls in your bags, and
--  class buffs missing in your group.
--
--  Out of combat only. The client withdraws aura access in combat and at boss pulls
--  before InCombatLockdown() turns true, so every read is gated on
--  C_Secrets.ShouldAurasBeSecret() and the icons keep what they last showed until it ends.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.AuraBuffSettings
local D = ns.BuffReminderData

local GAP = 4
local ELIXIR_ICON = 13454   -- Greater Arcane Elixir, for "no elixir at all"
local KEYS = {
    enabled = true, food = true, elixirs = true, flasks = true, consumablesWhere = true,
    consumablesMinutes = true, onlyIfCarried = true, hideResting = true, scrolls = true,
    scrollsSkipActive = true, raidBuffs = true, raidBuffsOwn = true, iconSize = true,
}

local frame, unlocked, carriedFood
local cells = {}
local pending      -- a refresh is queued
local wakeGen = 0  -- invalidates an older "buff drops under the warning time" timer
local wakeAt

local function On()
    return S.Get("enabled") and (S.Get("food") or S.Get("flasks") or S.Get("elixirs")
        or S.Get("scrolls") or S.Get("raidBuffs"))
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- The unit's helpful auras by spell ID; nil when the client hands them over secret.
local function Buffs(unit)
    local buffs = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        if Secret(aura.spellId) then return nil end
        buffs[aura.spellId] = aura
    end
    return buffs
end

local function Find(buffs, ids)
    for _, id in ipairs(ids) do
        if buffs[id] then return buffs[id] end
    end
end

local function FirstCarried(items)
    for _, id in ipairs(items) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

-- Seconds left on the aura, nil when it does not run out or cannot be read.
local function Left(aura)
    local expiry = aura.expirationTime
    if Secret(expiry) or not expiry or expiry == 0 then return nil end
    return expiry - GetTime()
end

local function ScanFood()
    carriedFood = nil
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemID(bag, slot)
            if item and D.FOOD_SPELLS[select(2, C_Item.GetItemSpell(item))] then
                carriedFood = item
                return
            end
        end
    end
end

local function ConsumablesHere()
    if S.Get("hideResting") and IsResting() then return false end
    local where = S.Get("consumablesWhere")
    if where == "always" then return true end
    local _, kind = IsInInstance()
    return kind == "raid" or (where == "instance" and kind == "party")
end

-- Nothing fires as a buff runs down, so the earliest one to cross the warning time is timed.
local function Wake(seconds)
    if not wakeAt or seconds < wakeAt then wakeAt = seconds end
end

-- Adds a reminder unless one of `auras` is up with more than the warning time left.
local function Consumable(list, buffs, auras, item, icon)
    local aura = Find(buffs, auras)
    local left = aura and Left(aura)
    local warn = S.Get("consumablesMinutes") * 60
    if aura and not (left and left <= warn) then
        if left then Wake(left - warn) end
        return
    end
    if not item and S.Get("onlyIfCarried") then return end
    list[#list + 1] = { icon = item and C_Item.GetItemIconByID(item) or icon, aura = aura }
end

local function Consumables(list, buffs)
    if S.Get("food") then
        Consumable(list, buffs, D.WELL_FED, carriedFood, C_Spell.GetSpellTexture(D.WELL_FED[1]))
    end
    if S.Get("flasks") then
        Consumable(list, buffs, D.FLASKS.auras, FirstCarried(D.FLASKS.items),
            C_Item.GetItemIconByID(D.FLASKS.items[1]))
    end
    if S.Get("elixirs") then
        local carried, up
        for _, group in ipairs(D.ELIXIRS) do
            local item = FirstCarried(group.items)
            if item then
                carried = true
                Consumable(list, buffs, group.auras, item)
            elseif Find(buffs, group.auras) then
                up = true
            end
        end
        if not (carried or up or S.Get("onlyIfCarried")) then
            list[#list + 1] = { icon = C_Item.GetItemIconByID(ELIXIR_ICON) }
        end
    end
end

local function RaidFamily(key)
    for _, family in ipairs(D.RAID) do
        if family.key == key then return family end
    end
end

-- The best rank of each scroll you carry, until you read it.
local function Scrolls(list, buffs)
    for _, group in ipairs(D.SCROLLS) do
        local item
        for i = #group.items, 1, -1 do
            if C_Item.GetItemCount(group.items[i]) > 0 then item = group.items[i] break end
        end
        local active = S.Get("scrollsSkipActive") and (Find(buffs, group.auras)
            or group.raid and Find(buffs, RaidFamily(group.raid).spells))
        if item and not active then
            local count = C_Item.GetItemCount(item)
            list[#list + 1] = { icon = C_Item.GetItemIconByID(item), count = count > 1 and count }
        end
    end
end

local function Knows(spells)
    for _, id in ipairs(spells) do
        if C_SpellBook.IsSpellKnown(id) then return true end
    end
end

local function GroupUnits()
    local units = {}
    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, n - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Each class buff someone in the group could cast, with how many in range are missing it.
local function RaidBuffs(list, playerBuffs)
    local members, classes = {}, {}
    for _, unit in ipairs(GroupUnits()) do
        local _, class = UnitClass(unit)
        if class and not Secret(class) then
            classes[class] = true
            if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit) then
                local buffs = UnitIsUnit(unit, "player") and playerBuffs or Buffs(unit)
                if buffs then members[#members + 1] = { class = class, buffs = buffs } end
            end
        end
    end
    local own = S.Get("raidBuffsOwn")
    for _, family in ipairs(D.RAID) do
        local castable = Knows(family.spells)
        if castable or not (own or family.talent) and classes[family.class] then
            local missing = 0
            for _, member in ipairs(members) do
                if not (family.skip and family.skip[member.class])
                    and not Find(member.buffs, family.spells) then
                    missing = missing + 1
                end
            end
            if missing > 0 then
                list[#list + 1] = { icon = C_Spell.GetSpellTexture(family.spells[1]),
                    count = #members > 1 and missing }
            end
        end
    end
end

-- The reminders to show now, in order; nil while auras cannot be read.
local function Collect()
    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then return nil end
    local buffs = Buffs("player")
    if not buffs then return nil end
    local list = {}
    wakeAt = nil
    if ConsumablesHere() then Consumables(list, buffs) end
    if S.Get("scrolls") then Scrolls(list, buffs) end
    if S.Get("raidBuffs") then RaidBuffs(list, buffs) end
    return list
end

local function Cell(i)
    local cell = cells[i]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, frame)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Border(cell, { r = 0, g = 0, b = 0 })
    cell.timer = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.timer:SetAllPoints()
    cell.timer:SetDrawEdge(false)
    cell.timer:SetReverse(true)
    cell.count = ns.Font(cell, 14, "OUTLINE")
    cell.count:SetPoint("BOTTOMRIGHT", -2, 2)
    cells[i] = cell
    return cell
end

local function Show(list)
    local size = S.Get("iconSize")
    for i, entry in ipairs(list) do
        local cell = Cell(i)
        cell:SetSize(size, size)
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + GAP), 0)
        cell.icon:SetTexture(entry.icon)
        cell.count:SetText(entry.count or "")
        local aura = entry.aura
        if aura and Left(aura) and not Secret(aura.duration) then
            cell.timer:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            cell.timer:Show()
        else
            cell.timer:Hide()
        end
        cell:Show()
    end
    for i = #list + 1, #cells do cells[i]:Hide() end
    frame:SetSize(math.max(#list, 1) * (size + GAP) - GAP, size)
end

local PREVIEW = {
    { spell = D.WELL_FED[1] }, { item = D.FLASKS.items[1] }, { item = ELIXIR_ICON },
    { item = D.SCROLLS[4].items[4], count = 2 }, { spell = D.RAID[1].spells[1], count = 3 },
}

local function Refresh()
    pending = nil
    if not frame then return end
    if unlocked then
        local list = {}
        for i, p in ipairs(PREVIEW) do
            list[i] = { icon = p.item and C_Item.GetItemIconByID(p.item)
                or C_Spell.GetSpellTexture(p.spell), count = p.count }
        end
        Show(list)
        return
    end
    if not On() then
        Show({})
        return
    end
    local list = Collect()
    if not list then return end
    Show(list)
    wakeGen = wakeGen + 1
    if wakeAt then
        local gen = wakeGen
        C_Timer.After(wakeAt + 0.1, function()
            if gen == wakeGen then Refresh() end
        end)
    end
end

-- Group auras change in bursts, so a refresh waits a moment and covers the lot.
local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.3, Refresh)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    -- The unit arrives secret while auras are restricted; PLAYER_REGEN_ENABLED catches up.
    if event == "UNIT_AURA" and (Secret(unit)
        or not (unit == "player" or unit:find("^party%d") or unit:find("^raid%d"))) then
        return
    end
    if event == "BAG_UPDATE_DELAYED" then ScanFood() end
    Queue()
end)

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverBuffReminders", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.mover = ns.UI.AttachMover(frame, "Buff Reminders", function(pos) S.Set("buffsPos", pos) end)
end

local function Place()
    local pos = S.Get("buffsPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end
end

local function Apply()
    events:UnregisterAllEvents()
    wakeGen = wakeGen + 1
    if not (On() or unlocked) then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Place()
    frame.mover:SetShown(unlocked == true)
    frame:Show()
    if On() then
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
        ScanFood()
    end
    Refresh()
end

hooksecurefunc(S, "Set", function(key)
    if KEYS[key] then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
