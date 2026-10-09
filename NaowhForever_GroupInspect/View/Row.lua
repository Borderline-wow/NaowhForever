-- Row.lua: a Group Inspect raid member's row on the shared row engine: who they are, then their gear, talents or stats (GI.UI.RaidKinds).
local ns = _G.NaowhForever
local T = ns.THEME
local GI = ns.GroupInspect
local UI = GI.UI
local Shared = ns.Shared
local Parts, View, Items = Shared.Parts, Shared.View, Shared.Items
local Order = UI.RaidOrder

local St = UI.Style
local ROW_H, BAND_W = St.ROW_H, St.BAND_H
local STRIP_SLOT, STRIP_GAP = St.STRIP_SLOT, St.STRIP_GAP
local NAME_X, VIEW_X, TREE_W = St.RAID_NAME_X, St.RAID_VIEW_X, St.RAID_TREE_W
local SCORE_RIGHT, ILVL_RIGHT, STATE_RIGHT = St.RAID_SCORE_RIGHT, St.RAID_ILVL_RIGHT, St.RAID_STATE_RIGHT
local ROUND = GI.C.ROUND
local GEAR_SLOTS = Items.GEAR_SLOTS
local STATS = UI.STATS
local WAITING = UI.WAITING

local CLASS_X, NAME_W = 12, 138
local NF_X, ROLE_X = 184, 212
local FIRST_WEAPON = 15
local POINTS_X, TROLE_X = 512, 580
local STATE_W, REFRESH_RIGHT = 100, 8
local SCORE_SIZE, STAT_SIZE, STAT_GAP = 14, 11, 12

local SortValue = Order.SortValue

local function RowEnter(row) row.hover:Show() end
local function RowLeave(row) row.hover:Hide() end

local function RowRefresh(button)
    local guid = button:GetParent().guid
    if guid then GI.Refresh(guid) end
end

local function NewRow(view)
    local row = CreateFrame("Frame", nil, view)
    Parts.RowBands(row, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row.band = ns.Solid(row, "ARTWORK", T.fg, 1)
    row.band:SetPoint("TOPLEFT")
    row.band:SetPoint("BOTTOMLEFT")
    row.band:SetWidth(BAND_W)
    row.class = UI.ClassIcon(row, St.ROW_CLASS_ICON)
    row.class:SetPoint("LEFT", CLASS_X, 0)
    row.name = ns.Font(row, St.ROW_NAME_SIZE, nil, T.fg)
    row.name:SetPoint("LEFT", NAME_X, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.nameHit = UI.NameHit(row, row)
    row.nameHit:SetPoint("LEFT", NAME_X, 0)
    row.nameHit:SetSize(NAME_W, ROW_H)
    row.badge = UI.Badge(row, row)
    row.badge:SetFrameLevel(row.nameHit:GetFrameLevel() + 2)
    row.nf = UI.NFPill(row, row)
    row.nf:SetPoint("LEFT", NF_X, 0)
    row.role = UI.RoleIcon(row, St.ROW_ROLE_ICON)
    row.role:SetPoint("LEFT", ROLE_X, 0)
    row.score = ns.Font(row, SCORE_SIZE, nil, T.fg)
    row.score:SetPoint("RIGHT", row, "LEFT", SCORE_RIGHT, 0)
    row.ilvl = ns.Font(row, St.ROW_NAME_SIZE, nil, T.fg)
    row.ilvl:SetPoint("RIGHT", row, "LEFT", ILVL_RIGHT, 0)

    row.gear = CreateFrame("Frame", nil, row)
    row.gear:SetPoint("LEFT", VIEW_X, 0)
    row.gear:SetSize(#GEAR_SLOTS * (STRIP_SLOT + STRIP_GAP) + St.STRIP_WEAPON_GAP, STRIP_SLOT)
    row.slots = {}
    for i, entry in ipairs(GEAR_SLOTS) do
        local icon = UI.GearIcon(row.gear, STRIP_SLOT, entry[1], row, false)
        icon:SetPoint("LEFT", (i - 1) * (STRIP_SLOT + STRIP_GAP) + (i >= FIRST_WEAPON and St.STRIP_WEAPON_GAP or 0), 0)
        row.slots[i] = icon
    end

    row.tree = ns.Font(row, St.LINE_SIZE, nil, T.fg)
    row.tree:SetPoint("LEFT", VIEW_X, 0)
    row.tree:SetWidth(TREE_W)
    row.tree:SetJustifyH("LEFT")
    row.tree:SetWordWrap(false)
    row.points = ns.Font(row, St.LINE_SIZE, nil, T.fg)
    row.points:SetPoint("LEFT", POINTS_X, 0)
    row.trole = ns.Font(row, St.SUB_SIZE, nil, T.muted)
    row.trole:SetPoint("LEFT", TROLE_X, 0)

    row.stats = Parts.LabelRow(row, STAT_SIZE, nil, T.fg, { gap = STAT_GAP })
    row.stats:SetPoint("LEFT", VIEW_X, 0)
    row.statList = {}

    row.state = ns.Font(row, St.SUB_SIZE, nil, T.muted)
    row.state:SetPoint("RIGHT", -STATE_RIGHT, 0)
    row.state:SetWidth(STATE_W)
    row.state:SetJustifyH("RIGHT")
    row.refresh = Parts.IconButton(row, RowRefresh, St.RESET, 0, UI.REFRESH_TIP)
    row.refresh:SetPoint("RIGHT", -REFRESH_RIGHT, 0)
    return row
end

local function PaintStrip(row, rec)
    local gear = rec.gear
    for i = 1, #GEAR_SLOTS do
        UI.PaintGear(row.slots[i], gear and gear[GEAR_SLOTS[i][1]])
    end
end

local function PaintTalents(row, rec)
    local talents = rec.talents
    row.tree:SetText(talents and talents.tree or WAITING)
    row.points:SetText(talents and UI.TalentText(talents.spent) or "")
    row.trole:SetText(talents and talents.role or UI.ROLE_WORDS[rec.role] or "")
end

local function PaintStats(row, rec)
    local stats, list, n = rec.stats, row.statList, 0
    if stats then
        for i = 1, #STATS do
            local stat = STATS[i]
            local value = stats[stat.key]
            if type(value) == "number" and value ~= 0 then
                n = n + 1
                list[n] = UI.StatInline(stat, value)
            end
        end
    else
        n = 1
        list[1] = WAITING
    end
    row.stats:SetLabels(list, n)
    row.stats:Pack()
    row.stats:SetColor((rec.statsShared or rec.state == "self") and T.fg or T.muted)
end

local function SetRow(row, rec, index)
    local view = row:GetParent()
    local mode = view.mode
    row.guid, row.index = rec.guid, index
    row.sortValue = SortValue(rec, view.sort)
    row.stripe:SetShown(index % 2 == 0)
    local color = UI.ClassColor(rec.classFile)
    row.band:SetColorTexture(color.r, color.g, color.b, 1)
    UI.PaintClass(row.class, rec.classFile)
    local badged = UI.PaintBadge(row.badge, rec.guid)
    local room = NAME_W - (badged and St.BADGE + St.BADGE_GAP or 0)
    local width = UI.FitName(row.name, rec.name or WAITING, room, St.ROW_NAME_SIZE, St.ROW_NAME_MIN)
    row.name:SetTextColor(color.r, color.g, color.b)
    row.badge:ClearAllPoints()
    row.badge:SetPoint("LEFT", row.name, "LEFT", width + St.BADGE_GAP, 0)
    row.nf:SetShown(rec.hasNF == true)
    UI.PaintNFPill(row.nf, rec)
    UI.PaintRole(row.role, rec.role)
    row.score:SetText(UI.ScoreText(rec.score, rec.level))
    row.ilvl:SetText(rec.ilvl and tostring(math.floor(rec.ilvl + ROUND)) or WAITING)
    local gear, talents, stats = mode == "gear", mode == "talents", mode == "stats"
    row.gear:SetShown(gear)
    row.tree:SetShown(talents)
    row.points:SetShown(talents)
    row.trole:SetShown(talents)
    row.stats:SetShown(stats)
    if gear then
        PaintStrip(row, rec)
    elseif talents then
        PaintTalents(row, rec)
    else
        PaintStats(row, rec)
    end
    row.state:SetText(UI.StateText(rec.state))
    row:SetAlpha(UI.Away(rec) and St.AWAY_ALPHA or 1)
    return ROW_H
end

local kinds = View.NewKinds()
kinds.member = { New = NewRow, Set = SetRow }
UI.RaidKinds = kinds
