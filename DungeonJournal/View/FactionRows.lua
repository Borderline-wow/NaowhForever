-------------------------------------------------------------------------------
--  View/FactionRows.lua -- the rows of a faction's page and of the PvP rank's: the page's
--  header (the faction's name, its side, battleground and quartermaster, and your BiS and
--  looks among its rewards; for the rank, your rank's title, the season, and your honor), a
--  standing bar, a card's header for each standing's rewards (or each rank's), a line of
--  links between a faction and the dungeons it is earned in, and a rank reward that is not
--  an item.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Loot = J.Loot
local Rep = J.Reputation

local St = J.Style
local BIS_CODE, LOOK_CODE, LOOK_RGB, BIS_RGB = St.BIS_CODE, St.LOOK_CODE, St.LOOK_RGB, St.BIS_RGB
local STAR, HANGER, CHECK, ROUND, PLACE_DOT = St.STAR, St.HANGER, St.CHECK, St.ROUND, St.PLACE_DOT
local TERRITORY_CODE, HAVE_RGB, BORDER_RGB = St.TERRITORY_CODE, St.HAVE_RGB, St.BORDER_RGB
local TITLE_SIZE, TITLE_H, TITLE_GAP, WHERE_H, HEADER_PAD = St.TITLE_SIZE, St.TITLE_H, St.TITLE_GAP, St.WHERE_H,
    St.HEADER_PAD
local STAT_GAP, BOSS_HEADER_H, BOSS_NAME_SIZE = St.STAT_GAP, St.BOSS_HEADER_H, St.BOSS_NAME_SIZE
local ICON, ITEM_H, BAR_H, STAT_ICON = St.ICON, St.ITEM_H, St.STANDING_BAR, St.STAT_ICON

local View = J.View
local Kinds, Parts = View.Kinds, View.Parts

local NAME_TOP, RIGHT_TOP = 11, 13   -- a card header's name and right text, as a boss's
local CHECK_ICON = 14
local UNREACHED = 0.55               -- a standing or rank not reached yet: its name this faint
local DEEP = 0.6                     -- a bar's fill starts at its colour this dark
local LABEL_H, BAR_TOP, BAR_PAD = 18, 4, 14
local LINKS_H, LINK_GAP = 22, 14
local QUESTION_ICON = 134400         -- the game's question mark, for a reward with no icon

-------------------------------------------------------------------------------
--  The page's header
-------------------------------------------------------------------------------
-- A faction's where line: its side in the side's colour, its battleground, where its
-- quartermaster is (or only where it is, for one with no rewards to sell, a city), and that
-- it is new in Forever. The data is fixed, so made once each.
local whereLines = {}

local function FactionWhere(faction)
    local line = whereLines[faction]
    if line then return line end
    local parts = {}
    if faction.side then parts[#parts + 1] = TERRITORY_CODE[faction.side] .. faction.side .. "|r" end
    if faction.battleground then parts[#parts + 1] = ns.Color("fg", faction.battleground) end
    if faction.zone then
        parts[#parts + 1] = (#faction.tiers > 0 and "Quartermaster in " or "") .. ns.Color("fg", faction.zone)
    end
    if faction.new then parts[#parts + 1] = ns.Color("accent", "New in WoW Forever") end
    line = table.concat(parts, PLACE_DOT)
    whereLines[faction] = line
    return line
end

-- The rank's: your rank, the season and when it ends, and the city your side buys its
-- rewards in, as a faction's says where its quartermaster is (the pin after the title goes
-- there once you have opened that vendor); nothing while the game has no rank.
local RANK_CITY = { Alliance = "Stormwind", Horde = "Orgrimmar" }

local function RankWhere(info)
    if not info then return "" end
    local season, left = Rep.Season()
    local line = "Rank " .. ns.Color("fg", info.renownLevel)
    if season > 0 then line = line .. PLACE_DOT .. "Season " .. ns.Color("fg", season) end
    if left > 0 then line = line .. PLACE_DOT .. "Ends in " .. ns.Color("fg", Rep.Duration(left)) end
    local city = RANK_CITY[UnitFactionGroup("player")]
    if city then line = line .. PLACE_DOT .. "Rank vendor in " .. ns.Color("fg", city) end
    return line
end

-- A currency on the rank's header: its icon, how much you have, and its name, muted.
local function CurrencyText(id)
    local quantity, name, icon = Rep.Currency(id)
    if not name then return "" end
    return ("|T%d:%d:%d:0:0|t %s %s"):format(icon or QUESTION_ICON, STAT_ICON, STAT_ICON,
        BreakUpLargeNumbers(quantity), ns.Color("muted", name))
end

local function CurrencyEnter(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:SetCurrencyByID(frame.currency)
    GameTooltip:Show()
end

local function Currency(row)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetHeight(16)
    frame:EnableMouse(true)
    frame.text = ns.Font(frame, 12, nil, T.fg)
    frame.text:SetPoint("LEFT")
    frame:SetScript("OnEnter", CurrencyEnter)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    return frame
end

local function SetCurrency(frame, id)
    frame.currency = id
    frame.text:SetText(CurrencyText(id))
    frame:SetWidth(math.ceil(frame.text:GetStringWidth()))
    frame:SetShown(frame.text:GetText() ~= "")
end

-- The pin after a faction's name, once its quartermaster's spot is known (learned at the
-- vendor, or entered by hand), or after the rank's title, once your side's rank vendor's is
-- (learned at the vendor): a click shows it on your map, a right-click shares it with a map
-- pin link, as a dungeon's entrance pin does.
local PIN_DROP = 2   -- the title's letters sit under its middle: the pin goes this much lower
local RANK_SELLS = "PvP rank rewards"

-- Where the page's pin points: the spot, what to call it, and what it is for.
local function PinSpot(page)
    if page.rank then
        local spot = Rep.RankVendor()
        if spot then return spot, spot.name or RANK_SELLS, RANK_SELLS end
        return nil
    end
    local spot = Rep.Quartermaster(page)
    if spot then return spot, spot.name or (page.name .. " quartermaster"), page.name end
    return nil
end

local function PinClicked(pin, mouse)
    local spot, name, what = PinSpot(pin.page)
    if not spot then return end
    local note = " (" .. what .. ")"
    if mouse == "RightButton" then
        Parts.SharePlace(pin, pin.page.rank and "Share the rank vendor" or "Share the quartermaster", name,
            spot.map, spot.x, spot.y, note)
        return
    end
    ns.PlaceWaypoint(name, spot.map, spot.x, spot.y, note)
    if not InCombatLockdown() then C_Map.OpenWorldMap(spot.map) end
end

-- Its name over its where line; on the right, a faction's BiS and looks among its rewards
-- (as a dungeon's header counts them), or the rank's honor and rank points.
Kinds.page = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.title = ns.Font(row, TITLE_SIZE, nil, T.fg)
        row.title:SetPoint("TOPLEFT")
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.pin = Parts.IconButton(row, PinClicked, St.PIN)
        row.pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.pin:SetPoint("LEFT", row.title, "RIGHT", 6, -PIN_DROP)
        row.pin.tip = "Show the quartermaster on your map"
        row.pin.hint = "Right-click to share it in chat, or copy it."
        row.where = ns.Font(row, 12, nil, T.muted)
        row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -TITLE_GAP)
        row.where:SetJustifyH("LEFT")
        row.where:SetWordWrap(false)
        row.bis = Parts.Stat(row, "BiS", "You have %d of the %d BiS from your list among its rewards",
            "You have every BiS among its rewards", STAR, BIS_RGB, 2)
        row.bis.noneTip = "None of your BiS is among its rewards"
        Parts.OpensBisList(row.bis)
        row.looks = Parts.Stat(row, "Transmog", "You have %d of the %d looks among its rewards",
            "You have every look among its rewards", HANGER, LOOK_RGB, 2, -1)
        row.looks.noneTip = "None of its rewards listed has a look to collect"
        row.honor, row.points = Currency(row), Currency(row)
        -- Each page's stats, right to left.
        row.rankStats, row.factionStats = { row.points, row.honor }, { row.looks, row.bis }
        return row
    end,
    ---@param page JournalFaction|table a faction, or J.RANK
    ---@param info? table the rank's (Rep.Rank()), for J.RANK
    Set = function(row, page, info)
        local view = row:GetParent()
        local middle = -(TITLE_H + TITLE_GAP + WHERE_H / 2)
        local right, used = nil, 0
        row.bis:ClearAllPoints()
        row.looks:ClearAllPoints()
        row.honor:ClearAllPoints()
        row.points:ClearAllPoints()
        row.title:SetWidth(0)   -- unbounded, so it measures the whole name
        row.pin.page = page
        row.pin.tip = page.rank and "Show where your side's rank rewards are sold on your map"
            or "Show the quartermaster on your map"
        row.pin:SetShown(PinSpot(page) ~= nil)
        if page.rank then
            row.title:SetText(Rep.RankTitle(info and info.renownLevel or 0))
            row.where:SetText(RankWhere(info))
            row.bis:Hide()
            row.looks:Hide()
            SetCurrency(row.points, Rep.RANK_POINTS)
            SetCurrency(row.honor, Rep.HONOR)
            for _, stat in ipairs(row.rankStats) do
                if stat:IsShown() then
                    if right then
                        stat:SetPoint("RIGHT", right, "LEFT", -STAT_GAP, 0)
                    else
                        stat:SetPoint("RIGHT", row, "TOPRIGHT", 0, middle)
                    end
                    right, used = stat, used + stat:GetWidth() + STAT_GAP
                end
            end
        else
            row.title:SetText(page.name)
            row.where:SetText(FactionWhere(page))
            row.honor:Hide()
            row.points:Hide()
            local filters = view.filters
            local bis, haveBis = Rep.Bis(page)
            -- With the BiS List on, always: "0/0" says none of yours is here, as Transmog's does.
            Parts.SetStat(row.bis, haveBis, bis, BIS_CODE, Loot.BisOn())
            local new, looks = 0, 0
            if filters.showAppearance then new, looks = Rep.NewLooks(page, filters) end
            -- With Appearances on, always, as BiS: "0/0" says none of them has a look.
            Parts.SetStat(row.looks, looks - new, looks, LOOK_CODE, filters.showAppearance)
            for _, stat in ipairs(row.factionStats) do
                if stat:IsShown() then
                    if right then
                        stat:SetPoint("RIGHT", right, "LEFT", -STAT_GAP, 0)
                    else
                        stat:SetPoint("RIGHT", row, "TOPRIGHT", 0, middle)
                    end
                    right, used = stat, used + stat:GetWidth() + STAT_GAP
                end
            end
        end
        row.title:SetWidth(math.min(math.ceil(row.title:GetStringWidth()) + 1, row:GetWidth() - 30))
        row.where:SetWidth(math.max(1, row:GetWidth() - used))
        return TITLE_H + TITLE_GAP + WHERE_H + HEADER_PAD
    end,
}

-------------------------------------------------------------------------------
--  A standing bar: the standing in its colour, how far into it on the right, then a pill
--  bar in the opacity slider's look, its fill brightening from a deeper shade of the colour
-------------------------------------------------------------------------------
local function Round(row, layer, size)
    local dot = row:CreateTexture(nil, layer)
    dot:SetTexture(ROUND, nil, nil, "TRILINEAR")
    dot:SetSize(size, size)
    return dot
end

-- The fill's two colours, made once and filled on every draw.
local deep, bright = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1)

Kinds.standing = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.label = ns.Font(row, 13)
        row.label:SetPoint("TOPLEFT", 0, 0)
        row.value = ns.Font(row, 11, nil, T.muted)
        row.value:SetPoint("TOPRIGHT", 0, -2)
        row.track = ns.Solid(row, "BORDER", T.line, 1)
        row.track:SetPoint("TOPLEFT", BAR_H / 2, -(LABEL_H + BAR_TOP))
        row.track:SetPoint("TOPRIGHT", -BAR_H / 2, -(LABEL_H + BAR_TOP))
        row.track:SetHeight(BAR_H)
        row.trackStart = Round(row, "BORDER", BAR_H)
        row.trackStart:SetPoint("CENTER", row.track, "LEFT")
        row.trackStart:SetVertexColor(T.line.r, T.line.g, T.line.b, 1)
        row.trackEnd = Round(row, "BORDER", BAR_H)
        row.trackEnd:SetPoint("CENTER", row.track, "RIGHT")
        row.trackEnd:SetVertexColor(T.line.r, T.line.g, T.line.b, 1)
        row.fill = row:CreateTexture(nil, "ARTWORK")
        row.fill:SetColorTexture(1, 1, 1, 1)
        row.fill:SetPoint("LEFT", row.track)
        row.fill:SetHeight(BAR_H)
        row.fillStart = Round(row, "ARTWORK", BAR_H)
        row.fillStart:SetPoint("CENTER", row.fill, "LEFT")
        row.fillEnd = Round(row, "ARTWORK", BAR_H)
        row.fillEnd:SetPoint("CENTER", row.fill, "RIGHT")
        row.under = ns.Font(row, 11, nil, T.muted)
        row.under:SetPoint("TOPLEFT", 0, -(LABEL_H + BAR_TOP + BAR_H + 6))
        row.under:SetJustifyH("LEFT")
        row.under:SetWordWrap(true)
        return row
    end,
    ---@param label string
    ---@param color { r: number, g: number, b: number }
    ---@param value number how far into it
    ---@param max number how far it goes
    ---@param showValue boolean "value / max" on the right
    ---@param under? string a muted line under the bar
    Set = function(row, label, color, value, max, showValue, under)
        row.label:SetText(label)
        row.label:SetTextColor(color.r, color.g, color.b)
        row.value:SetText(showValue and ns.Color("fg", BreakUpLargeNumbers(value)) .. " / "
            .. BreakUpLargeNumbers(max) or "")
        local share = math.max(0, math.min(1, value / math.max(1, max)))
        deep:SetRGBA(color.r * DEEP, color.g * DEEP, color.b * DEEP, 1)
        bright:SetRGBA(color.r, color.g, color.b, 1)
        row.fill:SetGradient("HORIZONTAL", deep, bright)
        row.fillStart:SetVertexColor(deep.r, deep.g, deep.b, 1)
        row.fillEnd:SetVertexColor(color.r, color.g, color.b, 1)
        row.fill:SetWidth(math.max(0.1, (row:GetWidth() - BAR_H) * share))
        local any = share > 0
        row.fill:SetShown(any)
        row.fillStart:SetShown(any)
        row.fillEnd:SetShown(any)
        row.under:SetWidth(row:GetWidth())
        row.under:SetText(under or "")
        local height = LABEL_H + BAR_TOP + BAR_H + BAR_PAD
        if under then height = height + math.ceil(row.under:GetStringHeight()) + 2 end
        return height
    end,
}

-------------------------------------------------------------------------------
--  A faction's standing as a track: one segment per standing from Neutral (or lower, while
--  you are below it) to Exalted, those you have reached filled in their colour, the one you
--  are at as far as you are into it. Under each, its name (in its colour once reached) and,
--  with the game's bag, how many rewards it unlocks. Over it, where you stand and how far.
-------------------------------------------------------------------------------
local SEG_GAP, SEG_H, SEG_LABEL_TOP, SEG_LABEL_H = 3, 6, 5, 14
local HERE_TINT = 0.25   -- the standing you are at: its segment in its colour, this faint
-- A segment's words stay this much narrower than it, so two neighbours' never touch.
local SEG_LABEL_PAD = 6

-- Over a segment: the standing, how many rewards it unlocks for you, and whether you have
-- reached it, are there, or how much reputation it is still away.
local function SegmentEnter(hit)
    local s, info = hit.standing, hit:GetParent().info
    local color, muted = Rep.Color(s), T.muted
    GameTooltip:SetOwner(hit, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Rep.Label(s), color.r, color.g, color.b)
    local count = info.counts[s] or 0
    GameTooltip:AddLine(count > 0 and ("%d %s for you %s here"):format(count, count == 1 and "reward" or "rewards",
        count == 1 and "unlocks" or "unlock") or "No rewards for you here", 1, 1, 1)
    local reaction = info.reaction
    if not reaction then
        GameTooltip:AddLine("You have not met them yet.", muted.r, muted.g, muted.b)
    elseif reaction == s then
        GameTooltip:AddLine("You are here.", muted.r, muted.g, muted.b)
    elseif reaction > s then
        GameTooltip:AddLine("Reached.", St.HAVE_RGB.r, St.HAVE_RGB.g, St.HAVE_RGB.b)
    else
        local toGo, exact = Rep.ToGo(s, reaction, info.value, info.max)
        GameTooltip:AddLine(Rep.ToGoText(toGo, exact) .. " (reputation)", muted.r, muted.g, muted.b)
    end
    GameTooltip:Show()
end

local function Segment(row, s)
    local seg = {}
    seg.track = ns.Solid(row, "BORDER", T.line, 1)
    seg.track:SetHeight(SEG_H)
    seg.fill = row:CreateTexture(nil, "ARTWORK")
    seg.fill:SetColorTexture(1, 1, 1, 1)
    seg.fill:SetPoint("TOPLEFT", seg.track)
    seg.fill:SetPoint("BOTTOMLEFT", seg.track)
    -- Its name centred under it, and how many rewards it unlocks for you after a dot; on one
    -- line, as wide as the segment at most (Set shortens it to fit).
    seg.name = ns.Font(row, 10, nil, T.muted)
    seg.name:SetPoint("TOP", seg.track, "BOTTOM", 0, -SEG_LABEL_TOP)
    seg.name:SetWordWrap(false)
    -- What the mouse answers to: the segment and its line of words under it.
    seg.hit = CreateFrame("Frame", nil, row)
    seg.hit:SetPoint("TOPLEFT", seg.track, "TOPLEFT", 0, 4)
    seg.hit:SetPoint("BOTTOMRIGHT", seg.track, "BOTTOMRIGHT", 0, -(SEG_LABEL_TOP + SEG_LABEL_H))
    seg.hit:EnableMouse(true)
    seg.hit.standing = s
    seg.hit:SetScript("OnEnter", SegmentEnter)
    seg.hit:SetScript("OnLeave", GameTooltip_Hide)
    return seg
end

Kinds.track = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.label = ns.Font(row, 13)
        row.label:SetPoint("TOPLEFT", 0, 0)
        row.segments = {}
        for s = 1, Rep.EXALTED do row.segments[s] = Segment(row, s) end
        row.info = { counts = {} }   -- what the segments' tooltips read
        return row
    end,
    ---@param reaction? number where you stand; nil, not met yet
    ---@param value number how far into it
    ---@param max number how far it goes
    ---@param counts table<number, number> standing -> how many rewards it unlocks for you
    Set = function(row, reaction, value, max, counts)
        local info = row.info
        info.reaction, info.value, info.max, info.counts = reaction, value, max, counts
        -- "Neutral  0 / 3,000 to Friendly": where you stand, then how far into it, muted.
        if reaction then
            local color = Rep.Color(reaction)
            row.label:SetTextColor(color.r, color.g, color.b)
            local far = ""
            if reaction < Rep.EXALTED then
                far = "   " .. ns.Color("fg", BreakUpLargeNumbers(value)) .. ns.Color("muted", " / "
                    .. BreakUpLargeNumbers(max) .. " to " .. Rep.Label(reaction + 1))
            end
            row.label:SetText(Rep.Label(reaction) .. far)
        else
            row.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
            row.label:SetText("Not met yet")
        end
        local first = math.min(reaction or 4, 4)
        local n = Rep.EXALTED - first + 1
        local width = math.floor((row:GetWidth() - SEG_GAP * (n - 1)) / n)
        for s = 1, Rep.EXALTED do
            local seg = row.segments[s]
            local shown = s >= first
            seg.track:SetShown(shown)
            seg.name:SetShown(shown)
            seg.hit:SetShown(shown)
            seg.fill:SetShown(false)
            if shown then
                local i = s - first
                local w = s == Rep.EXALTED and row:GetWidth() - i * (width + SEG_GAP) or width
                seg.track:ClearAllPoints()
                seg.track:SetPoint("TOPLEFT", i * (width + SEG_GAP), -(LABEL_H + BAR_TOP))
                seg.track:SetWidth(w)
                local share = 0
                if reaction then share = s < reaction and 1 or s == reaction and math.min(1, value / math.max(1, max)) or 0 end
                local color = Rep.Color(s)
                if share > 0 then
                    seg.fill:SetVertexColor(color.r, color.g, color.b, 1)
                    seg.fill:SetWidth(math.max(1, math.floor(w * share + 0.5)))
                    seg.fill:Show()
                end
                -- The one you are at, tinted in its colour even before any progress, so where you
                -- stand always shows; the rest plain.
                if s == reaction then
                    seg.track:SetColorTexture(color.r, color.g, color.b, HERE_TINT)
                else
                    seg.track:SetColorTexture(T.line.r, T.line.g, T.line.b, 1)
                end
                local reached = reaction ~= nil and reaction >= s
                local count = counts[s] or 0
                -- "Honored . 10 rewards" where it fits, else "Honored . 10", else "Honored": with
                -- eight standings a narrow window has no room for the word (the tooltip says it).
                local name, label, room = seg.name, Rep.Label(s), w - SEG_LABEL_PAD
                name:SetWidth(0)   -- unbounded, so it measures the whole text
                if count > 0 then
                    name:SetText(label .. ns.Color("muted", PLACE_DOT .. count
                        .. (count == 1 and " reward" or " rewards")))
                    if name:GetStringWidth() > room then
                        name:SetText(label .. ns.Color("muted", PLACE_DOT .. count))
                    end
                    if name:GetStringWidth() > room then name:SetText(label) end
                else
                    name:SetText(label)
                end
                name:SetWidth(math.max(1, room))
                local tint = reached and color or T.muted
                seg.name:SetTextColor(tint.r, tint.g, tint.b)
            end
        end
        return LABEL_H + BAR_TOP + SEG_H + SEG_LABEL_TOP + SEG_LABEL_H + BAR_PAD
    end,
}

-------------------------------------------------------------------------------
--  A card's header: a standing's rewards, or a rank's
-------------------------------------------------------------------------------
-- Its name in its colour, a green check once you have reached it, faint until then; on the
-- right, muted, how far you are from it when it is the next one; a hairline over its rewards.
Kinds.tier = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.name = ns.Font(row, BOSS_NAME_SIZE, nil, T.fg)
        row.name:SetPoint("TOPLEFT", 0, -NAME_TOP)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.check = row:CreateTexture(nil, "ARTWORK")
        row.check:SetTexture(CHECK)
        row.check:SetSize(CHECK_ICON, CHECK_ICON)
        row.check:SetVertexColor(HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b)
        row.check:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        row.right = ns.Font(row, 11, nil, T.muted)
        row.right:SetPoint("TOPRIGHT", 0, -RIGHT_TOP)
        row.right:SetJustifyH("RIGHT")
        row.rule = ns.Solid(row, "ARTWORK", T.line, 0.7)
        row.rule:SetPoint("BOTTOMLEFT")
        row.rule:SetPoint("BOTTOMRIGHT")
        row.rule:SetHeight(1)
        return row
    end,
    ---@param label string
    ---@param color { r: number, g: number, b: number }
    ---@param reached boolean
    ---@param right? string
    ---@param shown number how many of its rewards are listed
    Set = function(row, label, color, reached, right, shown)
        row.name:SetWidth(0)   -- unbounded, so it measures the whole name
        row.name:SetText(label)
        row.name:SetTextColor(color.r, color.g, color.b)
        row.name:SetAlpha(reached and 1 or UNREACHED)
        row.check:SetShown(reached)
        row.right:SetText(right or "")
        row.name:SetWidth(math.min(math.ceil(row.name:GetStringWidth()) + 1,
            row:GetWidth() - CHECK_ICON - 12 - math.ceil(row.right:GetStringWidth())))
        row.rule:SetShown(shown > 0)
        return BOSS_HEADER_H
    end,
}

-------------------------------------------------------------------------------
--  A kind of reward inside a standing's card: the game's icon for it, its name small and in
--  capitals with how many, as the list's group titles; folded recipes with a chevron, the
--  whole row a click
-------------------------------------------------------------------------------
local KIND_ICONS = { "Interface\\Icons\\INV_Chest_Chain_05", "Interface\\Icons\\INV_Scroll_03",
    "Interface\\Icons\\INV_Misc_Bag_08" }
local GROUP_H, GROUP_ICON, GROUP_ARROW = 22, 14, 10

local function GroupColor(row, color)
    row.label:SetTextColor(color.r, color.g, color.b)
    row.arrow:SetVertexColor(color.r, color.g, color.b)
end

local function GroupEnter(row) GroupColor(row, T.fg) end
local function GroupLeave(row) GroupColor(row, T.accentSoft) end

local function GroupClicked(row)
    if row.onToggle then row.onToggle(row) end
end

Kinds.group = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row.arrow = Parts.Arrow(row, GROUP_ARROW, T.accentSoft)
        row.arrow:SetPoint("LEFT", -2, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(GROUP_ICON, GROUP_ICON)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = ns.Font(row, 10, nil, T.accentSoft)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.line = ns.Solid(row, "ARTWORK", T.line, 0.7)
        row.line:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
        row.line:SetPoint("RIGHT")
        row.line:SetHeight(1)
        row:SetScript("OnClick", GroupClicked)
        row:SetScript("OnEnter", GroupEnter)
        row:SetScript("OnLeave", GroupLeave)
        return row
    end,
    ---@param kind number 1 gear, 2 recipes, 3 the rest
    ---@param title string
    ---@param count number
    ---@param open? boolean with onToggle: whether it is open
    ---@param onToggle? fun(row: Frame)
    Set = function(row, kind, title, count, open, onToggle)
        row.onToggle = onToggle
        row:EnableMouse(onToggle ~= nil)
        row.arrow:SetShown(onToggle ~= nil)
        row.arrow:SetRotation(open and -math.pi / 2 or 0)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", onToggle and GROUP_ARROW + 2 or 0, 0)
        row.icon:SetTexture(KIND_ICONS[kind])
        row.label:SetText(title:upper() .. "   " .. ns.Color("muted", count))
        GroupColor(row, T.accentSoft)
        return GROUP_H
    end,
}

-------------------------------------------------------------------------------
--  Links between a faction and its dungeons: a muted label, then each name as a link that
--  opens it (the window's view.navigate)
-------------------------------------------------------------------------------
local function LinkClicked(link)
    local view = link:GetParent():GetParent()
    if view.navigate then view.navigate(link.target) end
end

-- After a faction's link, your standing with it: its name in its colour and how far into it.
local function StandingText(faction)
    local reaction, value, max = Rep.Standing(faction)
    if not reaction then return ns.Color("muted", "not met") end
    local color = Rep.Color(reaction)
    local text = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, Rep.Label(reaction))
    if reaction < Rep.EXALTED then
        text = text .. " " .. ns.Color("muted", BreakUpLargeNumbers(value) .. " / " .. BreakUpLargeNumbers(max))
    end
    return text
end

Kinds.links = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.label = ns.Font(row, 12, nil, T.muted)
        row.label:SetPoint("LEFT", 0, 0)
        row.links, row.after = {}, {}
        return row
    end,
    ---@param label string
    ---@param targets (JournalDungeon|JournalFaction)[]
    Set = function(row, label, targets)
        row.label:SetText(label)
        local anchor, gap = row.label, 8
        for i, target in ipairs(targets) do
            local link = row.links[i]
            if not link then
                link = Parts.Link(row, LinkClicked, true)
                row.links[i] = link
            end
            link.target = target
            Parts.SetLink(link, target.name)
            link:ClearAllPoints()
            link:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
            link:Show()
            anchor, gap = link, LINK_GAP
            -- A faction (on a dungeon's page): your standing with it, after its name.
            local after = row.after[i]
            if not after then
                after = ns.Font(row, 11, nil, T.muted)
                row.after[i] = after
            end
            after:SetShown(target.tab ~= nil)
            if target.tab then
                after:ClearAllPoints()
                after:SetPoint("LEFT", link, "RIGHT", 6, 0)
                after:SetText(StandingText(target))
                anchor = after
            end
        end
        for i = #targets + 1, #row.links do
            row.links[i]:Hide()
            row.after[i]:Hide()
        end
        return LINKS_H
    end,
}

-------------------------------------------------------------------------------
--  A line under a faction's standing: an icon in a black border, a line of text, and muted on
--  the right a figure. The next reward to work for, with its item's tooltip on hover; and what
--  the rewards you have unlocked and not got yet would cost, against your gold.
-------------------------------------------------------------------------------
local LINE_H, LINE_ICON = 26, 20

local function LineEnter(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT", 16, 0)
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
end

Kinds.line = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        local frame = CreateFrame("Frame", nil, row)
        frame:SetSize(LINE_ICON, LINE_ICON)
        frame:SetPoint("LEFT", 0, 0)
        ns.Border(frame, BORDER_RGB)
        row.icon = frame:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 1, -1)
        row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.right = ns.Font(row, 11, nil, T.muted)
        row.right:SetPoint("RIGHT", 0, 0)
        row.right:SetJustifyH("RIGHT")
        row.text = ns.Font(row, 12, nil, T.fg)
        row.text:SetPoint("LEFT", frame, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -12, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", LineEnter)
        row:SetScript("OnLeave", GameTooltip_Hide)
        return row
    end,
    ---@param icon number|string
    ---@param text string
    ---@param right? string
    ---@param itemID? number its tooltip on hover
    Set = function(row, icon, text, right, itemID)
        row.icon:SetTexture(icon)
        row.text:SetText(text)
        row.right:SetText(right or "")
        row.itemID = itemID
        return LINE_H
    end,
}

-------------------------------------------------------------------------------
--  The PvP rank as a track: one segment per rank this season, those reached filled in the
--  accent, the next as far as you are into it, and those past this week's cap faint. Under
--  each, its number; over it, the next rank and how far; under it, this week's cap.
-------------------------------------------------------------------------------
local RANK_SEG_GAP, CAPPED = 2, 0.35

local function RankSegment(row)
    local seg = {}
    seg.track = ns.Solid(row, "BORDER", T.line, 1)
    seg.track:SetHeight(SEG_H)
    seg.fill = ns.Solid(row, "ARTWORK", T.accent, 1)
    seg.fill:SetPoint("TOPLEFT", seg.track)
    seg.fill:SetPoint("BOTTOMLEFT", seg.track)
    seg.number = ns.Font(row, 10, nil, T.muted)
    seg.number:SetPoint("TOP", seg.track, "BOTTOM", 0, -SEG_LABEL_TOP)
    return seg
end

Kinds.rankTrack = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.label = ns.Font(row, 13, nil, T.accent)
        row.label:SetPoint("TOPLEFT", 0, 0)
        row.value = ns.Font(row, 11, nil, T.muted)
        row.value:SetPoint("TOPRIGHT", 0, -2)
        row.cap = ns.Font(row, 11, nil, T.muted)
        row.cap:SetPoint("TOPLEFT", 0, -(LABEL_H + BAR_TOP + SEG_H + SEG_LABEL_TOP + SEG_LABEL_H))
        row.segments = {}
        return row
    end,
    ---@param info table the rank's (Rep.Rank())
    Set = function(row, info)
        local level, top, cap = info.renownLevel, info.maxLevel, info.currentWeekProgressiveMaxLevel
        local accent = T.accent
        if level >= top then
            row.label:SetText("The highest rank this season")
            row.value:SetText("")
        else
            row.label:SetText(ns.Color("muted", "Next  ") .. "Rank " .. (level + 1) .. PLACE_DOT .. Rep.RankTitle(level + 1))
            row.value:SetText(ns.Color("fg", BreakUpLargeNumbers(info.renownReputationEarned)) .. " / "
                .. BreakUpLargeNumbers(info.renownLevelThreshold))
        end
        local width = math.floor((row:GetWidth() - RANK_SEG_GAP * (top - 1)) / math.max(1, top))
        for r = 1, math.max(top, #row.segments) do
            local seg = row.segments[r]
            if r <= top then
                if not seg then
                    seg = RankSegment(row)
                    row.segments[r] = seg
                end
                local w = r == top and row:GetWidth() - (r - 1) * (width + RANK_SEG_GAP) or width
                seg.track:ClearAllPoints()
                seg.track:SetPoint("TOPLEFT", (r - 1) * (width + RANK_SEG_GAP), -(LABEL_H + BAR_TOP))
                seg.track:SetWidth(w)
                local share = r <= level and 1 or r == level + 1
                    and math.min(1, info.renownReputationEarned / math.max(1, info.renownLevelThreshold)) or 0
                seg.fill:SetVertexColor(accent.r, accent.g, accent.b, 1)
                seg.fill:SetWidth(math.max(1, math.floor(w * share + 0.5)))
                seg.fill:SetShown(share > 0)
                local capped = cap > 0 and r > cap
                seg.track:SetAlpha(capped and CAPPED or 1)
                seg.number:SetText(r)
                local tint = r <= level and T.fg or T.muted
                seg.number:SetTextColor(tint.r, tint.g, tint.b)
                seg.number:SetAlpha(capped and CAPPED + 0.25 or 1)
                seg.track:Show()
                seg.number:Show()
            elseif seg then
                seg.track:Hide()
                seg.fill:Hide()
                seg.number:Hide()
            end
        end
        local capped = cap > 0 and cap < top
        row.cap:SetText(capped and ("This week you can reach rank %d of %d; the faint ranks open in the weeks to come.")
            :format(cap, top) or "")
        return LABEL_H + BAR_TOP + SEG_H + SEG_LABEL_TOP + SEG_LABEL_H + (capped and 18 or 0) + BAR_PAD
    end,
}

-------------------------------------------------------------------------------
--  A rank reward that is not an item: a title, a mount, an appearance, or what the rank
--  unlocks at its vendor. Its icon in a black border, its name, and under it what it is and
--  what the game says it gives (the line its own rank panel shows), and whether you have it
-------------------------------------------------------------------------------
local function RewardKind(reward)
    if reward.mountID then return "Mount" end
    if reward.titleMaskID then return "Title" end
    if reward.transmogSetID then return "Appearance set" end
    if reward.transmogID then return "Appearance" end
    if reward.transmogIllusionSourceID then return "Illusion" end
    if reward.spellID then return "Spell" end
    return nil
end

-- "Title . Knight-Captain" or the game's description alone, on one line: its first line, plain
-- (the description can carry its own colours and line breaks). Made once per reward text.
local described = {}

local function Described(reward)
    local text = reward.description
    if not text or text == "" then return nil end
    local line = described[text]
    if not line then
        line = Parts.Plain((text:match("^[^\n]+") or text))
        described[text] = line
    end
    return line
end

local KEPT_CODE = ("|cff%02x%02x%02x"):format(HAVE_RGB.r * 200, HAVE_RGB.g * 200, HAVE_RGB.b * 200)

-- As the game's own renown panel reads a reward (RenownRewardUtil): the item's, mount's or
-- spell's own tooltip when it is one of those; else its name and description, all the game
-- gives for the rest.
local function RewardEnter(row)
    local reward = row.reward
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT", 16, 0)
    local itemID = reward.itemID or reward.transmogID and C_Transmog.GetItemIDForSource(reward.transmogID)
    local mountSpell = reward.mountID and select(2, C_MountJournal.GetMountInfoByID(reward.mountID))
    if itemID then
        GameTooltip:SetItemByID(itemID)
    elseif mountSpell or reward.spellID then
        GameTooltip:SetSpellByID(mountSpell or reward.spellID)
    else
        GameTooltip:SetText(reward.name or RewardKind(reward) or "Reward", 1, 1, 1)
        if reward.description then GameTooltip:AddLine(reward.description, nil, nil, nil, true) end
    end
    GameTooltip:Show()
end

Kinds.reward = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        local frame = CreateFrame("Frame", nil, row)
        frame:SetSize(ICON, ICON)
        frame:SetPoint("LEFT", 0, 0)
        ns.Border(frame, BORDER_RGB)
        row.icon = frame:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 1, -1)
        row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = ns.Font(row, 12, nil, T.fg)
        row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, -1)
        row.name:SetPoint("RIGHT")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.meta = ns.Font(row, 11, nil, T.muted)
        row.meta:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 8, 1)
        row.meta:SetPoint("RIGHT")
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", RewardEnter)
        row:SetScript("OnLeave", GameTooltip_Hide)
        return row
    end,
    ---@param reward table MajorFactionRenownRewardInfo
    Set = function(row, reward)
        row.reward = reward
        row.icon:SetTexture(reward.icon or QUESTION_ICON)
        local kind, text = RewardKind(reward), Described(reward)
        row.name:SetText(reward.name or text or kind or "Reward")
        local meta = kind and text and kind .. PLACE_DOT .. text or text or kind or "Reward"
        row.meta:SetText(meta .. (reward.isCollected and "   " .. KEPT_CODE .. "Collected|r" or ""))
        return ITEM_H
    end,
}
