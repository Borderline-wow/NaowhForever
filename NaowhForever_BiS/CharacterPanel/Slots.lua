-- Slots.lua: a slot in the BiS List's look, laid over one of the game's slot buttons (CP.SlotOver, CP.FadeSlot, CP.CropSlot, CP.PaintEdge).
local ns = _G.NaowhForever

local CP = ns.CharacterPanel
local C = CP.C
local Shared = ns.Shared
local Items, Parts, St = Shared.Items, Shared.Parts, Shared.Style

local CROP_IN, CROP_OUT = C.CROP_IN, C.CROP_OUT
local OVER_LIFT = 3

local function Fade(button, alpha)
    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(alpha) end
    if button.IconBorder then button.IconBorder:SetAlpha(alpha) end
    if button.BorderFrame then button.BorderFrame:SetAlpha(alpha) end
end

local function Crop(button, on)
    local icon = button.icon
    if not icon then return end
    if on then icon:SetTexCoord(CROP_IN, CROP_OUT, CROP_IN, CROP_OUT) else icon:SetTexCoord(0, 1, 0, 1) end
end

local function PaintEdge(over, id)
    local color = id and Items.QualityColor(id) or St.BORDER_RGB
    over.edge:SetColor(color.r, color.g, color.b, 1)
end

local function SlotOver(button, slot)
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(button:GetFrameLevel() + OVER_LIFT)
    over.slot = slot
    over.look = CreateFrame("Frame", nil, over)
    over.look:SetAllPoints()
    over.edge = ns.Border(over.look, St.BORDER_RGB)
    local ring = CreateFrame("Frame", nil, over.look)
    ns.PixelInset(ring, C.RING_OUT, over)
    ns.Border(ring, St.BORDER_RGB)
    over.marks = Parts.ItemMarks(over, button:GetHeight())
    return over
end

CP.FadeSlot, CP.CropSlot = Fade, Crop
CP.PaintEdge = PaintEdge
CP.SlotOver = SlotOver
