-- SetupWindow.lua: Tailor my setup's window, from its welcome or a new character's choice to Apply.
local ns = _G.NaowhForever
local T = ns.THEME
local Parts = ns.Shared.Parts
local St = ns.Shared.Style
local UI = ns.UI
local Setup = ns.Setup

local WIDTH, HEIGHT = 780, 580
local INSET, EDGE, HEADER = St.CONTENT_INSET, St.WINDOW_PAD, St.WINDOW_HEADER
local BUTTON_H, NAV_W, APPLY_W, START_W, START_H = 26, 110, 150, 170, 32
local FOOT_H = BUTTON_H + EDGE * 2
local TILE_GAP, TILE_H, TILE_MAX_W, HINT_GAP = 12, 156, 230, 22
local ICON, GLYPH, CHECK = 60, 34, 16
local LIT, HOVER = 0.12, 0.06
local QUESTION_SIZE, HEAD_SIZE, BODY_SIZE, SMALL_SIZE = 19, 15, 13, 11
local PANE_PAD, ALL_W, LIST_TOP = 16, 70, 50
local EMPTY_ICON = 40
local ARROW, ARROW_GAP = 12, 6
local SCROLL_W, SCROLL_GAP = 6, 6
local PILL_SIZE = 11
local POSITION_KEY = "setupWindow"
local BLACK = St.BORDER_RGB
local GOLD = St.TIP_RGB
local RED = St.RED_RGB
local CHANGES = "changes"
local CHECK_ART = ns.MEDIA .. "check.tga"
local TRACK = "Interface\\AddOns\\NaowhForever\\Core\\Onboarding\\Media\\infinity_track.tga"
local GLOW = "Interface\\AddOns\\NaowhForever\\Core\\Onboarding\\Media\\glow_dot.tga"
local HEAD_RGB = { r = 0.85, g = 0.95, b = 1 }
local GLYPHS = "Interface\\AddOns\\NaowhForever\\Core\\Onboarding\\Media\\Setup\\"
local NEXT_ART, BACK_ART = GLYPHS .. "next.tga", GLYPHS .. "back.tga"
local FILTER = "TRILINEAR"
local CHANGES_ICON = "changes"
local PANEL_ALPHA, SIDE_ALPHA, DIM_ALPHA = 0.9, 0.6, 0.5
local WELCOME_LAYOUT = { taglineTop = 30, taglineSpacing = 4, signGap = 6, siteGap = 4, siteTextGrow = 1,
    thanksW = 540, thanksGap = 10, cornerGap = 4, promiseTop = 24, promisePlate = 34, promiseGlyph = 22,
    promiseX = 12, promiseTextRoom = 60, promiseTextGap = 10, promiseSubGap = 3, startGap = 28, keepGap = 10,
    promiseW = 210, promiseH = 58, promiseGap = 12, linkSize = 16, linkGap = 10, footLine = 16, footLineH = 18,
    taglineSize = 30 }
local SIGN_SHAPE = { fullTurn = 2 * math.pi, reachX = 0.44, reachY = 0.84, shrink = 0.45, curve = 1.6, alpha = 0.9,
    w = 168, h = 84, trackAlpha = 0.35, trail = 70, trailStep = 0.022, lap = 4.2, dot = 9, headDot = 22 }
local ANIM = { fadeIn = 0.18, glowOut = 0.45, glowAlpha = 0.5, popIn = 0.18, popFrom = 0.4 }
local SEG = { w = 26, h = 4, gap = 4, right = 44 }
local TILE_LAYOUT = { checkInset = 6, markInset = 4, iconTop = 20, nameGap = 14, textRoom = 20, blurbGap = 5,
    hintGap = 6, maxOneRow = 4, wideColumns = 3 }
local SIDE_LAYOUT = { rowGap = 2, barW = 2, iconX = 8, textGap = 8, nameRoom = 24, right = 8, dot = 5, dotGap = 6,
    w = 220, h = 30, icon = 18, pad = 10, countW = 36 }
local REVIEW_LAYOUT = { nameGap = 12, nameRise = 8, yoursSize = 10, yoursGap = 6, whyGap = 4, whyRoom = 100,
    statTop = 9, statLabelGap = 3, headRoom = 16, subGap = 4, allH = 22, allGap = 6, emptyDrop = 60,
    emptyRoom = 60, emptyTextGap = 12, groupIconX = 2, groupIconY = 7, groupTextGap = 8, rowH = 48, rowGap = 4,
    stripe = 3, toggleW = 32, toggleH = 16, rowPad = 12, groupH = 30, groupGap = 8, groupIcon = 16, statH = 54,
    statGap = 6, statSize = 20 }
local FOOT_LAYOUT = { noteGap = 12, skipLift = 4 }
local CHOICE = { step = -1, columns = 2, sameArt = ns.MEDIA .. "chain.tga",
    ownArt = ns.MEDIA .. "wand.tga" }
local TEXT_BACK, TEXT_START_OVER, TEXT_NEXT = "Back", "Start Over", "Next"
local TEXT_ALL_OFF, TEXT_ALL_ON = "All Off", "All On"
local TEXT_APPLY, TEXT_APPLY_RELOAD, TEXT_SEE_SETUP = "Apply", "Apply and Reload", "See My Setup"
local TEXT_ON, TEXT_OFF = "on", "off"

local TITLE = "Naowh Forever: Onboarding"
local WELCOME_SUB = "Welcome"
local WELCOME_FOR = "Just for %s"
local WELCOME = "Welcome, and thank you for joining us"
local TAGLINE_1, TAGLINE_2A, TAGLINE_2B = "One addon", "to rule", "them all."
local SITE_LINE = "New here? Every feature is shown on our website:"
local SITE_LINK = "naowh.gg/forever"
local SITE_TITLE = "Naowh Forever on naowh.gg"
local SITE_URL = "https://naowh.gg/forever/"
local THANKS = "This is a new adventure for all of us. Naowh Forever is crafted by a small, dedicated team with "
    .. "a lot of passion, and we hope you enjoy every bit of it."
local PROMISES = {
    { "Seven quick questions", "About a minute.", "questions" },
    { "Review it all", "Nothing changes before you apply.", "review" },
    { "Undo any time", "Restore it from the Profiles page.", "undo" },
}
local START = "Let's start"
local KEEP = "or keep my setup as it is"
local QUESTION_OF = "Question %d of %d"
local PICKED = "%d picked"
local PICK_ONE = "Pick at least one."
local SKIP = "Skip this question"
local REVIEW_SUB = "Your setup: change anything before it's applied."
local STATS = { "turn on", "turn off", "stay" }
local CHANGES_NAME = "Changes"
local CHANGES_SUB = "What changes, and what you set yourself."
local NO_CHANGES = "Nothing changes: your setup already fits your answers. Look through the sections to change anything."
local THEME_SUB = "%d of %d on."
local SIDE_COUNT = "%d/%d"
local FOUND = "We found %s."
local TURNS_ON, TURNS_OFF, STAYS_ON, STAYS_OFF, YOURS_TAG = "Turns on", "Turns off", "Stays on", "Stays off", "Yours"
local YOURS = "You set this; we'd suggest %s."
local IN_COMBAT = "Apply after your fight."
local DONE_RELOAD = "Your setup is ready. Reload now to finish?"
local DONE = "Your setup is ready."
local TEXT_CHOICE = {
    head = "Welcome, %s!",
    text = "You've played Naowh Forever on %s. Share %s's settings, or give %s its own?",
    sameName = "Same as %s", sameBlurb = "%s uses %s's settings; a change on one shows on both.",
    ownName = "Set Up %s", ownBlurb = "A few quick questions for %s only, its own modules included.",
    sameDone = "%s now uses the same settings as %s.",
}

local window, answers, detected, entries, step, section, forCharacter
local newCharacter = {}
local Paint

local function Question()
    return Setup.QUESTIONS[step]
end

local function Fresh()
    local found = Setup.Detected()
    local list = {}
    for key in pairs(found) do list[key] = true end
    return { addons = list }, found
end

local function ResetQuestion(q)
    if q.id == "addons" then
        answers.addons = {}
        for key in pairs(detected) do answers.addons[key] = true end
    else
        answers[q.id] = nil
    end
end

local function Selected(q, key)
    local value = answers[q.id]
    if q.one then return (value or q.default) == key end
    return type(value) == "table" and value[key] == true
end

local function PickedCount(q)
    local n = 0
    for _, a in ipairs(q.answers) do
        if Selected(q, a[1]) then n = n + 1 end
    end
    return n
end

local function Ready(q)
    return q.one or PickedCount(q) > 0
end

local function Choose(q, answer)
    local key = answer[1]
    if q.one then
        answers[q.id] = key
    else
        local picked = answers[q.id] or {}
        answers[q.id] = picked
        local on = not picked[key]
        if on then
            for _, a in ipairs(q.answers) do
                if (answer.none and a[1] ~= key) or (not answer.none and a.none) then picked[a[1]] = nil end
            end
        end
        picked[key] = on or nil
    end
    Paint()
end

local function IsChange(e)
    return Setup.Differs(e) or e.suggest ~= e.now or e.mine
end

local function Text(parent, size, color, width, justify)
    local fs = ns.Font(parent, size, nil, color)
    fs:SetJustifyH(justify or "LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

local function SetGlyph(tex, name)
    tex:SetTexture(GLYPHS .. name .. ".tga", nil, nil, FILTER)
end

local function Tint(tex, c)
    tex:SetVertexColor(c.r, c.g, c.b)
end

local function Glyph(parent, plate, size, name)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(plate, plate)
    ns.Solid(holder, "BACKGROUND", T.bg, 1):SetAllPoints()
    holder.edge = ns.Border(holder, BLACK)
    holder.tex = holder:CreateTexture(nil, "ARTWORK")
    holder.tex:SetPoint("CENTER")
    holder.tex:SetSize(size, size)
    if name then SetGlyph(holder.tex, name) end
    return holder
end

local function Rule(parent)
    local rule = ns.Solid(parent, "ARTWORK", T.line, 1)
    ns.Hairline(rule, "h")
    return rule
end

local function Panel(parent)
    local frame = CreateFrame("Frame", nil, parent)
    ns.Solid(frame, "BACKGROUND", T.panel, PANEL_ALPHA):SetAllPoints()
    frame.edge = ns.Border(frame, BLACK)
    return frame
end

local function SetLit(frame, on, hovered)
    local edge = on and T.accent or hovered and T.accentSoft or BLACK
    frame.edge:SetColor(edge.r, edge.g, edge.b, 1)
    frame.lit:SetShown(on or hovered)
    frame.lit:SetAlpha(on and 1 or HOVER / LIT)
end

local function FadeIn(frame)
    if not frame.fadeIn then
        local group = frame:CreateAnimationGroup()
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(ANIM.fadeIn)
        alpha:SetSmoothing("OUT")
        frame.fadeIn = group
    end
    frame.fadeIn:Stop()
    frame.fadeIn:Play()
end

local function Glow(frame)
    if not frame.glow then
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        local group = tex:CreateAnimationGroup()
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(ANIM.glowAlpha)
        alpha:SetToAlpha(0)
        alpha:SetDuration(ANIM.glowOut)
        alpha:SetSmoothing("OUT")
        frame.glow = group
    end
    frame.glow:Stop()
    frame.glow:Play()
end

local function Pop(frame)
    if not frame.pop then
        local group = frame:CreateAnimationGroup()
        local scale = group:CreateAnimation("Scale")
        scale:SetScaleFrom(ANIM.popFrom, ANIM.popFrom)
        scale:SetScaleTo(1, 1)
        scale:SetDuration(ANIM.popIn)
        scale:SetSmoothing("OUT")
        frame.pop = group
    end
    frame.pop:Stop()
    frame.pop:Play()
end

local function Arrow(button, art, after)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ARROW, ARROW)
    icon:SetTexture(art, nil, nil, FILTER)
    Tint(icon, T.fg)
    local shift = (ARROW + ARROW_GAP) / 2
    button.label:ClearAllPoints()
    button.label:SetPoint("CENTER", after and -shift or shift, 0)
    if after then
        icon:SetPoint("LEFT", button.label, "RIGHT", ARROW_GAP, 0)
    else
        icon:SetPoint("RIGHT", button.label, "LEFT", -ARROW_GAP, 0)
    end
    button.arrow = icon
    return button
end

local function Page()
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", 0, -HEADER)
    page:SetPoint("BOTTOMRIGHT", 0, FOOT_H)
    return page
end

local function KeepAsItIs()
    window:Hide()
end

local function Hidden(self)
    window.events:UnregisterAllEvents()
    if self:IsShown() then return end
    local account = ns.AccountSettings()
    account.onboardingSeen, account.welcomeSeen = true, true
    ns.MarkAsked()
end

local function ShowSite()
    ns.ShowCopyLine(SITE_TITLE, SITE_URL, St.LOGO)
end

local function SignPoint(angle)
    local s, c = math.sin(angle), math.cos(angle)
    local k = 1 + s * s
    return SIGN_SHAPE.w * SIGN_SHAPE.reachX * c / k, SIGN_SHAPE.h * SIGN_SHAPE.reachY * s * c / k
end

local function Spin(sign, elapsed)
    sign.angle = (sign.angle + elapsed * SIGN_SHAPE.fullTurn / SIGN_SHAPE.lap) % SIGN_SHAPE.fullTurn
    for i, dot in ipairs(sign.dots) do
        dot:SetPoint("CENTER", sign, "CENTER", SignPoint(sign.angle - (i - 1) * SIGN_SHAPE.trailStep))
    end
end

local function SpinStart(sign)
    sign:SetScript("OnUpdate", Spin)
end

local function SpinStop(sign)
    sign:SetScript("OnUpdate", nil)
end

local function Sign(page)
    local sign = CreateFrame("Frame", nil, page)
    sign:SetSize(SIGN_SHAPE.w, SIGN_SHAPE.h)
    local track = sign:CreateTexture(nil, "ARTWORK")
    track:SetTexture(TRACK, nil, nil, FILTER)
    track:SetAllPoints()
    track:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
    track:SetAlpha(SIGN_SHAPE.trackAlpha)
    sign.dots = {}
    for i = 1, SIGN_SHAPE.trail + 1 do
        local dot = sign:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(GLOW, nil, nil, FILTER)
        dot:SetBlendMode("ADD")
        if i == 1 then
            dot:SetSize(SIGN_SHAPE.headDot, SIGN_SHAPE.headDot)
            dot:SetVertexColor(HEAD_RGB.r, HEAD_RGB.g, HEAD_RGB.b)
        else
            local fade = (i - 2) / SIGN_SHAPE.trail
            local size = SIGN_SHAPE.dot * (1 - SIGN_SHAPE.shrink * fade)
            dot:SetSize(size, size)
            dot:SetVertexColor(T.accent.r + (HEAD_RGB.r - T.accent.r) * (1 - fade),
                T.accent.g + (HEAD_RGB.g - T.accent.g) * (1 - fade), T.accent.b + (HEAD_RGB.b - T.accent.b) * (1 - fade))
            dot:SetAlpha((1 - fade) ^ SIGN_SHAPE.curve * SIGN_SHAPE.alpha)
        end
        sign.dots[i] = dot
    end
    sign.angle = 0
    Spin(sign, 0)
    sign:SetScript("OnShow", SpinStart)
    sign:SetScript("OnHide", SpinStop)
    return sign
end

local function Corners(page)
    local middle = WELCOME_LAYOUT.footLine + WELCOME_LAYOUT.footLineH / 2
    local x = EDGE + WELCOME_LAYOUT.cornerGap
    for _, link in ipairs(ns.LINKS) do
        local name, url = link[1], link[3]
        local button = Parts.IconButton(page, function() ns.ShowCopyLine(name, url()) end,
            ns.LINK_ICONS .. link[2] .. ".tga", nil, name)
        button:SetSize(WELCOME_LAYOUT.linkSize, WELCOME_LAYOUT.linkSize)
        button.icon:SetSize(WELCOME_LAYOUT.linkSize, WELCOME_LAYOUT.linkSize)
        button:SetPoint("LEFT", window, "BOTTOMLEFT", x, middle)
        x = x + WELCOME_LAYOUT.linkSize + WELCOME_LAYOUT.linkGap
    end
    page.version = ns.Font(page, SMALL_SIZE, nil, T.muted)
    page.version:SetPoint("RIGHT", window, "BOTTOMRIGHT", -EDGE - WELCOME_LAYOUT.cornerGap, middle)
    page.version:SetText(ns.VersionText())
end

local function Tagline(page)
    page.tagline = Text(page, WELCOME_LAYOUT.taglineSize, T.fg, WIDTH - INSET * 2, "CENTER")
    page.tagline:SetPoint("TOP", 0, -WELCOME_LAYOUT.taglineTop)
    page.tagline:SetText(TAGLINE_1 .. "\n" .. ns.Color(T.accent) .. TAGLINE_2A .. "|r " .. St.LOOK_CODE .. TAGLINE_2B .. "|r")
    page.tagline:SetSpacing(WELCOME_LAYOUT.taglineSpacing)
    page.sign = Sign(page)
    page.sign:SetPoint("TOP", page.tagline, "BOTTOM", 0, -WELCOME_LAYOUT.signGap)
end

local function BuildWelcome()
    local page = Page()
    Tagline(page)
    page.head = Text(page, HEAD_SIZE, T.fg, WIDTH - INSET * 2, "CENTER")
    page.head:SetPoint("TOP", page.sign, "BOTTOM", 0, -WELCOME_LAYOUT.signGap)
    page.head:SetText(WELCOME)
    page.site = CreateFrame("Frame", nil, page)
    page.site:SetPoint("BOTTOM", window, "BOTTOM", 0, WELCOME_LAYOUT.footLine)
    page.site:SetHeight(WELCOME_LAYOUT.footLineH)
    local siteText = ns.Font(page.site, SMALL_SIZE + WELCOME_LAYOUT.siteTextGrow, nil, T.muted)
    siteText:SetPoint("LEFT")
    siteText:SetText(SITE_LINE)
    local siteLink = Parts.Link(page.site, ShowSite)
    Parts.SetLink(siteLink, SITE_LINK)
    siteLink:SetPoint("LEFT", siteText, "RIGHT", WELCOME_LAYOUT.siteGap, 0)
    page.site:SetWidth(math.ceil(siteText:GetStringWidth()) + WELCOME_LAYOUT.siteGap + siteLink:GetWidth())
    Corners(page)
    page.text = Text(page, BODY_SIZE, T.muted, WELCOME_LAYOUT.thanksW, "CENTER")
    page.text:SetPoint("TOP", page.head, "BOTTOM", 0, -WELCOME_LAYOUT.thanksGap)
    page.text:SetText(THANKS)
    local rowW = #PROMISES * WELCOME_LAYOUT.promiseW + (#PROMISES - 1) * WELCOME_LAYOUT.promiseGap
    for i, p in ipairs(PROMISES) do
        local tile = Panel(page)
        tile:SetSize(WELCOME_LAYOUT.promiseW, WELCOME_LAYOUT.promiseH)
        tile:SetPoint("TOPLEFT", page.text, "BOTTOM", -rowW / 2 + (i - 1) * (WELCOME_LAYOUT.promiseW + WELCOME_LAYOUT.promiseGap), -WELCOME_LAYOUT.promiseTop)
        local icon = Glyph(tile, WELCOME_LAYOUT.promisePlate, WELCOME_LAYOUT.promiseGlyph, p[3])
        Tint(icon.tex, T.accent)
        icon:SetPoint("LEFT", WELCOME_LAYOUT.promiseX, 0)
        local name = Text(tile, BODY_SIZE, T.fg, WELCOME_LAYOUT.promiseW - WELCOME_LAYOUT.promiseTextRoom)
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", WELCOME_LAYOUT.promiseTextGap, 0)
        name:SetText(p[1])
        local sub = Text(tile, SMALL_SIZE, T.muted, WELCOME_LAYOUT.promiseW - WELCOME_LAYOUT.promiseTextRoom)
        sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -WELCOME_LAYOUT.promiseSubGap)
        sub:SetText(p[2])
        page.last = tile
    end
    page.start = Arrow(ns.AccentBorder(ns.Button(page, START, START_W, START_H, function()
        step = 1
        Paint()
    end)), NEXT_ART, true)
    page.start:SetPoint("TOP", page.text, "BOTTOM", 0, -WELCOME_LAYOUT.promiseTop - WELCOME_LAYOUT.promiseH - WELCOME_LAYOUT.startGap)
    page.keep = Parts.Link(page, KeepAsItIs)
    Parts.SetLink(page.keep, KEEP)
    page.keep:SetPoint("TOP", page.start, "BOTTOM", 0, -WELCOME_LAYOUT.keepGap)
    return page
end

local function TileEnter(tile)
    tile.hovered = true
    SetLit(tile, tile.on, true)
end

local function TileLeave(tile)
    tile.hovered = false
    SetLit(tile, tile.on, false)
end

local function TileClick(tile)
    if not tile.onPick then return end
    tile.onPick()
    Glow(tile)
    if tile.on then Pop(tile.check) end
end

local function Tile(page, i)
    local tile = page.tiles[i]
    if tile then return tile end
    tile = CreateFrame("Button", nil, page)
    ns.Solid(tile, "BACKGROUND", T.panel, PANEL_ALPHA):SetAllPoints()
    tile.lit = ns.Solid(tile, "BORDER", T.accent, LIT)
    tile.lit:SetAllPoints()
    tile.edge = ns.Border(tile, BLACK)
    tile.icon = Glyph(tile, ICON, GLYPH)
    tile.name = ns.Font(tile, BODY_SIZE, nil, T.fg)
    tile.blurb = ns.Font(tile, SMALL_SIZE, nil, T.muted)
    tile.name:SetJustifyH("CENTER")
    tile.blurb:SetJustifyH("CENTER")
    tile.check = CreateFrame("Frame", nil, tile)
    tile.check:SetSize(CHECK, CHECK)
    tile.check:SetPoint("TOPRIGHT", -TILE_LAYOUT.checkInset, -TILE_LAYOUT.checkInset)
    ns.Solid(tile.check, "BACKGROUND", T.accent, 1):SetAllPoints()
    local mark = tile.check:CreateTexture(nil, "ARTWORK")
    mark:SetTexture(CHECK_ART)
    mark:SetPoint("CENTER")
    mark:SetSize(CHECK - TILE_LAYOUT.markInset, CHECK - TILE_LAYOUT.markInset)
    tile:SetScript("OnEnter", TileEnter)
    tile:SetScript("OnLeave", TileLeave)
    tile:SetScript("OnClick", TileClick)
    page.tiles[i] = tile
    return tile
end

local function LayoutTile(tile, width)
    tile:SetSize(width, TILE_H)
    tile.icon:ClearAllPoints()
    tile.icon:SetPoint("TOP", 0, -TILE_LAYOUT.iconTop)
    tile.name:ClearAllPoints()
    tile.name:SetPoint("TOP", tile.icon, "BOTTOM", 0, -TILE_LAYOUT.nameGap)
    tile.name:SetWidth(width - TILE_LAYOUT.textRoom)
    tile.blurb:ClearAllPoints()
    tile.blurb:SetPoint("TOP", tile.name, "BOTTOM", 0, -TILE_LAYOUT.blurbGap)
    tile.blurb:SetWidth(width - TILE_LAYOUT.textRoom)
end

local function TileWidth(columns)
    return math.min(TILE_MAX_W, (WIDTH - INSET * 2 - (columns - 1) * TILE_GAP) / columns)
end

local function PaintTile(tile, on)
    tile.on = on
    local text = on and T.accent or T.fg
    tile.name:SetTextColor(text.r, text.g, text.b)
    Tint(tile.icon.tex, text)
    local plate = on and T.accent or BLACK
    tile.icon.edge:SetColor(plate.r, plate.g, plate.b, 1)
    tile.check:SetShown(on)
    SetLit(tile, on, tile.hovered)
end

local function UseMain()
    local who = newCharacter
    if Setup.ShareProfile(who.profile) then ns.Print(TEXT_CHOICE.sameDone:format(who.me, who.main)) end
    window:Hide()
end

local function SetUpOwn()
    if not Setup.OwnProfile(newCharacter.me) then return end
    ns.MarkAsked()
    Setup.ForCharacter(true)
    forCharacter = newCharacter.me
    step = 1
    Paint()
end

local function ChoiceTile(page, i, art, onPick)
    local tile = Tile(page, i)
    local width = TileWidth(CHOICE.columns)
    local rowW = CHOICE.columns * width + (CHOICE.columns - 1) * TILE_GAP
    LayoutTile(tile, width)
    tile:SetPoint("TOPLEFT", page.text, "BOTTOM", -rowW / 2 + (i - 1) * (width + TILE_GAP), -WELCOME_LAYOUT.promiseTop)
    tile.icon.tex:SetTexture(art, nil, nil, FILTER)
    tile.onPick = onPick
    PaintTile(tile, false)
    return tile
end

local function BuildChoice()
    local page = Page()
    Tagline(page)
    page.head = Text(page, HEAD_SIZE, T.fg, WIDTH - INSET * 2, "CENTER")
    page.head:SetPoint("TOP", page.sign, "BOTTOM", 0, -WELCOME_LAYOUT.signGap)
    page.text = Text(page, BODY_SIZE, T.muted, WELCOME_LAYOUT.thanksW, "CENTER")
    page.text:SetPoint("TOP", page.head, "BOTTOM", 0, -WELCOME_LAYOUT.thanksGap)
    page.tiles = {}
    page.same = ChoiceTile(page, 1, CHOICE.sameArt, UseMain)
    page.own = ChoiceTile(page, 2, CHOICE.ownArt, SetUpOwn)
    Corners(page)
    return page
end

local function PaintChoice()
    local page, me, main = window.choice, newCharacter.me, newCharacter.main
    page.head:SetText(TEXT_CHOICE.head:format(me))
    page.text:SetText(TEXT_CHOICE.text:format(main, main, me))
    page.same.name:SetText(TEXT_CHOICE.sameName:format(main))
    page.same.blurb:SetText(TEXT_CHOICE.sameBlurb:format(me, main))
    page.own.name:SetText(TEXT_CHOICE.ownName:format(me))
    page.own.blurb:SetText(TEXT_CHOICE.ownBlurb:format(me))
end

local function BuildQuestion()
    local page = Page()
    page.title = Text(page, QUESTION_SIZE, T.fg, WIDTH - INSET * 2, "CENTER")
    page.hint = Text(page, BODY_SIZE, T.muted, WIDTH - INSET * 2, "CENTER")
    page.hint:SetPoint("TOP", page.title, "BOTTOM", 0, -TILE_LAYOUT.hintGap)
    page.tiles = {}
    return page
end

local function Columns(count)
    if count <= TILE_LAYOUT.maxOneRow then return count end
    return TILE_LAYOUT.wideColumns
end

local function PaintQuestion(q)
    local page = window.question
    page.title:SetText(q.title)
    page.hint:SetText(q.hint or "")
    local count = #q.answers
    local columns = Columns(count)
    local width = TileWidth(columns)
    local rows = math.ceil(count / columns)
    local tilesH = rows * TILE_H + (rows - 1) * TILE_GAP
    local headH = page.title:GetStringHeight() + TILE_LAYOUT.hintGap + page.hint:GetStringHeight() + HINT_GAP
    local pageH = HEIGHT - HEADER - FOOT_H
    local top = math.max(INSET, math.floor((pageH - headH - tilesH) / 2))
    page.title:ClearAllPoints()
    page.title:SetPoint("TOP", 0, -top)
    for i, answer in ipairs(q.answers) do
        local tile = Tile(page, i)
        local key, label, blurb = answer[1], answer[2], answer[3] or ""
        if q.id == "addons" and detected[key] then blurb = FOUND:format(detected[key]) end
        LayoutTile(tile, width)
        tile.name:SetText(label)
        tile.blurb:SetText(blurb)
        SetGlyph(tile.icon.tex, answer[4] or key)
        local row, col = math.floor((i - 1) / columns), (i - 1) % columns
        local inRow = math.min(columns, count - row * columns)
        local rowW = inRow * width + (inRow - 1) * TILE_GAP
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", page, "TOPLEFT", (WIDTH - rowW) / 2 + col * (width + TILE_GAP),
            -(top + headH + row * (TILE_H + TILE_GAP)))
        PaintTile(tile, Selected(q, key))
        tile.onPick = function() Choose(q, answer) end
        tile:Show()
    end
    for i = count + 1, #page.tiles do page.tiles[i]:Hide() end
end

local function Status(e)
    if not Setup.Differs(e) then return e.on and STAYS_ON or STAYS_OFF, nil end
    if e.on then return TURNS_ON, T.accent end
    return TURNS_OFF, RED
end

local function SetAll(on)
    for _, e in ipairs(entries) do
        if e.theme == section then Setup.Toggle(entries, e.id, on) end
    end
    Paint()
end

local function SideEnter(item)
    if item.key ~= section then item.lit:Show(); item.lit:SetAlpha(HOVER / LIT) end
end

local function SideLeave(item)
    if item.key ~= section then item.lit:Hide() end
end

local function SideClick(item)
    section = item.key
    window.review.scroll:SetVerticalScroll(0)
    Paint()
    FadeIn(window.review.pane)
end

local function SideItem(page, i)
    local item = page.side.items[i]
    if item then return item end
    item = CreateFrame("Button", nil, page.side)
    item:SetSize(SIDE_LAYOUT.w - SIDE_LAYOUT.pad * 2, SIDE_LAYOUT.h)
    item:SetPoint("TOPLEFT", SIDE_LAYOUT.pad, -SIDE_LAYOUT.pad - (i - 1) * (SIDE_LAYOUT.h + SIDE_LAYOUT.rowGap))
    item.lit = ns.Solid(item, "BACKGROUND", T.accent, LIT)
    item.lit:SetAllPoints()
    item.bar = ns.Solid(item, "ARTWORK", T.accent, 1)
    item.bar:SetPoint("TOPLEFT")
    item.bar:SetPoint("BOTTOMLEFT")
    item.bar:SetWidth(SIDE_LAYOUT.barW)
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetSize(SIDE_LAYOUT.icon, SIDE_LAYOUT.icon)
    item.icon:SetPoint("LEFT", SIDE_LAYOUT.iconX, 0)
    item.name = ns.Font(item, BODY_SIZE, nil, T.fg)
    item.name:SetPoint("LEFT", item.icon, "RIGHT", SIDE_LAYOUT.textGap, 0)
    item.name:SetJustifyH("LEFT")
    item.name:SetWordWrap(false)
    item.name:SetWidth(SIDE_LAYOUT.w - SIDE_LAYOUT.pad * 2 - SIDE_LAYOUT.icon - SIDE_LAYOUT.countW - SIDE_LAYOUT.nameRoom)
    item.count = ns.Font(item, SMALL_SIZE, nil, T.muted)
    item.count:SetPoint("RIGHT", -SIDE_LAYOUT.right, 0)
    item.dot = ns.Solid(item, "ARTWORK", T.accent, 1)
    item.dot:SetSize(SIDE_LAYOUT.dot, SIDE_LAYOUT.dot)
    item.dot:SetPoint("RIGHT", item.count, "LEFT", -SIDE_LAYOUT.dotGap, 0)
    item.pill = Parts.Pill(item, PILL_SIZE, T.accent)
    item.pill:SetPoint("RIGHT", -SIDE_LAYOUT.right, 0)
    item:SetScript("OnEnter", SideEnter)
    item:SetScript("OnLeave", SideLeave)
    item:SetScript("OnClick", SideClick)
    page.side.items[i] = item
    return item
end

local function SetRow(row, on)
    if not row.entry then return end
    Setup.Toggle(entries, row.entry.id, on)
    Paint()
    Glow(row)
end

local function RowEnter(row)
    SetLit(row, false, true)
end

local function RowLeave(row)
    SetLit(row, false, false)
end

local function RowClick(row)
    if row.entry then SetRow(row, not row.entry.on) end
end

local function Row(page, i)
    local row = page.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, page.list)
    row:SetHeight(REVIEW_LAYOUT.rowH)
    ns.Solid(row, "BACKGROUND", T.panel, PANEL_ALPHA):SetAllPoints()
    row.lit = ns.Solid(row, "BORDER", T.accent, LIT)
    row.lit:SetAllPoints()
    row.edge = ns.Border(row, BLACK)
    SetLit(row, false, false)
    row.stripe = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(REVIEW_LAYOUT.stripe)
    row.toggle = UI.BuildToggleControl(row, nil, function() return row.entry ~= nil and row.entry.on end,
        function(on) SetRow(row, on) end, REVIEW_LAYOUT.toggleW, REVIEW_LAYOUT.toggleH)
    row.toggle:SetPoint("LEFT", REVIEW_LAYOUT.rowPad + REVIEW_LAYOUT.stripe, 0)
    row.name = ns.Font(row, BODY_SIZE, nil, T.fg)
    row.name:SetPoint("TOPLEFT", row.toggle, "TOPRIGHT", REVIEW_LAYOUT.nameGap, REVIEW_LAYOUT.nameRise)
    row.yours = Parts.Pill(row, REVIEW_LAYOUT.yoursSize, GOLD)
    row.yours:SetPoint("LEFT", row.name, "RIGHT", REVIEW_LAYOUT.yoursGap, 0)
    Parts.SetPill(row.yours, YOURS_TAG)
    row.why = ns.Font(row, SMALL_SIZE, nil, T.muted)
    row.why:SetJustifyH("LEFT")
    row.why:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -REVIEW_LAYOUT.whyGap)
    row.why:SetPoint("RIGHT", row, "RIGHT", -REVIEW_LAYOUT.whyRoom, 0)
    row.status = Parts.Pill(row, PILL_SIZE, T.muted)
    row.status:SetPoint("RIGHT", -REVIEW_LAYOUT.rowPad, 0)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", RowClick)
    page.rows[i] = row
    return row
end

local function Stat(page, i, color)
    local stat = Panel(page.side)
    local width = (SIDE_LAYOUT.w - SIDE_LAYOUT.pad * 2 - REVIEW_LAYOUT.statGap * (#STATS - 1)) / #STATS
    stat:SetSize(width, REVIEW_LAYOUT.statH)
    stat:SetPoint("BOTTOMLEFT", SIDE_LAYOUT.pad + (i - 1) * (width + REVIEW_LAYOUT.statGap), SIDE_LAYOUT.pad)
    stat.value = ns.Font(stat, REVIEW_LAYOUT.statSize, nil, color)
    stat.value:SetPoint("TOP", 0, -REVIEW_LAYOUT.statTop)
    stat.label = ns.Font(stat, SMALL_SIZE, nil, T.muted)
    stat.label:SetPoint("TOP", stat.value, "BOTTOM", 0, -REVIEW_LAYOUT.statLabelGap)
    stat.label:SetText(STATS[i])
    return stat
end

local function BuildReview()
    local page = Page()
    page.side = CreateFrame("Frame", nil, page)
    page.side:SetPoint("TOPLEFT")
    page.side:SetPoint("BOTTOMLEFT")
    page.side:SetWidth(SIDE_LAYOUT.w)
    ns.Solid(page.side, "BACKGROUND", T.bg, SIDE_ALPHA):SetAllPoints()
    local edge = ns.Solid(page.side, "ARTWORK", T.line, 1)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    ns.Hairline(edge, "v")
    page.side.items = {}
    page.stats = { Stat(page, 1, T.accent), Stat(page, 2, RED), Stat(page, 3, T.fg) }
    page.pane = CreateFrame("Frame", nil, page)
    page.pane:SetPoint("TOPLEFT", page.side, "TOPRIGHT", PANE_PAD, -PANE_PAD)
    page.pane:SetPoint("BOTTOMRIGHT", -PANE_PAD, PANE_PAD)
    local paneW = WIDTH - SIDE_LAYOUT.w - PANE_PAD * 2
    local listW = paneW - SCROLL_W - SCROLL_GAP * 2
    page.head = Text(page.pane, HEAD_SIZE, T.fg, paneW - ALL_W * 2 - REVIEW_LAYOUT.headRoom)
    page.head:SetPoint("TOPLEFT")
    page.sub = Text(page.pane, SMALL_SIZE, T.muted, paneW - ALL_W * 2 - REVIEW_LAYOUT.headRoom)
    page.sub:SetPoint("TOPLEFT", page.head, "BOTTOMLEFT", 0, -REVIEW_LAYOUT.subGap)
    page.allOff = ns.Button(page.pane, TEXT_ALL_OFF, ALL_W, REVIEW_LAYOUT.allH, function() SetAll(false) end)
    page.allOff:SetPoint("TOPRIGHT")
    page.allOn = ns.Button(page.pane, TEXT_ALL_ON, ALL_W, REVIEW_LAYOUT.allH, function() SetAll(true) end)
    page.allOn:SetPoint("RIGHT", page.allOff, "LEFT", -REVIEW_LAYOUT.allGap, 0)
    page.scroll = UI.SlimScroll(page.pane, SCROLL_W, SCROLL_GAP)
    page.scroll:SetPoint("TOPLEFT", 0, -LIST_TOP)
    page.scroll:SetPoint("BOTTOMRIGHT", -(SCROLL_W + SCROLL_GAP * 2), 0)
    page.list = CreateFrame("Frame", nil, page.scroll)
    page.list:SetSize(listW, 1)
    page.scroll:SetScrollChild(page.list)
    page.emptyIcon = page.pane:CreateTexture(nil, "ARTWORK")
    page.emptyIcon:SetSize(EMPTY_ICON, EMPTY_ICON)
    page.emptyIcon:SetPoint("TOP", 0, -LIST_TOP - REVIEW_LAYOUT.emptyDrop)
    SetGlyph(page.emptyIcon, CHANGES_ICON)
    Tint(page.emptyIcon, T.muted)
    page.empty = Text(page.pane, BODY_SIZE, T.muted, listW - REVIEW_LAYOUT.emptyRoom, "CENTER")
    page.empty:SetPoint("TOP", page.emptyIcon, "BOTTOM", 0, -REVIEW_LAYOUT.emptyTextGap)
    page.empty:SetText(NO_CHANGES)
    page.rows, page.groups = {}, {}
    return page
end

local function Sections()
    local list, byTheme = { { key = CHANGES, name = CHANGES_NAME, on = 0, total = 0, icon = CHANGES_ICON } }, {}
    for _, e in ipairs(entries) do
        local s = byTheme[e.theme]
        if not s then
            s = { key = e.theme, name = e.theme, on = 0, total = 0, changes = 0, icon = Setup.THEME_ICONS[e.theme] }
            byTheme[e.theme] = s
            list[#list + 1] = s
        end
        if IsChange(e) then
            list[1].total = list[1].total + 1
            s.changes = s.changes + 1
        end
        s.total = s.total + 1
        if e.on then s.on = s.on + 1 end
    end
    return list
end

local function PaintSide(page, list)
    for i, s in ipairs(list) do
        local item = SideItem(page, i)
        item.key = s.key
        local picked = s.key == section
        item.lit:SetShown(picked)
        item.lit:SetAlpha(1)
        item.bar:SetShown(picked)
        local c = picked and T.accent or T.fg
        item.name:SetText(s.name)
        item.name:SetTextColor(c.r, c.g, c.b)
        local changes = s.key == CHANGES
        SetGlyph(item.icon, s.icon)
        Tint(item.icon, picked and T.accent or T.muted)
        item.pill:SetShown(changes)
        item.count:SetShown(not changes)
        item.dot:SetShown(not changes and s.changes > 0)
        if changes then
            Parts.SetPill(item.pill, tostring(s.total))
        else
            item.count:SetText(SIDE_COUNT:format(s.on, s.total))
        end
        item:Show()
    end
    for i = #list + 1, #page.side.items do page.side.items[i]:Hide() end
end

local function GroupHead(page, i)
    local head = page.groups[i]
    if head then return head end
    head = CreateFrame("Frame", nil, page.list)
    head:SetHeight(REVIEW_LAYOUT.groupH)
    head.icon = head:CreateTexture(nil, "ARTWORK")
    head.icon:SetSize(REVIEW_LAYOUT.groupIcon, REVIEW_LAYOUT.groupIcon)
    head.icon:SetPoint("BOTTOMLEFT", REVIEW_LAYOUT.groupIconX, REVIEW_LAYOUT.groupIconY)
    head.name = ns.Font(head, BODY_SIZE, nil, T.fg)
    head.name:SetPoint("LEFT", head.icon, "RIGHT", REVIEW_LAYOUT.groupTextGap, 0)
    head.rule = Rule(head)
    head.rule:SetPoint("BOTTOMLEFT")
    head.rule:SetPoint("BOTTOMRIGHT")
    page.groups[i] = head
    return head
end

local function PaintRow(row, e)
    row.name:SetText(e.name)
    row.yours:SetShown(e.mine)
    row.why:SetText(e.mine and YOURS:format(e.suggest and TEXT_ON or TEXT_OFF) or e.why)
    local tag, color = Status(e)
    local stripe = color or e.mine and GOLD
    row.stripe:SetShown(stripe ~= nil)
    if stripe then row.stripe:SetColorTexture(stripe.r, stripe.g, stripe.b, 1) end
    Parts.ColorPill(row.status, color or T.muted)
    Parts.SetPill(row.status, tag)
    row.toggle._refreshValue()
end

local function PaintRows(page)
    local width = page.list:GetWidth()
    local y, count, heads, last = 0, 0, 0, nil
    for _, e in ipairs(entries) do
        if (section == CHANGES and IsChange(e)) or e.theme == section then
            if section == CHANGES and e.theme ~= last then
                heads = heads + 1
                if heads > 1 then y = y + REVIEW_LAYOUT.groupGap end
                local head = GroupHead(page, heads)
                head:ClearAllPoints()
                head:SetPoint("TOPLEFT", 0, -y)
                head:SetWidth(width)
                head.name:SetText(e.theme or "")
                SetGlyph(head.icon, Setup.THEME_ICONS[e.theme] or CHANGES_ICON)
                Tint(head.icon, T.accent)
                head:Show()
                y = y + REVIEW_LAYOUT.groupH + REVIEW_LAYOUT.rowGap
                last = e.theme
            end
            count = count + 1
            local row = Row(page, count)
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetWidth(width)
            PaintRow(row, e)
            row:Show()
            y = y + REVIEW_LAYOUT.rowH + REVIEW_LAYOUT.rowGap
        end
    end
    for i = count + 1, #page.rows do page.rows[i]:Hide() end
    for i = heads + 1, #page.groups do page.groups[i]:Hide() end
    page.list:SetHeight(math.max(1, y))
    page.empty:SetShown(count == 0)
    page.emptyIcon:SetShown(count == 0)
end

local function PaintStats(page)
    local on, off, stay = Setup.Counts(entries)
    for i, value in ipairs({ on, off, stay }) do
        local stat = page.stats[i]
        if stat.shown ~= value then
            if stat.shown then Pop(stat.value) end
            stat.shown = value
            stat.value:SetText(tostring(value))
        end
    end
end

local function PaintReview()
    local page = window.review
    local list = Sections()
    local current
    for _, s in ipairs(list) do
        if s.key == section then current = s end
    end
    if not current then section, current = CHANGES, list[1] end
    PaintSide(page, list)
    local theme = section ~= CHANGES
    page.head:SetText(current.name)
    page.sub:SetText(theme and THEME_SUB:format(current.on, current.total) or CHANGES_SUB)
    page.allOn:SetShown(theme)
    page.allOff:SetShown(theme)
    PaintRows(page)
    PaintStats(page)
end

local function PaintSegments()
    local count = #Setup.QUESTIONS
    for i, seg in ipairs(window.segments) do
        local c = i < step and T.accent or i == step and T.accentSoft or T.line
        seg:SetColorTexture(c.r, c.g, c.b, 1)
        seg:SetShown(step >= 1 and step <= count)
    end
end

function Paint()
    local count = #Setup.QUESTIONS
    local choosing, welcome, reviewing = step == CHOICE.step, step == 0, step > count
    local asking = not (choosing or welcome or reviewing)
    if step ~= window.painted then
        window.painted = step
        FadeIn(choosing and window.choice or welcome and window.welcome or reviewing and window.review
            or window.question)
    end
    window.choice:SetShown(choosing)
    window.welcome:SetShown(welcome)
    window.question:SetShown(asking)
    window.review:SetShown(reviewing)
    window.foot:SetShown(asking or reviewing)
    PaintSegments()
    window.next.arrow:SetTexture(reviewing and CHECK_ART or NEXT_ART, nil, nil, FILTER)
    window.again:SetShown(reviewing)
    window.skip:SetShown(asking)
    if choosing then
        window.subtitle:SetText(WELCOME_SUB)
        PaintChoice()
    elseif welcome then
        window.subtitle:SetText(forCharacter and WELCOME_FOR:format(forCharacter) or WELCOME_SUB)
    elseif reviewing then
        window.subtitle:SetText(REVIEW_SUB)
        PaintReview()
        local combat = InCombatLockdown()
        ns.SetButtonText(window.next, Setup.NeedsReload(entries) and TEXT_APPLY_RELOAD or TEXT_APPLY)
        window.next:SetAlpha(combat and DIM_ALPHA or 1)
        window.note:SetText(combat and IN_COMBAT or "")
    else
        local q = Question()
        window.subtitle:SetText(QUESTION_OF:format(step, count))
        PaintQuestion(q)
        ns.SetButtonText(window.next, (step == count or Setup.Skips(answers)) and TEXT_SEE_SETUP or TEXT_NEXT)
        local ready = Ready(q)
        window.next:SetAlpha(ready and 1 or DIM_ALPHA)
        window.note:SetText(q.one and "" or ready and PICKED:format(PickedCount(q)) or PICK_ONE)
    end
end

local function Changed()
    local on, off = Setup.Counts(entries)
    return on + off > 0
end

local function Apply()
    if InCombatLockdown() then return Paint() end
    if not Changed() then return window:Hide() end
    local reload = Setup.Apply(entries)
    window:Hide()
    if reload then
        ns.ConfirmReload(DONE_RELOAD)
    else
        ns.Print(DONE)
    end
end

local function Next()
    local count = #Setup.QUESTIONS
    if step > count then return Apply() end
    if not Ready(Question()) then return end
    step = Setup.Skips(answers) and count + 1 or step + 1
    if step > count then
        entries = Setup.Plan(answers, Setup.Context())
        section = CHANGES
    end
    Paint()
end

local function Back()
    step = (step > #Setup.QUESTIONS and Setup.Skips(answers)) and 1 or step - 1
    Paint()
end

local function Skip()
    ResetQuestion(Question())
    local count = #Setup.QUESTIONS
    step = step + 1
    if step > count then
        entries = Setup.Plan(answers, Setup.Context())
        section = CHANGES
    end
    Paint()
end

local function StartOver()
    answers, detected = Fresh()
    step = 1
    Paint()
end

local function OnCombat()
    if window:IsShown() and step > #Setup.QUESTIONS then Paint() end
end

local function BuildFoot()
    local foot = CreateFrame("Frame", nil, window)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(FOOT_H)
    local rule = Rule(foot)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    window.back = Arrow(ns.Button(foot, TEXT_BACK, NAV_W, BUTTON_H, Back), BACK_ART)
    window.back:SetPoint("BOTTOMLEFT", EDGE, EDGE)
    window.skip = Parts.Link(foot, Skip)
    Parts.SetLink(window.skip, SKIP)
    window.skip:SetPoint("BOTTOM", 0, EDGE + FOOT_LAYOUT.skipLift)
    window.again = ns.Button(foot, TEXT_START_OVER, NAV_W, BUTTON_H, StartOver)
    window.again:SetPoint("BOTTOM", 0, EDGE)
    window.next = Arrow(ns.AccentBorder(ns.Button(foot, TEXT_NEXT, APPLY_W, BUTTON_H, Next)), NEXT_ART, true)
    window.next:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    window.note = ns.Font(foot, SMALL_SIZE, nil, T.muted)
    window.note:SetPoint("RIGHT", window.next, "LEFT", -FOOT_LAYOUT.noteGap, 0)
    window.foot = foot
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, POSITION_KEY)
    window.backdrop:Paint(1)
    Parts.TitleBar(window, TITLE, "")
    window.logo:EnableMouse(false)
    window.logo.icon:SetAlpha(1)
    window.segments = {}
    for i = #Setup.QUESTIONS, 1, -1 do
        local seg = window:CreateTexture(nil, "ARTWORK")
        seg:SetSize(SEG.w, SEG.h)
        local right = SEG.right + (#Setup.QUESTIONS - i) * (SEG.w + SEG.gap)
        seg:SetPoint("RIGHT", window, "TOPRIGHT", -right, -HEADER / 2)
        window.segments[i] = seg
    end
    window.choice = BuildChoice()
    window.welcome = BuildWelcome()
    window.question = BuildQuestion()
    window.review = BuildReview()
    BuildFoot()
    window.events = CreateFrame("Frame")
    window.events:SetScript("OnEvent", OnCombat)
    window:HookScript("OnShow", function()
        window.events:RegisterEvent("PLAYER_REGEN_DISABLED")
        window.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end)
    window:HookScript("OnHide", Hidden)
end

local function Open(thisCharacter, first)
    ns.StashOptionsWindow()
    Setup.ForCharacter(thisCharacter)
    forCharacter = thisCharacter and UnitName("player") or nil
    if not window then Build() end
    window.painted = nil
    answers, detected = Fresh()
    step = first
    Paint()
    window:Show()
end

function ns.ShowSetup(thisCharacter)
    Open(thisCharacter, 0)
end

function ns.ShowNewCharacter(me, main, profile)
    newCharacter.me, newCharacter.main, newCharacter.profile = me, main, profile
    Open(nil, CHOICE.step)
end
