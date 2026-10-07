-------------------------------------------------------------------------------
--  NaowhForever_SleepingBagTracker.lua -- the Sleeping Bag tracker: the Cozy Sleeping Bag's
--  chain in the shared tracker window (Parts.TrackerPanel), as the Library Books tracker: how
--  far along you are, then each step with a waypoint pin (a tick once done), the step to do
--  now in full white with how to get there under it. Off by default; on, it shows from level
--  14 until you have the bag. The X switches it off (the Tracker switch on the Sleeping Bag
--  settings tab brings it back). Drag it or move it in Unlock Mode.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.DiscoverySettings
local Bag = ns.SleepingBagChain
local T = ns.THEME
local Parts = ns.Shared.Parts

local SETTINGS_PAGE = "Discovery/Sleeping Bag"

local panel, events, refreshQueued
local entries = {}

local function On()
    return S.Get("enabled") and S.Get("bagTracker")
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function Opacity()
    return S.Get("bagTrackerAlpha") or 1
end

local function LoadPosition()
    local pos = S.Get("bagTrackerPos")
    if type(pos) == "table" then return pos.point, pos.relPoint, pos.x, pos.y end
end

local function SavePosition(point, relPoint, x, y)
    S.Set("bagTrackerPos", { point = point, relPoint = relPoint, x = x, y = y })
end

local function Mover(frame, onMoved)
    return ns.UI.AttachMover(frame, "Sleeping Bag", onMoved, "Discovery/Sleeping Bag",
        "Discovery/Sleeping Bag:bagtracker")
end

-- The X switches the tracker off, as its switch in the settings does.
local function Close()
    S.Set("bagTracker", false)
    ns.UI:RefreshPage(true)
end

local function OpenSteps()
    ns.OpenDiscoveryWindow("bag")
end

local function StepWaypoint(entry)
    Bag.Waypoint(entry.step)
end

local function StepTip(row)
    local step = row.entry.step
    GameTooltip:SetText(Bag.Name(step), 1, 1, 1)
    GameTooltip:AddLine(Bag.Where(step), T.muted.r, T.muted.g, T.muted.b, true)
    if step.tip then GameTooltip:AddLine(step.tip, 1, 1, 1, true) end
end

local function BuildPanel()
    panel = Parts.TrackerPanel("SLEEPING BAG", {
        onTitle = OpenSteps, titleTip = "Sleeping Bag",
        titleHint = "Click to see every step in the Discovery window.",
        onClose = Close,
        bar = true,
        settings = { page = SETTINGS_PAGE, card = "bagtracker", tip = "Sleeping Bag settings",
            hint = "Opens the Sleeping Bag tracker's settings." },
        opacity = Opacity,
        load = LoadPosition, save = SavePosition, place = { "RIGHT", "RIGHT", -260, 120 },
        mover = Mover,
    })
    panel:SetScale(S.Get("bagTrackerScale"))
    panel:Place()
    panel:Paint()
    panel:Hide()
end

-- Every step: done ones ticked and muted, the one to do now in white with how to get there,
-- the ones after it muted with a pin.
local function Render()
    local steps = Bag.Steps()
    local _, at = Bag.Current()
    local n = #steps
    local done = (at or n + 1) - 1
    local bar = panel.bar
    bar:SetMinMaxValues(0, n)
    bar:SetValue(done)
    bar:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b, 0.85)
    bar.text:SetText(("%d / %d  steps"):format(done, n))
    for i, step in ipairs(steps) do
        local entry = entries[i] or {}
        entries[i] = entry
        local isDone, isNow = i <= done, i == at
        entry.step, entry.done = step, isDone
        entry.text = ("%d. %s"):format(i, Bag.Name(step))
        entry.color = not isNow and T.muted or nil
        entry.sub = not isDone and Bag.Sub(step, isNow) or nil
        entry.waypoint, entry.tip = StepWaypoint, StepTip
    end
    for i = n + 1, #entries do entries[i] = nil end
    panel:Fit(panel:SetRows(entries))
end

-------------------------------------------------------------------------------
--  When it shows
-------------------------------------------------------------------------------
local function Refresh()
    local show = On() and Bag.Level() and Bag.Current() ~= nil
    if not show then
        if panel then panel:Hide() end
        return
    end
    if not panel then BuildPanel() end
    Render()
    panel:Show()
end

-- A quest taken or handed in moves the chain on; a level can bring it within reach.
local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }

local function QueuedRefresh()
    refreshQueued = false
    Refresh()
end

local function OnEvent()
    if refreshQueued then return end
    refreshQueued = true
    -- The quest log has the change a moment later.
    C_Timer.After(0.2, QueuedRefresh)
end

local function Apply()
    if On() then
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    elseif events then
        events:UnregisterAllEvents()
    end
    Refresh()
end

hooksecurefunc(S, "Set", function(key, value)
    if key == "bagTrackerScale" and panel then panel:SetScale(value) end
    if key == "bagTrackerAlpha" and panel then panel:Paint() end
    if key == "enabled" or key == "bagTracker" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

-- Unlock Mode shows it wherever you are, to place it.
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not On() then return end
    if not panel then BuildPanel() end
    Render()
    panel.mover:Show()
    panel:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if panel then
        panel.mover:Hide()
        Refresh()
    end
end)
