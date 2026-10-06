-- Run with Lua 5.1 from the repository root: the link view behind K. A plain click on another
-- player's trade link starts it; Shift or Ctrl only puts the link in chat and starts nothing.
-- Closing the window ends it, also when it closes in the first second after the click, once
-- that second has passed and the window is still closed. The real code is cut out of the file.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local source = Read("NaowhForever_Professions/NaowhForever_Professions.lua")
local first = assert(source:find("local casts = CreateFrame(\"Frame\")", 1, true))
local hook = assert(source:find("hooksecurefunc(\"SetItemRef\"", first, true))
local last = assert(source:find("\nend)\n", hook, true))
local chunk = "local viewingLink, linkClicked, linkGUID\nlocal RETRY_AFTER = 0.5\nlocal retrying\n"
    .. source:sub(first, last + 5)
    .. "return { Viewing = function() return viewingLink end, EndLinkView = EndLinkView }"

local now, timers, shown, modifier, refHook = 100, {}, false, false, nil
-- Fires each timer due by then, in order, with the clock at its own time.
local function Advance(seconds)
    local stop = now + seconds
    while true do
        local soon
        for i, t in ipairs(timers) do
            if t.at <= stop and (not soon or t.at < timers[soon].at) then soon = i end
        end
        if not soon then break end
        local t = table.remove(timers, soon)
        now = t.at
        t.fn()
    end
    now = stop
end
local env = {
    GetTime = function() return now end,
    C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end },
    CreateFrame = function()
        return { SetScript = function() end, RegisterUnitEvent = function() end,
            UnregisterAllEvents = function() end }
    end,
    hooksecurefunc = function(name, fn) if name == "SetItemRef" then refHook = fn end end,
    SetItemRef = function(...) refHook(...) end,
    IsShiftKeyDown = function() return modifier end,
    IsControlKeyDown = function() return false end,
    UnitGUID = function() return "Player-1-5E1F" end,
    On = function() return true end,
    Queue = function() end,
    ProfessionsFrame = { IsShown = function() return shown end },
    C_TradeSkillUI = { IsTradeSkillLinked = function() return shown end },
}
local fn = assert(loadstring(chunk))
setfenv(fn, setmetatable(env, { __index = _G }))
local api = fn()

local LINK_A, LINK_B = "trade:Player-1-AAAA:2259:171", "trade:Player-1-BBBB:2259:171"
local function Click(link) refHook(link, "[Alchemy]", "LeftButton") end
local function Close() shown = false; api.EndLinkView() end

-- A plain click starts the view; closing it after a second ends it.
Click(LINK_A); shown = true
check("a plain click on a link starts the link view", api.Viewing())
Advance(5); Close()
check("closing the link window ends the view", not api.Viewing())

-- Shift- or Ctrl-click only puts the link in chat.
modifier = true
Click(LINK_B)
check("a modified click starts no link view", not api.Viewing())
modifier = false

-- Your own link stays yours.
Click("trade:Player-1-5E1F:2259:171")
check("your own link starts no link view", not api.Viewing())

for _, link in ipairs({ "trade:|TInterface\\AddOns\\NaowhForever\\Media\\Badges\\BadgeNaowhChat.tga:0|t:2259:171",
    "trade:%s%d:2259:171", "trade:Player-1-ZZZZ:2259:171", "trade:Player-1-AAAA", "trade:" .. ("x"):rep(4000),
    "trade::2259:171", 42 }) do
    Click(link)
end
check("a crafted trade link starts no link view", not api.Viewing() and #timers == 0)

-- The reviewer's repro: open A, close it inside a second, shift-click B, then K.
Click(LINK_A); shown = true
Advance(0.6); Close()
check("closed inside a second: still viewing until the second has passed", api.Viewing())
Advance(0.5)
check("still closed once the second has passed: the view is over", not api.Viewing())
modifier = true; Click(LINK_B); modifier = false
check("then a shift-click on another link leaves it off", not api.Viewing())

-- The click's own close on its way to the link: the window opens again, the view stays.
Click(LINK_A)
Close(); shown = true
Advance(2)
check("the click's own close, window open again: the view stays", api.Viewing())
Close()
check("and a later close ends it", not api.Viewing())

-- A new link clicked before the first close's look is due keeps its own view.
Click(LINK_A); shown = true
Advance(0.2); Close()
Advance(0.1); Click(LINK_B)
Advance(0.85)
check("a newer click is not ended by the older close", api.Viewing())

print(("test-profession-link-view: %d checks passed"):format(checks))
