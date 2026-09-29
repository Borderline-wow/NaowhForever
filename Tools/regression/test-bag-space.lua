-- Loads NaowhForever_BagSpace.lua against stubbed bag, item and frame APIs and checks what
-- the row offers, what the clicks do, stacking, and what a scan costs.
-- Run from the repo root: lua Tools/regression/test-bag-space.lua
local f = assert(io.open(arg[1] or "QoL/NaowhForever_BagSpace.lua", "rb"))
local source = f:read("*a"); f:close()

-- itemID -> name, quality, required level, max stack, vendor price, class
local ITEMS = {
    [1] = { "Small Egg", 1, 0, 20, 4, 7 },
    [2] = { "Coyote Meat", 1, 0, 20, 3, 7 },
    [3] = { "Light Feather", 1, 0, 20, 41, 7 },
    [4] = { "Chipped Boar Tusk", 0, 0, 5, 38, 15 },
    [5] = { "Flash Powder", 1, 0, 20, 1, 5 },          -- reagent: protected
    [6] = { "Quest Letter", 1, 0, 1, 1, 12 },          -- quest: protected
    [7] = { "Hearthstone", 1, 0, 1, 0, 15 },           -- no vendor price: never offered
    [8] = { "Blue Ring", 3, 0, 1, 900, 4 },            -- rare: above the quality limit
    [9] = { "Tough Jerky", 1, 5, 20, 1, 0 },           -- food ten or more levels below: old
    [10] = { "Linen Cloth", 1, 0, 20, 13, 7 },
    [11] = { "Green Belt", 2, 0, 1, 50, 4 },
}

local WHITE = { r = 1, g = 1, b = 1, hex = "|cffffffff" }

local function Fixture(opts)
    local settings = opts.settings or {}
    local defaults = {
        enabled = true, bagSpace = true, bagSpaceCount = 4, bagSpaceSize = 36,
        bagSpaceGrow = "RIGHT", bagSpaceMaxQuality = 2, bagSpaceJunkFirst = false,
        bagSpaceAuction = true, bagSpaceProtect = true, bagSpaceFreeBelow = 0,
        bagSpaceHideCombat = true, bagSpaceOnFull = true, bagSpaceShowFree = true,
        bagSpaceStack = true, bagSpaceOldFirst = false,
    }
    local db, printed, buttons = {}, {}, {}
    local bags = opts.bags                 -- bags[bag][slot] = { id, count } or nil
    local cursor, ctrl, now = nil, false, 1000
    local registered = {}
    local infoCache = {}                   -- one table per slot, as reused as the real API allows

    local S = {}
    function S.Get(k) if settings[k] ~= nil then return settings[k] end return defaults[k] end
    function S.Set(k, v) settings[k] = v end
    function S.DB() return db end

    -- Methods are made once and shared, so the stubs add no garbage to the cost measured below.
    local function Noop() end
    local noopMeta = { __index = function() return Noop end }
    local function Stub() return setmetatable({}, noopMeta) end
    local Widget
    local methods = setmetatable({
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, v) self.shown = v and true or false end,
        IsShown = function(self) return self.shown end,
        SetText = function(self, v) self.text = v end,
        GetStringWidth = function() return 20 end,
        SetTexture = function(self, v) self.texture = v end,
        SetScript = function(self, name, fn) self[name] = fn end,
        CreateTexture = function() return Widget("region") end,
        CreateFontString = function() return Widget("region") end,
        RegisterEvent = function(self, e) registered[e] = registered[e] or {}; registered[e][self] = true end,
        UnregisterEvent = function(self, e) if registered[e] then registered[e][self] = nil end end,
        UnregisterAllEvents = function(self) for _, set in pairs(registered) do set[self] = nil end end,
    }, noopMeta)
    local widgetMeta = { __index = methods }
    function Widget(kind)
        return setmetatable({ kind = kind, shown = true }, widgetMeta)
    end

    local ns = {
        THEME = { accent = { r = 0, g = 0.57, b = 0.93 }, muted = { r = 0.6, g = 0.6, b = 0.6 },
            fg = { r = 0.94, g = 0.95, b = 0.95 }, bg = { r = 0.05, g = 0.06, b = 0.07 },
            line = { r = 0.18, g = 0.19, b = 0.21 } },
        QoLSettings = S,
        Print = function(msg) printed[#printed + 1] = msg end,
        Apply = function() end,
        ShowRaidReminderAnchorConfig = function() end,
        HideRaidReminderAnchorConfig = function() end,
        IsBisItem = function(id) return opts.bis and opts.bis[id] end,
        AuctionPrice = function(id) return opts.ah and opts.ah[id] end,
        Font = function() return Widget("font") end,
        Solid = function() return Widget("texture") end,
        Button = function() return Widget("button") end,
        Confirm = function(_, onYes) onYes() end,
        UI = { AttachMover = function() return Widget("mover") end },
    }

    local function Item(bag, slot) return bags[bag] and bags[bag][slot] end
    local function Info(bag, slot)
        local it = Item(bag, slot)
        if not it then return nil end
        local key = bag * 100 + slot
        local t = infoCache[key] or {}
        infoCache[key] = t
        local def = ITEMS[it.id]
        t.itemID, t.stackCount, t.quality, t.iconFileID = it.id, it.count, def[2], it.id
        t.hyperlink, t.isLocked = "[" .. def[1] .. "]", false
        return t
    end
    local function Place(bag, slot)
        local it = Item(bag, slot)
        if not it then
            bags[bag][slot] = cursor
            cursor = nil
        elseif it.id == cursor.id then
            local room = ITEMS[it.id][4] - it.count
            local moved = math.min(room, cursor.count)
            it.count = it.count + moved
            cursor.count = cursor.count - moved
            if cursor.count == 0 then cursor = nil end
        else
            bags[bag][slot], cursor = cursor, it
        end
    end

    local env = {
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = #bags,
        ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return WHITE end }),
        ERR_INV_FULL = "Inventory is full.", ERR_BAG_FULL = "That bag is full.",
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        time = function() return now end,
        GetTime = function() return now end,
        UnitLevel = function() return opts.level or 20 end,
        UnitAffectingCombat = function() return false end,
        InCombatLockdown = function() return false end,
        IsControlKeyDown = function() return ctrl end,
        IsModifiedClick = function() return false end,
        GameTooltip = Stub(),
        GameTooltip_Hide = function() end,
        C_Timer = { After = function(_, fn) fn() end },
        C_Container = {
            GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].size or 0 end,
            GetContainerNumFreeSlots = function(bag)
                local n = 0
                for slot = 1, bags[bag].size do if not bags[bag][slot] then n = n + 1 end end
                return n, 0
            end,
            GetContainerItemInfo = Info,
            PickupContainerItem = function(bag, slot)
                if cursor then return Place(bag, slot) end
                cursor, bags[bag][slot] = bags[bag][slot], nil
            end,
            SplitContainerItem = function(bag, slot, amount)
                local it = bags[bag][slot]
                it.count = it.count - amount
                cursor = { id = it.id, count = amount }
            end,
            UseContainerItem = function(bag, slot) bags[bag][slot] = nil end,
        },
        C_Item = {
            GetItemInfo = function(id)
                local d = ITEMS[id]
                return d[1], nil, d[2], nil, d[3], nil, nil, d[4], nil, nil, d[5]
            end,
            GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, ITEMS[id][6] end,
        },
        C_QuestLog = {
            GetNumQuestLogEntries = function() return opts.quests and #opts.quests or 0 end,
            GetInfo = function(i) return { questID = i, title = opts.quests[i].title, isHeader = false } end,
            GetQuestObjectives = function(id) return opts.quests[id].objectives end,
        },
        GetCursorInfo = function() if cursor then return "item", cursor.id end end,
        ClearCursor = function() cursor = nil end,
        DeleteCursorItem = function() cursor = nil end,
        CreateFrame = function(kind, name)
            local w = Widget(kind)
            if kind == "Button" then buttons[#buttons + 1] = w end
            if name == "NaowhForeverBagSpace" then buttons.row = w end
            return w
        end,
        hooksecurefunc = function(tbl, key, fn)
            local orig = tbl[key]
            tbl[key] = function(...) orig(...); fn(...) end
        end,
    }
    env._G = { NaowhForever = ns }
    setmetatable(env, { __index = _G })
    local chunk
    if setfenv then
        chunk = assert(loadstring(source)); setfenv(chunk, env)
    else
        chunk = assert(load(source, "BagSpace", "t", env))
    end
    chunk()

    local t = { ns = ns, printed = printed, env = env }
    function t.Fire(event, ...)
        for frame in pairs(registered[event] or {}) do frame.OnEvent(frame, event, ...) end
    end
    -- What the row shows, left to right: item names, or "Stack" for the stack button.
    function t.Row()
        local out = {}
        if not (buttons.row and buttons.row.shown) then return "" end
        for _, b in ipairs(buttons) do
            if b.shown and b.pick then
                out[#out + 1] = b.pick.stack and "Stack" or ITEMS[b.pick.itemID][1]
            end
        end
        return table.concat(out, ", ")
    end
    function t.FreeText()
        return buttons.row and buttons.row.free and buttons.row.free.text.text
    end
    function t.Button(i)
        local n = 0
        for _, b in ipairs(buttons) do
            if b.shown and b.pick then
                n = n + 1
                if n == i then return b end
            end
        end
    end
    function t.Click(i, mouse, withCtrl)
        ctrl = withCtrl or false
        local b = t.Button(i)
        b.OnClick(b, mouse or "LeftButton")
        ctrl = false
    end
    function t.Count(id)
        local n = 0
        for bag = 0, #bags do
            for slot = 1, bags[bag].size do
                local it = bags[bag][slot]
                if it and it.id == id then n = n + it.count end
            end
        end
        return n
    end
    function t.Slots(id)
        local n = 0
        for bag = 0, #bags do
            for slot = 1, bags[bag].size do
                if bags[bag][slot] and bags[bag][slot].id == id then n = n + 1 end
            end
        end
        return n
    end
    t.db, t.Set = db, S.Set
    -- The world loads: the module builds and scans.
    for frame in pairs(registered.PLAYER_LOGIN or {}) do frame.OnEvent(frame, "PLAYER_LOGIN") end
    return t
end

local failures = 0
local function Check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(("FAIL %s\n  got:  %s\n  want: %s"):format(label, tostring(got), tostring(want)))
    end
end

local function Bag(size, items)
    local bag = { size = size }
    for slot, it in pairs(items) do bag[slot] = { id = it[1], count = it[2] } end
    return bag
end

-- Cheapest stack first; protected, priceless and too-good items never offered.
do
    local t = Fixture({ bags = { [0] = Bag(16, {
        { 3, 2 }, { 1, 3 }, { 2, 11 }, { 4, 2 }, { 5, 10 }, { 6, 1 }, { 7, 1 }, { 8, 1 },
    }) } })
    Check("cheapest stack first", t.Row(), "Small Egg, Coyote Meat, Chipped Boar Tusk, Light Feather")
    Check("counter reads free out of total", t.FreeText(), "8/16")
end

-- Grey Items First puts the tusk ahead of everything.
do
    local t = Fixture({ settings = { bagSpaceJunkFirst = true },
        bags = { [0] = Bag(16, { { 3, 2 }, { 1, 3 }, { 4, 2 } }) } })
    Check("grey first", t.Row(), "Chipped Boar Tusk, Small Egg, Light Feather")
end

-- An auction price above the vendor price values the stack at the auction price.
do
    local t = Fixture({ ah = { [1] = 500 }, bags = { [0] = Bag(16, { { 1, 3 }, { 2, 11 } }) } })
    Check("auction value counts", t.Row(), "Coyote Meat, Small Egg")
end

-- BiS items are protected; outlevelled food is marked old and can go first.
do
    local t = Fixture({ bis = { [2] = true }, settings = { bagSpaceOldFirst = true },
        bags = { [0] = Bag(16, { { 1, 3 }, { 2, 11 }, { 9, 20 } }) } })
    Check("BiS protected, old food first", t.Row(), "Tough Jerky, Small Egg")
    Check("old flag", t.Button(1).pick.old, true)
end

-- Ctrl-click deletes; middle-click ignores with the time it happened.
do
    local t = Fixture({ bags = { [0] = Bag(16, { { 1, 3 }, { 2, 11 } }) } })
    t.Click(1, "LeftButton", true)
    t.Fire("BAG_UPDATE_DELAYED")
    Check("ctrl-click deleted the eggs", t.Count(1), 0)
    Check("deleted message", t.printed[#t.printed]:find("^deleted") ~= nil, true)
    t.Click(1, "MiddleButton")
    Check("middle-click ignores with a time", type(t.db.bagSpaceIgnore[2]), "number")
    Check("ignored item leaves the row", t.Row(), "")
end

-- An unfinished quest objective flags its item, puts it last and asks for a second Ctrl-click;
-- a finished objective, or a count-first objective text, is read the same way.
do
    local t = Fixture({
        quests = {
            { title = "Westfall Stew", objectives = {
                { type = "item", text = "Small Egg: 1/3", finished = false, numFulfilled = 1, numRequired = 3 },
                { type = "item", text = "Coyote Meat: 5/5", finished = true, numFulfilled = 5, numRequired = 5 },
            } },
            { title = "Linen Trouble", objectives = {
                { type = "item", text = "2/6 Linen Cloth", finished = false, numFulfilled = 2, numRequired = 6 },
            } },
        },
        bags = { [0] = Bag(16, { { 1, 3 }, { 2, 11 }, { 10, 1 } }) },
    })
    Check("quest items go last", t.Row(), "Coyote Meat, Small Egg, Linen Cloth")
    Check("badge on a quest item", t.Button(2).quest.shown, true)
    Check("no badge on a finished objective", t.Button(1).quest.shown, false)
    t.Click(2, "LeftButton", true)
    Check("first ctrl-click only warns", t.Count(1), 3)
    Check("warning names the quest", t.printed[#t.printed]:find("Westfall Stew %(1/3%)") ~= nil, true)
    t.Click(2, "LeftButton", true)
    t.Fire("BAG_UPDATE_DELAYED")
    Check("second ctrl-click deletes", t.Count(1), 0)
end

-- Uncommon and better only go on the cursor, so the game's own delete confirmation applies.
do
    local t = Fixture({ bags = { [0] = Bag(16, { { 11, 1 } }) } })
    t.Click(1, "LeftButton", true)
    Check("uncommon is picked up, not deleted", select(2, t.env.GetCursorInfo()), 11)
    Check("ground hint", t.printed[#t.printed]:find("is on your cursor") ~= nil, true)
end

-- The key binding redraws the row from the scan it acts on, so icons match their items.
do
    local bags = { [0] = Bag(16, { { 1, 3 }, { 2, 11 }, { 3, 2 } }) }
    local t = Fixture({ bags = bags })
    bags[0][1] = nil   -- the eggs are gone, with no bag event yet
    t.env.NaowhForever_BagSpacePickUp()
    Check("binding picks up the cheapest", select(2, t.env.GetCursorInfo()), 2)
    for i = 1, 2 do
        local b = t.Button(i)
        Check("icon " .. i .. " matches its item", b.icon.texture, b.pick.itemID)
    end
end

-- Stacking starts from a fresh scan: a stack moved by hand since the row was drawn is found
-- where it is now, and the item put in its old slot stays put.
do
    local bags = { [0] = Bag(16, { { 1, 3 }, { 1, 5 }, { 2, 11 } }) }
    local t = Fixture({ bags = bags })
    bags[0][4], bags[0][1] = bags[0][1], { id = 10, count = 3 }
    t.Click(1)
    for _ = 1, 5 do t.Fire("BAG_UPDATE_DELAYED") end
    Check("linen left alone", bags[0][1] and bags[0][1].id, 10)
    Check("moved eggs merged", t.Slots(1), 1)
    Check("no moved eggs lost", t.Count(1), 8)
end

-- Two part-filled egg stacks: a Stack button that merges them into one slot.
do
    local t = Fixture({ bags = { [0] = Bag(16, { { 1, 3 }, { 1, 5 }, { 2, 11 } }) } })
    Check("stack button first", t.Row():match("^[^,]+"), "Stack")
    t.Click(1)
    for _ = 1, 5 do t.Fire("BAG_UPDATE_DELAYED") end
    Check("eggs merged into one slot", t.Slots(1), 1)
    Check("no eggs lost", t.Count(1), 8)
    Check("stack message", t.printed[#t.printed], "stacked your bags: 1 slot freed.")
end

-- A threshold hides the row until an "Inventory is full" error brings it up.
do
    local t = Fixture({ settings = { bagSpaceFreeBelow = 3 },
        bags = { [0] = Bag(16, { { 1, 3 }, { 2, 11 } }) } })
    Check("hidden with room to spare", t.Row(), "")
    t.Fire("UI_ERROR_MESSAGE", 0, "Inventory is full.")
    Check("shown after inventory full", t.Row(), "Small Egg, Coyote Meat")
end

-- Cost: a full set of bags, scanned the way loot triggers it.
do
    local bags = { [0] = Bag(16, {}) }
    for b = 1, 4 do bags[b] = Bag(20, {}) end
    local n = 0
    for b = 0, 4 do
        for slot = 1, bags[b].size do
            n = n + 1
            local id = n % 10 + 1
            bags[b][slot] = { id = id, count = math.max(1, (n * 7) % ITEMS[id][4]) }
        end
    end
    local t = Fixture({ bags = bags })
    local SCANS = 2000
    for _ = 1, 50 do t.Fire("BAG_UPDATE_DELAYED") end   -- warm the pools
    collectgarbage("collect")
    collectgarbage("stop")
    local before, start = collectgarbage("count"), os.clock()
    for _ = 1, SCANS do t.Fire("BAG_UPDATE_DELAYED") end
    local elapsed, grown = os.clock() - start, collectgarbage("count") - before
    collectgarbage("restart")
    print(("bag space: %d slots, %.3f ms and %.2f KB per scan and redraw")
        :format(96, elapsed * 1000 / SCANS, grown / SCANS))
    Check("under 1 ms per scan", elapsed * 1000 / SCANS < 1, true)
    -- Pooled: once warm, a scan leaves nothing for the garbage collector.
    Check("no garbage per scan", grown / SCANS < 0.05, true)
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("test-bag-space: all passed")
