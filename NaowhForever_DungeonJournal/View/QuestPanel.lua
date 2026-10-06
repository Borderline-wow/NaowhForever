-------------------------------------------------------------------------------
--  View/QuestPanel.lua -- a quest in your log, opened from its row in Dungeon Quests: its
--  level, name and where to hand it in; its objectives, each with its count and a bar; its
--  description; and its rewards as the Journal's own item rows (BiS star, upgrade arrow,
--  the item's tooltip and right-click menu), with Share, Track, Waypoint and Abandon. Drawn
--  by a view like a dungeon's page, in a side panel beside the window it was opened from
--  (Parts.SidePanel): the game's quest details live on the world map, and opening them from
--  addon code taints the map's quest pins (see Quests.Track). Made the first time a quest
--  is opened.
--
--  The game reads a quest's text and rewards through the quest selected in the log, so the
--  panel selects it to read them and puts your selection back straight after.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Quests = J.Quests
-- Forever has the money string only here: the global GetCoinTextureString is not loaded.
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local St = J.Style
local HAVE_RGB, CHECK, QUEST_CODE, INDENT = St.HAVE_RGB, St.CHECK, St.QUEST_CODE, St.INDENT
local QUEST_LEVEL_W, SECTION_SPACE, CHANCE_BAR_W = St.QUEST_LEVEL_W, St.SECTION_SPACE, St.CHANCE_BAR_W
local PLACE_DOT = St.PLACE_DOT

local View = J.View
local Parts = View.Parts
local Kinds, Plain = View.Kinds, Parts.Plain

local QuestPanel = {}
View.QuestPanel = QuestPanel

local REDRAW_DELAY = 0.15  -- a burst of quest log updates draws once
local TITLE_SIZE = 16
local TITLE_TOP, TITLE_GAP, TITLE_BOTTOM = 4, 4, 10
local OBJECTIVE_H, OBJECTIVE_BAR_H, OBJECTIVE_BAR_BOTTOM = 26, 3, 4

local panel, view
local shownID          -- the quest shown
local queued = false

-------------------------------------------------------------------------------
--  What the Journal knows about the quest: its dungeon's entry, for where to hand it in
-------------------------------------------------------------------------------
local function FindQuest(id)
    for _, dungeon in ipairs(J.Dungeons()) do
        local data = dungeon.quests
        for _, quest in ipairs(data and data.quests or {}) do
            if Quests.LoggedID(quest) == id then return quest, dungeon end
        end
    end
end

-- Where to take it: its turn-in when that is not its quest giver, else where it started.
local function HandIn(id, quest)
    local turnIn = J.QuestTurnIns[id]
    if turnIn then return "Hand in: " .. turnIn[4] end
    return quest and Plain(quest[6])
end

-------------------------------------------------------------------------------
--  Row kinds: the quest's title, and an objective
-------------------------------------------------------------------------------
-- Its level in the quest log's colour for you, its name, and under them its state in the
-- quest marks' colours, then where to hand it in.
Kinds.questTitle = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.level = ns.Font(row, 13)
        row.level:SetPoint("TOPLEFT", 0, -TITLE_TOP)
        row.level:SetWidth(QUEST_LEVEL_W)
        row.level:SetJustifyH("LEFT")
        row.name = ns.Font(row, TITLE_SIZE, nil, T.fg)
        row.name:SetPoint("TOPLEFT", QUEST_LEVEL_W, -TITLE_TOP + 1)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(true)
        row.where = ns.Font(row, 11, nil, T.muted)
        row.where:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -TITLE_GAP)
        row.where:SetJustifyH("LEFT")
        row.where:SetWordWrap(true)
        return row
    end,
    Set = function(row, name, level, complete, where)
        local width = row:GetWidth() - QUEST_LEVEL_W
        local color = level and GetQuestDifficultyColor(level) or T.fg
        row.level:SetText(level or "")
        row.level:SetTextColor(color.r, color.g, color.b)
        row.name:SetWidth(width)
        row.name:SetText(name)
        local state = complete and QUEST_CODE.ready .. "Complete|r" or QUEST_CODE.active .. "In log|r"
        row.where:SetWidth(width)
        row.where:SetText(where and state .. PLACE_DOT .. where or state)
        return TITLE_TOP + math.ceil(row.name:GetStringHeight()) + TITLE_GAP
            + math.ceil(row.where:GetStringHeight()) + TITLE_BOTTOM
    end,
}

-- What to do, with how far along on the right over a bar, as an item's drop chance: blue
-- while under way, green with a check once done.
local CHECK_ICON = "|T" .. CHECK .. ":0|t "

Kinds.objective = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = ns.Font(row, 12)
        row.text:SetPoint("LEFT", INDENT, 0)
        row.text:SetPoint("RIGHT", -(CHANCE_BAR_W + 12), 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.count = ns.Font(row, 11)
        row.count:SetPoint("TOPRIGHT", 0, -4)
        row.track = ns.Solid(row, "BORDER", T.line, 1)
        row.track:SetPoint("BOTTOMRIGHT", 0, OBJECTIVE_BAR_BOTTOM)
        row.track:SetSize(CHANCE_BAR_W, OBJECTIVE_BAR_H)
        row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
        row.bar:SetPoint("LEFT", row.track)
        row.bar:SetHeight(OBJECTIVE_BAR_H)
        return row
    end,
    ---@param objective table C_QuestLog.GetQuestObjectives' entry
    Set = function(row, objective)
        local done = objective.finished
        local have, need = objective.numFulfilled or 0, objective.numRequired or 0
        -- The count is on the right, so it comes off the front of the text ("0/4 Miners' Union Card").
        local text = (objective.text or ""):gsub("^%d+%s*/%s*%d+%s+", "")
        local color = done and HAVE_RGB or T.fg
        row.text:SetText((done and CHECK_ICON or "") .. text)
        row.text:SetTextColor(color.r, color.g, color.b)
        row.count:SetText(need > 0 and (have .. "/" .. need) or "")
        row.count:SetTextColor(color.r, color.g, color.b)
        local fill = need > 0 and math.min(have / need, 1) or (done and 1 or 0)
        local bar = done and HAVE_RGB or T.accent
        row.bar:SetColorTexture(bar.r, bar.g, bar.b, 1)
        row.bar:SetWidth(math.max(1, CHANCE_BAR_W * fill))
        row.bar:SetShown(fill > 0)
        row.track:SetShown(need > 0 or done)
        return OBJECTIVE_H
    end,
}

-------------------------------------------------------------------------------
--  Reading the quest: selected for the getters that read the selected quest, then put back
-------------------------------------------------------------------------------
local choices, rewards = {}, {}   -- item IDs, reused

local function ReadItems(out, count, get)
    wipe(out)
    for i = 1, count do
        local itemID = select(6, get(i))
        if itemID then out[#out + 1] = itemID end
    end
end

local function Read(id)
    local previous = C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(id)
    local description = GetQuestLogQuestText()
    ReadItems(choices, GetNumQuestLogChoices(id, true) or 0, GetQuestLogChoiceInfo)
    ReadItems(rewards, GetNumQuestLogRewards() or 0, GetQuestLogRewardInfo)
    local xp, money = GetQuestLogRewardXP() or 0, GetQuestLogRewardMoney() or 0
    if previous and previous ~= id then C_QuestLog.SetSelectedQuest(previous) end
    return description, xp, money
end

local function Items(list)
    for i = 1, #list do
        local itemID = list[i]
        view:Add("item", itemID, nil, view:ItemRank(itemID), view:ItemUpgrade(itemID))
    end
end

local function Draw()
    local id = shownID
    if not (id and C_QuestLog.GetLogIndexForQuestID(id)) then
        panel:Hide()   -- handed in or abandoned
        return
    end
    local quest, dungeon = FindQuest(id)
    panel.title:SetText(dungeon and dungeon.name:upper() or "QUEST")
    local description, xp, money = Read(id)

    view:Begin(nil, nil, nil)
    view.showChance = false   -- rewards, not drops
    view:Add("questTitle", C_QuestLog.GetTitleForQuestID(id) or (quest and quest[2]) or "",
        quest and Quests.Level(quest), C_QuestLog.IsComplete(id), HandIn(id, quest))

    local objectives = C_QuestLog.GetQuestObjectives(id) or {}
    if #objectives > 0 then
        view:Section("Objectives", #objectives)
        for i = 1, #objectives do view:Add("objective", objectives[i]) end
        view:Space(SECTION_SPACE)
    end

    if description and description ~= "" then
        view:Section("Description")
        view:Note(description)
        view:Space(SECTION_SPACE)
    end

    if #choices > 0 or #rewards > 0 or xp > 0 or money > 0 then
        view:Section("Rewards", #choices + #rewards)
        if #choices > 1 then view:Note("Choose one of these:") end
        Items(choices)
        if #rewards > 0 and #choices > 0 then view:Note("And also:") end
        Items(rewards)
        local gains = {}
        if xp > 0 then gains[#gains + 1] = BreakUpLargeNumbers(xp) .. " experience" end
        if money > 0 then gains[#gains + 1] = GetCoinTextureString(money) end
        if #gains > 0 then view:Note(table.concat(gains, PLACE_DOT)) end
    end
    view:Finish()

    -- The buttons for what can be done with it now.
    local buttons = panel.buttons
    ns.SetButtonText(buttons.Track, QuestUtils_IsQuestWatched(id) and "Untrack" or "Track")
    buttons.Share:SetEnabled(IsInGroup() and C_QuestLog.IsPushableQuest(id) == true)
    buttons.Abandon:SetEnabled(C_QuestLog.CanAbandonQuest(id) == true)
end

local function Flush()
    queued = false
    if panel:IsShown() then Draw() end
end

local function OnEvent()
    if queued then return end
    queued = true
    C_Timer.After(REDRAW_DELAY, Flush)
end

-------------------------------------------------------------------------------
--  The buttons
-------------------------------------------------------------------------------
local function Share()
    local index = C_QuestLog.GetLogIndexForQuestID(shownID)
    if index then QuestLogPushQuest(index) end
end

local function Track()
    if QuestUtils_IsQuestWatched(shownID) then
        C_QuestLog.RemoveQuestWatch(shownID)
    else
        C_QuestLog.AddQuestWatch(shownID)
    end
    Draw()
end

local function Waypoint()
    local quest = FindQuest(shownID)
    if quest then Quests.Waypoint(quest) end
end

-- As the game's own Abandon: selected and set to abandon, then asked first.
local function Abandon()
    local id = shownID
    local name = C_QuestLog.GetTitleForQuestID(id) or ""
    ns.Confirm(("Abandon %s?"):format(name), function()
        local previous = C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
        if previous and previous ~= id then C_QuestLog.SetSelectedQuest(previous) end
        panel:Hide()
    end)
end

local ACTIONS = { { "Share", Share }, { "Track", Track }, { "Waypoint", Waypoint }, { "Abandon", Abandon } }

local function Build()
    panel = Parts.SidePanel(ACTIONS)
    view = panel.view
    -- Its own redraw: it shows a quest, not a dungeon, so the view's would draw nothing.
    view.Redraw = Draw
    panel:SetScript("OnEvent", OnEvent)
    panel:SetScript("OnShow", function(self) self:RegisterEvent("QUEST_LOG_UPDATE") end)
    panel:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
end

-- Opens the quest (its ID in your log) beside the frame holding from, on whichever side has
-- room, and closes with that frame; opened again on the same quest, it closes.
---@param questID number
---@param from Frame
function QuestPanel.Show(questID, from)
    if not panel then Build() end
    if panel:IsShown() and shownID == questID then
        panel:Hide()
        return
    end
    shownID = questID
    Parts.ShowBeside(panel, from)
    Draw()
end
