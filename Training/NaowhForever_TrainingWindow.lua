-------------------------------------------------------------------------------
--  NaowhForever_TrainingWindow.lua -- the Training Planner's own window (/nftraining, its
--  minimap and top bar button). Across the top what your next trainer visit costs against
--  your gold, then your road to 60: a dot for every level that brings spells, sized by what
--  they cost; click one for that level. Below, the spells you can train now as cards, then
--  the ones waiting on a rank, coming soon, needing a talent or skipped, and one line per
--  later level. A Builds tab shows a class's talent builds and the picked one level by level,
--  marking the points you have taken. Made the first time it opens; movable, and it remembers
--  where you put it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local Training = ns.Training
local S = ns.TrainingSettings
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local WIDTH, HEIGHT = 940, 850
local HEADER, FOOTER = St.WINDOW_HEADER, St.WINDOW_FOOTER
local PAGE = "Training Planner"   -- its options page, opened from the logo and the footer
local LOGO = St.LOGO
local CIRCLE_MASK = St.ROUND
local CARD_INSET = 6       -- the backdrop's cards from the window's edges, as the Journal's
local INSET = St.CONTENT_INSET     -- a card's edge to what is in it
local BODY_PAD = 14        -- the lists' card to the lists
local TOOL_GAP = 10        -- the title bar's rule to the switch, and the switch to the cards
local SWITCH_W = 180
local TOP = HEADER + TOOL_GAP + St.TAB_H + TOOL_GAP   -- where the cards start
local GAP = 6              -- between the cards
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
local ROW_H, ROW_ICON = 30, 22
-- A list as the Dungeon Journal draws one: rows touching, no edges, every other row a faint
-- band, and a soft band under the mouse.
local STRIPE, HOVER = St.STRIPE, 0.05
local LATER_ICON, LATER_ICONS = 20, 5   -- a later level's spells, as icons before their names
local SECTION_H = St.SECTION_H
local SECTION_GAP = 18
local SKIP_W, SKIP_H = 46, 18
local BLACK = St.BORDER_RGB
local FILL = St.WINDOW_CARD_FILL   -- a spell's card or row: the text colour, this faint
local WARN = { r = 0.94, g = 0.70, b = 0.29 }   -- short of gold, waiting on something
local UP = { r = 0.30, g = 0.82, b = 0.48 }     -- how much stronger a rank is
local UP_COLOR = "|cff4dd17a"
local SHADOW = 0.85       -- the text shadow's opacity
local DIM = 0.45           -- a learned spell in a level's cards
local MAX_LATER = 12       -- later levels listed before "and N more"
local SEARCH_W = 180
local LOAD_SETTLE = 0.1    -- seconds to gather spell descriptions arriving together
local MINI_W, MINI_H, MINI_PAD, MINI_LOGO = 340, 74, 10, 16
local CLASS_H, CLASS_GAP = 26, 6
local SHARE_W = 64         -- Edit, Copy, Export and Delete over a build
local LIST_W, LIST_ROW = 250, 44   -- the builds down the left, as the Journal lists its dungeons
local PANE_GAP = 20        -- the list to the build beside it
local SELECTED_BAR, PICKED = 2, 0.10   -- the picked build: an accent edge and a firmer band
local EDIT_W = 80          -- Undo, Clear and Done above the talent tree
local LEARN_W, FOLLOW_W = 140, 140   -- Learn Next Points and Follow This Build on your build
local NODE, NODE_GAP, NODE_ROW = 36, 12, 56   -- a talent in the tree, its gap, a row's height
local COUNT_GAP = 2        -- a talent's ranks, under it
local TREE_ROWS, TREE_SLOTS = 7, 4
local SPEC_H = 28          -- a tree column's name, above it
local FIRST_TALENT_LEVEL = 10
local CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

local window, scroll, body
local selected             -- the level shown, or nil for every level
local loadQueued = false
local tab = "spells"
local buildClass               -- the class the Builds tab shows; nil is your own
local buildIndex = 1
local paneX = 0                -- where the Builds tab's right side starts; 0 on Spells
local editing = false          -- the picked build is open in the talent tree

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
    if self.band then
        self.band:SetAlpha(HOVER)
    else
        self.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    end
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
    if self.band then
        self.band:SetAlpha(0)
    else
        self.border:SetColor(BLACK.r, BLACK.g, BLACK.b, 1)
    end
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

local function ListRow(b)
    b.stripe = ns.Solid(b, "BACKGROUND", T.fg, STRIPE)
    b.stripe:SetAllPoints()
    b.band = ns.Solid(b, "BACKGROUND", T.fg, 1)
    b.band:SetAllPoints()
    b.band:SetAlpha(0)
end

-- Every other row of a section is banded, the first plain; a section title starts it again.
local listed = 0

local function Stripe(row)
    listed = listed + 1
    row.stripe:SetShown(listed % 2 == 0)
end

-- list: a row of a list, banded; else a card in its edge.
local function SpellButton(height, list)
    local b = CreateFrame("Button", nil, body)
    b:SetHeight(height)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if list then
        ListRow(b)
    else
        b.bg = ns.Solid(b, "BACKGROUND", T.fg, FILL)
        b.bg:SetAllPoints()
        b.border = ns.Border(b, BLACK)
    end
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
    ns.PixelInset(icon, 1, edge)
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
    local r = SpellButton(ROW_H, true)
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
    Stripe(r)
    return y - ROW_H
end

-- A section title as every page draws it: small capitals in the soft accent, a muted count,
-- over a line; a note on the right.
local function NewHeader()
    local h = CreateFrame("Frame", nil, body)
    h:SetHeight(SECTION_H)
    h.title = Text(h, 12, nil, T.accentSoft)
    h.title:SetPoint("BOTTOMLEFT", 0, 5)
    h.note = Text(h, 11, nil, T.muted)
    h.note:SetPoint("BOTTOMRIGHT", 0, 5)
    local rule = ns.Solid(h, "ARTWORK", T.line, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    ns.Hairline(rule, "h")
    return h
end

local function Header(y, title, count, note)
    local h = Take("header", NewHeader)
    h:SetPoint("TOPLEFT", body, "TOPLEFT", paneX, y)
    h:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
    h.title:SetText(title .. (count and ("   " .. ns.Color("muted", count)) or ""))
    h.note:SetText(note or "")
    listed = 0
    return y - SECTION_H - St.SECTION_SPACE
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
    ListRow(b)
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
    b:SetScript("OnEnter", function(self) self.band:SetAlpha(HOVER) end)
    b:SetScript("OnLeave", function(self) self.band:SetAlpha(0) end)
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
            Stripe(b)
            y = y - ROW_H
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

-------------------------------------------------------------------------------
--  The Builds tab: a class's talent builds, and the one picked point by point
-------------------------------------------------------------------------------
local function NewClassButton()
    return ns.Button(body, "", 1, CLASS_H)
end

local function ClassRow(classID, y)
    local w = math.floor((body:GetWidth() - (#CLASSES - 1) * CLASS_GAP) / #CLASSES)
    for i, id in ipairs(CLASSES) do
        local b = Take("class", NewClassButton)
        b:SetPoint("TOPLEFT", body, "TOPLEFT", (i - 1) * (w + CLASS_GAP), y)
        b:SetWidth(w)
        local name, file = GetClassInfo(id)
        b.label:SetText(RAID_CLASS_COLORS[file]:WrapTextInColorCode(name))
        b._rest = id == classID and T.accent or BLACK
        b._border:SetColor(b._rest.r, b._rest.g, b._rest.b, 1)
        b._onClick = function()
            buildClass, buildIndex, editing = id, 1, false
            Render()
        end
    end
    return y - CLASS_H - SECTION_GAP
end

local function BuildRowEnter(self)
    if not self.picked then self.band:SetAlpha(HOVER) end
end

local function BuildRowLeave(self)
    if not self.picked then self.band:SetAlpha(0) end
end

local function NewBuildRow()
    local r = CreateFrame("Button", nil, body)
    r:SetSize(LIST_W, LIST_ROW)
    ListRow(r)
    r.bar = ns.Solid(r, "ARTWORK", T.accent, 1)
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(SELECTED_BAR)
    r.name = Text(r, 13, nil)
    r.name:SetPoint("TOPLEFT", 12, -8)
    r.spec = Text(r, 11, nil, T.muted)
    r.spec:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    for _, line in ipairs({ r.name, r.spec }) do
        line:SetPoint("RIGHT", -8, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
    end
    r:SetScript("OnEnter", BuildRowEnter)
    r:SetScript("OnLeave", BuildRowLeave)
    return r
end

-- The class's builds down the left; a click shows one beside them.
local function BuildList(builds, y)
    for i, build in ipairs(builds) do
        local r = Take("buildRow", NewBuildRow)
        r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        r.picked = i == buildIndex
        r.bar:SetShown(r.picked)
        r.band:SetAlpha(r.picked and PICKED or 0)
        r.name:SetText(build.name)
        local source = build.source or (build.saved and "Saved by you")
        r.spec:SetText(build.spec .. ", " .. #build.points .. " points" .. (source and St.PLACE_DOT .. source or ""))
        r:SetScript("OnClick", function()
            buildIndex, editing = i, false
            Render()
        end)
        Stripe(r)
        y = y - LIST_ROW
    end
    return y
end

local function StepEnter(self)
    self.band:SetAlpha(HOVER)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spell)
    GameTooltip:Show()
end

local function NewStep()
    local r = CreateFrame("Button", nil, body)
    r:SetHeight(ROW_H)
    ListRow(r)
    r.level = Text(r, 13, nil)
    r.level:SetPoint("LEFT", 10, 0)
    r.level:SetWidth(90)
    r.level:SetJustifyH("LEFT")
    r.icon = Icon(r, ROW_ICON)
    r.icon.edge:SetPoint("LEFT", r.level, "RIGHT", 0, 0)
    r.name = Text(r, 13, nil)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.rank = Text(r, 12, nil, T.muted)
    r.rank:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.state = Text(r, 12, nil)
    r.state:SetPoint("RIGHT", -10, 0)
    r:SetScript("OnEnter", StepEnter)
    r:SetScript("OnLeave", function(self)
        self.band:SetAlpha(0)
        GameTooltip:Hide()
    end)
    return r
end

-- One row for each run of points in the same talent: "Levels 10-14, Improved Heroic Strike,
-- Rank 1-5 of 5". ranks is your rank in each talent, or nil for another class.
local function Steps(build, talents, ranks, level, y)
    local points, count = build.points, {}
    local i, found = 1, false
    while i <= #points do
        local node, j = points[i], i
        while points[j + 1] == node do j = j + 1 end
        local spell, max = talents[node][1], talents[node][2]
        local first = (count[node] or 0) + 1
        local last = first + j - i
        count[node] = last
        local from, to = FIRST_TALENT_LEVEL + i - 1, FIRST_TALENT_LEVEL + j - 1
        local r = Take("step", NewStep)
        r:SetPoint("TOPLEFT", body, "TOPLEFT", paneX, y)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
        r.spell = spell
        r.level:SetText(from == to and ("Level " .. from) or ("Levels " .. from .. "-" .. to))
        r.icon:SetTexture(C_Spell.GetSpellTexture(spell))
        r.name:SetText(C_Spell.GetSpellName(spell) or "")
        r.rank:SetText((first == last and ("Rank " .. first) or ("Rank " .. first .. "-" .. last)) .. " of " .. max)
        local taken = ranks ~= nil and ranks[node] >= last
        r:SetAlpha(taken and DIM or 1)
        r.icon:SetDesaturated(taken)
        local color, text = T.muted, ""
        if taken then
            text = "Taken"
        elseif ranks and not found then
            found = true
            local at = from + math.max(0, ranks[node] - first + 1)
            color, text = T.accent, level >= at and "Next, spend it now" or ("Next, at level " .. at)
        end
        r.state:SetText(text)
        Paint(r.state, color)
        Stripe(r)
        y = y - ROW_H
        i = j + 1
    end
    return y
end

-------------------------------------------------------------------------------
--  Editing a build: the class's talent tree, clicked in the order the points are taken
-------------------------------------------------------------------------------
local function NodeEnter(self)
    self.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spell)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Rank %d of %d"):format(self.rank, self.max), 1, 1, 1)
    if self.why then GameTooltip:AddLine(self.why, WARN.r, WARN.g, WARN.b, true) end
    GameTooltip:AddLine("Click to take the next point here, right-click to give one back.",
        T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function NodeLeave(self)
    self.border:SetColor(self.rest.r, self.rest.g, self.rest.b, 1)
    GameTooltip:Hide()
end

local function NewNode()
    local b = CreateFrame("Button", nil, body)
    b:SetSize(NODE, NODE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = ns.Border(b, BLACK)
    b.count = Text(b, 10, nil)
    b.count:SetPoint("TOP", b, "BOTTOM", 0, -COUNT_GAP)
    b:SetScript("OnEnter", NodeEnter)
    b:SetScript("OnLeave", NodeLeave)
    return b
end

local function NewSpecTitle()
    local h = CreateFrame("Frame", nil, body)
    h:SetHeight(SPEC_H)
    h.text = Text(h, 13, nil)
    h.text:SetPoint("LEFT")
    return h
end

local function NewEditButton()
    return ns.Button(body, "", EDIT_W, SKIP_H + 6)
end

local function EditButtons(tree, build, y)
    local actions = {
        { "Undo", function()
            if #build.points > 0 then Training.UndoPoint(tree, build) end
        end },
        { "Clear", function()
            ns.Confirm(("Take every point out of %s?"):format(build.name), function() Training.ClearPoints(build) end)
        end },
        { "Done", function()
            editing = false
            Render()
        end },
    }
    for i, action in ipairs(actions) do
        local b = Take("edit", NewEditButton)
        b:SetPoint("TOPLEFT", body, "TOPLEFT", paneX + (i - 1) * (EDIT_W + 6), y)
        ns.SetButtonText(b, action[1])
        b._onClick = action[2]
    end
    return y - SKIP_H - 6 - SECTION_GAP
end

local function DrawEditor(tree, build, level, y)
    local points = build.points
    y = Header(y, "EDITING " .. build.name:upper(), nil,
        ("%d of 51 points. Click talents in the order you take them"):format(#points))
    y = EditButtons(tree, build, y)
    local count, spent = {}, {}
    for _, node in ipairs(points) do
        count[node] = (count[node] or 0) + 1
        local col = tree.talents[node][4]
        spent[col] = (spent[col] or 0) + 1
    end
    local colW = math.floor((body:GetWidth() - paneX) / #tree.specs)
    local gridW = TREE_SLOTS * NODE + (TREE_SLOTS - 1) * NODE_GAP
    local function Left(col) return paneX + (col - 1) * colW + math.floor((colW - gridW) / 2) end
    for col, spec in ipairs(tree.specs) do
        local h = Take("spec", NewSpecTitle)
        h:SetPoint("TOPLEFT", body, "TOPLEFT", Left(col), y)
        h:SetWidth(gridW)
        h.text:SetText(spec .. "  " .. ns.Color("accent", spent[col] or 0))
    end
    local top = y - SPEC_H
    for node, talent in pairs(tree.talents) do
        local b = Take("node", NewNode)
        local col, row, slot = talent[4], talent[3], talent[5]
        b:SetPoint("TOPLEFT", body, "TOPLEFT", Left(col) + (slot - 1) * (NODE + NODE_GAP), top - (row - 1) * NODE_ROW)
        b.spell, b.rank, b.max = talent[1], count[node] or 0, talent[2]
        -- Why the next point cannot go here, if it cannot: shown on the tooltip.
        points[#points + 1] = node
        b.why = Training.CheckBuild(tree, points)
        points[#points] = nil
        b.icon:SetTexture(C_Spell.GetSpellTexture(talent[1]))
        b.icon:SetDesaturated(b.rank == 0 and b.why ~= nil)
        b.count:SetText(b.rank .. "/" .. b.max)
        Paint(b.count, b.rank == b.max and T.accent or b.rank > 0 and T.fg or T.muted)
        b.rest = b.rank > 0 and T.accent or BLACK
        b.border:SetColor(b.rest.r, b.rest.g, b.rest.b, 1)
        b:SetScript("OnClick", function(_, button)
            local why
            if button == "RightButton" then
                why = Training.RemovePoint(tree, build, node)
            else
                why = Training.AddPoint(tree, build, node)
            end
            if why then ns.Print(why) end
        end)
    end
    y = top - TREE_ROWS * NODE_ROW - SECTION_GAP
    y = Header(y, "LEVEL BY LEVEL", #points, "The order the points are taken in")
    return Steps(build, tree.talents, nil, level, y)
end

local function NewActionButton()
    return ns.Button(body, "", SHARE_W, SKIP_H + 6)
end

-- Over the picked build, in a row: on your own class Learn Next Points and Follow This Build;
-- then Edit or Copy (the built-in builds stay as they are, a copy of one can be changed),
-- Export, and Delete on a saved build.
local function BuildActions(classID, build, ownClass, y)
    local saved = build.saved == true
    local following = Training.Followed() == build
    local actions = {}
    if ownClass then
        actions[#actions + 1] = { "Learn Next Points", LEARN_W, function()
            local bought = Training.LearnBuild(classID, build)
            if bought > 0 then
                ns.Print(("Learned %d talent %s from %s."):format(bought, bought == 1 and "point" or "points",
                    build.name))
            elseif InCombatLockdown() then
                ns.Print("Talents can be learned once the fight is over.")
            elseif not C_ClassTalents.HasUnspentTalentPoints() then
                ns.Print("You have no talent points to spend.")
            else
                ns.Print("The build's next talent cannot be taken now: your talents are not the build's.")
            end
        end }
        actions[#actions + 1] = { following and "Stop Following" or "Follow This Build", FOLLOW_W, function()
            Training.Follow(classID, not following and build or nil)
        end, following }
    end
    if saved then
        actions[#actions + 1] = { "Edit", SHARE_W, function()
            editing = true
            Render()
        end }
    else
        actions[#actions + 1] = { "Copy", SHARE_W, function()
            buildIndex, editing = Training.NewBuild(classID, build.name .. " Copy", build), true
            Render()
        end }
    end
    actions[#actions + 1] = { "Export", SHARE_W, function()
        ns.ShowCopyBox(build.name, Training.ExportBuild(classID, build))
    end }
    if saved then
        actions[#actions + 1] = { "Delete", SHARE_W, function()
            ns.Confirm(("Delete the build %s?"):format(build.name), function()
                buildIndex, editing = 1, false
                Training.DeleteBuild(classID, build)
            end)
        end }
    end
    local x = paneX
    for _, action in ipairs(actions) do
        local b = Take("action", NewActionButton)
        b:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
        b:SetWidth(action[2])
        ns.SetButtonText(b, action[1])
        b._onClick = action[3]
        b._rest = action[4] and T.accent or BLACK
        b._border:SetColor(b._rest.r, b._rest.g, b._rest.b, 1)
        x = x + action[2] + 6
    end
    return y - SKIP_H - 6 - SECTION_GAP
end

-- The class row across the top; under it the class's builds down the left, and the picked one
-- beside them, level by level, or open in the talent tree.
local function DrawBuilds(level, y)
    local _, _, myClass = UnitClass("player")
    local classID = buildClass or myClass
    y = ClassRow(classID, y)
    local tree = ns.TrainingBuilds[classID]
    local builds = Training.Builds(classID)
    if #builds == 0 then return Header(y, "NO BUILDS YET", nil, "Builds for this class are on the way") end
    if not builds[buildIndex] then buildIndex = 1 end
    y = Header(y, "BUILDS", #builds, "Leveling builds from Mobalytics' WoW Forever guides, levels 10 to 30")
    local listBottom = BuildList(builds, y)
    local build = builds[buildIndex]
    paneX = LIST_W + PANE_GAP
    local bottom
    if editing and build.saved then
        bottom = DrawEditor(tree, build, level, y)
    else
        local ranks = classID == myClass and Training.Ranks(tree.talents) or nil
        local note = "Another class's build, to look at"
        if ranks then
            local taken, count = 0, {}
            for _, node in ipairs(build.points) do
                count[node] = (count[node] or 0) + 1
                if ranks[node] >= count[node] then taken = taken + 1 end
            end
            note = ("%d of %d points taken"):format(taken, #build.points)
                .. (Training.Followed() == build and ", following it as you level" or "")
        end
        bottom = Header(y, build.name:upper(), nil, note)
        bottom = BuildActions(classID, build, ranks ~= nil, bottom)
        bottom = Steps(build, tree.talents, ranks, level, bottom)
    end
    paneX = 0
    return math.min(listBottom, bottom)
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
    if tab == "builds" then
        body:SetHeight(math.max(1, -DrawBuilds(plan.level, 0)))
        return
    end
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
    Parts.Backdrop(mini):Paint(1)
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

-- The three cards on the window's backdrop: the next visit, the road to 60, and the lists
-- under them. The Builds tab has only the lists' card, from the top.
local ROAD_TOP = TOP + HERO_H + GAP
local BODY_TOP = ROAD_TOP + ROAD_H + GAP

local function MakeCards()
    local backdrop = window.backdrop
    window.heroCard = backdrop:Card(CARD_INSET, TOP, CARD_INSET, HEIGHT - TOP - HERO_H)
    window.roadCard = backdrop:Card(CARD_INSET, ROAD_TOP, CARD_INSET, HEIGHT - ROAD_TOP - ROAD_H)
    window.bodyCard = backdrop:Card(CARD_INSET, BODY_TOP, CARD_INSET, FOOTER + CARD_INSET)
end

local function BuildHero()
    local hero = CreateFrame("Frame", nil, window)
    hero:SetPoint("TOPLEFT", CARD_INSET, -TOP)
    hero:SetPoint("TOPRIGHT", -CARD_INSET, -TOP)
    hero:SetHeight(HERO_H)
    hero.label = Label(hero, "NEXT TRAINER VISIT")
    hero.label:SetPoint("TOPLEFT", INSET, -LABEL_Y)
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
    goldLabel:SetPoint("TOPRIGHT", -INSET, -LABEL_Y)
    hero.gold = Text(hero, 22, nil)
    hero.gold:SetPoint("TOPRIGHT", goldLabel, "BOTTOMRIGHT", 0, -10)
    local sixtyLabel = Label(hero, "LEFT TO 60")
    sixtyLabel:SetPoint("TOPRIGHT", hero.gold, "BOTTOMRIGHT", 0, -14)
    hero.sixty = Text(hero, 16, nil)
    hero.sixty:SetPoint("TOPRIGHT", sixtyLabel, "BOTTOMRIGHT", 0, -6)
    window.hero = hero
end

local ROAD_X = CARD_INSET + INSET + DOT_MAX / 2   -- the road's ends from the window's edges

local function BuildRoad()
    local road = CreateFrame("Frame", nil, window)
    road:SetPoint("TOPLEFT", ROAD_X, -ROAD_TOP)
    road:SetPoint("TOPRIGHT", -ROAD_X, -ROAD_TOP)
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
        tick:SetPoint("TOP", road.track, "LEFT", (level - 1) / (MAX_LEVEL - 1) * (WIDTH - 2 * ROAD_X),
            -(DOT_MAX / 2 + YOU_GAP))
    end
    window.road = road
end

local function ShowCard(card, shown)
    for _, part in ipairs(card) do part:SetShown(shown) end
end

-- Spells shows the next visit, the road and the spell lists; Builds only the builds, from
-- just under the title bar.
local function SetTab(key)
    tab = key
    local spells = key == "spells"
    Parts.PaintTabs(window.switch, key)
    window.hero:SetShown(spells)
    window.road:SetShown(spells)
    ShowCard(window.heroCard, spells)
    ShowCard(window.roadCard, spells)
    window.search:SetShown(spells)
    window.learned:SetShown(spells)
    window.back:SetShown(spells and selected ~= nil)
    window.import:SetShown(not spells)
    window.save:SetShown(not spells)
    window.new:SetShown(not spells)
    local top = spells and BODY_TOP or TOP
    window.bodyCard[1]:SetPoint("TOPLEFT", CARD_INSET, -top)
    scroll:SetPoint("TOPLEFT", CARD_INSET + BODY_PAD, -(top + BODY_PAD))
end

local function OpacityGet()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

local function OpacitySet(value)
    S.Set("windowAlpha", value / 100)
end
Training.OpacityGet, Training.OpacitySet = OpacityGet, OpacitySet

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "trainingWindow")
    -- Snapped to whole pixels when dropped, or every line in it blurs.
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self, WIDTH, HEIGHT, "trainingWindow")
    end)
    MakeCards()

    -- The title bar: right to left, close, opacity and Mini.
    local close = Parts.TitleBar(window, "Training Planner", "", PAGE)
    local opacityIcon, slider = Parts.Opacity(window, close, OpacityGet, OpacitySet)
    window.opacity = slider
    local miniButton = Parts.BarButton(window, St.LOGO_SMALL, "Mini", "Swap the window for a small bar with "
        .. "your next visit and your gold, to leave up while you level. Move it by dragging.", function()
        window:Hide()
        S.Set("miniShown", true)
    end, "Mini")
    miniButton:SetPoint("RIGHT", opacityIcon, "LEFT", -St.BAR_GAP - 6, 0)

    -- Under it, the switch between Spells and Builds, and on the right what the part shown
    -- has: the search, Show Learned and All Levels, or the Builds tab's own.
    window.switch = Parts.Tabs(window, SWITCH_W, {
        { key = "spells", label = "Spells", tip = "What you can train now and what each level brings." },
        { key = "builds", label = "Builds", tip = "Talent builds, level by level." },
    }, function(key)
        SetTab(key)
        Render()
        scroll:SetVerticalScroll(0)
    end)
    window.switch:SetPoint("TOPLEFT", CARD_INSET, -(HEADER + TOOL_GAP))
    local toolMiddle = -(HEADER + TOOL_GAP + St.TAB_H / 2)
    window.search = Parts.SearchBox(window, "Search spells", function()
        if window:IsShown() then
            Render()
            scroll:SetVerticalScroll(0)
        end
    end)
    window.search:SetSize(SEARCH_W, St.SEARCH_H)
    window.search:SetPoint("RIGHT", window, "TOPRIGHT", -CARD_INSET, toolMiddle)
    window.learned = ns.Button(window, "Show Learned", 110, St.SEARCH_H, function()
        S.Set("showLearned", not S.Get("showLearned"))
    end)
    window.learned:SetPoint("RIGHT", window.search, "LEFT", -8, 0)
    window.back = ns.Button(window, "All Levels", 100, St.SEARCH_H, function() Select(nil) end)
    window.back:SetPoint("RIGHT", window.learned, "LEFT", -8, 0)
    local function ShowBuild(classID, index)
        buildClass, buildIndex, editing = classID, index, false
        Render()
    end
    window.import = Parts.BarButton(window, St.IMPORT, "Import a Build", "Paste a build someone shared with you.",
        function()
            ns.PromptText("Paste a Naowh Forever talent build", "", 0, function(text)
                Training.ImportBuild(text, ShowBuild)
            end)
        end, "Import")
    window.import:SetPoint("RIGHT", window, "TOPRIGHT", -CARD_INSET, toolMiddle)
    window.save = Parts.BarButton(window, St.WAND, "Save My Talents", "Keep the talents you have now as a build "
        .. "you can export. The game does not keep the order you took them in, so it lists them row by row.",
        function()
            ns.PromptText("Name for your current talents", "", 40, function(name)
                local classID, index = Training.SaveMyTalents(name)
                if classID then ShowBuild(classID, index) end
            end)
        end, "Save My Talents")
    window.save:SetPoint("RIGHT", window.import, "LEFT", -St.BAR_GAP, 0)
    window.new = Parts.BarButton(window, St.PLUS, "New Build", "Start an empty build for the class shown and "
        .. "click its talents in the order they are taken, level by level.", function()
        ns.PromptText("Name the new build", "", 40, function(name)
            local _, _, myClass = UnitClass("player")
            local classID = buildClass or myClass
            buildClass, buildIndex, editing = classID, Training.NewBuild(classID, name), true
            Render()
        end)
    end, "New Build")
    window.new:SetPoint("RIGHT", window.save, "LEFT", -St.BAR_GAP, 0)

    BuildHero()
    BuildRoad()

    scroll = UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", CARD_INSET + BODY_PAD, -(BODY_TOP + BODY_PAD))
    scroll:SetPoint("BOTTOMRIGHT", -(CARD_INSET + BODY_PAD + 12), FOOTER + CARD_INSET + BODY_PAD)
    body = CreateFrame("Frame", nil, scroll)
    body:SetSize(WIDTH - 2 * (CARD_INSET + BODY_PAD) - 12, 1)
    scroll:SetScrollChild(body)

    Parts.FooterBrand(window, PAGE, CARD_INSET)
    Parts.FooterNote(window, "Prices from your trainer")

    window:HookScript("OnShow", function(self)
        self:RegisterEvent("PLAYER_MONEY")
        self:RegisterEvent("SPELL_DATA_LOAD_RESULT")
        self:RegisterEvent("TRAIT_CONFIG_UPDATED")
        self.backdrop:Paint(S.Get("windowAlpha") or 1)
        Render()
    end)
    window:HookScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_MONEY")
        self:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
        self:UnregisterEvent("TRAIT_CONFIG_UPDATED")
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
    SetTab(tab)
    window:Hide()
end

-- Opening it turns the module on, as opening the Dungeon Journal does.
function ns.OpenTrainingWindow(level)
    if not S.Get("enabled") then S.Set("enabled", true) end
    if not window then Build() end
    selected = level
    if level then SetTab("spells") end
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
    elseif key == "windowAlpha" and window then
        window.backdrop:Paint(S.Get("windowAlpha") or 1)
        window.opacity._refreshValue()
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
