-- Grid.lua: Unlock Mode's grid, counted out from the screen's centre.
local ns = _G.NaowhForever
local T = ns.THEME
local H = ns.HudEditor

local Pixel = H.Pixel

local GRID_STEP = 40
local GRID_MAJOR = 5
local GRID_LINE_ALPHA = 0.08
local GRID_MAJOR_ALPHA = 0.18
local GRID_CENTER_ALPHA = 0.6
local GRID_MARK = 5
local AXES = { true, false }

local grid
local used = 0
local screen = {}

local function GridLine(upright, along, color, alpha)
    used = used + 1
    local line = grid.lines[used]
    if not line then
        line = grid:CreateTexture(nil, "BACKGROUND")
        grid.lines[used] = line
    end
    line:SetColorTexture(color.r, color.g, color.b, alpha)
    line:ClearAllPoints()
    if upright then
        line:SetSize(screen.px, screen.h)
        line:SetPoint("TOPLEFT", UIParent, "TOPLEFT", PixelUtil.GetNearestPixelSize(screen.cx + along, screen.scale), 0)
    else
        line:SetSize(screen.w, screen.px)
        line:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -PixelUtil.GetNearestPixelSize(screen.cy - along, screen.scale))
    end
    line:Show()
end

local function DrawMark()
    local px, cx, cy = screen.px, screen.cx, screen.cy
    local inset = (GRID_MARK - 1) / 2 * px
    grid.mark:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    grid.mark:SetSize(GRID_MARK * px, GRID_MARK * px)
    grid.mark:ClearAllPoints()
    grid.mark:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx - inset, -(cy - inset))
end

local function DrawGrid()
    screen.w, screen.h = UIParent:GetWidth(), UIParent:GetHeight()
    screen.scale, screen.px = UIParent:GetEffectiveScale(), Pixel()
    screen.cx = PixelUtil.GetNearestPixelSize(screen.w / 2, screen.scale)
    screen.cy = PixelUtil.GetNearestPixelSize(screen.h / 2, screen.scale)
    used = 0
    for _, upright in ipairs(AXES) do
        for i = 1, math.floor((upright and screen.cx or screen.cy) / GRID_STEP) do
            local alpha = i % GRID_MAJOR == 0 and GRID_MAJOR_ALPHA or GRID_LINE_ALPHA
            GridLine(upright, i * GRID_STEP, T.fg, alpha)
            GridLine(upright, -i * GRID_STEP, T.fg, alpha)
        end
        GridLine(upright, 0, T.accent, GRID_CENTER_ALPHA)
    end
    for i = used + 1, #grid.lines do grid.lines[i]:Hide() end
    DrawMark()
end

function ns.SetAnchorGridShown(shown)
    if not shown then
        if grid then grid:Hide() end
        return
    end
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid:SetAllPoints()
        grid.lines = {}
        grid.mark = grid:CreateTexture(nil, "BORDER")
    end
    DrawGrid()
    grid:Show()
end
