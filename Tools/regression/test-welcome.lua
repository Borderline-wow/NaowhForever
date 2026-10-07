-- Run with Lua 5.1 from the repository root: the welcome window (Core/NaowhForever_Welcome.lua)
-- against stubs of the shared window parts. Checks that nothing is made at load; it shows a few
-- seconds after the first login, or after a reload while it is still unseen (another addon's
-- setup reloading over it), never during a loading screen, and waits
-- for combat to end; once seen (closed, Esc or any button) it never shows by itself again; Join
-- Discord puts the Discord link on the copy card, Open Settings opens the options; /nf welcome
-- and the settings button open it again; and none of its words ask for support.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local DISCORD = "https://discord.com/invite/naowh"
local WELCOME = "Core/NaowhForever_Welcome.lua"

-------------------------------------------------------------------------------
--  Stubs: a frame keeps its scripts, hooks, events, text and shown state; any other method the
--  game has (capitalised) does nothing.
-------------------------------------------------------------------------------
local Frame = {}
local function noop() end
Frame.__index = function(_, key)
    return Frame[key] or (type(key) == "string" and key:match("^%u") and noop or nil)
end
local function NewFrame(made)
    local f = setmetatable({ scripts = {}, hooks = {}, events = {}, shown = true }, Frame)
    made[#made + 1] = f
    return f
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn) self.hooks[name] = fn end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
local textures = {}
function Frame:CreateTexture()
    local tx = setmetatable({ SetTexture = function(tx, path) tx.path = path end }, Frame)
    textures[#textures + 1] = tx
    return tx
end
function Frame:IsShown() return self.shown end
function Frame:SetText(text) self.text = text end
function Frame:GetStringHeight() return 14 end
function Frame:SetHeight(h) self.h = h end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    if self.hooks.OnHide then self.hooks.OnHide(self) end
end

-- A fresh load of the file, as at login, on the account's saved table.
local function Setup(account)
    local s = { account = account or {}, made = {}, timers = {}, texts = {}, combat = false, copied = nil,
        options = 0, windows = 0, cards = {} }
    local function Text(text) s.texts[#s.texts + 1] = text end
    local St
    local ns
    ns = {
        THEME = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end }),
        Color = function(_, text) return text end,
        AccountSettings = function() return s.account end,
        Font = function(parent)
            local fs = NewFrame(s.made)
            fs.parent = parent
            fs.SetText = function(self, text) self.text = text; Text(text) end
            return fs
        end,
        Button = function(parent, text, w, h, onClick)
            local b = NewFrame(s.made)
            b.parent, b.label, b.w, b.h, b.click = parent, text, w, h, onClick
            Text(text)
            return b
        end,
        AccentBorder = function(b) b.accent = true; return b end,
        Border = function(f) f.bordered = true end,
        Tooltip = function(f, title, body) f.tipTitle, f.tipBody = title, body end,
        ShowCopyLine = function(title, text, icon) s.copied = { title = title, text = text, icon = icon } end,
        OpenOptionsWindow = function() s.options = s.options + 1 end,
        OpenFromOptions = function(open) s.fromOptions = (s.fromOptions or 0) + 1; open() end,
        NAOWH_DISCORD = DISCORD,
        QoLSettings = {},
        Shared = {
            Parts = {
                Window = function(w, h, key)
                    s.windows = s.windows + 1
                    local win = NewFrame(s.made)
                    win.w, win.h, win.key = w, h, key
                    win.shown = false
                    win.backdrop = { Paint = function(self, alpha) self.alpha = alpha end }
                    s.window = win
                    return win
                end,
                TitleBar = function(win, title, subtitle)
                    Text(title); Text(subtitle)
                    win.titleText, win.subtitleText = title, subtitle
                    win.x = { click = function() win:Hide() end }
                    return win.x
                end,
            },
            Settings = {
                Page = function(key)
                    return { Card = function(_, spec) s.cards[key .. ":" .. spec.id] = spec; return spec end }
                end,
            },
        },
    }
    local env = setmetatable({
        NaowhForever = ns,
        CreateFrame = function() return NewFrame(s.made) end,
        InCombatLockdown = function() return s.combat end,
        C_Timer = { NewTimer = function(delay, fn)
            local t = { delay = delay, fn = fn }
            t.Cancel = function(self) self.cancelled = true end
            s.timers[#s.timers + 1] = t
            return t
        end },
    }, { __index = _G })
    env._G = env
    local style = assert(loadfile("Shared/Style.lua"))
    setfenv(style, env)
    style()
    St = ns.Shared.Style
    check("the house style loads", St.WINDOW_HEADER ~= nil)
    local before = #s.made
    local chunk = assert(loadfile(WELCOME))
    setfenv(chunk, env)
    chunk()
    s.ns = ns
    s.login = s.made[before + 1]
    s.madeAtLoad = #s.made - before
    return s
end

local function Event(s, event, ...)
    s.login.scripts.OnEvent(s.login, event, ...)
end

-- The newest timer still running, run as the game would when it is due.
local function RunTimer(s)
    for i = #s.timers, 1, -1 do
        local t = s.timers[i]
        if not t.cancelled and not t.ran then
            t.ran = true
            t.fn()
            return t
        end
    end
end

local function Shown(s) return s.window ~= nil and s.window.shown end

-------------------------------------------------------------------------------
--  Nothing at load
-------------------------------------------------------------------------------
do
    local s = Setup()
    check("one frame at load, for the login check", s.madeAtLoad == 1)
    check("no window, no text before it shows", s.windows == 0 and #s.texts == 0 and s.window == nil)
    check("it listens for the first world entry only", s.login.events.PLAYER_ENTERING_WORLD
        and not s.login.events.PLAYER_REGEN_ENABLED and not s.login.events.PLAYER_LEAVING_WORLD)
    check("its settings card is declared on QoL > System", s.cards["QoL/System:welcome"] ~= nil)
end

-------------------------------------------------------------------------------
--  A reload before it was seen (another addon's setup reloaded over it): it comes back
-------------------------------------------------------------------------------
do
    local s = Setup()
    Event(s, "PLAYER_ENTERING_WORLD", false, true)
    check("an unseen reload waits a few seconds, like a login", #s.timers == 1 and s.timers[1].delay > 0
        and s.windows == 0)
    RunTimer(s)
    check("then the window shows", Shown(s))
end
do
    local s = Setup({ welcomeSeen = true })
    Event(s, "PLAYER_ENTERING_WORLD", false, true)
    check("seen: a reload starts no timer and stops listening", #s.timers == 0 and next(s.login.events) == nil)
    check("and makes nothing", s.windows == 0)
end
do
    local s = Setup()
    Event(s, "PLAYER_ENTERING_WORLD", false, false)
    check("a world entry that is neither login nor reload does not start it", #s.timers == 0
        and s.windows == 0)
end

-------------------------------------------------------------------------------
--  The first login: a few seconds in, then once
-------------------------------------------------------------------------------
local account = {}
do
    local s = Setup(account)
    Event(s, "PLAYER_ENTERING_WORLD", true, false)
    check("the first login waits a few seconds", #s.timers == 1 and s.timers[1].delay > 0 and s.windows == 0)
    RunTimer(s)
    check("then the window shows", Shown(s) and s.windows == 1)
    check("and stops listening", next(s.login.events) == nil)
    check("not seen until it is closed", account.welcomeSeen == nil)
    local win = s.window
    check("the house window: its title and the logo's bar", win.titleText == "Welcome to Naowh Forever"
        and win.key == "welcomeWindow" and win.backdrop.alpha ~= nil)
    check("three lines of text", #win.lines == 3 and win.h ~= nil)
    check("Join Discord is the main action, in the accent", win.discord.label == "Join Discord"
        and win.discord.accent == true and win.settings.label == "Open Settings" and win.close.label == "Close")
    -- Its parent hidden (the game's UI toggled off) is not a close.
    win.hooks.OnHide(win)
    check("the UI hidden with it is not a close", account.welcomeSeen == nil)
    win.close.click()
    check("Close closes it and marks it seen", not Shown(s) and account.welcomeSeen == true)
end
do
    local s = Setup(account)
    Event(s, "PLAYER_ENTERING_WORLD", true, false)
    check("seen: the next login shows nothing", #s.timers == 0 and s.windows == 0
        and next(s.login.events) == nil)
end

-------------------------------------------------------------------------------
--  Combat and loading screens
-------------------------------------------------------------------------------
do
    local s = Setup()
    Event(s, "PLAYER_ENTERING_WORLD", true, false)
    s.combat = true
    RunTimer(s)
    check("in combat when due: nothing yet, waits for combat to end", s.windows == 0
        and s.login.events.PLAYER_REGEN_ENABLED)
    s.combat = false
    Event(s, "PLAYER_REGEN_ENABLED")
    check("combat over: it shows", Shown(s) and next(s.login.events) == nil)
end
do
    local s = Setup()
    Event(s, "PLAYER_ENTERING_WORLD", true, false)
    local first = s.timers[1]
    Event(s, "PLAYER_LEAVING_WORLD")
    check("a loading screen before it is due puts it off", first.cancelled == true and s.windows == 0)
    Event(s, "PLAYER_ENTERING_WORLD", false, false)
    check("the world entry after it starts the wait again", #s.timers == 2 and not s.timers[2].cancelled)
    RunTimer(s)
    check("and it shows after", Shown(s))
end
do
    local s = Setup()
    Event(s, "PLAYER_ENTERING_WORLD", true, false)
    s.combat = true
    RunTimer(s)
    Event(s, "PLAYER_LEAVING_WORLD")
    check("waiting on combat, a loading screen stops the wait", not s.login.events.PLAYER_REGEN_ENABLED)
    s.combat = false
    Event(s, "PLAYER_ENTERING_WORLD", false, false)
    RunTimer(s)
    check("and the next world entry shows it", Shown(s))
end

-------------------------------------------------------------------------------
--  Each button marks it seen
-------------------------------------------------------------------------------
do
    local seen = {}
    local s = Setup(seen)
    s.ns.ShowWelcome()
    s.window.discord.click()
    check("Join Discord marks it seen", seen.welcomeSeen == true)
    check("and puts Naowh's Discord on the copy card", s.copied and s.copied.text == DISCORD
        and s.copied.title == "Naowh's Discord")
    check("the welcome stays up behind the copy card", Shown(s))
end
do
    local seen = {}
    local s = Setup(seen)
    s.ns.ShowWelcome()
    s.window.settings.click()
    check("Open Settings opens the options and closes the welcome", s.options == 1 and not Shown(s))
    check("and marks it seen", seen.welcomeSeen == true)
end
do
    local seen = {}
    local s = Setup(seen)
    s.ns.ShowWelcome()
    s.window.x.click()
    check("the title bar's close marks it seen", seen.welcomeSeen == true)
end
do
    local seen = {}
    local s = Setup(seen)
    s.ns.ShowWelcome()
    s.window:Hide()   -- Esc: the shared window's own key handler hides it
    check("Esc marks it seen", seen.welcomeSeen == true)
end

-------------------------------------------------------------------------------
--  /nf welcome and the settings button
-------------------------------------------------------------------------------
do
    local s = Setup({ welcomeSeen = true })
    local source = Read("Core/NaowhForever_Window.lua")
    local body = assert(source:match('SlashCmdList%["NAOWHFOREVER"%] = function%(msg%)\n(.-)\nend\n'),
        "the /nf handler")
    local env = setmetatable({ ns = s.ns, strtrim = function(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end },
        { __index = _G })
    local handler = assert(loadstring("return function(msg)\n" .. body .. "\nend"))
    setfenv(handler, env)
    handler = handler()
    s.ns.ToggleOptionsWindow = function() s.toggled = true end
    handler("welcome")
    check("/nf welcome opens it, seen or not", Shown(s) and not s.toggled)
    check("over the options window, which steps aside for it", s.fromOptions == 1)
    s.window.close.click()
    handler(" Welcome ")
    check("in any case, again", Shown(s))
    s.window.close.click()
    local card = s.cards["QoL/System:welcome"]
    local row = card.rows[1]
    check("the settings card has a Show button", row.buttonText == "Show" and row.label == "Welcome Window")
    row.button()
    check("which opens it", Shown(s))
    check("one window, made once", s.windows == 1)
end

-------------------------------------------------------------------------------
--  Its words: no ask
-------------------------------------------------------------------------------
do
    local s = Setup()
    s.ns.ShowWelcome()
    local card = s.cards["QoL/System:welcome"]
    local words = { card.name, card.help }
    for _, row in ipairs(card.rows) do
        words[#words + 1] = row.label
        words[#words + 1] = row.help
        words[#words + 1] = row.buttonText
    end
    for _, text in ipairs(s.texts) do words[#words + 1] = text end
    check("it has words to read", #words > 8)
    local source = Read(WELCOME):lower()
    for _, word in ipairs({ "support", "patreon", "badge", "donat" }) do
        for _, text in ipairs(words) do
            check(("no %q in %q"):format(word, text), not text:lower():find(word, 1, true))
        end
        check("no " .. word .. " anywhere in the file", not source:find(word, 1, true))
    end
    check("it says how to start", table.concat(s.texts, " "):find("/nf", 1, true) ~= nil)
end

-------------------------------------------------------------------------------
--  How to start: a row per preset (ns.PRESETS). On a new account a pick applies at once (the
--  one a new install already has, nothing); picked again later it asks first.
-------------------------------------------------------------------------------
do
    local s = Setup()
    local used = {}
    s.ns.PRESETS = { newInstall = "minimalist", order = { "minimalist", "recommended" },
        minimalist = { name = "Minimalist", about = "Almost everything off." },
        recommended = { name = "Recommended", about = "Naowh's setup." } }
    s.ns.UsePreset = function(key, ask) used[#used + 1] = { key = key, ask = ask } end
    s.ns.ShowWelcome()
    local win = s.window
    check("a row per preset, named, with its line", win.presets and #win.presets == 2
        and win.presets[1].label == "Minimalist" and win.presets[2].label == "Recommended")
    local paths = {}
    for _, tx in ipairs(textures) do if tx.path then paths[#paths + 1] = tx.path end end
    local all = table.concat(paths, " ")
    check("each preset's picture, as a .png the game can load (it adds no extension to a PNG)",
        all:find("Welcome\\minimalist.png", 1, true) ~= nil and all:find("Welcome\\recommended.png", 1, true) ~= nil)
    s.ns.PresetChanges = function(key) return "changes of " .. key end
    check("each button's tooltip lists what that preset changes", win.presets[2].tipTitle == "Recommended"
        and win.presets[2].tipBody() == "changes of recommended")
    check("under the question", table.concat(s.texts, " "):find("How do you want to start?", 1, true) ~= nil
        and table.concat(s.texts, " "):find("Naowh's setup.", 1, true) ~= nil)
    win.presets[2].click()
    check("a new account's pick applies at once, the window closed and seen", #used == 1
        and used[1].key == "recommended" and used[1].ask == false and not Shown(s) and s.account.welcomeSeen == true)
    s.ns.ShowWelcome()
    win.presets[1].click()
    check("picked again later, it asks first", #used == 2 and used[2].key == "minimalist" and used[2].ask == true)
    local fresh = Setup()
    local none = {}
    fresh.ns.PRESETS = s.ns.PRESETS
    fresh.ns.UsePreset = function(key) none[#none + 1] = key end
    fresh.ns.ShowWelcome()
    fresh.window.presets[1].click()
    check("a new account keeping what it has (Minimalist): nothing to apply", #none == 0 and not Shown(fresh))
    local one = Setup()
    one.ns.PRESETS = { newInstall = "minimalist", order = { "minimalist" }, minimalist = s.ns.PRESETS.minimalist }
    one.ns.UsePreset = s.ns.UsePreset
    one.ns.ShowWelcome()
    check("one preset only: no question", one.window.presets == nil)
end

print(("test-welcome: %d checks passed"):format(checks))
