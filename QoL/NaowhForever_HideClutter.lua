-------------------------------------------------------------------------------
--  NaowhForever_HideClutter.lua -- the QoL UI clutter options: hides the pop-up alerts
--  (achievements, loot won and the like), event toasts, zone text, red error text,
--  tutorials and help tips and the screenshot status text, and skips cinematics already seen.
--
--  The hooks go in once and check the setting each time, so turning an option off takes
--  effect straight away rather than after a reload.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local function On(key)
    return S.Get("enabled") and S.Get(key) and true or false
end

hooksecurefunc(AlertFrame, "AddAlertFrame", function(_, frame)
    if On("hideAlerts") then frame:Hide() end
end)

for _, frame in ipairs({ ZoneTextFrame, SubZoneTextFrame }) do
    frame:HookScript("OnShow", function(self)
        if On("hideZoneText") then self:Hide() end
    end)
end

-- The toast frame is not in every client; its own hide button stays usable when shown.
if EventToastManagerFrame then
    hooksecurefunc(EventToastManagerFrame, "DisplayToast", function(self)
        if not On("hideEventToasts") then return end
        C_Timer.After(0.05, function()
            if self:IsShown() and not (self.HideButton and self.HideButton:IsShown()) then
                self:CloseActiveToasts()
            end
        end)
    end)
end

-- The game's own switches: showTutorials is the Show Tutorials box in Blizzard's options.
local TUTORIAL_CVARS = { showTutorials = "0", hideHelptips = "1" }

local errorsHidden, screenshotHidden, movieHooked = false, false, false

-- In-game cinematics carry no ID, so one is known by where it plays.
local function SeenBefore(key)
    local account = ns.AccountSettings()
    account.seenCinematics = account.seenCinematics or {}
    local seen = account.seenCinematics[key]
    account.seenCinematics[key] = true
    return seen
end

-- Deferred a frame so CinematicFrame has taken the start before it is cancelled.
local cinematics = CreateFrame("Frame")
cinematics:SetScript("OnEvent", function(_, _, canBeCancelled)
    if not canBeCancelled then return end
    if SeenBefore("cinematic:" .. GetZoneText() .. "/" .. GetSubZoneText()) then
        C_Timer.After(0, function()
            if InCinematic() then CinematicFrame_CancelCinematic() end
        end)
    end
end)

-- Finishing a movie shows UIParent again, which combat lockdown would block.
local function OnMovie(self, movieID)
    if On("skipCinematics") and self.movieID == movieID and SeenBefore("movie:" .. movieID)
        and not InCombatLockdown() then
        self:FinishMovie()
    end
end

-- What the player had before is kept in the account store and put back when the option
-- goes off, even in a later session.
local function ApplyTutorials()
    local account = ns.AccountSettings()
    if On("hideTutorials") then
        if not account.tutorialCVars then
            local saved = {}
            for name in pairs(TUTORIAL_CVARS) do saved[name] = C_CVar.GetCVar(name) end
            account.tutorialCVars = saved
        end
        for name, value in pairs(TUTORIAL_CVARS) do C_CVar.SetCVar(name, value) end
    elseif account.tutorialCVars then
        for name, value in pairs(account.tutorialCVars) do C_CVar.SetCVar(name, value) end
        account.tutorialCVars = nil
    end
end

local function Apply()
    -- The same switch as Blizzard's /uierrorsoff.
    local hide = On("hideErrors")
    if hide ~= errorsHidden then
        if hide then
            UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        else
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        end
        errorsHidden = hide
    end

    hide = On("hideScreenshot")
    if hide ~= screenshotHidden then
        if hide then
            ActionStatus:UnregisterEvent("SCREENSHOT_SUCCEEDED")
            ActionStatus:UnregisterEvent("SCREENSHOT_FAILED")
        else
            ActionStatus:RegisterEvent("SCREENSHOT_SUCCEEDED")
            ActionStatus:RegisterEvent("SCREENSHOT_FAILED")
        end
        screenshotHidden = hide
    end

    ApplyTutorials()

    if On("skipCinematics") then
        cinematics:RegisterEvent("CINEMATIC_START")
        if not movieHooked then
            hooksecurefunc(MovieFrame, "PlayMovie", OnMovie)
            movieHooked = true
        end
    else
        cinematics:UnregisterEvent("CINEMATIC_START")
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "hideErrors" or key == "hideTutorials"
        or key == "hideScreenshot" or key == "skipCinematics" then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
