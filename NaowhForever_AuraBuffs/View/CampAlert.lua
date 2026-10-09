-- CampAlert.lua: the Camp Nearby alert's look: the bar drawn bare, fading in, breathing and fading out.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings
local FADE = A.Style.CAMP_FADE
local Bar = A.CampBar

local SMOOTHING = "IN_OUT"
local LOOP = "BOUNCE"

local Alert = {}
A.CampAlert = Alert

local function Faded(a)
    a.leaving = false
    a:Hide()
end

local function Shown(a)
    if S.Get("campAlertFade") then a.breathe:Play() end
end

local function Fader(a, from, to, duration, finished)
    local group = a:CreateAnimationGroup()
    local anim = group:CreateAnimation("Alpha")
    anim:SetFromAlpha(from)
    anim:SetToAlpha(to)
    anim:SetDuration(duration)
    anim:SetSmoothing(SMOOTHING)
    if finished then
        group:SetToFinalAlpha(true)
        group:SetScript("OnFinished", function() finished(a) end)
    end
    return group
end

function Alert.Stop(a)
    a.fadeIn:Stop()
    a.breathe:Stop()
    a.fadeOut:Stop()
    a.leaving = false
end

function Alert.Look(a)
    a.bar = Bar.New(a, { bare = true })
    a.fadeIn = Fader(a, 0, 1, FADE.IN, Shown)
    a.fadeOut = Fader(a, 1, 0, FADE.OUT, Faded)
    a.breathe = Fader(a, 1, FADE.LOW, FADE.BREATHE)
    a.breathe:SetLooping(LOOP)
    a.leaving = false
end

function Alert.Fade(a, show)
    local fade = S.Get("campAlertFade")
    if show then
        if a:IsShown() and not a.leaving then return end
        Alert.Stop(a)
        a:SetAlpha(1)
        a:Show()
        if fade then a.fadeIn:Play() end
    elseif a:IsShown() and not a.leaving then
        Alert.Stop(a)
        if not fade then
            a:Hide()
            return
        end
        a.leaving = true
        a.fadeOut:Play()
    end
end
