-- DamageMeterPreview.lua: the Default Damage Meter card's preview, a mock of the game's meter drawn with what the card picks.
local ns = _G.NaowhForever

local T = ns.THEME
local Parts = ns.Shared.Parts

local ATLAS_HEADER, ATLAS_BAR, ATLAS_SHADOW = "ui-damagemeters-header-bar", "UI-HUD-CoolDownManager-Bar", "ui-damagemeters-bar-shadowbg"
local ATLAS_EDGE, ATLAS_BORDERED, ATLAS_WINDOW = "ui-damagemeters-bar-shadowedge", "UI-HUD-CoolDownManager-Bar-BG", "damagemeters-background"
local ATLAS_MINIMIZE, ATLAS_MODE = "ui-questtrackerbutton-collapse-all", "common-dropdown-a-button-shadowless"
local ATLAS_COG, ATLAS_SESSION = "common-dropdown-a-button-settings-shadowless", "common-dropdown-c-button"
local ICON_PATH = "Interface\\Icons\\ClassIcon_"
local FONT_BAR, FONT_TITLE = "NumberFontNormal", "GameFontNormalMed1"
local TEXT_TITLE, TEXT_NOTE = ns.L("Damage Done"), ns.L("A sample: the meter in the game shows your fights.")
local TEXT_TIMER, TEXT_SESSION = "2:41", "O"
local NOTE_SIZE, NOTE_H, NOTE_Y, MARGIN, STAGE_H = 11, 20, 6, 14, 220
local HEADER_H, BODY_TOP, BODY_BOTTOM = 32, 4, 6
local MODE_SIZE, COG_SIZE, SESSION_SIZE, MINIMIZE_W, MINIMIZE_H = 25, 27, 18, 18, 19
local TIMER_X, TIMER_Y, MODE_RISE, MODE_Y, MINIMIZE_X, MINIMIZE_Y = 1, -9, 6, -2, -3, -5
local TITLE_Y, BUTTON_GAP, COG_Y, SESSION_RISE, SESSION_OUT = 3, 2, -2, 3, 7
local CROP_LOW, CROP_HIGH = 0.0625, 0.9
local ICON_GAP_FRAMED, BAR_RIGHT, BAR_VERTICAL, NAME_LEFT, VALUE_RIGHT, NAME_VALUE = 5, -4, 1, 2, -3, -25
local SHADOW_INSET, BORDERED_INSET = { -2, 2, 2, -2 }, { -2, 2, 6, -7 }
local PERCENT, WINDOW_LEVEL, BORDER_LEVEL = 100, 1, 10
local DEFAULT_WIDTH, DEFAULT_BAR, DEFAULT_PAD = 300, 24, 4
local STYLE_BORDERED, STYLE_THIN = "Bordered", "Thin"
local FALLBACK_BAR = { r = 0.78, g = 0.78, b = 0.78 }
local OUTLINE_GAME = "game"

local SAMPLES = {
    { name = "Aldric", class = "DEATHKNIGHT", icon = "DeathKnight", value = "5,214 (8.7)", fill = 1 },
    { name = "Brightheart", class = "MAGE", icon = "Mage", value = "4,276 (7.1)", fill = 0.82 },
    { name = "Corvin", class = "WARLOCK", icon = "Warlock", value = "3,339 (5.6)", fill = 0.64 },
    { name = "Dessa", class = "HUNTER", icon = "Hunter", value = "2,138 (3.6)", fill = 0.41 },
}

local function Layout(name, default)
    local layout = ns.DamageMeterLayout
    local row = layout and layout.byName and layout.byName[name]
    local value = row and row.get and row.get()
    if value == nil then return default end
    return value
end

local function Geometry()
    local g = { width = Layout("FrameWidth", DEFAULT_WIDTH), barHeight = Layout("BarHeight", DEFAULT_BAR),
        padding = Layout("Padding", DEFAULT_PAD), opacity = Layout("Transparency", PERCENT),
        background = Layout("BackgroundTransparency", 0), text = Layout("TextSize", PERCENT),
        icons = Layout("ShowSpecIcon", true) ~= false, classColor = Layout("ShowClassColor", true) ~= false }
    local style = tostring(Layout("Style", ""))
    local enum = _G.Enum and _G.Enum.DamageMeterStyle
    g.bordered = enum ~= nil and style == tostring(enum[STYLE_BORDERED])
    g.thin = enum ~= nil and style == tostring(enum[STYLE_THIN])
    g.opacity, g.background, g.text = g.opacity / PERCENT, g.background / PERCENT, g.text / PERCENT
    g.bodyHeight = #SAMPLES * (g.barHeight + g.padding) - g.padding
    g.height = HEADER_H + BODY_TOP + g.bodyHeight + BODY_BOTTOM
    return g
end

local function Remember(fs)
    local path, size, flags = fs:GetFont()
    local r, g, b = fs:GetTextColor()
    local sx, sy = fs:GetShadowOffset()
    local sr, sg, sb, sa = fs:GetShadowColor()
    fs.game = { path = path, size = size, flags = flags, r = r, g = g, b = b, sx = sx, sy = sy, sr = sr, sg = sg, sb = sb,
        sa = sa }
    return fs
end

local function Text(parent, template)
    return Remember(parent:CreateFontString(nil, "OVERLAY", template))
end

local function Dress(fs, look, color, size, scale)
    local game = fs.game
    local size_ = (type(size) == "number" and size > 0) and size or game.size
    local path = look.font or game.path
    if look.outline == nil or look.outline == OUTLINE_GAME then
        fs:SetFont(path, size_, game.flags)
        fs:SetShadowOffset(game.sx, game.sy)
        fs:SetShadowColor(game.sr, game.sg, game.sb, game.sa)
    else
        fs:SetFont(path, size_, Parts.HudFlags(look.outline))
        if look.outline == "" then Parts.HudText(fs) else Parts.HudText(fs, false) end
    end
    local c = color or game
    fs:SetTextColor(c.r, c.g, c.b)
    if fs.SetTextScale then fs:SetTextScale(scale) end
end

local function Tint(texture, c)
    if c then texture:SetVertexColor(c.r, c.g, c.b) else texture:SetVertexColor(1, 1, 1) end
end

local function Flat(texture, c, atlas)
    if c then texture:SetColorTexture(c.r, c.g, c.b, 1) else texture:SetAtlas(atlas) end
end

local function ClassColor(class)
    local colors = _G.RAID_CLASS_COLORS
    return colors and colors[class] or FALLBACK_BAR
end

local function DefaultBar()
    return _G.DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR or FALLBACK_BAR
end

local function NewEdge(frame)
    return ns.Border(frame, T.line)
end

local function NewEntry(parent)
    local e = CreateFrame("Frame", nil, parent)
    e.iconFrame = CreateFrame("Frame", nil, e)
    e.icon = e.iconFrame:CreateTexture(nil, "ARTWORK")
    e.icon:SetAllPoints()
    e.iconEdge = NewEdge(e.iconFrame)
    e.bar = CreateFrame("Frame", nil, e)
    e.shadow = e.bar:CreateTexture(nil, "BACKGROUND")
    e.fill = e.bar:CreateTexture(nil, "ARTWORK")
    e.edge = e.bar:CreateTexture(nil, "OVERLAY")
    e.over = CreateFrame("Frame", nil, e)
    e.over:SetAllPoints()
    e.over:SetFrameLevel(e.bar:GetFrameLevel() + 2)
    e.name = Text(e.over, FONT_BAR)
    e.value = Text(e.over, FONT_BAR)
    e.name:SetJustifyH("LEFT")
    e.value:SetJustifyH("LEFT")
    return e
end

local function PaintShadow(e, look, g)
    local c = look.barBackground
    local inset = g.bordered and BORDERED_INSET or SHADOW_INSET
    e.shadow:ClearAllPoints()
    e.shadow:SetPoint("TOPLEFT", e.bar, "TOPLEFT", inset[1], inset[2])
    e.shadow:SetPoint("BOTTOMRIGHT", e.bar, "BOTTOMRIGHT", inset[3], inset[4])
    Flat(e.shadow, c, g.bordered and ATLAS_BORDERED or ATLAS_SHADOW)
    e.shadow:SetAlpha(look.barBackgroundAlpha)
    e.edge:ClearAllPoints()
    e.edge:SetPoint("TOPLEFT", e.bar, "TOPLEFT", SHADOW_INSET[1], SHADOW_INSET[2])
    e.edge:SetPoint("BOTTOMRIGHT", e.bar, "BOTTOMRIGHT", SHADOW_INSET[3], SHADOW_INSET[4])
    e.edge:SetAtlas(ATLAS_EDGE)
    e.edge:SetShown(not g.bordered)
    e.edge:SetAlpha(c and 0 or 1)
end

local function PaintBar(e, sample, look, g, width)
    e.fill:ClearAllPoints()
    e.fill:SetPoint("TOPLEFT", e.bar, "TOPLEFT")
    e.fill:SetPoint("BOTTOMLEFT", e.bar, "BOTTOMLEFT")
    e.fill:SetWidth(math.max(1, width * sample.fill))
    if look.barTexture then
        e.fill:SetTexture(look.barTexture)
        e.fill:SetTexCoord(0, 1, 0, 1)
    else
        e.fill:SetAtlas(ATLAS_BAR)
    end
    local c = look.barColor or (g.classColor and ClassColor(sample.class)) or DefaultBar()
    e.fill:SetVertexColor(c.r, c.g, c.b)
    e.fill:SetAlpha(look.barAlpha)
end

local function PaintEntry(e, sample, index, look, g)
    local h = g.barHeight
    e:SetSize(g.width, h)
    e.iconFrame:SetShown(g.icons)
    e.iconFrame:ClearAllPoints()
    e.iconFrame:SetPoint("LEFT", e, "LEFT")
    e.iconFrame:SetSize(h, h)
    e.icon:SetTexture(ICON_PATH .. sample.icon)
    e.icon:SetTexCoord(CROP_LOW, CROP_HIGH, CROP_LOW, CROP_HIGH)
    if look.iconBorder and g.icons then
        e.iconEdge:SetColor(look.iconBorder.r, look.iconBorder.g, look.iconBorder.b, 1)
        e.iconEdge._frame:Show()
    else
        e.iconEdge._frame:Hide()
    end
    local framed = g.icons and (g.bordered or g.thin) and ICON_GAP_FRAMED or 0
    local iconW = g.icons and h or 0
    e.bar:ClearAllPoints()
    e.name:ClearAllPoints()
    e.value:ClearAllPoints()
    if g.icons then
        e.bar:SetPoint("LEFT", e.iconFrame, "RIGHT", framed, 0)
    else
        e.bar:SetPoint("LEFT", e, "LEFT")
    end
    if g.thin then
        e.name:SetPoint("TOP", e, "TOP")
        e.name:SetPoint("LEFT", g.icons and e.iconFrame or e, g.icons and "RIGHT" or "LEFT", framed, 0)
        e.name:SetPoint("RIGHT", e.value, "LEFT", NAME_VALUE, 0)
        e.value:SetPoint("TOP", e, "TOP")
        e.value:SetPoint("RIGHT", e, "RIGHT", VALUE_RIGHT, 0)
        e.bar:SetPoint("TOP", e.name, "BOTTOM")
        e.bar:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, BAR_VERTICAL)
    else
        e.bar:SetPoint("TOP", e, "TOP", 0, -BAR_VERTICAL)
        e.bar:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", BAR_RIGHT, BAR_VERTICAL)
        e.name:SetPoint("LEFT", e.bar, "LEFT", NAME_LEFT, 0)
        e.name:SetPoint("RIGHT", e.value, "LEFT", NAME_VALUE, 0)
        e.value:SetPoint("RIGHT", e.bar, "RIGHT", VALUE_RIGHT, 0)
    end
    e.name:SetText(index .. ". " .. sample.name)
    e.value:SetText(sample.value)
    Dress(e.name, look, look.nameColor, look.nameSize, g.text)
    Dress(e.value, look, look.valueColor, look.valueSize, g.text)
    PaintShadow(e, look, g)
    PaintBar(e, sample, look, g, g.width - iconW - framed + BAR_RIGHT)
end

local function NewButton(window, width, height, atlas, y)
    local b = CreateFrame("Frame", nil, window)
    b:SetSize(width, height)
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAtlas(atlas, true)
    b.texture:SetPoint("CENTER", b, "CENTER", 0, y or 0)
    return b
end

local function Glyph(b, look, shown)
    b:SetAlpha(shown and 1 or 0)
    b.texture:SetDesaturated(look.buttons ~= nil)
    Tint(b.texture, look.buttons)
end

local function NewWindow(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetFrameLevel(parent:GetFrameLevel() + WINDOW_LEVEL)
    w.back = w:CreateTexture(nil, "BACKGROUND")
    w.header = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.timer = Text(w, FONT_TITLE)
    w.title = Text(w, FONT_TITLE)
    w.title:SetJustifyH("LEFT")
    w.arrow = NewButton(w, MODE_SIZE, MODE_SIZE, ATLAS_MODE, MODE_Y)
    w.cog = NewButton(w, COG_SIZE, COG_SIZE, ATLAS_COG)
    w.minimize = NewButton(w, MINIMIZE_W, MINIMIZE_H, ATLAS_MINIMIZE)
    w.session = NewButton(w, SESSION_SIZE, SESSION_SIZE, ATLAS_SESSION)
    w.session.texture:ClearAllPoints()
    w.session.texture:SetPoint("TOPLEFT", w.session, "TOPLEFT", -SESSION_OUT, SESSION_OUT)
    w.session.texture:SetPoint("BOTTOMRIGHT", w.session, "BOTTOMRIGHT", SESSION_OUT, -SESSION_OUT)
    w.session.letter = Text(w.session, FONT_TITLE)
    w.session.letter:SetPoint("CENTER")
    w.border = NewEdge(w)
    w.border._frame:SetFrameLevel(w:GetFrameLevel() + BORDER_LEVEL)
    w.entries = {}
    for i = 1, #SAMPLES do w.entries[i] = NewEntry(w) end
    return w
end

local function PaintTitle(w, look, g)
    w.timer:SetText(TEXT_TIMER)
    Dress(w.timer, look, look.valueColor, look.valueSize, g.text)
    local timerWidth = look.timer and w.timer:GetStringWidth() or 1
    w.timer:ClearAllPoints()
    w.timer:SetPoint("TOPLEFT", w, "TOPLEFT", TIMER_X + look.timerX, TIMER_Y)
    w.timer:SetAlpha(look.timer and 1 or 0)
    w.arrow:ClearAllPoints()
    w.arrow:SetPoint("TOPLEFT", w, "TOPLEFT", TIMER_X + timerWidth, TIMER_Y + MODE_RISE)
    Glyph(w.arrow, look, look.arrow)
    w.title:ClearAllPoints()
    w.title:SetPoint("LEFT", w.arrow.texture, "RIGHT", look.gap + look.titleX, TITLE_Y)
    w.title:SetText(TEXT_TITLE)
    w.title:SetAlpha(look.title and 1 or 0)
    Dress(w.title, look, look.titleColor, look.titleSize, g.text)
    w.minimize:ClearAllPoints()
    w.minimize:SetPoint("TOPRIGHT", w, "TOPRIGHT", MINIMIZE_X, MINIMIZE_Y)
    Glyph(w.minimize, look, look.minimize)
    w.cog:ClearAllPoints()
    w.cog:SetPoint("RIGHT", w.minimize, "LEFT", -BUTTON_GAP, COG_Y)
    Glyph(w.cog, look, look.cog)
    w.session:ClearAllPoints()
    w.session:SetPoint("RIGHT", w.cog, "LEFT", -BUTTON_GAP, SESSION_RISE)
    Glyph(w.session, look, look.session)
    w.session.letter:SetText(TEXT_SESSION)
    Dress(w.session.letter, look, look.buttons, nil, g.text)
end

local function PaintBody(w, look, g)
    w.header:ClearAllPoints()
    w.header:SetPoint("TOPLEFT", w, "TOPLEFT")
    w.header:SetPoint("TOPRIGHT", w, "TOPRIGHT")
    w.header:SetHeight(HEADER_H)
    Flat(w.header, look.header, ATLAS_HEADER)
    w.back:ClearAllPoints()
    w.back:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -HEADER_H)
    w.back:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT")
    Flat(w.back, look.window, ATLAS_WINDOW)
    w.back:SetAlpha(g.background)
    for i, sample in ipairs(SAMPLES) do
        local e = w.entries[i]
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -(HEADER_H + BODY_TOP + (i - 1) * (g.barHeight + g.padding)))
        PaintEntry(e, sample, i, look, g)
    end
    if look.border then
        w.border:SetColor(look.border.r, look.border.g, look.border.b, 1)
        w.border._frame:Show()
    else
        w.border._frame:Hide()
    end
end

local live, queued

local function New(stage)
    local preview = CreateFrame("Frame", nil, stage)
    live = preview
    preview:SetAllPoints()
    preview.window = NewWindow(preview)
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function Paint(preview)
    local look = ns.DamageMeterLook.Describe()
    local g = Geometry()
    local w = preview.window
    local room = preview:GetWidth() - MARGIN * 2
    local scale = 1
    if room > 0 and g.width > room then scale = room / g.width end
    local tall = STAGE_H - MARGIN * 2 - NOTE_H
    if g.height * scale > tall then scale = tall / g.height end
    w:SetScale(scale)
    w:SetSize(g.width, g.height)
    w:SetAlpha(g.opacity)
    w:ClearAllPoints()
    w:SetPoint("TOP", preview, "TOP", 0, -MARGIN)
    PaintBody(w, look, g)
    PaintTitle(w, look, g)
    preview.note:SetText(TEXT_NOTE)
end

local function Refresh()
    if queued or not (live and live:IsVisible()) then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if live and live:IsVisible() then Paint(live) end
    end)
end

local store = ns.QoLSettings
if store and store.OnChange then store.OnChange(Refresh) end

ns.DamageMeterPreview = { height = STAGE_H, states = { { key = "meter", label = "Meter" } }, new = New, paint = Paint,
    Refresh = Refresh }
