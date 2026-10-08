-------------------------------------------------------------------------------
--  NaowhForever_SkyborneSpots.lua -- Skyborne Spots: the ley lines (for Read Ley Line, the
--  Alliance Skyborne's racial) and Elemental Convergences (for Skysight, the Horde
--  Skyborne's) pinned on the world map. The game marks neither, so the spots come from two
--  places: the list every player starts with (NaowhForever_SkyborneData.lua), and the ones
--  this account finds: the racial cast on a spot gives its buff (Energized, Elemental
--  Blessing), and where it was cast is saved.
--  A Skyborne character sees its own faction's kind; other races see none.
--  Hover a pin for what it is, click it for a waypoint, right-click one you found to forget it.
--  Nothing is made or added to the map until it is switched on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local TEMPLATE = "NaowhForeverSkybornePinTemplate"
local SAME_SPOT = 40                -- yards: a find this close to a known spot is that spot
local MIN_BUFF = 60                 -- seconds: the spot's buff lasts minutes, not a moment
local MAP_CONTINENT = 2             -- Enum.UIMapType: this or above is not a zone's map

-- Per kind: the racial cast on it, and the buff it gives there (IDs from the 1.60.1 client).
local KINDS = {
    leyline = { name = "Ley Line", faction = "Alliance", racial = 1259705, buff = 1259691,
        help = "Stand on it and cast Read Ley Line.",
        icon = "Interface\\Icons\\Spell_Arcane_Arcane04" },
    convergence = { name = "Elemental Convergence", faction = "Horde", racial = 1259686, buff = 1270893,
        help = "Cast Skysight here for Elemental Blessing.",
        icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
}

local function On()
    return S.Get("enabled") and S.Get("mapSkyborne")
end

-- This character's kind of spot, or nil when it is not Skyborne.
local function MyKind()
    if select(2, UnitRace("player")) ~= "Skyborne" then return nil end
    local faction = UnitFactionGroup("player")
    for key, kind in pairs(KINDS) do
        if kind.faction == faction then return key end
    end
end

-- The spots this account found: { leyline = { { map, x, y }, ... }, convergence = ... }.
local function Found(kind)
    local account = ns.AccountSettings()
    account.skyborneSpots = account.skyborneSpots or {}
    account.skyborneSpots[kind] = account.skyborneSpots[kind] or {}
    return account.skyborneSpots[kind]
end

local function AnyFound()
    local all = ns.AccountSettings().skyborneSpots
    for _, list in pairs(all or {}) do
        if #list > 0 then return true end
    end
    return false
end

-- Where a spot is in the world: its continent and position in yards, or nil.
local function World(map, x, y)
    local continent, pos = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
    if not (continent and pos) then return nil end
    local wx, wy = pos:GetXY()
    return continent, wx, wy
end

local function Near(spot, continent, wx, wy)
    local c, sx, sy = World(spot[1], spot[2], spot[3])
    if c ~= continent then return false end
    return (sx - wx) ^ 2 + (sy - wy) ^ 2 <= SAME_SPOT * SAME_SPOT
end

-------------------------------------------------------------------------------
--  Finding spots
-------------------------------------------------------------------------------
local Redraw

-- A spot of this kind at map, x, y (percent): saved unless one is known that close.
local function Save(kind, map, x, y)
    local continent, wx, wy = World(map, x, y)
    if not continent then return end
    for _, list in ipairs({ ns.SkyborneSpots[kind], Found(kind) }) do
        for _, spot in ipairs(list) do
            if Near(spot, continent, wx, wy) then return end
        end
    end
    local found = Found(kind)
    found[#found + 1] = { map, x, y }
    local info = C_Map.GetMapInfo(map)
    ns.Print(("%s saved on your map: %s %.1f, %.1f."):format(KINDS[kind].name, info and info.name or "?", x, y))
    Redraw()
end

-- The spot's buff, given at or after the cast; nil while the game has not applied it yet.
-- Auras are secret in combat; read only while Readable, and through pcall all the same.
local function Readable()
    return not (InCombatLockdown() or C_Secrets.ShouldAurasBeSecret())
end

local function HasBuff(cast)
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(KINDS[cast.kind].buff)
    return aura and aura.duration >= MIN_BUFF and aura.expirationTime - aura.duration >= cast.time
end

-- A cast waiting for combat to end, its buff unreadable until then.
local waiting
local events   -- the map's frame, made once switched on
local watch = CreateFrame("Frame")

-- Looks for the buff a few times, as the game applies it a moment after the cast.
local function Check(cast)
    cast.tries = cast.tries + 1
    local ok, has = false, nil
    if Readable() then ok, has = pcall(HasBuff, cast) end
    if ok and has then
        Save(cast.kind, cast.map, cast.x, cast.y)
    elseif ok and cast.tries < 4 then
        C_Timer.After(0.5, function() Check(cast) end)
    elseif not ok or InCombatLockdown() then
        waiting = cast
        watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function Cast(kind)
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    local cast = { kind = kind, map = map, tries = 0, time = GetTime() - 1,
        x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
    C_Timer.After(0.2, function() Check(cast) end)
end

watch:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "PLAYER_REGEN_ENABLED" then
        watch:UnregisterEvent(event)
        local cast = waiting
        waiting = nil
        if cast and Readable() then
            local ok, has = pcall(HasBuff, cast)
            if ok and has then Save(cast.kind, cast.map, cast.x, cast.y) end
        end
        return
    end
    local kind = MyKind()
    if kind and not (issecretvalue and issecretvalue(spellID)) and spellID == KINDS[kind].racial then Cast(kind) end
end)

local function Watch()
    watch:UnregisterAllEvents()
    if On() and MyKind() then watch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end
end

-------------------------------------------------------------------------------
--  Pins
-------------------------------------------------------------------------------
local provider, added

-- Where a spot sits on the map shown, 0-1, or nil when that map does not hold it.
local function SpotOn(mapID, spot)
    local x, y = spot[2] / 100, spot[3] / 100
    if spot[1] == mapID then return x, y end
    local continent, world = C_Map.GetWorldPosFromMapPos(spot[1], CreateVector2D(x, y))
    local pos = continent and world and select(2, C_Map.GetMapPosFromWorldPos(continent, world, mapID))
    if not pos then return nil end
    local px, py = pos:GetXY()
    if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end

local function PinSize(map)
    local info = C_Map.GetMapInfo(map:GetMapID())
    local size = S.Get("mapSkyborneSize") or 20
    if info and info.mapType and info.mapType <= MAP_CONTINENT then size = size * 0.75 end
    if map:IsMaximized() then size = size / 2 end
    return size
end

local function MakePinMixin()
    -- A global so the XML template can name it.
    NaowhForeverSkybornePinMixin = CreateFromMixins(MapCanvasPinMixin)
    local Pin = NaowhForeverSkybornePinMixin

    function Pin:OnLoad()
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        self.Icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end

    -- The map calls this on every acquired pin, and its SetPassThroughButtons is protected:
    -- from our refresh it is blocked in combat. These pins want their clicks.
    function Pin:CheckMouseButtonPassthrough() end

    -- entry: { kind, spot, found } found is true for the account's own finds.
    function Pin:OnAcquired(entry, x, y)
        self.entry = entry
        local size = PinSize(self:GetMap())
        self:SetSize(size, size)
        self.Icon:SetTexture(KINDS[entry.kind].icon)
        self:SetPosition(x, y)
    end

    function Pin:OnMouseEnter()
        local kind = KINDS[self.entry.kind]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(kind.name, 1, 1, 1)
        GameTooltip:AddLine(kind.help, 0.61, 0.64, 0.69)
        local c = ns.ThemeTint("accentSoft", nil)
        local r, g, b = c and c.r or 0.3, c and c.g or 0.71, c and c.b or 0.96
        GameTooltip:AddLine("Click for a waypoint.", r, g, b)
        if self.entry.found then GameTooltip:AddLine("Right-click to forget this spot.", r, g, b) end
        GameTooltip:Show()
    end

    function Pin:OnMouseLeave()
        GameTooltip:Hide()
    end

    function Pin:OnClick(button)
        local entry = self.entry
        if button == "RightButton" then
            if not entry.found then return end
            local list = Found(entry.kind)
            for i = #list, 1, -1 do
                if list[i] == entry.spot then table.remove(list, i) end
            end
            GameTooltip:Hide()
            Redraw()
        elseif button == "LeftButton" then
            local spot = entry.spot
            ns.PlaceWaypoint(KINDS[entry.kind].name, spot[1], spot[2], spot[3])
        end
    end
end

local function MakeProvider()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)

    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end

    function provider:RefreshAllData()
        self:RemoveAllData()
        local kind = On() and MyKind()
        if not kind then return end
        local map = self:GetMap()
        local mapID = map:GetMapID()
        if not mapID then return end
        for _, source in ipairs({ { ns.SkyborneSpots[kind], false }, { Found(kind), true } }) do
            for _, spot in ipairs(source[1]) do
                local x, y = SpotOn(mapID, spot)
                if x then map:AcquirePin(TEMPLATE, { kind = kind, spot = spot, found = source[2] }, x, y) end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
Redraw = function()
    if not (added and WorldMapFrame:IsShown()) then return end
    -- Pins acquired in combat taint the map (its SetPassThroughButtons is protected), so a
    -- redraw asked for then waits for combat to end.
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    provider:RefreshAllData()
end

-- Only sizes change, so this is safe in combat too.
local function Resize()
    if not (added and WorldMapFrame:IsShown()) then return end
    for pin in WorldMapFrame:EnumeratePinsByTemplate(TEMPLATE) do
        local size = PinSize(WorldMapFrame)
        pin:SetSize(size, size)
    end
end

local waitingForMap = false

local function Apply()
    Watch()
    if not On() then
        Redraw()   -- takes the pins away
        return
    end
    -- The map may load after this file does.
    if not WorldMapFrame then
        if not waitingForMap then
            waitingForMap = true
            EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Apply)
        end
        return
    end
    if not provider then
        MakePinMixin()
        MakeProvider()
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            events:UnregisterEvent(event)
            Redraw()
        end)
        WorldMapFrame:HookScript("OnSizeChanged", Resize)
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    Redraw()
end

local function ForgetAll()
    ns.AccountSettings().skyborneSpots = nil
    Redraw()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "mapSkyborne" then
        Apply()
    elseif key == "mapSkyborneSize" then
        Resize()
    end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

ns.Shared.Settings.Page("QoL/Interface", S):Card({
    id = "mapSkyborne", name = "Skyborne Spots", order = 46, switch = "mapSkyborne",
    help = "For Skyborne characters: ley lines (Alliance, for Read Ley Line) or Elemental "
        .. "Convergences (Horde, for Skysight) pinned on the world map. The game does not mark "
        .. "them: the addon knows the ones players have found, and saves each new one you cast "
        .. "your racial on. Other races see no pins.",
    summary = function()
        local kind = MyKind()
        if not kind then return "Only for Skyborne characters" end
        local count = #ns.SkyborneSpots[kind] + #Found(kind)
        return ("%d %s known"):format(count, count == 1 and KINDS[kind].name or KINDS[kind].name .. "s")
    end,
    rows = {
        { key = "mapSkyborneSize", label = "Pin Size", slider = { 12, 32, 1 } },
        { label = "Forget Found Spots", buttonText = "Forget All", button = ForgetAll, needs = AnyFound,
          why = "No spots found yet",
          help = "Forgets every spot this account found. The addon's own list stays." },
    },
})
