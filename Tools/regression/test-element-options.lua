-- Run with Lua 5.1 from the repository root: Unlock Mode's Element Options. Every mover names
-- the options page that sets it up, that page is one the options window has, and a section
-- it opens is one that page (or a section it draws) declares with W:Feature. A wrong name
-- would open the wrong page, or none, with no error to say so.
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
    local window = Read("Core/NaowhForever_Window.lua")
    local list = window:match("local MODULES = (%b{})")
    Check(list, "MODULES found")
    local module
    for line in list:gmatch("[^\n]+") do
        local name = line:match('^%s*{ name = "([^"]+)",')
        if name and not line:find("build =", 1, true) then module = name end
        local tab, build = line:match('{ name = "([^"]+)", build = "([^"]+)"')
        if tab and module then pages[module .. "/" .. tab] = build end
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

local movers = 0
for path, s in pairs(sources) do
    local i = 1
    while true do
        local a, b = s:find("UI%.AttachMover%(", i)
        if not a then break end
        i = b + 1
        if not s:sub(a - 9, a - 1):find("function") then
            local call = Call(s, b)
            local page, feature = call:match(',%s*"([^"]+)"%s*,%s*"([^"]+)"%s*%)$')
            if not page then page = call:match(',%s*"([^"]+)"%s*%)$') end
            local where = path .. ": " .. call:sub(1, 60)
            if path:find("NaowhForever_FPS", 1, true) then
                -- The FPS readout moved to the Top Bar; this mover is never shown.
                Check(page == nil, "the retired FPS mover names no page")
            else
                movers = movers + 1
                Check(page ~= nil, "a mover names its options page: " .. where)
                Check(pages[page] ~= nil, "its page is in the options window: " .. tostring(page) .. " (" .. where .. ")")
                if feature then
                    Check(feature:sub(1, #page + 1) == page .. ":", "its section is on its page: " .. feature)
                    Check(Declares(pages[page], feature:sub(#page + 2), 1),
                        "the page declares the section: " .. feature)
                end
            end
        end
    end
end
Check(movers >= 30, "every mover was found (" .. movers .. ")")

-- The right-click itself: the menu is built only with a page, and opening it leaves Unlock Mode.
local widgets = Read("Core/NaowhForever_Widgets.lua")
Check(widgets:find('button == "RightButton" and page and not InCombatLockdown()', 1, true), "right-click needs a page")
Check(widgets:find("ns.HideRaidReminderAnchorConfig()\n    ns.OpenOptionsWindow(item.page)", 1, true),
    "Element Options leaves Unlock Mode before opening the page")

print(("test-element-options: %d checks passed"):format(checks))
