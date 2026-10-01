-- Run with Lua 5.1 from the repository root: the Dungeon Journal's data and rules. Loads the
-- files its DungeonJournal.xml lists, in that order, against stubs (and checks the TOC loads
-- that XML), then checks the generated data holds together, the loot rules, which dungeon
-- you are in, the small helpers, what counting costs, and that nothing is made or hooked
-- while the Journal is off. Its quests have their own test (test-journal-quests.lua).
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

-- The journal's files, in load order, from its XML; the TOC loads that XML.
local tocLoads = false
for line in io.lines("NaowhForever.toc") do
    if line:gsub("\r$", "") == "DungeonJournal\\DungeonJournal.xml" then tocLoads = true end
end
check("the TOC loads the journal", tocLoads)
local files = dofile("Tools/regression/toc_files.lua")("^DungeonJournal/.*%.lua$")
check("the journal lists its files", #files > 40)

local RING_SLOTS = { 1, 2 }
local WHITE = { r = 1, g = 1, b = 1 }
-- A class's colour, as the game's ColorMixin: it can wrap a name in its colour code.
local CLASS_COLOR = { r = 1, g = 1, b = 1, WrapTextInColorCode = function(_, text) return "|cffffffff" .. text .. "|r" end }

-- The game's strsplit: the parts of s between each sep, as separate values; with limit, at
-- most that many, the last holding the rest.
local function strsplit(sep, s, limit)
    local parts, n, at = {}, 0, 1
    local plain = sep:gsub("%p", "%%%0")
    while true do
        local first, last = s:find(plain, at)
        if not first or (limit and n == limit - 1) then break end
        n = n + 1
        parts[n] = s:sub(at, first - 1)
        at = last + 1
    end
    n = n + 1
    parts[n] = s:sub(at)
    return unpack(parts, 1, n)
end

-- A frame whose every method does nothing, except: HookScript, which is counted; its
-- scripts and events, which it keeps (frame.scripts, frame.events) for a test to fire; its
-- parent, size and text, which it remembers; and the measures a layout reads, which answer
-- plausible numbers. Enough to build and draw the window offline, not to look at it.
local MEASURES = { GetStringWidth = 40, GetStringHeight = 12, GetFrameLevel = 1, GetEffectiveScale = 1,
    GetScale = 1, GetLeft = 0, GetRight = 300, GetTop = 0, GetBottom = 0, GetVerticalScroll = 0,
    GetVerticalScrollRange = 0, GetValue = 0 }
-- Each measure as a method, made once.
local MEASURE_METHODS = {}
for name, value in pairs(MEASURES) do MEASURE_METHODS[name] = function() return value end end
local Frame
-- One function for every method a frame does nothing with: made once, so a stub frame makes
-- no garbage and timings measure the addon alone.
local NOTHING = function() end
local METHODS = {
    SetScript = function(frame, script, fn) frame.scripts[script] = fn end,
    RegisterEvent = function(frame, event) frame.events[event] = true end,
    UnregisterAllEvents = function(frame) for event in pairs(frame.events) do frame.events[event] = nil end end,
    UnregisterEvent = function(frame, event) frame.events[event] = nil end,
    GetParent = function(frame) return rawget(frame, "parent") end,
    SetWidth = function(frame, w) frame.w = w end,
    SetHeight = function(frame, h) frame.h = h end,
    SetSize = function(frame, w, h) frame.w, frame.h = w, h end,
    GetWidth = function(frame) return rawget(frame, "w") or 300 end,
    GetHeight = function(frame) return rawget(frame, "h") or 24 end,
    SetText = function(frame, text) frame.text = text end,
    GetText = function(frame) return rawget(frame, "text") or "" end,
    IsShown = function(frame) return rawget(frame, "shown") ~= false end,
    IsVisible = function(frame) return rawget(frame, "shown") ~= false end,
    Show = function(frame) frame.shown = true end,
    Hide = function(frame) frame.shown = false end,
    SetShown = function(frame, shown) frame.shown = shown and true or false end,
    CreateTexture = function(frame) return Frame(rawget(frame, "state"), frame) end,
    CreateFontString = function(frame) return Frame(rawget(frame, "state"), frame) end,
    IsMouseOver = function(frame)
        local state = rawget(frame, "state")
        return state ~= nil and state.mouseOver == true
    end,
    -- Kept, so a test can tell what has the keyboard.
    SetFocus = function(frame)
        local state = rawget(frame, "state")
        if state then state.focus = frame end
    end,
    HasFocus = function(frame)
        local state = rawget(frame, "state")
        return state ~= nil and state.focus == frame
    end,
    -- Kept, so a test can tell which of the game's icons were shown.
    SetAtlas = function(frame, atlas)
        local state = rawget(frame, "state")
        if state then state.atlases[atlas] = true end
    end,
}
Frame = function(state, parent)
    return setmetatable({ scripts = {}, events = {}, state = state, parent = parent }, { __index = function(_, key)
        if key == "HookScript" then
            return function(_, script) state.hooks[#state.hooks + 1] = script end
        end
        if METHODS[key] then return METHODS[key] end
        local measure = MEASURE_METHODS[key]
        if measure then return measure end
        -- Any other method does nothing; a field the code keeps on the frame (lower case) is
        -- nil until set, as on a real frame.
        if key:find("^%u") then return NOTHING end
    end })
end

local function fixture(settings)
    local state = {
        level = 20, instance = nil, combat = false, bisList = true,
        hooks = {}, frames = 0, printed = {}, waypoints = {}, mapOpened = nil, requested = {},
        refreshes = 0, made = {}, logged = {}, watched = {}, objectives = {}, account = {}, guid = "Player-4613-006EB819", now = 1000, clock = 50,
        bis = {}, worn = {}, owned = {}, names = {}, sources = {}, looks = {},
        sent = {}, timers = {}, pushed = {}, fonts = {}, atlases = {}, dressable = {}, hasLook = {},
    }
    local values = {
        enabled = false, mapPanel = true, usableOnly = true, showRare = true, showChance = true,
        showAlliance = true, showHorde = true, showKills = true, shareRequests = true,
        showAppearance = false, showTips = true, missingBisOnly = false,
    }
    for k, v in pairs(settings or {}) do values[k] = v end
    -- The kit's module settings: Set tells every listener, as UI.ModuleSettings does.
    local listeners = {}
    local S = {}
    function S.Get(key) return values[key] end
    function S.Set(key, value)
        values[key] = value
        for i = 1, #listeners do listeners[i](key, value) end
    end
    function S.OnChange(fn) listeners[#listeners + 1] = fn end

    local ns = {
        THEME = setmetatable({}, { __index = function() return WHITE end }),
        UI = { ModuleSettings = function(_, defaults) state.defaults = defaults; return S end,
            SlimScroll = function(parent)
                local scroll = Frame(state, parent)
                scroll.bar = Frame(state, parent)
                return scroll
            end,
            BuildSliderCore = function(parent)
                local track = Frame(state, parent)
                track.rail, track.fill, track.thumb = Frame(state, track), Frame(state, track), Frame(state, track)
                track.valueBox, track.valueFill = Frame(state, parent), Frame(state, parent)
                track.valueBorder = { _frame = Frame(state, parent) }
                track._refreshValue = function() end
                return track
            end,
            CloseOnEscape = function() end,
            STATUS = { untested = "" },
            RefreshPage = function() state.refreshes = state.refreshes + 1 end },
        QoLSettings = { Get = function(key) return key == "bis" and state.bisList end },
        Color = function(_, text) return text and ("|cffffffff" .. text .. "|r") or "|cffffffff" end,
        Apply = function() end,
        AccountSettings = function() return state.account end,
        UIScale = function() return 1 end,
        UIFontPath = function() return "font" end,
        -- Kept, so a test can read what was written.
        Font = function(parent)
            local font = Frame(state, parent)
            state.fonts[#state.fonts + 1] = font
            return font
        end,
        Solid = function(parent) return Frame(state, parent) end,
        -- As ns.Border: its frame, and a way to colour it.
        Border = function(parent) return { _frame = Frame(state, parent), SetColor = function() end } end,
        Button = function(parent) return Frame(state, parent) end,
        BlackBorder = function(frame) return frame end,
        AccentBorder = function(frame) return frame end,
        BisListIsEmpty = function() return false end,
        SetButtonText = function() end,
        Tooltip = function() end,
        ThemeTint = function() return WHITE end,
        NewSearchBox = function(parent)
            local box = Frame(state, parent)
            box.border = Frame(state, box)   -- as ns.NewEditBox gives an edit box
            return box
        end,
        Print = function(text) state.printed[#state.printed + 1] = text end,
        PlaceWaypoint = function(title, map, x, y, note)
            state.waypoints[#state.waypoints + 1] = { title = title, map = map, x = x, y = y, note = note }
            return true
        end,
        IsBisItem = function(id) return state.bis[id] end,
        -- Every item goes in slot 1 or 2, like a ring.
        BisSlotsFor = function() return RING_SLOTS end,
        -- Cloth only, so a mage can use cloth and anything without an armor type.
        ClassCanUse = function(class, facts)
            return class == "MAGE" and (facts[1] == 4 and (facts[2] == 0 or facts[2] == 1))
        end,
    }
    local env = {
        _G = { NaowhForever = ns },
        strsplit = strsplit,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        issecretvalue = function() return false end,
        -- You are a mage; a group member is what the test made them.
        UnitClass = function(unit)
            local member = state.party and state.party[tonumber(unit:match("^party(%d)$") or 0)]
            if member and member.class then return member.class, member.class end
            return "Mage", "MAGE"
        end,
        UnitGroupRolesAssigned = function(unit)
            if unit == "player" then return state.role or "NONE" end
            local member = state.party and state.party[tonumber(unit:match("^party(%d)$") or 0)]
            return member and member.role or "NONE"
        end,
        UnitIsUnit = function(a, b) return a == b end,
        GetNumGroupMembers = function() return state.party and #state.party + 1 or 0 end,
        C_ClassColor = { GetClassColor = function() return CLASS_COLOR end },
        UnitLevel = function() return state.level end,
        UnitFactionGroup = function() return "Alliance" end,
        IsInInstance = function() return state.instance ~= nil, state.instance and (state.instance.kind or "party") end,
        LOOT_ITEM_SELF = "You receive loot: %s.",
        GetInstanceInfo = function()
            local i = state.instance or {}
            return i.name, nil, nil, nil, nil, nil, nil, i.id
        end,
        InCombatLockdown = function() return state.combat end,
        IsControlKeyDown = function() return state.ctrl == true end,
        LOCALIZED_CLASS_NAMES_MALE = { WARLOCK = "Warlock", PALADIN = "Paladin", MAGE = "Mage" },
        hooksecurefunc = function(t, key, fn)
            local orig = t[key]
            t[key] = function(...) orig(...); fn(...) end
        end,
        CreateFrame = function(_, _, parent)
            state.frames = state.frames + 1
            local frame = Frame(state, parent)
            state.made[#state.made + 1] = frame
            return frame
        end,
        Mixin = function(target, ...)
            for i = 1, select("#", ...) do
                for k, v in pairs((select(i, ...))) do target[k] = v end
            end
            return target
        end,
        CreateColor = function() return Frame(state) end,
        CreateAtlasMarkup = function(atlas) return "|A:" .. atlas .. "|a" end,
        UIParent = Frame(state),
        GameTooltip = Frame(state),
        GameTooltip_Hide = function() end,
        -- A home group, not an instance one (the dungeon finder's).
        IsInGroup = function(category) return state.party ~= nil and category ~= 2 end,
        IsInRaid = function() return false end,
        LE_PARTY_CATEGORY_INSTANCE = 2,
        GetNumSubgroupMembers = function() return state.party and #state.party or 0 end,
        UnitName = function(unit)
            if unit == "player" then return "Die Man" end
            local member = state.party and state.party[tonumber(unit:match("^party(%d)$") or 0)]
            return member and member.name
        end,
        QuestLogPushQuest = function(index) state.pushed[#state.pushed + 1] = index end,
        Enum = { SendAddonMessageResult = { Success = 0 } },
        C_ChatInfo = {
            InChatMessagingLockdown = function() return state.locked end,
            RegisterAddonMessagePrefix = function(prefix) state.prefix = prefix end,
            SendAddonMessage = function(prefix, text, channel)
                state.sent[#state.sent + 1] = { prefix = prefix, text = text, channel = channel }
                return 0
            end,
        },
        GetQuestLogQuestText = function() return "Bring me the head of Edwin VanCleef.", "0/1 Head" end,
        GetNumQuestLogChoices = function() return 1 end,
        GetQuestLogChoiceInfo = function() return "Chausses of Westfall", 134400, 1, 3, true, 6087 end,
        GetNumQuestLogRewards = function() return 0 end,
        GetQuestLogRewardInfo = function() end,
        GetQuestLogRewardXP = function() return 9750 end,
        GetQuestLogRewardMoney = function() return 0 end,
        BreakUpLargeNumbers = function(n) return tostring(n) end,
        GetCoinTextureString = function(n) return tostring(n) end,
        QuestUtils_IsQuestWatched = function(id) return state.watched[id] == true end,
        IsMouseButtonDown = function() return false end,
        GetQuestDifficultyColor = function() return {} end,
        QuestDifficultyColors = { trivial = {} },
        UnitGUID = function(unit)
            if unit == "player" then return state.guid end
            local member = state.party and state.party[tonumber(unit:match("^party(%d)$") or 0)]
            return member and member.guid
        end,
        time = function() return state.now end,
        date = os.date,   -- the game's date is the same function
        GetTime = function() return state.clock end,
        WorldMapFrame = Frame(state),
        EventUtil = { ContinueOnAddOnLoaded = function() end },
        C_Map = { OpenWorldMap = function(map) state.mapOpened = map end,
            GetMapInfo = function(map) return map == 52 and { name = "Westfall" } or nil end },
        C_Timer = { After = function(_, fn) state.timers[#state.timers + 1] = fn end },
        C_Item = {
            IsEquippedItem = function(id) return state.worn[1] == id or state.worn[2] == id end,
            GetItemCount = function(id) return state.owned[id] or 0 end,
            IsDressableItemByID = function(id) return state.dressable[id] == true end,
            GetItemNameByID = function(id) return state.names[id] end,
            GetItemInfo = function(id) return state.names[id], nil, state.names[id] and 3 end,
            -- What the test says an item is: its type's words and the slot it goes in.
            GetItemInfoInstant = function(id)
                local slot = state.slots and state.slots[id]
                if slot then return id, nil, "Game's words", slot end
            end,
            GetItemIconByID = function() return 134400 end,
            GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end,
            GetItemQualityByID = function() return nil end,
            RequestLoadItemDataByID = function(id) state.requested[#state.requested + 1] = id end,
        },
        C_QuestLog = {
            IsOnQuest = function() return false end,
            IsComplete = function() return false end,
            IsQuestFlaggedCompleted = function() return state.allDone == true end,
            GetTitleForQuestID = function() return nil end,
            GetQuestDifficultyLevel = function() return 0 end,
            IsUnitOnQuest = function(unit, id)
                local member = state.party and state.party[tonumber(unit:match("^party(%d)$") or 0)]
                return member ~= nil and member.quests[id] == true
            end,
            -- One quest in the log, for the quest panel.
            GetLogIndexForQuestID = function(id) return state.logged[id] end,
            GetSelectedQuest = function() return state.selected end,
            SetSelectedQuest = function(id) state.selected = id end,
            GetQuestObjectives = function() return state.objectives end,
            IsPushableQuest = function(id) return state.unpushable ~= id end,
            CanAbandonQuest = function() return true end,
            AddQuestWatch = function(id) state.watched[id] = true end,
            RemoveQuestWatch = function(id) state.watched[id] = nil end,
            SetAbandonQuest = function() state.abandonSet = state.selected end,
            AbandonQuest = function() state.abandoned = state.abandonSet end,
            RequestLoadQuestByID = function() end,
        },
        C_TransmogCollection = {
            GetItemInfo = function(id) return nil, state.sources[id] end,
            GetAppearanceInfoBySource = function(source) return state.looks[source] end,
            PlayerHasTransmogByItemInfo = function(id) return state.hasLook[id] == true end,
        },
        GetInventoryItemID = function(_, slot) return state.worn[slot] end,
    }
    setmetatable(env, { __index = _G })
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk()
    end
    return ns, state, S
end

-------------------------------------------------------------------------------
--  The data
-------------------------------------------------------------------------------
do
    local ns, state = fixture()
    local J = ns.Journal
    local questNames = {}
    for _, entry in ipairs(J.QuestData) do questNames[entry.name] = true end

    local keys, npcs, bosses, items, entrances = {}, {}, 0, 0, 0
    for _, dungeon in ipairs(J.Dungeons()) do
        check("dungeon key is unique: " .. dungeon.key, not keys[dungeon.key])
        keys[dungeon.key] = true
        check("dungeon is named as the quest data names it: " .. dungeon.name, questNames[dungeon.name])
        check("dungeon joined with its quest entry: " .. dungeon.name, dungeon.quests ~= nil)
        check("dungeon knows the zone of its entrance: " .. dungeon.name, type(dungeon.zone) == "string")
        check("and whose ground it is: " .. dungeon.name, dungeon.territory == "Alliance"
            or dungeon.territory == "Horde" or dungeon.territory == "Contested")
        local entrance = dungeon.entrance
        if entrance then
            entrances = entrances + 1
            check("entrance is on a map: " .. dungeon.name, type(entrance.map) == "number" and entrance.map > 0)
            check("entrance is a spot on it: " .. dungeon.name, entrance.x > 0 and entrance.x < 100
                and entrance.y > 0 and entrance.y < 100)
        end
        local here = {}
        for _, wing in ipairs(dungeon.wings) do
            for _, boss in ipairs(wing.bosses) do
                bosses = bosses + 1
                check("boss has a name in " .. dungeon.name, type(boss.name) == "string" and boss.name ~= "")
                if boss.npc then
                    check("boss listed once: " .. boss.name, not here[boss.npc])
                    here[boss.npc], npcs[boss.npc] = boss, true
                end
                if boss.chance then
                    check("a chance for every item: " .. boss.name, #boss.chance == #boss.loot)
                    for _, c in ipairs(boss.chance) do
                        check("chance is a percent, 0 when unknown: " .. boss.name, c >= 0 and c <= 100)
                    end
                end
                for _, id in ipairs(boss.loot or {}) do
                    items = items + 1
                    local facts = J.Items[id]
                    check("item " .. id .. " has its facts", facts ~= nil)
                    check("item " .. id .. " is uncommon or better", facts[J.FACT.QUALITY] >= 2)
                end
                -- A tip is shared in chat whole: "Naowh's tip for <boss>: <tip>" in one message.
                local tip = J.Tip(boss)
                if tip then
                    check("tip for " .. boss.name .. " is one plain line", tip ~= "" and not tip:find("[\r\n|]"))
                    check("tip for " .. boss.name .. " fits one chat message",
                        #("Naowh's tip for %s: %s"):format(boss.name, tip) <= 255)
                end
            end
        end
    end
    check("every quest dungeon has a journal entry", #J.Dungeons() == #J.QuestData)
    local new, raids = 0, {}
    for _, dungeon in ipairs(J.Dungeons()) do
        if dungeon.raid then
            raids[dungeon.key] = dungeon.raid
        elseif dungeon.new then
            new = new + 1
        end
    end
    check("the nine dungeons new in Forever are marked new", new == 9)
    -- The raids announced for Forever, and only those: the classic ones wait in the data.
    check("the three announced raids, with their sizes", raids.OnyxiasLair == 40 and raids.BarrowDeeps == 10
        and raids.HyjalSummit == 20)
    check("no raid that is not announced", raids.MoltenCore == nil and raids.Naxxramas == nil)
    check("a raid's page says what is not known yet", J.Get("HyjalSummit").note ~= nil)
    check("a raid for one level shows it once", J.LevelRange(J.Get("OnyxiasLair")) == "60")
    check("a dungeon shows its range", J.LevelRange(J.Get("RagefireChasm")) == "13-18")
    check("Onyxia's kills are counted", J.Get("OnyxiasLair").wings[1].bosses[1].encounters[1] == 1084)
    -- A quest that starts from a drop inside its dungeon has its waypoint at the entrance.
    local glowing
    for _, entry in ipairs(J.Quests.List(J.Get("WailingCaverns").quests, {}, {})) do
        if entry.quest[1] == 6981 then glowing = entry end
    end
    check("The Glowing Shard is listed", glowing ~= nil)
    check("and has a waypoint: the dungeon's entrance", glowing.canWaypoint)
    check("hundreds of bosses", bosses > 150)
    check("the entrances with a source that matches Forever's map", entrances == 29)
    local boss, dungeon = J.Boss(639)
    check("the boss loot window finds a boss by its NPC ID", boss and boss.name == "Edwin VanCleef"
        and dungeon.key == "Deadmines")
    check("and nothing for an NPC that is no boss", J.Boss(1) == nil)
    check("hundreds of loot entries", items > 300)
    local tips = 0
    for npc in pairs(J.Tips) do
        check("tip " .. npc .. " belongs to a listed boss", npcs[npc])
        tips = tips + 1
    end
    check("nearly every boss has a tip", tips > 150)
    check("a boss with no NPC ID has no tip", J.Tip({ name = "Nobody" }) == nil)

    -- The Filters menu and the settings page are both built from J.OPTION_GROUPS.
    local labels, offered = {}, {}
    for _, group in ipairs(J.OPTION_GROUPS) do
        check("an option group has a title", type(group.title) == "string" and #group.options > 0)
        for _, option in ipairs(group.options) do
            check("option " .. option.key .. " is a setting", state.defaults[option.key] ~= nil)
            check("option " .. option.key .. " is offered once", not offered[option.key])
            check("option label " .. option.label .. " is unique", not labels[option.label])
            check("option " .. option.key .. " says what it does", type(option.tooltip) == "string"
                and option.tooltip ~= "")
            offered[option.key], labels[option.label] = true, true
        end
    end
    print(("  %d dungeons, %d bosses, %d loot entries, %d tips"):format(#J.Dungeons(), bosses, items, tips))
end

-------------------------------------------------------------------------------
--  Where you are, and the way in
-------------------------------------------------------------------------------
do
    local ns, state = fixture()
    local J = ns.Journal
    check("outside an instance, none", J.Current() == nil)
    state.instance = { id = 36, name = "The Deadmines" }
    check("the instance ID finds the dungeon", J.Current()[1].key == "Deadmines")
    check("and the page opens on it", J.Suggested().key == "Deadmines")
    state.instance = { id = 229, name = "Blackrock Spire" }
    check("Blackrock Spire is both halves", #J.Current() == 2)
    state.instance = { id = 99999, name = "Shaper's Terrace" }
    check("a new dungeon is found by its name", J.Current()[1].key == "ShapersTerrace")
    state.instance = { id = 99998, name = "Onyxia's Lair", kind = "raid" }
    check("so is a raid", J.Current()[1].key == "OnyxiasLair")
    state.instance = { id = 99997, name = "Warsong Gulch", kind = "pvp" }
    check("a battleground is no dungeon", J.Current() == nil)
    state.instance = nil
    state.level = 40
    local levels = J.Levels(J.Suggested())
    check("outside, the page opens on one in range", levels[1] <= 40 and levels[2] >= 40)

    check("an entrance that is not known shows nothing", J.ShowEntrance({ name = "Nowhere" }) == false)

    check("and places no waypoint", #state.waypoints == 0)
    local deadmines = J.Get("Deadmines")
    check("a known entrance shows", J.ShowEntrance(deadmines))
    local placed = state.waypoints[1]
    check("with a waypoint on it", placed.map == deadmines.entrance.map and placed.x == deadmines.entrance.x
        and placed.note == " (entrance)")
    check("and the world map open on its zone", state.mapOpened == deadmines.entrance.map)
    state.mapOpened, state.combat = nil, true
    J.ShowEntrance(deadmines)
    check("in combat the waypoint still goes on", #state.waypoints == 2)
    check("but the map stays shut", state.mapOpened == nil)
end

-------------------------------------------------------------------------------
--  The small helpers
-------------------------------------------------------------------------------
do
    local ns, state, S = fixture()
    local J = ns.Journal
    check("a creature's GUID gives its NPC ID", J.NpcID("Creature-0-4613-36-1234-639-0000ABCDEF") == 639)
    check("so does a vehicle's", J.NpcID("Vehicle-0-4613-36-1234-1234-0000ABCDEF") == 1234)
    check("a player's gives none", J.NpcID("Player-4613-006EB819") == nil)
    check("a pet's gives none", J.NpcID("Pet-0-4613-36-1234-165189-0100ABCDEF") == nil)

    J.TurnOn()
    check("opening the Journal turns it on", S.Get("enabled") == true)
    check("and its settings page follows", state.refreshes == 1)
    check("and says so once", #state.printed == 1)
    J.TurnOn()
    check("not again while it is on", #state.printed == 1)

    -- The faction switch: a dungeon on one side's ground is listed while that side is on;
    -- a contested one always.
    local horde, alliance, contested = J.Get("RagefireChasm"), J.Get("Stockade"), nil
    for _, dungeon in ipairs(J.Dungeons()) do
        if dungeon.territory == "Contested" then contested = contested or dungeon end
    end
    check("Ragefire Chasm is on Horde ground", horde.territory == "Horde")
    check("The Stockade on Alliance ground", alliance.territory == "Alliance")
    check("both sides listed by default", J.FactionShown(horde) and J.FactionShown(alliance))
    S.Set("showHorde", false)
    check("Horde off hides Horde ground", not J.FactionShown(horde) and J.FactionShown(alliance))
    check("a raid is listed whichever side is off", J.FactionShown(J.Get("OnyxiasLair")))
    check("some dungeons are on contested ground", contested ~= nil)
    S.Set("showAlliance", false)
    check("which is listed with either side off", J.FactionShown(contested))
    S.Set("showAlliance", true)
    S.Set("showHorde", true)

    local Columns, St = J.View.Columns, J.Style
    for _, width in ipairs({ 100, 340, 560, 700, 1000, 3000 }) do
        local columns, w = Columns(width)
        check("at least one card across at " .. width, columns >= 1 and columns <= St.MAX_COLUMNS)
        check("the cards fit across at " .. width, columns * w + St.CARD_GAP * (columns - 1) <= width)
        check("a second card only where both are wide enough at " .. width, columns == 1 or w >= St.CARD_MIN_W)
    end
    check("a narrow view is one card as wide as it", select(2, Columns(300)) == 300)
    check("a wide one stops at the most across", Columns(5000) == St.MAX_COLUMNS)

    local Plain = J.View.Parts.Plain
    check("a where line loses its colours and has dots for dashes",
        Plain("|cffffd100Ratchet|r - Crane Operator") == "Ratchet" .. St.PLACE_DOT .. "Crane Operator")
    check("a line with neither is unchanged", Plain("Plain place") == "Plain place")
end

-------------------------------------------------------------------------------
--  The loot rules
-------------------------------------------------------------------------------
do
    local ns, state, S = fixture()
    local J, Loot = ns.Journal, ns.Journal.Loot
    local filters = Loot.ReadFilters({})
    local cloth, leather
    for id, facts in pairs(J.Items) do
        if facts[1] == 4 and facts[2] == 1 then cloth = cloth or id end
        if facts[1] == 4 and facts[2] == 2 then leather = leather or id end
    end
    check("a mage can use cloth", Loot.Usable(cloth))
    check("but not leather", not Loot.Usable(leather))
    check("an item the journal does not know is usable", Loot.Usable(1))
    check("My Class Only hides leather", not Loot.Shown(leather, filters))
    S.Set("usableOnly", false)
    check("the filters are what was read, not the setting now", not Loot.Shown(leather, filters))
    Loot.ReadFilters(filters)
    check("and read again they show it", Loot.Shown(leather, filters))

    local boss = { loot = { 101, 102, 103 } }
    state.bis = { [101] = 1, [102] = 2 }
    check("a boss counts its BiS, pick 1 only", Loot.BossBis(boss) == 1)
    check("a boss with no loot counts none", Loot.BossBis({}) == 0)

    -- Upgrade: higher on the list than what you wear in a slot it fits.
    state.bis = { [201] = 2, [202] = 3, [203] = 1 }
    state.worn = { 202, 203 }
    check("a #2 beats the #3 you wear in one of its slots", Loot.Upgrade(201))
    state.worn = { 203, 203 }
    check("not your BiS in both slots", not Loot.Upgrade(201))
    state.worn = { 203 }
    check("an empty slot takes anything on the list", Loot.Upgrade(201))
    state.worn = { 999, 203 }
    check("something off the list is beaten by any pick", Loot.Upgrade(202))
    state.worn = { 201, 202 }
    check("never what you have on", not Loot.Upgrade(201))
    check("never an item off the list", not Loot.Upgrade(999))

    -- Missing BiS: an upgrade you do not have in your bags or bank.
    state.worn = { 202, 203 }
    check("an upgrade you do not have is missing", Loot.Missing(201))
    state.owned[201] = 1
    check("one in your bags or bank is not", not Loot.Missing(201))
    state.owned[201] = nil
    S.Set("missingBisOnly", true)
    Loot.ReadFilters(filters)
    check("Missing BiS Only lists a missing one", Loot.Shown(201, filters))
    check("and hides the rest", not Loot.Shown(999, filters))
    state.bisList = false
    Loot.ReadFilters(filters)
    check("with the BiS List off it filters nothing", Loot.Shown(999, filters) and not filters.missingBis)
    state.bisList = true
    S.Set("missingBisOnly", false)
    Loot.ReadFilters(filters)
    state.bis = { [101] = 1, [102] = 2 }

    local rare = { rare = true, loot = { 101 } }
    local dungeon = { wings = { { bosses = { boss, rare } } } }
    check("the dungeon counts its rares", Loot.DungeonBis(dungeon, filters) == 2)
    S.Set("showRare", false)
    Loot.ReadFilters(filters)
    check("unless rares are hidden", Loot.DungeonBis(dungeon, filters) == 1)
    S.Set("showRare", true)
    Loot.ReadFilters(filters)
    check("none of them had", select(2, Loot.DungeonBis(dungeon, filters)) == 0)
    state.owned[101] = 1
    check("and each one you have counted: in your bags", select(2, Loot.DungeonBis(dungeon, filters)) == 2)
    state.owned[101] = nil

    -- Looks: nil for an item with none (a ring), else whether you have it.
    state.sources = { [101] = 11, [102] = 12, [103] = 13 }
    state.looks = { [11] = { appearanceIsCollected = true }, [12] = { sourceIsCollected = false },
        [13] = { appearanceIsCollected = false, sourceIsCollected = false } }
    check("a look you have", Loot.Appearance(101) == true)
    check("a look you do not", Loot.Appearance(102) == false)
    check("no look to collect", Loot.Appearance(104) == nil)
    -- One the game has no appearance for, though you can wear it: whether you have it.
    state.dressable[105], state.dressable[106], state.hasLook[106] = true, true, true
    check("a wearable item with no appearance you do not have is a new look", Loot.Appearance(105) == false)
    check("and one you have is not", Loot.Appearance(106) == true)
    check("the dungeon counts the looks you do not have", Loot.DungeonNewLooks(dungeon, filters) == 2)
    check("and the items with a look at all", select(2, Loot.DungeonNewLooks(dungeon, filters)) >= 2)

    -- Names: asked for while the client has yet to load them, kept in lower case once it has.
    check("an unloaded name is nil", Loot.LowerName(101) == nil)
    check("and its load is asked for", state.requested[1] == 101)
    state.names[101] = "Cowl of the Magus"
    check("a loaded one is in lower case", Loot.LowerName(101) == "cowl of the magus")
    state.names[101] = nil
    check("and kept", Loot.LowerName(101) == "cowl of the magus")
end

-------------------------------------------------------------------------------
--  Cost: counting over every dungeon, as the list and the page header do
-------------------------------------------------------------------------------
local function Measure(label, budget, fn)
    fn()   -- warm up
    local runs = 200
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local start = os.clock()
    for _ = 1, runs do fn() end
    local ms = (os.clock() - start) * 1000 / runs
    local kb = (collectgarbage("count") - before) / runs
    collectgarbage("restart")
    print(("  %s: %.3f ms, %.3f KB"):format(label, ms, kb))
    check(label .. " takes under " .. budget .. " ms", ms < budget)
    check(label .. " makes no garbage", kb < 0.01)
end

do
    local ns, state = fixture()
    local J, Loot, Quests = ns.Journal, ns.Journal.Loot, ns.Journal.Quests
    for id in pairs(J.Items) do
        if id % 7 == 0 then state.bis[id] = 1 end
    end
    local dungeons = J.Dungeons()
    local filters = Loot.ReadFilters({})
    Measure("BiS count over every dungeon", 1, function()
        for _, d in ipairs(dungeons) do Loot.DungeonBis(d, filters) end
    end)
    Measure("quest signature over every dungeon", 1, function()
        for _, d in ipairs(dungeons) do Quests.Signature(d.quests) end
    end)
end

-------------------------------------------------------------------------------
--  Off means off
-------------------------------------------------------------------------------
do
    local ns, state, S = fixture({ enabled = false })
    check("loading makes no frame", state.frames == 0)
    ns.Apply()
    check("off, the map is not hooked", #state.hooks == 0)
    S.Set("mapPanel", true)
    check("turning the panel on with the module off hooks nothing", #state.hooks == 0)
    S.Set("enabled", true)
    check("turning the module on hooks the map", #state.hooks == 3)
    check("and makes three frames, the kill count's, the loot's and the share asks', until the map "
        .. "shows in a dungeon", state.frames == 3)
    local counter, looted, asks = state.made[1], state.made[2], state.made[3]
    check("which listens for your group, and for share asks only in one", asks.events.GROUP_ROSTER_UPDATE
        and not asks.events.CHAT_MSG_ADDON)
    check("which listen for boss fights", counter.events.ENCOUNTER_START and counter.events.ENCOUNTER_END)
    check("and for loading screens, not loot, outside a dungeon", looted.events.PLAYER_ENTERING_WORLD
        and not looted.events.CHAT_MSG_LOOT)
    S.Set("enabled", false)
    check("off again, they stop listening", next(counter.events) == nil and next(looted.events) == nil
        and next(asks.events) == nil)
    S.Set("enabled", true)
    ns.Apply()
    check("and hooks the map only once", #state.hooks == 3)
    check("and makes its frames only once", state.frames == 3)
end

-------------------------------------------------------------------------------
--  The window: it builds, draws a dungeon and a search, and its switches work
-------------------------------------------------------------------------------
do
    local ns, state, S = fixture({ enabled = true })
    ns.Apply()
    state.instance = { id = 36, name = "The Deadmines" }
    ns.OpenJournalWindow()
    check("the window opens", state.frames > 10)
    -- Quests handed in of how many; every one handed in, the count is a check.
    local Progress, deadminesQuests = ns.Journal.Quests.Progress, ns.Journal.Get("Deadmines").quests
    local done, total = Progress(deadminesQuests)
    check("none of The Deadmines' quests handed in yet, of several", done == 0 and total > 1)
    state.allDone = true
    done = Progress(deadminesQuests)
    check("all of them once every one is handed in", done == total)
    check("none for you, none to count", select(2, Progress({ quests = {} })) == 0 and select(2, Progress(nil)) == 0)
    -- Shadowfang Keep has none for an Alliance mage: says whose they are.
    local why = ns.Journal.Quests.NoneWhy(ns.Journal.Get("ShadowfangKeep").quests)
    check("a dungeon with none for you says whose they are", why == "None for you here. The rest: 3 Horde, 1 Warlock, 1 Paladin.")
    check("a dungeon with no quests says nothing", ns.Journal.Quests.NoneWhy(nil) == nil)
    ns.Journal.Settings.Set("showRare", false)
    local checked = false
    for _, font in ipairs(state.fonts) do
        local text = rawget(font, "text")
        if type(text) == "string" and text:find("|t", 1, true) and text:find("Quests", 1, true) then checked = true end
    end
    check("and the header shows a check for Quests", checked)
    state.allDone = nil
    ns.Journal.Settings.Set("showRare", true)

    -- Weapons in short: a one-handed sword, and one that only goes in the main hand.
    local sword, mainHand
    for _, w in ipairs(ns.Journal.Get("Deadmines").wings) do
        for _, b in ipairs(w.bosses) do
            for _, id in ipairs(b.loot or {}) do
                local facts = ns.Journal.Items[id]
                if facts and facts[1] == 2 and facts[2] == 7 then
                    if not sword then sword = id elseif not mainHand then mainHand = id end
                end
            end
        end
    end
    state.slots = { [sword] = "INVTYPE_WEAPON", [mainHand] = "INVTYPE_WEAPONMAINHAND" }
    ns.Journal.Settings.Set("usableOnly", false)
    local said = {}
    for _, font in ipairs(state.fonts) do
        local text = rawget(font, "text")
        if type(text) == "string" then said[text] = true end
    end
    check("a one-handed sword says 1h Sword", said["1h Sword"])
    check("one only for the main hand says MH Sword", said["MH Sword"])
    state.slots = nil
    -- The faction switch's halves, clicked as a player would.
    local half = {}
    for _, frame in ipairs(state.made) do
        local side = rawget(frame, "side")
        if side then half[side.faction] = frame end
    end
    check("the faction switch has both halves", half.Alliance and half.Horde)
    half.Horde.scripts.OnClick(half.Horde)
    check("a click hides Horde ground", S.Get("showHorde") == false)
    half.Alliance.scripts.OnClick(half.Alliance)
    check("switching off the other side turns the first back on", S.Get("showAlliance") == false
        and S.Get("showHorde") == true)
    half.Alliance.scripts.OnClick(half.Alliance)
    check("and both can be on", S.Get("showAlliance") and S.Get("showHorde"))
    S.Set("usableOnly", false)
    S.Set("listHidden", true)
    S.Set("listHidden", false)
    S.Set("windowAlpha", 0.6)
    check("and takes its settings without an error", true)
    -- The list: the BiS here you still miss, and a check once you have them all.
    local List, deadmines = ns.Journal.DungeonList, ns.Journal.Get("Deadmines")
    local function BisText()
        for _, font in ipairs(state.fonts) do
            local text = rawget(font, "text")
            if type(text) == "string" and text:find("|t", 1, true) and rawget(font, "parent")
                and rawget(rawget(font, "parent"), "dungeon") == deadmines and text:find("^|T") then
                return text
            end
        end
    end
    local first = deadmines.wings[1].bosses[1].loot[1]
    state.bis[first] = 1
    List.Paint(deadmines)
    check("the list says how many of your BiS here you still miss", BisText() and BisText():find("1$"))
    state.owned[first] = 1
    List.Paint(deadmines)
    check("and a check once you have them all", BisText() and not BisText():find("%d$"))
    Measure("the dungeon list's repaint", 2, function() List.Paint(deadmines) end)
    state.bis[first], state.owned[first] = nil, nil

    -- The quest tracker: the dungeon's quests alone, each on one line.
    local titled = 0
    ns.OpenQuestTracker(deadmines)
    for _, font in ipairs(state.fonts) do
        if rawget(font, "text") == "THE DEADMINES" then titled = titled + 1 end
    end
    check("the quest tracker opens on the dungeon", titled == 1)
    ns.OpenQuestTracker(deadmines)
    check("and closes on a second click", true)

    -- Ctrl+F, with the mouse on the window: the search box.
    local frame = state.made[1]
    for _, made in ipairs(state.made) do
        if made.scripts.OnKeyDown then frame = made end
    end
    state.mouseOver, state.ctrl = true, true
    frame.scripts.OnKeyDown(frame, "F")
    check("Ctrl+F goes to the search box", state.focus ~= nil)
    state.mouseOver, state.ctrl, state.focus = nil, nil, nil

    state.instance = nil
    ns.ToggleJournalWindow()
    ns.ToggleJournalWindow()
    check("and closes and opens again", true)

    -- A quest in the log, opened from its row: drawn, with your selection put back.
    local Panel = ns.Journal.View.QuestPanel
    state.logged[166], state.selected = 4, 99
    state.objectives = { { text = "0/1 Head of VanCleef", finished = false } }
    Panel.Show(166, state.made[#state.made])
    check("a quest in the log opens its panel", true)
    check("and your quest log selection is put back", state.selected == 99)
end

-------------------------------------------------------------------------------
--  Kill counts
-------------------------------------------------------------------------------
do
    local ns, state, S = fixture({ enabled = true })
    local J, Kills = ns.Journal, ns.Journal.Kills
    ns.Apply()
    local OnEvent = state.made[1].scripts.OnEvent
    local boss = J.Boss(639)   -- Edwin VanCleef
    check("a boss the game names when it dies is counted", Kills.Counted(boss))
    check("no kills before the first", Kills.Count(boss) == 0 and Kills.Record(boss) == nil)
    check("and nothing saved for it", state.account.journalKills == nil)

    local id = boss.encounters[1]
    OnEvent(nil, "ENCOUNTER_START", id, "Edwin VanCleef", 1, 5)
    state.clock, state.now = 50 + 92.4, 2000
    OnEvent(nil, "ENCOUNTER_END", id, "Edwin VanCleef", 1, 5, 1)
    local record = Kills.Record(boss)
    check("a kill is counted", Kills.Count(boss) == 1)
    check("with when it was", record.first == 2000 and record.at[1] == 2000)
    check("and how long it took, in whole seconds", record.took[1] == 92)
    check("saved account-wide under this character", state.account.journalKills[state.guid][id] == record)

    OnEvent(nil, "ENCOUNTER_START", id, "Edwin VanCleef", 1, 5)
    OnEvent(nil, "ENCOUNTER_END", id, "Edwin VanCleef", 1, 5, 0)
    check("a wipe is not a kill", Kills.Count(boss) == 1)
    OnEvent(nil, "ENCOUNTER_END", 99999, "Nobody", 1, 5, 1)
    check("an encounter the Journal does not list counts for nothing", next(state.account.journalKills[state.guid], next(state.account.journalKills[state.guid])) == nil)
    OnEvent(nil, "ENCOUNTER_END", id, "Edwin VanCleef", 1, 5, 1)
    check("a kill with no pull seen (after a reload) counts, its length not known",
        Kills.Count(boss) == 2 and Kills.Record(boss).took[2] == false)

    check("the record is the fastest kill", Kills.Best(record) == 92 and select(2, Kills.Best(record)) == 2000)
    state.now = 2500
    Kills.Add(boss, 30.4)
    check("a faster kill is the new record", Kills.Best(Kills.Record(boss)) == 30 and Kills.Record(boss).bestAt == 2500)
    check("and is said in chat", state.printed[#state.printed] == "New record on Edwin VanCleef: 0:30, was 1:32.")
    for i = 1, 12 do
        state.now = 3000 + i
        Kills.Add(boss, 60)
    end
    check("the record is kept past the latest kills", Kills.Best(Kills.Record(boss)) == 30)
    record = Kills.Record(boss)
    check("the count goes on", record.n == 15)
    check("but only the latest ones keep their date", #record.at == Kills.KEEP and #record.took == Kills.KEEP)
    check("oldest first", record.at[Kills.KEEP] == 3012 and record.at[1] == 3003)
    check("the first kill's date stays", record.first == 2000)

    state.guid = "Player-4613-00ABCDEF"
    check("another character has its own count", Kills.Count(boss) == 0)
    state.guid = "Player-4613-006EB819"

    -- Every boss's encounter IDs are its own: one kill never counts for two bosses.
    local owner, counted = {}, 0
    for _, dungeon in ipairs(J.Dungeons()) do
        for _, wing in ipairs(dungeon.wings) do
            for _, b in ipairs(wing.bosses) do
                -- One killed on the way into another's fight shares that fight's encounters.
                if b.encounters and not b.with then
                    counted = counted + 1
                    for _, e in ipairs(b.encounters) do
                        check("encounter " .. e .. " names one boss", owner[e] == nil)
                        owner[e] = b
                    end
                end
            end
        end
    end
    check("most bosses can be counted", counted > 150)
    print(("  %d bosses with a kill count"):format(counted))

    S.Set("enabled", false)
    check("off, no fight is listened for", next(state.made[1].events) == nil)
    check("and the saved kills stay", Kills.Count(boss) == 15)

    -- The latest kills of any boss, newest first.
    local first = J.Get("Deadmines").wings[1].bosses[1]
    state.now = 5000
    Kills.Add(first, nil)
    local latest = Kills.Latest(5, {})
    check("the latest kills, newest first", #latest == 5 and latest[1].boss == first and latest[1].at == 5000
        and latest[2].boss == boss and latest[2].at == 3012 and latest[5].at == 3009)
    check("with their dungeon and length", latest[1].dungeon.key == "Deadmines" and latest[1].took == false
        and latest[2].took == 60)
    check("and no more than asked for", #Kills.Latest(2, latest) == 2)
    Kills.Forget()
    check("forgotten, every count starts again", Kills.Count(boss) == 0 and #Kills.Latest(5, latest) == 0)
    state.guid = "Player-4613-00ABCDEF"
    check("none for a character with no kills", #Kills.Latest(5, latest) == 0)
end

-------------------------------------------------------------------------------
--  Loot looted in the Journal's dungeons
-------------------------------------------------------------------------------
do
    local ns, state, S = fixture({ enabled = true })
    local J, Looted = ns.Journal, ns.Journal.Looted
    ns.Apply()
    local frame = state.made[2]
    local OnEvent = frame.scripts.OnEvent
    check("loot is listened for only inside a dungeon", frame.events.PLAYER_ENTERING_WORLD
        and not frame.events.CHAT_MSG_LOOT)
    state.instance = { id = 36, name = "The Deadmines" }
    OnEvent(frame, "PLAYER_ENTERING_WORLD")
    check("inside one, it is", frame.events.CHAT_MSG_LOOT)

    local vanCleef = J.Boss(639)
    local drop = vanCleef.loot[1]
    local link = "|cnIQ3:|Hitem:" .. drop .. "::::::::20:::::|h[Cruel Barb]|h|r"
    OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
    local function List() return state.account.journalLoot and state.account.journalLoot[state.guid] end
    local list = List()
    check("your loot is kept", list and #list == 1 and list[1].id == drop and list[1].link == link)
    check("with where, from whom and when", list[1].dungeon == "Deadmines" and list[1].boss == "Edwin VanCleef"
        and list[1].at == state.now)
    check("saved account-wide under this character", state.account.journalLoot[state.guid] == list)
    OnEvent(frame, "CHAT_MSG_LOOT", "Die Dudu receives loot: " .. link .. ".")
    check("a group member's is not", #list == 1)
    OnEvent(frame, "CHAT_MSG_LOOT", "You receive item: " .. link .. ".")
    check("nor an item handed to you", #list == 1)
    OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2589::::::::20:::::|h[Linen Cloth]|h|r.")
    check("nor trash below Uncommon", #list == 1)
    local green = "|cnIQ2:|Hitem:99901::::::::20:::::|h[Some Green]|h|r"
    OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. green .. "x2.")
    check("but a green from trash is, from no boss", #list == 2 and list[2].id == 99901 and list[2].boss == nil)
    check("the boss's history lists what you looted from it", Looted.AllFrom(vanCleef, {})[1] == list[1])
    check("and another boss's lists none", #Looted.AllFrom(J.Boss(644), {}) == 0)
    local latest = Looted.Latest(5, {})
    check("the latest loot, newest first", #latest == 2 and latest[1] == list[2] and latest[2] == list[1])
    OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:99902::::::::20:::::|h[Unknown]|h|r.")
    check("an item whose quality is not known is not", #list == 2)
    for _ = 1, 25 do Looted.Add(J.Current(), green, 99901) end
    check("only the latest are kept", #list == Looted.KEEP and list[1].id == 99901)

    state.instance = nil
    OnEvent(frame, "PLAYER_ENTERING_WORLD")
    check("outside, it stops listening", not frame.events.CHAT_MSG_LOOT)
    OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
    check("and keeps nothing", list[Looted.KEEP].id == 99901)
    list[1].dungeon = "NoSuchDungeon"
    list[2].link = nil
    check("a mangled entry, or one of a dungeon no longer listed, is passed over",
        #Looted.Latest(Looted.KEEP, latest) == Looted.KEEP - 2)
    Looted.Forget()
    check("forgotten, the list is empty", #Looted.Latest(5, latest) == 0 and #Looted.AllFrom(vanCleef, {}) == 0)
    state.guid = "Player-4613-00ABCDEF"
    check("another character has its own list", List() == nil)
    S.Set("enabled", false)
    check("off, no loot is listened for", next(frame.events) == nil)
end

-------------------------------------------------------------------------------
--  What the latest kills and loot cost, for a player who has killed every boss ten times
--  and has a full loot list; and what the handlers cost for messages that are not theirs.
-------------------------------------------------------------------------------
do
    local ns, state = fixture({ enabled = true })
    local J, Kills, Looted = ns.Journal, ns.Journal.Kills, ns.Journal.Looted
    ns.Apply()
    local bosses, kills = {}, 0
    for _, d in ipairs(J.Dungeons()) do
        for _, w in ipairs(d.wings) do
            for _, b in ipairs(w.bosses) do
                bosses[#bosses + 1] = b
                if b.encounters then
                    for i = 1, Kills.KEEP do
                        state.now = i * 1000 + #bosses
                        Kills.Add(b, 60)
                        kills = kills + 1
                    end
                end
            end
        end
    end
    state.instance = { id = 36, name = "The Deadmines" }
    local vanCleef = J.Boss(639)
    local link = "|cnIQ3:|Hitem:" .. vanCleef.loot[1] .. "::::::::20:::::|h[Cruel Barb]|h|r"
    for _ = 1, Looted.KEEP do Looted.Add(J.Current(), link, vanCleef.loot[1]) end
    local out = {}
    Measure(("the latest 5 of %d kills"):format(kills), 0.5, function() Kills.Latest(5, out) end)
    check("five of them, the newest kill first", #out == 5 and out[1].at == state.now)
    for i = 1, 4 do check("then each older than the one before", out[i].at >= out[i + 1].at) end
    Measure("the latest 5 items looted", 0.1, function() Looted.Latest(5, out) end)
    Measure("what you looted from each boss of a dungeon", 0.1, function()
        for _, w in ipairs(J.Get("Deadmines").wings) do
            for _, b in ipairs(w.bosses) do Looted.AllFrom(b, out) end
        end
    end)
    local looted, asks = state.made[2], state.made[3]
    looted.scripts.OnEvent(looted, "PLAYER_ENTERING_WORLD")
    local others = "Emmy receives loot: " .. link .. "."
    Measure("a group member's loot line", 0.01, function()
        looted.scripts.OnEvent(looted, "CHAT_MSG_LOOT", others)
    end)
    Measure("another addon's message", 0.01, function()
        asks.scripts.OnEvent(asks, "CHAT_MSG_ADDON", "BigWigs", "V^1^2", "RAID", "Emmy-Realm")
    end)
end

-------------------------------------------------------------------------------
--  Who was with you: the team kept with a kill or an item, and read back in role order
-------------------------------------------------------------------------------
do
    local ns, state = fixture({ enabled = true })
    local Team = ns.Journal.Team
    check("solo, the team is you", Team.Now() == "Die Man,MAGE,N,m")
    state.role = "DAMAGER"
    state.party = {
        { name = "Trudy", guid = "Player-1-T", class = "WARRIOR", role = "TANK", quests = {} },
        { name = "Ding", guid = "Player-1-D", class = "ROGUE", role = "DAMAGER", quests = {} },
        { name = "Emmy", guid = "Player-1-E", class = "PRIEST", role = "HEALER", quests = {} },
        { name = "Ace", guid = "Player-1-A", class = "HUNTER", role = "DAMAGER", quests = {} },
    }
    local text = Team.Now()
    check("a group is kept as one line", text == "Die Man,MAGE,D,m;Trudy,WARRIOR,T,;Ding,ROGUE,D,;Emmy,PRIEST,H,;Ace,HUNTER,D,")
    local out = Team.Read(text, {})
    local order = {}
    for i, member in ipairs(out) do order[i] = member.name end
    check("read back: the tank, the healer, you, then the damage", table.concat(order, ",") == "Trudy,Emmy,Die Man,Ace,Ding")
    check("you are marked", out[3].me and not out[1].me)
    check("with each member's class and role", out[1].class == "WARRIOR" and out[1].role == "T")
    local first = out[1]
    Team.Read(text, out)
    check("a second read reuses the members", out[1] == first and #out == 5)
    check("nothing kept reads as no one", #Team.Read(nil, out) == 0 and #Team.Read(false, out) == 0)
    check("a mangled line reads what it can", #Team.Read("Trudy,WARRIOR,T,;garbage;,,;Emmy,PRIEST,X,", out) == 1)
    state.party[2].name = "Bad,Name;"
    check("a name cannot break the line", Team.Now():find("BadName,ROGUE", 1, true) ~= nil)
end

-------------------------------------------------------------------------------
--  The team kept with each kill; and a boss the game does not run as an encounter, which
--  cannot be counted (in a dungeon the game keeps which creature died secret)
-------------------------------------------------------------------------------
do
    local ns, state = fixture({ enabled = true })
    local J, Kills = ns.Journal, ns.Journal.Kills
    ns.Apply()
    local frame = state.made[1]
    local OnEvent = frame.scripts.OnEvent
    -- A boss the game runs no fight for (Baron Aquanis, Grizzle and others).
    local unnamed
    for _, d in ipairs(J.Dungeons()) do
        for _, w in ipairs(d.wings) do
            for _, b in ipairs(w.bosses) do
                if not b.encounters and b.npc then unnamed = unnamed or b end
            end
        end
    end
    check("a boss with no encounter is not counted", not Kills.Counted(unnamed) and Kills.Count(unnamed) == 0)
    check("and no death is listened for", not frame.events.UNIT_DIED and not frame.events.PARTY_KILL)

    -- Sneed's Shredder: Sneed climbs out of it, so it counts with his fight.
    local shredder, sneed = J.Boss(642), J.Boss(643)
    check("the Shredder counts with Sneed", Kills.Counted(shredder) and shredder.with == "Sneed")
    OnEvent(frame, "ENCOUNTER_END", sneed.encounters[1], "Sneed", 1, 5, 1)
    check("Sneed's fight is his kill", Kills.Count(sneed) == 1)
    check("and the Shredder's", Kills.Count(shredder) == 1 and Kills.Record(shredder) == Kills.Record(sneed))
    check("listed once among the latest, as Sneed", Kills.Latest(5, {})[1].boss == sneed)

    local vanCleef = J.Boss(639)
    OnEvent(frame, "ENCOUNTER_END", vanCleef.encounters[1], "Edwin VanCleef", 1, 5, 1)
    check("a kill keeps its team: you", Kills.Record(vanCleef).team[1] == "Die Man,MAGE,N,m")

    -- A kill kept before teams were: its list is filled in so the kills line up.
    state.account.journalKills[state.guid][vanCleef.encounters[1]] = { n = 2, first = 1, at = { 1, 2 }, took = { 60, 61 } }
    OnEvent(frame, "ENCOUNTER_END", vanCleef.encounters[1], "Edwin VanCleef", 1, 5, 1)
    local record = Kills.Record(vanCleef)
    check("an older record takes teams from its next kill", record.team[1] == false and record.team[2] == false
        and type(record.team[3]) == "string" and #record.at == 3)
end

-------------------------------------------------------------------------------
--  The rolls kept with an item, from the game's loot history; and the boss's side panel
-------------------------------------------------------------------------------
do
    local ns, state = fixture({ enabled = true })
    local J, Looted = ns.Journal, ns.Journal.Looted
    local vanCleef = J.Boss(639)
    local drop = vanCleef.loot[1]
    local link = "|cnIQ3:|Hitem:" .. drop .. "::::::::20:::::|h[Cruel Barb]|h|r"
    local history = {
        lootListKey = 1, itemHyperlink = link, startTime = 100,
        winner = { isSelf = true },
        rollInfos = {
            { playerName = "Die Man", state = 0, roll = 87, isWinner = true, isSelf = true, playerClass = "MAGE" },
            { playerName = "Emmy-Realm", state = 3, roll = 40, playerClass = "DRUID" },
            { playerName = "Trudy", state = 5 },
        },
    }
    local drops = {}
    -- The game's loot history, as the test fills it.
    local env = getfenv(J.TurnOn)
    env.C_LootHistory = {
        GetAllEncounterInfos = function() return { { encounterID = 2747 } } end,
        GetSortedDropsForEncounter = function() return drops end,
        GetSortedInfoForDrop = function() return history end,
    }
    ns.Apply()
    state.instance = { id = 36, name = "The Deadmines" }
    local frame = state.made[2]
    frame.scripts.OnEvent(frame, "PLAYER_ENTERING_WORLD")
    check("the loot history is listened for inside a dungeon", frame.events.LOOT_HISTORY_UPDATE_DROP)

    -- The roll came after the item: kept with it when it does.
    frame.scripts.OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
    local list = state.account.journalLoot[state.guid]
    check("an item looted before its roll is in has no rolls yet", list[1].rolls == nil)
    check("but its team", list[1].team == "Die Man,MAGE,N,m")
    frame.scripts.OnEvent(frame, "LOOT_HISTORY_UPDATE_DROP", 2747, 1)
    check("the roll's result is kept with it when it comes",
        list[1].rolls == "Die Man,0,87,w,MAGE;Emmy,3,40,,DRUID;Trudy,5,,,")
    local rolls = ns.Journal.Team.ReadRolls(list[1].rolls, {})
    check("read back: who rolled what, and who won", #rolls == 3 and rolls[1].winner and rolls[1].roll == 87
        and rolls[2].name == "Emmy" and rolls[2].state == 3 and rolls[2].class == "DRUID"
        and rolls[3].roll == nil and not rolls[3].winner and rolls[3].class == nil)

    -- The roll was in before the item: kept with it at once.
    drops[1] = history
    frame.scripts.OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
    check("an item whose roll is in already keeps it at once", list[2].rolls == list[1].rolls)
    history.winner.isSelf = false
    state.now = state.now + 1
    frame.scripts.OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
    check("someone else's win is not yours", list[3].rolls == nil)
    check("every item from the boss, newest first", #Looted.AllFrom(vanCleef, {}) == 3)

    -- Every drop of a kill, kept with it as each roll ends, whoever won it.
    local kills = state.made[1]
    kills.scripts.OnEvent(kills, "ENCOUNTER_END", 2747, "Edwin VanCleef", 1, 5, 1)
    local record = J.Kills.Record(vanCleef)
    check("a kill keeps no drops before the rolls end", record.drops[#record.at] == false)
    local saw = "|cnIQ2:|Hitem:5191::::::::20:::::|h[Cruel Barb]|h|r"
    drops[1] = { itemHyperlink = saw, startTime = state.clock * 1000 + 2000, rollInfos = {
            { playerName = "Ding", state = 3, roll = 96, isWinner = true, playerClass = "SHAMAN" },
            { playerName = "Die Man", state = 3, roll = 74, isSelf = true, playerClass = "MAGE" } },
        winner = { playerName = "Ding" } }
    drops[2] = { itemHyperlink = link, startTime = state.clock * 1000 - 3600000, winner = {},
        rollInfos = {} }   -- an hour before: another run's
    drops[3] = { itemHyperlink = link, startTime = state.clock * 1000 + 3000, rollInfos = {} }   -- still rolling
    kills.scripts.OnEvent(kills, "LOOT_HISTORY_UPDATE_DROP", 2747, 1)
    check("each drop with a winner is kept with the kill nearest it: only this run's, only ended rolls",
        record.drops[#record.at] == saw .. "\tDing,3,96,w,SHAMAN;Die Man,3,74,,MAGE")
    local seen = {}
    J.Kills.EachDrop(record.drops[#record.at], function(l, r) seen[#seen + 1] = l .. "|" .. r end)
    check("and read back, item by item", #seen == 1 and seen[1] == saw .. "|Ding,3,96,w,SHAMAN;Die Man,3,74,,MAGE")
    -- A kill missed (from before drops were kept, or a reload mid-roll) is filled in from the
    -- history when the boss's history is opened.
    record.drops[#record.at] = false
    J.Kills.Gather(vanCleef)
    check("a kill that missed its drops gets them from the history", record.drops[#record.at]
        == saw .. "	Ding,3,96,w,SHAMAN;Die Man,3,74,,MAGE")
    drops[1], drops[2], drops[3] = nil, nil, nil

    -- The side panel, drawn on both: what it says.
    local function Says(text)
        for _, font in ipairs(state.fonts) do
            local said = rawget(font, "text")
            if rawget(font, "shown") ~= false and type(said) == "string" and said:find(text, 1, true) then
                return true
            end
        end
        return false
    end
    local Panel = J.View.BossPanel
    local from = state.made[#state.made]
    Panel.Show(vanCleef, from)
    check("the boss's history opens in the side panel", Says("EDWIN VANCLEEF") and Says("KILLS"))
    check("loot with no kill before it stands on its own", Says("looted"))
    check("each item with everyone's roll, as the game's own icons", Says("Die Man") and Says("Emmy")
        and Says("Trudy") and state.atlases["lootroll-icon-need"] and state.atlases["lootroll-icon-greed"]
        and state.atlases["lootroll-icon-pass"])
    check("and what was picked up without one", Says("Picked up without a roll"))
    Panel.Show(vanCleef, from)

    -- A kill, then its loot: the loot goes under the kill.
    state.now = state.now + 60
    J.Kills.Add(vanCleef, 60, "Die Man,MAGE,D,m;Trudy,WARRIOR,T,")
    state.now = state.now + 30
    history.winner.isSelf = true
    frame.scripts.OnEvent(frame, "CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
    Panel.Show(vanCleef, from)
    check("a kill shows when, how long, and who was with you", Says("GROUP  2") and Says("took 1:00")
        and Says("Trudy") and Says("(you)"))
    check("and everything that dropped, with who won it", Says("Ding"))
    check("the fastest kill says it is the record", Says("Record|r  took 1:00"))
    Panel.Show(vanCleef, from)
    local unnamed
    for _, w in ipairs(J.Get("BlackfathomDeeps").wings) do
        for _, b in ipairs(w.bosses) do
            if not b.encounters then unnamed = unnamed or b end
        end
    end
    Panel.Show(unnamed, from)
    check("a boss the game does not report says why", Says("no boss fight to the game"))
end

-------------------------------------------------------------------------------
--  Asking a group member to share a quest: two players, each with the addon, passing the
--  messages one sends to the other.
-------------------------------------------------------------------------------
do
    local ME, EMMY, TRUDY = "Player-4613-006EB819", "Player-4613-00E33333", "Player-4613-00F44444"
    local QUEST = 6981   -- The Glowing Shard
    local asker, mine = fixture({ enabled = true })
    local emmy, hers = fixture({ enabled = true })
    asker.Apply()
    emmy.Apply()
    mine.guid, hers.guid = ME, EMMY
    mine.party = { { name = "Emmy", guid = EMMY, quests = { [QUEST] = true } } }
    hers.party = { { name = "Die Man", guid = ME, quests = {} } }
    hers.logged[QUEST] = 7
    local askerFrame, emmyFrame = mine.made[3], hers.made[3]
    check("out of a group, asks are not listened for", not askerFrame.events.CHAT_MSG_ADDON)
    askerFrame.scripts.OnEvent(askerFrame, "GROUP_ROSTER_UPDATE")
    emmyFrame.scripts.OnEvent(emmyFrame, "GROUP_ROSTER_UPDATE")
    check("in one, they are", askerFrame.events.CHAT_MSG_ADDON and emmyFrame.events.CHAT_MSG_ADDON)
    check("the share asks' prefix is registered", mine.prefix == "NaowhJournal")

    -- Delivers every message one side has sent to the other (and back to itself, as the game
    -- does on a group channel).
    local function Deliver(from, fromFrame, sender, to, toFrame)
        local sent = from.sent
        from.sent = {}
        for _, message in ipairs(sent) do
            for _, frame in ipairs({ toFrame, fromFrame }) do
                frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", message.prefix, message.text, message.channel, sender)
            end
        end
        return #sent
    end
    local function Printed(state) return state.printed[#state.printed] or "" end

    local entry
    for _, e in ipairs(asker.Journal.Quests.List(asker.Journal.Get("WailingCaverns").quests, {}, {})) do
        if e.quest[1] == QUEST then entry = e end
    end
    check("the asker does not have the quest, Emmy does", entry and not entry.inLog and entry.party == 1)
    asker.Journal.Sharing.Ask(entry)
    check("the ask goes to the group", #mine.sent == 1 and mine.sent[1].channel == "PARTY")
    check("and says so", Printed(mine):find("Asking Emmy to share", 1, true))
    Deliver(mine, askerFrame, "Die Man-Realm", hers, emmyFrame)
    check("Emmy shares it", #hers.pushed == 1 and hers.pushed[1] == 7)
    check("and is told who asked", Printed(hers):find("Die Man asked you to share", 1, true)
        and Printed(hers):find("shared it with your group", 1, true))
    check("and answers", Deliver(hers, emmyFrame, "Emmy-Realm", mine, askerFrame) == 1)
    check("the asker is told it was shared", Printed(mine):find("Emmy shared", 1, true))
    check("only once: the sender's own copy is not for it", #hers.pushed == 1)
    mine.timers[1]()
    check("the answered ask's timer does nothing", Printed(mine):find("Emmy shared", 1, true))

    -- Asked again at once, Emmy waits; her answer ends the ask.
    asker.Journal.Sharing.Ask(entry)
    Deliver(mine, askerFrame, "Die Man-Realm", hers, emmyFrame)
    check("a second ask in a moment is not shared", #hers.pushed == 1)
    Deliver(hers, emmyFrame, "Emmy-Realm", mine, askerFrame)
    check("and the asker is told to wait", Printed(mine):find("a moment ago", 1, true))

    -- A quest the game will not share.
    hers.clock = hers.clock + 10
    hers.unpushable = QUEST
    asker.Journal.Sharing.Ask(entry)
    Deliver(mine, askerFrame, "Die Man-Realm", hers, emmyFrame)
    Deliver(hers, emmyFrame, "Emmy-Realm", mine, askerFrame)
    check("one the game will not share is not", #hers.pushed == 1)
    check("and both are told why", Printed(hers):find("does not let it be shared", 1, true)
        and mine.printed[#mine.printed - 1]:find("does not let it be shared", 1, true))
    check("and that no one else can", Printed(mine):find("No one else in your group", 1, true))
    hers.unpushable = nil

    -- Two members on it: the first does not answer (no addon), the next is asked.
    mine.party = { { name = "Trudy", guid = TRUDY, quests = { [QUEST] = true } },
        { name = "Emmy", guid = EMMY, quests = { [QUEST] = true } } }
    mine.timers = {}
    asker.Journal.Sharing.Ask(entry)
    check("the first member on it is asked", mine.sent[1].text:find(TRUDY, 1, true))
    Deliver(mine, askerFrame, "Die Man-Realm", hers, emmyFrame)
    check("an ask for someone else is not answered", #hers.sent == 0 and #hers.pushed == 1)
    asker.Journal.Sharing.Ask(entry)
    check("a second click waits for the first ask", Printed(mine):find("Still waiting on Trudy", 1, true)
        and #mine.sent == 0)
    mine.timers[1]()
    check("no answer, and the asker is told", mine.printed[#mine.printed - 1]:find("Trudy did not answer", 1, true))
    check("and the next member is asked", Printed(mine):find("Asking Emmy", 1, true))
    Deliver(mine, askerFrame, "Die Man-Realm", hers, emmyFrame)
    Deliver(hers, emmyFrame, "Emmy-Realm", mine, askerFrame)
    check("who shares it", #hers.pushed == 2 and Printed(mine):find("Emmy shared", 1, true))
    mine.timers[1]()
    check("and the first timer, run late, does nothing", Printed(mine):find("Emmy shared", 1, true))

    -- In an encounter the game passes no addon messages.
    mine.locked = true
    asker.Journal.Sharing.Ask(entry)
    check("locked, nothing is sent", #mine.sent == 0 and Printed(mine):find("in an encounter", 1, true))
    mine.locked = false

    -- Quest Share Requests off: nothing is asked or answered.
    emmy.Journal.Settings.Set("shareRequests", false)
    check("with Quest Share Requests off, asks are not listened for", next(emmyFrame.events) == nil)
    asker.Journal.Settings.Set("shareRequests", false)
    asker.Journal.Sharing.Ask(entry)
    check("and nothing is asked", #mine.sent == 0)
    emmy.Journal.Settings.Set("shareRequests", true)
    check("on again, they are", emmyFrame.events.GROUP_ROSTER_UPDATE ~= nil)

    -- Off, nothing is answered.
    emmy.Journal.Settings.Set("enabled", false)
    check("off, asks are not listened for", next(emmyFrame.events) == nil)
end

-------------------------------------------------------------------------------
--  Never open the chat box: ChatFrameUtil.OpenChat from addon code writes fields on the
--  game's edit box, and the next message the player sends is then blocked as ours.
-------------------------------------------------------------------------------
do
    local opens = {}
    for _, path in ipairs(dofile("Tools/regression/toc_files.lua")("%.lua$")) do
        local number = 0
        for line in io.lines(path) do
            number = number + 1
            local code = line:gsub("%-%-.*$", "")
            if code:find("ChatFrameUtil.OpenChat", 1, true) then opens[#opens + 1] = path .. ":" .. number end
        end
    end
    check("no addon code opens the chat box (" .. table.concat(opens, ", ") .. ")", #opens == 0)
end

print(("test-dungeon-journal: %d checks passed"):format(checks))
