-------------------------------------------------------------------------------
--  NaowhForever_Search.lua -- the search bar under the options window's header: every page,
--  card and setting matching what is typed, in the order the window shows them, stepped
--  through one at a time. It reads the declared settings (ns.Shared.Settings); pages drawn
--  some other way are found by their name only.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

-- Lowercase words with single spaces, padded so " word" finds a word's start anywhere.
local function Words(text)
    return " " .. text:lower():gsub("[^%w]+", " ") .. " "
end

-- Where a page, card or setting sits: `tag` names the module (or the window's own page), and
-- `trail` the tab and card under it.
local function Place(page, cardName)
    local parts = {}
    local mod = page.module
    if mod and #mod.tabs > 1 then parts[#parts + 1] = ns.L(page.name) end
    if cardName then parts[#parts + 1] = cardName end
    return ns.L(mod and mod.name or page.title or page.name), table.concat(parts, " / ")
end

-- One list in window order: each page, then its cards, each card followed by its settings. A
-- setting knows its own words (name, help, group); a card its name and help; a page its own
-- and its module's names.
local function Collect()
    local list = {}
    local Settings = ns.Shared and ns.Shared.Settings
    for _, page in ipairs(UI.SearchPages()) do
        local tag, trail = Place(page)
        local pageWords = Words(tag .. " " .. ns.L(page.name))
        list[#list + 1] = { page = page.key, tag = tag, trail = trail, words = pageWords }
        if Settings then
            Settings.Index(page.key, function(card, label, help, cardName, group)
                local t, where = Place(page, cardName)
                list[#list + 1] = { page = page.key, card = card, label = label, tag = t, trail = where,
                    words = Words(table.concat({ label, help or "", group or "", cardName or "" }, " ")) }
            end)
        end
    end
    return list
end

-- Every typed word has to start a word of the target's own.
local function Find(list, query)
    local typed = {}
    for word in Words(query):gmatch("%S+") do typed[#typed + 1] = " " .. word end
    local out = {}
    if #typed == 0 then return out end
    for _, target in ipairs(list) do
        local all = true
        for _, word in ipairs(typed) do
            if not target.words:find(word, 1, true) then all = false break end
        end
        if all then out[#out + 1] = target end
    end
    return out
end

UI.Search = { Collect = Collect, Find = Find }

-------------------------------------------------------------------------------
--  The bar: the SEARCH tag, the input, a "3 of 12" counter and Previous / Next on its first
--  line; under them a chip per match, the current one lit.
-------------------------------------------------------------------------------
local BAR_H, BAR_PAD = 72, 10
local EDGE = 2              -- the accent line along the bar's bottom, against the page
local TAG_SIZE = 11         -- the SEARCH tag before the input
local INPUT_W, INPUT_H = 280, 26
local STEP_W, CLOSE_W, BUTTON_GAP = 72, 26, 6
local CHIP_H, CHIP_PAD, CHIP_GAP, CHIP_MAX_W = 22, 10, 6, 340
local CHIP_TEXT, CHIP_TAG = 11, 9
local TAG_GAP = 6           -- a chip's module tag to its text
local CHIP_LIT = 0.16       -- the current chip's fill, in the accent

local bar, input, counter, measure, measureTag
local chips = {}
local list
local matches, widths = {}, {}
local current, first = 0, 1

local function ChipText(target)
    local trail = target.trail ~= "" and ns.Color("muted", target.trail) or ""
    if not target.label then return trail end
    return trail ~= "" and (trail .. "  " .. target.label) or target.label
end

local function ChipWidth(i)
    if not widths[i] then
        local target = matches[i]
        measureTag:SetText(target.tag:upper())
        measure:SetText(ChipText(target))
        widths[i] = math.min(measureTag:GetStringWidth() + TAG_GAP + measure:GetStringWidth() + CHIP_PAD * 2, CHIP_MAX_W)
    end
    return widths[i]
end

local function PaintChip(chip, hover)
    local lit = chip.index == current
    local edge = (lit or hover) and T.accent or T.line
    local fill = lit and T.accent or T.bg
    chip.edge:SetColor(edge.r, edge.g, edge.b, 1)
    chip.fill:SetColorTexture(fill.r, fill.g, fill.b, lit and CHIP_LIT or 1)
end

local Go

local function NewChip()
    local chip = CreateFrame("Button", nil, bar)
    chip:SetHeight(CHIP_H)
    chip.fill = ns.Solid(chip, "BACKGROUND", T.bg, 1)
    chip.fill:SetAllPoints()
    chip.edge = ns.Border(chip, T.line)
    chip.tag = ns.Font(chip, CHIP_TAG, nil, T.accent)
    chip.tag:SetPoint("LEFT", CHIP_PAD, 0)
    chip.text = ns.Font(chip, CHIP_TEXT, nil)
    chip.text:SetPoint("LEFT", chip.tag, "RIGHT", TAG_GAP, 0)
    chip.text:SetPoint("RIGHT", -CHIP_PAD, 0)
    chip.text:SetJustifyH("LEFT")
    chip.text:SetWordWrap(false)
    chip:SetScript("OnClick", function(self) Go(self.index) end)
    chip:SetScript("OnEnter", function(self) PaintChip(self, true) end)
    chip:SetScript("OnLeave", function(self) PaintChip(self, false) end)
    return chip
end

-- The chips from `first` on, as many as fit; `first` moves only as far as it must to keep
-- the current chip in view.
local function DrawChips()
    local room = bar:GetWidth() - BAR_PAD * 2
    if current > 0 then
        if current < first then first = current end
        local span = -CHIP_GAP
        for i = first, current do span = span + ChipWidth(i) + CHIP_GAP end
        while first < current and span > room do
            span = span - ChipWidth(first) - CHIP_GAP
            first = first + 1
        end
    end
    local x, shown = BAR_PAD, 0
    for i = first, #matches do
        local w = ChipWidth(i)
        if x + w > BAR_PAD + room and shown > 0 then break end
        shown = shown + 1
        local chip = chips[shown] or NewChip()
        chips[shown] = chip
        chip.index = i
        chip.tag:SetText(matches[i].tag:upper())
        chip.text:SetText(ChipText(matches[i]))
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, BAR_PAD)
        PaintChip(chip, false)
        chip:Show()
        x = x + w + CHIP_GAP
    end
    for i = shown + 1, #chips do chips[i]:Hide() end
    if current > 0 then
        counter:SetText(current .. " " .. ns.L("of") .. " " .. #matches)
    else
        counter:SetText(input:GetText() ~= "" and ns.L("No match") or "")
    end
end

-- The match's card is held open and its row marked only while the bar is up.
function Go(i)
    current = i
    local target = matches[i]
    UI.searchOpen = target.card and { [target.card] = true }
    UI.searchFocus = target.label and { label = target.label, card = target.card }
    UI.GoToSetting(target.page, target.label, target.card)
    DrawChips()
end

local function Step(by)
    if #matches > 0 then Go((current - 1 + by) % #matches + 1) end
end

local function Unmark()
    if not (UI.searchFocus or UI.searchOpen) then return end
    UI.searchFocus, UI.searchOpen = nil, nil
    UI:RefreshPage(true)
end

local function OnText(text)
    matches, widths, current, first = {}, {}, 0, 1
    if text:find("%S") then
        -- Collected once per opening of the bar, so it lists the settings as they are now.
        list = list or Collect()
        matches = Find(list, text)
    end
    if matches[1] then
        Go(1)
    else
        Unmark()
        DrawChips()
    end
end

-- The card holding the last match stays open, so the setting is still there to change.
function UI.CloseSearch()
    local target = matches[current]
    if target and target.card then ns.Shared.Settings.Reveal(target.card) end
    bar:Hide()
    input:ClearFocus()
    input:SetText("")
    list = nil
end

function UI.OpenSearch()
    bar:Show()
    input:SetFocus()
    input:HighlightText()
end

local function StepButton(text, by)
    return ns.Button(bar, text, STEP_W, INPUT_H, function() Step(by) end)
end

function UI.AttachSearchBar(window, onLayout)
    bar = CreateFrame("Frame", nil, window)
    bar:SetHeight(BAR_H)
    bar:SetFrameLevel(window:GetFrameLevel() + 20)
    bar:EnableMouse(true)
    bar:Hide()
    ns.Solid(bar, "BACKGROUND", T.panel, 1):SetAllPoints()
    local edge = ns.Solid(bar, "ARTWORK", T.accent, 1)
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(EDGE)
    input = ns.NewSearchBox(bar, "Setting, card or page", OnText)
    input:SetSize(INPUT_W, INPUT_H)
    input:SetScript("OnEnterPressed", function() Step(IsShiftKeyDown() and -1 or 1) end)
    input:SetScript("OnEscapePressed", UI.CloseSearch)
    local tag = ns.Font(bar, TAG_SIZE, nil, T.accent)
    tag:SetPoint("TOPLEFT", BAR_PAD, -BAR_PAD)
    tag:SetHeight(INPUT_H)
    tag:SetText(ns.L("SEARCH"))
    input:SetPoint("LEFT", tag, "RIGHT", BAR_PAD, 0)
    counter = ns.Font(bar, 12, nil, T.muted)
    counter:SetPoint("LEFT", input, "RIGHT", BAR_PAD, 0)
    measure = ns.Font(bar, CHIP_TEXT, nil)
    measure:Hide()
    measureTag = ns.Font(bar, CHIP_TAG, nil)
    measureTag:Hide()
    local close = ns.Button(bar, "X", CLOSE_W, INPUT_H, UI.CloseSearch)
    close:SetPoint("TOPRIGHT", -BAR_PAD, -BAR_PAD)
    local nextButton = StepButton("Next", 1)
    nextButton:SetPoint("RIGHT", close, "LEFT", -BUTTON_GAP * 2, 0)
    StepButton("Previous", -1):SetPoint("RIGHT", nextButton, "LEFT", -BUTTON_GAP, 0)
    bar:SetScript("OnShow", onLayout)
    bar:SetScript("OnHide", function()
        Unmark()
        onLayout()
    end)
    bar:SetScript("OnSizeChanged", function() if bar:IsShown() then DrawChips() end end)
    UI:RegisterOnHide(UI.CloseSearch)
    return bar
end
