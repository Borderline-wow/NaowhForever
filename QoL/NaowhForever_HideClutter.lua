-------------------------------------------------------------------------------
--  NaowhForever_HideClutter.lua -- the QoL UI clutter options: hides alerts, toasts, zone and
--  error text and tutorials, and skips cinematics already seen.
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

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local CLUTTER = { "hideErrors", "hideTutorials", "hideScreenshot", "skipCinematics", "hideAlerts",
    "hideEventToasts", "hideZoneText", "cursorClip" }

local function ClutterSummary(store)
    local on = 0
    for i = 1, #CLUTTER do
        if store.Get(CLUTTER[i]) then on = on + 1 end
    end
    return ("%d of %d on"):format(on, #CLUTTER)
end

Settings.Page("QoL/Interface", S):Card({
    id = "uiClutter", name = "UI Clutter", order = 20,
    help = "Hides the game's messages, pop-ups and banners you can do without, each on its own switch.",
    summary = ClutterSummary,
    rows = {
        { key = "hideErrors", label = "Hide Error Messages", toggle = true,
          help = "Hides the red error text, like \"not ready yet\" and \"out of range\", and the "
              .. "voice line that comes with it." },
        { key = "hideTutorials", label = "Hide Tutorial Pop-ups", toggle = true,
          help = "Turns off the game's tutorials and help tips. Turning this back off restores "
              .. "what you had before." },
        { key = "hideScreenshot", label = "Hide Screenshot Status", toggle = true,
          help = "Hides the \"Screen captured\" text when you take a screenshot." },
        { key = "skipCinematics", label = "Skip Cinematics", toggle = true,
          help = "Skips cinematics you have already seen on this account. Each one plays the "
              .. "first time." },
        { key = "hideAlerts", label = "Hide Alert Pop-ups", toggle = true,
          help = "Hides the pop-ups for achievements, loot won and the like." },
        { key = "hideEventToasts", label = "Hide Event Toasts", toggle = true,
          help = "Closes the banners for level ups, new zones and events." },
        { key = "hideZoneText", label = "Hide Zone Text", toggle = true,
          help = "Hides the zone and subzone names that appear as you travel." },
        { key = "cursorClip", label = "Keep Cursor In Window During Combat", toggle = true,
          help = "Stops the cursor leaving the game window while you fight, for a second monitor. "
              .. "Your own setting comes back afterwards." },
    },
})
