-- Store.lua: the game's macros, the pack's and the Library's, and the icon each one shows (ns.Macros.Store).
local ns = _G.NaowhForever

local M = ns.Macros
local S = M.Settings
local QUESTION = M.C.QUESTION

local function Limits()
    return Constants.MacroConsts.MAX_ACCOUNT_MACROS, Constants.MacroConsts.MAX_CHARACTER_MACROS
end

local function Usable(name)
    return name and name ~= "" and not name:find("^%d+$")
end

local function BodyIcon(body)
    local item = body:match("item:(%d+)")
    if item then return C_Item.GetItemIconByID(tonumber(item)) or QUESTION end
    local named = body:match("#showtooltip%s+([^\n]+)") or body:match("/cast%s+%[[^\n]-%]%s*([^;\n%[]+)")
        or body:match("/cast%s+([^;\n%[]+)")
    named = named and strtrim(named)
    if Usable(named) then
        return C_Spell.GetSpellTexture(named) or C_Item.GetItemIconByID(named) or QUESTION
    end
    local used = body:match("/use%s+%[?[^\n]-%]?%s*([^;\n%[%]]+)")
    used = used and strtrim(used)
    return Usable(used) and C_Item.GetItemIconByID(used) or QUESTION
end

local function ShownIcon(index, icon, body)
    if icon and icon ~= QUESTION then return icon end
    local spell = index and GetMacroSpell(index)
    if spell then return C_Spell.GetSpellTexture(spell) or QUESTION end
    return BodyIcon(body or "")
end

local function GameMacros()
    local maxAccount, maxCharacter = Limits()
    local list = {}
    for index = 1, maxAccount + maxCharacter do
        local name, icon, body = GetMacroInfo(index)
        if name then
            list[#list + 1] = { index = index, account = index <= maxAccount, name = name, icon = icon,
                body = body or "" }
        end
    end
    return list
end

local function Find(name, body, account)
    local maxAccount, maxCharacter = Limits()
    local from, to = account and 1 or maxAccount + 1, account and maxAccount or maxAccount + maxCharacter
    for index = from, to do
        local n, _, b = GetMacroInfo(index)
        if n == name and b == body then return index end
    end
end

local function Room(account)
    local accountCount, characterCount = GetNumMacros()
    local maxAccount, maxCharacter = Limits()
    if account then return accountCount < maxAccount end
    return characterCount < maxCharacter
end

local function PackMacros(class)
    return (S.Get("classMacros") or {})[class] or {}
end

local function OwnMacros(class)
    local own = ns.AccountSettings().libraryMacros
    return own and own[class] or {}
end

local function NameFits(name)
    return name ~= "" and #name <= M.C.NAME_MAX
end

local function BodyFits(body)
    return body ~= "" and #body <= M.C.LIMIT
end

M.Store = { Limits = Limits, BodyIcon = BodyIcon, ShownIcon = ShownIcon, GameMacros = GameMacros, Find = Find,
    Room = Room, PackMacros = PackMacros, OwnMacros = OwnMacros, NameFits = NameFits, BodyFits = BodyFits }
