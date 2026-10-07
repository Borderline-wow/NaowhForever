-- Importing a curator's single-profile pack has to be able to move every character on the
-- account, not just the one that ran the import. Covers the Core half (SetAccountProfile
-- plus the fallback a character with no assignment takes) and the dialog half (that the
-- Import button reaches it, with the name the import actually landed under).
local core = assert(io.open(arg[1] or "Core/NaowhForever_Core.lua", "rb"))
local coreSrc = core:read("*a"):gsub("\r\n", "\n"); core:close()
local packs = assert(io.open(arg[2] or "Core/NaowhForever_Packs.lua", "rb"))
local packSrc = packs:read("*a"):gsub("\r\n", "\n"); packs:close()

local function Slice(source, a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

local function Fixture(char)
    local e = { char = char or "Main-Ravencrest", reapplied = 0 }
    local env = { ns = { QueueReapply = function() e.reapplied = e.reapplied + 1 end },
        activeRoot = nil,
        CharKey = function() return e.char end,
        UnitName = function() return e.char:match("^[^-]+") end, UNKNOWNOBJECT = "Unknown" }
    setmetatable(env, { __index = _G })
    local code = Slice(coreSrc, "local function DB()", "function ns.SettingsRoot()")
        .. Slice(coreSrc, "function ns.SettingsRoot()", "function ns.AccountSettings()")
        .. Slice(coreSrc, "function ns.ActiveProfileName()", "function ns.ListProfiles()")
        .. Slice(coreSrc, "function ns.SpecProfileMap()", "function ns.AutoSpecProfile(")
        .. Slice(coreSrc, "function ns.AutoSpecProfile(", "function ns.ApplySpecProfile(")
        .. Slice(coreSrc, "function ns.ApplySpecProfile(", "local function ValidName(")
        .. Slice(coreSrc, "function ns.SwitchProfile(", "local function ValidName(")
        .. Slice(coreSrc, "function ns.SetAccountProfile(", "function ns.CreateProfile(")
    local chunk = assert(loadstring(code)); setfenv(chunk, env); chunk()
    -- activeRoot is a file local in the real chunk; the slice reads it as a global here, so
    -- the cache it keeps behaves the same way without dragging the whole file in.
    e.env, e.ns = env, env.ns
    e.db = function() return _G.NaowhForeverDB end
    _G.NaowhForeverDB = nil
    return e
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("a player still named Unknown is not filed or cached", function()
    local e = Fixture("Unknown-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    assert(next(sv.charActive) == nil and e.env.activeRoot == nil)
end)

Case("a player still named Unknown reads the account default's name", function()
    local e = Fixture("Unknown-Ravencrest")
    e.ns.SettingsRoot()
    e.db().defaultProfile = "Naowh"
    assert(e.ns.ActiveProfileName() == "Naowh")
end)

Case("every known character moves, and the account default moves with them", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Naowh, sv.profiles.Old = {}, {}
    sv.charActive["Alt1-Ravencrest"] = "Old"
    sv.charActive["Alt2-Draenor"] = "Old"
    assert(e.ns.SetAccountProfile("Naowh") == true)
    assert(sv.defaultProfile == "Naowh")
    for _, on in pairs(sv.charActive) do assert(on == "Naowh") end
    assert(e.reapplied > 0)
end)

Case("a character never logged in lands on it through the account default", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Naowh = {}
    e.ns.SetAccountProfile("Naowh")
    -- A fresh alt has no charActive entry at all; SettingsRoot assigns one on first read.
    e.char = "NeverSeen-Ravencrest"
    e.env.activeRoot = nil
    e.ns.SettingsRoot()
    assert(sv.charActive["NeverSeen-Ravencrest"] == "Naowh")
end)

Case("a profile the pack did not land is refused rather than invented", function()
    local e = Fixture()
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.charActive["Alt1-Ravencrest"] = "Old"
    local ok, why = e.ns.SetAccountProfile("Missing")
    assert(ok == false and type(why) == "string")
    assert(sv.charActive["Alt1-Ravencrest"] == "Old" and sv.defaultProfile == nil)
end)

Case("switching one character afterwards leaves the rest on the account profile", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Naowh, sv.profiles.Mine = {}, {}
    sv.charActive["Alt1-Ravencrest"] = "Mine"
    e.ns.SetAccountProfile("Naowh")
    sv.charActive["Alt1-Ravencrest"] = "Mine"
    assert(sv.charActive["Main-Ravencrest"] == "Naowh" and sv.defaultProfile == "Naowh")
end)

-- The dialog half. The Import handler is inside a 400-line closure, so rather than rebuild
-- its frames these assert on the source: that the account call exists on the single-profile
-- branch, runs after the import, and is handed the landed name.
Case("the import dialog reaches SetAccountProfile with the landed name", function()
    local branch = Slice(packSrc, "local ok, newName = ns.ImportPackAsProfile(",
        "    applyBtn = ns.Button(panel, \"Import\"")
    assert(branch:find("ns.SetAccountProfile(newName)", 1, true),
        "the single-profile import must point the account at the name it landed under")
    assert(branch:find("if accountWanted and ns.SetAccountProfile then", 1, true),
        "it must be gated on the toggle")
    assert(branch:find("ImportPackAsProfile", 1, true)
        < branch:find("SetAccountProfile", 1, true),
        "SetAccountProfile refuses a profile that does not exist yet, so the import runs first")
end)

Case("the toggle is offered for single-profile packs only", function()
    local build = Slice(packSrc, "        if not multi then\n            if not accountBtn then",
        "        if not multi then\n            if not nameBox then")
    assert(build:find("accountWanted", 1, true) and build:find("KnownCharacters", 1, true))
    assert(packSrc:find("elseif accountBtn then", 1, true), "it must hide again for a whole-file pack")
    -- The Save as row anchors under it, or the two draw over each other.
    assert(packSrc:find("local anchorTo = (accountBtn and accountBtn:IsShown() and accountBtn)", 1, true))
end)

-- The bug this feature shipped with: the account choice was written correctly and then
-- undone on the alt's next login, because auto spec switching still pointed every spec at
-- the profile it replaced.
Case("auto spec switching cannot undo the account profile on the next login", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Naowh, sv.profiles["Naowh New"] = {}, {}
    sv.autoSpecProfile = true
    sv.specProfile = { ["250"] = "Naowh", ["104"] = "Naowh", ["259"] = "Naowh Profile" }
    sv.charActive["Alt-Area 52"] = "Naowh"
    local ok, turnedOff = e.ns.SetAccountProfile("Naowh New")
    assert(ok == true and turnedOff == true)
    -- The alt logs in: PLAYER_LOGIN runs ApplySpecProfile for whatever spec it is on.
    e.char = "Alt-Area 52"
    e.env.activeRoot = nil
    e.ns.CurrentSpec = function() return 104 end
    assert(e.ns.ApplySpecProfile(104) == false)
    assert(sv.charActive["Alt-Area 52"] == "Naowh New")
    assert(e.ns.ActiveProfileName() == "Naowh New")
end)

Case("the spec map survives untouched and comes back if switching is re-enabled", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Naowh, sv.profiles["Naowh New"] = {}, {}
    sv.autoSpecProfile = true
    sv.specProfile = { ["250"] = "Naowh", ["259"] = "Naowh Profile" }
    e.ns.SetAccountProfile("Naowh New")
    -- Hand-built per-spec choices are the user's work, not ours to overwrite.
    assert(sv.specProfile["250"] == "Naowh" and sv.specProfile["259"] == "Naowh Profile")
    e.ns.AutoSpecProfile(true)
    e.ns.CurrentSpec = function() return 250 end
    assert(e.ns.ApplySpecProfile(250) == true)
    assert(sv.charActive["Main-Ravencrest"] == "Naowh")
end)

Case("a deliberate switch afterwards still moves that one character and its spec", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Naowh, sv.profiles["Naowh New"] = {}, {}
    sv.specProfile = {}
    e.ns.SetAccountProfile("Naowh New")
    e.ns.CurrentSpec = function() return 250 end
    e.ns.SwitchProfile("Naowh")
    assert(sv.charActive["Main-Ravencrest"] == "Naowh")
    assert(sv.specProfile["250"] == "Naowh", "the map learns from a deliberate switch")
    assert(sv.defaultProfile == "Naowh New", "the account default is not dragged along")
end)

Case("switching already off is reported as such rather than as a change", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles["Naowh New"] = {}
    sv.specProfile = { ["250"] = "Old" }
    local ok, turnedOff = e.ns.SetAccountProfile("Naowh New")
    assert(ok == true and turnedOff == false)
    assert(sv.autoSpecProfile == nil and sv.specProfile["250"] == "Old")
end)

-- The installer's public entry point, run against the real Core slice. InstallProfilePack is
-- stubbed to do what the real one does to profile state: land the profile and switch to it,
-- which maps the current spec.
local function WithApi(e, install)
    e.env._G = e.env
    e.printed = {}
    e.ns.Print = function(msg) e.printed[#e.printed + 1] = msg end
    e.ns.InstallProfilePack = install
    local code = Slice(packSrc, "local function CurrentSpecEntry()", "-- opts, all optional:")
        .. Slice(packSrc, "local API = {}", "-- Decode and validate;")
    local chunk = assert(loadstring(code)); setfenv(chunk, e.env); chunk()
    return e.env.NaowhForever_API
end

Case("ImportProfile lands the named profile on every character and keeps the spec choice", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.profiles.Mine = {}
    sv.specProfile = { ["250"] = "Mine" }
    sv.charActive["Alt-Draenor"] = "Mine"
    e.ns.CurrentSpec = function() return 250 end
    local passed
    local API = WithApi(e, function(_, opts)
        passed = opts
        sv.profiles[opts.profileName] = {}
        e.ns.SwitchProfile(opts.profileName)
        return true, opts.profileName
    end)
    local ok, landed = API:ImportProfile("NSRPACK2:x", "Naowh")
    assert(ok == true and landed == "Naowh" and passed.profileName == "Naowh")
    assert(sv.defaultProfile == "Naowh" and sv.charActive["Alt-Draenor"] == "Naowh")
    assert(sv.specProfile["250"] == "Mine", "the spec map is put back the way the player had it")
end)

Case("a failed ImportProfile says so and leaves the account alone", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    sv.charActive["Alt-Draenor"] = "Mine"
    local API = WithApi(e, function() return false, "The string is damaged (encoding)." end)
    local ok, why = API:ImportProfile("garbage", "Naowh")
    assert(ok == false and why == "The string is damaged (encoding).")
    assert(e.printed[1] and e.printed[1]:find("damaged", 1, true))
    assert(sv.defaultProfile == nil and sv.charActive["Alt-Draenor"] == "Mine")
end)

Case("a whole-file pack keeps its own profiles instead of becoming the account profile", function()
    local e = Fixture("Main-Ravencrest")
    e.ns.SettingsRoot()
    local sv = e.db()
    local API = WithApi(e, function() return true, 3 end)
    assert(API:ImportProfile("NSRPACK2:x", "Naowh") == true)
    assert(sv.defaultProfile == nil)
end)

print(count .. " account profile import regressions passed")
