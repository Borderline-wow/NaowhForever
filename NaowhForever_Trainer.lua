-------------------------------------------------------------------------------
--  NaowhForever_Trainer.lua -- the QoL trainer popup: after a trainer visit (or
--  any new ability), a window lists what you learned, the new abilities glow on your bars
--  until you use them, and one button swaps each spell's highest rank on your bars for the
--  highest rank you know, leaving lower copies for downranking. Keyboard and controller bars are both covered.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local KEYBOARD_SLOTS = 180
local MAX_ROWS = 8
local ROW_H = 30
local GLOW_KEY = "NaowhNewAbility"

local learned = {}          -- spellIDs learned since the window last showed, in order
local listed = {}           -- the spellIDs the open window lists
local manual = false        -- the open window came from a manual check, which always scans ranks
local atTrainer, showQueued, showGen = false, false, 0
local popup
local glowing = {}

local function On()
    return S.Get("enabled") and S.Get("trainerPopup")
end

local function Account(key)
    local account = ns.AccountSettings()
    account[key] = account[key] or {}
    return account[key]
end

-- spellID -> true for abilities still waiting to be used; kept per character so a reload
-- does not drop the glow.
local function NewSpells()
    local all = Account("trainerNew")
    local key = UnitName("player") .. "-" .. GetRealmName()
    all[key] = all[key] or {}
    return all[key]
end

-- Spell names whose lower ranks stay on the bars, for deliberate downranking.
local function Kept()
    return Account("rankKeep")
end

local function RankOf(subtext)
    return tonumber(subtext and subtext:match("%d+")) or 0
end

-------------------------------------------------------------------------------
--  Ranks
-------------------------------------------------------------------------------
-- name -> { rank, spellID } for the highest rank of each active spell in the spellbook.
local function HighestRanks()
    local best = {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.isGuild then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER_BANK)
                if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
                    local rank = RankOf(item.subName)
                    local top = best[item.name]
                    if not top or rank > top.rank then
                        best[item.name] = { rank = rank, spellID = item.actionID }
                    end
                end
            end
        end
    end
    return best
end

local function CheckSlot(slot, best, found)
    local kind, id = GetActionInfo(slot)
    if kind ~= "spell" or not id then return end
    local name = C_Spell.GetSpellName(id)
    -- An uncached spell has no subtext yet; read as rank 0 it would pass for a downrank.
    local subtext = C_Spell.GetSpellSubtext(id)
    if not (name and best[name] and subtext and subtext ~= "") then return end
    found[#found + 1] = { slot = slot, name = name, id = id, rank = RankOf(subtext) }
end

-- Every bar slot, keyboard and controller, holding the highest rank of a spell on your bars
-- when you know a higher one. A lower rank beside it stays, for downranking: a healer's Rank 1
-- heal next to the main one. Kept spells are included, flagged, so the window can still list them.
local function Upgrades()
    local best, kept, found, onBars, out = HighestRanks(), Kept(), {}, {}, {}
    for slot = 1, KEYBOARD_SLOTS do CheckSlot(slot, best, found) end
    local slot = math.max(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex(), KEYBOARD_SLOTS + 1)
    while C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot) do
        CheckSlot(slot, best, found)
        slot = slot + 1
    end
    for _, f in ipairs(found) do onBars[f.name] = math.max(onBars[f.name] or 0, f.rank) end
    for _, f in ipairs(found) do
        local top = best[f.name]
        if top.spellID ~= f.id and top.rank > f.rank and f.rank == onBars[f.name] then
            out[#out + 1] = { slot = f.slot, name = f.name, spellID = top.spellID, kept = kept[f.name] }
        end
    end
    return out
end

-- The spell names in a list of upgrades, with a count where one sits on several slots.
local function Summary(ups)
    local counts, order = {}, {}
    for _, up in ipairs(ups) do
        if not counts[up.name] then order[#order + 1] = up.name end
        counts[up.name] = (counts[up.name] or 0) + 1
    end
    for i, name in ipairs(order) do
        if counts[name] > 1 then order[i] = ("%s (x%d)"):format(name, counts[name]) end
    end
    return table.concat(order, ", ")
end

-------------------------------------------------------------------------------
--  Glow until used
-------------------------------------------------------------------------------
-- Blizzard's, EUI's and the controller bars' buttons all inherit ActionBarButtonTemplate,
-- which registers them here. Blizzard's own new-ability highlight is avoided: its marks
-- table is read from secure code and a write from an addon taints it.
local function RefreshGlow()
    local new = NewSpells()
    local show = On() and S.Get("trainerGlow")
    local LCG = LibStub("LibCustomGlow-1.0")
    for _, btn in pairs(ActionBarButtonEventsFrame.frames) do
        local want = false
        if show and btn.action then
            local kind, id = GetActionInfo(btn.action)
            want = kind == "spell" and not (issecretvalue and issecretvalue(id)) and new[id] == true
        end
        if want and not glowing[btn] then
            LCG.PixelGlow_Start(btn, { T.accent.r, T.accent.g, T.accent.b, 1 }, 8, nil, nil, 2,
                0, 0, nil, GLOW_KEY)
            glowing[btn] = true
        elseif not want and glowing[btn] then
            LCG.PixelGlow_Stop(btn, GLOW_KEY)
            glowing[btn] = nil
        end
    end
end

-- Paging and slot events arrive before the buttons pick up their new action, so the
-- refresh waits a frame and several events in a row cost one pass.
local glowQueued = false
local function QueueGlow()
    if glowQueued then return end
    glowQueued = true
    C_Timer.After(0, function()
        glowQueued = false
        RefreshGlow()
    end)
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function Place()
    local pos = S.Get("trainerPos")
    popup:ClearAllPoints()
    if pos then
        popup:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        popup:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
end

local Render

local function ToggleKeep(name)
    local kept = Kept()
    kept[name] = not kept[name] or nil
    Render()
end

local function Swappable()
    local ups = {}
    for _, up in ipairs(Upgrades()) do
        if not up.kept then ups[#ups + 1] = up end
    end
    return ups
end

local function SwapRanks()
    if InCombatLockdown() then return end
    local ups = Swappable()
    ClearCursor()
    for _, up in ipairs(ups) do
        C_Spell.PickupSpell(up.spellID)
        PlaceAction(up.slot)
        ClearCursor()
    end
    if #ups > 0 then
        print(("|cff0091edNaowh|r: updated %d bar slot(s): %s"):format(#ups, Summary(ups)))
    end
    -- Done once every slot is swapped; anything left over keeps the window up.
    if #Swappable() == 0 then
        popup:Hide()
    else
        Render()
    end
end

local function BuildRow(i)
    local row = CreateFrame("Button", nil, popup)
    row:SetSize(300, ROW_H - 2)
    row:SetPoint("TOPLEFT", 12, -44 - (i - 1) * ROW_H)
    row:RegisterForClicks("RightButtonUp")
    row:RegisterForDrag("LeftButton")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = ns.Font(row, 13, nil)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.rank = ns.Font(row, 11, nil, T.muted)
    row.rank:SetPoint("LEFT", row.name, "RIGHT", 6, 0)

    row:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then C_Spell.PickupSpell(self.spellID) end
    end)
    row:SetScript("OnClick", function(self) ToggleKeep(self.spellName) end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag onto your bars to place it.", 1, 1, 1)
        GameTooltip:AddLine(Kept()[self.spellName]
            and "Right-click to let Update Bars swap it again."
            or "Right-click to leave it as it is on your bars when you update them.", 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function Build()
    popup = CreateFrame("Frame", "NaowhForeverTrainer", UIParent)
    popup:SetWidth(324)
    popup:SetFrameStrata("MEDIUM")
    popup:SetMovable(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        S.Set("trainerPos", { point = point, relPoint = relPoint, x = x, y = y })
    end)
    ns.Solid(popup, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(popup)

    local logo = popup:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga")
    logo:SetSize(22, 22)
    logo:SetPoint("TOPLEFT", 12, -10)

    popup.title = ns.Font(popup, 16, "OUTLINE", T.accent)
    popup.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)

    local close = ns.Button(popup, "X", 22, 22, function() popup:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)

    popup.rows = {}
    for i = 1, MAX_ROWS do popup.rows[i] = BuildRow(i) end

    popup.more = ns.Font(popup, 11, nil, T.muted)
    popup.ranks = ns.Font(popup, 12, nil)
    popup.ranks:SetWidth(300)
    popup.ranks:SetJustifyH("LEFT")
    popup.ranks:SetWordWrap(true)

    popup.swap = ns.Button(popup, "Update Bars", 140, 26, SwapRanks)
    popup.later = ns.Button(popup, "Later", 80, 26, function() popup:Hide() end)
    popup:Hide()
end

-- Lays the window out: what was learned, then any other spell your bars hold at a lower
-- rank, and the swap button while something is left to swap. Returns false when there is
-- nothing to show.
Render = function()
    local ups = (manual or S.Get("trainerRanks")) and Upgrades() or {}
    local rows, seen, swappable = {}, {}, {}
    for _, id in ipairs(listed) do
        rows[#rows + 1] = id
        seen[C_Spell.GetSpellName(id) or id] = true
    end
    for _, up in ipairs(ups) do
        if not seen[up.name] then
            rows[#rows + 1] = up.spellID
            seen[up.name] = true
        end
        if not up.kept then swappable[#swappable + 1] = up end
    end
    if #rows == 0 then
        if popup then popup:Hide() end
        return false
    end
    if not popup then Build() end

    popup.title:SetText(#listed > 0 and "New Abilities" or "Lower Ranks on Your Bars")
    local kept = Kept()
    local shown = math.min(#rows, MAX_ROWS)
    for i, row in ipairs(popup.rows) do
        local id = rows[i]
        if i <= shown then
            row.spellID, row.spellName = id, C_Spell.GetSpellName(id)
            row.icon:SetTexture(C_Spell.GetSpellTexture(id))
            row.name:SetText(row.spellName)
            local rank = C_Spell.GetSpellSubtext(id) or ""
            row.rank:SetText(kept[row.spellName] and (rank .. "  (kept)") or rank)
            row:Show()
        else
            row:Hide()
        end
    end

    local y = -44 - shown * ROW_H
    popup.more:ClearAllPoints()
    if #rows > MAX_ROWS then
        popup.more:SetPoint("TOPLEFT", 12, y - 2)
        popup.more:SetText(("+%d more"):format(#rows - MAX_ROWS))
        popup.more:Show()
        y = y - 20
    else
        popup.more:Hide()
    end

    popup.ranks:ClearAllPoints()
    popup.swap:ClearAllPoints()
    popup.later:ClearAllPoints()
    if #swappable > 0 then
        popup.ranks:SetPoint("TOPLEFT", 12, y - 8)
        popup.ranks:SetText(("%d bar slot(s) hold a lower rank: %s"):format(#swappable,
            Summary(swappable)))
        popup.ranks:Show()
        y = y - 14 - popup.ranks:GetStringHeight()
        popup.swap:SetPoint("TOPLEFT", 12, y)
        popup.swap:Show()
        popup.later:SetPoint("LEFT", popup.swap, "RIGHT", 8, 0)
        popup.later:Show()
        y = y - 26
    else
        popup.ranks:Hide()
        popup.swap:Hide()
        popup.later:Hide()
    end

    popup:SetHeight(-y + 14)
    Place()
    popup:Show()
    return true
end

-- The window never opens in combat: rank swaps cannot happen there. It waits for combat
-- to end instead.
local function Show()
    if not On() then return end
    if InCombatLockdown() then
        showQueued = true
        return
    end
    showQueued = false
    -- Reopening after combat keeps the list the window already had.
    if #learned > 0 then listed, learned, manual = learned, {}, false end
    Render()
end

-- /naowh ranks: check the bars now, as after a trainer visit.
function ns.TrainerRankCheck()
    if InCombatLockdown() then
        print("|cff0091edNaowh|r: leave combat, then check your bars again.")
        return
    end
    listed, manual = {}, true
    if not Render() then
        print("|cff0091edNaowh|r: every spell on your bars is at its highest rank.")
    end
end

function ns.TrainerForgetKept()
    ns.AccountSettings().rankKeep = {}
    if popup and popup:IsShown() then Render() end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local function Learned(spellID)
    if C_Spell.IsSpellPassive(spellID) then return end
    learned[#learned + 1] = spellID
    if S.Get("trainerGlow") then
        NewSpells()[spellID] = true
        QueueGlow()
    end
    -- Away from a trainer (a tome, a quest reward) the window follows a moment after the
    -- last new ability instead of waiting for TRAINER_CLOSED.
    if not atTrainer then
        showGen = showGen + 1
        local gen = showGen
        C_Timer.After(2, function()
            if gen == showGen and not atTrainer then Show() end
        end)
    end
end

local function Used(spellID)
    if issecretvalue and issecretvalue(spellID) then return end
    local new = NewSpells()
    if new[spellID] then
        new[spellID] = nil
        QueueGlow()
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        Learned(arg1)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        Used(arg3)
    elseif event == "TRAINER_SHOW" then
        atTrainer = true
    elseif event == "TRAINER_CLOSED" then
        atTrainer = false
        if #learned > 0 then Show() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if popup and popup:IsShown() then
            popup:Hide()
            showQueued = true
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if showQueued then Show() end
    else
        QueueGlow()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        learned, listed = {}, {}
        showQueued, atTrainer = false, false
        if popup then popup:Hide() end
        if next(glowing) then RefreshGlow() end
        return
    end
    events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    events:RegisterEvent("TRAINER_SHOW")
    events:RegisterEvent("TRAINER_CLOSED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if S.Get("trainerGlow") then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    QueueGlow()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^trainer") and key ~= "trainerPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
