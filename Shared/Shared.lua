-- Shared.lua: the namespace every module shares (ns.Shared), what a character keeps by its GUID, and how long ago a time was.
local ns = _G.NaowhForever

local MINUTE, HOUR, DAY = 60, 3600, 86400
local WEEK_DAYS = 7
local DATE_FORMAT = "%d %b %Y"
local TEXT_JUST_NOW = "just now"
local TEXT_MINUTES = "%d min ago"
local TEXT_HOURS = "%d h ago"
local TEXT_YESTERDAY = "yesterday"
local TEXT_DAYS = "%d days ago"

local Shared = { Parts = {}, Kinds = {}, Items = {}, View = {} }
ns.Shared = Shared

local function Child(parent, key, create)
    local child = parent[key]
    if type(child) == "table" then return child end
    if not create then return nil end
    child = {}
    parent[key] = child
    return child
end

function Shared.CharacterData(key, create)
    local guid = UnitGUID("player")
    if not guid then return end
    local all = Child(ns.AccountSettings(), key, create)
    if not all then return end
    return Child(all, guid, create)
end

function Shared.Ago(when)
    local seconds = time() - when
    if seconds < MINUTE then return TEXT_JUST_NOW end
    if seconds < HOUR then return TEXT_MINUTES:format(math.floor(seconds / MINUTE)) end
    if seconds < DAY then return TEXT_HOURS:format(math.floor(seconds / HOUR)) end
    local days = math.floor(seconds / DAY)
    if days == 1 then return TEXT_YESTERDAY end
    if days < WEEK_DAYS then return TEXT_DAYS:format(days) end
    return date(DATE_FORMAT, when)
end
