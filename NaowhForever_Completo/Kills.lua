-- Kills.lua: counts the rares this character kills, and what each one dropped for it.
local ns = _G.NaowhForever

local Completo = ns.Completo
local S = Completo.Settings
local R = Completo.Rares

local SOURCE_STRIDE = 2

local counted = {}
local watching
local events = CreateFrame("Frame")

local function Count(guid)
    local npc = R.NpcOf(guid)
    if not npc or not R.Known(npc) or counted[guid] then return end
    counted[guid] = true
    local record = R.Record(npc)
    if record and record.guid == guid then return end
    R.AddKill(npc, guid)
end

local function StopWatching()
    watching = nil
    events:UnregisterEvent("UNIT_HEALTH")
end

local function CheckTarget()
    local guid = UnitGUID("target")
    if not R.Readable(guid) or guid ~= watching then return end
    local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
    if not R.Readable(dead, denied) or not dead then return end
    if not denied then Count(guid) end
    StopWatching()
end

local function Retarget()
    StopWatching()
    local guid = UnitGUID("target")
    local npc = R.NpcOf(guid)
    if not npc or not R.Known(npc) or counted[guid] then return end
    local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
    if not R.Readable(dead, denied) then return end
    if dead then
        if not denied then Count(guid) end
        return
    end
    watching = guid
    events:RegisterUnitEvent("UNIT_HEALTH", "target")
end

local function ItemOf(link)
    if type(link) ~= "string" or not R.Readable(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function CountSources(itemID, ...)
    for i = 1, select("#", ...), SOURCE_STRIDE do
        local guid = (select(i, ...))
        if R.Readable(guid) then
            Count(guid)
            local npc = R.NpcOf(guid)
            if itemID and npc and R.Known(npc) then R.AddDrop(npc, itemID) end
        end
    end
end

local function Looted()
    for slot = 1, GetNumLootItems() do
        CountSources(ItemOf(GetLootSlotLink(slot)), GetLootSourceInfo(slot))
    end
end

local function OnEvent(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        Retarget()
    elseif event == "UNIT_HEALTH" then
        CheckTarget()
    elseif event == "LOOT_READY" then
        Looted()
    end
end

local function Apply()
    events:UnregisterAllEvents()
    watching = nil
    if not S.Get("enabled") then return end
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("LOOT_READY")
end

local function OnSet(key)
    if key == "enabled" then Apply() end
end

local function OnLogin(self)
    self:UnregisterAllEvents()
    Apply()
end

events:SetScript("OnEvent", OnEvent)
hooksecurefunc(S, "Set", OnSet)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", OnLogin)
