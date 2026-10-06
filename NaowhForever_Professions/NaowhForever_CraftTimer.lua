-------------------------------------------------------------------------------
--  NaowhForever_CraftTimer.lua -- Total Craft Timer: crafting several at once (Create All,
--  or Create with a count) shows one bar for the whole batch, drawn after the Flight Timer:
--  a thick track, the recipe's name over one end and how many are done over the other, the
--  time left on all of them beside it, and the recipe's icon where the Land Early button
--  sits. It is centred where the Flight Timer is, as nobody crafts in flight; move it in
--  Unlock Mode as the Flight Timer. Meanwhile the player cast bar, which would fill and
--  empty for every single craft, is hidden.
--
--  Also here: how many crafts the bags have room for, which caps Create All.
--
--  The time is worked out from the recipe's cast time, then set right from the real casts:
--  each craft that starts gives the time left on it, and the pause between two crafts is
--  measured and used for the ones still to come.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local T = ns.THEME

-- The Flight Timer's measures and art (QoL/NaowhForever_Flight.lua), so the two look alike.
local GRADIENT = "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga"
-- The track is twice the Flight Timer's height and has no end dots: a batch has no stops.
local WIDTH, TRACK_H, PIN, NAME_SIZE, ICON = 420, 20, 18, 14, 30
-- Between the track and the time left of it, and the icon right of it.
local SIDE_GAP = 10
local HEIGHT = PIN + 2 * (NAME_SIZE + 8)
-- A first guess at the pause between one craft ending and the next starting, until one is
-- measured.
local GAP = 0.3
-- A batch with no craft event for this long past its expected end has stopped some way the
-- events did not say.
local STALE = 5
-- The player cast bars hidden during a batch: EllesmereUI's, and Blizzard's for anyone
-- without it.
local CAST_BARS = { "ERB_CastBarFrame", "PlayerCastingBarFrame", "CastingBarFrame" }

local job   -- { recipeID, name, icon, count, done, cast, gap, start, known, lastEnd }
local bar, watch
local hidden = {}   -- cast bar frame -> the alpha it had
local events = CreateFrame("Frame")

local function On()
    return S.Get("enabled") and S.Get("craftTimer")
end

-- "2:34", as the Flight Timer counts.
local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Kept at zero alpha for the whole batch: the cast bar's own code shows it again on every
-- cast.
local function HideCastBars()
    for _, name in ipairs(CAST_BARS) do
        local frame = _G[name]
        if frame and frame.SetAlpha then
            if hidden[frame] == nil then hidden[frame] = frame:GetAlpha() end
            if frame:GetAlpha() ~= 0 then frame:SetAlpha(0) end
        end
    end
end

local function RestoreCastBars()
    for frame, alpha in pairs(hidden) do frame:SetAlpha(alpha) end
    wipe(hidden)
end

local Look = {}

-- The Flight Timer's layout: an invisible box with the track through its middle, a dot at
-- each end with a label over it, the time left of the track and the icon right of it.
function Look.New(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(WIDTH, HEIGHT)

    local track = CreateFrame("StatusBar", nil, frame)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(TRACK_H)
    track:SetStatusBarTexture(GRADIENT)
    track:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    track:SetMinMaxValues(0, 1)
    ns.Solid(track, "BACKGROUND", T.bg, 0.9):SetAllPoints()
    ns.Border(track, { r = 0, g = 0, b = 0 })
    frame.track = track

    -- A label over each end of the track, above its border.
    local over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints()
    over:SetFrameLevel(track:GetFrameLevel() + 3)
    frame.labels = {}
    for i, side in ipairs({ "LEFT", "RIGHT" }) do
        local label = ns.Font(over, NAME_SIZE, "OUTLINE")
        label:SetWordWrap(false)
        label:SetPoint("BOTTOM" .. side, track, "TOP" .. side, 0, 4)
        label:SetWidth(WIDTH * 0.47)
        label:SetJustifyH(side)
        frame.labels[i] = label
    end

    frame.time = ns.Font(frame, 18, "OUTLINE", T.accentSoft)
    frame.time:SetPoint("RIGHT", frame, "LEFT", -SIDE_GAP, 0)

    -- The recipe's icon where the Flight Timer has its Land Early button.
    local icon = CreateFrame("Frame", nil, frame)
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", frame, "RIGHT", SIDE_GAP, 0)
    ns.Border(icon, { r = 0, g = 0, b = 0 })
    frame.icon = icon:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return frame
end

-- The recipe over the left end, how many of the batch are done over the right.
function Look.Fill(frame, icon, name, done, count)
    frame.icon:SetTexture(icon)
    frame.labels[1]:SetText(name or "")
    frame.labels[2]:SetText(("%d / %d crafted"):format(done, count))
end

function Look.Progress(frame, share, left)
    frame.track:SetValue(math.min(share, 1))
    frame.time:SetText(Clock(left))
end

local function Build()
    bar = Look.New(UIParent, "NaowhForeverCraftTimer")
    bar:SetFrameStrata("MEDIUM")
    bar:SetScript("OnUpdate", function(self)
        if not job then return self:Hide() end
        HideCastBars()
        local elapsed = GetTime() - job.start
        Look.Progress(self, elapsed / job.known, job.known - elapsed)
    end)
    bar:Hide()
end

-- On the Flight Timer's spot and at its scale; a place of its own until that timer exists.
local function Place()
    local flight = _G.NaowhForeverFlightTimer
    bar:ClearAllPoints()
    if flight then
        bar:SetScale(flight:GetScale())
        bar:SetPoint("CENTER", flight, "CENTER")
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
end

local function Show()
    if not bar then Build() end
    Place()
    Look.Fill(bar, job.icon, job.name, job.done, job.count)
    HideCastBars()
    bar:Show()
end

local function Stop()
    job = nil
    events:UnregisterAllEvents()
    if watch then
        watch:Cancel()
        watch = nil
    end
    if bar then bar:Hide() end
    RestoreCastBars()
end

-- The whole batch's length from its start: the time left on the craft in hand, then every
-- craft after it with its pause.
local function Resync(castLeft)
    local after = job.count - job.done - 1
    job.known = (GetTime() - job.start) + math.max(0, castLeft) + math.max(0, after) * (job.cast + job.gap)
end

events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if not job or spellID ~= job.recipeID then return end
    if event == "UNIT_SPELLCAST_START" then
        if job.lastEnd then job.gap = GetTime() - job.lastEnd end
        local _, _, _, startMS, endMS = UnitCastingInfo("player")
        if startMS and endMS then
            job.cast = (endMS - startMS) / 1000
            Resync(endMS / 1000 - GetTime())
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        job.done = job.done + 1
        if job.done >= job.count then return Stop() end
        job.lastEnd = GetTime()
        Resync(job.gap + job.cast)
        Show()
    else
        -- Pressing Create again mid-craft fails that press ("Another action is in progress")
        -- while the batch casts on.
        if event == "UNIT_SPELLCAST_FAILED" and select(9, UnitCastingInfo("player")) == job.recipeID then
            return
        end
        -- Interrupted or failed: moving, combat, a reagent run out. The rest is not crafted.
        Stop()
    end
end)

local function OnCraft(recipeID, count)
    count = tonumber(count) or 1
    local spell = C_Spell.GetSpellInfo(recipeID)
    local cast = spell and (spell.castTime or 0) / 1000 or 0
    if not On() or count < 2 then return end
    local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
    Stop()
    -- Forever may report a craft's cast time as 0 until it is cast; the first cast then sets
    -- it, and a guess of 3 seconds stands in till then.
    job = { recipeID = recipeID, name = recipe and recipe.name or (spell and spell.name),
        icon = recipe and recipe.icon or (spell and spell.iconID), count = count, done = 0,
        cast = cast > 0 and cast or 3, gap = GAP, start = GetTime() }
    Resync(job.cast)
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
        events:RegisterUnitEvent(event, "player")
    end
    watch = C_Timer.NewTicker(1, function()
        if job and GetTime() > job.start + job.known + STALE then Stop() end
    end)
    Show()
end

-------------------------------------------------------------------------------
--  Bag room
-------------------------------------------------------------------------------
-- How many of `limit` crafts of a recipe the bags have room for, or nil when there is no
-- limit to tell (a recipe that makes no item). Played out craft by craft on what the bag
-- slots hold now: each craft's item goes on a stack of it with room, else into a free slot
-- that can take it; then the craft's reagents come out, and every stack that empties frees
-- its slot. So a batch that uses up stacks of flux and bars as it goes makes room for the
-- crafts after. The game uses the smallest stack of a reagent first: confirmed in game
-- 2026-09-30 (2 free slots, a stack of 5 bars among 20s and flux in 10s: 4 swords, then
-- "Inventory is full", as counted here).
-- A profession bag takes only items of its kind, the reagent bag only crafting reagents.
-- The profession window caps Create All with it.
local function BagTakes(bag, family, isReagent)
    if Enum.BagIndex and bag == Enum.BagIndex.ReagentBag then return isReagent end
    local _, bagType = C_Container.GetContainerNumFreeSlots(bag)
    return (bagType or 0) == 0 or bit.band(family, bagType) ~= 0
end

function ns.CraftBagRoom(output, made, reagents, limit)
    if not output or not limit or limit < 1 then return end
    local stack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(output)
        or select(8, C_Item.GetItemInfo(output))
    if not stack or stack < 1 then return end
    made = math.max(made or 1, 1)
    local family = C_Item.GetItemFamily and C_Item.GetItemFamily(output) or 0
    local isReagent = select(17, C_Item.GetItemInfo(output)) == true

    -- What the bags hold: free slots and room on the item's stacks where it can go, and every
    -- stack of each reagent, marked by whether its slot could take the item once empty.
    local free, room = 0, 0
    local stacks = {}   -- reagent itemID -> { { count, takes } }
    for _, r in ipairs(reagents or {}) do stacks[r.itemID] = {} end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local takes = BagTakes(bag, family, isReagent)
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info then
                if takes then free = free + 1 end
            elseif info.itemID == output then
                if takes then room = room + math.max(0, stack - (info.stackCount or 0)) end
            elseif stacks[info.itemID] then
                local list = stacks[info.itemID]
                list[#list + 1] = { count = info.stackCount or 1, takes = takes }
            end
        end
    end
    for _, list in pairs(stacks) do
        table.sort(list, function(a, b) return a.count < b.count end)
    end

    for n = 1, limit do
        -- The item: onto stacks with room first, the rest into new slots.
        if room >= made then
            room = room - made
        else
            local slots = math.ceil((made - room) / stack)
            if free < slots then return n - 1 end
            free = free - slots
            room = room + slots * stack - made
        end
        -- The reagents, smallest stacks first; each one emptied frees its slot.
        for _, r in ipairs(reagents or {}) do
            local need, list = r.need, stacks[r.itemID]
            for _, s in ipairs(list) do
                if need <= 0 then break end
                local take = math.min(need, s.count)
                if take > 0 then
                    s.count, need = s.count - take, need - take
                    if s.count == 0 and s.takes then free = free + 1 end
                end
            end
        end
    end
    return limit
end

-- Nothing is hooked until Total Craft Timer is first switched on: crafting, and Blizzard's
-- own way to stop a batch, which ends it too. A hook cannot be taken off again, so once on
-- they stay, doing nothing while the setting is off.
local hooked = false
local function Apply()
    if not On() then return Stop() end
    if hooked then return end
    hooked = true
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", OnCraft)
    if C_TradeSkillUI.StopRecipeRepeat then hooksecurefunc(C_TradeSkillUI, "StopRecipeRepeat", Stop) end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "craftTimer" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local SAMPLE_ICON = "Interface\\Icons\\INV_Ingot_02"
local SAMPLE_NAME, SAMPLE_DONE, SAMPLE_COUNT = "Smelt Copper", 4, 10
local SAMPLE_SHARE, SAMPLE_LEFT = 0.4, 15
local PREVIEW_STATES = {
    { key = "crafting", label = "Crafting", tip = "A batch of ten, four done, as it shows while you craft." },
}

local function NewPreview(stage)
    local preview = Look.New(stage)
    preview:SetPoint("CENTER")
    return preview
end

local function PaintPreview(preview)
    Look.Fill(preview, SAMPLE_ICON, SAMPLE_NAME, SAMPLE_DONE, SAMPLE_COUNT)
    Look.Progress(preview, SAMPLE_SHARE, SAMPLE_LEFT)
end

Settings.Page("Professions/Settings", S):Card({
    id = "craftTimer", name = "Total Craft Timer", order = 30, switch = "craftTimer",
    help = "Crafting several at once (Create All, or Create with a count) shows one bar for the whole batch, "
        .. "drawn like the Flight Timer: the recipe, how many are done and the time left on all of them, in place "
        .. "of the cast bar that fills for every craft. It sits where the Flight Timer is, as nobody crafts in "
        .. "flight: move it in Layout Mode as the Flight Timer.",
    studio = { height = 100, states = PREVIEW_STATES, new = NewPreview, paint = PaintPreview },
})
