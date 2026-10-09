-------------------------------------------------------------------------------
--  NaowhForever_Macros.lua -- the Macros module: macros the addon
--  writes and keeps pointed at the best item or spell you have, rewritten out of combat
--  as bags and spells change.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local S = UI.ModuleSettings("macros", {
    enabled = true, classMacros = {},
    health = true, healthOrder = "potion",
    mana = true, food = true, bandage = true,
    trinket1 = true, trinket2 = true,
    focus = true, focusMark = true, focusMarker = 8, focusAnnounce = true,
    acceptPopup = true, windowAlpha = 1,
})
-- Authored definitions travel with shared packs; presentation settings stay in this module.
local GetSetting, SetSetting = S.Get, S.Set
function S.Get(key)
    if key == "classMacros" and ns.DB then
        local data = ns.DB().utilityReminders
        return data and data.classMacros or {}
    end
    return GetSetting(key)
end
function S.Set(key, value)
    if key == "classMacros" and ns.DB then
        local db = ns.DB()
        db.utilityReminders = db.utilityReminders or {}
        db.utilityReminders.classMacros = value
    else
        SetSetting(key, value)
    end
end

ns.MacroSettings = S

local HEALTH_ORDER_VALUES = { stone = "Healthstone First", potion = "Potion First" }
local HEALTH_ORDER_ORDER = { "stone", "potion" }

local MARKER_VALUES = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull" }
local MARKER_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
local ACCEPT_ICON = 136814  -- the ready check mark

local ICON = 134400     -- question mark, so #showtooltip shows the item
local SCRIPT_COMMANDS = { ["/run"] = true, ["/script"] = true, ["/dump"] = true }

-- Every slash command and emote the client knows, from its SLASH_ and EMOTE_CMD strings.
-- Commands from addons that are not loaded are missing, so an unknown command is a warning.
local knownCommands
local ownCommands, addonCommands = {}, {}
local function KnownCommands()
    if knownCommands then return knownCommands end
    knownCommands = {}
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string"
            and (key:find("^SLASH_") or key:find("^EMOTE%d+_CMD%d+$")) and value:sub(1, 1) == "/" then
            local command = value:lower()
            knownCommands[command] = true
            if key:find("^SLASH_NAOWH") then
                ownCommands[command] = true
            elseif key:find("^SLASH_") and issecurevariable and not issecurevariable(key) then
                addonCommands[command] = true
            end
        end
    end
    return knownCommands
end
ns.MacroKnownCommands = KnownCommands

function ns.MacroCommandKind(command)
    command = command:lower()
    if SCRIPT_COMMANDS[command] then return "script" end
    local known = KnownCommands()
    if ownCommands[command] then return "own" end
    if addonCommands[command] then return "addon" end
    if not known[command] and not command:find("^/%d+$") then return "unknown" end
end

-- Problems a player would hit when the macro runs: unknown commands, lines that are not
-- commands, and unbalanced brackets. Script lines are Lua, so only their command is checked.
function ns.MacroProblems(body)
    local problems, n = {}, 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local text = strtrim(line)
        if text ~= "" and text:sub(1, 1) ~= "#" then
            local command = text:match("^(/%S+)")
            if not command then
                problems[#problems + 1] = ("Line %d does not start with / or #."):format(n)
            else
                command = command:lower()
                if not (command:find("^/%d+$") or KnownCommands()[command]) then
                    problems[#problems + 1] = ("Line %d: %s is not a command the game knows."):format(n, command)
                end
                if not SCRIPT_COMMANDS[command] then
                    local _, open = text:gsub("%[", "")
                    local _, close = text:gsub("%]", "")
                    if open ~= close then
                        problems[#problems + 1] = ("Line %d has %d [ but %d ]."):format(n, open, close)
                    end
                end
            end
        end
    end
    return problems
end

local icons
local function MacroIcons()
    if not icons then
        local all = {}
        GetLooseMacroIcons(all)
        GetLooseMacroItemIcons(all)
        GetMacroIcons(all)
        GetMacroItemIcons(all)
        icons = {}
        for _, icon in ipairs(all) do
            local id = tonumber(icon)
            if id then icons[#icons + 1] = id end
        end
    end
    return icons
end
ns.MacroIconList = MacroIcons

-- Picked icons are the player's own, kept by macro name outside the profile so a pack
-- export never carries them and Profile Icon can always go back to the author's choice.
local function IconChoices()
    local account = ns.AccountSettings()
    account.macroIcons = account.macroIcons or {}
    return account.macroIcons
end

local function EntryIcon(entry)
    return IconChoices()[entry.name] or entry.icon
end

ns.MacroEntryIcon = EntryIcon

-------------------------------------------------------------------------------
--  Runtime
-------------------------------------------------------------------------------
-- Classic-era item IDs, best first.
local MANA_POTIONS = { 13444, 13443, 6149, 3827, 3385, 2455 }
local BANDAGES = { 14530, 14529, 8545, 8544, 6451, 6450, 3531, 3530, 2581, 1251 }

local MACROS = {
    { key = "health", name = "NF Health" },
    { key = "mana", name = "NF Mana" },
    { key = "food", name = "NF Food" },
    { key = "bandage", name = "NF Bandage" },
    { key = "trinket1", name = "NF Trinket 1" },
    { key = "trinket2", name = "NF Trinket 2" },
    { key = "focus", name = "NF Focus" },
    { key = "acceptPopup", name = "NF Accept", icon = ACCEPT_ICON },
}

local ready, pending
local warnedFull = {}
local toDelete = {}
local events = CreateFrame("Frame")
local BAG_MACROS = { health = true, mana = true, food = true, bandage = true }

local function FirstCarried(list)
    for _, id in ipairs(list) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

local function UseLines(first, second)
    if first and second then return "#showtooltip\n" .. first .. "\n" .. second end
    local line = first or second
    if line then return "#showtooltip\n" .. line end
end

local function ItemLine(id, prefix)
    return id and ("/use " .. (prefix or "") .. "item:" .. id)
end

-- The macro body for each key, or nil to leave an existing macro as it is (nothing carried).
local BODIES = {
    health = function()
        local Items = ns.Shared.Items
        local stone, potion = FirstCarried(Items.HEALTHSTONES), FirstCarried(Items.HEALING_POTIONS)
        if S.Get("healthOrder") == "potion" then return UseLines(ItemLine(potion or stone)) end
        return UseLines(ItemLine(stone or potion))
    end,
    mana = function() return UseLines(ItemLine(FirstCarried(MANA_POTIONS))) end,
    food = function()
        local food, drink = ns.BestFoodAndDrink()
        return UseLines(ItemLine(food), ItemLine(drink))
    end,
    bandage = function() return UseLines(ItemLine(FirstCarried(BANDAGES), "[@player] ")) end,
    trinket1 = function() return "#showtooltip 13\n/use 13" end,
    trinket2 = function() return "#showtooltip 14\n/use 14" end,
    acceptPopup = function() return "/click StaticPopup1Button1" end,
    focus = function()
        local body = "/focus [@mouseover,exists,nodead][]"
        if S.Get("focusMark") then body = body .. "\n/tm [@focus] " .. S.Get("focusMarker") end
        -- Chat commands take no conditionals, so the channel is chosen here and the macro
        -- is rewritten on roster changes.
        local channel = (IsInRaid() and "/ra") or (IsInGroup() and "/p")
        if S.Get("focusAnnounce") and channel then
            body = body .. "\n" .. channel .. " Focus: %f"
        end
        return body
    end,
}

-- For Naowh's Forge: the Smart Macros and the text each would be written with now.
ns.MacroSmart = { list = MACROS, Body = function(key) return BODIES[key]() end }

local function Write(m, body, perCharacter)
    local index = GetMacroIndexByName(m.name)
    if index > 0 then
        if GetMacroBody(index) ~= body then EditMacro(index, m.name, ICON, body) end
        return
    end
    local accountCount, characterCount = GetNumMacros()
    local full
    if perCharacter then
        full = characterCount >= Constants.MacroConsts.MAX_CHARACTER_MACROS
    else
        full = accountCount >= Constants.MacroConsts.MAX_ACCOUNT_MACROS
    end
    if full then
        local scope = perCharacter and "character" or "general"
        if not warnedFull[scope] then
            warnedFull[scope] = true
            ns.Print((perCharacter and "Character" or "General") .. " macros are full, so " .. m.name
                .. " could not be made. Delete one and it will be added.")
        end
        return
    end
    CreateMacro(m.name, m.icon or ICON, body, perCharacter or false)
end

local function SyncEvents()
    local on, any, bags = S.Get("enabled"), false, false
    if on then
        for _, m in ipairs(MACROS) do
            if S.Get(m.key) then
                any = true
                if BAG_MACROS[m.key] then bags = true end
            end
        end
    end
    if bags then events:RegisterEvent("BAG_UPDATE_DELAYED") else events:UnregisterEvent("BAG_UPDATE_DELAYED") end
    if any then events:RegisterEvent("UPDATE_MACROS") else events:UnregisterEvent("UPDATE_MACROS") end
    if on and S.Get("focus") and S.Get("focusAnnounce") then
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
    else
        events:UnregisterEvent("GROUP_ROSTER_UPDATE")
    end
end

local function Update()
    if not ready then return end
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = false
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local on = S.Get("enabled")
    for _, m in ipairs(MACROS) do
        if on and S.Get(m.key) then
            toDelete[m.name] = nil
            local body = BODIES[m.key]()
            if body then Write(m, body) end
        elseif toDelete[m.name] then
            toDelete[m.name] = nil
            local index = GetMacroIndexByName(m.name)
            if index > 0 then DeleteMacro(index) end
        end
    end
end

function ns.PickupManagedMacro(key)
    if InCombatLockdown() then ns.Print("Move macros outside combat.") return end
    if not ready or not S.Get("enabled") then ns.Print("Enable Macros first.") return end
    S.Set(key, true)
    if UI.RefreshPage then UI:RefreshPage(true) end
    Update()
    for _, macro in ipairs(MACROS) do
        if macro.key == key then
            local index = GetMacroIndexByName(macro.name)
            if index > 0 then PickupMacro(index)
            else ns.Print("Carry a matching item and make room in General macros first.") end
            return
        end
    end
end

function ns.RemoveManagedMacro(key)
    if InCombatLockdown() then ns.Print("Remove macros outside combat.") return end
    if not S.Get(key) then return end
    S.Set(key, false)
    if UI.RefreshPage then UI:RefreshPage(true) end
end

function ns.PickupProfileMacro(entry)
    if InCombatLockdown() or not ready or not S.Get("enabled") then return end
    if type(entry.name) ~= "string" or #entry.name < 1 or #entry.name > 16
        or type(entry.body) ~= "string" or #entry.body < 1 or #entry.body > 255 then
        ns.Print("A profile macro needs a name (1-16 characters) and body (1-255 characters).")
        return
    end
    local index = GetMacroIndexByName(entry.name)
    if index > 0 and GetMacroBody(index) ~= entry.body then
        ns.Print("A different macro already uses that name; rename it before adding the profile macro.")
        return
    end
    local function Place()
        if InCombatLockdown() then return end
        Write({ name = entry.name, icon = EntryIcon(entry) }, entry.body, true)
        local placed = GetMacroIndexByName(entry.name)
        if placed > 0 then PickupMacro(placed) end
        local problems = ns.MacroProblems(entry.body)
        if #problems > 0 then
            ns.Print(entry.name .. " may not work: " .. table.concat(problems, " "))
        end
    end
    -- Profile macros come from shared packs, so script lines need the player's say-so.
    if index == 0 then
        for line in entry.body:gmatch("[^\n]+") do
            local command = line:match("^%s*(/%a+)")
            if command and SCRIPT_COMMANDS[command:lower()] then
                ns.Confirm(entry.name .. " runs a script from a shared profile. Hover its icon to "
                    .. "read it first. Create it?", Place)
                return
            end
        end
    end
    Place()
end

-- Only switching a macro or the module off deletes it. A profile or spec switch that turns
-- one off leaves it alone, since deleting a macro also empties its action bar slot.
local function SettingChanged(key, value)
    if value == false then
        for _, m in ipairs(MACROS) do
            if key == "enabled" or key == m.key then toDelete[m.name] = true end
        end
    end
    SyncEvents()
    Update()
end

local function Reapply()
    SyncEvents()
    Update()
end

-- Nothing is written before the first PLAYER_ENTERING_WORLD, when the character's macros
-- are loaded; GetMacroIndexByName misses them earlier and every macro would be made twice.
-- UPDATE_MACROS fires when a macro is deleted, so a macro that did not fit is made once there
-- is room.
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ready = true
        SyncEvents()
    elseif event == "PLAYER_REGEN_ENABLED" and not pending then
        return
    elseif event == "GROUP_ROSTER_UPDATE" and not (S.Get("focus") and S.Get("focusAnnounce")) then
        return
    end
    Update()
end)
events:RegisterEvent("PLAYER_ENTERING_WORLD")

hooksecurefunc(S, "Set", SettingChanged)
hooksecurefunc(ns, "Apply", Reapply)

local function On() return S.Get("enabled") == true end

local function Headline()
    local n = 0
    for _, m in ipairs(MACROS) do
        if S.Get(m.key) then n = n + 1 end
    end
    return ("%d of %d macros kept current for you"):format(n, #MACROS)
end

local function Detail()
    if not On() then return "Turn on Macros to keep them current." end
    local name, class = UnitClass("player")
    local count = #((S.Get("classMacros") or {})[class] or {})
    if count == 0 then return ("Your profile has no class macros for your %s."):format(name) end
    return ("%d class macro%s from your profile for your %s."):format(count, count == 1 and "" or "s", name)
end

ns.MacroStatus = { Headline = Headline, Detail = Detail }

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local Group = Settings.Group
local MACROS_OFF = "Turn on Macros"
local function MarkOn() return On() and S.Get("focusMark") == true end

local function HealthSummary(store)
    return HEALTH_ORDER_VALUES[store.Get("healthOrder")] or ""
end

local function FocusSummary(store)
    local announce, mark = store.Get("focusAnnounce"), store.Get("focusMark")
    if announce and mark then return "Announces and marks your focus" end
    if announce then return "Announces your focus" end
    if mark then return "Marks your focus" end
    return "Just sets your focus"
end

local function KeptSummary(store)
    local n = 0
    for _, m in ipairs(MACROS) do
        if store.Get(m.key) then n = n + 1 end
    end
    return ("%d of %d kept current"):format(n, #MACROS)
end

local page = Settings.Page("Macros/Settings", S)

page:Window({
    text = "Open Naowh's Forge",
    open = function() ns.OpenMacroWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "kept", name = "Kept Current", order = 5,
    help = "The macros the addon writes and keeps up to date for you, out of combat. Switch one on here, "
        .. "or take it to your bars from Smart Macros in Naowh's Forge.",
    summary = KeptSummary,
    rows = {
        { key = "health", label = "NF Health", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best healthstone or healing potion." },
        { key = "mana", label = "NF Mana", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best mana potion." },
        { key = "food", label = "NF Food", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best food and drink, conjured first." },
        { key = "bandage", label = "NF Bandage", toggle = true, needs = On, why = MACROS_OFF,
          help = "Your best bandage, on yourself." },
        { key = "trinket1", label = "NF Trinket 1", toggle = true, needs = On, why = MACROS_OFF,
          help = "Uses your top trinket." },
        { key = "trinket2", label = "NF Trinket 2", toggle = true, needs = On, why = MACROS_OFF,
          help = "Uses your bottom trinket." },
        { key = "focus", label = "NF Focus", toggle = true, needs = On, why = MACROS_OFF,
          help = "Focuses your mouseover, or your target." },
        { key = "acceptPopup", label = "NF Accept", toggle = true, needs = On, why = MACROS_OFF,
          help = "Accepts the popup on screen: a summons, a resurrection, a group invite." },
    },
})

page:Card({
    id = "health", name = "Health Macro", order = 20,
    help = "NF Health uses the best healthstone or healing potion in your bags. Switch it on in Kept Current.",
    summary = HealthSummary,
    rows = {
        { key = "healthOrder", label = "Health Priority", choice = { HEALTH_ORDER_VALUES, HEALTH_ORDER_ORDER },
          needs = On, why = MACROS_OFF,
          help = "Which the macro uses first when you carry both: a healthstone or a healing potion." },
    },
})

page:Card({
    id = "focus", name = "Focus Macro", order = 30,
    help = "NF Focus focuses your mouseover, or your target. Switch it on in Kept Current.",
    summary = FocusSummary,
    rows = {
        Group("Announce"),
        { key = "focusAnnounce", label = "Announce Focus", toggle = true, needs = On, why = MACROS_OFF,
          help = "Tells your group what you focused." },
        Group("Marker"),
        { key = "focusMark", label = "Mark Focus", toggle = true, needs = On, why = MACROS_OFF,
          help = "Puts a raid marker on your focus. Pressing the macro again on the same focus clears the marker." },
        { key = "focusMarker", label = "Focus Marker", choice = { MARKER_VALUES, MARKER_ORDER }, needs = MarkOn,
          why = "Needs Mark Focus", help = "The raid marker Mark Focus puts on your focus." },
    },
})

page:Card({
    id = "window", name = "Window", order = 40,
    help = "Naowh's Forge, Macros' own window: your macros, the ones kept current, and Naowh's library.",
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the window is, in percent. Also on its title bar." },
    },
})
