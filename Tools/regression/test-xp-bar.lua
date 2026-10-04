-- Run with Lua 5.1 from the repository root: the XP Bar's settings. A colour swatch that is
-- only opened, or cancelled, leaves the colour unset so it keeps following the theme; a text
-- shows in one spot at a time, the level's three forms counting as one; and the texts are
-- measured again only when one of them changed.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end

-- Runs source with env as its globals and hands back what it returns.
local function Load(source, env)
    local fn = assert(loadstring(source))
    setfenv(fn, setmetatable(env, { __index = _G }))
    return fn()
end

local function Settings(defaults)
    local db = {}
    local S = { db = db }
    function S.DB() return db end
    function S.Get(k)
        if db[k] == nil then return defaults[k] end
        return db[k]
    end
    function S.Set(k, v) db[k] = v end
    return S
end

-- A colour swatch: opening the picker reports the colour it opens with, and so does cancel.
do
    local source = Read("QoL/NaowhForever_XPBar.lua")
    local chunk = "local SAME_COLOUR = 1 / 255\n"
        .. assert(source:match("(local function SetColour%(.-\nend\n\nlocal function ColourRow%(.-\nend)\n"))
    local S = Settings({})
    local accent = { r = 0, g = 0x91 / 255, b = 0xed / 255 }
    local ns = { XPBarDefaultColor = function() return accent end }
    function ns.XPBarColor(k) return S.Get(k) or accent end
    local ColourRow = Load(chunk .. "\nreturn ColourRow", { S = S, ns = ns })
    local row = ColourRow("xpBarFillColor", "Fill Colour")
    row.getValue, row.setValue = row.get, row.set

    row.setValue(row.getValue())
    check("opening a swatch on the default saves nothing", S.db.xpBarFillColor == nil)
    row.setValue(accent.r + 0.5 / 255, accent.g, accent.b - 0.5 / 255)
    check("a colour within 1/255 of the default is the default", S.db.xpBarFillColor == nil)
    row.setValue(0.2, 0.8, 0.4)
    check("a real pick is saved", S.db.xpBarFillColor and S.db.xpBarFillColor.g == 0.8)
    row.setValue(0.2, 0.8, 0.4)
    check("cancelling reports the pick back, which stays", S.db.xpBarFillColor.r == 0.2)
    row.setValue(accent.r, accent.g, accent.b)
    check("picking the default again goes back to following the theme", S.db.xpBarFillColor == nil)
end

-- One spot per text.
do
    local source = Read("QoL/NaowhForever_XPBar.lua")
    local chunk = assert(source:match("(local SAME_TEXT = .-\nlocal function OneEach%(spots%).-\nend)\n"))
    local spots = { { key = "a" }, { key = "b" }, { key = "c" } }

    local S = Settings({ a = "played", b = "xphour", c = "none" })
    local env = { S = S }
    Load(chunk .. "\nClaimFn, OneEachFn = Claim, OneEach", env)

    S.db.c = "xphour"
    env.OneEachFn(spots)
    check("a text saved in two spots keeps the first", S.Get("b") == "xphour" and S.Get("c") == "none")

    env.ClaimFn(spots, "c", "played")
    check("picking a text for a spot clears the spot that had it", S.Get("a") == "none")

    S.db.a, S.db.b = "level", "none"
    env.ClaimFn(spots, "b", "levelnum")
    check("the level's forms count as one text", S.Get("a") == "none")

    S.db.a, S.db.b = "level", "levelshort"
    env.OneEachFn(spots)
    check("a profile with two level forms keeps the first", S.Get("a") == "level" and S.Get("b") == "none")

    S.db.a, S.db.b = "none", "none"
    env.ClaimFn(spots, "a", "none")
    check("None is never claimed", S.Get("b") == "none")
end

-- The texts are measured again only when one of them changed.
do
    local source = Read("QoL/NaowhForever_XPBar.lua")
    local chunk = assert(source:match("(local function TextsChanged%(list%).-\nend)\n"))
    local TextsChanged = Load(chunk .. "\nreturn TextsChanged", {})
    local function FS(text) return { text = text, GetText = function(self) return self.text end } end
    local list = { FS("Level 20"), FS("2509 / 23200"), FS("10.8%") }
    check("the first look counts as a change", TextsChanged(list))
    check("nothing changed", not TextsChanged(list))
    list[2].text = "2510 / 23200"
    check("one text changed", TextsChanged(list))
    check("and is remembered", not TextsChanged(list))
end

print(("test-xp-bar: %d checks passed"):format(checks))
