-------------------------------------------------------------------------------
--  NaowhForever_PvPDisplays.lua -- the game's battleground displays in the HUD Editor's PvP
--  section while the PvP module is on: the scores at the top of the screen and the start
--  countdown. Until one is dragged its holder follows the game's frame, which stays where the
--  game (or the Top Bar) put it; once dragged, the game's frame hangs from the holder.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.PvPSettings
local UI = ns.UI
local Settings = ns.Shared.Settings

local SCORES_W, SCORES_H, SCORES_Y = 260, 48, -15  -- two faction scores; the game's spot
local TIMER_W, TIMER_H, TIMER_TOP = 206, 26, -155  -- one countdown bar, under the screen's top

local function Scores() return UIWidgetTopCenterContainerFrame end
local function Countdown() return TimerTracker end

-- frame: the game's; follow: the holder over it unmoved; hang: it from the holder; home: back.
local DISPLAYS = {
    { label = "Battleground Scores", posKey = "scoresPos", w = SCORES_W, h = SCORES_H, frame = Scores,
      follow = function(holder, f) holder:SetPoint("TOP", f, "TOP") end,
      hang = function(f, holder)
          f:ClearAllPoints()
          f:SetPoint("TOP", holder, "TOP")
      end,
      home = function(f)
          f:ClearAllPoints()
          f:SetPoint("TOP", UIParent, "TOP", 0, SCORES_Y)
          if ns.PlaceTopCentreWidgets then ns.PlaceTopCentreWidgets() end
      end },
    -- The countdown's bars hang from the top of a screen-sized frame and its last seconds sit at
    -- its centre, so the whole frame moves with the first bar.
    { label = "Battleground Countdown", posKey = "timerPos", w = TIMER_W, h = TIMER_H, frame = Countdown,
      follow = function(holder, f) holder:SetPoint("TOP", f, "TOP", 0, TIMER_TOP) end,
      hang = function(f, holder)
          f:ClearAllPoints()
          f:SetSize(UIParent:GetWidth(), UIParent:GetHeight())
          f:SetPoint("TOP", holder, "TOP", 0, -TIMER_TOP)
      end,
      home = function(f)
          f:ClearAllPoints()
          f:SetAllPoints(UIParent)
      end },
}

local unlocked
local resize = CreateFrame("Frame")

local function Apply()
    local on = S.Get("enabled") == true
    local hung = false
    for _, d in ipairs(DISPLAYS) do
        local f = d.frame()
        if f then
            local pos = on and S.Get(d.posKey)
            if on and not d.holder then
                d.holder = CreateFrame("Frame", nil, UIParent)
                d.holder:SetSize(d.w, d.h)
                d.holder.mover = UI.AttachMover(d.holder, d.label, function(at) S.Set(d.posKey, at) end,
                    "PvP/Battlegrounds", "PvP/Battlegrounds:displays")
            end
            if d.holder then
                d.holder:ClearAllPoints()
                if pos then
                    d.holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                else
                    d.follow(d.holder, f)
                end
                d.holder.mover:SetShown(on and unlocked == true)
            end
            if pos then
                d.hang(f, d.holder)
                d.hung = true
                hung = hung or d.frame == Countdown
            elseif d.hung then
                d.hung = false
                d.home(f)
            end
        end
    end
    -- A countdown moved off the screen-sized frame is sized again when the screen changes.
    if hung then
        resize:RegisterEvent("UI_SCALE_CHANGED")
        resize:RegisterEvent("DISPLAY_SIZE_CHANGED")
    else
        resize:UnregisterAllEvents()
    end
end

resize:SetScript("OnEvent", Apply)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "scoresPos" or key == "timerPos" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
local function Reset()
    S.Set("scoresPos", false)
    S.Set("timerPos", false)
end

Settings.Page("PvP/Battlegrounds", S):Card({
    id = "displays", name = "Battleground Displays", order = 10,
    help = "Move the battleground scores and the start countdown in the HUD Editor, under PvP.",
    rows = {
        { key = "scoresPos", label = "Reset Positions", buttonText = "Reset", button = Reset,
          help = "Puts both back where the game shows them." },
    },
})
