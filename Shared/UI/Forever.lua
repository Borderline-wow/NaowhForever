-- Forever.lua: the Forever skin's parts (ns.Shared.Parts), each on the game's own art when this client has it and drawn from the house tokens when it does not.
local ns = _G.NaowhForever
local Parts = ns.Shared.Parts
local St = ns.Shared.Style

local BLACK = St.BORDER_RGB
local WHITE = St.FOREVER_VALUE_RGB
local GOLD = St.FOREVER_GOLD_RGB
local YELLOW = St.FOREVER_CHECK_RGB
local TEXT_ADDON = "Naowh Forever"
local TEXT_PLUS, TEXT_MINUS = "+", "-"
local FRAME_RINGS = { BLACK, St.FOREVER_BRONZE_DARK_RGB, St.FOREVER_BRONZE_RGB, St.FOREVER_BRONZE_DEEP_RGB, BLACK }
local SWATCH_RINGS = { St.FOREVER_SWATCH_RIM_RGB, BLACK }
local TIP_RINGS = { YELLOW, YELLOW, BLACK }
local CLOSE_ATLASES = { St.FOREVER_CLOSE_ATLAS.normal, St.FOREVER_CLOSE_ATLAS.pushed, St.FOREVER_CLOSE_ATLAS.highlight }
local TAB_ATLASES = { St.FOREVER_TAB_ATLAS.left, St.FOREVER_TAB_ATLAS.middle, St.FOREVER_TAB_ATLAS.right,
    St.FOREVER_ACTIVE_TAB_ATLAS.left, St.FOREVER_ACTIVE_TAB_ATLAS.middle, St.FOREVER_ACTIVE_TAB_ATLAS.right }
local SIDE_ATLASES = { St.FOREVER_SIDE_TAB_ATLAS.normal, St.FOREVER_SIDE_TAB_ATLAS.selected,
    St.FOREVER_SIDE_TAB_ATLAS.hover, St.FOREVER_SIDE_TAB_ATLAS.mask }
local SEARCH_ATLASES = { St.FOREVER_SEARCH_ATLAS.left, St.FOREVER_SEARCH_ATLAS.middle, St.FOREVER_SEARCH_ATLAS.right }
local SIGN_ATLASES = { St.FOREVER_PLUS_ATLAS, St.FOREVER_MINUS_ATLAS }
local TITLE_SUBLEVEL = 7
local PORTRAIT_ART = { logo = 0.94, glow = 0.7, glowAlpha = 0.45, shade = 1, shadeAlpha = 0.55 }
local SIDE_ICON_X = -4
local KNOB_RAISE = 2
local KNOB_EDGE = 2
local RING_EDGE = 1
local RING_LAYERS = { black = 0, bronze = 1, deep = 2 }
local KNOB_EDGE_SUBLEVEL = -1
local FILL_ALPHA = 0.6
local CHEVRON_DOWN = -math.pi / 2
local CHEVRON_UP = math.pi / 2
local PICK_SUBLEVEL = 1
local RAIL_SUBLEVEL = 1
local RED_RIM_INSET = 1
local RED_NORMAL, RED_PRESSED, RED_DISABLED = 1, 2, 3
local RED_NAMES, RED_ATLASES = {}, { St.FOREVER_RED_BUTTON_ATLAS.highlight }
for i, suffix in ipairs(St.FOREVER_RED_BUTTON_STATES) do
    local atlas = St.FOREVER_RED_BUTTON_ATLAS
    RED_NAMES[i] = { atlas.left .. suffix, atlas.center .. suffix, atlas.right .. suffix }
    for _, name in ipairs(RED_NAMES[i]) do RED_ATLASES[#RED_ATLASES + 1] = name end
end

local HIGHLIGHT, SELECTED = "highlight", "selected"
local SELECTION_SLOTS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
    "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local SELECTION_OUT = St.FOREVER_SELECTION_OUT
local SELECTION_PIECES = St.FOREVER_SELECTION_PIECES
local SELECTION_LAYOUT = {
    TopLeftCorner = { atlas = SELECTION_PIECES.corner, mirrorLayout = true, x = -SELECTION_OUT, y = SELECTION_OUT },
    TopRightCorner = { atlas = SELECTION_PIECES.corner, mirrorLayout = true, x = SELECTION_OUT, y = SELECTION_OUT },
    BottomLeftCorner = { atlas = SELECTION_PIECES.corner, mirrorLayout = true, x = -SELECTION_OUT, y = -SELECTION_OUT },
    BottomRightCorner = { atlas = SELECTION_PIECES.corner, mirrorLayout = true, x = SELECTION_OUT, y = -SELECTION_OUT },
    TopEdge = { atlas = SELECTION_PIECES.top },
    BottomEdge = { atlas = SELECTION_PIECES.bottom },
    LeftEdge = { atlas = SELECTION_PIECES.left },
    RightEdge = { atlas = SELECTION_PIECES.right },
    Center = { atlas = SELECTION_PIECES.center, x = -SELECTION_OUT, y = SELECTION_OUT, x1 = SELECTION_OUT,
        y1 = -SELECTION_OUT },
}
local SELECTION_ATLASES = {}
for _, kit in pairs(St.FOREVER_SELECTION_KIT) do
    for _, piece in pairs(SELECTION_PIECES) do SELECTION_ATLASES[#SELECTION_ATLASES + 1] = piece:format(kit) end
end

local known = {}
local redInfo = {}
local gradients = {}
local lightColors

local function HasAtlas(name)
    local ok = known[name]
    if ok == nil then
        ok = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
        known[name] = ok
    end
    return ok
end

local function HasAtlases(names)
    for i = 1, #names do
        if not HasAtlas(names[i]) then return false end
    end
    return true
end

local function Atlas(texture, name, useSize)
    if not HasAtlas(name) then return false end
    texture:SetAtlas(name, useSize)
    return true
end

local function Layout(container, name, atlases)
    if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName and HasAtlases(atlases)) then return false end
    NineSliceUtil.ApplyLayoutByName(container, name)
    return true
end

local function Colors(pair)
    local made = gradients[pair]
    if not made then
        local top, bottom = pair[1], pair[2]
        made = { CreateColor(top.r, top.g, top.b, 1), CreateColor(bottom.r, bottom.g, bottom.b, 1) }
        gradients[pair] = made
    end
    return made
end

local function Gradient(texture, pair, flipped)
    local made = Colors(pair)
    texture:SetColorTexture(1, 1, 1, 1)
    if flipped then
        texture:SetGradient("VERTICAL", made[1], made[2])
    else
        texture:SetGradient("VERTICAL", made[2], made[1])
    end
end

local function Fill(frame, pair, layer, sublevel)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    texture:SetAllPoints()
    Gradient(texture, pair)
    return texture
end

local function Rings(frame, colors)
    local borders = {}
    for i, color in ipairs(colors) do
        local ring = CreateFrame("Frame", nil, frame)
        ns.PixelInset(ring, -i, frame)
        borders[i] = ns.Border(ring, color)
    end
    return borders
end

local function Rim(frame, color, parent)
    local ring = CreateFrame("Frame", nil, parent or frame)
    ns.PixelInset(ring, -1, frame)
    return ns.Border(ring, color)
end

local function Paint(border, color)
    border:SetColor(color.r, color.g, color.b, 1)
end

local function Round(parent, layer, size, color, sublevel)
    local dot = parent:CreateTexture(nil, layer, nil, sublevel)
    dot:SetTexture(St.ROUND, nil, nil, "TRILINEAR")
    dot:SetSize(size, size)
    dot:SetVertexColor(color.r, color.g, color.b, 1)
    return dot
end

local function Tint(texture, color)
    texture:SetVertexColor(color.r, color.g, color.b, 1)
end

Parts.ForeverAtlas = Atlas
Parts.ForeverGradient = Gradient
Parts.ForeverRim = Rim

local function Title(chrome, text, left)
    local title = ns.Font(chrome, St.FOREVER_TITLE_SIZE, nil, GOLD, true)
    title:SetDrawLayer("OVERLAY", TITLE_SUBLEVEL)
    title:SetPoint("TOP", chrome, "TOP", 0, -St.FOREVER_TITLE_Y)
    title:SetPoint("LEFT", chrome, "LEFT", left, 0)
    title:SetPoint("RIGHT", chrome, "RIGHT", -St.FOREVER_TITLE_RIGHT, 0)
    title:SetWordWrap(false)
    title:SetText(text or TEXT_ADDON)
    return title
end

local function Portrait(chrome, drawn)
    local holder = CreateFrame("Frame", nil, chrome)
    holder:SetFrameLevel(chrome:GetFrameLevel() + St.FOREVER_PORTRAIT_LEVEL)
    holder:SetSize(St.FOREVER_PORTRAIT, St.FOREVER_PORTRAIT)
    holder:SetPoint("TOPLEFT", chrome, "TOPLEFT", St.FOREVER_PORTRAIT_X, St.FOREVER_PORTRAIT_Y)
    local disc = St.FOREVER_PORTRAIT - 2 * St.FOREVER_MASK_IN
    local middle = CreateFrame("Frame", nil, holder)
    middle:SetSize(disc, St.FOREVER_PORTRAIT - St.FOREVER_MASK_DROP)
    middle:SetPoint("TOPLEFT", St.FOREVER_MASK_IN, 0)
    if drawn then
        local ring = St.FOREVER_PORTRAIT_RING
        Round(middle, "BACKGROUND", disc + 2 * ring, BLACK, RING_LAYERS.black):SetPoint("CENTER")
        Round(middle, "BACKGROUND", disc + 2 * (ring - RING_EDGE), St.FOREVER_BRONZE_RGB, RING_LAYERS.bronze):SetPoint("CENTER")
        Round(middle, "BACKGROUND", disc + 2 * RING_EDGE, St.FOREVER_BRONZE_DEEP_RGB, RING_LAYERS.deep):SetPoint("CENTER")
    end
    holder.disc = Round(middle, "ARTWORK", disc, St.FOREVER_PORTRAIT_RGB)
    holder.disc:SetPoint("CENTER")
    holder.glow = Round(middle, "ARTWORK", disc * PORTRAIT_ART.glow, St.FOREVER_PORTRAIT_GLOW_RGB, 1)
    holder.glow:SetAlpha(PORTRAIT_ART.glowAlpha)
    holder.glow:SetPoint("CENTER")
    holder.logo = middle:CreateTexture(nil, "OVERLAY")
    holder.logo:SetTexture(St.LOGO, nil, nil, "TRILINEAR")
    holder.logo:SetSize(disc * PORTRAIT_ART.logo, disc * PORTRAIT_ART.logo)
    holder.logo:SetPoint("CENTER")
    holder.shade = middle:CreateTexture(nil, "OVERLAY", nil, 1)
    holder.shade:SetTexture(St.RING, nil, nil, "TRILINEAR")
    holder.shade:SetSize(disc * PORTRAIT_ART.shade, disc * PORTRAIT_ART.shade)
    holder.shade:SetVertexColor(BLACK.r, BLACK.g, BLACK.b, PORTRAIT_ART.shadeAlpha)
    holder.shade:SetPoint("CENTER")
    holder.middle = middle
    return holder
end

local function CloseClicked(close)
    if close.onClose then return close.onClose() end
    close.window:Hide()
end

local function Close(chrome, window, onClose)
    local close = CreateFrame("Button", nil, chrome)
    close:SetSize(St.FOREVER_CLOSE, St.FOREVER_CLOSE)
    close:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", St.FOREVER_CLOSE_X, St.FOREVER_CLOSE_Y)
    close.window, close.onClose = window, onClose
    close:SetScript("OnClick", CloseClicked)
    local atlas = St.FOREVER_CLOSE_ATLAS
    if HasAtlases(CLOSE_ATLASES) then
        close:SetNormalAtlas(atlas.normal)
        close:SetPushedAtlas(atlas.pushed)
        close:SetHighlightAtlas(atlas.highlight, "ADD")
        close.art = true
        return close
    end
    Fill(close, St.FOREVER_CLOSE_RGB)
    ns.Border(close, BLACK)
    Rim(close, St.FOREVER_BRONZE_RGB)
    close.cross = close:CreateTexture(nil, "ARTWORK")
    close.cross:SetTexture(St.CROSS, nil, nil, "TRILINEAR")
    close.cross:SetSize(St.FOREVER_CLOSE_GLYPH, St.FOREVER_CLOSE_GLYPH)
    close.cross:SetPoint("CENTER")
    Tint(close.cross, YELLOW)
    return close
end

local function DragStart(strip)
    strip.window:StartMoving()
end

local function DragStop(strip)
    local window = strip.window
    local stop = window:GetScript("OnDragStop")
    if stop then stop(window) else window:StopMovingOrSizing() end
end

local function Strip(chrome, window)
    local strip = CreateFrame("Frame", nil, chrome)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT", -St.FOREVER_TITLE_RIGHT, 0)
    strip:SetHeight(St.FOREVER_TITLE_H)
    strip.window = window
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", DragStart)
    strip:SetScript("OnDragStop", DragStop)
    return strip
end

function Parts.ForeverFrame(window, opts)
    local bare = opts and opts.bare
    local chrome = CreateFrame("Frame", nil, window)
    chrome:SetPoint("TOPLEFT", window, "TOPLEFT", -St.FOREVER_SIDE, St.FOREVER_TITLE_H)
    chrome:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", St.FOREVER_SIDE, -St.FOREVER_SIDE)
    chrome:SetFrameLevel(window:GetFrameLevel() + St.FOREVER_CHROME_LEVEL)
    chrome.bar = chrome:CreateTexture(nil, "BACKGROUND")
    chrome.bar:SetPoint("TOPLEFT")
    chrome.bar:SetPoint("TOPRIGHT")
    chrome.bar:SetHeight(St.FOREVER_TITLE_H)
    Gradient(chrome.bar, St.FOREVER_TITLE_BAR_RGB)
    if bare then
        chrome.art = Layout(chrome, St.FOREVER_BARE_LAYOUT, St.FOREVER_BARE_ATLASES)
    else
        chrome.art = Layout(chrome, St.FOREVER_FRAME_LAYOUT, St.FOREVER_FRAME_ATLASES)
    end
    if not chrome.art then
        chrome.rings = Rings(chrome, FRAME_RINGS)
        chrome.rule = ns.Solid(chrome, "ARTWORK", St.FOREVER_BRONZE_DARK_RGB, 1)
        chrome.rule:SetPoint("TOPLEFT", chrome.bar, "BOTTOMLEFT")
        chrome.rule:SetPoint("TOPRIGHT", chrome.bar, "BOTTOMRIGHT")
        ns.Hairline(chrome.rule, "h")
    end
    chrome.title = Title(chrome, opts and opts.title, bare and St.FOREVER_TITLE_RIGHT or St.FOREVER_TITLE_LEFT)
    if not bare then chrome.portrait = Portrait(chrome, not chrome.art) end
    chrome.strip = Strip(chrome, window)
    chrome.close = Close(chrome, window, opts and opts.onClose)
    window.forever = chrome
    return chrome
end

function Parts.ForeverInset(parent)
    local inset = CreateFrame("Frame", nil, parent)
    inset:SetFrameLevel(parent:GetFrameLevel())
    inset.fill = inset:CreateTexture(nil, "BACKGROUND")
    inset.fill:SetAllPoints()
    local c = St.FOREVER_INSET_RGB
    inset.fill:SetColorTexture(c.r, c.g, c.b, 1)
    inset.art = Layout(inset, St.FOREVER_INSET_LAYOUT, St.FOREVER_INSET_ATLASES)
    if not inset.art then
        ns.Border(inset, BLACK)
        inset.rim = Rim(inset, St.FOREVER_INSET_RIM_RGB)
    end
    return inset
end

function Parts.ForeverBox(frame, color)
    return Rim(frame, color or St.FOREVER_BAR_RIM_RGB)
end

local function RedInfo(name)
    local info = redInfo[name]
    if not info then
        info = C_Texture.GetAtlasInfo(name)
        redInfo[name] = info
    end
    return info
end

local function RedCap(texture, name, height, width)
    local info = RedInfo(name)
    local full = info.width * height / info.height
    local share = full > 0 and math.min(1, width / full) or 1
    texture:SetWidth(full * share)
    return share
end

local function FitRed(frame)
    local art = frame.redArt
    if not art then return end
    local h, w = frame:GetHeight(), frame:GetWidth()
    local names = St.FOREVER_RED_BUTTON_ATLAS
    local half = w / 2
    local left = RedCap(art[1], names.left, h, half)
    local right = RedCap(art[3], names.right, h, half)
    art[1]:SetTexCoord(0, left, 0, 1)
    art[3]:SetTexCoord(1 - right, 1, 0, 1)
end

local function RedState(frame)
    if frame.IsEnabled and not frame:IsEnabled() then return RED_DISABLED end
    if frame._pressed or frame._latched then return RED_PRESSED end
    return RED_NORMAL
end

local function PaintRed(frame)
    local state = RedState(frame)
    local art = frame.redArt
    if art then
        if frame._redState == state then return end
        frame._redState = state
        local names = RED_NAMES[state]
        art[1]:SetAtlas(names[1])
        art[2]:SetAtlas(names[2])
        art[3]:SetAtlas(names[3])
        return FitRed(frame)
    end
    local pair = St.FOREVER_RED_RGB
    if state == RED_DISABLED then
        pair = St.FOREVER_RED_DISABLED_RGB
    elseif frame._hover then
        pair = St.FOREVER_RED_HOVER_RGB
    end
    Gradient(frame.redFill, pair, state == RED_PRESSED)
end

local function RedPiece(frame)
    local piece = frame:CreateTexture(nil, "BACKGROUND")
    piece:SetPoint("TOP")
    piece:SetPoint("BOTTOM")
    return piece
end

local function RedArt(frame, fill, edge)
    if HasAtlases(RED_ATLASES) then
        local left, middle, right = RedPiece(frame), RedPiece(frame), RedPiece(frame)
        left:SetPoint("LEFT")
        right:SetPoint("RIGHT")
        middle:SetPoint("LEFT", left, "RIGHT")
        middle:SetPoint("RIGHT", right, "LEFT")
        middle:SetHorizTile(true)
        frame.redArt = { left, middle, right }
        if fill then fill:Hide() end
        return true
    end
    frame.redFill = fill or Fill(frame, St.FOREVER_RED_RGB)
    local ring = CreateFrame("Frame", nil, edge or frame)
    ns.PixelInset(ring, RED_RIM_INSET, frame)
    frame.redRim = ns.Border(ring, St.FOREVER_BRONZE_RGB)
    return false
end

function Parts.ForeverButtonArt(frame)
    local art = RedArt(frame)
    if not art then ns.Border(frame, BLACK) end
    PaintRed(frame)
    return art
end

local function LabelColor(btn, color)
    btn.label:SetTextColor(color.r, color.g, color.b, 1)
end

local function Unlight(btn)
    local c = btn._litFrom
    if not c then return end
    btn._litFrom = nil
    btn.label:SetTextColor(c[1], c[2], c[3], c[4])
end

local function ButtonEnter(btn)
    if not btn:IsEnabled() then return end
    btn._hover = true
    PaintRed(btn)
    if btn._litFrom then return end
    btn._litFrom = { btn.label:GetTextColor() }
    LabelColor(btn, WHITE)
end

local function ButtonLeave(btn)
    btn._hover = nil
    PaintRed(btn)
    Unlight(btn)
end

local function ButtonDown(btn)
    if not btn:IsEnabled() then return end
    btn._pressed = true
    PaintRed(btn)
end

local function ButtonUp(btn)
    btn._pressed = nil
    PaintRed(btn)
end

local function ButtonDisable(btn)
    Unlight(btn)
    btn._hover, btn._pressed = nil, nil
    PaintRed(btn)
    if btn._greyFrom then return end
    btn._greyFrom = { btn.label:GetTextColor() }
    LabelColor(btn, St.FOREVER_DISABLED_TEXT_RGB)
end

local function ButtonEnable(btn)
    PaintRed(btn)
    local c = btn._greyFrom
    if not c then return end
    btn._greyFrom = nil
    btn.label:SetTextColor(c[1], c[2], c[3], c[4])
end

local function PickedEdge(border, r, g, b, a)
    border._plainSetColor(border, r, g, b, a)
    border._frame:SetShown(r ~= BLACK.r or g ~= BLACK.g or b ~= BLACK.b)
end

function Parts.ForeverButton(btn, bg, border, lbl)
    btn._forever = true
    if RedArt(btn, bg, border._frame) then
        btn._art = btn.redArt
        btn:SetHighlightAtlas(St.FOREVER_RED_BUTTON_ATLAS.highlight, "ADD")
        border._plainSetColor = border.SetColor
        border.SetColor = PickedEdge
        border._frame:Hide()
    end
    LabelColor(btn, GOLD)
    btn:SetScript("OnEnter", ButtonEnter)
    btn:SetScript("OnLeave", ButtonLeave)
    btn:SetScript("OnMouseDown", ButtonDown)
    btn:SetScript("OnMouseUp", ButtonUp)
    btn:HookScript("OnHide", ButtonUp)
    btn:HookScript("OnSizeChanged", FitRed)
    btn:SetScript("OnDisable", ButtonDisable)
    btn:SetScript("OnEnable", ButtonEnable)
    PaintRed(btn)
    return btn
end

function Parts.SetForeverLatched(btn, on)
    btn._latched = on or nil
    PaintRed(btn)
end

function Parts.ForeverField(box)
    box._rim = Rim(box, St.FOREVER_FIELD_RIM_RGB)
    return box._rim
end

function Parts.ForeverSearch(box, fill, icon)
    local atlas = St.FOREVER_SEARCH_ATLAS
    if not HasAtlases(SEARCH_ATLASES) then
        local c = St.FOREVER_FIELD_RGB
        fill:SetColorTexture(c.r, c.g, c.b, 1)
        if box._rim then Paint(box._rim, St.FOREVER_SEARCH_RIM_RGB) end
        return false
    end
    fill:Hide()
    if box._fill then box._fill:Hide() end
    if box.border then box.border._frame:Hide() end
    if box._rim then box._rim._frame:Hide() end
    local left = box:CreateTexture(nil, "BACKGROUND")
    Atlas(left, atlas.left)
    left:SetWidth(St.FOREVER_SEARCH_CAP)
    left:SetPoint("TOPLEFT", St.FOREVER_SEARCH_CAP_X, 0)
    left:SetPoint("BOTTOMLEFT", St.FOREVER_SEARCH_CAP_X, 0)
    local right = box:CreateTexture(nil, "BACKGROUND")
    Atlas(right, atlas.right)
    right:SetWidth(St.FOREVER_SEARCH_CAP)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    local middle = box:CreateTexture(nil, "BACKGROUND")
    Atlas(middle, atlas.middle)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    if icon and Atlas(icon, atlas.icon) then icon:SetVertexColor(1, 1, 1, 1) end
    box.foreverArt = { left, middle, right }
    return true
end

local function TabPieces(button, atlas, leftX, rightX)
    local pieces = {}
    for i, name in ipairs({ atlas.left, atlas.middle, atlas.right }) do
        local piece = button:CreateTexture(nil, "BACKGROUND")
        Atlas(piece, name, true)
        piece:SetTexCoord(0, 1, 1, St.FOREVER_TOP_TAB_CROP)
        piece:SetHeight(piece:GetHeight() * St.FOREVER_TOP_TAB_SHARE)
        if i ~= 2 then piece:SetWidth(piece:GetWidth() * St.FOREVER_TOP_TAB_SHARE) end
        pieces[i] = piece
    end
    local left, middle, right = pieces[1], pieces[2], pieces[3]
    left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", leftX, 0)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", rightX, 0)
    middle:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return pieces
end

local function ShowPieces(pieces, shown)
    for i = 1, #pieces do pieces[i]:SetShown(shown) end
end

function Parts.ForeverTab(button)
    if HasAtlases(TAB_ATLASES) then
        button.idleArt = TabPieces(button, St.FOREVER_TAB_ATLAS, St.FOREVER_TAB_LEFT_X, St.FOREVER_TAB_RIGHT_X)
        button.activeArt = TabPieces(button, St.FOREVER_ACTIVE_TAB_ATLAS, St.FOREVER_ACTIVE_LEFT_X,
            St.FOREVER_ACTIVE_RIGHT_X)
        button.fill:SetColorTexture(0, 0, 0, 0)
        button.line:SetColorTexture(0, 0, 0, 0)
        local idle = button.idleArt
        button.capRoom = math.max((idle[1]:GetWidth() or 0) + (idle[3]:GetWidth() or 0), 2 * St.FOREVER_TAB_PAD)
        button.text:ClearAllPoints()
        button.text:SetPoint("CENTER", idle[2], "CENTER", 0, St.FOREVER_TAB_TEXT_Y)
        return true
    end
    button.capRoom = 2 * St.FOREVER_TAB_PAD
    button.idleFill = Fill(button, St.FOREVER_TAB_RGB, "BACKGROUND")
    Gradient(button.fill, St.FOREVER_TAB_ACTIVE_RGB)
    local rim = St.FOREVER_PICK_RIM_RGB
    button.line:SetColorTexture(rim.r, rim.g, rim.b, 1)
    button.line:ClearAllPoints()
    button.line:SetPoint("TOPLEFT")
    button.line:SetPoint("TOPRIGHT")
    return false
end

function Parts.PaintForeverTab(button, on)
    if button.idleArt then
        ShowPieces(button.idleArt, not on)
        ShowPieces(button.activeArt, on)
    end
    local c = on and St.FOREVER_TAB_ON_RGB or St.FOREVER_MUTED_RGB
    button.text:SetTextColor(c.r, c.g, c.b)
end

function Parts.ForeverSideTab(parent, iconName, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    local path = St.CLASSIC_ICONS[iconName]
    if path then tab.icon:SetTexture(St.CLASSIC_ICON_PATH .. path) end
    local atlas = St.FOREVER_SIDE_TAB_ATLAS
    if HasAtlases(SIDE_ATLASES) then
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        Atlas(bg, atlas.normal, true)
        bg:SetPoint("CENTER")
        tab:SetSize(bg:GetWidth(), bg:GetHeight() - St.FOREVER_SIDE_TAB_TRIM)
        tab.selected = tab:CreateTexture(nil, "OVERLAY")
        Atlas(tab.selected, atlas.selected, true)
        tab.selected:SetPoint("CENTER")
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        Atlas(hover, atlas.hover, true)
        hover:SetPoint("CENTER")
        local mask = tab:CreateMaskTexture()
        Atlas(mask, atlas.mask, true)
        mask:SetPoint("CENTER", SIDE_ICON_X, 0)
        tab.icon:SetAllPoints(mask)
        tab.icon:AddMaskTexture(mask)
        tab.art = true
    else
        tab:SetSize(St.FOREVER_SIDE_TAB, St.FOREVER_SIDE_TAB)
        ns.Solid(tab, "BACKGROUND", St.FOREVER_SIDE_RGB, 1):SetAllPoints()
        ns.Border(tab, BLACK)
        tab.rim = Rim(tab, St.FOREVER_SWATCH_RIM_RGB)
        tab.selected = tab:CreateTexture(nil, "OVERLAY")
        tab.selected:SetAllPoints()
        tab.selected:SetTexture(St.FOREVER_HIGHLIGHT)
        tab.selected:SetBlendMode("ADD")
        tab.selected:SetAlpha(St.FOREVER_GLOW_ALPHA)
        tab.icon:SetSize(St.FOREVER_SIDE_TAB_ICON, St.FOREVER_SIDE_TAB_ICON)
        tab.icon:SetPoint("CENTER")
        local crop = St.CLASSIC_ICON_CROP
        tab.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    end
    tab.selected:Hide()
    tab:SetScript("OnClick", onClick)
    return tab
end

function Parts.SetForeverSideTab(tab, on)
    tab.selected:SetShown(on)
    if tab.rim then Paint(tab.rim, on and YELLOW or St.FOREVER_SWATCH_RIM_RGB) end
end

local function BarArt(bar, gap)
    bar.barArt = bar:CreateTexture(nil, "BACKGROUND")
    bar.barArt:SetPoint("TOPLEFT", 0, -gap)
    bar.barArt:SetPoint("BOTTOMRIGHT", 0, gap)
    local hover = bar:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(bar.barArt)
    hover:SetBlendMode("ADD")
    hover:SetAlpha(St.FOREVER_HIGHLIGHT_ALPHA)
    if Atlas(bar.barArt, St.FOREVER_BAR_ATLAS) then
        Atlas(hover, St.FOREVER_BAR_ATLAS)
        bar.art = true
        return
    end
    Gradient(bar.barArt, St.FOREVER_BAR_RGB)
    hover:SetTexture(St.FOREVER_HIGHLIGHT)
    local edge = CreateFrame("Frame", nil, bar)
    edge:SetAllPoints(bar.barArt)
    ns.Border(edge, BLACK)
    bar.barRim = Rim(edge, St.FOREVER_BAR_RIM_RGB)
end

function Parts.ForeverBar(bar)
    BarArt(bar, 0)
    bar.sign = bar:CreateTexture(nil, "ARTWORK")
    bar.sign:SetSize(St.FOREVER_SIGN, St.FOREVER_SIGN)
    bar.signText = ns.Font(bar, St.FOREVER_SIGN_SIZE, nil, GOLD, true)
    bar.signText:SetPoint("CENTER", bar.sign)
    bar.signArt = HasAtlases(SIGN_ATLASES)
    if bar.signArt then
        bar.signGlow = bar:CreateTexture(nil, "HIGHLIGHT")
        bar.signGlow:SetPoint("CENTER", bar.sign)
        bar.signGlow:SetBlendMode("ADD")
        bar.signGlow:SetAlpha(St.FOREVER_HIGHLIGHT_ALPHA)
    end
    return bar
end

function Parts.PaintForeverBar(bar, open, openable)
    if bar.signArt then
        local name = open and St.FOREVER_MINUS_ATLAS or St.FOREVER_PLUS_ATLAS
        bar.sign:SetAtlas(name, true)
        bar.signGlow:SetAtlas(name, true)
        bar.sign:SetShown(openable)
        bar.signGlow:SetShown(openable)
        bar.signText:Hide()
    else
        bar.sign:Hide()
        bar.signText:SetText(open and TEXT_MINUS or TEXT_PLUS)
        bar.signText:SetShown(openable)
    end
    if bar.art then return end
    Gradient(bar.barArt, open and St.FOREVER_BAR_OPEN_RGB or St.FOREVER_BAR_RGB)
    Paint(bar.barRim, open and St.FOREVER_BRONZE_RGB or St.FOREVER_BAR_RIM_RGB)
end

local function Diamond(pill, point, x)
    local gem = pill:CreateTexture(nil, "OVERLAY")
    gem:SetTexture(St.GEM, nil, nil, "TRILINEAR")
    gem:SetSize(St.FOREVER_PILL_DIAMOND, St.FOREVER_PILL_DIAMOND)
    gem:SetPoint("CENTER", pill, point, x, 0)
    Tint(gem, St.FOREVER_BRONZE_RGB)
    return gem
end

function Parts.ForeverPill(parent, size)
    local pill = CreateFrame("Frame", nil, parent)
    local art = pill:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    if Atlas(art, St.FOREVER_PILL_ATLAS) then
        pill.art = true
    else
        Gradient(art, St.FOREVER_PILL_RGB)
        ns.Border(pill, BLACK)
        Rim(pill, St.FOREVER_PILL_RIM_RGB)
        Diamond(pill, "LEFT", 0)
        Diamond(pill, "RIGHT", 0)
    end
    pill.text = ns.Font(pill, size or St.TEXT_SIZE, nil, St.FOREVER_LIGHT_RGB, true)
    pill.text:SetPoint("CENTER")
    pill.text:SetWordWrap(false)
    return pill
end

function Parts.ForeverBand(row)
    local band = row:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    if not Atlas(band, St.FOREVER_BAND_ATLAS) then band:SetColorTexture(1, 1, 1, St.FOREVER_BAND_ALPHA) end
    band:Hide()
    return band
end

local function Tick(parent, size)
    local tick = parent:CreateTexture(nil, "OVERLAY")
    if tick:SetTexture(St.FOREVER_CHECK) then
        tick:SetSize(size * St.FOREVER_CHECK_SCALE, size * St.FOREVER_CHECK_SCALE)
    else
        tick:SetTexture(St.TICK, nil, nil, "TRILINEAR")
        Tint(tick, YELLOW)
        tick:SetSize(size, size)
    end
    tick:SetPoint("CENTER")
    return tick
end

local function DimCheck(t, off)
    off = off and true or false
    t:SetAlpha(1)
    if t._dimmed == off then return end
    t._dimmed = off
    local alpha = off and St.FOREVER_CHECK_DIM_ALPHA or 1
    if not t.checkArt then
        t.checkBox:SetAlpha(alpha)
        return
    end
    t.checkArt:SetAlpha(alpha)
    local tick = t.checkTick
    if not t.gameTick then
        tick:SetAlpha(alpha)
        return
    end
    local greyed = off and tick:SetTexture(St.FOREVER_CHECK_DISABLED)
    if not greyed then tick:SetTexture(St.FOREVER_CHECK) end
    tick:SetAlpha((off and not greyed) and alpha or 1)
end

function Parts.ForeverCheck(t)
    local s = St.FOREVER_CHECK_SIZE
    t:SetSize(s, s)
    t._dim = DimCheck
    local files = St.FOREVER_CHECKBOX
    local up = t:CreateTexture(nil, "ARTWORK")
    if up:SetTexture(files.up) then
        up:SetAllPoints()
        t:SetNormalTexture(up)
        t:SetPushedTexture(files.down)
        t:SetHighlightTexture(files.highlight, "ADD")
        t.checkArt = up
        local tick = t:CreateTexture(nil, "OVERLAY")
        tick:SetAllPoints()
        t.gameTick = tick:SetTexture(St.FOREVER_CHECK)
        if not t.gameTick then
            tick:SetTexture(St.TICK, nil, nil, "TRILINEAR")
            Tint(tick, YELLOW)
        end
        t.checkTick = tick
        return tick
    end
    up:Hide()
    local drawn = St.FOREVER_CHECK_DRAWN
    local box = CreateFrame("Frame", nil, t)
    box:SetSize(drawn, drawn)
    box:SetPoint("CENTER")
    ns.Solid(box, "BACKGROUND", St.FOREVER_FIELD_RGB, 1):SetAllPoints()
    ns.Border(box, BLACK)
    local rim = Rim(box, St.FOREVER_CHECK_RIM_RGB)
    t.checkBox = box
    t.checkTick = Tick(box, drawn)
    return t.checkTick, rim, St.FOREVER_CHECK_RIM_RGB
end

function Parts.ForeverDropdown(btn, bg, lbl, arrow)
    Gradient(bg, St.FOREVER_FIELD_FILL_RGB)
    Rim(btn, St.FOREVER_FIELD_RIM_RGB)
    lbl:SetTextColor(WHITE.r, WHITE.g, WHITE.b, 1)
    lbl:SetPoint("RIGHT", -(St.FOREVER_ARROW_BUTTON + 2 * St.FOREVER_PILL_PAD), 0)
    arrow:ClearAllPoints()
    arrow:SetPoint("RIGHT", -St.FOREVER_PILL_PAD, 0)
    if Atlas(arrow, St.FOREVER_DROPDOWN_ATLAS) then
        arrow:SetRotation(0)
        arrow:SetVertexColor(1, 1, 1, 1)
        arrow:SetSize(St.FOREVER_ARROW_BUTTON, St.FOREVER_ARROW_BUTTON)
        return true
    end
    local plate = CreateFrame("Frame", nil, btn)
    plate:SetSize(St.FOREVER_ARROW_BUTTON, St.FOREVER_ARROW_BUTTON)
    plate:SetPoint("CENTER", arrow)
    Fill(plate, St.FOREVER_PLATE_RGB)
    ns.Border(plate, BLACK)
    Rim(plate, St.FOREVER_BRONZE_RGB)
    arrow:SetParent(plate)
    arrow:SetDrawLayer("OVERLAY")
    arrow:SetRotation(CHEVRON_DOWN)
    arrow:SetSize(St.FOREVER_ARROW_GLYPH, St.FOREVER_ARROW_GLYPH)
    Tint(arrow, YELLOW)
    btn.arrowPlate = plate
    return false
end

function Parts.ForeverSlider(track, rail, fill, thumb, valBox, thumbSz)
    local field, bronze = St.FOREVER_FIELD_RGB, St.FOREVER_BRONZE_DARK_RGB
    rail:SetColorTexture(field.r, field.g, field.b, 1)
    fill:SetColorTexture(bronze.r, bronze.g, bronze.b, FILL_ALPHA)
    local groove = CreateFrame("Frame", nil, track)
    groove:SetAllPoints(rail)
    ns.Border(groove, BLACK)
    Rim(groove, St.FOREVER_FIELD_RIM_RGB)
    local knob = CreateFrame("Frame", nil, track)
    knob:SetAllPoints()
    knob:SetFrameLevel(groove:GetFrameLevel() + KNOB_RAISE)
    thumb:SetParent(knob)
    if thumb:SetTexture(St.FOREVER_KNOB) then
        thumb:SetVertexColor(1, 1, 1, 1)
        thumb:SetSize(thumbSz * St.FOREVER_KNOB_SCALE, thumbSz * St.FOREVER_KNOB_SCALE)
    else
        thumb:SetTexture(St.ROUND, nil, nil, "TRILINEAR")
        Tint(thumb, St.FOREVER_BRONZE_RGB)
        local edge = knob:CreateTexture(nil, "ARTWORK", nil, KNOB_EDGE_SUBLEVEL)
        edge:SetTexture(St.ROUND, nil, nil, "TRILINEAR")
        Tint(edge, BLACK)
        edge:SetSize(thumbSz + 2 * KNOB_EDGE, thumbSz + 2 * KNOB_EDGE)
        edge:SetPoint("CENTER", thumb)
    end
    Rim(valBox, St.FOREVER_FIELD_RIM_RGB)
    return knob
end

function Parts.ForeverSwatch(swatch)
    return Rings(swatch, SWATCH_RINGS)
end

function Parts.ForeverPick(row)
    local pick = row:CreateTexture(nil, "BACKGROUND", nil, PICK_SUBLEVEL)
    pick:SetAllPoints()
    if pick:SetTexture(St.FOREVER_HIGHLIGHT) then
        pick:SetBlendMode("ADD")
        pick:SetAlpha(St.FOREVER_GLOW_ALPHA)
        Tint(pick, GOLD)
    else
        Gradient(pick, St.FOREVER_NAV_PICK_RGB)
    end
    pick:Hide()
    return pick
end

local function PaintSelectionArt(mover, kit)
    NineSliceUtil.ApplyLayout(mover, SELECTION_LAYOUT, kit)
end

local function GlowPieces(glow)
    for i = 1, #SELECTION_SLOTS do
        local piece = glow[SELECTION_SLOTS[i]]
        if piece then piece:SetBlendMode("ADD") end
    end
end

function Parts.ForeverSelection(mover)
    local glow = CreateFrame("Frame", nil, mover)
    glow:SetAllPoints()
    glow:SetAlpha(St.FOREVER_SELECTION_GLOW_ALPHA)
    glow:Hide()
    mover.editGlow = glow
    if NineSliceUtil and NineSliceUtil.ApplyLayout and HasAtlases(SELECTION_ATLASES) then
        PaintSelectionArt(glow, St.FOREVER_SELECTION_KIT.highlight)
        GlowPieces(glow)
        mover.editArt = true
        return true
    end
    mover.editFill = mover:CreateTexture(nil, "BACKGROUND", nil, PICK_SUBLEVEL)
    mover.editFill:SetAllPoints()
    mover.editEdge = ns.Border(mover, St.FOREVER_SELECTION_EDGE_RGB)
    local lit = glow:CreateTexture(nil, "ARTWORK")
    lit:SetAllPoints()
    local c = St.FOREVER_SELECTION_RGB
    lit:SetColorTexture(c.r, c.g, c.b, 1)
    lit:SetBlendMode("ADD")
    return false
end

function Parts.PaintForeverSelection(mover, selected, hovered)
    local state = selected and SELECTED or HIGHLIGHT
    if mover.editState ~= state then
        mover.editState = state
        if mover.editArt then
            PaintSelectionArt(mover, St.FOREVER_SELECTION_KIT[state])
        else
            local fill = selected and St.FOREVER_SELECTED_RGB or St.FOREVER_SELECTION_RGB
            mover.editFill:SetColorTexture(fill.r, fill.g, fill.b, St.FOREVER_SELECTION_ALPHA)
            Paint(mover.editEdge, selected and St.FOREVER_SELECTED_EDGE_RGB or St.FOREVER_SELECTION_EDGE_RGB)
        end
    end
    mover.editGlow:SetShown(hovered and true or false)
end

function Parts.ForeverTip(card)
    Fill(card, St.FOREVER_TIP_RGB)
    ns.Border(card, BLACK)
    Rings(card, TIP_RINGS)
    card.arrow = card:CreateTexture(nil, "OVERLAY")
    card.arrow:SetSize(St.FOREVER_TIP_ARROW_W, St.FOREVER_TIP_ARROW_H)
    card.arrow:SetPoint("TOP", card, "BOTTOM", 0, -St.FOREVER_TIP_EDGE)
    if card.arrow:SetTexture(St.FOREVER_TIP_ARROW) then
        local c = St.FOREVER_TIP_ARROW_COORDS
        card.arrow:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        card.arrow:SetTexture(St.ARROW, nil, nil, "TRILINEAR")
        card.arrow:SetRotation(CHEVRON_DOWN)
        card.arrow:SetSize(St.FOREVER_TIP_ARROW_H, St.FOREVER_TIP_ARROW_H)
        Tint(card.arrow, YELLOW)
    end
    card.arrow:Hide()
    return card
end

function Parts.ForeverNavButton(btn)
    BarArt(btn, St.FOREVER_BAR_GAP)
    btn.forever = true
    btn.fill:ClearAllPoints()
    btn.fill:SetAllPoints(btn.barArt)
    btn.fill:SetDrawLayer("BACKGROUND", PICK_SUBLEVEL)
    btn.marker:SetColorTexture(0, 0, 0, 0)
    if not btn.art then
        Gradient(btn.barArt, St.FOREVER_NAV_RGB)
        Gradient(btn.fill, St.FOREVER_NAV_PICK_RGB)
        return btn
    end
    local shade = St.FOREVER_LEAF_SHADE
    btn.barArt:SetVertexColor(shade, shade, shade, 1)
    Atlas(btn.fill, St.FOREVER_BAR_ATLAS)
    btn.fill:SetVertexColor(1, 1, 1, 1)
    btn.pickEdge = CreateFrame("Frame", nil, btn)
    btn.pickEdge:SetAllPoints(btn.barArt)
    ns.Border(btn.pickEdge, St.FOREVER_PICK_RIM_RGB)
    btn.pickEdge:Hide()
    return btn
end

function Parts.PaintForeverNav(btn, active)
    if btn.barRim then Paint(btn.barRim, active and St.FOREVER_PICK_RIM_RGB or St.FOREVER_BAR_RIM_RGB) end
    if btn.pickEdge then btn.pickEdge:SetShown(active) end
end

local function ArrowClicked(arrow)
    local scroll = arrow.scroll
    local wheel = scroll:GetScript("OnMouseWheel")
    if wheel then wheel(scroll, arrow.delta) end
end

local function ArrowGlyph(arrow, layer, color)
    local glyph = arrow:CreateTexture(nil, layer)
    glyph:SetAllPoints()
    glyph:SetTexture(St.ARROW, nil, nil, "TRILINEAR")
    glyph:SetRotation(arrow.delta > 0 and CHEVRON_UP or CHEVRON_DOWN)
    Tint(glyph, color)
    return glyph
end

local function ScrollArrow(bar, scroll, delta)
    local arrow = CreateFrame("Button", nil, bar)
    arrow:SetSize(St.FOREVER_SCROLL_ARROW, St.FOREVER_SCROLL_ARROW)
    arrow.scroll, arrow.delta = scroll, delta
    arrow.glyph = ArrowGlyph(arrow, "ARTWORK", St.FOREVER_BRONZE_RGB)
    ArrowGlyph(arrow, "HIGHLIGHT", GOLD)
    arrow:SetScript("OnClick", ArrowClicked)
    return arrow
end

function Parts.ForeverScrollArrows(bar, scroll, gap)
    local room = St.FOREVER_SCROLL_ARROW + St.FOREVER_SCROLL_ARROW_GAP
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", gap, -room)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", gap, room)
    bar.up = ScrollArrow(bar, scroll, 1)
    bar.up:SetPoint("BOTTOM", bar, "TOP", 0, St.FOREVER_SCROLL_ARROW_GAP)
    bar.down = ScrollArrow(bar, scroll, -1)
    bar.down:SetPoint("TOP", bar, "BOTTOM", 0, -St.FOREVER_SCROLL_ARROW_GAP)
    return bar
end

function Parts.ForeverRail(parent, vertical)
    local rail = CreateFrame("Frame", nil, parent)
    local edge = St.FOREVER_RAIL_EDGE
    ns.Solid(rail, "ARTWORK", BLACK, 1):SetAllPoints()
    local bronze = St.FOREVER_BRONZE_RGB
    rail.core = rail:CreateTexture(nil, "ARTWORK", nil, RAIL_SUBLEVEL)
    rail.core:SetColorTexture(bronze.r, bronze.g, bronze.b, 1)
    if vertical then
        rail:SetWidth(St.FOREVER_RAIL)
        rail.core:SetPoint("TOPLEFT", edge, 0)
        rail.core:SetPoint("BOTTOMRIGHT", -edge, 0)
    else
        rail:SetHeight(St.FOREVER_RAIL)
        rail.core:SetPoint("TOPLEFT", 0, -edge)
        rail.core:SetPoint("BOTTOMRIGHT", 0, edge)
    end
    rail.vertical = vertical
    return rail
end

local function LightColors()
    if not lightColors then
        lightColors = { CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, St.FOREVER_LIGHT_ALPHA) }
    end
    return lightColors[1], lightColors[2]
end

local function LightHalf(window, area, left)
    local half = window:CreateTexture(nil, "BACKGROUND", nil, St.FOREVER_LIGHT_SUBLEVEL)
    local edge, middle = LightColors()
    half:SetColorTexture(1, 1, 1, 1)
    if left then
        half:SetPoint("TOPLEFT", area)
        half:SetPoint("BOTTOMRIGHT", area, "BOTTOM")
        half:SetGradient("HORIZONTAL", edge, middle)
    else
        half:SetPoint("TOPLEFT", area, "TOP")
        half:SetPoint("BOTTOMRIGHT", area)
        half:SetGradient("HORIZONTAL", middle, edge)
    end
    return half
end

function Parts.ForeverPanes(window, bandH, columnW)
    local panes = {}
    panes.band = window:CreateTexture(nil, "BACKGROUND", nil, St.FOREVER_LIGHT_SUBLEVEL)
    panes.band:SetPoint("TOPLEFT")
    panes.band:SetPoint("TOPRIGHT")
    panes.band:SetHeight(bandH)
    Gradient(panes.band, St.FOREVER_BAND_RGB)
    panes.rail = Parts.ForeverRail(window)
    panes.rail:SetPoint("TOPLEFT", 0, -bandH)
    panes.rail:SetPoint("TOPRIGHT", 0, -bandH)
    local top = bandH + St.FOREVER_RAIL
    panes.side = Parts.ForeverRail(window, true)
    panes.side:SetPoint("TOPLEFT", columnW, -top)
    panes.side:SetPoint("BOTTOMLEFT", columnW, 0)
    panes.area = CreateFrame("Frame", nil, window)
    panes.area:SetPoint("TOPLEFT", columnW + St.FOREVER_RAIL, -top)
    panes.area:SetPoint("BOTTOMRIGHT")
    panes.light = { LightHalf(window, panes.area, true), LightHalf(window, panes.area, false) }
    window.foreverPanes = panes
    return panes
end
