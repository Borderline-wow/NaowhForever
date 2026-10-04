-------------------------------------------------------------------------------
--  Window.lua -- a window in the house look (ns.Shared.Parts): the frame, its title bar
--  with the logo, icons and opacity slider, a switch over a list, a search box and the
--  footer. The Dungeon Journal's and the BiS List's windows are built from these.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Parts = ns.Shared.Parts

local St = ns.Shared.Style
local BORDER_RGB, HEADER, PAD, FOOTER = St.BORDER_RGB, St.WINDOW_HEADER, St.WINDOW_PAD, St.WINDOW_FOOTER
local BAR_ICON, ROUND, LOGO, LOGO_SIZE = St.BAR_ICON, St.ROUND, St.LOGO, St.LOGO_SIZE
local TAB_SIZE, TAB_H, TAB_LINE, TAB_FILL = St.TAB_SIZE, St.TAB_H, St.TAB_LINE, St.TAB_FILL
local SLIDER_W, SLIDER_H, KNOB, KNOB_GLOW, OPACITY_MIN = St.SLIDER_W, St.SLIDER_H, St.KNOB, St.KNOB_GLOW,
    St.OPACITY_MIN

local LOGO_REST = 0.9
local BRAND_REST = 0.8
local FOOTER_LOGO = 14
local FOOTER_INSET = 8

local function Tip(owner, anchor, title, line)
    if not Parts.Tip(owner, anchor) then return end
    GameTooltip:SetText(title, 1, 1, 1)
    if line then GameTooltip:AddLine(line, T.muted.r, T.muted.g, T.muted.b, true) end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  The frame
-------------------------------------------------------------------------------
local pendingBack, pendingBackText

function Parts.SetBack(window, back, text)
    window.onBack = back
    local link = window.backLink
    if not link then return end
    link:SetShown(back ~= nil)
    if back then Parts.SetLink(link, text or "Back") end
end

-- Opens a window from another one, which goes away; the new window's title then has a link
-- back to it, and closing the new window brings it back.
function Parts.OpenWithBack(open, from, back, text)
    pendingBack, pendingBackText = back, text
    from:Hide()
    open()
    pendingBack, pendingBackText = nil, nil
end

local function OnShow(frame)
    if not InCombatLockdown() then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    if pendingBack then
        Parts.SetBack(frame, pendingBack, pendingBackText)
        pendingBack, pendingBackText = nil, nil
    end
end

local function OnHide(frame)
    if frame.stepAside then return end
    local back = frame.onBack
    if not back then return end
    Parts.SetBack(frame, nil)
    back()
end

local function DragStop(frame)
    frame:StopMovingOrSizing()
    local point, _, relativePoint, x, y = frame:GetPoint()
    ns.AccountSettings()[frame.positionKey] = { point, relativePoint, x, y }
end

-- Movable, kept where you leave it (account-wide, under positionKey), closed by Esc. Its
-- backdrop is window.backdrop, for the caller's cards and opacity.
function Parts.Window(width, height, positionKey)
    local window = CreateFrame("Frame", nil, UIParent)
    window:SetSize(width, height)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window.positionKey = positionKey
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", DragStop)
    local saved = ns.AccountSettings()[positionKey]
    if type(saved) == "table" then
        window:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        window:SetPoint("CENTER")
    end
    window.backdrop = Parts.Backdrop(window)
    ns.Border(window, BORDER_RGB)
    window:SetScript("OnKeyDown", ns.UI.CloseOnEscape)
    window:SetScript("OnShow", OnShow)
    window:SetScript("OnHide", OnHide)
    local rule = ns.Solid(window, "ARTWORK", BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -HEADER)
    rule:SetPoint("TOPRIGHT", 0, -HEADER)
    ns.Hairline(rule, "h")
    return window
end

-------------------------------------------------------------------------------
--  The title bar: the logo (it opens the module's options page) and the title over its
--  subtitle on the left, close on the right. Returns close, for the bar's icons to follow.
-------------------------------------------------------------------------------
local function LogoEnter(logo)
    logo.icon:SetAlpha(1)
    Tip(logo, "ANCHOR_BOTTOMRIGHT", "Naowh Forever", "Click to open its options.")
end

local function LogoLeave(logo)
    logo.icon:SetAlpha(LOGO_REST)
    GameTooltip:Hide()
end

local function OpenPage(button)
    ns.OpenOptionsWindow(button.page)
end

local function BackClicked(link)
    link:GetParent():Hide()
end

function Parts.TitleBar(window, title, subtitle, page)
    local middle = -HEADER / 2
    local logo = CreateFrame("Button", nil, window)
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("LEFT", window, "TOPLEFT", PAD, middle)
    logo.icon = logo:CreateTexture(nil, "ARTWORK")
    logo.icon:SetAllPoints()
    logo.icon:SetTexture(LOGO, nil, nil, "TRILINEAR")
    logo.icon:SetAlpha(LOGO_REST)
    logo.page = page
    logo:SetScript("OnClick", OpenPage)
    logo:SetScript("OnEnter", LogoEnter)
    logo:SetScript("OnLeave", LogoLeave)
    window.logo = logo
    window.title = ns.Font(window, 20, nil, T.fg)
    window.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 1)
    window.title:SetText(title)
    window.subtitle = ns.Font(window, 11, nil, T.muted)
    window.subtitle:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -2)
    window.subtitle:SetText(subtitle)
    window.backLink = Parts.Link(window, BackClicked, true)
    window.backLink:SetPoint("LEFT", window.title, "RIGHT", 16, -1)
    window.backLink:Hide()
    local close = ns.Button(window, "x", 24, 24, function() window:Hide() end)
    close:SetPoint("RIGHT", window, "TOPRIGHT", -8, middle)
    return close
end

-------------------------------------------------------------------------------
--  The title bar's icons: muted, the accent under the mouse
-------------------------------------------------------------------------------
function Parts.LightBarIcon(frame, lit)
    local color = lit and T.accent or T.muted
    frame.icon:SetVertexColor(color.r, color.g, color.b)
    if frame.label then frame.label:SetTextColor(color.r, color.g, color.b) end
end
local Light = Parts.LightBarIcon

local function BarLeave(frame)
    Light(frame, false)
    GameTooltip:Hide()
end

function Parts.BarIcon(parent, texture, isButton)
    local frame = CreateFrame(isButton and "Button" or "Frame", nil, parent)
    frame:SetSize(BAR_ICON + 4, BAR_ICON + 4)
    frame:EnableMouse(true)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture(texture)
    frame.icon:SetSize(BAR_ICON, BAR_ICON)
    frame.icon:SetPoint("LEFT", 2, 0)
    Light(frame, false)
    frame:SetScript("OnLeave", BarLeave)
    return frame
end

local function BarButtonEnter(button)
    Light(button, true)
    Tip(button, "ANCHOR_BOTTOM", button.tip, button.hint)
end

-- An icon that does one thing: tip says what, hint how; text, a word after the icon for the
-- action a newcomer needs.
function Parts.BarButton(parent, texture, tip, hint, onClick, text)
    local button = Parts.BarIcon(parent, texture, true)
    button.tip, button.hint = tip, hint
    if text then
        button.label = ns.Font(button, 12)
        button.label:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
        button.label:SetText(text)
        button:SetWidth(BAR_ICON + 8 + math.ceil(button.label:GetStringWidth()))
        Light(button, false)
    end
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", BarButtonEnter)
    return button
end

-------------------------------------------------------------------------------
--  Opacity: a half-filled circle before a slider in the house look, on the kit's slider: a
--  thin track with round ends, its filled part a blue that brightens toward a round white
--  knob, a soft glow round the knob under the mouse, and the value as muted text before %.
-------------------------------------------------------------------------------
local function Round(parent, layer, size, color, alpha)
    local dot = parent:CreateTexture(nil, layer)
    dot:SetTexture(ROUND, nil, nil, "TRILINEAR")
    dot:SetSize(size, size)
    dot:SetVertexColor(color.r, color.g, color.b, alpha or 1)
    return dot
end

local function GlowShow(slider) slider.glow:Show() end
local function GlowHide(slider)
    if not IsMouseButtonDown("LeftButton") then slider.glow:Hide() end
end
local function GlowRelease(slider)
    if not slider:IsMouseOver() then slider.glow:Hide() end
end

local function OpacityEnter(frame)
    Light(frame, true)
    Tip(frame, "ANCHOR_BOTTOM", "Window opacity")
end

-- get() and set(value) in percent. Placed left of rightOf; returns the icon, its left end,
-- and the slider (slider._refreshValue() shows a value set elsewhere).
function Parts.Opacity(parent, rightOf, get, set)
    local slider = ns.UI.BuildSliderCore(parent, SLIDER_W, SLIDER_H, KNOB, 24, 18, 11, 1, OPACITY_MIN, 100, 5,
        get, set)
    local dim, bright = T.accent, T.accentSoft
    local deep = { r = dim.r * 0.6, g = dim.g * 0.6, b = dim.b * 0.6 }
    Round(slider, "BORDER", SLIDER_H, deep):SetPoint("CENTER", slider.rail, "LEFT", 0, 0)
    Round(slider, "BACKGROUND", SLIDER_H, T.line):SetPoint("CENTER", slider.rail, "RIGHT", 0, 0)
    slider.fill:SetColorTexture(1, 1, 1, 1)
    slider.fill:SetGradient("HORIZONTAL", CreateColor(deep.r, deep.g, deep.b, 1),
        CreateColor(bright.r, bright.g, bright.b, 1))
    slider.thumb:SetTexture(ROUND, nil, nil, "TRILINEAR")
    slider.thumb:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
    slider.thumb:SetSize(KNOB, KNOB)
    slider.glow = Round(slider, "BORDER", KNOB_GLOW, bright, 0.25)
    slider.glow:SetPoint("CENTER", slider.thumb, "CENTER")
    slider.glow:Hide()
    slider:HookScript("OnEnter", GlowShow)
    slider:HookScript("OnLeave", GlowHide)
    slider:HookScript("OnMouseUp", GlowRelease)
    local box = slider.valueBox
    slider.valueFill:Hide()
    slider.valueBorder._frame:Hide()
    box:SetFont(ns.UIFontPath(), 11, "")
    box:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(0, 0, 0, 0)
    box:SetWidth(24)
    local percent = ns.Font(parent, 11, nil, T.muted)
    percent:SetText("%")
    percent:SetPoint("RIGHT", rightOf, "LEFT", -14, 0)
    box:SetPoint("RIGHT", percent, "LEFT", -1, 0)
    slider:SetPoint("RIGHT", box, "LEFT", -10, 0)
    local icon = Parts.BarIcon(parent, St.OPACITY)
    icon:SetScript("OnEnter", OpacityEnter)
    icon:SetPoint("RIGHT", slider, "LEFT", -6, 0)
    return icon, slider
end

-------------------------------------------------------------------------------
--  A switch: parts side by side in the house's black border, each as wide as its words
--  want of the width, split by hairlines; the part shown in white on a faint accent fill,
--  with the accent under it. onPick(key) on a click on another part.
-------------------------------------------------------------------------------
function Parts.PaintTabs(bar, shown)
    bar.shown = shown
    for _, button in ipairs(bar.buttons) do
        local on = button.key == shown
        local color = on and T.fg or T.muted
        button.text:SetTextColor(color.r, color.g, color.b)
        button.fill:SetShown(on)
        button.line:SetShown(on)
    end
end

local function TabClicked(button)
    local bar = button:GetParent()
    if button.key ~= bar.shown then bar.onPick(button.key) end
end

local function TabEnter(button)
    if button.key ~= button:GetParent().shown then button.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b) end
    if button.tip then Tip(button, "ANCHOR_BOTTOM", button.label, button.tip) end
end

local function TabLeave(button)
    local bar = button:GetParent()
    Parts.PaintTabs(bar, bar.shown)
    GameTooltip:Hide()
end

local function NewTab(bar)
    local button = CreateFrame("Button", nil, bar)
    button.text = ns.Font(button, TAB_SIZE, nil, T.muted)
    button.text:SetPoint("CENTER", 0, 0)
    button.fill = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.fill:SetAllPoints()
    button.fill:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, TAB_FILL)
    button.line = ns.Solid(button, "ARTWORK", T.accent, 1)
    button.line:SetPoint("BOTTOMLEFT")
    button.line:SetPoint("BOTTOMRIGHT")
    button.line:SetHeight(TAB_LINE)
    button:SetScript("OnClick", TabClicked)
    button:SetScript("OnEnter", TabEnter)
    button:SetScript("OnLeave", TabLeave)
    return button
end

-- items: { key, label, tip? }. A bar can be given new items (a class's specs); its parts are
-- reused.
function Parts.SetTabs(bar, items)
    local width, words = bar:GetWidth(), 0
    for i, item in ipairs(items) do
        local button = bar.buttons[i] or NewTab(bar)
        bar.buttons[i] = button
        button.key, button.label, button.tip = item.key, item.label, item.tip
        button.text:SetText(item.label)
        button.want = math.ceil(button.text:GetStringWidth())
        words = words + button.want
        button:Show()
    end
    for i = #items + 1, #bar.buttons do bar.buttons[i]:Hide() end
    for i = 1, #bar.splits do bar.splits[i]:Hide() end
    if #items == 0 then return end
    local spare, x = (width - words) / #items, 0
    for i = 1, #items do
        local button = bar.buttons[i]
        local w = i == #items and width - x or math.floor(button.want + spare + 0.5)
        button:SetSize(w, TAB_H)
        button:SetPoint("LEFT", x, 0)
        if i > 1 then
            local split = bar.splits[i - 1]
            if not split then
                split = ns.Solid(bar, "BORDER", BORDER_RGB, 1)
                ns.Hairline(split, "v")   -- once, when made: the tabs are laid out again on a change
                bar.splits[i - 1] = split
            end
            split:SetPoint("TOPLEFT", x, 0)
            split:SetPoint("BOTTOMLEFT", x, 0)
            split:Show()
        end
        x = x + w
    end
end

function Parts.FitTabs(bar, items, margin, maxW)
    Parts.SetTabs(bar, items)
    local words = 0
    for i = 1, #items do words = words + bar.buttons[i].want end
    bar:SetWidth(math.min(maxW or math.huge, words + margin * #items))
    Parts.SetTabs(bar, items)
end

function Parts.Tabs(parent, width, items, onPick)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, TAB_H)
    ns.Solid(bar, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(bar, BORDER_RGB)
    bar.buttons, bar.splits, bar.onPick = {}, {}, onPick
    Parts.SetTabs(bar, items)
    return bar
end

-------------------------------------------------------------------------------
--  A search box: a lighter fill than the window in the black border, the accent edge while
--  you type, and a muted magnifier before the hint.
-------------------------------------------------------------------------------
local SEARCH_ICON_SIZE, SEARCH_ICON_LEFT = 13, 7
local SEARCH_TEXT_LEFT = SEARCH_ICON_LEFT + SEARCH_ICON_SIZE + 6

local function Edge(box, color)
    box.border:SetColor(color.r, color.g, color.b, 1)
end
local function SearchFocus(box) Edge(box, T.accent) end
local function SearchBlur(box) Edge(box, BORDER_RGB) end

function Parts.SearchBox(parent, hint, onSearch)
    local box = ns.NewSearchBox(parent, hint, onSearch)
    local fill = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 1)
    fill:SetAllPoints()
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(St.SEARCH)
    icon:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    icon:SetPoint("LEFT", SEARCH_ICON_LEFT, 0)
    icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    box:SetTextInsets(SEARCH_TEXT_LEFT, 22, 0, 0)
    box.hint:ClearAllPoints()
    box.hint:SetPoint("LEFT", SEARCH_TEXT_LEFT, 0)
    Edge(box, BORDER_RGB)
    box:HookScript("OnEditFocusGained", SearchFocus)
    box:HookScript("OnEditFocusLost", SearchBlur)
    return box
end

-------------------------------------------------------------------------------
--  The footer: on the left the Naowh N, then "Naowh" in white and "Forever" in the accent,
--  as the options window writes it (a click opens the module's page); on the right, small
--  and faint, a note of where the data is from.
-------------------------------------------------------------------------------
local function BrandEnter(brand)
    brand:SetAlpha(1)
    Tip(brand, "ANCHOR_TOP", "Naowh Forever", "Click to open its options.")
end

local function BrandLeave(brand)
    brand:SetAlpha(BRAND_REST)
    GameTooltip:Hide()
end

function Parts.FooterBrand(window, page, left)
    local brand = CreateFrame("Button", nil, window)
    brand.icon = brand:CreateTexture(nil, "ARTWORK")
    brand.icon:SetTexture(St.LOGO_SMALL, nil, nil, "TRILINEAR")
    brand.icon:SetSize(FOOTER_LOGO, FOOTER_LOGO)
    brand.icon:SetPoint("LEFT")
    brand.text = ns.Font(brand, 10, nil, T.fg)
    brand.text:SetPoint("LEFT", brand.icon, "RIGHT", 5, 0)
    brand.text:SetText("Naowh " .. ns.Color("accent", "Forever"))
    brand:SetSize(FOOTER_LOGO + 5 + math.ceil(brand.text:GetStringWidth()), FOOTER)
    brand:SetPoint("BOTTOMLEFT", (left or 6) + FOOTER_INSET, 3)
    brand.page = page
    brand:SetScript("OnClick", OpenPage)
    brand:SetScript("OnEnter", BrandEnter)
    brand:SetScript("OnLeave", BrandLeave)
    BrandLeave(brand)
    return brand
end

-- onEnter, when given, shows what the note is about.
function Parts.FooterNote(window, text, onEnter)
    local note = CreateFrame("Frame", nil, window)
    note.text = ns.Font(note, 10, nil, T.muted)
    note.text:SetPoint("RIGHT")
    note.text:SetText(text)
    note:SetSize(math.ceil(note.text:GetStringWidth()), FOOTER)
    note:SetPoint("BOTTOMRIGHT", -(4 + FOOTER_INSET), 3)
    if onEnter then
        note:EnableMouse(true)
        note:SetScript("OnEnter", onEnter)
        note:SetScript("OnLeave", GameTooltip_Hide)
    end
    return note
end

-------------------------------------------------------------------------------
--  A module's card at the top of its settings page: the logo, a line or two on where you
--  stand, and the button that opens its window.
-------------------------------------------------------------------------------
local CARD_H, CARD_PAD, CARD_ICON = 76, 16, 52
local CARD_BUTTON_W, CARD_BUTTON_H, CARD_LINE_GAP = 190, 30, 6
local HEADLINE_SIZE, DETAIL_SIZE = 15, 12

function Parts.SettingsCardFrame(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(CARD_H)
    ns.Solid(card, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(card, BORDER_RGB)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(CARD_ICON, CARD_ICON)
    card.icon:SetPoint("LEFT", CARD_PAD, 0)
    card.icon:SetTexture(LOGO, nil, nil, "TRILINEAR")
    -- ns.Button calls its click with no arguments, so the card is held here, once.
    card.open = ns.AccentBorder(ns.Button(card, "", CARD_BUTTON_W, CARD_BUTTON_H, function()
        ns.OpenFromOptions(card.onOpen)
    end))
    card.open:SetPoint("RIGHT", -CARD_PAD, 0)
    card.headline = ns.Font(card, HEADLINE_SIZE, nil, T.fg)
    card.detail = ns.Font(card, DETAIL_SIZE, nil, T.muted)
    for _, line in ipairs({ card.headline, card.detail }) do
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
    end
    return card
end

---@param detail? string a second, muted line
function Parts.PaintSettingsCard(card, buttonText, onOpen, headline, detail)
    card.onOpen = onOpen
    card.open:SetShown(onOpen ~= nil)
    if onOpen then ns.SetButtonText(card.open, buttonText) end
    card.headline:SetText(headline)
    card.detail:SetText(detail or "")
    card.detail:SetShown(detail ~= nil)
    -- One line, or two, as a block centred beside the logo.
    local height = detail and HEADLINE_SIZE + CARD_LINE_GAP + DETAIL_SIZE or HEADLINE_SIZE
    local right, rightPoint, rightX = card.open, "LEFT", -CARD_PAD
    if not onOpen then right, rightPoint, rightX = card, "RIGHT", -CARD_PAD end
    card.headline:ClearAllPoints()
    card.headline:SetPoint("TOPLEFT", card.icon, "RIGHT", CARD_PAD, height / 2)
    card.headline:SetPoint("RIGHT", right, rightPoint, rightX, 0)
    card.detail:ClearAllPoints()
    card.detail:SetPoint("TOPLEFT", card.headline, "BOTTOMLEFT", 0, -CARD_LINE_GAP)
    card.detail:SetPoint("RIGHT", right, rightPoint, rightX, 0)
    return CARD_H
end

function Parts.SettingsCard(parent, y, key, buttonText, onOpen, headline, detail)
    local UI = ns.UI
    if UI.searchScan then return y - CARD_H - CARD_PAD end
    local card = UI.Keep(parent, key, Parts.SettingsCardFrame)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y - CARD_PAD)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y - CARD_PAD)
    Parts.PaintSettingsCard(card, buttonText, onOpen, headline, detail)
    return y - CARD_H - CARD_PAD
end
