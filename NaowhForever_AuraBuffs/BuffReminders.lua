-- BuffReminders.lua: the Buffs & Consumables rules: which food, flask, elixir and class buffs are missing.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings
local D = ns.BuffReminderData

local MAX_AURAS = 40
local SECONDS = A.C.SECONDS
local PARTY_UNITS = MAX_PARTY_MEMBERS or 4
local RAID_UNITS_MAX = MAX_RAID_MEMBERS or 40
local CATEGORY_ORDER = A.CATEGORY_ORDER

local GROUP_UNIT = { player = true }
local RAID_UNITS, PARTY_UNITS_LIST = {}, {}
for i = 1, PARTY_UNITS do
    GROUP_UNIT["party" .. i] = true
    PARTY_UNITS_LIST[i] = "party" .. i
end
for i = 1, RAID_UNITS_MAX do
    GROUP_UNIT["raid" .. i] = true
    RAID_UNITS[i] = "raid" .. i
end

local buffPool, members, memberCount, classes = {}, {}, 0, {}
local itemBuffs, requested = {}, {}
local wellFedName
local wakeAt

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Buffs(unit)
    local buffs = buffPool[unit]
    if buffs then wipe(buffs) else buffs = {}; buffPool[unit] = buffs end
    for i = 1, MAX_AURAS do
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

local function WellFed(buffs)
    wellFedName = wellFedName or C_Spell.GetSpellName(D.WELL_FED[1])
    for _, aura in pairs(buffs) do
        if aura.name == wellFedName then return aura end
    end
end

local function ItemBuff(itemID)
    if not itemBuffs[itemID] then
        local _, spell = C_Item.GetItemSpell(itemID)
        if spell then
            itemBuffs[itemID] = spell
        elseif not requested[itemID] then
            requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    return itemBuffs[itemID]
end

local function FirstCarried(items)
    for _, id in ipairs(items) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

local function Left(aura)
    local expiry = aura.expirationTime
    if Secret(expiry) or not expiry or expiry == 0 then return nil end
    return expiry - GetTime()
end

local function ConsumablesHere()
    if S.Get("hideResting") and IsResting() then return false end
    local where = S.Get("consumablesWhere")
    if where == "always" then return true end
    local _, kind = IsInInstance()
    return kind == "raid" or (where == "instance" and kind == "party")
end

local function Wake(seconds)
    if not wakeAt or seconds < wakeAt then wakeAt = seconds end
end

local function Consumable(list, buffs, group, item, icon)
    local aura = Find(buffs, group.auras) or group.wellFed and WellFed(buffs)
    local left = aura and Left(aura)
    local warn = S.Get("consumablesMinutes") * SECONDS
    if aura and not (left and left <= warn) then
        if left then Wake(left - warn) end
        return
    end
    if not item and S.Get("onlyIfCarried") then return end
    list[#list + 1] = { icon = item and C_Item.GetItemIconByID(item) or icon, aura = aura }
end

local function Groups()
    local groups = {}
    for _, entry in ipairs(S.Get("consumableEntries") or {}) do
        if type(entry) == "table" and type(entry.itemID) == "number" then
            local group = groups[entry.category]
            if not group then group = { items = {}, auras = {} }; groups[entry.category] = group end
            group.items[#group.items + 1] = entry.itemID
            if type(entry.auras) == "table" then
                for _, id in ipairs(entry.auras) do group.auras[#group.auras + 1] = id end
            elseif entry.category == "food" then
                group.wellFed = true
            else
                group.auras[#group.auras + 1] = ItemBuff(entry.itemID)
            end
        end
    end
    return groups
end

local function Consumables(list, buffs)
    local groups = Groups()
    for _, category in ipairs(CATEGORY_ORDER) do
        local group = groups[category]
        if group then
            local before = #list
            Consumable(list, buffs, group, FirstCarried(group.items),
                C_Item.GetItemIconByID(group.items[1]))
            if #list > before then list[#list].items = group.items end
        end
    end
end

local function Picked(family)
    local on = S.Get("raidBuffPicks")[family.key]
    if on == nil then return family.class ~= "PALADIN" end
    return on
end

local function Knows(spells)
    for _, id in ipairs(spells) do
        if C_SpellBook.IsSpellKnown(id) then return true end
    end
end

local function AddMember(unit, playerBuffs)
    local _, class = UnitClass(unit)
    if not class or Secret(class) then return end
    classes[class] = true
    if not (UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit)) then return end
    local buffs = UnitIsUnit(unit, "player") and playerBuffs or Buffs(unit)
    if not buffs then return end
    memberCount = memberCount + 1
    local member = members[memberCount]
    if not member then member = {}; members[memberCount] = member end
    member.class, member.buffs = class, buffs
end

local function AddGroup(playerBuffs)
    memberCount = 0
    wipe(classes)
    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do AddMember(RAID_UNITS[i] or ("raid" .. i), playerBuffs) end
    else
        AddMember("player", playerBuffs)
        for i = 1, n - 1 do AddMember(PARTY_UNITS_LIST[i] or ("party" .. i), playerBuffs) end
    end
end

local function Missing(family)
    local missing = 0
    for m = 1, memberCount do
        local member = members[m]
        if not (family.skip and family.skip[member.class]) and not Find(member.buffs, family.spells) then
            missing = missing + 1
        end
    end
    return missing
end

local function RaidBuffs(list, playerBuffs)
    AddGroup(playerBuffs)
    local own = S.Get("raidBuffsOwn")
    for _, family in ipairs(D.RAID) do
        if Picked(family) and (Knows(family.spells) or not (own or family.talent) and classes[family.class]) then
            local missing = Missing(family)
            if missing > 0 then
                list[#list + 1] = { icon = C_Spell.GetSpellTexture(family.spells[1]),
                    count = memberCount > 1 and missing }
            end
        end
    end
    for m = 1, memberCount do members[m].buffs = nil end
end

local Reminders = {}
A.Buffs = Reminders

Reminders.GROUP_UNIT = GROUP_UNIT
Reminders.Left = Left
Reminders.Picked = Picked
Reminders.Secret = Secret

function Reminders.On()
    return S.Get("enabled") and (#(S.Get("consumableEntries") or {}) > 0 or S.Get("raidBuffs"))
end

function Reminders.Requested(itemID)
    return requested[itemID] == true
end

function Reminders.WakeAt()
    return wakeAt
end

function Reminders.Collect()
    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then return nil end
    local buffs = Buffs("player")
    if not buffs then return nil end
    local list = {}
    wakeAt = nil
    if ConsumablesHere() then Consumables(list, buffs) end
    if S.Get("raidBuffs") then RaidBuffs(list, buffs) end
    return list
end
