-------------------------------------------------------------------------------
--  UI/DungeonMap.lua -- a dungeon's map: the game's own map art of the dungeon (Data/Maps.lua),
--  or, for one the game has no art for yet, a picture the addon ships (image), with its
--  maker's credit in the map's corner; its bosses where they stand, each as its mark: its
--  round portrait (a chest's icon), with its place in the kill order on a small badge (a
--  muted R, O or Q for a rare, optional or quest boss, in a muted ring; a tick, and the mark
--  dimmed, once killed this run); and the entrance (its label on a side clear of the pins
--  and the map's edge, or none when every side is taken). Hover a boss for its name, click it
--  for its loot; a dungeon on several floors has a switch under the map. It shows in two
--  places, each a view of its own:
--
--  - A window, from Map on a dungeon page's Bosses title: in front of the window that holds
--    the page, beside it where the screen has room (else over its top right), as tall as it.
--    The floor switch has a line under the map only with several floors (or Copy, placing).
--    Beside the map on its right, as tall as it, the bosses in a list in kill order under
--    BOSSES and their count, by wing under each wing's name where the dungeon has several:
--    each row its pin's own mark, smaller, its name (lined up, cut to fit), the tag of one
--    with no number (RARE, QUEST...), and at its right edge a quest mark where a quest in
--    your log needs it and your BiS there. Hover a row to light its pin, a pin to light its
--    row; picked, both are ringed alike and the row filled; it scrolls when longer than the
--    map, to keep the picked row in sight. The run's count is in the title.
--    Under the map and the list, the page of the boss picked (a pin or a row), compact, to
--    read at a glance (View's DrawBossPage): its name and level on one line, Naowh's tip,
--    its loot and its abilities side by side (what each ability does on two lines while the
--    page has the room, else one), its quests; it scrolls only when it must. The chevron in
--    its title folds the page away, for the map and the list alone (kept for the account),
--    and a pin or a row then opens its loot at the mouse. It closes with that window unless pinned (the pin in
--    its title, kept for the account too); the Naowh mark in its title, or its name, opens
--    the Dungeon Journal on the dungeon's page again.
--  - The world map: press M inside a dungeon and its map fills the map's picture, while the
--    Journal sits beside the map (UI/MapPanel.lua says when: it already watches the map).
--    Right-click goes up to the zone the dungeon is in, as the world map goes up a level;
--    Map on the panel beside it brings it back.
--
--  Where the bosses stand is placed by hand. /nf mappins turns placing on in the window:
--  every boss gets a pin to drag (those not placed yet, or on another floor, wait along the
--  top; a right-click takes one off its floor), the entrance too, and Copy gives the
--  dungeon's line for Data/Maps.lua. What you place is kept for the account until then, and
--  shown over the data. /nf mapcheck prints which map art and floors the client has. The
--  switch only offers the floors something stands on, once anything is placed, in the order
--  you walk them: the art has floors with nothing of the dungeon on them (Shadowfang Keep's
--  fifth). Placing, or before anything is placed, it offers them all (a map's order, where
--  it has one). A floor the art lacks is the addon's own picture.
--
--  The window follows the Journal it was opened beside: another dungeon's page there shows
--  that dungeon's map (one with no map closes it).
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
local BADGE_IN = 6
local BADGE_SIZE = 11
local BADGE_TICK = 14
local BADGE_ALPHA = 0.9
local BIG_SIZE = 18
local LIT_RING, LIT_ALPHA = 12, 0.9
local ENTRANCE = 28
local TRAY_STEP = PIN + 10       -- placing: the pins not placed yet, along the top
local TRAY_ROW = math.floor((MAP_W - 16) / TRAY_STEP)   -- that many to a row, across the map
local FLOOR_H = 22               -- the floor switch under the map
local FLOOR_STEP_W = 22
local COPY_W = 52
local PIN_BUTTON = 20            -- the window's pin, beside its close button
local PIN_ICON = 14
local MAP_SHOWN_H = MAP_H * WINDOW_SCALE
local MAP_SHOWN_W = MAP_W * WINDOW_SCALE
local LIST_W = 210
local LIST_GAP = 10
local LIST_BAR, LIST_BAR_GAP = 4, 4
local PAGE_W = MAP_SHOWN_W + LIST_GAP + LIST_W
local LIST_ROW_H = 28
local LIST_SCALE = 0.52
local LIST_BADGE_GROW = 1.2
local ROW_PAD = 4
local ROW_NAME_X = 36
local ROW_TAG_GAP = 5
local ROW_STAR_GAP = 2
local ROW_MARK_GAP = 6
local ROW_ICON = 13
local WING_SIZE = 9
local WING_H = 20
local WING_BOTTOM = 4
local TAG_SHORT = { RARE = "R", OPTIONAL = "O", QUEST = "Q" }
local LABEL_GAP = 4
local LABEL_CLEAR = 8
local LABEL_SIDES = { "RIGHT", "LEFT", "BELOW", "ABOVE" }
local DOWN_KEY = 100
local LOWER_GAP = St.BOSS_PAGE_GAP
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
--  Where a pin stands: what was placed on this account while placing, else the data.
--  Taken off while placing (right-click), it is kept as false: on no floor, whatever the data says.
-------------------------------------------------------------------------------
local function Placed(dungeon)
    local all = ns.AccountSettings().journalMapPins
    return type(all) == "table" and all[dungeon.key] or nil
end

local function Spot(dungeon, key)
    local placed = Placed(dungeon)
    local spot = placed and placed[key]
    if type(spot) == "table" then return spot end
    if spot == false then return nil end
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
-- optional or quest boss and a chest have none); fn(boss, number, key, wing).
local function EachBoss(dungeon, fn)
    for _, wing in ipairs(dungeon.wings) do
        local number = 0
        for _, boss in ipairs(wing.bosses) do
            local key = KeyOf(boss)
            local ordered = J.Numbered(boss)
            if ordered then number = number + 1 end
            if key then fn(boss, ordered and number or nil, key, wing) end
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
    local hint = "Click for its loot."
    if pin.view:Placing() then
        hint = pin.elsewhere and ("On %s: drag it here to move it."):format(pin.elsewhere)
            or Spot(pin.view.dungeon, pin.key) and "Drag to move it, right-click to take it off."
            or "Drag to place it."
    end
    GameTooltip:AddLine(hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
    if pin.view.onPinHover then pin.view.onPinHover(pin.key, true) end
end

local function PinLeave(pin)
    GameTooltip:Hide()
    if pin.view.onPinHover then pin.view.onPinHover(pin.key, false) end
end

local function PinClicked(pin, button)
    -- Placing, a right-click takes the pin off its floor, back along the top.
    if button == "RightButton" and pin.view:Placing() then
        Keep(pin.view.dungeon, pin.key, false)
        GameTooltip:Hide()
        pin.view:Draw()
        return
    end
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

local function BuildMark(frame)
    frame.halo = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
    frame.halo:SetPoint("CENTER")
    frame.halo:SetSize(PIN + PICKED_GLOW, PIN + PICKED_GLOW)
    frame.halo:SetColorTexture(1, 1, 1, 1)
    frame.halo:SetBlendMode("ADD")
    Round(frame, frame.halo)
    frame.halo:Hide()
    frame.pulse = frame.halo:CreateAnimationGroup()
    frame.pulse:SetLooping("BOUNCE")
    local fade = frame.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(GLOW_LOW)
    fade:SetToAlpha(GLOW_HIGH)
    fade:SetDuration(GLOW_PULSE)
    fade:SetSmoothing("IN_OUT")
    frame.gold = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.gold:SetPoint("CENTER")
    frame.gold:SetSize(PIN + PICKED_RING, PIN + PICKED_RING)
    frame.gold:SetColorTexture(1, 1, 1, 1)
    Round(frame, frame.gold)
    frame.gold:Hide()
    frame.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    frame.glow:SetPoint("CENTER")
    frame.glow:SetSize(PIN + LIT_RING, PIN + LIT_RING)
    frame.glow:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, LIT_ALPHA)
    Round(frame, frame.glow)
    frame.glow:Hide()
    frame.ring = frame:CreateTexture(nil, "BACKGROUND")
    frame.ring:SetPoint("CENTER")
    Round(frame, frame.ring)
    frame.plate = frame:CreateTexture(nil, "BORDER")
    frame.plate:SetAllPoints()
    frame.plate:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 1)
    Round(frame, frame.plate)
    frame.face = frame:CreateTexture(nil, "ARTWORK")
    frame.face:SetAllPoints()
    Round(frame, frame.face)
    frame.big = ns.Font(frame, BIG_SIZE, nil, T.fg)
    frame.big:SetPoint("CENTER")
    frame.badge = CreateFrame("Frame", nil, frame)
    frame.badge:SetSize(BADGE, BADGE)
    frame.badge:SetPoint("CENTER", frame, "BOTTOMRIGHT", -BADGE_IN, BADGE_IN)
    frame.badge.disc = frame.badge:CreateTexture(nil, "ARTWORK")
    frame.badge.disc:SetAllPoints()
    frame.badge.disc:SetColorTexture(0, 0, 0, BADGE_ALPHA)
    Round(frame.badge, frame.badge.disc)
    frame.badge.text = ns.Font(frame.badge, BADGE_SIZE, nil, T.fg)
    frame.badge.text:SetPoint("CENTER")
    frame.badge.tick = frame.badge:CreateTexture(nil, "OVERLAY")
    frame.badge.tick:SetTexture(St.CHECK, nil, nil, "TRILINEAR")
    frame.badge.tick:SetSize(BADGE_TICK, BADGE_TICK)
    frame.badge.tick:SetPoint("CENTER")
end

function View:NewPin()
    local pin = CreateFrame("Button", nil, self.canvas)
    pin.view = self
    pin:SetSize(PIN, PIN)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    BuildMark(pin)
    pin:SetScript("OnEnter", PinEnter)
    pin:SetScript("OnLeave", PinLeave)
    pin:SetScript("OnClick", PinClicked)
    Draggable(pin)
    return pin
end

local function SetMark(mark, boss, number, ring, killed)
    mark.ring:SetSize(PIN + ring * 2, PIN + ring * 2)
    local edge = number and St.BORDER_RGB or T.muted
    mark.ring:SetColorTexture(edge.r, edge.g, edge.b, 1)
    local face = boss.model and SetPortraitTextureFromCreatureDisplayID
    if boss.chest then
        mark.face:SetTexture(St.CHEST_ICON)
    elseif face then
        SetPortraitTextureFromCreatureDisplayID(mark.face, boss.model)
    end
    local drawn = boss.chest ~= nil or face ~= nil
    mark.face:SetShown(drawn)
    mark.face:SetDesaturated(killed == true)
    mark.big:SetShown(not drawn)
    local tag = J.BossTag(boss)
    local glyph = not boss.chest and tag and TAG_SHORT[tag] or nil
    mark.big:SetText(number or glyph or "")
    mark.badge:SetShown(killed or drawn and (number or glyph) ~= nil)
    mark.badge.tick:SetShown(killed == true)
    mark.badge.text:SetShown(not killed)
    mark.badge.text:SetText(number or glyph or "")
    local color = number and T.fg or T.muted
    mark.badge.text:SetTextColor(color.r, color.g, color.b)
    mark:SetAlpha(killed and KILLED_ALPHA or 1)
end

local function ShowPicked(mark, on, ringOnly)
    mark.gold:SetShown(on)
    mark.halo:SetShown(on and not ringOnly)
    if on then
        local c = ns.ThemeTint("accent", PICKED_RGB)
        mark.gold:SetColorTexture(c.r, c.g, c.b, 1)
        mark.halo:SetColorTexture(c.r, c.g, c.b, 1)
    end
    if on and not ringOnly then
        if not mark.pulse:IsPlaying() then mark.pulse:Play() end
    else
        mark.pulse:Stop()
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

-- Where art floor n comes as you walk the dungeon: map.order lists the art's floors in that
-- order, where the art numbers them otherwise (Shadowfang Keep's top is its seventh).
local function Walked(map, n)
    if not map.order then return n end
    for i = 1, #map.order do
        if map.order[i] == n then return i end
    end
    return n
end

local sorting   -- the map FillFloors sorts by, for the comparison below (made once)
local function ByWalk(a, b) return Walked(sorting, a) < Walked(sorting, b) end

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
        sorting = J.Maps[dungeon.key]
        table.sort(floors, ByWalk)
    end
    if #floors == 0 then
        local map = J.Maps[dungeon.key]
        -- A dungeon on one floor of shared art (map.floor) offers only that one.
        if map.floor then
            floors[1] = map.floor
        else
            -- map.order: only the floors it lists, where shared art has another dungeon's too.
            for n = 1, map.order and #map.order or map.floors do floors[n] = map.order and map.order[n] or n end
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

local function FloorName(map, n)
    return map.names and map.names[n] or ("Floor %d"):format(Walked(map, n))
end

function View:DrawPin(boss, number, key)
    local spot = Spot(self.dungeon, key)
    local here = type(spot) == "table" and spot[1] == self.floor
    -- Placing, a pin on another floor waits along the top too, to drag onto this one.
    if not here and not self:Placing() then return end
    self.used = self.used + 1
    local pin = self.pins[self.used] or self:NewPin()
    self.pins[self.used] = pin
    pin.boss, pin.key = boss, key
    local killed = self.inside and J.Kills.ThisRun(boss) or false
    SetMark(pin, boss, number, 1 / self.scale, killed)
    pin.elsewhere = not here and type(spot) == "table" and FloorName(J.Maps[self.dungeon.key], spot[1]) or nil
    pin.glow:Hide()
    ShowPicked(pin, self.picked ~= nil and key == self.picked and not self:Placing())
    pin.atX = here and spot[2] * MAP_W or nil
    pin.atY = here and spot[3] * MAP_H or nil
    if here then
        self:At(pin, spot[2], spot[3])
    else
        -- Not placed yet, or on another floor: along the top, to drag from.
        self.tray = self.tray + 1
        local row, col = math.floor((self.tray - 1) / TRAY_ROW), (self.tray - 1) % TRAY_ROW
        pin:ClearAllPoints()
        pin:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", col * TRAY_STEP + 8, -8 - row * TRAY_STEP)
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
    -- The game's art in twelve tiles, or the addon's own picture of a dungeon without any
    -- (a floor after the first is its own picture, the floor's number after the name), or of
    -- a floor the art lacks (map.images).
    local image = map.images and map.images[self.floor]
    if not image and map.image then image = self.floor > 1 and map.image .. self.floor or map.image end
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
    local lines = { ("    %s = { %s, floors = %d,%s%s"):format(dungeon.key, source, map.floors,
        map.floor and (" floor = %d,"):format(map.floor) or "",
        map.order and (" order = { %s },"):format(table.concat(map.order, ", ")) or "") }
    if map.names then
        local names = {}
        for i = 1, map.floors do
            if map.names[i] then names[#names + 1] = ("[%d] = %q"):format(i, map.names[i]) end
        end
        lines[#lines + 1] = "        names = { " .. table.concat(names, ", ") .. " },"
    end
    -- One images line, as with names: a second `images =` in the table would replace the first.
    if map.images then
        local images = {}
        for i = 1, map.floors do
            if map.images[i] then images[#images + 1] = ("[%d] = %q"):format(i, map.images[i]) end
        end
        lines[#lines + 1] = "        images = { " .. table.concat(images, ", ") .. " },"
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
--  Beside the map: its bosses in a list; under both: the picked boss's page
-------------------------------------------------------------------------------
local list, listView, page, lootView, picked
local quests = {}   -- boss -> what your quests need of it, filled each draw: { text, done }
local wingTexts = {}
local NO_EVENTS = {}

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
    return window:GetHeight() - MapFoot() - LOWER_GAP - PANEL_PAD
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
    local need = quests[boss]
    if not need then
        listsUsed = listsUsed + 1
        need = lists[listsUsed] or {}
        lists[listsUsed] = need
        wipe(need)
        quests[boss] = need
    end
    needsUsed = needsUsed + 1
    local entry = needs[needsUsed] or {}
    needs[needsUsed] = entry
    entry[1], entry[2], entry[3] = J.Quests.Name(matchQuest), matchText, matchDone
    need[#need + 1] = entry
end

local function FillQuests(dungeon)
    wipe(quests)
    listsUsed, needsUsed = 0, 0
    local all = dungeon.quests and dungeon.quests.quests
    if not all then return end
    for _, quest in ipairs(all) do
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
    local pool = listView.pools.bossRow
    for i = 1, pool.used do
        if pool[i].key == key then return pool[i] end
    end
end

local function PaintRow(row)
    local on = row.boss == picked
    local c = ns.ThemeTint("accent", PICKED_RGB)
    row.fill:SetColorTexture(c.r, c.g, c.b, St.TAB_FILL)
    row.fill:SetShown(on)
    row.hover:SetShown(row.lit == true and not on)
    ShowPicked(row.mark, on, true)
    local color = row.killed and not on and T.muted or T.fg
    row.name:SetTextColor(color.r, color.g, color.b)
end

-- A row hovered lights its pin; a pin hovered lights its row.
local function Light(key, on)
    local pin = PinOf(key)
    if pin then pin.glow:SetShown(on) end
    local row = RowOf(key)
    if row then
        row.lit = on
        PaintRow(row)
    end
end

local function ShowRow(row)
    local top, shown = list:GetVerticalScroll(), list:GetHeight()
    if row.top < top or row.top + LIST_ROW_H > top + shown then listView:ScrollToRow(list, row) end
end

local function Pick(boss)
    local again = boss == picked
    picked = boss
    windowView:Pick(boss and KeyOf(boss))
    local pool = listView.pools.bossRow
    for i = 1, pool.used do PaintRow(pool[i]) end
    local row = boss and RowOf(KeyOf(boss))
    if row then ShowRow(row) end
    window.hint:SetShown(boss == nil and not Folded())
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

local function RowEnter(row)
    Light(row.key, true)
    local boss = row.boss
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    local tag = J.BossTag(boss)
    if tag then GameTooltip:AddLine(TAG_WORDS[tag], T.muted.r, T.muted.g, T.muted.b) end
    if row.killed then GameTooltip:AddLine("Killed this run", St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b) end
    for _, need in ipairs(quests[boss] or NO_EVENTS) do
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

-- A click shows its page (folded, its loot at the mouse), and its floor on the map.
local function RowClicked(row)
    local spot = Spot(windowView.dungeon, row.key)
    if type(spot) == "table" and spot[1] ~= windowView.floor and windowView:FloorAt(spot[1]) then
        windowView.floor = spot[1]
        windowView:Draw()
    end
    windowView.onPick(row.boss)
end

local function Mark(row, texture)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_ICON, ROW_ICON)
    icon:SetTexture(texture, nil, nil, "TRILINEAR")
    return icon
end

local listKinds = ns.Shared.View.NewKinds()

listKinds.wing = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.text = ns.Font(row, WING_SIZE, nil, T.muted)
        row.text:SetPoint("BOTTOMLEFT", ROW_PAD, WING_BOTTOM)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        return row
    end,
    Set = function(row, wing)
        local text = wingTexts[wing]
        if not text then
            text = wing.name and wing.name:upper() or ""
            wingTexts[wing] = text
        end
        row.text:SetWidth(row:GetWidth() - ROW_PAD)
        row.text:SetText(text)
        return WING_H
    end,
}

listKinds.bossRow = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, St.HOVER)
        row.hover:SetAllPoints()
        row.fill = ns.Solid(row, "BORDER", T.accent, St.TAB_FILL)
        row.fill:SetAllPoints()
        row.mark = CreateFrame("Frame", nil, row)
        row.mark:SetSize(PIN, PIN)
        row.mark:SetScale(LIST_SCALE)
        row.mark:SetPoint("LEFT", row, "LEFT", ROW_PAD / LIST_SCALE, 0)
        BuildMark(row.mark)
        row.mark.badge:SetScale(LIST_BADGE_GROW)
        row.name = ns.Font(row, 12, nil, T.fg)
        row.name:SetPoint("LEFT", row, "LEFT", ROW_NAME_X, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.tag = ns.Font(row, 9, nil, T.muted)
        row.tag:SetPoint("LEFT", row.name, "RIGHT", ROW_TAG_GAP, 0)
        row.bisText = ns.Font(row, 11, nil, T.fg)
        row.bisText:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
        row.star = Mark(row, St.STAR)
        row.star:SetVertexColor(St.BIS_RGB.r, St.BIS_RGB.g, St.BIS_RGB.b)
        row.star:SetPoint("RIGHT", row.bisText, "LEFT", -ROW_STAR_GAP, 0)
        row.quest = Mark(row, St.BANG)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        row:SetScript("OnClick", RowClicked)
        return row
    end,
    Set = function(row, boss, number, key, killed)
        row.boss, row.key, row.lit, row.killed = boss, key, false, killed
        SetMark(row.mark, boss, number, 1 / LIST_SCALE, killed)
        local tag = J.BossTag(boss)
        row.tag:SetText(tag or "")
        row.tag:SetShown(tag ~= nil)
        local tagW = tag and ROW_TAG_GAP + math.ceil(row.tag:GetStringWidth()) or 0
        row.bis, row.haveBis = J.Loot.BossBis(boss)
        row.bisText:SetText(row.bis > 0 and row.bis or "")
        row.bisText:SetShown(row.bis > 0)
        row.star:SetShown(row.bis > 0)
        local right = row.bis > 0 and ROW_PAD + math.ceil(row.bisText:GetStringWidth()) + ROW_STAR_GAP + ROW_ICON
            or ROW_PAD - ROW_MARK_GAP
        local needed = quests[boss] ~= nil
        row.quest:SetShown(needed)
        if needed then
            row.quest:ClearAllPoints()
            row.quest:SetPoint("RIGHT", row, "RIGHT", -(right + ROW_MARK_GAP), 0)
            right = right + ROW_MARK_GAP + ROW_ICON
        end
        row.name:SetWidth(0)
        row.name:SetText(boss.name)
        local room = row:GetWidth() - ROW_NAME_X - tagW - right - ROW_MARK_GAP
        row.name:SetWidth(math.max(1, math.min(math.ceil(row.name:GetStringWidth()) + 1, room)))
        PaintRow(row)
        return LIST_ROW_H
    end,
}

local drawKilled, drawTotal, drawInside, drawGrouped, lastWing

local function ListRow(boss, number, key, wing)
    if drawGrouped and wing ~= lastWing then
        lastWing = wing
        listView:Add("wing", wing)
    end
    local killed = drawInside and J.Kills.ThisRun(boss) or false
    if number then
        drawTotal = drawTotal + 1
        if killed then drawKilled = drawKilled + 1 end
    end
    listView.rows = listView.rows + 1
    listView:Add("bossRow", boss, number, key, killed)
end

local function CountRow()
    listView.rows = listView.rows + 1
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

local function DrawList()
    local dungeon = windowView.dungeon
    FillQuests(dungeon)
    local named = 0
    for _, wing in ipairs(dungeon.wings) do
        if wing.name then named = named + 1 end
    end
    drawKilled, drawTotal, drawInside = 0, 0, windowView.inside
    drawGrouped, lastWing = named > 1, nil
    listView:Clear()
    listView.tightTitles = true
    listView.rows = 0
    EachBoss(dungeon, CountRow)
    listView:Section("Bosses", listView.rows)
    listView.rows = 0
    EachBoss(dungeon, ListRow)
    listView:Fit(NO_EVENTS)
    return drawInside and drawTotal > 0 and DownText(drawKilled, drawTotal) or ""
end

-- The map and the list beside it, and under both, unless folded, the page: exactly as tall
-- as the window it was opened beside, so their edges line up; with none, LOWER_MIN under the
-- map.
local function Size(owner)
    local folded = Folded()
    local foot = MapFoot()
    page:SetShown(not folded)
    window.hint:SetShown(not folded and picked == nil)
    window.fold:SetRotation(folded and 0 or -math.pi / 2)
    page:SetPoint("TOPLEFT", PANEL_PAD, -(foot + LOWER_GAP))
    if folded then
        window:SetHeight(foot + PANEL_PAD)
    else
        window:SetHeight(owner and owner:GetHeight() or foot + LOWER_GAP + LOWER_MIN)
    end
end

local function WindowDrawn()
    Size(window.owner)
    local down = DrawList()
    window.title:SetText(windowView.dungeon.name:upper() .. down
        .. (placing and ns.Color("muted", "   PLACING PINS") or ""))
    window.copy:SetShown(placing)
    if picked then
        local row = RowOf(KeyOf(picked))
        if row then ShowRow(row) end
        if not Folded() then PageDrawn(lootView:GetHeight()) end
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
    GameTooltip:SetText(Folded() and "Show the boss's page" or "Map and bosses only", 1, 1, 1)
    GameTooltip:AddLine(Folded() and "The picked boss's loot and abilities, under the map."
        or "Folds the boss's page away, to keep the map on screen.",
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

local ListMixin = {}

function ListMixin:Redraw()
    if windowView.dungeon then DrawList() end
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
    local underMap = -(PANEL_HEADER + MAP_SHOWN_H + UNDER_MAP_GAP)
    windowView.down:SetPoint("TOPLEFT", PANEL_PAD, underMap)
    window.copy = ns.Button(window, "Copy", COPY_W, FLOOR_H - 2, function() Copy(windowView.dungeon) end)
    window.copy:SetPoint("TOPLEFT", PANEL_PAD + MAP_SHOWN_W - COPY_W, underMap)
    windowView.onPick = function(boss)
        if not Folded() then return Pick(boss) end
        lootFrom = windowView
        windowView:Pick(KeyOf(boss))
        J.View.OpenBossLoot(boss, windowView.dungeon)
    end
    windowView.onPinHover = Light
    list = ns.UI.SlimScroll(window, LIST_BAR, LIST_BAR_GAP)
    list:SetPoint("TOPLEFT", PANEL_PAD + MAP_SHOWN_W + LIST_GAP, -PANEL_HEADER)
    list:SetSize(LIST_W - LIST_BAR - LIST_BAR_GAP, MAP_SHOWN_H)
    listView = ns.Shared.View.New(list, listKinds, ListMixin)
    listView:SetWidth(LIST_W - LIST_BAR - LIST_BAR_GAP)
    list:SetScrollChild(listView)
    page = ns.UI.SlimScroll(window)
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
-- The window on the dungeon, with the boss to go for next picked: the first in kill order not
-- killed this run.
local function ShowDungeon(dungeon)
    windowView:Open(dungeon)
    Size(window.owner)
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
    Paint()
    Place(from)
    window.owner = from and Owner(from)
    window:Show()
    window:Raise()
    ShowDungeon(dungeon)
end

-- The Journal the window was opened beside went to another dungeon's page: the window, where
-- it is, shows that dungeon's map; a dungeon with no map closes it.
---@param view Frame the Journal's view drawing the page
---@param dungeon JournalDungeon
function J.FollowDungeonMap(view, dungeon)
    if not (window and window:IsShown()) or windowView.dungeon == dungeon then return end
    if not window.owner or Owner(view) ~= window.owner then return end
    if not J.Maps[dungeon.key] then
        window:Hide()
        return
    end
    ShowDungeon(dungeon)
end

-- What the window shows, drawn again (a test, a setting).
function J.DrawDungeonMap()
    if window and window:IsShown() then windowView:Draw() end
end

-------------------------------------------------------------------------------
--  /nf mappins and /nf mapcheck
-------------------------------------------------------------------------------
local probe

-- Names the client might keep a dungeon's art under, for the dungeons its art was not found
-- for yet: mapcheck tries each (paths ignore case, so only spellings differ).
local MAYBE_ART = {
    ZulFarrak = { "ZulFarrak", "ZulFarak", "ZulFarrakDungeon", "ZulFarrak1" },
    SunkenTemple = { "TheTempleOfAtalHakkar", "TempleOfAtalHakkar", "SunkenTemple", "TheSunkenTemple",
        "AtalHakkar", "TempleOfAtalHakkar1" },
    UpperBlackrockSpire = { "UpperBlackrockSpire", "BlackrockSpireUpper", "UpperBlackrock", "BlackrockSpire2" },
}

-- The floors of art the client has under the name, 1 to 10.
local function FloorsOf(art)
    local found = {}
    for n = 1, 10 do
        probe:SetTexture(ART:format(art, art, n, 1))
        local id = probe:GetTextureFileID()
        if type(id) == "number" and id > 0 then found[#found + 1] = n end
    end
    return found
end

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
            local found = FloorsOf(map.art)
            ns.Print(("%s (%s): %s, data says %d"):format(map.art, key,
                #found > 0 and "floors " .. table.concat(found, ",") or "no art", map.floors))
        end
    end
    for key, names in pairs(MAYBE_ART) do
        local hits = {}
        for _, art in ipairs(names) do
            local found = FloorsOf(art)
            if #found > 0 then hits[#hits + 1] = art .. " (floors " .. table.concat(found, ",") .. ")" end
        end
        ns.Print(("%s, other names tried: %s"):format(key, #hits > 0 and table.concat(hits, ", ") or "none found"))
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
-- setting (a filter, BiS): the list and the page are drawn again, the page once for a burst.
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
