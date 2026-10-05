-------------------------------------------------------------------------------
--  NaowhForever_RXPThemes.lua -- NaowhUI, the eight Naowh themes and the player's current theme in
--  RestedXP Guides, and hooks that style its arrow, title bar, quest list and scroll bar. Off unless
--  Settings > RESTEDXP turns it on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local RXP_ADDON = "RXPGuides"
local NAME_PREFIX = "NaowhForever:"
local AUTHOR = "Naowh Forever"
local DEFAULT_KEY, DEFAULT_NAME = "default", "NaowhUI"
local CURRENT_KEY, CURRENT_NAME = "current", "Naowh (current)"
local RXP_DEFAULT = "Default"   -- RestedXP's name for its own theme

local RXP_TEXTURES = "Interface/AddOns/RXPGuides/Textures/"
local TEXTURES = RXP_TEXTURES .. "DarkMode/"
local WHITE = "Interface/BUTTONS/WHITE8X8"

local HIGHLIGHT_ALPHA = 0.5
local RULE_ALPHA = 0.6
local CHROME_ALPHA = 0.7
local RULE_DROP = 3   -- quest rows are 3 apart; the rule sits at the far edge of that gap

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
local FRAME = MEDIA .. "rxp_frame.tga"
local ARROW_IMAGES = {   -- by shape, then by glow
    kite = { [false] = MEDIA .. "rxp_arrow.tga", [true] = MEDIA .. "rxp_arrow_glow.tga" },
    wide = { [false] = MEDIA .. "rxp_arrow_wide.tga", [true] = MEDIA .. "rxp_arrow_wide_glow.tga" },
}
local DEFAULT_SHAPE = "kite"
local ARROW_STYLES = { layer = true, image = true, off = true }
local DEFAULT_ARROW = "layer"
-- Naowh's image is drawn this percent of RestedXP's arrow frame; with a glow the kite fills only
-- GLOW_FILL of it (Tools/make_media.py), so that image is drawn larger to keep the kite the same size.
local SIZE_MIN, SIZE_MAX, SIZE_STEP, DEFAULT_SIZE = 60, 200, 5, 90
local GLOW_FILL = 0.76
local GAP_MIN, GAP_MAX, DEFAULT_GAP = 0, 20, 4   -- extra space between Naowh's image and the distance text
-- The layer is lighter at the top, deeper at the bottom and not full strength, so the dark arrow still shades it.
local TOP_TOWARD_WHITE = 0.22
local BOTTOM_SHARE = 0.72
local LAYER_STRENGTH = 0.9

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local PaintArrow   -- defined below
local boot         -- our frame, which also waits for the end of combat

---@return boolean
function ns.RXPThemesAvailable()
    return C_AddOns.DoesAddOnExist(RXP_ADDON) == true
end

---@return boolean
function ns.RXPThemesEnabled()
    return ns.AccountSettings().rxpThemes == true
end

---@param on boolean
function ns.SetRXPThemes(on)
    ns.AccountSettings().rxpThemes = on and true or nil
end

---@return table values by id
---@return table order
function ns.RXPThemeChoices()
    local values = { [""] = "RestedXP (default)", [CURRENT_KEY] = "Current Theme", [DEFAULT_KEY] = DEFAULT_NAME }
    local order = { "", CURRENT_KEY, DEFAULT_KEY }
    for _, key in ipairs(ns.THEME_PRESET_ORDER) do
        values[key] = ns.THEME_PRESETS[key].name
        order[#order + 1] = key
    end
    return values, order
end

local function ThemeId(key)
    return key == CURRENT_KEY or key == DEFAULT_KEY or (type(key) == "string" and ns.THEME_PRESETS[key] ~= nil)
end

local function Has(object, method)
    return type(object) == "table" and type(object[method]) == "function"
end

-- t[k1][k2]... when every step is a table, else nil.
local function Dig(t, ...)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end

local function Ours(name)
    return type(name) == "string" and name:find(NAME_PREFIX, 1, true) == 1
end

-- RestedXP's own theme reload, which scales its protected target frame: in combat it waits for the end of it.
local function Reload()
    local rxp = _G.RXP
    if not Has(rxp, "ReloadTheme") then return end
    if InCombatLockdown() then
        boot:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    rxp:ReloadTheme()
end

-- Our themes are in RestedXP's list, which they are after the reload that follows turning them on.
---@return boolean
function ns.RXPThemesReady()
    local rxp = _G.RXP
    return type(Dig(rxp, "settings", "profile")) == "table" and Has(rxp, "ReloadTheme")
        and type(Dig(rxp, "themes", NAME_PREFIX .. DEFAULT_KEY)) == "table"
end

---@return string "" or a theme's id
function ns.RXPThemeChoice()
    local name = Dig(_G.RXP, "settings", "profile", "activeTheme")
    local key = Ours(name) and name:sub(#NAME_PREFIX + 1)
    return ThemeId(key) and Dig(_G.RXP, "themes", name) and key or ""
end

-- Written only when the player picks; "" puts RestedXP back on its own theme if it is on one of ours.
---@param key string
---@return string|nil "reload" when RestedXP shows the theme only after a reload
function ns.SetRXPThemeChoice(key)
    local rxp = _G.RXP
    local profile = Dig(rxp, "settings", "profile")
    if type(profile) ~= "table" or not Has(rxp, "ReloadTheme") then return end
    local name
    if key == "" then
        name = Ours(profile.activeTheme) and RXP_DEFAULT
    elseif ThemeId(key) and Dig(rxp, "themes", NAME_PREFIX .. key) then
        name = NAME_PREFIX .. key
    end
    if not name or profile.activeTheme == name then return end
    profile.activeTheme = name
    if not profile.enableThemeLiveReload then return "reload" end
    Reload()
end

-- On unless saved as false.
local function Wanted(key)
    return ns.AccountSettings()[key] ~= false
end

local function Want(key, on)
    if on then ns.AccountSettings()[key] = nil else ns.AccountSettings()[key] = false end
end

-- The font and text color are in the themes, which RestedXP reads as it starts: they take a reload.
---@return boolean
function ns.RXPFontEnabled() return Wanted("rxpFont") end

---@param on boolean
function ns.SetRXPFont(on) Want("rxpFont", on) end

---@return boolean
function ns.RXPTextColorEnabled() return Wanted("rxpTextColor") end

---@param on boolean
function ns.SetRXPTextColor(on) Want("rxpTextColor", on) end

---@return string "layer", "image" or "off"
function ns.RXPArrowStyle()
    local style = ns.AccountSettings().rxpArrow
    return ARROW_STYLES[style] and style or DEFAULT_ARROW
end

---@param style string
function ns.SetRXPArrowStyle(style)
    ns.AccountSettings().rxpArrow = (ARROW_STYLES[style] and style ~= DEFAULT_ARROW) and style or nil
    PaintArrow()
end

---@return string "kite" or "wide"
function ns.RXPArrowShape()
    local shape = ns.AccountSettings().rxpArrowShape
    return ARROW_IMAGES[shape] and shape or DEFAULT_SHAPE
end

---@param shape string
function ns.SetRXPArrowShape(shape)
    ns.AccountSettings().rxpArrowShape = (ARROW_IMAGES[shape] and shape ~= DEFAULT_SHAPE) and shape or nil
    PaintArrow()
end

---@return number min
---@return number max
---@return number step
function ns.RXPArrowSizeRange() return SIZE_MIN, SIZE_MAX, SIZE_STEP end

local function Snap(value, lo, hi, step)
    return math.min(hi, math.max(lo, math.floor(value / step + 0.5) * step))
end

---@return number percent of RestedXP's arrow frame
function ns.RXPArrowSize()
    local size = tonumber(ns.AccountSettings().rxpArrowSize)
    return size and Snap(size, SIZE_MIN, SIZE_MAX, SIZE_STEP) or DEFAULT_SIZE
end

---@param size number
function ns.SetRXPArrowSize(size)
    size = tonumber(size)
    size = size and Snap(size, SIZE_MIN, SIZE_MAX, SIZE_STEP)
    ns.AccountSettings().rxpArrowSize = size ~= DEFAULT_SIZE and size or nil
    PaintArrow()
end

---@return number min
---@return number max
function ns.RXPArrowGapRange() return GAP_MIN, GAP_MAX end

---@return number pixels
function ns.RXPArrowGap()
    local gap = tonumber(ns.AccountSettings().rxpArrowGap)
    return gap and Snap(gap, GAP_MIN, GAP_MAX, 1) or DEFAULT_GAP
end

---@param gap number
function ns.SetRXPArrowGap(gap)
    gap = tonumber(gap)
    gap = gap and Snap(gap, GAP_MIN, GAP_MAX, 1)
    ns.AccountSettings().rxpArrowGap = gap ~= DEFAULT_GAP and gap or nil
    PaintArrow()
end

---@return boolean
function ns.RXPArrowTextEnabled() return Wanted("rxpArrowText") end

---@param on boolean
function ns.SetRXPArrowText(on)
    Want("rxpArrowText", on)
    PaintArrow()
end

---@return boolean
function ns.RXPArrowGlow()
    return ns.AccountSettings().rxpArrowGlow == true
end

---@param on boolean
function ns.SetRXPArrowGlow(on)
    ns.AccountSettings().rxpArrowGlow = on and true or nil
    PaintArrow()
end

-------------------------------------------------------------------------------
--  Themes
-------------------------------------------------------------------------------
local function Rgba(c, alpha)
    return { c.r, c.g, c.b, alpha }
end

local function Hex(c)
    return ("%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5))
end

-- One theme from a Naowh palette: source is a preset's key, "" for the default theme, or "custom".
local function Theme(id, displayName, source)
    local palette = ns.ThemePalette(source)
    local c = {}
    for i, token in ipairs(ns.THEME_EDITABLE) do c[token] = palette[i] end
    return {
        name = NAME_PREFIX .. id,
        displayName = displayName,
        author = AUTHOR,
        background = Rgba(c.panel, 1),
        bottomFrameBG = Rgba(c.panel, 1),
        bottomFrameHighlight = Rgba(c.accent, HIGHLIGHT_ALPHA),
        dividerColor = Rgba(c.line, RULE_ALPHA),   -- this and chromeColor are ours, not RestedXP's
        chromeColor = Rgba(c.muted, CHROME_ALPHA),
        mapPins = Rgba(c.accent, 1),
        tooltip = "|cff" .. Hex(c.accent),
        -- Left out, RestedXP uses its own. AddonFontPath, not UIFontPath: that one remembers what it finds,
        -- and this runs before every addon has loaded.
        textColor = ns.RXPTextColorEnabled() and { c.fg.r, c.fg.g, c.fg.b } or nil,
        font = ns.RXPFontEnabled() and ns.AddonFontPath() or nil,
        texturePath = TEXTURES,
        bgTextures = { edge = WHITE, bottom = WHITE, guideName = WHITE },   -- the bars need a fill to show
        edges = { edge = FRAME, guideName = FRAME },
    }
end

local late   -- RestedXP was up before us

-- RestedXP imports the global list as it starts. If it is up already, the themes go in through its own call.
local function Register()
    local themes = {}
    local function Add(id, displayName, source)
        local theme = Theme(id, displayName, source)
        themes[theme.name] = theme
    end
    Add(DEFAULT_KEY, DEFAULT_NAME, "")
    for _, key in ipairs(ns.THEME_PRESET_ORDER) do Add(key, ns.THEME_PRESETS[key].name, key) end
    Add(CURRENT_KEY, CURRENT_NAME, ns.ThemePresetKey())
    local rxp = _G.RXP
    if Has(rxp, "RegisterTheme") and type(rxp.activeTheme) == "table" then
        late = true
        for _, theme in pairs(themes) do rxp:RegisterTheme(theme) end
        return
    end
    local list = _G.RXPGuides_Themes
    if type(list) ~= "table" then
        list = {}
        _G.RXPGuides_Themes = list
    end
    for name, theme in pairs(themes) do list[name] = theme end
end

-- RestedXP started before the themes were in, so it fell back from a theme of ours that it was saved on.
local function Resume()
    local rxp = _G.RXP
    local saved = Dig(rxp, "themes", Dig(rxp, "settings", "profile", "activeTheme"))
    if type(saved) == "table" and Ours(saved.name) and saved ~= rxp.activeTheme then Reload() end
end

-------------------------------------------------------------------------------
--  Hooks into RestedXP's window. Each checks what it needs and does nothing without it.
-------------------------------------------------------------------------------
local function ActiveTheme()
    local rxp = _G.RXP
    local theme = rxp and rxp.activeTheme
    if type(theme) == "table" and type(theme.name) == "string" and type(theme.mapPins) == "table"
            and theme.name:find(NAME_PREFIX, 1, true) == 1 then
        return theme
    end
end

-- The arrow
local layer     -- our layer over the arrow
local swapped   -- our image is on the arrow in place of RestedXP's
local fitted    -- how many times the frame our image is drawn; set while our image and tint are on
local rxpImage  -- the image RestedXP last set
local textHome  -- where RestedXP anchored the distance text, as GetPoint gives it
local textHidden  -- we have hidden that text

local function BuildLayer(arrow)
    local texture = arrow.texture
    if not Has(texture, "SetRotation") then return nil end
    local f = CreateFrame("Frame", nil, arrow)
    f:SetAllPoints()
    f:SetFrameLevel(arrow:GetFrameLevel() + 1)
    f.color = f:CreateTexture(nil, "OVERLAY")
    f.color:SetAllPoints()
    f.color:SetBlendMode("ADD")
    f.mask = f:CreateMaskTexture()
    f.mask:SetAllPoints()
    f.color:AddMaskTexture(f.mask)
    hooksecurefunc(texture, "SetRotation", function(_, radians) f.mask:SetRotation(radians) end)
    return f
end

local function ShowLayer(arrow, c)
    layer = layer or BuildLayer(arrow)
    if not layer then return end
    layer.color:SetColorTexture(1, 1, 1, 1)
    layer.color:SetGradient("VERTICAL",
        CreateColor(c[1] * BOTTOM_SHARE, c[2] * BOTTOM_SHARE, c[3] * BOTTOM_SHARE, LAYER_STRENGTH),
        CreateColor(c[1] + (1 - c[1]) * TOP_TOWARD_WHITE, c[2] + (1 - c[2]) * TOP_TOWARD_WHITE,
            c[3] + (1 - c[3]) * TOP_TOWARD_WHITE, LAYER_STRENGTH))
    layer.mask:SetTexture(arrow.texture:GetTexture(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    layer.mask:SetRotation(arrow.orientation or 0)
    layer:Show()
end

-- The distance text goes `down` lower than RestedXP puts it.
local function MoveText(arrow, down)
    local text = arrow.text
    if not Has(text, "GetPoint") then return end
    textHome = textHome or { text:GetPoint() }
    local point, relativeTo, relativePoint, x, y = unpack(textHome)
    text:SetPoint(point, relativeTo, relativePoint, x, y - down)
end

-- The image over the arrow's frame, `scale` times its size around the same center, so it still turns in
-- place; and the distance text clear of wherever the image now reaches.
local function Fit(arrow, texture, scale)
    if not (Has(texture, "ClearAllPoints") and Has(arrow, "GetSize")) then return end
    local w, h = arrow:GetSize()
    local dx, dy = w * (scale - 1) / 2, h * (scale - 1) / 2
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", arrow, "TOPLEFT", -dx, dy)
    texture:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", dx, -dy)
    MoveText(arrow, math.max(0, dy) + ns.RXPArrowGap())
end

local function ShowImage(arrow, texture, c)
    texture:SetTexture(ARROW_IMAGES[ns.RXPArrowShape()][ns.RXPArrowGlow()])
    texture:SetVertexColor(c[1], c[2], c[3], 1)
    fitted = ns.RXPArrowSize() / 100 / (ns.RXPArrowGlow() and GLOW_FILL or 1)
    Fit(arrow, texture, fitted)
    swapped = true
end

local function HandBack(arrow, texture)
    if fitted then
        fitted = nil
        if Has(texture, "SetAllPoints") then
            texture:ClearAllPoints()
            texture:SetAllPoints()
        end
        if textHome then arrow.text:SetPoint(unpack(textHome)) end
        texture:SetVertexColor(1, 1, 1, 1)
    end
    if swapped then
        if rxpImage then texture:SetTexture(rxpImage) end
        swapped = false
    end
end

-- RestedXP only sets the text, never shows or hides it.
local function PaintText(arrow, theme)
    local text = arrow.text
    if not Has(text, "Hide") then return end
    local hide = theme ~= nil and not ns.RXPArrowTextEnabled()
    if hide and not textHidden then
        text:Hide()
    elseif textHidden and not hide then
        text:Show()
    end
    textHidden = hide
end

function PaintArrow()
    local arrow = _G.RXPG_ARROW
    local texture = arrow and arrow.texture
    if not texture then return end
    local theme = ActiveTheme()
    local style = theme and ns.RXPArrowStyle() or "off"
    if style == "layer" then
        ShowLayer(arrow, theme.mapPins)
    elseif layer then
        layer:Hide()
    end
    if style == "image" then
        ShowImage(arrow, texture, theme.mapPins)
    else
        HandBack(arrow, texture)
    end
    PaintText(arrow, theme)
end

-- RestedXP has just set its own image again (its theme loaded or changed).
local function OnRxpUpdate()
    local arrow = _G.RXPG_ARROW
    swapped = false
    rxpImage = arrow and arrow.texture and arrow.texture:GetTexture()
    PaintArrow()
end

local function HookArrow()
    local arrow = _G.RXPG_ARROW
    if not (arrow and arrow.texture and Has(arrow, "UpdateVisuals")) then return end
    hooksecurefunc(arrow, "UpdateVisuals", OnRxpUpdate)
    if Has(arrow, "HookScript") then   -- its Arrow Size setting resizes the frame silently
        arrow:HookScript("OnSizeChanged", function()
            if fitted then Fit(arrow, arrow.texture, fitted) end
        end)
    end
    OnRxpUpdate()
end

-- The title bar and footer: a fill under a banner image that is plain black in DarkMode. The image is
-- hidden so the fill shows; RestedXP sets it again whenever it draws its theme, so SetTexture is watched.
local BARS = { "GuideName", "Footer" }
local barsHidden

local function Banner(name)
    local banner = Dig(_G.RXPFrame, name, "bg")
    return type(banner) == "table" and banner or nil
end

local function PaintBars()
    local hide = ActiveTheme() ~= nil
    if not hide and not barsHidden then return end
    for _, name in ipairs(BARS) do
        local banner = Banner(name)
        if Has(banner, "SetAlpha") then banner:SetAlpha(hide and 0 or 1) end
    end
    barsHidden = hide
end

local function HookBars()
    for _, name in ipairs(BARS) do
        local banner = Banner(name)
        if Has(banner, "SetTexture") then hooksecurefunc(banner, "SetTexture", PaintBars) end
    end
    PaintBars()
end

-- The cog, the corner grip and the scroll bar have no theme field: the cog and grip are swapped for Naowh's
-- images, and the scroll bar is a thin thumb without arrows, as in Naowh's windows. All in Secondary Text.
local COG = MEDIA .. "cog.tga"
local GRIP = MEDIA .. "rxp_grip.tga"
local ARROWS = { "ScrollUpButton", "ScrollDownButton" }
local ARROW_PARTS = { "Normal", "Highlight", "Pushed", "Disabled" }
local THUMB_W, THUMB_H = 8, 40
local chromeTinted, gripOriginal, thumbSize

local function Skin(texture, path, color)
    if not Has(texture, "SetVertexColor") then return end
    if path and Has(texture, "SetTexture") then texture:SetTexture(path) end
    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1], color[2], color[3], color[4] or 1 end
    texture:SetVertexColor(r, g, b, a)
end

local function Normal(button)
    return Has(button, "GetNormalTexture") and button:GetNormalTexture() or nil
end

local function PaintThumb(thumb, color)
    if not (Has(thumb, "SetSize") and Has(thumb, "GetSize")) then return end
    thumbSize = thumbSize or { thumb:GetSize() }
    if color and Has(thumb, "SetColorTexture") then
        thumb:SetColorTexture(color[1], color[2], color[3], color[4])
        thumb:SetSize(THUMB_W, THUMB_H)
    else
        thumb:SetSize(thumbSize[1], thumbSize[2])
    end
end

local function PaintChrome()
    local theme = ActiveTheme()
    local color = theme and type(theme.chromeColor) == "table" and theme.chromeColor or nil
    if not color and not chromeTinted then return end
    chromeTinted = color ~= nil
    local frame = _G.RXPFrame
    local grip = Normal(Dig(frame, "Footer", "icon"))
    if Has(grip, "GetTexture") then gripOriginal = gripOriginal or grip:GetTexture() end   -- RestedXP never sets it again
    Skin(Normal(Dig(frame, "Footer", "cog")), color and COG, color)
    Skin(grip, color and GRIP or gripOriginal, color)
    local bar = Dig(frame, "ScrollFrame", "ScrollBar")
    PaintThumb(Has(bar, "GetThumbTexture") and bar:GetThumbTexture() or nil, color)
    for _, name in ipairs(ARROWS) do
        for _, part in ipairs(ARROW_PARTS) do
            local texture = Dig(bar, name, part)
            if Has(texture, "SetAlpha") then texture:SetAlpha(color and 0 or 1) end
        end
    end
end

local function HookChrome()
    local frame = _G.RXPFrame
    if Has(frame, "UpdateScrollBar") then hooksecurefunc(frame, "UpdateScrollBar", PaintChrome) end
    PaintChrome()
end

-- The quest list: a rule at the bottom of each row. Rows are made when a guide loads, which ends in
-- SetStep, so that is watched; rules are redrawn only when the theme or the row count changes.
local rules = setmetatable({}, { __mode = "k" })   -- row -> its rule
local ruleTheme, ruleRows

local function PaintRules()
    local list = Dig(_G.RXPFrame, "ScrollChild", "framePool")
    if type(list) ~= "table" then return end
    local theme = ActiveTheme()
    if theme == ruleTheme and #list == ruleRows then return end
    ruleTheme, ruleRows = theme, #list
    local color = theme and theme.dividerColor
    if type(color) ~= "table" then color = nil end
    for _, row in ipairs(list) do
        local rule = rules[row]
        if color and not rule and Has(row, "CreateTexture") then
            rule = row:CreateTexture(nil, "ARTWORK")
            rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -RULE_DROP)
            rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -RULE_DROP)
            rule:SetHeight(1)
            rules[row] = rule
        end
        if rule and color then
            rule:SetColorTexture(color[1], color[2], color[3], color[4])
            rule:Show()
        elseif rule then
            rule:Hide()
        end
    end
end

local function HookRules()
    local rxp = _G.RXP
    if Has(rxp, "SetStep") then hooksecurefunc(rxp, "SetStep", PaintRules) end
    PaintRules()
end

-- Themes go in while our addon loads; the hooks need RestedXP's frames, so they wait for PLAYER_LOGIN.
boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ns.MODULE_KEY then return end
        self:UnregisterEvent("ADDON_LOADED")
        if ns.RXPThemesEnabled() and ns.RXPThemesAvailable() then
            Register()
            self:RegisterEvent("PLAYER_LOGIN")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Reload()
    else
        self:UnregisterAllEvents()
        if late then Resume() end
        HookArrow()
        HookBars()
        HookChrome()
        HookRules()
    end
end)
