-- Returns ns.Shared.Style as Shared/Style.lua makes it, for a test whose stub ns builds its own
-- ns.Shared rather than loading Shared.xml. Not a test itself (run-all.sh runs only test*.lua).
-- Run from the repo root:
--
--   Shared = { Style = dofile("Tools/regression/shared_style.lua"), ... }
local shared = {}
local chunk = assert(loadfile("Shared/Style.lua"))
setfenv(chunk, { _G = { NaowhForever = { Shared = shared } } })
chunk()
return shared.Style
