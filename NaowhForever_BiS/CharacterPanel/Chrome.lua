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
--
--  CP.Restyler and CP.Chrome are the same for any of the game's windows: the Naowh Inspect
--  Panel (InspectPanel/) dresses the inspect window with them.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local CP = ns.CharacterPanel
local St = ns.Shared.Style

local HEADER = 20        -- the game's title strip: its panes start this far down
local LOGO = 14          -- Naowh's logo, left in the title strip
local LOGO_IN = 6        -- in from the left edge
local MODEL_INSET = 4    -- the model's panel, in from the left pane's edges
local CLOSE = 10         -- our cross, on the game's close button
local TITLE_SIZE, LEVEL_SIZE, STAT_SIZE, CATEGORY_SIZE = 12, 14, 12, 11
local BACKDROP_ALPHA = 0.97
local MODEL_ALPHA = 0.35 -- the model's dark panel
CP.HEADER, CP.TITLE_SIZE, CP.LEVEL_SIZE, CP.MODEL_ALPHA = HEADER, TITLE_SIZE, LEVEL_SIZE, MODEL_ALPHA

local TAB_RGB = { r = 0.16, g = 0.16, b = 0.17 }   -- a tab's own art, as dark as our panels
CP.TAB_RGB = TAB_RGB

local uppers = {}        -- a stats title -> its capitals, made once each
local styled = setmetatable({}, { __mode = "k" })   -- the stats' rows we styled
local chrome, installed

--- The game's art faded or tinted to our look, each piece remembered so Restore brings it all
--- back: one per window.
function CP.Restyler()
    local r = {}
    local faded, tinted, fonts = {}, {}, {}

    function r.Fade(region)
        if type(region) == "table" and region.SetAlpha then
            region:SetAlpha(0)
            faded[region] = true
        end
    end

    function r.FadeRegions(frame)
        if not frame then return end
        for _, region in ipairs({ frame:GetRegions() }) do r.Fade(region) end
    end

    -- Every texture of a frame and the frames in it (a model's buttons: the game sets their
    -- frame's alpha itself on hover, never their art's).
    function r.FadeTree(frame)
        if not frame then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "Texture" then r.Fade(region) end
        end
        for _, child in ipairs({ frame:GetChildren() }) do r.FadeTree(child) end
    end

    -- The game's art in our colour: its own shape, desaturated and coloured.
    function r.Tint(region, color, alpha)
        if not (type(region) == "table" and region.SetDesaturated) then return end
        region:SetDesaturated(true)
        region:SetVertexColor(color.r, color.g, color.b, alpha or 1)
        tinted[region] = true
    end

    -- Every texture of a frame and the frames in it (a scroll bar's arrows, track and thumb).
    function r.TintTree(frame, color)
        if not frame then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "Texture" then r.Tint(region, color) end
        end
        for _, child in ipairs({ frame:GetChildren() }) do r.TintTree(child, color) end
    end

    -- Text of the game's in our font and colour; its own font object kept to bring back.
    function r.Restyle(fontString, size, color)
        if not fontString then return end
        if not fonts[fontString] then fonts[fontString] = fontString:GetFontObject() or GameFontNormal end
        fontString:SetFont(ns.UIFontPath(), size, "")
        fontString:SetTextColor(color.r, color.g, color.b, 1)
    end

    -- A side tab (Character, Reputation, Guild...) dark, with the accent where it is picked and hovered.
    function r.TintSideTab(tab)
        if not tab then return end
        r.Tint(tab.Background, TAB_RGB)
        r.Tint(tab.SelectedTexture, T.accent)
        r.Tint(tab.HighlightTexture, T.accent, 0.5)
        r.Fade(tab.TabGlow)
    end

    -- The close button's own look gone, under our cross (CP.Chrome).
    function r.FadeClose(close)
        if not close then return end
        r.Fade(close:GetNormalTexture()); r.Fade(close:GetPushedTexture())
        r.Fade(close:GetHighlightTexture()); r.Fade(close:GetDisabledTexture())
    end

    function r.Restore()
        for region in pairs(faded) do region:SetAlpha(1) end
        wipe(faded)
        for region in pairs(tinted) do
            region:SetDesaturated(false)
            region:SetVertexColor(1, 1, 1, 1)
        end
        wipe(tinted)
        for fontString, object in pairs(fonts) do fontString:SetFontObject(object) end
        wipe(fonts)
    end

    return r
end

local game = CP.Restyler()

--- Ours under a window of the game's: our backdrop, border, the title strip's rule with Naowh's
--- logo, and our cross on its close button (which keeps closing it), as .cross: shown and
--- hidden with the rest by the caller.
function CP.Chrome(frame)
    local back = CreateFrame("Frame", nil, frame)
    back:SetAllPoints()
    back:SetFrameLevel(frame:GetFrameLevel())
    back.backdrop = ns.Shared.Parts.Backdrop(back)
    back.backdrop:Paint(BACKDROP_ALPHA)
    ns.Border(back, St.BORDER_RGB)
    local rule = ns.Solid(back, "ARTWORK", St.BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -HEADER)
    rule:SetPoint("TOPRIGHT", 0, -HEADER)
    ns.Hairline(rule, "h")
    local logo = back:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(St.LOGO_SMALL, nil, nil, "TRILINEAR")
    logo:SetSize(LOGO, LOGO)
    logo:SetPoint("LEFT", back, "TOPLEFT", LOGO_IN, -HEADER / 2)
    local close = frame.CloseButton
    if close then
        local cross = close:CreateTexture(nil, "OVERLAY")
        cross:SetTexture(St.CROSS, nil, nil, "TRILINEAR")
        cross:SetSize(CLOSE, CLOSE)
        cross:SetPoint("CENTER")
        cross:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
        close:HookScript("OnEnter", function() cross:SetVertexColor(T.fg.r, T.fg.g, T.fg.b) end)
        close:HookScript("OnLeave", function() cross:SetVertexColor(T.muted.r, T.muted.g, T.muted.b) end)
        back.cross = cross
    end
    return back
end

--- A model's dark panel, as the BiS List's: inset from its box.
function CP.ModelPanel(back, box)
    local panel = ns.Solid(back, "BACKGROUND", T.panel, MODEL_ALPHA)
    panel:SetPoint("TOPLEFT", box, "TOPLEFT", MODEL_INSET, -MODEL_INSET)
    panel:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -MODEL_INSET, MODEL_INSET)
    return panel
end

--- A hairline down the left edge of a pane, for the game's divider.
function CP.Split(back, pane)
    local split = ns.Solid(back, "ARTWORK", St.BORDER_RGB, 1)
    split:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    split:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    ns.Hairline(split, "v")
    return split
end

-- The BiS List's link in the left pane's top-right corner, on your badge's middle, clear of
-- the game's toggle for the stats there (28px, 6px in).
local TOGGLE_EDGE, TOGGLE_W, LINK_GAP = 6, 28, 12

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
        game.Restyle(title, CATEGORY_SIZE, T.accentSoft)
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
        game.Restyle(frame.Label, STAT_SIZE, T.muted)
        game.Restyle(frame.Value, STAT_SIZE, T.fg)
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
local function Build()
    local frame = CharacterFrame
    chrome = CP.Chrome(frame)
    -- The model on the BiS List's dark panel.
    CP.ModelPanel(chrome, frame.LeftPaneHost)
    -- A hairline between the panes, for the game's divider.
    CP.Split(chrome, frame.RightPaneHost)
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
end

-- The game's art the restyle covers: its border and portrait, both panes' backgrounds and the
-- divider, the model's backdrop, the level's banner, the stats' frame and class art, and the
-- close button's own look.
local function FadeGame()
    local frame = CharacterFrame
    game.Fade(frame.NineSlice)
    game.Fade(frame.PortraitContainer)
    game.FadeRegions(frame.LeftPaneHost)
    local right = frame.RightPaneHost
    game.FadeRegions(right)
    if right then
        for _, child in ipairs({ right:GetChildren() }) do game.Fade(child) end
    end
    local model = CharacterModelScene
    if model then
        game.Fade(model.BackgroundTopLeft); game.Fade(model.BackgroundTopRight)
        game.Fade(model.BackgroundBotLeft); game.Fade(model.BackgroundBotRight)
        game.Fade(model.BackgroundOverlay)
    end
    game.Fade(CharacterLevelTextBackground)
    game.FadeRegions(CharacterStatsPaneScrollBox)
    -- The ammo slot's own bracket round its icon.
    local ammo = _G.CharacterAmmoSlot
    if ammo then
        for _, region in ipairs({ ammo:GetRegions() }) do
            if region ~= ammo.icon and region:GetObjectType() == "Texture" then game.Fade(region) end
        end
    end
    game.FadeClose(frame.CloseButton)
end

-- The game's tabs and buttons in our colours: the side tabs (Character, Reputation and the
-- rest) and the stats' three tabs dark with the accent where they are picked and hovered, the
-- panes' toggle and the stats' scroll bar muted.
local function TintGame()
    for i = 1, 6 do game.TintSideTab(_G["CharacterFrameModeTab" .. i]) end
    for i = 1, 3 do
        local tab = _G["PaperDollSidebarTab" .. i]
        if tab then
            for _, region in ipairs({ tab:GetRegions() }) do
                if region ~= tab.Icon and region:GetObjectType() == "Texture" then game.Tint(region, TAB_RGB) end
            end
            game.Tint(tab:GetCheckedTexture(), T.accent)
            game.Tint(tab:GetHighlightTexture(), T.accent, 0.5)
        end
    end
    local toggle = CharacterFrame.RightPaneToggleButton
    if toggle then
        game.Tint(toggle:GetNormalTexture(), T.muted)
        game.Tint(toggle:GetPushedTexture(), T.accent)
    end
    game.TintTree(CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ScrollBar, T.muted)
    -- The model's zoom and turn buttons: gone (dragging the model turns it, the wheel zooms);
    -- the BiS List's link up in the corner (Build).
    game.FadeTree(CharacterModelScene and CharacterModelScene.ControlFrame)
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
        game.Restyle(CharacterFrameTitleText, TITLE_SIZE, T.fg)
        game.Restyle(CharacterLevelText, LEVEL_SIZE, T.fg)
        chrome:Show()
        if chrome.cross then chrome.cross:Show() end
        if chrome.cover then chrome.cover:Show() end
        local list = CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ScrollBox
        if list and list.ForEachFrame then list:ForEachFrame(function(frame) StyleStat(nil, frame) end) end
    else
        game.Restore()
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
