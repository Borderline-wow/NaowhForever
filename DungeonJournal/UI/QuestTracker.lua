-------------------------------------------------------------------------------
--  UI/QuestTracker.lua -- a dungeon's quests in a small window of their own, to keep on
--  screen while you run it: each quest on one line, with its mark, its chain, who in your
--  group has it and its waypoint, all as on the Journal's page (hover for the quest, click
--  one in your log for its details, right-click for its menu, the group icon to ask for a
--  share, the pin's right-click to share where it is). Opened from Tracker on the Dungeon
--  Quests title of a dungeon's page, and moved anywhere by its title; while it is open it
--  follows you into the next dungeon the Journal lists. Made the first time it is opened;
--  closed, it listens to nothing.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings

local St = J.Style
local PANEL_PAD, PANEL_HEADER = St.PANEL_PAD, St.PANEL_HEADER

local TRACKER_W = 420     -- room for a quest's name beside its icons
local MAX_H = 420         -- taller than this, it scrolls
local SCROLL_GAP = 20     -- the view's right edge to the window's, for the scrollbar
local SHARE_W, SHARE_H = 52, 20
local TITLE_RIGHT = -34 - SHARE_W - 4   -- the title stops short of Share and the close button

local panel, view
local shown               -- the dungeon it shows

-- Where you left it, kept for the account.
local function SavePosition()
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    ns.AccountSettings().journalTracker = { point, relativePoint, x, y }
end

local function Place()
    panel:ClearAllPoints()
    local saved = ns.AccountSettings().journalTracker
    if type(saved) == "table" and type(saved[1]) == "string" then
        panel:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    end
end

-- As tall as its quests, up to MAX_H.
local function Fit(height)
    panel:SetHeight(math.min(MAX_H, PANEL_HEADER + 4 + height + PANEL_PAD))
end

local function Draw(dungeon)
    shown = dungeon
    panel.title:SetText(dungeon.name:upper())
    view:DrawTracker(dungeon)
end

-- PLAYER_ENTERING_WORLD: a new instance, and its dungeon when the Journal lists one.
local function OnEvent()
    local here = J.Current()
    if here and here[1] ~= shown then Draw(here[1]) end
end

local function DragStop(frame)
    frame:StopMovingOrSizing()
    SavePosition()
end

local function OnShow(frame)
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function OnHide(frame)
    frame:UnregisterAllEvents()
end

-- In the Journal window's look rather than the plain dark panel's, so the two match side by
-- side: its gradient faded by its Opacity, its card behind the quests, and its titles' blue.
local function Paint()
    panel.backdrop:Paint(S.Get("windowAlpha") or 1)
end

local function Build()
    panel = J.View.Parts.Panel("", true)
    panel.backdrop:Card(4, PANEL_HEADER, 4, 4)
    panel.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    panel:SetWidth(TRACKER_W)
    panel:SetFrameStrata("MEDIUM")
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", DragStop)
    panel.title:SetPoint("RIGHT", TITLE_RIGHT, 0)
    local titleBtn = CreateFrame("Button", nil, panel)
    titleBtn:SetPoint("TOPLEFT", panel.title, "TOPLEFT", -4, 4)
    titleBtn:SetPoint("BOTTOMRIGHT", panel.title, "BOTTOMRIGHT", 0, -4)
    titleBtn:SetScript("OnClick", function() ns.OpenOptionsWindow("Dungeon Journal") end)
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBtn:SetScript("OnDragStop", function() DragStop(panel) end)
    titleBtn:SetScript("OnEnter", function(self)
        panel.title:SetTextColor(T.accent.r, T.accent.g, T.accent.b)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Dungeon Journal")
        GameTooltip:AddLine("Click to open the Dungeon Journal settings.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        GameTooltip:Show()
    end)
    titleBtn:SetScript("OnLeave", function()
        panel.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        GameTooltip:Hide()
    end)
    panel.share = ns.Button(panel, "Share", SHARE_W, SHARE_H, function() J.Sharing.ShareAll(shown) end)
    panel.share:SetPoint("RIGHT", panel.close, "LEFT", -4, 0)
    panel.share:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Share Quests")
        GameTooltip:AddLine("Shares your quests for this dungeon with your group, one at a time.", 1, 1, 1, true)
        local count = #J.Sharing.Shareable(shown)
        if not IsInGroup() then
            GameTooltip:AddLine("You are not in a group.", T.muted.r, T.muted.g, T.muted.b)
        elseif count == 0 then
            GameTooltip:AddLine("None of your quests here can be shared.", T.muted.r, T.muted.g, T.muted.b)
        else
            GameTooltip:AddLine(("%d to share."):format(count), T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        end
        GameTooltip:Show()
    end)
    panel.share:HookScript("OnLeave", GameTooltip_Hide)
    local scroll = ns.UI.SlimScroll(panel)
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - 4)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, PANEL_PAD)
    view = J.View.New(scroll)
    view:SetWidth(TRACKER_W - PANEL_PAD * 2 - SCROLL_GAP)
    view.tracker = true   -- it draws a dungeon's quests alone, each on one line
    view.onResize = Fit
    scroll:SetScrollChild(view)
    panel:SetScript("OnEvent", OnEvent)
    panel:SetScript("OnShow", OnShow)
    panel:SetScript("OnHide", OnHide)
end

-- Opens the tracker on the dungeon's quests; on the dungeon it shows already, closes it.
---@param dungeon JournalDungeon
function ns.OpenQuestTracker(dungeon)
    if not panel then Build() end
    if panel:IsShown() and shown == dungeon then
        panel:Hide()
        return
    end
    panel:SetScale(ns.UIScale())
    Paint()
    Place()
    panel:Show()
    Draw(dungeon)
end

-- The Journal switched off: the tracker goes with it. Its Opacity: the tracker follows.
S.OnChange(function(key)
    if not panel then return end
    if key == "enabled" and not S.Get("enabled") then
        panel:Hide()
    elseif key == "windowAlpha" then
        Paint()
    end
end)
