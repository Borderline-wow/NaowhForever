-------------------------------------------------------------------------------
--  NaowhForever_MacroText.lua -- reading a macro's text (ns.MacroText): its size in bytes
--  against the game's 255, the lines that will not work and why, what each line does in plain
--  words, and a shorter spelling that does the same. Text only: no frames, nothing at load.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local MacroText = {}
ns.MacroText = MacroText

MacroText.LIMIT = 255   -- bytes the game keeps of a macro's text

-- Conditions the macro system reads, without their "no" (nodead is dead's).
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
local SCRIPT = { ["/run"] = true, ["/script"] = true, ["/dump"] = true }
-- How far a word may be from a real one to be offered as "did you mean".
local NEAR = 2

local function Unit(word)
    word = word:lower()
    return UNITS[word] or word:find("^party%d$") or word:find("^raid%d+$") or word:find("^arena%d$")
        or word:find("^boss%d$") or word:find("^partypet%d$") or word:find("^raidpet%d+$")
        or word:find("^nameplate%d+$") or (word:find("target$") and Unit(word:sub(1, -7)))
        or (word:find("pet$") and Unit(word:sub(1, -4)))
end

-- Edit distance, for "did you mean".
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

-- Each [ ] group of a line, as its text without the brackets.
local function Groups(line)
    local groups = {}
    for inner in line:gmatch("%[([^%]]*)%]") do groups[#groups + 1] = inner end
    return groups
end

-------------------------------------------------------------------------------
--  Problems
-------------------------------------------------------------------------------
-- { line, kind = "error" | "warning", text } for every line that will not do what it says.
-- known: the set of slash commands the game knows ("/cast" = true), from the module.
function MacroText.Check(body, known)
    local issues = {}
    local function Add(line, kind, text) issues[#issues + 1] = { line = line, kind = kind, text = text } end
    if #body > MacroText.LIMIT then
        Add(0, "error", ("%d bytes over the game's %d: the end is cut off."):format(#body - MacroText.LIMIT,
            MacroText.LIMIT))
    end
    local n = 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local text = strtrim(line)
        if text:sub(1, 1) == "#" then
            if not (text:lower():find("^#showtooltip") or text:lower():find("^#show[%s]") or text:lower() == "#show") then
                Add(n, "warning", "Only #showtooltip and #show do anything; other # lines are skipped.")
            end
        elseif text ~= "" then
            local command = text:match("^(/[^%s%[]+)")
            if not command then
                Add(n, "warning", "Does nothing: a line has to start with /.")
            else
                command = command:lower()
                -- A warning: commands of addons that are not loaded are missing from the list.
                if not (known[command] or command:find("^/%d+$")) then
                    local guess = Nearest(command, known)
                    Add(n, "warning", command .. " is not a command the game knows"
                        .. (guess and (". Did you mean " .. guess .. "?") or "."))
                end
                if not SCRIPT[command] then
                    local _, open = text:gsub("%[", "")
                    local _, close = text:gsub("%]", "")
                    if open ~= close then
                        Add(n, "error", ("%d [ but %d ]: a bracket is missing."):format(open, close))
                    end
                    for _, group in ipairs(Groups(text)) do
                        for part in group:gmatch("[^,]+") do
                            part = strtrim(part):lower()
                            local unit = part:match("^@(.+)$") or part:match("^target=(.+)$")
                            if unit then
                                -- Any other word is a player's or a pet's name, which the game
                                -- takes; one close to a unit is a typo.
                                local guess = not Unit(unit) and Nearest(unit, UNITS)
                                if guess then
                                    Add(n, "warning", "@" .. unit .. " is not a unit the game knows. Did you mean @"
                                        .. guess .. "?")
                                end
                            elseif part ~= "" then
                                local word = part:match("^([%a]+)")
                                local base = word and (CONDITIONS[word] and word or word:match("^no(.+)$"))
                                if not (word and CONDITIONS[base or ""]) then
                                    local guess = word and Nearest(word, CONDITIONS)
                                    Add(n, "warning", part .. " is not a condition the game knows"
                                        .. (guess and (". Did you mean " .. guess .. "?") or "."))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return issues
end

-------------------------------------------------------------------------------
--  Plain words
-------------------------------------------------------------------------------
local SPELL, WHO, WHEN = "|cff6cc4ff", "|cffffb36b", "|cfff2d36b"
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

local function Condition(part)
    part = strtrim(part):lower()
    if SIMPLE[part] then return SIMPLE[part] end
    local word, value = part:match("^(%a+):(.+)$")
    if word == "mod" or word == "modifier" then
        return "you hold " .. value:gsub("^%l", string.upper)
    elseif word == "btn" or word == "button" then
        return value == "2" and "you right-click" or ("you click with button " .. value)
    elseif word == "stance" or word == "form" then
        return "you are in " .. word .. " " .. value
    elseif word == "noform" or word == "nostance" then
        return "you are not in " .. word:sub(3) .. " " .. value
    elseif word == "equipped" or word == "worn" then
        return "you have " .. value .. " equipped"
    end
    return part
end

-- "Casts Polymorph on your focus if it is hostile and it is alive, otherwise on your target."
-- lead, when given, is said in place of "<verb> <what> on": "Sets your focus to".
local function Clause(clause, verb, lead)
    clause = strtrim(clause)
    local said, any = {}, false
    while true do
        local inner, rest = clause:match("^%[([^%]]*)%]%s*(.*)$")
        if not inner then break end
        any = true
        local unit, conditions = nil, {}
        for part in inner:gmatch("[^,]+") do
            local u = strtrim(part):match("^@(.+)$") or strtrim(part):match("^[Tt]arget=(.+)$")
            if u then unit = u:lower() elseif strtrim(part) ~= "" then conditions[#conditions + 1] = Condition(part) end
        end
        said[#said + 1] = { unit = unit, conditions = conditions }
        clause = rest
    end
    local what = SPELL .. (clause ~= "" and clause or "it") .. "|r"
    if not any then
        if not lead then return verb .. " " .. what end
        local unit = clause:lower()
        return lead .. " " .. WHO .. (clause ~= "" and (UNIT_WORDS[unit] or clause) or "your target") .. "|r"
    end
    local out = {}
    for i, group in ipairs(said) do
        local who = WHO .. (group.unit and (UNIT_WORDS[group.unit] or ("@" .. group.unit)) or "your target") .. "|r"
        local first = lead and (lead .. " ") or (verb .. " " .. what .. " on ")
        local part = (i == 1 and first or (lead and "otherwise to " or "otherwise on ")) .. who
        if #group.conditions > 0 then
            part = part .. " if " .. WHEN .. table.concat(group.conditions, " and ") .. "|r"
        end
        out[#out + 1] = part
    end
    return table.concat(out, ", ")
end

-- One plain sentence per line that does something, in order.
function MacroText.Explain(body)
    local said = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local text = strtrim(line)
        local lower = text:lower()
        local sentence
        if text == "" then
            sentence = nil
        elseif lower:find("^#showtooltip") then
            local what = strtrim(text:sub(13))
            sentence = what ~= "" and ("Shows " .. SPELL .. what .. "|r on the button, with its tooltip and cooldown.")
                or "Shows what the macro will cast on the button, with its tooltip and cooldown."
        elseif lower:find("^#show") then
            sentence = "Shows " .. SPELL .. strtrim(text:sub(6)) .. "|r on the button."
        elseif lower:find("^/stopcasting") then
            sentence = "Stops your current cast, so the next line goes off at once."
        elseif lower:find("^/cast ") or lower:find("^/use ") then
            local verb = lower:find("^/use") and "Uses" or "Casts"
            local parts = {}
            for clause in (text:match("^/%a+%s+(.*)$") .. ";"):gmatch("([^;]*);") do
                if strtrim(clause) ~= "" then
                    parts[#parts + 1] = Clause(clause, #parts == 0 and verb or ("or " .. verb:lower()))
                end
            end
            sentence = table.concat(parts, "; ") .. "."
        elseif lower:find("^/castsequence") then
            local reset, list = text:match("^/%a+%s+reset=(%S+)%s+(.*)$")
            list = list or text:match("^/%a+%s+(.*)$") or ""
            local spells = {}
            for spell in list:gmatch("[^,]+") do spells[#spells + 1] = SPELL .. strtrim(spell) .. "|r" end
            sentence = "Casts " .. table.concat(spells, ", then ") .. ", one per press"
                .. (reset and (", starting over after " .. reset) or "") .. "."
        elseif lower:find("^/cancelaura") then
            sentence = "Removes " .. SPELL .. strtrim(text:sub(12)) .. "|r from you."
        elseif lower:find("^/startattack") then
            sentence = "Starts your auto attack."
        elseif lower:find("^/stopattack") then
            sentence = "Stops your auto attack."
        elseif lower:find("^/petattack") then
            sentence = "Sends your pet to attack."
        elseif lower:find("^/petfollow") then
            sentence = "Calls your pet back to you."
        elseif lower:find("^/focus") then
            sentence = Clause(text:match("^/%a+%s*(.*)$"), nil, "Sets your focus to") .. "."
        elseif lower:find("^/tm ") then
            local marker = text:match("(%d+)%s*$")
            sentence = (marker and ("Puts raid marker " .. marker) or "Puts a raid marker (1 to 8)") .. " on "
                .. (text:find("@focus") and "your focus" or "your target") .. "."
        elseif lower:find("^/dismount") then
            sentence = "Gets you off your mount."
        elseif lower:find("^/click") then
            sentence = "Clicks " .. SPELL .. strtrim(text:sub(7)) .. "|r for you."
        elseif SCRIPT[lower:match("^(/%a+)") or ""] then
            sentence = "Runs a script (Lua)."
        elseif text:sub(1, 1) == "/" then
            sentence = "Runs " .. SPELL .. text:match("^(/%S+)") .. "|r."
        end
        said[#said + 1] = sentence or false
    end
    local out = {}
    for _, sentence in ipairs(said) do
        if sentence then out[#out + 1] = sentence end
    end
    return out
end

-------------------------------------------------------------------------------
--  Colours in the editor
-------------------------------------------------------------------------------
-- An edit box cannot colour its own text, so the editor holds the macro with colour codes in
-- it: Colorize puts them in, Strip takes them out, and the two Pos functions move a cursor
-- between the two. A | the player types is doubled, as the game shows || as one |.
local SHOW, COMMAND = "|cff7bd88f", "|cff6cc4ff"

function MacroText.Colorize(body)
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("|", "||")
        local lead, command, rest = line:match("^(%s*)(/[^%s%[]+)(.*)$")
        if line:match("^%s*#") then
            line = SHOW .. line .. "|r"
        elseif command then
            if not SCRIPT[command:lower()] then rest = rest:gsub("%b[]", WHEN .. "%0|r") end
            line = lead .. COMMAND .. command .. "|r" .. rest
        end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end

-- Walks coded text: each step is a colour code (no letters of the macro) or one letter.
local function Walk(coded, step)
    local i, n = 1, #coded
    while i <= n do
        local size, letter = 1, coded:sub(i, i)
        if letter == "|" then
            local nxt = coded:sub(i + 1, i + 1)
            if nxt == "c" and coded:find("^|c%x%x%x%x%x%x%x%x", i) then
                size, letter = 10, nil
            elseif nxt == "r" then
                size, letter = 2, nil
            elseif nxt == "|" then
                size = 2
            end
        end
        if step(i, size, letter) then return end
        i = i + size
    end
end

function MacroText.Strip(coded)
    local out = {}
    Walk(coded, function(_, _, letter) out[#out + 1] = letter end)
    return table.concat(out)
end

-- The cursor at byte `at` of the coded text, as a place in the macro.
function MacroText.PlainPos(coded, at)
    local plain = 0
    Walk(coded, function(i, size, letter)
        if i + size - 1 > at then return true end
        if letter then plain = plain + 1 end
    end)
    return plain
end

-- A place in the macro, as a cursor in the coded text: just after its letter.
function MacroText.CodedPos(coded, plain)
    if plain <= 0 then return 0 end
    local at, seen = #coded, 0
    Walk(coded, function(i, size, letter)
        if letter then
            seen = seen + 1
            if seen == plain then
                at = i + size - 1
                return true
            end
        end
    end)
    return at
end

-------------------------------------------------------------------------------
--  Shorter
-------------------------------------------------------------------------------
-- Commands that take [conditions]. Everything else (chat, emotes, scripts) is left as written.
local CONDITIONAL = {}
for _, command in ipairs({ "/cast", "/use", "/castsequence", "/castrandom", "/userandom", "/target", "/targetenemy",
    "/targetfriend", "/targetparty", "/targetraid", "/targetexact", "/focus", "/assist", "/startattack",
    "/stopattack", "/petattack", "/petfollow", "/petstay", "/petpassive", "/petdefensive", "/petaggressive",
    "/cancelaura", "/cancelform", "/stopcasting", "/stopmacro", "/click", "/equip", "/equipslot", "/dismount",
    "/tm", "/cleartarget", "/clearfocus" }) do
    CONDITIONAL[command] = true
end

-- The same macro in fewer bytes, by spellings the game reads the same way: @ for target=,
-- mod: and btn: for modifier: and button:, and no spaces around ; and , or at line ends.
function MacroText.Shorten(body)
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local text = line:gsub("%s+$", "")
        if CONDITIONAL[(text:match("^(/%a+)") or ""):lower()] then
            text = text:gsub("[Tt]arget=", "@"):gsub("modifier:", "mod:"):gsub("button:", "btn:")
                :gsub("%s*;%s*", ";"):gsub("%[%s*", "["):gsub("%s*%]", "]")
            text = text:gsub("%b[]", function(group) return (group:gsub("%s*,%s*", ",")) end)
        end
        lines[#lines + 1] = text
    end
    while lines[#lines] == "" do lines[#lines] = nil end
    return table.concat(lines, "\n")
end
