-- Run with Lua 5.1 from the repository root: Unlock Mode's Element Options. Every mover names
-- the options page that sets it up, that page is one the options window has, and a section
-- it names is a card that page declares.
local TocFiles = dofile("Tools/regression/toc_files.lua")

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

-- The text from the ( at `open` to its matching ), skipping strings.
local function Call(s, open)
    local depth, i, quote = 0, open, nil
    while i <= #s do
        local c = s:sub(i, i)
        if quote then
            if c == "\\" then i = i + 1 elseif c == quote then quote = nil end
        elseif c == '"' or c == "'" then
            quote = c
        elseif c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
            if depth == 0 then return s:sub(open, i) end
        end
        i = i + 1
    end
end

-- The options window's pages, "Module/Tab", and the function each is built by.
local pages = {}
do
    local window = Read("Core/Options/Modules.lua")
    local list = window:match("local MODULES = (%b{})")
    Check(list, "MODULES found")
    local module
    for line in list:gmatch("[^\n]+") do
        local name = line:match('^    { name = "([^"]+)",')
        if name then module = name end
        local tab, build = line:match('{ name = "([^"]+)", build = "([^"]+)"')
        if tab and module then pages[module .. "/" .. tab] = build end
        local declared = not line:find("build =", 1, true) and line:match('^%s*{ name = "([^"]+)"%s*[,}]')
        if declared and module then pages[module .. "/" .. declared] = false end
    end
end

-- Every addon file's source.
local sources = {}
for _, path in ipairs(TocFiles()) do
    if path:find("%.lua$") then sources[path] = Read(path) end
end

local Eval

-- A local the file picks at load (`local page = <test> and A or B`, or one built on it with `..`):
-- every value it can take, each checked as if it were the only one.
local function Choices(s, expr)
    if not (expr and expr:match("^[%l_][%w_]*$")) then return { expr } end
    local def = s:match("\nlocal " .. expr .. " = ([^\n]+)")
    if not def then return { expr } end
    local a, b = def:match(" and ([%u_][%u%d_]*) or ([%u_][%u%d_]*)$")
    if a then return { a, b } end
    local inner, rest = def:match("^([%l_][%w_]*)(%s*%.%..+)$")
    if not inner then return { def } end
    local out = {}
    for n, choice in ipairs(Choices(s, inner)) do out[n] = choice .. rest end
    return out
end

-- Whether one file declares the page (by literal or constant) and a card with that id.
local function DeclaresCard(page, id)
    for path, s in pairs(sources) do
        if s:find('id = "' .. id .. '"', 1, true) then
            for expr in s:gmatch("Settings%.Page%(([^,)]+)") do
                for _, choice in ipairs(Choices(s, expr)) do
                    if Eval(path, s, choice, 0) == page then return true end
                end
            end
        end
    end
    return false
end

-- The text between top-level commas, skipping strings and brackets.
local function Split(text)
    local parts, depth, quote, start = {}, 0, nil, 1
    for i = 1, #text do
        local c = text:sub(i, i)
        if quote then
            if c == quote then quote = nil end
        elseif c == '"' or c == "'" then
            quote = c
        elseif c == "(" or c == "{" then
            depth = depth + 1
        elseif c == ")" or c == "}" then
            depth = depth - 1
        elseif c == "," and depth == 0 then
            parts[#parts + 1] = text:sub(start, i - 1)
            start = i + 1
        end
    end
    parts[#parts + 1] = text:sub(start)
    for n, part in ipairs(parts) do parts[n] = part:match("^%s*(.-)%s*$") end
    return parts
end

-- A field a module's folder sets once (`PAGE = "..."`), for a mover that names `C.PAGE`.
local function FolderField(path, field)
    local folder = path:match("^[^/]+/")
    local found
    for other, s in pairs(sources) do
        if other:sub(1, #folder) == folder then
            for value in s:gmatch("\n%s+" .. field .. ' = "([^"\n]*)",') do
                if found and found ~= value then return nil end
                found = value
            end
        end
    end
    return found
end

-- A string a mover passes: a literal, a file constant, a folder field, or those joined by `..`.
function Eval(path, s, expr, depth)
    if not expr or depth > 4 then return nil end
    local out = {}
    for part in (expr .. ".."):gmatch("%s*(.-)%s*%.%.") do
        local value = part:match('^"([^"]*)"$')
        local alias, field = part:match("^([%a_][%w_]*)%.([%u_][%u%d_]*)$")
        if alias then value = FolderField(path, field) end
        if not value and part:match("^[%u_][%u%d_]*$") then
            for names, values in s:gmatch("\nlocal ([%w_, ]+) = ([^\n]+)") do
                local list, n = Split(values), 0
                for name in names:gmatch("[%w_]+") do
                    n = n + 1
                    if name == part then value = Eval(path, s, list[n], depth + 1) end
                end
                if value then break end
            end
        end
        if not value then return nil end
        out[#out + 1] = value
    end
    return table.concat(out)
end

local movers = 0
for path, s in pairs(sources) do
    local i = 1
    while true do
        -- A bar on the shared item bar is a mover too: ItemBar.Frame names its page, and the item
        -- bar only hands that on to AttachMover.
        local a, b = s:find("UI%.AttachMover%(", i)
        local fa, fb = s:find("ItemBar%.Frame%(", i)
        if fa and (not a or fa < a) then a, b = fa, fb end
        if not a then break end
        i = b + 1
        local handOn = path == "Shared/UI/ItemBar.lua" and s:sub(a, b) == "UI.AttachMover("
        local call = not handOn and not s:sub(a - 9, a - 1):find("function") and Call(s, b)
        -- A trailing true (it keeps its own screen spot) is not part of where its options are.
        local args = call and Split(call:gsub(",%s*true%s*%)$", ")"):sub(2, -2))
        local pageChoices = args and Choices(s, args[#args - 1])
        local featureChoices = args and Choices(s, args[#args])
        if call then movers = movers + 1 end
        for n = 1, call and math.max(#pageChoices, #featureChoices) or 0 do
            local page = Eval(path, s, pageChoices[n] or pageChoices[1], 0)
            local feature = Eval(path, s, featureChoices[n] or featureChoices[1], 0)
            if not (page and feature) then page, feature = feature, nil end
            local where = path .. ": " .. call:sub(1, 60)
            Check(page ~= nil, "a mover names its options page: " .. where)
            Check(pages[page] ~= nil, "its page is in the options window: " .. tostring(page) .. " (" .. where .. ")")
            if feature then
                Check(feature:sub(1, #page + 1) == page .. ":", "its section is on its page: " .. feature)
                Check(DeclaresCard(page, feature:sub(#page + 2)), "a card on the declared page: " .. feature)
            end
        end
    end
end
Check(movers >= 29, "every mover was found (" .. movers .. ")")

-- The selected element's tag has Settings only with a page; opening it leaves the HUD Editor.
local unlock = Read("Core/Unlock/Tag.lua")
Check(unlock:find("tag.settings:SetShown(item.page ~= nil)", 1, true), "Settings needs a page")
Check(unlock:find("ns.HideUnlockMode()\n    ns.OpenOptionsWindow(page)", 1, true),
    "Settings leaves the HUD Editor before opening the page")

print(("test-element-options: %d checks passed"):format(checks))
