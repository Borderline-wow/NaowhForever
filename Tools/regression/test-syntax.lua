-- Compiles every file the TOC loads without running it, following the XML files it includes
-- (a module's own load file, the libraries' embeds). luacheck accepts newer syntax the game
-- rejects (goto, //); a real Lua 5.1 does not. LuaJIT accepts goto, so use Lua 5.1:
--   lua5.1 Tools/regression/test-syntax.lua
local TocFiles = dofile("Tools/regression/toc_files.lua")
local checked, failed = 0, 0
for _, path in ipairs(TocFiles("%.lua$")) do
    local chunk, err = loadfile(path)
    checked = checked + 1
    if not chunk then
        failed = failed + 1
        print(err)
    end
end
assert(checked > 0, "no Lua files found in NaowhForever.toc")
assert(failed == 0, failed .. " of " .. checked .. " files do not compile on Lua 5.1")
print(checked .. " TOC files compile on Lua 5.1")
