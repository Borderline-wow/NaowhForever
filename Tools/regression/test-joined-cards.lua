-- A card declared with `into` puts its rows, under a group named for it, in another card of the page, in order.
-- Run with Lua 5.1 from the repository root.
local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end

local ns
ns = { THEME = {}, L = function(text) return text end, Upper = string.upper, Lower = string.lower,
    Shared = { Style = dofile("Tools/regression/shared_style.lua") }, UI = {} }
local env = setmetatable({ _G = { NaowhForever = ns }, CreateFrame = function() return {} end }, { __index = _G })
local chunk = assert(loadfile("Shared/Settings/Settings.lua"))
setfenv(chunk, env)
chunk()

local Settings = ns.Shared.Settings
local store = { Get = function() end, Set = function() end, Default = function() end, OnChange = function() end }
local page = Settings.Page("Test/Page", store)
local trade = page:Card({ id = "trade", name = "Buying and Selling", order = 10, rows = {} })
page:Card({ id = "mail", name = "Mail", order = 40, into = "trade", rows = { { key = "a", label = "Alts", toggle = true } } })
page:Card({ id = "vendors", name = "Vendors", order = 20, into = "trade",
    rows = { { key = "b", label = "Repair", toggle = true }, { key = "c", label = "Sell", toggle = true } } })

local rows = Settings.Rows(trade)
Check(#rows == 5, "every row and a group per part")
Check(rows[1].group == "Vendors" and rows[2].label == "Repair" and rows[3].label == "Sell", "the lower order first")
Check(rows[4].group == "Mail" and rows[5].label == "Alts", "then the next part")
Check(rows[2].card == trade and rows[2].store == store, "rows belong to the shared card")
Check(Settings.CardOf("Test/Page:mail") == trade and Settings.CardOf("Test/Page:vendors") == trade,
    "a joined card's id finds the shared card")

local count = 0
for _, item in ipairs(page.items) do if not item.window then count = count + 1 end end
Check(count == 1, "the page draws one card")

Check(not pcall(page.Card, page, { id = "x", name = "X", into = "missing", rows = {} }), "joining a card that is not there fails")
Check(not pcall(page.Card, page, { id = "y", name = "Y", into = "trade", switch = "on", rows = {} }), "a joined card has no switch of its own")

print(("test-joined-cards: %d checks passed"):format(cases))
