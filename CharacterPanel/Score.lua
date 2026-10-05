-------------------------------------------------------------------------------
--  Score.lua -- your Naowh Score on the character panel, as a card in the BiS List's look,
--  under your level at the top of the stats' pane (SpecStats.lua makes the room, moving the
--  game's list down), on the same left edge as the stats under it: the kicker, the score big
--  in its grade's colour, and a bar the card's width on the score's colour ramp, filled to its
--  share of the best it is graded against, that best under its end, and with Both your level's
--  goal as a gold tick on it while short of the best in the game. Only the score: your
--  BiS's is the BiS List's. Hover it for the score with your BiS, your level's goal and the
--  best in the game; click it for the BiS List. Painted when the panel opens and, while it is
--  open, when your gear changes.
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
local LEGEND_SPACE = 8              -- at least this between the goal's label and the best's
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

-- "Level 27 goal 24.4": made once per level and tenth.
local goals = {}
local function GoalLegend(level, goal)
    local byLevel = goals[level]
    if not byLevel then
        byLevel = {}
        goals[level] = byLevel
    end
    local tenths = math.floor(goal * 10 + 0.5)
    local text = byLevel[tenths]
    if not text then
        text = ("Level " .. level .. " goal %.1f"):format(tenths / 10)
        byLevel[tenths] = text
    end
    return text
end

-- With Both, your level's goal on the bar while it is short of the best in the game: a gold
-- tick, and its label under it when it fits beside the best's.
local function PaintGoal(level, best)
    local goal = S.Get("naowhScoreCompare") == "both" and ns.NaowhScore.Best(level)
    local show = goal and best and goal < best
    badge.goal:SetShown(show and true or false)
    badge.goalLabel:SetShown(false)
    if not show then return end
    local x = math.floor(CARD_W * goal / best + 0.5)
    badge.goal:ClearAllPoints()
    badge.goal:SetPoint("CENTER", badge.bar, "LEFT", x, 0)
    local label = badge.goalLabel
    label:SetText(GoalLegend(level, goal))
    local w = label:GetStringWidth()
    local left = math.max(0, x - w / 2)
    if left + w + LEGEND_SPACE + badge.best:GetStringWidth() > CARD_W then return end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", badge.bar, "BOTTOMLEFT", left, -LEGEND_GAP)
    label:Show()
end

local function Paint()
    local Score = ns.NaowhScore
    local score, level = Score.Unit("player"), UnitLevel("player")
    badge.value:SetText(Score.Colored(score, level))
    -- Filled to the share Grade Against grades it on (the best for your level, or in the game).
    local ofLevel = S.Get("naowhScoreCompare") == "level"
    local best = Score.Best(ofLevel and level or nil)
    local share = Score.Grade(score, level) or 0
    local x = math.floor(CARD_W * math.min(1, share) + 0.5)
    local rest = badge.rest
    rest:ClearAllPoints()
    rest:SetPoint("TOPLEFT", badge.bar, "TOPLEFT", x, 0)
    rest:SetPoint("BOTTOMRIGHT", badge.bar, "BOTTOMRIGHT")
    rest:SetShown(x < CARD_W)
    badge.best:SetText(best and Legend(ofLevel, level, best) or "")
    PaintGoal(level, best)
end

-- The ramp, a gradient between each of its stops, its plain track drawn over the part past
-- your score; a 1px black edge round it, as the house's items have.
local function Bar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, -BAR_TOP)
    bar:SetSize(CARD_W, BAR_H)
    local edge = bar:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(0, 0, 0, 1)
    ns.PixelInset(edge, -1)
    local ramp = ns.NaowhScore.RAMP
    for i = 1, #ramp - 1 do
        local a, b = ramp[i], ramp[i + 1]
        local segment = bar:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(1, 1, 1, 1)
        segment:SetGradient("HORIZONTAL", CreateColor(a[2], a[3], a[4], 1), CreateColor(b[2], b[3], b[4], 1))
        segment:SetPoint("TOPLEFT", a[1] * CARD_W, 0)
        segment:SetSize((b[1] - a[1]) * CARD_W, BAR_H)
    end
    parent.rest = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    parent.rest:SetColorTexture(TRACK_RGB, TRACK_RGB, TRACK_RGB, 1)
    parent.best = ns.Font(parent, LEGEND_SIZE, nil, T.muted)
    parent.best:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -LEGEND_GAP)
    parent.goal = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    parent.goal:SetColorTexture(GOAL_RGB.r, GOAL_RGB.g, GOAL_RGB.b, 1)
    parent.goal:SetSize(TICK_W, BAR_H + TICK_OUT * 2)
    parent.goal:Hide()
    parent.goalLabel = ns.Font(parent, LEGEND_SIZE, nil, GOAL_RGB)
    parent.goalLabel:Hide()
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

local function Build()
    -- On the panel itself, not its right pane: the restyle fades the pane's own frames.
    local right = CharacterFrame.RightPaneHost
    badge = CreateFrame("Button", nil, CharacterFrame)
    badge:SetPoint("TOP", CharacterLevelText, "BOTTOM", 0, -GAP)
    badge:SetSize(CARD_W, CP.BADGE_H)
    badge:SetFrameLevel(right:GetFrameLevel() + 20)
    local kicker = ns.Font(badge, KICKER_SIZE, nil, T.accentSoft)
    kicker:SetPoint("TOPLEFT")
    kicker:SetText("NAOWH SCORE")
    badge.value = ns.Font(badge, VALUE_SIZE, nil, T.fg)
    badge.value:SetPoint("TOPLEFT", 0, -VALUE_TOP)
    -- A soft shadow under it, so the big number sits on the panel as the badge's title does.
    badge.value:SetShadowColor(0, 0, 0, SHADOW_ALPHA)
    badge.value:SetShadowOffset(SHADOW_X, -SHADOW_X)
    badge.bar = Bar(badge)
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
    if on and not installed and CharacterFrame then
        installed = true
        Build()
        local pane = CharacterLevelText:GetParent()
        if pane then
            pane:HookScript("OnShow", Apply)
            pane:HookScript("OnHide", Apply)
        end
    end
    if not installed then return end
    badge:SetShown(on and CharacterLevelText:IsVisible())
    if on and badge:IsVisible() then Paint() end
end
CP.ApplyScore = Apply

S.OnChange(function(key)
    if key == "enabled" or key:find("^characterPanel") or key == "naowhScoreCompare" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
