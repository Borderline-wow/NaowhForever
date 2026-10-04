-------------------------------------------------------------------------------
--  Studio.lua -- a settings card's live preview: a stage and the moments it can be seen in,
--  painted by the module's own drawing code. A moment with `needs` (a setting's key, or a
--  function) only has its tab while that is on. Used by every settings card with a preview.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Settings, Parts = Shared.Settings, Shared.Parts

local St = Shared.Style
local BORDER_RGB = St.BORDER_RGB

local PAD = 14
local TOP = 12
local TABS_MARGIN = 24
local TABS_GAP = 8
local DEFAULT_H = 150

local shownState = {}

local function Shown(card, state)
    local needs = state.needs
    if not needs then return true end
    if type(needs) == "function" then return needs() and true or false end
    return card.store.Get(needs) and true or false
end

local function StateOf(card, states)
    local key = shownState[card.uid]
    for i = 1, #states do
        if states[i].key == key then return key end
    end
    return states[1].key
end

local function TabPicked(row, key)
    shownState[row.card.uid] = key
    row:GetParent():QueueSettingsRedraw()
end

local function NewStudio(view)
    local row = CreateFrame("Frame", nil, view)
    row.stage = CreateFrame("Frame", nil, row)
    row.stage:SetPoint("BOTTOMLEFT", PAD, PAD)
    row.stage:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ns.Solid(row.stage, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(row.stage, BORDER_RGB)
    row.stage:SetClipsChildren(true)
    row.previews = {}
    row.states = {}
    return row
end

local function SetStudio(row, card)
    local studio = card.studio
    row.card = card
    local height = studio.height or DEFAULT_H
    for owner, preview in pairs(row.previews) do preview:SetShown(owner == card) end
    local preview = row.previews[card]
    if not preview then
        preview = studio.new(row.stage)
        row.previews[card] = preview
    end
    preview:Show()
    local states = row.states
    wipe(states)
    for _, s in ipairs(studio.states) do
        if Shown(card, s) then states[#states + 1] = s end
    end
    if #states == 0 then states[1] = studio.states[1] end
    local state = StateOf(card, states)
    if #states > 1 and not row.tabs then
        row.tabs = Parts.Tabs(row, 1, states, function(key) TabPicked(row, key) end)
        row.tabs:SetPoint("TOPRIGHT", -PAD, -TOP)
    end
    if row.tabs then
        row.tabs:SetShown(#states > 1)
        if #states > 1 then
            Parts.FitTabs(row.tabs, states, TABS_MARGIN)
            Parts.PaintTabs(row.tabs, state)
        end
    end
    local tabsH = #states > 1 and (row.tabs:GetHeight() + TABS_GAP) or 0
    row.stage:SetHeight(height)
    studio.paint(preview, state)
    return TOP + tabsH + height + PAD
end

Settings.kinds.studio = { New = NewStudio, Set = SetStudio }
