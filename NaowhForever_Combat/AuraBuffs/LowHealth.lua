-- LowHealth.lua: the Low Health rules: the healing item to offer, and the curve that shows it below the threshold.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings

local PERCENT = A.C.PERCENT
local STEP_EDGE = 0.001

local Low = {}
A.LowHealth = Low

local function FirstCarried(list)
    for _, id in ipairs(list) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

function Low.On()
    return S.Get("enabled") and S.Get("lowHealth")
end

function Low.Below()
    return S.Get("lowHealthBelow") / PERCENT
end

function Low.PickItem()
    local mode = S.Get("lowHealthItem")
    if mode == "stone" then return FirstCarried(ns.HEALTHSTONES) end
    if mode == "potion" then return FirstCarried(ns.HEALING_POTIONS) end
    return FirstCarried(ns.HEALTHSTONES) or FirstCarried(ns.HEALING_POTIONS)
end

function Low.Curve(curve)
    local below = Low.Below()
    curve = curve or C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:ClearPoints()
    curve:AddPoint(0, 1)
    curve:AddPoint(below - STEP_EDGE, 1)
    curve:AddPoint(below, 0)
    curve:AddPoint(1, 0)
    return curve
end
