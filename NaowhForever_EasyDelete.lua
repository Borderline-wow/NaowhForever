-------------------------------------------------------------------------------
--  NaowhForever_EasyDelete.lua -- Auto-Fill Delete Confirmation: types DELETE into the box
--  Blizzard asks for before destroying a rare or better item.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local TYPED = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

-- Only the text box is filled. Blizzard's own text handler enables Yes, and the delete
-- itself still comes from the player's click or Enter.
hooksecurefunc("StaticPopup_Show", function(which)
    if not (TYPED[which] and S.Get("enabled") and S.Get("deleteConfirm")) then return end
    local dialog = StaticPopup_FindVisible(which)
    if dialog then dialog:GetEditBox():SetText(DELETE_ITEM_CONFIRM_STRING) end
end)
