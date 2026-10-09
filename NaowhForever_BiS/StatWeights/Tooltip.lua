-- Tooltip.lua: the upgrade line on gear tooltips, while Stat Weights is on.
local ns = _G.NaowhForever

local SW = ns.StatWeights
local S = SW.Settings
local Items = ns.Shared.Items
local UpgradeLine = ns.Shared.Parts.UpgradeLine

local installed = false

local function TooltipLink(tooltip)
    if not tooltip.GetItem then return nil end
    local link = select(2, tooltip:GetItem())
    if link and issecretvalue(link) then return nil end
    return link
end

local function OnItem(tooltip, data)
    if not SW.On() or tooltip:IsForbidden() then return end
    local id = data and data.id
    if not id or issecretvalue(id) then return end
    local key = Items.SlotsFor(id) and SW.ActiveSpec()
    local weights = key and SW.For(key)
    if not weights then return end
    local best = SW.BestGain(id, TooltipLink(tooltip), weights, SW.Power(weights))
    if best then tooltip:AddLine(UpgradeLine(best, SW.Spec(key).name)) end
end

local function Install()
    if installed or not SW.On() then return end
    installed = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
end

local function OnSetting(key)
    if key == "enabled" then Install() end
end

S.OnChange(OnSetting)
hooksecurefunc(ns, "Apply", Install)
