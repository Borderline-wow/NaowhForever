-------------------------------------------------------------------------------
--  View/ItemMenu.lua -- the right-click menu on a Dungeon Journal item: put it on your BiS
--  list, make it your #1, or take it off, through the BiS List module's own functions, so
--  the list, its page and its tooltips all agree.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local Loot = J.Loot

local GetItemInfo = C_Item.GetItemInfo

-- onChange runs after the list changed, so the caller can redraw.
---@param owner Frame
---@param itemID number
---@param onChange? fun()
function J.View.ItemMenu(owner, itemID, onChange)
    local function Then(change)
        change(itemID)
        if onChange then onChange() end
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle((GetItemInfo(itemID)) or "BiS List")
        if not Loot.BisOn() then
            root:CreateButton("Turn on BiS List", function()
                ns.QoLSettings.Set("bis", true)
                if onChange then onChange() end
            end)
            return
        end
        local rank = Loot.Rank(itemID)
        if not rank then
            root:CreateButton("Add to BiS List", function() Then(ns.AddBisItem) end)
            return
        end
        if rank > 1 then root:CreateButton("Make it #1", function() Then(ns.PromoteBisItem) end) end
        root:CreateButton("Remove from BiS List", function() Then(ns.RemoveBisItem) end)
    end)
end
