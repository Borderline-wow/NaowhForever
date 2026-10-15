-- Displays.lua: the battleground scores and start countdown, movable in the HUD Editor.
local ns = _G.NaowhForever

local S = ns.PvPSettings
local UI = ns.UI

local SCORES_W, SCORES_H, SCORES_Y = 260, 48, -15
local TIMER_W, TIMER_H, TIMER_TOP = 206, 26, -155
local PAGE, CARD = "PvP/Battlegrounds", "PvP/Battlegrounds:displays"
local KEYS = { enabled = true, scoresPos = true, timerPos = true }

local function Scores() return UIWidgetTopCenterContainerFrame end
local function Countdown() return TimerTracker end

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

local function NewHolder(d)
    d.holder = CreateFrame("Frame", nil, UIParent)
    d.holder:SetSize(d.w, d.h)
    d.holder.mover = UI.AttachMover(d.holder, d.label, function(at) S.Set(d.posKey, at) end, PAGE, CARD)
end

local function PlaceHolder(d, f, pos, on)
    d.holder:ClearAllPoints()
    if pos then
        d.holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        d.follow(d.holder, f)
    end
    d.holder.mover:SetShown(on and unlocked == true)
end

local function ApplyDisplay(d, f, on)
    local pos = on and S.Get(d.posKey)
    if on and not d.holder then NewHolder(d) end
    if d.holder then PlaceHolder(d, f, pos, on) end
    if pos then
        d.hang(f, d.holder)
        d.hung = true
        return d.frame == Countdown
    elseif d.hung then
        d.hung = false
        d.home(f)
    end
    return false
end

local function Apply()
    local on = S.Get("enabled") == true
    local hung = false
    for _, d in ipairs(DISPLAYS) do
        local f = d.frame()
        if f then hung = ApplyDisplay(d, f, on) or hung end
    end
    if hung then
        resize:RegisterEvent("UI_SCALE_CHANGED")
        resize:RegisterEvent("DISPLAY_SIZE_CHANGED")
    else
        resize:UnregisterAllEvents()
    end
end

local function OnSet(key)
    if KEYS[key] then Apply() end
end

local function OnUnlock()
    unlocked = true
    Apply()
end

local function OnLock()
    unlocked = false
    Apply()
end

local function OnLogin(self)
    self:UnregisterAllEvents()
    Apply()
end

resize:SetScript("OnEvent", Apply)
hooksecurefunc(S, "Set", OnSet)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", OnUnlock)
hooksecurefunc(ns, "HideUnlockMode", OnLock)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", OnLogin)
