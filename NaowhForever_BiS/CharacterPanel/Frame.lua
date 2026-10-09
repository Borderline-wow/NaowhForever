-- Frame.lua: the Naowh frame both panels wear: backdrop, title rule, logo and close cross, the model's panel and the split (CP.Chrome, CP.ModelPanel, CP.Split).
local ns = _G.NaowhForever

local T = ns.THEME
local CP = ns.CharacterPanel
local C = CP.C
local St = ns.Shared.Style
local Parts = ns.Shared.Parts

local HEADER = 20
local LOGO = 14
local LOGO_IN = 6
local MODEL_INSET = 4
local CLOSE = 10
local TITLE_SIZE, LEVEL_SIZE = C.TEXT_SIZE, 14
local BACKDROP_ALPHA = St.BACKDROP_ALPHA
local MODEL_ALPHA = 0.35

local function CloseCross(close)
    local cross = close:CreateTexture(nil, "OVERLAY")
    cross:SetTexture(St.CROSS, nil, nil, C.FILTER)
    cross:SetSize(CLOSE, CLOSE)
    cross:SetPoint("CENTER")
    cross:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    close:HookScript("OnEnter", function() cross:SetVertexColor(T.fg.r, T.fg.g, T.fg.b) end)
    close:HookScript("OnLeave", function() cross:SetVertexColor(T.muted.r, T.muted.g, T.muted.b) end)
    return cross
end

CP.HEADER, CP.TITLE_SIZE, CP.LEVEL_SIZE, CP.MODEL_ALPHA = HEADER, TITLE_SIZE, LEVEL_SIZE, MODEL_ALPHA

function CP.Chrome(frame)
    local back = CreateFrame("Frame", nil, frame)
    back:SetAllPoints()
    back:SetFrameLevel(frame:GetFrameLevel())
    back.backdrop = Parts.Backdrop(back)
    back.backdrop:Paint(BACKDROP_ALPHA)
    ns.Border(back, St.BORDER_RGB)
    local rule = ns.Solid(back, "ARTWORK", St.BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -HEADER)
    rule:SetPoint("TOPRIGHT", 0, -HEADER)
    ns.Hairline(rule, "h")
    local logo = back:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(St.LOGO_SMALL, nil, nil, C.FILTER)
    logo:SetSize(LOGO, LOGO)
    logo:SetPoint("LEFT", back, "TOPLEFT", LOGO_IN, -HEADER / 2)
    local close = frame.CloseButton
    if close then back.cross = CloseCross(close) end
    return back
end

function CP.ModelPanel(back, box)
    local panel = ns.Solid(back, "BACKGROUND", T.panel, MODEL_ALPHA)
    panel:SetPoint("TOPLEFT", box, "TOPLEFT", MODEL_INSET, -MODEL_INSET)
    panel:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -MODEL_INSET, MODEL_INSET)
    return panel
end

function CP.Split(back, pane)
    local split = ns.Solid(back, "ARTWORK", St.BORDER_RGB, 1)
    split:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    split:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    ns.Hairline(split, "v")
    return split
end
