-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_DungeonQuests.lua -- the QoL dungeon quest tracker: entering a
--  dungeon lists its quests for your faction, in your log or still to pick up and where;
--  and a page listing every dungeon's quests with where each one starts.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings
local T = ns.THEME

local DONE, ACTIVE, MISSING = "|cff9ca3afDone|r", "|cff4ade80In log|r", "|cfff87171Missing|r"
local MUTED = "|cff9ca3af"

-- Instance ID -> the dungeons that use it; Blackrock Spire holds both its halves.
local byMap = {}
for _, dungeon in ipairs(ns.DungeonQuests) do
    byMap[dungeon.map] = byMap[dungeon.map] or {}
    table.insert(byMap[dungeon.map], dungeon)
end

local panel, shownMap
local dismissed = {}   -- instance IDs closed by hand, until you leave

local function Status(questID)
    if C_QuestLog.IsQuestFlaggedCompleted(questID) then return DONE end
    if C_QuestLog.IsOnQuest(questID) then return ACTIVE end
    return MISSING
end

local function ForFaction(side, all)
    if side == "B" or all then return true end
    local faction = UnitFactionGroup("player")
    return (side == "A" and faction == "Alliance") or (side == "H" and faction == "Horde")
end

-- The client's title when it has one (in the player's language), the guide's otherwise.
local function Title(quest)
    local level = quest[3]
    local name = C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2]
    if not level then return name end
    local c = GetQuestDifficultyColor(level)
    return ("|cff%02x%02x%02x[%d]|r %s"):format(c.r * 255, c.g * 255, c.b * 255, level, name)
end

local SHARE = { [true] = "Shareable", [false] = "Not shareable", pre = "Needs a prerequisite" }

-- Marks where the quest giver stands. The tracking arrow is not confirmed on Forever, so the
-- waypoint goes on the map either way.
local function SetWaypoint(quest)
    local map = quest[7]
    if not C_Map.CanSetUserWaypointOnMap(map) then
        ns.Print("That quest giver's map does not take waypoints.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, quest[8] / 100, quest[9] / 100))
    if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    local info = C_Map.GetMapInfo(map)
    ns.Print(("Waypoint for %s: %s %.1f, %.1f"):format(C_QuestLog.GetTitleForQuestID(quest[1]) or quest[2],
        info and info.name or "", quest[8], quest[9]))
end

-------------------------------------------------------------------------------
--  In the dungeon
-------------------------------------------------------------------------------
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
    panel.close = ns.Button(panel, "X", 18, 18, function()
        if shownMap then dismissed[shownMap] = true end
        panel:Hide()
    end)
    panel.close:SetPoint("TOPRIGHT", -5, -5)
    panel.text = ns.Font(panel, 12, nil)
    panel.text:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.text:SetWidth(324)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetWordWrap(true)
    panel.mover = ns.UI.AttachMover(panel, "Dungeon Quests", function(pos) S.Set("dqPos", pos) end)
    local pos = S.Get("dqPos")
    if pos then
        panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
    end
    panel:Hide()
end

local function Render(dungeons)
    local lines, inLog, missing = {}, 0, 0
    for _, dungeon in ipairs(dungeons) do
        if #dungeons > 1 then lines[#lines + 1] = "|cff4db5f5" .. dungeon.name .. "|r" end
        for _, quest in ipairs(dungeon.quests) do
            if ForFaction(quest[4]) then
                local status = Status(quest[1])
                if status == ACTIVE then inLog = inLog + 1 end
                if status == MISSING then missing = missing + 1 end
                if status ~= DONE or S.Get("dqShowDone") then
                    lines[#lines + 1] = Title(quest) .. "  " .. status
                    if status == MISSING then lines[#lines + 1] = "    " .. MUTED .. quest[6] .. "|r" end
                end
            end
        end
    end
    if inLog + missing == 0 and not S.Get("dqShowDone") then lines[#lines + 1] = MUTED .. "All done here.|r" end
    local name = #dungeons > 1 and "Blackrock Spire" or dungeons[1].name
    panel.title:SetText(("%s  %s%d in log, %d missing|r"):format(name, MUTED, inLog, missing))
    panel.text:SetText(table.concat(lines, "\n"))
    panel:SetHeight(panel.title:GetStringHeight() + panel.text:GetStringHeight() + 22)
end

local questEvents = CreateFrame("Frame")
questEvents:SetScript("OnEvent", function()
    if panel and panel:IsShown() and shownMap then Render(byMap[shownMap]) end
end)

local function HasQuestsForMe(dungeons)
    for _, dungeon in ipairs(dungeons) do
        for _, quest in ipairs(dungeon.quests) do
            if ForFaction(quest[4]) then return true end
        end
    end
end

local function Refresh()
    local inInstance, kind = IsInInstance()
    local map = inInstance and kind == "party" and select(8, GetInstanceInfo())
    if not inInstance then wipe(dismissed) end
    local dungeons = map and byMap[map]
    if not (S.Get("enabled") and S.Get("dqTracker") and dungeons and not dismissed[map]
            and HasQuestsForMe(dungeons)) then
        shownMap = nil
        questEvents:UnregisterAllEvents()
        if panel then panel:Hide() end
        return
    end
    if not panel then BuildPanel() end
    shownMap = map
    Render(dungeons)
    panel:Show()
    questEvents:RegisterEvent("QUEST_LOG_UPDATE")
    questEvents:RegisterEvent("QUEST_TURNED_IN")
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
            "List the other faction's quests on this page too."),
        { type = "label", text = "" }
    ); y = y - h

    local all = S.Get("dqAllFactions")
    for _, dungeon in ipairs(ns.DungeonQuests) do
        _, h = W:SectionHeader(parent, dungeon.name:upper(), y); y = y - h
        for _, quest in ipairs(dungeon.quests) do
            if ForFaction(quest[4], all) then
                local status = Status(quest[1])
                if status ~= DONE or S.Get("dqShowDone") then
                    local side = all and quest[4] ~= "B" and (quest[4] == "A" and " (Alliance)" or " (Horde)") or ""
                    y = y - Row(parent, y, Title(quest) .. side .. "  " .. status,
                        quest[6] .. "  -  " .. SHARE[quest[5]],
                        quest[7] and function() SetWaypoint(quest) end)
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
    if key == "enabled" or (key:find("^dq") and key ~= "dqPos") then Refresh() end
end)
hooksecurefunc(ns, "Apply", Refresh)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
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
