-- Run with Lua 5.1 from the repository root: Unlock Mode's Element Options. Every mover names
-- the options page that sets it up, that page is one the options window has, and a section
-- it names is one that page declares.
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

-- Every addon file's source, and the body of each ns.Build... function.
local sources, bodies = {}, {}
for _, path in ipairs(TocFiles()) do
    if path:find("%.lua$") then
        local s = Read(path)
        sources[path] = s
        for name, body in s:gmatch("\nfunction ns%.(Build[%w_]+)%(.-\n(.-)\nend\n") do bodies[name] = body end
    end
end

local Eval

-- Whether one file declares the page (by literal or constant) and a card with that id.
local function DeclaresCard(page, id)
    for path, s in pairs(sources) do
        if s:find('id = "' .. id .. '"', 1, true) then
            for expr in s:gmatch("Settings%.Page%(([^,)]+)") do
                if Eval(path, s, expr, 0) == page then return true end
            end
        end
    end
    return false
end

-- Whether a page's builder, or a section builder it calls, declares the feature.
local function Declares(build, text, depth)
    local body = bodies[build]
    if not body then return false end
    local i = 1
    while true do
        local s, e = body:find("W:Feature%(", i)
        if not s then break end
        local call = Call(body, e) or ""
        if call:find('"' .. text .. '"', 1, true) then return true end
        i = e + 1
    end
    if depth > 0 then
        for inner in body:gmatch("ns%.(Build[%w_]+)%(") do
            if inner ~= build and Declares(inner, text, depth - 1) then return true end
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
        local a, b = s:find("UI%.AttachMover%(", i)
        if not a then break end
        i = b + 1
        if not s:sub(a - 9, a - 1):find("function") then
            -- A trailing true (it keeps its own screen spot) is not part of where its options are.
            local call = Call(s, b):gsub(",%s*true%s*%)$", ")")
            local args = Split(call:sub(2, -2))
            local page, feature = Eval(path, s, args[#args - 1], 0), Eval(path, s, args[#args], 0)
            if not (page and feature) then page, feature = feature, nil end
            local where = path .. ": " .. call:sub(1, 60)
            movers = movers + 1
            Check(page ~= nil, "a mover names its options page: " .. where)
            Check(pages[page] ~= nil, "its page is in the options window: " .. tostring(page) .. " (" .. where .. ")")
            if feature then
                Check(feature:sub(1, #page + 1) == page .. ":", "its section is on its page: " .. feature)
                local id = feature:sub(#page + 2)
                if pages[page] == false then
                    Check(DeclaresCard(page, id), "a card on the declared page: " .. feature)
                else
                    Check(Declares(pages[page], id, 1), "the page declares the section: " .. feature)
                end
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
