-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Blessings.lua -- the QoL blessing assignments: each paladin picks a
--  blessing per class, shared with the group's other paladins running Naowh Forever, and a
--  bar of click-to-cast buttons, one per class in the group, counting who still needs yours.
--  Greater Blessings reach everyone of the target's class; one blessing per paladin each.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings

local PREFIX = "NaowhBless"
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local VALID_CLASS = {}
for _, c in ipairs(CLASSES) do VALID_CLASS[c] = true end

-- Each blessing's Greater ranks and its single-target spell, from Forever's spell data.
local BLESSINGS = {
    might     = { name = "Might", greater = { 25782, 25916 }, single = 19740 },
    wisdom    = { name = "Wisdom", greater = { 25894, 25918 }, single = 19742 },
    kings     = { name = "Kings", greater = { 25898 }, single = 20217 },
    salvation = { name = "Salvation", greater = { 25895 }, single = 1038 },
    light     = { name = "Light", greater = { 25890 }, single = 19977 },
}
local ORDER = { "might", "wisdom", "kings", "salvation", "light" }

local others = {}      -- short paladin name -> { class -> blessing }, from their broadcasts
local bar, buttons, dirty

local function IsPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end

local function On()
    return S.Get("enabled") and S.Get("blessings")
end

local function Short(name)
    return name and Ambiguate(name, "short")
end

local function Mine()
    local account = ns.AccountSettings()
    account.blessings = account.blessings or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    account.blessings[key] = account.blessings[key] or {}
    return account.blessings[key]
end

-- The spell a click should cast: the highest Greater rank known, else the single blessing.
local function SpellFor(key)
    local b = BLESSINGS[key]
    for i = #b.greater, 1, -1 do
        if IsPlayerSpell(b.greater[i]) then return b.greater[i] end
    end
    if IsPlayerSpell(b.single) then return b.single end
end

-- Every spell that counts as a blessing of this kind, for reading who already has it.
local SPELLS = {}
for key, b in pairs(BLESSINGS) do
    SPELLS[b.single] = key
    for _, id in ipairs(b.greater) do SPELLS[id] = key end
end

local function GroupUnits()
    local units = { "player" }
    if IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Out of combat only: other units' auras are not readable in a fight.
local function HasMyBlessing(unit, key)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL|PLAYER")
        if not aura then return false end
        if SPELLS[aura.spellId] == key then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  Sharing assignments
-------------------------------------------------------------------------------
local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Send(msg)
    local channel = Channel()
    if channel and not InCombatLockdown() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
    end
end

local function Broadcast()
    if not IsPaladin() then return end
    local parts = {}
    for class, key in pairs(Mine()) do parts[#parts + 1] = class .. "=" .. key end
    Send("F|" .. table.concat(parts, ","))
end

local function InGroup(name)
    for _, unit in ipairs(GroupUnits()) do
        if Short(GetUnitName(unit, true)) == name then return unit end
    end
end

-- Parsed as data: only known classes and blessings from a paladin in the group are kept.
local function OnMessage(msg, sender)
    local who = Short(sender)
    if who == Short(GetUnitName("player", true)) then return end
    if msg == "R" then Broadcast() return end
    local body = msg:match("^F|(.*)$")
    local unit = body and InGroup(who)
    if not (unit and select(2, UnitClass(unit)) == "PALADIN") then return end
    local set = {}
    for class, key in body:gmatch("(%u+)=(%l+)") do
        if VALID_CLASS[class] and BLESSINGS[key] then set[class] = key end
    end
    others[who] = set
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

-------------------------------------------------------------------------------
--  The bar
-------------------------------------------------------------------------------
local function ClassesInGroup()
    local present, list = {}, {}
    for _, unit in ipairs(GroupUnits()) do
        local class = select(2, UnitClass(unit))
        if class and not present[class] then
            present[class] = true
            list[#list + 1] = class
        end
    end
    table.sort(list)
    return list
end

local function NewButton()
    local btn = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    btn:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
    btn:SetAttribute("type", "spell")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(btn, { r = 0, g = 0, b = 0 })
    btn.class = ns.Font(btn, 10, "OUTLINE")
    btn.class:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    btn.count = ns.Font(btn, 14, "OUTLINE", { r = 0.97, g = 0.44, b = 0.44 })
    btn.count:SetPoint("CENTER")
    return btn
end

-- Secure attributes can only change out of combat; a change asked for in one waits.
local function Refresh()
    if not bar then return end
    if InCombatLockdown() then
        dirty = true
        return
    end
    dirty = false
    local size = S.Get("blessBarSize")
    local mine, n = Mine(), 0
    for _, class in ipairs(ClassesInGroup()) do
        local key = mine[class]
        local spell = key and SpellFor(key)
        if spell then
            n = n + 1
            local btn = buttons[n] or NewButton()
            buttons[n] = btn
            local target, missing, anyone = nil, 0, nil
            for _, unit in ipairs(GroupUnits()) do
                if select(2, UnitClass(unit)) == class and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
                    anyone = anyone or unit
                    if not HasMyBlessing(unit, key) then
                        missing = missing + 1
                        target = target or unit
                    end
                end
            end
            btn:SetAttribute("spell", spell)
            btn:SetAttribute("unit", target or anyone)
            btn.icon:SetTexture(C_Spell.GetSpellTexture(spell))
            btn.icon:SetDesaturated(missing == 0)
            btn.count:SetText(missing > 0 and missing or "")
            local className = LOCALIZED_CLASS_NAMES_MALE[class] or class
            btn.class:SetText(className)
            btn:SetSize(size, size)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", (n - 1) * (size + 6), 0)
            btn:Show()
        end
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    bar:SetSize(math.max(n, 1) * (size + 6), size)
    bar:SetShown(n > 0 or bar.mover:IsShown())
end

local function BuildBar()
    bar = CreateFrame("Frame", "NaowhForeverBlessingBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    buttons = {}
    bar.mover = ns.UI.AttachMover(bar, "Blessings", function(pos) S.Set("blessPos", pos) end)
    local pos = S.Get("blessPos")
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
    end
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
local function Values()
    local values, order = { [""] = "None" }, { "" }
    for _, key in ipairs(ORDER) do
        values[key] = BLESSINGS[key].name
        order[#order + 1] = key
    end
    return values, order
end

function ns.BuildQoLBlessingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Pick the blessing you give each class. Other paladins in your group "
        .. "running Naowh Forever share theirs, so you can split the classes between you. Your "
        .. "bar then has a button per class in the group: click it to bless whoever of that "
        .. "class still needs it. The red number is how many do.", y); y = y - h

    _, h = W:SectionHeader(parent, "BLESSINGS" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("blessings", "Blessing Assignments", "The bar and sharing, for paladins."),
        S.Slider("blessBarSize", "Button Size", 20, 48, 1, nil, "blessings")
    ); y = y - h

    if IsPaladin() then
        _, h = W:SectionHeader(parent, "YOUR BLESSINGS", y); y = y - h
        local values, order = Values()
        local mine = Mine()
        for i = 1, #CLASSES, 2 do
            local function Row(class)
                if not class then return { type = "label", text = "" } end
                return { type = "dropdown", text = LOCALIZED_CLASS_NAMES_MALE[class] or class,
                    values = values, order = order,
                    getValue = function() return mine[class] or "" end,
                    setValue = function(v)
                        mine[class] = v ~= "" and v or nil
                        Broadcast()
                        Refresh()
                    end }
            end
            _, h = W:DualRow(parent, y, Row(CLASSES[i]), Row(CLASSES[i + 1])); y = y - h
        end
    end

    for who, set in pairs(others) do
        local parts = {}
        for _, class in ipairs(CLASSES) do
            if set[class] then
                parts[#parts + 1] = (LOCALIZED_CLASS_NAMES_MALE[class] or class) .. ": " .. BLESSINGS[set[class]].name
            end
        end
        _, h = W:SectionHeader(parent, who:upper(), y); y = y - h
        _, h = W:Note(parent, #parts > 0 and table.concat(parts, ",  ") or "Nothing assigned yet.", y); y = y - h
    end
    return y
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
-- Auras and the roster change constantly in a raid: one rescan per half second at most, and
-- one exchange of assignments per second.
local refreshQueued, syncQueued

local function RefreshSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.5, function()
        refreshQueued = false
        Refresh()
    end)
end

local function SyncSoon()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(1, function()
        syncQueued = false
        for who in pairs(others) do
            if not InGroup(who) then others[who] = nil end
        end
        Send("R")
        Broadcast()
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == PREFIX then OnMessage(msg, sender) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        SyncSoon()
        RefreshSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if dirty then Refresh() end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" or unit:find("^party%d") or unit:find("^raid%d") then RefreshSoon() end
    else
        RefreshSoon()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if bar and not InCombatLockdown() then bar:Hide() end
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if IsPaladin() then
        events:RegisterEvent("UNIT_AURA")
        events:RegisterEvent("SPELLS_CHANGED")
        if not bar then BuildBar() end
        Refresh()
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^bless") and key ~= "blessPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if bar and not InCombatLockdown() then
        bar.mover:Show()
        bar:Show()
    end
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if bar then
        bar.mover:Hide()
        Refresh()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
