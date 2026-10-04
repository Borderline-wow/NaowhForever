-------------------------------------------------------------------------------
--  Bags.lua -- the item buttons in your bags, for the marks modules paint on them (the BiS
--  List's Bag Marks, QoL's Scrap Marker): the game's bag frames, with each module's painter
--  run after a frame updates its items, and EllesmereUI's bags, through the hook it offers
--  other addons. Nothing is hooked until a module first asks.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Shared = ns.Shared

local Bags = {}
Shared.Bags = Bags

local ELLESMERE_WINDOWS = { "EUI_Bags", "EUI_BagsReagent" }

local frames = {}
local painters = {}

local function Painted(frame)
    for i = 1, #painters do painters[i](frame) end
end

local function HookGameBags()
    local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    for i = 1, list and #list or 0 do frames[#frames + 1] = list[i] end
    frames[#frames + 1] = ContainerFrameCombinedBags
    for _, frame in ipairs(frames) do
        if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", Painted) end
    end
end

function Bags.OnGameUpdate(painter)
    if #painters == 0 then HookGameBags() end
    painters[#painters + 1] = painter
end

function Bags.RepaintGame(painter)
    for _, frame in ipairs(frames) do
        if frame:IsShown() then painter(frame) end
    end
end

function Bags.Ellesmere()
    local bags = _G.EUI_Bags
    return C_AddOns.IsAddOnLoaded("EllesmereUIBags") and bags and bags.RegisterItemOverlayIcon and bags or nil
end

function Bags.RefreshEllesmere()
    for _, name in ipairs(ELLESMERE_WINDOWS) do
        local frame = _G[name]
        if frame and frame.RefreshInventory and frame:IsVisible() then frame:RefreshInventory() end
    end
end
