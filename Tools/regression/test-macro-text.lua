-- Run with Lua 5.1 from the repository root: reading a macro's text (ns.MacroText). The
-- checks find what will not work and say what was meant, Explain says what each line does in
-- plain words, and Shorten saves bytes without changing what the macro does.
local ns = { Macros = {} }
local env = setmetatable({
    NaowhForever = ns,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
}, { __index = _G })
env._G = env
for _, path in ipairs({ "NaowhForever_Macros/Constants.lua", "NaowhForever_Macros/Text.lua" }) do
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk()
end
local Text = ns.MacroText

local KNOWN = {}
for _, c in ipairs({ "/cast", "/use", "/castsequence", "/stopcasting", "/focus", "/tm", "/cancelaura", "/startattack",
    "/petattack", "/run", "/click", "/dismount" }) do KNOWN[c] = true end

local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Issues(body)
    local out = {}
    for _, i in ipairs(Text.Check(body, KNOWN)) do out[#out + 1] = i.line .. " " .. i.kind .. ": " .. i.text end
    return table.concat(out, "\n")
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("a good macro has nothing to say", function()
    assert(Issues("#showtooltip Polymorph\n/stopcasting\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] Polymorph") == "")
end)

Case("an unknown command says what was meant", function()
    local said = Issues("#showtooltip\n/castsequnce reset=3 Scorch, Fire Blast")
    -- A warning, not an error: commands of addons that are not loaded are missing from the list.
    assert(said == "2 warning: /castsequnce is not a command the game knows. Did you mean /castsequence?", said)
end)

Case("a raid marker line half typed is explained, not an error", function()
    assert(Plain(Text.Explain("/tm [@focus] ")[1]) == "Puts a raid marker (1 to 8) on your focus.")
    assert(Plain(Text.Explain("/tm 8")[1]) == "Puts raid marker 8 on your target.")
end)

Case("a missing bracket, a misspelt condition and an unknown unit", function()
    local said = Issues("/cast [@focus,harm Polymorph\n/cast [harmm] Frostbolt\n/cast [@mousover] Blink")
    assert(said:find("1 error: 1 %[ but 0 %]"), said)
    assert(said:find("2 warning: harmm is not a condition the game knows. Did you mean harm?"), said)
    assert(said:find("3 warning: @mousover is not a unit"), said)
end)

Case("no conditions are looked for inside a script, and raid units are fine", function()
    assert(Issues("/run print('[a')\n/cast [@raid25,help] Renew\n/cast [@party2target] Fireball") == "")
end)

Case("over 255 bytes is an error, counted in bytes", function()
    local said = Issues("/cast " .. string.rep("x", 260))
    assert(said:find("^0 error: 11 bytes over the game's 255"), said)
end)

Case("Explain says each line in plain words", function()
    local lines = Text.Explain("#showtooltip Polymorph\n/stopcasting\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] Polymorph")
    assert(Plain(lines[1]) == "Shows Polymorph on the button, with its tooltip and cooldown.", Plain(lines[1]))
    assert(Plain(lines[2]) == "Stops your current cast, so the next line goes off at once.")
    local cast = Plain(lines[3])
    assert(cast == "Casts Polymorph on your focus if it is hostile and it is alive, otherwise on the unit under "
        .. "your mouse if it is hostile and it is alive, otherwise on your target.", cast)
end)

Case("Explain: alternatives, sequences, focus and modifiers", function()
    local lines = Text.Explain("/cast [mod:shift] Blink; Frost Nova\n/castsequence reset=3 Scorch, Fire Blast\n"
        .. "/focus [@mouseover,exists][]\n/cancelaura Ice Block")
    assert(Plain(lines[1]) == "Casts Blink on your target if you hold Shift; or casts Frost Nova.", Plain(lines[1]))
    assert(Plain(lines[2]) == "Casts Scorch, then Fire Blast, one per press, starting over after 3.", Plain(lines[2]))
    assert(Plain(lines[3]) == "Sets your focus to the unit under your mouse if it exists, otherwise to your target.",
        Plain(lines[3]))
    assert(Plain(lines[4]) == "Removes Ice Block from you.", Plain(lines[4]))
end)

Case("Shorten saves bytes with spellings the game reads the same way", function()
    local long = "#showtooltip\n/cast [ target=focus , modifier:shift ] Polymorph ; [button:2] Frostbolt   \n"
    local short = Text.Shorten(long)
    assert(short == "#showtooltip\n/cast [@focus,mod:shift] Polymorph;[btn:2] Frostbolt", short)
    assert(#short < #long)
    assert(Text.Shorten("/run print( 'a ; b' )") == "/run print( 'a ; b' )", "a script is left as it is")
end)

Case("Shorten leaves chat as it was written", function()
    local chat = "/say Pull in 3 ; target=me [ go ]\n/p modifier: shift , please"
    assert(Text.Shorten(chat) == chat, Text.Shorten(chat))
end)

Case("a player's or pet's name is a unit; a near miss of one is a typo", function()
    assert(Issues("/cast [@Thrall,help] Blessing of Kings\n/cast [@party1pet,help] Mend Pet") == "")
    local said = Issues("/cast [@mousover] Blink")
    assert(said == "1 warning: @mousover is not a unit the game knows. Did you mean @mouseover?", said)
end)

Case("/focus with a unit says that unit", function()
    assert(Plain(Text.Explain("/focus arena1")[1]) == "Sets your focus to arena1.", Plain(Text.Explain("/focus arena1")[1]))
    assert(Plain(Text.Explain("/focus mouseover")[1]) == "Sets your focus to the unit under your mouse.")
    assert(Plain(Text.Explain("/focus")[1]) == "Sets your focus to your target.")
end)

Case("Explain: a slash with no command yet says nothing", function()
    assert(#Text.Explain("/") == 0)
    assert(#Text.Explain("/ cast Blink") == 0)
    local lines = Text.Explain("#showtooltip\n/\n/dance")
    assert(#lines == 2 and Plain(lines[2]) == "Runs /dance.", Plain(lines[2] or "nil"))
end)

Case("bar and vehicle conditions are known", function()
    local said = Issues("/cast [petbattle] A\n/cast [nooverridebar,nopossessbar] B\n/cast [canexitvehicle] C\n"
        .. "/cast [shapeshift] D")
    assert(said == "", said)
end)

Case("the editor's colours come off exactly, and a typed | survives", function()
    local body = "#showtooltip Polymorph\n/cast [@focus,harm][] Polymorph\n/run print('a|b')\nnote"
    local coded = Text.Colorize(body)
    assert(coded:find("|cff6cc4ff/cast|r", 1, true), coded)
    assert(coded:find("|cfff2d36b[@focus,harm]|r", 1, true), coded)
    assert(coded:find("print('a||b')", 1, true), "a script is not coloured, its | doubled")
    assert(Text.Strip(coded) == body)
    assert(Text.Colorize(Text.Strip(coded)) == coded, "colouring twice changes nothing")
    assert(Text.Strip("/say a|b") == "/say a|b", "a lone | typed before the recolour is kept")
end)

Case("a cursor keeps its place in the macro through the colours", function()
    local body = "/cast [harm] Fireball"
    local coded = Text.Colorize(body)
    for plain = 0, #body do
        assert(Text.PlainPos(coded, Text.CodedPos(coded, plain)) == plain, "place " .. plain)
    end
    local at = Text.CodedPos(coded, 5)   -- just after "/cast"
    assert(Text.Strip(coded:sub(1, at)) == "/cast", coded:sub(1, at))
end)

print(("test-macro-text: %d cases passed"):format(count))
