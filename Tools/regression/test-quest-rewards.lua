-- Run with Lua 5.1 from the repository root: the saved quest rewards list reads, removes and clears the picks,
-- tolerates old and damaged entries, and falls back to the title kept at save time; the window's X removes that
-- quest's pick, loaded with the Shared files and the window against stubs.
local Load = dofile("Tools/regression/load_files.lua")
local TocFiles = dofile("Tools/regression/toc_files.lua")

local NOTHING = function() end
local Frame
local METHODS = {
    SetScript = function(f, script, fn) f.scripts[script] = fn end,
    GetScript = function(f, script) return f.scripts[script] end,
    HookScript = function(f, script, fn) f.scripts[script] = f.scripts[script] or fn end,
    RegisterEvent = function(f, event) f.events[event] = true end,
    UnregisterAllEvents = function(f) for event in pairs(f.events) do f.events[event] = nil end end,
    GetParent = function(f) return rawget(f, "parent") end,
    GetWidth = function() return 400 end,
    GetHeight = function() return 24 end,
    SetText = function(f, text) f.text = text end,
    GetText = function(f) return rawget(f, "text") or "" end,
    GetStringWidth = function() return 40 end,
    GetStringHeight = function() return 12 end,
    Show = function(f) f.shown = true end,
    Hide = function(f) f.shown = false end,
    SetShown = function(f, shown) f.shown = shown and true or false end,
    IsShown = function(f) return rawget(f, "shown") ~= false end,
    IsVisible = function(f) return rawget(f, "shown") ~= false end,
    IsMouseOver = function() return false end,
    GetFrameLevel = function() return 1 end,
    IsForbidden = function() return false end,
    GetEffectiveScale = function() return 1 end,
    CreateTexture = function(f) return Frame(f) end,
    CreateFontString = function(f) return Frame(f) end,
    CreateAnimationGroup = function(f) return Frame(f) end,
    CreateAnimation = function(f) return Frame(f) end,
}
local META = { __index = function(_, key)
    if METHODS[key] then return METHODS[key] end
    if type(key) == "string" and key:find("^%u") then return NOTHING end
end }
function Frame(parent)
    return setmetatable({ scripts = {}, events = {}, parent = parent }, META)
end

local WHITE = { r = 1, g = 1, b = 1 }
local timers = {}
local tooltip = Frame()
tooltip.GetOwner = function() return nil end

local db, account = { questRewards = { [10] = 111, [20] = 222, [30] = 333, bad = 5, [40] = "x" } }, {}
local S = { Get = function() end, Set = function() end, DB = function() return db end }
local ns = { L = dofile("Tools/regression/locale_stub.lua").L, Upper = string.upper, Lower = string.lower,
    QoLSettings = S, Print = NOTHING, Apply = NOTHING, AccountSettings = function() return account end,
    THEME = setmetatable({}, { __index = function() return WHITE end }),
    Color = function(_, text) return tostring(text) end,
    Font = function(parent) return Frame(parent) end,
    Solid = function(parent) return Frame(parent) end,
    ThemeTint = function(_, literal) return literal end,
    Hairline = function(region) return region end,
    PixelInset = function(region) return region end,
    Border = function() return { SetColor = NOTHING } end,
    AccentBorder = function() return { SetColor = NOTHING } end,
    AllowOffscreen = NOTHING,
    Button = function(parent) return Frame(parent) end,
    UIFontPath = function() return "font" end,
    UIScale = function() return 1 end,
    UI = { Keep = NOTHING, SlimScroll = function(parent) return Frame(parent) end, CloseOnEscape = NOTHING },
}

local titles = { [10] = "Ten" }
local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function(_, _, parent) return Frame(parent) end,
    hooksecurefunc = function(a, b, c)
        if type(a) ~= "table" then return end
        local original = a[b]
        a[b] = function(...) original(...); c(...) end
    end,
    Mixin = function(target, ...)
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do target[k] = v end
        end
        return target
    end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    C_QuestLog = { GetTitleForQuestID = function(id) return titles[id] end, RequestLoadQuestByID = NOTHING },
    C_Item = {
        GetItemInfoInstant = function(id) return id end,
        GetItemInfo = function(id) return "item " .. id end,
        GetItemNameByID = function(id) return "item " .. id end,
        GetItemQualityByID = function() return 1 end,
        GetItemIconByID = function(id) return id end,
        GetItemCount = function() return 0 end,
        IsItemDataCachedByID = function() return true end,
    },
    ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff", r = 1, g = 1, b = 1 } },
    GameTooltip = tooltip,
    GameTooltip_Hide = NOTHING,
    InCombatLockdown = function() return false end,
    CreateColor = function() return Frame() end,
    UIParent = Frame(),
}, { __index = _G })
env._G = env

local files = TocFiles("^Shared/.*%.lua$")
for i = #files, 1, -1 do
    if files[i] == "Shared/UI/CopyCard.lua" then table.remove(files, i) end
end
files[#files + 1] = "NaowhForever_QoL/Questing/QuestAutomation.lua"
files[#files + 1] = "NaowhForever_QoL/Questing/RewardList.lua"
Load(files, env)

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local R = ns.QuestRewards
local list = R.List({})
table.sort(list)
check("only well-formed picks are listed", #list == 3 and list[1] == 10 and list[3] == 30)
check("an old numeric pick reads back its item", R.ItemID(20) == 222)

check("a cached title wins", R.Title(10) == "Ten")
check("no title is nil", R.Title(20) == nil)
account.questTitles = { [20] = "Kept" }
check("the title kept at save time is the fallback", R.Title(20) == "Kept")

local changed = 0
R.OnChange(function() changed = changed + 1 end)
R.Remove(20)
check("remove drops that quest only", db.questRewards[20] == nil and db.questRewards[10] == 111 and changed == 1)
R.Clear()
check("clear drops every pick", next(db.questRewards) == nil and changed == 2)
check("an empty list is empty", #R.List({}) == 0)

local views = {}
local NewView = ns.Shared.View.New
ns.Shared.View.New = function(...)
    local view = NewView(...)
    views[#views + 1] = view
    return view
end
db.questRewards = { [10] = 111, [20] = 222, [30] = 333 }
ns.OpenQuestRewards()
local rewardView = views[1]
local function Find(questID)
    for i = 1, rewardView.pools.item.used do
        local row = rewardView.pools.item[i]
        if row:IsShown() and row.key == questID then return row end
    end
end
local row = Find(20)
check("the window lists a row for each saved reward", rewardView.pools.item.used == 3 and row and row.itemID == 222
    and row.remove.shown == true)
row.remove.scripts.OnClick(row.remove)
check("its X removes that quest's reward only", db.questRewards[20] == nil and db.questRewards[10] == 111
    and db.questRewards[30] == 333)
while #timers > 0 do table.remove(timers, 1)() end
check("and the row goes", Find(20) == nil and Find(10) ~= nil)

print(checks .. " saved quest reward checks passed")
