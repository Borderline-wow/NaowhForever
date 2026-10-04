-------------------------------------------------------------------------------
--  UI/AlertPreview.lua -- Drop Alert's studio on the BiS List's settings page. A header with
--  the On-Screen Alert switch, which moment the preview shows and Play test; under it a stage
--  with the alert as it will look, at its real size, drawn by View/Toast.lua with your BiS
--  (else your spec's first ranked item); beside it how it looks: size, how long it stays, its
--  background and glow. Click a part of the alert (the star, the line under the name, its
--  edge) or its chip under it to change that part. Repainted as you change any of Drop
--  Alert's settings.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local B = ns.BiS
local S = B.Settings
local Shared = ns.Shared
local Items, Parts = Shared.Items, Shared.Parts
local St = B.Style

local BLACK = { r = 0, g = 0, b = 0 }

-- The block: a header over a body, padded all round; the stage on the body's left and the look
-- column on its right.
local STUDIO_H, HEAD_H, BODY_PAD, BODY_H = 212, 40, 12, 148
local GAP_UNDER = 12        -- under the block, before the next row
local PAD = 12              -- the block's inside edge, and the stage to the look column
local OFF_ALPHA = 0.35      -- a part that is switched off
local TITLE_SIZE = 14
local TOGGLE_GAP = 10       -- the title to its switch
local TEST_W, TEST_H = 92, 26
local TABS_W, TABS_GAP = 270, 12
local HIT_PAD = 4           -- round a label, for its tooltip
-- The stage
local TOAST_W = 300         -- View/Toast.lua's alert at size 100%
local TOAST_ROOM = 32       -- the least room left beside the alert when the stage is narrow
local CHIPS_ROOM = 38       -- for the chips under the alert, which sits up by half of it
local CHIP_H, CHIP_GAP, CHIP_BOTTOM = 22, 8, 10
local CHIP_PAD, CHIP_WORD_GAP, CHIP_SIZE = 8, 5, 12
local NOTE_SIZE = 12
local EMPTY_LINK_GAP = 6    -- the empty stage's note to its link
local EMPTY_RAISE = 12      -- the note and link, as a block, centred
local FALLBACK_STAGE_W = 689 -- the stage on a 1085px page, before layout has run
-- The parts to click on the alert, in the stage's own size
local STAR_ZONE_PAD, STAR_ZONE_MIN = 6, 28
local LINE_ZONE_PAD = 3
local LINE_ZONE_EMPTY = 14  -- the band under the name while the line says nothing
local EDGE_ZONE_OUT = 4     -- the edge's click area, a little outside the alert
local LIT_FILL = 0.12       -- the part under the mouse, or under the chip it is on: a soft tint, no lines
local EDGE_LEVEL, LINE_LEVEL, STAR_LEVEL = 8, 10, 12   -- over the alert's own frames (its star is +6)
-- The look column
local LOOK_W, LOOK_ROW_H, LOOK_INSET, DIVIDER_INSET = 360, 37, 16, 8
local RULE_ALPHA = 0.6
local LABEL_SIZE = 13
local TRACK_W, TRACK_H, THUMB, BOX_W, BOX_H, BOX_FONT, TRACK_GAP = 140, 4, 12, 52, 22, 12, 8

local TIP_OPTS = { anchor = "cursor", justify = "LEFT" }
local TOAST_TIP = "The item, your star and what happened, on screen for a while. Move it in Unlock Mode."
local TEST_TIP = "Plays Drop Alert with your list's first BiS, as you set it: up for a roll, dropped, then yours."
local TEST_NEEDS_BIS = "Pick your BiS first: the test plays with your list's first one."
local OFF_NOTE = "Turn on On-Screen Alert to change how it looks."
local EMPTY_NOTE = "Pick your BiS to see your alert here."

local EVENTS = { { key = "roll", label = "Up for a roll" }, { key = "dropped", label = "Dropped" },
    { key = "yours", label = "Yours!" } }
local STARS = { { "icon", "On the icon, left" }, { "iconRight", "On the icon, right" }, { "name", "Before the name" },
    { "none", "Hidden" } }
local STAR_SHORT = { icon = "Icon, left", iconRight = "Icon, right", name = "By name", none = "Hidden" }
local LINES = { { "bisToastEvent", "What happened" }, { "bisToastRank", "Your rank" }, { "bisToastSlot", "The slot" },
    { "bisToastSource", "Where it drops" }, { "bisToastGain", "How much stronger (+%)" } }
local BORDERS = { { "none", "None" }, { "black", "Black" }, { "quality", "The item's quality" },
    { "rank", "Your rank's colour (BiS orange)" } }
local BORDER_SHORT = { none = "None", black = "Black", quality = "Quality", rank = "Rank colour" }

-- What the settings search finds here, and jumps to.
local SEARCH_LABELS = { "On-Screen Alert", "Play Test", "Size", "Stays For", "Background", "Glow", "Star",
    "Text Line", "Border" }
local SEARCH_TIP = "How Drop Alert's on-screen alert looks. Click a part of the preview to change it."
local SEARCH_SET = {}
for _, label in ipairs(SEARCH_LABELS) do SEARCH_SET[label] = true end

local studio
local shownEvent = "dropped"   -- the moment the preview shows; the preview's own, not saved

-- The item it shows: your first BiS, else your spec's first ranked item. The third return is
-- true for a BiS of yours, the one Play test plays with.
local function Sample()
    local list = B.Lists.List()
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local id = list.slots[gear[1]]
        if id then return id, ns.IsBisItem(id) or 1, true end
    end
    local first = B.Rankings.Candidates(1, B.Lists.CurrentSpec())[1]
    return first, 1, false
end

-------------------------------------------------------------------------------
--  The three parts: what each is set to, and the menu a click on it opens
-------------------------------------------------------------------------------
local function StarValue() return STAR_SHORT[S.Get("bisToastStar")] or STAR_SHORT.icon end

local function LineValue()
    local shown = 0
    for _, part in ipairs(LINES) do
        if S.Get(part[1]) then shown = shown + 1 end
    end
    return shown == 0 and "Nothing" or (shown .. " of " .. #LINES)
end

local function BorderValue()
    local border = BORDER_SHORT[S.Get("bisToastBorder")] or BORDER_SHORT.none
    return S.Get("bisToastGlow") and border .. " + glow" or border
end

local function StarMenu(root)
    root:CreateTitle("Your star")
    for _, choice in ipairs(STARS) do
        root:CreateRadio(choice[2], function() return S.Get("bisToastStar") == choice[1] end,
            function() S.Set("bisToastStar", choice[1]) end)
    end
end

local function LineMenu(root)
    root:CreateTitle("Text line")
    for _, part in ipairs(LINES) do
        root:CreateCheckbox(part[2], function() return S.Get(part[1]) == true end,
            function() S.Set(part[1], not S.Get(part[1])) end)
    end
end

local function BorderMenu(root)
    root:CreateTitle("Border")
    for _, choice in ipairs(BORDERS) do
        root:CreateRadio(choice[2], function() return S.Get("bisToastBorder") == choice[1] end,
            function() S.Set("bisToastBorder", choice[1]) end)
    end
    root:CreateDivider()
    root:CreateCheckbox("Glow in your rank's colour", function() return S.Get("bisToastGlow") == true end,
        function() S.Set("bisToastGlow", not S.Get("bisToastGlow")) end)
end

local PARTS = {
    { name = "Star", value = StarValue, fill = StarMenu },
    { name = "Line", value = LineValue, fill = LineMenu },
    { name = "Border", value = BorderValue, fill = BorderMenu },
}

-- Blizzard's menu, anchored under the chip or part, as the settings dropdowns open it; a
-- second click closes it.
local function OpenMenu(owner)
    if owner._menu and owner._menu:IsShown() then
        owner._menu:Close()
        owner._menu = nil
        return
    end
    if not (MenuUtil and MenuUtil.CreateRootMenuDescription and MenuVariants
        and Menu and Menu.GetManager and AnchorUtil) then return end
    local desc = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
    if not desc then return end
    owner.part.fill(desc)
    owner._menu = Menu.GetManager():OpenMenu(owner, desc,
        AnchorUtil.CreateAnchor("TOPLEFT", owner, "BOTTOMLEFT", 0, -2))
end

local function CloseMenu(owner)
    if owner._menu then owner._menu:Close(); owner._menu = nil end
end

-- Answering this keeps the menu manager from closing the menu before OnMouseDown toggles it.
local function HandlesGlobalMouseEvent(_, button, event)
    return event == "GLOBAL_MOUSE_DOWN" and button == "LeftButton"
end

-------------------------------------------------------------------------------
--  Signposting: the part under the mouse, or under the chip it is on, takes a soft tint, and
--  its tooltip says what a click changes. No outlines: they crowd the alert they explain.
-------------------------------------------------------------------------------
local function PaintZones(f)
    for _, zone in ipairs(f.zones) do zone.fill:SetShown(zone == f.lit) end
end

local function Hint(f, zone)
    f.lit = zone
    PaintZones(f)
end

local function Unhint(f)
    f.lit = nil
    PaintZones(f)
end


local function ZoneEnter(zone)
    Hint(zone.studio, zone)
    ns.UI.ShowWidgetTooltip(zone, zone.part.name .. ": " .. zone.part.value() .. "|nClick to change.", TIP_OPTS)
end

local function ZoneLeave(zone)
    Unhint(zone.studio)
    ns.UI.HideWidgetTooltip()
end

local function ChipEnter(chip)
    chip.edge:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    Hint(chip.studio, chip.zone)
end

local function ChipLeave(chip)
    chip.edge:SetColor(BLACK.r, BLACK.g, BLACK.b, 1)
    Unhint(chip.studio)
end

local function LabelEnter(hit) ns.UI.ShowWidgetTooltip(hit, hit.tip, TIP_OPTS) end
local function LabelLeave() ns.UI.HideWidgetTooltip() end

-- Play test while there is no BiS to play: muted, its tooltip says why, no hover light.
local function TestEnter(button)
    if button.off then button._border:SetColor(BLACK.r, BLACK.g, BLACK.b, 1) end
end

local function PlayTest() B.Actions.TestAlert() end

local function OpenList()
    ns.StashOptionsWindow()
    ns.OpenBisWindow()
end

-------------------------------------------------------------------------------
--  Building it, once
-------------------------------------------------------------------------------
-- A label's hover area, for its tooltip.
local function LabelTip(parent, label, tip)
    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("TOPLEFT", label, "TOPLEFT", -HIT_PAD, HIT_PAD)
    hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", HIT_PAD, -HIT_PAD)
    hit.tip = tip
    hit:SetScript("OnEnter", LabelEnter)
    hit:SetScript("OnLeave", LabelLeave)
    return hit
end

local function NewZone(f, part, level)
    local zone = CreateFrame("Button", nil, f.stage)
    zone:SetFrameLevel(f.toast:GetFrameLevel() + level)
    zone.fill = ns.Solid(zone, "BACKGROUND", T.accent, LIT_FILL)
    zone.fill:SetAllPoints()
    zone.fill:Hide()
    zone.studio, zone.part = f, part
    zone.HandlesGlobalMouseEvent = HandlesGlobalMouseEvent
    zone:SetScript("OnMouseDown", OpenMenu)
    zone:SetScript("OnEnter", ZoneEnter)
    zone:SetScript("OnLeave", ZoneLeave)
    zone:SetScript("OnHide", CloseMenu)
    f.zones[#f.zones + 1] = zone
    return zone
end

local function NewChip(f, part, zone)
    local chip = CreateFrame("Button", nil, f.chips)
    chip:SetHeight(CHIP_H)
    ns.Solid(chip, "BACKGROUND", T.panel, 1):SetAllPoints()
    chip.edge = ns.Border(chip, BLACK)
    chip.label = ns.Font(chip, CHIP_SIZE, nil, T.muted)
    chip.label:SetPoint("LEFT", CHIP_PAD, 0)
    chip.label:SetText(part.name)
    chip.value = ns.Font(chip, CHIP_SIZE, nil, T.fg)
    chip.value:SetPoint("LEFT", chip.label, "RIGHT", CHIP_WORD_GAP, 0)
    chip.arrow = ns.Font(chip, CHIP_SIZE, nil, T.muted)
    chip.arrow:SetPoint("LEFT", chip.value, "RIGHT", CHIP_WORD_GAP, 0)
    chip.arrow:SetText("v")
    chip.studio, chip.part, chip.zone = f, part, zone
    chip.HandlesGlobalMouseEvent = HandlesGlobalMouseEvent
    chip:SetScript("OnMouseDown", OpenMenu)
    chip:SetScript("OnEnter", ChipEnter)
    chip:SetScript("OnLeave", ChipLeave)
    chip:SetScript("OnHide", CloseMenu)
    return chip
end

-- One row of the look column, its label with its tooltip; i from the top.
local function LookRow(f, i, text, tip)
    local row = CreateFrame("Frame", nil, f.look)
    row:SetHeight(LOOK_ROW_H)
    row:SetPoint("TOPLEFT", f.look, "TOPLEFT", 0, -(BODY_PAD + (i - 1) * LOOK_ROW_H))
    row:SetPoint("TOPRIGHT", f.look, "TOPRIGHT", 0, -(BODY_PAD + (i - 1) * LOOK_ROW_H))
    local label = ns.Font(row, LABEL_SIZE, nil, T.fg)
    label:SetPoint("LEFT", LOOK_INSET, 0)
    label:SetText(text)
    LabelTip(row, label, tip)
    if i > 1 then
        local rule = ns.Solid(row, "ARTWORK", T.line, RULE_ALPHA)
        rule:SetPoint("TOPLEFT", LOOK_INSET, 0)
        rule:SetPoint("TOPRIGHT", -LOOK_INSET, 0)
        ns.Hairline(rule, "h")
    end
    return row
end

local function Slider(f, row, minV, maxV, step, get, set, format)
    local track, box = ns.UI.BuildSliderCore(row, TRACK_W, TRACK_H, THUMB, BOX_W, BOX_H, BOX_FONT, 1, minV, maxV,
        step, get, set)
    track._format = format
    track._refreshValue()
    box:SetPoint("RIGHT", row, "RIGHT", -LOOK_INSET, 0)
    track:SetPoint("RIGHT", box, "LEFT", -TRACK_GAP, 0)
    track.box = box
    f.sliders[#f.sliders + 1] = track
    return track
end

-- Saved as a fraction, shown and set in percent.
local function SizeGet() return math.floor(S.Get("bisToastScale") * 100 + 0.5) end
local function SizeSet(v) S.Set("bisToastScale", v / 100) end
local function TimeGet() return S.Get("bisToastTime") end
local function TimeSet(v) S.Set("bisToastTime", v) end
local function AlphaGet() return math.floor(S.Get("bisToastAlpha") * 100 + 0.5) end
local function AlphaSet(v) S.Set("bisToastAlpha", v / 100) end
local function GlowGet() return S.Get("bisToastGlow") end
local function GlowSet(v) S.Set("bisToastGlow", v and true or false) end
local function ToastGet() return S.Get("bisToast") end
local function ToastSet(v)
    S.Set("bisToast", v and true or false)
    ns.UI:RefreshPage(true)
end

local function PickEvent(key)
    shownEvent = key
    if studio then studio:Refresh() end
end

local function New(parent)
    local UI = ns.UI
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(STUDIO_H)
    ns.Solid(f, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(f, BLACK)
    f.zones, f.sliders = {}, {}

    -- The header: the switch on the left, the moment to show and Play test on the right.
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_H)
    ns.Solid(head, "BACKGROUND", T.panel, 1):SetAllPoints()
    local rule = ns.Solid(head, "ARTWORK", T.line, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    ns.Hairline(rule, "h")
    f.title = ns.Font(head, TITLE_SIZE, nil, T.fg)
    f.title:SetPoint("LEFT", PAD, 0)
    f.title:SetText("On-Screen Alert")
    LabelTip(head, f.title, TOAST_TIP)
    f.toastToggle = UI.BuildToggleControl(head, nil, ToastGet, ToastSet)
    f.toastToggle:SetPoint("LEFT", f.title, "RIGHT", TOGGLE_GAP, 0)
    f.test = ns.Button(head, "Play test", TEST_W, TEST_H, PlayTest)
    f.test:SetPoint("RIGHT", -PAD, 0)
    f.test:HookScript("OnEnter", TestEnter)
    f.tabs = Parts.Tabs(head, TABS_W, EVENTS, PickEvent)
    f.tabs:SetPoint("RIGHT", f.test, "LEFT", -TABS_GAP, 0)

    -- The look column, then the stage left of it.
    f.look = CreateFrame("Frame", nil, f)
    f.look:SetPoint("TOPRIGHT", -PAD, -HEAD_H)
    f.look:SetPoint("BOTTOMRIGHT", -PAD, 0)
    f.look:SetWidth(LOOK_W)
    local divider = ns.Solid(f.look, "ARTWORK", T.line, RULE_ALPHA)
    divider:SetPoint("TOPLEFT", 0, -DIVIDER_INSET)
    divider:SetPoint("BOTTOMLEFT", 0, DIVIDER_INSET)
    ns.Hairline(divider, "v")
    f.size = Slider(f, LookRow(f, 1, "Size", "How big the on-screen alert is."), 60, 160, 5, SizeGet, SizeSet,
        UI.FormatPercent)
    f.time = Slider(f, LookRow(f, 2, "Stays For", "Seconds before it fades."), 2, 15, 1, TimeGet, TimeSet,
        UI.FormatSeconds)
    f.background = Slider(f, LookRow(f, 3, "Background", "How solid its background is."), 0, 100, 5, AlphaGet, AlphaSet,
        UI.FormatPercent)
    local glowRow = LookRow(f, 4, "Glow", "A soft glow round it in your rank's colour.")
    f.glow = UI.BuildToggleControl(glowRow, nil, GlowGet, GlowSet)
    f.glow:SetPoint("RIGHT", -LOOK_INSET, 0)

    -- The stage: darker than the page, like the game world behind the alert.
    local stage = CreateFrame("Frame", nil, f)
    f.stage, stage.studio = stage, f
    stage:SetPoint("TOPLEFT", PAD, -(HEAD_H + BODY_PAD))
    stage:SetPoint("TOPRIGHT", f.look, "TOPLEFT", -PAD, -BODY_PAD)
    stage:SetHeight(BODY_H)
    ns.Solid(stage, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(stage, BLACK)
    stage:EnableMouse(true)
    f.toast = B.Toast.New(stage)
    -- The edge under the rest, so the star and the line take their own clicks.
    f.edgeZone = NewZone(f, PARTS[3], EDGE_LEVEL)
    f.lineZone = NewZone(f, PARTS[2], LINE_LEVEL)
    f.starZone = NewZone(f, PARTS[1], STAR_LEVEL)
    f.chips = CreateFrame("Frame", nil, stage)
    f.chips:SetHeight(CHIP_H)
    f.chips:SetPoint("BOTTOM", 0, CHIP_BOTTOM)
    f.chips:SetFrameLevel(f.toast:GetFrameLevel() + STAR_LEVEL)
    f.chipList = { NewChip(f, PARTS[1], f.starZone), NewChip(f, PARTS[2], f.lineZone),
        NewChip(f, PARTS[3], f.edgeZone) }
    f.offNote = ns.Font(stage, NOTE_SIZE, nil, T.muted)
    f.offNote:SetPoint("CENTER", f.chips, "CENTER")
    f.offNote:SetText(OFF_NOTE)
    f.empty = ns.Font(stage, NOTE_SIZE, nil, T.muted)
    f.empty:SetPoint("CENTER", 0, EMPTY_RAISE)
    f.empty:SetText(EMPTY_NOTE)
    f.emptyLink = Parts.Link(stage, OpenList, true)
    f.emptyLink:SetPoint("TOP", f.empty, "BOTTOM", 0, -EMPTY_LINK_GAP)
    Parts.SetLink(f.emptyLink, "Open BiS List")
    return f
end

-------------------------------------------------------------------------------
--  Painting it, as you set it
-------------------------------------------------------------------------------
local function StageWidth(f)
    local w = f.stage:GetWidth()
    if not w or w <= 0 then w = FALLBACK_STAGE_W end
    return w
end

-- The parts to click, over the alert as it is drawn now.
local function PlaceZones(f, scale)
    local toast = f.toast
    local star = math.max(STAR_ZONE_MIN, toast.star:GetWidth() * scale + STAR_ZONE_PAD * 2)
    f.starZone:ClearAllPoints()
    f.starZone:SetPoint("CENTER", toast.star, "CENTER")
    f.starZone:SetSize(star, star)
    local line = f.lineZone
    line:ClearAllPoints()
    local text = toast.detail:GetText()
    if text and text ~= "" then
        line:SetPoint("TOPLEFT", toast.detail, "TOPLEFT", -LINE_ZONE_PAD, LINE_ZONE_PAD)
        line:SetPoint("BOTTOMRIGHT", toast.detail, "BOTTOMRIGHT", LINE_ZONE_PAD, -LINE_ZONE_PAD)
    else
        -- Nothing to click on: a band under the name, so the line can be brought back.
        line:SetPoint("BOTTOMLEFT", toast.detail, "BOTTOMLEFT", -LINE_ZONE_PAD, -LINE_ZONE_PAD)
        line:SetPoint("BOTTOMRIGHT", toast.detail, "BOTTOMRIGHT", LINE_ZONE_PAD, -LINE_ZONE_PAD)
        line:SetHeight(LINE_ZONE_EMPTY)
    end
    f.edgeZone:ClearAllPoints()
    f.edgeZone:SetPoint("TOPLEFT", toast, "TOPLEFT", -EDGE_ZONE_OUT, EDGE_ZONE_OUT)
    f.edgeZone:SetPoint("BOTTOMRIGHT", toast, "BOTTOMRIGHT", EDGE_ZONE_OUT, -EDGE_ZONE_OUT)
end

-- Each chip as wide as its words, the row of them centred.
local function PaintChips(f)
    local x = 0
    for _, chip in ipairs(f.chipList) do
        chip.value:SetText(chip.part.value())
        local w = CHIP_PAD * 2 + CHIP_WORD_GAP * 2 + math.ceil(chip.label:GetStringWidth())
            + math.ceil(chip.value:GetStringWidth()) + math.ceil(chip.arrow:GetStringWidth())
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", f.chips, "LEFT", x, 0)
        x = x + w + CHIP_GAP
    end
    f.chips:SetWidth(math.max(1, x - CHIP_GAP))
end

-- Off (BiS List or Drop Alert): all of it faded and still. On-Screen Alert off: the header
-- stays live, since Play test still plays the chat line, sounds and badge.
local function PaintState(f, live, looks, picked)
    f:SetAlpha(live and 1 or OFF_ALPHA)
    f.toastToggle:EnableMouse(live)
    for _, tab in ipairs(f.tabs.buttons) do tab:EnableMouse(live) end
    f.test:EnableMouse(live)
    f.test.off = not picked
    f.test:SetAlpha((live and not picked) and OFF_ALPHA or 1)
    f.test._onClick = picked and PlayTest or nil
    ns.Tooltip(f.test, "Play test", picked and TEST_TIP or TEST_NEEDS_BIS)
    local faded = live and not looks
    f.stage:SetAlpha(faded and OFF_ALPHA or 1)
    f.look:SetAlpha(faded and OFF_ALPHA or 1)
    f.stage:EnableMouse(looks)
    for _, zone in ipairs(f.zones) do zone:EnableMouse(looks) end
    for _, chip in ipairs(f.chipList) do chip:EnableMouse(looks) end
    for _, track in ipairs(f.sliders) do
        track:EnableMouse(looks)
        track.box:EnableMouse(looks)
        if not looks then track.box:ClearFocus() end
        track._refreshValue()
    end
    f.glow:EnableMouse(looks)
    if not looks then f.lit = nil end
    PaintZones(f)
end

local function Refresh(f)
    if not f:IsVisible() then return end
    local live = B.On() and S.Get("bisLootAlert") and true or false
    local looks = live and S.Get("bisToast") == true
    local id, rank, picked = Sample()
    f.toastToggle._refreshValue()
    f.glow._refreshValue()
    Parts.PaintTabs(f.tabs, shownEvent)
    PaintState(f, live, looks, picked)

    local shown = id ~= nil
    f.toast:SetShown(shown)
    f.empty:SetShown(not shown)
    f.emptyLink:SetShown(not shown)
    f.chips:SetShown(shown and S.Get("bisToast") == true)
    f.offNote:SetShown(shown and S.Get("bisToast") ~= true)
    for _, zone in ipairs(f.zones) do zone:SetShown(shown) end
    if not shown then return end
    B.Toast.Paint(f.toast, id, rank, shownEvent)
    -- At its real size, unless the stage is too narrow for it; raised clear of the chips.
    local scale = math.min(S.Get("bisToastScale"), (StageWidth(f) - TOAST_ROOM) / TOAST_W)
    f.toast:SetScale(scale)
    f.toast:ClearAllPoints()
    f.toast:SetPoint("CENTER", f.stage, "CENTER", 0, CHIPS_ROOM / 2 / scale)
    PlaceZones(f, scale)
    PaintChips(f)
end

-- The stage's width is only known once the page is laid out.
local function StageResized(stage) Refresh(stage.studio) end

local function Build(parent)
    local f = New(parent)
    f.Refresh = Refresh
    f.stage:SetScript("OnSizeChanged", StageResized)
    return f
end

--- The studio, at y on the settings page; returns its height with the gap under it.
function B.BuildAlertStudio(parent, y)
    local UI = ns.UI
    if UI.searchScan then
        UI.ScanLabels(SEARCH_LABELS, SEARCH_TIP)
        return STUDIO_H + GAP_UNDER
    end
    studio = UI.Keep(parent, "bisAlertStudio", Build)
    studio._searchLabels, studio._searchF = SEARCH_SET, parent._nsuiFeatureId
    studio:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y)
    studio:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, y)
    studio:Refresh()
    return STUDIO_H + GAP_UNDER
end

S.OnChange(function(key)
    if studio and (key == "bis" or key == "bisLootAlert" or key:find("^bisToast") or key:find("^bisAlert")) then
        studio:Refresh()
    end
end)
