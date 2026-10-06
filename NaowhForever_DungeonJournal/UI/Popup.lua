-------------------------------------------------------------------------------
--  UI/Popup.lua -- Boss Loot at Cursor: a key binding (Naowh Forever's own section in Key
--  Bindings) that opens a small panel at the mouse with the loot of the boss you hover, or
--  else your target, drawn by the Dungeon Journal's view: BiS marked, right-click for the
--  BiS list. In the Journal window's look, as the quest tracker and the dungeon map are: its
--  gradient faded by its Opacity, a card behind the loot, its titles' blue. Pressing the key
--  again, or the X, closes it. Nothing is made until the key is
--  first pressed, which turns the module on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal

local T = ns.THEME
local S = J.Settings
local St = J.Style
local PANEL_W, PANEL_PAD, PANEL_HEADER = St.PANEL_W, St.PANEL_PAD, St.PANEL_HEADER

local CURSOR_OFFSET = 12
local VIEW_TOP = 4   -- the card's top edge to the page, as the Journal beside the map has it

local popup, view

-- The panel grows with what the view draws, also when a late item name redraws it.
local function Drawn(height)
    popup:SetHeight(height + PANEL_HEADER + VIEW_TOP + PANEL_PAD)
end

local function Build()
    popup = J.View.Parts.Panel("", true)
    popup.backdrop:Card(4, PANEL_HEADER, 4, 4)
    popup.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    popup:SetFrameStrata("DIALOG")
    view = J.View.New(popup)
    view:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - VIEW_TOP)
    view:SetWidth(PANEL_W - PANEL_PAD * 2)
    view.onResize = Drawn
    -- Closed (its X, the key, its map): the pin that opened it is no longer ringed.
    popup:HookScript("OnHide", J.View.ForgetMapLoot)
end

local function Open(boss, dungeon)
    if not popup then Build() end
    local x, y = GetCursorPosition()
    popup:SetScale(ns.UIScale())
    local scale = popup:GetEffectiveScale()
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + CURSOR_OFFSET, y / scale - CURSOR_OFFSET)
    popup.title:SetText(dungeon.name:upper())
    popup.backdrop:Paint(S.Get("mapAlpha") or 1)
    popup:Show()
    view:DrawBossLoot(boss, dungeon)
end

-- A boss pin on the dungeon map opens the same panel, at the mouse; the map closing closes it.
J.View.OpenBossLoot = Open

function J.View.CloseBossLoot()
    if popup then popup:Hide() end
end

-- The binding's action (Bindings.xml).
function NaowhForever_BossLoot()
    if popup and popup:IsShown() then
        popup:Hide()
        return
    end
    J.TurnOn()
    local unit = UnitExists("mouseover") and "mouseover" or "target"
    if not UnitExists(unit) then
        ns.Print("Hover or target a boss, then press the key again.")
        return
    end
    -- A GUID the game keeps secret (enemies in combat, in some places) cannot be read.
    local guid = UnitGUID(unit)
    local npc = guid and not issecretvalue(guid) and J.NpcID(guid)
    if not npc then
        ns.Print("That is not a boss the Dungeon Journal can read right now.")
        return
    end
    J.View.ForgetMapLoot()
    local boss, dungeon = J.Boss(npc)
    if not boss then
        ns.Print(("%s is not a boss the Dungeon Journal knows."):format(UnitName(unit) or "That"))
        return
    end
    Open(boss, dungeon)
end

-- Turning the module off closes it.
J.Settings.OnChange(function(key, value)
    if key == "enabled" and not value and popup then popup:Hide() end
end)
