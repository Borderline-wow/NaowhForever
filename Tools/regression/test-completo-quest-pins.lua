-- Run with Lua 5.1 from the repository root: Completo's quest giver pins on the world map are
-- Pin Size on the small map and half that on the full screen map, and resize when the map
-- changes between the two.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end

local settings = { enabled = true, mapPins = true, mapPinSize = 20 }
local S = { Get = function(key) return settings[key] end, Set = function() end }
local ns = { CompletoSettings = S, Apply = function() end, ThemeTint = function() end,
    Completo = { Quests = { Refresh = function() end, Givers = function() return {} end } } }

local maximized, onSize = false, nil
local pins = {}
local map = {
    IsShown = function() return true end,
    IsMaximized = function() return maximized end,
    AddDataProvider = function() end,
    HookScript = function(_, name, fn) if name == "OnSizeChanged" then onSize = fn end end,
    GetMapID = function() return 1 end,
    RemoveAllPinsByTemplate = function() end,
    AcquirePin = function() end,
    EnumeratePinsByTemplate = function()
        local i = 0
        return function() i = i + 1; return pins[i] end
    end,
}
local boot
local env = setmetatable({
    _G = { NaowhForever = ns },
    CreateFromMixins = function() return { GetMap = function() return map end } end,
    MapCanvasPinMixin = {}, MapCanvasDataProviderMixin = {},
    CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetScript(name, fn) self[name] = fn end
        if not boot then boot = f end
        return f
    end,
    hooksecurefunc = function() end,
    WorldMapFrame = map,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
}, { __index = _G })
local chunk = assert(loadstring(Read("NaowhForever_Completo/NaowhForever_CompletoMap.lua")))
setfenv(chunk, env)
chunk()
boot.OnEvent(boot)

local Pin = env.NaowhForeverQuestGiverPinMixin
local function NewPin()
    local pin = setmetatable({ Icon = { SetAtlas = function() return true end, SetDesaturated = function() end,
        SetVertexColor = function() end } }, { __index = Pin })
    function pin:GetMap() return map end
    function pin:SetSize(w) self.size = w end
    function pin:SetPosition() end
    return pin
end

local pin = NewPin()
pin:OnAcquired({ x = 50, y = 50, quests = { 1 } })
Check(pin.size == 20, "Pin Size on the small map")
maximized = true
local big = NewPin()
big:OnAcquired({ x = 50, y = 50, quests = { 1 } })
Check(big.size == 10, "half that on the full screen map")

pins = { pin }
Check(onSize ~= nil, "the pins follow the map's size")
onSize()
Check(pin.size == 10, "going full screen shrinks the pins already drawn")
maximized = false
onSize()
Check(pin.size == 20, "and back")

print(("test-completo-quest-pins: %d checks passed"):format(checks))
