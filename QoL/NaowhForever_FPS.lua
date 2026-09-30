-------------------------------------------------------------------------------
--  NaowhForever_FPS.lua -- the QoL FPS counter, with local and world latency beside it
--  when those are on. Move it in Unlock Mode.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local frame, clock, unlocked

local function On()
    return false -- FPS and latency now live in the Top Bar.
end

local function Update()
    local LABEL, VALUE = ns.Color("accent"), ns.Color("fg")
    local text = LABEL .. "FPS|r " .. VALUE .. math.floor(GetFramerate() + 0.5) .. "|r"
    local _, _, home, world = GetNetStats()
    if S.Get("localMS") then text = text .. "   " .. LABEL .. "Local|r " .. VALUE .. home .. " ms|r" end
    if S.Get("worldMS") then text = text .. "   " .. LABEL .. "World|r " .. VALUE .. world .. " ms|r" end
    frame.text:SetText(text)
end

local function Place()
    local pos = S.Get("fpsPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -30)
    end
end

local function Apply()
    if not On() then
        if clock then clock:Cancel(); clock = nil end
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverFPS", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.text = ns.Font(frame, 14, "OUTLINE")
        frame.text:SetPoint("CENTER")
        frame.mover = ns.UI.AttachMover(frame, "FPS", function(pos) S.Set("fpsPos", pos) end)
    end
    Place()
    Update()
    frame:SetSize(frame.text:GetStringWidth() + 12, frame.text:GetStringHeight() + 8)
    if not clock then clock = C_Timer.NewTicker(1, Update) end
    frame.mover:SetShown(unlocked == true)
    frame:Show()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "fps" or key == "localMS" or key == "worldMS" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
