-- DeathRelease.lua: Death Release Protection, Release Spirit held down in dungeons and raids.
local ns = _G.NaowhForever

local S = ns.QoLSettings
local T = ns.THEME

local FILL_ALPHA = 0.4
local MIN_FILL_WIDTH = 1
local LEVEL_ABOVE = 5
local HOLD_RANGE = { 0.5, 3, 0.1 }
local DEATH = "DEATH"
local TIP_TITLE = "Release Spirit"
local TIP_TEXT = "Hold for %.1f seconds to release. Naowh Forever's Death Release Protection "
    .. "is on in dungeons and raids."
local SUMMARY = "Hold Release Spirit for %ss in dungeons and raids"

local guard

local function InGroupContent()
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function Reset(self)
    self.held = nil
    self.fill:Hide()
end

local function OnMouseDown(self, button)
    if button == "LeftButton" and self.target:IsEnabled() then self.held = 0 end
end

local function Fill(self)
    local hold = S.Get("deathReleaseHold")
    self.fill:SetWidth(math.max(MIN_FILL_WIDTH, self:GetWidth() * math.min(1, self.held / hold)))
    self.fill:Show()
    if self.held >= hold then
        Reset(self)
        self.target:Click()
    end
end

local function OnUpdate(self, elapsed)
    if not (self.dialog:IsShown() and self.dialog.which == DEATH) then
        self:Hide()
        return
    end
    if not self.held then return end
    if not self.target:IsEnabled() then
        Reset(self)
        return
    end
    self.held = self.held + elapsed
    Fill(self)
end

local function TipText()
    return TIP_TEXT:format(S.Get("deathReleaseHold"))
end

local function Build()
    guard = CreateFrame("Button", nil, UIParent)
    guard.fill = guard:CreateTexture(nil, "OVERLAY")
    guard.fill:SetPoint("TOPLEFT")
    guard.fill:SetPoint("BOTTOMLEFT")
    guard.fill:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, FILL_ALPHA)
    guard.fill:Hide()
    guard:SetScript("OnMouseDown", OnMouseDown)
    guard:SetScript("OnMouseUp", Reset)
    guard:SetScript("OnHide", Reset)
    guard:SetScript("OnUpdate", OnUpdate)
    ns.Tooltip(guard, TIP_TITLE, TipText)
end

local function Cover(dialog)
    if not guard then Build() end
    local target = dialog:GetButton1()
    guard.dialog, guard.target = dialog, target
    guard:SetParent(dialog)
    guard:ClearAllPoints()
    guard:SetAllPoints(target)
    guard:SetFrameLevel(target:GetFrameLevel() + LEVEL_ABOVE)
    guard:Show()
end

local function OnPopupShow(which)
    if which ~= DEATH then return end
    if not (S.Get("deathRelease") and InGroupContent()) then
        if guard then guard:Hide() end
        return
    end
    local dialog = StaticPopup_FindVisible(DEATH)
    if dialog then Cover(dialog) end
end

hooksecurefunc("StaticPopup_Show", OnPopupShow)

local function Summary(store)
    return SUMMARY:format(store.Get("deathReleaseHold"))
end

ns.Shared.Settings.Page("QoL/Combat", S):Card({
    id = "deathRelease", name = "Death Release Protection", order = 20, switch = "deathRelease",
    help = "Release Spirit has to be held down for a moment inside a dungeon or raid, so a stray "
        .. "click never sends you on a corpse run while a battle res is coming.",
    summary = Summary,
    rows = {
        { key = "deathReleaseHold", label = "Hold Time", slider = HOLD_RANGE, unit = "s",
          help = "How long Release Spirit has to be held down." },
    },
})
