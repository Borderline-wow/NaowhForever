-------------------------------------------------------------------------------
--  NaowhForever_LowHealth.lua -- the AuraBuffs low health reminder: the best
--  healing item in your bags, with a LOW HEALTH warning, while your health is under the
--  threshold.
--
--  Showing it never compares the health: a step curve turns the health percent into 1
--  below the threshold and 0 above it, and the engine applies that as the frame's alpha
--  itself, so it works in combat even where health is secret to addons.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.AuraBuffSettings
local Parts = ns.Shared.Parts

local HEALTHSTONES, POTIONS = ns.Shared.Items.HEALTHSTONES, ns.Shared.Items.HEALING_POTIONS
local FALLBACK_ICON = 134830    -- Healing Potion
local COUNT_SIZE = 14

local Look = {}

function Look.New(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Border(frame, { r = 0, g = 0, b = 0 })

    frame.count = ns.Font(frame, COUNT_SIZE, "OUTLINE")
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)

    frame.label = ns.Font(frame, 16, "OUTLINE", { r = 1, g = 0.25, b = 0.25 })
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -4)
    frame.label:SetText("LOW HEALTH")
end

-- Font Size is the warning's; the count keeps its size and follows the font and outline.
function Look.Style(frame)
    local font, outline = S.Get("lowHealthFont"), S.Get("lowHealthOutline")
    Parts.HudFont(frame.label, font, S.Get("lowHealthFontSize"), outline)
    Parts.HudFont(frame.count, font, COUNT_SIZE, outline)
end

function Look.Item(frame, id, count)
    frame.count:SetText(count > 1 and count or "")
    frame.icon:SetTexture(id and C_Item.GetItemIconByID(id) or FALLBACK_ICON)
    frame.icon:SetDesaturated(id == nil)
end

local frame, curve, unlocked
local shownItem, wasLow, glowing

local function On()
    return S.Get("enabled") and S.Get("lowHealth")
end

local function FirstCarried(list)
    for _, id in ipairs(list) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

local function PickItem()
    local mode = S.Get("lowHealthItem")
    if mode == "stone" then return FirstCarried(HEALTHSTONES) end
    if mode == "potion" then return FirstCarried(POTIONS) end
    return FirstCarried(HEALTHSTONES) or FirstCarried(POTIONS)
end

local function UpdateItem()
    local id = PickItem()
    local count = id and C_Item.GetItemCount(id) or 0
    if id == shownItem and frame.itemShown then
        frame.count:SetText(count > 1 and count or "")
        return
    end
    shownItem, frame.itemShown = id, true
    Look.Item(frame, id, count)
end

local function SetGlow(on)
    on = on and true or false
    if on == glowing then return end
    glowing = on
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if not LCG then return end
    if on then
        LCG.PixelGlow_Start(frame, { 1, 0.25, 0.25, 1 }, nil, nil, nil, 2)
    else
        LCG.PixelGlow_Stop(frame)
    end
end

-- The sound and the glow need the health itself, not just the curve. Where the client hands
-- it over readable the sound plays once per dip below the threshold and the glow runs only
-- while low; a secret read skips the sound and leaves the glow running under the alpha.
local function CheckSound()
    local pct = UnitHealthPercent("player", true)
    if issecretvalue and issecretvalue(pct) then
        SetGlow(S.Get("lowHealthGlow"))
        return
    end
    local low = pct < S.Get("lowHealthBelow") / 100
    SetGlow(low and S.Get("lowHealthGlow"))
    if low and not wasLow and S.Get("lowHealthSound") then
        ns.UI._PlayLSMSound(ns.UI.SoundPathFor(S.Get("lowHealthSoundKey")))
    end
    wasLow = low
end

local function UpdateAlpha()
    if unlocked then
        frame:SetAlpha(1)
    elseif UnitIsDeadOrGhost("player") then
        frame:SetAlpha(0)
        SetGlow(false)
        wasLow = false
    else
        frame:SetAlpha(UnitHealthPercent("player", true, curve))
        CheckSound()
    end
end

-- Flat on both sides of the threshold, so a step curve gives the same answer whether it
-- snaps to the point before or the nearest point.
local function BuildCurve()
    local below = S.Get("lowHealthBelow") / 100
    curve = curve or C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:ClearPoints()
    curve:AddPoint(0, 1)
    curve:AddPoint(below - 0.001, 1)
    curve:AddPoint(below, 0)
    curve:AddPoint(1, 0)
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverLowHealth", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetAlpha(0)

    Look.New(frame)

    frame.mover = ns.UI.AttachMover(frame, "Low Health", function(pos) S.Set("lowHealthPos", pos) end,
        "AuraBuffs/Settings", "AuraBuffs/Settings:lowHealth")
end

local function Place()
    local pos = S.Get("lowHealthPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then UpdateItem() else UpdateAlpha() end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (On() or unlocked) then
        if frame then
            frame:Hide()
            SetGlow(false)
        end
        return
    end
    if not frame then Build() end
    local size = S.Get("lowHealthIconSize")
    frame:SetSize(size, size)
    Look.Style(frame)
    Place()
    BuildCurve()
    frame.itemShown = nil
    UpdateItem()
    SetGlow(unlocked and S.Get("lowHealthGlow"))
    frame.mover:SetShown(unlocked == true)
    frame:Show()
    if On() then
        events:RegisterUnitEvent("UNIT_HEALTH", "player")
        events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        events:RegisterEvent("PLAYER_DEAD")
        events:RegisterEvent("PLAYER_ALIVE")
        events:RegisterEvent("PLAYER_UNGHOST")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("BAG_UPDATE_DELAYED")
    end
    UpdateAlpha()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^lowHealth") and key ~= "lowHealthPos") then Apply() end
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

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local T = ns.THEME

local OFF = "Turn on AuraBuffs"
local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN, LABEL_ROOM = 150, 10, 11, 16, 24
local GLOW_RGB = { r = 1, g = 0.25, b = 0.25 }
local GLOW_OUT = 2
local SAMPLE_POTIONS = 3
local ITEMS = { { auto = "Best in Bags", stone = "Healthstone", potion = "Healing Potion" },
    { "auto", "stone", "potion" } }
local STATES = {
    { key = "low", label = "Low Health", tip = "Your health under the threshold, with a healing item in your bags." },
    { key = "none", label = "None in Bags", tip = "Your health under the threshold, with nothing to drink or eat." },
}

local function Enabled() return S.Get("enabled") and true or false end
local function SoundOn() return S.Get("enabled") and S.Get("lowHealthSound") and true or false end

local function NewPreview(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.icon = CreateFrame("Frame", nil, shot)
    Look.New(shot.icon)
    shot.glow = CreateFrame("Frame", nil, shot.icon)
    shot.glow:SetPoint("TOPLEFT", -GLOW_OUT, GLOW_OUT)
    shot.glow:SetPoint("BOTTOMRIGHT", GLOW_OUT, -GLOW_OUT)
    ns.Border(shot.glow, GLOW_RGB)
    shot.note = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return shot
end

local function PaintPreview(shot, state)
    local f = shot.icon
    local size = S.Get("lowHealthIconSize")
    f:SetSize(size, size)
    Look.Style(f)
    local room = shot:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2 - LABEL_ROOM
    local scale = (room > 0 and size > room) and room / size or 1
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", shot, "CENTER", 0, (NOTE_Y + LABEL_ROOM / 2) / scale)
    local mode = S.Get("lowHealthItem")
    local id
    if state == "low" then id = mode == "potion" and POTIONS[1] or HEALTHSTONES[1] end
    Look.Item(f, id, mode == "potion" and SAMPLE_POTIONS or 1)
    shot.glow:SetShown(S.Get("lowHealthGlow"))
    shot.note:SetText(("Shown below %d%% health, in combat too."):format(S.Get("lowHealthBelow")))
end

local function Summary(store)
    return ("Below %d%%, %s"):format(store.Get("lowHealthBelow"), ITEMS[1][store.Get("lowHealthItem")] or "")
end

Settings.Page("AuraBuffs/Settings", S):Card({
    id = "lowHealth", name = "Low Health", order = 40, switch = "lowHealth",
    help = "Shows a healing item's icon the moment your health drops below the threshold, in combat too: "
        .. "the game shows and hides it itself. Move it in the HUD Editor.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "lowHealthBelow", label = "Show Below", slider = { 10, 90, 1 }, unit = "%", needs = Enabled,
          why = OFF },
        { key = "lowHealthItem", label = "Item", choice = ITEMS, needs = Enabled, why = OFF,
          help = "Best in Bags: your best healthstone, else your best healing potion." },
        { key = "lowHealthGlow", label = "Glow", toggle = true, needs = Enabled, why = OFF,
          help = "A red glow around the icon while it shows." },
        { key = "lowHealthSound", label = "Play a Sound", toggle = true, needs = Enabled, why = OFF,
          help = "Plays once each time your health drops below the threshold. If the game hides your "
              .. "health from addons mid-fight, it only plays out of combat." },
        { key = "lowHealthSoundKey", label = "Sound", sound = true, needs = SoundOn, why = "Needs Play a Sound" },
        Settings.Group("Size"),
        { key = "lowHealthIconSize", label = "Icon Size", slider = { 24, 96, 1 }, needs = Enabled, why = OFF },
        Settings.Look("lowHealth", { text = true, size = { 10, 28, 1 }, needs = Enabled, why = OFF }),
    },
})
