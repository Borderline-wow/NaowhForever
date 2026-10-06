-------------------------------------------------------------------------------
--  UI/DungeonMap.lua -- a dungeon's map: the game's own map art of the dungeon (Data/Maps.lua),
--  or, for one the game has no art for yet, a picture the addon ships (image), with its
--  maker's credit in the map's corner; its bosses as round portraits where they stand, each
--  with its place in the kill order, and the entrance (its label on a side clear of the pins
--  and the map's edge, or none when every side is taken). Hover a boss for its name, click it
--  for its loot; a dungeon on several floors has a switch under the map. It shows in two
--  places, each a view of its own:
--
--  - A window, from Map on a dungeon page's Bosses title: in front of the window that holds
--    the page, beside it where the screen has room (else over its top right), as tall as it.
--    The floor switch has a line under the map only with several floors (or Copy, placing).
--    Under the map, the bosses in kill order as a grid of equal chips, up to five across and
--    the full width (hover one to light its pin, a pin to light its chip; past ten they show
--    only their number and portrait, spread across), each with a tick once killed this run
--    (and its pin dimmed, and the run's count in the title), a quest mark where a quest in
--    your log needs it, your BiS there, and the tag of one with no number (RARE, QUEST...).
--    Under the strip, the page of the boss picked (a pin or a chip), compact, to read
--    at a glance (View's DrawBossPage): its name and level on one line, Naowh's tip, its loot
--    and its abilities side by side (what each ability does on two lines while the page has
--    the room, else one), its quests; it scrolls only when it must. The chevron in
--    its title folds that part away, for the map alone (kept for the account), and a pin
--    then opens its loot at the mouse. It closes with that window unless pinned (the pin in
--    its title, kept for the account too); the Naowh mark in its title, or its name, opens
--    the Dungeon Journal on the dungeon's page again.
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
--  Nothing is made until a map is first shown, and it listens to nothing: the window draws
--  again on a pick, a kill, a setting, and its page on the item or spell data it waits on.
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
local MAP_SHOWN_H = MAP_H * WINDOW_SCALE
local PAGE_W = MAP_W * WINDOW_SCALE
local CHIP_H = 24
local CHIP_FACE = 18
local CHIP_PAD = 6
local CHIP_PART_GAP = 4
local CHIP_NAME_GAP = 6
local CHIP_STAR_GAP = 2
local CHIP_NUMBER_W = 14
local CHIP_MARK = 13
local CHIP_FILL = 0.04
local CHIP_GAP = St.CHIP_GAP
local STRIP_COLUMNS, STRIP_ROWS = 5, 2
local COMPACT_W = CHIP_PAD * 2 + CHIP_NUMBER_W + CHIP_PART_GAP + CHIP_FACE + 2
local TAG_SHORT = { RARE = "R", OPTIONAL = "O", QUEST = "Q", CHEST = "C" }
local LABEL_GAP = 4
local LABEL_CLEAR = 8
local LABEL_SIDES = { "RIGHT", "LEFT", "BELOW", "ABOVE" }
local DOWN_KEY = 100
local LOWER_GAP = 10
local STRIP_GAP = 8
local LOWER_MIN = 292
local SCROLL_GAP = 16
local UNDER_MAP_GAP = 6          -- the map to the floor switch's line
local KILLED_ALPHA = 0.45        -- a pin killed this run, on the map
local UNPLACED_ALPHA = 0.7       -- placing: a pin waiting along the top
-- The picked pin's ring and its glow: gold, or the theme's Accent once the player picked one.
local PICKED_RGB = St.PICKED_RGB
local PICKED_RING = 8            -- the ring round the picked pin's portrait, edge to edge
local PICKED_GLOW = 24           -- and the glow pulsing round it
local GLOW_LOW, GLOW_HIGH, GLOW_PULSE = 0.15, 0.55, 0.9
local TAG_WORDS = { RARE = "Rare", OPTIONAL = "Optional", QUEST = "Quest boss", CHEST = "Chest" }
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
-- optional or quest boss and a chest have none); fn(boss, number, key).
local function EachBoss(dungeon, fn)
    for _, wing in ipairs(dungeon.wings) do
        local number = 0
        for _, boss in ipairs(wing.bosses) do
            local key = KeyOf(boss)
            local ordered = J.Numbered(boss)
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
    local tag = J.BossTag(boss)
    if tag then GameTooltip:AddLine(TAG_WORDS[tag], T.muted.r, T.muted.g, T.muted.b) end
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
    -- Lit while its chip under the map is hovered: the accent, round, just outside its ring.
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
    pin.atX = here and spot[2] * MAP_W or nil
    pin.atY = here and spot[3] * MAP_H or nil
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

local function LabelBox(side, cx, cy, w, h)
    local half = ENTRANCE / 2
    if side == "RIGHT" then return cx + half + LABEL_GAP, cy - h / 2 end
    if side == "LEFT" then return cx - half - LABEL_GAP - w, cy - h / 2 end
    if side == "BELOW" then return cx - w / 2, cy + half + LABEL_GAP end
    return cx - w / 2, cy - half - LABEL_GAP - h
end

function View:LabelFree(left, top, w, h)
    if left < 0 or top < 0 or left + w > MAP_W or top + h > MAP_H then return false end
    local reach = PIN / 2 + LABEL_CLEAR
    for i = 1, self.used do
        local pin = self.pins[i]
        local x, y = pin.atX, pin.atY
        if x and left < x + reach and left + w > x - reach and top < y + reach and top + h > y - reach then
            return false
        end
    end
    return true
end

local LABEL_ANCHOR = {
    RIGHT = { "LEFT", "RIGHT", LABEL_GAP, 0 }, LEFT = { "RIGHT", "LEFT", -LABEL_GAP, 0 },
    BELOW = { "TOP", "BOTTOM", 0, -LABEL_GAP }, ABOVE = { "BOTTOM", "TOP", 0, LABEL_GAP },
}

function View:PlaceDoorLabel(cx, cy)
    local text = self.door.text
    local w, h = math.ceil(text:GetStringWidth()), math.ceil(text:GetStringHeight())
    local side
    for i = 1, #LABEL_SIDES do
        local left, top = LabelBox(LABEL_SIDES[i], cx, cy, w, h)
        if self:LabelFree(left, top, w, h) then
            side = LABEL_SIDES[i]
            break
        end
    end
    self.door.side = side
    text:SetShown(side ~= nil)
    if not side then return end
    local anchor = LABEL_ANCHOR[side]
    text:ClearAllPoints()
    text:SetPoint(anchor[1], self.door, anchor[2], anchor[3], anchor[4])
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
        self:PlaceDoorLabel(door[2] * MAP_W, door[3] * MAP_H)
    elseif self:Placing() then
        self.door:ClearAllPoints()
        self.door:SetPoint("TOPRIGHT", self.canvas, "TOPRIGHT", -8, -8)
        self:PlaceDoorLabel(MAP_W - 8 - ENTRANCE / 2, 8 + ENTRANCE / 2)
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
--  Under the map: the bosses as a strip of chips, and the picked boss's page
-------------------------------------------------------------------------------
local strip, page, lootView, picked
local chips = {}
local quests = {}   -- boss -> what your quests need of it, filled each draw: { text, done }

local function Folded()
    return ns.AccountSettings().journalMapFolded == true
end

local function FloorLine()
    return #windowView.floors > 1 or placing
end

local function MapFoot()
    return PANEL_HEADER + MAP_SHOWN_H + (FloorLine() and UNDER_MAP_GAP + FLOOR_H or 0)
end

local function PageRoom()
    return window:GetHeight() - MapFoot() - LOWER_GAP - strip:GetHeight() - STRIP_GAP - PANEL_PAD
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

local function ChipOf(key)
    for _, chip in ipairs(chips) do
        if chip:IsShown() and chip.key == key then return chip end
    end
end

local function PaintChip(chip)
    local on = chip.boss == picked
    chip.fill:SetShown(on)
    chip.line:SetShown(on)
    chip.hover:SetShown(chip.lit == true and not on)
    local color = chip.killed and not on and T.muted or T.fg
    chip.name:SetTextColor(color.r, color.g, color.b)
end

-- A chip hovered lights its pin; a pin hovered lights its chip.
local function Light(key, on)
    local pin = PinOf(key)
    if pin then pin.glow:SetShown(on) end
    local chip = ChipOf(key)
    if chip then
        chip.lit = on
        PaintChip(chip)
    end
end

local function Pick(boss)
    local again = boss == picked
    picked = boss
    windowView:Pick(boss and KeyOf(boss))
    for _, chip in ipairs(chips) do
        if chip:IsShown() then PaintChip(chip) end
    end
    window.hint:SetShown(boss == nil)
    if not boss then
        lootView:Hide()
        return
    end
    lootView:Show()
    if not again then page:SetVerticalScroll(0) end
    lootView.fitHeight = PageRoom()
    lootView:DrawBossPage(boss, windowView.dungeon)
end

local function PageDrawn(height)
    local scrolls = height > PageRoom()
    local want = scrolls and PAGE_W - SCROLL_GAP or PAGE_W
    if math.abs(lootView:GetWidth() - want) < 1 then return end
    page:SetPoint("BOTTOMRIGHT", -(PANEL_PAD + (scrolls and SCROLL_GAP or 0)), PANEL_PAD)
    lootView:SetWidth(want)
    lootView:Redraw()
end

local function ChipEnter(chip)
    Light(chip.key, true)
    local boss = chip.boss
    GameTooltip:SetOwner(chip, "ANCHOR_TOP")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    local tag = J.BossTag(boss)
    if tag then GameTooltip:AddLine(TAG_WORDS[tag], T.muted.r, T.muted.g, T.muted.b) end
    if chip.killed then GameTooltip:AddLine("Killed this run", St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b) end
    for _, need in ipairs(quests[boss] or {}) do
        GameTooltip:AddLine(need[1], 1, 0.82, 0)
        GameTooltip:AddLine("  " .. need[2], need[3] and T.muted.r or 1, need[3] and T.muted.g or 1,
            need[3] and T.muted.b or 1, true)
    end
    if chip.bis > 0 then
        GameTooltip:AddLine(("%d of your BiS, %d of them yours"):format(chip.bis, chip.haveBis),
            St.BIS_RGB.r, St.BIS_RGB.g, St.BIS_RGB.b)
    end
    if not Spot(windowView.dungeon, chip.key) then
        GameTooltip:AddLine("Not on the map yet.", T.muted.r, T.muted.g, T.muted.b)
    end
    GameTooltip:AddLine("Click for its loot.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function ChipLeave(chip)
    Light(chip.key, false)
    GameTooltip:Hide()
end

-- A click shows its page, and its floor on the map.
local function ChipClicked(chip)
    local spot = Spot(windowView.dungeon, chip.key)
    if type(spot) == "table" and spot[1] ~= windowView.floor and windowView:FloorAt(spot[1]) then
        windowView.floor = spot[1]
        windowView:Draw()
    end
    Pick(chip.boss)
end

local function Mark(chip, texture)
    local icon = chip:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CHIP_MARK, CHIP_MARK)
    icon:SetTexture(texture, nil, nil, "TRILINEAR")
    return icon
end

-- In the house's chip look (a faint fill in a 1px black edge): its place in the kill order (a
-- tick once killed this run), its portrait in a ring (black, muted for a boss with no number),
-- its name cut to fit and its tag; a quest mark and your BiS there after them. Compact, its
-- number (or its tag's letter) and portrait, in the middle.
local function NewChip()
    local chip = CreateFrame("Button", nil, strip)
    chip:SetHeight(CHIP_H)
    ns.Solid(chip, "BACKGROUND", T.fg, CHIP_FILL):SetAllPoints()
    chip.hover = ns.Solid(chip, "BACKGROUND", T.fg, St.HOVER)
    chip.hover:SetAllPoints()
    chip.fill = ns.Solid(chip, "BORDER", T.accent, St.TAB_FILL)
    chip.fill:SetAllPoints()
    chip.line = ns.Solid(chip, "ARTWORK", T.accent, 1)
    chip.line:SetPoint("BOTTOMLEFT")
    chip.line:SetPoint("BOTTOMRIGHT")
    chip.line:SetHeight(St.TAB_LINE)
    ns.Border(chip, St.BORDER_RGB)
    chip.number = ns.Font(chip, 11, nil, T.muted)
    chip.number:SetWidth(CHIP_NUMBER_W)
    chip.number:SetJustifyH("RIGHT")
    chip.tick = Mark(chip, St.CHECK)
    chip.tick:SetPoint("CENTER", chip.number, "CENTER", 0, 0)
    chip.ring = chip:CreateTexture(nil, "ARTWORK", nil, 1)
    chip.ring:SetSize(CHIP_FACE + 2, CHIP_FACE + 2)
    chip.ring:SetColorTexture(0, 0, 0, 1)
    Round(chip, chip.ring)
    chip.face = chip:CreateTexture(nil, "ARTWORK", nil, 2)
    chip.face:SetSize(CHIP_FACE, CHIP_FACE)
    chip.face:SetPoint("CENTER", chip.ring, "CENTER", 0, 0)
    Round(chip, chip.face)
    chip.name = ns.Font(chip, 12, nil, T.fg)
    chip.name:SetJustifyH("LEFT")
    chip.name:SetWordWrap(false)
    chip.tag = ns.Font(chip, 9, nil, T.muted)
    chip.quest = Mark(chip, St.BANG)
    chip.star = Mark(chip, St.STAR)
    chip.star:SetVertexColor(St.BIS_RGB.r, St.BIS_RGB.g, St.BIS_RGB.b)
    chip.bisText = ns.Font(chip, 11, nil, T.fg)
    chip:SetScript("OnEnter", ChipEnter)
    chip:SetScript("OnLeave", ChipLeave)
    chip:SetScript("OnClick", ChipClicked)
    return chip
end

local function PlacePart(part, x, gap, width)
    if x > CHIP_PAD then x = x + gap end
    part:ClearAllPoints()
    part:SetPoint("LEFT", part:GetParent(), "LEFT", x, 0)
    return x + width
end

local function MarksWidth(chip)
    local w = 0
    if chip.tagW > 0 then w = w + CHIP_PART_GAP + chip.tagW end
    if chip.needed then w = w + CHIP_NAME_GAP + CHIP_MARK end
    if chip.bis > 0 then w = w + CHIP_NAME_GAP + CHIP_MARK + CHIP_STAR_GAP + chip.bisW end
    return w
end

local function LayChip(chip, compact, width)
    local named = not compact or not chip.hasFace
    local short = compact and chip.short
    local slot = chip.numbered or chip.killed or short and true
    chip.number:SetText(short or chip.numberText)
    chip.number:SetShown(slot and not chip.killed)
    chip.tick:SetShown(chip.killed == true)
    chip.ring:SetShown(chip.hasFace)
    chip.face:SetShown(chip.hasFace)
    chip.name:SetShown(named)
    chip.tag:SetShown(named and chip.tagW > 0)
    chip.quest:SetShown(named and chip.needed)
    chip.star:SetShown(named and chip.bis > 0)
    chip.bisText:SetShown(named and chip.bis > 0)
    local x = CHIP_PAD
    if not named then
        local content = (slot and CHIP_NUMBER_W + CHIP_PART_GAP or 0) + CHIP_FACE + 2
        x = math.max(CHIP_PAD, math.floor((width - content) / 2))
        if slot then x = PlacePart(chip.number, x, 0, CHIP_NUMBER_W) + CHIP_PART_GAP end
        chip.ring:ClearAllPoints()
        chip.ring:SetPoint("LEFT", chip, "LEFT", x, 0)
        return
    end
    if slot then x = PlacePart(chip.number, x, 0, CHIP_NUMBER_W) end
    if chip.hasFace then x = PlacePart(chip.ring, x, CHIP_PART_GAP, CHIP_FACE + 2) end
    local room = width - CHIP_PAD - (x > CHIP_PAD and x + CHIP_NAME_GAP or x) - MarksWidth(chip)
    local nameW = math.max(1, math.min(chip.nameW, room))
    chip.name:SetWidth(nameW)
    x = PlacePart(chip.name, x, CHIP_NAME_GAP, nameW)
    if chip.tagW > 0 then x = PlacePart(chip.tag, x, CHIP_PART_GAP, chip.tagW) end
    if chip.needed then x = PlacePart(chip.quest, x, CHIP_NAME_GAP, CHIP_MARK) end
    if chip.bis > 0 then
        x = PlacePart(chip.star, x, CHIP_NAME_GAP, CHIP_MARK)
        PlacePart(chip.bisText, x, CHIP_STAR_GAP, chip.bisW)
    end
end

-- One draw's count and settings, for StripChip (EachBoss's callback, made once).
local drawN, drawKilled, drawTotal, drawInside

local function StripChip(boss, number, key)
    drawN = drawN + 1
    local chip = chips[drawN] or NewChip()
    chips[drawN] = chip
    chip.boss, chip.key, chip.lit = boss, key, false
    chip.killed = drawInside and J.Kills.ThisRun(boss) or false
    chip.numbered = number ~= nil
    if number then
        drawTotal = drawTotal + 1
        if chip.killed then drawKilled = drawKilled + 1 end
    end
    chip.numberText = number or ""
    local face = boss.model and SetPortraitTextureFromCreatureDisplayID
    if face then SetPortraitTextureFromCreatureDisplayID(chip.face, boss.model) end
    chip.hasFace = face ~= nil
    chip.face:SetDesaturated(chip.killed)
    chip.name:SetWidth(0)
    chip.name:SetText(boss.name)
    chip.nameW = math.ceil(chip.name:GetStringWidth()) + 1
    local tag = J.BossTag(boss)
    chip.short = tag and TAG_SHORT[tag]
    chip.tag:SetText(tag or "")
    chip.tagW = tag and math.ceil(chip.tag:GetStringWidth()) or 0
    local ring = tag and T.muted or St.BORDER_RGB
    chip.ring:SetColorTexture(ring.r, ring.g, ring.b, 1)
    chip.needed = quests[boss] ~= nil
    chip.bis, chip.haveBis = J.Loot.BossBis(boss)
    chip.bisText:SetText(chip.bis > 0 and chip.bis or "")
    chip.bisW = chip.bis > 0 and math.ceil(chip.bisText:GetStringWidth()) or 0
    PaintChip(chip)
    chip:Show()
end

local function Columns(n, most)
    local columns = math.max(1, math.min(n, most))
    local rows = math.ceil(n / columns)
    return math.ceil(n / rows), rows
end

local function Grid(compact)
    local most = compact and math.floor((PAGE_W + CHIP_GAP) / (COMPACT_W + CHIP_GAP)) or STRIP_COLUMNS
    local columns, rows = Columns(drawN, most)
    local step = (PAGE_W + CHIP_GAP) / columns
    for i = 1, drawN do
        local chip = chips[i]
        local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local left = math.floor(column * step + 0.5)
        local width = math.floor((column + 1) * step + 0.5) - CHIP_GAP - left
        chip:SetWidth(width)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", left, -row * (CHIP_H + CHIP_GAP))
        LayChip(chip, compact, width)
    end
    return rows
end

local downTexts = {}

local function DownText(killed, total)
    local key = killed * DOWN_KEY + total
    local text = downTexts[key]
    if not text then
        text = ns.Color("muted", ("   %d of %d down"):format(killed, total))
        downTexts[key] = text
    end
    return text
end

local function DrawStrip()
    local dungeon = windowView.dungeon
    FillQuests(dungeon)
    drawN, drawKilled, drawTotal, drawInside = 0, 0, 0, windowView.inside
    EachBoss(dungeon, StripChip)
    for i = drawN + 1, #chips do chips[i]:Hide() end
    local rows = Grid(drawN > STRIP_COLUMNS * STRIP_ROWS)
    strip:SetHeight(rows * CHIP_H + (rows - 1) * CHIP_GAP)
    return drawInside and drawTotal > 0 and DownText(drawKilled, drawTotal) or ""
end

-- The map, and under it, unless folded, the strip and the page: exactly as tall as the window
-- it was opened beside, so their edges line up; with none, LOWER_MIN under the map.
local function Size(owner)
    local folded = Folded()
    local foot = MapFoot()
    strip:SetShown(not folded)
    page:SetShown(not folded)
    window.hint:SetShown(not folded and picked == nil)
    window.fold:SetRotation(folded and 0 or -math.pi / 2)
    strip:SetPoint("TOPLEFT", PANEL_PAD, -(foot + LOWER_GAP))
    if folded then
        window:SetHeight(foot + PANEL_PAD)
    else
        window:SetHeight(owner and owner:GetHeight() or foot + LOWER_GAP + LOWER_MIN)
    end
end

local function WindowDrawn()
    Size(window.owner)
    local down = not Folded() and DrawStrip() or ""
    window.title:SetText(windowView.dungeon.name:upper() .. down
        .. (placing and ns.Color("muted", "   PLACING PINS") or ""))
    window.copy:SetShown(placing)
    if picked and not Folded() then PageDrawn(lootView:GetHeight()) end
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
    WindowDrawn()
    if not Folded() then Pick(picked) end
    FoldEnter(button)
end

local function Build()
    window = J.View.Parts.Panel("", true)
    window:SetSize(PAGE_W + PANEL_PAD * 2, PANEL_HEADER + MAP_SHOWN_H + PANEL_PAD)
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
    -- The floor switch and Copy on a line under the map, while it has a use (FloorLine).
    local underMap = -(PANEL_HEADER + MAP_SHOWN_H + UNDER_MAP_GAP)
    windowView.down:SetPoint("TOPLEFT", PANEL_PAD, underMap)
    window.copy = ns.Button(window, "Copy", COPY_W, FLOOR_H - 2, function() Copy(windowView.dungeon) end)
    window.copy:SetPoint("TOPRIGHT", -PANEL_PAD, underMap)
    -- Folded, the page is away: a pin opens its loot at the mouse instead.
    windowView.onPick = function(boss)
        if not Folded() then return Pick(boss) end
        lootFrom = windowView
        windowView:Pick(KeyOf(boss))
        J.View.OpenBossLoot(boss, windowView.dungeon)
    end
    windowView.onPinHover = Light
    -- Under them, the strip of bosses (placed by Size), and under it the picked boss's page.
    strip = CreateFrame("Frame", nil, window)
    strip:SetSize(PAGE_W, CHIP_H)
    page = ns.UI.SlimScroll(window)
    page:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -STRIP_GAP)
    page:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_PAD)
    lootView = J.View.New(page)
    lootView:SetWidth(PAGE_W)
    lootView.onResize = PageDrawn
    page:SetScrollChild(lootView)
    window.hint = ns.Font(window, 12, nil, T.muted)
    window.hint:SetPoint("CENTER", page, "CENTER", 0, 0)
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
        local next
        EachBoss(dungeon, function(boss, number)
            if not next and number and not (windowView.inside and J.Kills.ThisRun(boss)) then next = boss end
        end)
        Pick(next)
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

-- The Journal switched off: the maps go with it. Its Opacity: the window follows. Any other
-- setting (a filter, BiS): the strip and the page are drawn again, the page once for a burst.
S.OnChange(function(key)
    if key == "enabled" and not S.Get("enabled") then
        if window then window:Hide() end
        if overlay then overlay:Hide() end
    elseif key == "mapAlpha" and window then
        Paint()
    elseif window and window:IsShown() then
        windowView:Draw()
        if picked and not Folded() then lootView:QueueRedraw() end
    end
end)
