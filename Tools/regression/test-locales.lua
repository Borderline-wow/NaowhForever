-- Offline checks for the language Naowh Forever runs in: the client's or the one picked in Settings
-- (NaowhForever_Language), the per-language translation addon Core.lua loads, and the fonts for
-- CJK and Cyrillic text. Run from the repo root: lua Tools/regression/test-locales.lua

local FONT_CLASSIC = "Friz Quadrata TT"

local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function Exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

-- Each language is its own load-on-demand addon, NaowhForever_<code>, holding <code>.xml and
-- <code>.lua. The addon name tells the TOC code; the XML holds only that one file.
local function Load(client, picked)
    local loaded, filesRead = {}, {}
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
        local code = name:match("^NaowhForever_(%a%a%a%a)$")
        for path in Read(name .. "/" .. code .. ".xml"):gmatch('file="([^"]+)"') do
            local full = name .. "/" .. path
            filesRead[#filesRead + 1] = full
            local chunk = assert(loadstring(Read(full), full))
            setfenv(chunk, env)
            chunk()
        end
    end }
    for _, path in ipairs({ "Core/Locales/enUS.lua", "Core/Core.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", {})
    end
    return env.NaowhForever, loaded, filesRead
end

local ns, loaded, read = Load("enUS")
check("an English client loads no translation addon", ns.LOCALE == "enUS" and #loaded == 0 and #read == 0)
check("and shows the English text", ns.L("Language") == "Language" and ns.L("Back (slot)") == "Back")
check("its fonts are its own", ns.LocaleFont("Naowh", "Interface\\naowh.ttf") == "Interface\\naowh.ttf")

ns, loaded = Load("enGB")
check("a British client is English", ns.LOCALE == "enUS" and #loaded == 0)

ns, loaded, read = Load("deDE")
check("a German client loads exactly one addon, German", ns.LOCALE == "deDE" and #loaded == 1
    and loaded[1] == "NaowhForever_deDE")
check("and reads exactly one file, not every language's", #read == 1 and read[1] == "NaowhForever_deDE/deDE.lua")
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
check("Korean uses the game's Korean font everywhere", ns.LocaleFont("Naowh", "Interface\\naowh.ttf") == "Fonts\\2002.TTF"
    and ns.TitleFontPath() == "Fonts\\2002.TTF")
ns = Load("enUS", "zhTW")
check("Traditional Chinese has its own font", ns.LocaleFont("Naowh", "x") == "Fonts\\bLEI00D.ttf")
ns = Load("enUS", "ruRU")
check("Russian swaps Friz Quadrata for its Cyrillic cut, by name, not by the resolved path",
    ns.LocaleFont(FONT_CLASSIC, "Fonts\\FRIZQT__.TTF") == "Fonts\\FRIZQT___CYR.TTF"
    and ns.LocaleFont(FONT_CLASSIC, "Interface\\SomeOtherRegisteredPath.ttf") == "Fonts\\FRIZQT___CYR.TTF")
check("a different font name does not swap, even at the same path",
    ns.LocaleFont("Naowh", "Fonts\\FRIZQT__.TTF") == "Fonts\\FRIZQT__.TTF")

for _, code in ipairs(ns.LANGUAGES) do
    check(code .. " has a name in the picker", type(ns.LANGUAGE_NAMES[code]) == "string")
    if code ~= "enUS" then
        local folder = "NaowhForever_" .. code
        check(folder .. " has its own TOC and XML", Exists(folder .. "/" .. folder .. ".toc")
            and Exists(folder .. "/" .. code .. ".xml"))
        check(folder .. "'s XML lists only its own file", Read(folder .. "/" .. code .. ".xml")
            :find(code .. ".lua", 1, true) ~= nil and not Read(folder .. "/" .. code .. ".xml"):find("Script.*Script"))
    end
end

-- Settings' Language dropdown: UI.KeepMissing keeps a stale saved pick visible and selectable,
-- the same way the other LSM-backed dropdowns in that file do (UI.FontChoices, UI.TextureChoices).
local function LoadWidgets()
    local env = setmetatable({
        GetLocale = function() return "enUS" end,
        CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
    }, { __index = _G })
    env._G = env
    env.C_AddOns = { LoadAddOn = function() end }
    for _, path in ipairs({ "Core/Locales/enUS.lua", "Core/Core.lua", "Core/Options/Widgets.lua" }) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", {})
    end
    return env.NaowhForever
end
local wui = LoadWidgets().UI
local values, order = wui.KeepMissing({ en = "English" }, { "en" }, "ghostCode")
check("KeepMissing adds a stale saved value back in", values.ghostCode ~= nil and order[#order] == "ghostCode")
local _, order2 = wui.KeepMissing({ en = "English" }, { "en" }, "en")
check("and leaves a known value alone", order2[#order2] == "en" and #order2 == 1)

print(checks .. " locale checks passed")
