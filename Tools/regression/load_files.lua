-- Runs addon files in order in one environment, as the game would load them: the tests' way to
-- load a module's real files against stubs. Not a test itself (run-all.sh runs only
-- test*.lua). Run from the repo root.
--
--   local Load = dofile("Tools/regression/load_files.lua")
--   Load({ "Shared/Shared.lua", "BiS/BiS.lua" }, env)
return function(files, env)
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk()
    end
    return env
end
