-- The "what is coming" line on the alert. The boss mod names its own bars for what an
-- ability does -- "Frontal", "Debuffs", "Boss Buff" -- and hands that name over as ordinary
-- text beside the timer. Nothing here is a secret value: the client is never asked what is
-- being cast, because it will not say. The label is the one the schedule already carried.
local f = assert(io.open(arg[1] or "NaowhUI_SmartReminders.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local function Fixture()
    local e = { db = {}, drawn = {} }
    local env = {
        TRDB = function() return e.db end,
        frame = {
            incoming = {
                SetText = function(_, v) e.drawn.text = v end,
                Show = function() e.drawn.shown = true end,
                Hide = function() e.drawn.hidden = true end,
            },
        },
    }
    setmetatable(env, { __index = _G })
    local chunk = assert(loadstring("local ns = ...; "
        .. Slice("function ns.ShowIncomingLabel(", "-- The one plain answer in the set")))
    setfenv(chunk, env)
    e.ns = {}
    chunk(e.ns)
    e.env = env
    return e
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("the bar's own name goes up when it is asked for", function()
    local e = Fixture()
    e.db.showIncoming = true
    e.ns.ShowIncomingLabel("Frontal (1)")
    assert(e.drawn.text == "Frontal (1)" and e.drawn.shown)
end)

Case("off until asked for", function()
    local e = Fixture()
    e.ns.ShowIncomingLabel("Frontal (1)")
    assert(e.drawn.text == nil and e.drawn.hidden,
        "it is a second line on an alert people have arranged around")
end)

Case("a callout with no bar behind it shows nothing rather than an empty line", function()
    -- An authored reminder or a test fire has no boss-mod bar, so there is no name to give.
    local e = Fixture()
    e.db.showIncoming = true
    e.ns.ShowIncomingLabel(nil)
    assert(e.drawn.text == nil and e.drawn.hidden)

    e = Fixture(); e.db.showIncoming = true
    e.ns.ShowIncomingLabel("")
    assert(e.drawn.text == nil and e.drawn.hidden)
end)

Case("a label that is not text is refused rather than passed to SetText", function()
    local e = Fixture()
    e.db.showIncoming = true
    e.ns.ShowIncomingLabel(1296220)
    assert(e.drawn.text == nil and e.drawn.hidden)
end)

Case("no alert built yet is not an error", function()
    local e = Fixture()
    e.db.showIncoming = true
    e.env.frame = nil
    e.ns.ShowIncomingLabel("Frontal (1)")
    assert(e.drawn.text == nil)
end)

print(count .. " incoming label regressions passed")
