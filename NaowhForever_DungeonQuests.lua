-------------------------------------------------------------------------------
--  NaowhForever_DungeonQuests.lua -- the QoL dungeon quest tracker: entering a
--  dungeon lists its quests for your faction, in your log or still to pick up and where;
--  and a page listing every dungeon's quests with where each one starts.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

-- In log is the quest log's own in-progress yellow.
local DONE, ACTIVE, MISSING = "Completed", "|cffffd100In log|r", "|cfff87171Missing|r"
-- A completed quest is drawn whole in the quest log's own completed green.
local COMPLETE = "|cff19ff19"
local MUTED = "|cff9ca3af"

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

-- Part of a chain done, and the next step not picked up yet.
local NEXT = "|cffff9933Next step|r"

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

local function AnyOn(ids)
    return OnID(ids) ~= nil
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
    if C_QuestLog.IsOnQuest(quest[1]) or AnyOn(quest.alt) or AnyOn(quest.steps) or AnyOn(quest.lead) then
        return ACTIVE
    end
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

-- plain leaves the level uncoloured, for a line that is coloured whole.
local function Title(quest, plain)
    local level = QuestLevel(quest)
    local name = C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2]
    if not level then return name end
    if plain then return ("[%d] %s"):format(level, name) end
    local c = GetQuestDifficultyColor(level)
    return ("|cff%02x%02x%02x[%d]|r %s"):format(c.r * 255, c.g * 255, c.b * 255, level, name)
end

-- The quest's line: title, then its status; suffix sits between them (the page's faction).
local function QuestLine(quest, status, suffix)
    suffix = suffix or ""
    if status == DONE then return COMPLETE .. Title(quest, true) .. suffix .. "  " .. DONE .. "|r" end
    return Title(quest) .. suffix .. "  " .. status
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

local function SetWaypoint(quest)
    local map, x, y = WaypointSpot(quest)
    if not map then return end
    PlaceWaypoint(C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2], map, x, y)
end

-- The ID of whichever step or version of the quest is in your log, if any.
local function LoggedID(quest)
    if C_QuestLog.IsOnQuest(quest[1]) then return quest[1] end
    return OnID(quest.alt) or OnID(quest.steps) or OnID(quest.lead)
end

-- The quest log opens on the world map in this engine. Not in combat: showing that panel
-- from addon code mid-fight is blocked.
local function OpenInQuestLog(id)
    if InCombatLockdown() then
        ns.Print("The quest log cannot be opened from here in combat.")
        return
    end
    if QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(id)
    elseif QuestLog_OpenToQuest and C_QuestLog.GetLogIndexForQuestID then
        QuestLog_OpenToQuest(C_QuestLog.GetLogIndexForQuestID(id))
    else
        C_QuestLog.SetSelectedQuest(id)
        ToggleQuestLog()
    end
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
    ns.Solid(panel, "BACKGROUND", T.bg, 0.85):SetAllPoints()
    ns.Border(panel)
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

local PIN, BODY_W = 14, 324

local function RowTooltip(row)
    local quest = row.quest
    if not quest then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2])
    GameTooltip:AddLine(quest[6], 1, 1, 1, true)
    if LoggedID(quest) then GameTooltip:AddLine("Click to open it in your quest log.", 0.3, 0.7, 0.95) end
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
    row:SetScript("OnClick", function(self)
        local id = self.quest and LoggedID(self.quest)
        if id then OpenInQuestLog(id) end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    panel.rows[i] = row
    return row
end

-- entries: { text, quest?, pin?, indent? }. Quest rows leave room for the pin whether or
-- not they have one, so every title lines up.
local function Layout(entries)
    local y = 0
    for i, entry in ipairs(entries) do
        local row = TrackerRow(i)
        local x = entry.quest and PIN + 3 or (entry.indent or 0)
        row.quest = entry.quest
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", x, 0)
        row.text:SetWidth(BODY_W - x)
        row.text:SetText(entry.text)
        row.pin:SetShown(entry.pin == true)
        row:EnableMouse(entry.quest ~= nil)
        local h = math.ceil(row.text:GetStringHeight()) + 2
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
        row:Show()
        y = y + h
    end
    for i = #entries + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.body:SetHeight(math.max(y, 1))
    return y
end

local function NearLevel(quest)
    local level, mine = QuestLevel(quest), UnitLevel("player")
    return not level or (level >= mine - BELOW and level <= mine + ABOVE)
end

-- near, outside a dungeon, drops the missing quests that are not close to your level.
local function Render(dungeons, title, near)
    local lines, inLog, missing, mine = {}, 0, 0, 0
    local function Add(text, extra)
        extra = extra or {}
        extra.text = text
        lines[#lines + 1] = extra
    end
    for _, dungeon in ipairs(dungeons) do
        if #dungeons > 1 then Add("|cff4db5f5" .. dungeon.name .. "|r") end
        -- Completed quests go under the rest of their dungeon.
        local completed = {}
        for _, quest in ipairs(dungeon.quests) do
            local status = ForMe(quest) and Status(quest)
            if status then mine = mine + 1 end
            if status and near and (status == MISSING or status == DONE) and not NearLevel(quest) then
                status = nil
            end
            if status then
                if status == ACTIVE then inLog = inLog + 1 end
                if status == MISSING or status == NEXT then missing = missing + 1 end
                if status == DONE then
                    if S.Get("dqShowDone") then
                        completed[#completed + 1] = { text = QuestLine(quest, status), quest = quest }
                    end
                else
                    -- A pin on every quest in your log (it tracks the quest), and on the rest
                    -- wherever the data knows where the quest giver stands.
                    Add(QuestLine(quest, status),
                        { quest = quest, pin = status == ACTIVE or WaypointSpot(quest) ~= nil })
                    if status == MISSING then Add(MUTED .. quest[6] .. "|r", { indent = PIN + 15 }) end
                    local nextSpot = status == NEXT and NextSpot(quest)
                    if nextSpot then
                        Add(MUTED .. "Next: " .. nextSpot[4] .. "|r", { indent = PIN + 15 })
                    end
                end
            end
        end
        for _, entry in ipairs(completed) do lines[#lines + 1] = entry end
    end
    local known = 0
    for _, dungeon in ipairs(dungeons) do known = known + #dungeon.quests end
    if known == 0 then
        Add(MUTED .. "No quests known for this dungeon yet.|r")
    elseif mine == 0 then
        Add(MUTED .. "No quests here for your faction and class.|r")
    elseif inLog + missing == 0 and not S.Get("dqShowDone") then
        Add(MUTED .. (near and "No dungeon quests near your level." or "All done here.") .. "|r")
    end
    local name = title or (#dungeons > 1 and "Blackrock Spire" or dungeons[1].name)
    panel.title:SetText(("%s  %s%d in log, %d missing|r"):format(name, MUTED, inLog, missing))
    local single = S.Get("dqSingle")
    panel.picker:SetShown(single)
    panel.body:ClearAllPoints()
    panel.body:SetPoint("TOPLEFT", single and panel.picker or panel.title, "BOTTOMLEFT", 0, -6)
    if single then panel.picker._refreshLabel() end
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
                if status == ACTIVE or status == NEXT or (status == MISSING and NearLevel(quest)) then
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
        -- A dungeon picked by hand lists all of your quests there, whatever their level.
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
-- Quest loads arrive one event per quest, dozens at once outside a dungeon, so they are
-- gathered into a single redraw.
local redrawQueued
questEvents:SetScript("OnEvent", function(_, event)
    if event == "QUEST_DATA_LOAD_RESULT" then
        if redrawQueued then return end
        redrawQueued = true
        C_Timer.After(0.2, function()
            redrawQueued = false
            if panel and panel:IsShown() then Refresh() end
        end)
        return
    end
    if panel and panel:IsShown() then Refresh() end
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
local function Row(parent, y, text, sub, onWaypoint)
    local UI = ns.UI
    local x = UI.CONTENT_PAD + 20
    local width = (parent:GetWidth() or 0) > 0 and parent:GetWidth() or 960
    if onWaypoint then
        local btn = ns.Button(parent, "Waypoint", 80, 20, onWaypoint)
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y - 2)
        width = width - 90
    end
    local fs = ns.Font(parent, 13, nil)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    fs:SetWidth(width - x * 2)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    local h = math.ceil(fs:GetStringHeight()) + 4
    if sub then
        local s = ns.Font(parent, 11, nil, T.muted)
        s:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 14, -2)
        s:SetWidth(width - x * 2 - 14)
        s:SetJustifyH("LEFT")
        s:SetWordWrap(true)
        s:SetText(sub)
        h = h + math.ceil(s:GetStringHeight()) + 2
    end
    return h + 6
end

function ns.BuildQoLDungeonQuestsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Every dungeon quest on WoW Forever and where it starts, from Wowhead's "
        .. "Forever dungeon quest guide. Levels are coloured like your quest log. Waypoint marks "
        .. "the quest giver on your map.", y); y = y - h

    _, h = W:SectionHeader(parent, "DUNGEON QUEST TRACKER" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("dqTracker", "Dungeon Quest Tracker",
            "Entering a dungeon shows its quests for your faction: the ones in your log, and the "
            .. "ones you still need, with where to get them. Close it with the X; it comes back "
            .. "next time you enter. Move it in Unlock Mode."),
        S.Toggle("dqShowDone", "Show Completed", "Also list the quests you have already done.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("dqAllFactions", "Show Both Factions",
            "List the other faction's quests, and other classes' class quests, on this page too."),
        S.Toggle("dqOutside", "Show Outside Dungeons",
            "Out in the world, list the dungeons with one of your quests in the log, or one you "
            .. "still need near your level. /nf dungeon and the X on the tracker switch this "
            .. "on and off.", "dqTracker")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("dqSingle", "Show Single Dungeon",
            "A dropdown on the tracker picks the one dungeon it lists, with all of your quests "
            .. "there. Entering a dungeon selects it.", "dqTracker"),
        { type = "label", text = "" }
    ); y = y - h

    local all = S.Get("dqAllFactions")
    for _, dungeon in ipairs(ns.DungeonQuests) do
        local levels = dungeon.levels and ("   |cff9a9ea6LEVEL %d-%d|r"):format(dungeon.levels[1], dungeon.levels[2]) or ""
        _, h = W:SectionHeader(parent, dungeon.name:upper() .. levels, y); y = y - h
        if #dungeon.quests == 0 then
            y = y - Row(parent, y, MUTED .. "No quests known for this dungeon yet.|r")
        end
        -- Two passes: open quests first, then the completed ones under them.
        for pass = 1, 2 do
            for _, quest in ipairs(dungeon.quests) do
                if ForMe(quest, all) then
                    local status = Status(quest)
                    local show = pass == 1 and status ~= DONE
                        or pass == 2 and status == DONE and S.Get("dqShowDone")
                    if show then
                        local side = all and quest[4] ~= "B" and (quest[4] == "A" and " (Alliance)" or " (Horde)") or ""
                        y = y - Row(parent, y, QuestLine(quest, status, side),
                            quest[6] .. "  -  " .. SHARE[quest[5]],
                            quest[7] and function() SetWaypoint(quest) end)
                    end
                end
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
