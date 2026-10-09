-- Sharing.lua: one macro or many as a string to share, and a shared string read back as character macros (ns.Macros.Sharing).
local ns = _G.NaowhForever

local M = ns.Macros
local C = M.C
local Store = M.Store

local SHARE = "!NFM1!"
local SHARE_PATTERN = "^%s*" .. SHARE:gsub("!", "%%!") .. "(%S+)%s*$"
local VERSION = 1
local SHOWN_COMMANDS = 4
local DECODE_LIMITS = { maxChars = 100000, maxBytes = 1048576, maxDepth = 8, maxValues = 20000 }

local TEXT_NOT_A_STRING = "That is not a Naowh Forever macro string."
local TEXT_ADD = "Add %d %s as character macros?%s"
local TEXT_IN_COMBAT = "Macros can be added once the fight is over."
local TEXT_ADDED = "Added %d."
local TEXT_ADDED_SOME = "Added %d of %d: %s."
local TEXT_TAKEN = " a name you already have"
local TEXT_FULL = "character macros are full"
local TEXT_SCRIPT = "run%s a script"
local TEXT_WARNING = " %s %s: read %s in the editor before you use %s."
local TEXT_PROMPT = "Paste a Naowh Forever macro string"

local COMMAND_KINDS = {
    { kind = "own", text = "use%s Naowh Forever's own commands (%s)" },
    { kind = "addon", text = "use%s other addons' commands (%s)" },
    { kind = "unknown", text = "use%s commands the game does not know (%s)" },
}

local foundCommands = { own = {}, addon = {}, unknown = {} }

local function Codec()
    return LibStub("LibSerialize"), LibStub("LibDeflate")
end

local function Export(macros)
    local LS, LD = Codec()
    local out = {}
    for i, m in ipairs(macros) do out[i] = { name = m.name, body = m.body } end
    return SHARE .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({ v = VERSION, macros = out })))
end

local function ReadMacro(m)
    if type(m) ~= "table" or type(m.name) ~= "string" or type(m.body) ~= "string" then return end
    local name = m.name:gsub("[|\r\n]", "")
    if #name < 1 or #name > C.NAME_MAX or #m.body > C.LIMIT then return end
    return { name = name, body = m.body }
end

local function Decode(text)
    local body = type(text) == "string" and text:match(SHARE_PATTERN)
    local data = body and ns.Shared.Decode.String(body, DECODE_LIMITS)
    if not (type(data) == "table" and data.v == VERSION and type(data.macros) == "table") then return end
    local out = {}
    local maxAccount, maxCharacter = Store.Limits()
    for i, m in ipairs(data.macros) do
        if i > maxAccount + maxCharacter then return end
        out[i] = ReadMacro(m)
        if not out[i] then return end
    end
    return #out > 0 and out or nil
end

local function Note(command)
    local kind = ns.MacroCommandKind(command)
    if kind ~= "script" and kind then
        local list = foundCommands[kind]
        command = command:lower()
        if not list[command] and #list < SHOWN_COMMANDS then
            list[command] = true
            list[#list + 1] = command
        end
    end
    return kind
end

local function Flagged(m)
    local hit, script = false, false
    for line in m.body:gmatch("[^\n]+") do
        local command = line:match("^%s*(/[^%s%[]+)")
        local kind = command and Note(command)
        if kind == "script" then script = true end
        if kind then hit = true end
    end
    return hit, script
end

local function Joined(pieces)
    if #pieces == 1 then return pieces[1] end
    return table.concat(pieces, ", ", 1, #pieces - 1) .. " and " .. pieces[#pieces]
end

local function CommandWarning(macros)
    for _, list in pairs(foundCommands) do wipe(list) end
    local flagged, script = 0, false
    for _, m in ipairs(macros) do
        local hit, runs = Flagged(m)
        if runs then script = true end
        if hit then flagged = flagged + 1 end
    end
    if flagged == 0 then return "" end
    local s = flagged == 1 and "s" or ""
    local pieces = {}
    if script then pieces[1] = TEXT_SCRIPT:format(s) end
    for _, k in ipairs(COMMAND_KINDS) do
        local list = foundCommands[k.kind]
        if #list > 0 then pieces[#pieces + 1] = k.text:format(s, table.concat(list, ", ")) end
    end
    local it = flagged == 1 and "it" or "them"
    return TEXT_WARNING:format(flagged == 1 and "One" or "Some", Joined(pieces), it, it)
end

local function AddAll(macros)
    if InCombatLockdown() then ns.Print(TEXT_IN_COMBAT) return end
    local added, taken, full = 0, 0, 0
    for _, m in ipairs(macros) do
        if GetMacroIndexByName(m.name) > 0 then
            taken = taken + 1
        elseif Store.Room(false) then
            CreateMacro(m.name, C.QUESTION, m.body, true)
            added = added + 1
        else
            full = full + 1
        end
    end
    local why = {}
    if taken > 0 then why[#why + 1] = taken .. (taken == 1 and " uses" or " use") .. TEXT_TAKEN end
    if full > 0 then why[#why + 1] = TEXT_FULL end
    ns.Print(added == #macros and TEXT_ADDED:format(added)
        or TEXT_ADDED_SOME:format(added, #macros, table.concat(why, ", ")))
    M.Redraw()
end

function ns.ImportMacroString(text)
    local macros = Decode(text)
    if not macros then ns.Print(TEXT_NOT_A_STRING) return end
    ns.Confirm(TEXT_ADD:format(#macros, #macros == 1 and "macro" or "macros", CommandWarning(macros)),
        function() AddAll(macros) end)
end

local function Prompt()
    ns.PromptText(TEXT_PROMPT, "", 0, ns.ImportMacroString)
end

M.Sharing = { Export = Export, Prompt = Prompt }
