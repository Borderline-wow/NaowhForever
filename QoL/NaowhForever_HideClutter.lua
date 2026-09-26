-------------------------------------------------------------------------------
--  NaowhForever_HideClutter.lua -- the QoL UI clutter options from NaowhQOL: hides the
--  pop-up alerts (achievements, loot won and the like), event toasts, and zone text.
--
--  The hooks go in once and check the setting each time, so turning an option off takes
--  effect straight away rather than after a reload.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local function On(key)
    return S.Get("enabled") and S.Get(key)
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
