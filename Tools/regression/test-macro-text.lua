-- Run with Lua 5.1 from the repository root: reading and writing a macro's text (ns.MacroText), which
-- the Forge's editor, Build, Reads as, Simulate and Test it all share. Check finds what will not work
-- and Fix applies the suggestion, Explain says each line in words, Simulate says what one press does,
-- Build writes edited clauses back, and Shorten and the colors leave the macro doing the same.
local ns = { Macros = {}, L = dofile("Tools/regression/locale_stub.lua").L }
local env = setmetatable({
    NaowhForever = ns,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
}, { __index = _G })
env._G = env
dofile("Tools/regression/load_files.lua")({ "NaowhForever_Macros/Constants.lua", "NaowhForever_Macros/Text.lua" }, env)
local Text = ns.MacroText

local KNOWN = {}
for _, c in ipairs({ "/cast", "/use", "/castsequence", "/stopcasting", "/focus", "/tm", "/startattack", "/stopmacro",
    "/run", "/dismount" }) do KNOWN[c] = true end

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Issues(body)
    local out = {}
    for _, i in ipairs(Text.Check(body, KNOWN)) do out[#out + 1] = i.line .. " " .. i.kind .. ": " .. i.text end
    return table.concat(out, "\n")
end
local function Said(body)
    local out = {}
    for _, s in ipairs(Text.Explain(body)) do out[#out + 1] = Plain(s.text) end
    return out
end
local function Press(body, state)
    local out = {}
    for _, row in ipairs(Text.Simulate(body, state)) do out[#out + 1] = row.status .. ":" .. (row.action or row.why or "") end
    return table.concat(out, " | ")
end

-- Check and Fix
check("a good macro has nothing to say",
    Issues("#showtooltip Polymorph\n/stopcasting\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] Polymorph") == "")
local said = Issues("/cats Fireball")
check("an unknown command says what was meant", said == "1 warning: /cats is not a command the game knows. Did you mean /cast?")
check("Fix applies it", Text.Fix("/cats Fireball", Text.Check("/cats Fireball", KNOWN)[1]) == "/cast Fireball")
said = Issues("/cast [@focus,harm Polymorph\n/cast [harmm] Frostbolt\n/cast [mouseover] Blink\n/cast [help,harm] Heal")
check("a missing bracket is an error", said:find("1 error: 1 %[ but 0 %]") ~= nil)
check("a misspelt condition gets a guess", said:find("2 warning: harmm is not a condition the game knows. Did you mean harm?", 1, true) ~= nil)
check("a unit without its @ is caught, with the fix",
    said:find("3 warning: [mouseover] needs an @ to aim at that unit: @mouseover.", 1, true) ~= nil)
check("help and harm together can never be true", said:find("4 warning: help and harm in one bracket", 1, true) ~= nil)
check("raid units and scripts are left alone", Issues("/run print('[a')\n/cast [@raid25,help] Renew\n/cast [@party2target] Fireball") == "")
check("over 255 bytes is counted in bytes", Issues("/cast " .. ("x"):rep(260)):find("^0 error: 11 bytes over the game's 255") ~= nil)
check("#showtooltip belongs on the first line", Issues("/cast Blink\n#showtooltip"):find("2 warning: #showtooltip only works on the first line.", 1, true) ~= nil)

-- Explain
local lines = Said("#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Greater Heal")
check("#showtooltip says what the button shows", lines[1] == "The button shows what the macro will cast, with its tooltip and cooldown.")
check("each choice reads as a sentence", lines[2] == "If the unit under your mouse is friendly and is alive: Cast Greater Heal on the unit under your mouse."
    .. " Otherwise, if your target is friendly and is alive: Cast Greater Heal. Otherwise: Cast Greater Heal on yourself.")
check("modifiers and combat read in words", Said("/cast [mod:alt,nocombat] Mount")[1] == "If you hold Alt and you are out of combat: Cast Mount.")
check("a trinket slot is named", Said("/use 13")[1] == "Use trinket 1 (slot 13).")

-- Simulate and Needs
local heal = "/cast [@mouseover,help,nodead][help,nodead][@player] Greater Heal"
check("nothing under the mouse and an enemy targeted: it falls to you",
    Press(heal, { target = "enemy", mouseover = "none" }) == "fire:Cast Greater Heal on yourself")
check("a friend under the mouse takes the first choice",
    Press(heal, { target = "enemy", mouseover = "friend" }) == "fire:Cast Greater Heal on the unit under your mouse")
check("one spell per press: the second /cast is skipped",
    Press("/cast Frostbolt\n/cast Fireball", {}) == "fire:Cast Frostbolt | skipped:Cast Fireball")
check("a line that cannot fire says why",
    Press("/cast [combat] Charge", { combat = false }) == "none:It only fires when you are in combat.")
check("/stopmacro ends the press", Press("/stopmacro [nocombat]\n/startattack", { combat = false })
    == "fire:Stop the macro here | unreached:")
local needs = Text.Needs(heal .. "\n/cast [mod:shift,stance:2] X")
check("Needs lists what the macro depends on, and not yourself", needs.mouseover and needs.target and needs.mod
    and needs.stance and not needs.player)

-- Build
local p = Text.Expand(Text.Parse(heal))
check("Expand splits each bracket into its own choice", #p.clauses == 3 and p.clauses[3].groups[1].parts[1] == "@player")
check("Build writes them back as they were", Text.Build(p) == heal)
p.clauses[1].groups[1].parts[#p.clauses[1].groups[1].parts + 1] = "mod:alt"
check("an added condition lands in its bracket",
    Text.Build(p) == "/cast [@mouseover,help,nodead,mod:alt][help,nodead][@player] Greater Heal")
p.clauses[2].arg = "Flash Heal"
check("a choice with its own spell becomes its own clause",
    Text.Build(p) == "/cast [@mouseover,help,nodead,mod:alt] Greater Heal; [help,nodead] Flash Heal; [@player] Greater Heal")

-- Shorten and colors
local long = "/cast [target=focus, harm] Polymorph ; [modifier:alt] Blink"
local short = Text.Shorten(long)
check("Shorten saves bytes", short == "/cast [@focus,harm] Polymorph;[mod:alt] Blink")
check("and reads the same", Plain(Text.Explain(short)[1].text) == Plain(Text.Explain(long)[1].text))
local body = "#showtooltip\n/cast [@focus,harm][] Polymorph"
local colored = Text.Colorize(body)
check("colors come off again", colored ~= body and Text.Strip(colored) == body)
check("a cursor position maps through the colors", Text.PlainPos(colored, Text.CodedPos(colored, 20)) == 20)
check("a | in the text survives the colors", Text.Strip(Text.Colorize("/say a|b")) == "/say a|b")

print(("test-macro-text: %d checks passed"):format(checks))
