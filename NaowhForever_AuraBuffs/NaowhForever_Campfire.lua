-------------------------------------------------------------------------------
--  NaowhForever_Campfire.lua -- the AuraBuffs campfire reminder, in two looks on one mover:
--  Round, a camp icon with a time ring and a countdown, and Simple, a self-contained bar in the
--  windows' backdrop: the campfire inside it at the left, sized from the bar's height, the
--  camp's bonuses with their amounts, and the time left on the right over a line that runs down
--  green, yellow, then red. Nothing draws outside the bar, so it can sit anywhere. Every Simple
--  state keeps the fire, the words and the bar's size the same; the down states leave the time's
--  place empty. The bar is never narrower than four wide bonuses need at its text size
--  (MIN_LABELS), and its text never under 11. Hovering it lists each bonus, the time left and
--  when to refresh. The Camp Nearby alert is the same bar (Bar.Nearby) drawn bare: no backdrop,
--  edge or line, the fire and words alone, larger by its own scale, sized to what it says and
--  stacked in the Alerts group (ns.AlertStack), with the camp's time left inline after a dot when
--  it still runs; it fades in, breathes and fades out through animation groups (FADE), never
--  OnUpdate. With Simple it shows only while Camp Benefits is still up and low: once it is gone,
--  the bar's own Camp Nearby pill says it. Right-click (or Ctrl-click) hides it until you leave
--  the campfire's range; only right clicks are taken (SetPassThroughButtons, set out of combat),
--  so left clicks and camera drags reach the world.
--  The bonuses come from the hidden aura each camp feature puts on you, by spell ID, and for the
--  rest from Camp Benefits' tooltip (spell 1229741, wago.tools build 1.60.1.70205), in FEATURES
--  order with no feature twice. The tooltip is kept once per Camp Benefits as soon as a read finds
--  anything; an empty read is tried again at most every LINE.RETRY seconds. One line per feature, matched by the feature's name as the client spells it, its
--  numbers read in the description's order (the Lute's armor, stats, resistances; the Mana
--  Well's mana, then its 5 seconds). FONT_LIFT raises the bar's words: the Naowh font sits low.
--  The bar's fire has no plate or ring: the art (transparent round its fire) sits on the bar's
--  own backdrop, ART_CROP trimming its empty margin so the fire fills the square.
--  Both looks keep the fire on one screen spot: Round's centre is the Simple fire's centre. The
--  saved spot is LEFT for Simple and CENTER for Round (an older corner point is the Round icon's),
--  converted to the current style once, when placed, from the settings alone. A setting change
--  refilters the last bonuses read (FilterBar), so the bar repaints in every state, resting too.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.AuraBuffSettings
local T = ns.THEME
local St, Parts = ns.Shared.Style, ns.Shared.Parts

-- Forever's Camp Benefits aura and icon, probed on the client 2026-09-19.
local CAMP_BENEFITS = 1229741
-- Area aura from being in range of a campfire, probed 2026-09-24.
local CAMPFIRE_NEARBY = 1283391
-- The 60 second aura while sitting at a campfire, before Camp Benefits lands; probed 2026-09-25.
local WELCOMING_CAMPFIRE = 1229739
local WELCOMING_CAMPFIRE_CRAFT = 1289723
local CIRCLE_MASK = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"
local CIRCLE_RING = "Interface\\AddOns\\NaowhForever\\Media\\circle_ring.tga"
local CAMPFIRE_ART = "Interface\\AddOns\\NaowhForever\\Media\\CampfireHD.tga"
local ART_CROP = { 40 / 1024, 993 / 1024, 36 / 1024, 988 / 1024 }
-- The time ring's colour by minutes left: green above 30, yellow above 5, red below.
local TIME_STEPS = { { 1800, St.TIME_OK_RGB }, { 300, St.TIME_LOW_RGB }, { 0, St.TIME_OUT_RGB } }
local REFRESH_NOW = TIME_STEPS[2][1]

local TEXT_SIZE = 16
local FADE = { IN = 0.3, OUT = 0.4, BREATHE = 0.8, LOW = 0.6 }
-- The plate behind the campfire art; ns.ThemeTint swaps in the player's Panels color.
local PLATE = { r = 0.14, g = 0.15, b = 0.16 }

local BAR = { PAD = St.PANEL_PAD, TEXT = 12, TEXT_MIN = 11, LINE_H = 2, FONT_LIFT = 1, EDGE = 1, ICON_PAD = 2,
    CAMP_GAP = 8, BONUS_GAP = 10, TIME_GAP = 12, BONUS_ICON_GROW = 1, BONUS_ICON_GAP = 3,
    BONUS_ICON_DROP = 1 }
local MIN_LABELS = { "+8% Stats", "+308 Armor", "+2% Crit", "+29 MP5" }
local SIT_PREFIX = "in "
local TIME_SAMPLE, SIT_SAMPLE = "44m", SIT_PREFIX .. "44s"
local DEFAULT_X, DEFAULT_Y = -260, 120
local Spot = { DEFAULT = { point = "CENTER", relPoint = "CENTER", x = DEFAULT_X, y = DEFAULT_Y } }
Spot.CORNERS = { TOPLEFT = { 1, -1 }, TOP = { 0, -1 }, TOPRIGHT = { -1, -1 }, RIGHT = { -1, 0 },
    BOTTOMLEFT = { 1, 1 }, BOTTOM = { 0, 1 }, BOTTOMRIGHT = { -1, 1 } }
local UNLOCK_TEXT = "+Rested\n+Crit"
local DISMISS_TIP = "Right-click to dismiss until you leave the campfire."

local FEATURES = {
    { id = 1229451, tag = "+Rested", short = "Rested", name = "Camp Tent", stat = "Rested experience", points = 0,
      aliases = { "Tent", "Camp Tent", "Tanning Rack", "Sewing Machine" } },
    { id = 1230172, tag = "+STR", short = "Str", name = "Sharpening Wheel", stat = "Strength",
      amount = "+%s Strength", aliases = { "Sharpening Wheel", "Anvil", "Master Forge" } },
    { id = 1230124, tag = "+STA", short = "Sta", name = "First Aid Kit", stat = "Stamina", amount = "+%s Stamina",
      aliases = { "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory" } },
    { id = 1229513, tag = "+INT", short = "Int", name = "Incense Candle", stat = "Intellect",
      amount = "+%s Intellect", aliases = { "Incense Candle", "Greenhouse", "Seed Hybridizer" } },
    { id = 1229718, tag = "+Spirit", short = "Spi", name = "Faction Banner", stat = "Spirit", amount = "+%s Spirit",
      aliases = { "Faction Banner", "Spinning Wheel", "Loom" } },
    { id = 1230098, tag = "+Stats", short = "Stats", unit = "%", name = "Fish Bowl", stat = "All stats",
      amount = "+%s%% all stats", aliases = { "Fish Bowl", "Fishing Rack", "Fishing Hut" } },
    { id = 1230653, tag = "+ARM", short = "Armor", name = "Enchanted Lute", stat = "Armor, all stats and resistances",
      amount = "+%s Armor, +%s all stats, +%s resistances", points = 3, aliases = { "Enchanted Lute" } },
    { id = 1230164, tag = "+ATK", short = "AP", name = "Lodestone", stat = "Melee Attack Power",
      amount = "+%s Melee Attack Power", aliases = { "Lodestone", "Rock Garden", "Molten Foundry" } },
    { id = 1230552, tag = "+Spell", short = "SP", stat = "Spell damage and healing",
      amount = "+%s spell damage, +%s healing", points = 2 },
    { id = 1229519, tag = "+Crit", short = "Crit", unit = "%", name = "Camp Chair", stat = "Critical Strike",
      amount = "+%s%% Critical Strike", aliases = { "Camp Chair", "Trapper's Workbench", "Field Guide" } },
    { id = 1230587, tag = "+MP5", short = "MP5", name = "Mana Well", stat = "Mana every 5 sec",
      amount = "+%s Mana every %s sec", numbers = 2, period = 5,
      aliases = { "Mana Well", "Fermenter", "Alchemy Laboratory" } },
    { id = 1283701, tag = "+Disenchant", short = "Disenchant", name = "Arcane Salvager", stat = "Better disenchanting",
      points = 0 },
}
local FEATURE_BY_TAG, featureByName = {}, {}
for i, feature in ipairs(FEATURES) do
    feature.bit = 2 ^ (i - 1)
    feature.points = feature.points or 1
    feature.numbers = feature.numbers or feature.points
    feature.labels = {}
    FEATURE_BY_TAG[feature.tag] = feature
    for _, alias in ipairs(feature.aliases or {}) do featureByName[alias] = feature end
end
local SAMPLE_BONUSES = { { FEATURES[1] }, { FEATURES[3], 56 }, { FEATURES[4], 25 }, { FEATURES[10], 2 } }

local function CampArt(icon, bare)
    icon.tex = Parts.Smooth(icon:CreateTexture(nil, "ARTWORK"), CAMPFIRE_ART)
    icon.tex:SetAllPoints()
    if bare then
        icon.tex:SetTexCoord(ART_CROP[1], ART_CROP[2], ART_CROP[3], ART_CROP[4])
        return
    end
    icon.plate = icon:CreateTexture(nil, "BACKGROUND", nil, 1)
    icon.plate:SetAllPoints()
    local plate = ns.ThemeTint("panel", PLATE)
    icon.plate:SetColorTexture(plate.r, plate.g, plate.b, 1)
    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints()
    icon.mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon.tex:AddMaskTexture(icon.mask)
    icon.plate:AddMaskTexture(icon.mask)
    if bare then return end

    -- A black circle one pixel wider on every side, behind the icon: a 1px round border.
    icon.ring = icon:CreateTexture(nil, "BACKGROUND")
    ns.PixelInset(icon.ring, -1)
    icon.ring:SetColorTexture(0, 0, 0, 1)
    icon.ringMask = icon:CreateMaskTexture()
    icon.ringMask:SetAllPoints(icon.ring)
    icon.ringMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon.ring:AddMaskTexture(icon.ringMask)
end

local Look = {}
local ROUND_ART = { "tex", "plate", "ring" }
local ROUND_EXTRAS = { "timer", "drain", "track", "label", "buffs" }

function Look.New(icon)
    CampArt(icon)

    icon.timer = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.timer:SetAllPoints()
    icon.timer:SetSwipeTexture(CIRCLE_MASK)
    icon.timer:SetDrawSwipe(false)
    icon.timer:SetDrawBling(false)
    icon.timer:SetDrawEdge(false)
    icon.timer:SetReverse(true)

    -- The black disk extends past the drain on both sides, edging the time ring.
    icon.track = icon:CreateTexture(nil, "BACKGROUND")
    icon.track:SetPoint("TOPLEFT", -6, 6)
    icon.track:SetPoint("BOTTOMRIGHT", 6, -6)
    icon.track:SetTexture(CIRCLE_MASK)
    icon.track:SetVertexColor(0, 0, 0, 1)
    icon.drain = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.drain:SetPoint("TOPLEFT", -5, 5)
    icon.drain:SetPoint("BOTTOMRIGHT", 5, -5)
    icon.drain:SetSwipeTexture(CIRCLE_RING)
    icon.drain:SetDrawEdge(false)
    icon.drain:SetDrawBling(false)
    icon.drain:SetHideCountdownNumbers(true)

    icon.label = Parts.HudText(ns.Font(icon, TEXT_SIZE, nil, T.accentSoft))
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    icon.label:SetText("Refresh Camp")

    icon.buffs = Parts.HudText(ns.Font(icon, TEXT_SIZE))
    icon.buffs:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    icon.buffs:SetJustifyH("CENTER")
end

function Look.Layout(icon)
    local size = S.Get("campIconSize")
    icon:SetSize(size, size)
    icon.buffs:SetFont(ns.UIFontPath(), S.Get("campBuffTextSize"), "")
    icon.buffs:ClearAllPoints()
    local side = S.Get("campBuffSide")
    icon.buffs:SetJustifyH(side == "right" and "LEFT" or side == "left" and "RIGHT" or "CENTER")
    if side == "right" then icon.buffs:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    elseif side == "left" then icon.buffs:SetPoint("RIGHT", icon, "LEFT", -12, 0)
    elseif side == "above" then icon.buffs:SetPoint("BOTTOM", icon, "TOP", 0, 12)
    else icon.buffs:SetPoint("TOP", icon, "BOTTOM", 0, -12) end
end

function Look.Shown(icon, on)
    for i = 1, #ROUND_ART do icon[ROUND_ART[i]]:SetShown(on) end
    if on then return end
    for i = 1, #ROUND_EXTRAS do icon[ROUND_EXTRAS[i]]:Hide() end
end

function Look.Step(left)
    for _, step in ipairs(TIME_STEPS) do
        if left > step[1] or step[1] == 0 then return step end
    end
end

function Look.Timed(icon, on)
    icon.timer:SetShown(on)
    icon.drain:SetShown(on)
    icon.track:SetShown(on)
end

function Look.Up(icon, buffs)
    icon.tex:SetDesaturated(false)
    icon.label:Hide()
    icon.buffs:SetText(buffs)
    icon.buffs:Show()
end

function Look.Sitting(icon)
    icon.tex:SetDesaturated(false)
    icon.label:SetText("Resting")
    icon.label:Show()
    icon.buffs:Hide()
end

function Look.Missing(icon)
    icon.tex:SetDesaturated(true)
    icon.label:SetText("Refresh Camp")
    icon.label:Show()
    icon.buffs:Hide()
    Look.Timed(icon, false)
end

local Bar = {}

local function Edge(f, axis)
    local edge = ns.Solid(f.edges, "OVERLAY", St.BORDER_RGB, 1)
    ns.Hairline(edge, axis)
    return edge
end

local function NewEdges(f)
    f.edges = CreateFrame("Frame", nil, f.bar)
    f.edges:SetAllPoints()
    f.edges:SetFrameLevel(f.line:GetFrameLevel() + 1)
    f.top, f.bottom, f.left, f.right = Edge(f, "h"), Edge(f, "h"), Edge(f, "v"), Edge(f, "v")
    f.top:SetPoint("TOPLEFT")
    f.top:SetPoint("TOPRIGHT")
    f.bottom:SetPoint("BOTTOMLEFT")
    f.bottom:SetPoint("BOTTOMRIGHT")
    f.left:SetPoint("TOPLEFT")
    f.left:SetPoint("BOTTOMLEFT")
    f.right:SetPoint("TOPRIGHT")
    f.right:SetPoint("BOTTOMRIGHT")
end

local function TextWidth(f, text)
    f.probe:SetText(text)
    return f.probe:GetStringWidth()
end

local function MinWidth(f, size)
    local text = 0
    for i = 1, #MIN_LABELS do text = text + TextWidth(f, MIN_LABELS[i]) end
    local icons = S.Get("campBonusIcons") and #MIN_LABELS * (size + BAR.BONUS_ICON_GROW + BAR.BONUS_ICON_GAP) or 0
    local time = S.Get("campTimer") and BAR.TIME_GAP + f.timeW or 0
    return math.ceil(f.labelX + text + icons + (#MIN_LABELS - 1) * BAR.BONUS_GAP + time + BAR.PAD)

end

function Bar.CampSize(height)
    return height - 2 * (BAR.EDGE + BAR.ICON_PAD) - BAR.LINE_H
end

function Bar.FireX(height)
    return BAR.EDGE + BAR.ICON_PAD + Bar.CampSize(height) / 2
end

-- Camp Nearby's own font, outline and background. With no background its words keep the card's
-- shadow, as they always had.
local function BareFonts(f, size)
    local font, outline = S.Get("campAlertFont"), S.Get("campAlertOutline")
    local mode = f.plate:SetMode(S.Get("campAlertBackground"))
    local shadow = mode ~= "none" and mode or nil
    Parts.HudFont(f.note, font, size, outline, shadow)
    Parts.HudFont(f.time, font, size, outline, shadow)
    Parts.HudFont(f.dot, font, size, outline, shadow)
    Parts.HudFont(f.probe, font, size, outline, shadow)
end

function Bar.Layout(f)
    local size = math.max(BAR.TEXT_MIN, S.Get("campSimpleTextSize"))
    local height = S.Get("campSimpleHeight")
    f.height, f.size = height, size
    f.campSize = Bar.CampSize(height)
    f.campX = Bar.FireX(height)
    f.labelX = f.campX + f.campSize / 2 + BAR.CAMP_GAP
    f.textY = BAR.FONT_LIFT + BAR.LINE_H / 2
    local font = ns.UIFontPath()
    f.time:SetFont(font, size, "")
    f.note:SetFont(font, size, "")
    f.probe:SetFont(font, size, "")
    if f.bare then BareFonts(f, size) end
    f.labels:SetTextSize(size)
    f.timeW, f.sitW = math.ceil(TextWidth(f, TIME_SAMPLE)), math.ceil(TextWidth(f, SIT_SAMPLE))
    f.minW = MinWidth(f, size)
    f.width = math.max(S.Get("campSimpleWidth"), f.minW)
    f.camp:ClearAllPoints()
    f.camp:SetSize(f.campSize, f.campSize)
    f.camp:SetPoint("CENTER", f.bar, "LEFT", f.campX, BAR.LINE_H / 2)
    f.note:ClearAllPoints()
    f.note:SetPoint("LEFT", f.bar, "LEFT", f.labelX, f.textY)
    f.time:ClearAllPoints()
    if f.bare then
        f.dotW = TextWidth(f, St.PLACE_DOT)
        f.dot:ClearAllPoints()
        f.dot:SetPoint("LEFT", f.note, "RIGHT")
        f.time:SetPoint("LEFT", f.dot, "RIGHT")
    else
        f.time:SetPoint("RIGHT", f.bar, "RIGHT", -BAR.PAD, f.textY)
    end
end

function Bar.New(host, opts)
    local f = CreateFrame("Frame", nil, host)
    f:SetAllPoints()
    f.host = host
    f.bare = opts and opts.bare or false
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetAllPoints()
    f.backdrop = Parts.Backdrop(f.bar)
    f.backdrop:Paint(f.bare and 0 or St.BACKDROP_ALPHA)

    f.inner = ns.PixelInset(CreateFrame("Frame", nil, f.bar), 1)
    f.time = ns.Font(f.bar, BAR.TEXT, nil, T.fg)
    f.time:SetJustifyH("RIGHT")
    f.line = Parts.TimerLine(f.inner, BAR.LINE_H, f.time)
    f.line:SetPoint("BOTTOMLEFT")
    f.line:SetPoint("BOTTOMRIGHT")
    NewEdges(f)
    f.edges:SetShown(not f.bare)
    f.labels = Parts.LabelRow(f.bar, BAR.TEXT, nil, T.fg, { gap = BAR.BONUS_GAP, iconGrow = BAR.BONUS_ICON_GROW,
        iconGap = BAR.BONUS_ICON_GAP, iconDrop = BAR.BONUS_ICON_DROP })
    f.note = ns.Font(f.bar, BAR.TEXT, nil, T.fg)
    f.note:SetWordWrap(false)
    f.probe = ns.Font(f.bar, BAR.TEXT)
    f.probe:Hide()
    if f.bare then
        Parts.HudText(f.note)
        Parts.HudText(f.time)
        f.time:SetJustifyH("LEFT")
        f.dot = Parts.HudText(ns.Font(f.bar, BAR.TEXT, nil, T.muted))
        f.dot:SetText(St.PLACE_DOT)
        f.plate = Parts.HudBackdrop(f.bar, { mode = "none" })
    end
    f.campText = "Camp Active" .. ns.Color("muted", St.PLACE_DOT .. "no bonuses")
    f.restText = "Resting"
    f.refreshText = ns.Color("accent", "Refresh") .. " Camp"
    f.nearbyText = f.bare and ns.Color("accent", "Camp Nearby")
        or ns.Color("accent", "Camp Nearby") .. ns.Color("muted", St.PLACE_DOT .. "sit to refresh")
    f.moreLabels, f.moreIcons, f.more = {}, {}, 0

    f.camp = CreateFrame("Frame", nil, f.bar)
    f.camp:SetFrameLevel(f.edges:GetFrameLevel() + 1)
    CampArt(f.camp, true)
    f.lit, f.low, f.lead, f.group, f.pill, f.slot = true, false, 0, 0, false, 0
    Bar.Layout(f)
    Bar.Paint(f, T.accent, false)
    return f
end

local moreTexts = {}

local function MoreText(n)
    local text = moreTexts[n]
    if not text then
        text = ns.Color("muted", ("+%d more"):format(n))
        moreTexts[n] = text
    end
    return text
end

local function BarSize(f)
    local w = f.width
    if f.bare then
        w = f.labelX + f.note:GetStringWidth() + BAR.PAD
        if f.slot > 0 then w = w + f.dotW + f.slot end
    end
    f.host:SetSize(math.ceil(w), f.height)
end

local function PlaceLabels(f)
    f.labels:ClearAllPoints()
    f.labels:SetPoint("LEFT", f.bar, "LEFT", f.labelX + f.lead, f.textY)
end

local function BarFit(f, labels, icons, n, slot)
    f.pill, f.slot = false, slot
    local room = f.width - f.labelX - f.lead - BAR.PAD
    if slot > 0 then room = room - slot - BAR.TIME_GAP end
    f.labels:SetLabels(labels, n, icons)
    f.group = f.labels:Pack()
    f.more = 0
    local kept = n - 1
    while f.group > room and kept >= 1 do
        local list, marks = f.moreLabels, f.moreIcons
        for i = 1, kept do list[i], marks[i] = labels[i], icons and icons[i] or false end
        list[kept + 1], marks[kept + 1] = MoreText(n - kept), false
        f.labels:SetLabels(list, kept + 1, marks)
        f.group = f.labels:Pack()
        f.more = n - kept
        kept = kept - 1
    end
    PlaceLabels(f)
    BarSize(f)
end

local function BarNote(f, text, color)
    f.note:SetText(text)
    f.note:SetTextColor(color.r, color.g, color.b)
    f.note:Show()
end

local function BarLit(f, on)
    f.lit = on
    f.camp.tex:SetDesaturated(not on)
end

function Bar.Paint(f, color, low)
    f.low = low and true or false
    f.line:Paint(color, f.low and color or T.fg)
end

function Bar.Timed(f, on)
    on = on and true or false
    if not on then f.line:Stop() end
    f.line:SetShown(on and not f.bare)
    f.time:SetShown(on)
    if f.dot then f.dot:SetShown(on) end
end

function Bar.Up(f, labels, icons, n, timed)
    BarLit(f, true)
    f.lead = 0
    f.labels:SetColor(T.fg)
    if n > 0 then f.note:Hide() else BarNote(f, f.campText, T.fg) end
    BarFit(f, labels, icons, n, timed and f.timeW or 0)
end

function Bar.Sitting(f, labels, icons, n, timed, upcoming)
    BarLit(f, true)
    f.lead = 0
    if upcoming then
        f.note:Hide()
        f.labels:SetColor(T.accentSoft)
    else
        BarNote(f, f.restText, T.accentSoft)
        f.labels:SetColor(T.muted)
        if n > 0 then f.lead = math.ceil(f.note:GetStringWidth()) + BAR.BONUS_GAP end
    end
    BarFit(f, labels, icons, n, timed and f.sitW or 0)
end

function Bar.Missing(f, nearby, lit)
    BarLit(f, lit and true or false)
    f.lead, f.more, f.group = 0, 0, 0
    f.labels:SetLabels(nil, 0)
    PlaceLabels(f)
    BarNote(f, nearby and f.nearbyText or f.refreshText, T.fg)
    Bar.Timed(f, false)
    f.pill, f.slot = true, 0
    BarSize(f)
end

function Bar.Nearby(f, start, duration)
    Bar.Missing(f, true, start ~= nil)
    if start then
        Bar.Paint(f, Look.Step(start + duration - GetTime())[2], true)
        if f.runStart ~= start or f.runLength ~= duration then
            f.runStart, f.runLength = start, duration
            f.line:Run(start, duration)
        end
        Bar.Timed(f, true)
        f.slot = f.timeW
        BarSize(f)
    else
        f.runStart, f.runLength = nil, nil
    end
end

local function AlertFaded(a)
    a.leaving = false
    a:Hide()
end

local function AlertShown(a)
    if S.Get("campAlertFade") then a.breathe:Play() end
end

local function AlertStop(a)
    a.fadeIn:Stop()
    a.breathe:Stop()
    a.fadeOut:Stop()
    a.leaving = false
end

local function Fader(a, from, to, duration, finished)
    local group = a:CreateAnimationGroup()
    local anim = group:CreateAnimation("Alpha")
    anim:SetFromAlpha(from)
    anim:SetToAlpha(to)
    anim:SetDuration(duration)
    anim:SetSmoothing("IN_OUT")
    if finished then
        group:SetToFinalAlpha(true)
        group:SetScript("OnFinished", function() finished(a) end)
    end
    return group
end

local function AlertLook(a)
    a.bar = Bar.New(a, { bare = true })
    a.fadeIn = Fader(a, 0, 1, FADE.IN, AlertShown)
    a.fadeOut = Fader(a, 1, 0, FADE.OUT, AlertFaded)
    a.breathe = Fader(a, 1, FADE.LOW, FADE.BREATHE)
    a.breathe:SetLooping("BOUNCE")
    a.leaving = false
end

local function AlertFade(a, show)
    local fade = S.Get("campAlertFade")
    if show then
        if a:IsShown() and not a.leaving then return end
        AlertStop(a)
        a:SetAlpha(1)
        a:Show()
        if fade then a.fadeIn:Play() end
    elseif a:IsShown() and not a.leaving then
        AlertStop(a)
        if fade then
            a.leaving = true
            a.fadeOut:Play()
        else
            a:Hide()
        end
    end
end

local icon, unlocked
local hasCamp       -- nil until the first read
local shownExpiry   -- the expiry the swipe was last started from
local alert
local alertGen = 0   -- invalidates an older Alert Under timer
local alertArmed     -- the expiry that timer was set for
local alertDismissed -- Ctrl-clicked away; back once you leave the campfire's range
local ringGen = 0    -- invalidates an older ring colour change
local showGen = 0    -- invalidates an older "drops under the Show Only When Low time" timer
local showArmed      -- the expiry and minutes that timer was set for
local bonusTags, bonusFeatures = {}, {}
local barLabels, barIcons, sampleLabels, sampleIcons = {}, {}, {}, {}
local joinedTags, numberTexts = {}, {}
local bonusCount, barCount, bonusText = 0, 0, ""
local Reader = { gen = 0, unknown = 0, unknownTexts = {}, tryGen = 0, nextTry = 0 }
local campState, campExpiry, campUpcoming
local simpleBar

local function On()
    return S.Get("enabled") and S.Get("campfire")
end

local function Simple()
    return S.Get("campStyle") == "simple"
end

-- Camp Benefits is earned in the open world, so dungeons, raids and battlegrounds never
-- nag about it.
local function InOpenWorld()
    local inInstance = IsInInstance()
    return not inInstance
end

-- Show Active Camp Buffs: Off, Always or On Mouseover. A profile that never picked one
-- follows the old on/off switch, so nobody's setting changes.
function ns.CampBuffMode()
    local mode = S.Get("campBuffMode")
    if mode then return mode end
    return S.Get("campBuffs") and "always" or "off"
end

-- On Mouseover: the buff lines stay written but invisible until the icon is hovered.
local function PaintBuffs()
    local hidden = ns.CampBuffMode() == "hover" and not unlocked and not icon:IsMouseOver()
    icon.buffs:SetAlpha(hidden and 0 or 1)
end

local function TimeWords(left)
    if left >= 60 then return ("%d min"):format(math.ceil(left / 60)) end
    return ("%d sec"):format(math.max(0, math.ceil(left)))
end

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

local function Points(feature, aura)
    if not aura then return nil end
    local points = aura.points
    if Secret(points) or type(points) ~= "table" then return nil end
    for i = 1, feature.points do
        local v = points[i]
        if Secret(v) or type(v) ~= "number" then return nil end
    end
    return points
end

local function NumberText(v)
    local text = numberTexts[v]
    if not text then
        text = v == math.floor(v) and ("%d"):format(v) or ("%.1f"):format(v)
        numberTexts[v] = text
    end
    return text
end

local function BonusLabel(feature, amount)
    if not amount then return feature.short end
    local text = feature.labels[amount]
    if not text then
        text = "+" .. NumberText(amount) .. (feature.unit or "") .. " " .. ns.Color("muted", feature.short)
        feature.labels[amount] = text
    end
    return text
end

local function BonusWords(feature)
    local a1, a2, a3, count = feature.a1, feature.a2, feature.a3, feature.numbers
    if not (feature.amount and a1) then return feature.stat or feature.short end
    if count == 1 or (count == 2 and a2) or (count == 3 and a2 and a3) then
        return feature.amount:format(NumberText(a1), a2 and NumberText(a2), a3 and NumberText(a3))
    end
    return "+" .. NumberText(a1) .. (feature.unit or "") .. " " .. feature.stat
end

local function FeatureName(feature)
    Reader.Names()
    return feature.lineName or feature.localName or feature.name or ""
end

local function FeatureIcon(feature)
    if feature.icon == nil then feature.icon = C_Spell.GetSpellTexture(feature.id) or false end
    return feature.icon
end

local function Hidden(feature)
    local hidden = S.Get("campHiddenBonuses")
    return feature and hidden and hidden[feature.id] and true or false
end

local function FilterBar()
    local icons, n = S.Get("campBonusIcons"), 0
    for i = 1, bonusCount do
        local feature = bonusFeatures[i]
        if not Hidden(feature) then
            n = n + 1
            barLabels[n] = feature and BonusLabel(feature, feature.a1) or bonusTags[i]
            barIcons[n] = icons and feature and FeatureIcon(feature) or false
        end
    end
    barCount = n
end

local function FillSamples(filter)
    local icons, n = S.Get("campBonusIcons"), 0
    for i = 1, #SAMPLE_BONUSES do
        local feature, amount = SAMPLE_BONUSES[i][1], SAMPLE_BONUSES[i][2]
        if not (filter and Hidden(feature)) then
            n = n + 1
            sampleLabels[n] = BonusLabel(feature, amount)
            sampleIcons[n] = icons and FeatureIcon(feature) or false
        end
    end
    return n
end

local function TipBonuses(tip)
    local fg, muted = T.fg, T.muted
    for i = 1, bonusCount do
        local feature = bonusFeatures[i]
        if feature then
            tip:AddDoubleLine(BonusWords(feature), FeatureName(feature), fg.r, fg.g, fg.b, muted.r, muted.g, muted.b)
        else
            tip:AddLine(bonusTags[i], fg.r, fg.g, fg.b)
        end
    end
end

local function ShowTip(owner)
    if unlocked or not Parts.Tip(owner, "ANCHOR_TOP") then return end
    local tip, fg, muted, soft = GameTooltip, T.fg, T.muted, T.accentSoft
    tip:SetText("Camp Benefits", T.accent.r, T.accent.g, T.accent.b)
    if campState == "sitting" then
        if campUpcoming then
            tip:AddLine("You'll get:", fg.r, fg.g, fg.b)
            TipBonuses(tip)
        else
            tip:AddLine("Resting at a campfire", fg.r, fg.g, fg.b)
        end
        if campExpiry then
            tip:AddDoubleLine("Camp Benefits in", TimeWords(campExpiry - GetTime()), muted.r, muted.g, muted.b,
                soft.r, soft.g, soft.b)
        end
    elseif campState == "up" then
        if bonusCount > 0 then
            TipBonuses(tip)
        else
            tip:AddLine("Camp Benefits is up, but it lists no bonuses: this camp may have no features, or they "
                .. "can't be read yet.", muted.r, muted.g, muted.b, true)
        end
        if campExpiry then
            local left = campExpiry - GetTime()
            local c = Look.Step(left)[2]
            tip:AddDoubleLine("Time left", TimeWords(left), muted.r, muted.g, muted.b, c.r, c.g, c.b)
            if left <= REFRESH_NOW then
                tip:AddLine("Refresh now", c.r, c.g, c.b)
            else
                tip:AddLine("Refresh in " .. TimeWords(left - REFRESH_NOW), muted.r, muted.g, muted.b)
            end
        end
    else
        local out = St.TIME_OUT_RGB
        tip:AddLine("No Camp Benefits", muted.r, muted.g, muted.b)
        tip:AddLine("Sit at a campfire to refresh", out.r, out.g, out.b)
    end
    local readable = not (InCombatLockdown() or C_Secrets.ShouldAurasBeSecret())
    if readable and C_UnitAuras.GetPlayerAuraBySpellID(CAMPFIRE_NEARBY) then
        tip:AddLine("A campfire is in range", soft.r, soft.g, soft.b)
    end
    tip:Show()
end

local function HideTip()
    GameTooltip:Hide()
end

local function Anchored(simple, left, x, y)
    if simple then return { point = "LEFT", relPoint = "BOTTOMLEFT", x = left, y = y } end
    return { point = "CENTER", relPoint = "BOTTOMLEFT", x = x, y = y }
end

local function SavePos(pos)
    local x, y = icon:GetCenter()
    local left = icon:GetLeft()
    if x and y and left then
        pos = Anchored(Simple(), left, x, y)
        icon:ClearAllPoints()
        icon:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    S.Set("campPos", pos)
end

local function Build()
    icon = CreateFrame("Frame", "NaowhForeverCampfire", UIParent)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)

    Look.New(icon)

    -- Hovering the icon shows the buff lines while Show Active Camp Buffs is On Mouseover. The
    -- icon only takes the mouse then (Apply), so clicks and camera drags otherwise go through.
    icon:SetScript("OnEnter", PaintBuffs)
    icon:SetScript("OnLeave", PaintBuffs)

    -- Its spot follows its style (Spot.ForStyle), held to a corner of its own choosing.
    icon.mover = ns.UI.AttachMover(icon, "Campfire", SavePos, "AuraBuffs/Settings", "AuraBuffs/Settings:campfire", true)
    icon:Hide()
end

local function UseStyle(simple)
    if simple and not simpleBar then
        simpleBar = Bar.New(icon)
        simpleBar:SetMouseMotionEnabled(true)
        simpleBar:SetMouseClickEnabled(false)
        simpleBar:SetScript("OnEnter", ShowTip)
        simpleBar:SetScript("OnLeave", HideTip)
    end
    if simpleBar then simpleBar:SetShown(simple) end
    Look.Shown(icon, not simple)
end

function Spot.ForStyle(pos)
    local want = Simple() and "LEFT" or "CENTER"
    if pos.point == want then return pos end
    local x, y = pos.x, pos.y
    local corner = Spot.CORNERS[pos.point]
    if corner then
        local half = S.Get("campIconSize") / 2
        x, y = x + corner[1] * half, y + corner[2] * half
    elseif pos.point == "LEFT" then
        x = x + Bar.FireX(S.Get("campSimpleHeight"))
    end
    if want == "LEFT" then x = x - Bar.FireX(S.Get("campSimpleHeight")) end
    return { point = want, relPoint = pos.relPoint, x = x, y = y }
end

local function Place()
    local saved = S.Get("campPos")
    local pos = Spot.ForStyle(saved or Spot.DEFAULT)
    if saved and pos ~= saved then S.Set("campPos", pos) end
    icon:ClearAllPoints()
    icon:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function BarShown()
    return simpleBar ~= nil and simpleBar:IsShown()
end

local function PaintTime(color, low)
    if BarShown() then
        Bar.Paint(simpleBar, color, low)
    else
        icon.drain:SetSwipeColor(color.r, color.g, color.b, 1)
    end
end

local function RunTimer(start, duration, prefix)
    if BarShown() then
        simpleBar.line:Run(start, duration, prefix)
    else
        icon.timer:SetCooldown(start, duration)
        icon.drain:SetCooldown(start, duration)
    end
end

local function Timed(on)
    if BarShown() then Bar.Timed(simpleBar, on) else Look.Timed(icon, on) end
end

-- Nothing fires as the buff runs down, so each colour change is timed.
local function ColorRing(expiry)
    ringGen = ringGen + 1
    local left = expiry - GetTime()
    local step = Look.Step(left)
    PaintTime(step[2], step ~= TIME_STEPS[1])
    if step[1] > 0 then
        local gen = ringGen
        C_Timer.After(left - step[1] + 0.1, function()
            if gen == ringGen then ColorRing(expiry) end
        end)
    end
end

local function ShowUp(duration, expiry, text, labels, icons, n)
    local timed = S.Get("campTimer") and duration and duration > 0 and true or false
    campState, campExpiry = "up", expiry
    if BarShown() then
        Bar.Up(simpleBar, labels, icons, n, timed)
    else
        Look.Up(icon, ns.CampBuffMode() ~= "off" and text or "")
        PaintBuffs()
    end
    if timed then
        if shownExpiry ~= expiry then
            RunTimer(expiry - duration, duration)
            ColorRing(expiry)
            shownExpiry = expiry
        end
        Timed(true)
    else
        Timed(false)
        ringGen = ringGen + 1
        shownExpiry = nil
    end
    icon:Show()
end

local function ShowSitting(duration, expiry, upcoming)
    local timed = S.Get("campTimer") and true or false
    campState, campExpiry, campUpcoming = "sitting", expiry, upcoming
    if BarShown() then
        Bar.Sitting(simpleBar, barLabels, barIcons, barCount, timed, upcoming)
    else
        Look.Sitting(icon)
    end
    ringGen = ringGen + 1
    if timed and shownExpiry ~= expiry then
        RunTimer(expiry - duration, duration, SIT_PREFIX)
        PaintTime(T.accent, false)
        shownExpiry = expiry
    elseif not timed then
        shownExpiry = nil
    end
    Timed(timed)
    icon:Show()
end

local function ShowMissing(nearby)
    campState, campExpiry = "missing", nil
    if BarShown() then Bar.Missing(simpleBar, nearby) else Look.Missing(icon) end
    ringGen = ringGen + 1
    shownExpiry = nil
    icon:SetShown(S.Get("campShowMissing") or unlocked == true)
end

local function AlertTip(self)
    if unlocked or not Parts.Tip(self, "ANCHOR_TOP") then return end
    GameTooltip:SetText(DISMISS_TIP, T.fg.r, T.fg.g, T.fg.b)
    GameTooltip:Show()
end

local function AlertDismiss(self, button)
    if button ~= "RightButton" or unlocked then return end
    alertDismissed = true
    self:EnableMouse(false)
    HideTip()
    AlertFade(alert, false)
end

-- "Camp Nearby" in the middle of the screen when a campfire is in range and the camp needs
-- refreshing: no Camp Benefits, or less than two minutes left on it.
local function BuildAlert()
    alert = CreateFrame("Frame", "NaowhForeverCampNearby", UIParent)
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    AlertLook(alert)
    -- Ctrl-click dismisses it. It takes the mouse only while Ctrl is down, so an ordinary click
    -- or camera drag in the middle of the screen still reaches the world.
    alert:EnableMouse(false)
    alert:SetScript("OnShow", function(self)
        self:EnableMouse(IsControlKeyDown())
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
    end)
    alert:SetScript("OnHide", function(self)
        AlertStop(self)
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end)
    alert:SetScript("OnEvent", function(self) self:EnableMouse(IsControlKeyDown()) end)
    alert:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and IsControlKeyDown() and not unlocked then
            alertDismissed = true
            AlertFade(self, false)
        end
    end)
    alert.click = CreateFrame("Button", nil, alert)
    alert.click:SetAllPoints()
    alert.click:RegisterForClicks("RightButtonUp")
    alert.click:EnableMouse(false)
    alert.click:SetScript("OnClick", AlertDismiss)
    alert.click:SetScript("OnEnter", AlertTip)
    alert.click:SetScript("OnLeave", HideTip)
    alert:Hide()
    ns.AlertStack(alert, 1)
end

local function LayoutAlert()
    alert:SetScale(S.Get("campAlertScale"))
    local f = alert.bar
    Bar.Layout(f)
    -- Sized again for the new font; Refresh drew it before this layout.
    if alert:IsShown() then Bar.Nearby(f, f.runStart, f.runLength) end
end

local function SetAlert(show, start, duration)
    if not alert then
        if not show then return end
        BuildAlert()
        LayoutAlert()
    end
    if show then Bar.Nearby(alert.bar, start, duration) end
    AlertFade(alert, show)
    if show and not alert.passed and not InCombatLockdown() then
        alert.click:SetPassThroughButtons("LeftButton")
        alert.passed = true
    end
    alert.click:EnableMouse(show and alert.passed and not unlocked or false)
end

local EFFECT_TAGS = {
    { "rested", "+Rested" }, { "rest experience", "+Rested" }, { "disenchant", "+Disenchant" },
    { "critical strike", "+Crit" }, { "spell damage", "+Spell" }, { "spell power", "+Spell" },
    { "armor", "+ARM" }, { "attack power", "+ATK" }, { "strength", "+STR" }, { "stamina", "+STA" },
    { "intellect", "+INT" }, { "spirit", "+Spirit" }, { "mana", "+MP5" }, { "mp5", "+MP5" },
    { "stats", "+Stats" },
}
local LINE = { PATTERN = "^%s*(.-)%s*:%s*(%S.-)%s*$", WIDE = "^%s*(.-)%s*\239\188\154%s*(%S.-)%s*$",
    NUMBER = "(%d+)([%.,]?)(%d*)", MAX_UNKNOWN = 4, SHORT_EFFECT = 28, RETRY = 5 }

function Reader.Names()
    local GetSpellName = C_Spell and C_Spell.GetSpellName
    if Reader.named or not GetSpellName then return end
    local all = true
    for i = 1, #FEATURES do
        local feature = FEATURES[i]
        if not feature.localName then
            local name = GetSpellName(feature.id)
            if name ~= nil and not Secret(name) and type(name) == "string" and name ~= "" then
                feature.localName = name
                featureByName[name] = feature
            else
                all = false
            end
        end
    end
    Reader.named = all
end

function Reader.FeatureOf(label, effect)
    local feature = featureByName[label]
    if feature then return feature end
    local lower = effect:lower()
    for i = 1, #EFFECT_TAGS do
        local entry = EFFECT_TAGS[i]
        if lower:find(entry[1], 1, true) then return FEATURE_BY_TAG[entry[2]] end
    end
end

function Reader.Number(whole, mark, part)
    if mark ~= "" and part ~= "" then
        if #part == 3 then return tonumber(whole .. part) end
        return tonumber(whole .. "." .. part)
    end
    return tonumber(whole)
end

function Reader.Numbers(feature, effect)
    feature.t1, feature.t2, feature.t3 = nil, nil, nil
    local want, k = feature.numbers, 0
    if want == 0 then return end
    for whole, mark, part in effect:gmatch(LINE.NUMBER) do
        k = k + 1
        local v = Reader.Number(whole, mark, part)
        if k == 1 then feature.t1 = v elseif k == 2 then feature.t2 = v else feature.t3 = v end
        if k >= want then break end
    end
    local period = feature.period
    if period and feature.t1 == period and feature.t2 and feature.t2 ~= period then
        feature.t1, feature.t2 = feature.t2, feature.t1
    end
end

function Reader.Unknown(text)
    local texts = Reader.unknownTexts
    for i = 1, Reader.unknown do
        if texts[i] == text then return end
    end
    if Reader.unknown < LINE.MAX_UNKNOWN then
        Reader.unknown = Reader.unknown + 1
        texts[Reader.unknown] = text
    end
end

function Reader.Line(row)
    local label, effect = row:match(LINE.PATTERN)
    if not label then label, effect = row:match(LINE.WIDE) end
    if not label or label == "" or label:find("[%d|]") or label:find("ID$") then return false end
    local feature = Reader.FeatureOf(label, effect)
    if not feature then
        Reader.Unknown(#effect <= LINE.SHORT_EFFECT and effect or label)
    elseif feature.tipGen ~= Reader.gen then
        feature.tipGen, feature.lineName = Reader.gen, label
        Reader.Numbers(feature, effect)
    end
    return true
end

function Reader.Settle()
    Reader.tryInstance, Reader.tryExpiry, Reader.tryGen = nil, nil, Reader.tryGen + 1
end

function Reader.Again(instance, expiry)
    if instance ~= Reader.tryInstance or expiry ~= Reader.tryExpiry then
        Reader.tryInstance, Reader.tryExpiry, Reader.tryGen = instance, expiry, Reader.tryGen + 1
    end
    Reader.nextTry, Reader.armedGen = GetTime() + LINE.RETRY, Reader.tryGen
    if not Reader.armed then
        Reader.armed = true
        C_Timer.After(LINE.RETRY, Reader.Retry)
    end
end

function Reader.Camp(aura)
    local instance, expiry = aura.auraInstanceID, aura.expirationTime
    if Secret(instance) or Secret(expiry) then
        Reader.gen, Reader.instance, Reader.unknown = Reader.gen + 1, nil, 0
        Reader.Settle()
        return
    end
    if instance ~= nil and instance == Reader.instance and expiry == Reader.expiry then return end
    if instance ~= nil and instance == Reader.tryInstance and expiry == Reader.tryExpiry
        and GetTime() < Reader.nextTry then return end
    Reader.Names()
    Reader.gen, Reader.instance, Reader.expiry, Reader.unknown = Reader.gen + 1, nil, nil, 0
    local data = instance and C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", instance)
    local lines = data and data.lines
    local found = false
    if type(lines) == "table" then
        for i = 2, #lines do
            local text = lines[i] and lines[i].leftText
            if text ~= nil and not Secret(text) and type(text) == "string" then
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                for row in text:gmatch("[^\n]+") do
                    if Reader.Line(row) then found = true end
                end
            end
        end
    end
    if found then
        Reader.instance, Reader.expiry = instance, expiry
        Reader.Settle()
    elseif instance ~= nil then
        Reader.Again(instance, expiry)
    end
end

function Reader.Add(n, feature, a1, a2, a3)
    n = n + 1
    if feature.period and a1 and not a2 then a2 = feature.period end
    feature.a1, feature.a2, feature.a3 = a1, a2, a3
    bonusTags[n], bonusFeatures[n] = feature.tag, feature
    return n
end

function Reader.Merge(tip)
    local n, mask = 0, 0
    for i = 1, #FEATURES do
        local feature = FEATURES[i]
        local found = C_UnitAuras.GetPlayerAuraBySpellID(feature.id)
        if found then
            local p, count = feature.amount and Points(feature, found), feature.points
            n = Reader.Add(n, feature, p and p[1] or nil, p and count >= 2 and p[2] or nil,
                p and count >= 3 and p[3] or nil)
            mask = mask + feature.bit
        elseif tip and feature.tipGen == Reader.gen then
            n = Reader.Add(n, feature, feature.t1, feature.t2, feature.t3)
            mask = mask + feature.bit
        end
    end
    if not tip then return n, mask end
    local texts = Reader.unknownTexts
    for i = 1, Reader.unknown do
        n = n + 1
        bonusTags[n], bonusFeatures[n] = texts[i], false
    end
    return n, mask
end

function Reader.Join(n, mask, unknown)
    if unknown then
        if Reader.joinedGen ~= Reader.gen or Reader.joinedMask ~= mask then
            Reader.joined = table.concat(bonusTags, "\n", 1, n)
            Reader.joinedGen, Reader.joinedMask = Reader.gen, mask
        end
        return Reader.joined
    end
    local text = joinedTags[mask]
    if not text then
        text = table.concat(bonusTags, "\n", 1, n)
        joinedTags[mask] = text
    end
    return text
end

local Refresh

function Reader.Retry()
    Reader.armed = false
    if Reader.armedGen ~= Reader.tryGen or not Reader.tryInstance then return end
    local wait = Reader.nextTry - GetTime()
    if wait > 0 then
        Reader.armed = true
        C_Timer.After(wait, Reader.Retry)
        return
    end
    Refresh()
end

local function ReadBonuses(aura)
    if aura then Reader.Camp(aura) end
    local tip = aura ~= nil and Reader.instance ~= nil
    local n, mask = Reader.Merge(tip)
    if n == 0 and not aura then return false end
    bonusText = Reader.Join(n, mask, tip and Reader.unknown > 0)
    bonusCount = n
    if Simple() then FilterBar() end
    return n > 0
end

local function DisarmAlert()
    alertGen = alertGen + 1
    alertArmed = nil
end

-- UNIT_AURA fires often, so the timer is only set again for a new expiry.
local function UpdateAlert(aura)
    if not (S.Get("campNearbyAlert") and C_UnitAuras.GetPlayerAuraBySpellID(CAMPFIRE_NEARBY)) then
        alertDismissed = nil
        DisarmAlert()
        SetAlert(false)
        return
    end
    if alertDismissed or (Simple() and not aura) then
        DisarmAlert()
        SetAlert(false)
        return
    end
    local expiry = aura and aura.expirationTime
    if expiry and issecretvalue and issecretvalue(expiry) then expiry = nil end
    local left = expiry and expiry > 0 and expiry - GetTime()
    if aura and not left then
        DisarmAlert()
        SetAlert(false)
        return
    end
    local low = S.Get("campNearbyMinutes") * 60
    local duration = aura and aura.duration
    if duration and (Secret(duration) or duration <= 0) then duration = nil end
    local timed = aura and duration and left < low
    SetAlert(not aura or left < low, timed and expiry - duration or nil, timed and duration or nil)
    if not (aura and left >= low) then
        DisarmAlert()
    elseif alertArmed ~= expiry then
        DisarmAlert()
        alertArmed = expiry
        local gen = alertGen
        C_Timer.After(left - low + 0.1, function()
            if gen == alertGen then
                alertArmed = nil
                Refresh()
            end
        end)
    end
end

-- The client hides the player's auras from addons during combat, where this read comes back
-- empty with the buff up, so the icon keeps whatever it last showed until the fight ends.
-- InCombatLockdown() is still false while PLAYER_REGEN_DISABLED is handled.
function Refresh(_, event)
    if not icon then return end
    if unlocked then
        ShowUp(3600, GetTime() + 2400, UNLOCK_TEXT, sampleLabels, sampleIcons, FillSamples(true))
        SetAlert(S.Get("campNearbyAlert"))
        return
    end
    if not (On() and InOpenWorld()) then
        icon:Hide()
        DisarmAlert()
        SetAlert(false)
        return
    end
    if InCombatLockdown() or event == "PLAYER_REGEN_DISABLED" or C_Secrets.ShouldAurasBeSecret() then
        DisarmAlert()
        SetAlert(false)
        return
    end

    local aura = C_UnitAuras.GetPlayerAuraBySpellID(CAMP_BENEFITS)
    local had = hasCamp
    hasCamp = aura ~= nil
    local sitting = C_UnitAuras.GetPlayerAuraBySpellID(WELCOMING_CAMPFIRE)
        or C_UnitAuras.GetPlayerAuraBySpellID(WELCOMING_CAMPFIRE_CRAFT)
    local sitDuration, sitExpiry = sitting and sitting.duration, sitting and sitting.expirationTime
    if sitting and not (issecretvalue and (issecretvalue(sitDuration) or issecretvalue(sitExpiry)))
        and sitDuration > 0 then
        ShowSitting(sitDuration, sitExpiry, Simple() and ReadBonuses(aura) or false)
        DisarmAlert()
        SetAlert(false)
        return
    end
    if aura then
        local duration, expiry = aura.duration, aura.expirationTime
        if issecretvalue and (issecretvalue(duration) or issecretvalue(expiry)) then
            duration, expiry = nil, nil
        end
        local left = expiry and expiry > 0 and expiry - GetTime()
        local under = S.Get("campShowUnderMinutes") * 60
        if S.Get("campShowUnder") and left and left > under then
            icon:Hide()
            local key = expiry .. ":" .. under
            if showArmed ~= key then
                showArmed = key
                showGen = showGen + 1
                local gen = showGen
                C_Timer.After(left - under + 0.1, function()
                    if gen == showGen then
                        showArmed = nil
                        Refresh()
                    end
                end)
            end
        else
            if showArmed then
                showArmed = nil
                showGen = showGen + 1
            end
            if Simple() or ns.CampBuffMode() ~= "off" then ReadBonuses(aura) end
            ShowUp(duration, expiry, bonusText, barLabels, barIcons, barCount)
        end
    else
        ShowMissing(C_UnitAuras.GetPlayerAuraBySpellID(CAMPFIRE_NEARBY) ~= nil)
        if had and S.Get("campSound") then
            ns.UI._PlayLSMSound(ns.UI.SoundPathFor(S.Get("campSoundKey")))
        end
    end
    UpdateAlert(aura)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Refresh)

local function Apply()
    if not On() then
        events:UnregisterAllEvents()
        hasCamp = nil
        ringGen = ringGen + 1
        DisarmAlert()
        SetAlert(false)
        if icon and not unlocked then icon:Hide() end
        if not unlocked then return end
    end
    if not icon then Build() end
    local simple = Simple()
    UseStyle(simple)
    icon:EnableMouse(not simple and ns.CampBuffMode() == "hover")
    if simple then
        Bar.Layout(simpleBar)
        FilterBar()
    else
        Look.Layout(icon)
    end
    Place()
    icon.mover:SetShown(unlocked == true)
    if On() then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
    shownExpiry = nil
    Refresh()
    if alert then LayoutAlert() end
end

hooksecurefunc(S, "Set", function(key)
    -- A timer armed for the old threshold would fire at the wrong time.
    if key == "campNearbyMinutes" then DisarmAlert() end
    if key == "enabled" or (key:find("^camp") and key ~= "campPos") then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if icon then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group

local OFF = "Turn on AuraBuffs"
local STAGE_H, ALERT_H, NOTE_Y, NOTE_SIZE, NOTE_GAP_Y, STAGE_MARGIN, HINT_ROOM = 230, 120, 10, 11, 4, 16, 30
local CAMP_HOUR, SIT_TIME, BUFF_GAP = 3600, 60, 12
local EDGE_HIT, HIDDEN_ALPHA, DRAG_FACTOR = 8, 0.35, 2
local WIDTH_RANGE, TEXT_RANGE, HEIGHT_RANGE = { 200, 480, 5 }, { BAR.TEXT_MIN, 16, 1 }, { 20, 36, 1 }
local SAMPLE_BUFFS = "+Rested\n+Crit"
local SIMPLE_HINT = "Drag the right edge for width. Wheel: text size (Shift: height). Click a bonus or the time "
    .. "to show or hide it. Right-click for more."
local SIMPLE_OFF_HINT = "Turn on the Campfire reminder to edit the bar here."
local SAMPLES = { up = 2400, low = 720, sitting = 35, unread = 2400, alert = 100 }
local STYLES = { { round = "Round", simple = "Simple" }, { "round", "simple" } }
local BUFF_MODES = { { off = "Off", always = "Always", hover = "On Mouseover" }, { "off", "always", "hover" } }
local SIDES = { { below = "Below", above = "Above", left = "Left", right = "Right" },
    { "below", "above", "left", "right" } }
local BAR_KEYS = { campSimpleWidth = true, campSimpleHeight = true, campSimpleTextSize = true,
    campBonusIcons = true, campHiddenBonuses = true }

local function NearbyState() return Simple() and S.Get("campShowMissing") and true or false end

local STATES = {
    { key = "up", label = "Active", tip = "Camp Benefits with most of its hour left." },
    { key = "low", label = "Running Low", tip = "Camp Benefits running down." },
    { key = "sitting", label = "Resting", tip = "Sitting at a campfire, before Camp Benefits lands." },
    { key = "missing", label = "Refresh", tip = "No Camp Benefits, out in the world.", needs = "campShowMissing" },
    { key = "nearby", label = "Camp Nearby", tip = "No Camp Benefits, with a campfire in range.", needs = NearbyState },
    { key = "unread", label = "No Bonuses", tip = "Camp Benefits up, with no bonuses listed on it.", needs = Simple },
}
local ALERT_STATES = {
    { key = "nearby", label = "Camp Nearby", tip = "A campfire in range and no Camp Benefits." },
    { key = "low", label = "Running Low", tip = "A campfire in range and Camp Benefits about to run out." },
}
local ALERT_SCALE = { 100, 250, 10 }
local ALERT_HINT = "Wheel: size. Right-click for more."

local campCard

local function Enabled() return S.Get("enabled") and true or false end
local function Needs(key) return function() return S.Get("enabled") and S.Get(key) and true or false end end
local function CampOn() return S.Get("enabled") and S.Get("campfire") and true or false end
local function RoundStyle() return not Simple() end
local function PickBuffMode(v) S.Set("campBuffMode", v) end

local function HiddenNote(state)
    if (state == "up" or state == "unread") and S.Get("campShowUnder")
        and SAMPLES.up > S.Get("campShowUnderMinutes") * 60 then
        return ("Show Only When Low: hidden until under %d min."):format(S.Get("campShowUnderMinutes"))
    end
end

local function ToggleBonus(feature)
    local copy = {}
    for id, on in pairs(S.Get("campHiddenBonuses") or {}) do copy[id] = on end
    if copy[feature.id] then copy[feature.id] = nil else copy[feature.id] = true end
    S.Set("campHiddenBonuses", copy)
end

local function ShowAllBonuses() S.Set("campHiddenBonuses", {}) end
local function BonusShown(feature) return not Hidden(feature) end
local function Toggled(key) return S.Get(key) == true end
local function Toggle(key) S.Set(key, not S.Get(key)) end
local function StylePicked(style) return S.Get("campStyle") == style end
local function PickStyle(style) S.Set("campStyle", style) end
local function BonusClicked(zone) ToggleBonus(zone.feature) end
local function TimeClicked() Toggle("campTimer") end
local function WidthSet(v) S.Set("campSimpleWidth", v) end

local function ResetBar()
    for _, row in ipairs(campCard.rows) do
        if BAR_KEYS[row.key] then Settings.ResetRow(row) end
    end
end

local function BarWheel(_, delta)
    local key, range = "campSimpleTextSize", TEXT_RANGE
    if IsShiftKeyDown() then key, range = "campSimpleHeight", HEIGHT_RANGE end
    local v = Settings.Snap(S.Get(key) + delta * range[3], range)
    if v ~= S.Get(key) then S.Set(key, v) end
end

local function BarMenu(_, root)
    root:CreateTitle("Style")
    root:CreateRadio("Round", StylePicked, PickStyle, "round")
    root:CreateRadio("Simple", StylePicked, PickStyle, "simple")
    root:CreateDivider()
    root:CreateCheckbox("Bonus Icons", Toggled, Toggle, "campBonusIcons")
    root:CreateCheckbox("Show Timer", Toggled, Toggle, "campTimer")
    local list = root:CreateButton("Bonuses")
    for _, feature in ipairs(FEATURES) do
        list:CreateCheckbox(feature.name and feature.short .. St.PLACE_DOT .. feature.name or feature.short,
            BonusShown, ToggleBonus, feature)
    end
    root:CreateDivider()
    root:CreateButton("Reset Bar", ResetBar)
end

local function NewPreview(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.icon = CreateFrame("Frame", nil, shot)
    Look.New(shot.icon)
    shot.hint = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.hint:SetPoint("BOTTOMLEFT", STAGE_MARGIN, NOTE_Y)
    shot.hint:SetPoint("BOTTOMRIGHT", -STAGE_MARGIN, NOTE_Y)
    shot.note = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    return shot
end

local function Fit(shot)
    local f = shot.icon
    local reach = f:GetHeight() + (S.Get("campBuffTextSize") + BUFF_GAP) * 2
    local room = shot:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2
    local scale = 1
    if room > 0 and reach > room then scale = room / reach end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", shot, "CENTER", 0, NOTE_Y / scale)
end

local function Run(f, left, duration)
    local start = GetTime() - (duration - left)
    f.timer:SetCooldown(start, duration)
    f.drain:SetCooldown(start, duration)
    Look.Timed(f, S.Get("campTimer"))
end

local function Zone(shot, opts)
    opts.wheel, opts.menu = BarWheel, BarMenu
    local zone = Settings.EditZone(shot.bar, opts)
    zone:SetFrameLevel(shot.bar.camp:GetFrameLevel() + #shot.zones + 1)
    shot.zones[#shot.zones + 1] = zone
    return zone
end

local function PreviewBar(shot)
    if shot.bar then return shot.bar end
    shot.barHost = CreateFrame("Frame", nil, shot)
    local f = Bar.New(shot.barHost)
    shot.bar, shot.zones, shot.bonusZones = f, {}, {}
    local body = Zone(shot, {})
    body:SetAllPoints(f.bar)
    f.labels:SetLabels(sampleLabels, FillSamples(false))
    for i = 1, #SAMPLE_BONUSES do
        local zone = Zone(shot, { click = BonusClicked, wash = true })
        zone.feature = SAMPLE_BONUSES[i][1]
        zone:SetAllPoints(f.labels.labels[i])
        shot.bonusZones[i] = zone
    end
    shot.timeZone = Zone(shot, { click = TimeClicked, wash = true })
    shot.timeZone:SetPoint("TOPRIGHT", f.bar, "TOPRIGHT")
    shot.timeZone:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
    shot.dragRange = { WIDTH_RANGE[1], WIDTH_RANGE[2], WIDTH_RANGE[3] }
    shot.widthZone = Zone(shot, { edge = true, drag = { get = function() return f.width end, set = WidthSet,
        range = shot.dragRange,
        factor = DRAG_FACTOR, live = function(v) f.width = v; BarSize(f) end } })
    shot.widthZone:SetPoint("TOP", f.bar, "TOPRIGHT")
    shot.widthZone:SetPoint("BOTTOM", f.bar, "BOTTOMRIGHT")
    shot.widthZone:SetWidth(EDGE_HIT)
    return f
end

local function FitBar(shot)
    local host, f = shot.barHost, shot.bar
    local half = S.Default("campSimpleWidth") / 2
    local reach, h = WIDTH_RANGE[2] - half, f.height
    local roomW = shot:GetWidth() / 2 - STAGE_MARGIN
    local roomH = shot:GetHeight() - STAGE_MARGIN * 2 - HINT_ROOM
    local scale = 1
    if roomW > 0 and reach > roomW then scale = roomW / reach end
    if roomH > 0 and h * scale > roomH then scale = roomH / h end
    host:SetScale(scale)
    host:ClearAllPoints()
    host:SetPoint("LEFT", shot, "CENTER", -half, HINT_ROOM / 2 / scale)
end

local function RunBar(f, left, duration, timed, prefix)
    if timed then f.line:Run(GetTime() - (duration - left), duration, prefix) end
    Bar.Timed(f, timed)
end

local function PaintBarPreview(shot, state, hidden)
    local f = PreviewBar(shot)
    Bar.Layout(f)
    local timed = S.Get("campTimer") and true or false
    local n = FillSamples(false)
    local pill = state == "missing" or state == "nearby"
    if pill then
        Bar.Missing(f, state == "nearby")
    elseif state == "sitting" then
        Bar.Sitting(f, sampleLabels, sampleIcons, n, timed, false)
        Bar.Paint(f, T.accent, false)
        RunBar(f, SAMPLES.sitting, SIT_TIME, timed, SIT_PREFIX)
    else
        Bar.Up(f, sampleLabels, sampleIcons, state == "unread" and 0 or n, timed)
        local step = Look.Step(SAMPLES[state])
        Bar.Paint(f, step[2], step ~= TIME_STEPS[1])
        RunBar(f, SAMPLES[state], CAMP_HOUR, timed)
    end
    local editable = CampOn()
    for _, zone in ipairs(shot.zones) do zone:SetShown(editable and (not pill or zone == shot.zones[1])) end
    local bonuses = f.labels.count - (f.more > 0 and 1 or 0)
    for i, zone in ipairs(shot.bonusZones) do
        local alpha = Hidden(zone.feature) and HIDDEN_ALPHA or 1
        f.labels.labels[i]:SetAlpha(alpha)
        if f.labels.icons[i] then f.labels.icons[i]:SetAlpha(alpha) end
        if i > bonuses then zone:Hide() end
    end
    shot.timeZone:SetWidth(f.timeW + BAR.PAD)
    local step = WIDTH_RANGE[3]
    shot.dragRange[1] = math.max(WIDTH_RANGE[1], math.ceil(f.minW / step) * step)

    FitBar(shot)
    shot.barHost:SetShown(not hidden)
    shot.hint:SetText(editable and SIMPLE_HINT or SIMPLE_OFF_HINT)
    shot.note:ClearAllPoints()
    shot.note:SetPoint("BOTTOM", shot.hint, "TOP", 0, NOTE_GAP_Y)
    shot.note:SetText(hidden or "")
end

local function PaintPreview(shot, state)
    local f = shot.icon
    local hidden = HiddenNote(state)
    if Simple() then
        f:Hide()
        PaintBarPreview(shot, state, hidden)
        return
    end
    if shot.barHost then shot.barHost:Hide() end
    shot.hint:SetText("")
    shot.note:ClearAllPoints()
    shot.note:SetPoint("BOTTOM", shot, "BOTTOM", 0, NOTE_Y)
    Look.Layout(f)
    Fit(shot)
    local mode = ns.CampBuffMode()
    local note = hidden
    if state == "missing" then
        Look.Missing(f)
    elseif state == "sitting" then
        Look.Sitting(f)
        f.drain:SetSwipeColor(T.accent.r, T.accent.g, T.accent.b, 1)
        Run(f, SAMPLES.sitting, SIT_TIME)
    else
        Look.Up(f, mode ~= "off" and SAMPLE_BUFFS or "")
        f.buffs:SetAlpha(1)
        local color = Look.Step(SAMPLES[state] or SAMPLES.up)[2]
        f.drain:SetSwipeColor(color.r, color.g, color.b, 1)
        Run(f, SAMPLES[state] or SAMPLES.up, CAMP_HOUR)
        if not note and mode == "hover" then note = "The buffs show while you hover the icon." end
    end
    f:SetShown(not hidden)
    shot.note:SetText(note or "")
end

local alertCard

local function AlertWheel(_, delta)
    local v = Settings.Snap(S.Get("campAlertScale") * 100 + delta * ALERT_SCALE[3], ALERT_SCALE) / 100
    if v ~= S.Get("campAlertScale") then S.Set("campAlertScale", v) end
end

local function ResetAlert()
    for _, row in ipairs(alertCard.rows) do
        if row.key == "campAlertScale" or row.key == "campAlertFade" then Settings.ResetRow(row) end
    end
end

local function AlertMenu(_, root)
    root:CreateTitle("Camp Nearby")
    root:CreateCheckbox("Fade", Toggled, Toggle, "campAlertFade")
    root:CreateDivider()
    root:CreateButton("Reset", ResetAlert)
end

local function NewAlert(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.alert = CreateFrame("Frame", nil, shot)
    AlertLook(shot.alert)
    shot.zone = Settings.EditZone(shot.alert, { wheel = AlertWheel, menu = AlertMenu })
    shot.zone:SetAllPoints()
    shot.hint = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.hint:SetPoint("BOTTOMLEFT", STAGE_MARGIN, NOTE_Y)
    shot.hint:SetPoint("BOTTOMRIGHT", -STAGE_MARGIN, NOTE_Y)
    return shot
end

local function PaintAlert(shot, state)
    local a, f = shot.alert, shot.alert.bar
    Bar.Layout(f)
    if state == "low" then
        Bar.Nearby(f, GetTime() - (CAMP_HOUR - SAMPLES.alert), CAMP_HOUR)
    else
        Bar.Nearby(f)
    end
    local scale = S.Get("campAlertScale")
    local half = (f.labelX + f.note:GetStringWidth() + BAR.PAD) / 2
    a:SetScale(scale)
    a:ClearAllPoints()
    a:SetPoint("LEFT", shot, "CENTER", -half, HINT_ROOM / 2 / scale)
    AlertStop(a)
    a:SetAlpha(1)
    if S.Get("campAlertFade") then a.breathe:Play() end
    local editable = CampOn() and S.Get("campNearbyAlert") and true or false
    shot.zone:SetShown(editable)
    shot.hint:SetText(editable and ALERT_HINT or "")
end

local function CampSummary(store)
    if store.Get("campStyle") == "simple" then
        local parts = { "Simple bar", store.Get("campTimer") and "timer" or "no timer" }
        if store.Get("campBonusIcons") then parts[#parts + 1] = "bonus icons" end
        if store.Get("campSound") then parts[#parts + 1] = "a sound to refresh" end
        return table.concat(parts, ", ")
    end
    local parts = { store.Get("campTimer") and "Timer" or "No timer" }
    local mode = ns.CampBuffMode()
    if mode == "always" then parts[#parts + 1] = "camp buffs"
    elseif mode == "hover" then parts[#parts + 1] = "camp buffs on mouseover" end
    if store.Get("campSound") then parts[#parts + 1] = "a sound to refresh" end
    return table.concat(parts, ", ")
end

local function AlertSummary(store)
    return ("Under %d min"):format(store.Get("campNearbyMinutes"))
end

local function StageHeight()
    if Simple() then return STAGE_MARGIN * 2 + HEIGHT_RANGE[2] + HINT_ROOM end
    return STAGE_H
end

local function Only(group, hidden)
    group.hidden = hidden
    return group
end

local page = Settings.Page("AuraBuffs/Settings", S)

campCard = page:Card({
    id = "campfire", name = "Campfire", order = 20, switch = "campfire",
    help = "Your camp's bonuses and time left on screen, and a reminder when Camp Benefits runs out.",
    summary = CampSummary,
    studio = { height = StageHeight, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "campStyle", label = "Style", choice = STYLES, needs = Enabled, why = OFF,
          help = "Round shows the camp icon; Simple shows a slim bar with your camp's bonuses." },
        Group("Reminder"),
        { key = "campTimer", label = "Show Camp Timer", toggle = true, needs = Enabled, why = OFF,
          help = "The time left, turning yellow, then red, as the camp runs down." },
        { key = "campShowMissing", label = "Show Refresh Reminder", toggle = true, needs = Enabled, why = OFF,
          help = "Stays on screen, greyed out, while you have no Camp Benefits." },
        { key = "campShowUnder", label = "Show Only When Low", toggle = true, needs = Enabled, why = OFF,
          help = "Hides it until the camp drops under Show Under." },
        { key = "campShowUnderMinutes", label = "Show Under", slider = { 1, 59, 1 }, unit = " min",
          needs = Needs("campShowUnder"), why = "Needs Show Only When Low" },
        Only(Group("Simple Bar"), RoundStyle),
        { key = "campSimpleWidth", label = "Bar Width", slider = WIDTH_RANGE, needs = Enabled, why = OFF,
          hidden = RoundStyle, help = "Bonuses that do not fit show as +N more." },
        { key = "campSimpleHeight", label = "Bar Height", slider = HEIGHT_RANGE, needs = Enabled, why = OFF,
          hidden = RoundStyle },
        { key = "campSimpleTextSize", label = "Text Size", slider = TEXT_RANGE, needs = Enabled, why = OFF,
          hidden = RoundStyle },
        { key = "campBonusIcons", label = "Bonus Icons", toggle = true, needs = Enabled, why = OFF,
          hidden = RoundStyle, help = "Each camp feature's own icon before its bonus." },
        { key = "campHiddenBonuses", label = "Hidden Bonuses", buttonText = "Show All", button = ShowAllBonuses,
          needs = Enabled, why = OFF, hidden = RoundStyle,
          help = "Shows every bonus again; click one on the preview to hide it." },
        Only(Group("Round Icon"), Simple),
        { key = "campIconSize", label = "Icon Size", slider = { 24, 110, 1 }, needs = Enabled, why = OFF,
          hidden = Simple },
        { key = "campBuffMode", label = "Show Active Camp Buffs", choice = BUFF_MODES, get = ns.CampBuffMode,
          set = PickBuffMode, needs = Enabled, why = OFF, hidden = Simple,
          help = "Your camp's bonuses by the icon, always or while you hover it." },
        { key = "campBuffTextSize", label = "Buff Text Size", slider = { 8, 28, 1 }, needs = Enabled, why = OFF,
          hidden = Simple },
        { key = "campBuffSide", label = "Buff Text Position", choice = SIDES, needs = Enabled, why = OFF,
          hidden = Simple },
        Group("Sound"),
        { key = "campSound", label = "Play a Sound to Refresh", toggle = true, needs = Enabled, why = OFF,
          help = "Plays when it is time to refresh the camp." },
        { key = "campSoundKey", label = "Sound", sound = true, needs = Needs("campSound"),
          why = "Needs Play a Sound to Refresh" },
    },
})

alertCard = page:Card({
    id = "campNearby", name = "Camp Nearby", order = 30, switch = "campNearbyAlert",
    help = "Camp Nearby on screen when a campfire is in range and your camp needs a refresh.",
    summary = AlertSummary,
    studio = { height = ALERT_H, states = ALERT_STATES, new = NewAlert, paint = PaintAlert },
    rows = {
        { key = "campNearbyMinutes", label = "Alert Under", slider = { 1, 59, 1 }, unit = " min",
          needs = CampOn, why = "Needs the Campfire reminder",
          help = "How little Camp Benefits time counts as needing a refresh." },
        { key = "campAlertFade", label = "Fade", toggle = true,
          needs = CampOn, why = "Needs the Campfire reminder",
          help = "Fades the alert in and out, breathing softly while it shows." },
        Group("Size"),
        { key = "campAlertScale", label = "Alert Size", slider = ALERT_SCALE, unit = "%", scale = 0.01,
          needs = CampOn, why = "Needs the Campfire reminder" },
        Settings.Look("campAlert", { text = true, background = "card", keys = { FontSize = false },
            needs = CampOn, why = "Needs the Campfire reminder" }),
    },
})
