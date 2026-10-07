-------------------------------------------------------------------------------
--  Party.lua -- Group Inspect's party of two to five (GI.UI.PartyBoard): a big card per member
--  side by side, wider for four or fewer, each under a band of their class's color with their
--  class icon, name (smaller for a long one, whole on hover), supporter badge, level, role and
--  the NF pill for who runs Naowh Forever; then their Naowh Score on the score card's ramp
--  beside their item level, their gear laid out as the character sheet (item level, BiS star
--  and missing enchant on each slot, the game's tooltip on hover, the game's empty slot art),
--  their talents and their stats in two lined-up columns. Five cards made once and repainted;
--  a member's change repaints only their card. Used by the window and the settings preview.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local GI = ns.GroupInspect
local UI = GI.UI
local CP = ns.CharacterPanel
local Parts, Items = ns.Shared.Parts, ns.Shared.Items

local St = UI.Style
local GAP, MAX, PAD = St.PARTY_GAP, St.PARTY_MAX, St.PARTY_PAD
local BAND_H, KICKER_SIZE, KICKER_GAP = St.BAND_H, St.KICKER_SIZE, St.KICKER_GAP
local LINE_SIZE, LINE_H, SUB_SIZE, SECTION_GAP = St.LINE_SIZE, St.LINE_H, St.SUB_SIZE, St.SECTION_GAP
local CLASS_ICON, ROLE_ICON = St.CLASS_ICON, St.ROLE_ICON
local GEAR_SLOTS = Items.GEAR_SLOTS
local STATS = UI.STATS
local WAITING = UI.WAITING

local NAME_GAP, SUB_Y, ICON_GAP, PILL_DROP = 8, 19, 6, 1
local RULE_GAP = 8
local ILVL_SIZE, ILVL_GAP = 20, 3
local STAT_ROWS, VALUE_CHARS, VALUE_ROOM = 5, 6, 40
local GRID_COL = { 0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1, 3, 4, 5 }
local GRID_ROW = { 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 }
local GRID_COLS, GRID_ROWS = 6, 3

local HEAD_Y = BAND_H + PAD
local RULE_Y = HEAD_Y + CLASS_ICON + RULE_GAP
local SCORE_Y = RULE_Y + RULE_GAP + 1
local GEAR_Y = SCORE_Y + CP.BADGE_H + SECTION_GAP

local NARROW = { w = St.PARTY_W, slot = St.SLOT, slotGap = St.SLOT_GAP, cellGap = 16 }
local WIDE = { w = St.PARTY_WIDE_W, slot = St.WIDE_SLOT, slotGap = St.WIDE_SLOT_GAP, cellGap = 24, long = true }

local function Measure(l)
    l.inner = l.w - 2 * PAD
    l.gridW = GRID_COLS * l.slot + (GRID_COLS - 1) * l.slotGap
    l.gridX = PAD + math.floor((l.inner - l.gridW) / 2)
    l.cellW = (l.inner - l.cellGap) / 2
    l.slotsY = GEAR_Y + KICKER_SIZE + KICKER_GAP
    l.talentsY = l.slotsY + GRID_ROWS * l.slot + (GRID_ROWS - 1) * l.slotGap + SECTION_GAP
    l.treeY = l.talentsY + KICKER_SIZE + KICKER_GAP
    l.statsY = l.treeY + 2 * LINE_H + SECTION_GAP
    l.cellsY = l.statsY + KICKER_SIZE + KICKER_GAP
    l.stateY = l.cellsY + STAT_ROWS * LINE_H + SECTION_GAP / 2
    l.h = l.stateY + St.ACTION + PAD
end
Measure(NARROW)
Measure(WIDE)

UI.PARTY_H = math.max(NARROW.h, WIDE.h)
UI.BOARD_W = MAX * NARROW.w + (MAX - 1) * GAP
UI.PARTY_LAYOUTS = { narrow = NARROW, wide = WIDE }

local SCORE_SHARED, SCORE_READ, SCORE_YOURS = "Shared by their Naowh Forever", "Read from their gear", "Yours"
local NOT_READ, NO_TALENTS = "Not inspected yet", "Not known yet"
local REFRESH_TIP = "Inspect them again"

local function Color(text, color)
    text:SetTextColor(color.r, color.g, color.b)
end

local function ScoreEnter(score)
    if GameTooltip:IsForbidden() then return end
    local guid = score:GetParent().guid
    local rec = guid and GI.Member(guid)
    if not Parts.Tip(score, "ANCHOR_BOTTOM") then return end
    local m = T.muted
    GameTooltip:SetText("Naowh Score", 1, 1, 1)
    if rec and rec.score then
        GameTooltip:AddLine(ns.NaowhScore.Tooltip(rec.score, rec.level))
        local source = rec.state == "self" and SCORE_YOURS or rec.scoreShared and SCORE_SHARED or SCORE_READ
        GameTooltip:AddLine(source, m.r, m.g, m.b)
    else
        GameTooltip:AddLine(NOT_READ, m.r, m.g, m.b)
    end
    GameTooltip:Show()
end

local function Refresh(button)
    local guid = button:GetParent().guid
    if guid then GI.Refresh(guid) end
end

local function NewStat(card)
    local stat = { label = ns.Font(card, SUB_SIZE, nil, T.muted) }
    stat.label:SetJustifyH("LEFT")
    stat.label:SetWordWrap(false)
    stat.value = Parts.Cells(card, LINE_SIZE, T.fg, VALUE_CHARS)
    return stat
end

local function NewCard(board)
    local card = CreateFrame("Frame", nil, board)
    ns.Solid(card, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(card, St.BORDER_RGB)
    card.band = ns.Solid(card, "ARTWORK", T.fg, 1)
    card.band:SetPoint("TOPLEFT", 1, -1)
    card.band:SetPoint("TOPRIGHT", -1, -1)
    card.band:SetHeight(BAND_H)

    card.class = UI.ClassIcon(card, CLASS_ICON)
    card.class:SetPoint("TOPLEFT", PAD, -HEAD_Y)
    card.nameHit = UI.NameHit(card, card)
    card.nameHit:SetPoint("TOPLEFT", card.class, "TOPLEFT")
    card.nameHit:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -(PAD + ROLE_ICON + ICON_GAP), -(HEAD_Y + CLASS_ICON))
    card.nf = UI.NFPill(card, card)
    card.nf:SetPoint("TOPRIGHT", -PAD, -(HEAD_Y + PILL_DROP))
    card.role = UI.RoleIcon(card, ROLE_ICON)
    card.role:SetPoint("TOPRIGHT", -PAD, -(HEAD_Y + CLASS_ICON - ROLE_ICON))
    card.name = ns.Font(card, St.NAME_SIZE, nil, T.fg)
    card.name:SetPoint("TOPLEFT", card.class, "TOPRIGHT", NAME_GAP, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    card.badge = UI.Badge(card, card)
    card.badge:SetFrameLevel(card.nameHit:GetFrameLevel() + 2)
    card.sub = ns.Font(card, SUB_SIZE, nil, T.muted)
    card.sub:SetPoint("TOPLEFT", card.class, "TOPRIGHT", NAME_GAP, -SUB_Y)
    card.sub:SetPoint("RIGHT", card, "RIGHT", -(PAD + ROLE_ICON + ICON_GAP), 0)
    card.sub:SetJustifyH("LEFT")
    card.sub:SetWordWrap(false)
    local rule = ns.Solid(card, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", PAD, -RULE_Y)
    rule:SetPoint("TOPRIGHT", -PAD, -RULE_Y)
    ns.Hairline(rule, "h")

    card.score = CP.ScoreCard(card, NARROW.inner)
    card.score:SetPoint("TOPLEFT", PAD, -SCORE_Y)
    card.score:SetScript("OnEnter", ScoreEnter)
    card.score:SetScript("OnLeave", GameTooltip_Hide)
    local ilvlKicker = UI.Kicker(card, "ITEM LEVEL")
    ilvlKicker:SetPoint("TOPRIGHT", -PAD, -SCORE_Y)
    card.ilvl = ns.Font(card, ILVL_SIZE, nil, T.fg)
    card.ilvl:SetPoint("TOPRIGHT", ilvlKicker, "BOTTOMRIGHT", 0, -ILVL_GAP)

    UI.Kicker(card, "GEAR"):SetPoint("TOPLEFT", PAD, -GEAR_Y)
    card.enchants = ns.Font(card, KICKER_SIZE, nil, T.fg)
    card.enchants:SetPoint("TOPRIGHT", -PAD, -GEAR_Y)
    card.slots = {}
    for i, entry in ipairs(GEAR_SLOTS) do
        card.slots[i] = UI.GearIcon(card, NARROW.slot, entry[1], card, true)
    end

    card.talentsKicker = UI.Kicker(card, "TALENTS")
    card.tree = ns.Font(card, LINE_SIZE, nil, T.fg)
    card.tree:SetJustifyH("LEFT")
    card.tree:SetWordWrap(false)
    card.points = Parts.Cells(card, LINE_SIZE, T.fg, VALUE_CHARS + 2)
    card.trole = ns.Font(card, SUB_SIZE, nil, T.muted)
    card.statsKicker = UI.Kicker(card, "STATS")
    card.from = ns.Font(card, KICKER_SIZE, nil, T.muted)
    card.stats = {}
    for i = 1, STAT_ROWS * 2 do card.stats[i] = NewStat(card) end

    card.state = ns.Font(card, SUB_SIZE, nil, T.muted)
    card.refresh = Parts.IconButton(card, Refresh, St.RESET, 0, REFRESH_TIP)
    card:Hide()
    return card
end

local function Place(card, l)
    card.layout = l
    card:SetSize(l.w, l.h)
    CP.SizeScoreCard(card.score, l.inner)
    for i, icon in ipairs(card.slots) do
        icon:SetSize(l.slot, l.slot)
        Parts.SizeItemMarks(icon.marks, l.slot)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", l.gridX + GRID_COL[i] * (l.slot + l.slotGap),
            -(l.slotsY + GRID_ROW[i] * (l.slot + l.slotGap)))
    end
    card.talentsKicker:ClearAllPoints()
    card.talentsKicker:SetPoint("TOPLEFT", PAD, -l.talentsY)
    card.tree:ClearAllPoints()
    card.tree:SetPoint("TOPLEFT", PAD, -l.treeY)
    card.tree:SetWidth(l.inner - VALUE_ROOM * 2)
    card.points[1]:ClearAllPoints()
    card.points[1]:SetPoint("TOPRIGHT", card, "TOPLEFT", PAD + l.inner, -l.treeY)
    card.trole:ClearAllPoints()
    card.trole:SetPoint("TOPLEFT", PAD, -(l.treeY + LINE_H))
    card.statsKicker:ClearAllPoints()
    card.statsKicker:SetPoint("TOPLEFT", PAD, -l.statsY)
    card.from:ClearAllPoints()
    card.from:SetPoint("TOPRIGHT", -PAD, -l.statsY)
    for _, stat in ipairs(card.stats) do stat.label:SetWidth(l.cellW - VALUE_ROOM) end
    card.state:ClearAllPoints()
    card.state:SetPoint("LEFT", card, "TOPLEFT", PAD, -(l.stateY + St.ACTION / 2))
    card.refresh:ClearAllPoints()
    card.refresh:SetPoint("TOPRIGHT", -PAD, -l.stateY)
end

local function PaintHeader(card, rec, color)
    local nf = rec.hasNF == true
    card.nf:SetShown(nf)
    UI.PaintNFPill(card.nf, rec)
    local badged = UI.PaintBadge(card.badge, rec.guid)
    local room = card.layout.inner - CLASS_ICON - NAME_GAP - (nf and card.nf:GetWidth() + ICON_GAP or 0)
        - (badged and St.BADGE + St.BADGE_GAP or 0)
    local width = UI.FitName(card.name, rec.name or WAITING, room, St.NAME_SIZE, St.NAME_MIN)
    Color(card.name, color)
    card.badge:ClearAllPoints()
    card.badge:SetPoint("LEFT", card.name, "LEFT", width + St.BADGE_GAP, 0)
    card.sub:SetText(UI.LevelText(rec.level, rec.classFile))
    UI.PaintRole(card.role, rec.role)
end

local function PaintGear(card, rec)
    local gear = rec.gear
    for i = 1, #GEAR_SLOTS do
        UI.PaintGear(card.slots[i], gear and gear[GEAR_SLOTS[i][1]])
    end
    card.enchants:SetText(UI.EnchantText(rec))
end

local function PaintTalents(card, rec)
    local talents = rec.talents
    if not talents then
        card.tree:SetText(NO_TALENTS)
        Color(card.tree, T.muted)
        card.points:SetText("")
        card.trole:SetText(UI.ROLE_WORDS[rec.role] or "")
        return
    end
    card.tree:SetText(talents.tree or "")
    Color(card.tree, T.fg)
    card.points:SetText(UI.TalentText(talents.spent))
    card.trole:SetText(talents.role or UI.ROLE_WORDS[rec.role] or "")
end

local shown = {}

local function PaintStats(card, rec)
    local l, values, stats, n = card.layout, rec.stats, card.stats, 0
    if values then
        for i = 1, #STATS do
            local stat = STATS[i]
            local value = values[stat.key]
            if type(value) == "number" and value ~= 0 and n < #stats then
                n = n + 1
                shown[n] = stat
            end
        end
    end
    local split = math.ceil(n / 2)
    for i = 1, #stats do
        local cell, stat = stats[i], shown[i]
        cell.label:ClearAllPoints()
        if stat then
            local col = i <= split and 0 or 1
            local row = col == 0 and i - 1 or i - split - 1
            local x, y = PAD + col * (l.cellW + l.cellGap), l.cellsY + row * LINE_H
            cell.label:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
            cell.label:SetText(l.long and stat.name or stat.card or stat.name)
            cell.value[1]:ClearAllPoints()
            cell.value[1]:SetPoint("TOPRIGHT", card, "TOPLEFT", x + l.cellW, -y)
            cell.value:SetText(UI.StatValue(stat, values[stat.key]))
        else
            cell.label:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -l.cellsY)
            cell.label:SetText(i == 1 and not values and WAITING or "")
            cell.value:SetText("")
        end
    end
    for i = 1, n do shown[i] = nil end
    local from, color = UI.StatsFrom(rec)
    card.from:SetText(from)
    Color(card.from, color)
end

local function PaintCard(card, rec)
    card.guid = rec.guid
    local color = UI.ClassColor(rec.classFile)
    card.band:SetColorTexture(color.r, color.g, color.b, 1)
    UI.PaintClass(card.class, rec.classFile)
    PaintHeader(card, rec, color)
    if rec.score then CP.PaintScoreCard(card.score, rec.score, rec.level) else CP.ScoreCardWaiting(card.score) end
    card.ilvl:SetText(rec.ilvl and tostring(math.floor(rec.ilvl + 0.5)) or WAITING)
    PaintGear(card, rec)
    PaintTalents(card, rec)
    PaintStats(card, rec)
    card.state:SetText(UI.StateText(rec.state))
    card:SetAlpha(UI.Away(rec) and St.AWAY_ALPHA or 1)
end

local function Paint(board)
    local members = GI.Members()
    local n = math.min(#members, MAX)
    local l = n >= MAX and NARROW or WIDE
    board:SetHeight(l.h)
    local x = math.floor((UI.BOARD_W - (n * l.w + math.max(0, n - 1) * GAP)) / 2)
    for i = 1, MAX do
        local card = board.cards[i]
        if i <= n then
            if card.layout ~= l then Place(card, l) end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", x + (i - 1) * (l.w + GAP), 0)
            PaintCard(card, members[i])
            card:Show()
        else
            card.guid = nil
            card:Hide()
        end
    end
end

local function PaintGuid(board, guid)
    for i = 1, MAX do
        local card = board.cards[i]
        if card.guid == guid and card:IsShown() then
            local rec = GI.Member(guid)
            if not rec then return false end
            PaintCard(card, rec)
            return true
        end
    end
    return false
end

function UI.PartyBoard(parent)
    local board = CreateFrame("Frame", nil, parent)
    board:SetSize(UI.BOARD_W, NARROW.h)
    board.cards = {}
    for i = 1, MAX do
        board.cards[i] = NewCard(board)
        Place(board.cards[i], NARROW)
    end
    board.Paint, board.PaintGuid = Paint, PaintGuid
    return board
end
