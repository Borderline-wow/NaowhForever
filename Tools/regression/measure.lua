-- Times fn and counts the garbage it makes, over 200 runs after warming up (after the
-- collection, so what the collector shrinks has grown back), and checks both
-- against a budget: under budget ms and under 0.01 KB a run. Not a test itself (run-all.sh
-- runs only test*.lua). Run from the repo root.
--
--   local Measure = dofile("Tools/regression/measure.lua")(check)
--   Measure("the list redrawn", 2, function() view:Redraw() end)
local RUNS, WARM = 200, 10

return function(check)
    return function(label, budget, fn)
        collectgarbage("collect")
        collectgarbage("stop")
        for _ = 1, WARM do fn() end
        local before, start = collectgarbage("count"), os.clock()
        for _ = 1, RUNS do fn() end
        local ms = (os.clock() - start) * 1000 / RUNS
        local kb = (collectgarbage("count") - before) / RUNS
        collectgarbage("restart")
        print(("  %s: %.3f ms, %.3f KB"):format(label, ms, kb))
        check(label .. " takes under " .. budget .. " ms", ms < budget)
        check(label .. " makes no garbage", kb < 0.01)
    end
end
