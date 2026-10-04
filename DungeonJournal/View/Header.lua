-------------------------------------------------------------------------------
--  View/Header.lua -- the top of a dungeon's page, as two lines: its name, with a pin that
--  shows its entrance on your map; under it, where it is (its zone in the colour of whose
--  ground it is, and its levels) and, on the right, small stats of what is there for you.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Tip = ns.Shared.Parts.Tip
local T = ns.THEME
local J = ns.Journal
local Loot = J.Loot
local Quests = J.Quests

local St = J.Style
local BIS_CODE, LOOK_CODE, LOOK_RGB, TERRITORY_CODE = St.BIS_CODE, St.LOOK_CODE, St.LOOK_RGB, St.TERRITORY_CODE
local BANG, HANGER, PLACE_DOT = St.BANG, St.HANGER, St.PLACE_DOT
local STAR, BIS_RGB = St.STAR, St.BIS_RGB
local STAT_ICON, STAT_GAP, STAT_SPACE, STAT_LINE_H = St.STAT_ICON, St.STAT_GAP, St.STAT_SPACE, St.STAT_LINE_H
local TITLE_SIZE, TITLE_H, TITLE_GAP = St.TITLE_SIZE, St.TITLE_H, St.TITLE_GAP
local WHERE_H, HEADER_PAD = St.WHERE_H, St.HEADER_PAD

local Kinds = J.View.Kinds

local PIN_BOX, PIN_ICON = 20, 18
-- The entrance pin is the game's own, as its world map marks dungeon and raid entrances (the
-- "dungeon" and "raid" atlases), in its own colours: a touch faded at rest, full on hover.
local PIN_ATLAS = { dungeon = "dungeon", raid = "raid" }
local PIN_REST = 0.85
-- The round mark on the title's middle. Measured in game (2 Oct 2026): 2px under it put the
-- mark 4px below the capitals' middle, and 2px above it level with them, which read as high
-- beside the lower-case letters; on the middle it sits between the two.
local PIN_DROP = 0
local STAT_H = 16
-- Narrow: the stats' line starts this far under the where line, and the header ends this far
-- under what it holds.
local COMPACT_STAT_TOP, COMPACT_PAD = 6, 12

-------------------------------------------------------------------------------
--  Stats: an icon or none, and a count; hover says what it counts
-------------------------------------------------------------------------------
-- The tooltip is written when it opens, from the count and the stat's own line. A stat a
-- click does something on (the BiS's) says what, as a hint under it, while the click works.
local function StatEnter(stat)
    if not Tip(stat, "ANCHOR_BOTTOM") then return end
    local tip = stat.done and stat.doneTip or stat.total == 0 and stat.noneTip
        or stat.tipFormat:format(stat.have, stat.total)
    GameTooltip:SetText(tip, 1, 1, 1)
    if stat.onClick and stat.canClick() then
        GameTooltip:AddLine(stat.hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    end
    GameTooltip:Show()
end

local function StatClicked(stat, button)
    if button == "LeftButton" and stat.onClick and stat.canClick() then stat.onClick() end
end

-- label is the word after the number ("Quests"), muted. tint greys the icon and colours it
-- (the grey ?, the cyan hanger); without, its own colours. gap is from the icon's box to the
-- number, per icon, so the space you see between the shape and the number is the same for
-- all: the quest marks are thin shapes in a wide box, the hanger fills its box. dy lifts or drops a shape that sits off centre in its box.
local function Stat(parent, label, tipFormat, doneTip, icon, tint, gap, dy)
    local stat = CreateFrame("Frame", nil, parent)
    stat:SetHeight(STAT_H)
    stat:EnableMouse(true)
    stat.tipFormat, stat.doneTip = tipFormat, doneTip
    stat.label = ns.Color("muted", " " .. label)   -- after the number, saying what it counts
    stat.text = ns.Font(stat, 12, nil, T.fg)
    stat.gap = icon and (gap or STAT_SPACE) or 0
    if icon then
        stat.icon = stat:CreateTexture(nil, "ARTWORK")
        -- Drawn from the image's smaller sizes, as the window's logo is: sharp at this size.
        stat.icon:SetTexture(icon, nil, nil, "TRILINEAR")
        stat.icon:SetSize(STAT_ICON, STAT_ICON)
        stat.icon:SetPoint("LEFT", 0, dy or 0)
        if tint then
            stat.icon:SetDesaturated(true)
            stat.icon:SetVertexColor(tint.r, tint.g, tint.b)
        end
        stat.text:SetPoint("LEFT", stat.icon, "RIGHT", stat.gap, -(dy or 0))
    else
        stat.text:SetPoint("LEFT")
    end
    stat:SetScript("OnEnter", StatEnter)
    stat:SetScript("OnLeave", GameTooltip_Hide)
    stat:SetScript("OnMouseUp", StatClicked)
    return stat
end

-- The BiS stat, on a dungeon's page and a faction's, opens the BiS List's window while the
-- module is on.
local function OpenBisList()
    ns.OpenBisWindow()
end

local function OpensBisList(stat)
    stat.onClick, stat.canClick, stat.hint = OpenBisList, Loot.BisOn, "Click to see your BiS."
end

-- Shown while there is something to count, hidden otherwise unless always ("0/0"): how many
-- you have of how many ("2/7"), in code's colour when given. All of them had (every quest
-- done, every BiS or look yours): a green check in its place, and its own line on hover.
local DONE = ("|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(St.CHECK, St.HAVE_RGB.r * 255,
    St.HAVE_RGB.g * 255, St.HAVE_RGB.b * 255)

local function SetStat(stat, have, total, code, always)
    stat.have, stat.total, stat.done = have, total, total > 0 and have == total
    stat:SetShown(total > 0 or always == true)
    if not stat:IsShown() then return end
    local count = code and code .. have .. "/" .. total .. "|r" or have .. "/" .. total
    stat.text:SetText((stat.done and DONE or count) .. stat.label)
    stat:SetWidth((stat.icon and STAT_ICON + stat.gap or 0) + math.ceil(stat.text:GetStringWidth()))
end
-- A faction's page counts its BiS and looks the same way.
J.View.Parts.Stat, J.View.Parts.SetStat, J.View.Parts.OpensBisList = Stat, SetStat, OpensBisList

-------------------------------------------------------------------------------
--  The pin and the zone
-------------------------------------------------------------------------------
-- A click shows the entrance on your map; a right-click shares where it is, with a map pin
-- link the reader can click for the same pin.
local function PinClicked(pin, mouse)
    local dungeon = pin:GetParent().dungeon
    if mouse ~= "RightButton" then
        J.ShowEntrance(dungeon)
        return
    end
    local entrance = dungeon.entrance
    J.View.Parts.SharePlace(pin, "Share the entrance", dungeon.name, entrance.map, entrance.x, entrance.y,
        " entrance")
end

local function PinEnter(pin)
    pin.icon:SetAlpha(1)
    if not Tip(pin, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText("Show the entrance on your map", 1, 1, 1)
    GameTooltip:AddLine("Right-click to share it in chat, or copy it.", T.accentSoft.r, T.accentSoft.g,
        T.accentSoft.b)
    GameTooltip:Show()
end

local function PinLeave(pin)
    pin.icon:SetAlpha(PIN_REST)
    GameTooltip:Hide()
end

-- WoW Forever's mark after a new dungeon's name, and what it means.
local FOREVER_H, FOREVER_GAP = 12, 8

local function ForeverEnter(mark)
    if not Tip(mark, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText(ns.Shared.Parts.ForeverLine())
    GameTooltip:Show()
end

local TERRITORY_TIP = {
    Alliance = "Alliance territory", Horde = "Horde territory",
    Contested = "Contested territory: both factions",
}

local function ZoneEnter(zone)
    if not Tip(zone, "ANCHOR_BOTTOM") then return end
    GameTooltip:SetText(zone.name, 1, 1, 1)
    GameTooltip:AddLine(TERRITORY_CODE[zone.territory] .. TERRITORY_TIP[zone.territory] .. "|r")
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  The row
-------------------------------------------------------------------------------
-- The stats, left to right: your quests here handed in of how many (the yellow !; each
-- quest's own row says where it stands), your BiS here you have of how many (the orange
-- star), and with Appearances on the looks here you have of how many (the cyan hanger).
local STATS = { "quests", "bis", "looks" }

-- Laid out along the where line from the right, or when narrow (the map panel) on a line of
-- their own under it, from the left. Returns how wide they are along the line.
local function PlaceStats(row, compact)
    local anchor, used = nil, 0
    for i = 1, #STATS do row.stats[STATS[i]]:ClearAllPoints() end
    local first, last, step = #STATS, 1, -1
    if compact then first, last, step = 1, #STATS, 1 end
    for i = first, last, step do
        local stat = row.stats[STATS[i]]
        if stat:IsShown() then
            if anchor then
                stat:SetPoint(compact and "LEFT" or "RIGHT", anchor, compact and "RIGHT" or "LEFT",
                    compact and STAT_GAP or -STAT_GAP, 0)
            elseif compact then
                stat:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(TITLE_H + TITLE_GAP + WHERE_H + COMPACT_STAT_TOP))
            else
                stat:SetPoint("RIGHT", row, "TOPRIGHT", 0, -(TITLE_H + TITLE_GAP + WHERE_H / 2))
            end
            used = used + stat:GetWidth() + STAT_GAP
            anchor = stat
        end
    end
    return used, anchor ~= nil
end

Kinds.header = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.title = ns.Font(row, TITLE_SIZE, nil, T.fg)
        row.title:SetPoint("TOPLEFT")
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.forever = CreateFrame("Frame", nil, row)
        row.forever:SetSize(FOREVER_H * 2, FOREVER_H)
        row.forever:SetPoint("LEFT", row.title, "RIGHT", FOREVER_GAP, 0)
        row.forever:EnableMouse(true)
        ns.Shared.Parts.ForeverMark(row.forever, FOREVER_H):SetAllPoints()
        row.forever:SetScript("OnEnter", ForeverEnter)
        row.forever:SetScript("OnLeave", GameTooltip_Hide)
        row.pin = CreateFrame("Button", nil, row)
        row.pin:SetSize(PIN_BOX, PIN_BOX)
        row.pin.icon = row.pin:CreateTexture(nil, "ARTWORK")
        row.pin.icon:SetSize(PIN_ICON, PIN_ICON)
        row.pin.icon:SetPoint("CENTER")
        row.pin.icon:SetAlpha(PIN_REST)
        row.pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.pin:SetScript("OnClick", PinClicked)
        row.pin:SetScript("OnEnter", PinEnter)
        row.pin:SetScript("OnLeave", PinLeave)
        -- The zone on its own, to hover; the rest of the line after it.
        row.zone = CreateFrame("Frame", nil, row)
        row.zone:SetHeight(WHERE_H)
        row.zone:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -TITLE_GAP)
        row.zone:EnableMouse(true)
        row.zone.text = ns.Font(row.zone, 12)
        row.zone.text:SetPoint("LEFT")
        row.zone:SetScript("OnEnter", ZoneEnter)
        row.zone:SetScript("OnLeave", GameTooltip_Hide)
        row.where = ns.Font(row, 12, nil, T.muted)
        row.where:SetJustifyH("LEFT")
        row.where:SetWordWrap(false)
        row.stats = {
            -- The ! a pixel lower and two further from its number than its box puts it, to
            -- match the star and the hanger (measured in game, 2026-10-01: 2 from its number
            -- and a pixel high, where they are 4 and level).
            quests = Stat(row, "Quests", "You have handed in %d of your %d quests here",
                "Every quest here is done", BANG, nil, 0, -1),
            bis = Stat(row, "BiS", "You have %d of the %d BiS from your list that drop here",
                "You have every BiS that drops here", STAR, BIS_RGB, 2),
            looks = Stat(row, "Transmog", "You have %d of the %d looks here", "You have every look here",
                HANGER, LOOK_RGB, 2, -1),
        }
        row.stats.bis.noneTip = "None of your BiS drops here"
        OpensBisList(row.stats.bis)
        row.stats.looks.noneTip = "Nothing listed here has a look to collect"
        return row
    end,
    ---@param dungeon JournalDungeon
    Set = function(row, dungeon)
        local view = row:GetParent()
        row.dungeon = dungeon
        row.pin:SetShown(dungeon.entrance ~= nil and not view.compact)
        row.pin.icon:SetAtlas(dungeon.raid and PIN_ATLAS.raid or PIN_ATLAS.dungeon)
        -- New in Forever: its mark after the name, then the pin.
        local new = dungeon.new == true
        row.forever:SetShown(new)
        row.pin:ClearAllPoints()
        row.pin:SetPoint("LEFT", new and row.forever or row.title, "RIGHT", new and 2 or 6, -PIN_DROP)
        row.title:SetWidth(0)   -- unbounded, so it measures the whole name
        row.title:SetText(dungeon.name)
        row.title:SetWidth(math.min(math.ceil(row.title:GetStringWidth()) + 1,
            row:GetWidth() - PIN_BOX - 10 - (new and FOREVER_H * 2 + FOREVER_GAP or 0)))

        local zone = row.zone
        local territory = dungeon.territory or "Contested"
        zone:SetShown(dungeon.zone ~= nil)
        row.where:ClearAllPoints()
        if dungeon.zone then
            zone.name, zone.territory = dungeon.zone, territory
            zone.text:SetText(TERRITORY_CODE[territory] .. dungeon.zone .. "|r")
            zone:SetWidth(math.ceil(zone.text:GetStringWidth()))
            row.where:SetPoint("LEFT", zone, "RIGHT", 0, 0)
        else
            row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -TITLE_GAP)
        end
        -- A dungeon's levels; a raid's size (raids are all level 60).
        local range = J.LevelRange(dungeon)
        local where
        if dungeon.raid then
            where = (dungeon.zone and PLACE_DOT or "") .. ns.Color("fg", dungeon.raid) .. " players"
        else
            where = range and ((dungeon.zone and PLACE_DOT or "") .. "Level " .. ns.Color("fg", range)) or ""
        end
        row.where:SetText(where)

        local filters = view.filters
        local bis, haveBis = Loot.DungeonBis(dungeon, filters)
        local newLooks, looks = 0, 0
        if filters.showAppearance then newLooks, looks = Loot.DungeonNewLooks(dungeon, filters) end
        local stats = row.stats
        SetStat(stats.quests, Quests.Progress(dungeon.quests))
        -- With the BiS List on, always: none of yours here is worth knowing too.
        SetStat(stats.bis, haveBis, bis, BIS_CODE, Loot.BisOn())
        -- With Appearances on, always, as BiS: "0/0" says nothing here has a look.
        SetStat(stats.looks, looks - newLooks, looks, LOOK_CODE, filters.showAppearance)

        local used, any = PlaceStats(row, view.compact)
        local zoneW = dungeon.zone and zone:GetWidth() or 0
        local lines = TITLE_H + TITLE_GAP + WHERE_H
        if view.compact then
            row.where:SetWidth(row:GetWidth() - zoneW)
            return lines + (any and STAT_LINE_H or 0) + COMPACT_PAD
        end
        row.where:SetWidth(row:GetWidth() - used - zoneW)
        return lines + HEADER_PAD
    end,
}
