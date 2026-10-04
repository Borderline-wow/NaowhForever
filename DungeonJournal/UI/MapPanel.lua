-------------------------------------------------------------------------------
--  UI/MapPanel.lua -- the Dungeon Journal beside the world map: open the map (M) inside a
--  dungeon and its bosses and loot sit on the map's right, or inside its right edge when the
--  map fills the screen. With Factions Beside the Map on, in a zone or a battleground the
--  page of a faction earned there sits in the same place (a switch when there are two).
--  Inside a dungeon with a map (Data/Maps.lua) the dungeon's map also fills the world map's
--  picture (UI/DungeonMap.lua); this file tells it when, and when another map is shown
--  (it steps aside, and the page offers Map to bring it back). And there the game's quest log
--  beside the map folds away, so the Journal sits against the map: the game's own setting
--  for it (questLogOpen, which the map reads each time it opens) is set on entering, and put
--  back as it was on leaving (kept for the account meanwhile, so a logout inside keeps it).
--  The panel is the addon's own frame; the map is only watched, with
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
local PANEL_LEVEL = 100 -- over the map: above the dungeon's map on its picture too

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
    -- The dungeon's map on the world map, while its page shows.
    J.ShowMapOnWorldMap(not pagesAreFactions and page or nil)
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
    panel.backdrop:Paint(S.Get("mapAlpha") or 1)
end

local function Build()
    panel = J.View.Parts.Panel("DUNGEON JOURNAL", true)
    panel.onWorldMap = true   -- its Map shows the dungeon's map on the world map
    panel.backdrop:Card(4, PANEL_HEADER, 4, 4)
    panel.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    panel.switch = ns.Button(panel, "Other half", 90, 20, OtherHalf)
    panel.switch:SetPoint("RIGHT", panel.close, "LEFT", -6, 0)
    panel.classOnly = ns.Button(panel, "", 90, 20, ToggleClass)
    local scroll = ns.UI.SlimScroll(panel)
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - 4)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, PANEL_PAD)
    view = J.View.New(scroll)
    view.onWorldMap = true   -- no Map: the dungeon's map is on the world map beside it
    view:SetWidth(PANEL_W - PANEL_PAD * 2 - SCROLL_GAP)
    scroll:SetScrollChild(view)
    panel.scroll = scroll
end

local function Place()
    local map = WorldMapFrame
    panel:SetFrameStrata(map:GetFrameStrata())
    -- Above the dungeon's map over the picture (UI/DungeonMap.lua), when it sits inside it.
    panel:SetFrameLevel(map:GetFrameLevel() + PANEL_LEVEL)
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
        J.ShowMapOnWorldMap(nil)
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
    J.ShowMapOnWorldMap(nil)
end

-- The map changes size when it is maximised or made small again.
local function MapResized()
    if panel and panel:IsShown() then Place() end
    J.FitMapOnWorldMap()
end

-- Inside a dungeon the Journal has: the quest log folded, what it was kept. Elsewhere, or
-- switched off: put back. Not in combat (it waits for the next loading screen).
local folder
local function FoldQuestLog()
    if InCombatLockdown() then
        -- Put back, or folded, once combat ends.
        if folder then folder:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    if folder then folder:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    local account = ns.AccountSettings()
    if On() and S.Get("mapPanel") and J.Current() then
        if account.journalQuestLogWas == nil then
            account.journalQuestLogWas = GetCVar("questLogOpen") or "1"
            SetCVar("questLogOpen", "0")
        end
    elseif account.journalQuestLogWas ~= nil then
        SetCVar("questLogOpen", account.journalQuestLogWas)
        account.journalQuestLogWas = nil
    end
end

-- The map opening puts the Journal's window away, and closing brings it back (Window.lua).
local function MapShown()
    J.WindowAwayForMap(true)
    Refresh()
end

local function MapHidden()
    Hide()
    J.WindowAwayForMap(false)
end

-- Another map shown (Blizzard's buttons, its dropdown, a right-click up to the zone): the
-- dungeon's map steps aside, and the panel's page is drawn again, offering Map to bring it
-- back.
local function MapChanged()
    if not (panel and panel:IsShown()) then return end
    local away = J.DungeonMapAway()
    J.WorldMapChanged()
    if J.DungeonMapAway() ~= away then view:Redraw() end
end

local function Hook()
    if hooked then return end
    hooked = true
    folder = CreateFrame("Frame")
    folder:SetScript("OnEvent", FoldQuestLog)
    WorldMapFrame:HookScript("OnShow", MapShown)
    WorldMapFrame:HookScript("OnHide", MapHidden)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", MapChanged)
    WorldMapFrame:HookScript("OnSizeChanged", MapResized)
end

local function HookAndRefresh()
    Hook()
    folder:RegisterEvent("PLAYER_ENTERING_WORLD")
    FoldQuestLog()
    Refresh()
end

-- Hooks the map the first time the panel is on; the map may load after this file does.
local function Sync()
    if folder then
        if On() then folder:RegisterEvent("PLAYER_ENTERING_WORLD") else folder:UnregisterAllEvents() end
    end
    -- Folded or put back; off, a quest log left folded by a logout inside is put back too.
    FoldQuestLog()
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
    elseif key == "mapAlpha" then
        -- Only the backdrop: the page itself is unchanged.
        if panel then Paint() end
    elseif panel and panel:IsShown() then
        PaintButtons()
        view:Redraw()
    end
end

S.OnChange(SettingChanged)
hooksecurefunc(ns, "Apply", Sync)
