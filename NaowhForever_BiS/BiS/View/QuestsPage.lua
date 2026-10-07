-------------------------------------------------------------------------------
--  View/QuestsPage.lua -- the BiS List's Quests page: every quest that rewards a pick on your
--  list you do not have yet, by the zone it starts in, lowest first. Each is the Dungeon
--  Journal's quest row (what to do first, the level it needs, its chain, its waypoint, share
--  and track), with the picks it gives under it as the Journal's item rows. Drawn by a Journal
--  view, made the first time the page opens (the Journal loads after the BiS List).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local Q = B.Quests

local NONE = "No quest gives a pick on your list that you do not have yet."
local CHOICE = "A choice among its rewards: pick this one."

local function Draw(view)
    if not view:IsVisible() then return end
    local J = ns.Journal
    local St = J.Style
    local indent = St.INDENT + St.QUEST_LEVEL_W + 4
    view:Begin(nil, nil, nil)
    view.showChance = false   -- rewards, not drops
    local listed = 0
    for _, zone in ipairs(Q.Zones(B.Lists.List())) do
        local entries = J.Quests.List(zone.data, zone.out, zone.pool)
        if #entries > 0 then
            listed = listed + #entries
            view:Section(zone.name, #entries)
            for i, entry in ipairs(entries) do
                view:Add("quest", entry, i)
                local id = entry.quest[1]
                view.left, view.width = indent, view:GetWidth() - indent
                for _, itemID in ipairs(Q.Rewards(id)) do
                    if Q.Wanted(itemID) then
                        view:Add("item", itemID, nil, view:ItemRank(itemID), view:ItemUpgrade(itemID))
                    end
                end
                if Q.Choice(id) then view:Note(CHOICE) end
                view.left, view.width = 0, view:GetWidth()
            end
            view:Space(St.SECTION_SPACE)
        end
    end
    if listed == 0 then view:Note(NONE) end
    view.questsDrawn = true   -- the quest log redraws it
    view:Finish()
end

--- The Quests page, in parent, at width.
---@param parent Frame
---@return Frame view
function B.View.QuestsPage(parent)
    local view = ns.Journal.View.New(parent)
    view.Redraw = Draw
    return view
end
