-------------------------------------------------------------------------------
--  UI/Window.lua -- the Dungeon Journal's own window (/nfjournal or /nfdj, its minimap and
--  top bar button, and Open Dungeon Journal on its settings page). Down the left a switch
--  between Dungeons & Raids, Reputation and PvP, a search over every dungeon and faction,
--  and the list the switch shows (UI/DungeonList.lua, or UI/FactionList.lua for the other
--  two); on the right the one you pick, drawn by the Journal's view; in the title bar the
--  list's button, Filters and the window's opacity. The list can be hidden, switch and
--  search with it, for the cards across the whole window. Made the first time it opens; movable, and it remembers where you put
--  it, the tab and whether the list shows. Opening it turns the module on; turning the
--  module off closes it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings
local Loot = J.Loot
local List = J.DungeonList
local Factions = J.FactionList

local St = J.Style
local WIDTH, HEIGHT, HEADER, PAD = St.WINDOW_W, St.WINDOW_H, St.WINDOW_HEADER, St.WINDOW_PAD
local FOOTER = St.WINDOW_FOOTER
local LIST_W, SEARCH_H, SCROLLBAR, CONTENT_INSET = St.LIST_W, St.SEARCH_H, St.SCROLLBAR, St.CONTENT_INSET
local BORDER_RGB, PLACE_DOT = St.BORDER_RGB, St.PLACE_DOT
local BAR_ICON, FUNNEL, OPACITY, ROUND, TICK = St.BAR_ICON, St.FUNNEL, St.OPACITY, St.ROUND, St.TICK
local LIST_SHOWN, LIST_HIDDEN, LOGO, LOGO_SIZE = St.LIST_SHOWN, St.LIST_HIDDEN, St.LOGO, St.LOGO_SIZE
local FACTION_W, FACTION_ICON, FACTION_OFF, FACTION_GAP = St.FACTION_W, St.FACTION_ICON, St.FACTION_OFF, St.FACTION_GAP
local FACTION_ATLAS, TERRITORY_CODE = St.FACTION_ATLAS, St.TERRITORY_CODE
local TAB_SIZE, TAB_H, TAB_LINE, TAB_FILL, TAB_GAP = St.TAB_SIZE, St.TAB_H, St.TAB_LINE, St.TAB_FILL, St.TAB_GAP
local SLIDER_W, SLIDER_H, KNOB, KNOB_GLOW, OPACITY_MIN = St.SLIDER_W, St.SLIDER_H, St.KNOB, St.KNOB_GLOW,
    St.OPACITY_MIN

local SEARCH_DELAY = 0.15   -- seconds after the last key before the search runs
local MIN_QUERY = 2         -- letters

local window, view, scroll, search, listFrame, factionFrame
local backdrop                -- the window's background (Parts.Backdrop), faded by Opacity
local listCard, contentCard   -- its two cards: behind the list, and behind the page
local selected                -- the page shown: a dungeon, a faction or J.RANK
local shownTab                -- "dungeons", "reputation" or "pvp"
local picked = {}             -- tab -> the page last shown on it, for this session

-------------------------------------------------------------------------------
--  The switch over the list: Dungeons & Raids, Reputation, PvP. Each part shows its own
--  list, and opens on the page last shown on it.
-------------------------------------------------------------------------------
local TABS = {
    { key = "dungeons", label = "Dungeons & Raids" },
    { key = "reputation", label = "Reputation" },
    { key = "pvp", label = "PvP" },
}

-- The tab a page is on.
local function TabOf(page)
    return page.tab or "dungeons"
end

-- The tab it was left on, last session too.
local function SavedTab()
    local tab = ns.AccountSettings().journalTab
    return (tab == "reputation" or tab == "pvp") and tab or "dungeons"
end

-- The shown tab's list, or neither while the list is hidden. Nothing before the first page
-- is shown, which picks the tab.
-- The search, beside the faction switch; alone at the list's width where the switch has
-- nothing to list or hide (Reputation: no faction there is one side's).
local SEARCH_W = LIST_W - 8 - FACTION_W * 2 - FACTION_GAP
local SEARCH_FULL_W = LIST_W - 8

local function ShowLists()
    if not shownTab then return end
    local hidden = S.Get("listHidden")
    local dungeons = shownTab == "dungeons"
    local sides = shownTab ~= "reputation"
    listFrame:SetShown(dungeons and not hidden)
    factionFrame:SetShown(not dungeons and not hidden)
    window.factionSwitch:SetShown(sides and not hidden)
    search:SetWidth(sides and SEARCH_W or SEARCH_FULL_W)
    if not dungeons then Factions.Layout(shownTab) end
end

local function PaintTabs()
    for _, button in ipairs(window.tabs) do
        local on = button.tab == shownTab
        local color = on and T.fg or T.muted
        button.text:SetTextColor(color.r, color.g, color.b)
        button.fill:SetShown(on)
        button.line:SetShown(on)
    end
end

local function ShowTab(tab)
    shownTab = tab
    ns.AccountSettings().journalTab = tab
    -- The faction list shows your standing: the view redraws, and the list with it, when it moves.
    view.watchFactions = tab ~= "dungeons"
    ShowLists()
    PaintTabs()
end

-- The page a tab opens on with none picked on it yet: the dungeon for you, the first
-- faction, your rank.
local function FirstPage(tab)
    if tab == "dungeons" then return J.Suggested() end
    if tab == "pvp" then return J.RANK end
    return Factions.First(tab) or J.Suggested()
end

-------------------------------------------------------------------------------
--  Showing a dungeon, and searching
-------------------------------------------------------------------------------
local shownQuery = ""         -- the search on the page ("" for a dungeon)
local searchQueued = false
local clearing = false        -- the window is emptying the search box itself

local function DrawPage(page)
    if page.rank then
        view:DrawRank()
    elseif page.tab then
        view:DrawFaction(page)
    else
        view:Draw(page)
    end
end

-- Shows the page, on its tab: a dungeon, a faction or J.RANK. The list is painted when the
-- view has drawn (Drawn).
local function Select(page)
    local tab = TabOf(page)
    if tab ~= shownTab then ShowTab(tab) end
    selected = page
    picked[tab] = page
    if search:GetText() ~= "" then
        clearing = true
        search:SetText("")
        clearing = false
    end
    shownQuery = ""
    DrawPage(page)
    scroll:SetVerticalScroll(0)
end

local function TabClicked(button)
    if button.tab == shownTab then return end
    Select(picked[button.tab] or FirstPage(button.tab))
end

local function TabEnter(button)
    if button.tab ~= shownTab then button.text:SetTextColor(T.fg.r, T.fg.g, T.fg.b) end
end

local function TabLeave()
    PaintTabs()
end

-- The switch, as wide as the search under it and the list's rows (the list less its
-- scrollbar), in the house's black border like the faction switch beside the search: three
-- parts, each as wide as its words want of the width, split by hairlines. The part shown in
-- white on a faint accent fill, with the accent under it.
local function Tabs(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(SEARCH_FULL_W, TAB_H)
    ns.Solid(bar, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(bar, BORDER_RGB)
    local buttons, words = {}, 0
    for i, info in ipairs(TABS) do
        local button = CreateFrame("Button", nil, bar)
        button.tab = info.key
        button.text = ns.Font(button, TAB_SIZE, nil, T.muted)
        button.text:SetPoint("CENTER", 0, 0)
        button.text:SetText(info.label)
        button.want = math.ceil(button.text:GetStringWidth())
        words = words + button.want
        button.fill = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        button.fill:SetAllPoints()
        button.fill:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, TAB_FILL)
        button.line = ns.Solid(button, "ARTWORK", T.accent, 1)
        button.line:SetPoint("BOTTOMLEFT")
        button.line:SetPoint("BOTTOMRIGHT")
        button.line:SetHeight(TAB_LINE)
        button:SetScript("OnClick", TabClicked)
        button:SetScript("OnEnter", TabEnter)
        button:SetScript("OnLeave", TabLeave)
        buttons[i] = button
    end
    -- What the words leave is shared out evenly, so each part has the same room round its words.
    local spare, x = (SEARCH_FULL_W - words) / #buttons, 0
    for i, button in ipairs(buttons) do
        local w = i == #buttons and SEARCH_FULL_W - x or math.floor(button.want + spare + 0.5)
        button:SetSize(w, TAB_H)
        button:SetPoint("LEFT", x, 0)
        if i > 1 then
            local split = ns.Solid(bar, "BORDER", BORDER_RGB, 1)
            split:SetPoint("TOPLEFT", x, 0)
            split:SetPoint("BOTTOMLEFT", x, 0)
            split:SetWidth(1)
        end
        x = x + w
    end
    return bar, buttons
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
    if query == "" then DrawPage(selected) else view:DrawSearch(query, Select) end
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
            local by = key == "UP" and -1 or 1
            Select(shownTab == "dungeons" and List.Next(selected, by) or Factions.Next(selected, by))
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

-- A magnifier before the hint, as the addon's own settings search has, muted; the hint and
-- what you type start after it.
local SEARCH_ICON = "Interface\\AddOns\\NaowhForever\\Media\\Navigation\\search.tga"
local SEARCH_ICON_SIZE, SEARCH_ICON_LEFT = 13, 7
local SEARCH_TEXT_LEFT = SEARCH_ICON_LEFT + SEARCH_ICON_SIZE + 6   -- the icon, then a gap

local function SearchBox(parent)
    local box = ns.NewSearchBox(parent, "Search items, bosses or factions", OnSearch)
    local fill = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 1)
    fill:SetAllPoints()
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(SEARCH_ICON)
    icon:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    icon:SetPoint("LEFT", SEARCH_ICON_LEFT, 0)
    icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    box:SetTextInsets(SEARCH_TEXT_LEFT, 22, 0, 0)
    box.hint:ClearAllPoints()
    box.hint:SetPoint("LEFT", SEARCH_TEXT_LEFT, 0)
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

-- The menu: the addon's own panel under the funnel, in the window's look. Each group's title
-- in small capitals, then a row per switch: a box ticked in the accent while it is on, and its
-- name; what it does shows on hover. One that needs the BiS List is dimmed, says why on
-- hover, and does nothing until it is on. A click on a row flips it; a click anywhere else, or
-- on the funnel again, closes the menu. It listens for clicks only while it is open.
local MENU_W, MENU_PAD = 220, 12
local MENU_TITLE_H, MENU_GROUP_GAP = 16, 10   -- a group's title line, and the space before the next group
local MENU_ROW_H = 26                          -- a switch's row, its hover band
local MENU_BOX, MENU_BOX_GAP = 14, 10          -- the tick box, and the space to the name after it
local MENU_DIMMED = 0.5                        -- a switch that does nothing without the BiS List
local menu

local function PaintMenu()
    local y = MENU_PAD
    for _, part in ipairs(menu.parts) do
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", MENU_PAD, -y)
        part:SetPoint("RIGHT", -MENU_PAD, 0)
        local option = part.option
        if not option then
            y = y + (part.gap or 0)
            part:SetPoint("TOPLEFT", MENU_PAD, -y)
            y = y + MENU_TITLE_H
        else
            local on, available = S.Get(option.key), Available(option)
            part.tick:SetShown(on and true or false)
            local edge = on and available and T.accent or BORDER_RGB
            part.edge:SetColor(edge.r, edge.g, edge.b, 1)
            part:SetAlpha(available and 1 or MENU_DIMMED)
            part:SetHeight(MENU_ROW_H)
            y = y + MENU_ROW_H
        end
    end
    menu:SetHeight(y + MENU_PAD)
end

local function RowClicked(row)
    if Available(row.option) then S.Set(row.option.key, not S.Get(row.option.key)) end
end

-- On hover: what the switch does, and why it does nothing when it needs the BiS List.
local function RowEnter(row)
    row.band:Show()
    local option = row.option
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT", MENU_PAD, 0)
    GameTooltip:SetText(option.label, 1, 1, 1)
    GameTooltip:AddLine(option.tooltip, T.muted.r, T.muted.g, T.muted.b, true)
    if not Available(option) then GameTooltip:AddLine(J.NEEDS_BIS, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, true) end
    GameTooltip:Show()
end

local function RowLeave(row)
    row.band:Hide()
    GameTooltip:Hide()
end

local function MenuRow(option)
    local row = CreateFrame("Button", nil, menu)
    row.option = option
    row.band = ns.Solid(row, "BACKGROUND", T.accent, 0.08)
    row.band:SetPoint("TOPLEFT", -MENU_PAD / 2, 0)
    row.band:SetPoint("BOTTOMRIGHT", MENU_PAD / 2, 0)
    row.band:Hide()
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(MENU_BOX, MENU_BOX)
    box:SetPoint("LEFT", 0, 0)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    row.edge = ns.Border(box, BORDER_RGB)
    row.tick = box:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(TICK)
    row.tick:SetPoint("TOPLEFT", 1, -1)
    row.tick:SetPoint("BOTTOMRIGHT", -1, 1)
    row.tick:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 1)
    local left = MENU_BOX + MENU_BOX_GAP
    row.label = ns.Font(row, 13, nil, T.fg)
    row.label:SetPoint("LEFT", left, 0)
    row.label:SetPoint("RIGHT")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(option.label)
    row:SetScript("OnClick", RowClicked)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

-- A click anywhere but on the menu or the funnel closes it.
local function MenuMouseDown()
    if not (menu:IsMouseOver() or window.filters:IsMouseOver()) then menu:Hide() end
end

local function BuildMenu()
    menu = CreateFrame("Frame", nil, window)
    menu:SetWidth(MENU_W)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:SetPoint("TOPRIGHT", window.filters, "BOTTOMRIGHT", 0, -6)
    ns.Solid(menu, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(menu, BORDER_RGB)
    menu.parts = {}
    for g, group in ipairs(GROUPS) do
        local title = ns.Font(menu, 11, nil, T.muted)
        title:SetText(group.title:upper())
        title:SetJustifyH("LEFT")
        title.gap = g > 1 and MENU_GROUP_GAP or 0
        menu.parts[#menu.parts + 1] = title
        for _, option in ipairs(group.options) do menu.parts[#menu.parts + 1] = MenuRow(option) end
    end
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    menu:SetScript("OnEvent", MenuMouseDown)
    menu:Hide()
end

local function OpenFilters()
    if not menu then BuildMenu() end
    if menu:IsShown() then
        menu:Hide()
        return
    end
    GameTooltip:Hide()
    menu:Show()
    PaintMenu()
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
    GameTooltip:SetText(TERRITORY_CODE[side.faction] .. side.faction .. "|r", 1, 1, 1)
    GameTooltip:AddLine(on and "Listed: the dungeons on " .. side.faction .. " ground, and its battleground "
        .. "factions. Click to hide them." or "Hidden. Click to list them again.", 1, 1, 1, true)
    GameTooltip:AddLine("Contested dungeons are always listed.", T.muted.r, T.muted.g, T.muted.b)
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
    dot:SetTexture(ROUND, nil, nil, "TRILINEAR")
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
    slider.thumb:SetTexture(ROUND, nil, nil, "TRILINEAR")
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
    window.tabBar:SetShown(not hidden)
    ShowLists()
    for _, part in ipairs(listCard) do part:SetShown(not hidden) end
    local cardLeft = hidden and 6 or LIST_W + PAD + 14
    local fill = contentCard[1]
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", cardLeft, -(HEADER + 6))
    fill:SetPoint("BOTTOMRIGHT", -4, FOOTER + 6)
    local left = cardLeft + CONTENT_INSET
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", left, -(HEADER + PAD + 4))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - 4, FOOTER + PAD)
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
-- The footer's words sit this far in from the content card's right edge, as its contents do.
local FOOTER_INSET = 8
local FOOTER_LOGO = 14   -- the Naowh N on the footer's left, at its words' height

-- The footer's left: the Naowh N, then "Naowh" in white and "Forever" in the accent, as the
-- options window and the item tooltips write it. A click opens the options, as the title's
-- logo does; it brightens under the mouse.
local function BrandEnter(brand)
    brand.text:SetAlpha(1)
    brand.icon:SetAlpha(1)
    GameTooltip:SetOwner(brand, "ANCHOR_TOP")
    GameTooltip:SetText("Naowh Forever", 1, 1, 1)
    GameTooltip:AddLine("Click to open its options.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function BrandLeave(brand)
    brand.text:SetAlpha(0.8)
    brand.icon:SetAlpha(0.8)
    GameTooltip:Hide()
end

local function FooterBrand(parent)
    local brand = CreateFrame("Button", nil, parent)
    brand.icon = brand:CreateTexture(nil, "ARTWORK")
    brand.icon:SetTexture(St.LOGO_SMALL, nil, nil, "TRILINEAR")
    brand.icon:SetSize(FOOTER_LOGO, FOOTER_LOGO)
    brand.icon:SetPoint("LEFT")
    brand.text = ns.Font(brand, 10, nil, T.fg)
    brand.text:SetPoint("LEFT", brand.icon, "RIGHT", 5, 0)
    brand.text:SetText("Naowh " .. ns.Color("accent", "Forever"))
    brand:SetSize(FOOTER_LOGO + 5 + math.ceil(brand.text:GetStringWidth()), FOOTER)
    brand:SetScript("OnClick", function() ns.OpenOptionsWindow("Dungeon Journal") end)
    brand:SetScript("OnEnter", BrandEnter)
    brand:SetScript("OnLeave", BrandLeave)
    BrandLeave(brand)
    return brand
end

local function DataEnter(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:SetText("Game data: WoW Forever " .. J.DATA_BUILD, 1, 1, 1)
    if J.DATA_DATE ~= "" then
        GameTooltip:AddLine("That build came out on " .. J.DATA_DATE .. ".", T.muted.r, T.muted.g, T.muted.b)
    end
    GameTooltip:AddLine("Faction rewards, their standings and prices, and the boss fights the kill counts follow, "
        .. "are read from it. A daily check moves them on to each new build.", T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function LogoLeave(logo)
    logo.icon:SetAlpha(LOGO_REST)
    GameTooltip:Hide()
end

-- Every draw repaints the list too: a BiS change from an item's menu moves its counts.
local function Drawn()
    if shownTab == "dungeons" then List.Paint(selected) else Factions.Paint(selected) end
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
    listCard = backdrop:Card(6, HEADER + 6, WIDTH - LIST_W - PAD - 6, FOOTER + 6)
    contentCard = backdrop:Card(LIST_W + PAD + 14, HEADER + 6, 4, FOOTER + 6)
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
    -- The footer, under the cards: Naowh Forever on the left, level with the list card's edge;
    -- on the right, level with the content card's, the game build the data is read from and
    -- its date, small and faint.
    FooterBrand(window):SetPoint("BOTTOMLEFT", 6 + FOOTER_INSET, 3)
    if J.DATA_BUILD then
        local data = CreateFrame("Frame", nil, window)
        data.text = ns.Font(data, 10, nil, T.muted)
        data.text:SetPoint("RIGHT")
        data.text:SetText("Game data: build " .. J.DATA_BUILD .. (J.DATA_DATE ~= "" and PLACE_DOT .. J.DATA_DATE or ""))
        data:SetSize(math.ceil(data.text:GetStringWidth()), FOOTER)
        data:SetPoint("BOTTOMRIGHT", -(4 + FOOTER_INSET), 3)
        data:EnableMouse(true)
        data:SetScript("OnEnter", DataEnter)
        data:SetScript("OnLeave", GameTooltip_Hide)
    end
    local subtitle = ns.Font(window, 11, nil, T.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("Dungeons and raids, reputation and PvP: what drops, your quests, and more.")
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
    -- The switch, then the search, then the list, down the left.
    window.tabBar, window.tabs = Tabs(window)
    window.tabBar:SetPoint("TOPLEFT", PAD, -(HEADER + PAD))
    local below = HEADER + PAD + TAB_H + TAB_GAP
    search:SetSize(SEARCH_W, SEARCH_H)
    search:SetPoint("TOPLEFT", PAD, -below)
    window.factionSwitch, window.factions = FactionSwitch(window)
    window.factionSwitch:SetPoint("LEFT", search, "RIGHT", FACTION_GAP, 0)
    listFrame = CreateFrame("Frame", nil, window)
    listFrame:SetPoint("TOPLEFT", PAD, -(below + SEARCH_H + 4))
    listFrame:SetPoint("BOTTOMLEFT", PAD, FOOTER + PAD)
    listFrame:SetWidth(LIST_W)
    List.Build(listFrame, Select)
    factionFrame = CreateFrame("Frame", nil, window)
    factionFrame:SetPoint("TOPLEFT", listFrame)
    factionFrame:SetPoint("BOTTOMLEFT", listFrame)
    factionFrame:SetWidth(LIST_W)
    factionFrame:Hide()
    Factions.Build(factionFrame, Select)

    -- The dungeon, scrolling under the title bar; Arrange places it, with the list or without.
    scroll = ns.UI.SlimScroll(window)
    view = J.View.New(scroll)
    scroll:SetScrollChild(view)
    view.onResize = Drawn
    view.navigate = Select

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
    elseif key == "openUnreleased" then
        if shownTab ~= "dungeons" then
            Factions.Layout(shownTab)
            Factions.Paint(selected)
        end
    elseif key == "showAlliance" or key == "showHorde" then
        PaintFactions()
        List.Layout()
        if shownTab ~= "dungeons" then
            Factions.Layout(shownTab)
            Factions.Paint(selected)
        end
        if shownQuery ~= "" then view:Redraw() end
    else
        if key == "listHidden" then Arrange() end
        PaintFilters()
        if menu and menu:IsShown() then PaintMenu() end
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

-- Opens on the dungeon you are in, else the page you last looked at, else the first of the
-- tab you left it on.
-- Draws the dungeon shown again, when the window is open: for data that changed under it
-- (kills or loot forgotten from the settings page).
function ns.RedrawJournalWindow()
    if window and window:IsShown() then view:Redraw() end
    J.View.BossPanel.Refresh()
end

-- Opens the window on the dungeon given, else the one you are in, else where it was.
---@param dungeon? JournalDungeon
local awayForMap = false   -- put away by the world map opening (J.WindowAwayForMap)

function ns.OpenJournalWindow(dungeon)
    awayForMap = false   -- opened by hand: the map closing has nothing to bring back
    J.TurnOn()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    ApplyProfile()
    local here = J.Current()
    Select(dungeon or here and here[1] or selected or FirstPage(SavedTab()))
end

function ns.ToggleJournalWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenJournalWindow() end
end

-- The world map opening (M) puts the window away while it is open, and the map closing (M
-- again) brings it back as it was; the map panel (UI/MapPanel.lua) says when.

---@param mapShown boolean
function J.WindowAwayForMap(mapShown)
    if mapShown then
        if window and window:IsShown() then
            awayForMap = true
            window:Hide()
        end
    elseif awayForMap then
        awayForMap = false
        if window and S.Get("enabled") then window:Show() end
    end
end

-- A key binding of its own (Bindings.xml, Naowh Forever's section of Key Bindings): opens the
-- window, or closes it.
BINDING_NAME_NAOWHFOREVER_JOURNAL = "Open Dungeon Journal"

function NaowhForever_ToggleJournal()
    ns.ToggleJournalWindow()
end
