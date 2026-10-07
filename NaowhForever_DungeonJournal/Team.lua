-------------------------------------------------------------------------------
--  Team.lua -- who was in your group, kept with a kill or an item (ns.Journal.Team): each
--  member's name, class and role, and which one was you. Kept as one short line of text
--  ("Emmy,PRIEST,H,;Die Man,ROGUE,D,m"), not a table per member: a heavy player keeps
--  thousands of them, and the same line from a run is one string in memory however often
--  it is kept.
--
--  Roles are the game's (the dungeon finder's, or set by hand): a member with none is listed
--  after those with one. Read back sorted as the group stands: tanks, healers, then damage,
--  you first in your role.
--
--  The group's rolls for an item are kept the same way, from the game's loot history
--  (C_LootHistory): "Ding,3,96,w,SHAMAN;Emmy,3,88,,DRUID", each roller's name, what they
--  rolled (Enum.EncounterLootDropRollState), the number, w on the winner, and their class.
-------------------------------------------------------------------------------
local J = _G.NaowhForever.Journal

local Team = {}
J.Team = Team

-- The game's role, as kept: Tank, Healer, Damage, or None.
local ROLE_CODE = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local ORDER = { T = 1, H = 2, D = 3, N = 4 }

---@param role string UnitGroupRolesAssigned's
---@return "T"|"H"|"D"|"N" code
function Team.RoleCode(role)
    return ROLE_CODE[role] or "N"
end

---@class JournalMember  One member of a team, read back by Team.Read.
---@field name string
---@field class string the class's file name ("PRIEST"), for its colour
---@field role "T"|"H"|"D"|"N"
---@field me boolean it was you

-------------------------------------------------------------------------------
--  Keeping
-------------------------------------------------------------------------------
local buffer = {}

-- A member as kept; nothing when the game keeps who they are secret.
local function Add(unit, me)
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    if not name or issecretvalue(name) or not class or issecretvalue(class) then return end
    local role = UnitGroupRolesAssigned(unit)
    role = not issecretvalue(role) and ROLE_CODE[role] or "N"
    -- The separators out of the name, though the game allows neither in one.
    buffer[#buffer + 1] = (name:gsub("[,;]", "")) .. "," .. class .. "," .. role .. "," .. (me and "m" or "")
end

-- Your group as it stands now, you included; you alone out of a group.
---@return string? team nil when the game says nothing of who you are
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
    if #buffer == 0 then return nil end
    return table.concat(buffer, ";")
end

-- A drop's rolls as kept (a C_LootHistory drop); nil when no one rolled.
---@param drop table EncounterLootDropInfo
---@return string? rolls
function Team.KeepRolls(drop)
    wipe(buffer)
    local infos = drop.rollInfos
    for i = 1, type(infos) == "table" and #infos or 0 do
        local info = infos[i]
        local name, class = info.playerName, info.playerClass
        if name and not issecretvalue(name) then
            class = class and not issecretvalue(class) and class or ""
            buffer[#buffer + 1] = ("%s,%d,%s,%s,%s"):format((name:gsub("%-.*", ""):gsub("[,;]", "")),
                info.state or 4, info.roll or "", info.isWinner and "w" or "", class)
        end
    end
    if #buffer == 0 then return nil end
    return table.concat(buffer, ";")
end

-------------------------------------------------------------------------------
--  Reading back
-------------------------------------------------------------------------------
local function ByRole(a, b)
    if a.role ~= b.role then return ORDER[a.role] < ORDER[b.role] end
    if a.me ~= b.me then return a.me end
    return a.name < b.name
end

---@class JournalRoll  One member's roll, read back by Team.ReadRolls.
---@field name string
---@field state number Enum.EncounterLootDropRollState: Need 0, off spec 1, Transmog 2, Greed 3, none 4, Pass 5
---@field roll? number
---@field winner boolean
---@field class? string kept from the roll, when the team did not keep them

-- The rolls kept for an item, in the order the game listed them (best first). Into out,
-- emptied first; its entries are reused by the next read into it.
---@param text? string as Team.KeepRolls made it
---@param out JournalRoll[]
---@return JournalRoll[] out
function Team.ReadRolls(text, out)
    local pool = out.pool or {}
    out.pool = pool
    for i = #out, 1, -1 do out[i] = nil end
    if type(text) ~= "string" then return out end
    for part in text:gmatch("[^;]+") do
        local name, state, roll, winner, class = strsplit(",", part)
        state = tonumber(state)
        if name and name ~= "" and state then
            local n = #out + 1
            local entry = pool[n] or {}
            pool[n] = entry
            entry.name, entry.state, entry.roll, entry.winner = name, state, tonumber(roll), winner == "w"
            entry.class = class ~= "" and class or nil
            out[n] = entry
        end
    end
    return out
end

-- The team kept in text, sorted: tanks, healers, damage, then those with no role; you
-- first in yours. Into out, emptied first; its members are reused by the next read into it.
---@param text? string as Team.Now made it; anything else reads as no one
---@param out JournalMember[]
---@return JournalMember[] out
function Team.Read(text, out)
    local pool = out.pool or {}
    out.pool = pool
    for i = #out, 1, -1 do out[i] = nil end
    if type(text) ~= "string" then return out end
    for part in text:gmatch("[^;]+") do
        local name, class, role, flags = strsplit(",", part)
        if name and name ~= "" and class and ORDER[role] then
            local n = #out + 1
            local member = pool[n] or {}
            pool[n] = member
            member.name, member.class, member.role, member.me = name, class, role, flags == "m"
            out[n] = member
        end
    end
    table.sort(out, ByRole)
    return out
end
