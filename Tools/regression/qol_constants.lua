-- Returns ns.QoLConstants as NaowhForever_QoL/Constants.lua makes it, for a test whose stub ns loads QoL files
-- one by one rather than through QoL.xml. Not a test itself (run-all.sh runs only test*.lua).
-- Run from the repo root:
--
--   ns.QoLConstants = dofile("Tools/regression/qol_constants.lua")
local ns = {}
local chunk = assert(loadfile("NaowhForever_QoL/Constants.lua"))
ns.Shared = { Style = dofile("Tools/regression/shared_style.lua") }
setfenv(chunk, { _G = { NaowhForever = ns } })
chunk()
return ns.QoLConstants
