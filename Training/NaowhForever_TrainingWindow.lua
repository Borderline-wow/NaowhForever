-------------------------------------------------------------------------------
--  NaowhForever_TrainingWindow.lua -- the Training Planner's own window (/nftraining, its
--  minimap and top bar button). Across the top what your next trainer visit costs against
--  your gold, then your road to 60: a dot for every level that brings spells, sized by what
--  they cost; click one for that level. Below, the spells you can train now as cards, then
--  the ones waiting on a rank, coming soon, needing a talent or skipped, and one line per
--  later level. Made the first time it opens; movable, and it remembers where you put it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local Training = ns.Training
local S = ns.TrainingSettings

local WIDTH, HEIGHT = 940, 780
local HEADER = 52          -- the title bar, to its rule
local PAD = 18
local LOGO = "Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga"
local LOGO_SIZE = 30
local CIRCLE_MASK = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"
local HERO_H = 140
local LABEL_Y = 18         -- a strip's small caps label, from its top
local BAR_W, BAR_H = 440, 6
local ROAD_H = 108
local TRACK_Y = 64         -- the road's line, from the strip's top
local DOT_MIN, DOT_MAX = 10, 20
local DOT_EDGE = 2         -- a level still to come is a ring this thick
local YOU_GAP = 6          -- the YOU tag above the largest dot
local ROAD_TICKS = { 1, 10, 20, 30, 40, 50, 60 }
local MAX_LEVEL = 60
local COLS = 3
local CARD_H, CARD_GAP, CARD_ICON = 58, 10, 36
local ROW_H, ROW_GAP, ROW_ICON = 30, 4, 22
local LATER_ICON, LATER_ICONS = 20, 5   -- a later level's spells, as icons before their names
local SECTION_H = 34
local SECTION_GAP = 18
local SKIP_W, SKIP_H = 46, 18
local BLACK = { r = 0, g = 0, b = 0 }
local WARN = { r = 0.94, g = 0.70, b = 0.29 }   -- short of gold, waiting on something
local UP = { r = 0.30, g = 0.82, b = 0.48 }     -- how much stronger a rank is
local UP_COLOR = "|cff4dd17a"
local SHADOW = 0.85       -- the text shadow's opacity
local DIM = 0.45           -- a learned spell in a level's cards
local MAX_LATER = 12       -- later levels listed before "and N more"
local SEARCH_W = 180
local LOAD_SETTLE = 0.1    -- seconds to gather spell descriptions arriving together
local MINI_W, MINI_H, MINI_PAD, MINI_LOGO = 340, 74, 10, 16

local window, scroll, body
local selected             -- the level shown, or nil for every level
local loadQueued = false

-------------------------------------------------------------------------------
--  Pooled parts, made once and reused on every draw
-------------------------------------------------------------------------------
local pools = {}

local function Take(kind, make)
    local pool = pools[kind]
    if not pool then
        pool = { list = {}, used = 0 }
        pools[kind] = pool
    end
    pool.used = pool.used + 1
    local f = pool.list[pool.used]
    if not f then
        f = make()
        pool.list[pool.used] = f
    end
    f:ClearAllPoints()
    f:Show()
    return f
end

local function ReleaseAll()
    for _, pool in pairs(pools) do
        for i = 1, #pool.list do pool.list[i]:Hide() end
        pool.used = 0
    end
end

local function Paint(fs, c)
    fs:SetTextColor(c.r, c.g, c.b, 1)
end

-- The house font with a soft drop shadow: on the dark panels it reads sharper than flat
-- text, as the game's own fonts do.
local function Text(parent, size, flags, color)
    local fs = ns.Font(parent, size, flags, color)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, SHADOW)
    return fs
end

-------------------------------------------------------------------------------
--  A spell: its tooltip, its menu, a link
-------------------------------------------------------------------------------
local function Reason(entry, state)
    if state == "rank" then
        return "Learn " .. (C_Spell.GetSpellName(entry.needs) or "") .. " ("
            .. (C_Spell.GetSpellSubtext(entry.needs) or "") .. ") first."
    elseif state == "talent" then
        return "Needs the talent " .. (C_Spell.GetSpellName(entry.talent) or "") .. "."
    elseif state == "soon" or state == "later" then
        return "Trainable at level " .. entry[1] .. "."
    elseif entry.quest then
        return "Taught by a quest, not a trainer."
    end
end

-- "+100%" in green after a rank's name: how much stronger it is than the rank before.
local function UpgradeTag(entry)
    local up = Training.Upgrade(entry)
    return up and ("  " .. UP_COLOR .. "+" .. up.pct .. "%|r") or ""
end

local function SpellEnter(self)
    self.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.entry[2])
    local up = Training.Upgrade(self.entry)
    if up then
        local before = self.entry.needs or self.entry.talent
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Over %s: %s %s to %s, +%d%%"):format(C_Spell.GetSpellSubtext(before) or "the rank before",
            up.what, up.from, up.to, up.pct), UP.r, UP.g, UP.b, true)
    end
    local reason = Reason(self.entry, self.state)
    if reason then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(reason, WARN.r, WARN.g, WARN.b, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link it. Right-click to skip it.", T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function SpellLeave(self)
    self.border:SetColor(T.line.r, T.line.g, T.line.b, 1)
    GameTooltip:Hide()
end

local function SpellClick(self, button)
    local spell = self.entry[2]
    if button == "RightButton" then
        local skipped = self.state == "ignored"
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(C_Spell.GetSpellName(spell) or ("Spell " .. spell))
            if skipped then
                root:CreateButton("Stop Skipping", function() Training.SetIgnored(spell, false, false) end)
                root:CreateButton("Stop Skipping All Ranks", function() Training.SetIgnored(spell, true, false) end)
            else
                root:CreateButton("Skip", function() Training.SetIgnored(spell, false, true) end)
                root:CreateButton("Skip All Ranks", function() Training.SetIgnored(spell, true, true) end)
            end
        end)
    elseif IsModifiedClick("CHATLINK") then
        ChatFrameUtil.InsertLink(C_Spell.GetSpellLink(spell))
    end
end

local function PriceText(entry)
    local price = Training.Price(entry)
    if price > 0 then return Training.Coins(price) end
    if entry.quest then return ns.Color("muted", "Quest") end
    return ns.Color("muted", "At the trainer")
end

local function SpellButton(height)
    local b = CreateFrame("Button", nil, body)
    b:SetHeight(height)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.bg = ns.Solid(b, "BACKGROUND", T.panel, 1)
    b.bg:SetAllPoints()
    b.border = ns.Border(b, T.line)
    b:SetScript("OnEnter", SpellEnter)
    b:SetScript("OnLeave", SpellLeave)
    b:SetScript("OnClick", SpellClick)
    return b
end

-------------------------------------------------------------------------------
--  Cards, rows, section headers
-------------------------------------------------------------------------------
-- A spell icon in the house's 1px black edge, trimmed of the art's own border. Anchor the
-- edge (icon.edge); the icon sits inside it.
local function Icon(parent, size)
    local edge = parent:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(0, 0, 0, 1)
    edge:SetSize(size + 2, size + 2)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("CENTER", edge)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.edge = edge
    return icon
end

local function NewCard()
    local c = SpellButton(CARD_H)
    c.icon = Icon(c, CARD_ICON)
    c.icon.edge:SetPoint("LEFT", 10, 0)
    c.name = Text(c, 14, nil)
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -2)
    c.name:SetPoint("RIGHT", -60, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.rank = Text(c, 12, nil, T.muted)
    c.rank:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 10, 2)
    c.price = Text(c, 13, nil)
    c.price:SetPoint("TOPRIGHT", -10, -10)
    c.skip = ns.Button(c, "Skip", SKIP_W, SKIP_H)
    c.skip:SetPoint("BOTTOMRIGHT", -8, 8)
    return c
end

local function Card(entry, state, x, y, w)
    local c = Take("card", NewCard)
    c:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
    c:SetWidth(w)
    c.entry, c.state = entry, state
    local learned = state == "learned"
    c.icon:SetTexture(C_Spell.GetSpellTexture(entry[2]))
    c.icon:SetDesaturated(state ~= "now")
    c.name:SetText(C_Spell.GetSpellName(entry[2]) or "")
    c.rank:SetText(learned and "Learned" or ((C_Spell.GetSpellSubtext(entry[2]) or "") .. UpgradeTag(entry)))
    c.price:SetText(PriceText(entry))
    c:SetAlpha(learned and DIM or 1)
    c.skip:SetShown(state == "now")
    c.skip._onClick = function() Training.SetIgnored(entry[2], false, true) end
    return c
end

local function NewRow()
    local r = SpellButton(ROW_H)
    r.icon = Icon(r, ROW_ICON)
    r.icon.edge:SetPoint("LEFT", 5, 0)
    r.name = Text(r, 13, nil)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.rank = Text(r, 12, nil, T.muted)
    r.rank:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.price = Text(r, 13, nil)
    r.price:SetPoint("RIGHT", -8, 0)
    r.why = Text(r, 12, nil, WARN)
    r.why:SetPoint("RIGHT", r.price, "LEFT", -16, 0)
    r.restore = ns.Button(r, "Restore", 64, 20)
    r.restore:SetPoint("RIGHT", r.price, "LEFT", -12, 0)
    return r
end

local function Row(entry, state, y, why)
    local r = Take("row", NewRow)
    r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
    r.entry, r.state = entry, state
    r.icon:SetTexture(C_Spell.GetSpellTexture(entry[2]))
    r.icon:SetDesaturated(true)
    r.name:SetText(C_Spell.GetSpellName(entry[2]) or "")
    r.rank:SetText((C_Spell.GetSpellSubtext(entry[2]) or "") .. (state == "learned" and "" or UpgradeTag(entry)))
    r.price:SetText(PriceText(entry))
    r.why:SetText(why or "")
    -- Amber only where something stands in the way: a rank or a talent first.
    Paint(r.why, (state == "rank" or state == "talent") and WARN or T.muted)
    r.why:SetShown(state ~= "ignored")
    r.restore:SetShown(state == "ignored")
    r.restore._onClick = function() Training.SetIgnored(entry[2], false, false) end
    return y - ROW_H - ROW_GAP
end

local function NewHeader()
    local h = CreateFrame("Frame", nil, body)
    h:SetHeight(SECTION_H)
    h.title = Text(h, 15, nil)
    h.title:SetPoint("BOTTOMLEFT", 0, 9)
    h.note = Text(h, 12, nil, T.muted)
    h.note:SetPoint("BOTTOMRIGHT", 0, 9)
    local rule = ns.Solid(h, "ARTWORK", T.line, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    return h
end

local function Header(y, title, count, note)
    local h = Take("header", NewHeader)
    h:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    h:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
    h.title:SetText(title .. (count and ("  " .. ns.Color("accent", count)) or ""))
    h.note:SetText(note or "")
    return y - SECTION_H - 8
end

local function Cards(entries, y, stateOf)
    local w = math.floor((body:GetWidth() - (COLS - 1) * CARD_GAP) / COLS)
    for i, entry in ipairs(entries) do
        local col, line = (i - 1) % COLS, math.floor((i - 1) / COLS)
        Card(entry, stateOf(entry), col * (w + CARD_GAP), y - line * (CARD_H + CARD_GAP), w)
    end
    return y - math.ceil(#entries / COLS) * (CARD_H + CARD_GAP)
end

local function NewLater()
    local b = CreateFrame("Button", nil, body)
    b:SetHeight(ROW_H)
    b.bg = ns.Solid(b, "BACKGROUND", T.panel, 0.6)
    b.bg:SetAllPoints()
    b.border = ns.Border(b, T.line)
    b.level = Text(b, 13, nil)
    b.level:SetPoint("LEFT", 10, 0)
    b.level:SetWidth(70)
    b.level:SetJustifyH("LEFT")
    b.price = Text(b, 13, nil)
    b.price:SetPoint("RIGHT", -8, 0)
    -- The level's spells as small icons, then their names.
    b.icons = {}
    for i = 1, LATER_ICONS do
        local icon = Icon(b, LATER_ICON)
        icon.edge:SetPoint("LEFT", b.level, "RIGHT", (i - 1) * (LATER_ICON + 4), 0)
        b.icons[i] = icon
    end
    b.names = Text(b, 12, nil, T.muted)
    b.names:SetPoint("LEFT", b.level, "RIGHT", LATER_ICONS * (LATER_ICON + 4) + 8, 0)
    b.names:SetPoint("RIGHT", b.price, "LEFT", -12, 0)
    b.names:SetJustifyH("LEFT")
    b.names:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
    b:SetScript("OnLeave", function(self) self.border:SetColor(T.line.r, T.line.g, T.line.b, 1) end)
    return b
end

-------------------------------------------------------------------------------
--  The window's top: the next visit, and the road to 60
-------------------------------------------------------------------------------
local Render

local function Select(level)
    selected = level
    Render()
    scroll:SetVerticalScroll(0)
end

local function DotEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Level " .. self.level, 1, 1, 1)
    GameTooltip:AddLine(self.summary, T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:AddLine("Click to see them.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

-- A disc drawn from the circle art itself, tinted. Pixel snapping would throw away the art's
-- antialiasing and leave small circles jagged (as the options toggle found).
local function Disc(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetTexture(CIRCLE_MASK, "CLAMP", "CLAMP", "TRILINEAR")
    tex:SetTexelSnappingBias(0)
    tex:SetSnapToPixelGrid(false)
    return tex
end

-- A dot is two discs: its edge, and inside it a fill; a filled dot has both the same colour,
-- a ring has the window's background inside. A third, larger and faint, marks the level shown.
local function NewDot()
    local d = CreateFrame("Button", nil, window.road)
    d.edge = Disc(d, "ARTWORK", 1)
    d.edge:SetAllPoints()
    d.fill = Disc(d, "ARTWORK", 2)
    d.fill:SetPoint("TOPLEFT", DOT_EDGE, -DOT_EDGE)
    d.fill:SetPoint("BOTTOMRIGHT", -DOT_EDGE, DOT_EDGE)
    d.ring = Disc(d, "BORDER")
    d.ring:SetPoint("CENTER")
    d.ring:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 0.25)
    d:SetScript("OnEnter", DotEnter)
    d:SetScript("OnLeave", GameTooltip_Hide)
    d:SetScript("OnClick", function(self) Select(self.level ~= selected and self.level or nil) end)
    return d
end

local function RoadX(level)
    return (level - 1) / (MAX_LEVEL - 1) * window.road:GetWidth()
end

local function DrawRoad(plan)
    local road = window.road
    local most = 1
    for _, group in pairs(plan.byLevel) do most = math.max(most, Training.Total(group)) end
    road.done:SetWidth(math.max(1, RoadX(math.min(plan.level, MAX_LEVEL))))
    for level, group in pairs(plan.byLevel) do
        local d = Take("dot", NewDot)
        local cost = Training.Total(group)
        -- Even sizes, so a dot centres on the line without a half pixel.
        local size = 2 * math.floor((DOT_MIN + (DOT_MAX - DOT_MIN) * math.sqrt(cost / most)) / 2 + 0.5)
        local learned = 0
        for _, entry in ipairs(group) do
            if plan.known[entry[2]] then learned = learned + 1 end
        end
        d.level = level
        d.summary = ("%d spells, %s; %d learned"):format(#group, Training.Coins(cost), learned)
        d:SetSize(size, size)
        d:SetPoint("CENTER", road.track, "LEFT", RoadX(level), 0)
        -- Done: filled grey. Trainable now: filled accent. Coming soon: an accent ring. Later: a grey ring.
        local edge, inside
        if learned == #group then
            edge, inside = T.line, T.line
        elseif level <= plan.level then
            edge, inside = T.accent, T.accent
        elseif level <= plan.level + Training.SOON then
            edge, inside = T.accent, T.bg
        else
            edge, inside = T.muted, T.bg
        end
        d.edge:SetVertexColor(edge.r, edge.g, edge.b, 1)
        d.fill:SetVertexColor(inside.r, inside.g, inside.b, 1)
        d.ring:SetSize(size + 10, size + 10)
        d.ring:SetShown(level == selected)
    end
    road.you:ClearAllPoints()
    road.you:SetPoint("BOTTOM", road.track, "LEFT", RoadX(math.min(plan.level, MAX_LEVEL)), DOT_MAX / 2 + YOU_GAP)
end

-- The visit the strip is about: what you can train now, else the first level still to come.
local function NextVisit(plan)
    if #plan.now > 0 then return plan.now end
    local first = plan.soon[1] or plan.later[1]
    if not first then return {}, nil end
    local list = {}
    for _, entry in ipairs(plan.soon[1] and plan.soon or plan.later) do
        if entry[1] == first[1] then list[#list + 1] = entry end
    end
    return list, first[1]
end

local function DrawHero(plan)
    local hero = window.hero
    local list, atLevel = NextVisit(plan)
    local cost, gold = Training.Total(list), GetMoney()
    hero.label:SetText(atLevel and ("NEXT TRAINER VISIT, LEVEL " .. atLevel) or "NEXT TRAINER VISIT")
    hero.cost:SetText(#list > 0 and Training.Coins(cost) or "Nothing left to learn")
    local spells = #list == 1 and "1 spell" or (#list .. " spells")
    hero.count:SetText(#list == 0 and "" or atLevel and spells or (spells .. " ready to train"))
    hero.gold:SetText(Training.Coins(gold))
    hero.sixty:SetText(Training.Coins(Training.ToSixty(plan)))
    local enough = gold >= cost
    local fill = cost > 0 and math.min(1, gold / cost) or 0
    hero.track:SetShown(cost > 0)
    hero.fill:SetWidth(math.max(1, BAR_W * fill))
    hero.fill:SetShown(fill > 0)
    local c = enough and T.accent or WARN
    hero.fill:SetColorTexture(c.r, c.g, c.b, 1)
    if cost == 0 then
        hero.note:SetText("")
    elseif enough then
        hero.note:SetText((atLevel and "You have enough already, with " or "Enough for all of it, with ")
            .. Training.Coins(gold - cost) .. " to spare.")
    else
        hero.note:SetText(Training.Coins(cost - gold) .. " short."
            .. (atLevel and "" or " The trainer panel learns what you can afford."))
    end
    Paint(hero.note, enough and T.muted or WARN)
end

-------------------------------------------------------------------------------
--  The body
-------------------------------------------------------------------------------
-- spellID -> the plan's state for it; a spell in none of them is learned.
local function States(plan)
    local states = {}
    for _, state in ipairs({ "now", "rank", "soon", "later", "talent", "ignored" }) do
        for _, entry in ipairs(plan[state]) do states[entry[2]] = state end
    end
    return states
end

local function DrawLevel(plan, y)
    local group = plan.byLevel[selected] or {}
    y = Header(y, "LEVEL " .. selected, #group, Training.Coins(Training.Total(group)))
    local states = States(plan)
    return Cards(group, y, function(entry) return states[entry[2]] or "learned" end)
end

local function DrawAll(plan, y)
    local function Now() return "now" end
    if #plan.now > 0 then
        y = Header(y, "AVAILABLE NOW", #plan.now, "Skip one to leave it out of your totals")
        y = Cards(plan.now, y, Now) - SECTION_GAP
    end
    if #plan.rank > 0 then
        y = Header(y, "NEEDS AN EARLIER RANK", #plan.rank, "Train the rank before it first")
        for _, entry in ipairs(plan.rank) do
            y = Row(entry, "rank", y, "Learn " .. (C_Spell.GetSpellSubtext(entry.needs) or "the rank before") .. " first")
        end
        y = y - SECTION_GAP
    end
    if #plan.soon > 0 then
        y = Header(y, "COMING SOON", #plan.soon, "Within " .. Training.SOON .. " levels, "
            .. Training.Coins(Training.Total(plan.soon)))
        for _, entry in ipairs(plan.soon) do y = Row(entry, "soon", y, "Level " .. entry[1]) end
        y = y - SECTION_GAP
    end
    if #plan.later > 0 then
        y = Header(y, "LATER", nil, "Click a level, or a dot above")
        local levels, groups = {}, {}
        for _, entry in ipairs(plan.later) do
            if not groups[entry[1]] then
                groups[entry[1]] = {}
                levels[#levels + 1] = entry[1]
            end
            local g = groups[entry[1]]
            g[#g + 1] = entry
        end
        for i = 1, math.min(#levels, MAX_LATER) do
            local level, names = levels[i], {}
            for _, entry in ipairs(groups[level]) do names[#names + 1] = C_Spell.GetSpellName(entry[2]) or "" end
            local b = Take("later", NewLater)
            b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
            b:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
            b.level:SetText("Level " .. level)
            b.names:SetText(table.concat(names, ", "))
            for n, icon in ipairs(b.icons) do
                local entry = groups[level][n]
                icon:SetShown(entry ~= nil)
                icon.edge:SetShown(entry ~= nil)
                if entry then icon:SetTexture(C_Spell.GetSpellTexture(entry[2])) end
            end
            b.price:SetText(Training.Coins(Training.Total(groups[level])))
            b:SetScript("OnClick", function() Select(level) end)
            y = y - ROW_H - ROW_GAP
        end
        if #levels > MAX_LATER then
            y = Header(y, "", nil, ("and %d more levels on the road above"):format(#levels - MAX_LATER))
        end
        y = y - SECTION_GAP
    end
    if #plan.talent > 0 then
        y = Header(y, "NEEDS A TALENT", #plan.talent, "Shows up once you take the talent")
        for _, entry in ipairs(plan.talent) do y = Row(entry, "talent", y, "Level " .. entry[1]) end
        y = y - SECTION_GAP
    end
    if #plan.ignored > 0 then
        y = Header(y, "SKIPPED", #plan.ignored, "Skipping these saves " .. Training.Coins(Training.Total(plan.ignored)))
        for _, entry in ipairs(plan.ignored) do y = Row(entry, "ignored", y) end
        y = y - SECTION_GAP
    end
    if S.Get("showLearned") and #plan.learned > 0 then
        y = Header(y, "LEARNED", #plan.learned, "About " .. Training.Coins(Training.Total(plan.learned)) .. " spent")
        for _, entry in ipairs(plan.learned) do y = Row(entry, "learned", y, "Level " .. entry[1]) end
    end
    return y
end

-- Every spell of your class whose name holds the search, learned or not, as cards in level order.
local function DrawSearch(plan, query, y)
    local states, found = States(plan), {}
    local levels = {}
    for level in pairs(plan.byLevel) do levels[#levels + 1] = level end
    table.sort(levels)
    for _, level in ipairs(levels) do
        for _, entry in ipairs(plan.byLevel[level]) do
            local name = (C_Spell.GetSpellName(entry[2]) or ""):lower()
            if name:find(query, 1, true) then found[#found + 1] = entry end
        end
    end
    if #found == 0 then return Header(y, "NO SPELLS MATCH", nil, "Try part of a spell's name") end
    y = Header(y, "RESULTS", #found, "Learned ones are dimmed")
    return Cards(found, y, function(entry) return states[entry[2]] or "learned" end)
end

Render = function()
    if not (window and window:IsShown()) then return end
    ReleaseAll()
    local plan = Training.Plan()
    local className, classFile = UnitClass("player")
    local color = RAID_CLASS_COLORS[classFile]
    window.subtitle:SetText(("%s, level %d"):format(color and color:WrapTextInColorCode(className) or className,
        plan.level))
    DrawHero(plan)
    DrawRoad(plan)
    window.back:SetShown(selected ~= nil)
    local query = strtrim(window.search:GetText() or ""):lower()
    local y
    if query ~= "" then
        y = DrawSearch(plan, query, 0)
    elseif selected then
        y = DrawLevel(plan, 0)
    elseif #plan.now + #plan.rank + #plan.soon + #plan.later + #plan.talent + #plan.ignored == 0 then
        y = Header(0, "NOTHING LEFT TO LEARN", nil, "Every spell your class trains, you know")
    else
        y = DrawAll(plan, 0)
    end
    body:SetHeight(math.max(1, -y))
end

-------------------------------------------------------------------------------
--  Building it
-------------------------------------------------------------------------------
-- Its top left corner on a whole screen pixel, and its size whole pixels too: a window that
-- lands between pixels (dragged, or centred on an odd screen) blurs every line and letter in it.
local function Snap(frame, w, h)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end
    frame:ClearAllPoints()
    PixelUtil.SetPoint(frame, "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    PixelUtil.SetSize(frame, w, h)
end

-- Snapped, then kept account-wide under key.
local function SavePosition(frame, w, h, key)
    Snap(frame, w, h)
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.AccountSettings()[key] = { point, relPoint, x, y }
end

local function Restore(frame, key, default)
    local saved = ns.AccountSettings()[key]
    if type(saved) == "table" then
        frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        frame:SetPoint(unpack(default))
    end
end

-- A button that stays lit in the accent while its setting is on.
local function PaintToggle(btn, on)
    btn._rest = on and T.accent or BLACK
    btn._border:SetColor(btn._rest.r, btn._rest.g, btn._rest.b, 1)
end

-------------------------------------------------------------------------------
--  The mini bar: the next visit and your gold, small enough to leave up while you level
-------------------------------------------------------------------------------
local mini

local function RenderMini()
    if not (mini and mini:IsShown()) then return end
    local plan = Training.Plan()
    local list, atLevel = NextVisit(plan)
    local cost, gold = Training.Total(list), GetMoney()
    mini.label:SetText(atLevel and ("NEXT VISIT, LEVEL " .. atLevel) or (#list > 0 and "TRAIN NOW" or "NEXT VISIT"))
    mini.cost:SetText(#list > 0 and (Training.Coins(cost) .. "  " .. ns.Color("muted", #list .. (#list == 1 and " spell" or " spells")))
        or "Nothing left to learn")
    mini.gold:SetText(Training.Coins(gold))
    local fill = cost > 0 and math.min(1, gold / cost) or 0
    mini.track:SetShown(cost > 0)
    mini.fill:SetShown(fill > 0)
    mini.fill:SetWidth(math.max(1, (MINI_W - 2 * MINI_PAD) * fill))
    local c = gold >= cost and T.accent or WARN
    mini.fill:SetColorTexture(c.r, c.g, c.b, 1)
end

local function BuildMini()
    mini = CreateFrame("Frame", nil, UIParent)
    mini:SetSize(MINI_W, MINI_H)
    mini:SetFrameStrata("MEDIUM")
    mini:SetClampedToScreen(true)
    mini:SetMovable(true)
    mini:EnableMouse(true)
    mini:RegisterForDrag("LeftButton")
    mini:SetScript("OnDragStart", mini.StartMoving)
    mini:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self, MINI_W, MINI_H, "trainingMini")
    end)
    Restore(mini, "trainingMini", { "TOP", UIParent, "TOP", 0, -60 })
    ns.Solid(mini, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(mini, BLACK)
    local logo = mini:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO, nil, nil, "TRILINEAR")
    logo:SetSize(MINI_LOGO, MINI_LOGO)
    logo:SetPoint("TOPLEFT", MINI_PAD, -MINI_PAD)
    mini.label = Text(mini, 11, nil, T.muted)
    mini.label:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    local close = ns.Button(mini, "x", 18, 18, function()
        S.Set("miniShown", false)
    end)
    close:SetPoint("TOPRIGHT", -6, -6)
    local open = ns.Button(mini, "Open", 46, 18, function() ns.OpenTrainingWindow() end)
    open:SetPoint("RIGHT", close, "LEFT", -4, 0)
    mini.cost = Text(mini, 15, nil)
    mini.cost:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -8)
    mini.gold = Text(mini, 13, nil)
    mini.gold:SetPoint("TOPRIGHT", -MINI_PAD, -(MINI_PAD + MINI_LOGO + 9))
    mini.track = ns.Solid(mini, "ARTWORK", T.line, 1)
    mini.track:SetPoint("BOTTOMLEFT", MINI_PAD, MINI_PAD)
    mini.track:SetPoint("BOTTOMRIGHT", -MINI_PAD, MINI_PAD)
    mini.track:SetHeight(BAR_H - 2)
    mini.fill = mini:CreateTexture(nil, "OVERLAY")
    mini.fill:SetPoint("TOPLEFT", mini.track)
    mini.fill:SetHeight(BAR_H - 2)
    mini:SetScript("OnShow", function(self)
        self:RegisterEvent("PLAYER_MONEY")
        RenderMini()
    end)
    mini:SetScript("OnHide", function(self) self:UnregisterEvent("PLAYER_MONEY") end)
    mini:SetScript("OnEvent", RenderMini)
    mini:Hide()
end

-- Shown while the module is on and you left it up, across reloads.
local function ApplyMini()
    local want = S.Get("enabled") and S.Get("miniShown")
    if want and not mini then BuildMini() end
    if not mini then return end
    if want then
        mini:SetScale(ns.UIScale())
        Snap(mini, MINI_W, MINI_H)
        mini:Show()
    else
        mini:Hide()
    end
end

local function Label(parent, text)
    local fs = Text(parent, 12, nil, T.muted)
    fs:SetText(text)
    return fs
end

local function BuildHero()
    local hero = CreateFrame("Frame", nil, window)
    hero:SetPoint("TOPLEFT", 0, -HEADER - 1)
    hero:SetPoint("TOPRIGHT", 0, -HEADER - 1)
    hero:SetHeight(HERO_H)
    ns.Solid(hero, "BACKGROUND", T.panel, 0.6):SetAllPoints()
    hero.label = Label(hero, "NEXT TRAINER VISIT")
    hero.label:SetPoint("TOPLEFT", PAD, -LABEL_Y)
    hero.cost = Text(hero, 30, nil)
    hero.cost:SetPoint("TOPLEFT", hero.label, "BOTTOMLEFT", 0, -10)
    hero.count = Text(hero, 13, nil, T.muted)
    hero.count:SetPoint("BOTTOMLEFT", hero.cost, "BOTTOMRIGHT", 14, 4)
    hero.track = ns.Solid(hero, "ARTWORK", T.line, 1)
    hero.track:SetSize(BAR_W, BAR_H)
    hero.track:SetPoint("TOPLEFT", hero.cost, "BOTTOMLEFT", 0, -14)
    hero.fill = hero:CreateTexture(nil, "OVERLAY")
    hero.fill:SetPoint("TOPLEFT", hero.track)
    hero.fill:SetHeight(BAR_H)
    hero.note = Text(hero, 12, nil, T.muted)
    hero.note:SetPoint("TOPLEFT", hero.track, "BOTTOMLEFT", 0, -10)
    local goldLabel = Label(hero, "YOUR GOLD")
    goldLabel:SetPoint("TOPRIGHT", -PAD, -LABEL_Y)
    hero.gold = Text(hero, 22, nil)
    hero.gold:SetPoint("TOPRIGHT", goldLabel, "BOTTOMRIGHT", 0, -10)
    local sixtyLabel = Label(hero, "LEFT TO 60")
    sixtyLabel:SetPoint("TOPRIGHT", hero.gold, "BOTTOMRIGHT", 0, -14)
    hero.sixty = Text(hero, 16, nil)
    hero.sixty:SetPoint("TOPRIGHT", sixtyLabel, "BOTTOMRIGHT", 0, -6)
    local rule = ns.Solid(hero, "ARTWORK", T.line, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    window.hero = hero
end

local function BuildRoad()
    local road = CreateFrame("Frame", nil, window)
    road:SetPoint("TOPLEFT", PAD + DOT_MAX / 2, -(HEADER + HERO_H + 2))
    road:SetPoint("TOPRIGHT", -(PAD + DOT_MAX / 2), -(HEADER + HERO_H + 2))
    road:SetHeight(ROAD_H)
    local label = Label(road, "YOUR ROAD TO 60")
    label:SetPoint("TOPLEFT", -DOT_MAX / 2, -LABEL_Y)
    local hint = Label(road, "Click a level to see what it brings")
    hint:SetPoint("TOPRIGHT", DOT_MAX / 2, -LABEL_Y)
    road.track = ns.Solid(road, "BORDER", T.line, 1)
    road.track:SetPoint("TOPLEFT", 0, -TRACK_Y)
    road.track:SetPoint("TOPRIGHT", 0, -TRACK_Y)
    road.track:SetHeight(2)
    road.done = ns.Solid(road, "ARTWORK", T.accent, 1)
    road.done:SetPoint("LEFT", road.track)
    road.done:SetHeight(2)
    road.you = Text(road, 11, nil, T.accent)
    road.you:SetText("YOU")
    for _, level in ipairs(ROAD_TICKS) do
        local tick = Text(road, 11, nil, T.muted)
        tick:SetText(level)
        tick:SetPoint("TOP", road.track, "LEFT", (level - 1) / (MAX_LEVEL - 1) * (WIDTH - 2 * PAD - DOT_MAX),
            -(DOT_MAX / 2 + YOU_GAP))
    end
    local rule = ns.Solid(window, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", 0, -(HEADER + HERO_H + ROAD_H + 2))
    rule:SetPoint("TOPRIGHT", 0, -(HEADER + HERO_H + ROAD_H + 2))
    rule:SetHeight(1)
    window.road = road
end

local function Build()
    window = CreateFrame("Frame", nil, UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self, WIDTH, HEIGHT, "trainingWindow")
    end)
    Restore(window, "trainingWindow", { "CENTER" })
    ns.Solid(window, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(window, BLACK)

    local logo = window:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO, nil, nil, "TRILINEAR")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("LEFT", window, "TOPLEFT", PAD, -HEADER / 2)
    local title = Text(window, 20, nil)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 1)
    title:SetText("Training Planner")
    window.subtitle = Text(window, 12, nil, T.muted)
    window.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    -- Right to left: close, Mini, Show Learned, the search, and All Levels while a level shows.
    local close = ns.Button(window, "x", 24, 24, function() window:Hide() end)
    close:SetPoint("RIGHT", window, "TOPRIGHT", -10, -HEADER / 2)
    local miniButton = ns.Button(window, "Mini", 54, 24, function()
        window:Hide()
        S.Set("miniShown", true)
    end)
    miniButton:SetPoint("RIGHT", close, "LEFT", -8, 0)
    ns.Tooltip(miniButton, "Mini", "Swap the window for a small bar with your next visit and your gold, "
        .. "to leave up while you level. Move it by dragging.")
    window.learned = ns.Button(window, "Show Learned", 110, 24, function()
        S.Set("showLearned", not S.Get("showLearned"))
    end)
    window.learned:SetPoint("RIGHT", miniButton, "LEFT", -8, 0)
    window.search = ns.NewSearchBox(window, "Search spells", function()
        if window:IsShown() then
            Render()
            scroll:SetVerticalScroll(0)
        end
    end)
    window.search:SetSize(SEARCH_W, 24)
    window.search:SetPoint("RIGHT", window.learned, "LEFT", -10, 0)
    window.back = ns.Button(window, "All Levels", 100, 24, function() Select(nil) end)
    window.back:SetPoint("RIGHT", window.search, "LEFT", -10, 0)
    local rule = ns.Solid(window, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", 0, -HEADER)
    rule:SetPoint("TOPRIGHT", 0, -HEADER)
    rule:SetHeight(1)

    BuildHero()
    BuildRoad()

    scroll = UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", PAD, -(HEADER + HERO_H + ROAD_H + 2 + PAD))
    scroll:SetPoint("BOTTOMRIGHT", -(PAD + 12), PAD)
    body = CreateFrame("Frame", nil, scroll)
    body:SetSize(WIDTH - 2 * PAD - 12, 1)
    scroll:SetScrollChild(body)

    -- Esc closes it the way it closes the options window, safe in combat.
    window:SetScript("OnKeyDown", function(self, key) UI.CloseOnEscape(self, key) end)
    window:SetScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(true)
        end
        self:RegisterEvent("PLAYER_MONEY")
        self:RegisterEvent("SPELL_DATA_LOAD_RESULT")
        Render()
    end)
    window:SetScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_MONEY")
        self:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
    end)
    -- A spell's description arriving can add its upgrade; one draw for a burst of them.
    window:SetScript("OnEvent", function(_, event, spell, success)
        if event ~= "SPELL_DATA_LOAD_RESULT" then return Render() end
        if not (success and Training.Waiting()) then return end
        Training.Loaded(spell)
        if loadQueued then return end
        loadQueued = true
        C_Timer.After(LOAD_SETTLE, function()
            loadQueued = false
            Render()
        end)
    end)
    window:Hide()
end

-- Opening it turns the module on, as opening the Dungeon Journal does.
function ns.OpenTrainingWindow(level)
    if not S.Get("enabled") then S.Set("enabled", true) end
    if not window then Build() end
    selected = level
    window:SetScale(ns.UIScale())
    Snap(window, WIDTH, HEIGHT)
    PaintToggle(window.learned, S.Get("showLearned"))
    ns.SetButtonText(window.learned, S.Get("showLearned") and "Hide Learned" or "Show Learned")
    if window:IsShown() then Render() else window:Show() end
end

function ns.ToggleTrainingWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenTrainingWindow() end
end

Training.OnChange(function()
    Render()
    RenderMini()
end)
S.OnChange(function(key)
    if key == "enabled" then
        if not S.Get("enabled") and window then window:Hide() end
        ApplyMini()
    elseif key == "miniShown" then
        ApplyMini()
    elseif key == "showLearned" and window then
        PaintToggle(window.learned, S.Get("showLearned"))
        ns.SetButtonText(window.learned, S.Get("showLearned") and "Hide Learned" or "Show Learned")
        Render()
    end
end)
hooksecurefunc(ns, "Apply", ApplyMini)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    ApplyMini()
end)
