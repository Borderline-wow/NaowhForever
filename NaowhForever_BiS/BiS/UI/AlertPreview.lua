-------------------------------------------------------------------------------
--  UI/AlertPreview.lua -- Drop Alert's live preview (B.AlertStudio), the studio on its card on
--  the BiS List's settings page (UI/SettingsPage.lua): the alert as it will look, at its real
--  size unless the stage is too narrow, drawn by View/Toast.lua with your BiS (else your spec's
--  first ranked item), in the moment you pick: up for a roll, dropped or yours. Plain frames.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local B = ns.BiS
local S = B.Settings
local Shared = ns.Shared
local Items, Parts = Shared.Items, Shared.Parts

local STAGE_H = 130
local TOAST_W = 300          -- View/Toast.lua's alert at size 100%
local TOAST_ROOM = 32        -- the least room left beside the alert when the stage is narrow
local FALLBACK_STAGE_W = 600 -- the stage before layout has run
local NOTE_SIZE = 12
local NOTE_BOTTOM = 10
local EMPTY_LINK_GAP = 6     -- the empty stage's note to its link
local EMPTY_RAISE = 12       -- the note and link, as a block, centred
local OFF_ALPHA = 0.35

local OFF_NOTE = "On-Screen Alert is off: Drop Alert plays its chat line and sounds only."
local EMPTY_NOTE = "Pick your BiS to see your alert here."

local STATES = { { key = "roll", label = "Up for a roll" }, { key = "dropped", label = "Dropped" },
    { key = "yours", label = "Yours!" } }

-- The item it shows: your first BiS, else your spec's first ranked item, and its rank.
local function Sample()
    local list = B.Lists.List()
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local id = list.slots[gear[1]]
        if id then return id, ns.IsBisItem(id) or 1 end
    end
    return B.Rankings.Candidates(1, B.Lists.CurrentSpec())[1], 1
end

local function OpenList()
    ns.OpenFromOptions(ns.OpenBisWindow)
end

local function New(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.toast = B.Toast.New(preview)
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_BOTTOM)
    preview.note:SetText(OFF_NOTE)
    preview.empty = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.empty:SetPoint("CENTER", 0, EMPTY_RAISE)
    preview.empty:SetText(EMPTY_NOTE)
    preview.emptyLink = Parts.Link(preview, OpenList, true)
    preview.emptyLink:SetPoint("TOP", preview.empty, "BOTTOM", 0, -EMPTY_LINK_GAP)
    Parts.SetLink(preview.emptyLink, "Open BiS List")
    return preview
end

local function Paint(preview, state)
    local id, rank = Sample()
    local shown = id ~= nil
    preview.toast:SetShown(shown)
    preview.empty:SetShown(not shown)
    preview.emptyLink:SetShown(not shown)
    local looks = S.Get("bisToast") == true
    preview.note:SetShown(shown and not looks)
    if not shown then return end
    B.Toast.Paint(preview.toast, id, rank, state)
    preview.toast:SetAlpha(looks and 1 or OFF_ALPHA)
    local w = preview:GetWidth()
    if not w or w <= 0 then w = FALLBACK_STAGE_W end
    local scale = math.min(S.Get("bisToastScale"), (w - TOAST_ROOM) / TOAST_W)
    preview.toast:SetScale(scale)
    preview.toast:ClearAllPoints()
    preview.toast:SetPoint("CENTER", preview, "CENTER", 0, 0)
end

B.AlertStudio = { height = STAGE_H, states = STATES, new = New, paint = Paint }
