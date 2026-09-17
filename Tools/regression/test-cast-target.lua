-- Showing who a boss is casting at. Three of the four values involved are secrets: the
-- client will let us hold them and hand them back, and raises if we look inside. The point
-- of this suite is to prove the code never looks.
--
-- The stand-in secrets below raise on concatenation, comparison, tostring, indexing and
-- length, which is what a real secret does. So any case that finishes at all is a case that
-- only passed the value through.
local f = assert(io.open(arg[1] or "NaowhUI_SmartReminders.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

local function Secret(what)
    local function raise() error("touched a secret " .. what .. " value", 0) end
    return setmetatable({}, { __concat = raise, __lt = raise, __le = raise,
        __tostring = raise, __index = raise, __len = raise, __call = raise })
end

local function Fixture()
    local e = { db = {}, drawn = {} }
    local secretName, secretClass, secretMine =
        Secret("string"), Secret("string"), Secret("bool")
    e.secretName, e.secretClass, e.secretMine = secretName, secretClass, secretMine
    e.colour = { GetRGB = function() return 0.1, 0.2, 0.3 end }

    local env = {
        TRDB = function() return e.db end,
        frame = {
            castTarget = {
                SetText = function(_, v) e.drawn.name = v end,
                SetTextColor = function(_, r, g, b) e.drawn.colour = { r, g, b } end,
                Show = function() e.drawn.nameShown = true end,
                Hide = function() e.drawn.nameHidden = true end,
            },
            youMarker = {
                SetShown = function(_, v) e.drawn.marker = v end,
                Hide = function() e.drawn.markerHidden = true end,
            },
        },
        UnitShouldDisplaySpellTargetName = function(unit)
            e.askedShow = unit
            return e.show ~= false
        end,
        UnitSpellTargetName = function() return e.name end,
        UnitSpellTargetClass = function() return secretClass end,
        PlayerIsSpellTarget = function() return secretMine end,
        C_ClassColor = { GetClassColor = function(cls) e.classGiven = cls; return e.colour end },
    }
    e.name = secretName
    setmetatable(env, { __index = _G })
    local chunk = assert(loadstring("local ns = ...; "
        .. Slice("function ns.ShowCastTargetOn(", "-- Previews one custom line")))
    setfenv(chunk, env)
    e.ns = {}
    chunk(e.ns)
    e.env = env
    return e
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("the name and the marker are passed through untouched", function()
    local e = Fixture()
    assert(e.ns.ShowCastTargetOn("boss1") == true)
    assert(e.askedShow == "boss1", "the plain gate decides, and it is asked about the caster")
    assert(e.drawn.name == e.secretName, "the secret name reaches the font string as it came")
    assert(e.drawn.nameShown == true)
    assert(e.drawn.marker == e.secretMine, "the secret boolean reaches SetShown as it came")
end)

Case("the class colour is resolved without the class being read", function()
    local e = Fixture()
    e.ns.ShowCastTargetOn("boss1")
    assert(e.classGiven == e.secretClass, "the secret class goes straight to GetClassColor")
    assert(e.drawn.colour and e.drawn.colour[1] == 0.1 and e.drawn.colour[3] == 0.3)
end)

Case("a cast with nothing displayable clears whatever the last one left", function()
    local e = Fixture()
    e.show = false
    assert(e.ns.ShowCastTargetOn("boss1") == false)
    assert(e.drawn.name == nil and e.drawn.marker == nil)
    assert(e.drawn.nameHidden and e.drawn.markerHidden,
        "otherwise the previous cast's target stays on screen under a new callout")
end)

Case("each half can be switched off on its own", function()
    local e = Fixture()
    e.db.showCastTarget = false
    e.ns.ShowCastTargetOn("boss1")
    assert(e.drawn.name == nil and e.drawn.marker == e.secretMine)

    e = Fixture()
    e.db.markCastTarget = false
    e.ns.ShowCastTargetOn("boss1")
    assert(e.drawn.name == e.secretName and e.drawn.marker == nil)
end)

Case("both off means the client is never asked at all", function()
    local e = Fixture()
    e.db.showCastTarget, e.db.markCastTarget = false, false
    assert(e.ns.ShowCastTargetOn("boss1") == false)
    assert(e.askedShow == nil, "no point asking a question whose answer cannot be used")
end)

Case("a client without the API, or no unit, is refused rather than erroring", function()
    local e = Fixture()
    e.env.UnitSpellTargetName = nil
    assert(e.ns.ShowCastTargetOn("boss1") == false)
    e = Fixture()
    assert(e.ns.ShowCastTargetOn(nil) == false)
    assert(e.ns.ShowCastTargetOn(e.secretName) == false, "a unit token that is not a string")
end)

Case("a target the client declines to name leaves the marker working", function()
    local e = Fixture()
    e.name = nil
    e.ns.ShowCastTargetOn("boss1")
    assert(e.drawn.name == nil and e.drawn.nameShown == nil)
    assert(e.drawn.marker == e.secretMine, "being unable to name them does not mean it is not you")
end)

print(count .. " cast target regressions passed")
