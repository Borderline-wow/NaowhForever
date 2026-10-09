-- The real ns.PlainText cut out of Core/Core.lua, for tests that stub the rest of
-- the Core: local PlainText = dofile("Tools/regression/plain_text.lua")(). Not a test itself.
return function(root)
    local f = assert(io.open((root or ".") .. "/Core/Core.lua", "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    local first = assert(source:find("function ns.PlainText(", 1, true))
    local last = assert(source:find("\nend\n", first, true))
    local ns = {}
    local chunk = assert(loadstring(source:sub(first, last + 4), "PlainText"))
    setfenv(chunk, { ns = ns, type = type })
    chunk()
    return ns.PlainText
end
