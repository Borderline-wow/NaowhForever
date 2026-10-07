-------------------------------------------------------------------------------
--  Score.lua -- your Naowh Score on the character panel, as a card in the BiS List's look,
--  under your level at the top of the stats' pane (SpecStats.lua makes the room, moving the
--  game's list down), on the same left edge as the stats under it: the kicker, the score big
--  in its grade's colour, and a bar the card's width on the score's colour ramp, filled to its
--  share of the best it is graded against, that best under its end, and with Both your level's
--  goal as a gold tick on it (named in the tooltip) while short of the best in the game. Only
--  the score: your BiS's is the BiS List's. Hover it for the score with your BiS, your level's
--  goal and the best in the game; click it for the BiS List. A child of the game's stats list
--  (its fade ignored), so the game hides it with the list whenever its gear sets, titles or pet
--  take that room, and it never sits over their rows. Painted when it shows and, while it is
--  shown, when your gear changes.
--  CP.ScoreCard and CP.PaintScoreCard draw the same card for another player on the Naowh
--  Inspect Panel (InspectPanel/).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local CP = ns.CharacterPanel
local B = ns.BiS

local GAP = 10                       -- under your level
local CARD_W = CP.PANE_W - 2 * CP.EDGE
-- The card's rows, from its top: the kicker, the big score, the bar, its legend.
local KICKER_SIZE = 10
local VALUE_TOP, VALUE_SIZE = 13, 26
local SHADOW_ALPHA, SHADOW_X = 0.8, 1   -- the big score's shadow: down and right this far
local BAR_TOP, BAR_H = 46, 6
local LEGEND_GAP, LEGEND_SIZE = 4, 10
local TRACK_RGB = 0.16               -- the bar past your score, as the score card's
local GOAL_RGB = { r = 1, g = 0.82, b = 0 }   -- a level's goal, gold as on the score card
local TICK_W, TICK_OUT = 2, 3       -- the goal's tick, and how far it stands out over and under the bar
CP.BADGE_GAP = GAP
CP.BADGE_H = BAR_TOP + BAR_H + LEGEND_GAP + LEGEND_SIZE + 2

local badge, installed
local gains = { stats = {} }   -- your BiS over what you wear, read on hover, reused

local function BadgeOn()
    return CP.On() and S.Get("characterPanelScore") == true
end

-- "Best 58.8", "Level 20 best 18.9": made once per level and tenth.
local legends = {}
local function Legend(ofLevel, level, best)
    local key = ofLevel and level or 0
    local byLevel = legends[key]
    if not byLevel then
        byLevel = {}
        legends[key] = byLevel
    end
    local tenths = math.floor(best * 10 + 0.5)
    local text = byLevel[tenths]
    if not text then
        text = (ofLevel and "Level " .. level .. " best %.1f" or "Best %.1f"):format(tenths / 10)
        byLevel[tenths] = text
    end
    return text
end

-- With Both, your level's goal on the bar while it is short of the best in the game: a gold
-- tick; the tooltip says what it is.
local function PaintGoal(card, level, best)
    local goal = S.Get("naowhScoreCompare") == "both" and ns.NaowhScore.Best(level)
    local show = goal and best and goal < best
    card.goal:SetShown(show and true or false)
    if not show then return end
    local x = math.floor(card.barW * goal / best + 0.5)
    card.goal:ClearAllPoints()
    card.goal:SetPoint("CENTER", card.bar, "LEFT", x, 0)
end

-- The bar filled to x, the plain track past it.
local function Fill(card, x)
    local rest = card.rest
    rest:ClearAllPoints()
    rest:SetPoint("TOPLEFT", card.bar, "TOPLEFT", x, 0)
    rest:SetPoint("BOTTOMRIGHT", card.bar, "BOTTOMRIGHT")
    rest:SetShown(x < card.barW)
end

--- A score card painted for a score at a level (a player's own level, for Grade Against).
function CP.PaintScoreCard(card, score, level)
    local Score = ns.NaowhScore
    card.value:SetText(Score.Colored(score, level))
    -- Filled to the share Grade Against grades it on (the best for your level, or in the game).
    local ofLevel = S.Get("naowhScoreCompare") == "level"
    local best = Score.Best(ofLevel and level or nil)
    local share = Score.Grade(score, level) or 0
    Fill(card, math.floor(card.barW * math.min(1, share) + 0.5))
    card.best:SetText(best and Legend(ofLevel, level, best) or "")
    PaintGoal(card, level, best)
end

--- A score card with no score yet: "..." over an empty bar.
function CP.ScoreCardWaiting(card)
    card.value:SetText(CP.WAITING)
    Fill(card, 0)
    card.best:SetText("")
    card.goal:Hide()
end
CP.WAITING = "..."

local function Paint()
    CP.PaintScoreCard(badge, ns.NaowhScore.Unit("player"), UnitLevel("player"))
end

-- The ramp, a gradient between each of its stops, its plain track drawn over the part past
-- your score; a 1px black edge round it, as the house's items have.
local function Bar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, -BAR_TOP)
    bar:SetHeight(BAR_H)
    local edge = bar:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(0, 0, 0, 1)
    ns.PixelInset(edge, -1)
    local ramp = ns.NaowhScore.RAMP
    parent.segments = {}
    for i = 1, #ramp - 1 do
        local a, b = ramp[i], ramp[i + 1]
        local segment = bar:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(1, 1, 1, 1)
        segment:SetGradient("HORIZONTAL", CreateColor(a[2], a[3], a[4], 1), CreateColor(b[2], b[3], b[4], 1))
        parent.segments[i] = segment
    end
    parent.rest = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    parent.rest:SetColorTexture(TRACK_RGB, TRACK_RGB, TRACK_RGB, 1)
    parent.best = ns.Font(parent, LEGEND_SIZE, nil, T.muted)
    parent.best:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -LEGEND_GAP)
    parent.goal = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    parent.goal:SetColorTexture(GOAL_RGB.r, GOAL_RGB.g, GOAL_RGB.b, 1)
    parent.goal:SetSize(TICK_W, BAR_H + TICK_OUT * 2)
    parent.goal:Hide()
    return bar
end

local function Enter(frame)
    local Score = ns.NaowhScore
    if not ns.Shared.Parts.Tip(frame, "ANCHOR_BOTTOM") then return end
    local m, level = T.muted, UnitLevel("player")
    GameTooltip:SetText("Naowh Score", 1, 1, 1)
    GameTooltip:AddDoubleLine("Now", Score.Colored((Score.Unit("player")), level), m.r, m.g, m.b)
    local read = B.Gains.Read(B.Lists.List(), gains)
    if read.bis and read.bis > 0 then
        GameTooltip:AddDoubleLine("With your BiS", Score.Colored(read.bis, level), m.r, m.g, m.b)
    end
    local goal, best = Score.Best(level), Score.Best()
    if goal and best and goal < best then
        GameTooltip:AddDoubleLine("Level " .. level .. " goal", Score.Text(goal), GOAL_RGB.r, GOAL_RGB.g,
            GOAL_RGB.b, 1, 1, 1)
    end
    if best then GameTooltip:AddDoubleLine("Best in the game", Score.Text(best), m.r, m.g, m.b, 1, 1, 1) end
    GameTooltip:AddLine("Click to open the BiS List.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function OnEvent()
    if badge:IsVisible() then Paint() end
end

local function Shown()
    badge:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    Paint()
end

local function Hidden()
    badge:UnregisterAllEvents()
end

local function Clicked()
    ns.OpenBisWindow()
end

--- The score card on parent, CARD_W wide and CP.BADGE_H tall: the kicker, the value (big),
--- the bar on the score's ramp and the best under its end. Placed and painted by the caller.
function CP.SizeScoreCard(card, width)
    card.barW = width
    card:SetWidth(width)
    card.bar:SetWidth(width)
    local ramp = ns.NaowhScore.RAMP
    for i, segment in ipairs(card.segments) do
        local a, b = ramp[i], ramp[i + 1]
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", a[1] * width, 0)
        segment:SetSize((b[1] - a[1]) * width, BAR_H)
    end
end

function CP.ScoreCard(parent, width)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(CP.BADGE_H)
    local kicker = ns.Font(card, KICKER_SIZE, nil, T.accentSoft)
    kicker:SetPoint("TOPLEFT")
    kicker:SetText("NAOWH SCORE")
    card.kicker = kicker
    card.value = ns.Font(card, VALUE_SIZE, nil, T.fg)
    card.value:SetPoint("TOPLEFT", 0, -VALUE_TOP)
    -- A soft shadow under it, so the big number sits on the panel as the badge's title does.
    card.value:SetShadowColor(0, 0, 0, SHADOW_ALPHA)
    card.value:SetShadowOffset(SHADOW_X, -SHADOW_X)
    card.bar = Bar(card)
    CP.SizeScoreCard(card, width or CARD_W)
    return card
end
CP.CARD_W, CP.LEGEND_SIZE, CP.LEGEND_GAP, CP.GOAL_RGB = CARD_W, LEGEND_SIZE, LEGEND_GAP, GOAL_RGB

local function Build()
    local stats = CharacterStatsPaneScrollBox
    badge = CP.ScoreCard(stats)
    badge:SetIgnoreParentAlpha(true)
    badge:SetPoint("TOP", CharacterLevelText, "BOTTOM", 0, -GAP)
    badge:SetFrameLevel(stats:GetFrameLevel() + 20)
    badge:SetScript("OnEnter", Enter)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    badge:SetScript("OnClick", Clicked)
    badge:SetScript("OnEvent", OnEvent)
    badge:SetScript("OnShow", Shown)
    badge:SetScript("OnHide", Hidden)
    CP.badge = badge
end

local function Apply()
    local on = BadgeOn()
    if on and not installed and CharacterStatsPaneScrollBox then
        installed = true
        Build()
    end
    if not installed then return end
    badge:SetShown(on)
    if on and badge:IsVisible() then Paint() end
end
CP.ApplyScore = Apply

S.OnChange(function(key)
    if key == "enabled" or key:find("^characterPanel") or key == "naowhScoreCompare" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
