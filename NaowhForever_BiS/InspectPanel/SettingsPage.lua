-------------------------------------------------------------------------------
--  SettingsPage.lua -- the inspect panel's card on QoL > Character, beside the Character
--  Panel's: the Naowh Inspect Panel with what it adds, and Share Your BiS, which answers other
--  players' inspect panels with your BiS stars. The Supporter Badge row is there only while
--  ns.FEATURE_BADGES is 1.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local IP = ns.InspectPanel
local S = ns.QoLSettings

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local function Summary(store)
    if IP.EllesmereSheet() then
        return store.Get("inspectPanel") and "EllesmereUI's inspect window is in use: switch this off and on for this one"
            or "Takes over from EllesmereUI's inspect window, after a reload"
    end
    local badge = ns.FEATURE_BADGES == 1 and store.Get("inspectPanelBadge")
    local score = store.Get("inspectPanelScore")
    if badge and score then return "With their badge and Naowh Score" end
    if badge then return "With their badge" end
    if score then return "With their Naowh Score" end
    return "Their gear, talents and history"
end

local rows = {
    { key = "inspectPanelScore", label = "Naowh Score", toggle = true,
      help = "Their Naowh Score at the top of the panel, with yours under it." },
    { key = "inspectPanelShareBis", label = "Share Your BiS", toggle = true, always = true,
      help = "Shows your BiS stars to players who inspect you with Naowh Forever." },
}
if ns.FEATURE_BADGES == 1 then
    table.insert(rows, 1, { key = "inspectPanelBadge", label = "Supporter Badge", toggle = true,
        help = "Their supporter badge in the window's corner, if they have one." })
end

Settings.Page("QoL/Character", S):Card({
    id = "inspectPanel", name = "Inspect Panel", order = 15, switch = "inspectPanel", store = S,
    help = "The inspect window in the BiS List's look, with their score, gear check, talents and history.",
    summary = Summary,
    rows = rows,
})
