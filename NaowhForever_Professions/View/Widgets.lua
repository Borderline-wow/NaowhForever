-- Widgets.lua: the small parts the Professions windows share: a flat checkbox, a skill bar, a star, a count box.
local ns = _G.NaowhForever

local T = ns.THEME

local P = ns.Professions
local S = P.Settings
local Style = P.Style

local CHECK_INSET = 3
local BAR_DARKEN = 0.55
local BAR_FROM = CreateColor(0x00 / 255, 0x4f / 255, 0x85 / 255, 1)
local STAR_ON, STAR_OFF = "auctionhouse-icon-favorite", "auctionhouse-icon-favorite-off"
local REPUTATION_STAR = "Interface\\COMMON\\ReputationStar"
local HALF = 0.5
local STAR_BUTTON = 18
local SEARCH_GAP = 8
local SEARCH_EDGE = 12

local Widgets = {}
P.Widgets = Widgets

function Widgets.SetColor(fs, c)
    fs:SetTextColor(c.r, c.g, c.b, 1)
end

function Widgets.EnableButton(button, on)
    button:SetEnabled(on)
    button:SetAlpha(on and 1 or Style.DIMMED)
end

function Widgets.Crop(texture)
    texture:SetTexCoord(Style.CROP_LOW, Style.CROP_HIGH, Style.CROP_LOW, Style.CROP_HIGH)
    return texture
end

function Widgets.StyleBar(bar)
    local shifted = ns.ThemeTint("accent", nil)
    local from = shifted and CreateColor(shifted.r * BAR_DARKEN, shifted.g * BAR_DARKEN, shifted.b * BAR_DARKEN, 1)
        or BAR_FROM
    bar:SetStatusBarTexture(Style.WHITE)
    bar:GetStatusBarTexture():SetGradient("HORIZONTAL", from, CreateColor(T.accent.r, T.accent.g, T.accent.b, 1))
    ns.Border(bar, Style.BORDER_RGB)
end

local function LightBorder(box)
    box.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
end

local function DarkBorder(box)
    local black = Style.BORDER_RGB
    box.border:SetColor(black.r, black.g, black.b, 1)
end

function Widgets.CheckBox(parent)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(Style.CHECK_SIZE, Style.CHECK_SIZE)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    box.border = ns.Border(box, Style.BORDER_RGB)
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", CHECK_INSET, -CHECK_INSET)
    mark:SetPoint("BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
    mark:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    box:SetCheckedTexture(mark)
    box:SetScript("OnEnter", LightBorder)
    box:SetScript("OnLeave", DarkBorder)
    return box
end

function Widgets.Star(texture, on)
    local atlas = on and STAR_ON or STAR_OFF
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        texture:SetDesaturated(false)
        texture:SetAlpha(1)
    else
        texture:SetTexture(REPUTATION_STAR)
        texture:SetTexCoord(on and 0 or HALF, on and HALF or 1, 0, HALF)
    end
end

function Widgets.StarButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(STAR_BUTTON, STAR_BUTTON)
    button.tex = button:CreateTexture(nil, "ARTWORK")
    button.tex:SetAllPoints()
    return button
end

function Widgets.ShowSearch(button, name, nameText, parent)
    button.itemName = S.Get("ahSearch") and P.AH.Open() and name or nil
    button:SetShown(button.itemName ~= nil)
    if not nameText then return end
    if button:IsShown() then
        nameText:SetPoint("RIGHT", button, "LEFT", -SEARCH_GAP, 0)
    else
        nameText:SetPoint("RIGHT", parent, "RIGHT", -SEARCH_EDGE, 0)
    end
end

function Widgets.QtyBox(parent)
    local qty = ns.NewEditBox(parent)
    qty:SetSize(Style.QTY_W, Style.BUTTON_H)
    qty:SetNumeric(true)
    qty:SetMaxLetters(Style.QTY_LETTERS)
    qty:SetJustifyH("CENTER")
    qty:SetText("1")
    qty:SetScript("OnEscapePressed", qty.ClearFocus)
    qty:SetScript("OnEnterPressed", qty.ClearFocus)
    return qty
end
