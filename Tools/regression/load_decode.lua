-- Loads Shared/Decode.lua into a test's environment, so it finds that test's LibStub. With a
-- stand-in codec (no real deflate), standIn makes the size scan read the string's own length.
return function(env, standIn)
    local chunk = assert(loadfile("Shared/Decode.lua"))
    setfenv(chunk, env)
    local Decode = chunk()
    if standIn then Decode.InflatedSize = function(data) return type(data) == "string" and #data or nil end end
    return Decode
end
