-------------------------------------------------------------------------------
--  NaowhForever_MapPinsPanel.lua -- the Map Pins button in the world map's top right corner.
--  It opens a panel with the town map's switches: which kinds of pin show, Vendors & Trainers
--  Only in Cities and the minimap pins. The options window keeps only the card's switch and
--  Pin Size; the rest is chosen with the map open.
--
--  The keys stay in the QoL table, so saved settings carry over. Free while the map pins are
--  off: the button and the panel are made the first time they are on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME
local S = ns.QoLSettings

-- The panel's rows in order.
local ROWS = {
    { header = "OPTIONS" },
    { key = "townCapitalsOnly", text = "Vendors & Trainers Only in Cities",
      tip = "Keeps vendors, trainers and the bank off questing maps." },
    { key = "townMinimap", text = "Mailboxes on Minimap", tip = "Pins the mailboxes near you on the minimap." },
    { key = "townMinimapSpirit", text = "Spirit Healers on Minimap",
      tip = "Pins the spirit healers near you on the minimap." },
    { header = "SHOW" },
    { key = "townFlight", text = "Flight Masters" },
    { key = "townInn", text = "Innkeepers" },
    { key = "townMail", text = "Mailboxes", tip = "Every mailbox, in towns and out in the world." },
    { key = "townSpiritHealers", text = "Spirit Healers",
      tip = "Every graveyard's spirit healer, in towns and out in the world." },
    { key = "townZoneLinks", text = "Zone Exits", tip = "Click an exit to open the adjoining zone map." },
    { key = "townTravel", text = "Boats & Zeppelins",
      tip = "Every dock and zeppelin tower; click one to open where it goes." },
    { key = "townClass", text = "Class Trainers", tip = "Your class's trainers only." },
    { key = "townProfession", text = "Profession Trainers" },
    { key = "townBank", text = "Bank & Auction House" },
    { key = "townRepair", text = "Repairs" },
    { key = "townSupplies", text = "Reagents, Ammo & Food" },
    { key = "townStable", text = "Stable Masters" },
    { key = "townVendors", text = "Other Vendors", tip = "Trade goods and every other merchant." },
}

local function On()
    return S.Get("enabled") and S.Get("townMap")
end

-------------------------------------------------------------------------------
--  The panel: a drawer against the map window's left side, the map's height (the Dungeon
--  Journal takes the right side). Where that side has no room, the right; on the maximized
--  map, which fills the screen, in the black bar left of its picture, or else under the button.
-------------------------------------------------------------------------------
-- The options window's look: a header strip in the panel colour, small accent group titles and
-- ruled rows with the switch on the right, on the window's backdrop with a black border.
local St = ns.Shared.Style
local PAD, HEAD_H, ROW_H, ROW_MIN_H = 14, 40, 28, 20   -- a group title takes a row's height
local LABEL_SIZE, NAME_SIZE, SMALL_SIZE = 13, 14, 11
local RULE_ALPHA = 0.6
local PANEL_W = 330   -- the quest log's width, where the map has none to read

-- As wide as the quest log beside the map, so the two drawers match.
local function PanelWidth()
    local log = WorldMapFrame.QuestLog or _G.QuestMapFrame
    local w = log and log:GetWidth() or 0
    return w > 0 and w or PANEL_W
end
local GAP = -1   -- the drawer's border on the map's, so the two read as one window
local BAR_MARGIN, BAR_MIN_W = 8, 200   -- the full screen map's black bar

local button, panel
local controls, strips = {}, {}

local function RefreshRows()
    for _, control in ipairs(controls) do control._refreshValue() end
end

local function Rule(frame, alpha)
    local rule = ns.Solid(frame, "ARTWORK", T.line, alpha or RULE_ALPHA)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    ns.Hairline(rule, "h")
end

local function Strip(parent, y, h)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(h)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, y)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, y)
    return frame
end

-- The rows under the header, each rowH high. Returns the drawer's height.
local function Layout(rowH)
    local y = -1 - HEAD_H
    for _, frame in ipairs(strips) do
        frame:SetHeight(rowH)
        frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, y)
        frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, y)
        y = y - rowH
    end
    return -y + 1
end

local function MakeGroup(parent, title, y)
    local frame = Strip(parent, y, ROW_H)
    strips[#strips + 1] = frame
    local text = ns.Font(frame, SMALL_SIZE, nil, T.accentSoft)
    text:SetPoint("BOTTOMLEFT", PAD, 7)
    text:SetText(title)
    Rule(frame)
end

local function MakeRow(parent, row, y)
    local frame = Strip(parent, y, ROW_H)
    strips[#strips + 1] = frame
    frame:EnableMouse(true)
    Rule(frame)
    local control = UI.BuildToggleControl(frame, frame:GetFrameLevel() + 2,
        function() return S.Get(row.key) end,
        function(v)
            S.Set(row.key, v)
            if UI.RefreshPage then UI:RefreshPage(true) end
        end)
    control:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    local label = ns.Font(frame, LABEL_SIZE, nil, T.fg)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetPoint("LEFT", PAD, 0)
    label:SetPoint("RIGHT", control, "LEFT", -8, 0)
    label:SetText(row.text)
    if row.tip then ns.Tooltip(frame, row.text, row.tip) end
    controls[#controls + 1] = control
end

local function PlacePanel()
    if not panel then return end
    local map = WorldMapFrame
    panel:ClearAllPoints()
    if map.IsMaximized and map:IsMaximized() then
        -- The full screen map letterboxes its picture on a wide screen: the drawer goes in the
        -- black bar on the left, as wide as the bar allows. With no bar wide enough it hangs
        -- under the Map Pins button in the top right, which stays free to close it.
        local canvas = map:GetCanvasContainer()
        local bar = (canvas:GetLeft() or 0) - (map:GetLeft() or 0) - BAR_MARGIN * 2
        if bar >= BAR_MIN_W then
            panel:SetWidth(math.min(PanelWidth(), bar))
            panel:SetPoint("TOPRIGHT", canvas, "TOPLEFT", -BAR_MARGIN, 0)
        else
            panel:SetWidth(PanelWidth())
            panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
        end
        panel:SetHeight(Layout(ROW_H))
    else
        local w = PanelWidth()
        panel:SetWidth(w)
        if (map:GetLeft() or 0) >= w + GAP then
            panel:SetPoint("TOPRIGHT", map, "TOPLEFT", -GAP, 0)
        else
            panel:SetPoint("TOPLEFT", map, "TOPRIGHT", GAP, 0)
        end
        -- The map's height: the rows shrink to fit a small map, down to ROW_MIN_H.
        local fit = math.floor((map:GetHeight() - HEAD_H - 2) / #strips)
        local h = Layout(math.max(ROW_MIN_H, math.min(ROW_H, fit)))
        panel:SetHeight(math.max(h, map:GetHeight()))
    end
end

local function BuildPanel()
    -- The map's child, so it opens, closes and scales with the map.
    panel = CreateFrame("Frame", nil, WorldMapFrame)
    panel:SetWidth(PanelWidth())
    panel:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)   -- over the map's pins, as the Journal's drawer
    panel:EnableMouse(true)
    panel:Hide()
    ns.Solid(panel, "BACKGROUND", T.bg, St.BACKDROP_ALPHA):SetAllPoints()
    ns.Border(panel, St.BORDER_RGB)

    local head = Strip(panel, -1, HEAD_H)
    ns.Solid(head, "BACKGROUND", T.panel, 1):SetAllPoints()
    Rule(head, 1)
    local title = ns.Font(head, NAME_SIZE, nil, T.fg)
    title:SetPoint("LEFT", PAD, 0)
    title:SetText("Map Pins")
    local close = ns.Button(head, "x", 22, 22, function() panel:Hide() end)
    close:SetPoint("RIGHT", -9, 0)

    for _, row in ipairs(ROWS) do
        if row.header then MakeGroup(panel, row.header, 0) else MakeRow(panel, row, 0) end
    end
    panel:SetScript("OnShow", RefreshRows)
    -- The map's size buttons move it between windowed and the whole screen.
    if WorldMapFrame.Maximize then hooksecurefunc(WorldMapFrame, "Maximize", PlacePanel) end
    if WorldMapFrame.Minimize then hooksecurefunc(WorldMapFrame, "Minimize", PlacePanel) end
end

-------------------------------------------------------------------------------
--  The map button
-------------------------------------------------------------------------------
-- In the map's top right corner, left of the buttons the map keeps there (tracking options and
-- the like) and at their size, so they read as one row. Those are found by where they sit, not
-- by name, so a map with more, fewer or none of them still gets a free spot.
local function Place()
    local canvas = WorldMapFrame:GetCanvasContainer()
    local edge, edgeX
    for _, frame in ipairs(WorldMapFrame.overlayFrames or {}) do
        if frame:IsShown() and frame:GetNumPoints() > 0 then
            local point, relative, _, x = frame:GetPoint(1)
            if point == "TOPRIGHT" and relative == canvas and (not edgeX or x < edgeX) then
                edge, edgeX = frame, x
            end
        end
    end
    button:ClearAllPoints()
    if edge then
        local w, h = edge:GetSize()
        button:SetSize(w > 0 and w or 32, h > 0 and h or 32)
        button:SetPoint("TOPRIGHT", edge, "TOPLEFT", -2, 0)
    else
        button:SetSize(32, 32)
        button:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -4, -2)
    end
end

local function BuildButton()
    button = CreateFrame("Button", nil, WorldMapFrame:GetCanvasContainer())
    button:SetFrameStrata("DIALOG")
    ns.Solid(button, "BACKGROUND", T.bg, 0.9):SetAllPoints()
    local border = ns.Border(button, St.BORDER_RGB)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\LogoSmall.tga")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    button:SetScript("OnClick", function()
        if not panel then BuildPanel() end
        PlacePanel()
        panel:SetShown(not panel:IsShown())
    end)
    button:SetScript("OnEnter", function()
        border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    end)
    button:SetScript("OnLeave", function()
        border:SetColor(St.BORDER_RGB.r, St.BORDER_RGB.g, St.BORDER_RGB.b, 1)
    end)
    ns.Tooltip(button, "Map Pins", "Click to choose which pins show on the map.")
    Place()
    WorldMapFrame:HookScript("OnShow", function()
        Place()
        PlacePanel()
    end)
end

local function Apply()
    if On() then
        if not button then BuildButton() end
        button:Show()
        if panel and panel:IsShown() then RefreshRows() end
    elseif button then
        button:Hide()
        if panel then panel:Hide() end
    end
end

-- A reset or a change in the options window shows on an open panel straight away.
hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^town") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
