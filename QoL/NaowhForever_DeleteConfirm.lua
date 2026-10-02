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
-- applies once the box is filled in and hidden.
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
    local typed = editBox:IsShown()
    if typed then
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
        editBox:Hide()
    end

    local kind, _, link = GetCursorInfo()
    local text = _G[name .. "Text"]
    if kind == "item" and link then
        text:SetText(StripInstruction(text:GetText() or "") .. "\n\n" .. link)
        -- The hidden box leaves room for the link; the plain dialog needs the space added.
        if not typed then dialog:SetHeight(dialog:GetHeight() + 32) end
    end
end)
