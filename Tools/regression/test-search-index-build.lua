-- The search index the release builds (Tools/build/search_index.lua, NaowhForever_SearchIndex/SearchIndex.lua):
-- every addon file still loads against its stubs, and what it writes is Lua that holds every module's settings.
-- Run with Lua 5.1 from the repository root.
local built = dofile("Tools/build/search_index.lua")
local chunk = assert(loadstring(built, "SearchIndex.lua"))
local ns = {}
setfenv(chunk, { _G = { NaowhForever = ns } })
chunk()

local entries, pages = 0, 0
for _, list in pairs(ns.SEARCH_INDEX) do
    pages = pages + 1
    entries = entries + #list
end
assert(entries > 1000, "the index has every module's settings, " .. entries .. " found")
assert(not built:find("[\128-\255]"), "the index is ASCII")
assert(not built:find("[^\r]\n"), "the index has CRLF line endings")
print(("PASS search index build: %d entries on %d pages"):format(entries, pages))
