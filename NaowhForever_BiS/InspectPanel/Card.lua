-------------------------------------------------------------------------------
--  Card.lua -- the inspected player's Naowh Score as the character panel's score card, at the
--  top of our pane, with yours under the bar's start to compare; and their supporter badge
--  plate in the model's top-left corner, as on your panel. The score is read from their gear
--  while the game's inspect data is theirs (and kept for their tooltip), else the last read
--  or the one their Naowh Forever shared; "..." while their items load, never another
--  player's. Hover the card for both scores and the bests they are graded against.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local IP = ns.InspectPanel
local CP = ns.CharacterPanel

local YOU = "You "
local PLATE_LEVEL = 10

local card, plate
local last = {}

local function ScoreOn()
    return IP.On() and S.Get("inspectPanelScore") == true
end

local function BadgeOn()
    local wanted = S.Get("inspectPanelBadge")
    if ns.FEATURE_BADGES ~= 1 then wanted = S.Default("inspectPanelBadge") end
    return IP.On() and wanted == true
end

local function LevelOf(unit)
    local level = UnitLevel(unit)
    return level and level > 0 and level or nil
end

local function TheirScore(unit, guid)
    local Score = ns.NaowhScore
    if IP.Ready(guid) and IP.HasGear(unit, guid) then
        local score, complete = Score.Unit(unit)
        if complete then
            last.guid, last.score, last.level = guid, score, LevelOf(unit)
            Score.Remember(guid, score, true, false, last.level)
            return score, last.level
        end
        IP.Wait()
    end
    if last.guid == guid then return last.score, last.level end
    local known = Score.Known(guid)
    if known then return known.score, known.level or LevelOf(unit) end
end

local function Paint(unit, guid)
    local Score = ns.NaowhScore
    local score, level
    if guid then score, level = TheirScore(unit, guid) end
    card.score, card.level = score, level
    if score then CP.PaintScoreCard(card, score, level) else CP.ScoreCardWaiting(card) end
    card.you:SetText(YOU .. Score.Colored((Score.Unit("player")), LevelOf("player")))
end

local function PaintPlate(guid)
    local shown = BadgeOn() and guid ~= nil and ns.BadgeOf(guid) ~= nil
    plate:SetShown(shown)
    if shown then CP.PaintBadgePlate(plate, guid) end
end

local function Enter(self)
    local Score = ns.NaowhScore
    if not ns.Shared.Parts.Tip(self, "ANCHOR_BOTTOM") then return end
    local m = T.muted
    local unit = IP.unit
    GameTooltip:SetText("Naowh Score", 1, 1, 1)
    local name = unit and UnitName(unit)
    GameTooltip:AddDoubleLine(IP.Readable(name) and name or "Them",
        card.score and Score.Colored(card.score, card.level) or CP.WAITING, m.r, m.g, m.b)
    GameTooltip:AddDoubleLine("You", Score.Colored((Score.Unit("player")), LevelOf("player")), m.r, m.g, m.b)
    local goal, best = card.level and Score.Best(card.level), Score.Best()
    if goal and best and goal < best then
        local gold = CP.GOAL_RGB
        GameTooltip:AddDoubleLine("Level " .. card.level .. " goal", Score.Text(goal), gold.r, gold.g, gold.b, 1, 1, 1)
    end
    if best then GameTooltip:AddDoubleLine("Best in the game", Score.Text(best), m.r, m.g, m.b, 1, 1, 1) end
    GameTooltip:Show()
end

local function Build()
    card = CP.ScoreCard(IP.pane)
    card:SetPoint("TOPLEFT", IP.EDGE, -IP.CARD_GAP)
    card.you = ns.Font(card, CP.LEGEND_SIZE, nil, T.muted)
    card.you:SetPoint("TOPLEFT", card.bar, "BOTTOMLEFT", 0, -CP.LEGEND_GAP)
    card:SetScript("OnEnter", Enter)
    card:SetScript("OnLeave", GameTooltip_Hide)
    IP.card = card
    local parent = InspectPaperDollFrame or InspectFrame
    plate = CP.BadgePlate(parent)
    local model = InspectModelFrame or parent
    plate:SetPoint("TOPLEFT", model, "TOPLEFT", CP.BADGE_INSET, -CP.BADGE_INSET)
    plate:SetFrameLevel(model:GetFrameLevel() + PLATE_LEVEL)
    plate:Hide()
    IP.plate = plate
end

IP.OnApply(function(on)
    if on and not card then Build() end
    if not card then return end
    card:SetShown(ScoreOn())
    if not BadgeOn() then plate:Hide() end
end)

IP.OnRefresh(function(unit, guid)
    if ScoreOn() then Paint(unit, guid) end
    PaintPlate(guid)
end)
