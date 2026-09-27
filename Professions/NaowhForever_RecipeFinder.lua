-------------------------------------------------------------------------------
--  NaowhForever_RecipeFinder.lua -- the recipes you have not learned yet, and for each the
--  skill it needs, what it costs and where it comes from: the nearest trainers, the vendor
--  selling its manual, or the mobs that drop it. Trainer and vendor lines set a waypoint.
--  Naowh's profession window lists them through ns.RecipeFinder; with that window off they
--  show in a drawer on Blizzard's. Data: RecipeData.lua.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local T = ns.THEME

local WIDTH, HEADER_H, ROW_H, DETAIL_H = 280, 34, 22, 236
local MAX_LINES, NEAREST = 7, 3
local GREEN = { r = 0.35, g = 1, b = 0.35 }
local ORANGE = { r = 1, g = 0.6, b = 0.2 }

local panel, hooked
local list, rows = {}, {}
local state, selected
local offset = 0

local function On()
    return S.Get("enabled") and S.Get("recipeFinder")
end

local function Faction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

local function ForMe(fac)
    return fac == "-" or fac:find(Faction(), 1, true) ~= nil
end

local function Money(copper)
    if not copper or copper <= 0 then return "free" end
    return GetMoneyString and GetMoneyString(copper, true) or C_CurrencyInfo.GetCoinTextureString(copper)
end

local function ZoneName(map)
    local info = C_Map.GetMapInfo(map)
    return info and info.name or "?"
end

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

-------------------------------------------------------------------------------
--  Profession state
-------------------------------------------------------------------------------
local function Match(p)
    if not p then return end
    if ns.RecipeData[p.professionID] then return p.professionID end
    if ns.RecipeData[p.parentProfessionID] then return p.parentProfessionID end
    for id, data in pairs(ns.RecipeData) do
        if p.professionName and p.professionName == C_Spell.GetSpellName(data.skillSpell) then return id end
    end
end

-- Only your own profession: a linked or guild recipe list, or an NPC's crafting window, is
-- somebody else's recipes.
local function ReadProfession()
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then return end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return end
    local child, base = C_TradeSkillUI.GetChildProfessionInfo(), C_TradeSkillUI.GetBaseProfessionInfo()
    local id = Match(child) or Match(base)
    if not id then return end
    local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
    return id, src.skillLevel or 0, src.maxSkillLevel or 0
end

local function Learned(spell)
    local info = C_TradeSkillUI.GetRecipeInfo(spell)
    if info and info.learned then return true end
    return C_SpellBook.IsSpellKnown(spell)
end

-- What profession trainers actually ask, read off their window: Forever lowered many trainer
-- requirements and Wowhead still lists the older ones. Account-wide, spellID -> { skill, cost }.
local function Overrides()
    local account = ns.AccountSettings()
    account.profTrainerReq = account.profTrainerReq or {}
    return account.profTrainerReq
end

local function Skill(r)
    local o = Overrides()[r.spell]
    return o and o[1] or r.skill
end

local function Cost(r)
    local o = Overrides()[r.spell]
    return o and o[2] or r.cost
end

-- "ready": learnable now. "later": your cap allows it, your skill does not yet.
-- "rank": your cap is below it, so the next profession rank comes first.
local function Status(r)
    if state.skill >= Skill(r) then return "ready" end
    if state.max < Skill(r) then return "rank" end
    return "later"
end

local function NextRank()
    for _, rank in ipairs(state.data.ranks) do
        if rank.cap > state.max then return rank end
    end
end

-------------------------------------------------------------------------------
--  Nearest NPCs
-------------------------------------------------------------------------------
local function WorldPos(map, x, y)
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if ok and cont and pos then return cont, pos end
end

-- The NPCs your faction can use, nearest first. Anything on another continent (or while
-- you are somewhere with no map position) sorts after, alphabetically.
local function Nearest(npcs, n)
    local map = C_Map.GetBestMapForUnit("player")
    local here = map and C_Map.GetPlayerMapPosition(map, "player")
    local cont, pos
    if here then cont, pos = WorldPos(map, here:GetXY()) end
    local out = {}
    for _, npc in ipairs(npcs) do
        if ForMe(npc[3]) then
            local dist = math.huge
            if cont and npc[4] > 0 then
                local c, p = WorldPos(npc[4], npc[5] / 100, npc[6] / 100)
                if c == cont then
                    local x1, y1 = pos:GetXY()
                    local x2, y2 = p:GetXY()
                    dist = (x1 - x2) ^ 2 + (y1 - y2) ^ 2
                end
            end
            out[#out + 1] = { npc = npc, dist = dist }
        end
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.npc[2] < b.npc[2]
    end)
    local picked = {}
    for i = 1, math.min(n or #out, #out) do picked[i] = out[i].npc end
    return picked
end

-------------------------------------------------------------------------------
--  Detail text
-------------------------------------------------------------------------------
local RenderDetail

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if name then return Hex(T.accent) .. name .. "|r" end
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if panel and panel:IsShown() then RenderDetail() end
    end)
    return "its manual"
end

-- The detail reads as paragraphs, each followed by the NPCs it talks about.
local function Para(out, text)
    out[#out + 1] = { text = text, para = true }
end

local function NpcLine(out, npc, extra)
    out[#out + 1] = {
        text = ("%s - %s %.1f, %.1f%s"):format(npc[2], ZoneName(npc[4]), npc[5], npc[6], extra or ""),
        npc = npc,
    }
end

-- Trainer lists in the data are indices into the profession's trainers, so each NPC is written
-- out once; rank books, quest givers and vendors are full rows.
local function Rows(list)
    if not list or type(list[1]) ~= "number" then return list or {} end
    local rows = {}
    for i, index in ipairs(list) do rows[i] = state.data.trainers[index] end
    return rows
end

local function QuestTitle(id, fallback)
    return id and C_QuestLog.GetTitleForQuestID(id) or fallback or "?"
end

local function DescribeRank(rank, r, out)
    if rank.item then
        Para(out, ("Your cap is %d.\nFirst read %s (needs skill %d):"):format(
            state.max, ItemName(rank.item), rank.skill))
        for _, v in ipairs(Nearest(rank.vendors, 1)) do NpcLine(out, v, "  " .. Money(v[7])) end
    elseif rank.quest then
        local title = QuestTitle(rank.quest[Faction()], rank.questName)
        Para(out, ("Your cap is %d.\nFirst do the quest %s%s|r (%sskill %d):"):format(state.max,
            Hex(T.accent), title, rank.level and ("level " .. rank.level .. ", ") or "", rank.skill))
        for _, v in ipairs(Nearest(rank.teachers, 1)) do NpcLine(out, v) end
    else
        Para(out, ("Your cap is %d.\nFirst train %s (%s, needs skill %d):"):format(
            state.max, rank.name, Money(rank.cost), rank.skill))
        for _, v in ipairs(Nearest(rank.t and Rows(rank.t) or state.data.trainers, 1)) do NpcLine(out, v) end
    end
end

local function DescribeQuests(out, quests, recipe)
    local mine = {}
    for _, q in ipairs(quests) do
        if ForMe(q.side or "AH") then mine[#mine + 1] = q end
    end
    if #mine == 0 then
        Para(out, (recipe and ("Recipe: " .. ItemName(recipe) .. "\n") or "")
            .. "A quest reward for the other faction; try the Auction House.")
        return
    end
    local names = {}
    for i, q in ipairs(mine) do names[i] = Hex(T.accent) .. QuestTitle(q.id, q.name) .. "|r" end
    Para(out, (recipe and ("Recipe: " .. ItemName(recipe) .. "\n") or "")
        .. "A reward from the quest " .. table.concat(names, " or ") .. ":")
    for _, q in ipairs(mine) do
        if q.npc then NpcLine(out, q.npc, "  (quest giver)") end
    end
end

local function Describe(r)
    local out = {}
    local data = state.data
    if Status(r) == "rank" then
        local rank = NextRank()
        if rank then DescribeRank(rank, r, out) end
    end

    if r.source == "trainer" then
        Para(out, ("Trainer: %s.%s Nearest:"):format(Money(Cost(r)),
            r.quest and (" Also a reward from the quest " .. Hex(T.accent) .. r.quest .. "|r.") or ""))
        for _, v in ipairs(Nearest(r.t and Rows(r.t) or data.trainers, NEAREST)) do NpcLine(out, v) end
    elseif r.source == "teacher" then
        Para(out, "Taught for free by the Artisan doctor:")
        for _, rank in ipairs(data.ranks) do
            if rank.teachers then
                for _, v in ipairs(Nearest(rank.teachers, 1)) do NpcLine(out, v) end
            end
        end
    elseif r.source == "vendor" then
        local sellers = Nearest(r.vendors)
        if #sellers == 0 then
            Para(out, ("Recipe: %s\nOnly the other faction sells it; try the Auction House."):format(
                ItemName(r.recipe)))
        else
            local price = sellers[1][7] and ("Sold for " .. Money(sellers[1][7])) or "Sold"
            Para(out, ("Recipe: %s\n%s%s by:"):format(ItemName(r.recipe), price,
                r.rep and (" (needs " .. r.rep .. ")") or ""))
            for i = 1, math.min(NEAREST, #sellers) do NpcLine(out, sellers[i]) end
        end
    elseif r.source == "drop" and r.bosses then
        Para(out, ("Recipe: %s\nDrops from:"):format(ItemName(r.recipe)))
        for _, b in ipairs(r.bosses) do
            out[#out + 1] = { text = ("%s - %s"):format(b[1], b[2] and C_Map.GetAreaInfo(b[2]) or "?") }
        end
    elseif r.source == "drop" and r.world then
        Para(out, ("Recipe: %s\nA world drop%s. Also try the Auction House."):format(ItemName(r.recipe),
            r.world > 1 and (", from mobs around level " .. r.world) or ""))
    elseif r.source == "drop" then
        local extra = {}
        if r.chests then extra[#extra + 1] = "chests and lockboxes" end
        if r.fished then extra[#extra + 1] = "fishing" end
        if r.pickpocket then extra[#extra + 1] = "pickpocketing" end
        local from = (r.mobs or 0) > 0 and ("A world drop from %d kinds of mob"):format(r.mobs) or "Found"
        Para(out, ("Recipe: %s\n%s%s.%s"):format(ItemName(r.recipe), from,
            #extra > 0 and ((r.mobs or 0) > 0 and ", " or " through ") .. table.concat(extra, ", ") or "",
            #(r.drops or {}) > 0 and " Best odds:" or ""))
        for _, d in ipairs(r.drops or {}) do
            local level = d[3] == d[4] and tostring(d[3]) or (d[3] .. "-" .. d[4])
            out[#out + 1] = { text = ("%s (%s) - %s, %.1f%%"):format(d[1], level,
                C_Map.GetAreaInfo(d[2]) or "?", d[5]) }
        end
    elseif r.source == "quest" then
        DescribeQuests(out, r.quests, r.recipe)
    else
        Para(out, (r.recipe and ("Recipe: " .. ItemName(r.recipe) .. "\n") or "")
            .. "Where it comes from is not recorded yet; try the Auction House.")
    end
    return out
end

-------------------------------------------------------------------------------
--  The panel
-------------------------------------------------------------------------------
local Render

-- A drawer on Blizzard's window's right edge, overlapping its 1px border so the two read as one.
local function Collapsed()
    return S.Get("recipeFinderCollapsed")
end

local function Place()
    local pf = ProfessionsFrame
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", pf, "TOPRIGHT", -1, 0)
    if Collapsed() then
        panel:SetHeight(HEADER_H)
    else
        panel:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", -1, 0)
    end
    panel:SetFrameLevel(pf:GetFrameLevel() + 20)
end

local function VisibleRows()
    return math.max(1, math.floor((ProfessionsFrame:GetHeight() - HEADER_H - DETAIL_H - 8) / ROW_H))
end

-------------------------------------------------------------------------------
--  Side tabs
-------------------------------------------------------------------------------
-- Whatever hangs off the window's right edge (profession tab strips from Blizzard or another
-- addon) moves out by the drawer's width while it is open, and back when it closes. Only
-- frames anchored to the window itself are moved; a chain of tabs follows its first one.
-- Tabs may be secure buttons, so this never runs in combat.
local shifted, shiftedOn, shiftPending = {}, false, nil

local function RightAnchored(p)
    return p[2] == ProfessionsFrame and type(p[3]) == "string" and p[3]:find("RIGHT") ~= nil
end

local function Candidates(right, out)
    local function Check(f)
        if f == panel or out[f] or (f.IsForbidden and f:IsForbidden()) or not f:IsShown() then return end
        local left = f:GetLeft()
        if not left or left < right - 2 then return end
        local pts, hit = {}, false
        for i = 1, f:GetNumPoints() do
            local p = { f:GetPoint(i) }
            pts[i] = p
            if RightAnchored(p) then hit = true end
        end
        if hit then out[f] = pts end
    end
    for _, f in ipairs({ ProfessionsFrame:GetChildren() }) do Check(f) end
    for _, f in ipairs({ UIParent:GetChildren() }) do Check(f) end
    return out
end

local function ShiftTabs(on)
    if on == shiftedOn then
        shiftPending = nil
        return
    end
    if InCombatLockdown() then
        shiftPending = on
        return
    end
    shiftPending = nil
    shiftedOn = on
    if on then
        local right = ProfessionsFrame:GetRight()
        if not right then return end
        for f, pts in pairs(Candidates(right, {})) do
            shifted[f] = pts
            f:ClearAllPoints()
            for _, p in ipairs(pts) do
                f:SetPoint(p[1], p[2], p[3], (p[4] or 0) + (RightAnchored(p) and WIDTH - 1 or 0), p[5] or 0)
            end
        end
    else
        for f, pts in pairs(shifted) do
            f:ClearAllPoints()
            for _, p in ipairs(pts) do f:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
        end
        wipe(shifted)
    end
end

local function RowColor(r)
    local st = Status(r)
    if st == "ready" then return GREEN end
    if st == "rank" then return ORANGE end
    return T.muted
end

local SOURCE_TAG = { trainer = "Trainer", teacher = "Trainer", vendor = "Vendor", drop = "Drop",
    unknown = "?" }

local function BuildRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(WIDTH - 16, ROW_H - 2)
    row:SetPoint("TOPLEFT", 8, -HEADER_H - (i - 1) * ROW_H)
    row.sel = ns.Solid(row, "BACKGROUND", T.accent, 0.25)
    row.sel:SetAllPoints()
    row.hl = ns.Solid(row, "BACKGROUND", T.panel, 0.9)
    row.hl:SetAllPoints()
    row.hl:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.tag = ns.Font(row, 11, nil, T.muted)
    row.tag:SetPoint("RIGHT", -4, 0)
    row.tag:SetJustifyH("RIGHT")
    row.skill = ns.Font(row, 12, nil)
    row.skill:SetPoint("RIGHT", -58, 0)
    row.name = ns.Font(row, 12, nil)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.skill, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        selected = self.recipe
        Render()
    end)
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.recipe.spell)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip_Hide()
    end)
    row:SetScript("OnMouseWheel", function(_, delta) panel:GetScript("OnMouseWheel")(panel, delta) end)
    return row
end

local function BuildLine(detail)
    local line = CreateFrame("Button", nil, detail)
    line:SetSize(WIDTH - 24, 16)
    line.text = ns.Font(line, 12, nil)
    line.text:SetPoint("LEFT")
    line.text:SetPoint("RIGHT")
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    line:SetScript("OnClick", function(self)
        local npc = self.npc
        if npc and ns.PlaceWaypoint then ns.PlaceWaypoint(npc[2], npc[4], npc[5], npc[6]) end
    end)
    line:SetScript("OnEnter", function(self)
        if not self.npc then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.npc[2], 1, 1, 1)
        GameTooltip:AddLine("Click to set a waypoint.", T.accent.r, T.accent.g, T.accent.b)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", GameTooltip_Hide)
    return line
end

local function Build()
    panel = CreateFrame("Frame", "NaowhForeverRecipeFinder", ProfessionsFrame)
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    ns.Solid(panel, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(panel)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga")
    logo:SetSize(20, 20)
    logo:SetPoint("LEFT", 8, 0)
    panel.title = ns.Font(header, 14, "OUTLINE", T.accent)
    panel.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    panel.collapse = ns.Button(header, "-", 20, 20, function()
        S.Set("recipeFinderCollapsed", not S.Get("recipeFinderCollapsed"))
        Place()
        Render()
    end)
    panel.collapse:SetPoint("RIGHT", -4, 0)

    panel.more = ns.Font(panel, 11, nil, T.muted)

    local detail = CreateFrame("Frame", nil, panel)
    detail:SetPoint("BOTTOMLEFT", 0, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)
    detail:SetHeight(DETAIL_H)
    local sep = ns.Solid(detail, "ARTWORK", T.line, 1)
    sep:SetPoint("TOPLEFT", 8, 0)
    sep:SetPoint("TOPRIGHT", -8, 0)
    sep:SetHeight(1)

    detail.icon = detail:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(30, 30)
    detail.icon:SetPoint("TOPLEFT", 10, -10)
    detail.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    detail.title = ns.Font(detail, 14, nil)
    detail.title:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 8, 0)
    detail.title:SetPoint("RIGHT", -10, 0)
    detail.title:SetJustifyH("LEFT")
    detail.req = ns.Font(detail, 12, nil)
    detail.req:SetPoint("BOTTOMLEFT", detail.icon, "BOTTOMRIGHT", 8, 0)

    detail.paras = {}
    for i = 1, 3 do
        local fs = ns.Font(detail, 12, nil)
        fs:SetWidth(WIDTH - 20)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetSpacing(2)
        detail.paras[i] = fs
    end

    detail.lines = {}
    for i = 1, MAX_LINES do detail.lines[i] = BuildLine(detail) end
    panel.detail = detail

    panel:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #list - VisibleRows())
        offset = math.min(maxOffset, math.max(0, offset - delta))
        Render()
    end)
end

RenderDetail = function()
    local detail = panel.detail
    local r = selected
    local profName = C_Spell.GetSpellName(state.data.skillSpell) or "First Aid"
    for _, line in ipairs(detail.lines) do line:Hide() end
    for _, fs in ipairs(detail.paras) do fs:Hide() end
    if not r then
        detail.icon:Hide()
        detail.title:SetText("")
        detail.req:SetText("")
        local fs = detail.paras[1]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 10, -12)
        fs:SetText(#list == 0 and ("You know every " .. profName .. " recipe.")
            or "Click a recipe to see where to learn it.")
        fs:Show()
        return
    end

    detail.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
    detail.icon:Show()
    detail.title:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
    detail.req:SetText(("%sRequires %s %d|r   %s(you: %d/%d)|r"):format(Hex(RowColor(r)), profName,
        Skill(r), Hex(T.muted), state.skill, state.max))

    local y, nPara, nLine = -50, 0, 0
    for _, entry in ipairs(Describe(r)) do
        if entry.para then
            nPara = nPara + 1
            local fs = detail.paras[nPara]
            if not fs then break end
            if nPara > 1 then y = y - 6 end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 10, y)
            fs:SetText(entry.text)
            fs:Show()
            y = y - fs:GetStringHeight() - 4
        else
            nLine = nLine + 1
            local line = detail.lines[nLine]
            if not line then break end
            line.npc = entry.npc
            line.text:SetText(entry.text)
            local c = entry.npc and T.accent or T.fg
            line.text:SetTextColor(c.r, c.g, c.b, 1)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 14, y)
            line:Show()
            y = y - 17
        end
    end
end

Render = function()
    Place()
    local collapsed = Collapsed()
    ns.SetButtonText(panel.collapse, collapsed and "+" or "-")
    panel.title:SetText(("Unlearned Recipes (%d)"):format(#list))
    panel.detail:SetShown(not collapsed)

    local visible = collapsed and 0 or VisibleRows()
    offset = math.min(offset, math.max(0, #list - visible))
    for i = 1, math.max(visible, #rows) do
        local row = rows[i]
        local r = i <= visible and list[i + offset]
        if r then
            row = row or BuildRow(i)
            rows[i] = row
            row.recipe = r
            row.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
            row.name:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
            local c = RowColor(r)
            row.name:SetTextColor(c.r, c.g, c.b, 1)
            row.skill:SetText(Skill(r))
            row.skill:SetTextColor(c.r, c.g, c.b, 1)
            row.tag:SetText(SOURCE_TAG[r.source])
            row.sel:SetShown(r == selected)
            row:Show()
        elseif row then
            row:Hide()
        end
    end

    panel.more:ClearAllPoints()
    local hidden = #list - visible - offset
    if not collapsed and (offset > 0 or hidden > 0) then
        panel.more:SetPoint("BOTTOMRIGHT", panel.detail, "TOPRIGHT", -10, 4)
        panel.more:SetText(("scroll for more (%d-%d of %d)"):format(offset + 1, offset + visible, #list))
        panel.more:Show()
    else
        panel.more:Hide()
    end

    if not collapsed then RenderDetail() end
    ShiftTabs(not collapsed)
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
local function Hide()
    if panel then panel:Hide() end
    ShiftTabs(false)
end

-- Reads the open profession into state and list. False when it is not one with data, or not
-- your own.
local function Compute()
    local id, skill, max = ReadProfession()
    if not id then
        state, list = nil, {}
        return false
    end
    if not state or state.id ~= id then selected, offset = nil, 0 end
    state = { id = id, data = ns.RecipeData[id], skill = skill, max = max }
    list = {}
    for _, r in ipairs(state.data.recipes) do
        if not Learned(r.spell) then list[#list + 1] = r end
    end
    table.sort(list, function(a, b)
        local sa, sb = Skill(a), Skill(b)
        if sa ~= sb then return sa < sb end
        return a.spell < b.spell
    end)
    if selected and not tContains(list, selected) then selected = nil end
    return true
end

local function Refresh()
    if not (On() and ProfessionsFrame and ProfessionsFrame:IsShown()) or ns.ProfWindowActive then
        return Hide()
    end
    -- The overview tab's book page lists every profession, not recipes.
    if ProfessionsFrame.BookPage and ProfessionsFrame.BookPage:IsShown() then return Hide() end
    if ProfessionsFrame.GetTab and ProfessionsFrame.recipesTabID
        and ProfessionsFrame:GetTab() ~= ProfessionsFrame.recipesTabID then
        return Hide()
    end
    if not Compute() then return Hide() end

    if not panel then Build() end
    panel:Show()
    Render()
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Refresh()
    end)
end
ns.RecipeFinderRefresh = Queue

-- For Naowh's profession window: the unlearned recipes of the open profession (empty when the
-- finder is off or has no data for it), each one's colour and requirement line, and the
-- paragraphs and NPC lines saying where to learn it.
ns.RecipeFinder = {
    Unlearned = function()
        if not (On() and Compute()) then return {} end
        return list
    end,
    Color = function(r) return RowColor(r) end,
    Requirement = function(r)
        local profName = C_Spell.GetSpellName(state.data.skillSpell) or "First Aid"
        return ("%sRequires %s %d|r   %s(you: %d/%d)|r"):format(Hex(RowColor(r)), profName, Skill(r),
            Hex(T.muted), state.skill, state.max)
    end,
    Describe = function(r) return Describe(r) end,
    Tag = function(r) return SOURCE_TAG[r.source] end,
    Skill = function(r) return Skill(r) end,
}

-- At a profession trainer: remember what each recipe on offer really needs and costs.
-- Matched by name within the trainer's profession, since the service list has no spell IDs.
local function ScanTrainer()
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    local byName, lineOf = {}, {}
    for line, data in pairs(ns.RecipeData) do
        lineOf[C_Spell.GetSpellName(data.skillSpell) or ""] = line
        for _, r in ipairs(data.recipes) do
            local name = C_Spell.GetSpellName(r.spell)
            if name then
                byName[name] = byName[name] or {}
                byName[name][#byName[name] + 1] = { r = r, line = line }
            end
        end
    end
    local overrides, changed = Overrides(), false
    for i = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(i)
        local skillName, rank = GetTrainerServiceSkillReq(i)
        if name and category ~= "header" and rank and byName[name] then
            local line = lineOf[skillName or ""]
            for _, m in ipairs(byName[name]) do
                if not line or m.line == line then
                    local cost = GetTrainerServiceCost(i)
                    local old = overrides[m.r.spell]
                    if not old or old[1] ~= rank or old[2] ~= cost then
                        overrides[m.r.spell] = { rank, cost }
                        changed = true
                    end
                end
            end
        end
    end
    if changed and ns.ProfWindowRefresh then ns.ProfWindowRefresh() end
end

local trainerQueued = false
local function QueueTrainerScan()
    if trainerQueued then return end
    trainerQueued = true
    C_Timer.After(0.2, function()
        trainerQueued = false
        ScanTrainer()
    end)
end

-- /naowh recipes: what the profession API reports on this client, to check the finder's
-- reading of it.
function ns.RecipeFinderDebug()
    local function Dump(label, p)
        if not p then
            ns.Print(label .. ": nil")
            return
        end
        ns.Print(("%s: id=%s parent=%s name=%s skill=%s/%s"):format(label, tostring(p.professionID),
            tostring(p.parentProfessionID), tostring(p.professionName), tostring(p.skillLevel),
            tostring(p.maxSkillLevel)))
    end
    Dump("child", C_TradeSkillUI.GetChildProfessionInfo())
    Dump("base", C_TradeSkillUI.GetBaseProfessionInfo())
    local id, skill, max = ReadProfession()
    ns.Print(("matched=%s skill=%s/%s"):format(tostring(id), tostring(skill), tostring(max)))
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
    local apiUnlearned = 0
    for _, rid in ipairs(ids) do
        local info = C_TradeSkillUI.GetRecipeInfo(rid)
        if info and not info.learned then apiUnlearned = apiUnlearned + 1 end
    end
    ns.Print(("API recipes: %d (%d unlearned)"):format(#ids, apiUnlearned))
    if id then
        local learned = 0
        for _, r in ipairs(ns.RecipeData[id].recipes) do
            if Learned(r.spell) then learned = learned + 1 end
        end
        ns.Print(("Data recipes: %d, %d learned"):format(#ns.RecipeData[id].recipes, learned))
    end
    local pf = ProfessionsFrame
    if not (pf and pf:IsShown() and pf:GetRight()) then return end
    ns.Print(("Tabs moved: %s. Frames past the window's right edge:"):format(shiftedOn and "yes" or "no"))
    local edge = pf:GetRight() + (shiftedOn and WIDTH or 0)
    local all = { pf:GetChildren() }
    for _, f in ipairs({ UIParent:GetChildren() }) do all[#all + 1] = f end
    for _, f in ipairs(all) do
        local left = not (f.IsForbidden and f:IsForbidden()) and f:IsShown() and f ~= panel and f:GetLeft()
        if left and left >= pf:GetRight() - 2 and left <= edge + 80 then
            local _, rel, relPoint = f:GetPoint(1)
            ns.Print(("  %s -> %s %s%s"):format(f:GetDebugName(), rel and rel:GetDebugName() or "?",
                tostring(relPoint), shifted[f] and " (moved)" or ""))
        end
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then return QueueTrainerScan() end
    if event == "PLAYER_REGEN_ENABLED" then
        if shiftPending ~= nil then ShiftTabs(shiftPending) end
        return
    end
    if event == "ADDON_LOADED" then
        if name ~= "Blizzard_Professions" then return end
        events:UnregisterEvent("ADDON_LOADED")
    end
    if not hooked and ProfessionsFrame then
        hooked = true
        ProfessionsFrame:HookScript("OnShow", Queue)
        ProfessionsFrame:HookScript("OnSizeChanged", Queue)
        ProfessionsFrame:HookScript("OnHide", function() ShiftTabs(false) end)
        if ProfessionsFrame.SetTab then hooksecurefunc(ProfessionsFrame, "SetTab", Queue) end
    end
    Queue()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then return Hide() end
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("TRAINER_SHOW")
    events:RegisterEvent("TRAINER_UPDATE")
    if not C_AddOns.IsAddOnLoaded("Blizzard_Professions") then events:RegisterEvent("ADDON_LOADED") end
    events:GetScript("OnEvent")(events, "APPLY")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "recipeFinder" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
