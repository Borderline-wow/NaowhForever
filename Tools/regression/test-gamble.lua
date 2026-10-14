-- test-gamble.lua: offline tests for Gamble sessions and rolls.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local HOST = { first = "Host", surname = "Brightmane", guid = "Player-1-0000HOST" }
local ALICE = { first = "Alice", surname = "Stone", guid = "Player-1-000ALICE" }
local BOB = { first = "Bob", surname = "Hill", guid = "Player-1-00000BOB" }
local GUEST = { first = "Guest", surname = "Wood", guid = "Player-1-000GUEST" }
local CHARLIE = { first = "Charlie", surname = "", guid = "Player-1-0CHARLIE" }

local state = { settings = { enabled = true, gamble = false, gambleChannel = "PARTY", gamblePool = "200g00s",
    gambleMode = "classic", gambleJoinWord = "join", gambleLeaveWord = "leave" },
    buttons = {}, chats = {}, addons = {},
    prints = {}, frames = {}, listeners = {}, editboxes = {}, fonts = {}, inRaid = false,
    party = { ALICE, BOB, GUEST }, disconnected = {}, secrets = {} }

local widgetMethods = {}
function widgetMethods:SetText(text) self.text = text end
function widgetMethods:GetText() return self.text or "" end
function widgetMethods:SetScript(key, callback)
    self.scripts[key] = callback
    if key == "OnEvent" then state.events = self end
end
function widgetMethods:HookScript(key, callback)
    self.hooks[key] = self.hooks[key] or {}
    self.hooks[key][#self.hooks[key] + 1] = callback
end
function widgetMethods:Show()
    if self.shown then return end
    self.shown = true
    for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
end
function widgetMethods:Hide()
    if not self.shown then return end
    self.shown = false
    for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
end
function widgetMethods:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end
function widgetMethods:IsShown() return self.shown end
function widgetMethods:SetEnabled(enabled) self.enabled = enabled end
function widgetMethods:Click()
    if self.enabled == false then return end
    if self.onClick then self.onClick(self) end
end
function widgetMethods:RegisterEvent(event) self.events[event] = true end
function widgetMethods:UnregisterAllEvents() self.events = {} end
function widgetMethods:ClearFocus() self.focused = false end
function widgetMethods:HasFocus() return self.focused == true end
function widgetMethods:SetPoint(...)
    local points = rawget(self, "anchorPoints") or {}
    points[#points + 1] = { ... }
    rawset(self, "anchorPoints", points)
end
function widgetMethods:SetScrollChild(child) self.scrollChild = child end
function widgetMethods:SetSize(width, height)
    rawset(self, "width", width)
    rawset(self, "height", height)
end
function widgetMethods:SetHeight() end
function widgetMethods:GetStringHeight() return 600 end
function widgetMethods:SetNumeric() end
function widgetMethods:SetScale() end
function widgetMethods:SetJustifyH() end
function widgetMethods:SetJustifyV() end
function widgetMethods:SetWidth() end
function widgetMethods:SetMovable() end
function widgetMethods:SetFrameStrata() end
function widgetMethods:SetToplevel() end
function widgetMethods:SetClampedToScreen() end
function widgetMethods:EnableMouse() end
function widgetMethods:RegisterForDrag() end

local function widget()
    local item = { scripts = {}, hooks = {}, events = {}, shown = false }
    return setmetatable(item, { __index = function(_, key)
        return widgetMethods[key] or function() end
    end })
end

local parts = {}
function parts.Window()
    local frame = widget()
    frame.backdrop = widget()
    state.window = frame
    return frame
end
function parts.TitleBar(_, _, _, _, onClose)
    local close = widget()
    close.text = "X"
    close:SetPoint("RIGHT", state.window, "TOPRIGHT", -8, 0)
    close.onClick = function() state.window:Hide(); if onClose then onClose() end end
    state.buttons[#state.buttons + 1] = close
    return close
end
function parts.FooterBrand() end
local S = {}
function S.Get(key) return state.settings[key] end
function S.Set(key, value)
    state.settings[key] = value
    for _, listener in ipairs(state.listeners) do listener(key, value) end
end
function S.OnChange(listener)
    state.listeners = state.listeners or {}
    state.listeners[#state.listeners + 1] = listener
end

local catalog = {}
local catalogChunk = assert(loadfile("Core/Locales/enUS.lua"))
setfenv(catalogChunk, { _G = { NaowhForeverLocale = catalog } })
catalogChunk()
local untranslated = {}

local ns = {
    QoLSettings = S,
    THEME = { muted = {}, accent = {} },
    Shared = { Parts = parts, Style = { WINDOW_PAD = 12, WINDOW_HEADER = 52, WINDOW_FOOTER = 28,
        CONTENT_INSET = 22 },
        Settings = { Page = function() return { Card = function(_, spec) state.card = spec end } end } },
    UI = {},
}
function ns.L(text)
    if catalog[text] == nil then untranslated[#untranslated + 1] = text end
    return text
end
function ns.Font(parent)
    local font = widget()
    font.parent = parent
    if parent == state.controls and not state.poolLabel then state.poolLabel = font end
    if state.helpContent == parent then state.helpText = font end
    if parent == state.window then
        if not state.status then state.status = font else state.roster = font end
    end
    state.fonts[#state.fonts + 1] = font
    return font
end
function ns.NewEditBox(parent)
    local box = widget()
    box.parent = parent
    state.editboxes[#state.editboxes + 1] = box
    return box
end
function ns.Button(parent, text, width, height, onClick)
    local button = widget()
    button.parent, button.text, button.onClick = parent, text, onClick
    button:SetSize(width, height)
    state.buttons[#state.buttons + 1] = button
    return button
end
function ns.SetButtonText(button, text) button.text = text end
function ns.AccentBorder(button) return button end
function ns.UIScale() return 1 end
function ns.Print(text) state.prints[#state.prints + 1] = text end
function ns.StashOptionsWindow() state.optionsStashed = true end
function ns.UI.SlimScroll(parent)
    local scroll = widget()
    scroll.parent = parent
    state.helpScroll = scroll
    return scroll
end

local function Member(unit)
    if unit == "player" then return HOST end
    local index = tonumber(unit:match("^party(%d+)$"))
    return index and state.party[index]
end

local env = setmetatable({
    _G = { NaowhForever = ns },
    RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)",
    YOU_ROLL_RESULT = "You roll %d (%d-%d)",
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendChatMessage = function(text, channel) state.chats[#state.chats + 1] = { text, channel } end,
        SendAddonMessage = function(prefix, text, channel)
            state.addons[#state.addons + 1] = { prefix, text, channel }
        end,
    },
    CreateFrame = function(_, _, parent)
        local frame = widget()
        frame.parent = parent
        state.frames[#state.frames + 1] = frame
        if parent == state.window then
            if not state.controls then state.controls = frame else state.helpView = frame end
        end
        if parent == state.helpScroll then state.helpContent = frame end
        return frame
    end,
    issecretvalue = function(value) return state.secrets[value] == true end,
    UnitName = function(unit)
        local member = Member(unit)
        return member and member.first
    end,
    UnitFullName = function(unit)
        local member = Member(unit)
        if member then return member.first, member.surname end
    end,
    UnitGUID = function(unit)
        local member = Member(unit)
        return member and member.guid
    end,
    UnitIsConnected = function(unit) return state.disconnected[unit] ~= true end,
    GetNumGroupMembers = function() return #state.party + 1 end,
    GetNumSubgroupMembers = function() return #state.party end,
    GetNormalizedRealmName = function() return "Forever" end,
    Ambiguate = function(name, mode)
        return mode == "short" and (name:gsub("%-%w+$", "")) or name
    end,
    IsInRaid = function() return state.inRaid end,
    IsInGroup = function() return true end,
    GetTime = function() return 10 end,
    RandomRoll = function(minimum, maximum) state.roll = { minimum, maximum } end,
    strlower = string.lower,
    strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
    math = { floor = math.floor, abs = math.abs, min = math.min, random = function() return 1 end },
}, { __index = _G })
env._G = env
env.NaowhForever = ns
local function Load(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local chunk = assert(loadstring(source, path))
    setfenv(chunk, env)
    chunk()
end
Load("Core/Senders.lua")
Load("NaowhForever_QoL/Gambling/GambleHelp.lua")
Load("NaowhForever_QoL/Gambling/Gamble.lua")

local function Button(text)
    for _, button in ipairs(state.buttons) do
        if button.text == text then return button end
    end
    error("missing button: " .. text)
end

local function HasButton(text)
    for _, button in ipairs(state.buttons) do
        if button.text == text then return true end
    end
    return false
end

local function Event(event, ...)
    assert(state.events and state.events.events[event], "event not registered: " .. event)
    state.events.scripts.OnEvent(state.events, event, ...)
end

local function Say(text, member, event)
    Event(event or "CHAT_MSG_PARTY", text, member.first, "", "", "", "", 0, 0, "", 0, 1, member.guid)
end

local function Addon(message, member)
    Event("CHAT_MSG_ADDON", "NaowhGamble", message, "PARTY", member.first .. " " .. member.surname)
end

local function Roll(member, value, max)
    Event("CHAT_MSG_SYSTEM", ("%s rolls %d (1-%d)"):format(member.first, value, max or 1050))
end

local function Chat(text, channel)
    for i = #state.chats, 1, -1 do
        if state.chats[i][1]:find(text, 1, true) and (not channel or state.chats[i][2] == channel) then
            return true
        end
    end
    return false
end

local function Lit(text) return (text:gsub("%p", "%%%0")) end

local function LastAddon() return state.addons[#state.addons][2] end

local function Entries(...)
    local out = {}
    for i, member in ipairs({ ... }) do out[i] = member.guid .. ":" .. member.first end
    return table.concat(out, ",")
end

ns.ToggleGamble()
check("off by default, Gamble builds no frames", #state.frames == 0 and #state.prints == 1)
S.Set("gamble", true)
ns.ToggleGamble()
check("opening registers the session listeners", state.window:IsShown() and state.events.events.CHAT_MSG_SYSTEM)
state.optionsStashed = false
state.window:Hide()
state.card.rows[1].button()
check("Open closes the main options menu before opening Gamble",
    state.optionsStashed and state.window:IsShown())
check("the default pool setting is shown as gold and silver",
    state.editboxes[1]:GetText() == "200g00s")
local helpButton = Button("How to play")
local helpAnchor = rawget(helpButton, "anchorPoints")[1]
check("How to play is positioned next to the window close button",
    helpAnchor[1] == "RIGHT" and helpAnchor[2] == Button("X") and helpAnchor[3] == "LEFT")
check("the how-to-play text is loaded from its separate Gambling file",
    type(ns.GambleHelpText) == "string" and ns.GambleHelpText:find("CLASSIC", 1, true)
        and ns.GambleHelpText:find("DEATHROLL", 1, true)
        and ns.GambleHelpText:find("Cancel Session", 1, true))
helpButton:Click()
check("How to play replaces the game controls with the scrollable guide",
    state.helpView:IsShown() and not state.controls:IsShown()
        and state.helpText and state.helpText.text == ns.GambleHelpText
        and Button("Back to game").text == "Back to game")
Button("Back to game"):Click()
check("the guide can return to the game controls",
    not state.helpView:IsShown() and state.controls:IsShown() and HasButton("How to play"))
check("pool, chat and announce controls are inset within the Gamble card",
    state.controls and state.controls.parent == state.window
        and rawget(state.controls, "anchorPoints")[1][4] >= ns.Shared.Style.WINDOW_PAD + 8
        and -rawget(state.controls, "anchorPoints")[1][5] >= ns.Shared.Style.WINDOW_HEADER
            + ns.Shared.Style.WINDOW_PAD + 8
        and rawget(state.poolLabel, "anchorPoints")[1][4] == ns.Shared.Style.WINDOW_PAD
        and rawget(state.editboxes[1], "anchorPoints")[1][2] == state.poolLabel
        and state.editboxes[1].parent == state.controls
        and Button("Party Chat").parent == state.controls
        and Button("Announce Rolls").parent == state.controls
        and rawget(Button("Party Chat"), "anchorPoints")[1][1] == "LEFT"
        and rawget(Button("Party Chat"), "anchorPoints")[1][2] == state.editboxes[1]
        and rawget(Button("Party Chat"), "anchorPoints")[1][3] == "RIGHT"
        and rawget(Button("Announce Rolls"), "anchorPoints")[1][1] == "LEFT"
        and rawget(Button("Announce Rolls"), "anchorPoints")[1][2] == Button("Party Chat")
        and rawget(Button("Announce Rolls"), "anchorPoints")[1][3] == "RIGHT"
        and rawget(Button("Announce Rolls"), "anchorPoints")[1][4] == 10
        and rawget(Button("Announce Rolls"), "anchorPoints")[1][5] == 0
        and rawget(Button("Announce Rolls"), "height") == rawget(Button("Party Chat"), "height")
        and state.editboxes[2].parent == state.controls and state.editboxes[2]:GetText() == "join"
        and state.editboxes[3].parent == state.controls and state.editboxes[3]:GetText() == "leave"
        and HasButton("Game mode: Classic") and not HasButton("Options")
        and not HasButton("Join") and not HasButton("Roll for Me")
        and Button("Cancel Session").enabled == false)
local newAnchor = rawget(Button("New Game"), "anchorPoints")[1]
local lastAnchor = rawget(Button("Last Call"), "anchorPoints")[1]
local startAnchor = rawget(Button("Start Rolling"), "anchorPoints")[1]
local cancelAnchor = rawget(Button("Cancel Session"), "anchorPoints")[1]
check("the four session buttons share one centered bottom row",
    newAnchor[1] == "BOTTOMLEFT" and lastAnchor[1] == "BOTTOMLEFT"
        and startAnchor[1] == "BOTTOMLEFT" and cancelAnchor[1] == "BOTTOMLEFT"
        and newAnchor[3] == lastAnchor[3] and lastAnchor[3] == startAnchor[3]
        and startAnchor[3] == cancelAnchor[3] and lastAnchor[2] > newAnchor[2]
        and startAnchor[2] > lastAnchor[2] and cancelAnchor[2] > startAnchor[2]
        and cancelAnchor[2] + rawget(Button("Cancel Session"), "width") < 520)
Button("Party Chat"):Click()
check("chat channel selection switches from Party to Raid",
    S.Get("gambleChannel") == "RAID" and HasButton("Raid Chat"))
Button("Raid Chat"):Click()
check("chat channel selection cycles from Raid back to Party",
    S.Get("gambleChannel") == "PARTY" and HasButton("Party Chat"))
state.inRaid = true
local addonCount = #state.addons
Button("New Game"):Click()
check("Party chat is not offered as a partial-raid channel",
    #state.addons == addonCount and state.prints[#state.prints]:find("party or raid", 1, true) ~= nil)
state.inRaid = false
state.editboxes[1]:SetText("10g50s")
state.editboxes[1].scripts.OnEnterPressed()
check("pool accepts gold and silver and stores the normalized string",
    S.Get("gamblePool") == "10g50s" and state.editboxes[1]:GetText() == "10g50s")
state.editboxes[1]:SetText("10g5")
state.editboxes[1].scripts.OnEnterPressed()
check("pool rejects values that do not include both currency suffixes",
    S.Get("gamblePool") == "10g50s"
        and state.prints[#state.prints]:find("10g50s", 1, true) ~= nil)
state.editboxes[1]:SetText("10001g00s")
state.editboxes[1].scripts.OnEnterPressed()
check("the pool stops at 1,000,000 silver, the most /roll is given",
    S.Get("gamblePool") == "10g50s" and state.prints[#state.prints]:find("10000g00s", 1, true) ~= nil)
state.editboxes[1]:SetText("10g50s")
S.Set("gambleChannel", "UNSUPPORTED")
Button("New Game"):Click()
check("a new Classic session is announced in the selected channel",
    S.Get("gambleChannel") == "PARTY" and Chat("Classic, pool 10g50s", "PARTY")
        and LastAddon():match("^O|"))
check("the new-game announcement explains how to leave",
    Chat('Say "join" to join or "leave" to leave; use /roll when it\'s your turn.', "PARTY"))
check("the session announcement carries its join and leave words and the host's GUID",
    LastAddon():match("^O|[^|]+|1050|classic|join|leave|" .. Lit(HOST.guid) .. "$") ~= nil)
Button("Start Rolling"):Click()
check("Start Rolling explains when more players are needed",
    state.prints[#state.prints]:find("At least two players", 1, true) ~= nil)
local chatsBeforeJoin = #state.chats
Say("join", HOST)
Say("join", ALICE)
Say("join", BOB)
check("host and players join through group chat",
    state.roster.text == "Host\nAlice\nBob")
check("a join is not repeated in group chat", #state.chats == chatsBeforeJoin)
check("each join sends only that player to the group",
    LastAddon():match("^J|[^|]+|" .. Lit(BOB.guid) .. "|Bob$") ~= nil
        and state.addons[#state.addons - 1][2]:match("^J|[^|]+|" .. Lit(ALICE.guid) .. "|Alice$") ~= nil)
local addonsBeforeQuery = #state.addons
Addon("Q", ALICE)
check("a window that opens late gets the session and whole roster",
    state.addons[addonsBeforeQuery + 1][2]:match("^O|")
        and state.addons[addonsBeforeQuery + 2][2]:match("^R|[^|]+|1|1|1|(.+)$") == Entries(HOST, ALICE, BOB))
Say("leave", BOB)
check("leaving is said in chat and sent to the group",
    Chat("Bob left the Gamble session.", "PARTY") and LastAddon():match("^L|[^|]+|" .. Lit(BOB.guid) .. "$")
        and state.roster.text == "Host\nAlice")
Say("join", BOB)
Button("Start Rolling"):Click()
check("Start Rolling starts the Classic round when players joined",
    state.status.text == "Waiting for rolls")
check("round broadcasts keep the chunk protocol, keyed by GUID",
    LastAddon():match("^C|[^|]+|1|1050|1|1|(.+)$") == Entries(HOST, ALICE, BOB))
check("starting Classic announces that everyone can roll and the silver limit",
    Chat("Everyone can start rolling from 1 to 1050.", "PARTY"))
Button("Announce Rolls"):Click()
check("Classic announces only players still waiting and the roll range",
    Chat("Still need to roll: Host, Alice and Bob. Roll from 1 to 1050", "PARTY"))
Roll(HOST, 70)
check("the host's own roll counts though their name has a surname", state.roster.text:find("Host  70", 1, true) ~= nil)
Roll(HOST, 90)
check("Classic ignores a player's later reroll", state.roster.text:find("Host  70", 1, true) ~= nil)
Button("Announce Rolls"):Click()
check("Classic roll calls exclude players who already rolled",
    Chat("Still need to roll: Alice and Bob. Roll from 1 to 1050", "PARTY"))
state.secrets["Alice rolls 5 (1-1050)"] = true
Event("CHAT_MSG_SYSTEM", "Alice rolls 5 (1-1050)")
state.secrets = {}
check("a secret roll line is skipped", not state.roster.text:find("Alice  5", 1, true))
Roll(ALICE, 90)
Roll(BOB, 20)
check("Classic settlement converts a silver difference to gold and silver",
    Chat("Bob pays Alice 0g70s", "PARTY"))

Button("New Game"):Click()
Say("join", HOST)
Say("join", ALICE)
Button("Start Rolling"):Click()
local chatsBeforeTie = #state.chats
Event("CHAT_MSG_SYSTEM", "You roll 300 (1-1050)")
Roll(ALICE, 300)
check("when everyone ties, the round is rolled again and nobody pays",
    #state.chats == chatsBeforeTie + 1 and Chat("Everyone rolled 300: roll again from 1 to 1050.", "PARTY")
        and LastAddon():match("^C|[^|]+|2|1050|1|1|(.+)$") == Entries(HOST, ALICE)
        and state.status.text == "Waiting for rolls" and not state.roster.text:find("300", 1, true))
Event("CHAT_MSG_SYSTEM", "You roll 40 (1-1050)")
Roll(ALICE, 10)
check("the reroll settles the game", Chat("Alice pays Host 0g30s", "PARTY"))

Button("New Game"):Click()
Say("join", HOST)
Say("join", ALICE)
Say("join", BOB)
Button("Start Rolling"):Click()
Roll(HOST, 20)
Roll(ALICE, 90)
Roll(BOB, 90)
check("a tied high side rerolls only its tied players",
    LastAddon():match("^C|[^|]+|2|1050|1|1|(.+)$") == Entries(ALICE, BOB))
local settlementsBeforeTieBreak = #state.chats
Roll(ALICE, 10)
Roll(BOB, 100)
check("a high-side tie-break keeps the original spread and unique low",
    #state.chats == settlementsBeforeTieBreak + 1
        and Chat("Host pays Bob 0g70s", "PARTY"))

Button("New Game"):Click()
Say("join", HOST)
Say("join", ALICE)
Say("join", BOB)
Say("join", GUEST)
Button("Start Rolling"):Click()
Roll(HOST, 20)
Roll(ALICE, 90)
Roll(BOB, 90)
Roll(GUEST, 20)
Roll(ALICE, 50)
Roll(BOB, 70)
check("when both extremes tie, the low-side reroll excludes the resolved high side",
    LastAddon():match("^C|[^|]+|3|1050|1|1|(.+)$") == Entries(HOST, GUEST))
Roll(HOST, 20)
Roll(GUEST, 10)
check("both tie-breaks preserve the original high-low settlement amount",
    Chat("Guest pays Bob 0g70s", "PARTY"))

state.editboxes[2]:SetText("ready|bad")
state.editboxes[3]:SetText("gone")
state.editboxes[2].scripts.OnEnterPressed()
check("inline join words reject addon-message delimiters",
    S.Get("gambleJoinWord") == "join" and state.prints[#state.prints]:find("without |", 1, true) ~= nil)
state.editboxes[2]:SetText("ready")
state.editboxes[2].scripts.OnEnterPressed()
check("inline join and leave words save from the main window",
    S.Get("gambleJoinWord") == "ready" and S.Get("gambleLeaveWord") == "gone")
Button("Game mode: Classic"):Click()
check("the main-window mode button switches to Deathroll",
    S.Get("gambleMode") == "deathroll" and HasButton("Game mode: Deathroll"))
Button("New Game"):Click()
check("custom join and leave words are announced for a new game",
    Chat('Say "ready" to join or "gone" to leave; use /roll when it\'s your turn.', "PARTY"))
state.secrets.ready = true
Say("ready", HOST)
state.secrets = {}
check("a secret chat line is skipped without joining anyone", state.roster.text == "No players have joined yet.")
Say("ready", HOST)
Say("ready", ALICE)
Button("Start Rolling"):Click()
check("Deathroll starts and waits for its first /roll",
    state.status.text == "Deathroll in progress")
local duelAnnouncement = state.chats[#state.chats - 1]
local starterAnnouncement = state.chats[#state.chats]
check("Deathroll announces the two randomly selected participants first",
    duelAnnouncement[1] == "Deathroll: Host and Alice are playing for 10g50s."
        and duelAnnouncement[2] == "PARTY")
check("Deathroll then announces its randomly selected first roller and range",
    starterAnnouncement[1] == "Host was randomly selected to roll first. Roll from 1 to 1050."
        and starterAnnouncement[2] == "PARTY"
        and state.addons[#state.addons - 1][2]:match("|" .. Lit(HOST.guid) .. "|" .. Lit(ALICE.guid) .. "|" .. Lit(HOST.guid) .. "$")
        and LastAddon():match("^T|[^|]+|1050|" .. Lit(HOST.guid) .. "$"))
Event("CHAT_MSG_SYSTEM", "You roll 40 (1-1050)")
check("Deathroll does not automatically announce every next turn", not Chat("Alice, roll", "PARTY"))
Addon("Q", ALICE)
check("a late window is told whose turn is next, not who rolled first",
    state.addons[#state.addons - 1][2]:match("^M|[^|]+|1050|" .. Lit(HOST.guid) .. "|" .. Lit(ALICE.guid) .. "|"
        .. Lit(ALICE.guid) .. "$")
        and LastAddon():match("^T|[^|]+|40|" .. Lit(ALICE.guid) .. "$"))
Button("Announce Rolls"):Click()
check("Deathroll announces the current player and their roll range on demand",
    Chat("Alice, roll from 1 to 40", "PARTY"))
Roll(ALICE, 1, 40)
check("rolling 1 pays the full Deathroll pool",
    Chat("Alice pays Host 10g50s", "PARTY"))

state.secrets.NaowhGamble = true
Addon("O|secret|200|classic|ready|gone|" .. GUEST.guid, GUEST)
state.secrets = {}
check("a secret addon prefix is skipped", state.status.text == "Session complete")
Addon("O|forged|200|classic|ready|gone|" .. BOB.guid, GUEST)
check("a session sent for someone else's GUID is ignored", state.status.text == "Session complete")
Addon("O|remote|200|classic|ready|gone|" .. GUEST.guid, GUEST)
check("players use the advertised chat join word instead of a Join button",
    not HasButton("Join") and state.status.text == "Waiting for players to join")
Addon("J|remote|" .. ALICE.guid .. "|Alice", ALICE)
check("only the host can change the roster", state.roster.text == "No players have joined yet.")
Addon("J|remote|" .. ALICE.guid .. "|Alice", GUEST)
check("a join from the host adds that player", state.roster.text == "Alice")
local localRoster = state.roster.text
Addon("R|remote|1|1|2|" .. Entries(GUEST, ALICE), GUEST)
check("a partial roster waits for every chunk", state.roster.text == localRoster)
Addon("R|remote|1|2|2|" .. Entries(BOB, CHARLIE), GUEST)
check("chunked rosters assemble before display", state.roster.text == "Guest\nAlice\nBob\nCharlie")
Addon("L|remote|" .. CHARLIE.guid, GUEST)
check("a leave from the host drops that player", state.roster.text == "Guest\nAlice\nBob")
Event("GROUP_ROSTER_UPDATE")
check("the host stays connected across a roster update", state.status.text == "Waiting for players to join")
Addon("C|remote|1|100|1|2|" .. Entries(GUEST, ALICE), GUEST)
Addon("C|remote|1|100|2|2|" .. Entries(BOB), GUEST)
check("chunked roll rounds accept player /roll messages",
    state.status.text == "Waiting for rolls" and state.events.events.CHAT_MSG_SYSTEM and not HasButton("Roll for Me"))
Roll(ALICE, 42, 100)
check("a client counts the rolls it sees", state.roster.text:find("Alice  42", 1, true) ~= nil)
Event("UNIT_CONNECTION", "party1", true)
check("a joined client keeps its session while the host is online", state.status.text == "Waiting for rolls")

Button("X"):Click()
check("closing keeps listeners active for the joined session",
    not state.window:IsShown() and state.events.events.CHAT_MSG_ADDON)
Addon("D|remote|Bob|Alice|10", GUEST)
check("a completed session unregisters hidden-window listeners", next(state.events.events) == nil)

ns.ToggleGamble()
Addon("O|host-left|200|classic|ready|gone|" .. GUEST.guid, GUEST)
state.party = { ALICE, BOB }
Event("GROUP_ROSTER_UPDATE")
check("a remote session ends when its host leaves the group",
    state.status.text == "Host left; session ended." and Button("New Game").enabled)
state.party = { ALICE, BOB, GUEST }
Addon("O|host-offline|200|classic|ready|gone|" .. GUEST.guid, GUEST)
local hostOnline = state.status.text
Button("New Game"):Click()
check("a second host cannot start a session while the first is online",
    hostOnline == "Waiting for players to join" and state.prints[#state.prints]:find("Only the session host", 1, true))
state.disconnected.party3 = true
Event("UNIT_CONNECTION", "party3", false)
check("a remote session ends when its host disconnects",
    state.status.text == "Host left; session ended." and Button("New Game").enabled)
state.disconnected = {}
Button("New Game"):Click()
check("a new local session can start after the remote host disappears",
    state.status.text == "Waiting for players to join" and LastAddon():match("^O|"))
S.Set("gambleMode", "classic")
Button("New Game"):Click()
Say("ready", HOST)
Say("ready", ALICE)
Button("Start Rolling"):Click()
check("the host can cancel an active session",
    Button("Cancel Session").enabled and state.status.text == "Waiting for rolls")
Button("Cancel Session"):Click()
check("cancelling closes the session and announces it to the group",
    state.status.text == "Session cancelled"
        and Chat("Gamble session cancelled by Host", "PARTY")
        and LastAddon():match("^X|"))
check("cancel is disabled after the session ends", Button("Cancel Session").enabled == false)

check("every string Gamble translates is in the English catalog", #untranslated == 0)
local card = state.card
for _, text in ipairs({ card.name, card.help, card.rows[1].label, card.rows[1].buttonText, card.rows[1].help,
        "/nf gamble: open Gamble" }) do
    check("in the English catalog: " .. text, catalog[text] ~= nil)
end
print(("test-gamble: %d checks passed"):format(checks))
