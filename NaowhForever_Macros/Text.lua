-- Text.lua: reading and writing a macro's text (M.Text): its lines as commands and conditions, what will not work, each line in plain words, what one press does, the editor's colors and a shorter spelling.
local ns = _G.NaowhForever

local M = ns.Macros
local C = M.C

local LIMIT = C.LIMIT
local SCRIPT = C.SCRIPT_COMMANDS
local NEAR = 2
local COLOR_CODE_LEN, RESET_LEN, ESCAPED_BAR_LEN = 10, 2, 2
local SHOWTOOLTIP, SHOW = "#showtooltip", "#show"
local NEGATION = "no"
local TARGET_SUFFIX, PET_SUFFIX = "target", "pet"
local DEFAULT_UNIT = "target"
local LEFT_BUTTON = "1"
local TRINKET_SLOTS = { ["13"] = 1, ["14"] = 2 }

local COMMAND_CODE, WHEN_CODE, WHO_CODE = "|cff6cc4ff", "|cfff2d36b", "|cffc4a0ff"
local SPELL_CODE, SHOW_CODE, MUTED_CODE = "|cff8fe0b0", "|cff8a9099", "|cff6e737c"
local RESET = "|r"

local TEXT_OVER = ns.L("%d bytes over the game's %d: the end is cut off.")
local TEXT_HASH = ns.L("Only #showtooltip and #show do anything; other # lines are skipped.")
local TEXT_SHOW_FIRST = ns.L("#showtooltip only works on the first line.")
local TEXT_NO_SLASH = ns.L("Does nothing: a line has to start with /.")
local TEXT_UNKNOWN_COMMAND = ns.L("%s is not a command the game knows")
local TEXT_BRACKETS = ns.L("%d [ but %d ]: a bracket is missing.")
local TEXT_UNKNOWN_UNIT = ns.L("@%s is not a unit the game knows")
local TEXT_UNKNOWN_CONDITION = ns.L("%s is not a condition the game knows")
local TEXT_NEEDS_AT = ns.L("[%s] needs an @ to aim at that unit: @%s.")
local TEXT_HELP_HARM = ns.L("help and harm in one bracket can never both be true.")
local TEXT_NOTHING = ns.L("%s has nothing to cast or use.")
local TEXT_DID_YOU_MEAN = ns.L(". Did you mean %s?")

local TEXT_SHOWTOOLTIP = ns.L("The button shows %s, with its tooltip and cooldown.")
local TEXT_SHOWTOOLTIP_ANY = ns.L("The button shows what the macro will cast, with its tooltip and cooldown.")
local TEXT_SHOW = ns.L("The button shows %s.")
local TEXT_IF, TEXT_ELSE_IF, TEXT_ELSE = ns.L("If %s: "), ns.L("Otherwise, if %s: "), ns.L("Otherwise: ")
local TEXT_AND, TEXT_OR = ns.L(" and "), ns.L(", or ")
local TEXT_CAST, TEXT_USE, TEXT_ON = ns.L("Cast %s"), ns.L("Use %s"), ns.L("%s on %s")
local TEXT_TRINKET = ns.L("trinket %d (slot %s)")
local TEXT_SEQUENCE = ns.L("Cast %s, one per press")
local TEXT_CANCELAURA = ns.L("Remove %s from you")
local TEXT_TARGET_UNIT = ns.L("Target %s")
local TEXT_FOCUS_UNIT = ns.L("Set your focus to %s")
local TEXT_MARKER = ns.L("Put raid marker %s on %s")
local TEXT_SCRIPT = ns.L("Runs a script (Lua).")
local TEXT_SAYS = ns.L("Says in chat: %s")
local TEXT_RUNS = ns.L("Run %s")
local TEXT_SOMETHING = ns.L("it")
local TEXT_NOT_TESTED = ns.L("%s cannot be tested here")
local TEXT_NEEDS = ns.L("It only fires when %s.")

local ACTIONS = {
    ["/stopcasting"] = ns.L("Stop your current cast"),
    ["/startattack"] = ns.L("Start auto attack"),
    ["/stopattack"] = ns.L("Stop auto attack"),
    ["/petattack"] = ns.L("Send your pet to attack"),
    ["/petfollow"] = ns.L("Call your pet back"),
    ["/petstay"] = ns.L("Tell your pet to stay"),
    ["/petpassive"] = ns.L("Set your pet to passive"),
    ["/petdefensive"] = ns.L("Set your pet to defensive"),
    ["/petaggressive"] = ns.L("Set your pet to aggressive"),
    ["/stopmacro"] = ns.L("Stop the macro here"),
    ["/cleartarget"] = ns.L("Clear your target"),
    ["/clearfocus"] = ns.L("Clear your focus"),
    ["/targetlasttarget"] = ns.L("Target your last target"),
    ["/targetenemy"] = ns.L("Target the nearest enemy"),
    ["/targetfriend"] = ns.L("Target the nearest friend"),
    ["/dismount"] = ns.L("Get off your mount"),
    ["/cancelform"] = ns.L("Leave your form"),
}

local CHAT = { ["/say"] = true, ["/s"] = true, ["/yell"] = true, ["/y"] = true, ["/party"] = true, ["/p"] = true,
    ["/raid"] = true, ["/ra"] = true, ["/rw"] = true, ["/emote"] = true, ["/em"] = true, ["/e"] = true,
    ["/guild"] = true, ["/g"] = true, ["/instance"] = true, ["/i"] = true }

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

local UNIT_WORDS = { player = ns.L("yourself"), target = ns.L("your target"), focus = ns.L("your focus"),
    mouseover = ns.L("the unit under your mouse"), targettarget = ns.L("your target's target"),
    pet = ns.L("your pet"), cursor = ns.L("the spot under your cursor"), focustarget = ns.L("your focus's target"),
    pettarget = ns.L("your pet's target"), none = ns.L("no one") }

local CONDITIONAL = {}
for _, command in ipairs({ "/cast", "/use", "/castsequence", "/castrandom", "/userandom", "/target", "/targetenemy",
    "/targetfriend", "/targetparty", "/targetraid", "/targetexact", "/targetlasttarget", "/focus", "/assist",
    "/startattack", "/stopattack", "/petattack", "/petfollow", "/petstay", "/petpassive", "/petdefensive",
    "/petaggressive", "/cancelaura", "/cancelform", "/stopcasting", "/stopmacro", "/click", "/equip", "/equipslot",
    "/dismount", "/tm", "/cleartarget", "/clearfocus" }) do
    CONDITIONAL[command] = true
end

local FIRES = { ["/cast"] = true, ["/use"] = true, ["/castsequence"] = true, ["/castrandom"] = true,
    ["/userandom"] = true }

local UNIT_CONDITIONS = { help = true, harm = true, exists = true, dead = true }

local function Unit(word)
    word = word:lower()
    if UNITS[word] then return true end
    for i = 1, #UNIT_PATTERNS do
        if word:find(UNIT_PATTERNS[i]) then return true end
    end
    if word:sub(-#TARGET_SUFFIX) == TARGET_SUFFIX and #word > #TARGET_SUFFIX
        and Unit(word:sub(1, -#TARGET_SUFFIX - 1)) then return true end
    return word:sub(-#PET_SUFFIX) == PET_SUFFIX and #word > #PET_SUFFIX and Unit(word:sub(1, -#PET_SUFFIX - 1))
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
        if d < bestDistance and candidate ~= word then best, bestDistance = candidate, d end
    end
    return best
end

local function SplitLines(body)
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

local function SplitClauses(rest)
    local out, depth, start = {}, 0, 1
    for i = 1, #rest do
        local ch = rest:sub(i, i)
        if ch == "[" then
            depth = depth + 1
        elseif ch == "]" then
            depth = math.max(0, depth - 1)
        elseif ch == ";" and depth == 0 then
            out[#out + 1] = rest:sub(start, i - 1)
            start = i + 1
        end
    end
    out[#out + 1] = rest:sub(start)
    return out
end

local function ParseClause(text)
    local clause = { groups = {} }
    text = strtrim(text)
    while true do
        local inner, after = text:match("^%[([^%]]*)%]%s*(.*)$")
        if not inner then break end
        local group = { parts = {} }
        for part in inner:gmatch("[^,]+") do
            part = strtrim(part)
            if part ~= "" then group.parts[#group.parts + 1] = part end
        end
        clause.groups[#clause.groups + 1] = group
        text = after
    end
    clause.arg = text
    return clause
end

local function ParseClauses(p)
    if p.rest:find("%[[^%]]*$") then return end
    p.clauses = {}
    for _, clause in ipairs(SplitClauses(p.rest)) do p.clauses[#p.clauses + 1] = ParseClause(clause) end
end

local function Parse(line)
    local p = { raw = line }
    local text = strtrim(line)
    if text == "" then
        p.kind = "blank"
    elseif text:sub(1, 1) == "#" then
        p.kind = "meta"
        p.word = (text:match("^(#%a+)") or ""):lower()
        p.arg = strtrim(text:match("^#%a+(.*)$") or "")
    else
        local command, rest = text:match("^(/[^%s%[]+)%s*(.*)$")
        if not command then
            p.kind = "other"
        else
            p.kind, p.command, p.cmd, p.rest = "cmd", command, command:lower(), rest
            if CONDITIONAL[p.cmd] then ParseClauses(p) end
        end
    end
    return p
end

local function Expand(p)
    if not p.clauses then return p end
    local out = {}
    for _, c in ipairs(p.clauses) do
        if #c.groups > 1 then
            for _, g in ipairs(c.groups) do out[#out + 1] = { groups = { g }, arg = c.arg } end
        else
            out[#out + 1] = c
        end
    end
    p.clauses = out
    return p
end

local function Condition(part)
    local lower = strtrim(part):lower()
    local unit = lower:match("^@(.+)$") or lower:match("^target=(.+)$")
    if unit then return { unit = unit } end
    local word, value = lower:match("^(%a+):(.+)$")
    word = word or lower
    local neg = false
    if not CONDITIONS[word] and word:sub(1, #NEGATION) == NEGATION and CONDITIONS[word:sub(#NEGATION + 1)] then
        neg, word = true, word:sub(#NEGATION + 1)
    end
    return { base = word, value = value, neg = neg, known = CONDITIONS[word] == true }
end

local function GroupUnit(group)
    for _, part in ipairs(group.parts) do
        local c = Condition(part)
        if c.unit then return c.unit end
    end
    return DEFAULT_UNIT
end

local function UnitWord(unit)
    return UNIT_WORDS[unit] or unit
end

local PREDICATES = {
    help = { ns.L("is friendly"), ns.L("is not friendly") },
    harm = { ns.L("is hostile"), ns.L("is not hostile") },
    exists = { ns.L("exists"), ns.L("does not exist") },
    dead = { ns.L("is dead"), ns.L("is alive") },
}

local STATES = {
    combat = { ns.L("you are in combat"), ns.L("you are out of combat") },
    mounted = { ns.L("you are mounted"), ns.L("you are not mounted") },
    stealth = { ns.L("you are stealthed"), ns.L("you are not stealthed") },
    pet = { ns.L("you have a pet"), ns.L("you have no pet") },
    channeling = { ns.L("you are channeling"), ns.L("you are not channeling") },
    group = { ns.L("you are in a group"), ns.L("you are not in a group") },
    indoors = { ns.L("you are indoors"), ns.L("you are not indoors") },
    outdoors = { ns.L("you are outdoors"), ns.L("you are not outdoors") },
    swimming = { ns.L("you are swimming"), ns.L("you are not swimming") },
}

local MODIFIER = { ns.L("you hold %s"), ns.L("you are not holding %s") }
local ANY_MODIFIER = { ns.L("you hold a modifier key"), ns.L("you hold no modifier key") }
local STANCE = { ns.L("you are in stance %s"), ns.L("you are not in stance %s") }
local ANY_STANCE = { ns.L("you are in a stance or form"), ns.L("you are in no stance or form") }
local EQUIPPED = { ns.L("you have %s equipped"), ns.L("you do not have %s equipped") }
local TEXT_BUTTON = ns.L("you click with mouse button %s")

local function Pick(pair, no)
    return no and pair[2] or pair[1]
end

local function Predicate(c)
    local pair = PREDICATES[c.base]
    return pair and Pick(pair, c.neg)
end

local function Phrase(c, unit)
    local no, base, value = c.neg, c.base, c.value
    local predicate = Predicate(c)
    if predicate then return UnitWord(unit) .. " " .. predicate end
    if STATES[base] then return Pick(STATES[base], no) end
    if base == "mod" or base == "modifier" then
        if value then return Pick(MODIFIER, no):format((value:gsub("^%l", string.upper))) end
        return Pick(ANY_MODIFIER, no)
    end
    if base == "stance" or base == "form" then
        return value and Pick(STANCE, no):format(value) or Pick(ANY_STANCE, no)
    end
    if base == "btn" or base == "button" then return TEXT_BUTTON:format(value or LEFT_BUTTON) end
    if base == "equipped" or base == "worn" then return Pick(EQUIPPED, no):format(value or TEXT_SOMETHING) end
    return (no and NEGATION or "") .. base .. (value and (":" .. value) or "")
end

local function GroupPhrase(group)
    local unit, said, about = GroupUnit(group), {}, {}
    for _, part in ipairs(group.parts) do
        local c = Condition(part)
        if not c.unit then
            local predicate = Predicate(c)
            if predicate then about[#about + 1] = predicate else said[#said + 1] = Phrase(c, unit) end
        end
    end
    if #about > 0 then table.insert(said, 1, UnitWord(unit) .. " " .. table.concat(about, TEXT_AND)) end
    return said, unit
end

local function ClausePhrase(clause)
    local out = {}
    for _, group in ipairs(clause.groups) do
        local said = GroupPhrase(group)
        if #said > 0 then out[#out + 1] = table.concat(said, TEXT_AND) end
    end
    return table.concat(out, TEXT_OR)
end

local function ClauseUnit(clause)
    local group = clause.groups[1]
    return group and GroupUnit(group) or DEFAULT_UNIT
end

local function Action(p, clause)
    local cmd, arg = p.cmd, clause and strtrim(clause.arg or "") or ""
    local unit = clause and ClauseUnit(clause) or DEFAULT_UNIT
    local what = arg ~= "" and arg or TEXT_SOMETHING
    if cmd == "/cast" or cmd == "/castrandom" then
        local s = TEXT_CAST:format(what)
        return unit ~= DEFAULT_UNIT and TEXT_ON:format(s, UnitWord(unit)) or s
    end
    if cmd == "/use" or cmd == "/userandom" then
        local slot = TRINKET_SLOTS[arg]
        local s = TEXT_USE:format(slot and TEXT_TRINKET:format(slot, arg) or what)
        return unit ~= DEFAULT_UNIT and TEXT_ON:format(s, UnitWord(unit)) or s
    end
    if cmd == "/castsequence" then return TEXT_SEQUENCE:format(what) end
    if cmd == "/cancelaura" then return TEXT_CANCELAURA:format(what) end
    if cmd == "/target" or cmd == "/targetexact" or cmd == "/assist" then
        return TEXT_TARGET_UNIT:format(arg ~= "" and arg or UnitWord(unit))
    end
    if cmd == "/focus" then return TEXT_FOCUS_UNIT:format(arg ~= "" and arg or UnitWord(unit)) end
    if cmd == "/tm" then return TEXT_MARKER:format(arg ~= "" and arg or "?", UnitWord(unit)) end
    if ACTIONS[cmd] then return ACTIONS[cmd] end
    return TEXT_RUNS:format(p.command .. (arg ~= "" and (" " .. arg) or ""))
end

local function Add(issues, line, kind, text, from, to)
    issues[#issues + 1] = { line = line, kind = kind, text = text, from = from, to = to }
end

local function CheckPart(issues, n, part, group)
    local c = Condition(part)
    if c.unit then
        if not Unit(c.unit) then
            local guess = Nearest(c.unit, UNITS)
            Add(issues, n, "warning", TEXT_UNKNOWN_UNIT:format(c.unit) .. (guess and TEXT_DID_YOU_MEAN:format("@" .. guess) or "."),
                guess and part, guess and ("@" .. guess))
        end
        return
    end
    if c.known then return end
    local bare = strtrim(part)
    if Unit(bare) then
        Add(issues, n, "warning", TEXT_NEEDS_AT:format(bare, bare:lower()), bare, "@" .. bare:lower())
        return
    end
    local guess = Nearest(c.base, CONDITIONS)
    local to = guess and ((c.neg and NEGATION or "") .. guess .. (c.value and (":" .. c.value) or ""))
    Add(issues, n, "warning", TEXT_UNKNOWN_CONDITION:format(bare) .. (guess and TEXT_DID_YOU_MEAN:format(to) or "."),
        guess and bare, to)
    group.unknown = true
end

local function CheckGroups(issues, n, p)
    for _, clause in ipairs(p.clauses) do
        for _, group in ipairs(clause.groups) do
            local help, harm
            for _, part in ipairs(group.parts) do
                CheckPart(issues, n, part, group)
                local c = Condition(part)
                if c.base == "help" and not c.neg then help = true end
                if c.base == "harm" and not c.neg then harm = true end
            end
            if help and harm then Add(issues, n, "warning", TEXT_HELP_HARM) end
        end
    end
end

local function HasArg(p)
    for _, clause in ipairs(p.clauses) do
        if strtrim(clause.arg) ~= "" then return true end
    end
    return false
end

local function CheckCommand(issues, n, p, known)
    local cmd = p.cmd
    if not (known[cmd] or cmd:find("^/%d+$")) then
        local guess = Nearest(cmd, known)
        Add(issues, n, "warning", TEXT_UNKNOWN_COMMAND:format(cmd) .. (guess and TEXT_DID_YOU_MEAN:format(guess) or "."),
            guess and p.command, guess)
        if guess and CONDITIONAL[guess] then ParseClauses(p) end
    end
    if SCRIPT[cmd] then return end
    local _, open = p.rest:gsub("%[", "")
    local _, close = p.rest:gsub("%]", "")
    if open ~= close then Add(issues, n, "error", TEXT_BRACKETS:format(open, close)) return end
    if not p.clauses then return end
    CheckGroups(issues, n, p)
    if (cmd == "/cast" or cmd == "/use") and not HasArg(p) then Add(issues, n, "warning", TEXT_NOTHING:format(cmd)) end
end

local function CheckLine(issues, n, p, known)
    if p.kind == "meta" then
        if p.word ~= SHOWTOOLTIP and p.word ~= SHOW then
            Add(issues, n, "warning", TEXT_HASH)
        elseif n > 1 then
            Add(issues, n, "warning", TEXT_SHOW_FIRST)
        end
    elseif p.kind == "other" then
        Add(issues, n, "warning", TEXT_NO_SLASH)
    elseif p.kind == "cmd" then
        CheckCommand(issues, n, p, known)
    end
end

local function Sentence(p)
    if p.kind == "meta" then
        if p.word == SHOWTOOLTIP then
            return p.arg ~= "" and TEXT_SHOWTOOLTIP:format(SPELL_CODE .. p.arg .. RESET) or TEXT_SHOWTOOLTIP_ANY
        end
        if p.word == SHOW then return TEXT_SHOW:format(SPELL_CODE .. p.arg .. RESET) end
        return nil
    end
    if p.kind ~= "cmd" then return nil end
    if SCRIPT[p.cmd] then return TEXT_SCRIPT end
    if CHAT[p.cmd] then return TEXT_SAYS:format(p.rest) end
    if not p.clauses then return Action(p) .. "." end
    local out, clauses = {}, Expand(p).clauses
    for i, clause in ipairs(clauses) do
        local when = ClausePhrase(clause)
        local lead
        if #clauses == 1 then
            lead = when ~= "" and TEXT_IF:format(when) or ""
        elseif when ~= "" then
            lead = (i == 1 and TEXT_IF or TEXT_ELSE_IF):format(when)
        else
            lead = TEXT_ELSE
        end
        if strtrim(clause.arg) ~= "" or #clause.groups > 0 or #clauses == 1 then
            out[#out + 1] = lead .. Action(p, clause) .. "."
        end
    end
    return table.concat(out, " ")
end

local function UnitKind(unit, state)
    if unit == "player" then return "friend" end
    return state[unit] or "none"
end

local function Holds(c, unit, state)
    local kind, value, base = UnitKind(unit, state), c.value, c.base
    local v
    if base == "exists" then
        v = kind ~= "none"
    elseif base == "help" then
        v = kind == "friend"
    elseif base == "harm" then
        v = kind == "enemy" or kind == "corpse"
    elseif base == "dead" then
        v = kind == "corpse"
    elseif base == "combat" then
        v = state.combat == true
    elseif base == "mounted" then
        v = state.mounted == true
    elseif base == "stealth" then
        v = false
    elseif base == "mod" or base == "modifier" then
        v = value and state.mod == value or (not value and state.mod ~= "none")
    elseif base == "stance" or base == "form" then
        v = false
        for one in (value or "0"):gmatch("[^/]+") do
            if tonumber(one) == state.stance then v = true end
        end
    elseif base == "btn" or base == "button" then
        v = (value or LEFT_BUTTON) == LEFT_BUTTON
    else
        return nil
    end
    if c.neg then v = not v end
    return v
end

local function GroupHolds(group, state)
    local unit = GroupUnit(group)
    for _, part in ipairs(group.parts) do
        local c = Condition(part)
        if not c.unit then
            local v = Holds(c, unit, state)
            if v == nil then return false, TEXT_NOT_TESTED:format(strtrim(part)) end
            if not v then return false, TEXT_NEEDS:format(Phrase(c, unit)) end
        end
    end
    return true
end

local function ClauseHolds(clause, state)
    if #clause.groups == 0 then return true end
    local why
    for _, group in ipairs(clause.groups) do
        local ok, reason = GroupHolds(group, state)
        if ok then return true end
        why = why or reason
    end
    return false, why
end

local function SimulateLine(p, state)
    if not p.clauses then return { status = "fire", action = Action(p) } end
    local why
    for _, clause in ipairs(p.clauses) do
        if strtrim(clause.arg) ~= "" or #clause.groups > 0 or #p.clauses == 1 then
            local ok, reason = ClauseHolds(clause, state)
            if ok then return { status = "fire", action = Action(p, clause), clause = clause } end
            why = why or reason
        end
    end
    return { status = "none", why = why }
end

local function ColorBracket(inner)
    local out, first = { MUTED_CODE .. "[" .. RESET }, true
    for part in (inner .. ","):gmatch("([^,]*),") do
        if not first then out[#out + 1] = MUTED_CODE .. "," .. RESET end
        first = false
        if part ~= "" then
            local trimmed = strtrim(part)
            local code = (trimmed:sub(1, 1) == "@" or trimmed:lower():find("^target=")) and WHO_CODE or WHEN_CODE
            out[#out + 1] = code .. part .. RESET
        end
    end
    out[#out + 1] = MUTED_CODE .. "]" .. RESET
    return table.concat(out)
end

local function ColorRest(rest)
    local out, i, n = {}, 1, #rest
    while i <= n do
        local ch = rest:sub(i, i)
        if ch == "[" then
            local close = rest:find("]", i, true)
            if not close then
                out[#out + 1] = rest:sub(i)
                break
            end
            out[#out + 1] = ColorBracket(rest:sub(i + 1, close - 1))
            i = close + 1
        elseif ch == ";" then
            out[#out + 1] = MUTED_CODE .. ";" .. RESET
            i = i + 1
        else
            local stop = rest:find("[%[;]", i) or (n + 1)
            local text = rest:sub(i, stop - 1)
            out[#out + 1] = text:find("%S") and (SPELL_CODE .. text .. RESET) or text
            i = stop
        end
    end
    return table.concat(out)
end

local function ColorLine(line)
    line = line:gsub("|", "||")
    if line:match("^%s*#") then return SHOW_CODE .. line .. RESET end
    local lead, command, rest = line:match("^(%s*)(/[^%s%[]+)(.*)$")
    if not command then return line end
    if CONDITIONAL[command:lower()] then rest = ColorRest(rest) end
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
    if not CONDITIONAL[(text:match("^%s*(/%a+)") or ""):lower()] then return text end
    text = text:gsub("[Tt]arget=", "@"):gsub("modifier:", "mod:"):gsub("button:", "btn:")
        :gsub("%s*;%s*", ";"):gsub("%[%s*", "["):gsub("%s*%]", "]")
    return (text:gsub("%b[]", function(group) return (group:gsub("%s*,%s*", ",")) end))
end

local Text = {}
M.Text = Text

Text.Lines, Text.Parse, Text.Expand, Text.Condition, Text.Action = SplitLines, Parse, Expand, Condition, Action
Text.UnitWord, Text.GroupUnit = UnitWord, GroupUnit

function Text.Build(p)
    if not p.clauses then return p.raw end
    local merged = {}
    for _, c in ipairs(p.clauses) do
        if c.arg ~= "" or #c.groups > 0 or #p.clauses == 1 then
            local last = merged[#merged]
            if last and c.arg ~= "" and last.arg == c.arg and #last.groups > 0 and #c.groups > 0 then
                for _, g in ipairs(c.groups) do last.groups[#last.groups + 1] = g end
            else
                local copy = { arg = c.arg, groups = {} }
                for _, g in ipairs(c.groups) do copy.groups[#copy.groups + 1] = g end
                merged[#merged + 1] = copy
            end
        end
    end
    local out = {}
    for _, c in ipairs(merged) do
        local s = ""
        for _, g in ipairs(c.groups) do s = s .. "[" .. table.concat(g.parts, ",") .. "]" end
        if c.arg ~= "" then s = (s ~= "" and (s .. " ") or "") .. c.arg end
        out[#out + 1] = s
    end
    local body = table.concat(out, "; ")
    return p.command .. (body ~= "" and (" " .. body) or "")
end

function Text.Check(body, known)
    local issues = {}
    if #body > LIMIT then Add(issues, 0, "error", TEXT_OVER:format(#body - LIMIT, LIMIT)) end
    for n, line in ipairs(SplitLines(body)) do CheckLine(issues, n, Parse(line), known) end
    return issues
end

function Text.Fix(body, issue)
    local lines = SplitLines(body)
    local line = lines[issue.line]
    if not (line and issue.from and issue.to) then return body end
    local at = line:find(issue.from, 1, true)
    if not at then return body end
    lines[issue.line] = line:sub(1, at - 1) .. issue.to .. line:sub(at + #issue.from)
    return table.concat(lines, "\n")
end

function Text.Explain(body)
    local out = {}
    for n, line in ipairs(SplitLines(body)) do
        local sentence = Sentence(Parse(line))
        if sentence then out[#out + 1] = { line = n, text = sentence } end
    end
    return out
end

function Text.Simulate(body, state)
    local rows, fired, stopped = {}, false, false
    for n, line in ipairs(SplitLines(body)) do
        local p = Expand(Parse(line))
        if p.kind == "cmd" and not SCRIPT[p.cmd] and not CHAT[p.cmd] then
            local row
            if stopped then
                row = { status = "unreached" }
            else
                row = SimulateLine(p, state)
                if row.status == "fire" and FIRES[p.cmd] then
                    if fired then row.status = "skipped" else fired = true end
                end
                if row.status == "fire" and p.cmd == "/stopmacro" then stopped = true end
            end
            row.line, row.text = n, line
            rows[#rows + 1] = row
        end
    end
    return rows
end

function Text.Needs(body)
    local needs = {}
    for _, line in ipairs(SplitLines(body)) do
        local p = Parse(line)
        for _, clause in ipairs(p.clauses or {}) do
            for _, group in ipairs(clause.groups) do
                local unit = GroupUnit(group)
                for _, part in ipairs(group.parts) do
                    local c = Condition(part)
                    if not c.unit then
                        if UNIT_CONDITIONS[c.base] and unit ~= "player" then
                            needs[unit] = true
                        elseif c.base == "modifier" then
                            needs.mod = true
                        elseif c.base == "form" then
                            needs.stance = true
                        else
                            needs[c.base] = true
                        end
                    end
                end
            end
        end
    end
    return needs
end

function Text.Colorize(body)
    local lines = {}
    for _, line in ipairs(SplitLines(body)) do lines[#lines + 1] = ColorLine(line) end
    return table.concat(lines, "\n")
end

function Text.Strip(coded)
    local out = {}
    Walk(coded, function(_, _, letter) out[#out + 1] = letter end)
    return table.concat(out)
end

function Text.PlainPos(coded, at)
    local plain = 0
    Walk(coded, function(i, size, letter)
        if i + size - 1 > at then return true end
        if letter then plain = plain + 1 end
    end)
    return plain
end

function Text.CodedPos(coded, plain)
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

function Text.Shorten(body)
    local lines = {}
    for _, line in ipairs(SplitLines(body)) do lines[#lines + 1] = ShortenLine(line) end
    while lines[#lines] == "" do lines[#lines] = nil end
    return table.concat(lines, "\n")
end

ns.MacroText = Text
