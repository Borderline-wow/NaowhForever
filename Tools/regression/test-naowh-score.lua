-- Run with Lua 5.1 from the repository root: the Naowh Score. Its formula on sets of known
-- gear (a full epic set of a level scores that level; quality, slots, a two-hander, empty
-- slots, an item not loaded yet); player tooltips (off until turned on, one inspect at a time,
-- kept by GUID, filled in when the gear comes, never in combat or while the game's Inspect
-- window holds the inspect); your group scanned in the background; your score shared with
-- your group and guild, always, and theirs kept; and what the hot paths cost.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end
local Measure = dofile("Tools/regression/measure.lua")(check)
local NOTHING = function() end

-------------------------------------------------------------------------------
--  Stubs: gear by unit and slot as { level, quality, equip }, links "item:<unit>:<slot>"
-------------------------------------------------------------------------------
local function Fixture()
    local state = { gear = {}, now = 100, combat = false, inspected = {}, cleared = 0, postCalls = {},
        frames = {}, timers = {}, sent = {}, members = 0, guild = false,
        values = { enabled = true, naowhScore = false, naowhScoreTooltip = true, naowhScoreScan = true } }
    local listeners = {}
    local S = {
        Get = function(key) return state.values[key] end,
        Set = function(key, value)
            state.values[key] = value
            for i = 1, #listeners do listeners[i](key, value) end
        end,
        OnChange = function(fn) listeners[#listeners + 1] = fn end,
    }
    local ns = { QoLSettings = S, Apply = NOTHING, Shared = { Style = { LOGO_SMALL = "logo" } },
        THEME = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end }) }
    local function Item(link)
        local unit, slot = link:match("^item:(%w+):(%d+)$")
        return unit and state.gear[unit] and state.gear[unit][tonumber(slot)]
    end
    -- The tooltip: its lines, the right text of each as the game's TextRight font strings.
    local lines, rights = {}, {}
    local tooltip = {
        GetUnit = function() return "Someone", state.hovered end,
        IsForbidden = function() return false end,
        IsShown = function() return true end,
        Show = NOTHING,
        HookScript = function(self, script, fn) self[script] = fn end,
        AddDoubleLine = function(_, left, right)
            lines[#lines + 1] = left
            local n = #lines
            rights[n] = rights[n] or { SetText = function(self, text) self.text = text end }
            rights[n].text = right
        end,
        NumLines = function() return #lines end,
    }
    state.lines, state.rights, state.tooltip = lines, rights, tooltip
    -- Each module's own event frame.
    local function Frame()
        local frame = { events = {} }
        function frame.RegisterEvent(self, event) self.events[event] = true end
        function frame.UnregisterEvent(self, event) self.events[event] = nil end
        function frame.SetScript(self, _, fn) self.onEvent = fn end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    local units = { player = "Player-1-1" }
    state.units = units
    local env = setmetatable({
        _G = setmetatable({ NaowhForever = ns }, { __index = function(_, key)
            local n = key:match("^GameTooltipTextRight(%d+)$")
            return n and rights[tonumber(n)]
        end }),
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        issecretvalue = function() return false end,
        C_Item = {
            GetDetailedItemLevelInfo = function(link) local i = Item(link) return i and i[1] end,
            GetItemInfo = function(link) local i = Item(link) if i then return "x", link, i[2], i[1] end end,
            -- An item ID: where it goes, as state.instant has it; a link: its gear's.
            GetItemInfoInstant = function(link)
                if type(link) == "number" then
                    local equip = state.instant and state.instant[link]
                    if equip then return link, "", "", equip end
                    return nil
                end
                local i = Item(link)
                if i then return 1, "", "", i[3] end
            end,
        },
        GetInventoryItemLink = function(unit, slot)
            return state.gear[unit] and state.gear[unit][slot] and ("item:" .. unit .. ":" .. slot)
        end,
        GetTime = function() return state.now end,
        CreateFrame = Frame,
        GameTooltip = tooltip,
        TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) state.postCalls[#state.postCalls + 1] = fn end },
        Enum = { TooltipDataType = { Unit = 2 } },
        hooksecurefunc = function(t, key, fn)
            local original = t[key]
            t[key] = function(...) original(...); fn(...) end
        end,
        UnitIsPlayer = function(unit) return unit ~= nil end,
        UnitGUID = function(unit) return units[unit] or (unit and ("Player-1-" .. unit:gsub("%a", "") .. "9")) end,
        UnitIsUnit = function(a, b) return a == b end,
        UnitExists = function(unit) return unit == "player" or state.gear[unit] ~= nil end,
        UnitIsConnected = function() return true end,
        UnitLevel = function() return state.level or 60 end,
        ITEM_QUALITY_COLORS = { [0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" },
            [3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" }, [5] = { hex = "|cffff8000" } },
        InCombatLockdown = function() return state.combat end,
        CanInspect = function() return true end,
        CheckInteractDistance = function(unit) return not (state.far and state.far[unit]) end,
        NotifyInspect = function(unit) state.inspected[#state.inspected + 1] = unit end,
        ClearInspectPlayer = function() state.cleared = state.cleared + 1 end,
        C_Timer = { After = function(_, fn) state.timers[#state.timers + 1] = fn end },
        C_ChatInfo = { RegisterAddonMessagePrefix = NOTHING,
            SendAddonMessage = function(_, message, channel) state.sent[#state.sent + 1] = { message, channel } end },
        LE_PARTY_CATEGORY_INSTANCE = 2,
        IsInGroup = function(category) return category == nil and state.members > 0 end,
        IsInRaid = function() return false end,
        IsInGuild = function() return state.guild end,
        GetNumSubgroupMembers = function() return state.members end,
        GetNumGroupMembers = function() return state.members + 1 end,
    }, { __index = _G })
    Load({ "NaowhScore/Data/Formula.lua", "NaowhScore/Score.lua", "NaowhScore/Inspect.lua", "NaowhScore/Share.lua" },
        env)
    -- An event, to every frame listening for it (Share always; Inspect while on).
    function state.Fire(event, ...)
        for _, frame in ipairs(state.frames) do
            if frame.events[event] then frame.onEvent(frame, event, ...) end
        end
    end
    -- The timers waiting, run until none is left.
    function state.RunTimers()
        local guard = 0
        while state.timers[1] and guard < 50 do
            guard = guard + 1
            table.remove(state.timers, 1)()
        end
    end
    return ns, state, env
end

-- A full set, every slot at one level and quality; a two-hander or a main and off hand.
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function Set(level, quality, twoHand)
    local gear = {}
    for _, slot in ipairs(SLOTS) do gear[slot] = { level, quality, "INVTYPE_HEAD" } end
    if twoHand then
        gear[16] = { level, quality, "INVTYPE_2HWEAPON" }
        gear[17] = nil
    end
    return gear
end

-------------------------------------------------------------------------------
--  The formula
-------------------------------------------------------------------------------
do
    local ns, state = Fixture()
    local Score = ns.NaowhScore
    local function Of(gear)
        state.gear.player = gear
        return Score.Unit("player")
    end
    check("a full set of level 26 epics scores 26", math.abs(Of(Set(26, 4)) - 26) < 1e-9)
    check("so does it with a two-hander in place of a main and off hand",
        math.abs(Of(Set(26, 4, true)) - 26) < 1e-9)
    check("the same set in blues scores less, in greens less again",
        Of(Set(26, 3)) < 26 and Of(Set(26, 2)) < Of(Set(26, 3)))
    check("nothing worn scores 0", Of({}) == 0)
    -- The fitted worth of a quality (Data/Formula.lua): an epic of level x SCALE + SHIFT.
    local function Worth(level, quality) return level * Score.SCALE[quality] + Score.SHIFT[quality] end
    check("a full set of level 60 blues scores what a level 60 blue is worth",
        math.abs(Of(Set(60, 3)) - Worth(60, 3)) < 1e-9 and Worth(60, 3) > 40 and Worth(60, 3) < 55)
    check("a full set of level 20 greens scores what a level 20 green is worth",
        math.abs(Of(Set(20, 2)) - Worth(20, 2)) < 1e-9 and Worth(20, 2) > 5 and Worth(20, 2) < 12)
    check("starter whites worth less than nothing count 0", Of(Set(5, 1)) == 0)
    local gear = Set(30, 4)
    gear[5] = nil
    local noChest = Of(gear)
    gear = Set(30, 4)
    gear[11] = nil
    local noRing = Of(gear)
    check("an empty chest costs more than an empty ring: it carries more", noChest < noRing and noRing < 30)
    check("the shirt and tabard do not count", (function()
        local g = Set(30, 4)
        g[4], g[19] = { 300, 4, "INVTYPE_BODY" }, { 300, 4, "INVTYPE_TABARD" }
        return math.abs(Of(g) - 30) < 1e-9
    end)())
    gear = Set(30, 4)
    gear[1] = { 30, nil, "INVTYPE_HEAD" }   -- its quality not loaded yet
    local _, complete = Of(gear)
    check("an item not loaded yet: the score says it is not complete", complete == false)
    check("26.4 reads 26.4", Score.Text(26.44) == "26.4")
    state.gear.player = Set(40, 3)
    Measure("a character's score", 0.05, function() Score.Unit("player") end)
end

-------------------------------------------------------------------------------
--  Player tooltips
-------------------------------------------------------------------------------
do
    local ns, state = Fixture()
    local S = ns.QoLSettings
    S.Set("naowhScoreScan", false)   -- the hover alone here; the scan has its own test
    ns.Apply()
    check("off by default: no tooltip hook, no inspect listened for", #state.postCalls == 0
        and not state.frames[1].events.INSPECT_READY)
    S.Set("naowhScore", true)
    check("on: its hook goes in a frame later, after every module's (the badge line first)",
        #state.postCalls == 0 and state.timers[1] ~= nil)
    state.RunTimers()
    check("then once", #state.postCalls == 1 and state.frames[1].events.INSPECT_READY)
    ns.Apply()
    check("and only once", #state.postCalls == 1)
    local OnUnit = state.postCalls[1]
    local function Hover(unit)
        state.hovered = unit
        for k in pairs(state.lines) do state.lines[k] = nil end
        OnUnit(state.tooltip)
        return state.rights[#state.lines] and state.rights[#state.lines].text
    end
    state.gear.player = Set(20, 4)
    check("your own: from what you wear", Hover("player") == "20.0" and #state.inspected == 0)
    state.gear.party1 = Set(26, 4)
    local guid = "Player-1-19"
    check("another player's: asked for, '...' until it comes", Hover("party1") == "..."
        and state.inspected[1] == "party1")
    state.now = state.now + 0.5
    Hover("party1")
    check("not asked again while that request is out", #state.inspected == 1)
    state.Fire("INSPECT_READY", guid)
    check("the gear comes: the line fills in, and the inspect is let go",
        state.rights[#state.lines].text == "26.0" and state.cleared == 1)
    check("kept: hovered again, shown at once, not asked again", Hover("party1") == "26.0" and #state.inspected == 1)
    state.now = state.now + 400
    state.combat = true
    check("kept too long: asked again, but never in combat", Hover("party1") == "..." and #state.inspected == 1)
    state.combat = false
    local env = getfenv(OnUnit)
    env.InspectFrame = { IsShown = function() return true end }
    Hover("party1")
    check("nor while the game's Inspect window holds the inspect", #state.inspected == 1)
    env.InspectFrame = nil
    Hover("party1")
    check("then it is asked again", #state.inspected == 2)
    S.Set("naowhScore", false)
    check("off: no line", Hover("party1") == nil)
end

-------------------------------------------------------------------------------
--  Your group, in the background
-------------------------------------------------------------------------------
do
    local ns, state = Fixture()
    state.members = 3
    state.gear.party1, state.gear.party2, state.gear.party3 = Set(10, 4), Set(20, 4), Set(30, 4)
    ns.QoLSettings.Set("naowhScore", true)
    -- party2 runs Naowh Forever: its score is shared, so it is never inspected.
    state.Fire("CHAT_MSG_ADDON", "NaowhScore", "S Player-1-29 250", "PARTY", "Two")
    state.RunTimers()
    check("the first member not known is read", state.inspected[1] == "party1" and #state.inspected == 1)
    state.Fire("INSPECT_READY", "Player-1-19")
    state.now = state.now + 2
    state.RunTimers()
    check("then the next, skipping one who shares theirs", state.inspected[2] == "party3" and #state.inspected == 2)
    state.Fire("INSPECT_READY", "Player-1-39")
    state.now = state.now + 2
    state.RunTimers()
    check("and it stops once everyone is known", #state.inspected == 2 and not state.timers[1])
    local Score = ns.NaowhScore
    local function Near(guid, score) return math.abs(Score.Known(guid).score - score) < 1e-9 end
    check("their scores kept: inspected and shared", Near("Player-1-19", 10) and Near("Player-1-39", 30)
        and Near("Player-1-29", 25))
    state.Fire("INSPECT_READY", "Player-1-29")
    check("a shared score is never replaced by an inspect", Score.Known("Player-1-29").shared)
    Measure("the group walked, everyone known", 0.05, function() Score.Scan() end)
    ns.QoLSettings.Set("naowhScoreScan", false)
    check("Scan Your Group off: no roster listened to", not state.frames[1].events.GROUP_ROSTER_UPDATE)
end

-------------------------------------------------------------------------------
--  Players nearby: target, focus, mouseover and shown nameplates
-------------------------------------------------------------------------------
do
    local ns, state = Fixture()
    state.values.naowhScoreScan, state.values.naowhScoreNearby = false, true
    state.gear.nameplate1, state.gear.nameplate2, state.gear.target = Set(12, 3), Set(14, 3), Set(16, 3)
    state.far = { nameplate2 = true }
    ns.QoLSettings.Set("naowhScore", true)
    table.remove(state.timers, 1)()   -- the tooltip hook, a frame after Apply
    check("Scan Players Nearby on: nameplates and target listened to",
        state.frames[1].events.NAME_PLATE_UNIT_ADDED and state.frames[1].events.PLAYER_TARGET_CHANGED
        and not state.frames[1].events.GROUP_ROSTER_UPDATE)
    state.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    state.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    state.Fire("PLAYER_TARGET_CHANGED")
    state.timers[1]()
    table.remove(state.timers, 1)
    check("your target first", state.inspected[1] == "target")
    state.Fire("INSPECT_READY", "Player-1-9")
    state.now = state.now + 2
    table.remove(state.timers, 1)()
    check("then a player whose nameplate shows", state.inspected[2] == "nameplate1")
    state.Fire("INSPECT_READY", "Player-1-19")
    state.now = state.now + 2
    for i = #state.timers, 1, -1 do table.remove(state.timers, i)() end
    check("one out of inspect range is not asked, and looked at again later", #state.inspected == 2
        and state.timers[1] ~= nil)
    state.far = nil
    state.now = state.now + 5
    table.remove(state.timers, 1)()
    check("once in range, asked", state.inspected[3] == "nameplate2")
    state.Fire("INSPECT_READY", "Player-1-29")
    state.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    state.now = state.now + 2
    state.RunTimers()
    check("everyone known: the walk stops", #state.inspected == 3 and not state.timers[1])
    ns.QoLSettings.Set("naowhScoreNearby", false)
    check("Scan Players Nearby off: nothing around you listened to",
        not state.frames[1].events.NAME_PLATE_UNIT_ADDED and not state.frames[1].events.UPDATE_MOUSEOVER_UNIT)
end

-------------------------------------------------------------------------------
--  Sharing: always on, to your group and guild; theirs kept
-------------------------------------------------------------------------------
do
    local ns, state = Fixture()
    local Score = ns.NaowhScore
    check("sharing listens with the feature off: running Naowh means sharing",
        state.frames[2].events.CHAT_MSG_ADDON and state.values.naowhScore == false)
    state.gear.player, state.guild = Set(20, 4), true
    state.Fire("PLAYER_ENTERING_WORLD")
    check("logging in: the guild is asked for theirs and given yours",
        state.sent[1][1] == "R" and state.sent[1][2] == "GUILD" and state.sent[2][1] == "S Player-1-1 200 60")
    local sent = #state.sent
    state.RunTimers()
    check("nothing changed: nothing more goes", #state.sent == sent)
    state.members = 1
    state.gear.party1 = Set(5, 2)
    state.Fire("GROUP_ROSTER_UPDATE")
    check("joining a group: it is asked, and given yours", state.sent[sent + 1][1] == "R"
        and state.sent[sent + 1][2] == "PARTY" and state.sent[sent + 2][2] == "PARTY")
    sent = #state.sent
    state.gear.player = Set(22, 4)
    state.Fire("PLAYER_EQUIPMENT_CHANGED", 1)
    state.Fire("PLAYER_EQUIPMENT_CHANGED", 2)
    state.RunTimers()
    check("a gear swap: one message to the group and one to the guild",
        #state.sent == sent + 2 and state.sent[sent + 1][1] == "S Player-1-1 220 60")
    sent = #state.sent
    state.combat = true
    state.gear.player = Set(24, 4)
    state.Fire("PLAYER_EQUIPMENT_CHANGED", 1)
    state.RunTimers()
    check("in combat: held", #state.sent == sent)
    state.combat = false
    state.Fire("PLAYER_REGEN_ENABLED")
    check("and sent once it ends", #state.sent > sent and state.sent[#state.sent][1] == "S Player-1-1 240 60")
    sent = #state.sent
    state.Fire("CHAT_MSG_ADDON", "NaowhScore", "R", "PARTY", "Someone")
    state.Fire("CHAT_MSG_ADDON", "NaowhScore", "R", "PARTY", "Another")
    state.RunTimers()
    check("asked twice at once: answered once", #state.sent == sent + 1 and state.sent[#state.sent][2] == "PARTY")
    state.Fire("CHAT_MSG_ADDON", "NaowhScore", "S Player-7-00AB 264 31", "GUILD", "Guildie")
    check("a guildmate's, kept at once, as shared, with their level", Score.Known("Player-7-00AB").score == 26.4
        and Score.Known("Player-7-00AB").shared and Score.Known("Player-7-00AB").level == 31)
    state.Fire("CHAT_MSG_ADDON", "NaowhScore", "S nonsense", "GUILD", "Guildie")
    state.Fire("CHAT_MSG_ADDON", "NaowhScore", "S Player-7-00AB 264", "WHISPER", "Stranger")
    state.Fire("CHAT_MSG_ADDON", "OtherAddon", "S Player-8-00AB 999", "GUILD", "Guildie")
    check("nonsense, whispers and other addons' messages are ignored", Score.Known("Player-8-00AB") == nil)
    local onEvent = state.frames[2].onEvent
    Measure("a shared score received", 0.02, function()
        onEvent(state.frames[2], "CHAT_MSG_ADDON", "NaowhScore", "S Player-7-00AB 264", "GUILD", "Guildie")
    end)
    Measure("another addon's message passed over", 0.005, function()
        onEvent(state.frames[2], "CHAT_MSG_ADDON", "OtherAddon", "hello", "GUILD", "Someone")
    end)
end

-------------------------------------------------------------------------------
--  The best there is, and grades: against the best in the game, or for a level
-------------------------------------------------------------------------------
do
    local ns, state = Fixture()
    local Score = ns.NaowhScore
    -- Gear the data knows: { item level, required level, quality } and where it goes.
    local GEAR = {
        [1] = { 60, 55, 4, "INVTYPE_HEAD" }, [2] = { 30, 25, 3, "INVTYPE_HEAD" },
        [3] = { 60, 55, 4, "INVTYPE_FINGER" }, [4] = { 58, 53, 4, "INVTYPE_FINGER" },
        [5] = { 60, 0, 4, "INVTYPE_CHEST" },   -- a faction reward: no required level
        [6] = { 60, 55, 4, "INVTYPE_2HWEAPON" }, [7] = { 60, 55, 4, "INVTYPE_WEAPON" },
    }
    ns.Journal = { Items = {} }
    for id, g in pairs(GEAR) do ns.Journal.Items[id] = { 4, 0, g[1], g[2], g[3] } end
    state.instant = {}
    for id, g in pairs(GEAR) do state.instant[id] = g[4] end
    local W = Score.SLOTS
    local total = 0
    for _, slot in ipairs(SLOTS) do total = total + W[slot] end
    local expected = (W[1] * 60 + W[11] * 60 + W[12] * 58 + W[5] * 60 + (W[16] + W[17]) * 60) / total
    check("the best in the game: each slot's best, two different rings, a two-hander for both hands",
        math.abs(Score.Best() - expected) < 1e-9)
    -- A level's best: a full set of blues five item levels over it (the data has little that
    -- low), never over the best in the game.
    local blue = function(level) return level * Score.SCALE[3] + Score.SHIFT[3] end
    local at30 = blue(35)
    check("for a level: a full set of blues five levels over it, capped at the best in the game",
        math.abs(Score.Best(30) - math.min(at30, Score.Best())) < 1e-9 and math.abs(Score.Best(10) - blue(15)) < 1e-9)
    at30 = Score.Best(30)
    check("rising with the level, and never over the best in the game", Score.Best(15) > Score.Best(14)
        and Score.Best(200) == Score.Best())
    check("a level 12 in whites is far from its best, not at it", Score.Grade(1.3, 12, "level") < 0.2)
    local share, quality = Score.Grade(Score.Best() * 0.5, 30)
    check("against the best in the game: half is green", math.abs(share - 0.5) < 1e-9 and quality == 2)
    state.values.naowhScoreCompare = "level"
    share, quality = Score.Grade(at30, 30)
    check("against the best for their level: the best for 30 is orange at 30", share == 1 and quality == 5)
    check("and coloured as the top of the ramp", Score.Colored(at30, 30):find("^|cffff8000") ~= nil)
    state.values.naowhScoreCompare = "max"
    -- The ramp: grey at nothing, white, greens, blues, purples, orange at the best.
    check("the ramp: grey, white, green at 45%, blue at 65%, purple at 80%, orange at the best",
        Score.Code(0) == "|cff9e9e9e" and Score.Code(0.15) == "|cffffffff" and Score.Code(0.45) == "|cff1fff00"
        and Score.Code(0.65) == "|cff0070de" and Score.Code(0.8) == "|cffa336ed" and Score.Code(1) == "|cffff8000")
    check("between two stops, a colour between them", Score.Code(0.3) ~= Score.Code(0.25)
        and Score.Code(0.3) ~= Score.Code(0.35))
    check("made once per percent", Score.Code(0.301) == Score.Code(0.3))
    -- The tooltip: the number, then its share in the same colour; no bar.
    local tip = Score.Tooltip(Score.Best() * 0.5, 30)
    check("the tooltip: the number and its percent, in one colour",
        tip == Score.Colored(Score.Best() * 0.5, 30) .. "  " .. Score.Code(0.5) .. "50%|r")
    check("no bar", not tip:find("|T", 1, true))
    check("made once per percent", Score.Tooltip(Score.Best() * 0.5, 30) == tip)
    -- Both: the number against the best in the game, then in gold its share of their level's.
    state.values.naowhScoreCompare = "both"
    local at10 = Score.Best(10)
    local both = Score.Tooltip(at10 * 0.44, 10)
    check("Both: the number against the best in the game, then in gold, saying so, the level's",
        both == Score.Colored(at10 * 0.44, 10, "max") .. "  |cffffd10044% of level 10|r")
    check("at a level whose best is the best in the game, just the one percent",
        not Score.Tooltip(Score.Best(), 60):find("of level", 1, true))
    -- The real hook, on your own tooltip at 20 with Both and the data loaded: the line is there.
    ns.QoLSettings.Set("naowhScoreScan", false)
    ns.QoLSettings.Set("naowhScore", true)
    ns.Apply()
    state.RunTimers()
    state.level, state.hovered = 20, "player"
    state.gear.player = Set(20, 3)
    for k in pairs(state.lines) do state.lines[k] = nil end
    state.postCalls[#state.postCalls](state.tooltip)
    local right = state.rights[#state.lines] and state.rights[#state.lines].text
    check("your own tooltip at 20, Both: the score and its share of level 20", right
        and right:find("of level 20", 1, true) ~= nil)
    state.level = nil
    state.values.naowhScoreCompare = "max"
end

print(("test-naowh-score: %d checks passed"):format(checks))
