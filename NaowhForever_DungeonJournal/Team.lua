-- Team.lua: who was in your group and how they rolled, kept as short lines of text (J.Team).
local ns = _G.NaowhForever

local J = ns.Journal

local NO_ROLL = 4
local NO_ROLE = "N"
local ROLE_CODE = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local ORDER = { T = 1, H = 2, D = 3, N = 4 }
local FIELD, ENTRY = ",", ";"
local ME, WINNER = "m", "w"
local SEPARATORS = "[,;]"
local EACH_ENTRY = "[^;]+"
local REALM = "%-.*"
local MEMBER = "%s,%s,%s,%s"
local ROLL = "%s,%d,%s,%s,%s"

local buffer = {}

local function Add(unit, me)
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    if not name or issecretvalue(name) or not class or issecretvalue(class) then return end
    local role = UnitGroupRolesAssigned(unit)
    role = not issecretvalue(role) and ROLE_CODE[role] or NO_ROLE
    buffer[#buffer + 1] = MEMBER:format((name:gsub(SEPARATORS, "")), class, role, me and ME or "")
end

local function Joined()
    if #buffer == 0 then return nil end
    return table.concat(buffer, ENTRY)
end

local function AddRoll(info)
    local name, class = info.playerName, info.playerClass
    if not name or issecretvalue(name) then return end
    class = class and not issecretvalue(class) and class or ""
    buffer[#buffer + 1] = ROLL:format((name:gsub(REALM, ""):gsub(SEPARATORS, "")),
        info.state or NO_ROLL, info.roll or "", info.isWinner and WINNER or "", class)
end

local function Reset(out)
    local pool = out.pool or {}
    out.pool = pool
    for i = #out, 1, -1 do out[i] = nil end
    return pool
end

local function ByRole(a, b)
    if a.role ~= b.role then return ORDER[a.role] < ORDER[b.role] end
    if a.me ~= b.me then return a.me end
    return a.name < b.name
end

local Team = {}
J.Team = Team

function Team.RoleCode(role)
    return ROLE_CODE[role] or NO_ROLE
end

function Team.Now()
    wipe(buffer)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            Add(unit, UnitIsUnit(unit, "player"))
        end
    else
        Add("player", true)
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i, false) end
    end
    return Joined()
end

function Team.KeepRolls(drop)
    wipe(buffer)
    local infos = drop.rollInfos
    for i = 1, type(infos) == "table" and #infos or 0 do AddRoll(infos[i]) end
    return Joined()
end

function Team.ReadRolls(text, out)
    local pool = Reset(out)
    if type(text) ~= "string" then return out end
    for part in text:gmatch(EACH_ENTRY) do
        local name, state, roll, winner, class = strsplit(FIELD, part)
        state = tonumber(state)
        if name and name ~= "" and state then
            local n = #out + 1
            local entry = pool[n] or {}
            pool[n] = entry
            entry.name, entry.state, entry.roll, entry.winner = name, state, tonumber(roll), winner == WINNER
            entry.class = class ~= "" and class or nil
            out[n] = entry
        end
    end
    return out
end

function Team.Read(text, out)
    local pool = Reset(out)
    if type(text) ~= "string" then return out end
    for part in text:gmatch(EACH_ENTRY) do
        local name, class, role, flags = strsplit(FIELD, part)
        if name and name ~= "" and class and ORDER[role] then
            local n = #out + 1
            local member = pool[n] or {}
            pool[n] = member
            member.name, member.class, member.role, member.me = name, class, role, flags == ME
            out[n] = member
        end
    end
    table.sort(out, ByRole)
    return out
end
