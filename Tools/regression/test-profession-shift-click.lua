-- Run with Lua 5.1 from the repository root: Shift-click on a recipe or reagent in the
-- Professions window. With the auction house open and Shift-Click Searches AH on it searches
-- the auction house; while you type in chat, or otherwise, it links the item in chat, through
-- ChatFrameUtil (the ChatEdit_ names are deprecated shims Forever does not load).
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local source = Read("Professions/NaowhForever_Professions.lua")
local first = assert(source:find("local function TypingInChat()", 1, true))
local shift = assert(source:find("local function ShiftClick(itemID, link)", first, true))
local last = assert(source:find("\nend\n", shift, true))
local chunk = source:sub(first, last + 4) .. "return ShiftClick"

local settings, ahOpen, typing, names = {}, false, false, { [2840] = "Copper Bar" }
local searched, linked
local env = {
    S = { Get = function(k) return settings[k] end },
    AuctionHouseOpen = function() return ahOpen end,
    ItemName = function(id) return id and names[id] end,
    SearchAuctionHouse = function(name) searched = name end,
    ChatFrameUtil = {
        -- As with some chat settings: there is always an active chat box, typing or not.
        GetActiveWindow = function() return { HasFocus = function() return typing end } end,
        InsertLink = function(link) linked = link end,
    },
}
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local ShiftClick = fn()

local function Click(id, link)
    searched, linked = nil, nil
    ShiftClick(id, link)
end

Click(2840, "[Copper Bar]")
check("switch off: it links", linked == "[Copper Bar]" and not searched)

settings.ahShiftClick = true
Click(2840, "[Copper Bar]")
check("auction house closed: it links", linked == "[Copper Bar]" and not searched)

ahOpen = true
Click(2840, "[Copper Bar]")
check("auction house open, chat box there but not typing: it searches",
    searched == "Copper Bar" and not linked)

typing = true
Click(2840, "[Copper Bar]")
check("typing in chat: it links", linked == "[Copper Bar]" and not searched)
typing = false

Click(9999, "[Not Loaded]")
check("a name not loaded yet: it links", linked == "[Not Loaded]" and not searched)

Click(nil, "[Enchant Bracer]")
check("a recipe that makes no item: it links", linked == "[Enchant Bracer]" and not searched)

local deprecated = false
for line in source:gmatch("[^\n]+") do
    if not line:match("^%s*%-%-") and line:find("ChatEdit_", 1, true) then deprecated = true end
end
check("no deprecated ChatEdit_ calls in the Professions window", not deprecated)

print(("test-profession-shift-click: %d checks passed"):format(checks))
