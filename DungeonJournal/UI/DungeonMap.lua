-------------------------------------------------------------------------------
--  UI/DungeonMap.lua -- a dungeon's map: the game's own map art of the dungeon (Data/Maps.lua),
--  or, for one the game has no art for yet, a picture the addon ships (image), with its
--  maker's credit in the map's corner; its bosses as round portraits where they stand, each
--  with its place in the kill order, and the entrance. Hover a boss for its name, click it
--  for its loot; a dungeon on several floors has a switch under the map. It shows in two
--  places, each a view of its own:
--
--  - A window, from Map on a dungeon page's Bosses title: in front of the window that holds
--    the page, beside it where the screen has room (else over its top right), as tall as it.
--    Under the map, the bosses in kill order (the legend: hover one to light its pin, a pin
--    to light its row), each with a tick once killed this run (and its pin dimmed), a quest
--    mark where a quest in your log needs it, and your BiS there; beside them the loot of
--    the boss picked (a pin or a row). The chevron in its title folds that part away, for
--    the map alone (kept for the account). It closes with that window unless pinned (the
--    pin in its title, kept for the account too); the Naowh mark in its title, or its name,
--    opens the Dungeon Journal on the dungeon's page again.
--  - The world map: press M inside a dungeon and its map fills the map's picture, while the
--    Journal sits beside the map (UI/MapPanel.lua says when: it already watches the map).
--    Right-click goes up to the zone the dungeon is in, as the world map goes up a level;
--    Map on the panel beside it brings it back.
--
--  Where the bosses stand is placed by hand. /nf mappins turns placing on in the window:
--  every boss gets a pin to drag (those not placed yet wait along the top), the entrance too,
--  and Copy gives the dungeon's line for Data/Maps.lua. What you place is kept for the
--  account until then, and shown over the data. /nf mapcheck prints which map art and floors
--  the client has. The switch only offers the floors something stands on, once anything is
--  placed: the art has floors with nothing of the dungeon on them (Shadowfang Keep's fifth).
--  Placing, or before anything is placed, it offers them all.
--
--  Nothing is made until a map is first shown, and it listens to nothing.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings

local St = J.Style
local PANEL_PAD, PANEL_HEADER = St.PANEL_PAD, St.PANEL_HEADER

local ART = "Interface\\WorldMap\\%s\\%s%d_%d"   -- folder, folder, floor, tile (1 to 12)
local TILE = 256
local MAP_W, MAP_H = 1002, 668   -- the part of the four by three tiles the map shows
-- An addon picture (a map's image) is a 1024 square TGA with the map in its top 1024 by 683,
-- drawn over the whole map.
local IMAGE_BOTTOM = 683 / 1024
local WINDOW_SCALE = 0.7         -- the map in the window: about 700 by 470
local PIN = 46                   -- a boss's portrait, in the map's own size
local BADGE = 20                 -- its number
local ENTRANCE = 28
local TRAY_STEP = PIN + 10       -- placing: the pins not placed yet, along the top
local FLOOR_H = 22               -- the floor switch under the map
local FLOOR_STEP_W = 22
local COPY_W = 52
local PIN_BUTTON = 20            -- the window's pin, beside its close button
local PIN_ICON = 14
local LEGEND_W = 320             -- the bosses under the map; their loot takes the rest
local ROW_H = 22
local FACE = 18                  -- a row's portrait
local ICON = 13                  -- a row's quest mark, tick and star
local LOWER_GAP = 10             -- the map's floor line to the legend; the legend to the loot
local LOWER_MIN = 260            -- the part under the map, opened with no window to match
local SCROLL_GAP = 16
local UNDER_MAP_GAP = 6          -- the map to the floor switch's line
local KILLED_ALPHA = 0.45        -- a pin killed this run, on the map
local UNPLACED_ALPHA = 0.7       -- placing: a pin waiting along the top
-- The picked pin's ring and its glow: gold, or the theme's Accent once the player picked one.
local PICKED_RGB = St.PICKED_RGB
local PICKED_RING = 8            -- the ring round the picked pin's portrait, edge to edge
local PICKED_GLOW = 24           -- and the glow pulsing round it
local GLOW_LOW, GLOW_HIGH, GLOW_PULSE = 0.15, 0.55, 0.9
-- A legend row, left to right: its number, portrait and name, each after a gap; what the
-- quest mark, the star and its count take on the right.
local ROW_PAD, NUMBER_W, ROW_GAP, MARKS_W = 6, 18, 6, 70
local MASK = "Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga"

local placing = false            -- /nf mappins, in the window
local lootFrom                   -- the view whose pin opened the boss's loot, to close it with

-------------------------------------------------------------------------------
--  Where a pin stands: what was placed on this account while placing, else the data
-------------------------------------------------------------------------------
local function Placed(dungeon)
    local all = ns.AccountSettings().journalMapPins
    return type(all) == "table" and all[dungeon.key] or nil
end

local function Spot(dungeon, key)
    local placed = Placed(dungeon)
    local spot = placed and placed[key]
    if type(spot) == "table" then return spot end
    local map = J.Maps[dungeon.key]
    if key == "entrance" then return map.entrance end
    return map.pins[key]
end

local function Keep(dungeon, key, spot)
    local account = ns.AccountSettings()
    account.journalMapPins = account.journalMapPins or {}
    account.journalMapPins[dungeon.key] = account.journalMapPins[dungeon.key] or {}
    account.journalMapPins[dungeon.key][key] = spot
end

-- A boss's key on the map: its NPC ID, or minus a chest's object ID; nil for the trash.
local function KeyOf(boss)
    return boss.npc or (boss.chest and -boss.chest) or nil
end

-- Each boss of the dungeon, numbered in kill order as its page numbers them (a rare, an
-- optional boss and a chest have none); fn(boss, number, key).
local function EachBoss(dungeon, fn)
    for _, wing in ipairs(dungeon.wings) do
        local number = 0
        for _, boss in ipairs(wing.bosses) do
            local key = KeyOf(boss)
            local ordered = not (boss.rare or boss.optional or boss.chest or boss.trash)
            if ordered then number = number + 1 end
            if key then fn(boss, ordered and number or nil, key) end
        end
    end
end

-------------------------------------------------------------------------------
--  A view: the map art, its pins and the floor switch, drawn into a frame
-------------------------------------------------------------------------------
local View = {}
View.__index = View

local function PinEnter(pin)
    local boss = pin.boss
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    local kind = boss.rare and "Rare" or boss.optional and "Optional" or boss.chest and "Chest" or nil
    if kind then GameTooltip:AddLine(kind, T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:AddLine(pin.view:Placing() and "Drag to place it." or "Click for its loot.",
        T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
    if pin.view.onPinHover then pin.view.onPinHover(pin.key, true) end
end

local function PinLeave(pin)
    GameTooltip:Hide()
    if pin.view.onPinHover then pin.view.onPinHover(pin.key, false) end
end

local function PinClicked(pin, button)
    -- A right-click goes to the view (on the world map: up to the zone).
    if button == "RightButton" then
        if pin.view.onRightClick then pin.view.onRightClick() end
        return
    end
    if pin.view:Placing() then return end
    local view = pin.view
    -- The window shows it in its own loot pane.
    if view.onPick then return view.onPick(pin.boss) end
    -- The world map: the Journal beside it shows the boss's page (its loot and abilities);
    -- the boss clicked again, the dungeon's page again.
    local again = view.picked == pin.key
    view:Pick(not again and pin.key or nil)
    J.ShowBossBesideMap(not again and pin.boss or nil)
    if again then
        if lootFrom == view then
            lootFrom = nil
            J.View.CloseBossLoot()
        end
        return
    end
    -- Maximised, the Journal sits over the map's edge: its loot at the mouse too.
    if not WorldMapFrame:IsMaximized() then return end
    lootFrom = view
    J.View.OpenBossLoot(pin.boss, view.dungeon)
end

-- A map closes (the world map, M again; the window): no pin is picked, and the loot one of
-- its pins opened goes too.
local function ViewHidden(view)
    view:Pick(nil)
    if lootFrom == view then
        lootFrom = nil
        J.View.CloseBossLoot()
    end
end

-- A drag ends: where the pin's middle is on the map, 0 to 1 across and down, kept.
local function DragStop(frame)
    frame:StopMovingOrSizing()
    local view = frame.view
    -- The game ends a drag on any pin a click moved a little: only placing keeps where it is.
    if not view:Placing() then return end
    local x, y = frame:GetCenter()
    local left, top = view.canvas:GetLeft(), view.canvas:GetTop()
    if x and left then
        x = math.min(1, math.max(0, (x - left) / MAP_W))
        y = math.min(1, math.max(0, (top - y) / MAP_H))
        Keep(view.dungeon, frame.key, { view.floor, math.floor(x * 1000 + 0.5) / 1000,
            math.floor(y * 1000 + 0.5) / 1000 })
    end
    view:Draw()
end

local function DragStart(frame)
    if frame.view:Placing() then frame:StartMoving() end
end

local function Draggable(frame)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", DragStart)
    frame:SetScript("OnDragStop", DragStop)
end

-- Round: a texture cut to a circle.
local function Round(frame, texture)
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(texture)
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
end

-- The portrait in a 1px black ring, as the house's edges are (its width set for the view's
-- scale when drawn); its number on a small dark disc at its foot. A boss without a portrait
-- (or a chest) shows its number, larger.
function View:NewPin()
    local pin = CreateFrame("Button", nil, self.canvas)
    pin.view = self
    pin:SetSize(PIN, PIN)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Picked (its loot is showing): a ring round its portrait in a slow glow, gold or the
    -- theme's Accent (PICKED_RGB).
    pin.halo = pin:CreateTexture(nil, "BACKGROUND", nil, -3)
    pin.halo:SetPoint("CENTER")
    pin.halo:SetSize(PIN + PICKED_GLOW, PIN + PICKED_GLOW)
    pin.halo:SetColorTexture(1, 1, 1, 1)   -- its colour is set as it shows (ShowPicked)
    pin.halo:SetBlendMode("ADD")
    Round(pin, pin.halo)
    pin.halo:Hide()
    pin.pulse = pin.halo:CreateAnimationGroup()
    pin.pulse:SetLooping("BOUNCE")
    local fade = pin.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(GLOW_LOW)
    fade:SetToAlpha(GLOW_HIGH)
    fade:SetDuration(GLOW_PULSE)
    fade:SetSmoothing("IN_OUT")
    pin.gold = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
    pin.gold:SetPoint("CENTER")
    pin.gold:SetSize(PIN + PICKED_RING, PIN + PICKED_RING)
    pin.gold:SetColorTexture(1, 1, 1, 1)
    Round(pin, pin.gold)
    pin.gold:Hide()
    -- Lit while its legend row is hovered: the accent, round, just outside its ring.
    pin.glow = pin:CreateTexture(nil, "BACKGROUND", nil, -2)
    pin.glow:SetPoint("CENTER")
    pin.glow:SetSize(PIN + 12, PIN + 12)
    pin.glow:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.9)
    Round(pin, pin.glow)
    pin.glow:Hide()
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetPoint("CENTER")
    pin.ring:SetColorTexture(0, 0, 0, 1)
    Round(pin, pin.ring)
    pin.plate = pin:CreateTexture(nil, "BORDER")
    pin.plate:SetAllPoints()
    pin.plate:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 1)
    Round(pin, pin.plate)
    pin.face = pin:CreateTexture(nil, "ARTWORK")
    pin.face:SetAllPoints()
    Round(pin, pin.face)
    pin.big = ns.Font(pin, 18, nil, T.fg)
    pin.big:SetPoint("CENTER")
    pin.badge = CreateFrame("Frame", nil, pin)
    pin.badge:SetSize(BADGE, BADGE)
    pin.badge:SetPoint("CENTER", pin, "BOTTOMRIGHT", -6, 6)
    pin.badge.disc = pin.badge:CreateTexture(nil, "ARTWORK")
    pin.badge.disc:SetAllPoints()
    pin.badge.disc:SetColorTexture(0, 0, 0, 0.9)
    Round(pin.badge, pin.badge.disc)
    pin.badge.text = ns.Font(pin.badge, 11, nil, T.fg)
    pin.badge.text:SetPoint("CENTER")
    pin:SetScript("OnEnter", PinEnter)
    pin:SetScript("OnLeave", PinLeave)
    pin:SetScript("OnClick", PinClicked)
    Draggable(pin)
    return pin
end

-- The boss's portrait from its creature display, where the client can draw one.
local function SetFace(pin, boss, number, ring)
    pin.ring:SetSize(PIN + ring * 2, PIN + ring * 2)
    local face = boss.model and SetPortraitTextureFromCreatureDisplayID
    if face then SetPortraitTextureFromCreatureDisplayID(pin.face, boss.model) end
    pin.face:SetShown(face ~= nil)
    pin.big:SetShown(not face)
    pin.big:SetText(boss.chest and "?" or number or "")
    pin.badge:SetShown(face ~= nil and number ~= nil)
    pin.badge.text:SetText(number or "")
end

-- The gold ring and its glow on or off; the glow only pulses while it shows.
local function ShowPicked(pin, on)
    pin.gold:SetShown(on)
    pin.halo:SetShown(on)
    if on then
        -- Read as it shows, so a theme changed since follows on the next pick.
        local c = ns.ThemeTint("accent", PICKED_RGB)
        pin.gold:SetColorTexture(c.r, c.g, c.b, 1)
        pin.halo:SetColorTexture(c.r, c.g, c.b, 1)
        if not pin.pulse:IsPlaying() then pin.pulse:Play() end
    else
        pin.pulse:Stop()
    end
end

-- The view's switch: back, the floor's name, on; its caller places self.down.
local function NewView(parent, holder, editable)
    local view = setmetatable({ pins = {}, used = 0, tray = 0, floors = {}, editable = editable }, View)
    -- The map in its own size; what lies past its 1002 by 668 is cut off.
    local canvas = CreateFrame("Frame", nil, parent)
    canvas:SetSize(MAP_W, MAP_H)
    canvas:SetClipsChildren(true)
    view.canvas, view.tiles = canvas, {}
    for i = 1, 12 do
        local tile = canvas:CreateTexture(nil, "BACKGROUND")
        tile:SetSize(TILE, TILE)
        tile:SetPoint("TOPLEFT", (i - 1) % 4 * TILE, -math.floor((i - 1) / 4) * TILE)
        view.tiles[i] = tile
    end
    view.picture = canvas:CreateTexture(nil, "BACKGROUND")
    view.picture:SetAllPoints()
    view.picture:SetTexCoord(0, 1, 0, IMAGE_BOTTOM)
    view.picture:Hide()
    local door = CreateFrame("Button", nil, canvas)
    door:SetSize(ENTRANCE, ENTRANCE)
    door.icon = door:CreateTexture(nil, "ARTWORK")
    door.icon:SetAllPoints()
    door.icon:SetAtlas("dungeon")
    door.text = ns.Font(door, 16, "OUTLINE", T.fg)
    door.text:SetPoint("LEFT", door, "RIGHT", 4, 0)
    door.text:SetText("Entrance")
    door.key, door.view = "entrance", view
    Draggable(door)
    view.door = door
    view.down = ns.Button(holder, "<", FLOOR_STEP_W, FLOOR_H - 2, function() view:Step(-1) end)
    view.floorName = ns.Font(holder, 12, nil, T.fg)
    view.floorName:SetPoint("LEFT", view.down, "RIGHT", 8, 0)
    view.up = ns.Button(holder, ">", FLOOR_STEP_W, FLOOR_H - 2, function() view:Step(1) end)
    view.up:SetPoint("LEFT", view.floorName, "RIGHT", 8, 0)
    return view
end

-- The boss whose loot shows (its key), ringed in gold; nil for none.
function View:Pick(key)
    self.picked = key
    for i = 1, self.used do
        local pin = self.pins[i]
        ShowPicked(pin, key ~= nil and pin.key == key and not self:Placing())
    end
end

function View:Placing()
    return placing and self.editable
end

-- Where n is in the switch's floors, or nil.
function View:FloorAt(n)
    for i = 1, #self.floors do
        if self.floors[i] == n then return i end
    end
end

function View:Offer(spot)
    if type(spot) == "table" and not self:FloorAt(spot[1]) then self.floors[#self.floors + 1] = spot[1] end
end

-- The floors the switch offers: those something stands on, else (placing, or nothing placed
-- yet) every floor of the art.
-- The view being filled, for the callbacks below (EachBoss's, made once: no garbage).
local filling

local function OfferBoss(_, _, key)
    filling:Offer(Spot(filling.dungeon, key))
end

local function FirstFloor(_, _, key)
    local spot = Spot(filling.dungeon, key)
    if not filling.floor and type(spot) == "table" then filling.floor = spot[1] end
end

function View:FillFloors()
    local dungeon, floors = self.dungeon, self.floors
    wipe(floors)
    if not self:Placing() then
        self:Offer(Spot(dungeon, "entrance"))
        filling = self
        EachBoss(dungeon, OfferBoss)
        table.sort(floors)
    end
    if #floors == 0 then
        local map = J.Maps[dungeon.key]
        -- A dungeon on one floor of shared art (map.floor) offers only that one.
        if map.floor then
            floors[1] = map.floor
        else
            for n = 1, map.floors do floors[n] = n end
        end
    end
    if not self:FloorAt(self.floor) then self.floor = floors[1] end
end

-- Shows the dungeon, on the floor its first placed boss is on, else its first.
function View:Open(dungeon)
    self.dungeon, self.floor, self.picked = dungeon, nil, nil
    filling = self
    EachBoss(dungeon, FirstFloor)
    self:FillFloors()
end

function View:At(frame, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", self.canvas, "TOPLEFT", x * MAP_W, -y * MAP_H)
end

function View:DrawPin(boss, number, key)
    local spot = Spot(self.dungeon, key)
    local here = type(spot) == "table" and spot[1] == self.floor
    if not here and not (self:Placing() and spot == nil) then return end
    self.used = self.used + 1
    local pin = self.pins[self.used] or self:NewPin()
    self.pins[self.used] = pin
    pin.boss, pin.key = boss, key
    SetFace(pin, boss, number, 1 / self.scale)
    pin.glow:Hide()
    ShowPicked(pin, self.picked ~= nil and key == self.picked and not self:Placing())
    if here then
        self:At(pin, spot[2], spot[3])
        -- Killed this run, in the dungeon you are in: dimmed.
        pin:SetAlpha(self.inside and J.Kills.ThisRun(boss) and KILLED_ALPHA or 1)
    else
        -- Not placed yet: along the top, to drag from.
        self.tray = self.tray + 1
        pin:ClearAllPoints()
        pin:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", (self.tray - 1) * TRAY_STEP + 8, -8)
        pin:SetAlpha(UNPLACED_ALPHA)
    end
    pin:Show()
end

local function FloorName(map, n)
    return map.names and map.names[n] or ("Floor %d"):format(n)
end

local function DrawPinOf(view)
    return function(boss, number, key) view:DrawPin(boss, number, key) end
end

-- Whether you are in the dungeon shown (its run's progress shows then).
local function Inside(dungeon)
    local here = J.Current()
    if not here then return false end
    for i = 1, #here do
        if here[i] == dungeon then return true end
    end
    return false
end

function View:Draw()
    local dungeon = self.dungeon
    if not dungeon then return end
    self.inside = Inside(dungeon)
    local map = J.Maps[dungeon.key]
    -- The game's art in twelve tiles, or the addon's own picture of a dungeon without any.
    local image = map.image
    self.picture:SetShown(image ~= nil)
    if image then self.picture:SetTexture(image, nil, nil, "TRILINEAR") end
    for i = 1, 12 do
        self.tiles[i]:SetShown(image == nil)
        if not image then self.tiles[i]:SetTexture(ART:format(map.art, map.art, self.floor, i)) end
    end
    for i = 1, self.used do
        self.pins[i]:Hide()
        ShowPicked(self.pins[i], false)
    end
    self.used, self.tray = 0, 0
    self.drawPin = self.drawPin or DrawPinOf(self)
    EachBoss(dungeon, self.drawPin)
    local door = Spot(dungeon, "entrance")
    local here = type(door) == "table" and door[1] == self.floor
    self.door:SetShown(here or self:Placing())
    if here then
        self:At(self.door, door[2], door[3])
    elseif self:Placing() then
        self.door:ClearAllPoints()
        self.door:SetPoint("TOPRIGHT", self.canvas, "TOPRIGHT", -8, -8)
    end
    local several = #self.floors > 1
    self.floorName:SetShown(several)
    self.down:SetShown(several)
    self.up:SetShown(several)
    self.floorName:SetText(FloorName(map, self.floor))
    if self.onDraw then self.onDraw() end
end

function View:Step(by)
    local at = self:FloorAt(self.floor) or 1
    self.floor = self.floors[(at - 1 + by) % #self.floors + 1]
    self:Draw()
end

-------------------------------------------------------------------------------
--  Placing: the dungeon's line for Data/Maps.lua
-------------------------------------------------------------------------------
-- 0.5, not 0.500.
local function Number(v)
    local text = ("%.3f"):format(v):gsub("0+$", "")
    return (text:gsub("%.$", ""))
end

local function SpotText(spot)
    return ("{ %d, %s, %s }"):format(spot[1], Number(spot[2]), Number(spot[3]))
end

local function Copy(dungeon)
    local map = J.Maps[dungeon.key]
    local source = map.image and ("image = %q"):format(map.image) or ("art = %q"):format(map.art)
    local lines = { ("    %s = { %s, floors = %d,%s"):format(dungeon.key, source, map.floors,
        map.floor and (" floor = %d,"):format(map.floor) or "") }
    if map.names then
        local names = {}
        for i, name in ipairs(map.names) do names[i] = ("%q"):format(name) end
        lines[#lines + 1] = "        names = { " .. table.concat(names, ", ") .. " },"
    end
    local door = Spot(dungeon, "entrance")
    if door then lines[#lines + 1] = "        entrance = " .. SpotText(door) .. "," end
    lines[#lines + 1] = "        pins = {"
    EachBoss(dungeon, function(boss, _, key)
        local spot = Spot(dungeon, key)
        if spot then
            lines[#lines + 1] = ("            [%d] = %s,   -- %s"):format(key, SpotText(spot), boss.name)
        end
    end)
    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "    },"
    ns.ShowCopyBox(dungeon.name .. ": Data/Maps.lua", table.concat(lines, "\n"))
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local BESIDE_GAP = 4
local OVER_INSET = 40      -- over the window, clear of its title bar
local window, windowView
local owners = {}          -- the windows it closes with, hooked once each

local function Pinned()
    return ns.AccountSettings().journalMapPinned == true
end

-- The top of the frame Map was clicked in: the Journal window, or the map panel.
local function Owner(frame)
    while frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
    return frame
end

-- Its window closes: the map goes with it, unless pinned; pinned, it stays where it is.
local function OwnerHidden()
    if not window:IsShown() then return end
    if not Pinned() then
        window:Hide()
        return
    end
    local x, y = window:GetCenter()
    window:ClearAllPoints()
    window:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

-- In front of the window it was opened from, on its layer: beside it on the right where the
-- screen has room, else on the left, else over its top right. Opened with nothing to
-- follow (a test, a command), in the middle.
local function Place(from)
    window:ClearAllPoints()
    local owner = from and Owner(from)
    if not owner then
        window:SetFrameStrata("HIGH")
        window:SetScale(ns.UIScale())
        window:SetPoint("CENTER")
        return
    end
    if not owners[owner] then
        owners[owner] = true
        owner:HookScript("OnHide", OwnerHidden)
    end
    window:SetFrameStrata(owner:GetFrameStrata())
    window:SetScale(owner:GetScale())
    local scale = owner:GetEffectiveScale()
    local need = (window:GetWidth() + BESIDE_GAP) * scale
    local right = UIParent:GetRight() * UIParent:GetEffectiveScale() - (owner:GetRight() or 0) * scale
    local left = (owner:GetLeft() or 0) * scale
    if right >= need then
        window:SetPoint("TOPLEFT", owner, "TOPRIGHT", BESIDE_GAP, 0)
    elseif left >= need then
        window:SetPoint("TOPRIGHT", owner, "TOPLEFT", -BESIDE_GAP, 0)
    else
        window:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -OVER_INSET / 2, -OVER_INSET)
    end
end

local function Paint()
    window.backdrop:Paint(S.Get("mapAlpha") or 1)
end

-- The pin: the accent while pinned, muted while not, white under the mouse.
local function PaintPin(button)
    local color = button:IsMouseOver() and T.fg or Pinned() and T.accent or T.muted
    button.icon:SetVertexColor(color.r, color.g, color.b)
end

local function PinButtonEnter(button)
    PaintPin(button)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Pinned() and "Pinned" or "Pin the map", 1, 1, 1)
    GameTooltip:AddLine(Pinned() and "It stays open when the Journal closes. Click to unpin."
        or "Keeps it open when the Journal closes.", T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function PinButtonLeave(button)
    PaintPin(button)
    GameTooltip:Hide()
end

local function PinButtonClicked(button)
    ns.AccountSettings().journalMapPinned = not Pinned() or nil
    PinButtonEnter(button)
end

-------------------------------------------------------------------------------
--  Under the map: the legend and the loot
-------------------------------------------------------------------------------
local legend, lootView, picked
local rows = {}
local quests = {}   -- boss -> what your quests need of it, filled each draw: { text, done }

local function Folded()
    return ns.AccountSettings().journalMapFolded == true
end

-- What a quest in your log needs of the boss: an objective naming it (its head, its death).
-- Read from your log's own words, so it is a match by name: none when the game words it
-- otherwise.
-- Kept and reused from draw to draw (a draw makes no garbage): each boss's list, and each
-- need in it, { quest's name, objective's text, done }.
local lists, needs = {}, {}
local listsUsed, needsUsed = 0, 0
-- The objective being matched against each boss (EachBoss's callback, made once).
local matchLower, matchQuest, matchText, matchDone

local function MatchBoss(boss)
    if not (boss.npc and matchLower:find(boss.name:lower(), 1, true)) then return end
    local list = quests[boss]
    if not list then
        listsUsed = listsUsed + 1
        list = lists[listsUsed] or {}
        lists[listsUsed] = list
        wipe(list)
        quests[boss] = list
    end
    needsUsed = needsUsed + 1
    local need = needs[needsUsed] or {}
    needs[needsUsed] = need
    need[1], need[2], need[3] = J.Quests.Name(matchQuest), matchText, matchDone
    list[#list + 1] = need
end

local function FillQuests(dungeon)
    wipe(quests)
    listsUsed, needsUsed = 0, 0
    local list = dungeon.quests and dungeon.quests.quests
    if not list then return end
    for _, quest in ipairs(list) do
        local id = J.Quests.LoggedID(quest)
        local objectives = id and C_QuestLog.GetQuestObjectives(id)
        if objectives then
            for _, objective in ipairs(objectives) do
                local text = objective.text
                if text and text ~= "" and not issecretvalue(text) then
                    matchLower, matchQuest, matchText, matchDone = text:lower(), quest, text, objective.finished
                    EachBoss(dungeon, MatchBoss)
                end
            end
        end
    end
end

local function PinOf(key)
    for i = 1, windowView.used do
        if windowView.pins[i].key == key then return windowView.pins[i] end
    end
end

local function RowOf(key)
    for _, row in ipairs(rows) do
        if row:IsShown() and row.key == key then return row end
    end
end

-- A row hovered lights its pin; a pin hovered lights its row.
local function Light(key, on)
    local pin = PinOf(key)
    if pin then pin.glow:SetShown(on) end
    local row = RowOf(key)
    if row then row.hover:SetShown(on or row.boss == picked) end
end

local function Pick(boss)
    picked = boss
    windowView:Pick(boss and KeyOf(boss))
    for _, row in ipairs(rows) do
        row.bar:SetShown(row:IsShown() and row.boss == picked)
        row.hover:SetShown(row:IsShown() and row.boss == picked)
    end
    window.hint:SetShown(boss == nil)
    if boss then lootView:DrawBossLoot(boss, windowView.dungeon) else lootView:Hide() end
    if boss then lootView:Show() end
end

local function RowEnter(row)
    Light(row.key, true)
    local boss = row.boss
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    if row.killed then GameTooltip:AddLine("Killed this run", St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b) end
    for _, need in ipairs(quests[boss] or {}) do
        GameTooltip:AddLine(need[1], 1, 0.82, 0)
        GameTooltip:AddLine("  " .. need[2], need[3] and T.muted.r or 1, need[3] and T.muted.g or 1,
            need[3] and T.muted.b or 1, true)
    end
    if row.bis > 0 then
        GameTooltip:AddLine(("%d of your BiS, %d of them yours"):format(row.bis, row.haveBis),
            St.BIS_RGB.r, St.BIS_RGB.g, St.BIS_RGB.b)
    end
    if not Spot(windowView.dungeon, row.key) then
        GameTooltip:AddLine("Not on the map yet.", T.muted.r, T.muted.g, T.muted.b)
    end
    GameTooltip:AddLine("Click for its loot.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function RowLeave(row)
    Light(row.key, false)
    GameTooltip:Hide()
end

-- A click shows its loot, and its floor on the map.
local function RowClicked(row)
    local spot = Spot(windowView.dungeon, row.key)
    if type(spot) == "table" and spot[1] ~= windowView.floor and windowView:FloorAt(spot[1]) then
        windowView.floor = spot[1]
        windowView:Draw()
    end
    Pick(row.boss)
end

local function Icon(row, texture)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetTexture(texture, nil, nil, "TRILINEAR")
    return icon
end

-- Its place in the kill order (a tick once killed this run), its portrait, its name and
-- tag; on the right its quest mark and your BiS there.
local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.06)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(2)
    row.bar:Hide()
    row.number = ns.Font(row, 11, nil, T.muted)
    row.number:SetPoint("LEFT", ROW_PAD, 0)
    row.number:SetWidth(NUMBER_W)
    row.number:SetJustifyH("RIGHT")
    row.tick = Icon(row, St.CHECK)
    row.tick:SetPoint("CENTER", row.number, "CENTER", 2, 0)
    row.face = row:CreateTexture(nil, "ARTWORK")
    row.face:SetSize(FACE, FACE)
    row.face:SetPoint("LEFT", row.number, "RIGHT", ROW_GAP, 0)
    Round(row, row.face)
    row.name = ns.Font(row, 12, nil, T.fg)
    row.name:SetPoint("LEFT", row.face, "RIGHT", ROW_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.tag = ns.Font(row, 9, nil, T.muted)
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.star = Icon(row, St.STAR)
    row.star:SetVertexColor(St.BIS_RGB.r, St.BIS_RGB.g, St.BIS_RGB.b)
    row.bisText = ns.Font(row, 11, nil, T.fg)
    row.bisText:SetPoint("RIGHT", -4, 0)
    row.star:SetPoint("RIGHT", row.bisText, "LEFT", -2, 0)
    row.quest = Icon(row, St.BANG)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", RowClicked)
    return row
end

-- One draw's count and settings, for LegendRow (EachBoss's callback, made once).
local drawN, drawKilled, drawTotal, drawInside
local ROW_W = LEGEND_W - SCROLL_GAP
local NAME_ROOM = ROW_W - ROW_PAD - NUMBER_W - ROW_GAP - FACE - ROW_GAP - MARKS_W

local function LegendRow(boss, number, key)
        drawN = drawN + 1
        local n, width, inside = drawN, ROW_W, drawInside
        local row = rows[n] or NewRow(legend.child)
        rows[n] = row
        row.boss, row.key = boss, key
        row:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H)
        row.killed = inside and J.Kills.ThisRun(boss)
        if number then
            drawTotal = drawTotal + 1
            if row.killed then drawKilled = drawKilled + 1 end
        end
        row.number:SetText(number or "")
        row.number:SetShown(not row.killed)
        row.tick:SetShown(row.killed == true)
        local face = boss.model and SetPortraitTextureFromCreatureDisplayID
        if face then SetPortraitTextureFromCreatureDisplayID(row.face, boss.model) end
        row.face:SetShown(face ~= nil)
        row.name:SetWidth(0)
        row.name:SetText(boss.name)
        row.name:SetTextColor(row.killed and T.muted.r or T.fg.r, row.killed and T.muted.g or T.fg.g,
            row.killed and T.muted.b or T.fg.b)
        row.tag:SetText(boss.rare and "RARE" or boss.optional and "OPTIONAL" or boss.chest and "CHEST" or "")
        row.bis, row.haveBis = J.Loot.BossBis(boss)
        row.star:SetShown(row.bis > 0)
        row.bisText:SetText(row.bis > 0 and row.bis or "")
        row.quest:SetShown(quests[boss] ~= nil)
        row.quest:ClearAllPoints()
        row.quest:SetPoint("RIGHT", row.bis > 0 and row.star or row.bisText, "LEFT", -6, 0)
        row.name:SetWidth(math.min(math.ceil(row.name:GetStringWidth()) + 1, NAME_ROOM))
        row.bar:SetShown(boss == picked)
        row.hover:SetShown(boss == picked)
        row:Show()
end

local function DrawLegend()
    local dungeon = windowView.dungeon
    FillQuests(dungeon)
    drawN, drawKilled, drawTotal, drawInside = 0, 0, 0, windowView.inside
    EachBoss(dungeon, LegendRow)
    for i = drawN + 1, #rows do rows[i]:Hide() end
    legend.child:SetSize(ROW_W, math.max(1, drawN * ROW_H))
    legend.title:SetText("BOSSES" .. (drawInside and drawTotal > 0
        and ns.Color("muted", ("   %d of %d down"):format(drawKilled, drawTotal)) or ""))
end

local function WindowDrawn()
    window.title:SetText(windowView.dungeon.name:upper()
        .. (placing and ns.Color("muted", "   PLACING PINS") or ""))
    window.copy:SetShown(placing)
    if not Folded() then DrawLegend() end
end

-- The map's own height, and under it, unless folded, the legend and the loot: exactly as
-- tall as the window it was opened beside, so their edges line up; with none, LOWER_MIN.
local MAP_PART = PANEL_HEADER + MAP_H * WINDOW_SCALE + FLOOR_H + PANEL_PAD * 2

local function Size(owner)
    local folded = Folded()
    legend:SetShown(not folded)
    window.lootScroll:SetShown(not folded)
    window.hint:SetShown(not folded and picked == nil)
    window.fold:SetRotation(folded and 0 or -math.pi / 2)
    if folded then
        window:SetHeight(MAP_PART)
    else
        window:SetHeight(owner and owner:GetHeight() or MAP_PART + LOWER_GAP + LOWER_MIN)
    end
end

-- Back to the Journal, on the dungeon's page: the Naowh mark in the title, or the name.
local function OpenJournalPage()
    if windowView.dungeon then ns.OpenJournalWindow(windowView.dungeon) end
end

local function JournalEnter(button)
    if button.icon then button.icon:SetAlpha(1) end
    window.title:SetTextColor(T.accent.r, T.accent.g, T.accent.b)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Open in the Dungeon Journal", 1, 1, 1)
    GameTooltip:AddLine("Its page: quests, bosses and loot.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function JournalLeave(button)
    if button.icon then button.icon:SetAlpha(0.8) end
    window.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Hide()
end

local function FoldEnter(button)
    button.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Folded() and "Show the bosses" or "Map only", 1, 1, 1)
    GameTooltip:AddLine(Folded() and "The bosses in kill order and their loot, under the map."
        or "Folds the bosses and their loot away: the map alone, to keep on screen.",
        T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function FoldLeave(button)
    button.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Hide()
end

local function FoldClicked(button)
    ns.AccountSettings().journalMapFolded = not Folded() or nil
    Size(window.owner)
    if not Folded() then
        DrawLegend()
        Pick(picked)
    end
    FoldEnter(button)
end

local function Build()
    window = J.View.Parts.Panel("", true)
    window:SetSize(MAP_W * WINDOW_SCALE + PANEL_PAD * 2, PANEL_HEADER + MAP_H * WINDOW_SCALE + FLOOR_H + PANEL_PAD * 2)
    window.backdrop:Card(4, PANEL_HEADER, 4, 4)
    window.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    ns.AllowOffscreen(window)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    windowView = NewView(window, window, true)
    window:HookScript("OnHide", function() ViewHidden(windowView) end)
    windowView.scale = WINDOW_SCALE
    windowView.onDraw = WindowDrawn
    local canvas = windowView.canvas
    canvas:SetScale(WINDOW_SCALE)
    canvas:SetPoint("TOPLEFT", PANEL_PAD / WINDOW_SCALE, -PANEL_HEADER / WINDOW_SCALE)
    -- The floor switch and Copy on a line under the map.
    local underMap = -(PANEL_HEADER + MAP_H * WINDOW_SCALE + UNDER_MAP_GAP)
    windowView.down:SetPoint("TOPLEFT", PANEL_PAD, underMap)
    window.copy = ns.Button(window, "Copy", COPY_W, FLOOR_H - 2, function() Copy(windowView.dungeon) end)
    window.copy:SetPoint("TOPRIGHT", -PANEL_PAD, underMap)
    -- Folded, the loot pane is away: a pin opens its loot at the mouse instead.
    windowView.onPick = function(boss)
        if not Folded() then return Pick(boss) end
        lootFrom = windowView
        windowView:Pick(KeyOf(boss))
        J.View.OpenBossLoot(boss, windowView.dungeon)
    end
    windowView.onPinHover = Light
    -- Under them, the legend on the left and the picked boss's loot on the right.
    local lowerTop = -(MAP_PART - PANEL_PAD + LOWER_GAP)
    legend = CreateFrame("Frame", nil, window)
    legend:SetPoint("TOPLEFT", PANEL_PAD, lowerTop)
    legend:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD)
    legend:SetWidth(LEGEND_W)
    legend.title = ns.Font(legend, 12, nil, T.accentSoft)
    legend.title:SetPoint("TOPLEFT", 0, 0)
    local list = ns.UI.SlimScroll(legend)
    list:SetPoint("TOPLEFT", 0, -20)
    list:SetPoint("BOTTOMRIGHT")
    legend.child = CreateFrame("Frame", nil, list)
    list:SetScrollChild(legend.child)
    local lootScroll = ns.UI.SlimScroll(window)
    lootScroll:SetPoint("TOPLEFT", PANEL_PAD + LEGEND_W + LOWER_GAP, lowerTop)
    lootScroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, PANEL_PAD)
    lootView = J.View.New(lootScroll)
    lootView:SetWidth(MAP_W * WINDOW_SCALE - LEGEND_W - LOWER_GAP - SCROLL_GAP)
    lootScroll:SetScrollChild(lootView)
    window.lootScroll = lootScroll
    window.hint = ns.Font(window, 12, nil, T.muted)
    window.hint:SetPoint("CENTER", lootScroll, "CENTER", 0, 0)
    window.hint:SetText("Click a boss for its loot.")
    -- The chevron: fold the part under the map away, or open it.
    local fold = CreateFrame("Button", nil, window)
    fold:SetSize(PIN_BUTTON, PIN_BUTTON)
    fold.icon = fold:CreateTexture(nil, "ARTWORK")
    fold.icon:SetTexture(St.ARROW, nil, nil, "TRILINEAR")
    fold.icon:SetSize(PIN_ICON, PIN_ICON)
    fold.icon:SetPoint("CENTER")
    fold.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    fold:SetScript("OnEnter", FoldEnter)
    fold:SetScript("OnLeave", FoldLeave)
    fold:SetScript("OnClick", FoldClicked)
    window.fold = fold.icon
    local pin = CreateFrame("Button", nil, window)
    pin:SetSize(PIN_BUTTON, PIN_BUTTON)
    pin:SetPoint("RIGHT", window.close, "LEFT", -4, 0)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetTexture(St.PIN, nil, nil, "TRILINEAR")
    pin.icon:SetSize(PIN_ICON, PIN_ICON)
    pin.icon:SetPoint("CENTER")
    pin:SetScript("OnEnter", PinButtonEnter)
    pin:SetScript("OnLeave", PinButtonLeave)
    pin:SetScript("OnClick", PinButtonClicked)
    PaintPin(pin)
    window.pin = pin
    fold:SetPoint("RIGHT", pin, "LEFT", -2, 0)
    local journal = CreateFrame("Button", nil, window)
    journal:SetSize(PIN_BUTTON, PIN_BUTTON)
    journal:SetPoint("RIGHT", fold, "LEFT", -2, 0)
    journal.icon = journal:CreateTexture(nil, "ARTWORK")
    journal.icon:SetTexture(St.LOGO_SMALL, nil, nil, "TRILINEAR")
    journal.icon:SetSize(PIN_ICON, PIN_ICON)
    journal.icon:SetPoint("CENTER")
    journal.icon:SetAlpha(0.8)
    journal:SetScript("OnEnter", JournalEnter)
    journal:SetScript("OnLeave", JournalLeave)
    journal:SetScript("OnClick", OpenJournalPage)
    window.title:SetPoint("RIGHT", -34 - PIN_BUTTON * 3 - 8, 0)
    -- The name does the same; dragging it still moves the window.
    local name = CreateFrame("Button", nil, window)
    name:SetPoint("TOPLEFT", window.title, "TOPLEFT", -4, 4)
    name:SetPoint("BOTTOMRIGHT", window.title, "BOTTOMRIGHT", 0, -4)
    name:RegisterForDrag("LeftButton")
    name:SetScript("OnDragStart", function() window:StartMoving() end)
    name:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    name:SetScript("OnEnter", JournalEnter)
    name:SetScript("OnLeave", JournalLeave)
    name:SetScript("OnClick", OpenJournalPage)
end

-------------------------------------------------------------------------------
--  On the world map
-------------------------------------------------------------------------------
local OVERLAY_LEVEL = 50   -- over the map's picture, under its own buttons' strata
local HINT_PAD = 10
local BAR_H = 28           -- the strip along the map's foot: the floor switch and the hint
local BAR_ALPHA = 0.55
local overlay, overlayView

-- Right-click: up to the zone the dungeon is in, as the world map goes up a level. In combat
-- the map is not moved (the game keeps it from addons then): the world shows instead.
local function UpToZone()
    overlay:Hide()
    local entrance = overlayView.dungeon.entrance
    if entrance and not InCombatLockdown() then C_Map.OpenWorldMap(entrance.map) end
end

local function OverlayClicked(_, button)
    if button == "RightButton" then UpToZone() end
end

-- The whole picture: as big as it fits, in the middle (the art is the map's own shape, so
-- nothing or little shows round it); the floor switch and the hint over its foot.
local function Fit()
    local w, h = overlay:GetWidth(), overlay:GetHeight()
    local scale = math.max(0.1, math.min(w / MAP_W, h / MAP_H))
    overlayView.scale = scale
    overlayView.canvas:SetScale(scale)
    overlayView.canvas:ClearAllPoints()
    overlayView.canvas:SetPoint("CENTER", overlay, "CENTER", 0, 0)
end

local function BuildOverlay()
    local map = WorldMapFrame
    -- The map's picture, where the client has it as the mainline map does; else the map.
    local picture = type(map.ScrollContainer) == "table" and map.ScrollContainer or map
    overlay = CreateFrame("Frame", nil, map)
    overlay:SetAllPoints(picture)
    overlay:SetFrameLevel(picture:GetFrameLevel() + OVERLAY_LEVEL)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)   -- the picture under it does not zoom
    overlay:SetScript("OnMouseUp", OverlayClicked)
    overlay:SetScript("OnMouseWheel", function() end)
    ns.Solid(overlay, "BACKGROUND", { r = 0, g = 0, b = 0 }, 1):SetAllPoints()
    -- The strip over the map's foot, above the art and its pins: the switch and the hint.
    local bar = CreateFrame("Frame", nil, overlay)
    bar:SetPoint("BOTTOMLEFT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetHeight(BAR_H)
    ns.Solid(bar, "BACKGROUND", { r = 0, g = 0, b = 0 }, BAR_ALPHA):SetAllPoints()
    overlayView = NewView(overlay, bar, false)
    bar:SetFrameLevel(overlayView.canvas:GetFrameLevel() + 20)
    overlay:SetScript("OnHide", function() ViewHidden(overlayView) end)
    overlayView.onRightClick = UpToZone
    overlayView.onWorldMap = true
    overlayView.down:SetPoint("LEFT", HINT_PAD, 0)
    overlay.hint = ns.Font(bar, 12, nil, T.fg)
    overlay.hint:SetPoint("RIGHT", -HINT_PAD, 0)
end

-- The map panel's say: the dungeon to show on the world map (it is open, inside one), or
-- nil to hide it.
---@param dungeon? JournalDungeon
function J.ShowMapOnWorldMap(dungeon)
    if not (dungeon and J.Maps[dungeon.key]) then
        if overlay then overlay:Hide() end
        return
    end
    if not overlay then BuildOverlay() end
    -- Drawn again on the same dungeon (a setting, the panel placed again, a pin's boss page):
    -- its boss stays picked and its floor stays.
    local same = overlay:IsShown() and overlayView.dungeon == dungeon
    local keep, floor = same and overlayView.picked or nil, same and overlayView.floor or nil
    overlayView:Open(dungeon)
    overlayView.picked = keep
    if floor and overlayView:FloorAt(floor) then overlayView.floor = floor end
    overlay.hint:SetText(dungeon.entrance and dungeon.zone and ("Right-click: " .. dungeon.zone) or "")
    overlay:Show()
    overlay.mapID = WorldMapFrame:GetMapID()   -- the map it covers; another one, and it steps aside
    Fit()
    overlayView:Draw()
end

-- The map shown on the world map changed (its own buttons, its dropdown, a right-click up to
-- the zone): the dungeon's map steps aside for it. Map on the panel beside it brings it back.
function J.WorldMapChanged()
    if overlay and overlay:IsShown() and WorldMapFrame:GetMapID() ~= overlay.mapID then overlay:Hide() end
end

-- Whether the dungeon's map stepped aside on an open world map (the panel offers Map then).
function J.DungeonMapAway()
    return overlay ~= nil and not overlay:IsShown() and WorldMapFrame:IsShown()
end

-- A kill was counted: the maps showing tick and dim it.
function J.RedrawDungeonMaps()
    if window and window:IsShown() then windowView:Draw() end
    if overlay and overlay:IsShown() then overlayView:Draw() end
end

-- The key's Boss Loot opens its own, or the loot at the mouse closed: the map no longer
-- closes it, and the window's pin loses its gold ring (the world map's follows the Journal
-- beside it, which still shows the boss).
function J.View.ForgetMapLoot()
    if lootFrom and not lootFrom.onWorldMap then lootFrom:Pick(nil) end
    lootFrom = nil
end

-- The Journal beside the world map went back to the dungeon's page: no pin is picked.
function J.UnpickOnWorldMap()
    if overlayView then overlayView:Pick(nil) end
end

-- The world map changed size (maximised, or small again).
function J.FitMapOnWorldMap()
    -- Small again: the loot a pin opened at the mouse goes, the Journal beside it has it; its
    -- pin stays ringed.
    if overlayView and lootFrom == overlayView and not WorldMapFrame:IsMaximized() then
        lootFrom = nil
        J.View.CloseBossLoot()
    end
    if overlay and overlay:IsShown() then
        Fit()
        overlayView:Draw()
    end
end

-------------------------------------------------------------------------------
--  Opening
-------------------------------------------------------------------------------
-- Opens the map of the dungeon: from the panel beside the world map, on the world map; else
-- in the window, beside the window holding from. On the dungeon the window shows already,
-- it closes.
---@param dungeon JournalDungeon
---@param from? Frame what Map was clicked on
function J.OpenDungeonMap(dungeon, from)
    if not J.Maps[dungeon.key] then return end
    local owner = from and Owner(from)
    if owner and owner.onWorldMap then return J.ShowMapOnWorldMap(dungeon) end
    if not window then Build() end
    if window:IsShown() and windowView.dungeon == dungeon then
        window:Hide()
        return
    end
    windowView:Open(dungeon)
    Paint()
    Place(from)
    window.owner = from and Owner(from)
    Size(window.owner)
    window:Show()
    window:Raise()
    -- The boss to go for next: the first in kill order not killed this run.
    picked = nil
    windowView:Draw()
    if not Folded() then
        EachBoss(dungeon, function(boss, number)
            if not picked and number and not (windowView.inside and J.Kills.ThisRun(boss)) then picked = boss end
        end)
        Pick(picked)
    end
end

-- What the window shows, drawn again (a test, a setting).
function J.DrawDungeonMap()
    if window and window:IsShown() then windowView:Draw() end
end

-------------------------------------------------------------------------------
--  /nf mappins and /nf mapcheck
-------------------------------------------------------------------------------
local probe

-- Which floors of each map's art the client has: a file the client holds has an ID, one it
-- does not has none (SetTexture's own answer is true either way, measured 2 Oct 2026).
local function MapCheck()
    probe = probe or CreateFrame("Frame"):CreateTexture()
    local seen = {}
    for key, map in pairs(J.Maps) do
        if map.image then
            ns.Print(("%s: the addon's own picture, until the game has art for it"):format(key))
        elseif not seen[map.art] then
            seen[map.art] = true
            local found = {}
            for n = 1, 10 do
                probe:SetTexture(ART:format(map.art, map.art, n, 1))
                local id = probe:GetTextureFileID()
                if type(id) == "number" and id > 0 then found[#found + 1] = n end
            end
            ns.Print(("%s (%s): %s, data says %d"):format(map.art, key,
                #found > 0 and "floors " .. table.concat(found, ",") or "no art", map.floors))
        end
    end
    probe:SetTexture(nil)
    ns.Print(("Portraits: %s. Your position in here: %s."):format(
        SetPortraitTextureFromCreatureDisplayID and "yes" or "no",
        UnitPosition("player") and "yes" or "no"))
end

function ns.DungeonMapCommand(cmd)
    if cmd == "mapcheck" then return MapCheck() end
    placing = not placing
    ns.Print(placing and "Placing map pins: drag them, then Copy. /nf mappins again to stop."
        or "Placing map pins: off.")
    if window and window:IsShown() then
        windowView:FillFloors()
        windowView:Draw()
    end
end

-- The Journal switched off: the maps go with it. Its Opacity: the window follows.
S.OnChange(function(key)
    if key == "enabled" and not S.Get("enabled") then
        if window then window:Hide() end
        if overlay then overlay:Hide() end
    elseif key == "mapAlpha" and window then
        Paint()
    end
end)
