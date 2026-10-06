-- Every file the TOCs load, in load order, following XML includes: the Lua twin of
-- Tools/hooks/toc_files.py, for the tests. A module can load through its own XML file
-- (NaowhForever_DungeonJournal/DungeonJournal.xml) instead of listing each file in the TOC; this walks
-- the TOC and expands each XML's <Script file> and <Include file> entries, recursively. As
-- the game does, a path in an XML is looked up next to that XML first, then from the root.
--
--   local TocFiles = dofile("Tools/regression/toc_files.lua")
--   for _, path in ipairs(TocFiles()) do ... end      -- every file, XML files included
--   TocFiles("%.lua$")                                  -- only the paths that match
--
-- Not a test itself: run-all.sh runs only test*.lua. Run from the repo root.
local function Exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

local function Dir(path)
    return path:match("^(.*)/[^/]*$") or ""
end

-- "a/b/../c" -> "a/c", so paths compare equal however an XML spelled them.
local function Normalize(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

local function Resolve(xml, entry)
    entry = entry:gsub("\\", "/")
    local beside = Normalize(Dir(xml) .. "/" .. entry)
    if Exists(beside) then return beside end
    return Normalize(entry)
end

local Expand

local function ExpandXml(path, out, seen)
    if seen[path] or not Exists(path) then return end
    seen[path] = true
    local f = io.open(path, "rb")
    local text = f:read("*a"):gsub("<!%-%-.-%-%->", "")
    f:close()
    for entry in text:gmatch("<%a+%s+file%s*=%s*[\"']([^\"']+)[\"']") do
        Expand(Resolve(path, entry), out, seen)
    end
end

function Expand(path, out, seen)
    out[#out + 1] = path
    if path:lower():find("%.xml$") then ExpandXml(path, out, seen) end
end

-- NaowhForever.toc, then each module addon .pkgmeta moves out of NaowhForever/, in the order it
-- lists them. A module's TOC paths are relative to its own folder.
local function Tocs()
    local tocs = { { dir = "", toc = "NaowhForever.toc" } }
    for line in io.lines(".pkgmeta") do
        local child = line:gsub("\r$", ""):match("^%s+NaowhForever/(%S+):")
        if child then tocs[#tocs + 1] = { dir = child .. "/", toc = child .. "/" .. child .. ".toc" } end
    end
    return tocs
end

return function(pattern, toc)
    local all, seen = {}, {}
    for _, t in ipairs(toc and { { dir = "", toc = toc } } or Tocs()) do
        for line in io.lines(t.toc) do
            line = line:gsub("\r$", "")
            if line ~= "" and not line:find("^#") then
                -- "Locales\deDE.lua [AllowLoadTextLocale deDE]": the path is the first word.
                Expand(t.dir .. line:match("^(%S+)"):gsub("\\", "/"), all, seen)
            end
        end
    end
    if not pattern then return all end
    local matching = {}
    for _, path in ipairs(all) do
        if path:find(pattern) then matching[#matching + 1] = path end
    end
    return matching
end
