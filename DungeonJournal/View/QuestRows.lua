-------------------------------------------------------------------------------
--  View/QuestRows.lua -- your quests in the dungeon, as rows laid out like a table: the
--  quest's level in a column of its own; its title with where to go under it (or what to do
--  first); and on the right, in fixed slots so every column lines up, Chain as an icon, its
--  state as the game's own quest mark (a yellow ! to pick up, a ? in your log), and
--  Waypoint as a pin. Hover says what the mark means, how far along it is and who in your
--  party has it; right-click shares it, links it, tracks it or copies its Wowhead link.
--  The rules are Quests.lua's; the words and colours are here.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Tip = ns.Shared.Parts.Tip
-- WoW Forever's mark after the name of what is new in Forever, and its tooltip line.
local ForeverInline, ForeverLine = ns.Shared.Parts.ForeverInline, ns.Shared.Parts.ForeverLine
local IsForever, CARD_DROP = ns.Shared.Parts.IsForever, ns.Shared.Parts.CARD_DROP
local T = ns.THEME
local J = ns.Journal
local Quests = J.Quests

local St = J.Style
local QUEST_CODE, HAVE_RGB, BANG, QUESTION = St.QUEST_CODE, St.HAVE_RGB, St.BANG, St.QUESTION
local PIN, CHAIN, CHECK, GAP, INDENT = St.PIN, St.CHAIN, St.CHECK, St.GAP, St.INDENT
local PEOPLE, PARTY_SLOT, BAG = St.PEOPLE, St.PARTY_SLOT, St.BAG
local GetItemCount, GetItemIconByID, GetItemNameByID = C_Item.GetItemCount, C_Item.GetItemIconByID,
    C_Item.GetItemNameByID
local QUESTION_ICON = 134400   -- the game's question mark icon, for an item not loaded yet
local STRIPE = St.STRIPE
local QUEST_LEVEL_W, QUEST_TOP, QUEST_LINE_GAP, QUEST_BOTTOM = St.QUEST_LEVEL_W, St.QUEST_TOP, St.QUEST_LINE_GAP,
    St.QUEST_BOTTOM
local MARK, CHAIN_SLOT, WAYPOINT_SLOT = St.MARK, St.CHAIN_SLOT, St.WAYPOINT_SLOT

local View = J.View
local Kinds, Parts = View.Kinds, View.Parts
local IconButton, Plain = Parts.IconButton, Parts.Plain

-- The fixed slots on the right, from the right: Waypoint, the mark, then Chain.
local QUEST_RIGHT = St.QUEST_RIGHT
local MARK_SLOT = QUEST_RIGHT + WAYPOINT_SLOT + GAP * 2
-- The mark (a thin ! or ? in the middle of its box) goes this much right of its slot, so
-- what you see of it is midway between the pin's shape and the group icon's, which stand in
-- from their boxes by different amounts. Measured in game (2026-10-01): the space either
-- side of it was 20 and 28; this makes both 24.
local MARK_SHIFT = 4
local MARK_RIGHT = MARK_SLOT - MARK_SHIFT
-- Who in your group is on it, always shown (0 out of a group), so the slots never leave a gap.
local PARTY_RIGHT = MARK_SLOT + MARK + GAP * 2
local CHAIN_RIGHT = PARTY_RIGHT + PARTY_SLOT + GAP * 2
local RIGHT_W = CHAIN_RIGHT + CHAIN_SLOT
-- The empty right edge of the pin's and the chain's images at this size (Style's icons).
local PIN_MARGIN, CHAIN_MARGIN = 4, 2

-------------------------------------------------------------------------------
--  Words, marks and colours for each state
-------------------------------------------------------------------------------
local STATUS = {
    prereq = "Do first", prereqLog = "Do first", low = "Level %d to pick up", pickup = "To pick up",
    tooHigh = "Too high (%d)", next = "Next step", active = "In log", ready = "Complete",
}
local CHAIN_STATE = {
    active = QUEST_CODE.active .. "In log|r", done = QUEST_CODE.done .. "Finished|r",
    todo = QUEST_CODE.done .. "Not done|r",
}

-- "|cffff9933" -> { r, g, b }
local function RGB(code)
    local hex = code:match("^|c%x%x(%x%x%x%x%x%x)")
    return { r = tonumber(hex:sub(1, 2), 16) / 255, g = tonumber(hex:sub(3, 4), 16) / 255,
        b = tonumber(hex:sub(5, 6), 16) / 255 }
end

-- The game's quest marks, as every quest giver shows them: a yellow ! to pick up, a grey ?
-- while it is in your log, a yellow ? to hand in. The tinted ones are greyed and coloured
-- with the state: orange to do something first, grey while your level is too low, red when
-- it is too high for you. (The game's newer in-progress icon, a speech bubble with dots,
-- did not read as a quest.)
local MARKS = {
    pickup = { BANG }, next = { BANG },
    prereq = { BANG, RGB(QUEST_CODE.prereq) }, prereqLog = { BANG, RGB(QUEST_CODE.prereqLog) },
    low = { BANG, RGB(QUEST_CODE.low) }, tooHigh = { BANG, RGB(QUEST_CODE.tooHigh) },
    active = { QUESTION, T.muted }, ready = { QUESTION },
}
-- Do first needs no words on hover: the line under the title names the quest to do.
local SAID_BELOW = { prereq = true, prereqLog = true }

-- The state the row shows: a quest to pick up that is too high for you is told apart.
local function Shown(entry)
    return entry.tooHigh and "tooHigh" or entry.kind
end

local function StatusText(entry)
    local shown = Shown(entry)
    local text = STATUS[shown]
    if shown == "low" then text = text:format(Quests.MinLevel(entry.quest)) end
    if shown == "tooHigh" then text = text:format(entry.level) end
    return QUEST_CODE[shown] .. text .. "|r"
end

local function PaintMark(mark, entry)
    local look = MARKS[Shown(entry)] or MARKS.pickup
    local tint = look[2]
    mark:SetTexture(look[1])
    mark:SetDesaturated(tint ~= nil)
    if tint then mark:SetVertexColor(tint.r, tint.g, tint.b) else mark:SetVertexColor(1, 1, 1) end
end

-------------------------------------------------------------------------------
--  The chain menu
-------------------------------------------------------------------------------
-- Every quest of the chain in order with how far you are, the dungeon quest marked. A step
-- not done yet with somewhere to go puts a waypoint there when clicked; a quest in your log
-- can be tracked from here.
local function OpenChain(owner, quest)
    local chain, own = Quests.Chain(quest)
    if not chain then return end
    local logged = Quests.LoggedID(quest)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(("%s: step %d of %d"):format(Quests.Name(quest), own, #chain))
        root:CreateTitle(ns.Color("muted", "Click a step for a waypoint."))
        for i, step in ipairs(chain) do
            local state, id = Quests.StepState(step)
            local name = Quests.StepName(id)
            local text = ("%d.  %s  %s"):format(i, name, CHAIN_STATE[state])
            if state == "done" then text = QUEST_CODE.done .. ("%d.  %s|r  "):format(i, name) .. CHAIN_STATE.done end
            -- The one you finish inside the dungeon; every step above it leads to it.
            if i == own then text = text .. "  " .. ns.Color("accentSoft", "(dungeon quest)") end
            if state ~= "done" and (state == "active" or Quests.StepHasSpot(step, id)) then
                root:CreateButton(text, function() Quests.StepWaypoint(step, state, id, name) end)
            else
                root:CreateTitle(text, WHITE_FONT_COLOR)
            end
        end
        if logged then
            root:CreateDivider()
            root:CreateButton("Track in Quest Log", function() Quests.Track(logged) end)
        end
    end)
end

-------------------------------------------------------------------------------
--  The right-click menu
-------------------------------------------------------------------------------
-- The quest's link for chat, once the client has the quest; nil before.
local function QuestLink(id)
    return GetQuestLink(id)
end

-- Into the chat box you have open. Never opened from here: opening it from addon code
-- (ChatFrameUtil.OpenChat) taints it, and the game then blocks the next message you send.
local function LinkInChat(id)
    local link = QuestLink(id)
    if link and not ChatFrameUtil.InsertLink(link) then
        ns.Print("Open your chat box first (Enter), then link the quest.")
    end
end

-- Sharing first, then finding it, then its Wowhead page. The menu keeps the quest it was
-- opened on, not the row's entry, which a redraw may reuse for another quest.
local function OpenQuestMenu(row)
    local entry = row.entry
    local quest, logged, name, canWaypoint = entry.quest, entry.loggedID, entry.name, entry.canWaypoint
    local linkID = logged or quest[1]
    local shareable = logged ~= nil and IsInGroup() and C_QuestLog.IsPushableQuest(logged)
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(name)
        root:CreateButton(SHARE_QUEST, function()
            QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(logged))
        end):SetEnabled(shareable)
        root:CreateButton("Link in Chat", function() LinkInChat(linkID) end):SetEnabled(QuestLink(linkID) ~= nil)
        root:CreateDivider()
        if canWaypoint then root:CreateButton("Waypoint", function() Quests.Waypoint(quest) end) end
        if Quests.Chain(quest) then root:CreateButton("Show Chain", function() OpenChain(row, quest) end) end
        if logged then root:CreateButton("Track in Quest Log", function() Quests.Track(logged) end) end
        root:CreateDivider()
        root:CreateButton("Copy Wowhead Link", function() ns.ShowCopyCard("quest", "Quest ID", quest[1], name) end)
    end)
end

-------------------------------------------------------------------------------
--  The hover card: only what the row does not show already
-------------------------------------------------------------------------------
-- A quest in your log: each objective with its count, the ones done ticked and greyed.
local CHECK_ICON = "|T" .. CHECK .. ":0|t "

local function ProgressLines(entry)
    if not entry.inLog then return end
    local objectives = C_QuestLog.GetQuestObjectives(entry.loggedID)
    for _, objective in ipairs(objectives or {}) do
        local text = objective.text
        if text and text ~= "" then
            if objective.finished then
                GameTooltip:AddLine(CHECK_ICON .. text, T.muted.r, T.muted.g, T.muted.b, true)
            else
                GameTooltip:AddLine(text, 1, 1, 1, true)
            end
        end
    end
end

-- The quest itself, a line each, a muted label before what it says: its level and from when
-- you can pick it up, who it is for, where it starts, its place in its chain (the quest
-- before and after) and whether it can be shared.
local SIDE = { A = "Alliance", H = "Horde", B = "Alliance and Horde" }

local function Fact(label, text)
    GameTooltip:AddLine(ns.Color("muted", label .. "  ") .. text, 1, 1, 1, true)
end

local function DetailLines(entry)
    local quest = entry.quest
    local need = Quests.MinLevel(quest)
    if entry.level then
        Fact("Level", entry.level .. (need and ns.Color("muted", ("   picked up from %d"):format(need)) or ""))
    end
    local class = quest.class
    Fact("For", class and (class:sub(1, 1) .. class:sub(2):lower()) .. "s" or SIDE[quest[4]] or "everyone")
    -- As the guide writes it, its coordinates in it.
    if quest[6] and quest[6] ~= "" then Fact("Starts", Plain(quest[6])) end
    local chain, own = Quests.Chain(quest)
    if chain then
        local around = {}
        if chain[own - 1] then around[#around + 1] = "after " .. Quests.StepName(select(2, Quests.StepState(chain[own - 1]))) end
        if chain[own + 1] then around[#around + 1] = "then " .. Quests.StepName(select(2, Quests.StepState(chain[own + 1]))) end
        Fact("Chain", ("step %d of %d"):format(own, #chain) .. (#around > 0 and ns.Color("muted", ": ") .. table.concat(around, ", ") or ""))
    end
    if quest[5] == true then
        Fact("Sharing", "can be shared with your party")
    elseif quest[5] == false then
        Fact("Sharing", "cannot be shared")
    end
end

-- Your party, one line each, from what the game shows of them: on the quest, the wrong
-- class for it, or too low to pick it up; otherwise only that they are not on it, since
-- whether they have done it is theirs to know.
local function PartyLines(entry)
    local members = GetNumSubgroupMembers()
    if members == 0 then return end
    local quest = entry.quest
    local need = Quests.MinLevel(quest)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Your party", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    for i = 1, members do
        local unit = "party" .. i
        local level = UnitLevel(unit)
        local text, color
        if Quests.UnitOnQuest(unit, quest, entry.loggedID) then
            text, color = "has it", HAVE_RGB
        elseif quest.class and select(2, UnitClass(unit)) ~= quest.class then
            text, color = "not their class", T.muted
        elseif need and level and level > 0 and level < need then
            text, color = ("level %d, needs %d"):format(level, need), T.muted
        else
            text, color = "not on it", T.muted
        end
        GameTooltip:AddDoubleLine(UnitName(unit) or "?", text, T.fg.r, T.fg.g, T.fg.b, color.r, color.g, color.b)
    end
end

-- A faction's hand-in on hover: what one gives, what it takes against what your bags hold,
-- and where its items come from (some of what gives them, in each zone).
local function TurnInLines(entry)
    local turnin, held = entry.turnin, entry.held
    GameTooltip:AddLine(("+%d reputation each time you hand it in"):format(turnin.rep), 1, 1, 1)
    if held > 0 then
        GameTooltip:AddLine(QUEST_CODE.ready .. (held == 1 and "Your bags hold enough to hand it in once"
            or ("Your bags hold enough to hand it in %d times"):format(held)) .. "|r")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("It takes", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    local takes = turnin.takes
    for i = 1, #takes, 2 do
        local id, need = takes[i], takes[i + 1]
        local have = GetItemCount(id)
        local color = have >= need and HAVE_RGB or T.muted
        GameTooltip:AddDoubleLine(("|T%d:0|t %d %s"):format(GetItemIconByID(id) or QUESTION_ICON, need,
            GetItemNameByID(id) or ("item " .. id)), ("%d in your bags"):format(have),
            T.fg.r, T.fg.g, T.fg.b, color.r, color.g, color.b)
    end
    local from = turnin.from
    if from then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Where to get them", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        for _, place in ipairs(from) do
            local more = place[2] - (#place - 2)
            GameTooltip:AddLine(ns.Color("fg", place[1]) .. "  " .. table.concat(place, ", ", 3)
                .. (more > 0 and (" and %d more"):format(more) or ""), T.muted.r, T.muted.g, T.muted.b, true)
        end
    end
end

local function QuestEnter(row)
    row.hover:Show()
    local entry = row.entry
    local kind = entry.kind
    if not Tip(row, "ANCHOR_CURSOR_RIGHT", 16, 0) then return end
    GameTooltip:SetText(entry.name)
    if row.forever then GameTooltip:AddLine(ForeverLine()) end
    if entry.turnin then
        TurnInLines(entry)
        PartyLines(entry)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(entry.canWaypoint and "Pin: a waypoint to who takes it    Right-click: Share, Link"
            or "Right-click: Share, Link", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        GameTooltip:Show()
        return
    end
    -- One line each (the quest tracker): where to go, which the row leaves out.
    if row:GetParent().tight then
        GameTooltip:AddLine(Plain(entry.where), T.muted.r, T.muted.g, T.muted.b, true)
    end
    if not SAID_BELOW[kind] then GameTooltip:AddLine(StatusText(entry)) end
    if entry.tooHigh then
        GameTooltip:AddLine(("It is level %d, five or more above you, so it will be hard for now.")
            :format(entry.level), 1, 1, 1, true)
    end
    -- In your log: where it stands first.
    ProgressLines(entry)
    GameTooltip:AddLine(" ")
    DetailLines(entry)
    PartyLines(entry)
    GameTooltip:AddLine(" ")
    local hints = (entry.loggedID and "Click: details    " or "") .. "Right-click: Share, Link, Track"
        .. (entry.canWaypoint and "    Pin: waypoint" or "")
    GameTooltip:AddLine(hints, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function QuestLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

-- Right-click: the menu. Left-click on a quest in your log: its details beside the window.
local function QuestMouseUp(row, button)
    if button == "RightButton" then
        OpenQuestMenu(row)
    elseif row.entry.loggedID then
        View.QuestPanel.Show(row.entry.loggedID, row)
    end
end

-- A click puts the waypoint on your map; a right-click shares where it is, with a map pin
-- link the reader can click for the same pin.
local function WaypointClicked(button, mouse)
    local quest = button:GetParent().quest
    if mouse ~= "RightButton" then return Quests.Waypoint(quest) end
    local name, map, x, y, note, why = Quests.Spot(quest)
    if map then
        Parts.SharePlace(button, "Share the waypoint", name, map, x, y, note)
    elseif why then
        ns.Print(why)
    end
end

local function ChainClicked(button)
    if button:GetParent().entry.turnin then return end   -- a hand-in's bag: its hover says it all
    OpenChain(button, button:GetParent().quest)
end

-- Its step in its chain, always shown so the slots line up: a quest on its own is 1/1,
-- muted, as the group count is at 0.
local function PaintChain(button)
    local color = button.chained and T.accentSoft or T.muted
    button.icon:SetVertexColor(color.r, color.g, color.b)
    button.label:SetTextColor(color.r, color.g, color.b)
end

local function ChainLeave(button)
    PaintChain(button)
    GameTooltip:Hide()
end

-- Who in your group is on it too: the blue of the row's other icons when someone is, muted
-- at 0. Hover names them.
local function PaintParty(button)
    local color = button.count > 0 and T.accentSoft or T.muted
    button.icon:SetVertexColor(color.r, color.g, color.b)
    button.label:SetTextColor(color.r, color.g, color.b)
end

-- A group member's role, on the right of their name: the game's small role icon and its
-- name. Nothing for no role (none is chosen outside the dungeon finder).
local ROLES = {}
for code, atlas in pairs(St.ROLE_ATLAS) do
    ROLES[code] = CreateAtlasMarkup(atlas, 14, 14) .. " " .. St.ROLE_NAME[code]
end

local function PartyEnter(button)
    button.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    button.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
    local entry = button:GetParent().entry
    if not Tip(button, "ANCHOR_TOP") then return end
    if not IsInGroup() then
        GameTooltip:SetText("Not in a group", 1, 1, 1)
        GameTooltip:AddLine("In a group, this counts who else is on the quest.", T.muted.r, T.muted.g, T.muted.b)
    elseif button.count == 0 then
        GameTooltip:SetText("No one else in your group is on this quest", 1, 1, 1)
    else
        GameTooltip:SetText("In your group on this quest", 1, 1, 1)
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if Quests.UnitOnQuest(unit, entry.quest, entry.loggedID) then
                -- In their class colour; green while the game has not said their class.
                local _, class = UnitClass(unit)
                local color = class and not issecretvalue(class) and C_ClassColor.GetClassColor(class) or HAVE_RGB
                local role = UnitGroupRolesAssigned(unit)
                role = not issecretvalue(role) and ROLES[J.Team.RoleCode(role)] or ""
                GameTooltip:AddDoubleLine(UnitName(unit) or "?", role, color.r, color.g, color.b,
                    T.muted.r, T.muted.g, T.muted.b)
            end
        end
        if not entry.inLog and J.Sharing.On() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to ask them, one at a time, to share it (they need Naowh Forever).",
                T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, true)
        end
    end
    GameTooltip:Show()
end

-- A quest you do not have: ask the members on it to share it (Sharing.lua says the rest in
-- chat), while Quest Share Requests is on. One you have shares from its right-click menu.
local function PartyClicked(button)
    local entry = button:GetParent().entry
    if button.count > 0 and not entry.inLog then J.Sharing.Ask(entry) end
end

local function PartyLeave(button)
    PaintParty(button)
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
--  The row
-------------------------------------------------------------------------------
Kinds.quest = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
        row.stripe:SetAllPoints()
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.04)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.divider = ns.Solid(row, "BORDER", T.line, 0.6)
        row.divider:SetPoint("BOTTOMLEFT", INDENT, 0)
        row.divider:SetPoint("BOTTOMRIGHT")
        ns.Hairline(row.divider, "h")
        row.waypoint = IconButton(row, WaypointClicked, PIN, PIN_MARGIN)
        row.waypoint.tip = "Waypoint"
        row.waypoint.hint = "Right-click to share it in chat, or copy it."
        row.waypoint:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.chain = IconButton(row, ChainClicked, CHAIN, CHAIN_MARGIN)
        row.chain:SetWidth(CHAIN_SLOT)
        -- Lined up to the pixel, "1/1" with "7/7" (Parts.Cells); up to "12/12".
        row.chain.label = Parts.Cells(row.chain, 11, T.accentSoft, 5)
        row.chain.label[1]:SetPoint("RIGHT", row.chain.icon, "LEFT", -3, 0)
        row.chain:SetScript("OnLeave", ChainLeave)
        row.party = IconButton(row, PartyClicked, PEOPLE)
        row.party:SetWidth(PARTY_SLOT)
        row.party.label = Parts.Cells(row.party, 11, T.accentSoft, 2)
        row.party.label[1]:SetPoint("RIGHT", row.party.icon, "LEFT", -3, 0)
        row.party:SetScript("OnEnter", PartyEnter)
        row.party:SetScript("OnLeave", PartyLeave)
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetSize(MARK, MARK)
        row.level = ns.Font(row, 12)
        row.level:SetPoint("TOPLEFT", INDENT, -(QUEST_TOP + 1))
        row.level:SetWidth(QUEST_LEVEL_W)
        row.level:SetJustifyH("LEFT")
        row.title = ns.Font(row, 13, nil, T.fg)
        row.title:SetPoint("TOPLEFT", INDENT + QUEST_LEVEL_W + 4, -QUEST_TOP)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.where = ns.Font(row, 11, nil, T.muted)
        row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -QUEST_LINE_GAP)
        row.where:SetJustifyH("LEFT")
        row.where:SetWordWrap(true)
        row:EnableMouse(true)
        row:SetScript("OnEnter", QuestEnter)
        row:SetScript("OnLeave", QuestLeave)
        row:SetScript("OnMouseUp", QuestMouseUp)
        return row
    end,
    ---@param entry JournalQuestEntry the view's own entry
    ---@param index number its place in the list: every other one is striped
    Set = function(row, entry, index)
        row.entry, row.quest = entry, entry.quest
        row.stripe:SetShown(index % 2 == 0)
        row.hover:Hide()
        row.waypoint:SetShown(entry.canWaypoint)
        local chain = row.chain
        if entry.turnin then
            -- A hand-in's slot is its bag: short of one, how many of what it takes you carry,
            -- of how many ("5/20"); with enough, how many hand-ins ("17"), in the accent. Either
            -- fits the slot's five places.
            local takes, held = entry.turnin.takes, entry.held
            local have = GetItemCount(takes[1])
            chain.icon:SetTexture(BAG)
            chain.chained = held > 0
            chain.label:SetText(held == 0 and #takes == 2 and have .. "/" .. takes[2] or held)
            chain.tip = held > 0 and ("In your bags: enough to hand it in %d %s"):format(held,
                held == 1 and "time" or "times") or "In your bags: not enough to hand it in yet"
        else
            chain.icon:SetTexture(CHAIN)
            chain.chained = entry.steps ~= nil
            chain.label:SetText(chain.chained and entry.step .. "/" .. entry.steps or "1/1")
            chain.tip = chain.chained and ("Chain: step %d of %d"):format(entry.step, entry.steps)
                or "On its own: no quest leads to it or follows it"
        end
        PaintChain(chain)
        PaintMark(row.mark, entry)
        local color = entry.level and GetQuestDifficultyColor(entry.level) or T.fg
        row.level:SetText(entry.level or "")
        row.level:SetTextColor(color.r, color.g, color.b)
        -- Narrow (the map panel): the mark and icons on the title's line, on the right in the
        -- same slots as the wide page, and where to go under both, the row's whole width.
        -- Tight (the quest tracker): one line, the title and the icons on its right; where to
        -- go is in the hover card.
        local view = row:GetParent()
        local tight = view.tight
        local compact = view.compact and not tight
        local left = INDENT + QUEST_LEVEL_W + 4
        local width = row:GetWidth() - left - RIGHT_W - GAP * 2
        row.party.count = entry.party
        row.party.label:SetText(entry.party)
        PaintParty(row.party)
        row.title:SetWidth(width)
        row.forever = entry.quest ~= nil and IsForever("quests", entry.quest[1])
        row.title:SetText(row.forever and entry.name .. ForeverInline(11, CARD_DROP) or entry.name)
        row.where:SetWidth(compact and row:GetWidth() - left or width)
        row.where:SetText(Plain(entry.where))
        row.where:SetShown(not tight)
        local height = QUEST_TOP + math.ceil(row.title:GetStringHeight()) + QUEST_BOTTOM
        if not tight then height = height + QUEST_LINE_GAP + math.ceil(row.where:GetStringHeight()) end
        row.mark:ClearAllPoints()
        row.chain:ClearAllPoints()
        row.waypoint:ClearAllPoints()
        row.party:ClearAllPoints()
        -- Level with the title (narrow) or the row's middle.
        local anchor, y = "RIGHT", 0
        if compact then
            anchor, y = "TOPRIGHT", -(QUEST_TOP + math.ceil(row.title:GetStringHeight()) / 2)
        end
        row.party:SetPoint("RIGHT", row, anchor, -PARTY_RIGHT, y)
        row.waypoint:SetPoint("RIGHT", row, anchor, -QUEST_RIGHT, y)
        row.mark:SetPoint("RIGHT", row, anchor, -MARK_RIGHT, y)
        row.chain:SetPoint("RIGHT", row, anchor, -CHAIN_RIGHT, y)
        return height
    end,
}
