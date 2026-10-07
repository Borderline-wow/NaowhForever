-------------------------------------------------------------------------------
--  View/Rows.lua -- the BiS List's rows (ns.BiS.View.Kinds): your progress, the filter, a
--  slot's row with its enchant, a pick, and a place to run next.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Tip = ns.Shared.Parts.Tip
local T = ns.THEME
local B = ns.BiS
local R, Enchants = B.Rankings, B.Enchants
local Shared = ns.Shared
local Items, Parts, Places = Shared.Items, Shared.Parts, Shared.Places
local Kinds = B.View.Kinds

local GetItemInfo = C_Item.GetItemInfo
local GetItemIconByID = C_Item.GetItemIconByID

local St = B.Style
local CARD_PAD, ICON, ITEM_H, ACTION = St.CARD_PAD, St.ICON, St.ITEM_H, St.ACTION
local PLACE_DOT, RED_CODE, FILTER_W = St.PLACE_DOT, St.RED_CODE, St.FILTER_W
local PLACE_H, ROW_H, ROW_ICON = St.PLACE_H, St.ROW_H, St.ROW_ICON
local STATUS_W, SLOT_W, META_W, TAIL_W = St.STATUS_W, St.SLOT_W, St.META_W, St.TAIL_W
local INSET, GAP = St.STATUS_W, St.COLUMN_GAP
local GAIN_W = 44   -- "+18%", right-aligned over its bar
local BACKUP_STEP = 14   -- a backup's rank, in from the slot's name: it hangs under it
-- The line that joins a slot's backups to it, as a tree, in the second pick's silver: down
-- from under the slot's name (TREE_X in, starting TREE_UP into the slot's row, under its
-- letters), a branch across to each rank stopping TREE_GAP short of it, and the last turning
-- into its branch on a rounded corner (ELBOW, its texture's own size). The branch sits
-- TREE_DROP under the row's middle, level with the rank's letters: the Naowh font leaves room
-- above its capitals, so a line on the middle reads a pixel high (unmeasured; check in game).
local TREE_X, TREE_UP, TREE_GAP, TREE_ALPHA, TREE_DROP, ELBOW = 12, 9, 4, 0.5, 1, 8
local TREE_RGB = St.SECOND_RGB
-- A place to run next's columns on the right: its link ("Waypoint" the longest, with its
-- arrow), the count of your BiS there ("<star> 12") and the gaps between them and the gain.
local PLACE_LINK_W, PLACE_COUNT_W, PLACE_GAP = 72, 34, 10
local CARD_DROP, STRIPE = Parts.CARD_DROP, St.STRIPE
local SLOT_NAME = Items.SLOT_NAME

local ACTION_GAP = 6
local ACTIONS_W = -(St.ACTION + ACTION_GAP) * 3   -- a pick's move up, move down and remove
local NAME_TOP = 1
local UNKNOWN = "World drop"   -- what the data has no source for
local STAR_MARK = Parts.RankMark(1, CARD_DROP)

local function OpenPicker(slot, from)
    B.OpenPicker(slot, from)
end

-- A row's gain as a small bar chart: the percent, right-aligned, and under it a thin bar as
-- long as its share of the list's biggest gain, by the square root, so +1%
-- still shows beside +18% and the big wins stand out down the column (as the Journal's drop
-- chances). Text and bar are as bright as the gain: a big one (GAIN_BIG and up) the upgrade
-- green, a small one (under GAIN_SMALL) muted, the rest between.
local GAIN_H, GAIN_BIG, GAIN_SMALL = 18, 10, 2
local GAIN_BAR_H = 2
local GAIN_BIG_RGB = { r = 0x1e / 255, g = 1, b = 0 }
local GAIN_RGB = { r = 0.47, g = 0.86, b = 0.45 }
local GAIN_SMALL_RGB = { r = 0.42, g = 0.62, b = 0.45 }
local gainWords = {}

local function GainCell(row, anchor, gap)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetSize(GAIN_W, GAIN_H)
    cell:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
    cell.bar = ns.Solid(cell, "ARTWORK", GAIN_BIG_RGB, 1)
    cell.bar:SetPoint("BOTTOMRIGHT")
    cell.bar:SetHeight(GAIN_BAR_H)
    cell.text = ns.Font(cell, 12)
    cell.text:SetPoint("TOPRIGHT", 0, 0)
    cell.text:SetJustifyH("RIGHT")
    row.gain = cell
end

---@param gain? number percent
---@param most? number the list's biggest gain
local function PaintGain(cell, gain, most)
    if not gain then
        cell:Hide()
        return
    end
    local percent = math.max(1, math.floor(gain + 0.5))
    local words = gainWords[percent]
    if not words then
        words = "+" .. percent .. "%"
        gainWords[percent] = words
    end
    cell.text:SetText(words)
    local color = gain >= GAIN_BIG and GAIN_BIG_RGB or gain < GAIN_SMALL and GAIN_SMALL_RGB or GAIN_RGB
    cell.text:SetTextColor(color.r, color.g, color.b)
    local share = most and most > 0 and math.sqrt(math.min(1, gain / most)) or 1
    cell.bar:SetWidth(math.max(2, math.floor(GAIN_W * share + 0.5)))
    cell.bar:SetColorTexture(color.r, color.g, color.b, 1)
    cell:Show()
end

-- Text made once per pair of numbers ("2 of 17", "To get 15").
local function Memo(format)
    local made = {}
    return function(a, b)
        local byA = made[a]
        if not byA then
            byA = {}
            made[a] = byA
        end
        local text = byA[b]
        if not text then
            text = format:format(a, b)
            byA[b] = text
        end
        return text
    end
end

-------------------------------------------------------------------------------
--  Where an item drops, and the rest of its second line
-------------------------------------------------------------------------------
-- A weapon's kind, where it drops, and the level it needs: always (withLevel, in the picker),
-- else only while above yours, in red. Made once per item and way, and again when that level
-- goes from above yours to within it.
local metas = { [true] = {}, [false] = {} }
local metaAbove = { [true] = {}, [false] = {} }

-- A quest for your own side says only "Quest": the list gives you no quest of the other's.
local OWN_QUEST = { Alliance = "Quest (Alliance)", Horde = "Quest (Horde)" }
local ownQuest

local function Place(itemID)
    local place, detail = R.Place(ns.BiSSource(itemID) or UNKNOWN)
    ownQuest = ownQuest or OWN_QUEST[UnitFactionGroup("player")] or false
    if place == ownQuest then place = "Quest" end
    return place, detail
end

local function Meta(itemID, playerLevel, withLevel)
    local required = R.ReqLevel(itemID)
    local above = required ~= nil and required > playerLevel
    withLevel = withLevel == true
    local meta = metas[withLevel][itemID]
    if meta and metaAbove[withLevel][itemID] == above then return meta end
    local place, detail = Place(itemID)
    local weapon = Items.WeaponOf(itemID)
    local level = required and required > 1 and (above or withLevel)
        and PLACE_DOT .. (above and RED_CODE or "") .. "Level " .. required .. (above and "|r" or "") or ""
    meta = (weapon and weapon .. PLACE_DOT or "") .. (detail and detail .. PLACE_DOT or "") .. place .. level
    metas[withLevel][itemID], metaAbove[withLevel][itemID] = meta, above
    return meta
end

local keptTails = { [""] = "" }

local function KeptTail(kept)
    local tail = keptTails[kept]
    if not tail then
        tail = PLACE_DOT .. kept
        keptTails[kept] = tail
    end
    return tail
end

-- An item new in Forever says so in its tooltip, under the badge on its icon.
local function ForeverTip(itemID)
    if Parts.IsForever("items", itemID) then GameTooltip:AddLine(Parts.ForeverLine()) end
end

local function ItemTip(owner, itemID, hint)
    if not Tip(owner, "ANCHOR_CURSOR_RIGHT", 16, 0) then return end
    GameTooltip:SetItemByID(itemID)
    ForeverTip(itemID)
    if hint then GameTooltip:AddLine(hint, T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:Show()
end

-- An item's card comes up over its icon and name only, so it never covers the list while
-- the mouse crosses a row; the rest of the row only lights up. The zone takes the mouse over
-- it, not its clicks, which go on to the row.
local NAME_GAP = 8   -- between a row's icon and its name, as the rows anchor it

local function TipLeave(zone)
    GameTooltip:Hide()
    local row = zone:GetParent()
    if not row:IsMouseOver() then row:GetScript("OnLeave")(row) end
end

local function TipZone(row, icon, height, onEnter)
    local zone = CreateFrame("Frame", nil, row)
    zone:SetPoint("LEFT", icon, "LEFT")
    zone:SetHeight(height)
    zone:SetScript("OnEnter", onEnter)
    zone:SetScript("OnLeave", TipLeave)
    -- After SetScript: setting mouse scripts turns clicks back on.
    zone:SetMouseMotionEnabled(true)
    zone:SetMouseClickEnabled(false)
    row.tipZone = zone
end

-- As wide as the icon and the name's text, once the name is set.
local function FitTip(row)
    local name = row.name
    local text, room = name:GetStringWidth(), name:GetWidth()
    row.tipZone:SetWidth(row.iconFrame:GetWidth() + NAME_GAP + (room > 0 and math.min(text, room) or text))
end

-- Where an item comes from is a link: the dungeon in the Journal, the quest, a waypoint, the
-- recipe, the map or Wowhead (BiS/Sources.lua). The zone is the text's own size, so the rest
-- of the row keeps its clicks; hovered, the text takes the link colour and says where it goes.
local function SourceEnter(zone)
    local row = zone:GetParent()
    local meta = row.meta
    meta:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    if not Tip(zone, "ANCHOR_TOP") then return end
    -- Cut short in the row: the whole of it first.
    if meta:IsTruncated() then
        GameTooltip:SetText(meta:GetText(), T.muted.r, T.muted.g, T.muted.b)
        GameTooltip:AddLine(B.Sources.Hint(zone.itemID), T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    else
        GameTooltip:SetText(B.Sources.Hint(zone.itemID), T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    end
    GameTooltip:Show()
end

local function SourceLeave(zone)
    local row = zone:GetParent()
    row.meta:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Hide()
    if not row:IsMouseOver() then row:GetScript("OnLeave")(row) end
end

local function SourceClicked(zone)
    GameTooltip:Hide()
    B.Sources.Go(zone.itemID)
end

local function SourceZone(row)
    local zone = CreateFrame("Button", nil, row)
    zone:SetPoint("LEFT", row.meta, "LEFT")
    zone:SetHeight(16)
    zone:SetScript("OnEnter", SourceEnter)
    zone:SetScript("OnLeave", SourceLeave)
    zone:SetScript("OnClick", SourceClicked)
    row.source = zone
end

-- As wide as the source's text, once it is set; none without an item.
local function FitSource(row, itemID)
    local zone, meta = row.source, row.meta
    zone.itemID = itemID
    zone:SetShown(itemID ~= nil)
    local text, room = meta:GetStringWidth(), meta:GetWidth()
    zone:SetWidth(math.max(1, room > 0 and math.min(text, room) or text))
end

-------------------------------------------------------------------------------
--  The summary: how many of your BiS are yours, the filter beside it, and under them a bar of
--  your slots in gear order: green what you wear, grey what is in your bags or bank, dark
--  what is still to get. Hover a slot's segment for its item; a click shows its row. Not a
--  row of the list: the window pins it over it, so it stays in sight however far the list
--  scrolls.
-------------------------------------------------------------------------------
local FILTER_ITEMS = {
    { key = "all", word = "All", tip = "Every slot." },
    { key = "get", word = "To get", tip = "Your BiS you do not have yet: where to go next." },
    { key = "wear", word = "In bag", tip = "Your BiS in your bags or bank: put it on." },
    { key = "enchant", word = "To enchant", tip = "What you wear that takes a better enchant for your level." },
}
local FilterLabel = Memo("%s %d")
local SEGMENT_H, SEGMENT_GAP = 8, 2
local SEGMENT_TOP = St.TAB_H + 12
local SUMMARY_H = SEGMENT_TOP + SEGMENT_H + 14
local HAVE_RGB, RED_RGB = St.HAVE_RGB, St.RED_RGB
local STATE_WORDS = { worn = "You wear it", kept = "In your bags or bank", get = "Not yours yet",
    none = "Nothing picked" }

local function SegmentEnter(segment)
    local slot, bis = segment.slot, segment.bis
    if not Tip(segment, "ANCHOR_BOTTOM") then return end
    GameTooltip:SetText(ns.L(SLOT_NAME[slot]), 1, 1, 1)
    if bis then GameTooltip:AddLine(Items.QualityHex(bis) .. Items.Name(bis) .. "|r  " .. STAR_MARK) end
    local color = segment.state == "worn" and HAVE_RGB or T.muted
    GameTooltip:AddLine(STATE_WORDS[segment.state], color.r, color.g, color.b)
    GameTooltip:Show()
end

local function SegmentClicked(segment)
    local view = segment:GetParent().view
    view:Light(segment.slot)
    view:ScrollTo(segment.slot)
end

local function PaintSegment(segment, list)
    local bis = list.slots[segment.slot]
    local state = not bis and "none" or Items.Wearing(segment.slot, bis) and "worn"
        or Items.Owned(bis) and "kept" or "get"
    segment.bis, segment.state = bis, state
    local color = state == "worn" and HAVE_RGB or state == "kept" and T.muted or T.line
    segment.fill:SetColorTexture(color.r, color.g, color.b, state == "none" and 0.35 or 1)
end

B.View.SUMMARY_H = SUMMARY_H

-- The summary for view, made once, on parent (the window, out of the list's scroll).
function B.View.Summary(parent, view)
    local row = CreateFrame("Frame", nil, parent)
    row.view = view
    row:SetHeight(SUMMARY_H)
    row.count = ns.Font(row, 20, nil, T.fg)
    row.count:SetPoint("TOPLEFT", INSET, -2)
    row.label = ns.Font(row, 12, nil, T.muted)
    row.label:SetPoint("BOTTOMLEFT", row.count, "BOTTOMRIGHT", 6, 2)
    row.label:SetText("BiS yours")
    row.tabs = Parts.Tabs(row, FILTER_W, FILTER_ITEMS, function(key) view:SetFilter(key) end)
    row.tabs:SetPoint("TOPRIGHT", -INSET, 0)
    row.segments = {}
    for i, gear in ipairs(Items.GEAR_SLOTS) do
        local segment = CreateFrame("Button", nil, row)
        segment.slot = gear[1]
        segment.fill = segment:CreateTexture(nil, "ARTWORK")
        segment.fill:SetAllPoints()
        segment:SetScript("OnEnter", SegmentEnter)
        segment:SetScript("OnLeave", GameTooltip_Hide)
        segment:SetScript("OnClick", SegmentClicked)
        row.segments[i] = segment
    end
    return row
end

function B.View.PaintSummary(row, list, filter, counts)
    local have, total = R.Had(list)
    row.count:SetText(Parts.Fraction(have, total))
    FILTER_ITEMS[1].label = FILTER_ITEMS[1].word
    for i = 2, #FILTER_ITEMS do
        local item = FILTER_ITEMS[i]
        item.label = FilterLabel(item.word, counts[item.key])
    end
    Parts.SetTabs(row.tabs, FILTER_ITEMS)
    Parts.PaintTabs(row.tabs, filter)
    local segments = row.segments
    local width = (row:GetWidth() - SEGMENT_GAP * (#segments - 1)) / #segments
    for i, segment in ipairs(segments) do
        segment:SetPoint("TOPLEFT", (i - 1) * (width + SEGMENT_GAP), -SEGMENT_TOP)
        segment:SetSize(width, SEGMENT_H)
        PaintSegment(segment, list)
    end
end

-------------------------------------------------------------------------------
--  A slot's enchant: a wand on its row, bright while the best enchant for what you wear there
--  (for its level) beats what is on it, green once it has that or as good. Hover for which;
--  a click asks for it in Trade chat (or elsewhere), or copies the message.
-------------------------------------------------------------------------------
local ItemLevelText = Memo("Best for this level %d item%s")
local LEARN = { trainer = "trainers teach it", vendor = "a vendor sells the formula",
    drop = "its formula drops", quest = "from a quest" }

local function SpellName(spell)
    return C_Spell.GetSpellName(spell) or ("Enchant " .. spell)
end

local function AddEnchant(spell, color)
    local enchant = ns.BiSEnchants[spell]
    GameTooltip:AddDoubleLine(SpellName(spell), enchant.text and enchant.text .. (enchant.proc and " on average" or ""),
        color.r, color.g, color.b, T.fg.r, T.fg.g, T.fg.b)
    local learn = LEARN[enchant.source]
    GameTooltip:AddLine("Enchanting " .. enchant.skill .. (learn and PLACE_DOT .. learn or ""),
        T.muted.r, T.muted.g, T.muted.b)
    if IsPlayerSpell(spell) then GameTooltip:AddLine("You know it.", HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b) end
end

local function Heading(text)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(text, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
end

local function EnchantEnter(button)
    local slot = button:GetParent().slot
    local a = Enchants.Advise(slot)
    if not Tip(button, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText("Enchants: " .. ns.L(SLOT_NAME[slot]), 1, 1, 1)
    if a.current == 0 then
        GameTooltip:AddLine("Nothing on it yet.", RED_RGB.r, RED_RGB.g, RED_RGB.b)
    elseif a.onIt and a.onIt == a.now then
        GameTooltip:AddLine("It has the best for its level.", HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b)
    elseif a.onIt then
        GameTooltip:AddLine("On it now: " .. SpellName(a.onIt), T.muted.r, T.muted.g, T.muted.b)
    else
        GameTooltip:AddLine("On it now: an enchant from elsewhere.", T.muted.r, T.muted.g, T.muted.b)
    end
    if a.now and a.now ~= a.onIt then
        Heading(ItemLevelText(a.itemLevel, ""))
        AddEnchant(a.now, a.todo and T.accent or T.fg)
    end
    if a.specials[1] then
        Heading("Also worth a look")
        for _, spell in ipairs(a.specials) do AddEnchant(spell, T.fg) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: ask for it in Trade, or copy the message", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

-- "LF Enchanter: [Enchant Bracer - Agility] (+5 Agility), will tip", the recipe as its link in
-- chat (an enchanter can click it) and as its name to copy.
local ASK = "LF Enchanter: %s (%s), will tip"

local function EnchantClicked(button)
    local spell = Enchants.Advise(button:GetParent().slot).now
    if not spell then return end
    local name, text = SpellName(spell), ns.BiSEnchants[spell].text or ""
    Parts.ShareMenu(button, "Ask for " .. name, function()
        return ASK:format(C_Spell.GetSpellLink(spell) or name, text)
    end, "Ask for " .. name, ASK:format(name, text), true, C_Spell.GetSpellTexture(spell))
end

-- The paperdoll's enchant mark: a small accent dot on a dark rim in a slot icon's top-right
-- corner (Forever's mark has the top-left, the item level the bottom-right), shown only while
-- a better enchant waits for what you wear there. Hovered, the advice; clicked, ask in Trade
-- or copy. Its parent is the slot's button, whose slot it reads; its hit area is a little
-- bigger than the dot, as the dot is small. With opts ({ color, tip }), a plain mark in that
-- colour saying tip on hover, for someone else's gear (the Naowh Inspect Panel's unenchanted
-- slots): no advice, no click.
local DOT, DOT_RIM, DOT_HIT, DOT_IN = 6, 2, 14, 3

local function TipEnter(badge)
    if not Parts.Tip(badge, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText(badge.tip, 1, 1, 1)
    GameTooltip:Show()
end

function B.View.EnchantBadge(button, opts)
    local badge = CreateFrame("Button", nil, button)
    badge:SetSize(DOT_HIT, DOT_HIT)
    badge:SetPoint("CENTER", button, "TOPRIGHT", -DOT_IN - DOT / 2, -DOT_IN - DOT / 2)
    badge:SetFrameLevel(button:GetFrameLevel() + 5)
    local rim = Parts.Smooth(badge:CreateTexture(nil, "ARTWORK"), St.ROUND)
    rim:SetSize(DOT + DOT_RIM * 2, DOT + DOT_RIM * 2)
    rim:SetPoint("CENTER")
    rim:SetVertexColor(0, 0, 0, 0.85)
    local dot = Parts.Smooth(badge:CreateTexture(nil, "OVERLAY"), St.ROUND)
    dot:SetSize(DOT, DOT)
    dot:SetPoint("CENTER")
    local color = opts and opts.color or T.accent
    dot:SetVertexColor(color.r, color.g, color.b)
    badge.tip = opts and opts.tip
    badge:SetScript("OnEnter", badge.tip and TipEnter or EnchantEnter)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    if not badge.tip then badge:SetScript("OnClick", EnchantClicked) end
    badge:Hide()
    return badge
end

function B.View.PaintEnchantBadge(badge, slot)
    badge:SetShown(Enchants.Advise(slot).todo == true)
end

-------------------------------------------------------------------------------
--  A slot's row: the slot, the BiS (Forever's mark after it when new in Forever), how much
--  stronger it makes you, the wand for what you wear there, where it drops and where you keep
--  it; on the right its picks
--  from two up, opening them under it, or + under the mouse for a first backup. A click opens
--  its picker, right-click the BiS's menu. What is yours has the check on its icon.
-------------------------------------------------------------------------------
local Picks = Memo("%d %s")

local function RowClicked(row, button)
    if button == "RightButton" then
        if row.bis then Parts.CopyWowhead("item", row.bis, C_Item.GetItemNameByID(row.bis)) end
        return
    end
    if row.bis and IsModifiedClick() then
        local _, link = GetItemInfo(row.bis)
        if link then HandleModifiedItemClick(link) end
        return
    end
    OpenPicker(row.slot, row)
end

local function RowEnter(row)
    row.hover:Show()
    row.add:SetShown(row.count == 1)
end

-- How much stronger it makes you, unless Stat Weights already says so on every tooltip.
local function GainTip(gain)
    if not gain or (ns.StatWeights and ns.StatWeights.On()) then return end
    local spec = B.Lists.CurrentSpec()
    GameTooltip:AddLine(Parts.UpgradeLine(gain, spec and spec.name))
end

local function SlotTipEnter(zone)
    local row = zone:GetParent()
    if row.bis then
        if not Tip(zone, "ANCHOR_CURSOR_RIGHT", 16, 0) then return end
        GameTooltip:SetItemByID(row.bis)
        ForeverTip(row.bis)
        local gains = row:GetParent().gains
        local gain = gains and gains[row.slot]
        GainTip(gain)
        GameTooltip:AddLine("Click: change picks" .. PLACE_DOT .. "Right-click: Wowhead link", T.muted.r, T.muted.g,
            T.muted.b)
        return GameTooltip:Show()
    end
    if not Tip(zone, "ANCHOR_TOP") then return end
    GameTooltip:SetText(ns.L(SLOT_NAME[row.slot]), 1, 1, 1)
    GameTooltip:AddLine("Click to pick its BiS.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function RowLeave(row)
    if row:IsMouseOver() then return end
    row.hover:Hide()
    row.add:Hide()
    GameTooltip:Hide()
end

local function ChildLeave(child)
    RowLeave(child:GetParent())
end

local function ToggleClicked(button)
    local row = button:GetParent()
    row:GetParent():Toggle(row.slot)
end

local function AddClicked(button)
    local row = button:GetParent()
    OpenPicker(row.slot, row)
end

Kinds.slotRow = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row:SetHeight(ROW_H)
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.05)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.lit = ns.Solid(row, "BACKGROUND", T.accent, 0.12)
        row.lit:SetAllPoints()
        row.lit:Hide()
        row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
        row.stripe:SetAllPoints()
        row.slotName = ns.Font(row, 12, nil, T.muted)
        row.slotName:SetPoint("LEFT", STATUS_W, 0)
        row.slotName:SetWidth(SLOT_W - 8)
        row.slotName:SetJustifyH("LEFT")
        row.slotName:SetWordWrap(false)
        local icon = Parts.ItemIcon(row, ROW_ICON)
        TipZone(row, icon, ROW_H, SlotTipEnter)
        icon:SetPoint("LEFT", STATUS_W + SLOT_W, 0)
        row.iconFrame, row.icon = icon, icon.texture
        row.toggle = CreateFrame("Button", nil, row)
        row.toggle:SetSize(TAIL_W, ROW_H)
        row.toggle:SetPoint("RIGHT", -INSET, 0)
        row.toggle.arrow = Parts.Arrow(row.toggle, 10, T.muted)
        row.toggle.arrow:SetPoint("RIGHT", 0, 0)
        row.toggle.text = ns.Font(row.toggle, 11, nil, T.muted)
        row.toggle.text:SetPoint("RIGHT", row.toggle.arrow, "LEFT", -4, 0)
        row.toggle:SetScript("OnClick", ToggleClicked)
        row.toggle:SetScript("OnLeave", ChildLeave)
        row.add = Parts.IconButton(row, AddClicked, St.PLUS, 0, "Add a backup pick")
        row.add:SetPoint("RIGHT", -INSET, 0)
        row.add:HookScript("OnLeave", ChildLeave)
        row.add:Hide()
        row.meta = ns.Font(row, 11, nil, T.muted)
        row.meta:SetPoint("RIGHT", -(TAIL_W + INSET + GAP), 0)
        row.meta:SetWidth(META_W)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)
        SourceZone(row)
        -- How much stronger it makes you, in a column of its own before where it drops, so the
        -- numbers line up down the list. (Its enchant is on the paperdoll, on its slot's icon.)
        GainCell(row, row.meta, GAP)
        row.worn = Parts.WornBar(row, 0)
        row.name = ns.Font(row, 12)
        row.name:SetPoint("LEFT", icon, "RIGHT", NAME_GAP, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", RowClicked)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        return row
    end,
    ---@param bis? number the slot's BiS
    ---@param count number its picks
    ---@param open boolean its backups shown under it
    Set = function(row, slot, bis, count, open)
        local view = row:GetParent()
        row.slot, row.bis, row.count = slot, bis, count
        row.hover:Hide()
        row.add:Hide()
        row.stripe:SetShown(view.striped)
        row.slotName:SetText(ns.L(SLOT_NAME[slot]))
        local gain = bis and view.gains and view.gains[slot]
        PaintGain(row.gain, gain, view.mostGain)
        -- The name runs on to the next thing there: the gain, or where it drops.
        row.name:SetPoint("RIGHT", gain and row.gain or row.meta, "LEFT", -GAP, 0)
        Parts.MarkForever(row.iconFrame, bis)
        row.toggle:SetShown(count > 1)
        if count > 1 then
            row.toggle.text:SetText(Picks(count, "picks"))
            row.toggle.arrow:SetRotation(open and -math.pi / 2 or 0)
        end
        if not bis then
            row.icon:SetTexture(select(2, C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot)))
            row.name:SetText(ns.Color("accentSoft", "Pick its BiS"))
            FitTip(row)
            row.meta:SetText("")
            FitSource(row, nil)
            row.worn:Hide()
            return ROW_H
        end
        local name = GetItemInfo(bis)
        if not name then view.waitingFor[bis] = true end
        local worn = Items.Wearing(slot, bis)
        row.icon:SetTexture(GetItemIconByID(bis))
        -- No star: every item in these rows is your BiS. The star marks ranks where they differ.
        row.name:SetText(Items.QualityHex(bis) .. (name or ("Item " .. bis)) .. "|r")
        FitTip(row)
        row.meta:SetText(Meta(bis, view.playerLevel) .. KeptTail(not worn and Items.Kept(bis) or ""))
        FitSource(row, bis)
        row.worn:SetShown(worn)
        return ROW_H, name == nil
    end,
}

-------------------------------------------------------------------------------
--  A pick: the item's icon, its name in its quality colour with its rank after it (and
--  before it, in a ranking, its place there), and under that a weapon's kind, where it drops
--  and the level it needs, then In Bag or In Bank; what is yours has the check on its icon. In
--  "list" and "own" mode its move and remove icons show on hover ("own": always); in "add"
--  mode a click adds it to the slot.
-------------------------------------------------------------------------------
local HINT = { list = "Right-click: Wowhead link" .. PLACE_DOT .. "Shift-click: link",
    own = "Right-click: Wowhead link" .. PLACE_DOT .. "Shift-click: link",
    add = "Click: add it" .. PLACE_DOT .. "Right-click: Wowhead link" }

local ORDER = {}   -- a ranking's place, muted, made once each

local function Order(order)
    local text = ORDER[order]
    if not text then
        text = ns.Color("muted", order .. ".") .. "  "
        ORDER[order] = text
    end
    return text
end

local function ShowActions(row, shown)
    local always = row.mode == "own"
    for _, button in ipairs(row.actions) do button:SetShown(row.canAct[button] and (always or shown)) end
end

local function PickEnter(row)
    row.hover:Show()
    ShowActions(row, true)
end

local function PickTipEnter(zone)
    local row = zone:GetParent()
    if row.mode ~= "add" or not row.rank then return ItemTip(zone, row.itemID, HINT[row.mode]) end
    if not Tip(zone, "ANCHOR_CURSOR_RIGHT", 16, 0) then return end
    GameTooltip:SetItemByID(row.itemID)
    ForeverTip(row.itemID)
    GameTooltip:AddLine(Parts.RankLine(row.rank))
    GameTooltip:Show()
end

local function PickLeave(row)
    if row:IsMouseOver() then return end
    row.hover:Hide()
    ShowActions(row, false)
    GameTooltip:Hide()
end

local function PickClicked(row, button)
    if button == "RightButton" then
        Parts.CopyWowhead("item", row.itemID, C_Item.GetItemNameByID(row.itemID))
        return
    end
    if IsModifiedClick() then
        local _, link = GetItemInfo(row.itemID)
        if link then HandleModifiedItemClick(link) end
    elseif row.mode == "add" then
        ns.AddBisPick(row.slot, row.itemID)
    end
end

local function MoveUp(button) ns.MoveBisPick(button.row.slot, button.row.itemID, -1) end
local function MoveDown(button) ns.MoveBisPick(button.row.slot, button.row.itemID, 1) end
local function Remove(button) ns.RemoveBisPick(button.row.slot, button.row.itemID) end

-- The icons keep the row lit while the mouse moves onto them.
local function ActionLeave(button)
    PickLeave(button.row)
end

local function Action(row, onClick, texture, tip)
    local button = Parts.IconButton(row, onClick, texture, 0, tip)
    button.row = row
    button:HookScript("OnLeave", ActionLeave)
    row.actions[#row.actions + 1] = button
    return button
end

Kinds.pick = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row:SetHeight(ITEM_H)
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.05)
        row.hover:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
        row.hover:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
        row.hover:Hide()
        row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
        row.stripe:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
        row.stripe:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
        row.worn = Parts.WornBar(row, CARD_PAD)
        local icon = Parts.ItemIcon(row, ICON)
        TipZone(row, icon, ITEM_H, PickTipEnter)
        icon:SetPoint("LEFT", 0, 0)
        row.iconFrame, row.icon = icon, icon.texture
        row.actions, row.canAct = {}, {}
        row.remove = Action(row, Remove, St.CROSS, "Remove")
        row.remove:SetPoint("RIGHT", 0, 0)
        row.down = Action(row, MoveDown, St.UP, "Move down")
        row.down.icon:SetTexCoord(0, 1, 1, 0)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -ACTION_GAP, 0)
        row.up = Action(row, MoveUp, St.UP, "Move up")
        row.up:SetPoint("RIGHT", row.down, "LEFT", -ACTION_GAP, 0)
        row.name = ns.Font(row, 12)
        row.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -NAME_TOP)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.meta = ns.Font(row, 11, nil, T.muted)
        row.meta:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, NAME_TOP)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)
        SourceZone(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", PickClicked)
        row:SetScript("OnEnter", PickEnter)
        row:SetScript("OnLeave", PickLeave)
        return row
    end,
    ---@param slot number
    ---@param itemID number
    ---@param rank? number its pick number in the slot
    ---@param mode "list"|"own"|"add"
    ---@param count? number the slot's picks
    ---@param order? number its place in a ranking
    Set = function(row, slot, itemID, rank, mode, count, order)
        local view = row:GetParent()
        row.slot, row.itemID, row.rank, row.mode = slot, itemID, rank, mode
        row.hover:Hide()
        row.stripe:SetShown(view.striped)
        -- Room for the move and remove icons on your own picks; one to add runs to the edge.
        local right = mode == "add" and 0 or ACTIONS_W
        row.name:SetPoint("RIGHT", right, 0)
        row.meta:SetPoint("RIGHT", right, 0)
        row.icon:SetTexture(GetItemIconByID(itemID))
        local name = GetItemInfo(itemID)
        if not name then view.waitingFor[itemID] = true end
        local worn = Items.Wearing(slot, itemID)
        row.worn:SetShown(worn)
        Parts.MarkForever(row.iconFrame, itemID)
        row.name:SetText((order and Order(order) or "") .. Items.QualityHex(itemID) .. (name or ("Item " .. itemID))
            .. "|r  " .. Parts.RankMark(rank, CARD_DROP))
        FitTip(row)
        row.meta:SetText(Meta(itemID, view.playerLevel) .. KeptTail(not worn and Items.Kept(itemID) or ""))
        FitSource(row, itemID)
        local mine = mode ~= "add"
        row.canAct[row.up] = mine and rank > 1
        row.canAct[row.down] = mine and rank < count
        row.canAct[row.remove] = mine
        ShowActions(row, false)
        return ITEM_H, name == nil
    end,
}

-------------------------------------------------------------------------------
--  A backup pick, opened under its slot's row and laid out as it, so the two read as one
--  list: its rank where the slot's name is (the silver star for your second pick), the item
--  with Forever's mark, how much stronger it makes you in the gain column, where it drops in
--  the source column; move and remove on hover, where the slot's picks count is.
-------------------------------------------------------------------------------
local ORDINAL = { "BiS", "2nd", "3rd" }
local backupRanks = {}

local function BackupRank(rank)
    local text = backupRanks[rank]
    if not text then
        text = Parts.RankMark(rank, CARD_DROP) .. " " .. ns.Color("muted", ORDINAL[rank] or (rank .. "th"))
        backupRanks[rank] = text
    end
    return text
end

Kinds.backup = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row:SetHeight(ROW_H)
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.05)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.rankText = ns.Font(row, 12, nil, T.muted)
        row.rankText:SetPoint("LEFT", STATUS_W + BACKUP_STEP, 0)
        row.trunk = ns.Solid(row, "ARTWORK", TREE_RGB, TREE_ALPHA)
        ns.Hairline(row.trunk, "v")
        row.branch = ns.Solid(row, "ARTWORK", TREE_RGB, TREE_ALPHA)
        ns.Hairline(row.branch, "h")
        row.elbow = row:CreateTexture(nil, "ARTWORK")
        row.elbow:SetTexture(St.ELBOW)
        row.elbow:SetSize(ELBOW, ELBOW)
        row.elbow:SetPoint("BOTTOMLEFT", row, "LEFT", TREE_X, -TREE_DROP - 1)
        row.elbow:SetVertexColor(TREE_RGB.r, TREE_RGB.g, TREE_RGB.b, TREE_ALPHA)
        local icon = Parts.ItemIcon(row, ROW_ICON)
        TipZone(row, icon, ROW_H, PickTipEnter)
        icon:SetPoint("LEFT", STATUS_W + SLOT_W, 0)
        row.iconFrame, row.icon = icon, icon.texture
        row.actions, row.canAct = {}, {}
        row.remove = Action(row, Remove, St.CROSS, "Remove")
        row.remove:SetPoint("RIGHT", -INSET, 0)
        row.down = Action(row, MoveDown, St.UP, "Move down")
        row.down.icon:SetTexCoord(0, 1, 1, 0)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -ACTION_GAP, 0)
        row.up = Action(row, MoveUp, St.UP, "Move up")
        row.up:SetPoint("RIGHT", row.down, "LEFT", -ACTION_GAP, 0)
        row.meta = ns.Font(row, 11, nil, T.muted)
        row.meta:SetPoint("RIGHT", -(TAIL_W + INSET + GAP), 0)
        row.meta:SetWidth(META_W)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)
        SourceZone(row)
        GainCell(row, row.meta, GAP)
        row.worn = Parts.WornBar(row, 0)
        row.name = ns.Font(row, 12)
        row.name:SetPoint("LEFT", icon, "RIGHT", NAME_GAP, 0)
        row.name:SetPoint("RIGHT", row.gain, "LEFT", -GAP, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", PickClicked)
        row:SetScript("OnEnter", PickEnter)
        row:SetScript("OnLeave", PickLeave)
        return row
    end,
    ---@param slot number
    ---@param itemID number
    ---@param rank number its pick number in the slot, 2 and up
    ---@param count number the slot's picks
    Set = function(row, slot, itemID, rank, count)
        local view = row:GetParent()
        row.slot, row.itemID, row.rank, row.mode = slot, itemID, rank, "list"
        row.hover:Hide()
        row.rankText:SetText(BackupRank(rank))
        -- The first reaches up into the slot's row; the last turns into its branch on the
        -- rounded corner, the others go on down past theirs.
        local up, last = rank == 2 and TREE_UP or 0, rank == count
        local corner = last and ELBOW or 0
        row.trunk:ClearAllPoints()
        row.trunk:SetPoint("TOPLEFT", TREE_X, up)
        row.trunk:SetHeight(last and up + ROW_H / 2 + TREE_DROP - ELBOW + 1 or up + ROW_H)
        row.elbow:SetShown(last)
        row.branch:ClearAllPoints()
        row.branch:SetPoint("TOPLEFT", row, "LEFT", TREE_X + corner, -TREE_DROP)
        row.branch:SetWidth(STATUS_W + BACKUP_STEP - TREE_GAP - TREE_X - corner)
        row.icon:SetTexture(GetItemIconByID(itemID))
        local name = GetItemInfo(itemID)
        if not name then view.waitingFor[itemID] = true end
        local worn = Items.Wearing(slot, itemID)
        row.worn:SetShown(worn)
        Parts.MarkForever(row.iconFrame, itemID)
        row.name:SetText(Items.QualityHex(itemID) .. (name or ("Item " .. itemID)) .. "|r")
        FitTip(row)
        PaintGain(row.gain, B.Upgrades.Gain(itemID, slot), view.mostGain)
        row.meta:SetText(Meta(itemID, view.playerLevel) .. KeptTail(not worn and Items.Kept(itemID) or ""))
        FitSource(row, itemID)
        row.canAct[row.up] = rank > 2
        row.canAct[row.down] = rank < count
        row.canAct[row.remove] = true
        ShowActions(row, false)
        return ROW_H, name == nil
    end,
}

-------------------------------------------------------------------------------
--  A place to run next: a pin and the place, a dungeon's levels (red while above yours) and
--  your quests there from the Dungeon Journal, how many of your BiS are there and Open or Map;
--  under them the slots and who drops them, and out in the world where they stand. Hover lists
--  the items; a click opens the dungeon in the Journal, or puts a waypoint on whoever has your
--  BiS and shows it on your map.
-------------------------------------------------------------------------------
local QuestsText = Memo("%d %s")
local dungeonsByName

local function JournalDungeon(name)
    local J = ns.Journal
    if not (J and ns.OpenJournalWindow) then return nil end
    if not dungeonsByName then
        dungeonsByName = {}
        for _, dungeon in ipairs(J.Dungeons()) do dungeonsByName[dungeon.name] = dungeon end
    end
    return dungeonsByName[name]
end

-- The Journal or the world map takes the BiS List's place until it closes.
local function Go(row)
    local spot = row.spot
    -- A quest, a craft or a faction's reward: where its item's source goes.
    if row.place.via then return B.Sources.Go(row.place.via) end
    if row.dungeon then
        B.StepAside("journal")
        ns.OpenJournalWindow(row.dungeon, B.BackFromJournal, "Back to BiS List")
        return
    end
    if spot then
        local name = C_Item.GetItemNameByID(row.spotItem)
        ns.PlaceWaypoint(spot.name, spot.map, spot.x, spot.y, name and " (" .. name .. ")")
    end
    if Places.ShowMap(row.map) then B.StepAside("map") end
end

local function GoLink(link)
    Go(link:GetParent())
end

local counts, details = {}, {}

local function Count(bis)
    local text = counts[bis]
    if not text then
        text = STAR_MARK .. " " .. bis
        counts[bis] = text
    end
    return text
end

-- Who drops (or sells) the slot's BiS there, its name (nil until loaded) and where they stand.
local function Drop(list, slot)
    local id = list.slots[slot]
    local _, who = R.Place(ns.BiSSource(id) or UNKNOWN)
    return who, C_Item.GetItemNameByID(id), ns.BiSSpots[id]
end

-- "Swiftmane drops", "Grazlix sells".
local function Has(who, spot)
    return who .. (spot and spot.sells and " sells" or " drops")
end

-- "around 60.7, 32.9" where its spawns spread out, else "at 62.2, 38.4".
local function Where(spot)
    return ("%s %.1f, %.1f"):format(spot.roams and "around" or "at", spot.x, spot.y)
end

-- The first of the place's BiS with a spot, and that spot.
local function FirstSpot(place, list)
    for _, slot in ipairs(place.slots) do
        local id = list.slots[slot]
        if ns.BiSSpots[id] then return id, ns.BiSSpots[id] end
    end
end

-- In a dungeon, "Shoulder, Back, Hands . Lady Anacondra, Skum"; anywhere else what to do there,
-- "Swiftmane drops Signet of the Zhevra (Ring 2) around 60.7, 32.9". Made once per place and items.
-- What a quest, a craft or a faction gives you, before its items; and its link.
local VIA_LINKS = { quest = "Quest", recipe = "Recipe", faction = "Open" }
local VIA_WORDS = { quest = "Rewards ", recipe = "Crafts ", faction = "Sells " }

local function Detail(place, list, dungeon)
    local byKey = details[place.name]
    if not byKey then
        byKey = {}
        details[place.name] = byKey
    end
    local text = byKey[place.key]
    if text then return text end
    local parts, who, seen, loaded = {}, {}, {}, true
    for i, slot in ipairs(place.slots) do
        local boss, name, spot = Drop(list, slot)
        loaded = loaded and name ~= nil
        if place.kind then
            parts[i] = (name or "your BiS") .. " (" .. ns.L(SLOT_NAME[slot]) .. ")"
        elseif dungeon then
            parts[i] = ns.L(SLOT_NAME[slot])
            if boss and not seen[boss] then
                seen[boss] = true
                who[#who + 1] = boss
            end
        else
            parts[i] = (boss and Has(boss, spot) .. " " or "") .. (name or "your BiS")
                .. " (" .. ns.L(SLOT_NAME[slot]) .. ")" .. (spot and " " .. Where(spot) or "")
        end
    end
    if place.kind then
        text = VIA_WORDS[place.kind] .. table.concat(parts, ", ")
    else
        text = dungeon and table.concat(parts, ", ") .. (who[1] and PLACE_DOT .. table.concat(who, ", ") or "")
            or table.concat(parts, "; ")
    end
    if loaded then byKey[place.key] = text end
    return text
end

-- A dungeon's levels: red while above yours, muted once you are past them.
local function Levels(dungeon, playerLevel)
    local range = ns.Journal.LevelRange(dungeon)
    if not range then return "" end
    local levels = ns.Journal.Levels(dungeon)
    if playerLevel < levels[1] then return RED_CODE .. range .. "|r" end
    if playerLevel > levels[2] then return ns.Color("muted", range) end
    return range
end

local function PlaceEnter(row)
    row.hover:Show()
    local list = row:GetParent().list
    if not Tip(row, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText(row.place.name, 1, 1, 1)
    if row.dungeon and row.dungeon.new then GameTooltip:AddLine(Parts.ForeverLine()) end
    for _, slot in ipairs(row.place.slots) do
        local id = list.slots[slot]
        GameTooltip:AddDoubleLine(Parts.RankMark(1) .. " " .. Items.QualityHex(id) .. Items.Name(id) .. "|r",
            ns.L(SLOT_NAME[slot]), 1, 1, 1, T.muted.r, T.muted.g, T.muted.b)
        local who, _, spot = Drop(list, slot)
        if who and not (row.dungeon or row.place.via) then
            GameTooltip:AddLine(("%s it %s."):format(Has(who, spot), spot and Where(spot) or "in " .. row.place.name),
                T.muted.r, T.muted.g, T.muted.b)
        end
    end
    local via = row.place.via
    local hint = via and B.Sources.Hint(via)
        or row.dungeon and "Click to open it in the Dungeon Journal."
        or row.spot and ("Click to put a waypoint on %s."):format(row.spot.name)
        or row.map and ("Click to show %s on your map."):format(row.place.name)
    if hint then GameTooltip:AddLine(hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Show()
end

local function PlaceLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

Kinds.place = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.05)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.pin = row:CreateTexture(nil, "ARTWORK")
        row.pin:SetTexture(St.PIN)
        row.pin:SetSize(ACTION, ACTION)
        row.pin:SetPoint("TOPLEFT", INSET, -4)
        row.pin:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        row.name = ns.Font(row, 13, nil, T.fg)
        row.name:SetPoint("TOPLEFT", row.pin, "TOPRIGHT", 8, 0)
        row.levels = ns.Font(row, 12, nil, T.fg)
        row.levels:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.quests = ns.Font(row, 12, nil, T.muted)
        row.quests:SetPoint("LEFT", row.levels, "RIGHT", 10, 0)
        -- On the right, in columns of their own so they line up down the list: your BiS there
        -- (the star, then how many), how much stronger they make you, and the link, its arrow
        -- at the edge.
        row.open = Parts.Link(row, GoLink, true)
        row.open:SetPoint("TOPRIGHT", -INSET, -2)
        local linkSlot = CreateFrame("Frame", nil, row)
        linkSlot:SetSize(PLACE_LINK_W, 16)
        linkSlot:SetPoint("TOPRIGHT", -INSET, -2)
        GainCell(row, linkSlot, PLACE_GAP)
        row.count = ns.Font(row, 12, nil, T.fg)
        row.count:SetPoint("RIGHT", row.gain, "LEFT", -PLACE_GAP, 0)
        row.count:SetWidth(PLACE_COUNT_W)
        row.count:SetJustifyH("LEFT")
        row.detail = ns.Font(row, 11, nil, T.muted)
        row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.detail:SetPoint("RIGHT", -INSET, 0)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)
        row:SetScript("OnClick", Go)
        row:SetScript("OnEnter", PlaceEnter)
        row:SetScript("OnLeave", PlaceLeave)
        return row
    end,
    ---@param place { name: string, bis: number, slots: number[], mask: number, key: number }
    Set = function(row, place)
        local view = row:GetParent()
        row.place = place
        row.count:SetText(Count(place.bis))
        PaintGain(row.gain, place.gain > 0 and place.gain or nil, view.mostPlaceGain)
        row.dungeon = not place.via and JournalDungeon(place.name) or nil
        row.name:SetText(row.dungeon and row.dungeon.new and place.name .. Parts.ForeverInline(11, CARD_DROP)
            or place.name)
        local dungeon = row.dungeon
        row.spotItem, row.spot = nil, nil
        if not (dungeon or place.via) then row.spotItem, row.spot = FirstSpot(place, view.list) end
        row.map = not (dungeon or place.via) and (row.spot and row.spot.map or Places.Zone(place.name)) or nil
        row.detail:SetText(Detail(place, view.list, dungeon))
        row.levels:SetText(dungeon and Levels(dungeon, view.playerLevel) or "")
        local quests = 0
        if dungeon and dungeon.quests then
            local toPickUp, inLog = ns.Journal.Quests.Count(dungeon.quests)
            quests = toPickUp + inLog
        end
        row.quests:SetText(quests > 0 and QuestsText(quests, quests == 1 and "quest" or "quests") or "")
        row.open:SetShown(dungeon ~= nil or row.map ~= nil or place.via ~= nil)
        Parts.SetLink(row.open, VIA_LINKS[place.kind] or dungeon and "Open" or row.spot and "Waypoint" or "Map")
        return PLACE_H
    end,
}
