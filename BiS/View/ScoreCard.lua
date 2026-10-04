-------------------------------------------------------------------------------
--  View/ScoreCard.lua -- the Naowh Score card (B.View.ScoreCard): the score big (with your
--  BiS, or what you wear now, as the look is) and the gain your BiS brings; under it a bar on
--  the score's colour ramp, filled to what you wear, dimmer on to your BiS, plain after; its
--  scale the best it is graded against (Grade Against), with Both a gold tick at your level's
--  goal; then the stats your BiS adds and takes away, the ones that matter most to your list's
--  spec, by its stat weights (an amount times what a point is worth), gains and losses alike.
--  What the spec does not weigh (resistances, the odd proc stat) is left out; with no weights,
--  the core stats in a fixed order.
--
--  Under the BiS List's paperdoll.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Tip = ns.Shared.Parts.Tip
local T = ns.THEME
local B = ns.BiS

local St = B.Style
local RED_CODE, UPGRADE_CODE = St.RED_CODE, St.UPGRADE_CODE

local STAT_ORDER = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_MANA_REGENERATION_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT",
    "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "RESISTANCE0_NAME" }
local CORE = {}
for i, key in ipairs(STAT_ORDER) do CORE[key] = i end
local STAT_CELLS = 4          -- the grid: two lines of two, the stats that matter most
local STAT_ROW, VALUE_W = 20, 44
local GRID_GAP = 16           -- between the grid's two columns
local BAND_PAD = 4            -- a grid line's band reaches this far past its text
-- The card's rows, from its top: the kicker, the big score, the bar, its legend, then the
-- stats' grid, two lines of two.
local VALUE_TOP, VALUE_SIZE = 13, 26
local BAR_TOP, BAR_H = 48, 8
local TICK_W, TICK_OUT = 2, 3   -- the goal's tick, and how far it stands out over and under the bar
local LEGEND_GAP = 4            -- the legend under the bar
local LEGEND_MIN = 90           -- the goal's label this close to the scale's: the goal's goes
local LEGEND_HALF = 40          -- the goal's label's half width, kept inside the card
local GRID_TOP = 82
local CARD_H = 120             -- the whole card, its grid under the bar
local GAIN_ALPHA = 0.5          -- the stretch your BiS adds: the ramp, darkened this much
local TRACK_RGB = 0.16          -- the bar past your BiS
local GOAL_RGB = { r = 1, g = 0.82, b = 0 }

local shown = {}   -- the stat keys to show, in order, reused
local worthOf = {}  -- stat key -> what its gain is worth to your spec, this paint

local function ByOrder(a, b)
    local oa, ob = CORE[a] or 1000, CORE[b] or 1000
    if oa ~= ob then return oa < ob end
    return a < b
end

-- Most worth first, a loss by its size as a gain; even, the fixed order.
local function ByWorth(a, b)
    local wa, wb = math.abs(worthOf[a]), math.abs(worthOf[b])
    if wa ~= wb then return wa > wb end
    return ByOrder(a, b)
end

local function Amount(value)
    local amount = math.abs(value)
    local text = amount % 1 == 0 and ("%d"):format(amount) or ("%.1f"):format(amount)
    return (value > 0 and UPGRADE_CODE .. "+" or RED_CODE .. "-") .. text .. "|r"
end

local function StatName(key)
    return ns.StatWeights.KeyName(key) or _G[key] or key
end

-- The stats to show: those your spec weighs, most worth first; with no weights, the core ones.
local function Shown(stats)
    wipe(shown)
    wipe(worthOf)
    local SW, spec = ns.StatWeights, B.Lists.CurrentSpec()
    local weights = spec and SW.For(spec.key)
    for key, value in pairs(stats) do
        if value ~= 0 then
            if weights then
                local worth = SW.KeyWorth(key, value, weights)
                if worth ~= 0 then
                    worthOf[key] = worth
                    shown[#shown + 1] = key
                end
            elseif CORE[key] then
                shown[#shown + 1] = key
            end
        end
    end
    table.sort(shown, weights and ByWorth or ByOrder)
end

local scoreTexts = {}   -- "now 8.3", "with your BiS 16.3", made once each

local function ScoreText(format, score)
    local tenths = math.floor(score * 10 + 0.5)
    local byFormat = scoreTexts[format]
    if not byFormat then
        byFormat = {}
        scoreTexts[format] = byFormat
    end
    local text = byFormat[tenths]
    if not text then
        text = format:format(tenths / 10)
        byFormat[tenths] = text
    end
    return text
end

-- The scale: the best the score is graded against (the best for your level, or in the game),
-- and with Both your level's goal on it while short of the best in the game. With no data
-- yet, a little over what is shown.
local function Scale(level, now, bis)
    local Score = ns.NaowhScore
    local compare = ns.QoLSettings.Get("naowhScoreCompare")
    local goal = Score.Best(level)
    local top = Score.Best(compare == "level" and level or nil)
    if not top then top = math.max(bis, now, goal or 0) * 1.25 end
    if compare ~= "both" or not goal or goal >= top then goal = nil end
    return top, goal, compare == "level"
end

-- A stretch of the bar, from x to x2 (a stretch of nothing hides).
local function Stretch(texture, x, x2)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", x, 0)
    texture:SetPoint("BOTTOMLEFT", x, 0)
    texture:SetWidth(math.max(1, x2 - x))
    texture:SetShown(x2 - x >= 1)
end


-- The header and the bar, as the look is: run on each look change and each new read.
local function PaintScore(card)
    local gains = card.gains
    local Score, bar = ns.NaowhScore, card.bar
    local now, bis = gains.now or 0, gains.bis or 0
    if bis == 0 then
        card.value:SetText(ns.Color("muted", "Pick your BiS"))
        card.which:SetText("")
        card.other:SetText("")
        card.gain:SetText("")
        bar:Hide()
        return
    end
    local level = UnitLevel("player")
    local onNow = card.look == "now"
    card.value:SetText(Score.Colored(onNow and now or bis, level))
    card.which:SetText(onNow and "now" or "with your BiS")
    local gain = bis - now
    if gain >= 0.05 then
        card.gain:SetText(UPGRADE_CODE .. ScoreText("+%.1f", gain) .. "|r")
        card.other:SetText(onNow and "with your BiS" or ScoreText("from %.1f", now))
    else
        card.gain:SetText("")
        card.other:SetText(onNow and ScoreText("%.1f with your BiS", bis) or ScoreText("%.1f now", now))
    end
    local top, goal, ofLevel = Scale(level, now, bis)
    if top <= 0 then
        bar:Hide()
        return
    end
    local width = card.w
    local function X(score) return math.floor(math.min(1, score / top) * width + 0.5) end
    local xNow, xBis = X(now), X(math.max(bis, now))
    Stretch(bar.gain, xNow, xBis)
    Stretch(bar.rest, xBis, width)
    bar.cut:ClearAllPoints()
    bar.cut:SetPoint("TOPLEFT", xNow, 0)
    bar.cut:SetPoint("BOTTOMLEFT", xNow, 0)
    bar.cut:SetShown(xNow > 0 and xBis - xNow >= 2)
    -- The legend: the scale's top at the far end, and your level's goal under its tick
    -- unless the two would meet.
    bar.topLabel:SetText(ofLevel and ScoreText("Level " .. level .. " best %.1f", top)
        or ScoreText("Best %.1f", top))
    local xGoal = goal and X(goal)
    bar.goal:SetShown(xGoal ~= nil)
    bar.goalLabel:SetShown(xGoal ~= nil and width - xGoal >= LEGEND_MIN)
    if xGoal then
        bar.goal:ClearAllPoints()
        bar.goal:SetPoint("CENTER", bar, "LEFT", xGoal, 0)
        bar.goalLabel:ClearAllPoints()
        bar.goalLabel:SetPoint("TOP", bar, "BOTTOMLEFT", math.max(LEGEND_HALF, xGoal), -LEGEND_GAP)
        bar.goalLabel:SetText(ScoreText("Level " .. level .. " goal %.1f", goal))
    end
    bar.values[1], bar.values[2], bar.values[3], bar.values[4] = now, bis, goal or 0, top
    bar.ofLevel = ofLevel
    bar:Show()
end

--- Reads what your list's BiS gets you over what you wear and paints the whole card, as look
--- ("bis" or "now") is. Returns the read (gains.waiting: item data still loading).
function B.View.PaintScoreCard(card, list, look)
    card.look = look
    local gains = B.Gains.Read(list, card.gains)
    local grid = card.grid
    Shown(gains.stats)
    for i, cell in ipairs(grid.cells) do
        local key = shown[i]
        cell.name:SetText(key and StatName(key) or "")
        cell.value:SetText(key and Amount(gains.stats[key]) or "")
    end
    for line, band in ipairs(grid.bands) do
        band:SetShown(line % 2 == 1 and shown[(line - 1) * grid.columns + 1] ~= nil)
    end
    grid.whole:SetShown(gains.bis > 0 and #shown == 0)
    PaintScore(card)
    return gains
end

--- The score and the bar again for another look, the read as it was.
function B.View.PaintScoreLook(card, look)
    card.look = look
    PaintScore(card)
end

-- The bar's card: each value, and the scale.
local function BarEnter(bar)
    if not Tip(bar, "ANCHOR_TOP") then return end
    local values, Text = bar.values, ns.NaowhScore.Text
    local m = T.muted
    GameTooltip:SetText("Naowh Score", 1, 1, 1)
    GameTooltip:AddDoubleLine("Now", Text(values[1]), m.r, m.g, m.b, 1, 1, 1)
    GameTooltip:AddDoubleLine("With your BiS", Text(values[2]), m.r, m.g, m.b, 1, 1, 1)
    if values[3] > 0 then
        GameTooltip:AddDoubleLine("Level " .. UnitLevel("player") .. " goal", Text(values[3]),
            GOAL_RGB.r, GOAL_RGB.g, GOAL_RGB.b, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(bar.ofLevel and "Best for your level" or "Best in the game", Text(values[4]),
        m.r, m.g, m.b, 1, 1, 1)
    GameTooltip:AddLine("Filled to what you wear, dimmer on to your BiS. A level's goal is a full set "
        .. "of blues for it.", m.r, m.g, m.b, true)
    GameTooltip:Show()
end

local function Bar(card)
    local width = card.w
    local bar = CreateFrame("Frame", nil, card)
    bar:SetPoint("TOPLEFT", 0, -BAR_TOP)
    bar:SetPoint("TOPRIGHT", 0, -BAR_TOP)
    bar:SetHeight(BAR_H)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", BarEnter)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    bar.values = { 0, 0, 0, 0 }
    -- A 1px black edge, as the house's items have.
    local edge = bar:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(0, 0, 0, 1)
    ns.PixelInset(edge, -1)
    -- The ramp, a gradient between each of its stops, as long as its share of the scale.
    local ramp = ns.NaowhScore.RAMP
    for i = 1, #ramp - 1 do
        local a, b = ramp[i], ramp[i + 1]
        local segment = bar:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(1, 1, 1, 1)
        segment:SetGradient("HORIZONTAL", CreateColor(a[2], a[3], a[4], 1), CreateColor(b[2], b[3], b[4], 1))
        segment:SetPoint("TOPLEFT", a[1] * width, 0)
        segment:SetSize((b[1] - a[1]) * width, BAR_H)
    end
    bar.gain = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.gain:SetColorTexture(0, 0, 0, GAIN_ALPHA)
    bar.rest = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.rest:SetColorTexture(TRACK_RGB, TRACK_RGB, TRACK_RGB, 1)
    -- A hairline where what you wear ends and your BiS's stretch starts.
    bar.cut = bar:CreateTexture(nil, "OVERLAY")
    bar.cut:SetColorTexture(0, 0, 0, 1)
    ns.Hairline(bar.cut, "v")
    bar.goal = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    bar.goal:SetColorTexture(GOAL_RGB.r, GOAL_RGB.g, GOAL_RGB.b, 1)
    bar.goal:SetSize(TICK_W, BAR_H + TICK_OUT * 2)
    bar.goalLabel = ns.Font(bar, 11, nil, GOAL_RGB)
    bar.goalLabel:SetJustifyH("CENTER")
    bar.topLabel = ns.Font(bar, 11, nil, T.muted)
    bar.topLabel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -LEGEND_GAP)
    bar:Hide()
    return bar
end

-- The stats' grid: STAT_CELLS cells in columns, width wide, every other line on a
-- faint band, as the list's rows, so a name reads across to its amount.
local function Grid(card, width, columns)
    local grid = CreateFrame("Frame", nil, card)
    local lines = STAT_CELLS / columns
    grid:SetSize(width, lines * STAT_ROW)
    grid:SetPoint("TOPLEFT", 0, -GRID_TOP)
    grid.columns, grid.cells, grid.bands = columns, {}, {}
    local column = width / columns
    for line = 1, lines do
        local band = ns.Solid(grid, "BACKGROUND", T.fg, St.STRIPE)
        band:SetPoint("TOPLEFT", -BAND_PAD, -(line - 1) * STAT_ROW + BAND_PAD)
        band:SetPoint("TOPRIGHT", BAND_PAD, -(line - 1) * STAT_ROW + BAND_PAD)
        band:SetHeight(STAT_ROW)
        grid.bands[line] = band
    end
    for i = 1, STAT_CELLS do
        local x = ((i - 1) % columns) * column
        local y = -math.floor((i - 1) / columns) * STAT_ROW
        local name = ns.Font(grid, 12, nil, T.muted)
        name:SetPoint("TOPLEFT", x, y)
        name:SetWidth(column - VALUE_W - GRID_GAP)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        -- The last column's amounts end at the grid's edge; the others a gap short of the next.
        local value = ns.Font(grid, 12)
        local last = i % columns == 0
        value:SetPoint("TOPRIGHT", grid, "TOPLEFT", last and x + column or x + column - GRID_GAP, y)
        value:SetJustifyH("RIGHT")
        grid.cells[i] = { name = name, value = value }
    end
    grid.whole = ns.Font(grid, 12, nil, T.muted)
    grid.whole:SetPoint("TOPLEFT", 0, 0)
    grid.whole:SetText("You wear your whole BiS.")
    grid.whole:Hide()
    return grid
end

--- The card, width wide and CARD_H tall (its maker anchors it), its grid under the bar.
function B.View.ScoreCard(parent, width)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, CARD_H)
    card.w, card.look = width, "bis"
    card.gains = { stats = {} }
    local kicker = ns.Font(card, 10, nil, T.accentSoft)
    kicker:SetPoint("TOPLEFT", 0, 0)
    kicker:SetText("NAOWH SCORE")
    card.value = ns.Font(card, VALUE_SIZE, nil, T.fg)
    card.value:SetPoint("TOPLEFT", 0, -VALUE_TOP)
    card.which = ns.Font(card, 12, nil, T.muted)
    card.which:SetPoint("BOTTOMLEFT", card.value, "BOTTOMRIGHT", 6, 3)
    -- The gain on the right, on the big score's baseline, what it is from before it.
    card.gain = ns.Font(card, 16)
    card.gain:SetPoint("BOTTOMRIGHT", card.value, "BOTTOMLEFT", width, 1)
    card.other = ns.Font(card, 12, nil, T.muted)
    card.other:SetPoint("BOTTOMRIGHT", card.gain, "BOTTOMLEFT", -6, 1)
    card.bar = Bar(card)
    card.grid = Grid(card, width, 2)
    return card
end
B.View.SCORE_CARD_H = CARD_H
