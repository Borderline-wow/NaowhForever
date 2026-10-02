-------------------------------------------------------------------------------
--  UI/MapPanel.lua -- the Dungeon Journal beside the world map: open the map (M) inside a
--  dungeon and its bosses and loot sit on the map's right, or inside its right edge when the
--  map fills the screen. With Factions Beside the Map on, in a zone or a battleground the
--  page of a faction earned there sits in the same place (a switch when there are two). The panel is the addon's own frame; the map is only watched, with
--  HookScript, and the hooks go on the first time the panel is switched on. Until then, and
--  whenever it is off, nothing runs.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings

local St = J.Style
local PANEL_W, PANEL_PAD, PANEL_HEADER = St.PANEL_W, St.PANEL_PAD, St.PANEL_HEADER

local SCROLL_GAP = 20   -- the view's right edge to the panel's, for the scrollbar

local panel, view
local hooked, waitingForMap = false, false
-- What the panel shows: the dungeons of the instance you are in (Blackrock Spire holds two),
-- or the factions earned where you are; shownIndex is the one drawn.
local pages, pagesAreFactions, shownIndex = nil, false, 1
local factionsHere = {}

local function On()
    return S.Get("enabled") and (S.Get("mapPanel") or S.Get("mapFactions"))
end

local function DrawShown()
    local page = pages[shownIndex]
    if pagesAreFactions then view:DrawFaction(page) else view:Draw(page) end
end

-- Two dungeons in one instance, or two factions in one zone: this flips between them.
local function OtherHalf()
    if not pages then return end
    shownIndex = shownIndex % #pages + 1
    DrawShown()
    panel.scroll:SetVerticalScroll(0)
end

-- My Class Only, the same setting as the window's; the settings listener redraws the panel.
local function ToggleClass()
    S.Set("usableOnly", not S.Get("usableOnly"))
end

-- In the Journal window's look rather than the plain dark panel's, so the two match: its
-- gradient faded by its Opacity, its card behind the page, and its titles' blue.
local function Paint()
    panel.backdrop:Paint(S.Get("windowAlpha") or 1)
end

local function Build()
    panel = J.View.Parts.Panel("DUNGEON JOURNAL", true)
    panel.backdrop:Card(4, PANEL_HEADER, 4, 4)
    panel.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    panel.switch = ns.Button(panel, "Other half", 90, 20, OtherHalf)
    panel.switch:SetPoint("RIGHT", panel.close, "LEFT", -6, 0)
    panel.classOnly = ns.Button(panel, "", 90, 20, ToggleClass)
    local scroll = ns.UI.SlimScroll(panel)
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - 4)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, PANEL_PAD)
    view = J.View.New(scroll)
    view:SetWidth(PANEL_W - PANEL_PAD * 2 - SCROLL_GAP)
    scroll:SetScrollChild(view)
    panel.scroll = scroll
end

local function Place()
    local map = WorldMapFrame
    panel:SetFrameStrata(map:GetFrameStrata())
    panel:SetFrameLevel(map:GetFrameLevel() + 20)
    panel:SetScale(ns.UIScale())
    panel:ClearAllPoints()
    local mapRight = (map:GetRight() or 0) * map:GetEffectiveScale()
    local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale()
    if screenRight - mapRight >= (PANEL_W + 8) * panel:GetEffectiveScale() then
        panel:SetPoint("TOPLEFT", map, "TOPRIGHT", 4, 0)
        panel:SetPoint("BOTTOMLEFT", map, "BOTTOMRIGHT", 4, 0)
    else
        panel:SetPoint("TOPRIGHT", map, "TOPRIGHT", -8, -70)
        panel:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -8, 8)
    end
end

-- The header's buttons for what it shows and the setting.
local function PaintButtons()
    local two = #pages > 1
    panel.switch:SetShown(two)
    ns.SetButtonText(panel.switch, pagesAreFactions and "Other faction" or "Other half")
    panel.classOnly:ClearAllPoints()
    panel.classOnly:SetPoint("RIGHT", two and panel.switch or panel.close, "LEFT", -6, 0)
    ns.SetButtonText(panel.classOnly, S.Get("usableOnly") and "My class" or "All classes")
end

-- What to show where you are: a dungeon's page inside one, else the factions earned here.
local function Pick()
    pages, pagesAreFactions = nil, false
    if not (On() and WorldMapFrame:IsShown()) then return end
    local here = S.Get("mapPanel") and J.Current()
    if here then
        pages = here
    elseif S.Get("mapFactions") and #J.FactionsHere(factionsHere) > 0 then
        pages, pagesAreFactions = factionsHere, true
    end
end

-- Shown on the map where there is something to show, from its top.
local function Refresh()
    Pick()
    if not pages then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build() end
    if shownIndex > #pages then shownIndex = 1 end
    Paint()
    PaintButtons()
    Place()
    panel:Show()
    DrawShown()
    panel.scroll:SetVerticalScroll(0)
end

local function Hide()
    if panel then panel:Hide() end
end

-- The map changes size when it is maximised or made small again.
local function MapResized()
    if panel and panel:IsShown() then Place() end
end

local function Hook()
    if hooked then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", Refresh)
    WorldMapFrame:HookScript("OnHide", Hide)
    WorldMapFrame:HookScript("OnSizeChanged", MapResized)
end

local function HookAndRefresh()
    Hook()
    Refresh()
end

-- Hooks the map the first time the panel is on; the map may load after this file does.
local function Sync()
    if not On() then
        Hide()
        return
    end
    if WorldMapFrame then
        HookAndRefresh()
    elseif not waitingForMap then
        waitingForMap = true
        EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", HookAndRefresh)
    end
end

-- Switched on or off: shown or hidden. Anything else it shows: drawn again where it is.
local function SettingChanged(key)
    if key == "enabled" or key == "mapPanel" or key == "mapFactions" then
        Sync()
        if hooked then Refresh() end
    elseif key == "windowAlpha" then
        -- Only the backdrop: the page itself is unchanged.
        if panel then Paint() end
    elseif panel and panel:IsShown() then
        PaintButtons()
        view:Redraw()
    end
end

S.OnChange(SettingChanged)
hooksecurefunc(ns, "Apply", Sync)
