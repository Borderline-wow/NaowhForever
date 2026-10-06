-------------------------------------------------------------------------------
--  View/BossDetails.lua -- the rows of a boss's own page beside its loot: the stacked page
--  (ViewMixin:DrawBossLoot, each list in a card of its own) and the dungeon map's compact one
--  (ViewMixin:DrawBossPage, on a dense view: shorter rows, one line each):
--
--  - bossHeader: the stacked page's top, as a dungeon's is: its name, large, with its kill
--    count on the right; under it its title, level and classification and creature type, as
--    its Wowhead Forever page has them (Data/BossInfo.lua).
--  - bossTitle: the compact page's top, on one line: its name, large, then the same muted,
--    and its kill count on the right.
--  - tip: Naowh's tip (Data/Tips.lua), written out beside the Naowh mark (a loot icon's
--    size, smaller when dense), at the top of the page; the chat bubble on its right shares
--    it (Say, Party, Raid, Guild, your target).
--  - bossQuest: a dungeon quest that needs the boss (Data/BossQuests.lua): its name in the
--    quest log's color for where it stands for you, and on the right that state in words,
--    a tick once it is done. Its tooltip says where it starts.
--  - questChips: the same quests as chips on one line (wrapping when they do not fit), each
--    its name in that color and its state, for the compact page.
--  - ability: one of its abilities (Data/Abilities.lua): its icon in a black border, its
--    name, and under it, muted, what the game says it does: wrapped, or when dense cut short
--    on two lines (view.abilityLines 2: the page has the room) or one. Its tooltip is the
--    game's, whole, and Shift-click links it. A spell the client has not loaded yet draws
--    again once it has, as an item's name does.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal

local GetSpellName = C_Spell.GetSpellName
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellDescription = C_Spell.GetSpellDescription
local IsSpellDataCached = C_Spell.IsSpellDataCached
local GetSpellLink = C_Spell.GetSpellLink

local Quests = J.Quests

local St = J.Style
local TITLE_SIZE, TITLE_H, TITLE_GAP = St.TITLE_SIZE, St.TITLE_H, St.TITLE_GAP
local WHERE_H, HEADER_PAD, PLACE_DOT = St.WHERE_H, St.HEADER_PAD, St.PLACE_DOT
local HEADER_TOP = 8   -- over the name: room from the panel's edge, as the cards keep inside theirs
local CARD_PAD, QUEST_CODE, HAVE_RGB, CHECK = St.CARD_PAD, St.QUEST_CODE, St.HAVE_RGB, St.CHECK
local HOVER = St.HOVER
local KILLS_GAP = 10      -- the name to the kill count on its right

local View = J.View
local Kinds, Parts = View.Kinds, View.Parts

local ICON = St.ICON      -- as big as a loot icon
local TEXT_GAP = 8        -- the icon to its name and description
local NAME_DESC_GAP = 2
local ROW_PAD = 5         -- above and under each ability
local QUESTION = 134400   -- the game's question mark, for a spell with no icon
local MARK = 14           -- the Naowh mark beside the tip; a done quest's tick
local QUEST_H = 22
local STATE_W = 120       -- a quest's state, on the right
local TICK_GAP = 4        -- a done quest's tick to its state
local SHARE = St.ACTION   -- the tip's share button
local TIP_MARK = St.ICON  -- the Naowh mark beside the tip, as big as a loot icon
local DENSE_H, DENSE_TALL_H, DENSE_ICON = St.DENSE_H, St.DENSE_TALL_H, St.DENSE_ICON
local DENSE_TALL_TOP = 4
local TALL_LINES = 2
local DENSE_PAD = St.CARD_BOTTOM
local DENSE_NAME_TOP = 1
local TITLE_LINE_TOP = 2
local TITLE_LINE_PAD = 4
local ABOUT_GAP = 10
local ABOUT_RISE = 2
local CHIP_H, CHIP_PAD, CHIP_GAP = St.CHIP_H, St.CHIP_PAD, St.CHIP_GAP
local CHIP_FILL = 0.04
local STATE_GAP = 6
local QUESTS_LABEL = "QUESTS"
local BUBBLE = "Interface\\GossipFrame\\GossipGossipIcon"
local LINK_HINT = "Shift-click: link"

-------------------------------------------------------------------------------
--  The page's header
-------------------------------------------------------------------------------
-- Data/BossInfo.lua's numbers, as Wowhead has them.
local CLASSIFICATION = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local CREATURE_TYPE = {
    [1] = "Beast", [2] = "Dragonkin", [3] = "Demon", [4] = "Elemental", [5] = "Giant", [6] = "Undead",
    [7] = "Humanoid", [8] = "Critter", [9] = "Mechanical", [11] = "Totem", [15] = "Aberration",
}

-- "Level 16 Elite", "Level 15-16", "Level ?? Boss".
local function LevelText(info)
    local low, high = info[1], info[2]
    local level = (high < 0 or low < 0) and "??" or low == high and tostring(low) or (low .. "-" .. high)
    local kind = CLASSIFICATION[info[3]]
    return "Level " .. ns.Color("fg", level) .. (kind and " " .. kind or "")
end

-- Its title, its level and kind, its creature type; what Wowhead has of them.
local parts = {}

local function AboutText(boss)
    local info = boss.npc and J.BossInfo[boss.npc]
    wipe(parts)
    if info then
        if info[5] then parts[#parts + 1] = ns.Color("fg", info[5]) end
        parts[#parts + 1] = LevelText(info)
        if CREATURE_TYPE[info[4]] then parts[#parts + 1] = CREATURE_TYPE[info[4]] end
    end
    if boss.rare then
        parts[#parts + 1] = "Rare spawn"
    elseif boss.optional then
        parts[#parts + 1] = "Optional"
    elseif boss.quest then
        parts[#parts + 1] = "Quest boss"
    end
    return table.concat(parts, PLACE_DOT)
end

Kinds.bossHeader = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.title = ns.Font(row, TITLE_SIZE, nil, T.fg)
        row.title:SetPoint("TOPLEFT", 0, -HEADER_TOP)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.kills = Parts.KillCount(row)
        row.kills:SetPoint("RIGHT", row, "TOPRIGHT", 0, -HEADER_TOP - TITLE_H / 2)
        row.about = ns.Font(row, 12, nil, T.muted)
        row.about:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -TITLE_GAP)
        row.about:SetPoint("RIGHT")
        row.about:SetJustifyH("LEFT")
        row.about:SetWordWrap(false)
        return row
    end,
    ---@param boss JournalBoss
    Set = function(row, boss)
        -- No fight to count for a chest or the trash.
        local showKills = row:GetParent().showKills and not boss.trash and not boss.chest
        row.kills:SetShown(showKills)
        if showKills then Parts.SetKillCount(row.kills, boss) end
        row.title:SetText(boss.name)
        row.title:SetWidth(math.max(1, row:GetWidth() - (showKills and row.kills:GetWidth() + KILLS_GAP or 0)))
        row.about:SetText(AboutText(boss))
        return HEADER_TOP + TITLE_H + TITLE_GAP + WHERE_H + HEADER_PAD
    end,
}

Kinds.bossTitle = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.title = ns.Font(row, TITLE_SIZE, nil, T.fg)
        row.title:SetPoint("TOPLEFT", 0, -TITLE_LINE_TOP)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.about = ns.Font(row, 12, nil, T.muted)
        row.about:SetPoint("BOTTOMLEFT", row.title, "BOTTOMRIGHT", ABOUT_GAP, ABOUT_RISE)
        row.about:SetJustifyH("LEFT")
        row.about:SetWordWrap(false)
        row.kills = Parts.KillCount(row)
        row.kills:SetPoint("RIGHT", row, "TOPRIGHT", 0, -TITLE_LINE_TOP - TITLE_H / 2)
        return row
    end,
    Set = function(row, boss)
        local showKills = row:GetParent().showKills and not boss.trash and not boss.chest
        row.kills:SetShown(showKills)
        if showKills then Parts.SetKillCount(row.kills, boss) end
        local room = row:GetWidth() - (showKills and row.kills:GetWidth() + KILLS_GAP or 0)
        row.title:SetWidth(0)
        row.title:SetText(boss.name)
        local nameW = math.min(math.ceil(row.title:GetStringWidth()) + 1, room)
        row.title:SetWidth(nameW)
        row.about:SetText(AboutText(boss))
        local aboutW = room - nameW - ABOUT_GAP
        row.about:SetShown(aboutW > 0)
        row.about:SetWidth(math.max(1, aboutW))
        return TITLE_LINE_TOP + TITLE_H + TITLE_LINE_PAD
    end,
}

-------------------------------------------------------------------------------
--  Naowh's tip
-------------------------------------------------------------------------------
local function ShareClicked(button)
    Parts.ShareTip(button, button.boss, button.tipText)
end

Kinds.tip = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetTexture(St.LOGO_SMALL, nil, nil, "TRILINEAR")
        row.share = Parts.IconButton(row, ShareClicked, BUBBLE, 0, "Share Naowh's tip in chat")
        row.text = ns.Font(row, 12, nil, T.fg)
        row.text:SetPoint("TOPLEFT", row.mark, "TOPRIGHT", TEXT_GAP, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        return row
    end,
    ---@param boss JournalBoss
    ---@param tip string
    Set = function(row, boss, tip)
        local dense = row:GetParent().dense
        local mark, pad = dense and MARK or TIP_MARK, dense and DENSE_PAD or ROW_PAD
        row.mark:SetSize(mark, mark)
        row.mark:SetPoint("TOPLEFT", 0, -pad)
        row.share:SetPoint("RIGHT", 0, dense and -pad / 2 or 0)
        row.share.boss, row.share.tipText = boss, tip
        row.text:SetWidth(row:GetWidth() - mark - TEXT_GAP * 2 - SHARE)
        row.text:SetText(tip)
        -- Beside the mark, in the middle of it while it is the taller.
        local text = row.text:GetStringHeight()
        row.text:SetPoint("TOPLEFT", row.mark, "TOPRIGHT", TEXT_GAP, -math.max(0, (mark - text) / 2))
        return math.ceil(math.max(mark, text)) + (dense and pad or pad * 2)
    end,
}

-------------------------------------------------------------------------------
--  The quests that need it
-------------------------------------------------------------------------------
local STATE = {
    prereq = "Prerequisite", prereqLog = "Prerequisite", low = "Level %d to pick up", pickup = "To pick up",
    next = "Next step", active = "In log", ready = "Complete", done = "Done",
}

local function QuestEnter(row)
    row.hover:Show()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(Quests.Name(row.quest), 1, 1, 1)
    GameTooltip:AddLine(row.quest[6], T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function QuestLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

Kinds.bossQuest = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, HOVER)
        row.hover:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
        row.hover:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
        row.hover:Hide()
        row.state = ns.Font(row, 11, nil, T.muted)
        row.state:SetPoint("RIGHT", 0, 0)
        row.state:SetJustifyH("RIGHT")
        row.tick = row:CreateTexture(nil, "ARTWORK")
        row.tick:SetTexture(CHECK)
        row.tick:SetSize(MARK, MARK)
        row.tick:SetPoint("RIGHT", row.state, "LEFT", -TICK_GAP, 0)
        row.name = ns.Font(row, 12)
        row.name:SetPoint("LEFT", 0, 0)
        row.name:SetPoint("RIGHT", -STATE_W, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", QuestEnter)
        row:SetScript("OnLeave", QuestLeave)
        return row
    end,
    ---@param quest JournalQuest
    Set = function(row, quest)
        row.quest = quest
        local kind = Quests.Kind(quest)
        row.name:SetText((QUEST_CODE[kind] or "") .. Quests.Name(quest) .. "|r")
        local state = STATE[kind]
        if kind == "low" then state = state:format(Quests.MinLevel(quest) or 0) end
        row.state:SetText(state)
        local done = kind == "done"
        row.tick:SetShown(done)
        if done then
            row.state:SetTextColor(HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b)
        else
            row.state:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
        end
        return QUEST_H
    end,
}

local function ChipEnter(chip)
    chip.hover:Show()
    GameTooltip:SetOwner(chip, "ANCHOR_TOP")
    GameTooltip:SetText(Quests.Name(chip.quest), 1, 1, 1)
    GameTooltip:AddLine(chip.quest[6], T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function ChipLeave(chip)
    chip.hover:Hide()
    GameTooltip:Hide()
end

local function QuestChip(row)
    local chip = CreateFrame("Frame", nil, row)
    chip:SetHeight(CHIP_H)
    ns.Solid(chip, "BACKGROUND", T.fg, CHIP_FILL):SetAllPoints()
    chip.hover = ns.Solid(chip, "BACKGROUND", T.fg, HOVER)
    chip.hover:SetAllPoints()
    chip.hover:Hide()
    ns.Border(chip, St.BORDER_RGB)
    chip.name = ns.Font(chip, 11)
    chip.name:SetPoint("LEFT", CHIP_PAD, 0)
    chip.name:SetJustifyH("LEFT")
    chip.name:SetWordWrap(false)
    chip.state = ns.Font(chip, 11, nil, T.muted)
    chip.state:SetPoint("LEFT", chip.name, "RIGHT", STATE_GAP, 0)
    chip.state:SetWordWrap(false)
    chip:EnableMouse(true)
    chip:SetScript("OnEnter", ChipEnter)
    chip:SetScript("OnLeave", ChipLeave)
    return chip
end

Kinds.questChips = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.label = ns.Font(row, 12, nil, T.accentSoft)
        row.label:SetPoint("LEFT", row, "TOPLEFT", 0, -CHIP_H / 2)
        row.label:SetText(QUESTS_LABEL)
        row.chips = {}
        return row
    end,
    Set = function(row, list)
        local width = row:GetWidth()
        local start = math.ceil(row.label:GetStringWidth()) + CHIP_GAP * 2
        local x, y = start, 0
        for i = 1, #list do
            local quest = list[i]
            local chip = row.chips[i] or QuestChip(row)
            row.chips[i] = chip
            chip.quest = quest
            local kind = Quests.Kind(quest)
            chip.name:SetWidth(0)
            chip.name:SetText((QUEST_CODE[kind] or "") .. Quests.Name(quest) .. "|r")
            local state = STATE[kind]
            if kind == "low" then state = state:format(Quests.MinLevel(quest) or 0) end
            chip.state:SetText(state)
            local color = kind == "done" and HAVE_RGB or T.muted
            chip.state:SetTextColor(color.r, color.g, color.b)
            local stateW = math.ceil(chip.state:GetStringWidth())
            local nameW = math.min(math.ceil(chip.name:GetStringWidth()) + 1,
                width - start - CHIP_PAD * 2 - STATE_GAP - stateW)
            chip.name:SetWidth(math.max(1, nameW))
            local w = CHIP_PAD * 2 + nameW + STATE_GAP + stateW
            if x + w > width and x > start then
                x, y = start, y + CHIP_H + CHIP_GAP
            end
            chip:SetWidth(w)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", x, -y)
            chip:Show()
            x = x + w + CHIP_GAP
        end
        for i = #list + 1, #row.chips do row.chips[i]:Hide() end
        return y + CHIP_H
    end,
}

-------------------------------------------------------------------------------
--  Its abilities
-------------------------------------------------------------------------------

local function AbilityEnter(row)
    row.hover:Show()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(row.spell)
    GameTooltip:AddLine(LINK_HINT, T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function AbilityClick(row)
    if not IsModifiedClick("CHATLINK") then return end
    local link = GetSpellLink(row.spell)
    if link then ChatFrameUtil.InsertLink(link) end
end

local function AbilityLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local oneLine = {}

local function OneLine(spell, desc)
    local line = oneLine[spell]
    if not line then
        line = desc:gsub("%s*[\r\n]+%s*", " ")
        oneLine[spell] = line
    end
    return line
end

-- A spell loaded after its row was drawn: the view draws again, once for a burst of them.
local function Loaded(view)
    return function()
        if view:IsVisible() then view:QueueRedraw() end
    end
end

Kinds.ability = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        -- The hover reaches out to the card's edges, as an item's does.
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, HOVER)
        row.hover:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
        row.hover:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
        row.hover:Hide()
        local frame = Parts.ItemIcon(row, ICON)
        row.icon, row.iconFrame = frame.texture, frame
        row.name = ns.Font(row, 12, nil, T.fg)
        row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", TEXT_GAP, 0)
        row.name:SetPoint("RIGHT")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.desc = ns.Font(row, 11, nil, T.muted)
        row.desc:SetJustifyH("LEFT")
        row:SetScript("OnEnter", AbilityEnter)
        row:SetScript("OnLeave", AbilityLeave)
        row:SetScript("OnClick", AbilityClick)
        row.loaded = Loaded(view)
        return row
    end,
    ---@param spell number its spell ID
    Set = function(row, spell)
        row.spell = spell
        row.icon:SetTexture(GetSpellTexture(spell) or QUESTION)
        row.name:SetText(GetSpellName(spell) or ("Spell " .. spell))
        local desc = GetSpellDescription and GetSpellDescription(spell) or ""
        if desc == "" and IsSpellDataCached and not IsSpellDataCached(spell) and Spell then
            Spell:CreateFromSpellID(spell):ContinueOnSpellLoad(row.loaded)
        end
        local view = row:GetParent()
        local frame, dense = row.iconFrame, view.dense
        local tall = dense and view.abilityLines == TALL_LINES
        frame:ClearAllPoints()
        row.desc:ClearAllPoints()
        row.desc:SetWordWrap(not dense or tall)
        row.desc:SetMaxLines(tall and TALL_LINES or 0)
        if dense then
            frame:SetSize(DENSE_ICON, DENSE_ICON)
            row.desc:SetWidth(row:GetWidth() - DENSE_ICON - TEXT_GAP)
            row.desc:SetText(desc ~= "" and OneLine(spell, desc) or "")
            row.desc:SetShown(desc ~= "")
            if tall then
                frame:SetPoint("TOPLEFT", 0, -DENSE_TALL_TOP)
                row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", TEXT_GAP, -DENSE_NAME_TOP)
                row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -NAME_DESC_GAP)
                return DENSE_TALL_H
            end
            frame:SetPoint("LEFT", 0, 0)
            row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", TEXT_GAP, -DENSE_NAME_TOP)
            row.desc:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", TEXT_GAP, DENSE_NAME_TOP)
            return DENSE_H
        end
        frame:SetSize(ICON, ICON)
        frame:SetPoint("TOPLEFT", 0, -ROW_PAD)
        row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -NAME_DESC_GAP)
        row.desc:SetWidth(row:GetWidth() - ICON - TEXT_GAP)
        row.desc:SetText(desc)
        row.desc:SetShown(desc ~= "")
        local text = row.name:GetStringHeight()
        if desc ~= "" then text = text + NAME_DESC_GAP + row.desc:GetStringHeight() end
        -- Beside the icon, in the middle of it while it is the taller, as an item's lines are.
        row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", TEXT_GAP, -math.max(0, (ICON - text) / 2))
        return math.ceil(math.max(ICON, text)) + ROW_PAD * 2
    end,
}
