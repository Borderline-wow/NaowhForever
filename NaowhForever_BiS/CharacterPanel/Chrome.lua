-------------------------------------------------------------------------------
--  Chrome.lua -- the character panel's frame in the BiS List's look: our backdrop, border and
--  title rule with Naowh's logo, the model on the dark panel the BiS List's has, a hairline
--  between the panes, and the stats as plain rows in our fonts and colours under accent titles.
--
--  The game's art is faded (SetAlpha, never Hide), or for its tabs and buttons tinted to our
--  colours (desaturated), each piece remembered to bring back when it is turned off; ours sits
--  under the game's frames, at the panel's own frame level, so the
--  game's slots, model and stats draw over it. The stats' rows are styled as the game's list
--  makes them (its scroll box's initialized-frame callback), the same on every reuse.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local CP = ns.CharacterPanel
local St = ns.Shared.Style

local HEADER = 20        -- the game's title strip: its panes start this far down
local LOGO = 14          -- Naowh's logo, left in the title strip
local MODEL_INSET = 4    -- the model's panel, in from the left pane's edges
local CLOSE = 10         -- our cross, on the game's close button
local TITLE_SIZE, LEVEL_SIZE, STAT_SIZE, CATEGORY_SIZE = 12, 14, 12, 11
local BACKDROP_ALPHA = 0.97

local faded = {}         -- the game's art we faded -> true, to bring back
local tinted = {}        -- the game's art we tinted -> true, to bring back
local uppers = {}        -- a stats title -> its capitals, made once each
local fonts = {}         -- the game's text we restyled -> its font object, to bring back
local styled = setmetatable({}, { __mode = "k" })   -- the stats' rows we styled
local chrome, installed

local function Fade(region)
    if region and region.SetAlpha then
        region:SetAlpha(0)
        faded[region] = true
    end
end

local function FadeRegions(frame)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do Fade(region) end
end

-- The game's art in our colour: its own shape, desaturated and coloured.
local function Tint(region, color, alpha)
    if not (region and region.SetDesaturated) then return end
    region:SetDesaturated(true)
    region:SetVertexColor(color.r, color.g, color.b, alpha or 1)
    tinted[region] = true
end

-- Every texture of a frame and the frames in it (a scroll bar's arrows, track and thumb).
local function TintTree(frame, color)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" then Tint(region, color) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do TintTree(child, color) end
end

local TAB_RGB = { r = 0.16, g = 0.16, b = 0.17 }   -- a tab's own art, as dark as our panels

-- Every texture of a frame and the frames in it, faded (the model's buttons: the game sets
-- their frame's alpha itself on hover, never their art's).
local function FadeTree(frame)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" then Fade(region) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do FadeTree(child) end
end

-- The BiS List's link in the left pane's top-right corner, on your badge's middle, clear of
-- the game's toggle for the stats there (28px, 6px in).
local TOGGLE_EDGE, TOGGLE_W, LINK_GAP = 6, 28, 12

-- Text of the game's in our font and colour; its own font object kept to bring back.
local function Restyle(fontString, size, color)
    if not fontString then return end
    if not fonts[fontString] then fonts[fontString] = fontString:GetFontObject() or GameFontNormal end
    fontString:SetFont(ns.UIFontPath(), size, "")
    fontString:SetTextColor(color.r, color.g, color.b, 1)
end

-------------------------------------------------------------------------------
--  The stats: each row as the game's list makes it
-------------------------------------------------------------------------------
local function StyleStat(_, frame)
    if not CP.On() then return end
    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.Title then
        -- A category: an accent title in capitals on the left, over a hairline, as the BiS
        -- List's section titles.
        local title = frame.Title
        Restyle(title, CATEGORY_SIZE, T.accentSoft)
        local text = title:GetText()
        if text then
            local upper = uppers[text]
            if not upper then
                upper = text:upper()
                uppers[text], uppers[upper] = upper, upper
            end
            title:SetText(upper)
        end
        title:ClearAllPoints()
        title:SetPoint("BOTTOMLEFT", 8, 8)
        local line = styled[frame]
        if type(line) ~= "table" then
            line = ns.Solid(frame, "ARTWORK", T.line, 1)
            line:SetPoint("BOTTOMLEFT", 8, 4)
            line:SetPoint("BOTTOMRIGHT", -8, 4)
            ns.Hairline(line, "h")
            styled[frame] = line
        end
        line:Show()
    else
        Restyle(frame.Label, STAT_SIZE, T.muted)
        Restyle(frame.Value, STAT_SIZE, T.fg)
        styled[frame] = styled[frame] or true
    end
end

local function UnstyleStats()
    for frame, line in pairs(styled) do
        if frame.Background then frame.Background:SetAlpha(1) end
        if type(line) == "table" then
            line:Hide()
            frame.Title:ClearAllPoints()
            frame.Title:SetPoint("CENTER", 0, 1)   -- the game's own anchor
        end
    end
end

-------------------------------------------------------------------------------
--  Ours: under the game's frames
-------------------------------------------------------------------------------
local function CloseEnter() chrome.cross:SetVertexColor(T.fg.r, T.fg.g, T.fg.b) end
local function CloseLeave() chrome.cross:SetVertexColor(T.muted.r, T.muted.g, T.muted.b) end

local function Build()
    local frame = CharacterFrame
    chrome = CreateFrame("Frame", nil, frame)
    chrome:SetAllPoints()
    chrome:SetFrameLevel(frame:GetFrameLevel())
    chrome.backdrop = ns.Shared.Parts.Backdrop(chrome)
    chrome.backdrop:Paint(BACKDROP_ALPHA)
    ns.Border(chrome, St.BORDER_RGB)
    local rule = ns.Solid(chrome, "ARTWORK", St.BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -HEADER)
    rule:SetPoint("TOPRIGHT", 0, -HEADER)
    ns.Hairline(rule, "h")
    local logo = chrome:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(St.LOGO_SMALL, nil, nil, "TRILINEAR")
    logo:SetSize(LOGO, LOGO)
    logo:SetPoint("LEFT", chrome, "TOPLEFT", 6, -HEADER / 2)
    -- The model on the BiS List's dark panel.
    local left = frame.LeftPaneHost
    local panel = ns.Solid(chrome, "BACKGROUND", T.panel, 0.35)
    panel:SetPoint("TOPLEFT", left, "TOPLEFT", MODEL_INSET, -MODEL_INSET)
    panel:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -MODEL_INSET, MODEL_INSET)
    -- A hairline between the panes, for the game's divider.
    local split = ns.Solid(chrome, "ARTWORK", St.BORDER_RGB, 1)
    split:SetPoint("TOPLEFT", frame.RightPaneHost, "TOPLEFT", 0, 0)
    split:SetPoint("BOTTOMLEFT", frame.RightPaneHost, "BOTTOMLEFT", 0, 0)
    ns.Hairline(split, "v")
    -- The model's buttons faded, a frame over their whole strip so they take no clicks, and the
    -- BiS List's link on it.
    local controls = CharacterModelScene and CharacterModelScene.ControlFrame
    if controls then
        local cover = CreateFrame("Frame", nil, frame)
        cover:SetAllPoints(controls)
        cover:SetFrameLevel(CharacterModelScene:GetFrameLevel() + 20)
        cover:EnableMouse(true)
        -- The link itself in the pane's top-right corner, on your badge's middle (Badge.lua),
        -- beside the game's toggle for the stats.
        local bis = ns.Shared.Parts.Link(cover, function() ns.OpenBisWindow() end, true)
        -- The BiS star before its name, as the BiS List marks your BiS.
        ns.Shared.Parts.SetLink(bis, ns.Shared.Parts.Inline(St.STAR, St.BIS_RGB, ns.Shared.Parts.CARD_DROP)
            .. " BiS List")
        bis:SetPoint("RIGHT", frame.LeftPaneHost, "TOPRIGHT", -(TOGGLE_EDGE + TOGGLE_W + LINK_GAP),
            -(CP.BADGE_MID or 32))
        chrome.cover = cover
    end
    -- Our cross on the game's close button, which keeps closing the panel.
    local close = frame.CloseButton
    if close then
        chrome.cross = close:CreateTexture(nil, "OVERLAY")
        chrome.cross:SetTexture(St.CROSS, nil, nil, "TRILINEAR")
        chrome.cross:SetSize(CLOSE, CLOSE)
        chrome.cross:SetPoint("CENTER")
        CloseLeave()
        close:HookScript("OnEnter", CloseEnter)
        close:HookScript("OnLeave", CloseLeave)
    end
end

-- The game's art the restyle covers: its border and portrait, both panes' backgrounds and the
-- divider, the model's backdrop, the level's banner, the stats' frame and class art, and the
-- close button's own look.
local function FadeGame()
    local frame = CharacterFrame
    Fade(frame.NineSlice)
    Fade(frame.PortraitContainer)
    FadeRegions(frame.LeftPaneHost)
    local right = frame.RightPaneHost
    FadeRegions(right)
    if right then
        for _, child in ipairs({ right:GetChildren() }) do Fade(child) end
    end
    local model = CharacterModelScene
    if model then
        Fade(model.BackgroundTopLeft); Fade(model.BackgroundTopRight)
        Fade(model.BackgroundBotLeft); Fade(model.BackgroundBotRight)
        Fade(model.BackgroundOverlay)
    end
    Fade(CharacterLevelTextBackground)
    FadeRegions(CharacterStatsPaneScrollBox)
    -- The ammo slot's own bracket round its icon.
    local ammo = _G.CharacterAmmoSlot
    if ammo then
        for _, region in ipairs({ ammo:GetRegions() }) do
            if region ~= ammo.icon and region:GetObjectType() == "Texture" then Fade(region) end
        end
    end
    local close = frame.CloseButton
    if close then
        Fade(close:GetNormalTexture()); Fade(close:GetPushedTexture())
        Fade(close:GetHighlightTexture()); Fade(close:GetDisabledTexture())
    end
end

-- The game's tabs and buttons in our colours: the side tabs (Character, Reputation and the
-- rest) and the stats' three tabs dark with the accent where they are picked and hovered, the
-- panes' toggle and the stats' scroll bar muted.
local function TintGame()
    for i = 1, 6 do
        local tab = _G["CharacterFrameModeTab" .. i]
        if tab then
            Tint(tab.Background, TAB_RGB)
            Tint(tab.SelectedTexture, T.accent)
            Tint(tab.HighlightTexture, T.accent, 0.5)
            Fade(tab.TabGlow)
        end
    end
    for i = 1, 3 do
        local tab = _G["PaperDollSidebarTab" .. i]
        if tab then
            for _, region in ipairs({ tab:GetRegions() }) do
                if region ~= tab.Icon and region:GetObjectType() == "Texture" then Tint(region, TAB_RGB) end
            end
            Tint(tab:GetCheckedTexture(), T.accent)
            Tint(tab:GetHighlightTexture(), T.accent, 0.5)
        end
    end
    local toggle = CharacterFrame.RightPaneToggleButton
    if toggle then
        Tint(toggle:GetNormalTexture(), T.muted)
        Tint(toggle:GetPushedTexture(), T.accent)
    end
    TintTree(CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ScrollBar, T.muted)
    -- The model's zoom and turn buttons: gone (dragging the model turns it, the wheel zooms);
    -- the BiS List's link up in the corner (Build).
    FadeTree(CharacterModelScene and CharacterModelScene.ControlFrame)
end

local function Install()
    installed = true
    Build()
    local list = CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ScrollBox
    if list and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(list, StyleStat, chrome, true)
    end
end

local function Apply()
    local on = CP.On()
    if on and not installed and CharacterFrame then Install() end
    if not installed then return end
    if on then
        FadeGame()
        TintGame()
        Restyle(CharacterFrameTitleText, TITLE_SIZE, T.fg)
        Restyle(CharacterLevelText, LEVEL_SIZE, T.fg)
        chrome:Show()
        if chrome.cross then chrome.cross:Show() end
        if chrome.cover then chrome.cover:Show() end
        local list = CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ScrollBox
        if list and list.ForEachFrame then list:ForEachFrame(function(frame) StyleStat(nil, frame) end) end
    else
        for region in pairs(faded) do region:SetAlpha(1) end
        wipe(faded)
        for region in pairs(tinted) do
            region:SetDesaturated(false)
            region:SetVertexColor(1, 1, 1, 1)
        end
        wipe(tinted)
        for fontString, object in pairs(fonts) do fontString:SetFontObject(object) end
        wipe(fonts)
        UnstyleStats()
        chrome:Hide()
        if chrome.cross then chrome.cross:Hide() end
        if chrome.cover then chrome.cover:Hide() end
    end
end
CP.ApplyChrome = Apply

S.OnChange(function(key)
    if key == "enabled" or key:find("^characterPanel") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
