-------------------------------------------------------------------------------
--  NaowhForever_DeleteConfirm.lua -- the QoL delete confirmation auto-fill: types DELETE for
--  you and names the item in the dialog as a link.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local DIALOGS = { DELETE_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true }

local patched

-- DELETE_GOOD_ITEM's second paragraph is the "type DELETE" instruction, which no longer
-- applies once the box is filled in.
local function StripInstruction(text)
    local cut = DELETE_GOOD_ITEM:find("\n")
    if not cut then return text end
    local instruction = strtrim((DELETE_GOOD_ITEM:sub(cut):gsub("%%s", "")))
    if instruction == "" then return text end
    local at = text:find(instruction, 1, true)
    return at and strtrim(text:sub(1, at - 1)) or text
end

local function LinkEnter(self, link)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

hooksecurefunc("StaticPopup_Show", function(which)
    if not (DIALOGS[which] and S.Get("enabled") and S.Get("deleteConfirm")) then return end
    local dialog = StaticPopup_FindVisible(which)
    if not dialog then return end
    if not patched then
        for name in pairs(DIALOGS) do
            StaticPopupDialogs[name].OnHyperlinkEnter = LinkEnter
            StaticPopupDialogs[name].OnHyperlinkLeave = GameTooltip_Hide
        end
        patched = true
    end

    local name = dialog:GetName()
    local editBox = _G[name .. "EditBox"]
    if editBox:IsShown() then
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
        -- Filling the box from code left Yes greyed on Forever; the dialog's own check, run
        -- here, enables it when the text matches.
        local check = StaticPopupDialogs[which].EditBoxOnTextChanged
        if check then check(editBox, dialog.data) end
    end

    local kind, _, link = GetCursorInfo()
    local text = _G[name .. "Text"]
    if kind == "item" and link then
        text:SetText(StripInstruction(text:GetText() or "") .. "\n\n" .. link)
        -- The dialog only sizes itself to its text on show, and the box sits under the text.
        dialog:Resize()
    end
end)

ns.Shared.Settings.Page("QoL/Loot & Items", S):Card({
    id = "looting", name = "Looting", order = 10,
    help = "Fewer clicks around loot and items: the delete confirmation filled in, auto loot that "
        .. "keeps the loot window, and enchants that replace the old one without asking.",
    rows = {
        { key = "deleteConfirm", label = "Type DELETE For You", toggle = true,
          help = "Types DELETE into the confirmation box for you, and names the item in the dialog as a "
              .. "link you can hover for its tooltip." },
        { key = "fastLoot", label = "Faster Auto Loot", toggle = true,
          help = "Loots automatically without hiding the loot window. Hold Shift to loot manually." },
        { key = "enchantReplace", label = "Auto-Replace Enchants", toggle = true,
          help = "Says yes when an enchant would replace the one already on the item, instead of asking. "
              .. "Hold Shift while applying it to be asked." },
    },
})
