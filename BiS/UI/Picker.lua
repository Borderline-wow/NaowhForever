-------------------------------------------------------------------------------
--  UI/Picker.lua -- a slot's picker, in a side panel beside the window it was opened from:
--  your picks, the ranking and the dungeon drops (View/View.lua), and along the bottom a
--  box to add any item by its ID, link or Wowhead URL. Made the first time it opens.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local L = B.Lists
local Shared = ns.Shared
local Items, Parts = Shared.Items, Shared.Parts

local St = B.Style
local PANEL_PAD, PANEL_W, PICKER_BOX_W, PLACE_DOT = St.PANEL_PAD, St.PANEL_W, St.PICKER_BOX_W, St.PLACE_DOT

local panel, box

local function Opacity()
    return B.Settings.Get("bisWindowAlpha") or 1
end

local function Title(slot)
    local spec = L.CurrentSpec()
    return ns.L(Items.SLOT_NAME[slot]) .. (spec and ns.Color("muted", PLACE_DOT .. spec.name) or "")
end

local function AddFromBox()
    local slot = panel.view.slot
    local id = Items.IDFrom(box:GetText())
    if not (id and C_Item.GetItemInfoInstant(id)) then
        return ns.Print("There is no item with that ID.")
    end
    if not Items.Fits(id, slot) then
        return ns.Print(("%s does not go in the %s slot."):format(Items.Name(id), ns.L(Items.SLOT_NAME[slot])))
    end
    box:SetText("")
    box:ClearFocus()
    ns.AddBisPick(slot, id)
end

local function Build()
    panel = Parts.SidePanel({ { "Add", AddFromBox } }, B.View.New, Opacity)
    local add = panel.buttons.Add
    add:SetWidth(PANEL_W - PANEL_PAD * 3 - PICKER_BOX_W)
    box = ns.NewEditBox(panel)
    box:SetSize(PICKER_BOX_W, 24)
    box:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD)
    add:ClearAllPoints()
    add:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_PAD)
    box.hint = ns.Font(box, 12, nil, ns.THEME.muted)
    box.hint:SetPoint("LEFT", 7, 0)
    box.hint:SetText("Item ID, link or Wowhead URL")
    local function Hint(self) self.hint:SetShown(self:GetText() == "" and not self:HasFocus()) end
    box:SetScript("OnTextChanged", Hint)
    box:SetScript("OnEditFocusGained", Hint)
    box:SetScript("OnEditFocusLost", Hint)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", AddFromBox)
end

-- Opens the slot's picker beside the window holding from.
function B.OpenPicker(slot, from)
    if not panel then Build() end
    panel.title:SetText(Title(slot))
    box:SetText("")
    Parts.ShowBeside(panel, from)
    panel.view:DrawPicker(slot)
end

-- Another spec's ranking, after a switch.
B.OnListChange(function()
    if panel and panel:IsShown() then panel.title:SetText(Title(panel.view.slot)) end
end)
