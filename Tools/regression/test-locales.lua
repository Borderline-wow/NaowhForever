-- Offline checks for the language Naowh Forever runs in: the client's or the one picked in Settings
-- (NaowhForever_Language), the translations NaowhForever_Locales loads, and the fonts for CJK text.
-- Run from the repo root: lua Tools/regression/test-locales.lua

local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function Load(client, picked)
    local loaded = {}
    local env = setmetatable({
        GetLocale = function() return client end,
        NaowhForeverLanguageDB = picked and { locale = picked } or nil,
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
        CreateFrame = function()
            return setmetatable({}, { __index = function() return function() end end })
        end,
    }, { __index = _G })
    env._G = env
    env.C_AddOns = { LoadAddOn = function(name)
        loaded[#loaded + 1] = name
        for path in Read(name .. "/Locales.xml"):gmatch('file="([^"]+)"') do
            local chunk = assert(loadstring(Read(name .. "/" .. path), path))
            setfenv(chunk, env)
            chunk()
        end
    end }
    for _, path in ipairs({ "Core/Locales/enUS.lua", "Core/Core.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", {})
    end
    return env.NaowhForever, loaded
end

local ns, loaded = Load("enUS")
check("an English client loads no translations", ns.LOCALE == "enUS" and #loaded == 0)
check("and shows the English text", ns.L("Language") == "Language" and ns.L("Back (slot)") == "Back")
check("its fonts are its own", ns.LocaleFont("Fonts\\FRIZQT__.TTF") == "Fonts\\FRIZQT__.TTF")

ns, loaded = Load("enGB")
check("a British client is English", ns.LOCALE == "enUS" and #loaded == 0)

ns, loaded = Load("deDE")
check("a German client loads the translations once", ns.LOCALE == "deDE" and #loaded == 1
    and loaded[1] == "NaowhForever_Locales")
check("and shows German", ns.L("Language") == "Sprache")
check("a key with context shows its translation", ns.L("Back (slot)") ~= "Back (slot)")
check("an untranslated key falls back to English", ns.L("No such string %d", 3) == "No such string 3")

ns = Load("enUS", "deDE")
check("a language picked in Settings wins over the client's", ns.LOCALE == "deDE" and ns.L("Language") == "Sprache")
ns = Load("deDE", "enUS")
check("English can be picked on a German client", ns.LOCALE == "enUS" and ns.L("Language") == "Language")
ns = Load("deDE", "auto")
check("Game Language follows the client", ns.LOCALE == "deDE")
ns = Load("frFR", "xxXX")
check("an unknown pick follows the client", ns.LOCALE == "frFR")

ns = Load("enUS", "koKR")
check("Korean uses the game's Korean font everywhere", ns.LocaleFont("Interface\\naowh.ttf") == "Fonts\\2002.TTF"
    and ns.TitleFontPath() == "Fonts\\2002.TTF")
ns = Load("enUS", "zhTW")
check("Traditional Chinese has its own font", ns.LocaleFont("x") == "Fonts\\bLEI00D.ttf")
ns = Load("enUS", "ruRU")
check("Russian swaps Friz Quadrata for its Cyrillic cut", ns.LocaleFont("Fonts\\FRIZQT__.TTF") == "Fonts\\FRIZQT___CYR.TTF"
    and ns.LocaleFont("Interface\\naowh.ttf") == "Interface\\naowh.ttf")

for _, code in ipairs(ns.LANGUAGES) do
    check(code .. " has a name in the picker", type(ns.LANGUAGE_NAMES[code]) == "string")
    if code ~= "enUS" then
        check(code .. " is in NaowhForever_Locales", Read("NaowhForever_Locales/Locales.xml"):find(code .. ".lua", 1, true) ~= nil)
    end
end

print(checks .. " locale checks passed")
