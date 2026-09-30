-- Offline behavior checks for Group XP; these do not emulate client taint, comms or rendering.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local NO_ADDON = "|cff9ca3afno addon|r"

local function boot(settings)
    local s = { now = 0, timers = {}, sent = {}, created = {}, combat = false, group = true,
        raid = false, settings = settings or {},
        units = {
            player = { name = "You", class = "PALADIN", level = 20, xp = 500, max = 1000 },
            party1 = { name = "Tank", class = "WARRIOR", level = 21 },
            party2 = { name = "Mage", realm = "OtherRealm", class = "MAGE", level = 19 },
        } }
    local function frame(kind, name, parent)
        local f = { kind = kind, parent = parent, scripts = {}, events = {}, fonts = {}, shown = true }
        setmetatable(f, { __index = function() return function() end end })
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(k) self.events[k] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:SetShown(v) self.shown = v and true or false end
        function f:SetSize(w, h) self.w, self.h = w, h end
        function f:SetText(t) self.text = t end
        function f:SetValue(v) self.value = v end
        return f
    end
    local ns = { THEME = { bg = {}, accent = { r = 0, g = 0.5, b = 1 } },
        Font = function(parent)
            local fs = frame("FontString", nil, parent)
            parent.fonts[#parent.fonts + 1] = fs
            return fs
        end,
        Solid = function() return frame("Texture") end, Border = function() return frame("Border") end,
        Apply = function() end, ShowRaidReminderAnchorConfig = function() end,
        HideRaidReminderAnchorConfig = function() end,
        UI = { AttachMover = function() return frame("Mover") end } }
    ns.QoLSettings = {
        Get = function(k)
            local v = s.settings[k]
            if v == nil then v = ({ enabled = true, groupXP = true, groupXPShowSelf = true, groupXPWidth = 260 })[k] end
            return v
        end,
        Set = function(k, v) s.settings[k] = v end,
    }
    local function partyCount()
        local n = 0
        while s.units["party" .. (n + 1)] do n = n + 1 end
        return n
    end
    local env = { _G = { NaowhForever = ns }, UIParent = frame("Parent"),
        CreateFrame = function(kind, name, parent)
            local f = frame(kind, name, parent)
            s.created[#s.created + 1] = f
            return f
        end,
        RAID_CLASS_COLORS = { PALADIN = { r = 1, g = 0.5, b = 0.7 }, WARRIOR = { r = 0.8, g = 0.6, b = 0.4 },
            MAGE = { r = 0.4, g = 0.8, b = 1 } },
        LE_PARTY_CATEGORY_INSTANCE = 2,
        IsInGroup = function(cat) return s.group and cat == nil end, IsInRaid = function() return s.raid end,
        GetNumSubgroupMembers = partyCount,
        GetNumGroupMembers = function() return partyCount() + 1 end,
        InCombatLockdown = function() return s.combat end,
        UnitLevel = function(u) return s.units[u] and s.units[u].level end,
        UnitXP = function() return s.units.player.xp end,
        UnitXPMax = function() return s.units.player.max end,
        UnitName = function(u) return s.units[u] and s.units[u].name end,
        UnitFullName = function(u) local d = s.units[u]; if d then return d.name, d.realm or "HomeRealm" end end,
        UnitClass = function(u) return "x", s.units[u] and s.units[u].class end,
        UnitIsUnit = function(a, b) return a == b end,
        GetNormalizedRealmName = function() return "HomeRealm" end,
        GetMaxLevelForPlayerExpansion = function() return 60 end,
        -- A string op, so a secret sender (a table here) reaching it errors the test.
        Ambiguate = function(name) return (name:gsub("%-HomeRealm$", "")) end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end end,
        issecretvalue = function(v) return type(v) == "table" and v.secret == true end,
        C_ChatInfo = { RegisterAddonMessagePrefix = function(p) s.prefix = p end,
            SendAddonMessage = function(p, msg, channel) s.sent[#s.sent + 1] = { p, msg, channel } end },
        C_Timer = { After = function(delay, fn) s.timers[#s.timers + 1] = { at = s.now + delay, fn = fn } end },
        hooksecurefunc = function(t, k, fn)
            local old = t[k]; t[k] = function(...) local r = old(...); fn(...); return r end
        end,
    }
    setmetatable(env, { __index = _G })
    local f = assert(io.open("QoL/NaowhForever_GroupXP.lua", "rb"))
    local src = f:read("*a"); f:close()
    local chunk = assert(loadstring(src, "GroupXP")); setfenv(chunk, env); chunk()
    local events, bootFrame = s.created[1], s.created[2]
    s.events = events
    s.S = ns.QoLSettings
    function s.fire(event, ...) events.scripts.OnEvent(events, event, ...) end
    function s.msg(msg, sender, channel) s.fire("CHAT_MSG_ADDON", "NaowhGroupXP", msg, channel or "PARTY", sender) end
    function s.run(seconds)
        s.now = s.now + seconds
        local due = {}
        for i = #s.timers, 1, -1 do
            if s.timers[i].at <= s.now then due[#due + 1] = table.remove(s.timers, i) end
        end
        for _, t in ipairs(due) do t.fn() end
    end
    -- What each shown row reads, "Name: bar text", top to bottom.
    function s.rows()
        local out = {}
        for _, bar in ipairs(s.created) do
            if bar.kind == "StatusBar" and bar.parent.shown then
                out[#out + 1] = bar.parent.fonts[1].text .. ": " .. bar.fonts[1].text
            end
        end
        return table.concat(out, " | ")
    end
    function s.messages()
        local out = {}
        for _, m in ipairs(s.sent) do out[#out + 1] = m[2] end
        return table.concat(out, ",")
    end
    bootFrame.scripts.OnEvent(bootFrame, "PLAYER_LOGIN")
    s.display = s.created[3]
    return s
end

do -- off: nothing registered, nothing built, nothing sent
    local s = boot({ groupXP = false })
    check("off registers no events", next(s.events.events) == nil)
    check("off builds no display", #s.created == 2)
    s.run(5)
    check("off sends nothing", #s.sent == 0)
end

do -- starting: asks the group and sends its own numbers, once, after the throttle
    local s = boot()
    check("prefix registered", s.prefix == "NaowhGroupXP")
    check("nothing sent before the throttle", #s.sent == 0)
    s.fire("PLAYER_ENTERING_WORLD")
    s.run(2)
    check("request then numbers", s.messages() == "R,1 20 500 1000")
    check("to the party", s.sent[1][3] == "PARTY" and s.sent[2][3] == "PARTY")
    for _ = 1, 10 do s.fire("PLAYER_XP_UPDATE") end
    s.run(2)
    check("a burst of XP updates is one send", s.messages() == "R,1 20 500 1000,1 20 500 1000")
    s.S.Set("groupXPWidth", 300)
    s.run(2)
    check("a setting change sends no request", select(2, s.messages():gsub("R", "")) == 1)
    s.sent = {}
    s.fire("PLAYER_ENTERING_WORLD")
    s.run(2)
    check("a loading screen asks again", s.messages() == "R,1 20 500 1000")
end

do -- answering: a request gets our numbers back, without asking again
    local s = boot()
    s.run(2)
    s.sent = {}
    s.msg("R", "Tank-HomeRealm")
    s.msg("R", "Mage-OtherRealm")
    s.run(2)
    check("two requests, one answer", s.messages() == "1 20 500 1000")
end

do -- display: yourself, a member with the addon, a member without it
    local s = boot()
    s.msg("1 21 300 1200", "Tank-HomeRealm")
    s.fire("CHAT_MSG_ADDON", "OtherPrefix", "1 50 1 2", "PARTY", "Mage-OtherRealm")
    s.msg("junk", "Mage-OtherRealm")
    s.msg("1 21 1 2", "Mage-OtherRealm", "WHISPER")
    check("rows read from the messages",
        s.rows() == "You: Lv 20  50.0% | Tank: Lv 21  25.0% | Mage: Lv 19  " .. NO_ADDON)
    s.msg("1 60 0 0", "Mage-OtherRealm")
    check("cross-realm sender matched, max level shown",
        s.rows() == "You: Lv 20  50.0% | Tank: Lv 21  25.0% | Mage: Lv 60  Max")
end

do -- ignored: a secret sender (it would reach Ambiguate and error)
    local s = boot()
    s.msg("1 21 300 1200", { secret = true })
    s.msg("1 21 300 1200", "Tank")
    check("secret sender ignored, Tank read",
        s.rows() == "You: Lv 20  50.0% | Tank: Lv 21  25.0% | Mage: Lv 19  " .. NO_ADDON)
end

do -- "O" drops the sender's bar
    local s = boot()
    s.msg("1 21 300 1200", "Tank-HomeRealm")
    s.msg("O", "Tank-HomeRealm")
    check("switched-off member shows no addon", s.rows():find("Tank: Lv 21  " .. NO_ADDON, 1, true) ~= nil)
end

do -- switching off tells the group, once
    local s = boot()
    s.run(2)
    s.sent = {}
    s.S.Set("groupXP", false)
    check("off sends O", s.messages() == "O")
    s.S.Set("enabled", false)
    check("only once", s.messages() == "O")
    s.S.Set("enabled", true); s.S.Set("groupXP", true)
    s.run(2)
    check("back on asks again", s.messages() == "O,R,1 20 500 1000")
end

do -- switched off in combat: the O waits for combat to end, and survives a second switch-off
    local s = boot()
    s.run(2)
    s.sent = {}
    s.combat = true
    s.S.Set("groupXP", false)
    s.S.Set("enabled", false)
    check("nothing sent in combat", #s.sent == 0)
    check("only combat's end is listened for", s.events.events.PLAYER_REGEN_ENABLED
        and not s.events.events.CHAT_MSG_ADDON)
    s.combat = false
    s.fire("PLAYER_REGEN_ENABLED")
    check("O sent once combat ends", s.messages() == "O")
    check("then nothing registered", next(s.events.events) == nil)
end

do -- switched off and back on within one fight: no O
    local s = boot()
    s.run(2)
    s.sent = {}
    s.combat = true
    s.S.Set("groupXP", false)
    s.S.Set("groupXP", true)
    s.combat = false
    s.fire("PLAYER_REGEN_ENABLED")
    s.run(2)
    check("no O, just the request and numbers", s.messages() == "R,1 20 500 1000")
end

do -- a member who leaves is dropped
    local s = boot()
    s.msg("1 21 300 1200", "Tank-HomeRealm")
    s.units.party1, s.units.party2 = s.units.party2, nil
    s.fire("GROUP_ROSTER_UPDATE")
    check("two rows after one leaves", s.rows() == "You: Lv 20  50.0% | Mage: Lv 19  " .. NO_ADDON)
    s.units.party2 = { name = "Tank", class = "WARRIOR", level = 21 }
    s.fire("GROUP_ROSTER_UPDATE")
    check("rejoining starts without old numbers", s.rows():find("Tank: Lv 21  " .. NO_ADDON, 1, true) ~= nil)
end

do -- combat: sends wait and go out once combat ends
    local s = boot()
    s.combat = true
    s.run(2)
    check("no send in combat", #s.sent == 0)
    s.combat = false
    s.fire("PLAYER_REGEN_ENABLED")
    check("sent when combat ends", s.messages() == "R,1 20 500 1000")
    s.fire("PLAYER_REGEN_ENABLED")
    check("only once", #s.sent == 2)
end

do -- solo: hidden, no send
    local s = boot()
    s.group = false
    s.units.party1, s.units.party2 = nil, nil
    s.fire("GROUP_ROSTER_UPDATE")
    s.run(2)
    check("hidden solo", not s.display.shown)
    check("no send solo", #s.sent == 0)
end

do -- Show Yourself off drops your row
    local s = boot({ groupXPShowSelf = false })
    s.fire("GROUP_ROSTER_UPDATE")
    check("no row for yourself", s.rows() == "Tank: Lv 21  " .. NO_ADDON .. " | Mage: Lv 19  " .. NO_ADDON)
end

print(("PASS group XP: %d checks"):format(checks))
