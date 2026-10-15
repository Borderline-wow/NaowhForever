-- The generated search index (NaowhForever_SearchIndex/SearchIndex.lua) matches what the module pages
-- declare now, so a turned-off module is searched as it is. Needs Libs/. Run with Lua 5.1 from the
-- repository root.
local built = dofile("Tools/build/search_index.lua")
local f = assert(io.open("NaowhForever_SearchIndex/SearchIndex.lua", "rb"))
local saved = f:read("*a")
f:close()

local function Counts(text)
    local counts, page = {}, nil
    for line in text:gmatch("[^\n]*\n") do
        local key = line:match('^    %["(.-)"%] = {')
        if key then
            page = key
            counts[page] = 0
        elseif page and line:find("^        {") then
            counts[page] = counts[page] + 1
        end
    end
    return counts
end

if saved ~= built then
    local before, after, differs = Counts(saved), Counts(built), {}
    for page, n in pairs(before) do
        if after[page] ~= n then differs[#differs + 1] = ("%s %d -> %s"):format(page, n, tostring(after[page])) end
    end
    for page, n in pairs(after) do
        if not before[page] then differs[#differs + 1] = ("%s new, %d"):format(page, n) end
    end
    table.sort(differs)
    print("NaowhForever_SearchIndex/SearchIndex.lua is out of date: run lua5.1 Tools/build/search_index.lua")
    print("entries per page, saved -> built: " .. (differs[1] and table.concat(differs, "; ") or "same counts"))
    os.exit(1)
end
local entries = select(2, built:gsub("\n        {", ""))
assert(entries > 1000, "the index has every module's settings, " .. entries .. " found")
print("PASS search index current: " .. entries .. " entries")
