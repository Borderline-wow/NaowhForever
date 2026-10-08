-------------------------------------------------------------------------------
--  Parts.lua -- the components a page is made of (ns.Shared.Parts): the chevron, text links,
--  icon buttons, icons inline in text, rank stars, an item's icon and its marks, the backdrop with its
--  cards, the panel a view sits in and the side panel that opens beside a window, numbers
--  lined up to the pixel, and sharing a line in chat. A window's own pieces (title bar,
--  opacity, switch, search, footer) are Window.lua's. Also a timer line the client runs down by
--  itself (Parts.TimerLine), a row of short labels spread evenly (Parts.LabelRow), and a HUD
--  card's background: the card, a soft fade or none (Parts.HudBackdrop).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Parts = Shared.Parts

local St = Shared.Style
local ARROW, PLACE_DOT, ACTION, STAR = St.ARROW, St.PLACE_DOT, St.ACTION, St.STAR
local PANEL_W, PANEL_PAD, BORDER_RGB = St.PANEL_W, St.PANEL_PAD, St.BORDER_RGB
local PANEL_HEADER, PANEL_BUTTONS = St.PANEL_HEADER, St.PANEL_BUTTONS
local CARD_FILL, CARD_EDGE = St.WINDOW_CARD_FILL, St.WINDOW_CARD_EDGE
-- Forever's mark on an icon's corner: this share of the icon tall, never under FOREVER_MIN.
local FOREVER_MIN, FOREVER_SHARE = 7, 0.32
-- An item's marks on a slot (Parts.ItemMarks): the item level and the star this big, outlined,
-- this far in from the icon's edge, over a shade this share of the icon tall and this dark at
-- its foot, so the numbers read on any icon's art.
local MARK_SIZE, MARK_IN = 13, 2
local SHADE_SHARE, SHADE_ALPHA = 0.5, 0.8
-- The star 1px over the line's middle (a negative drop raises it), level with the item level's
-- outlined digits across the icon; 2px left it high beside a two-digit level (7 Oct 2026).
local MARK_STAR_DROP = -1
Parts.MARK_IN = MARK_IN
local MARK_UP = 14   -- the upgrade arrow, square, in the top-right corner
local BADGE_SIZE, BADGE_ART, BADGE_ALPHA, BADGE_IN = 14, 12, 0.75, 1

-------------------------------------------------------------------------------
--  Icons in text
-------------------------------------------------------------------------------
-- How much lower an icon in text sits, level with the letters: a tooltip's lines need 1; on a
-- card the Naowh font's capitals fill the middle of the line (measured in game, 2 Oct 2026).
Parts.TOOLTIP_DROP = 1
Parts.CARD_DROP = 0

---@param color { r: number, g: number, b: number }
function Parts.Inline(texture, color, drop)
    return ("|T%s:0:0:0:%d:64:64:0:64:0:64:%d:%d:%d|t"):format(texture, -(drop or Parts.TOOLTIP_DROP),
        color.r * 255, color.g * 255, color.b * 255)
end
local Inline = Parts.Inline

local HUD_SHADOW, HUD_ALPHA = St.HUD_SHADOW_RGB, St.HUD_SHADOW_ALPHA
local HUD_X, HUD_Y = St.HUD_SHADOW_X, St.HUD_SHADOW_Y

local HOUSE_SHADOW = { x = HUD_X, y = HUD_Y, a = HUD_ALPHA }
local SHADOWS = {
    card = HOUSE_SHADOW,
    soft = { x = HUD_X, y = HUD_Y, a = St.HUD_SOFT_SHADOW_ALPHA },
    none = { x = St.HUD_BARE_SHADOW_X, y = St.HUD_BARE_SHADOW_Y, a = St.HUD_BARE_SHADOW_ALPHA },
}

function Parts.HudText(fs, shadow)
    if shadow == false then
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(HUD_SHADOW.r, HUD_SHADOW.g, HUD_SHADOW.b, 0)
    else
        local s = SHADOWS[shadow] or HOUSE_SHADOW
        fs:SetShadowOffset(s.x, s.y)
        fs:SetShadowColor(HUD_SHADOW.r, HUD_SHADOW.g, HUD_SHADOW.b, s.a)
    end
    return fs
end

Parts.HUD_OUTLINES = { { NONE = "None", [""] = "Shadow", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" },
    { "NONE", "", "OUTLINE", "THICKOUTLINE" } }

-- font is a SharedMedia name ("" for the Addon Font); outline one of HUD_OUTLINES. Shadow ("")
-- gets the HUD shadow for background (a Parts.HudBackdrop mode, or nil for the card's).
function Parts.HudFont(fs, font, size, outline, background)
    fs:SetFont(ns.UI.FontPath(font), size, outline == "NONE" and "" or outline)
    return Parts.HudText(fs, outline == "" and (background or "card") or false)
end

Parts.HUD_BACKGROUNDS = { { card = "Card", soft = "Soft", none = "None" }, { "card", "soft", "none" } }
local BACKGROUND_NAMES, NO_OPTS = Parts.HUD_BACKGROUNDS[1], {}
local SOFT_CORNERS = {   -- point, its x and y outwards, then the round texture's quarter: left, right, top, bottom
    { "TOPLEFT", -1, 1, 0, 0.5, 0, 0.5 },
    { "TOPRIGHT", 1, 1, 0.5, 1, 0, 0.5 },
    { "BOTTOMLEFT", -1, -1, 0, 0.5, 0.5, 1 },
    { "BOTTOMRIGHT", 1, -1, 0.5, 1, 0.5, 1 },
}
local SOFT_SPANS = {     -- from a corner's point to another's, over the texture's middle row, column or texel
    { 1, "TOPRIGHT", 2, "BOTTOMLEFT", 0.5, 0.5, 0, 0.5 },
    { 3, "TOPRIGHT", 4, "BOTTOMLEFT", 0.5, 0.5, 0.5, 1 },
    { 1, "BOTTOMLEFT", 3, "TOPRIGHT", 0, 0.5, 0.5, 0.5 },
    { 2, "BOTTOMLEFT", 4, "TOPRIGHT", 0.5, 1, 0.5, 0.5 },
    { 1, "BOTTOMRIGHT", 4, "TOPLEFT", 0.5, 0.5, 0.5, 0.5 },
}

local SOFT_SIDES = 4      -- the spans along the four sides; the last one is the middle

local function SoftPiece(pieces, frame, color, alpha, l, r, t, b)
    local tex = Parts.Smooth(frame:CreateTexture(nil, "BACKGROUND"), St.SOFT_SHADE)
    tex:SetTexCoord(l, r, t, b)
    tex:SetVertexColor(color.r, color.g, color.b, alpha)
    pieces[#pieces + 1] = tex
    return tex
end

-- The soft fade on frame: color at alpha, clear `fade` out, its corners `out` past the frame's.
-- Hollow leaves the middle out, for a shadow round the frame that covers nothing of it.
local function SoftPieces(frame, color, alpha, fade, out, hollow)
    local pieces = {}
    for i = 1, #SOFT_CORNERS do
        local c = SOFT_CORNERS[i]
        local tex = SoftPiece(pieces, frame, color, alpha, c[4], c[5], c[6], c[7])
        tex:SetSize(fade, fade)
        tex:SetPoint(c[1], frame, c[1], c[2] * out, c[3] * out)
    end
    for i = 1, hollow and SOFT_SIDES or #SOFT_SPANS do
        local s = SOFT_SPANS[i]
        local tex = SoftPiece(pieces, frame, color, alpha, s[5], s[6], s[7], s[8])
        tex:SetPoint("TOPLEFT", pieces[s[1]], s[2])
        tex:SetPoint("BOTTOMRIGHT", pieces[s[3]], s[4])
    end
    return pieces
end

local function BuildSoft(backdrop)
    backdrop.soft = SoftPieces(backdrop.frame, backdrop.color, backdrop.softAlpha, backdrop.fade,
        backdrop.fade - backdrop.inset)
end

local function BackdropMode(backdrop, mode)
    if not BACKGROUND_NAMES[mode] then mode = "card" end
    if backdrop.mode == mode then return mode end
    backdrop.mode = mode
    local card, soft = mode == "card", mode == "soft"
    backdrop.fill:SetShown(card)
    backdrop.border._frame:SetShown(card)
    if soft and not backdrop.soft then BuildSoft(backdrop) end
    local pieces = backdrop.soft
    if pieces then
        for i = 1, #pieces do pieces[i]:SetShown(soft) end
    end
    return mode
end

function Parts.HudBackdrop(frame, opts)
    opts = opts or NO_OPTS
    local color = opts.color or T.bg
    local backdrop = { frame = frame, color = color, SetMode = BackdropMode,
        softAlpha = opts.softAlpha or St.HUD_SOFT_ALPHA, fade = opts.fade or St.HUD_SOFT_FADE,
        inset = opts.inset or St.HUD_SOFT_INSET }
    backdrop.fill = ns.Solid(frame, "BACKGROUND", color, opts.alpha or St.HUD_CARD_ALPHA)
    backdrop.fill:SetAllPoints()
    backdrop.border = ns.Border(frame, BORDER_RGB)
    BackdropMode(backdrop, opts.mode)
    return backdrop
end

-- A soft drop shadow round a window, outside it only: the soft fade in black, from alpha
-- (St.SHADOW_ALPHA) at the window's edge to clear `size` (St.SHADOW_SIZE) out.
function Parts.Shadow(frame, size, alpha)
    size = size or St.SHADOW_SIZE
    return SoftPieces(frame, BORDER_RGB, alpha or St.SHADOW_ALPHA, size, size, true)
end

local PROGRESS_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local PROGRESS_TRACK_ALPHA, PROGRESS_FROM_SHARE, PROGRESS_AHEAD_ALPHA = 1, 0.45, 0.45

local function ProgressBar(line)
    local bar = CreateFrame("StatusBar", nil, line)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(PROGRESS_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function ProgressSet(line, value, ahead)
    value = math.max(0, math.min(1, value))
    line.fill:SetValue(value)
    line.ahead:SetValue(math.min(1, value + math.max(0, ahead or 0)))
end

local function ProgressPaint(line, color, aheadColor)
    local share = PROGRESS_FROM_SHARE
    line.from:SetRGBA(color.r * share, color.g * share, color.b * share, 1)
    line.to:SetRGBA(color.r, color.g, color.b, 1)
    line.fill:GetStatusBarTexture():SetGradient("HORIZONTAL", line.from, line.to)
    local c = aheadColor or color
    line.ahead:SetStatusBarColor(c.r, c.g, c.b, PROGRESS_AHEAD_ALPHA)
end

function Parts.ProgressLine(parent, height)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(height)
    line.track = ns.Solid(line, "BACKGROUND", T.line, PROGRESS_TRACK_ALPHA)
    line.track:SetAllPoints()
    line.ahead = ProgressBar(line)
    line.fill = ProgressBar(line)
    line.fill:SetFrameLevel(line.ahead:GetFrameLevel() + 1)
    line.from, line.to = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    line.SetProgress, line.Paint = ProgressSet, ProgressPaint
    ProgressPaint(line, T.accent)
    return line
end

-------------------------------------------------------------------------------
--  Ranks on your BiS list: your BiS (#1) an orange star, your second pick a silver one, the
--  rest a muted number. Made once per rank and drop.
-------------------------------------------------------------------------------
local RANK_RGB = { St.BIS_RGB, St.SECOND_RGB }
local marks = {}

function Parts.RankColor(rank)
    return RANK_RGB[rank] or T.muted
end

---@param rank? number
---@param drop? number Parts.CARD_DROP on a card, else as in a tooltip
function Parts.RankMark(rank, drop)
    if not rank then return "" end
    drop = drop or Parts.TOOLTIP_DROP
    local byRank = marks[drop]
    if not byRank then
        byRank = {}
        marks[drop] = byRank
    end
    local mark = byRank[rank]
    if not mark then
        mark = RANK_RGB[rank] and Inline(STAR, RANK_RGB[rank], drop) or ns.Color("muted", "#" .. rank)
        byRank[rank] = mark
    end
    return mark
end

-------------------------------------------------------------------------------
--  The addon's lines in an item's tooltip, one fact each, one look: the mark, the words in
--  its colour, and after a dot, muted, whose it is. The BiS List's and Stat Weights' on every
--  tooltip, the Journal's and the BiS List's rows add theirs from the same makers, so the
--  same fact never reads two ways, or twice.
-------------------------------------------------------------------------------
-- "<star> Your BiS", "Your second pick", "#3 on your BiS list"; with a list's name, " . Die".
---@param listName? string
function Parts.RankLine(rank, listName)
    local words = rank == 1 and "Your BiS" or rank == 2 and "Your second pick" or ("#%d on your BiS list"):format(rank)
    local color = Parts.RankColor(rank)
    return Parts.RankMark(rank) .. " " .. ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255,
        color.b * 255, words) .. (listName and ns.Color("muted", PLACE_DOT .. listName) or "")
end

local upgradeArrow

-- "<green arrow> +18% upgrade . Combat": how much stronger it makes you, by your spec's weights.
---@param gain number percent
---@param specName? string
function Parts.UpgradeLine(gain, specName)
    upgradeArrow = upgradeArrow or ("|A:%s:0:0:0:%d|a"):format(St.UPGRADE_ATLAS, -Parts.TOOLTIP_DROP)
    return upgradeArrow .. " " .. St.UPGRADE_CODE .. "+" .. math.floor(gain + 0.5) .. "% upgrade|r"
        .. (specName and ns.Color("muted", PLACE_DOT .. specName) or "")
end

-------------------------------------------------------------------------------
--  WoW Forever's mark, on what is new in Forever (not in the original game): its infinity
--  sign, before a name or in text, and a tooltip line that says what it means.
-------------------------------------------------------------------------------
-- The sign fills its texture, 32 by 16, twice as wide as it is tall.
local FOREVER = St.FOREVER
local FOREVER_RGB = St.FOREVER_RGB
local foreverText = {}

---@param kind "items"|"quests"|"npcs"
---@return boolean new whether Wowhead's Forever database has it as new in Forever
function Parts.IsForever(kind, id)
    local new = Shared.ForeverNew
    return id ~= nil and new ~= nil and new[kind][id] == true
end

-- The mark at a height in text, after a space; made once per height and drop.
---@param height number the line's font size
---@param drop? number Parts.CARD_DROP on a card, else as in a tooltip
function Parts.ForeverInline(height, drop)
    drop = drop or Parts.TOOLTIP_DROP
    local key = height * 100 + drop
    local text = foreverText[key]
    if not text then
        text = (" |T%s:%d:%d:0:%d:32:16:0:32:0:16:%d:%d:%d|t"):format(FOREVER, height, height * 2, -drop,
            FOREVER_RGB.r * 255, FOREVER_RGB.g * 255, FOREVER_RGB.b * 255)
        foreverText[key] = text
    end
    return text
end

-- A texture drawn smaller than its file stays smooth: mipmapped ("TRILINEAR") where it is one
-- of the addon's own (pass the path), and never snapped to whole screen pixels, which makes a
-- scaled icon's edges step. A text icon (|T|t) cannot be smoothed: draw those near their size.
---@param path? string|number
function Parts.Smooth(texture, path)
    if path then texture:SetTexture(path, nil, nil, "TRILINEAR") end
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end
local Smooth = Parts.Smooth

-- The mark as a texture, height tall, for a row's own column.
function Parts.ForeverMark(parent, height)
    local mark = Smooth(parent:CreateTexture(nil, "OVERLAY"), FOREVER)
    mark:SetVertexColor(FOREVER_RGB.r, FOREVER_RGB.g, FOREVER_RGB.b)
    mark:SetSize(height * 2, height)
    return mark
end

local foreverLine

-- "<sign> New in WoW Forever", for a tooltip.
function Parts.ForeverLine()
    if not foreverLine then
        foreverLine = Parts.ForeverInline(12):sub(2) .. " " .. St.FOREVER_CODE .. "New in WoW Forever|r"
    end
    return foreverLine
end

-- "3/10", made once each, so a count redrawn makes no garbage.
local fractions = {}

function Parts.Fraction(part, whole)
    local byWhole = fractions[whole]
    if not byWhole then
        byWhole = {}
        fractions[whole] = byWhole
    end
    local text = byWhole[part]
    if not text then
        text = part .. "/" .. whole
        byWhole[part] = text
    end
    return text
end

local coins, coinsKept = {}, 0
local COINS_KEPT = 500
local GOLD, SILVER = 10000, 100   -- copper in a gold coin, in a silver one

-- The amount with the game's coin icons ("1g 50s 25c"), made once each. With compact, only its
-- largest coin, to the nearest ("1g", "2s", "36c"), for a price under a small icon.
---@param compact? boolean
function Parts.Coins(copper, compact)
    if compact then
        local unit = copper >= GOLD and GOLD or copper >= SILVER and SILVER or 1
        copper = math.floor(copper / unit + 0.5) * unit
    end
    local text = coins[copper]
    if not text then
        if coinsKept >= COINS_KEPT then
            wipe(coins)
            coinsKept = 0
        end
        text = C_CurrencyInfo.GetCoinTextureString(copper)
        coins[copper] = text
        coinsKept = coinsKept + 1
    end
    return text
end

-------------------------------------------------------------------------------
--  Pieces
-------------------------------------------------------------------------------
-- The addon's chevron, pointing right.
function Parts.Arrow(parent, size, color)
    local arrow = parent:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    arrow:SetSize(size, size)
    arrow:SetVertexColor(color.r, color.g, color.b)
    return arrow
end
local Arrow = Parts.Arrow

-- WoW Forever's mark in an icon's top-left corner, just inside its edge: no box, its own dark
-- outline keeps it readable on the icon's art. Hidden until shown.
local function IconForever(over, size)
    local h = math.max(FOREVER_MIN, math.floor(size * FOREVER_SHARE))
    local sign = Smooth(over:CreateTexture(nil, "OVERLAY"), St.FOREVER_ICON)
    sign:SetVertexColor(FOREVER_RGB.r, FOREVER_RGB.g, FOREVER_RGB.b)
    sign:SetSize(h * 2, h)
    sign:SetPoint("TOPLEFT", 1, -1)
    sign:Hide()
    return sign
end

-- icon.texture is what to set.
function Parts.ItemIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame.edge = ns.Border(frame, BORDER_RGB)
    frame.texture = Smooth(frame:CreateTexture(nil, "ARTWORK"))
    ns.PixelInset(frame.texture, 1)
    frame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints()
    over:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.forever = IconForever(over, size)
    return frame
end

-- Forever's badge on an item icon, for an item new in Forever.
function Parts.MarkForever(icon, itemID)
    icon.forever:SetShown(Parts.IsForever("items", itemID))
end

-- An item's marks on a slot, the same wherever we draw one (the BiS List's paperdoll, the
-- character panel, your bags): its item level in the bottom-right, your BiS's star in the
-- bottom-left, Forever's mark in the top-left, the game's green upgrade arrow in the top-right
-- (in your bags, for gear better than what you wear), and a shade rising from the foot behind
-- the level and the star.
-- A frame over icon (an item icon of ours, whose own Forever mark it takes, or a game's button);
-- size is the icon's. Painted with Parts.PaintItemMarks.
function Parts.ItemMarks(icon, size)
    local set = CreateFrame("Frame", nil, icon)
    set:SetAllPoints()
    set:SetFrameLevel(icon:GetFrameLevel() + 4)
    local shade = set:CreateTexture(nil, "ARTWORK")
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, SHADE_ALPHA), CreateColor(0, 0, 0, 0))
    shade:SetPoint("BOTTOMLEFT", 1, 1)
    shade:SetPoint("BOTTOMRIGHT", -1, 1)
    shade:SetHeight(size * SHADE_SHARE)
    set.shade = shade
    set.level = ns.Font(set, MARK_SIZE, "OUTLINE", T.fg)
    set.level:SetPoint("BOTTOMRIGHT", -MARK_IN, MARK_IN)
    set.rank = ns.Font(set, MARK_SIZE, "OUTLINE", T.fg)
    set.rank:SetPoint("BOTTOMLEFT", MARK_IN, MARK_IN)
    set.forever = icon.forever or IconForever(set, size)
    local up = set:CreateTexture(nil, "OVERLAY")
    up:SetAtlas(St.UPGRADE_ATLAS)
    up:SetSize(MARK_UP, MARK_UP)
    up:SetPoint("TOPRIGHT", -1, -1)
    up:Hide()
    set.up = up
    return set
end

-- level: the item level (none at 1 or under); rank: your list's rank for it, for its star;
-- forever: whether it is new in Forever; upgrade: whether it is one. The shade only behind a
-- number or a star.
---@param level? number|false
---@param rank? number
---@return boolean shown whether it shows an item level
function Parts.PaintItemMarks(set, level, rank, forever, upgrade)
    local shown = level and level > 1 or false
    set.level:SetText(shown and level or "")
    set.rank:SetText(rank and Parts.RankMark(rank, MARK_STAR_DROP) or "")
    set.forever:SetShown(forever == true)
    set.up:SetShown(upgrade == true)
    set.shade:SetShown(shown or rank ~= nil)
    return shown
end

-- After the icon is resized: its shade to the new height.
function Parts.SizeItemMarks(set, size)
    set.shade:SetHeight(size * SHADE_SHARE)
end

function Parts.ItemBadge(set, corner, atlas, color)
    local badge = CreateFrame("Frame", nil, set)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint(corner, corner == "TOPLEFT" and BADGE_IN or -BADGE_IN, -BADGE_IN)
    badge.back = Smooth(badge:CreateTexture(nil, "BACKGROUND"), St.ROUND)
    badge.back:SetAllPoints()
    badge.back:SetVertexColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, BADGE_ALPHA)
    badge.art = Smooth(badge:CreateTexture(nil, "ARTWORK"))
    badge.art:SetAtlas(atlas)
    badge.art:SetSize(BADGE_ART, BADGE_ART)
    badge.art:SetPoint("CENTER")
    if color then badge.art:SetVertexColor(color.r, color.g, color.b) end
    badge:Hide()
    return badge
end

local PILL_PAD, PILL_FILL = 4, St.TAB_FILL

function Parts.Pill(parent, size, color)
    local pill = CreateFrame("Frame", nil, parent)
    pill.fill = ns.Solid(pill, "BACKGROUND", color, PILL_FILL)
    pill.fill:SetAllPoints()
    pill.edge = ns.Border(pill, color)
    pill.text = ns.Font(pill, size, nil, color)
    pill.text:SetPoint("CENTER")
    pill:SetHeight(size + PILL_PAD)
    return pill
end

function Parts.ColorPill(pill, color)
    if pill.color == color then return end
    pill.color = color
    pill.fill:SetColorTexture(color.r, color.g, color.b, PILL_FILL)
    pill.edge:SetColor(color.r, color.g, color.b)
    pill.text:SetTextColor(color.r, color.g, color.b)
end

function Parts.SetPill(pill, text)
    pill.text:SetText(text)
    pill:SetWidth(math.ceil(pill.text:GetStringWidth()) + 2 * PILL_PAD)
    return pill:GetWidth()
end

-- The tooltip's owner set, for a hover card; nothing while a menu is open, so moving the mouse
-- from a menu's owner over other rows to reach it does not cover the menu with their cards.
---@return boolean shown false while a menu is open: the caller shows nothing
function Parts.Tip(owner, anchor, x, y)
    if Menu.GetManager():IsAnyMenuOpen() then return false end
    GameTooltip:SetOwner(owner, anchor, x, y)
    return true
end
local Tip = Parts.Tip

-- What you wear, in a list's row: a green bar at its left edge, out by inset.
function Parts.WornBar(row, inset)
    local bar = ns.Solid(row, "ARTWORK", St.HAVE_RGB, 1)
    bar:SetPoint("TOPLEFT", -inset + 2, -4)
    bar:SetPoint("BOTTOMLEFT", -inset + 2, 4)
    bar:SetWidth(2)
    bar:Hide()
    return bar
end

-- An action on a page is a link, not a box, so the page reads as content; boxes are for a
-- window's controls. With arrow, a chevron after it, for one that goes somewhere else.
local function LinkColor(link, color)
    link.text:SetTextColor(color.r, color.g, color.b)
    if link.arrow then link.arrow:SetVertexColor(color.r, color.g, color.b) end
end
Parts.LinkColor = LinkColor

-- A disabled link rests muted and says why on hover.
local function LinkEnter(link)
    if link.tip then
        if not Tip(link, "ANCHOR_TOP") then return end
        GameTooltip:SetText(link.tip, 1, 1, 1)
        if link.tipLine then GameTooltip:AddLine(link.tipLine, T.muted.r, T.muted.g, T.muted.b, true) end
        GameTooltip:Show()
    end
    if link.disabled then return end
    LinkColor(link, T.fg)
    link.underline:Show()
end

local function LinkLeave(link)
    if link.tip then GameTooltip:Hide() end
    LinkColor(link, link.disabled and T.muted or T.accentSoft)
    link.underline:Hide()
end

function Parts.Link(parent, onClick, arrow)
    local link = CreateFrame("Button", nil, parent)
    link:SetHeight(18)
    link.text = ns.Font(link, 12, nil, T.accentSoft)
    if arrow then
        link.arrow = Arrow(link, 10, T.accentSoft)
        -- Out by the chevron's own margin, so its point lines up with the text above.
        link.arrow:SetPoint("RIGHT", 2, 0)
        link.text:SetPoint("RIGHT", link.arrow, "LEFT", 0, 0)
    else
        link.text:SetPoint("RIGHT")
    end
    link.underline = ns.Solid(link, "ARTWORK", T.fg, 1)
    link.underline:SetPoint("TOPLEFT", link.text, "BOTTOMLEFT", 0, -1)
    link.underline:SetPoint("TOPRIGHT", link.text, "BOTTOMRIGHT", 0, -1)
    ns.Hairline(link.underline, "h")
    link.underline:Hide()
    link:SetScript("OnClick", onClick)
    link:SetScript("OnEnter", LinkEnter)
    link:SetScript("OnLeave", LinkLeave)
    return link
end

function Parts.SetLink(link, text)
    link.text:SetText(text)
    link:SetWidth(math.ceil(link.text:GetStringWidth()) + (link.arrow and 12 or 0))
end

-- margin: the empty edge on the right of the icon's image; it moves out by it, so the shapes,
-- not their boxes, line up.
local function IconEnter(button)
    button.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    if button.label then button.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b) end
    if not Tip(button, "ANCHOR_TOP") then return end
    GameTooltip:SetText(button.tip)
    if button.hint then GameTooltip:AddLine(button.hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Show()
end

local function IconLeave(button)
    button.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    if button.label then button.label:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Hide()
end

---@param tip? string what it does, on hover (or button.tip, set later)
function Parts.IconButton(parent, onClick, texture, margin, tip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ACTION, ACTION)
    button.icon = Smooth(button:CreateTexture(nil, "ARTWORK"), texture)
    button.icon:SetSize(ACTION, ACTION)
    button.icon:SetPoint("RIGHT", margin or 0, 0)
    button.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    button.tip = tip
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", IconEnter)
    button:SetScript("OnLeave", IconLeave)
    return button
end

-- The copy card the tooltips' Ctrl-Shift-C opens, its Wowhead link selected: the game cannot
-- put text on the clipboard for an addon. kind is Wowhead's: "item", "spell", "quest", "npc"
-- or "object".
local ID_LABELS = { item = "Item ID", spell = "Spell ID", quest = "Quest ID", npc = "NPC ID", object = "Object ID" }

function Parts.CopyWowhead(kind, id, name)
    ns.ShowCopyCard(kind, ID_LABELS[kind] or "ID", id, name, "url")
end

-- A where line without its colour codes (they pull the eye off the titles), dashes between
-- place and person ("Ratchet - Crane Operator") as dots. Made once each.
local plain = {}

function Parts.Plain(text)
    local out = plain[text]
    if not out then
        out = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%-%s+", PLACE_DOT)
        plain[text] = out
    end
    return out
end

-------------------------------------------------------------------------------
--  The backdrop of a window and its panels: a gradient from the theme's panel colour down
--  toward its backdrop, with lighter cards in black edges. Opacity is painted into the
--  colours, not set with SetAlpha: a texture's alpha does not reach a gradient's colours.
-------------------------------------------------------------------------------
local Backdrop = {}
Backdrop.__index = Backdrop

local EDGES = {
    { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
    { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true },
}

function Backdrop:Keep(texture, color, alpha)
    texture.color, texture.alpha = color, alpha
    self.flat[#self.flat + 1] = texture
    return texture
end

-- Insets from each side. Returns its textures, the fill first: the edges follow it, so moving
-- the fill moves the card.
function Backdrop:Card(left, top, right, bottom)
    local frame = self.frame
    local fill = self:Keep(frame:CreateTexture(nil, "BACKGROUND", nil, -6), T.fg, CARD_FILL)
    fill:SetPoint("TOPLEFT", left, -top)
    fill:SetPoint("BOTTOMRIGHT", -right, bottom)
    local parts = { fill }
    for _, edge in ipairs(EDGES) do
        local line = self:Keep(frame:CreateTexture(nil, "BORDER"), BORDER_RGB, CARD_EDGE)
        line:SetPoint(edge[1], fill)
        line:SetPoint(edge[2], fill)
        ns.Hairline(line, edge[3] and "v" or "h")
        parts[#parts + 1] = line
    end
    return parts
end

---@param alpha number 0 to 1
function Backdrop:Paint(alpha)
    local top, bg = T.panel, T.bg
    self.bottom:SetRGBA((top.r + bg.r) / 2, (top.g + bg.g) / 2, (top.b + bg.b) / 2, alpha)
    self.top:SetRGBA(top.r, top.g, top.b, alpha)
    self.gradient:SetGradient("VERTICAL", self.bottom, self.top)
    local flat = self.flat
    for i = 1, #flat do
        local texture = flat[i]
        local c = texture.color
        texture:SetColorTexture(c.r, c.g, c.b, texture.alpha * alpha)
    end
end

function Parts.Backdrop(frame)
    local backdrop = setmetatable({ frame = frame, flat = {} }, Backdrop)
    backdrop.gradient = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop.gradient:SetAllPoints()
    backdrop.gradient:SetColorTexture(1, 1, 1, 1)
    backdrop.bottom, backdrop.top = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1)
    return backdrop
end

-------------------------------------------------------------------------------
--  Sharing a line in chat, or in a box to copy. Never through the chat box: opening it from
--  addon code taints it, and the game then blocks the next message you send.
-------------------------------------------------------------------------------
-- A dungeon finder group's chat is the instance's.
local function PartyChat()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return "PARTY"
end
Parts.PartyChat = PartyChat

-- The Trade channel's number while you are in it (in a city), else nil.
local function TradeChannel()
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local name = list[i + 1]
        if type(name) == "string" and name:find("^Trade") then return list[i] end
    end
end

-- message, or a function making it when sent (a map pin link is made then). With trade,
-- Trade chat first: for asking the city. Copy puts copyText on a copy card, with icon.
---@param owner Frame
---@param title string the menu's title
---@param message string|fun(): string
---@param copyTitle string
---@param copyText string
---@param trade? boolean
---@param icon? number|string
function Parts.ShareMenu(owner, title, message, copyTitle, copyText, trade, icon, say)
    local locked = C_ChatInfo.InChatMessagingLockdown()
    local target = UnitIsPlayer("target") and not UnitIsUnit("target", "player") and UnitIsFriend("player", "target")
        and GetUnitName("target", true) or nil
    local function Send(channel, to)
        local text = type(message) == "function" and message() or message
        C_ChatInfo.SendChatMessage(text, channel, nil, to)
    end
    local tradeChannel = trade and TradeChannel()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        -- Say: the game lets an addon speak only inside an instance.
        if say then
            root:CreateButton("Say", function() Send("SAY") end):SetEnabled(not locked and IsInInstance())
        end
        if trade then
            root:CreateButton("Trade", function() Send("CHANNEL", tradeChannel) end)
                :SetEnabled(not locked and tradeChannel ~= nil)
        end
        root:CreateButton("Party", function() Send(PartyChat()) end):SetEnabled(not locked and IsInGroup())
        root:CreateButton("Raid", function() Send("RAID") end):SetEnabled(not locked and IsInRaid())
        root:CreateButton("Guild", function() Send("GUILD") end):SetEnabled(not locked and IsInGuild())
        root:CreateButton(target and "Whisper " .. target or "Whisper your target", function()
            Send("WHISPER", target)
        end):SetEnabled(not locked and target ~= nil)
        root:CreateDivider()
        root:CreateButton("Copy", function() ns.ShowCopyLine(copyTitle, copyText, icon) end)
        if locked then root:CreateTitle(ns.Color("muted", "Chat is locked right now.")) end
        if trade and not tradeChannel then root:CreateTitle(ns.Color("muted", "Trade chat is only available in cities.")) end
    end)
end

-- A spot on the map, with a map pin link the reader can click; the line alone to copy.
---@param owner Frame
---@param title string the menu's title
---@param name string what the spot is for
---@param map number uiMapID
---@param x number percent
---@param y number percent
---@param note? string
function Parts.SharePlace(owner, title, name, map, x, y, note)
    local text = ns.WaypointText(name, map, x, y, note)
    Parts.ShareMenu(owner, title, function()
        local link = ns.WaypointLink(map, x, y)
        return link and text .. " " .. link or text
    end, name, text)
end

-------------------------------------------------------------------------------
--  Numbers lined up to the pixel: the Naowh font's digits are not all as wide, so each
--  character gets a cell as wide as the widest digit ("-" and "/" narrower), measured once
--  per size. The caller anchors the rightmost cell, cells[1].
-------------------------------------------------------------------------------
local cellWidths = {}   -- text size -> { digit = w, ["-"] = w, ["/"] = w }

local function CellWidths(parent, size)
    local widths = cellWidths[size]
    if widths then return widths end
    local probe = ns.Font(parent, size)
    local digit = 0
    for d = 0, 9 do
        probe:SetText(d)
        digit = math.max(digit, math.ceil(probe:GetStringWidth()))
    end
    widths = { digit = digit }
    for _, mark in ipairs({ "-", "/" }) do
        probe:SetText(mark)
        widths[mark] = math.ceil(probe:GetStringWidth()) + 2
    end
    probe:Hide()
    cellWidths[size] = widths
    return widths
end

local Cells = {}
Cells.__index = Cells

-- From the right, the rest hidden. Returns the leftmost shown.
function Cells:SetText(text)
    text = tostring(text)
    local n, widths = #text, self.widths
    for i = 1, #self do
        local cell = self[i]
        if i <= n then
            local char = text:sub(n - i + 1, n - i + 1)
            cell:SetWidth(widths[char] or widths.digit)
            cell:SetText(char)
            cell:Show()
        else
            cell:Hide()
        end
    end
    return self[math.max(1, math.min(n, #self))]
end

function Cells:SetTextColor(r, g, b)
    for i = 1, #self do self[i]:SetTextColor(r, g, b) end
end

function Parts.Cells(parent, size, color, count)
    local cells = setmetatable({ widths = CellWidths(parent, size) }, Cells)
    for i = 1, count do
        local cell = ns.Font(parent, size, nil, color)
        cell:SetJustifyH("CENTER")
        if i > 1 then cell:SetPoint("RIGHT", cells[i - 1], "LEFT", 0, 0) end
        cells[i] = cell
    end
    return cells
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local LINE_TRACK_ALPHA = 1
local LINE_FROM_SHARE = 0.45
local LINE_GLOW_W, LINE_GLOW_ALPHA = 28, 0.55
local shortTimes = {}

-- Seconds up to 90, then minutes up to 90, then hours, each rounded up so a time never reads
-- less than is left. The game formats it, since the time can be secret.
function Parts.ShortTime(prefix)
    prefix = prefix or ""
    local formatter = shortTimes[prefix]
    if formatter then return formatter end
    local Up = Enum.NumericRuleFormatRounding.Up
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({
        { threshold = 0, format = prefix .. "%ds", step = 1, rounding = Up },
        { threshold = 90, format = prefix .. "%dm", step = 1, rounding = Up, components = { { div = 60 } } },
        { threshold = 5400, format = prefix .. "%dh", step = 1, rounding = Up, components = { { div = 3600 } } },
    })
    shortTimes[prefix] = formatter
    return formatter
end

local function LineTimed()
    return C_DurationUtil and C_DurationUtil.CreateDuration and Enum and Enum.StatusBarTimerDirection
        and Enum.StatusBarInterpolation and true or false
end

local function LineRun(line, start, duration, prefix)
    if line.dur then
        line.dur:SetTimeFromStart(start, duration)
        if line.binding then
            local formatter = Parts.ShortTime(prefix)
            if formatter ~= line.formatter then
                line.formatter = formatter
                line.binding:SetFormatter(formatter)
            end
        end
        line:SetTimerDuration(line.dur, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.RemainingTime)
        if line.binding then line.binding:SetEnabled(true) end
    else
        line:SetValue(math.max(0, math.min(1, (start + duration - GetTime()) / duration)))
    end
    line.glow:Show()
end

-- Stops a status bar its timer owns, empty or full: SetValue does not repaint such a bar, but a
-- duration that has already run out leaves it still.
function Parts.StopTimer(bar, dur, full)
    dur:SetTimeFromStart(GetTime() - 1, 1)
    bar:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, full
        and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
end

local function LineStop(line)
    if line.dur then
        Parts.StopTimer(line, line.dur)
        if line.binding then line.binding:SetEnabled(false) end
    end
    line:SetValue(0)
    line.glow:Hide()
    if line.text then line.text:SetText("") end
end

local function LinePaint(line, color, textColor)
    local share = LINE_FROM_SHARE
    line.from:SetRGBA(color.r * share, color.g * share, color.b * share, 1)
    line.to:SetRGBA(color.r, color.g, color.b, 1)
    line:GetStatusBarTexture():SetGradient("HORIZONTAL", line.from, line.to)
    line.glowFrom:SetRGBA(color.r, color.g, color.b, 0)
    line.glowTo:SetRGBA(color.r, color.g, color.b, LINE_GLOW_ALPHA)
    line.glow:SetGradient("HORIZONTAL", line.glowFrom, line.glowTo)
    local c = textColor or color
    if line.text then line.text:SetTextColor(c.r, c.g, c.b) end
end

function Parts.TimerLine(parent, height, text)
    local line = CreateFrame("StatusBar", nil, parent)
    line:SetHeight(height)
    line:SetStatusBarTexture(WHITE)
    line:SetMinMaxValues(0, 1)
    line:SetValue(0)
    line:SetClipsChildren(true)
    ns.Solid(line, "BACKGROUND", T.line, LINE_TRACK_ALPHA):SetAllPoints()
    line.from, line.to = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    line.glowFrom, line.glowTo = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
    local over = CreateFrame("Frame", nil, line)
    over:SetAllPoints()
    line.glow = over:CreateTexture(nil, "OVERLAY")
    line.glow:SetTexture(WHITE)
    line.glow:SetBlendMode("ADD")
    line.glow:SetSize(LINE_GLOW_W, height)
    line.glow:SetPoint("RIGHT", line:GetStatusBarTexture(), "RIGHT")
    line.glow:Hide()
    line.text = text
    if LineTimed() then
        line.dur = C_DurationUtil.CreateDuration()
        if text and C_DurationUtil.CreateDurationTextBinding and C_StringUtil
            and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding then
            local binding = C_DurationUtil.CreateDurationTextBinding()
            binding:SetFontString(text)
            binding:SetDuration(line.dur)
            line.formatter = Parts.ShortTime()
            binding:SetFormatter(line.formatter)
            binding:SetZeroDurationText("")
            binding:SetExpiredText("")
            binding:SetEnabled(false)
            line.binding = binding
        end
    end
    line.Run, line.Stop, line.Paint = LineRun, LineStop, LinePaint
    LinePaint(line, T.accent)
    return line
end

local function RowItem(row, i)
    local label = row.labels[i]
    if label then return label end
    label = ns.Font(row, row.size, row.flags, row.color)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    row.labels[i] = label
    if row.iconSize then
        local icon = Parts.ItemIcon(row, row.iconSize)
        icon:Hide()
        row.icons[i] = icon
    end
    if row.sep and i > 1 then
        local sep = ns.Font(row, row.size, row.flags, row.sepColor)
        sep:SetText(row.sep)
        row.seps[i] = sep
    end
    return label
end

local function RowSetLabels(row, list, n, icons)
    local labels, widest = row.labels, 0
    for i = 1, math.max(n, #labels) do
        local label = i <= n and RowItem(row, i) or labels[i]
        local icon, sep = row.icons[i], row.seps[i]
        if i <= n then
            label:SetText(list[i])
            label:Show()
            local w = label:GetStringWidth()
            if w > widest then widest = w end
            if icon then
                local texture = icons and icons[i]
                if texture then icon.texture:SetTexture(texture) end
                icon:SetShown(texture and true or false)
            end
            if sep then sep:Show() end
        else
            label:Hide()
            if icon then icon:Hide() end
            if sep then sep:Hide() end
        end
    end
    row.count = n
    return widest
end

local function RowSpread(row, width)
    row:SetWidth(width)
    local n = row.count
    if n == 0 then return end
    local share = width / n
    local labels = row.labels
    for i = 1, n do
        labels[i]:ClearAllPoints()
        labels[i]:SetPoint("CENTER", row, "LEFT", share * (i - 0.5), 0)
    end
end

local function RowPack(row)
    local x, gap = 0, row.gap
    for i = 1, row.count do
        local sep, icon, label = row.seps[i], row.icons[i], row.labels[i]
        if i > 1 then x = x + gap end
        if sep then
            sep:ClearAllPoints()
            sep:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + sep:GetStringWidth()
        end
        if icon and icon:IsShown() then
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", row, "LEFT", x, -row.iconDrop)
            x = x + row.iconSize + row.iconGap
        end
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", x, 0)
        x = x + label:GetStringWidth()
    end
    row:SetWidth(math.max(1, x))
    return x
end

local function RowTextSize(row, size)
    if size == row.size then return end
    row.size = size
    row:SetHeight(size)
    if row.iconGrow then row.iconSize = size + row.iconGrow end
    local font, labels, seps, icons = ns.UIFontPath(), row.labels, row.seps, row.icons
    for i = 1, #labels do
        labels[i]:SetFont(font, size, row.flags or "")
        if seps[i] then seps[i]:SetFont(font, size, row.flags or "") end
        if icons[i] then icons[i]:SetSize(row.iconSize, row.iconSize) end
    end
end

local function RowColor(row, color)
    row.color = color
    local labels = row.labels
    for i = 1, #labels do labels[i]:SetTextColor(color.r, color.g, color.b) end
end

function Parts.LabelRow(parent, size, flags, color, opts)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(size)
    row.size, row.flags, row.color = size, flags, color or T.fg
    row.labels, row.icons, row.seps, row.count, row.gap = {}, {}, {}, 0, 0
    if opts then
        row.gap = opts.gap or 0
        row.iconGrow = opts.iconGrow
        row.iconSize = opts.icon or (opts.iconGrow and size + opts.iconGrow)
        row.iconGap, row.iconDrop = opts.iconGap or St.GAP, opts.iconDrop or 0
        row.sep, row.sepColor = opts.separator, opts.separatorColor or T.muted
    end
    row.SetLabels, row.Spread, row.Pack, row.SetColor = RowSetLabels, RowSpread, RowPack, RowColor
    row.SetTextSize = RowTextSize
    return row
end

-------------------------------------------------------------------------------
--  Panels
-------------------------------------------------------------------------------
-- Its title in the accent and a close button; the caller puts a view in it. With windowLook,
-- a window's backdrop (panel.backdrop, painted by the caller).
function Parts.Panel(title, windowLook)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(PANEL_W)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    if windowLook then
        panel.backdrop = Parts.Backdrop(panel)
    else
        ns.Solid(panel, "BACKGROUND", T.bg, 0.96):SetAllPoints()
    end
    ns.Border(panel, BORDER_RGB)
    panel.title = ns.Font(panel, 12, nil, T.accent)
    panel.title:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
    panel.title:SetPoint("RIGHT", -34, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    panel.title:SetText(title)
    panel.close = ns.Button(panel, "x", 20, 20, function() panel:Hide() end)
    panel.close:SetPoint("TOPRIGHT", -6, -6)
    return panel
end

-------------------------------------------------------------------------------
--  The side panel: details beside the window they were opened from, on whichever side has
--  room, with buttons along the bottom. It closes with that window, and opening one closes
--  the others.
-------------------------------------------------------------------------------
local SCROLL_GAP = 20    -- the view's right edge to the panel's, for the scrollbar
local SIDE_MIN_H = 320
local BUTTON_GAP = 4
local sidePanels = {}

-- panel.view is newView(scroll)'s; panel.buttons[label] each action's. opacity() is its
-- window's, 0 to 1.
---@param actions { [1]: string, [2]: fun() }[]
---@param newView fun(scroll: Frame): Frame
---@param opacity fun(): number
function Parts.SidePanel(actions, newView, opacity)
    local bottom = #actions > 0 and PANEL_BUTTONS or 0
    local panel = Parts.Panel("", true)
    panel:SetFrameStrata("HIGH")
    panel.opacity = opacity
    panel.backdrop:Card(4, PANEL_HEADER, 4, bottom + 4)
    panel.backdrop:Paint(opacity())
    local scroll = ns.UI.SlimScroll(panel)
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - 4)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, bottom + PANEL_PAD)
    local view = newView(scroll)
    view:SetWidth(PANEL_W - PANEL_PAD * 2 - SCROLL_GAP)
    scroll:SetScrollChild(view)
    panel.scroll, panel.view, panel.owners, panel.buttons = scroll, view, {}, {}
    -- The game's Lua stops on a division by zero.
    local count = math.max(1, #actions)
    local width = (PANEL_W - PANEL_PAD * 2 - BUTTON_GAP * (count - 1)) / count
    local previous
    for _, action in ipairs(actions) do
        local button = ns.Button(panel, action[1], width, 24, action[2])
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", BUTTON_GAP, 0)
        else
            button:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD)
        end
        panel.buttons[action[1]] = button
        previous = button
    end
    sidePanels[#sidePanels + 1] = panel
    return panel
end

-- When a window's opacity changes.
function Parts.RepaintSidePanels()
    for _, panel in ipairs(sidePanels) do panel.backdrop:Paint(panel.opacity()) end
end

local function Owner(frame)
    while frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
    return frame
end

-- Beside the window holding from, scrolled to the top.
function Parts.ShowBeside(panel, from)
    for _, other in ipairs(sidePanels) do
        if other ~= panel then other:Hide() end
    end
    local owner = Owner(from)
    if not panel.owners[owner] then
        panel.owners[owner] = true
        owner:HookScript("OnHide", function() panel:Hide() end)
    end
    panel:SetScale(owner:GetScale())
    panel:SetHeight(math.max(SIDE_MIN_H, owner:GetHeight()))
    panel:ClearAllPoints()
    local right = (owner:GetRight() or 0) * owner:GetEffectiveScale()
    local room = UIParent:GetRight() * UIParent:GetEffectiveScale() - right
    if room >= (PANEL_W + 8) * owner:GetEffectiveScale() then
        panel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
    end
    panel.scroll:SetVerticalScroll(0)
    panel:Show()
end
