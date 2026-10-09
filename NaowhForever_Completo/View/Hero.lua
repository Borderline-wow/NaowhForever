-- Hero.lua: the card on top of a Completo page: done of total, as a count and a bar.
local ns = _G.NaowhForever

local T = ns.THEME
local Completo = ns.Completo
local Parts = ns.Shared.Parts
local Style = Completo.Style
local V = Completo.View

local HERO_H = 84
local COUNT_GAP = 4
local ABOUT_GAP, ABOUT_DROP = 10, 3
local BAR_GAP = 12
local TEXT_COUNT = "%d / %d"

local function NewHero(parent)
    local hero = CreateFrame("Frame", nil, parent)
    ns.Solid(hero, "BACKGROUND", T.fg, Style.CARD_FILL):SetAllPoints()
    ns.Border(hero, Style.BORDER_RGB)
    hero.kicker = ns.Font(hero, Style.KICKER_SIZE, nil, T.accentSoft)
    hero.kicker:SetPoint("TOPLEFT", Style.HERO_PAD, -Style.HERO_TOP)
    hero.count = ns.Font(hero, Style.COUNT_SIZE, nil, T.fg)
    hero.count:SetPoint("TOPLEFT", hero.kicker, "BOTTOMLEFT", 0, -COUNT_GAP)
    hero.about = ns.Font(hero, Style.TEXT_SIZE, nil, T.muted)
    hero.about:SetPoint("BOTTOMLEFT", hero.count, "BOTTOMRIGHT", ABOUT_GAP, ABOUT_DROP)
    hero.bar = Parts.ProgressLine(hero, Style.BAR_H)
    hero.bar:SetPoint("TOPLEFT", hero.count, "BOTTOMLEFT", 0, -BAR_GAP)
    hero.bar:SetPoint("RIGHT", -Style.HERO_PAD, 0)
    return hero
end

local function SetHero(hero, kicker, n, total, about)
    hero.kicker:SetText(kicker:upper())
    hero.count:SetText(TEXT_COUNT:format(n, total))
    hero.about:SetText(about)
    hero.bar:SetProgress(V.Share(n, total))
    return HERO_H
end

V.Kinds.hero = { New = NewHero, Set = SetHero }
