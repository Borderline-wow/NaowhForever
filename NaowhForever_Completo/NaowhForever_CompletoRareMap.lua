-------------------------------------------------------------------------------
--  NaowhForever_CompletoRareMap.lua -- rares on the world map: one star for each rare you have
--  not killed, the game's rare star, where it is most likely to be (the spot Wowhead saw it
--  at most, or the middle of the way it patrols); with Show Killed Rares a grey one for those
--  you have. Hover a star for the rare: its other spawn spots show as smaller stars and its
--  way, if it patrols, as a trail of small ones, until you move off it; every other rare's
--  star fades meanwhile. Click a star for a waypoint, as every pin of ours. Right-click it to
--  keep it so (focus it) after you move off, with a panel beside it: the rare and its drops,
--  each drop's item tooltip on hover. Right-click it again, another star, or the panel's close
--  button to let go. Built like the quest giver pins (NaowhForever_CompletoMap.lua).
--
--  Off until Rare Pins is switched on: then a data provider on the world map, redrawn when a
--  rare is killed or ticked off while the map is open.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.CompletoSettings
local R = ns.Completo.Rares
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local TEMPLATE = "NaowhForeverRarePinTemplate"
-- The game's rare star; the skull raid mark where the client has no such atlas.
local STAR_ATLAS = "VignetteKill"
local SKULL_FILE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local KILLED_ALPHA = 0.7
-- What a hovered star shows, against the star: its other spawn spots ("spot") and the dots
-- along its way ("dot"); size and alpha of each.
local KINDS = { spot = { 0.7, 0.9 }, dot = { 0.45, 0.8 } }
local LIT_SCALE = 1.3                      -- the hovered rare's star
local FADED_ALPHA = 0.2                    -- every other rare's, while one is hovered

local function On()
    return S.Get("enabled") and S.Get("rarePins")
end

local function SoftBlue(r, g, b)
    local c = ns.ThemeTint("accentSoft", nil)
    if c then return c.r, c.g, c.b end
    return r, g, b
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
-- A global so the XML template can name it.
NaowhForeverRarePinMixin = CreateFromMixins(MapCanvasPinMixin)

function NaowhForeverRarePinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

-- The map calls this on every acquired pin, and its SetPassThroughButtons is protected: from
-- our refresh it is blocked in combat. These pins want their clicks, so there is nothing to
-- pass through.
function NaowhForeverRarePinMixin:CheckMouseButtonPassthrough() end

-- Not smaller on the small map than on the full-screen one.
NaowhForeverRarePinMixin.ApplyCurrentScale = ns.Completo.ScalePin

-- How it looks: as drawn, or while a rare is hovered (lit: this pin's rare; else faded).
local function Look(pin, lit, faded)
    local kind = KINDS[pin.kind]
    local size = S.Get("rarePinSize") * (kind and kind[1] or 1)
    if lit and not kind then size = size * LIT_SCALE end
    pin:SetSize(size, size)
    local alpha = kind and kind[2] or 1
    if pin.killed then alpha = alpha * KILLED_ALPHA end
    if lit and not kind then alpha = 1 elseif faded then alpha = FADED_ALPHA end
    pin.Icon:SetAlpha(alpha)
end

-- spot: { npc, x, y (percent), kind: nil for a rare's star, "spot" or "dot" for what its
-- hover shows }.
function NaowhForeverRarePinMixin:OnAcquired(spot)
    self.npc, self.spotX, self.spotY, self.kind = spot.npc, spot.x, spot.y, spot.kind
    self.killed = R.Killed(spot.npc)
    -- The star a level above what its hover shows, so nothing covers it.
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI", spot.kind and 0 or 1)
    -- Those take no mouse: the pointer stays on the star they belong to.
    self:EnableMouse(not spot.kind)
    local icon = self.Icon
    if not icon:SetAtlas(STAR_ATLAS) then icon:SetTexture(SKULL_FILE) end
    icon:SetDesaturated(self.killed)
    Look(self)
    self:SetPosition(spot.x / 100, spot.y / 100)
    if self.ApplyCurrentScale then self:ApplyCurrentScale() end
end

local provider
local focused       -- the rare clicked: shown as when hovered, until clicked again
local shown = {}    -- the pins a hovered star shows, until the pointer leaves it
local spot = {}     -- handed to each pin; OnAcquired copies what it needs

-- The points from the first'th on ({ x, y, ... }), as pins of that kind; kept in into.
local function Place(map, npc, points, first, kind, into)
    for i = first * 2 - 1, points and #points or 0, 2 do
        spot.npc, spot.x, spot.y, spot.kind = npc, points[i], points[i + 1], kind
        local pin = map:AcquirePin(TEMPLATE, spot)
        if into then into[#into + 1] = pin end
    end
end

-- A rare's other spawn spots and its way, while its star is hovered; nil takes them away.
local function ShowMore(npc)
    local map = provider and provider:GetMap()
    if not map then return end
    for i = #shown, 1, -1 do
        map:RemovePin(shown[i])
        shown[i] = nil
    end
    if not npc then return end
    Place(map, npc, R.Trail(npc), 1, "dot", shown)
    Place(map, npc, R.Spots(npc), 2, "spot", shown)
end

-- npc: the rare hovered, its pins lit and the rest faded; nil puts every pin back.
local function Highlight(npc)
    local map = provider and provider:GetMap()
    if not map then return end
    for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
        Look(pin, npc ~= nil and pin.npc == npc, npc ~= nil and pin.npc ~= npc)
    end
end

-- The rare's tooltip, beside its star: what it is, whether you killed it, where else it is,
-- its loot.
local function ShowTip(pin)
    local npc, m = pin.npc, T.muted
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(R.Name(npc), 1, 1, 1)
    local low, high = R.Levels(npc)
    local level = low <= 0 and "??" or low == high and tostring(low) or ("%d-%d"):format(low, high)
    GameTooltip:AddLine(("%s, level %s"):format(R.Elite(npc) and "Rare elite" or "Rare", level), 1, 0.82, 0)
    local record = R.Record(npc)
    if record then
        local have = St.HAVE_RGB
        GameTooltip:AddLine(record.n > 1 and ("Killed %d times"):format(record.n) or "Killed", have.r, have.g, have.b)
    else
        GameTooltip:AddLine("Not killed yet", 1, 1, 1)
    end
    local others = R.SpotCount(npc) - 1
    if R.Trail(npc) then
        GameTooltip:AddLine("Patrols: the small stars are its way", m.r, m.g, m.b)
    end
    if others > 0 then
        GameTooltip:AddLine(("Spawns at %d more spots, shown smaller"):format(others), m.r, m.g, m.b)
    end
    R.AddLoot(GameTooltip, npc)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click for a waypoint, right-click to keep its route shown.", SoftBlue(0.3, 0.71, 0.96))
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  The focused rare's panel: beside its star, the house panel with the rare's name, what the
--  tooltip says, its drops as rows you can hover (the item's own tooltip) or right-click (its
--  Wowhead link), and buttons for a waypoint and its row in Completo. Made on first use.
-------------------------------------------------------------------------------
local PANEL_W, PAD, HEADER = St.PANEL_W, St.PANEL_PAD, St.PANEL_HEADER
local DROP_H, DROP_ICON, TICK = 20, 16, 14
local BUTTON_H, BUTTON_GAP = 24, 4
local GOLD = { r = 1, g = 0.82, b = 0 }
local panel
local lineN, lineY   -- ShowPanel's place: lines written, the y under them

local function QualityColor(quality)
    return ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or T.fg
end

local function DropEnter(row)
    row.hover:Show()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.item[1])
    if R.NewInForever(row.item) then GameTooltip:AddLine(Parts.ForeverLine()) end
    if row.tick:IsShown() then
        local have = St.HAVE_RGB
        GameTooltip:AddLine("This rare dropped it for you.", have.r, have.g, have.b)
    end
    GameTooltip:AddLine("Right-click: Wowhead link", SoftBlue(0.3, 0.71, 0.96))
    GameTooltip:Show()
end

local function DropLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function DropClick(row, button)
    if button == "RightButton" then Parts.CopyWowhead("item", row.item[1], row.item[4]) end
end

local function NewDropRow()
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(PANEL_W - PAD * 2, DROP_H)
    row:RegisterForClicks("RightButtonUp")
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.06)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.icon = Parts.ItemIcon(row, DROP_ICON)
    row.icon:SetPoint("LEFT", 2, 0)
    row.chance = ns.Font(row, 11, nil, T.muted)
    row.chance:SetPoint("RIGHT", -2, 0)
    row.chance:SetJustifyH("RIGHT")
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(St.TICK, nil, nil, "TRILINEAR")
    row.tick:SetSize(TICK, TICK)
    row.tick:SetVertexColor(St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b)
    row.tick:SetPoint("RIGHT", row.chance, "LEFT", -6, 0)
    row.name = ns.Font(row, 12, nil, T.fg)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.tick, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", DropEnter)
    row:SetScript("OnLeave", DropLeave)
    row:SetScript("OnClick", DropClick)
    return row
end

local Rest

local function LetGo()
    focused = nil
    Rest()
end

local function PanelWaypoint()
    local pin = panel.pin
    if pin then ns.PlaceWaypoint(R.Name(pin.npc), R.Map(pin.npc), pin.spotX, pin.spotY) end
end

-- The panel would sit over the window (DIALOG over HIGH): it goes, with the focus.
local function OpenInCompleto()
    local npc = panel.npc
    LetGo()
    ns.OpenCompletoWindow("rares", npc)
end

local function BuildPanel()
    panel = Parts.Panel("")
    panel:SetParent(WorldMapFrame)
    panel:SetFrameStrata("DIALOG")
    panel.close._onClick = LetGo
    panel.lines = {}
    panel.rows = {}
    local width = (PANEL_W - PAD * 2 - BUTTON_GAP) / 2
    panel.waypoint = ns.Button(panel, "Set a Waypoint", width, BUTTON_H, PanelWaypoint)
    panel.waypoint:SetPoint("BOTTOMLEFT", PAD, PAD)
    panel.open = ns.Button(panel, "Open in Completo", width, BUTTON_H, OpenInCompleto)
    panel.open:SetPoint("LEFT", panel.waypoint, "RIGHT", BUTTON_GAP, 0)
    panel:Hide()
end

-- The next text line, at y below the panel's top; returns the y under it.
local function Line(i, y, text, color)
    local fs = panel.lines[i]
    if not fs then
        fs = ns.Font(panel, 12, nil, T.fg)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(PANEL_W - PAD * 2)
        panel.lines[i] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", PAD, -y)
    fs:SetText(text)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:Show()
    return y + math.ceil(fs:GetStringHeight()) + 3
end

local function Add(text, color)
    lineN = lineN + 1
    lineY = Line(lineN, lineY, text, color)
end

-- Drawn once per focus: a pointer moving between stars leaves it as it is.
-- Beside the star on the side with room, as Parts.ShowBeside places a side panel: clamped to
-- the screen, it would otherwise slide back over the star and its route.
local function PlacePanel(pin)
    panel:ClearAllPoints()
    local right = (pin:GetRight() or 0) * pin:GetEffectiveScale()
    local room = UIParent:GetRight() * UIParent:GetEffectiveScale() - right
    if room >= (PANEL_W + 8) * panel:GetEffectiveScale() then
        panel:SetPoint("TOPLEFT", pin, "TOPRIGHT", 8, 0)
    else
        panel:SetPoint("TOPRIGHT", pin, "TOPLEFT", -8, 0)
    end
end

local function ShowPanel(pin)
    if not panel then BuildPanel() end
    local npc = pin.npc
    if panel:IsShown() and panel.npc == npc and panel.pin == pin then return end
    panel.npc, panel.pin = npc, pin
    panel.title:SetText(R.Name(npc))
    for _, fs in ipairs(panel.lines) do fs:Hide() end
    for _, row in ipairs(panel.rows) do row:Hide() end
    lineN, lineY = 0, HEADER
    local low, high = R.Levels(npc)
    local level = low <= 0 and "??" or low == high and tostring(low) or ("%d-%d"):format(low, high)
    Add(("%s, level %s"):format(R.Elite(npc) and "Rare elite" or "Rare", level), GOLD)
    local record = R.Record(npc)
    Add(record and (record.n > 1 and ("Killed %d times"):format(record.n) or "Killed") or "Not killed yet",
        record and St.HAVE_RGB or T.fg)
    if R.Trail(npc) then Add("Patrols: the small stars are its way", T.muted) end
    local others = R.SpotCount(npc) - 1
    if others > 0 then Add(("Spawns at %d more spots, shown smaller"):format(others), T.muted) end
    local loot = R.Loot(npc)
    lineY = lineY + 6
    if loot then
        Add("Drops", GOLD)
        for i, item in ipairs(loot) do
            local row = panel.rows[i] or NewDropRow()
            panel.rows[i] = row
            row.item = item
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -lineY)
            row.icon.texture:SetTexture(C_Item.GetItemIconByID(item[1]) or 134400)
            local name = item[4]
            if R.NewInForever(item) then name = name .. Parts.ForeverInline(12) end
            row.name:SetText(name)
            local c = QualityColor(item[2])
            row.name:SetTextColor(c.r, c.g, c.b)
            row.tick:SetShown(R.Dropped(npc, item[1]))
            local chance = item[3]
            row.chance:SetText(chance >= 1 and ("%d%%"):format(math.floor(chance + 0.5)) or ("%.1f%%"):format(chance))
            row:Show()
            lineY = lineY + DROP_H
        end
        if loot.more then Add(("And %d more"):format(loot.more), T.muted) end
    else
        Add("No special drops", T.muted)
    end
    panel:SetHeight(lineY + PAD + BUTTON_H + PAD)
    PlacePanel(pin)
    panel:Show()
end

local function HidePanel()
    if panel then
        panel:Hide()
        panel.npc, panel.pin = nil, nil
    end
end

function NaowhForeverRarePinMixin:OnMouseEnter()
    -- The focused rare's star has its panel up already.
    if self.npc ~= focused then ShowTip(self) end
    ShowMore(self.npc)
    Highlight(self.npc)
end

-- Back to the focused rare, if one is, its panel up beside its star; else every rare as
-- drawn, and no panel.
function Rest()
    ShowMore(focused)
    Highlight(focused)
    local map = provider and provider:GetMap()
    if focused and map then
        for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
            if pin.npc == focused and not pin.kind then return ShowPanel(pin) end
        end
    end
    HidePanel()
end

function NaowhForeverRarePinMixin:OnMouseLeave()
    GameTooltip:Hide()
    Rest()
end

-- Click: a waypoint to this star; right-click: focus the rare, or let go of the one focused.
function NaowhForeverRarePinMixin:OnClick(button)
    if button == "LeftButton" then
        ns.PlaceWaypoint(R.Name(self.npc), R.Map(self.npc), self.spotX, self.spotY)
    elseif button == "RightButton" then
        focused = focused ~= self.npc and self.npc or nil
        GameTooltip:Hide()
        Rest()
        -- Let go of while still under the pointer: as hovered again.
        if not focused then self:OnMouseEnter() end
    end
end

-------------------------------------------------------------------------------
--  The map's data provider
-------------------------------------------------------------------------------
provider = CreateFromMixins(MapCanvasDataProviderMixin)

-- The map panned, zoomed or resized: the star may have moved to the other side.
local function Reside()
    if panel and panel:IsShown() and panel.pin then PlacePanel(panel.pin) end
end
provider.OnCanvasScaleChanged = Reside
provider.OnCanvasPanChanged = Reside
provider.OnCanvasSizeChanged = Reside

function provider:RemoveAllData()
    wipe(shown)
    HidePanel()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

-- One star per rare: its first spot, where it was seen most (R.Spots's order).
function provider:RefreshAllData()
    self:RemoveAllData()
    if not On() then return end
    local map = self:GetMap()
    local killedToo = S.Get("rarePinsKilled")
    local still = false
    for _, npc in ipairs(R.OnMap(map:GetMapID())) do
        if killedToo or not R.Killed(npc) then
            local spots = R.Spots(npc)
            spot.npc, spot.x, spot.y, spot.kind = npc, spots[1], spots[2], nil
            map:AcquirePin(TEMPLATE, spot)
            if npc == focused then still = true end
        end
    end
    -- The focused rare stays so while it is on the map shown; another map lets go of it.
    if not still then focused = nil end
    Rest()
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local added

local function Redraw()
    if added and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

local function Apply()
    if On() and not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    Redraw()
end

-- A rare killed or ticked off: its star goes, or turns grey.
R.OnChange(function()
    if On() then Redraw() end
end)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "rarePins" or key == "rarePinsKilled" or key == "rarePinSize" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local OFF = "Turn on Completo"
local function Enabled() return S.Get("enabled") == true end

Settings.Page("Completo/Rares", S):Card({
    id = "rarePins", name = "Map Pins", order = 30, switch = "rarePins",
    help = "A star on the world map for every rare you have not killed, where it is most likely to be. "
        .. "Hover one for its other spawn spots and, if it patrols, its way; click it for a waypoint, "
        .. "right-click it to keep them shown with a panel of its drops.",
    summary = function(store)
        return store.Get("rarePinsKilled") and "Every rare, the ones you killed in grey"
            or "The rares you have not killed"
    end,
    rows = {
        { key = "rarePinsKilled", label = "Show Killed Rares", toggle = true, needs = Enabled, why = OFF,
          help = "Also a grey star on the map for the rares you have killed." },
        { key = "rarePinSize", label = "Pin Size", slider = { 12, 32, 1 }, needs = Enabled, why = OFF,
          help = "How big the stars are on the map." },
    },
})
