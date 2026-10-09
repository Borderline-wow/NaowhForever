-- BackupRow.lua: a backup pick, opened under its slot's row and laid out as it, joined to it by a tree line.
local ns = _G.NaowhForever

local GetItemInfo = C_Item.GetItemInfo
local GetItemIconByID = C_Item.GetItemIconByID

local T = ns.THEME
local B = ns.BiS
local Shared = ns.Shared
local Items, Parts = Shared.Items, Shared.Parts
local Cells, PickRow = B.View.Cells, B.View.PickRow
local St = B.Style

local ROW_H, ROW_ICON = St.ROW_H, St.ROW_ICON
local STATUS_W, SLOT_W, META_W, TAIL_W = St.STATUS_W, St.SLOT_W, St.META_W, St.TAIL_W
local INSET, GAP, NAME_GAP = St.STATUS_W, St.COLUMN_GAP, St.NAME_GAP
local CARD_DROP = Parts.CARD_DROP
local BACKUP_STEP = 14
local TREE_X, TREE_UP, TREE_GAP, TREE_ALPHA, TREE_DROP, ELBOW = 12, 9, 4, 0.5, 1, 8
local ELBOW_OVERLAP = 1
local TREE_RGB = St.SECOND_RGB
local FIRST_BACKUP = 2
local ORDINAL = { "BiS", "2nd", "3rd" }
local ORDINAL_TAIL = "th"

local backupRanks = {}

local function BackupRank(rank)
    local text = backupRanks[rank]
    if not text then
        text = Parts.RankMark(rank, CARD_DROP) .. " " .. ns.Color("muted", ORDINAL[rank] or (rank .. ORDINAL_TAIL))
        backupRanks[rank] = text
    end
    return text
end

local function Tree(row)
    row.trunk = ns.Solid(row, "ARTWORK", TREE_RGB, TREE_ALPHA)
    ns.Hairline(row.trunk, "v")
    row.branch = ns.Solid(row, "ARTWORK", TREE_RGB, TREE_ALPHA)
    ns.Hairline(row.branch, "h")
    row.elbow = row:CreateTexture(nil, "ARTWORK")
    row.elbow:SetTexture(St.ELBOW)
    row.elbow:SetSize(ELBOW, ELBOW)
    row.elbow:SetPoint("BOTTOMLEFT", row, "LEFT", TREE_X, -TREE_DROP - ELBOW_OVERLAP)
    row.elbow:SetVertexColor(TREE_RGB.r, TREE_RGB.g, TREE_RGB.b, TREE_ALPHA)
end

local function PaintTree(row, rank, count)
    local up, last = rank == FIRST_BACKUP and TREE_UP or 0, rank == count
    local corner = last and ELBOW or 0
    row.trunk:ClearAllPoints()
    row.trunk:SetPoint("TOPLEFT", TREE_X, up)
    row.trunk:SetHeight(last and up + ROW_H / 2 + TREE_DROP - ELBOW + ELBOW_OVERLAP or up + ROW_H)
    row.elbow:SetShown(last)
    row.branch:ClearAllPoints()
    row.branch:SetPoint("TOPLEFT", row, "LEFT", TREE_X + corner, -TREE_DROP)
    row.branch:SetWidth(STATUS_W + BACKUP_STEP - TREE_GAP - TREE_X - corner)
end

local function Meta(row)
    row.meta = ns.Font(row, St.SMALL_SIZE, nil, T.muted)
    row.meta:SetPoint("RIGHT", -(TAIL_W + INSET + GAP), 0)
    row.meta:SetWidth(META_W)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetWordWrap(false)
end

local function New(view)
    local row = CreateFrame("Button", nil, view)
    row:SetHeight(ROW_H)
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, St.HOVER)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.rankText = ns.Font(row, St.TEXT_SIZE, nil, T.muted)
    row.rankText:SetPoint("LEFT", STATUS_W + BACKUP_STEP, 0)
    Tree(row)
    local icon = Parts.ItemIcon(row, ROW_ICON)
    Cells.TipZone(row, icon, ROW_H, PickRow.TipEnter)
    icon:SetPoint("LEFT", STATUS_W + SLOT_W, 0)
    row.iconFrame, row.icon = icon, icon.texture
    PickRow.Actions(row, -INSET)
    Meta(row)
    Cells.SourceZone(row)
    Cells.Gain(row, row.meta, GAP)
    row.worn = Parts.WornBar(row, 0)
    row.name = ns.Font(row, St.TEXT_SIZE)
    row.name:SetPoint("LEFT", icon, "RIGHT", NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.gain, "LEFT", -GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", PickRow.Clicked)
    row:SetScript("OnEnter", PickRow.Enter)
    row:SetScript("OnLeave", PickRow.Leave)
    return row
end

local function Set(row, slot, itemID, rank, count)
    local view = row:GetParent()
    row.slot, row.itemID, row.rank, row.mode = slot, itemID, rank, "list"
    row.hover:Hide()
    row.rankText:SetText(BackupRank(rank))
    PaintTree(row, rank, count)
    row.icon:SetTexture(GetItemIconByID(itemID))
    local name = GetItemInfo(itemID)
    if not name then view.waitingFor[itemID] = true end
    local worn = Items.Wearing(slot, itemID)
    row.worn:SetShown(worn)
    Parts.MarkForever(row.iconFrame, itemID)
    row.name:SetText(Cells.Named(itemID, name))
    Cells.FitTip(row)
    Cells.PaintGain(row.gain, B.Upgrades.Gain(itemID, slot), view.mostGain)
    row.meta:SetText(Cells.Meta(itemID, view.playerLevel) .. Cells.KeptTail(not worn and Items.Kept(itemID) or ""))
    Cells.FitSource(row, itemID)
    row.canAct[row.up] = rank > FIRST_BACKUP
    row.canAct[row.down] = rank < count
    row.canAct[row.remove] = true
    PickRow.ShowActions(row, false)
    return ROW_H, name == nil
end

B.View.Kinds.backup = { New = New, Set = Set }
