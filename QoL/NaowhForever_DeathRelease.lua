-------------------------------------------------------------------------------
--  NaowhForever_DeathRelease.lua -- Death Release Protection: inside a dungeon or raid,
--  Release Spirit has to be held down for a moment, so a stray click never sends you on a
--  corpse run while a battle res is on its way.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local guard

local function InGroupContent()
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function Reset(self)
    self.held = nil
    self.fill:Hide()
end

-- A cover over the death dialog's Release Spirit button that takes the mouse: a click does
-- nothing, and holding it fills a bar, then presses the button underneath. The dialogs are
-- pooled, so it hides itself once that dialog is no longer the death one.
local function Build()
    guard = CreateFrame("Button", nil, UIParent)
    guard.fill = guard:CreateTexture(nil, "OVERLAY")
    guard.fill:SetPoint("TOPLEFT")
    guard.fill:SetPoint("BOTTOMLEFT")
    guard.fill:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.4)
    guard.fill:Hide()
    guard:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self.target:IsEnabled() then self.held = 0 end
    end)
    guard:SetScript("OnMouseUp", Reset)
    guard:SetScript("OnHide", Reset)
    guard:SetScript("OnUpdate", function(self, elapsed)
        if not (self.dialog:IsShown() and self.dialog.which == "DEATH") then
            self:Hide()
            return
        end
        if not self.held then return end
        -- Blizzard disables the button while falling or while an encounter holds the release.
        if not self.target:IsEnabled() then
            Reset(self)
            return
        end
        self.held = self.held + elapsed
        local hold = S.Get("deathReleaseHold")
        self.fill:SetWidth(math.max(1, self:GetWidth() * math.min(1, self.held / hold)))
        self.fill:Show()
        if self.held >= hold then
            Reset(self)
            self.target:Click()
        end
    end)
    ns.Tooltip(guard, "Release Spirit", function()
        return ("Hold for %.1f seconds to release. Naowh Forever's Death Release Protection "
            .. "is on in dungeons and raids."):format(S.Get("deathReleaseHold"))
    end)
end

hooksecurefunc("StaticPopup_Show", function(which)
    if which ~= "DEATH" then return end
    if not (S.Get("deathRelease") and InGroupContent()) then
        if guard then guard:Hide() end
        return
    end
    local dialog = StaticPopup_FindVisible("DEATH")
    if not dialog then return end
    if not guard then Build() end
    local target = dialog:GetButton1()
    guard.dialog, guard.target = dialog, target
    guard:SetParent(dialog)
    guard:ClearAllPoints()
    guard:SetAllPoints(target)
    guard:SetFrameLevel(target:GetFrameLevel() + 5)
    guard:Show()
end)
