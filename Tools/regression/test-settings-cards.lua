-- Run with Lua 5.1 from the repository root: every settings card any file declares
-- (Settings.Page(...):Card({...})), read from the source. Each card has an id, a name and its
-- help; its labels are its own; "Colour", never "Color"; and every key it shows has a default in
-- some module's settings (UI.ModuleSettings), Smart Reminders' own default tables, or is one
-- whose unset value means "follow automatically".
local TocFiles = dofile("Tools/regression/toc_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end

local function Block(s, open)
    local depth, i, quote = 0, open, nil
    while i <= #s do
        local c = s:sub(i, i)
        if quote then
            if c == "\\" then i = i + 1 elseif c == quote then quote = nil end
        elseif c == "-" and s:sub(i + 1, i + 1) == "-" then
            i = (s:find("\n", i, true) or #s) - 1
        elseif c == '"' or c == "'" then
            quote = c
        elseif c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then return s:sub(open, i) end
        end
        i = i + 1
    end
end

local DEFAULT_TABLES = { "UI%.ModuleSettings%(%s*\"[^\"]+\"%s*,%s*{", "DEFAULTS%s*=%s*{", "SizeDefaults%s*=%s*{" }
local AUTOMATIC = { bossSource = true }

local sources, defaults = {}, {}
for key in pairs(AUTOMATIC) do defaults[key] = true end
for _, path in ipairs(TocFiles()) do
    if path:find("%.lua$") then
        local s = Read(path)
        sources[path] = s
        for _, pattern in ipairs(DEFAULT_TABLES) do
            local at = 1
            while true do
                local a, b = s:find(pattern, at)
                if not a then break end
                local body = Block(s, b) or ""
                for key in body:gmatch("[%s,{]([%a_][%w_]*)%s*=") do defaults[key] = true end
                at = b + 1
            end
        end
    end
end

local cards = 0
for path, s in pairs(sources) do
    local at = 1
    while true do
        local a, b = s:find(":Card%(%s*{", at)
        if not a then break end
        local body = Block(s, b) or ""
        at = b + 1
        cards = cards + 1
        local name = body:match('\n%s*id = "[^"]+", name = "([^"]+)"') or body:match('name = "([^"]+)"') or "?"
        local where = path .. " > " .. name
        check(where .. " has an id", body:find('id = "', 1, true) ~= nil)
        check(where .. " has its help", body:find("help = ", 1, true) ~= nil)
        check(where .. ": Colour, not Color", not body:gsub('key = "[^"]*"', ""):gsub("%a+Color", "")
            :gsub('needs = %b{}', ""):gsub('needs = "[^"]*"', ""):find("Color", 1, true))
        local labels = {}
        for label in body:gmatch('label = "([^"]+)"') do
            check(where .. ": the label " .. label .. " is its own on the card", not labels[label])
            labels[label] = true
        end
        for key in body:gmatch('key = "([%a_][%w_]*)"') do
            check(where .. ": " .. key .. " has a default", defaults[key] ~= nil)
        end
    end
end
check("the cards were found (" .. cards .. ")", cards >= 35)

print(("test-settings-cards: %d checks passed (%d cards)"):format(checks, cards))
