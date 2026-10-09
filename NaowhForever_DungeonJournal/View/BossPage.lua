-- BossPage.lua: a boss's own page: stacked in sections (Boss Loot at Cursor), or compact beside its abilities (the dungeon map).
local ns = _G.NaowhForever

local J = ns.Journal
local S = J.Settings
local Quests = J.Quests
local View = J.View
local ViewMixin = View.Mixin
local St = J.Style
local SECTION_SPACE = St.SECTION_SPACE

local PAGE_GAP, COLUMN_GAP, COLUMN_TITLE_GAP = St.BOSS_PAGE_GAP, 16, 2
local ROOMY_LINES, TIGHT_LINES = 2, 1
local LOOT_KEY = "loot"
local SECTION_KEYS = { ["Naowh's Tip"] = "bossTipOpen", Loot = LOOT_KEY, Quests = "bossQuestsOpen",
    Abilities = "bossAbilitiesOpen" }

local TEXT_TIP = "Naowh's Tip"
local TEXT_LOOT = "Loot"
local TEXT_QUESTS = "Quests"
local TEXT_ABILITIES = "Abilities"

local EMPTY = {}

local function MakeToggle(view, key)
    return function()
        if key == LOOT_KEY then
            view.lootClosed = view:SectionOpen(key) and view.boss or nil
        else
            S.Set(key, not S.Get(key))
        end
        view:Redraw()
    end
end

function ViewMixin:DrawBossLoot(boss, dungeon)
    self.bossPage = false
    self:Begin(dungeon, boss)
    local tip = self.showTips and J.Tip(boss)
    self.showTips = false
    self:DrawBossName(boss)
    if tip and self:OpenDetailCard(TEXT_TIP) then
        self:Add("tip", boss, tip)
        self:CloseCard(self.detailCard, self.detailTop)
    end
    self:DrawBossDetails(boss)
    self:DrawBossItems(boss)
    self:Finish()
end

function ViewMixin:DrawBossPage(boss, dungeon)
    local room = self.fitHeight
    self.abilityLines = room and ROOMY_LINES or TIGHT_LINES
    self:DrawBossPageRows(boss, dungeon)
    if room and self.cursor > room and self.abilitiesDrawn then
        self.abilityLines = TIGHT_LINES
        self:DrawBossPageRows(boss, dungeon)
    end
    self:Finish()
end

function ViewMixin:DrawTipCard(boss, tip)
    self:Space(PAGE_GAP)
    local top = self.cursor
    local card = self:OpenCard(0, self:GetWidth())
    self:Add("tip", boss, tip)
    self:CloseCard(card, top)
end

function ViewMixin:DrawBossPageRows(boss, dungeon)
    self.bossPage = true
    self:Begin(dungeon, boss)
    self.abilitiesDrawn = false
    self.dense, self.tightTitles = true, true
    self:Add("bossTitle", boss)
    local tip = self.showTips and J.Tip(boss)
    if tip then self:DrawTipCard(boss, tip) end
    local quests = self:BossQuests(boss)
    local loot = boss.loot or EMPTY
    local spells = boss.npc and J.Abilities[boss.npc] or EMPTY
    if quests and #loot == 0 then
        self:Space(PAGE_GAP)
        self:Add("questChips", quests)
    end
    self:Space(PAGE_GAP)
    if #loot > 0 or #spells > 0 then
        self:DrawBossColumns(boss, loot, spells)
    else
        self:Note(View.Parts.BossEmptyText(0, boss))
    end
    if quests and #loot > 0 then
        self:Space(PAGE_GAP)
        self:Add("questChips", quests)
    end
end

function ViewMixin:Column(x, w, top)
    self.left, self.width, self.cursor = x, w, top
end

function ViewMixin:DrawLootColumn(boss, loot, split, width, half, top)
    local bottom = top
    local shown = self:ShownCount(boss)
    self:Column(0, split and width or half, top)
    self:Section(TEXT_LOOT, shown)
    self:Space(COLUMN_TITLE_GAP)
    local start, leftCount, n = self.cursor, split and math.ceil(shown / 2) or shown, 0
    self.width = half
    local chance = boss.chance
    for i = 1, #loot do
        local id = loot[i]
        if self:Listed(id) then
            n = n + 1
            if n == leftCount + 1 then
                bottom = math.max(bottom, self.cursor)
                self:Column(width - half, half, start)
            end
            self:AddItem(id, chance and chance[i], boss)
        end
    end
    if shown == 0 then self:Note(View.Parts.BossEmptyText(shown, boss)) end
    return math.max(bottom, self.cursor)
end

function ViewMixin:DrawAbilityColumn(spells, whole, width, half, top)
    self:Column(whole and 0 or width - half, whole and width or half, top)
    self.abilitiesDrawn = true
    self:Section(TEXT_ABILITIES, #spells)
    self:Space(COLUMN_TITLE_GAP)
    for i = 1, #spells do self:Add("ability", spells[i]) end
    return self.cursor
end

function ViewMixin:DrawBossColumns(boss, loot, spells)
    local width, top = self:GetWidth(), self.cursor
    local half = math.floor((width - COLUMN_GAP) / 2)
    local bottom = top
    if #loot > 0 then
        bottom = math.max(bottom, self:DrawLootColumn(boss, loot, #spells == 0, width, half, top))
    end
    if #spells > 0 then
        bottom = math.max(bottom, self:DrawAbilityColumn(spells, #loot == 0, width, half, top))
    end
    self:Column(0, width, bottom)
end

function ViewMixin:DrawBossName(boss)
    self:Add("bossHeader", boss)
end

function ViewMixin:SectionOpen(key)
    if key == LOOT_KEY then return self.lootClosed ~= self.boss end
    return S.Get(key)
end

function ViewMixin:ToggleFor(title)
    self.toggles = self.toggles or {}
    local toggle = self.toggles[title]
    if not toggle then
        toggle = MakeToggle(self, SECTION_KEYS[title])
        self.toggles[title] = toggle
    end
    return toggle
end

function ViewMixin:OpenDetailCard(title, count)
    if self.cursor > 0 then self:Space(SECTION_SPACE) end
    local key = SECTION_KEYS[title]
    local open = not key or self:SectionOpen(key)
    if key then
        self:SectionToggle(title, count, open, self:ToggleFor(title))
    else
        self:Section(title, count)
    end
    if not open then return false end
    self:Space(SECTION_SPACE)
    self.detailTop = self.cursor
    self.detailCard = self:OpenCard(0, self:GetWidth())
    self:Space(St.CARD_BOTTOM)
    return true
end

function ViewMixin:DetailCard(title, count, kind, list)
    if not self:OpenDetailCard(title, count) then return end
    for i = 1, #list do self:Add(kind, list[i]) end
    self:CloseCard(self.detailCard, self.detailTop)
end

function ViewMixin:DrawBossItems(boss)
    local loot = boss.loot or EMPTY
    if #loot == 0 then return end
    local shown = self:ShownCount(boss)
    if not self:OpenDetailCard(TEXT_LOOT, shown) then return end
    local chance = boss.chance
    for i = 1, #loot do
        local id = loot[i]
        if self:Listed(id) then self:AddItem(id, chance and chance[i], boss) end
    end
    if shown == 0 then self:Note(View.Parts.BossEmptyText(shown, boss)) end
    self:CloseCard(self.detailCard, self.detailTop)
end

function ViewMixin:BossQuests(boss)
    local ids = boss.npc and J.BossQuests[boss.npc]
    if not ids then return nil end
    local list = self.bossQuests or {}
    self.bossQuests = list
    wipe(list)
    for i = 1, #ids do
        local quest = Quests.ByID(ids[i])
        if quest and Quests.ForMe(quest) then list[#list + 1] = quest end
    end
    if #list == 0 then return nil end
    self.watchQuestLog = true
    return list
end

function ViewMixin:DrawBossDetails(boss)
    local list = self:BossQuests(boss)
    if list then self:DetailCard(TEXT_QUESTS, #list, "bossQuest", list) end
    local spells = boss.npc and J.Abilities[boss.npc]
    if spells then self:DetailCard(TEXT_ABILITIES, #spells, "ability", spells) end
end
