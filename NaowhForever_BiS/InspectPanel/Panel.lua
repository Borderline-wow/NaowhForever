-------------------------------------------------------------------------------
--  Panel.lua -- the Naowh inspect panel (ns.InspectPanel): the game's inspect window in the BiS
--  List's look, as the Naowh Character Panel dresses the character panel, with a pane of ours
--  on its right for the player you inspect. Blizzard keeps the window and all it does (its
--  slots' clicks and tooltips, the Talents button, its tabs, ctrl-click to the dressing room);
--  Naowh fades its art (SetAlpha, never Hide), widens it by the pane and lays its own frames
--  over it, from post-hooks only. Nothing is hooked or built until the game loads its inspect
--  window (the first inspect) with this on. Each part paints on IP.Refresh with the unit and
--  GUID shown, and reads the game's inspect data only while IP.Ready says it is that player's.
--  EllesmereUI's inspect sheet and this one are never on at once (CP.Rival).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local CP = ns.CharacterPanel
local Parts = ns.Shared.Parts

local IP = {}
ns.InspectPanel = IP

local PANE_W, EDGE = CP.PANE_W, CP.EDGE
local CARD_GAP, BODY_GAP = 10, 14
local SWITCH_H, SWITCH_GAP = 26, 6
local PANE_LEVEL = 20
local LEVEL_SIZE = 12
local LOAD_SETTLE = 0.2
local MODEL_BORDERS = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Left", "Right", "Top", "Bottom",
    "Bottom2" }
local MODEL_ART = { "BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight",
    "BackgroundOverlay" }
local LABELS = { { key = "player", label = "Player" }, { key = "history", label = "History" } }
local NONE = {}

IP.PANE_W, IP.EDGE, IP.CARD_GAP = PANE_W, EDGE, CARD_GAP
IP.BODY_Y = CARD_GAP + CP.BADGE_H + BODY_GAP
IP.BODY_W = PANE_W - 2 * EDGE

local rival = CP.Rival({ key = "inspectPanel", winKey = "inspect", dbKey = "themedInspectSheet",
    name = "inspect window" })
IP.EllesmereSheet = rival.Styled
IP.On = rival.On

local game = CP.Restyler()
local parts, applies = {}, {}
local installed, built, loadHooked, widened, base, back, events, barHeight, readyGUID
local waiting, settleQueued = false, false
local tab, hasHistory = "player", false

local function Readable(value)
    return value ~= nil and not issecretvalue(value)
end
IP.Readable = Readable

function IP.Current()
    local frame = InspectFrame
    local unit = frame and frame:IsShown() and frame.unit
    if type(unit) ~= "string" or issecretvalue(unit) then return nil end
    local guid = UnitGUID(unit)
    if not Readable(guid) then return nil end
    return unit, guid
end

function IP.FullName(unit)
    local first, second = UnitFullName(unit)
    if not Readable(first) then return nil end
    if Readable(second) and second ~= "" then return first .. " " .. second end
    return first
end

function IP.Ready(guid)
    return guid ~= nil and guid == readyGUID
end

function IP.OnRefresh(fn) parts[#parts + 1] = fn end
function IP.OnApply(fn) applies[#applies + 1] = fn end

local function Refresh()
    if not (built and IP.On() and InspectFrame:IsShown()) then return end
    local unit, guid = IP.Current()
    IP.unit, IP.guid = unit, guid
    for i = 1, #parts do parts[i](unit, guid) end
end
IP.Refresh = Refresh

local function Settled()
    settleQueued, waiting = false, false
    events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    Refresh()
end

local reasked

-- Gear the game says they wear but sends none of (an inspect cleared under the window): asked
-- for again once per player shown, so the window fills in rather than showing them bare.
function IP.HasGear(unit, guid)
    for _, entry in ipairs(ns.Shared.Items.GEAR_SLOTS) do
        local id = GetInventoryItemID(unit, entry[1])
        if id and id ~= 0 then return true end
    end
    local level = C_PaperDollInfo.GetInspectItemLevel and C_PaperDollInfo.GetInspectItemLevel(unit)
    if not (level and level > 0) then return true end
    if guid and reasked ~= guid and CanInspect(unit) then
        reasked = guid
        NotifyInspect(unit)
    end
    return false
end

function IP.Wait()
    if waiting or not events then return end
    waiting = true
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

local function OnEvent(_, event, arg)
    if event == "INSPECT_READY" then
        if not Readable(arg) then return end
        readyGUID = arg
        local _, guid = IP.Current()
        if arg == guid then Refresh() end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if Readable(arg) and arg == IP.unit then Refresh() end
    elseif not settleQueued then
        settleQueued = true
        C_Timer.After(LOAD_SETTLE, Settled)
    end
end

local function Shown()
    if not IP.On() then return end
    local _, guid = IP.Current()
    readyGUID = guid
    events:RegisterEvent("UNIT_INVENTORY_CHANGED")
    Refresh()
end

local function Hidden()
    events:UnregisterEvent("UNIT_INVENTORY_CHANGED")
    events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    waiting = false
    IP.unit, IP.guid = nil, nil
    reasked = nil
end

local function PlaceInset()
    local inset = InspectFrame.Inset
    if not inset then return end
    inset:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT",
        (PANEL_INSET_RIGHT_OFFSET or 0) - (widened and PANE_W or 0), barHeight or PANEL_INSET_BOTTOM_OFFSET or 0)
end

local function BarSet(frame, height)
    if frame ~= InspectFrame then return end
    barHeight = height
    if widened then PlaceInset() end
end

local function Widen(on)
    if on == (widened == true) then return end
    local frame = InspectFrame
    base = base or frame:GetWidth()
    widened = on
    frame:SetWidth(on and base + PANE_W or base)
    for _, name in ipairs(INSPECTFRAME_SUBFRAMES or NONE) do
        local sub = _G[name]
        if sub then
            sub:ClearAllPoints()
            if on then
                sub:SetPoint("TOPLEFT", frame, "TOPLEFT")
                sub:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PANE_W, 0)
            else
                sub:SetAllPoints(frame)
            end
        end
    end
    PlaceInset()
end

local function FadeGame()
    local frame = InspectFrame
    game.Fade(frame.NineSlice)
    game.Fade(frame.PortraitContainer)
    game.Fade(frame.Bg)
    game.Fade(frame.TopTileStreaks)
    local inset = frame.Inset
    if inset then
        game.Fade(inset.Bg)
        game.Fade(inset.NineSlice)
    end
    local model = InspectModelFrame
    if model then
        for _, key in ipairs(MODEL_ART) do game.Fade(model[key]) end
    end
    for _, name in ipairs(MODEL_BORDERS) do game.Fade(_G["InspectModelFrameBorder" .. name]) end
    game.FadeClose(frame.CloseButton)
    for _, mode in ipairs(frame.ModeTabs and frame.ModeTabs.Tabs or NONE) do game.TintSideTab(mode) end
    local talents = InspectPaperDollFrame and InspectPaperDollFrame.InspectTalents
    if talents then
        game.TintTree(talents, CP.TAB_RGB)
        game.Tint(talents:GetHighlightTexture(), T.accent, 0.5)
    end
    game.Restyle(frame.TitleContainer and frame.TitleContainer.TitleText, CP.TITLE_SIZE, T.fg)
    game.Restyle(InspectLevelText, LEVEL_SIZE, T.fg)
end

local function ShowBodies()
    local picked = hasHistory and tab or "player"
    IP.switch:SetShown(hasHistory)
    Parts.PaintTabs(IP.switch, picked)
    for key, body in pairs(IP.bodies) do body:SetShown(key == picked) end
end

function IP.SetHistory(on)
    hasHistory = on == true
    ShowBodies()
end

local function Picked(key)
    tab = key
    ShowBodies()
end

local function Build()
    built = true
    local frame = InspectFrame
    back = CP.Chrome(frame)
    if InspectModelFrame then CP.ModelPanel(back, InspectModelFrame) end
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPRIGHT", 0, -CP.HEADER)
    pane:SetPoint("BOTTOMRIGHT")
    pane:SetWidth(PANE_W)
    pane:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL)
    CP.Split(back, pane)
    IP.pane = pane
    IP.switch = Parts.Tabs(pane, IP.BODY_W, LABELS, Picked)
    IP.switch:SetPoint("BOTTOM", 0, SWITCH_GAP)
    IP.bodies = {}
    for _, item in ipairs(LABELS) do
        local body = CreateFrame("Frame", nil, pane)
        body:SetPoint("TOPLEFT", EDGE, -IP.BODY_Y)
        body:SetPoint("BOTTOMRIGHT", -EDGE, SWITCH_H + 2 * SWITCH_GAP)
        IP.bodies[item.key] = body
    end
    ShowBodies()
end

local function Install()
    installed = true
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    InspectFrame:HookScript("OnShow", Shown)
    InspectFrame:HookScript("OnHide", Hidden)
    hooksecurefunc("FrameTemplate_SetButtonBarHeight", BarSet)
    Build()
end

local function Apply()
    local on = IP.On()
    if on and not installed then
        if not InspectFrame then
            if not loadHooked then
                loadHooked = true
                EventUtil.ContinueOnAddOnLoaded("Blizzard_InspectUI", Apply)
            end
            return
        end
        Install()
    end
    if not installed then return end
    Widen(on)
    if on then
        FadeGame()
        events:RegisterEvent("INSPECT_READY")
    else
        game.Restore()
        events:UnregisterAllEvents()
        waiting = false
    end
    back:SetShown(on)
    if back.cross then back.cross:SetShown(on) end
    IP.pane:SetShown(on)
    for i = 1, #applies do applies[i](on) end
    if on and InspectFrame:IsShown() then Shown() end
end
IP.Apply = Apply

S.OnChange(function(key)
    if key == "enabled" or key:find("^inspectPanel") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
