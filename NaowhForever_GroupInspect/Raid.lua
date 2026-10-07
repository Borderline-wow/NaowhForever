-------------------------------------------------------------------------------
--  Raid.lua -- Group Inspect's raid of six to forty (GI.UI.RaidList): a compact row per member
--  on the shared row engine (pooled, reused on every draw), a band of their class's color at
--  its left, their class icon, name, Naowh Forever's mark, role, Naowh Score and item level,
--  then one view of three (Gear, a strip of their items with the game's tooltip; Talents; Stats),
--  how their inspect stands and a button to inspect them again. The toolbar (GI.UI.RaidBar)
--  switches the view, sorts and filters (class, role, armor, runs Naowh Forever, missing
--  enchants; for this session). A member's change repaints only their row, or sorts again when
--  their place changes. Used by the window and the settings preview.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local GI = ns.GroupInspect
local UI = GI.UI
local Shared = ns.Shared
local Parts, View, Items = Shared.Parts, Shared.View, Shared.Items

local St = UI.Style
local ROW_H, BAND_W, COLUMNS_H = St.ROW_H, St.BAND_H, St.COLUMNS_H
local STRIP_SLOT, STRIP_GAP = St.STRIP_SLOT, St.STRIP_GAP
local GEAR_SLOTS = Items.GEAR_SLOTS
local STATS = UI.STATS
local WAITING = UI.WAITING

local CLASS_X, NAME_X, NAME_W = 12, 40, 138
local NF_X, ROLE_X = 184, 212
local FIRST_WEAPON = 15
local SCORE_RIGHT, ILVL_RIGHT, VIEW_X = 290, 340, 364
local TREE_W, POINTS_X, TROLE_X = 140, 512, 580
local STATE_RIGHT, STATE_W, REFRESH_RIGHT = 32, 100, 8
local SCORE_SIZE, STAT_SIZE, STAT_GAP = 14, 11, 12
local BAR_SPACE, VIEWS_W = 16, 210
local NO_EVENTS = {}

local VIEWS = {
    { key = "gear", label = "Gear", tip = "Everyone's gear, with its item level and enchants on hover." },
    { key = "talents", label = "Talents", tip = "Everyone's talent points per tree." },
    { key = "stats", label = "Stats", tip = "Everyone's key stats." },
}
local VIEW_TITLES = { gear = "GEAR", talents = "TALENTS", stats = "STATS" }
local SORTS_LIST = { { "score", "Naowh Score" }, { "ilvl", "Item Level" }, { "name", "Name" },
    { "class", "Class" }, { "role", "Role" } }
local SORT_LABELS = {}
for _, sort in ipairs(SORTS_LIST) do SORT_LABELS[sort[1]] = "Sort: " .. sort[2] end
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local STATS_TIP = "White: exact, from their Naowh Forever. Grey: added up from their gear."
local NO_MATCH = "No one in the raid matches your filters."
local REFRESH_TIP = "Inspect them again"
local FILTERS, FILTERS_N = "Filters", "Filters (%d)"

local filters = { class = {}, role = {}, armor = {}, nf = false, bare = false }
local FILTER_GROUPS = {
    { title = "Class", items = {} },
    { title = "Role", items = { { group = "role", value = "TANK", label = "Tank" },
        { group = "role", value = "HEALER", label = "Healer" }, { group = "role", value = "DAMAGER", label = "Damage" } } },
    { title = "Armor", items = { { group = "armor", value = "Cloth", label = "Cloth" },
        { group = "armor", value = "Leather", label = "Leather" }, { group = "armor", value = "Mail", label = "Mail" },
        { group = "armor", value = "Plate", label = "Plate" } } },
}
for _, class in ipairs(UI.CLASS_ORDER) do
    local items = FILTER_GROUPS[1].items
    items[#items + 1] = { group = "class", value = class, label = UI.CLASS_NAMES[class] }
end
local NF_ITEM = { group = "nf", label = "Runs Naowh Forever" }
local BARE_ITEM = { group = "bare", label = "Missing enchants" }

local bar, windowList

local function ByName(a, b)
    local x, y = a.name or "", b.name or ""
    if x ~= y then return x < y end
    return (a.guid or "") < (b.guid or "")
end

local function ByScore(a, b)
    local x, y = a.score or -1, b.score or -1
    if x ~= y then return x > y end
    return ByName(a, b)
end

local function ByIlvl(a, b)
    local x, y = a.ilvl or -1, b.ilvl or -1
    if x ~= y then return x > y end
    return ByScore(a, b)
end

local function ByClass(a, b)
    local x, y = a.classFile or "", b.classFile or ""
    if x ~= y then return x < y end
    return ByScore(a, b)
end

local function ByRole(a, b)
    local x, y = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
    if x ~= y then return x < y end
    return ByScore(a, b)
end

local SORTS = { score = ByScore, ilvl = ByIlvl, name = ByName, class = ByClass, role = ByRole }

local function SortValue(rec, sort)
    if sort == "ilvl" then return rec.ilvl or -1 end
    if sort == "name" then return rec.name or "" end
    if sort == "class" then return rec.classFile or "" end
    if sort == "role" then return ROLE_ORDER[rec.role] or 4 end
    return rec.score or -1
end

local function FilterCount()
    local n = (filters.nf and 1 or 0) + (filters.bare and 1 or 0)
    for _ in pairs(filters.class) do n = n + 1 end
    for _ in pairs(filters.role) do n = n + 1 end
    for _ in pairs(filters.armor) do n = n + 1 end
    return n
end

local function Passes(rec)
    if next(filters.class) and not filters.class[rec.classFile or ""] then return false end
    if next(filters.role) and not filters.role[rec.role or ""] then return false end
    if next(filters.armor) and not filters.armor[UI.ARMOR[rec.classFile or ""] or ""] then return false end
    if filters.nf and not rec.hasNF then return false end
    if filters.bare and UI.MissingEnchants(rec) == 0 then return false end
    return true
end
UI.Passes = Passes

local function RowEnter(row) row.hover:Show() end
local function RowLeave(row) row.hover:Hide() end

local function RowRefresh(button)
    local guid = button:GetParent().guid
    if guid then GI.Refresh(guid) end
end

local function NewRow(view)
    local row = CreateFrame("Frame", nil, view)
    Parts.RowBands(row, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row.band = ns.Solid(row, "ARTWORK", T.fg, 1)
    row.band:SetPoint("TOPLEFT")
    row.band:SetPoint("BOTTOMLEFT")
    row.band:SetWidth(BAND_W)
    row.class = UI.ClassIcon(row, St.ROW_CLASS_ICON)
    row.class:SetPoint("LEFT", CLASS_X, 0)
    row.name = ns.Font(row, St.ROW_NAME_SIZE, nil, T.fg)
    row.name:SetPoint("LEFT", NAME_X, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.nameHit = UI.NameHit(row, row)
    row.nameHit:SetPoint("LEFT", NAME_X, 0)
    row.nameHit:SetSize(NAME_W, ROW_H)
    row.badge = UI.Badge(row, row)
    row.badge:SetFrameLevel(row.nameHit:GetFrameLevel() + 2)
    row.nf = UI.NFPill(row, row)
    row.nf:SetPoint("LEFT", NF_X, 0)
    row.role = UI.RoleIcon(row, St.ROW_ROLE_ICON)
    row.role:SetPoint("LEFT", ROLE_X, 0)
    row.score = ns.Font(row, SCORE_SIZE, nil, T.fg)
    row.score:SetPoint("RIGHT", row, "LEFT", SCORE_RIGHT, 0)
    row.ilvl = ns.Font(row, St.ROW_NAME_SIZE, nil, T.fg)
    row.ilvl:SetPoint("RIGHT", row, "LEFT", ILVL_RIGHT, 0)

    row.gear = CreateFrame("Frame", nil, row)
    row.gear:SetPoint("LEFT", VIEW_X, 0)
    row.gear:SetSize(#GEAR_SLOTS * (STRIP_SLOT + STRIP_GAP) + St.STRIP_WEAPON_GAP, STRIP_SLOT)
    row.slots = {}
    for i, entry in ipairs(GEAR_SLOTS) do
        local icon = UI.GearIcon(row.gear, STRIP_SLOT, entry[1], row, false)
        icon:SetPoint("LEFT", (i - 1) * (STRIP_SLOT + STRIP_GAP) + (i >= FIRST_WEAPON and St.STRIP_WEAPON_GAP or 0), 0)
        row.slots[i] = icon
    end

    row.tree = ns.Font(row, St.LINE_SIZE, nil, T.fg)
    row.tree:SetPoint("LEFT", VIEW_X, 0)
    row.tree:SetWidth(TREE_W)
    row.tree:SetJustifyH("LEFT")
    row.tree:SetWordWrap(false)
    row.points = ns.Font(row, St.LINE_SIZE, nil, T.fg)
    row.points:SetPoint("LEFT", POINTS_X, 0)
    row.trole = ns.Font(row, St.SUB_SIZE, nil, T.muted)
    row.trole:SetPoint("LEFT", TROLE_X, 0)

    row.stats = Parts.LabelRow(row, STAT_SIZE, nil, T.fg, { gap = STAT_GAP })
    row.stats:SetPoint("LEFT", VIEW_X, 0)
    row.statList = {}

    row.state = ns.Font(row, St.SUB_SIZE, nil, T.muted)
    row.state:SetPoint("RIGHT", -STATE_RIGHT, 0)
    row.state:SetWidth(STATE_W)
    row.state:SetJustifyH("RIGHT")
    row.refresh = Parts.IconButton(row, RowRefresh, St.RESET, 0, REFRESH_TIP)
    row.refresh:SetPoint("RIGHT", -REFRESH_RIGHT, 0)
    return row
end

local function PaintStrip(row, rec)
    local gear = rec.gear
    for i = 1, #GEAR_SLOTS do
        UI.PaintGear(row.slots[i], gear and gear[GEAR_SLOTS[i][1]])
    end
end

local function PaintTalents(row, rec)
    local talents = rec.talents
    row.tree:SetText(talents and talents.tree or WAITING)
    row.points:SetText(talents and UI.TalentText(talents.spent) or "")
    row.trole:SetText(talents and talents.role or UI.ROLE_WORDS[rec.role] or "")
end

local function PaintStats(row, rec)
    local stats, list, n = rec.stats, row.statList, 0
    if stats then
        for i = 1, #STATS do
            local stat = STATS[i]
            local value = stats[stat.key]
            if type(value) == "number" and value ~= 0 then
                n = n + 1
                list[n] = UI.StatInline(stat, value)
            end
        end
    else
        n = 1
        list[1] = WAITING
    end
    row.stats:SetLabels(list, n)
    row.stats:Pack()
    row.stats:SetColor((rec.statsShared or rec.state == "self") and T.fg or T.muted)
end

local function SetRow(row, rec, index)
    local view = row:GetParent()
    local mode = view.mode
    row.guid, row.index = rec.guid, index
    row.sortValue = SortValue(rec, view.sort)
    row.stripe:SetShown(index % 2 == 0)
    local color = UI.ClassColor(rec.classFile)
    row.band:SetColorTexture(color.r, color.g, color.b, 1)
    UI.PaintClass(row.class, rec.classFile)
    local badged = UI.PaintBadge(row.badge, rec.guid)
    local room = NAME_W - (badged and St.BADGE + St.BADGE_GAP or 0)
    local width = UI.FitName(row.name, rec.name or WAITING, room, St.ROW_NAME_SIZE, St.ROW_NAME_MIN)
    row.name:SetTextColor(color.r, color.g, color.b)
    row.badge:ClearAllPoints()
    row.badge:SetPoint("LEFT", row.name, "LEFT", width + St.BADGE_GAP, 0)
    row.nf:SetShown(rec.hasNF == true)
    UI.PaintNFPill(row.nf, rec)
    UI.PaintRole(row.role, rec.role)
    row.score:SetText(UI.ScoreText(rec.score, rec.level))
    row.ilvl:SetText(rec.ilvl and tostring(math.floor(rec.ilvl + 0.5)) or WAITING)
    local gear, talents, stats = mode == "gear", mode == "talents", mode == "stats"
    row.gear:SetShown(gear)
    row.tree:SetShown(talents)
    row.points:SetShown(talents)
    row.trole:SetShown(talents)
    row.stats:SetShown(stats)
    if gear then
        PaintStrip(row, rec)
    elseif talents then
        PaintTalents(row, rec)
    else
        PaintStats(row, rec)
    end
    row.state:SetText(UI.StateText(rec.state))
    row:SetAlpha(UI.Away(rec) and St.AWAY_ALPHA or 1)
    return ROW_H
end

local kinds = View.NewKinds()
kinds.member = { New = NewRow, Set = SetRow }

local function PaintBar()
    if not bar then return end
    Parts.PaintTabs(bar.views, S.Get("groupInspectView"))
    Parts.SetLink(bar.sort, SORT_LABELS[S.Get("groupInspectSort")] or SORT_LABELS.score)
    local n = FilterCount()
    local button = bar.filter
    button.label:SetText(n > 0 and FILTERS_N:format(n) or FILTERS)
    button:SetWidth(St.BAR_ICON + 8 + math.ceil(button.label:GetStringWidth()))
    Parts.LightBarIcon(button, n > 0)
end

local function DrawRows(view)
    local mode = S.Get("groupInspectView")
    if not VIEW_TITLES[mode] then mode = "gear" end
    view.mode, view.sort = mode, S.Get("groupInspectSort")
    local order, members, n = view.order, GI.Members(), 0
    for i = 1, #members do
        local rec = members[i]
        if view.unfiltered or Passes(rec) then
            n = n + 1
            order[n] = rec
        end
    end
    for i = #order, n + 1, -1 do order[i] = nil end
    table.sort(order, SORTS[view.sort] or ByScore)
    view:Clear()
    for i = 1, n do view:Add("member", order[i], i) end
    if n == 0 and #members > 0 then view:Note(NO_MATCH) end
    view:Fit(NO_EVENTS)
    for i = 1, n do order[i] = nil end
    local header = view.header
    header.title:SetText(VIEW_TITLES[mode])
    header.tip:SetShown(mode == "stats")
    if not view.unfiltered then PaintBar() end
end

local function IsGuid(row, guid)
    return row.guid == guid
end

local function Draw(list)
    list.view:Redraw()
end

local function PaintGuid(list, guid)
    local view = list.view
    local rec = GI.Member(guid)
    local row = view:Find("member", IsGuid, guid)
    if not rec then
        if row then view:QueueRedraw() end
        return
    end
    local shows = view.unfiltered or Passes(rec)
    if not row then
        if shows then view:QueueRedraw() end
        return
    end
    if not shows or SortValue(rec, view.sort) ~= row.sortValue then view:QueueRedraw() end
    SetRow(row, rec, row.index)
end

local function TipEnter(frame)
    if GameTooltip:IsForbidden() or not Parts.Tip(frame, "ANCHOR_TOP") then return end
    GameTooltip:SetText(STATS_TIP, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function Header(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(UI.LIST_W, COLUMNS_H)
    UI.Kicker(header, "NAME"):SetPoint("LEFT", NAME_X, 0)
    UI.Kicker(header, "SCORE"):SetPoint("RIGHT", header, "LEFT", SCORE_RIGHT, 0)
    UI.Kicker(header, "ILVL"):SetPoint("RIGHT", header, "LEFT", ILVL_RIGHT, 0)
    UI.Kicker(header, "STATUS"):SetPoint("RIGHT", -STATE_RIGHT, 0)
    header.title = UI.Kicker(header, "")
    header.title:SetPoint("LEFT", VIEW_X, 0)
    header.tip = CreateFrame("Frame", nil, header)
    header.tip:SetPoint("LEFT", VIEW_X, 0)
    header.tip:SetSize(TREE_W, COLUMNS_H)
    header.tip:EnableMouse(true)
    header.tip:SetScript("OnEnter", TipEnter)
    header.tip:SetScript("OnLeave", GameTooltip_Hide)
    header.tip:Hide()
    return header
end

function UI.RaidList(parent, scroll)
    local list = { Draw = Draw, PaintGuid = PaintGuid }
    list.header = Header(parent)
    local view = View.New(scroll or parent, kinds, { Redraw = DrawRows })
    view:SetWidth(UI.LIST_W)
    view.order, view.header = {}, list.header
    list.view = view
    if scroll then windowList = list end
    return list
end

local function Redraw()
    if windowList then windowList:Draw() end
end

local function IsSort(key)
    return S.Get("groupInspectSort") == key
end

local function SetSort(key)
    S.Set("groupInspectSort", key)
end

local function SortMenu(_, root)
    root:CreateTitle("Sort by")
    for _, sort in ipairs(SORTS_LIST) do root:CreateRadio(sort[2], IsSort, SetSort, sort[1]) end
end

local function SortClicked(link)
    MenuUtil.CreateContextMenu(link, SortMenu)
end

local function IsFiltered(item)
    local group = filters[item.group]
    if type(group) == "table" then return group[item.value] == true end
    return group == true
end

local function ToggleFilter(item)
    local group = filters[item.group]
    if type(group) == "table" then
        group[item.value] = not group[item.value] or nil
    else
        filters[item.group] = not group
    end
    Redraw()
end

local function ClearFilters()
    wipe(filters.class)
    wipe(filters.role)
    wipe(filters.armor)
    filters.nf, filters.bare = false, false
    Redraw()
end

local function FilterMenu(_, root)
    for _, group in ipairs(FILTER_GROUPS) do
        root:CreateTitle(group.title)
        for _, item in ipairs(group.items) do root:CreateCheckbox(item.label, IsFiltered, ToggleFilter, item) end
        root:CreateDivider()
    end
    root:CreateCheckbox(NF_ITEM.label, IsFiltered, ToggleFilter, NF_ITEM)
    root:CreateCheckbox(BARE_ITEM.label, IsFiltered, ToggleFilter, BARE_ITEM)
    if FilterCount() > 0 then
        root:CreateDivider()
        root:CreateButton("Clear filters", ClearFilters)
    end
end

local function FilterClicked(button)
    MenuUtil.CreateContextMenu(button, FilterMenu)
end

local function PickView(key)
    S.Set("groupInspectView", key)
end

function UI.RaidBar(parent)
    bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(VIEWS_W + 2 * BAR_SPACE + 240, St.TAB_H)
    bar.filter = Parts.BarButton(bar, St.FUNNEL, "Filters", "Shows only part of the raid.", FilterClicked, FILTERS)
    bar.filter:SetPoint("RIGHT")
    bar.sort = Parts.Link(bar, SortClicked, true)
    bar.sort:SetPoint("RIGHT", bar.filter, "LEFT", -BAR_SPACE, 0)
    bar.views = Parts.Tabs(bar, VIEWS_W, VIEWS, PickView)
    bar.views:SetPoint("RIGHT", bar.sort, "LEFT", -BAR_SPACE, 0)
    PaintBar()
    return bar
end

UI.Filters = filters
UI.ClearFilters = ClearFilters
UI.ToggleFilter = ToggleFilter
