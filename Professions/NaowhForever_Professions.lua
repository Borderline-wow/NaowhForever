-------------------------------------------------------------------------------
--  NaowhForever_Professions.lua -- Naowh's profession window. Your recipes by category
--  on the left with the ones you have not learned below them, the chosen recipe in the
--  middle (reagents and craft buttons, or where to learn it), and Blizzard's own profession
--  tabs moved onto its edge. The overview tab shows every profession as a card instead.
--
--  Blizzard's own window stays open underneath at zero alpha: hiding it would close the
--  trade skill (its OnHide calls CloseTradeSkill) and take the recipe data with it. This
--  window covers it, one strata higher, so nothing of it can be clicked. Closing either
--  one closes the profession.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

-- The Professions module's settings, its own profile section. `enabled` is the sidebar
-- switch for the whole module; off leaves Blizzard's window alone.
local S = UI.ModuleSettings("professions", {
    enabled = true, profWindow = true, recipeFinder = true,
})
ns.ProfessionSettings = S

local MIN_H, PAD = 620, 8
local LEFT_W, MID_W = 280, 400
local MID_X = PAD + LEFT_W + PAD
local W = MID_X + MID_W + PAD
local TOP_Y = -68
local ROW_H, REAGENT_H, MAX_REAGENTS = 20, 36, 8
local MAX_PARAS, MAX_LINES = 3, 7
local PRIMARY_H, CARD_GAP = 128, 8
-- Blizzard's book cards, in the order this window's cards are laid out.
local BOOK_ORDER = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
    "SecondaryProfession2", "SecondaryProfession3" }
local SECONDARY_NAMES = { PROFESSIONS_COOKING or "Cooking", PROFESSIONS_FISHING or "Fishing",
    PROFESSIONS_FIRST_AID or "First Aid" }
local GOLD = { r = 1, g = 0.82, b = 0 }
local RED = { r = 1, g = 0.3, b = 0.3 }
-- Enum.TradeskillRelativeDifficulty: Optimal, Medium, Easy, Trivial.
local DIFFICULTY = {
    [0] = { r = 1, g = 0.5, b = 0.25 },
    [1] = { r = 1, g = 1, b = 0 },
    [2] = { r = 0.25, g = 0.75, b = 0.25 },
    [3] = { r = 0.55, g = 0.55, b = 0.55 },
}
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }

local win, hooked
local categories, entries, rows, unlearned = {}, {}, {}, {}
local collapsed = {}
local selectedID, offset, query = nil, 0, ""
-- An unlearned recipe (a RecipeData row) when one is chosen; it takes over the middle column.
local selectedUnlearned
local UNLEARNED = { name = "Unlearned", unlearned = true }

local function On()
    return S.Get("enabled") and S.Get("profWindow")
end

local function Own()
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then return false end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return false end
    return true
end

local function Profession()
    local child, base = C_TradeSkillUI.GetChildProfessionInfo(), C_TradeSkillUI.GetBaseProfessionInfo()
    local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
    if not src then return end
    return {
        id = base and base.professionID or src.professionID,
        name = (base and base.professionName) or src.professionName or "",
        skill = src.skillLevel or 0,
        max = src.maxSkillLevel or 0,
    }
end

local function NextStrata(strata)
    for i, s in ipairs(STRATA) do
        if s == strata then return STRATA[math.min(i + 1, #STRATA)] end
    end
    return "HIGH"
end

local function SetColor(fs, c)
    fs:SetTextColor(c.r, c.g, c.b, 1)
end

-------------------------------------------------------------------------------
--  Recipes
-------------------------------------------------------------------------------
local function Collect()
    wipe(categories)
    local byID = {}
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned then
            local catID = info.categoryID or 0
            local cat = byID[catID]
            if not cat then
                local ci = catID > 0 and C_TradeSkillUI.GetCategoryInfo(catID)
                cat = { id = catID, name = ci and ci.name or OTHER or "Other", order = ci and ci.uiOrder or 999,
                    recipes = {} }
                byID[catID] = cat
                categories[#categories + 1] = cat
            end
            cat.recipes[#cat.recipes + 1] = info
        end
    end
    table.sort(categories, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    unlearned = ns.RecipeFinder and ns.RecipeFinder.Unlearned() or {}
end

local function IsCollapsed(cat)
    if query ~= "" then return false end
    if cat.unlearned then return S.Get("profUnlearnedCollapsed") end
    return collapsed[cat.name]
end

local function ToggleCollapsed(cat)
    if cat.unlearned then
        S.Set("profUnlearnedCollapsed", not S.Get("profUnlearnedCollapsed"))
    else
        collapsed[cat.name] = not collapsed[cat.name] or nil
    end
end

local function Matches(info)
    return query == "" or (info.name and info.name:lower():find(query, 1, true) ~= nil)
end

local function BuildEntries()
    wipe(entries)
    local first, found
    for _, cat in ipairs(categories) do
        local shown = {}
        for _, info in ipairs(cat.recipes) do
            if Matches(info) then shown[#shown + 1] = info end
        end
        if #shown > 0 then
            entries[#entries + 1] = { cat = cat }
            -- A search opens every category, so a match is never hidden in a closed one.
            local open = not IsCollapsed(cat)
            for _, info in ipairs(shown) do
                first = first or info.recipeID
                if info.recipeID == selectedID then found = true end
                if open then entries[#entries + 1] = { recipe = info } end
            end
        end
    end

    local shownU, foundU = {}, false
    for _, r in ipairs(unlearned) do
        local name = C_Spell.GetSpellName(r.spell) or ""
        if query == "" or name:lower():find(query, 1, true) then shownU[#shownU + 1] = r end
    end
    if #shownU > 0 then
        UNLEARNED.count = #shownU
        entries[#entries + 1] = { cat = UNLEARNED }
        local open = not IsCollapsed(UNLEARNED)
        for _, r in ipairs(shownU) do
            if r == selectedUnlearned then foundU = true end
            if open then entries[#entries + 1] = { unlearned = r } end
        end
    end

    if not foundU then selectedUnlearned = nil end
    if not found then selectedID = first end
end

local function SelectedInfo()
    return not selectedUnlearned and selectedID and C_TradeSkillUI.GetRecipeInfo(selectedID)
end

-- itemID and quantity per reagent. The schematic call is the current API; the reagent-info
-- pair is the older one, kept as a fallback in case Forever still answers only that.
local function Reagents(recipeID)
    local out = {}
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if ok and schematic and schematic.reagentSlotSchematics then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reagent = slot.reagents and slot.reagents[1]
            if slot.required ~= false and reagent and reagent.itemID then
                out[#out + 1] = { itemID = reagent.itemID, need = slot.quantityRequired or 1 }
            end
        end
        return out
    end
    if C_TradeSkillUI.GetRecipeNumReagents then
        for i = 1, C_TradeSkillUI.GetRecipeNumReagents(recipeID) or 0 do
            local _, _, need = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
            local link = C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, i)
            local itemID = link and C_Item.GetItemInfoInstant(link)
            if itemID then out[#out + 1] = { itemID = itemID, need = need or 1 } end
        end
    end
    return out
end

local function ItemCount(itemID)
    return C_Item.GetItemCount(itemID, false, false, true) or 0
end

-- How many you can make from your bags. Forever answers numAvailable with 0, so it is worked
-- out from the reagents when the game gives nothing.
local function Craftable(info)
    if (info.numAvailable or 0) > 0 then return info.numAvailable end
    local reagents = Reagents(info.recipeID)
    if #reagents == 0 then return 0 end
    local n = math.huge
    for _, r in ipairs(reagents) do
        n = math.min(n, math.floor(ItemCount(r.itemID) / math.max(r.need, 1)))
    end
    return n
end

local function Craft(count)
    local info = SelectedInfo()
    if not info or count < 1 then return end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, info.recipeID, count)
    if not ok then ns.Print("Could not craft: " .. tostring(err)) end
end

-------------------------------------------------------------------------------
--  Rendering
-------------------------------------------------------------------------------
local Render, RenderList, RenderDetail, RenderLearn

local function VisibleRows()
    return math.max(1, math.floor((win.list:GetHeight()) / ROW_H))
end

RenderList = function()
    local visible = VisibleRows()
    offset = math.min(offset, math.max(0, #entries - visible))
    for i = 1, visible do
        local row = rows[i]
        local e = entries[i + offset]
        if e then
            if not row then
                row = win.BuildRow(i)
                rows[i] = row
            end
            row.entry = e
            row.icon:ClearAllPoints()
            if e.cat then
                local label = e.cat.unlearned and ("%s (%d)"):format(e.cat.name, e.cat.count) or e.cat.name
                row.text:SetText((IsCollapsed(e.cat) and "+  " or "-  ") .. label)
                SetColor(row.text, GOLD)
                row.text:SetPoint("LEFT", 4, 0)
                row.count:SetText("")
                row.icon:Hide()
                row.head:Show()
                row.sel:Hide()
            elseif e.unlearned then
                local r = e.unlearned
                local c = ns.RecipeFinder.Color(r)
                row.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
                row.icon:SetPoint("LEFT", 14, 0)
                row.icon:Show()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
                SetColor(row.text, c)
                row.count:SetText(ns.RecipeFinder.Skill(r))
                SetColor(row.count, c)
                row.head:Hide()
                row.sel:SetShown(r == selectedUnlearned)
            else
                local info = e.recipe
                SetColor(row.count, T.fg)
                row.icon:SetTexture(info.icon)
                row.icon:SetPoint("LEFT", 14, 0)
                row.icon:Show()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetText(info.name)
                SetColor(row.text, DIFFICULTY[info.relativeDifficulty] or T.fg)
                local n = Craftable(info)
                row.count:SetText(n > 0 and ("(" .. n .. ")") or "")
                row.head:Hide()
                row.sel:SetShown(not selectedUnlearned and info.recipeID == selectedID)
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
end

RenderLearn = function(r)
    local l = win.learn
    l.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
    l.name:SetText(C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell))
    SetColor(l.name, ns.RecipeFinder.Color(r))
    l.req:SetText(ns.RecipeFinder.Requirement(r))
    for _, fs in ipairs(l.paras) do fs:Hide() end
    for _, line in ipairs(l.lines) do line:Hide() end
    local y, nPara, nLine = -72, 0, 0
    for _, entry in ipairs(ns.RecipeFinder.Describe(r)) do
        if entry.para then
            nPara = nPara + 1
            local fs = l.paras[nPara]
            if not fs then break end
            if nPara > 1 then y = y - 8 end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 14, y)
            fs:SetText(entry.text)
            fs:Show()
            y = y - fs:GetStringHeight() - 6
        else
            nLine = nLine + 1
            local line = l.lines[nLine]
            if not line then break end
            line.npc = entry.npc
            line.text:SetText(entry.text)
            SetColor(line.text, entry.npc and T.accent or T.fg)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 20, y)
            line:Show()
            y = y - 18
        end
    end
end

RenderDetail = function()
    local d = win.detail
    if selectedUnlearned then
        d:Hide()
        win.empty:Hide()
        win.learn:Show()
        return RenderLearn(selectedUnlearned)
    end
    win.learn:Hide()
    local info = SelectedInfo()
    d:SetShown(info ~= nil)
    win.empty:SetShown(info == nil)
    if not info then return end

    d.icon:SetTexture(info.icon)
    d.name:SetText(info.name)
    SetColor(d.name, DIFFICULTY[info.relativeDifficulty] or T.fg)

    local ok, desc = pcall(C_TradeSkillUI.GetRecipeDescription, info.recipeID, {})
    local lines = { ok and desc or "" }
    local okReq, reqs = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
    if okReq and reqs and #reqs > 0 then
        local parts = {}
        for _, req in ipairs(reqs) do
            local c = req.met and T.fg or RED
            parts[#parts + 1] = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, req.name)
        end
        lines[#lines + 1] = "Requires: " .. table.concat(parts, ", ")
    end
    local okCd, cooldown = pcall(C_TradeSkillUI.GetRecipeCooldown, info.recipeID)
    if okCd and cooldown and cooldown > 0 then
        lines[#lines + 1] = "|cffff4d4dCooldown: " .. SecondsToTime(cooldown) .. "|r"
    end
    d.desc:SetText(table.concat(lines, "\n"))

    d.reagentsLabel:ClearAllPoints()
    d.reagentsLabel:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -14)
    local reagents = Reagents(info.recipeID)
    for i, r in ipairs(d.reagents) do
        local data = reagents[i]
        if data then
            local name = C_Item.GetItemNameByID(data.itemID)
            if not name then C_Item.RequestLoadItemDataByID(data.itemID) end
            local have = ItemCount(data.itemID)
            r.itemID = data.itemID
            r.icon:SetTexture(C_Item.GetItemIconByID(data.itemID))
            r.count:SetText(("%d/%d"):format(have, data.need))
            SetColor(r.count, have >= data.need and T.fg or RED)
            r.name:SetText(name or "")
            r:Show()
        else
            r:Hide()
        end
    end

    ns.SetButtonText(win.createAll, ("Create All (%d)"):format(Craftable(info)))
end

Render = function()
    local prof = Profession()
    if not prof then return end
    win.title:SetText(prof.name)
    win.rank:SetMinMaxValues(0, math.max(prof.max, 1))
    win.rank:SetValue(prof.skill)
    win.rankText:SetText(("%s %d/%d"):format(prof.name, prof.skill, prof.max))


    Collect()
    BuildEntries()
    RenderList()
    RenderDetail()
end

-------------------------------------------------------------------------------
--  Tabs
-------------------------------------------------------------------------------
-- Blizzard's profession tabs (the overview book, then every profession with a crafting
-- window, Fishing included) switch profession by casting its spell, which only Blizzard's
-- code may do. So the real tabs move onto this window's edge instead of being rebuilt: the
-- chain hangs off the overview tab, and they ignore their invisible parent's alpha.
local savedTabPoints

local function BlizzardTabs()
    local pf = ProfessionsFrame
    local head = pf.ProfessionsOverviewTab
    if not head then return end
    local all = { head }
    for _, tab in ipairs(pf.rightProfessionTabs or {}) do all[#all + 1] = tab end
    return head, all
end

local function DockTabs(on)
    local head, all = BlizzardTabs()
    if not head then return end
    if on then
        if not savedTabPoints then
            savedTabPoints = {}
            for i = 1, head:GetNumPoints() do savedTabPoints[i] = { head:GetPoint(i) } end
        end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", win, "TOPRIGHT", 0, -60)
    elseif savedTabPoints then
        head:ClearAllPoints()
        for _, pt in ipairs(savedTabPoints) do head:SetPoint(unpack(pt)) end
        savedTabPoints = nil
    end
    for _, tab in ipairs(all) do
        if tab.SetIgnoreParentAlpha then tab:SetIgnoreParentAlpha(on) end
    end
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function CloseAll()
    HideUIPanel(ProfessionsFrame)
end

local function Build()
    win = CreateFrame("Frame", "NaowhForeverProfessions", UIParent)
    win:SetWidth(W)
    win:EnableMouse(true)
    win:Hide()
    ns.Solid(win, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(win)

    local logo = win:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga")
    logo:SetSize(20, 20)
    logo:SetPoint("TOPLEFT", 10, -8)
    win.title = ns.Font(win, 15, "OUTLINE", T.accent)
    win.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    local close = ns.Button(win, "X", 22, 22, CloseAll)
    close:SetPoint("TOPRIGHT", -8, -7)

    -- Skill rank across the recipe and detail columns.
    local rank = CreateFrame("StatusBar", nil, win)
    rank:SetPoint("TOPLEFT", PAD + 2, -40)
    rank:SetSize(W - PAD * 2 - 4, 18)
    rank:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rank:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    ns.Solid(rank, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(rank)
    win.rank = rank
    win.rankText = ns.Font(rank, 12, "OUTLINE")
    win.rankText:SetPoint("CENTER")

    -- Left column: search and the recipe list.
    local search = ns.NewEditBox(win)
    win.search = search
    search:SetPoint("TOPLEFT", PAD, TOP_Y)
    search:SetSize(LEFT_W, 22)
    search.hint = ns.Font(search, 12, nil, T.muted)
    search.hint:SetPoint("LEFT", 6, 0)
    search.hint:SetText(SEARCH or "Search")
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        query = text:lower()
        offset = 0
        BuildEntries()
        RenderList()
        RenderDetail()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)

    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    list:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, PAD)
    list:SetWidth(LEFT_W)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.min(math.max(0, #entries - VisibleRows()), math.max(0, offset - delta * 2))
        RenderList()
    end)
    ns.Solid(list, "BACKGROUND", T.panel, 0.6):SetAllPoints()
    win.list = list

    function win.BuildRow(i)
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LEFT_W - 4, ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        row.head = ns.Solid(row, "BACKGROUND", T.line, 0.6)
        row.head:SetAllPoints()
        row.sel = ns.Solid(row, "BACKGROUND", T.accent, 0.25)
        row.sel:SetAllPoints()
        row.hl = ns.Solid(row, "HIGHLIGHT", T.fg, 0.06)
        row.hl:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 4, ROW_H - 4)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.count = ns.Font(row, 12, nil)
        row.count:SetPoint("RIGHT", -6, 0)
        row.text = ns.Font(row, 12, nil)
        row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if e.cat then
                ToggleCollapsed(e.cat)
                BuildEntries()
                RenderList()
            elseif e.unlearned then
                selectedUnlearned = e.unlearned
                RenderList()
                RenderDetail()
            elseif IsModifiedClick("CHATLINK") then
                local link = C_TradeSkillUI.GetRecipeLink(e.recipe.recipeID)
                if link then ChatEdit_InsertLink(link) end
            else
                selectedID, selectedUnlearned = e.recipe.recipeID, nil
                RenderList()
                RenderDetail()
            end
        end)
        row:SetScript("OnEnter", function(self)
            local r = self.entry.unlearned
            if r then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(r.spell)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(("Required skill: %d  (%s)"):format(ns.RecipeFinder.Skill(r),
                    ns.RecipeFinder.Tag(r)), 1, 1, 1)
                GameTooltip:Show()
                return
            end
            if not self.entry.recipe then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, self.entry.recipe.recipeID) then
                GameTooltip:SetSpellByID(self.entry.recipe.recipeID)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnMouseWheel", function(_, delta) list:GetScript("OnMouseWheel")(list, delta) end)
        return row
    end

    -- Middle column: the chosen recipe.
    local mid = CreateFrame("Frame", nil, win)
    win.mid = mid
    mid:SetPoint("TOPLEFT", MID_X, TOP_Y)
    mid:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", MID_X, PAD)
    mid:SetWidth(MID_W)
    ns.Solid(mid, "BACKGROUND", T.panel, 0.6):SetAllPoints()

    win.empty = ns.Font(mid, 13, nil, T.muted)
    win.empty:SetPoint("CENTER")
    win.empty:SetText("No recipes match.")

    local d = CreateFrame("Frame", nil, mid)
    d:SetAllPoints()
    win.detail = d
    local iconBtn = CreateFrame("Button", nil, d)
    iconBtn:SetSize(44, 44)
    iconBtn:SetPoint("TOPLEFT", 14, -14)
    d.icon = iconBtn:CreateTexture(nil, "ARTWORK")
    d.icon:SetAllPoints()
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    iconBtn:SetScript("OnEnter", function(self)
        local info = SelectedInfo()
        if not info then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, info.recipeID) then
            GameTooltip:SetSpellByID(info.recipeID)
        end
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", GameTooltip_Hide)
    d.name = ns.Font(d, 16, nil)
    d.name:SetPoint("LEFT", iconBtn, "RIGHT", 10, 0)
    d.name:SetPoint("RIGHT", -12, 0)
    d.name:SetJustifyH("LEFT")

    d.desc = ns.Font(d, 12, nil)
    d.desc:SetPoint("TOPLEFT", iconBtn, "BOTTOMLEFT", 0, -12)
    d.desc:SetWidth(MID_W - 28)
    d.desc:SetJustifyH("LEFT")
    d.desc:SetSpacing(2)

    d.reagentsLabel = ns.Font(d, 12, nil, GOLD)
    d.reagentsLabel:SetText("Reagents:")
    d.reagents = {}
    for i = 1, MAX_REAGENTS do
        local r = CreateFrame("Button", nil, d)
        r:SetSize((MID_W - 28) / 2, REAGENT_H - 4)
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        r:SetPoint("TOPLEFT", d.reagentsLabel, "BOTTOMLEFT", col * (MID_W - 28) / 2, -6 - line * REAGENT_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(REAGENT_H - 6, REAGENT_H - 6)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.count = ns.Font(r, 12, nil)
        r.count:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -2)
        r.name = ns.Font(r, 12, nil)
        r.name:SetPoint("TOPLEFT", r.count, "BOTTOMLEFT", 0, -1)
        r.name:SetPoint("RIGHT", -2, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            if IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(self.itemID)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        d.reagents[i] = r
    end

    -- Craft controls along the bottom of the middle column.
    local create = ns.Button(d, "Create", 90, 24, function()
        Craft(tonumber(win.qty:GetText()) or 1)
    end)
    create:SetPoint("BOTTOMRIGHT", -10, 10)
    local qty = ns.NewEditBox(d)
    qty:SetSize(40, 24)
    qty:SetNumeric(true)
    qty:SetMaxLetters(3)
    qty:SetJustifyH("CENTER")
    qty:SetText("1")
    qty:SetScript("OnEscapePressed", qty.ClearFocus)
    qty:SetScript("OnEnterPressed", qty.ClearFocus)
    win.qty = qty
    local plus = ns.Button(d, "+", 22, 24, function()
        qty:SetText(tostring(math.min(999, (tonumber(qty:GetText()) or 1) + 1)))
    end)
    plus:SetPoint("RIGHT", create, "LEFT", -12, 0)
    qty:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = ns.Button(d, "-", 22, 24, function()
        qty:SetText(tostring(math.max(1, (tonumber(qty:GetText()) or 1) - 1)))
    end)
    minus:SetPoint("RIGHT", qty, "LEFT", -2, 0)
    win.createAll = ns.Button(d, "Create All", 120, 24, function()
        local info = SelectedInfo()
        if info then Craft(Craftable(info)) end
    end)
    win.createAll:SetPoint("BOTTOMLEFT", 10, 10)

    -- The middle column for an unlearned recipe: where to learn it.
    local l = CreateFrame("Frame", nil, mid)
    l:SetAllPoints()
    l:Hide()
    win.learn = l
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(44, 44)
    l.icon:SetPoint("TOPLEFT", 14, -14)
    l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    l.name = ns.Font(l, 16, nil)
    l.name:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 10, -2)
    l.name:SetPoint("RIGHT", -12, 0)
    l.name:SetJustifyH("LEFT")
    l.req = ns.Font(l, 12, nil)
    l.req:SetPoint("BOTTOMLEFT", l.icon, "BOTTOMRIGHT", 10, 2)
    l.paras = {}
    for i = 1, MAX_PARAS do
        local fs = ns.Font(l, 12, nil)
        fs:SetWidth(MID_W - 28)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetSpacing(2)
        l.paras[i] = fs
    end
    l.lines = {}
    for i = 1, MAX_LINES do
        local line = CreateFrame("Button", nil, l)
        line:SetSize(MID_W - 36, 16)
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
        l.lines[i] = line
    end
    local hint = ns.Font(l, 11, nil, T.muted)
    hint:SetPoint("BOTTOMLEFT", 14, 14)
    hint:SetText("Click a trainer or vendor to set a waypoint.")

    -- The overview: two primary profession cards, then Cooking, Fishing and First Aid.
    local book = CreateFrame("Frame", nil, win)
    book:SetPoint("TOPLEFT", PAD, -40)
    book:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    book:Hide()
    win.book = book
    local innerW = W - PAD * 2
    local cardW = (innerW - CARD_GAP * 2) / 3
    book.cards = {}
    for i = 1, #BOOK_ORDER do
        local primary = i <= 2
        local card = CreateFrame("Frame", nil, book)
        ns.Solid(card, "BACKGROUND", T.panel, 0.6):SetAllPoints()
        ns.Border(card)
        card.primary = primary
        if primary then
            card:SetPoint("TOPLEFT", 0, -(i - 1) * (PRIMARY_H + CARD_GAP))
            card:SetSize(innerW, PRIMARY_H)
        else
            local x = (i - 3) * (cardW + CARD_GAP)
            card:SetPoint("TOPLEFT", x, -2 * (PRIMARY_H + CARD_GAP))
            card:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", x, 0)
            card:SetWidth(cardW)
        end
        card.name = ns.Font(card, 14, nil, GOLD)
        local bar = CreateFrame("StatusBar", nil, card)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
        ns.Solid(bar, "BACKGROUND", T.bg, 1):SetAllPoints()
        ns.Border(bar)
        if primary then
            card.name:SetPoint("TOPLEFT", 12, -10)
            bar:SetPoint("TOPLEFT", 250, -52)
            bar:SetSize(innerW - 250 - 44, 18)
        else
            card.name:SetPoint("TOP", 0, -12)
            bar:SetPoint("TOP", 0, -38)
            bar:SetSize(cardW - 24, 18)
        end
        card.bar = bar
        card.barText = ns.Font(bar, 12, "OUTLINE")
        card.barText:SetPoint("CENTER")
        card.missing = ns.Font(card, 12, nil, T.muted)
        card.missing:SetPoint("CENTER", 0, primary and -8 or 0)
        card.missing:SetWidth((primary and innerW or cardW) - 40)
        card.missing:SetWordWrap(true)
        book.cards[i] = card
    end
end

-------------------------------------------------------------------------------
--  The overview
-------------------------------------------------------------------------------
-- Forever's GetProfessions answers prof1, prof2, First Aid, Fishing, Cooking; the cards run
-- Cooking, Fishing, First Aid, as Blizzard's book does.
local function BookIndices()
    local prof1, prof2, firstAid, fishing, cooking = GetProfessions()
    return { prof1, prof2, cooking, fishing, firstAid }
end

local function RenderBook()
    win.title:SetText(TRADE_SKILLS or "Professions")
    local indices = BookIndices()
    for i, card in ipairs(win.book.cards) do
        local index = indices[i]
        if index then
            local name, _, rank, maxRank, _, _, _, modifier = GetProfessionInfo(index)
            card.name:SetText(name)
            card.bar:SetMinMaxValues(0, math.max(maxRank or 0, 1))
            card.bar:SetValue(rank or 0)
            card.barText:SetText(("%d/%d%s"):format(rank or 0, maxRank or 0,
                (modifier or 0) > 0 and (" (+%d)"):format(modifier) or ""))
            card.bar:Show()
            card.missing:Hide()
        else
            card.name:SetText(card.primary and (PROFESSIONS_FIRST_PROFESSION or "Primary Profession")
                or SECONDARY_NAMES[i - 2])
            card.missing:SetText(card.primary and (PROFESSIONS_MISSING_PROFESSION or
                "Visit a profession trainer to learn one.") or "Not learned yet.")
            card.bar:Hide()
            card.missing:Show()
        end
    end
end

-- The spell buttons (Smelting, Find Minerals, Bait and Tackle...) cast their spell and the red
-- cross unlearns, so they stay Blizzard's own. Blizzard's whole card moves into ours: a card
-- draws its buttons as part of itself, so a button moved alone stays as invisible as the card
-- it belongs to. The card's own art, name and bar go transparent, our card shows instead, and
-- Blizzard's code keeps laying the buttons out inside it. The buttons stay children of that
-- card, which is where their click reads the spellbook offset from, so casting is untouched.
-- They are secure, so this happens out of combat only, and is undone whenever the overview
-- is not showing, so nothing secure hangs off this window in any other state.
local docked = {}
local bookDocked, bookPending = false, nil
local CARD_ART = { "Background", "ProfessionName", "specialization", "missingHeader", "missingText", "StatusBar" }

local function Place(frame, place, level)
    frame:ClearAllPoints()
    place(frame)
    frame:SetFrameStrata(win:GetFrameStrata())
    frame:SetFrameLevel(level)
end

-- parent, when given, adopts the frame and hides its card art.
local function Dock(frame, place, level, parent)
    local saved = docked[frame]
    if not saved then
        local points = {}
        for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
        saved = { points = points, parent = frame:GetParent(), strata = frame:GetFrameStrata(),
            level = frame:GetFrameLevel(), art = {} }
        docked[frame] = saved
        if parent then
            frame:SetParent(parent)
            for _, key in ipairs(CARD_ART) do
                local region = frame[key]
                if type(region) == "table" and region.SetAlpha then
                    local art = { region = region, alpha = region:GetAlpha() }
                    if region.IsMouseEnabled then
                        art.mouse = region:IsMouseEnabled()
                        region:EnableMouse(false)
                    end
                    region:SetAlpha(0)
                    saved.art[#saved.art + 1] = art
                end
            end
        end
    end
    saved.place, saved.onLevel = place, level
    Place(frame, place, level)
end

local function Redock()
    if not bookDocked or InCombatLockdown() then return end
    for frame, saved in pairs(docked) do Place(frame, saved.place, saved.onLevel) end
end

local function Undock()
    for frame, saved in pairs(docked) do
        frame:SetParent(saved.parent)
        frame:ClearAllPoints()
        for _, pt in ipairs(saved.points) do frame:SetPoint(unpack(pt)) end
        frame:SetFrameStrata(saved.strata)
        frame:SetFrameLevel(saved.level)
        for _, art in ipairs(saved.art) do
            art.region:SetAlpha(art.alpha)
            if art.mouse ~= nil then art.region:EnableMouse(art.mouse) end
        end
    end
    wipe(docked)
end

local function DockBook(on)
    if on == bookDocked then
        bookPending = nil
        return
    end
    if InCombatLockdown() then
        bookPending = on
        return
    end
    bookPending, bookDocked = nil, on
    if not on then return Undock() end
    local content = ProfessionsFrame.BookPage and ProfessionsFrame.BookPage.ProfessionsContentFrame
    if not content then return end
    for i, key in ipairs(BOOK_ORDER) do
        local blizz, card = content[key], win.book.cards[i]
        if blizz then
            Dock(blizz, function(f) f:SetAllPoints(card) end, card:GetFrameLevel() + 3, card)
            if type(blizz.UnlearnButton) == "table" then
                Dock(blizz.UnlearnButton, function(f) f:SetPoint("LEFT", card.bar, "RIGHT", 6, 0) end,
                    card:GetFrameLevel() + 10)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Taking over from Blizzard's window
-------------------------------------------------------------------------------
local function Deactivate()
    if win then win:Hide() end
    if ProfessionsFrame then
        DockTabs(false)
        DockBook(false)
        ProfessionsFrame:SetAlpha(1)
    end
    if ns.ProfWindowActive then
        ns.ProfWindowActive = nil
        if ns.RecipeFinderRefresh then ns.RecipeFinderRefresh() end
    end
end

-- mode is "craft" (a profession's recipes) or "book" (the overview).
local function Activate(mode)
    local pf = ProfessionsFrame
    if not win then
        Build()
        win:SetFrameStrata(NextStrata(pf:GetFrameStrata()))
        win:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
    end
    pf:SetAlpha(0)
    -- Never narrower or shorter than Blizzard's window, so none of it is left clickable.
    -- Resizing waits for peace: the overview's secure buttons may hang off this window.
    if not InCombatLockdown() then
        win:SetSize(math.max(W, pf:GetWidth()), math.max(MIN_H, pf:GetHeight()))
    end
    if not win:IsShown() then
        selectedID, selectedUnlearned, offset = nil, nil, 0
        win:Show()
    end
    if not ns.ProfWindowActive then
        ns.ProfWindowActive = true
        if ns.RecipeFinderRefresh then ns.RecipeFinderRefresh() end
    end
    DockTabs(true)
    local book = mode == "book"
    win.search:SetShown(not book)
    win.list:SetShown(not book)
    win.mid:SetShown(not book)
    win.rank:SetShown(not book)
    win.book:SetShown(book)
    DockBook(book)
    if book then
        RenderBook()
        Redock()
    else
        Render()
    end
end

-- The overview tab shows Blizzard's book page (invisible, like the rest of its window); the
-- keybind can open it with no profession open at all.
local function BookOpen()
    local book = ProfessionsFrame.BookPage
    return book and book:IsShown()
end

local function Update()
    if not (On() and ProfessionsFrame and ProfessionsFrame:IsShown() and Own()) then return Deactivate() end
    if BookOpen() then return Activate("book") end
    if Profession() then return Activate("craft") end
    Deactivate()
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Update()
    end)
end
ns.ProfWindowRefresh = Queue

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "Blizzard_Professions" then return end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if bookPending ~= nil then DockBook(bookPending) end
    end
    if not hooked and ProfessionsFrame then
        hooked = true
        ProfessionsFrame:HookScript("OnShow", Queue)
        ProfessionsFrame:HookScript("OnHide", Deactivate)
        ProfessionsFrame:HookScript("OnSizeChanged", Queue)
        local book = ProfessionsFrame.BookPage
        if book then
            book:HookScript("OnShow", Queue)
            book:HookScript("OnHide", Queue)
            if book.Update then hooksecurefunc(book, "Update", Redock) end
            if book.FormatProfession then hooksecurefunc(book, "FormatProfession", Redock) end
        end
    end
    Queue()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then return Deactivate() end
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
        "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_NAME_UPDATE", "NEW_RECIPE_LEARNED",
        "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_Professions") then events:RegisterEvent("ADDON_LOADED") end
    events:GetScript("OnEvent")(events, "APPLY")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "profWindow" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  Settings page
-------------------------------------------------------------------------------
function ns.BuildProfessionsPage(parent, y)
    local W = UI.Widgets
    local STATUS = UI.STATUS
    local _, h
    _, h = W:Note(parent, UI.PREVIEW_NOTE, y); y = y - h

    _, h = W:SectionHeader(parent, "PROFESSION WINDOW" .. STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("profWindow", "Naowh Profession Window",
            "Replaces Blizzard's profession window with Naowh's: your recipes, reagents and "
            .. "crafting in one window, the overview of all your professions, and Blizzard's "
            .. "profession tabs on its edge. Off shows Blizzard's window."),
        S.Toggle("recipeFinder", "Unlearned Recipes",
            "Lists the recipes you have not learned yet below your own. Click one to see the "
            .. "skill it needs, what it costs and where it comes from: the nearest trainers, the "
            .. "vendor selling its manual, or the mobs that drop it. Click a trainer or vendor "
            .. "to set a waypoint. With the Naowh window off they show in a drawer beside "
            .. "Blizzard's. First Aid only for now.")
    ); y = y - h

    return y
end
