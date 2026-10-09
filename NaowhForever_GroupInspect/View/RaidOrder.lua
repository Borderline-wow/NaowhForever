-- RaidOrder.lua: who shows in Group Inspect's raid and in what order: its sorts and its filters, kept for the session (GI.UI.RaidOrder).
local ns = _G.NaowhForever
local GI = ns.GroupInspect
local UI = GI.UI

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local NO_ROLE = 4

local filters = { class = {}, role = {}, armor = {}, nf = false, bare = false }
local onFiltered

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
    local x, y = ROLE_ORDER[a.role] or NO_ROLE, ROLE_ORDER[b.role] or NO_ROLE
    if x ~= y then return x < y end
    return ByScore(a, b)
end

local Order = { SORTS = { score = ByScore, ilvl = ByIlvl, name = ByName, class = ByClass, role = ByRole },
    ByScore = ByScore }
UI.RaidOrder = Order

function Order.SortValue(rec, sort)
    if sort == "ilvl" then return rec.ilvl or -1 end
    if sort == "name" then return rec.name or "" end
    if sort == "class" then return rec.classFile or "" end
    if sort == "role" then return ROLE_ORDER[rec.role] or NO_ROLE end
    return rec.score or -1
end

function Order.FilterCount()
    local n = (filters.nf and 1 or 0) + (filters.bare and 1 or 0)
    for _ in pairs(filters.class) do n = n + 1 end
    for _ in pairs(filters.role) do n = n + 1 end
    for _ in pairs(filters.armor) do n = n + 1 end
    return n
end

function Order.OnFiltered(fn)
    onFiltered = fn
end

function Order.IsFiltered(item)
    local group = filters[item.group]
    if type(group) == "table" then return group[item.value] == true end
    return group == true
end

local function Passes(rec)
    if next(filters.class) and not filters.class[rec.classFile or ""] then return false end
    if next(filters.role) and not filters.role[rec.role or ""] then return false end
    if next(filters.armor) and not filters.armor[UI.ARMOR[rec.classFile or ""] or ""] then return false end
    if filters.nf and not rec.hasNF then return false end
    if filters.bare and UI.MissingEnchants(rec) == 0 then return false end
    return true
end

local function ToggleFilter(item)
    local group = filters[item.group]
    if type(group) == "table" then
        group[item.value] = not group[item.value] or nil
    else
        filters[item.group] = not group
    end
    onFiltered()
end

local function ClearFilters()
    wipe(filters.class)
    wipe(filters.role)
    wipe(filters.armor)
    filters.nf, filters.bare = false, false
    onFiltered()
end

UI.Passes = Passes
UI.Filters = filters
UI.ClearFilters = ClearFilters
UI.ToggleFilter = ToggleFilter
