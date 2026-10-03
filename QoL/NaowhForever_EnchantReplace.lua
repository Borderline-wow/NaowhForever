-------------------------------------------------------------------------------
--  NaowhForever_EnchantReplace.lua -- the QoL enchant replace skip: says yes when an enchant
--  would replace the one already on the item. Hold Shift to be asked as before.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

-- After the popup is up, so the answer cannot come before the question; the same call its Yes
-- button makes.
hooksecurefunc("StaticPopup_Show", function(which)
    if which ~= "REPLACE_ENCHANT" or not (S.Get("enabled") and S.Get("enchantReplace")) or IsShiftKeyDown() then
        return
    end
    C_Item.ReplaceEnchant()
    StaticPopup_Hide("REPLACE_ENCHANT")
end)
