-- Text.lua: reading a macro's text (ns.MacroText): the lines that will not work, each line in plain words, the editor's colors and a shorter spelling.
local ns = _G.NaowhForever

local M = ns.Macros
local C = M.C

local LIMIT = C.LIMIT
local SCRIPT = C.SCRIPT_COMMANDS
local NEAR = 2
local COLOR_CODE_LEN, RESET_LEN, ESCAPED_BAR_LEN = 10, 2, 2
local SHOWTOOLTIP, SHOW, CANCELAURA, CLICK = "#showtooltip", "#show", "/cancelaura", "/click"
local TARGET_SUFFIX, PET_SUFFIX, NEGATION = "target", "pet", "no"
local TARGET_END, PET_END, NEGATED = TARGET_SUFFIX .. "$", PET_SUFFIX .. "$", "^" .. NEGATION .. "(.+)$"
local RIGHT_BUTTON = "2"

local SPELL, WHO, WHEN = "|cff6cc4ff", "|cffffb36b", "|cfff2d36b"
local SHOW_CODE, COMMAND_CODE = "|cff7bd88f", "|cff6cc4ff"
local RESET = "|r"

local TEXT_OVER = "%d bytes over the game's %d: the end is cut off."
local TEXT_HASH = "Only #showtooltip and #show do anything; other # lines are skipped."
local TEXT_NO_SLASH = "Does nothing: a line has to start with /."
local TEXT_UNKNOWN_COMMAND = "%s is not a command the game knows"
local TEXT_BRACKETS = "%d [ but %d ]: a bracket is missing."
local TEXT_UNKNOWN_UNIT = "@%s is not a unit the game knows. Did you mean @%s?"
local TEXT_UNKNOWN_CONDITION = "%s is not a condition the game knows"
local TEXT_DID_YOU_MEAN = ". Did you mean %s?"
local TEXT_SHOWTOOLTIP = "Shows %s on the button, with its tooltip and cooldown."
local TEXT_SHOWTOOLTIP_ANY = "Shows what the macro will cast on the button, with its tooltip and cooldown."
local TEXT_SHOW = "Shows %s on the button."
local TEXT_SEQUENCE = "Casts %s, one per press%s."
local TEXT_SEQUENCE_RESET = ", starting over after %s"
local TEXT_CANCELAURA = "Removes %s from you."
local TEXT_FOCUS = "Sets your focus to"
local TEXT_MARKER = "Puts raid marker %s"
local TEXT_ANY_MARKER = "Puts a raid marker (1 to 8)"
local TEXT_MARKER_ON = "%s on %s."
local TEXT_CLICK = "Clicks %s for you."
local TEXT_SCRIPT = "Runs a script (Lua)."
local TEXT_RUNS = "Runs %s."
local TEXT_IT, TEXT_YOUR_TARGET, TEXT_YOUR_FOCUS = "it", "your target", "your focus"
local TEXT_OTHERWISE_TO, TEXT_OTHERWISE_ON = "otherwise to ", "otherwise on "

local CONDITIONS = {}
for _, word in ipairs({ "help", "harm", "exists", "dead", "combat", "mod", "modifier", "mounted", "outdoors",
    "indoors", "stealth", "channeling", "channel", "form", "stance", "btn", "button", "group", "swimming",
    "flying", "flyable", "pet", "equipped", "worn", "known", "spec", "talent", "actionbar", "bar", "bonusbar",
    "cursor", "extrabar", "party", "raid", "resting", "unithasvehicleui", "vehicleui", "petbattle", "overridebar",
    "possessbar", "shapeshift", "canexitvehicle" }) do
    CONDITIONS[word] = true
end

local UNITS = { player = true, target = true, focus = true, mouseover = true, pet = true, cursor = true,
    none = true, vehicle = true, targettarget = true, focustarget = true, pettarget = true,
    mouseovertarget = true }

local UNIT_PATTERNS = { "^party%d$", "^raid%d+$", "^arena%d$", "^boss%d$", "^partypet%d$", "^raidpet%d+$",
    "^nameplate%d+$" }

local UNIT_WORDS = { player = "yourself", target = "your target", focus = "your focus",
    mouseover = "the unit under your mouse", targettarget = "your target's target", pet = "your pet",
    cursor = "the spot under your cursor", focustarget = "your focus's target", none = "no one" }

local SIMPLE = {
    help = "it is friendly", harm = "it is hostile", exists = "it exists", noexists = "there is none",
    dead = "it is dead", nodead = "it is alive", combat = "you are in combat", nocombat = "you are out of combat",
    mod = "you hold a modifier key", modifier = "you hold a modifier key", nomod = "you hold no modifier key",
    nomodifier = "you hold no modifier key", mounted = "you are mounted", nomounted = "you are not mounted",
    outdoors = "you are outdoors", indoors = "you are indoors", stealth = "you are stealthed",
    nostealth = "you are not stealthed", channeling = "you are channeling", nochanneling = "you are not channeling",
    group = "you are in a group", nogroup = "you are not in a group", pet = "you have a pet", nopet = "you have no pet",
    swimming = "you are swimming", noswimming = "you are not swimming", resting = "you are resting",
}

local CONDITIONAL = {}
for _, command in ipairs({ "/cast", "/use", "/castsequence", "/castrandom", "/userandom", "/target", "/targetenemy",
    "/targetfriend", "/targetparty", "/targetraid", "/targetexact", "/focus", "/assist", "/startattack",
    "/stopattack", "/petattack", "/petfollow", "/petstay", "/petpassive", "/petdefensive", "/petaggressive",
    "/cancelaura", "/cancelform", "/stopcasting", "/stopmacro", "/click", "/equip", "/equipslot", "/dismount",
    "/tm", "/cleartarget", "/clearfocus" }) do
    CONDITIONAL[command] = true
end

local function Spell(text) return SPELL .. text .. RESET end

local function Unit(word)
    word = word:lower()
    if UNITS[word] then return true end
    for i = 1, #UNIT_PATTERNS do
        if word:find(UNIT_PATTERNS[i]) then return true end
    end
    if word:find(TARGET_END) and Unit(word:sub(1, -#TARGET_SUFFIX - 1)) then return true end
    return word:find(PET_END) and Unit(word:sub(1, -#PET_SUFFIX - 1))
end

local function Distance(a, b)
    if math.abs(#a - #b) > NEAR then return NEAR + 1 end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            local cost = a:byte(i) == b:byte(j) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[#b]
end

local function Nearest(word, set)
    local best, bestDistance = nil, NEAR + 1
    for candidate in pairs(set) do
        local d = Distance(word, candidate)
        if d < bestDistance then best, bestDistance = candidate, d end
    end
    return best
end

local function DidYouMean(guess)
    return guess and TEXT_DID_YOU_MEAN:format(guess) or "."
end

local function Add(issues, line, kind, text)
    issues[#issues + 1] = { line = line, kind = kind, text = text }
end

local function IsShowLine(text)
    local lower = text:lower()
    return lower:find("^#showtooltip") or lower:find("^#show[%s]") or lower == SHOW
end

local function CheckPart(issues, n, part)
    part = strtrim(part):lower()
    local unit = part:match("^@(.+)$") or part:match("^target=(.+)$")
    if unit then
        local guess = not Unit(unit) and Nearest(unit, UNITS)
        if guess then Add(issues, n, "warning", TEXT_UNKNOWN_UNIT:format(unit, guess)) end
        return
    end
    if part == "" then return end
    local word = part:match("^([%a]+)")
    local base = word and (CONDITIONS[word] and word or word:match(NEGATED))
    if word and CONDITIONS[base or ""] then return end
    local guess = word and Nearest(word, CONDITIONS)
    Add(issues, n, "warning", TEXT_UNKNOWN_CONDITION:format(part) .. DidYouMean(guess))
end

local function CheckBrackets(issues, n, text)
    local _, open = text:gsub("%[", "")
    local _, close = text:gsub("%]", "")
    if open ~= close then Add(issues, n, "error", TEXT_BRACKETS:format(open, close)) end
    for group in text:gmatch("%[([^%]]*)%]") do
        for part in group:gmatch("[^,]+") do CheckPart(issues, n, part) end
    end
end

local function CheckCommand(issues, n, text, known)
    local command = text:match("^(/[^%s%[]+)")
    if not command then
        Add(issues, n, "warning", TEXT_NO_SLASH)
        return
    end
    command = command:lower()
    if not (known[command] or command:find("^/%d+$")) then
        Add(issues, n, "warning", TEXT_UNKNOWN_COMMAND:format(command) .. DidYouMean(Nearest(command, known)))
    end
    if not SCRIPT[command] then CheckBrackets(issues, n, text) end
end

local function CheckLine(issues, n, line, known)
    local text = strtrim(line)
    if text:sub(1, 1) == "#" then
        if not IsShowLine(text) then Add(issues, n, "warning", TEXT_HASH) end
    elseif text ~= "" then
        CheckCommand(issues, n, text, known)
    end
end

local function Condition(part)
    part = strtrim(part):lower()
    if SIMPLE[part] then return SIMPLE[part] end
    local word, value = part:match("^(%a+):(.+)$")
    if word == "mod" or word == "modifier" then
        return "you hold " .. value:gsub("^%l", string.upper)
    elseif word == "btn" or word == "button" then
        return value == RIGHT_BUTTON and "you right-click" or ("you click with button " .. value)
    elseif word == "stance" or word == "form" then
        return "you are in " .. word .. " " .. value
    elseif word == "noform" or word == "nostance" then
        return "you are not in " .. word:sub(#NEGATION + 1) .. " " .. value
    elseif word == "equipped" or word == "worn" then
        return "you have " .. value .. " equipped"
    end
    return part
end

local function Groups(clause)
    local said = {}
    while true do
        local inner, rest = clause:match("^%[([^%]]*)%]%s*(.*)$")
        if not inner then break end
        local unit, conditions = nil, {}
        for part in inner:gmatch("[^,]+") do
            local u = strtrim(part):match("^@(.+)$") or strtrim(part):match("^[Tt]arget=(.+)$")
            if u then unit = u:lower() elseif strtrim(part) ~= "" then conditions[#conditions + 1] = Condition(part) end
        end
        said[#said + 1] = { unit = unit, conditions = conditions }
        clause = rest
    end
    return said, clause
end

local function Clause(clause, verb, lead)
    local said, rest = Groups(strtrim(clause))
    local what = Spell(rest ~= "" and rest or TEXT_IT)
    if #said == 0 then
        if not lead then return verb .. " " .. what end
        return lead .. " " .. WHO .. (rest ~= "" and (UNIT_WORDS[rest:lower()] or rest) or TEXT_YOUR_TARGET) .. RESET
    end
    local out = {}
    for i, group in ipairs(said) do
        local who = WHO .. (group.unit and (UNIT_WORDS[group.unit] or ("@" .. group.unit)) or TEXT_YOUR_TARGET) .. RESET
        local first = lead and (lead .. " ") or (verb .. " " .. what .. " on ")
        local part = (i == 1 and first or (lead and TEXT_OTHERWISE_TO or TEXT_OTHERWISE_ON)) .. who
        if #group.conditions > 0 then
            part = part .. " if " .. WHEN .. table.concat(group.conditions, " and ") .. RESET
        end
        out[#out + 1] = part
    end
    return table.concat(out, ", ")
end

local function ExplainShowtooltip(text)
    local what = strtrim(text:sub(#SHOWTOOLTIP + 1))
    return what ~= "" and TEXT_SHOWTOOLTIP:format(Spell(what)) or TEXT_SHOWTOOLTIP_ANY
end

local function ExplainShow(text)
    return TEXT_SHOW:format(Spell(strtrim(text:sub(#SHOW + 1))))
end

local function ExplainCast(text, lower)
    local verb = lower:find("^/use") and "Uses" or "Casts"
    local parts = {}
    for clause in (text:match("^/%a+%s+(.*)$") .. ";"):gmatch("([^;]*);") do
        if strtrim(clause) ~= "" then
            parts[#parts + 1] = Clause(clause, #parts == 0 and verb or ("or " .. verb:lower()))
        end
    end
    return table.concat(parts, "; ") .. "."
end

local function ExplainSequence(text)
    local reset, list = text:match("^/%a+%s+reset=(%S+)%s+(.*)$")
    list = list or text:match("^/%a+%s+(.*)$") or ""
    local spells = {}
    for spell in list:gmatch("[^,]+") do spells[#spells + 1] = Spell(strtrim(spell)) end
    return TEXT_SEQUENCE:format(table.concat(spells, ", then "), reset and TEXT_SEQUENCE_RESET:format(reset) or "")
end

local function ExplainCancelaura(text)
    return TEXT_CANCELAURA:format(Spell(strtrim(text:sub(#CANCELAURA + 1))))
end

local function ExplainFocus(text)
    return Clause(text:match("^/%a+%s*(.*)$"), nil, TEXT_FOCUS) .. "."
end

local function ExplainMarker(text)
    local marker = text:match("(%d+)%s*$")
    return TEXT_MARKER_ON:format(marker and TEXT_MARKER:format(marker) or TEXT_ANY_MARKER,
        text:find("@focus") and TEXT_YOUR_FOCUS or TEXT_YOUR_TARGET)
end

local function ExplainClick(text)
    return TEXT_CLICK:format(Spell(strtrim(text:sub(#CLICK + 1))))
end

local EXPLAIN = {
    { "^#showtooltip", ExplainShowtooltip },
    { "^#show", ExplainShow },
    { "^/stopcasting", "Stops your current cast, so the next line goes off at once." },
    { "^/cast ", ExplainCast },
    { "^/use ", ExplainCast },
    { "^/castsequence", ExplainSequence },
    { "^/cancelaura", ExplainCancelaura },
    { "^/startattack", "Starts your auto attack." },
    { "^/stopattack", "Stops your auto attack." },
    { "^/petattack", "Sends your pet to attack." },
    { "^/petfollow", "Calls your pet back to you." },
    { "^/focus", ExplainFocus },
    { "^/tm ", ExplainMarker },
    { "^/dismount", "Gets you off your mount." },
    { "^/click", ExplainClick },
}

local function Sentence(text)
    if text == "" then return nil end
    local lower = text:lower()
    for i = 1, #EXPLAIN do
        local pattern, say = EXPLAIN[i][1], EXPLAIN[i][2]
        if lower:find(pattern) then
            if type(say) == "string" then return say end
            return say(text, lower)
        end
    end
    if SCRIPT[lower:match("^(/%a+)") or ""] then return TEXT_SCRIPT end
    if text:sub(1, 1) ~= "/" then return nil end
    local command = text:match("^(/%S+)")
    return command and TEXT_RUNS:format(Spell(command))
end

local function ColorLine(line)
    line = line:gsub("|", "||")
    local lead, command, rest = line:match("^(%s*)(/[^%s%[]+)(.*)$")
    if line:match("^%s*#") then return SHOW_CODE .. line .. RESET end
    if not command then return line end
    if not SCRIPT[command:lower()] then rest = rest:gsub("%b[]", WHEN .. "%0" .. RESET) end
    return lead .. COMMAND_CODE .. command .. RESET .. rest
end

local function Walk(coded, step)
    local i, n = 1, #coded
    while i <= n do
        local size, letter = 1, coded:sub(i, i)
        if letter == "|" then
            local nxt = coded:sub(i + 1, i + 1)
            if nxt == "c" and coded:find("^|c%x%x%x%x%x%x%x%x", i) then
                size, letter = COLOR_CODE_LEN, nil
            elseif nxt == "r" then
                size, letter = RESET_LEN, nil
            elseif nxt == "|" then
                size = ESCAPED_BAR_LEN
            end
        end
        if step(i, size, letter) then return end
        i = i + size
    end
end

local function ShortenLine(line)
    local text = line:gsub("%s+$", "")
    if not CONDITIONAL[(text:match("^(/%a+)") or ""):lower()] then return text end
    text = text:gsub("[Tt]arget=", "@"):gsub("modifier:", "mod:"):gsub("button:", "btn:")
        :gsub("%s*;%s*", ";"):gsub("%[%s*", "["):gsub("%s*%]", "]")
    return (text:gsub("%b[]", function(group) return (group:gsub("%s*,%s*", ",")) end))
end

local MacroText = {}
ns.MacroText = MacroText

MacroText.LIMIT = LIMIT

function MacroText.Check(body, known)
    local issues = {}
    if #body > LIMIT then Add(issues, 0, "error", TEXT_OVER:format(#body - LIMIT, LIMIT)) end
    local n = 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        CheckLine(issues, n, line, known)
    end
    return issues
end

function MacroText.Explain(body)
    local out = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local sentence = Sentence(strtrim(line))
        if sentence then out[#out + 1] = sentence end
    end
    return out
end

function MacroText.Colorize(body)
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = ColorLine(line) end
    return table.concat(lines, "\n")
end

function MacroText.Strip(coded)
    local out = {}
    Walk(coded, function(_, _, letter) out[#out + 1] = letter end)
    return table.concat(out)
end

function MacroText.PlainPos(coded, at)
    local plain = 0
    Walk(coded, function(i, size, letter)
        if i + size - 1 > at then return true end
        if letter then plain = plain + 1 end
    end)
    return plain
end

function MacroText.CodedPos(coded, plain)
    if plain <= 0 then return 0 end
    local at, seen = #coded, 0
    Walk(coded, function(i, size, letter)
        if not letter then return end
        seen = seen + 1
        if seen ~= plain then return end
        at = i + size - 1
        return true
    end)
    return at
end

function MacroText.Shorten(body)
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = ShortenLine(line) end
    while lines[#lines] == "" do lines[#lines] = nil end
    return table.concat(lines, "\n")
end
