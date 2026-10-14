-- Run with Lua 5.1 from the repository root: the Quest List's quests and rares come from the
-- load-on-demand NaowhForever_DiscoveryData on the first read. Loaded, both tables are its data;
-- not loaded (off in the AddOns list, or missing), they read as empty lists, and the load is not
-- tried again.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local function Store()
    local s, values = {}, {}
    function s.Get(k) return values[k] end
    function s.Set(k, v) values[k] = v end
    function s.OnChange() end
    return s
end

local function Fixture(loads)
    local ns = { L = dofile("Tools/regression/locale_stub.lua").L, FEATURES = { completo = {} } }
    ns.DiscoverySettings = Store()
    ns.UI = { ModuleSettings = Store }
    local tries = 0
    local env = setmetatable({
        _G = { NaowhForever = ns },
        hooksecurefunc = function() end,
        CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end,
        C_AddOns = { LoadAddOn = function(name)
            assert(name == "NaowhForever_DiscoveryData", "loads the data addon")
            tries = tries + 1
            if not loads then return false, "DISABLED" end
            ns.CompletoQuestData.Zones = { { map = 1416, quests = { 500 } } }
            ns.CompletoQuestData.Quests = { [500] = { "Quest" } }
            ns.CompletoRareData.Zones = { { map = 1416, rares = { 2452 } } }
            ns.CompletoRareData.Rares = { [2452] = { "Rare" } }
            return true
        end },
    }, { __index = _G })
    local chunk = assert(loadstring(Read("NaowhForever_Discovery/QuestList/Completo.lua")))
    setfenv(chunk, env)
    chunk()
    return ns, function() return tries end
end

do
    local ns, tries = Fixture(true)
    Check(tries() == 0, "nothing loads until the data is read")
    Check(ns.CompletoRareData.Rares[2452][1] == "Rare", "the first read loads it")
    Check(ns.CompletoQuestData.Quests[500][1] == "Quest" and #ns.CompletoQuestData.Zones == 1,
        "the other table is filled by the same load")
    Check(tries() == 1 and getmetatable(ns.CompletoQuestData) == nil, "loaded once")
end

do
    local ns, tries = Fixture(false)
    local quests, rares = ns.CompletoQuestData, ns.CompletoRareData
    Check(rares.Rares[2452] == nil, "not loaded: no rare is known")
    for _, zones in ipairs({ quests.Zones, rares.Zones }) do
        Check(type(zones) == "table" and next(zones) == nil, "not loaded: no zones to list")
    end
    Check(next(quests.Quests) == nil and next(quests.Requires) == nil and next(quests.Chains) == nil,
        "not loaded: no quests")
    Check(quests.Repeatable == nil and rares.Loot == nil, "the guarded lists stay nil")
    Check(tries() == 1, "the load is not tried again")
end

print(("test-discovery-data-load: %d checks passed"):format(checks))
