-- Returns ns.MEDIA, the core's art folder, read from Core/Core.lua's own line, for a test whose
-- stub ns does not load Core.lua. Not a test itself (run-all.sh runs only test*.lua).
-- Run from the repo root:
--
--   local ns = { MEDIA = dofile("Tools/regression/core_media.lua"), ... }
local f = assert(io.open("Core/Core.lua", "rb"))
local core = f:read("*a")
f:close()
return assert(loadstring("return " .. assert(core:match("\nlocal MEDIA = (\"[^\n]-\")\r?\n"), "MEDIA")))()
