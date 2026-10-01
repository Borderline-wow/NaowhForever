-------------------------------------------------------------------------------
--  View/BossCards.lua -- a boss as a card: the card itself; its header (kill order, name,
--  Naowh's tip behind an (i), and what it holds for you); sharing a tip in chat; and the
--  chips of the bosses with nothing for you at the end of the page.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal

local St = J.Style
local TIP_RGB, INFO = St.TIP_RGB, St.INFO
local BORDER_RGB, SKULL, CROSS = St.BORDER_RGB, St.SKULL, St.CROSS
local CARD_FILL, BADGE, BOSS_HEADER_H, BOSS_NAME_SIZE = St.CARD_FILL, St.BADGE, St.BOSS_HEADER_H, St.BOSS_NAME_SIZE
local TIP_ICON, CHIP_H, CHIP_PAD, CHIP_GAP = St.TIP_ICON, St.CHIP_H, St.CHIP_PAD, St.CHIP_GAP

local Kinds = J.View.Kinds
local Kills = J.Kills
local S = J.Settings

local CHAT_MAX = 255        -- what chat takes in one message
local NAME_TOP = 11         -- the boss's name from the card's top; the badge sits 2 higher
local STATS_TOP = 13
local RARE_W = 42           -- "RARE" and its gap
local CHIP_TIP_W = 17       -- the (i) in a chip, and its gap
local CHIP_BOTTOM = 4
local CLEAR_ICON = 10       -- the x after "Nothing for your class"
local CLEAR_BOX = 18        -- what it answers to the mouse; level with the title's letters by KILL_DROP
local KILL_ICON = 14        -- the skull
local KILL_GAP = 3          -- the skull to its count
local KILLS_GAP = 12        -- the kill count to what the boss holds for you, left of it
-- Letters sit under the middle of their font string (the Naowh font leaves room above its
-- capitals): the x after a line of text goes this much under it, level with them. PIN_DROP
-- is 2 at the title's size 20; this is the same at size 11. The skull needs none: centred on
-- its count, it is level with the digits (measured in game, 2026-09-30; with this drop it sat
-- a pixel low).
local KILL_DROP = 1
local KILL_DATE, GOLD_CODE = St.KILL_DATE, St.GOLD_CODE

-- A boss's card: under its header and its loot, a level below them so they draw on top.
-- Placed only (no Set); its black edge turns the accent while the boss is clicked.
Kinds.card = {
    New = function(view)
        local card = CreateFrame("Frame", nil, view)
        ns.Solid(card, "BACKGROUND", T.fg, CARD_FILL):SetAllPoints()
        card.edge = ns.Border(card, BORDER_RGB)
        return card
    end,
}

-------------------------------------------------------------------------------
--  Naowh's tips: read on hover, shared in chat on a click
-------------------------------------------------------------------------------
local TIP_TEXT = "Naowh's tip for %s: %s"

-- For chat: cut to what one message takes.
local function TipMessage(boss, tip)
    local text = TIP_TEXT:format(boss.name, tip)
    if #text > CHAT_MAX then text = text:sub(1, CHAT_MAX - 3) .. "..." end
    return text
end

-- Shared from the share menu (Parts.ShareMenu): cut to one message in chat, whole to copy.
local function OpenTipMenu(button)
    local tip = button.tip
    if not tip then return end
    local name = button.boss.name
    J.View.Parts.ShareMenu(button, "Share Naowh's tip", TipMessage(button.boss, tip),
        "Naowh's tip: " .. name, TIP_TEXT:format(name, tip))
end

local function AddTip(tip)
    GameTooltip:AddLine("Naowh's tip", TIP_RGB.r, TIP_RGB.g, TIP_RGB.b)
    GameTooltip:AddLine(tip, 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: share in chat", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
end

local function TipEnter(button)
    button.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    AddTip(button.tip)
    GameTooltip:Show()
end

local function TipLeave(button)
    button.icon:SetVertexColor(TIP_RGB.r, TIP_RGB.g, TIP_RGB.b)
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
--  The kill count: a skull and how many times this character has killed the boss, 0 too;
--  hover for when, the latest first, and how long each fight took. A boss whose death the
--  game does not report (a rare) has a dash, and hover says why. A click opens the boss's
--  history in the side panel: each kill, who was with you, and what dropped.
-------------------------------------------------------------------------------
local OPEN_HISTORY = "Click for each kill: who was with you, what dropped and who won it."

local function PaintKills(button)
    local color = button.kills > 0 and T.fg or T.muted
    button.icon:SetVertexColor(color.r, color.g, color.b)
    button.count:SetTextColor(color.r, color.g, color.b)
end

local FightLength = J.View.Parts.FightLength

local function KillsEnter(button)
    local accent, muted = T.accent, T.muted
    button.icon:SetVertexColor(accent.r, accent.g, accent.b)
    local boss = button.boss
    local record = Kills.Record(boss)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    if not Kills.Counted(boss) then
        GameTooltip:AddLine(J.View.BossPanel.NotCounted(button:GetParent():GetParent().dungeon),
            muted.r, muted.g, muted.b, true)
        GameTooltip:AddLine("Click for what you looted from it.", T.accentSoft.r, T.accentSoft.g,
            T.accentSoft.b, true)
        GameTooltip:Show()
        return
    elseif not record then
        GameTooltip:AddLine("Not killed yet on this character.", muted.r, muted.g, muted.b)
    else
        GameTooltip:AddLine(record.n == 1 and "Killed once on this character."
            or ("Killed %d times on this character."):format(record.n), 1, 1, 1)
        local best, bestAt = Kills.Best(record)
        if best then
            GameTooltip:AddDoubleLine(GOLD_CODE .. "Record|r " .. FightLength(best), date(KILL_DATE, bestAt),
                1, 1, 1, muted.r, muted.g, muted.b)
        end
        local at, took = record.at, record.took
        GameTooltip:AddLine(" ")
        for i = #at, 1, -1 do
            if type(at[i]) == "number" then
                local length = took[i]
                GameTooltip:AddDoubleLine(date(KILL_DATE, at[i]),
                    type(length) == "number" and FightLength(length) or "", 1, 1, 1, muted.r, muted.g, muted.b)
            end
        end
        if record.n > #at and type(record.first) == "number" then
            GameTooltip:AddLine(("The latest %d. First counted: %s."):format(#at, date(KILL_DATE, record.first)),
                muted.r, muted.g, muted.b)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Kills count while the Dungeon Journal is on.", muted.r, muted.g, muted.b, true)
    GameTooltip:AddLine(OPEN_HISTORY, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, true)
    GameTooltip:Show()
end

-- The view's dungeon is the card's, outside a search.
local function OpenHistory(button)
    J.View.BossPanel.Show(button.boss, button, button:GetParent():GetParent().dungeon)
end

local function KillsLeave(button)
    PaintKills(button)
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
--  The card's header
-------------------------------------------------------------------------------
-- Hover lights the name and says what a click does; the fading is the click's, so moving
-- across a card changes nothing.
local function BossEnter(row)
    row.hovered = true
    local view = row:GetParent()
    view:ApplyPin()
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT", 16, 0)
    GameTooltip:SetText(view.pinned == row.boss and "Click to show all its loot again"
        or "Click to show only its BiS and upgrades", 1, 1, 1)
    GameTooltip:Show()
end

local function BossLeave(row)
    row.hovered = false
    row:GetParent():ApplyPin()
    GameTooltip:Hide()
end

local function BossClicked(row)
    row:GetParent():Pin(row.boss)
    BossEnter(row)   -- the hint follows the click
end

-- When none of its loot is listed, why; nothing otherwise (each item shows its own marks).
local function EmptyText(shown, boss)
    if shown > 0 then return "" end
    return ns.Color("muted", boss.loot and "Nothing for your class" or "No loot known yet")
end

-- Its place in the kill order in a small badge (none for a rare, which says RARE instead),
-- its name with Naowh's tip as an (i) after it, and on the right its kill count (and why,
-- when none of its loot is listed); then a hairline over the loot.
Kinds.boss = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.badge = CreateFrame("Frame", nil, row)
        row.badge:SetSize(BADGE, BADGE)
        row.badge:SetPoint("TOPLEFT", 0, -(NAME_TOP - 2))
        ns.Solid(row.badge, "BACKGROUND", T.bg, 0.8):SetAllPoints()
        ns.Border(row.badge, BORDER_RGB)
        row.number = ns.Font(row.badge, 11, nil, T.fg)
        row.number:SetPoint("CENTER", 0, 0)
        row.name = ns.Font(row, BOSS_NAME_SIZE, nil, T.fg)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.rare = ns.Font(row, 10, nil, T.muted)
        row.rare:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.rare:SetText("RARE")
        row.tipButton = CreateFrame("Button", nil, row)
        row.tipButton:SetSize(TIP_ICON + 4, TIP_ICON + 4)
        row.tipButton.icon = row.tipButton:CreateTexture(nil, "ARTWORK")
        row.tipButton.icon:SetTexture(INFO)
        row.tipButton.icon:SetSize(TIP_ICON, TIP_ICON)
        row.tipButton.icon:SetPoint("CENTER")
        row.tipButton.icon:SetVertexColor(TIP_RGB.r, TIP_RGB.g, TIP_RGB.b)
        row.tipButton:SetScript("OnEnter", TipEnter)
        row.tipButton:SetScript("OnLeave", TipLeave)
        row.tipButton:SetScript("OnClick", OpenTipMenu)
        row.stats = ns.Font(row, 11)
        row.stats:SetJustifyH("RIGHT")
        local kills = CreateFrame("Button", nil, row)
        kills:SetHeight(KILL_ICON + 4)
        kills:SetPoint("RIGHT", row, "TOPRIGHT", 0, -(STATS_TOP + 6))
        kills.icon = kills:CreateTexture(nil, "ARTWORK")
        kills.icon:SetTexture(SKULL)
        kills.icon:SetSize(KILL_ICON, KILL_ICON)
        kills.icon:SetPoint("LEFT")
        kills.count = ns.Font(kills, 11)
        kills.count:SetPoint("LEFT", kills.icon, "RIGHT", KILL_GAP, 0)
        kills:SetScript("OnEnter", KillsEnter)
        kills:SetScript("OnLeave", KillsLeave)
        kills:SetScript("OnClick", OpenHistory)
        row.kills = kills
        row.rule = ns.Solid(row, "ARTWORK", T.line, 0.7)
        row.rule:SetPoint("BOTTOMLEFT")
        row.rule:SetPoint("BOTTOMRIGHT")
        row.rule:SetHeight(1)
        row:SetScript("OnEnter", BossEnter)
        row:SetScript("OnLeave", BossLeave)
        row:SetScript("OnMouseUp", BossClicked)
        return row
    end,
    ---@param boss JournalBoss
    ---@param number? number its place in the kill order; nil for a rare or in a search
    ---@param shown number how many of its items are listed
    Set = function(row, boss, number, shown)
        local view = row:GetParent()
        row.boss, row.hovered = boss, false
        -- Clickable only once its items are in (the view's DrawBoss), and only with
        -- something to light.
        row:EnableMouse(false)
        row.badge:SetShown(number ~= nil)
        row.number:SetText(number or "")
        local left = number and BADGE + 8 or 0
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", left, -NAME_TOP)
        row.name:SetWidth(0)   -- unbounded, so it measures the whole name
        row.name:SetText(boss.name)
        row.rare:SetShown(boss.rare == true)
        row.stats:SetText(EmptyText(shown, boss))
        local kills = row.kills
        local showKills = view.showKills
        kills:SetShown(showKills)
        row.stats:ClearAllPoints()
        local right = 0   -- what the kill count takes on the right
        if showKills then
            kills.boss, kills.kills = boss, Kills.Count(boss)
            kills.count:SetText(Kills.Counted(boss) and kills.kills or "-")
            PaintKills(kills)
            kills:SetWidth(KILL_ICON + KILL_GAP + math.ceil(kills.count:GetStringWidth()))
            row.stats:SetPoint("RIGHT", kills, "LEFT", -KILLS_GAP, 0)
            right = kills:GetWidth() + KILLS_GAP
        else
            row.stats:SetPoint("TOPRIGHT", 0, -STATS_TOP)
        end
        local tip = view.showTips and J.Tip(boss) or nil
        local button = row.tipButton
        button.boss, button.tip = boss, tip
        button:SetShown(tip ~= nil)
        button:ClearAllPoints()
        button:SetPoint("LEFT", boss.rare and row.rare or row.name, "RIGHT", 4, 0)
        local after = (boss.rare and RARE_W or 0) + (tip and TIP_ICON + 10 or 0)
        row.name:SetWidth(math.min(math.ceil(row.name:GetStringWidth()) + 1,
            row:GetWidth() - left - after - right - math.ceil(row.stats:GetStringWidth()) - 12))
        row.rule:SetShown(shown > 0)
        return BOSS_HEADER_H
    end,
}

-------------------------------------------------------------------------------
--  The bosses with nothing for you, as chips at the end
-------------------------------------------------------------------------------
-- Each boss as a small chip, its number and name, with Naowh's (i) when it has a tip. Hover
-- says why it is folded away and shows the tip; a click shares the tip, as the (i) on a
-- card does. The chips run on and wrap.
local function ChipEnter(chip)
    chip.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
    GameTooltip:SetOwner(chip, "ANCHOR_TOP")
    GameTooltip:SetText(chip.boss.name, 1, 1, 1)
    GameTooltip:AddLine(chip.reason, T.muted.r, T.muted.g, T.muted.b)
    if chip.tip then
        GameTooltip:AddLine(" ")
        AddTip(chip.tip)
    end
    GameTooltip:Show()
end

local function ChipLeave(chip)
    chip.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Hide()
end

local function BossChip(row)
    local chip = CreateFrame("Button", nil, row)
    chip:SetHeight(CHIP_H)
    ns.Solid(chip, "BACKGROUND", T.fg, 0.04):SetAllPoints()
    ns.Border(chip, BORDER_RGB)
    chip.label = ns.Font(chip, 11, nil, T.muted)
    chip.label:SetPoint("LEFT", CHIP_PAD, 0)
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetTexture(INFO)
    chip.icon:SetSize(12, 12)
    chip.icon:SetPoint("LEFT", chip.label, "RIGHT", 5, 0)
    chip.icon:SetVertexColor(TIP_RGB.r, TIP_RGB.g, TIP_RGB.b)
    chip:SetScript("OnEnter", ChipEnter)
    chip:SetScript("OnLeave", ChipLeave)
    chip:SetScript("OnClick", OpenTipMenu)
    return chip
end

-- The x after the title: turns off the filter that folded them away, so their loot shows.
local function OptionLabel(key)
    for _, group in ipairs(J.OPTION_GROUPS) do
        for _, option in ipairs(group.options) do
            if option.key == key then return option.label end
        end
    end
    return key
end

local function ClearEnter(button)
    button.icon:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText("Show their loot", 1, 1, 1)
    GameTooltip:AddLine(("Turns off %s."):format(OptionLabel(button.filterKey)), T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function ClearLeave(button)
    button.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Hide()
end

local function ClearClicked(button)
    GameTooltip:Hide()
    S.Set(button.filterKey, false)
end

Kinds.skipped = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.title = ns.Font(row, 11, nil, T.muted)
        local clear = CreateFrame("Button", nil, row)
        clear:SetSize(CLEAR_BOX, CLEAR_BOX)
        clear:SetPoint("LEFT", row.title, "RIGHT", 0, -KILL_DROP)
        clear.icon = clear:CreateTexture(nil, "ARTWORK")
        clear.icon:SetTexture(CROSS)
        clear.icon:SetSize(CLEAR_ICON, CLEAR_ICON)
        clear.icon:SetPoint("CENTER")
        clear.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
        clear:SetScript("OnEnter", ClearEnter)
        clear:SetScript("OnLeave", ClearLeave)
        clear:SetScript("OnClick", ClearClicked)
        row.clear = clear
        row.chips = {}
        return row
    end,
    ---@param title string why they are here ("Nothing for your class")
    ---@param filterKey string the setting that folded them away, which the x turns off
    ---@param bosses JournalBoss[]
    ---@param labels string[] each boss's "1 Rhahk'Zor"
    Set = function(row, title, filterKey, bosses, labels)
        local showTips = row:GetParent().showTips
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row, "TOPLEFT", 0, -CHIP_H / 2)
        row.title:SetText(title)
        row.clear.filterKey = filterKey
        local width = row:GetWidth()
        local x, y = math.ceil(row.title:GetStringWidth()) + CLEAR_BOX + CHIP_GAP, 0
        for i = 1, #bosses do
            local boss = bosses[i]
            local chip = row.chips[i] or BossChip(row)
            row.chips[i] = chip
            chip.boss, chip.reason = boss, title
            chip.tip = showTips and J.Tip(boss) or nil
            chip.label:SetText(labels[i])
            chip.icon:SetShown(chip.tip ~= nil)
            local w = CHIP_PAD * 2 + math.ceil(chip.label:GetStringWidth()) + (chip.tip and CHIP_TIP_W or 0)
            chip:SetWidth(w)
            if x + w > width and x > 0 then
                x, y = 0, y + CHIP_H + CHIP_GAP
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", x, -y)
            chip:Show()
            x = x + w + CHIP_GAP
        end
        for i = #bosses + 1, #row.chips do row.chips[i]:Hide() end
        return y + CHIP_H + CHIP_BOTTOM
    end,
}
