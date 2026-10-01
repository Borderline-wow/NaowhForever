-------------------------------------------------------------------------------
--  UI/Window.lua -- the Dungeon Journal's own window (/nfjournal or /nfdj, its minimap and
--  top bar button, and Open Dungeon Journal on its settings page): the dungeon list down
--  the left (UI/DungeonList.lua), the one you pick on the right, drawn by the Journal's view,
--  a search over every dungeon, and in the title bar the list's button, Filters and the
--  window's opacity. The list can be hidden, for the bosses across the whole window. Made
--  the first time it opens; movable, and it remembers where you put it and whether the list
--  shows. Opening it turns the module on; turning the module off closes it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings
local Loot = J.Loot
local List = J.DungeonList

local St = J.Style
local WIDTH, HEIGHT, HEADER, PAD = St.WINDOW_W, St.WINDOW_H, St.WINDOW_HEADER, St.WINDOW_PAD
local LIST_W, SEARCH_H, SCROLLBAR, CONTENT_INSET = St.LIST_W, St.SEARCH_H, St.SCROLLBAR, St.CONTENT_INSET
local BORDER_RGB = St.BORDER_RGB
local BAR_ICON, FUNNEL, OPACITY, ROUND = St.BAR_ICON, St.FUNNEL, St.OPACITY, St.ROUND
local LIST_SHOWN, LIST_HIDDEN, LOGO, LOGO_SIZE = St.LIST_SHOWN, St.LIST_HIDDEN, St.LOGO, St.LOGO_SIZE
local FACTION_W, FACTION_ICON, FACTION_OFF, FACTION_GAP = St.FACTION_W, St.FACTION_ICON, St.FACTION_OFF, St.FACTION_GAP
local FACTION_ATLAS, TERRITORY_CODE = St.FACTION_ATLAS, St.TERRITORY_CODE
local SLIDER_W, SLIDER_H, KNOB, KNOB_GLOW, OPACITY_MIN = St.SLIDER_W, St.SLIDER_H, St.KNOB, St.KNOB_GLOW,
    St.OPACITY_MIN

local SEARCH_DELAY = 0.15   -- seconds after the last key before the search runs
local MIN_QUERY = 2         -- letters

local window, view, scroll, search, listFrame
local backdrop                -- the window's background (Parts.Backdrop), faded by Opacity
local listCard, contentCard   -- its two cards: behind the list, and behind the dungeon
local selected                -- the dungeon shown, for this session

-------------------------------------------------------------------------------
--  Showing a dungeon, and searching
-------------------------------------------------------------------------------
local shownQuery = ""         -- the search on the page ("" for a dungeon)
local searchQueued = false
local clearing = false        -- the window is emptying the search box itself

local function Select(dungeon)
    selected = dungeon
    if search:GetText() ~= "" then
        clearing = true
        search:SetText("")
        clearing = false
    end
    shownQuery = ""
    List.Paint(selected)
    view:Draw(dungeon)
    scroll:SetVerticalScroll(0)
end

-- Two letters or more search every dungeon's bosses and loot; fewer go back to the dungeon.
-- Runs once typing pauses, and only when the search changed.
local function RunSearch()
    searchQueued = false
    if not window:IsShown() then return end
    local query = strtrim(search:GetText()):lower()
    if #query < MIN_QUERY then query = "" end
    if query == shownQuery then return end
    shownQuery = query
    if query == "" then view:Draw(selected) else view:DrawSearch(query, Select) end
    scroll:SetVerticalScroll(0)
end

local function OnSearch()
    if clearing or searchQueued then return end
    searchQueued = true
    C_Timer.After(SEARCH_DELAY, RunSearch)
end

-- Up and Down step through the list, and Ctrl+F goes to the search box, while the mouse is
-- on the window and you are not typing. Only then: the rest of the time the keys do what the
-- game has them do. Out of combat, where the window may keep a key from the game; everything
-- else goes to Esc's handler.
local function PassKeysOn()
    if not InCombatLockdown() then window:SetPropagateKeyboardInput(true) end
end

local function OnKeyDown(self, key)
    if not InCombatLockdown() and self:IsMouseOver() and not search:HasFocus() then
        if key == "UP" or key == "DOWN" then
            self:SetPropagateKeyboardInput(false)
            Select(List.Next(selected, key == "UP" and -1 or 1))
            C_Timer.After(0, PassKeysOn)
            return
        elseif key == "F" and IsControlKeyDown() then
            self:SetPropagateKeyboardInput(false)
            search:SetFocus()
            C_Timer.After(0, PassKeysOn)
            return
        end
    end
    ns.UI.CloseOnEscape(self, key)
end

-- The search box: a lighter fill than the window in the house's black border, and the
-- accent edge while you type in it.
local function Edge(box, color)
    box.border:SetColor(color.r, color.g, color.b, 1)
end

local function SearchFocus(box) Edge(box, T.accent) end
local function SearchBlur(box) Edge(box, BORDER_RGB) end

local function SearchBox(parent)
    local box = ns.NewSearchBox(parent, "Search items or bosses", OnSearch)
    local fill = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 1)
    fill:SetAllPoints()
    Edge(box, BORDER_RGB)
    box:HookScript("OnEditFocusGained", SearchFocus)
    box:HookScript("OnEditFocusLost", SearchBlur)
    return box
end

-------------------------------------------------------------------------------
--  Filters: the Journal's switches (J.OPTION_GROUPS), ticked while on, under what they do
-------------------------------------------------------------------------------
local GROUPS = J.OPTION_GROUPS

-- Whether an option works now: one that needs the BiS List does nothing without it.
local function Available(option)
    return not option.needsBis or Loot.BisOn()
end

-- How many filters are hiding something: the number beside the funnel.
local function FiltersOn()
    local on = 0
    for _, group in ipairs(GROUPS) do
        for _, option in ipairs(group.options) do
            if option.hides ~= nil and S.Get(option.key) == option.hides and Available(option) then
                on = on + 1
            end
        end
    end
    return on
end

local function OptionOn(option)
    return S.Get(option.key)
end

local function OptionFlip(option)
    S.Set(option.key, not S.Get(option.key))
end

local function OptionAvailable(description)
    return Available(description:GetData())
end

local function OpenFilters(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for i, group in ipairs(GROUPS) do
            if i > 1 then root:CreateDivider() end
            root:CreateTitle(group.title)
            for _, option in ipairs(group.options) do
                local box = root:CreateCheckbox(option.label, OptionOn, OptionFlip, option)
                if option.needsBis then
                    box:SetEnabled(OptionAvailable)
                    box:SetTitleAndTextTooltip(option.label, Available(option) and option.tooltip
                        or option.tooltip .. " " .. J.NEEDS_BIS)
                else
                    box:SetTitleAndTextTooltip(option.label, option.tooltip)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  The faction switch beside the search: the Alliance crest on the left, the Horde's on the
--  right, each half listing or hiding the dungeons on its side's ground (contested ones
--  always show). One half stays on: switching off the last one turns the other back on.
-------------------------------------------------------------------------------
local SIDES = { { faction = "Alliance", key = "showAlliance" }, { faction = "Horde", key = "showHorde" } }

-- "|cff4a9eff" -> r, g, b
local function CodeRGB(code)
    return tonumber(code:sub(5, 6), 16) / 255, tonumber(code:sub(7, 8), 16) / 255, tonumber(code:sub(9, 10), 16) / 255
end

local function PaintSide(half)
    local on = S.Get(half.side.key)
    half.icon:SetDesaturated(not on)
    half.icon:SetAlpha(on and 1 or FACTION_OFF)
    half.fill:SetShown(on)
end

local function PaintFactions()
    for _, half in ipairs(window.factions) do PaintSide(half) end
end

local function SideEnter(half)
    local side = half.side
    local on = S.Get(side.key)
    GameTooltip:SetOwner(half, "ANCHOR_BOTTOM")
    GameTooltip:SetText(TERRITORY_CODE[side.faction] .. side.faction .. " dungeons|r", 1, 1, 1)
    GameTooltip:AddLine(on and "Listed. Click to hide the dungeons on " .. side.faction .. " ground."
        or "Hidden. Click to list them again.", 1, 1, 1, true)
    GameTooltip:AddLine("Contested ones are always listed.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function SideClicked(half)
    local key = half.side.key
    local turningOff = S.Get(key)
    if turningOff then
        for _, side in ipairs(SIDES) do
            if side.key ~= key and not S.Get(side.key) then S.Set(side.key, true) end
        end
    end
    S.Set(key, not turningOff)
    SideEnter(half)
end

local function FactionSwitch(parent)
    local switch = CreateFrame("Frame", nil, parent)
    switch:SetSize(FACTION_W * 2, SEARCH_H)
    ns.Solid(switch, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(switch, BORDER_RGB)
    local halves = {}
    for i, side in ipairs(SIDES) do
        local half = CreateFrame("Button", nil, switch)
        half:SetSize(FACTION_W, SEARCH_H)
        half:SetPoint("LEFT", (i - 1) * FACTION_W, 0)
        half.side = side
        -- A faint fill in the side's colour while it is on.
        half.fill = half:CreateTexture(nil, "BACKGROUND", nil, 1)
        half.fill:SetAllPoints()
        local r, g, b = CodeRGB(TERRITORY_CODE[side.faction])
        half.fill:SetColorTexture(r, g, b, 0.15)
        half.icon = half:CreateTexture(nil, "ARTWORK")
        half.icon:SetAtlas(FACTION_ATLAS[side.faction])
        half.icon:SetSize(FACTION_ICON, FACTION_ICON)
        half.icon:SetPoint("CENTER")
        half:SetScript("OnClick", SideClicked)
        half:SetScript("OnEnter", SideEnter)
        half:SetScript("OnLeave", GameTooltip_Hide)
        halves[i] = half
    end
    -- The line between the halves.
    local split = ns.Solid(switch, "BORDER", BORDER_RGB, 1)
    split:SetPoint("TOP", 0, 0)
    split:SetPoint("BOTTOM", 0, 0)
    split:SetWidth(1)
    return switch, halves
end

-------------------------------------------------------------------------------
--  The backdrop's opacity (the backdrop itself is Parts.Backdrop, shared with the quest panel)
-------------------------------------------------------------------------------
local function Opacity()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

-- value is a percent.
local function ApplyOpacity(value)
    backdrop:Paint(value / 100)
end

-- The slider's and the settings page's: the setting changes, and SettingChanged paints it.
local function SetOpacity(value)
    S.Set("windowAlpha", value / 100)
end

-------------------------------------------------------------------------------
--  The title bar's icons: muted, blue under the mouse, each saying what it is on hover
-------------------------------------------------------------------------------
local function IconColor(frame, color)
    frame.icon:SetVertexColor(color.r, color.g, color.b)
end

local function IconLeave(frame)
    IconColor(frame, T.muted)
    GameTooltip:Hide()
end

local function BarIcon(parent, texture, isButton)
    local frame = CreateFrame(isButton and "Button" or "Frame", nil, parent)
    frame:SetSize(BAR_ICON + 4, BAR_ICON + 4)
    frame:EnableMouse(true)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture(texture)
    frame.icon:SetSize(BAR_ICON, BAR_ICON)
    frame.icon:SetPoint("LEFT", 2, 0)
    IconColor(frame, T.muted)
    frame:SetScript("OnLeave", IconLeave)
    return frame
end

-- Filters: a funnel, with how many are on beside it.
local function FiltersEnter(button)
    IconColor(button, T.accent)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    local on = FiltersOn()
    GameTooltip:SetText(on == 1 and "Filters: 1 hiding loot or bosses"
        or ("Filters: %d hiding loot or bosses"):format(on), 1, 1, 1)
    GameTooltip:AddLine("Click to choose what is listed and shown.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function PaintFilters()
    local on = FiltersOn()
    local button = window.filters
    button.count:SetText(on > 0 and on or "")
    button:SetWidth(BAR_ICON + 4 + (on > 0 and math.ceil(button.count:GetStringWidth()) + 2 or 0))
end

local function FiltersButton(parent)
    local button = BarIcon(parent, FUNNEL, true)
    button.count = ns.Font(button, 12, nil, T.accentSoft)
    button.count:SetPoint("LEFT", button.icon, "RIGHT", 2, 0)
    button:SetScript("OnClick", OpenFilters)
    button:SetScript("OnEnter", FiltersEnter)
    return button
end

-- Opacity: a half-filled circle before its slider.
local function OpacityEnter(frame)
    IconColor(frame, T.accent)
    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Window opacity", 1, 1, 1)
    GameTooltip:Show()
end

-- The list's button: a window with its left panel filled while the list shows, empty while
-- it is hidden.
local function ToggleEnter(button)
    IconColor(button, T.accent)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText(S.Get("listHidden") and "Show the dungeon list" or "Hide the dungeon list", 1, 1, 1)
    GameTooltip:Show()
end

local function ToggleClicked(button)
    S.Set("listHidden", not S.Get("listHidden"))
    ToggleEnter(button)
end

-- The opacity slider in the Journal's own look, on the kit's slider: a thin track with
-- round ends, its filled part a blue that brightens toward a round white knob, a soft glow
-- round the knob under the mouse, and the value as plain muted text with a % after it.
local function Round(parent, layer, size, color, alpha)
    local dot = parent:CreateTexture(nil, layer)
    dot:SetTexture(ROUND)
    dot:SetSize(size, size)
    dot:SetVertexColor(color.r, color.g, color.b, alpha or 1)
    return dot
end

local function GlowShow(slider) slider.glow:Show() end
local function GlowHide(slider)
    if not IsMouseButtonDown("LeftButton") then slider.glow:Hide() end
end
local function GlowRelease(slider)
    if not slider:IsMouseOver() then slider.glow:Hide() end
end

local function OpacitySlider(parent, rightOf)
    local slider = ns.UI.BuildSliderCore(parent, SLIDER_W, SLIDER_H, KNOB, 24, 18, 11, 1, OPACITY_MIN, 100, 5,
        Opacity, SetOpacity)
    local dim, bright = T.accent, T.accentSoft
    local deep = { r = dim.r * 0.6, g = dim.g * 0.6, b = dim.b * 0.6 }
    -- Round ends: a dot at each end of the track, the left one in the fill's first colour.
    Round(slider, "BORDER", SLIDER_H, deep):SetPoint("CENTER", slider.rail, "LEFT", 0, 0)
    Round(slider, "BACKGROUND", SLIDER_H, T.line):SetPoint("CENTER", slider.rail, "RIGHT", 0, 0)
    slider.fill:SetColorTexture(1, 1, 1, 1)
    slider.fill:SetGradient("HORIZONTAL", CreateColor(deep.r, deep.g, deep.b, 1),
        CreateColor(bright.r, bright.g, bright.b, 1))
    slider.thumb:SetTexture(ROUND)
    slider.thumb:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
    slider.thumb:SetSize(KNOB, KNOB)
    slider.glow = Round(slider, "BORDER", KNOB_GLOW, bright, 0.25)
    slider.glow:SetPoint("CENTER", slider.thumb, "CENTER")
    slider.glow:Hide()
    slider:HookScript("OnEnter", GlowShow)
    slider:HookScript("OnLeave", GlowHide)
    slider:HookScript("OnMouseUp", GlowRelease)
    -- The value: no box, muted, right-aligned before its %.
    local box = slider.valueBox
    slider.valueFill:Hide()
    slider.valueBorder._frame:Hide()
    box:SetFont(ns.UIFontPath(), 11, "")
    box:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(0, 0, 0, 0)
    box:SetWidth(24)
    local percent = ns.Font(parent, 11, nil, T.muted)
    percent:SetText("%")
    percent:SetPoint("RIGHT", rightOf, "LEFT", -14, 0)
    box:SetPoint("RIGHT", percent, "LEFT", -1, 0)
    slider:SetPoint("RIGHT", box, "LEFT", -10, 0)
    return slider
end

-------------------------------------------------------------------------------
--  Hiding the list: the search, the list and their card fold away and the dungeon takes the
--  window's whole width, its bosses three across. Up and Down still step through dungeons.
-------------------------------------------------------------------------------
local function Arrange()
    local hidden = S.Get("listHidden")
    if hidden and search:GetText() ~= "" then
        clearing = true
        search:SetText("")
        clearing = false
        shownQuery = ""
    end
    search:SetShown(not hidden)
    window.factionSwitch:SetShown(not hidden)
    listFrame:SetShown(not hidden)
    for _, part in ipairs(listCard) do part:SetShown(not hidden) end
    local cardLeft = hidden and 6 or LIST_W + PAD + 14
    local fill = contentCard[1]
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", cardLeft, -(HEADER + 6))
    fill:SetPoint("BOTTOMRIGHT", -4, 6)
    local left = cardLeft + CONTENT_INSET
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", left, -(HEADER + PAD + 4))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - 4, PAD)
    view:SetWidth(WIDTH - left - SCROLLBAR - PAD - 8)
    window.listToggle.icon:SetTexture(hidden and LIST_HIDDEN or LIST_SHOWN)
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function SavePosition()
    local point, _, relativePoint, x, y = window:GetPoint()
    ns.AccountSettings().journalWindow = { point, relativePoint, x, y }
end

local function DragStop(frame)
    frame:StopMovingOrSizing()
    SavePosition()
end

local function OnShow(frame)
    if not InCombatLockdown() then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
end

local function Close()
    window:Hide()
end

-- The Naowh logo opens the addon's options on the Journal's page, over this window.
local function LogoClicked()
    ns.OpenOptionsWindow("Dungeon Journal")
end

local function LogoEnter(logo)
    logo.icon:SetAlpha(1)
    GameTooltip:SetOwner(logo, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText("Naowh Forever", 1, 1, 1)
    GameTooltip:AddLine("Click to open its options.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local LOGO_REST = 0.9

local function LogoLeave(logo)
    logo.icon:SetAlpha(LOGO_REST)
    GameTooltip:Hide()
end

-- Every draw repaints the list too: a BiS change from an item's menu moves its counts.
local function Drawn()
    List.Paint(selected)
end

local function Build()
    window = CreateFrame("Frame", nil, UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", DragStop)
    local saved = ns.AccountSettings().journalWindow
    if type(saved) == "table" then
        window:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        window:SetPoint("CENTER")
    end
    backdrop = J.View.Parts.Backdrop(window)
    listCard = backdrop:Card(6, HEADER + 6, WIDTH - LIST_W - PAD - 6, 6)
    contentCard = backdrop:Card(LIST_W + PAD + 14, HEADER + 6, 4, 6)
    ns.Border(window, BORDER_RGB)

    -- The title bar: the logo and the title on the left; right to left, close, opacity,
    -- Filters and the list's button. All centred on the bar.
    local middle = -HEADER / 2
    local logo = CreateFrame("Button", nil, window)
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("LEFT", window, "TOPLEFT", PAD, middle)
    logo.icon = logo:CreateTexture(nil, "ARTWORK")
    logo.icon:SetAllPoints()
    logo.icon:SetTexture(LOGO, nil, nil, "TRILINEAR")
    logo.icon:SetAlpha(LOGO_REST)
    logo:SetScript("OnClick", LogoClicked)
    logo:SetScript("OnEnter", LogoEnter)
    logo:SetScript("OnLeave", LogoLeave)
    -- The title over the subtitle, the pair as tall as the logo beside it.
    local title = ns.Font(window, 20, nil, T.fg)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 1)
    title:SetText("Dungeon Journal")
    local subtitle = ns.Font(window, 11, nil, T.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("Every dungeon and raid: what drops, your quests, and more.")
    local close = ns.Button(window, "x", 24, 24, Close)
    close:SetPoint("RIGHT", window, "TOPRIGHT", -8, middle)

    local slider = OpacitySlider(window, close)
    window.opacity = slider
    local opacityIcon = BarIcon(window, OPACITY)
    opacityIcon:SetScript("OnEnter", OpacityEnter)
    opacityIcon:SetPoint("RIGHT", slider, "LEFT", -6, 0)
    window.filters = FiltersButton(window)
    window.filters:SetPoint("RIGHT", opacityIcon, "LEFT", -18, 0)
    window.listToggle = BarIcon(window, LIST_SHOWN, true)
    window.listToggle:SetScript("OnClick", ToggleClicked)
    window.listToggle:SetScript("OnEnter", ToggleEnter)
    window.listToggle:SetPoint("RIGHT", window.filters, "LEFT", -12, 0)

    local rule = ns.Solid(window, "ARTWORK", BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -HEADER)
    rule:SetPoint("TOPRIGHT", 0, -HEADER)
    rule:SetHeight(1)

    -- The search, then the list, down the left.
    search = SearchBox(window)
    search:SetSize(LIST_W - 8 - FACTION_W * 2 - FACTION_GAP, SEARCH_H)
    search:SetPoint("TOPLEFT", PAD, -(HEADER + PAD))
    window.factionSwitch, window.factions = FactionSwitch(window)
    window.factionSwitch:SetPoint("LEFT", search, "RIGHT", FACTION_GAP, 0)
    listFrame = CreateFrame("Frame", nil, window)
    listFrame:SetPoint("TOPLEFT", PAD, -(HEADER + PAD + SEARCH_H + 4))
    listFrame:SetPoint("BOTTOMLEFT", PAD, PAD)
    listFrame:SetWidth(LIST_W)
    List.Build(listFrame, Select)

    -- The dungeon, scrolling under the title bar; Arrange places it, with the list or without.
    scroll = ns.UI.SlimScroll(window)
    view = J.View.New(scroll)
    scroll:SetScrollChild(view)
    view.onResize = Drawn

    -- Esc closes it the way it closes the options window, safe in combat.
    window:SetScript("OnKeyDown", OnKeyDown)
    window:SetScript("OnShow", OnShow)
end

-- What the profile holds: opacity, the list shown or not, the filters. On every open and on
-- a profile switch, so a switch while it is closed shows when it opens.
local function ApplyProfile()
    ApplyOpacity(Opacity())
    window.opacity._refreshValue()
    PaintFactions()
    Arrange()
    PaintFilters()
    List.Layout()
end

-- A setting it shows changed (the Filters menu here, or the settings page).
local function SettingChanged(key)
    if not (window and window:IsShown()) then return end
    if key == "enabled" then
        if not S.Get("enabled") then window:Hide() end
    elseif key == "windowAlpha" then
        ApplyOpacity(Opacity())
        window.opacity._refreshValue()
    elseif key:find("^closedGroup") then
        List.Layout()
    elseif key == "showAlliance" or key == "showHorde" then
        PaintFactions()
        List.Layout()
        if shownQuery ~= "" then view:Redraw() end
    else
        if key == "listHidden" then Arrange() end
        PaintFilters()
        view:Redraw()
    end
end

S.OnChange(SettingChanged)
hooksecurefunc(ns, "Apply", function()
    if window and window:IsShown() then
        ApplyProfile()
        view:Redraw()
    end
end)

-- Opens on the dungeon you are in, else the last one you looked at, else one for your level.
-- Draws the dungeon shown again, when the window is open: for data that changed under it
-- (kills or loot forgotten from the settings page).
function ns.RedrawJournalWindow()
    if window and window:IsShown() then view:Redraw() end
    J.View.BossPanel.Refresh()
end

-- Opens the window on the dungeon given, else the one you are in, else where it was.
---@param dungeon? JournalDungeon
function ns.OpenJournalWindow(dungeon)
    J.TurnOn()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    ApplyProfile()
    local here = J.Current()
    Select(dungeon or here and here[1] or selected or J.Suggested())
end

function ns.ToggleJournalWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenJournalWindow() end
end
