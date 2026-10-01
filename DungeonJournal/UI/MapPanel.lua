-------------------------------------------------------------------------------
--  UI/MapPanel.lua -- the Dungeon Journal beside the world map: open the map (M) inside a
--  dungeon and its bosses and loot sit on the map's right, or inside its right edge when the
--  map fills the screen. The panel is the addon's own frame; the map is only watched, with
--  HookScript, and the hooks go on the first time the panel is switched on. Until then, and
--  whenever it is off, nothing runs.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings

local St = J.Style
local PANEL_W, PANEL_PAD, PANEL_HEADER = St.PANEL_W, St.PANEL_PAD, St.PANEL_HEADER

local SCROLL_GAP = 20   -- the view's right edge to the panel's, for the scrollbar

local panel, view
local hooked, waitingForMap = false, false
local shownIndex = 1   -- which dungeon of the instance is drawn; Blackrock Spire has two

local function On()
    return S.Get("enabled") and S.Get("mapPanel")
end

-- Blackrock Spire is two dungeons in one instance: this flips between them.
local function OtherHalf()
    local here = J.Current()
    if not here then return end
    shownIndex = shownIndex % #here + 1
    view:Draw(here[shownIndex])
end

-- My Class Only, the same setting as the window's; the settings listener redraws the panel.
local function ToggleClass()
    S.Set("usableOnly", not S.Get("usableOnly"))
end

local function Build()
    panel = J.View.Parts.Panel("DUNGEON JOURNAL")
    panel.switch = ns.Button(panel, "Other half", 76, 20, OtherHalf)
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

-- The header's buttons for this instance and setting.
local function PaintButtons(here)
    panel.switch:SetShown(#here > 1)
    panel.classOnly:ClearAllPoints()
    panel.classOnly:SetPoint("RIGHT", #here > 1 and panel.switch or panel.close, "LEFT", -6, 0)
    ns.SetButtonText(panel.classOnly, S.Get("usableOnly") and "My class" or "All classes")
end

-- Shown on the map inside a dungeon, from its top.
local function Refresh()
    local here = On() and WorldMapFrame:IsShown() and J.Current()
    if not here then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build() end
    if shownIndex > #here then shownIndex = 1 end
    PaintButtons(here)
    Place()
    panel:Show()
    view:Draw(here[shownIndex])
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
    if key == "enabled" or key == "mapPanel" then
        Sync()
    elseif panel and panel:IsShown() then
        local here = J.Current()
        if here then PaintButtons(here) end
        view:Redraw()
    end
end

S.OnChange(SettingChanged)
hooksecurefunc(ns, "Apply", Sync)
