-------------------------------------------------------------------------------
--  SpecStats.lua -- the character panel's stats: your spec's first, the stats your spec weighs
--  by your stat weights (the BiS List's) in a fixed order (primary stats, power, the ratings,
--  then Stamina and Armor, always), each with a slim bar for what it is worth against your
--  spec's yardstick (the stat its weights are measured in, "VS AGI") and your total now; or
--  All Stats, the game's list. The switch between them sits at the pane's bottom. Hover a row
--  for what the stat is worth in its yardstick, what it does and your total.
--
--  The game's list is the game's: nothing is added to it or taken from it, but while the panel
--  is on it starts lower, for your Naowh Score (Score.lua) over it, and ends higher, for the
--  switch under it; back where the game had it when off. Your spec's is a panel of ours over
--  it while picked, the game's faded under it (SetAlpha), both showing only while the game
--  shows its stats (not its titles or gear sets). Its rows share out the room down to the
--  switch, up to a roomy height. Painted when shown and, while shown, when your stats change.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local CP = ns.CharacterPanel
local SW = ns.StatWeights
local Parts = ns.Shared.Parts
local STRIPE = ns.Shared.Style.STRIPE

local EDGE, PANE_W = CP.EDGE, CP.PANE_W
local CONTENT_W = PANE_W - 2 * EDGE
local SWITCH_W = CONTENT_W
local SWITCH_H = 26          -- the shared tabs' height
local GAP = 6                -- round the switch
-- The room the game leaves between your level and its list's top (the list's first title sits
-- low in its own row): what the score needs beyond it moves the list down.
local ROOM = 20

-- The order the stats show in: primary stats, power, the ratings, then what keeps you alive.
local ORDER = { "agi", "str", "int", "spi", "ap", "rap", "spell", "heal", "fire", "frost", "shadow",
    "nature", "arcane", "holy", "crit", "scrit", "hit", "haste", "dps", "mp5", "def", "dodge",
    "block", "sta", "armor" }
local ALWAYS = { sta = true, armor = true }   -- shown whatever your spec weighs them
local ROWS = 16

-- The section, from the top of ours: its title over a hairline as the game's categories have
-- it, the columns' headings under the line, then the rows.
local SECTION_TOP = 12
local TITLE_SIZE, HEAD_SIZE = 11, 10
local LINE_Y = SECTION_TOP + 16
local HEAD_GAP = 5           -- the headings under the line
local ROWS_TOP = LINE_Y + 20
local ROWS_BOTTOM = 4        -- the last row clear of the switch's gap
-- A row's height: the room down to the switch shared out, never over ROW_MAX (a few stats
-- stay a list, not a spread), in bigger type from ROW_ROOMY up; ROW_FLOOR only when a spec
-- weighs more than the pane can hold.
local ROW_MAX, ROW_ROOMY, ROW_FLOOR = 30, 24, 12
local ROW_SIZE, ROW_SIZE_TIGHT = 13, 12
-- The columns: the name, the worth's bar, your total right-aligned, on one grid; a row's band
-- reaches BAND_PAD past them, as the score card's stat lines.
local VALUE_W, COLUMN_GAP, NAME_GAP = 44, 10, 6
local BAR_W, BAR_H = 50, 4
local NAME_W = CONTENT_W - VALUE_W - COLUMN_GAP - BAR_W - NAME_GAP
local BAR_X = NAME_W + NAME_GAP
local BAND_PAD = 4
local TRACK_ALPHA = 0.08     -- the bar's track: the text colour, this faint
local BAR_DROP = Parts.CARD_DROP   -- level with the letters, as on the house's cards

-- ADDON_RESTRICTION_STATE_CHANGED: your stats can go secret under the game's addon restrictions
-- (combat, an encounter, some maps); painted again when one lifts.
local EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "COMBAT_RATING_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED" }
local UNIT_EVENTS = { "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_DAMAGE",
    "UNIT_ATTACK_SPEED", "UNIT_RESISTANCES" }

-- Your total now for each stat a weight can be set for: the game's numbers, as its own stats
-- list works them out. A percent's text says so; threat has none to show.
local SCHOOLS = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }

local HIDDEN = "-"   -- a total the game keeps secret for now, as a dps with no weapon speed
local function Percent(value) return ("%.1f%%"):format(value or 0) end
local function Whole(value) return ("%d"):format(math.floor((value or 0) + 0.5)) end

local function SpellDamage()
    local least
    for school = 2, 7 do
        local bonus = GetSpellBonusDamage(school)
        if not least or bonus < least then least = bonus end
    end
    return least
end

local TOTAL = {
    str = function() return Whole(select(2, UnitStat("player", 1))) end,
    agi = function() return Whole(select(2, UnitStat("player", 2))) end,
    sta = function() return Whole(select(2, UnitStat("player", 3))) end,
    int = function() return Whole(select(2, UnitStat("player", 4))) end,
    spi = function() return Whole(select(2, UnitStat("player", 5))) end,
    ap = function()
        local base, up, down = UnitAttackPower("player")
        return Whole(base + up + down)
    end,
    rap = function()
        local base, up, down = UnitRangedAttackPower("player")
        return Whole(base + up + down)
    end,
    dps = function()
        local low, high = UnitDamage("player")
        local speed = UnitAttackSpeed("player")
        return speed and speed > 0 and ("%.1f"):format((low + high) / 2 / speed) or "-"
    end,
    hit = function() return Percent(GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier()) end,
    crit = function() return Percent(GetCritChance()) end,
    haste = function() return Percent(GetMeleeHaste()) end,
    spell = function() return Whole(SpellDamage()) end,
    heal = function() return Whole(GetSpellBonusHealing()) end,
    scrit = function() return Percent(GetSpellCritChance()) end,
    mp5 = function() return Whole(GetManaRegen() * 5) end,
    def = function()
        local base, modifier = UnitDefenseSkill("player")
        return Whole(base + modifier)
    end,
    dodge = function() return Percent(GetDodgeChance()) end,
    block = function() return Percent(GetBlockChance()) end,
    armor = function() return Whole(select(2, UnitArmor("player"))) end,
}
for school, index in pairs(SCHOOLS) do
    TOTAL[school] = function() return Whole(GetSpellBonusDamage(index)) end
end

-- While the game keeps your stats secret: the ones it can still show, set straight on the row's
-- text by the calls that take a secret (a font string's SetText and SetFormattedText, and
-- C_StringUtil's rounding). A total we would have to add up or compare ourselves shows HIDDEN.
local function Rounded(read)
    return function(text) text:SetText(C_StringUtil.FloorToNearestString(read())) end
end
local function Percented(read)
    return function(text) text:SetFormattedText("%.1f%%", read()) end
end
local SECRET_TOTAL = {
    armor = Rounded(function() return select(2, UnitArmor("player")) end),
    heal = Rounded(GetSpellBonusHealing),
    crit = Percented(GetCritChance),
    haste = Percented(GetMeleeHaste),
    scrit = Percented(GetSpellCritChance),
    dodge = Percented(GetDodgeChance),
    block = Percented(GetBlockChance),
    -- Defense skill is never secret.
    def = function(text) text:SetText(TOTAL.def()) end,
}
for i, stat in ipairs({ "str", "agi", "sta", "int", "spi" }) do
    SECRET_TOTAL[stat] = Rounded(function() return select(2, UnitStat("player", i)) end)
end
for school, index in pairs(SCHOOLS) do
    SECRET_TOTAL[school] = Rounded(function() return GetSpellBonusDamage(index) end)
end

local NAME = {}
for _, stat in ipairs(SW.STATS) do NAME[stat[1]] = stat[2] end
-- The row's name where the full one does not fit its column; the hover card says it in full.
local SHORT = { rap = "Ranged AP", mp5 = "Mana / 5 sec" }

-- The yardstick: the stat a spec's weights are measured in (the defaults weigh it 1: Agility
-- or Strength for fighters, Stamina for tanks, Spell Damage or Healing for casters), else the
-- heaviest of these.
local YARDSTICKS = { "agi", "str", "sta", "spell", "heal", "int", "ap" }
local HEADING = { agi = "VS AGI", str = "VS STR", sta = "VS STA", spell = "VS SPELL", heal = "VS HEAL",
    int = "VS INT", ap = "VS AP" }

-- The hover card's words: what each stat does, and which are a percent ("1% Crit").
local DOES = {
    agi = "Attack power, crit chance, dodge and armor.",
    str = "Attack power, and block with a shield.",
    int = "Mana and spell crit chance.",
    spi = "Mana and health back while not casting.",
    ap = "More damage from your weapons.",
    rap = "More damage from your ranged weapon.",
    spell = "More damage from your spells.",
    heal = "More healing from your spells.",
    crit = "Chance for a hit to deal double damage.",
    scrit = "Chance for a spell to crit.",
    hit = "Chance not to miss: worth the most until you stop missing.",
    haste = "Faster attacks.",
    dps = "Your weapon's damage per second.",
    mp5 = "Mana back every 5 seconds, even while casting.",
    def = "Lowers the chance to be hit, crit and dazed.",
    dodge = "Chance to dodge a melee hit.",
    block = "Chance to block a hit with a shield.",
    sta = "Health.",
    armor = "Less physical damage taken.",
}
local SCHOOL_NAME = { fire = "Fire", frost = "Frost", shadow = "Shadow", nature = "Nature", arcane = "Arcane",
    holy = "Holy" }
for school, name in pairs(SCHOOL_NAME) do DOES[school] = "More damage from your " .. name .. " spells." end
local PERCENT = { hit = true, crit = true, haste = true, scrit = true, dodge = true, block = true }
local WORTH_LINE = "%s %s is worth %s %s to %s."      -- "1% Crit is worth 14 Agility to Combat."
local YARDSTICK_LINE = "%s is the yardstick: every other stat is weighed against it."
local UNCOUNTED_LINE = "%s does not count it."
local UNMEASURED_LINE = "%s weighs it %s."            -- no yardstick among your weights
local YOU_LINE = "You: %s"

local switch, view, installed
local keys = {}        -- the stats shown, in ORDER, reused
local LABELS = { { key = "spec", label = "Your Spec" }, { key = "all", label = "All Stats" } }
local shortNames, titles = {}, {}   -- a spec's name -> its short name, its title: made once each

-- "Assassination Rogue" -> "Assassination": the switch is under the class already.
local function ShortName(spec)
    if not spec then return "Your Spec" end
    local short = shortNames[spec.name]
    if not short then
        short = spec.name:match("^(.-) %a+$") or spec.name
        shortNames[spec.name] = short
    end
    return short
end

local function Title(short)
    local title = titles[short]
    if not title then
        title = "BEST FOR " .. short:upper()
        titles[short] = title
    end
    return title
end

-- The yardstick among your weights: the first weighed exactly 1, else the heaviest.
local function Yardstick(weights)
    if not weights then return nil end
    local heaviest
    for _, stat in ipairs(YARDSTICKS) do
        local weight = weights[stat] or 0
        if weight == 1 then return stat end
        if weight > 0 and (not heaviest or weight > weights[heaviest]) then heaviest = stat end
    end
    return heaviest
end

-- A weight in plain words: 14, 0.5, 0.15 (no trailing zeros).
local function Plain(value)
    local text = ("%.3f"):format(value):gsub("0+$", ""):gsub("%.$", "")
    return text
end

local function SpecShown()
    return CP.On() and S.Get("characterPanelStats") == "spec"
end

-------------------------------------------------------------------------------
--  A row's hover card
-------------------------------------------------------------------------------
local function WorthLine(row)
    local stat, spec, yard = row.stat, view.specName, view.yard
    if row.weight <= 0 then return UNCOUNTED_LINE:format(spec) end
    if stat == yard then return YARDSTICK_LINE:format(NAME[stat]) end
    if not yard then return UNMEASURED_LINE:format(spec, Plain(row.weight)) end
    local name = NAME[stat] or stat
    local amount = "1"
    if PERCENT[stat] then
        name = name:gsub(" %%$", "")
        amount = "1%"
    end
    return WORTH_LINE:format(amount, name, Plain(row.weight / view.yardWeight), NAME[yard], spec)
end

local function RowEnter(row)
    if not row.stat or not Parts.Tip(row, "ANCHOR_RIGHT") then return end
    local a, m, fg = T.accentSoft, T.muted, T.fg
    GameTooltip:SetText(NAME[row.stat] or row.stat, 1, 1, 1)
    GameTooltip:AddLine(WorthLine(row), a.r, a.g, a.b, true)
    if DOES[row.stat] then GameTooltip:AddLine(DOES[row.stat], m.r, m.g, m.b, true) end
    if row.secret then
        -- The total is secret: written into the line by the call that takes one.
        GameTooltip:AddLine(" ", fg.r, fg.g, fg.b)
        _G["GameTooltipTextLeft" .. GameTooltip:NumLines()]:SetFormattedText(YOU_LINE, row.total:GetText())
    else
        GameTooltip:AddLine(YOU_LINE:format(row.total:GetText() or ""), fg.r, fg.g, fg.b)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  Painting
-------------------------------------------------------------------------------
-- The rows down from the headings, as tall as the room shares out for count of them; laid out
-- again only when that height changes.
local function Lay(count)
    local room = view:GetHeight() - ROWS_TOP - ROWS_BOTTOM
    local height = math.max(ROW_FLOOR, math.min(ROW_MAX, math.floor(room / math.max(1, count))))
    if height == view.rowH then return end
    view.rowH = height
    local size = height >= ROW_ROOMY and ROW_SIZE or ROW_SIZE_TIGHT
    local font = ns.UIFontPath()
    for i, row in ipairs(view.rows) do
        local y = -(ROWS_TOP + (i - 1) * height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view, "TOPLEFT", EDGE - BAND_PAD, y)
        row:SetPoint("TOPRIGHT", view, "TOPRIGHT", -(EDGE - BAND_PAD), y)
        row:SetHeight(height)
        if size ~= view.size then
            row.name:SetFont(font, size, "")
            row.total:SetFont(font, size, "")
        end
    end
    view.size = size
end

local function Paint()
    local key = SW.ActiveSpec()
    local spec = key and SW.Spec(key)
    local weights = key and SW.For(key)
    local short = ShortName(spec)
    local yard = Yardstick(weights)
    view.title:SetText(spec and Title(short) or "YOUR STATS")
    view.head:SetText(HEADING[yard] or "WORTH")
    view.specName, view.yard = short, yard
    view.yardWeight = yard and weights[yard] or 1
    wipe(keys)
    local top = 0
    for _, stat in ipairs(ORDER) do
        local weight = weights and weights[stat] or 0
        if ALWAYS[stat] or weight > 0 then
            keys[#keys + 1] = stat
            if weight > top then top = weight end
        end
    end
    Lay(math.min(#keys, ROWS))
    local hidden = C_Secrets.ShouldUnitStatsBeSecret()
    for i, row in ipairs(view.rows) do
        local stat = keys[i]
        row:SetShown(stat ~= nil)
        if stat then
            local weight = weights and weights[stat] or 0
            row.stat, row.weight = stat, weight
            row.name:SetText(SHORT[stat] or NAME[stat] or stat)
            row.secret = hidden and SECRET_TOTAL[stat] ~= nil
            if row.secret then
                SECRET_TOTAL[stat](row.total)
            else
                row.total:SetText(hidden and HIDDEN or TOTAL[stat]())
            end
            -- The worth's bar, as long as its share of the heaviest weight by the square root,
            -- so a small one still shows beside the big ones, as the BiS List's gains.
            row.track:SetShown(weight > 0)
            row.bar:SetShown(weight > 0)
            if weight > 0 then
                row.bar:SetWidth(math.max(2, math.floor(BAR_W * math.sqrt(weight / top) + 0.5)))
            end
        end
    end
end

local function OnEvent()
    if view:IsVisible() then Paint() end
end

local function Resized()
    if view:IsVisible() then Lay(math.min(#keys, ROWS)) end
end

-- Ours over the game's list while your spec's is picked, the game's faded under it.
-- The game's list, from the pane's top art down to its bottom, as the game anchors it, less
-- drop at the top and lift at the bottom.
local function PlaceList(drop, lift)
    local stats = CharacterStatsPaneScrollBox
    stats:ClearAllPoints()
    stats:SetPoint("TOPLEFT", CharacterFrameRightPaneHostStoneBg, "BOTTOMLEFT", 0, -drop)
    stats:SetPoint("BOTTOMRIGHT", CharacterFrame.RightPaneHost, "BOTTOMRIGHT", 0, lift)
end

-- Your score (when on) under your level, the list starting under it; the switch at the pane's
-- bottom, the list ending over it.
local function Layout()
    local badge = CP.badge
    local scored = badge ~= nil and badge:IsShown()
    local need = scored and CP.BADGE_GAP + CP.BADGE_H or 0
    PlaceList(math.max(0, need - ROOM), SWITCH_H + 2 * GAP)
end

local function Show()
    local stats = CharacterStatsPaneScrollBox
    local on = CP.On() and stats:IsShown()
    switch:SetShown(on)
    if CP.On() then Layout() end
    LABELS[1].label = ShortName(SW.Spec(SW.ActiveSpec() or ""))
    Parts.SetTabs(switch, LABELS)
    Parts.PaintTabs(switch, S.Get("characterPanelStats"))
    local spec = on and SpecShown()
    view:SetShown(spec)
    stats:SetAlpha(spec and 0 or 1)
    view:UnregisterAllEvents()
    if spec then
        for _, event in ipairs(EVENTS) do view:RegisterEvent(event) end
        for _, event in ipairs(UNIT_EVENTS) do view:RegisterUnitEvent(event, "player") end
        Paint()
    end
end
CP.ShowSpecStats = Show

local function Picked(key)
    S.Set("characterPanelStats", key)
end

local function Row(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    if i % 2 == 1 then ns.Solid(row, "BACKGROUND", T.fg, STRIPE):SetAllPoints() end
    row.name = ns.Font(row, ROW_SIZE_TIGHT, nil, T.muted)
    row.name:SetPoint("LEFT", BAND_PAD, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.track = ns.Solid(row, "ARTWORK", T.fg, TRACK_ALPHA)
    row.track:SetPoint("LEFT", BAND_PAD + BAR_X, -BAR_DROP)
    row.track:SetSize(BAR_W, BAR_H)
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetDrawLayer("ARTWORK", 1)
    row.bar:SetPoint("LEFT", BAND_PAD + BAR_X, -BAR_DROP)
    row.bar:SetHeight(BAR_H)
    row.total = ns.Font(row, ROW_SIZE_TIGHT, nil, T.fg)
    row.total:SetPoint("RIGHT", -BAND_PAD, 0)
    row.total:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function Build()
    -- On the panel itself, not its right pane: the restyle fades the pane's own frames (the
    -- game's divider is one), and these are ours.
    local panel, stats = CharacterFrame, CharacterStatsPaneScrollBox
    switch = Parts.Tabs(panel, SWITCH_W, LABELS, Picked)
    switch:SetPoint("BOTTOM", CharacterFrame.RightPaneHost, "BOTTOM", 0, GAP)
    switch:SetFrameLevel(stats:GetFrameLevel() + 10)
    view = CreateFrame("Frame", nil, panel)
    view:SetAllPoints(stats)
    view:SetFrameLevel(stats:GetFrameLevel() + 10)
    view:EnableMouse(true)        -- the game's rows under it keep their tooltips to themselves
    view:EnableMouseWheel(true)
    view:SetScript("OnEvent", OnEvent)
    view:SetScript("OnSizeChanged", Resized)
    -- The weights these come from, a click away on the title's line: the scales, as the BiS
    -- List's title bar has them for Stat Weights.
    local weights = Parts.IconButton(view, function() ns.OpenStatWeightsWindow() end,
        ns.Shared.Style.SCALES, nil, "Stat Weights")
    weights.hint = "What each stat is worth to your spec: change them as you like."
    weights:SetPoint("RIGHT", view, "TOPRIGHT", -EDGE, -(SECTION_TOP + TITLE_SIZE / 2))
    view.weights = weights
    view.title = ns.Font(view, TITLE_SIZE, nil, T.accentSoft)
    view.title:SetPoint("TOPLEFT", EDGE, -SECTION_TOP)
    local line = ns.Solid(view, "ARTWORK", T.line, 1)
    line:SetPoint("TOPLEFT", EDGE, -LINE_Y)
    line:SetPoint("TOPRIGHT", -EDGE, -LINE_Y)
    ns.Hairline(line, "h")
    view.head = ns.Font(view, HEAD_SIZE, nil, T.muted)
    view.head:SetPoint("TOPLEFT", line, "BOTTOMLEFT", BAR_X, -HEAD_GAP)
    local you = ns.Font(view, HEAD_SIZE, nil, T.muted)
    you:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, -HEAD_GAP)
    you:SetText("YOU")
    view.rows = {}
    for i = 1, ROWS do view.rows[i] = Row(view, i) end
    stats:HookScript("OnShow", Show)
    stats:HookScript("OnHide", Show)
    SW.OnChange(function() if view:IsVisible() then Paint() end end)
end

local function Apply()
    if CP.On() and not installed and CharacterFrame and CharacterStatsPaneScrollBox then
        installed = true
        Build()
    end
    if not installed then return end
    if CP.On() then
        Show()
    else
        switch:Hide()
        view:Hide()
        view:UnregisterAllEvents()
        CharacterStatsPaneScrollBox:SetAlpha(1)
        PlaceList(0, 0)
    end
end

S.OnChange(function(key)
    if key == "enabled" or key:find("^characterPanel") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
