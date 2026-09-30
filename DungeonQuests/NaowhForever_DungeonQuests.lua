-------------------------------------------------------------------------------
--  NaowhForever_DungeonQuests.lua -- the QoL dungeon quest tracker: entering a
--  dungeon lists its quests for your faction, in your log or still to pick up and where;
--  and a page listing every dungeon's quests with where each one starts.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

-- The level in its difficulty colour and the title white; the state sits in a column on the
-- right of each line. In log is the quest log's own in-progress yellow. Complete is one in
-- your log with its objectives done, in the quest log's completed green. A quest handed in
-- reads Finished and fades to grey, with a check where its level would be.
local MUTED = "|cff9ca3af"
local COMPLETE = "|cff19ff19"
local DONE = MUTED .. "Finished|r"
local ACTIVE = "|cffffd100In log|r"
local MISSING = "|cfff87171Missing|r"
local READY = COMPLETE .. "Complete|r"
-- Size 0 is the font's own height, so the check does not make its line taller than the
-- status beside it.
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
-- A dark band behind every other quest on the page, so the lines are easy to follow
-- across. Black, so it darkens the panel rather than greying it.
local BLACK = { r = 0, g = 0, b = 0 }
local STRIPE = BLACK
local STRIPE_ALPHA = 0.35
-- On the tracker each quest is a solid bar a shade darker than the dropdown above it
-- (the theme's panel grey, 0x1a1c1f), edged in black.
local BAR = { r = 0x14 / 255, g = 0x16 / 255, b = 0x19 / 255 }

-- Instance ID -> the dungeons that use it; Blackrock Spire holds both its halves. A new
-- dungeon whose ID is not known yet is found by the instance name instead.
local byMap, byInstanceName = {}, {}
for _, dungeon in ipairs(ns.DungeonQuests) do
    if dungeon.map then
        byMap[dungeon.map] = byMap[dungeon.map] or {}
        table.insert(byMap[dungeon.map], dungeon)
    else
        byInstanceName[dungeon.name] = { dungeon }
    end
end

-- The dungeon you are in: its instance ID and its entries, or nil outside one.
local function CurrentDungeon()
    local inInstance, kind = IsInInstance()
    if not (inInstance and kind == "party") then return end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    return id, byMap[id] or byInstanceName[name]
end

local panel, shownMap
local dismissed = {}   -- instance IDs closed by hand, until you leave

-- Missing quests this far under or over your level are listed outside a dungeon; the ones
-- in your log always are.
local BELOW, ABOVE = 3, 6

-- A dungeon is within reach from this many levels under its range to as many over it; its
-- range is shown in the options' READY green then.
local REACH, IN_REACH = 5, "|cff4dd17a"

local function InReach(dungeon)
    local mine = UnitLevel("player")
    local levels = dungeon.levels
    return levels ~= nil and mine >= levels[1] - REACH and mine <= levels[2] + REACH
end

local function LevelRange(dungeon)
    if not dungeon.levels then return "" end
    return ("  %s%d-%d|r"):format(InReach(dungeon) and IN_REACH or MUTED, dungeon.levels[1], dungeon.levels[2])
end

-- Part of a chain done, and the next step not picked up yet.
local NEXT = "|cffff9933Next step|r"
local NOT_DONE = MUTED .. "Not done|r"

-- A step is a quest ID, or a table of IDs that each stand for it (one per faction).
local function StepIDs(step)
    return type(step) == "table" and step or { step }
end

local function OnID(ids)
    for _, step in ipairs(ids or {}) do
        for _, id in ipairs(StepIDs(step)) do
            if C_QuestLog.IsOnQuest(id) then return id end
        end
    end
end

-- The ID of whichever step or version of the quest is in your log, if any.
local function LoggedID(quest)
    if C_QuestLog.IsOnQuest(quest[1]) then return quest[1] end
    return OnID(quest.alt) or OnID(quest.steps) or OnID(quest.lead)
end

local function StepDone(step)
    for _, id in ipairs(StepIDs(step)) do
        if C_QuestLog.IsQuestFlaggedCompleted(id) then return true end
    end
    return false
end

-- A quest can carry more IDs than its own (see the data file): alt versions, either of
-- which counts; the other steps of its chain, all of which must be done; and a lead-in,
-- which only counts while you carry it.
local function Status(quest)
    local done = C_QuestLog.IsQuestFlaggedCompleted
    local id = LoggedID(quest)
    if id then return C_QuestLog.IsComplete(id) and READY or ACTIVE end
    local first = done(quest[1])
    for _, id in ipairs(quest.alt or {}) do first = first or done(id) end
    local all, any = first, first
    for _, step in ipairs(quest.steps or {}) do
        local d = StepDone(step)
        all, any = all and d, any or d
    end
    if all then return DONE end
    return any and NEXT or MISSING
end

local function InLog(status)
    return status == ACTIVE or status == READY
end

-- The order quests are listed in within a dungeon, the way a quest goes: still to pick up
-- (Next step is a chain's next quest to pick up), in your log, ready to hand in, done.
-- Data order within each.
local RANK = { [MISSING] = 1, [NEXT] = 2, [ACTIVE] = 3, [READY] = 4, [DONE] = 5 }
local RANKS = 5

-- Your faction's quests and your class's class quests; all lists every quest.
local function ForMe(quest, all)
    if all then return true end
    if quest.class and quest.class ~= select(2, UnitClass("player")) then return false end
    local side, faction = quest[4], UnitFactionGroup("player")
    return side == "B" or (side == "A" and faction == "Alliance") or (side == "H" and faction == "Horde")
end

-- The client's title when it has one (in the player's language), the guide's otherwise.
-- The quest level as the game has it, the number the quest log shows. The data file's
-- level is the guide's and often matches neither that nor the required level, so it is
-- only the fallback until the client has loaded the quest; the load is asked for once,
-- and QUEST_DATA_LOAD_RESULT redraws the tracker when it lands.
local requested = {}
local function QuestLevel(quest)
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(quest[1])
    if level and level > 0 then return level end
    if not requested[quest[1]] and C_QuestLog.RequestLoadQuestByID then
        requested[quest[1]] = true
        C_QuestLog.RequestLoadQuestByID(quest[1])
    end
    return quest[3]
end

-- done swaps the level for a check: it no longer matters once the quest is handed in.
-- Otherwise the level is in its difficulty colour and the title white.
local function Title(quest, done, suffix)
    suffix = suffix or ""
    local name = C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2]
    if done then return CHECK .. " " .. MUTED .. name .. suffix .. "|r" end
    local level = QuestLevel(quest)
    if not level then return name .. suffix end
    local c = GetQuestDifficultyColor(level)
    return ("|cff%02x%02x%02x[%d]|r %s%s"):format(c.r * 255, c.g * 255, c.b * 255, level, name, suffix)
end

-- Grey in the quest log: too far under your level to be worth picking up.
local function Grey(quest)
    local level = QuestLevel(quest)
    return level ~= nil and GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
end

-- The quest's title for its line; its status goes in the column on the right. suffix
-- follows the title (the page's faction).
local function QuestLine(quest, status, suffix)
    return Title(quest, status == DONE, suffix)
end

local SHARE = { [true] = "Shareable", [false] = "Not shareable", pre = "Needs a prerequisite" }

-- With part of a chain done, where its next step starts. quest.next runs alongside
-- quest.steps: next[i] = { uiMapID, x, y, where } for steps[i], false where unknown.
local function NextSpot(quest)
    if not (quest.next and quest.steps) then return end
    for i, step in ipairs(quest.steps) do
        if not StepDone(step) then return quest.next[i] or nil end
    end
end

-- Where the waypoint goes: the quest giver, or with part of the chain done, whoever gives
-- the next step. nil when the data has no spot.
local function WaypointSpot(quest)
    if Status(quest) == NEXT then
        local spot = NextSpot(quest)
        if spot then return spot[1], spot[2], spot[3], spot[4] end
    end
    if quest[7] then return quest[7], quest[8], quest[9], quest[6] end
end

-- Marks where the quest giver stands. The tracking arrow is not confirmed on Forever, so the
-- waypoint goes on the map either way.
-- With TomTom loaded, its waypoint and arrow instead of the game's. Only the last one the
-- tracker set is kept, so clicking pin after pin does not pile up arrows.
local tomtomWaypoint

local function PlaceTomTom(title, map, x, y, note)
    if tomtomWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomWaypoint) end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, x / 100, y / 100, {
        title = title .. (note or ""), from = "Naowh Forever", persistent = false, crazy = true,
        silent = true,
    })
    if not ok then return false end
    tomtomWaypoint = uid
    local info = C_Map.GetMapInfo(map)
    ns.Print(("TomTom waypoint for %s%s: %s %.1f, %.1f"):format(title, note or "",
        info and info.name or "", x, y))
    return true
end

-- x and y in percent, as the data file writes them. note says what the pin points at.
local function PlaceWaypoint(title, map, x, y, note)
    if TomTom and TomTom.AddWaypoint and PlaceTomTom(title, map, x, y, note) then return true end
    if not C_Map.CanSetUserWaypointOnMap(map) then
        ns.Print("That map does not take waypoints.")
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    local info = C_Map.GetMapInfo(map)
    ns.Print(("Waypoint for %s%s: %s %.1f, %.1f"):format(title, note or "", info and info.name or "", x, y))
    return true
end
ns.PlaceWaypoint = PlaceWaypoint

local function SetWaypoint(quest)
    local map, x, y = WaypointSpot(quest)
    if not map then return end
    PlaceWaypoint(C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2], map, x, y)
end

-- Selects and super-tracks the quest without opening the log. The quest log lives on the
-- world map in this engine, and opening it from addon code taints the map's quest pins:
-- the next time the map opens in combat their SetPassThroughButtons is blocked.
local function SelectInQuestLog(id)
    C_QuestLog.SetSelectedQuest(id)
    C_SuperTrack.SetSuperTrackedQuestID(id)
    ns.Print(("Tracking %s. Press L to see it in your quest log."):format(
        C_QuestLog.GetTitleForQuestID(id) or id))
end

local byID = {}
for _, dungeon in ipairs(ns.DungeonQuests) do
    for _, quest in ipairs(dungeon.quests) do byID[quest[1]] = quest end
end

-- The chain the quest belongs to (see the chains file) and which step of it the quest is;
-- nil for a quest that stands alone.
local function Chain(quest)
    local chain = ns.DungeonQuestChains[quest[1]]
    if not chain then return end
    for i, step in ipairs(chain) do
        for _, id in ipairs(StepIDs(step)) do
            if id == quest[1] then return chain, i end
        end
    end
end

-- Done, in your log or neither, and the ID of the step's version to name it by.
local function StepState(step)
    local ids = StepIDs(step)
    for _, id in ipairs(ids) do
        if C_QuestLog.IsOnQuest(id) then return ACTIVE, id end
    end
    for _, id in ipairs(ids) do
        if C_QuestLog.IsQuestFlaggedCompleted(id) then return DONE, id end
    end
    return NOT_DONE, ids[1]
end

-- Where a step is picked up: its quest giver in the data file, else where its quest page
-- says it starts. The version the step state names is tried first.
local function StepSpot(step, id)
    local ids = { id }
    for _, other in ipairs(StepIDs(step)) do ids[#ids + 1] = other end
    for _, try in ipairs(ids) do
        local quest = byID[try]
        if quest and quest[7] then return quest[7], quest[8], quest[9], " (quest giver)" end
        local start = ns.DungeonQuestChainStarts[try]
        if start then return start[1], start[2], start[3], " (" .. start[4] .. ")" end
    end
end

-- A step in your log goes where the game's own navigation sends you for it; any other
-- step goes to where it is picked up.
local function StepWaypoint(step, state, id, name)
    if state == ACTIVE and C_QuestLog.GetNextWaypoint then
        local map, x, y = C_QuestLog.GetNextWaypoint(id)
        if map and x and y and PlaceWaypoint(name, map, x * 100, y * 100) then return end
    end
    local map, x, y, note = StepSpot(step, id)
    if map then PlaceWaypoint(name, map, x, y, note) end
end

-- Every quest of the chain in order with how far you are, the clicked one marked. A step
-- not done yet with somewhere to go puts a waypoint there when clicked; a quest in your log
-- can be tracked from here.
local function OpenChain(owner, quest)
    local chain, own = Chain(quest)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local title = C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2]
        root:CreateTitle(("%s: step %d of %d"):format(title, own, #chain))
        root:CreateTitle(MUTED .. "Click a step for a waypoint.|r")
        for i, step in ipairs(chain) do
            local state, id = StepState(step)
            local name = C_QuestLog.GetTitleForQuestID(id) or ns.DungeonQuestChainNames[id] or byID[id][2]
            local text = ("%d.  %s  %s"):format(i, name, state)
            if state == DONE then text = MUTED .. ("%d.  %s|r  "):format(i, name) .. DONE end
            if i == own then text = text .. "  |cff4db5f5(this quest)|r" end
            if state ~= DONE and (state == ACTIVE or StepSpot(step, id)) then
                root:CreateButton(text, function() StepWaypoint(step, state, id, name) end)
            else
                root:CreateTitle(text, WHITE_FONT_COLOR)
            end
        end
        local logged = LoggedID(quest)
        if logged then
            root:CreateDivider()
            root:CreateButton("Track in quest log", function() SelectInQuestLog(logged) end)
        end
    end)
end

-- A quest in your log gets a waypoint where the game's own navigation would send you (its
-- objective or turn-in). Super-tracking alone puts nothing on the map, and Forever has no
-- route for many vanilla quests, so without one it falls back to the quest giver, which
-- for most of these is also where the quest is handed in.
local function TrackQuest(quest, id)
    if C_QuestLog.AddQuestWatch then C_QuestLog.AddQuestWatch(id) end
    local title = C_QuestLog.GetTitleForQuestID(id) or quest[2]
    local map, x, y
    if C_QuestLog.GetNextWaypoint then map, x, y = C_QuestLog.GetNextWaypoint(id) end
    if map and x and y and PlaceWaypoint(title, map, x * 100, y * 100) then return end
    -- Handed in to someone other than its quest giver: the data file's turn-in spot.
    local turnIn = ns.DungeonQuestTurnIns and ns.DungeonQuestTurnIns[id]
    if turnIn and PlaceWaypoint(title, turnIn[1], turnIn[2], turnIn[3], " (turn in: " .. turnIn[4] .. ")") then
        return
    end
    if quest[7] and PlaceWaypoint(title, quest[7], quest[8], quest[9], " (quest giver)") then return end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then C_SuperTrack.SetSuperTrackedQuestID(id) end
    ns.Print(("The game has no route for %s, and its quest giver's spot is not known."):format(title))
end

-- The game's own waypoint pin where the client has it, the minimap quest arrow otherwise.
local function SetPinTexture(tex)
    for _, atlas in ipairs({ "Waypoint-MapPin-ChatIcon", "Waypoint-MapPin-Untracked" }) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            tex:SetAtlas(atlas)
            return
        end
    end
    tex:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
end

-------------------------------------------------------------------------------
--  In the dungeon
-------------------------------------------------------------------------------
-- The Show Single Dungeon choices: every dungeon, in level order. Anyone can enter any
-- of them; faction and class only decide which of its quests are listed.
local dungeonValues, dungeonOrder = {}, {}
for _, dungeon in ipairs(ns.DungeonQuests) do
    dungeonValues[dungeon.name] = dungeon.name
    dungeonOrder[#dungeonOrder + 1] = dungeon.name
end

local function BuildPanel()
    panel = CreateFrame("Frame", "NaowhForeverDungeonQuests", UIParent)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:SetWidth(340)
    -- Black at 70%, so the world shows faintly through, with a black border rather than the
    -- theme's grey; the quest bars on it are solid.
    ns.Solid(panel, "BACKGROUND", BLACK, 0.7):SetAllPoints()
    ns.Border(panel, BLACK)
    panel.title = ns.Font(panel, 14, "OUTLINE", T.accent)
    panel.title:SetPoint("TOPLEFT", 8, -8)
    panel.title:SetPoint("RIGHT", -28, 0)
    panel.title:SetJustifyH("LEFT")
    -- Inside a dungeon the X closes it until you come back; outside it is the Show Outside
    -- Dungeons toggle, so it switches that off.
    panel.close = ns.Button(panel, "X", 18, 18, function()
        if shownMap then
            dismissed[shownMap] = true
            panel:Hide()
        else
            S.Set("dqOutside", false)
            ns.UI:RefreshPage(true)
        end
    end)
    panel.close:SetPoint("TOPRIGHT", -5, -5)
    panel.picker = ns.UI.BuildDropdownControl(panel, 324, panel:GetFrameLevel() + 3,
        dungeonValues, dungeonOrder,
        function() return S.Get("dqSelected") end,
        function(name) S.Set("dqSelected", name) end)
    panel.picker:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    -- The list: one row per line, built from a pool so a redraw reuses them.
    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetWidth(324)
    panel.rows = {}
    panel.mover = ns.UI.AttachMover(panel, "Dungeon Quests", function(pos) S.Set("dqPos", pos) end)
    local pos = S.Get("dqPos")
    if pos then
        panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
    end
    panel:Hide()
end

-- STATUS_W is the least room kept for the status, so short ones do not let titles run
-- right up to them; a wider status takes what it needs. GAP is the room kept above a quest
-- and below its last line, so each quest sits apart from the next.
-- INSET keeps the pin and the status in from the band's edges, as the dropdown keeps its text.
local PIN, BODY_W, STATUS_W, GAP, NUDGE, INSET = 18, 324, 64, 5, 2, 4

local function RowTooltip(row)
    local quest = row.quest
    if not quest then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2])
    GameTooltip:AddLine(quest[6], 1, 1, 1, true)
    if Chain(quest) then
        GameTooltip:AddLine("Click to list every quest in its chain.", 0.3, 0.7, 0.95)
    elseif LoggedID(quest) then
        GameTooltip:AddLine("Click to track it in your quest log.", 0.3, 0.7, 0.95)
    end
    GameTooltip:Show()
end

local function PinTooltip(pin)
    local quest = pin:GetParent().quest
    GameTooltip:SetOwner(pin, "ANCHOR_LEFT")
    if LoggedID(quest) then
        GameTooltip:SetText("Waypoint")
        GameTooltip:AddLine("Click to mark its objective or turn-in on your map, or its quest "
            .. "giver where the game has no route for it.", 0.3, 0.7, 0.95, true)
    else
        GameTooltip:SetText("Waypoint")
        GameTooltip:AddLine(select(4, WaypointSpot(quest)), 1, 1, 1, true)
        GameTooltip:AddLine("Click to mark the quest giver on your map.", 0.3, 0.7, 0.95)
    end
    GameTooltip:Show()
end

local function PinClick(pin)
    local quest = pin:GetParent().quest
    local id = LoggedID(quest)
    if id then TrackQuest(quest, id) else SetWaypoint(quest) end
end

local function TrackerRow(i)
    local row = panel.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.body)
    row:SetWidth(BODY_W)
    row.text = ns.Font(row, 12, nil)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row.pin = CreateFrame("Button", nil, row)
    row.pin:SetSize(PIN, PIN)
    row.pin:SetPoint("TOPLEFT", 0, 1)
    row.pin.tex = row.pin:CreateTexture(nil, "ARTWORK")
    row.pin.tex:SetAllPoints()
    SetPinTexture(row.pin.tex)
    row.pin:SetScript("OnClick", PinClick)
    row.pin:SetScript("OnEnter", PinTooltip)
    row.pin:SetScript("OnLeave", GameTooltip_Hide)
    -- No set width: it sizes to its text, so a status is never cut short.
    row.status = ns.Font(row, 12, nil)
    row.status:SetPoint("TOPRIGHT", 0, -1)
    row.status:SetJustifyH("RIGHT")
    row.status:SetWordWrap(false)
    -- The quest's bar spans the row exactly, the same width as the dropdown above. A quest
    -- whose lines take more than one row is one bar: its rows share the fill and the side
    -- edges, the top edge goes on its first row and the bottom edge on its last.
    row.stripe = ns.Solid(row, "BACKGROUND", BAR, 1)
    row.stripe:SetAllPoints()
    row.edges = {}
    for side, points in pairs({
        top = { "TOPLEFT", "TOPRIGHT" }, bottom = { "BOTTOMLEFT", "BOTTOMRIGHT" },
        left = { "TOPLEFT", "BOTTOMLEFT" }, right = { "TOPRIGHT", "BOTTOMRIGHT" },
    }) do
        local edge = ns.Solid(row, "ARTWORK", BLACK, 1)
        edge:SetPoint(points[1])
        edge:SetPoint(points[2])
        if side == "top" or side == "bottom" then edge:SetHeight(1) else edge:SetWidth(1) end
        row.edges[side] = edge
    end
    -- A 1px line in the Naowh blue in the gap between one quest's bar and the next.
    row.divider = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.divider:SetPoint("TOPLEFT", row, "BOTTOMLEFT")
    row.divider:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT")
    row.divider:SetHeight(1)
    row:SetScript("OnClick", function(self)
        if self.quest and Chain(self.quest) then
            OpenChain(self, self.quest)
            return
        end
        local id = self.quest and LoggedID(self.quest)
        if id then SelectInQuestLog(id) end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    panel.rows[i] = row
    return row
end

-- entries: { text, status?, quest?, pin?, indent?, stripe?, sub? }. Quest rows leave room
-- for the pin whether or not they have one, so every title lines up, and for the status
-- column, so every status lines up on the right. sub marks a quest's own line under its
-- title, which keeps close to it: the GAP goes above the title and below the last line,
-- and the divider in a 1px gap under the last line.
local function Layout(entries)
    local y = 0
    for i, entry in ipairs(entries) do
        local row = TrackerRow(i)
        local x = INSET + (entry.quest and PIN + 3 or (entry.indent or 0))
        local top = entry.sub and 0 or GAP
        local bottom = entries[i + 1] and entries[i + 1].sub and 0 or GAP
        row.quest = entry.quest
        row.text:ClearAllPoints()
        -- NUDGE lifts the line inside its row: the font leaves room above its capitals, so
        -- text placed evenly by the numbers looks low.
        row.text:SetPoint("TOPLEFT", x, NUDGE - 1 - top)
        row.status:ClearAllPoints()
        row.status:SetPoint("TOPRIGHT", -INSET, NUDGE - 1 - top)
        row.status:SetText(entry.status or "")
        local statusW = entry.status and math.max(STATUS_W, math.ceil(row.status:GetStringWidth())) + 6 or 0
        row.text:SetWidth(BODY_W - x - statusW - INSET)
        row.text:SetText(entry.text)
        -- Centred on the title's first line.
        row.pin:SetPoint("TOPLEFT", INSET, NUDGE + 1 - top)
        row.pin:SetShown(entry.pin == true)
        local bar = entry.stripe == true
        row.stripe:SetShown(bar)
        row.edges.left:SetShown(bar)
        row.edges.right:SetShown(bar)
        row.edges.top:SetShown(bar and top > 0)
        row.edges.bottom:SetShown(bar and bottom > 0)
        -- Only between two quests, not under a dungeon's name or the last quest.
        local divided = bar and bottom > 0 and entries[i + 1] ~= nil and entries[i + 1].stripe == true
        row.divider:SetShown(divided)
        row:EnableMouse(entry.quest ~= nil)
        local h = math.ceil(row.text:GetStringHeight()) + 3 + top + bottom
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
        row:Show()
        y = y + h + (divided and 1 or 0)
    end
    for i = #entries + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.body:SetHeight(math.max(y, 1))
    return y
end

local function NearLevel(quest)
    local level, mine = QuestLevel(quest), UnitLevel("player")
    return not level or (level >= mine - BELOW and level <= mine + ABOVE)
end

-- near, outside a dungeon, drops the missing quests that are not close to your level; a
-- missing quest grey to you is dropped everywhere.
local function Render(dungeons, title, near)
    local lines, inLog, missing, mine, grey = {}, 0, 0, 0, false
    local function Add(text, extra)
        extra = extra or {}
        extra.text = text
        lines[#lines + 1] = extra
    end
    for _, dungeon in ipairs(dungeons) do
        if #dungeons > 1 or near then Add("|cff4db5f5" .. dungeon.name .. "|r" .. LevelRange(dungeon)) end
        -- Gathered by state first, then listed in RANK order.
        local byRank = {}
        for r = 1, RANKS do byRank[r] = {} end
        for _, quest in ipairs(dungeon.quests) do
            local status = ForMe(quest) and Status(quest)
            if status then mine = mine + 1 end
            if status and near and (status == MISSING or status == DONE) and not NearLevel(quest) then
                status = nil
            end
            if status == MISSING and Grey(quest) then status, grey = nil, true end
            if status then
                if InLog(status) then inLog = inLog + 1 end
                if status == MISSING or status == NEXT then missing = missing + 1 end
                if status ~= DONE or S.Get("dqShowDone") then
                    table.insert(byRank[RANK[status]], { quest = quest, status = status })
                end
            end
        end
        for r = 1, RANKS do
            for _, item in ipairs(byRank[r]) do
                local quest, status = item.quest, item.status
                if status == DONE then
                    Add(QuestLine(quest, status), { status = status, quest = quest, stripe = true })
                else
                    -- A pin on every quest in your log (it tracks the quest), and on the rest
                    -- wherever the data knows where the quest giver stands.
                    Add(QuestLine(quest, status),
                        { status = status, quest = quest, pin = InLog(status) or WaypointSpot(quest) ~= nil,
                          stripe = true })
                    if status == MISSING then
                        Add(MUTED .. quest[6] .. "|r", { indent = PIN + 15, stripe = true, sub = true })
                    end
                    local nextSpot = status == NEXT and NextSpot(quest)
                    if nextSpot then
                        Add(MUTED .. "Next: " .. nextSpot[4] .. "|r", { indent = PIN + 15, stripe = true, sub = true })
                    end
                end
            end
        end
    end
    local known = 0
    for _, dungeon in ipairs(dungeons) do known = known + #dungeon.quests end
    if known == 0 then
        Add(MUTED .. (near and "No dungeon quests near your level." or "No quests known for this dungeon yet.") .. "|r")
    elseif mine == 0 then
        Add(MUTED .. "No quests here for your faction and class.|r")
    elseif inLog + missing == 0 and not S.Get("dqShowDone") then
        Add(MUTED .. (near and "No dungeon quests near your level."
            or grey and "Only quests grey to you are left here." or "All done here.") .. "|r")
    end
    local name = title or (#dungeons > 1 and "Blackrock Spire" or dungeons[1].name)
    panel.title:SetText(name)
    local single = S.Get("dqSingle")
    panel.picker:SetShown(single)
    panel.body:ClearAllPoints()
    panel.body:SetPoint("TOPLEFT", single and panel.picker or panel.title, "BOTTOMLEFT", 0, -6)
    if single then
        for _, dungeon in ipairs(ns.DungeonQuests) do
            dungeonValues[dungeon.name] = dungeon.name .. LevelRange(dungeon)
        end
        panel.picker._refreshLabel()
    end
    local listH = Layout(lines)
    panel:SetHeight(panel.title:GetStringHeight() + listH + 22
        + (single and panel.picker:GetHeight() + 6 or 0))
end

local questEvents = CreateFrame("Frame")

-- near: only a quest in your log, or one still to do close to your level, counts.
local function HasQuestsForMe(dungeons, near)
    for _, dungeon in ipairs(dungeons) do
        for _, quest in ipairs(dungeon.quests) do
            if ForMe(quest) then
                if not near then return true end
                local status = Status(quest)
                if InLog(status) or status == NEXT or (status == MISSING and NearLevel(quest)) then
                    return true
                end
            end
        end
    end
end

-- Outside a dungeon: each dungeon with one of your quests in the log, or one you still
-- need near your level. Blackrock Spire's two halves stay separate here.
local function Nearby()
    local list = {}
    for _, dungeon in ipairs(ns.DungeonQuests) do
        if HasQuestsForMe({ dungeon }, true) then list[#list + 1] = dungeon end
    end
    return list
end

local byName = {}
for _, dungeon in ipairs(ns.DungeonQuests) do byName[dungeon.name] = dungeon end

-- The dungeon you last walked into, so entering one selects it once and a pick made from
-- the dropdown after that sticks until you enter another.
local enteredMap

local function Refresh()
    local inInstance = IsInInstance()
    local map, dungeons = CurrentDungeon()
    if not inInstance then wipe(dismissed) end
    if dungeons and map ~= enteredMap then
        enteredMap = map
        -- Blackrock Spire holds both halves; Lower comes first in the data.
        if S.Get("dqSingle") then S.Set("dqSelected", dungeons[1].name) return end
    elseif not inInstance then
        enteredMap = nil
    end
    local single = S.Get("dqSingle")
    local show, title, near
    if dungeons then
        -- With the dropdown it shows in any dungeon, so you can pick another one from there.
        show = S.Get("dqTracker") and not dismissed[map] and (single or HasQuestsForMe(dungeons))
    elseif not inInstance then
        show = S.Get("dqTracker") and S.Get("dqOutside")
        dungeons, title, near = Nearby(), "Dungeon Quests", true
    end
    if show and single then
        local picked = byName[S.Get("dqSelected")]
        if not picked then
            -- Nothing picked yet: the first dungeon near your level, or the first there is.
            S.Set("dqSelected", (dungeons and dungeons[1] or ns.DungeonQuests[1]).name)
            return
        end
        -- A dungeon picked by hand lists your quests there at any level short of grey.
        dungeons, title, near = { picked }, "Dungeon Quests", nil
    end
    if not show then
        shownMap = nil
        questEvents:UnregisterAllEvents()
        if panel then panel:Hide() end
        return
    end
    if not panel then BuildPanel() end
    shownMap = map or nil
    Render(dungeons, title, near)
    panel:Show()
    questEvents:RegisterEvent("QUEST_LOG_UPDATE")
    questEvents:RegisterEvent("QUEST_TURNED_IN")
    questEvents:RegisterEvent("PLAYER_LEVEL_UP")
    questEvents:RegisterEvent("QUEST_DATA_LOAD_RESULT")
end
-- Quest loads arrive one event per quest, dozens at once outside a dungeon, and the quest
-- log updates several times per kill, so all of them are gathered into a single redraw.
local redrawQueued
questEvents:SetScript("OnEvent", function()
    if redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0.2, function()
        redrawQueued = false
        if panel and panel:IsShown() then Refresh() end
    end)
end)

-- /nf dungeon: outside a dungeon it flips Show Outside Dungeons; inside one it shows or
-- closes the tracker, like the X. Showing it switches the tracker itself on if it was off.
function ns.ToggleDungeonQuests()
    local inInstance = IsInInstance()
    local map, dungeons = CurrentDungeon()
    if dungeons then
        if panel and panel:IsShown() then
            dismissed[map] = true
            panel:Hide()
            return
        end
        dismissed[map] = nil
        if not S.Get("dqTracker") then S.Set("dqTracker", true) end
        Refresh()
    elseif inInstance then
        ns.Print("This instance has no dungeon quests to show.")
        return
    else
        local on = not (S.Get("dqTracker") and S.Get("dqOutside"))
        if on and not S.Get("dqTracker") then S.Set("dqTracker", true) end
        S.Set("dqOutside", on)
    end
    ns.UI:RefreshPage(true)
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
-- The status column sits left of the buttons, where it would be with both of them, so it
-- lines up down the page whichever buttons a quest has.
local BUTTONS_W, PAGE_STATUS_W = 160, 80

-- opts: { status?, stripe? }, as on the tracker.
local function Row(parent, y, text, sub, onWaypoint, onChain, opts)
    opts = opts or {}
    local UI = ns.UI
    local x = UI.CONTENT_PAD + 20
    local width = (parent:GetWidth() or 0) > 0 and parent:GetWidth() or 960
    local full = width
    local right = x
    if onWaypoint then
        local btn = UI.KeepButton(parent, "waypoint", "Waypoint", 80, 20, onWaypoint)
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, y - 2)
        width, right = width - 90, right + 90
    end
    if onChain then
        local btn
        btn = UI.KeepButton(parent, "chain", "Chain", 60, 20, function() onChain(btn) end)
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, y - 2)
        width = width - 70
    end
    local fs = UI.KeepFont(parent, "quest", 13, nil)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    if opts.status then
        -- Sized to its text, like the tracker's, so it is never cut short.
        local st = UI.KeepFont(parent, "questStatus", 13, nil)
        st:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(x + BUTTONS_W), y - 4)
        st:SetJustifyH("RIGHT")
        st:SetWordWrap(false)
        st:SetText(opts.status)
        local statusW = math.max(PAGE_STATUS_W, math.ceil(st:GetStringWidth()))
        fs:SetWidth(full - x * 2 - BUTTONS_W - statusW - 10)
    else
        fs:SetWidth(width - x * 2)
    end
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    local h = math.ceil(fs:GetStringHeight()) + 4
    if sub then
        local s = UI.KeepFont(parent, "questSub", 11, nil, T.muted)
        s:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 14, -2)
        s:SetWidth(width - x * 2 - 14)
        s:SetJustifyH("LEFT")
        s:SetWordWrap(true)
        s:SetText(sub)
        h = h + math.ceil(s:GetStringHeight()) + 2
    end
    -- The band covers the whole row, buttons included, so neighbouring bands meet.
    if opts.stripe then
        local band = UI.Keep(parent, "questStripe", function(p)
            return ns.Solid(p, "BACKGROUND", STRIPE, STRIPE_ALPHA)
        end)
        band:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 6, y)
        band:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(x - 6), y)
        band:SetHeight(h + 6)
    end
    return h + 6
end

function ns.BuildQoLDungeonQuestsSettingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Every dungeon quest on WoW Forever and where it starts, from Wowhead's "
        .. "Forever dungeon quest guide. Levels are coloured like your quest log, and quests grey "
        .. "to you are left out. Waypoint marks the quest giver on your map; Chain lists every "
        .. "quest in its chain, in order. With the module switched on, entering a dungeon "
        .. "shows a tracker of its quests; close it with the X, and move it in Unlock Mode.", y); y = y - h

    -- The tracker's own on/off is the module switch (dqTracker), in the sidebar or the
    -- window header, so it has no row here.
    _, h = W:SectionHeader(parent, "DUNGEON QUEST TRACKER" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("dqShowDone", "Show Completed", "Also list the quests you have already done."),
        S.Toggle("dqAllFactions", "Show Both Factions",
            "List the other faction's quests, and other classes' class quests, on this page too.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("dqOutside", "Show Outside Dungeons",
            "Out in the world, list the dungeons with one of your quests in the log, or one you "
            .. "still need near your level. /nf dungeon and the X on the tracker switch this "
            .. "on and off.", "dqTracker"),
        S.Toggle("dqSingle", "Show Single Dungeon",
            "A dropdown on the tracker picks the one dungeon it lists, with all of your quests "
            .. "there. Entering a dungeon selects it.", "dqTracker")
    ); y = y - h
    return y
end

function ns.BuildQoLDungeonQuestsPage(parent, y)
    local W = ns.UI.Widgets
    local all = S.Get("dqAllFactions")
    for _, dungeon in ipairs(ns.DungeonQuests) do
        local levels = dungeon.levels and ("   %sLEVEL %d-%d%s|r"):format(
            InReach(dungeon) and IN_REACH or "|cff9a9ea6", dungeon.levels[1], dungeon.levels[2],
            InReach(dungeon) and "  IN RANGE" or "") or ""
        y = y - select(2, W:SectionHeader(parent, dungeon.name:upper() .. levels, y))
        if #dungeon.quests == 0 then
            y = y - Row(parent, y, MUTED .. "No quests known for this dungeon yet.|r")
        end
        -- Gathered by state first, then listed in RANK order, as on the tracker.
        local byRank = {}
        for r = 1, RANKS do byRank[r] = {} end
        for _, quest in ipairs(dungeon.quests) do
            if ForMe(quest, all) then
                local status = Status(quest)
                local show = status == DONE and S.Get("dqShowDone")
                    or status ~= DONE and not (status == MISSING and Grey(quest))
                if show then table.insert(byRank[RANK[status]], { quest = quest, status = status }) end
            end
        end
        local band = false
        for r = 1, RANKS do
            for _, item in ipairs(byRank[r]) do
                local quest, status = item.quest, item.status
                band = not band
                local side = all and quest[4] ~= "B" and (quest[4] == "A" and " (Alliance)" or " (Horde)") or ""
                local chain, step = Chain(quest)
                local sub = quest[6] .. "  -  " .. SHARE[quest[5]]
                if chain then sub = sub .. ("  -  Chain: step %d of %d"):format(step, #chain) end
                y = y - Row(parent, y, QuestLine(quest, status, side), sub,
                    quest[7] and function() SetWaypoint(quest) end,
                    chain and function(btn) OpenChain(btn, quest) end,
                    { status = status, stripe = band })
            end
        end
    end
    return y
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local zoneEvents = CreateFrame("Frame")
zoneEvents:SetScript("OnEvent", Refresh)
zoneEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")

hooksecurefunc(S, "Set", function(key)
    -- Switched on inside a dungeon, it selects that dungeon as if you had just entered.
    if key == "dqSingle" then enteredMap = nil end
    if key:find("^dq") and key ~= "dqPos" then Refresh() end
end)
hooksecurefunc(ns, "Apply", Refresh)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not S.Get("dqTracker") then return end
    if not panel then BuildPanel() end
    Render(byMap[UnitFactionGroup("player") == "Horde" and 389 or 36])
    panel.mover:Show()
    panel:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if panel then
        panel.mover:Hide()
        Refresh()
    end
end)
