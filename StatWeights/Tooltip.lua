-------------------------------------------------------------------------------
--  StatWeights/Tooltip.lua -- while the module is on, a line on the tooltip of gear that is an
--  upgrade for your spec: "(green arrow) +9% upgrade . Fire" (Shared/Parts.lua's UpgradeLine).
--  Nothing on gear that is not one, that you wear, or that your class does not wear (SW.BestGain,
--  which the bags' arrow reads too). Installed the first time the module is turned on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local SW = ns.StatWeights
local S = SW.Settings
local Items = ns.Shared.Items
local UpgradeLine = ns.Shared.Parts.UpgradeLine

local function OnItem(tooltip, data)
    if not SW.On() or tooltip:IsForbidden() then return end
    local id = data and data.id
    if not id or issecretvalue(id) then return end
    local key = Items.SlotsFor(id) and SW.ActiveSpec()
    local weights = key and SW.For(key)
    if not weights then return end
    -- Its link, for its own stats where it has random ones. The comparison tooltips beside it
    -- (what you wear) have no GetItem on this client: those go by the ID.
    local link
    if tooltip.GetItem then
        link = select(2, tooltip:GetItem())
        if link and issecretvalue(link) then link = nil end
    end
    local best = SW.BestGain(id, link, weights, SW.Power(weights))
    if best then tooltip:AddLine(UpgradeLine(best, SW.Spec(key).name)) end
end

local installed = false

local function Install()
    if installed or not SW.On() then return end
    installed = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
end

S.OnChange(function(key)
    if key == "enabled" then Install() end
end)
hooksecurefunc(ns, "Apply", Install)
