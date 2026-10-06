-------------------------------------------------------------------------------
--  NaowhForever_BuffReminders.lua -- the AuraBuffs Buffs & Consumables reminders:
--  a row of icons for missing food, flask and elixir buffs, scrolls in your bags, and
--  class buffs missing in your group.
--
--  Out of combat only. The client withdraws aura access in combat and at boss pulls
--  before InCombatLockdown() turns true, so every read is gated on
--  C_Secrets.ShouldAurasBeSecret() and the icons keep what they last showed until it ends.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.AuraBuffSettings
local D = ns.BuffReminderData

local GAP = 4
local ELIXIR_ICON = 13454   -- Greater Arcane Elixir, for "no elixir at all"
local KEYS = {
    consumableEntries = true, enabled = true, food = true, elixirs = true, flasks = true, consumablesWhere = true,
    consumablesMinutes = true, onlyIfCarried = true, hideResting = true, scrolls = true,
    scrollsSkipActive = true, raidBuffs = true, raidBuffsOwn = true, iconSize = true,
}

local frame, unlocked
local cells = {}
local pending
local wakeGen = 0  -- invalidates an older "buff drops under the warning time" timer
local wakeAt

local function On()
    return S.Get("enabled") and (#(S.Get("consumableEntries") or {}) > 0 or S.Get("raidBuffs"))
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- The unit's helpful auras by spell ID; nil when the client hands them over secret.
local function Buffs(unit)
    local buffs = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        if Secret(aura.spellId) then return nil end
        buffs[aura.spellId] = aura
    end
    return buffs
end

local function Find(buffs, ids)
    for _, id in ipairs(ids) do
        if buffs[id] then return buffs[id] end
    end
end

local function FirstCarried(items)
    for _, id in ipairs(items) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

-- Seconds left on the aura, nil when it does not run out or cannot be read.
local function Left(aura)
    local expiry = aura.expirationTime
    if Secret(expiry) or not expiry or expiry == 0 then return nil end
    return expiry - GetTime()
end

local function ConsumablesHere()
    if S.Get("hideResting") and IsResting() then return false end
    local where = S.Get("consumablesWhere")
    if where == "always" then return true end
    local _, kind = IsInInstance()
    return kind == "raid" or (where == "instance" and kind == "party")
end

-- Nothing fires as a buff runs down, so the earliest one to cross the warning time is timed.
local function Wake(seconds)
    if not wakeAt or seconds < wakeAt then wakeAt = seconds end
end

-- Adds a reminder unless one of `auras` is up with more than the warning time left.
local function Consumable(list, buffs, auras, item, icon)
    local aura = Find(buffs, auras)
    local left = aura and Left(aura)
    local warn = S.Get("consumablesMinutes") * 60
    if aura and not (left and left <= warn) then
        if left then Wake(left - warn) end
        return
    end
    if not item and S.Get("onlyIfCarried") then return end
    list[#list + 1] = { icon = item and C_Item.GetItemIconByID(item) or icon, aura = aura }
end

local function Consumables(list, buffs)
    local groups = {}
    for _, entry in ipairs(S.Get("consumableEntries") or {}) do
        if type(entry) == "table" and type(entry.itemID) == "number" and type(entry.auras) == "table" then
            local group = groups[entry.category]
            if not group then group = { items = {}, auras = {} }; groups[entry.category] = group end
            group.items[#group.items + 1] = entry.itemID
            for _, id in ipairs(entry.auras) do group.auras[#group.auras + 1] = id end
        end
    end
    for _, category in ipairs({ "food", "flask", "scroll", "battle", "guardian" }) do
        local group = groups[category]
        if group then
            local before = #list
            Consumable(list, buffs, group.auras, FirstCarried(group.items),
                C_Item.GetItemIconByID(group.items[1]))
            if #list > before then list[#list].items = group.items end
        end
    end
end

local function Knows(spells)
    for _, id in ipairs(spells) do
        if C_SpellBook.IsSpellKnown(id) then return true end
    end
end

local function GroupUnits()
    local units = {}
    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, n - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Each class buff someone in the group could cast, with how many in range are missing it.
local function RaidBuffs(list, playerBuffs)
    local members, classes = {}, {}
    for _, unit in ipairs(GroupUnits()) do
        local _, class = UnitClass(unit)
        if class and not Secret(class) then
            classes[class] = true
            if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit) then
                local buffs = UnitIsUnit(unit, "player") and playerBuffs or Buffs(unit)
                if buffs then members[#members + 1] = { class = class, buffs = buffs } end
            end
        end
    end
    local own = S.Get("raidBuffsOwn")
    for _, family in ipairs(D.RAID) do
        local castable = Knows(family.spells)
        if castable or not (own or family.talent) and classes[family.class] then
            local missing = 0
            for _, member in ipairs(members) do
                if not (family.skip and family.skip[member.class])
                    and not Find(member.buffs, family.spells) then
                    missing = missing + 1
                end
            end
            if missing > 0 then
                list[#list + 1] = { icon = C_Spell.GetSpellTexture(family.spells[1]),
                    count = #members > 1 and missing }
            end
        end
    end
end

-- The reminders to show now, in order; nil while auras cannot be read.
local function Collect()
    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then return nil end
    local buffs = Buffs("player")
    if not buffs then return nil end
    local list = {}
    wakeAt = nil
    if ConsumablesHere() then Consumables(list, buffs) end
    if S.Get("raidBuffs") then RaidBuffs(list, buffs) end
    return list
end

local popup
-- The menu holds secure buttons, so it can only be hidden outside combat.
local function HideMenu()
    if popup and not InCombatLockdown() then popup:Hide() end
end
-- IsMouseOver on the frame: the old MouseIsOver global is gone from the game.
local function LeaveMenu()
    C_Timer.After(0.15, function()
        if popup and popup:IsShown() and not popup:IsMouseOver()
            and not (popup.owner and popup.owner:IsMouseOver()) then HideMenu() end
    end)
end
local function OpenMenu(cell)
    if unlocked or InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() or not cell.items then return end
    if not popup then
        popup = CreateFrame("Frame", nil, UIParent)
        popup:SetFrameStrata("DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup:SetScript("OnLeave", LeaveMenu)
        ns.Solid(popup, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
        ns.Border(popup)
        popup.buttons = {}
    end
    popup.owner = cell
    local count, seen = 0, {}
    for _, id in ipairs(cell.items) do
        if not seen[id] and C_Item.GetItemCount(id) > 0 then
            seen[id] = true
            count = count + 1
            local button = popup.buttons[count]
            if not button then
                button = CreateFrame("Button", nil, popup, "SecureActionButtonTemplate")
                button:SetSize(32, 32)
                button:RegisterForClicks("AnyUp", "AnyDown")
                button:SetAttribute("type1", "item")
                button.icon = button:CreateTexture(nil, "ARTWORK")
                button.icon:SetAllPoints()
                ns.Border(button, { r = 0, g = 0, b = 0 })
                button:SetScript("PostClick", HideMenu)
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide(); LeaveMenu() end)
                popup.buttons[count] = button
            end
            button.itemID = id
            button:SetAttribute("item1", "item:" .. id)
            button.icon:SetTexture(C_Item.GetItemIconByID(id))
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 4 + ((count - 1) % 8) * 36, -4 - math.floor((count - 1) / 8) * 36)
            button:Show()
        end
    end
    for i = count + 1, #popup.buttons do popup.buttons[i]:Hide() end
    popup:SetSize(math.max(1, math.min(count, 8)) * 36 + 4, math.max(1, math.ceil(count / 8)) * 36 + 4)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -2)
    popup:SetShown(count > 0)
end

local Look = {}

function Look.Cell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Border(cell, { r = 0, g = 0, b = 0 })
    cell.count = ns.Font(cell, 14, "OUTLINE")
    cell.count:SetPoint("BOTTOMRIGHT", -2, 2)
    return cell
end

function Look.Place(cell, parent, i, size, icon, count)
    cell:SetSize(size, size)
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", parent, "LEFT", (i - 1) * (size + GAP), 0)
    cell.icon:SetTexture(icon)
    cell.count:SetText(count or "")
end

function Look.Fit(parent, n, size)
    parent:SetSize(math.max(n, 1) * (size + GAP) - GAP, size)
end

local function Cell(i)
    local cell = cells[i]
    if cell then return cell end
    cell = Look.Cell(frame)
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", OpenMenu)
    cell:SetScript("OnLeave", LeaveMenu)
    cell:SetScript("OnHide", function() if popup and popup.owner == cell then HideMenu() end end)
    cell.timer = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.timer:SetAllPoints()
    cell.timer:SetDrawEdge(false)
    cell.timer:SetReverse(true)
    cells[i] = cell
    return cell
end

local function Show(list)
    local size = S.Get("iconSize")
    for i, entry in ipairs(list) do
        local cell = Cell(i)
        Look.Place(cell, frame, i, size, entry.icon, entry.count)
        cell.items = entry.items
        local aura = entry.aura
        if aura and Left(aura) and not Secret(aura.duration) then
            cell.timer:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            cell.timer:Show()
        else
            cell.timer:Hide()
        end
        cell:Show()
    end
    for i = #list + 1, #cells do cells[i]:Hide() end
    Look.Fit(frame, #list, size)
    if popup and popup:IsShown() then
        if popup.owner:IsShown() and popup.owner.items then OpenMenu(popup.owner) else HideMenu() end
    end
end

local PREVIEW = {
    { spell = D.WELL_FED[1] }, { item = D.FLASKS.items[1] }, { item = ELIXIR_ICON },
    { item = D.SCROLLS[4].items[4], count = 2 }, { spell = D.RAID[1].spells[1], count = 3 },
}

local function Refresh()
    pending = nil
    if not frame then return end
    if unlocked then
        local list = {}
        for i, p in ipairs(PREVIEW) do
            list[i] = { icon = p.item and C_Item.GetItemIconByID(p.item)
                or C_Spell.GetSpellTexture(p.spell), count = p.count }
        end
        Show(list)
        return
    end
    if not On() then
        Show({})
        return
    end
    local list = Collect()
    if not list then return end
    Show(list)
    wakeGen = wakeGen + 1
    if wakeAt then
        local gen = wakeGen
        C_Timer.After(wakeAt + 0.1, function()
            if gen == wakeGen then Refresh() end
        end)
    end
end

-- Group auras change in bursts, so a refresh waits a moment and covers the lot.
local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.3, Refresh)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    -- The unit arrives secret while auras are restricted; PLAYER_REGEN_ENABLED catches up.
    if event == "UNIT_AURA" and (Secret(unit)
        or not (unit == "player" or unit:find("^party%d") or unit:find("^raid%d"))) then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then HideMenu(); return end
    Queue()
end)

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverBuffReminders", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.mover = ns.UI.AttachMover(frame, "Buff Reminders", function(pos) S.Set("buffsPos", pos) end,
        "AuraBuffs/Settings", "AuraBuffs/Settings:buffs")
end

local function Place()
    local pos = S.Get("buffsPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end
end

local function Apply()
    HideMenu()
    events:UnregisterAllEvents()
    wakeGen = wakeGen + 1
    if not (On() or unlocked) then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Place()
    frame.mover:SetShown(unlocked == true)
    frame:Show()
    if On() then
        if S.Get("raidBuffs") then
            events:RegisterEvent("UNIT_AURA")
            events:RegisterEvent("GROUP_ROSTER_UPDATE")
        else
            events:RegisterUnitEvent("UNIT_AURA", "player")
        end
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_UPDATE_RESTING")
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
    Refresh()
end

hooksecurefunc(S, "Set", function(key)
    if KEYS[key] then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group
local T = ns.THEME

local OFF = "Turn on AuraBuffs"
local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 120, 10, 11, 16
local RAID_SAMPLE = #PREVIEW
local WHERE = { { always = "Everywhere", instance = "Dungeons & Raids", raid = "Raids Only" },
    { "always", "instance", "raid" } }
local STATES = {
    { key = "raid", label = "In a Raid", tip = "In a raid, where every Show In choice reminds you." },
    { key = "world", label = "Open World", tip = "Out in the world, where only Everywhere reminds you." },
    { key = "resting", label = "Resting", tip = "In a city or an inn, where Hide While Resting hides them.",
      needs = "hideResting" },
}

local function Enabled() return S.Get("enabled") and true or false end
local function RaidBuffsOn() return S.Get("enabled") and S.Get("raidBuffs") and true or false end

local function OpenList() ns.OpenAuraBuffsWindow("consumables") end

local function EditList()
    if ns.OpenFromOptions then ns.OpenFromOptions(OpenList) else OpenList() end
end

local function ConsumablesShown(state)
    if state == "resting" then return false end
    return state == "raid" or S.Get("consumablesWhere") == "always"
end

local function NewPreview(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.row = CreateFrame("Frame", nil, shot)
    shot.cells = {}
    for i = 1, #PREVIEW do shot.cells[i] = Look.Cell(shot.row) end
    shot.note = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return shot
end

local function Fit(shot)
    local row = shot.row
    local w, h = row:GetWidth(), row:GetHeight()
    local roomW = shot:GetWidth() - STAGE_MARGIN * 2
    local roomH = shot:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h > 0 and h * scale > roomH then scale = roomH / h end
    row:SetScale(scale)
    row:ClearAllPoints()
    row:SetPoint("CENTER", shot, "CENTER", 0, NOTE_Y / scale)
end

local function PaintPreview(shot, state)
    local size = S.Get("iconSize")
    local consumables, raid = ConsumablesShown(state), S.Get("raidBuffs")
    local n = 0
    for i, p in ipairs(PREVIEW) do
        local cell = shot.cells[i]
        local shown = (i == RAID_SAMPLE and raid) or (i < RAID_SAMPLE and consumables)
        if shown then
            n = n + 1
            Look.Place(cell, shot.row, n, size, p.item and C_Item.GetItemIconByID(p.item)
                or C_Spell.GetSpellTexture(p.spell), p.count)
        end
        cell:SetShown(shown and true or false)
    end
    Look.Fit(shot.row, n, size)
    Fit(shot)
    local note = ""
    if n == 0 then
        note = "Nothing to remind you of here."
    elseif consumables and #(S.Get("consumableEntries") or {}) == 0 then
        note = "Sample icons: add the consumables to watch in the AuraBuffs window."
    end
    shot.note:SetText(note)
end

local function Summary(store)
    local n = #(store.Get("consumableEntries") or {})
    local text = n == 1 and "1 consumable" or (n .. " consumables")
    if store.Get("raidBuffs") then text = text .. " and raid buffs" end
    return text
end

Settings.Page("AuraBuffs/Settings", S):Card({
    id = "buffs", name = "Buffs & Consumables", order = 10,
    help = "A row of icons for missing food, flask, elixir and scroll buffs, and for class buffs missing "
        .. "in your group. Out of combat only: the game keeps your buffs from addons in combat, so the "
        .. "icons keep what they showed. Hover one to pick a carried item to use. Move them with Move Elements.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Consumables"),
        { key = "consumablesWhere", label = "Show In", choice = WHERE, needs = Enabled, why = OFF },
        { key = "consumablesMinutes", label = "Warn With Minutes Left", slider = { 0, 10, 1 }, unit = " min",
          needs = Enabled, why = OFF, help = "A buff with less time than this left counts as missing." },
        { key = "onlyIfCarried", label = "Only If I Carry One", toggle = true, needs = Enabled, why = OFF,
          help = "Off: a reminder for each kind you watch, even with none in your bags." },
        { key = "hideResting", label = "Hide While Resting", toggle = true, needs = Enabled, why = OFF,
          help = "No consumable reminders in cities and inns." },
        { label = "Consumables to Watch", buttonText = "Edit List", needs = Enabled, why = OFF,
          button = EditList,
          help = "Opens the AuraBuffs window, where you add each item by its item ID and buff spell ID." },
        Group("Raid Buffs"),
        { key = "raidBuffs", label = "Raid Buff Reminders", toggle = true, needs = Enabled, why = OFF,
          help = "Missing class buffs in your group, out of combat, with how many are missing them. A camp "
              .. "buff standing in for one, the Incense Candle for Arcane Intellect for example, is not seen, "
              .. "so it still counts as missing." },
        { key = "raidBuffsOwn", label = "Only Buffs I Can Cast", toggle = true, needs = RaidBuffsOn,
          why = "Needs Raid Buff Reminders", help = "Off: every buff a class in your group can cast." },
        Group("Icons"),
        { key = "iconSize", label = "Icon Size", slider = { 20, 64, 1 }, needs = Enabled, why = OFF },
    },
})
