-- The theme colors written as |cffRRGGBB escapes used to be typed out by hand in 65 places. They
-- now come from ns.Color, and with the default theme every one of them must produce exactly the
-- string it replaced. Each row names the file, the shipped code (which must be in that file),
-- the same expression with sample arguments, and the literal it used to be. Run with Lua 5.1
-- from the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local frame = setmetatable({}, { __index = function() return function() end end })
function frame:SetScript() end
local coreEnv = { CreateFrame = function() return frame end,
    NaowhForeverDB = { account = {}, profiles = {}, charActive = {} } }
coreEnv._G = coreEnv
setmetatable(coreEnv, { __index = _G })
local core = assert(loadstring(Read("Core/NaowhForever_Core.lua"), "Core"))
setfenv(core, coreEnv)
core("NaowhForever")
local ns = coreEnv.NaowhForever

local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end
local function Eval(text)
    local chunk = assert(loadstring("return " .. text))
    setfenv(chunk, setmetatable({ ns = ns }, { __index = _G }))
    return chunk()
end

local ROWS = {
    { [==[Core/NaowhForever_Core.lua]==],
      [==[msg = ns.Color("accent", "(withheld: this line contained a secret value)")]==],
      [==[ns.Color("accent", "(withheld: this line contained a secret value)")]==],
      [==["|cff0091ed(withheld: this line contained a secret value)|r"]==] },
    { [==[Core/NaowhForever_Core.lua]==],
      [==[print(ns.PRINT_LOGO .. " " .. ns.Color("accent", "Naowh") .. " Forever: " .. tostring(msg))]==],
      [==[ns.Color("accent", "Naowh") .. " Forever: " .. tostring("hi")]==],
      [==["|cff0091edNaowh|r Forever: " .. tostring("hi")]==] },
    { [==[Core/NaowhForever_Core.lua]==],
      [==[return ns.Color("accent", frame._tipTitle) .. "\n" .. b]==],
      [==[ns.Color("accent", "Title") .. "\n" .. "body"]==],
      [==["|cff0091ed" .. "Title" .. "|r\n" .. "body"]==] },
    { [==[NaowhForever_DungeonJournal/View/QuestRows.lua]==],
      [==[text = text .. "  " .. ns.Color("accentSoft", "(dungeon quest)")]==],
      [==["x" .. "  " .. ns.Color("accentSoft", "(dungeon quest)")]==],
      [==["x" .. "  |cff4db5f5(dungeon quest)|r"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[("  " .. ns.Color("muted", "(%s each x%d)")):format(Coins(each), count)]==],
      [==[("  " .. ns.Color("muted", "(%s each x%d)")):format("5g", 3)]==],
      [==[("  |cff9a9ea6(%s each x%d)|r"):format("5g", 3)]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[GameTooltip:AddLine(ns.Color("accent", "Click") .. "  stack now", 1, 1, 1)]==],
      [==[ns.Color("accent", "Click") .. "  stack now"]==],
      [==["|cff0091edClick|r  stack now"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[or ns.Color("muted", "unknown")]==],
      [==[ns.Color("muted", "unknown")]==],
      [==["|cff9a9ea6unknown|r"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[GameTooltip:AddLine(ns.Color("accent", "Ctrl-click") .. "  twice to delete", 1, 1, 1)]==],
      [==[ns.Color("accent", "Ctrl-click") .. "  twice to delete"]==],
      [==["|cff0091edCtrl-click|r  twice to delete"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[GameTooltip:AddLine(ns.Color("accent", "Ctrl-click") .. "  pick up to delete", 1, 1, 1)]==],
      [==[ns.Color("accent", "Ctrl-click") .. "  pick up to delete"]==],
      [==["|cff0091edCtrl-click|r  pick up to delete"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[GameTooltip:AddLine(ns.Color("accent", "Ctrl-click") .. "  delete now", 1, 1, 1)]==],
      [==[ns.Color("accent", "Ctrl-click") .. "  delete now"]==],
      [==["|cff0091edCtrl-click|r  delete now"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[GameTooltip:AddLine(ns.Color("accent", "Click") .. "  sell", 1, 1, 1)]==],
      [==[ns.Color("accent", "Click") .. "  sell"]==],
      [==["|cff0091edClick|r  sell"]==] },
    { [==[QoL/NaowhForever_BagSpace.lua]==],
      [==[GameTooltip:AddLine(ns.Color("accent", "Middle-click") .. "  ignore this item", 1, 1, 1)]==],
      [==[ns.Color("accent", "Middle-click") .. "  ignore this item"]==],
      [==["|cff0091edMiddle-click|r  ignore this item"]==] },
    { [==[QoL/NaowhForever_LootFeed.lua]==],
      [==[name = name .. "  " .. ns.Color("accent", "BiS" .. (pick > 1 and " #" .. pick or ""))]==],
      [==["n" .. "  " .. ns.Color("accent", "BiS" .. (2 > 1 and " #" .. 2 or ""))]==],
      [==["n" .. "  |cff0091edBiS" .. (2 > 1 and " #" .. 2 or "") .. "|r"]==] },
    { [==[QoL/NaowhForever_XPBar.lua]==],
      [==[local LABEL, VALUE = ns.Color("muted"), ns.Color("fg")]==],
      [==[ns.Color("muted") .. "Session:|r " .. ns.Color("fg") .. "1h" .. "|r"]==],
      [==["|cff9a9ea6" .. "Session:|r " .. "|cfff0f1f3" .. "1h" .. "|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[tooltip = "Sends " .. ns.Color("accent", "EXTERNAL!") .. " to party, raid or instance chat when nothing on "]==],
      [==["Sends " .. ns.Color("accent", "EXTERNAL!") .. " to party, raid or instance chat when nothing on "]==],
      [==["Sends |cff0091edEXTERNAL!|r to party, raid or instance chat when nothing on "]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[ns.Color("accent", "Delete Preset") .. "\nRemoves this preset and its list. Cannot be undone.")]==],
      [==[ns.Color("accent", "Delete Preset") .. "\nRemoves this preset and its list. Cannot be undone."]==],
      [==["|cff0091edDelete Preset|r\nRemoves this preset and its list. Cannot be undone."]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[text = "      " .. ns.Color("muted", c.name .. (c.userAdded and " (added by you)" or "")),]==],
      [==["      " .. ns.Color("muted", "Bob" .. (true and " (added by you)" or ""))]==],
      [==["      |cff9a9ea6" .. "Bob" .. (true and " (added by you)" or "") .. "|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[text = ("      " .. ns.Color("accent", "Last:  %s")):format(]==],
      [==[("      " .. ns.Color("accent", "Last:  %s")):format("Call for an External")]==],
      [==[("      |cff0091edLast:  %s|r"):format("Call for an External")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[hint:SetText(ns.Color("muted", "No presets yet -- add one on the Setup page "]==],
      [==[ns.Color("muted", "No presets yet -- add one on the Setup page " .. "first.")]==],
      [==["|cff9a9ea6No presets yet -- add one on the Setup page " .. "first.|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[or ns.Color("muted", "No description in the journal.")]==],
      [==[ns.Color("muted", "No description in the journal.")]==],
      [==["|cff9a9ea6No description in the journal.|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[descText = (ns.Color("muted", "[%s]") .. "  "):format(restTag) .. descText]==],
      [==[(ns.Color("muted", "[%s]") .. "  "):format("Rest") .. "desc"]==],
      [==[("|cff9a9ea6[%s]|r  "):format("Rest") .. "desc"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[row.lbl:SetText((r.name or "Reminder") .. "  " .. ns.Color("muted", "("]==],
      [==[("Name") .. "  " .. ns.Color("muted", "(" .. (("cast") .. (" +" .. tostring(2) .. "s")) .. ")")]==],
      [==[("Name") .. "  |cff9a9ea6(" .. (("cast") .. (" +" .. tostring(2) .. "s")) .. ")|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[body:SetText(("Remove " .. ns.Color("accent", "%s") .. " from this boss?"):format]==],
      [==[("Remove " .. ns.Color("accent", "%s") .. " from this boss?"):format("Bolt")]==],
      [==[("Remove |cff0091ed%s|r from this boss?"):format("Bolt")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[ns.Print(("copied " .. ns.Color("accent", "%d") .. " abilities%s from %s%s.")]==],
      [==[("copied " .. ns.Color("accent", "%d") .. " abilities%s from %s%s."):format(3, "x", "a", "b")]==],
      [==[("copied |cff0091ed%d|r abilities%s from %s%s."):format(3, "x", "a", "b")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[(" and " .. ns.Color("accent", reminders) .. " message reminders")]==],
      [==[(" and " .. ns.Color("accent", 4) .. " message reminders")]==],
      [==[(" and |cff0091ed" .. 4 .. "|r message reminders")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[(curated and ("  " .. ns.Color("accent", "[tank hit]")) or "")]==],
      [==[(true and ("  " .. ns.Color("accent", "[tank hit]")) or "")]==],
      [==[(true and "  |cff0091ed[tank hit]|r" or "")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[lbl:SetText(name .. "  " .. ns.Color("muted", "(" .. desc .. ")"))]==],
      [==["n" .. "  " .. ns.Color("muted", "(" .. "d" .. ")")]==],
      [==["n" .. "  |cff9a9ea6(" .. "d" .. ")|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[pickerHint:SetText(ns.Color("muted", "Nothing recorded for this boss yet -- pull it with "]==],
      [==[ns.Color("muted", "Nothing recorded for this boss yet -- pull it with " .. "BigWigs running, or type a Spell ID below.")]==],
      [==["|cff9a9ea6Nothing recorded for this boss yet -- pull it with " .. "BigWigs running, or type a Spell ID below.|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[pickerHint:SetText((ns.Color("muted", "+%d more not shown -- type the Spell ID below."))]==],
      [==[(ns.Color("muted", "+%d more not shown -- type the Spell ID below.")):format(5)]==],
      [==[("|cff9a9ea6+%d more not shown -- type the Spell ID below.|r"):format(5)]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_Bosses.lua]==],
      [==[feedback:SetText(ns.Color("muted", "no spell name found -- boss-mod keys aren't "]==],
      [==[ns.Color("muted", "no spell name found -- boss-mod keys aren't " .. "always real spell ids, that's fine")]==],
      [==["|cff9a9ea6no spell name found -- boss-mod keys aren't " .. "always real spell ids, that's fine|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_IntegrationOptions.lua]==],
      [==[ns.Print(("copied " .. ns.Color("accent", "%d") .. " %s from %s%s."):format(]==],
      [==[("copied " .. ns.Color("accent", "%d") .. " %s from %s%s."):format(3, "rules", "Spec", "")]==],
      [==[("copied |cff0091ed%d|r %s from %s%s."):format(3, "rules", "Spec", "")]==] },
    { [==[Core/NaowhForever_Packs.lua]==],
      [==[(ns.Color("accent", "%s") .. " by %s"):format(]==],
      [==[(ns.Color("accent", "%s") .. " by %s"):format("Pack", "Me")]==],
      [==[("|cff0091ed%s|r by %s"):format("Pack", "Me")]==] },
    { [==[Core/NaowhForever_Packs.lua]==],
      [==[("  " .. ns.Color("accent", "%s") .. "%s"):format(ns.PlainText(p.name), specText)]==],
      [==[("  " .. ns.Color("accent", "%s") .. "%s"):format("Pack", " (Arms)")]==],
      [==[("  |cff0091ed%s|r%s"):format("Pack", " (Arms)")]==] },
    { [==[Core/NaowhForever_Packs.lua]==],
      [==[(ns.Color("accent", "%s") .. "%s"):format(names[i],]==],
      [==[(ns.Color("accent", "%s") .. "%s"):format("Pack", " -- Arms")]==],
      [==[("|cff0091ed%s|r%s"):format("Pack", " -- Arms")]==] },
    { [==[Core/NaowhForever_Packs.lua]==],
      [==[(ns.Color("accent", "%s") .. " by %s%s%s|n%s"):format(]==],
      [==[(ns.Color("accent", "%s") .. " by %s%s%s|n%s"):format("Pack", "Me", " (x)", "", "d")]==],
      [==[("|cff0091ed%s|r by %s%s%s|n%s"):format("Pack", "Me", " (x)", "", "d")]==] },
    { [==[Core/NaowhForever_Packs.lua]==],
      [==[ns.Print(("merged into " .. ns.Color("accent", "%s") .. ": %d spec sections]==],
      [==[("merged into " .. ns.Color("accent", "%s") .. ": %d spec sections and %d reminders. Specs you " .. "did not tick are exactly as they were."):format("T", 1, 2)]==],
      [==[("merged into |cff0091ed%s|r: %d spec sections and %d reminders. Specs you " .. "did not tick are exactly as they were."):format("T", 1, 2)]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[ns.Print((ns.Color("accent", "callout timing") .. " (build %s), %d callout(s):")]==],
      [==[(ns.Color("accent", "callout timing") .. " (build %s), %d callout(s):"):format("b1", 3)]==],
      [==[("|cff0091edcallout timing|r (build %s), %d callout(s):"):format("b1", 3)]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[ns.Print((ns.Color("muted", "last pull, encounter %s")):format(tostring(enc)))]==],
      [==[(ns.Color("muted", "last pull, encounter %s")):format("12")]==],
      [==[("|cff9a9ea6last pull, encounter %s|r"):format("12")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[ns.Print((ns.Color("accent", "observed") .. " %s (%s): %d pull(s), longest %.0fs"):format(]==],
      [==[(ns.Color("accent", "observed") .. " %s (%s): %d pull(s), longest %.0fs"):format("n", "k", 2, 90)]==],
      [==[("|cff0091edobserved|r %s (%s): %d pull(s), longest %.0fs"):format("n", "k", 2, 90)]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[ns.Print((ns.Color("accent", "boss mod keys") .. " seen this pull (encounter %s):"):format(tostring(enc)))]==],
      [==[(ns.Color("accent", "boss mod keys") .. " seen this pull (encounter %s):"):format("12")]==],
      [==[("|cff0091edboss mod keys|r seen this pull (encounter %s):"):format("12")]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[verdict = ns.Color("muted", "steps aside to its Ability Reminder")]==],
      [==[ns.Color("muted", "steps aside to its Ability Reminder")]==],
      [==["|cff9a9ea6steps aside to its Ability Reminder|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[or ns.Color("muted", "not a tank ability"),]==],
      [==[ns.Color("muted", "not a tank ability")]==],
      [==["|cff9a9ea6not a tank ability|r"]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[ns.Print((ns.Color("accent", "tank sheet cross-check") .. " against %d journal-scraped bosses:")]==],
      [==[(ns.Color("accent", "tank sheet cross-check") .. " against %d journal-scraped bosses:"):format(7)]==],
      [==[("|cff0091edtank sheet cross-check|r against %d journal-scraped bosses:"):format(7)]==] },
    { [==[NaowhForever_SmartReminders/NaowhForever_SmartReminders.lua]==],
      [==[ns.Print((ns.Color("accent", "cooldowns") .. " (build %s), in priority order:"):format(BuildString()))]==],
      [==[(ns.Color("accent", "cooldowns") .. " (build %s), in priority order:"):format("b1")]==],
      [==[("|cff0091edcooldowns|r (build %s), in priority order:"):format("b1")]==] },
}

local sources = {}
for _, r in ipairs(ROWS) do
    local file, has, new, old = r[1], r[2], r[3], r[4]
    sources[file] = sources[file] or Read(file)
    Check(sources[file]:find(has, 1, true), file .. ": ships `" .. has:sub(1, 60) .. "`")
    local got, want = Eval(new), Eval(old)
    Check(got == want, file .. ": " .. new:sub(1, 60) .. " is the old string")
end

-- Nothing in the addon spells a theme color out any more (comments may mention one).
-- Every Lua file the TOC loads, following the XML files it includes.
local toc = {}
for _, path in ipairs(dofile("Tools/regression/toc_files.lua")("%.lua$")) do
    if not path:find("^Locales") and not path:find("^Libs") then toc[#toc + 1] = path end
end
Check(#toc > 50, "the TOC lists the addon's files")
local left = {}
for _, path in ipairs(toc) do
    local n = 0
    for line in Read(path):gmatch("[^\n]+") do
        if not line:match("^%s*%-%-") then
            for hex in line:gmatch("|c[fF][fF](%x%x%x%x%x%x)") do
                hex = hex:lower()
                if hex == "0091ed" or hex == "9a9ea6" or hex == "f0f1f3" or hex == "4db5f5" then
                    n = n + 1
                    left[#left + 1] = path .. ": " .. line:sub(1, 80)
                end
            end
        end
    end
end
Check(#left == 0, "hand-written theme colors left: " .. table.concat(left, " | "))

-- The constants that used to be built at file load are looked up when they are used.
local function Slice(path, first, last)
    local source = Read(path)
    local a = assert(source:find(first, 1, true), path .. ": " .. first)
    local b = assert(source:find(last, a, true), path .. ": " .. last)
    return source:sub(a, b + #last - 1)
end
local function Run(code, env)
    local chunk = assert(loadstring(code))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    return chunk()
end

local TAGS = { { "NaowhForever_BiS/BiS/Alerts.lua", "|cff0091edNaowh BiS|r" }, { "QoL/NaowhForever_Alts.lua", "|cff0091edNaowh|r" },
    { "QoL/NaowhForever_AuctionPrices.lua", "|cff0091edNaowh AH|r" }, { "QoL/NaowhForever_Mail.lua", "|cff0091edNaowh Mail|r" } }
for _, t in ipairs(TAGS) do
    local code = Slice(t[1], "local function Tag()", " end") .. "\nreturn Tag()"
    Check(Run(code, { ns = ns }) == t[2], t[1] .. ": Tag() is the old TAG")
end

do -- the two combat logging prompts
    local acl = Run(Slice("QoL/NaowhForever_CombatLogger.lua", "local function AclText()", "\nend") .. "\nreturn AclText()", { ns = ns })
    Check(acl == "|cff0091edNaowh|r Forever\n\nAdvanced Combat Logging is off. Warcraft Logs needs it "
        .. "for a detailed report. Turn it on now? This reloads your UI.", "the advanced logging prompt text")
    local log = Run(Slice("QoL/NaowhForever_CombatLogger.lua", "local function LogText()", "\nend") .. "\nreturn LogText()", { ns = ns })
    Check(log == "|cff0091edNaowh|r Forever\n\nEnable combat logging for:\n|cffffa300%s|r\n(%s)\n\n"
        .. "Your choice will be remembered.", "the combat logging prompt text")
    local src = Read("QoL/NaowhForever_CombatLogger.lua")
    Check(src:find('.text = AclText()', 1, true) and src:find('.text = LogText()', 1, true), "the text is set when shown")
end

print("PASS theme literals: " .. cases .. " checks (" .. #ROWS .. " rows, the tag and prompt accessors, and a scan for leftovers)")
