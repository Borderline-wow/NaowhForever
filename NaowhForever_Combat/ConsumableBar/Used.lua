-- Used.lua: Hide After Use: whether an item's own cooldown or its effect is on you, and when to look again.
local ns = _G.NaowhForever

local GetTime = GetTime
local GetItemCooldown = C_Container.GetItemCooldown
local GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID

local CB = ns.ConsumableBar
local C = CB.C
local Secret = CB.Secret

local MS_PER_SECOND = 1000
local CAST_SLOP = 1

local wakeAt
local casts = {}

function CB.NoteCast(spellID)
    if spellID == nil or Secret(spellID) then return end
    casts[spellID] = GetTime()
end

local function Soon(seconds)
    if seconds and seconds > 0 and (not wakeAt or seconds < wakeAt) then wakeAt = seconds end
end

local function CooldownLeft(itemID)
    local start, duration, enable = GetItemCooldown(itemID)
    if Secret(start) or Secret(duration) or Secret(enable) then return nil end
    local cast = casts[CB.ItemSpell(itemID) or 0]
    if not (cast and cast >= start - CAST_SLOP) then return nil end
    if enable == 1 and duration and duration > C.GCD then
        local left = start + duration - GetTime()
        if left > 0 then return left end
    end
end

local function AuraLeft(spell)
    local aura = GetPlayerAuraBySpellID(spell)
    if not aura then return nil end
    local expires = aura.expirationTime
    if Secret(expires) then return nil, true end
    if not expires or expires == 0 then return math.huge end
    return expires - GetTime()
end

local function BuffLeft(itemID)
    if C_Secrets.ShouldAurasBeSecret() then return nil, true end
    local spell = CB.ItemSpell(itemID)
    if not spell then return nil end
    local left, unknown = AuraLeft(spell)
    if not left and not unknown and ns.FOOD_SPELLS[spell] then
        for _, fed in ipairs(ns.WELL_FED) do
            left, unknown = AuraLeft(fed)
            if left or unknown then break end
        end
    end
    return left, unknown
end

local function EffectLeft(itemID, flags)
    local track = flags.track or "buff"
    if track == "buff" then return BuffLeft(itemID) end
    local hasMain, mainMs, _, _, hasOff, offMs = GetWeaponEnchantInfo()
    local has, ms = hasMain, mainMs
    if track == "offhand" then has, ms = hasOff, offMs end
    if Secret(has) or Secret(ms) then return nil, true end
    if not has then return nil end
    return (ms or 0) / MS_PER_SECOND
end

function CB.Spent(button)
    local id = button.itemID
    if not id then return false end
    local flags = CB.Flags(button.entry)
    local left = CooldownLeft(id)
    local hidden = left ~= nil
    Soon(left)
    local effect, unknown = EffectLeft(id, flags)
    if unknown then
        hidden = hidden or button.spent == true
    elseif effect then
        local lead = flags.early and (flags.earlySeconds or C.EARLY_DEFAULT) or 0
        if effect > lead then
            hidden = true
            if effect ~= math.huge then Soon(effect - lead) end
        end
    end
    button.spent = hidden
    return hidden
end

function CB.TakeWake()
    local at = wakeAt
    wakeAt = nil
    return at
end
