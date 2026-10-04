-------------------------------------------------------------------------------
--  NaowhForever_Credits.lua -- the Credits page in the options window (/nf, Credits): the
--  team on their badges, the people we thank, and the data and libraries Naowh Forever is
--  built on, drawn on the shared row engine as cards in the house colours.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
local ICONS = MEDIA .. "Navigation\\"
local HERO_H, LOGO_SIZE, CARD_H, EMBLEM, ICON = 96, 64, 92, 52, 30
local PAD, GLOW, GLOW_ALPHA, STRIP = 16, 1.3, 0.35, 2
local CHIP_H, CHIP_GAP, CHIP_PAD = 24, 6, 10
local SECTION_GAP = 14

local function Tier(key)
    return ns.BADGE_TIERS and ns.BADGE_TIERS[key]
end

local GOLD = { r = 0xe6 / 255, g = 0xcc / 255, b = 0x80 / 255 }

local TEAM = {
    { tier = "naowh", name = "Naowh", role = "Founder", line = "The name on it, and the community it is made for." },
    { tier = "developer", name = "Glyalith", role = "Lead Developer", line = "Builds and ships Naowh Forever." },
    { tier = "developer", name = "Dieman", role = "Lead Developer", line = "Builds and ships Naowh Forever." },
}

local THANKS = {
    { tier = "moderator", name = "Moderators", role = "Community", line = "Every moderator keeping the Naowh community running." },
    { tier = "legendary", name = "Legendary Supporters", role = "Supporters", line = "Everyone wearing the Legendary badge: you keep Naowh Forever going." },
    { icon = "checklist", color = T.accentSoft, name = "Beta Testers", role = "Community", line = "Every bug report and screenshot made it better." },
}

local DATA = {
    { icon = "search", color = GOLD, name = "Wowhead", role = "Data", line = "WoW Forever's items, quests and NPCs, and what is new in Forever." },
    { icon = "trophy", color = GOLD, name = "wowsrc.com", role = "Data", line = "The BiS rankings behind the BiS List." },
    { icon = "bars", color = GOLD, name = "WoWSims", role = "Data", line = "The stat weights each spec starts with." },
    { icon = "map", color = GOLD, name = "Santiago Reyes", role = "Maps", line = "The maps of Ruins of Lordaeron, Hall of Thanes and the Excavation Site, from his Atlas de Azeroth: Forever." },
}

local LIBRARIES = { "LibStub", "CallbackHandler-1.0", "LibDataBroker-1.1", "LibDBIcon-1.0", "LibSharedMedia-3.0",
    "LibCustomGlow-1.0", "LibGetFrame-1.0", "LibDeflate", "LibSerialize" }

local SECTIONS = {
    { title = "The Team", people = TEAM },
    { title = "Thank You", people = THANKS },
    { title = "Built With", people = DATA, chips = LIBRARIES },
}

local function Smooth(texture, path)
    texture:SetTexture(path, nil, nil, "TRILINEAR")
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end

local function NewHero(view)
    local hero = CreateFrame("Frame", nil, view)
    local St = ns.Shared.Style
    ns.Solid(hero, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(hero, St.BORDER_RGB)
    hero.strip = ns.Solid(hero, "ARTWORK", T.accent, 1)
    hero.strip:SetPoint("TOPLEFT")
    hero.strip:SetPoint("TOPRIGHT")
    hero.strip:SetHeight(STRIP)
    hero.logo = Smooth(hero:CreateTexture(nil, "ARTWORK"), St.LOGO)
    hero.logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    hero.logo:SetPoint("LEFT", PAD, 0)
    hero.title = ns.Font(hero, 24, nil, T.fg)
    hero.title:SetPoint("TOPLEFT", hero.logo, "TOPRIGHT", PAD, -6)
    hero.line = ns.Font(hero, 12, nil, T.muted)
    hero.line:SetPoint("TOPLEFT", hero.title, "BOTTOMLEFT", 0, -6)
    hero.emblems = {}
    return hero
end

local HERO_TIERS = { "naowh", "developer", "moderator", "legendary" }

local function SetHero(hero)
    hero.title:SetText("Naowh " .. ns.Color("accent", "Forever"))
    hero.line:SetText(("Version %s, made by Naowh's team and the people who play it."):format(ns.CODE_BUILD or "?"))
    local x = -PAD
    for i = #HERO_TIERS, 1, -1 do
        local tier = Tier(HERO_TIERS[i])
        local emblem = hero.emblems[i]
        if not emblem then
            emblem = hero:CreateTexture(nil, "ARTWORK")
            emblem:SetSize(34, 34)
            hero.emblems[i] = emblem
        end
        emblem:SetShown(tier ~= nil)
        if tier then
            Smooth(emblem, tier.large)
            emblem:SetPoint("RIGHT", x, 0)
            x = x - 40
        end
    end
    return HERO_H
end

local function NewPerson(view)
    local card = CreateFrame("Frame", nil, view)
    local St = ns.Shared.Style
    ns.Solid(card, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(card, St.BORDER_RGB)
    card.strip = card:CreateTexture(nil, "ARTWORK")
    card.strip:SetPoint("TOPLEFT")
    card.strip:SetPoint("TOPRIGHT")
    card.strip:SetHeight(STRIP)
    card.glow = card:CreateTexture(nil, "BORDER")
    card.glow:SetBlendMode("ADD")
    card.art = card:CreateTexture(nil, "ARTWORK")
    card.art:SetPoint("LEFT", PAD, 0)
    card.glow:SetPoint("CENTER", card.art, "CENTER")
    card.name = ns.Font(card, 16, nil, T.fg)
    card.name:SetPoint("TOPLEFT", card.art, "TOPRIGHT", PAD - 2, 2)
    card.role = ns.Font(card, 10, nil, T.muted)
    card.role:SetPoint("LEFT", card.name, "RIGHT", 8, -1)
    card.line = ns.Font(card, 12, nil, T.muted)
    card.line:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
    card.line:SetJustifyH("LEFT")
    card.line:SetWordWrap(true)
    return card
end

local roleText = {}

local function Upper(text)
    local upper = roleText[text]
    if not upper then
        upper = text:upper()
        roleText[text] = upper
    end
    return upper
end

local function SetPerson(card, person, width)
    local tier = person.tier and Tier(person.tier)
    local color = tier and tier.color or person.color or T.accentSoft
    card.strip:SetColorTexture(color.r, color.g, color.b, 1)
    if tier then
        card.art:SetSize(EMBLEM, EMBLEM)
        Smooth(card.art, tier.large)
        card.art:SetVertexColor(1, 1, 1, 1)
        card.glow:Show()
        card.glow:SetSize(EMBLEM * GLOW, EMBLEM * GLOW)
        Smooth(card.glow, tier.large)
        card.glow:SetVertexColor(color.r, color.g, color.b, GLOW_ALPHA)
    else
        card.art:SetSize(ICON, ICON)
        Smooth(card.art, ICONS .. person.icon .. ".tga")
        card.art:SetVertexColor(color.r, color.g, color.b, 1)
        card.glow:Hide()
    end
    card.name:SetText(person.name)
    card.name:SetTextColor(color.r, color.g, color.b, 1)
    card.role:SetText(Upper(person.role))
    local textLeft = PAD + (tier and EMBLEM or ICON) + PAD - 2
    card.line:SetWidth(math.max(1, width - textLeft - PAD))
    card.line:SetText(person.line)
    return CARD_H
end

local function NewChips(view)
    local row = CreateFrame("Frame", nil, view)
    row.chips = {}
    return row
end

local function Chip(row, i)
    local chip = row.chips[i]
    if not chip then
        chip = CreateFrame("Frame", nil, row)
        chip:SetHeight(CHIP_H)
        ns.Solid(chip, "BACKGROUND", T.panel, 1):SetAllPoints()
        ns.Border(chip, ns.Shared.Style.BORDER_RGB)
        chip.text = ns.Font(chip, 11, nil, T.fg)
        chip.text:SetPoint("CENTER")
        row.chips[i] = chip
    end
    return chip
end

local function SetChips(row, names)
    local width = row:GetWidth()
    local x, y = 0, 0
    for i, name in ipairs(names) do
        local chip = Chip(row, i)
        chip.text:SetText(name)
        local w = math.ceil(chip.text:GetStringWidth()) + CHIP_PAD * 2
        if x > 0 and x + w > width then
            x, y = 0, y + CHIP_H + CHIP_GAP
        end
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", x, -y)
        chip:Show()
        x = x + w + CHIP_GAP
    end
    for i = #names + 1, #row.chips do row.chips[i]:Hide() end
    return y + CHIP_H
end

local kinds, view

local Draw = {}

function Draw:DrawCard(person, _, _, _, x, w)
    self.left, self.width = x, w
    local card = self:Acquire("person")
    local height = SetPerson(card, person, w)
    self.left, self.width = 0, self:GetWidth()
    return card, height
end

function Draw:Redraw()
    self:Clear()
    self:Add("hero")
    self:Space(SECTION_GAP)
    for _, section in ipairs(SECTIONS) do
        self:Section(section.title)
        self:Space(8)
        for _, person in ipairs(section.people) do self:Gather(person) end
        self:DrawGrid()
        if section.chips then self:Add("chips", section.chips) end
        self:Space(SECTION_GAP)
    end
    self:Fit({})
end

local function Kinds()
    if kinds then return kinds end
    kinds = ns.Shared.View.NewKinds()
    kinds.hero = { New = NewHero, Set = SetHero }
    kinds.person = { New = NewPerson }
    kinds.chips = { New = NewChips, Set = SetChips }
    return kinds
end

function ns.BuildCreditsPage(parent, y)
    view = parent.creditsView
    if not view then
        view = ns.Shared.View.New(parent, Kinds(), Draw)
        parent.creditsView = view
    end
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", parent, "TOPLEFT", ns.UI.CONTENT_PAD, y - ns.UI.CONTENT_PAD / 2)
    view:SetWidth(math.max(1, parent:GetWidth() - ns.UI.CONTENT_PAD * 2))
    view:Show()
    view:Redraw()
    return y - view:GetHeight() - ns.UI.CONTENT_PAD
end
