-- SettingsPage.lua: the AuraBuffs/Settings page's banner; each reminder adds its own card.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local TEXT_OFF = ns.L("AuraBuffs is off")
local TEXT_NOTHING = ns.L("No consumables to watch yet")
local TEXT_DETAIL = ns.L("Add the consumables to watch in the AuraBuffs window.")
local TEXT_TO_WATCH = ns.L("%d %s to watch")
local TEXT_CONSUMABLE, TEXT_CONSUMABLES = ns.L("consumable"), ns.L("consumables")

local function Headline()
    if not S.Get("enabled") then return TEXT_OFF end
    local n = #(S.Get("consumableEntries") or {})
    if n == 0 then return TEXT_NOTHING end
    return TEXT_TO_WATCH:format(n, n == 1 and TEXT_CONSUMABLE or TEXT_CONSUMABLES)
end

local function Detail()
    return TEXT_DETAIL
end

local function OpenWindow()
    ns.OpenAuraBuffsWindow()
end

local page = Settings.Page(A.PAGE, S)

page:Window({
    text = "Open AuraBuffs",
    open = OpenWindow,
    headline = Headline,
    detail = Detail,
})
