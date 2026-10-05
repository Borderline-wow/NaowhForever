-------------------------------------------------------------------------------
--  NaowhForever_Packs.lua -- shareable Reminder Packs.
--
--  A pack is a curator's lists, callouts, mutes and reminders in one string:
--  LibSerialize + LibDeflate + print encoding under its own prefix. Imports
--  preview first, validate whole, and land in a new profile. Ordinary packs
--  carry no license; only naowh.gg's personalized download appends a signed
--  ":LIC1:" segment (see NaowhForever_Verify.lua).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
if not ns then return end

local PREFIX = "NSRPACK2:"
local PACK_FORMAT = 1
local LICENSE_MARKER = ":LIC1:"
local MAX_PACK_CHARS = 1000000

-- Sections a pack may carry, in display order. value: what every entry of a flat section
-- must be. perEntry: merged reminder by reminder rather than a boss at a time.
-- customReminders, not `reminders`: nothing writes the latter, so exports silently lost
-- every custom reminder. activePreset rides along so the curator's live list survives.
local SECTIONS = {
    { field = "utilityReminders", label = "consumable and class macro groups", count = "keys", value = "table" },
    { field = "presets",         label = "spec priority lists",  count = "nested" },
    { field = "activePreset",    label = "active preset choice", count = "keys", value = "string" },
    { field = "bossLists",       label = "per-boss orders",      count = "keys", value = "table" },
    { field = "callouts",        label = "callout lines",        count = "keys", value = "string" },
    { field = "customReminders", label = "custom reminders",     count = "nested", perEntry = true },
    { field = "abilityBindings", label = "ability on/off",       count = "nested" },
    { field = "audioOff",        label = "audio switches",       count = "keys", value = "boolean" },
    { field = "raidReminders",   label = "raid reminders",       count = "nested", perEntry = true },
    { field = "integrationRules", label = "trash and debuff rules", count = "nested", perEntry = true },
}

local function CountSection(kind, t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    if kind == "nested" then
        for _, inner in pairs(t) do
            if type(inner) == "table" then
                for _ in pairs(inner) do n = n + 1 end
            end
        end
    else
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

-- Validate known fields without stripping forward-compatible metadata. Limits also
-- stop cyclic/deep serializer values from reaching the recursive copy on import.
local ENTRY_TABLES = { "trigger", "display", "target", "list", "together" }

local function PlainData(value, seen, depth, budget)
    local kind = type(value)
    if kind == "number" then return value == value and math.abs(value) < math.huge end
    if kind ~= "table" then return kind == "string" or kind == "boolean" or kind == "nil" end
    if seen[value] or depth > 32 then return false end
    seen[value] = true
    for k, v in pairs(value) do
        budget[1] = budget[1] - 1
        if budget[1] < 0 or (type(k) ~= "string" and type(k) ~= "number")
            or not PlainData(k, seen, depth + 1, budget)
            or not PlainData(v, seen, depth + 1, budget) then return false end
    end
    seen[value] = nil
    return true
end

local function Fields(t, schema)
    if type(t) ~= "table" then return false end
    for key, kinds in pairs(schema) do
        local v = t[key]
        if v ~= nil and not ("|" .. kinds .. "|"):find("|" .. type(v) .. "|", 1, true) then
            return false
        end
    end
    return true
end

local function FlagMap(t)
    if t == nil then return true end
    if type(t) ~= "table" then return false end
    for _, flag in pairs(t) do if type(flag) ~= "boolean" then return false end end
    return true
end

local function SpellList(t)
    if type(t) ~= "table" then return false end
    local count = 0
    for index, sid in pairs(t) do
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0
            or type(sid) ~= "number" or sid <= 0 or sid % 1 ~= 0 then return false end
        count = count + 1
    end
    for i = 1, count do if t[i] == nil then return false end end
    return true
end

local COLOR_FIELDS = { r = "number", g = "number", b = "number", a = "number" }
local TRIGGER_FIELDS = { type = "string", spellID = "number", delay = "number|string",
    stage = "number", leadTime = "number", timeleft = "number", counter = "string|number",
    target = "string", auraEvent = "string", mapID = "number" }
local DISPLAY_FIELDS = { type = "string", text = "string", spellID = "number", dur = "number",
    sound = "string", tts = "boolean", glowTarget = "string", hideAfterCastID = "number" }
local ENTRY_FIELDS = { name = "string", enabled = "boolean", specID = "number", healerReminder = "boolean",
    preset = "string", mode = "string", defensive = "boolean", dur = "number",
    text = "string", sound = "string", abilitySpellID = "number" }

local function ValidEntry(entry)
    if not Fields(entry, ENTRY_FIELDS) then return false end
    for j = 1, #ENTRY_TABLES do
        local v = entry[ENTRY_TABLES[j]]
        if v ~= nil and type(v) ~= "table" then return false end
    end
    if entry.list and not SpellList(entry.list) then return false end
    if not FlagMap(entry.together) then return false end
    if entry.trigger and not Fields(entry.trigger, TRIGGER_FIELDS) then return false end
    local display = entry.display
    if display and (not Fields(display, DISPLAY_FIELDS)
        or (display.color and not Fields(display.color, COLOR_FIELDS))) then return false end
    if entry.color and not Fields(entry.color, COLOR_FIELDS) then return false end
    local target = entry.target
    if target then
        if not Fields(target, { all = "boolean", kind = "string", value = "string|number" }) then
            return false
        end
        for _, key in ipairs({ "roles", "classes", "specs", "names", "subgroups" }) do
            if not FlagMap(target[key]) then return false end
        end
        if target.kind and target.kind ~= "all" and target.value == nil then return false end
    end
    return true
end

-- A bound on one pack string, not on what a spec may hold.
local MAX_IMPORTED_RULES = 500

local function PositiveID(id)
    return type(id) == "number" and id >= 1 and id <= 2147483647 and id == math.floor(id)
end
local function ValidUtilities(data)
    if type(data) ~= "table" then return false end
    local categories = { food = true, flask = true, scroll = true, battle = true, guardian = true }
    if data.consumables ~= nil then
        if type(data.consumables) ~= "table" then return false end
        local count = 0
        for index, entry in pairs(data.consumables) do
            count = count + 1
            if not PositiveID(index) or index > #data.consumables or count > 500
                or type(entry) ~= "table" or not categories[entry.category]
                or not PositiveID(entry.itemID) or type(entry.auras) ~= "table" or #entry.auras == 0 then return false end
            for i, id in pairs(entry.auras) do
                if not PositiveID(i) or i > #entry.auras or not PositiveID(id) then return false end
            end
        end
    end
    if data.classMacros ~= nil then
        if type(data.classMacros) ~= "table" then return false end
        for class, entries in pairs(data.classMacros) do
            if type(class) ~= "string" or type(entries) ~= "table" then return false end
            for i, entry in pairs(entries) do
                if not PositiveID(i) or i > #entries or #entries > 100 or type(entry) ~= "table"
                    or type(entry.name) ~= "string" or #entry.name < 1 or #entry.name > 16
                    or type(entry.body) ~= "string" or #entry.body < 1 or #entry.body > 255
                    or entry.icon ~= nil and not PositiveID(entry.icon)
                    or entry.note ~= nil and (type(entry.note) ~= "string" or #entry.note > 200) then return false end
            end
        end
    end
    return true
end

local function ValidData(data)
    if not PlainData(data, {}, 0, { 100000 }) then return false end
    if data.utilityReminders ~= nil and not ValidUtilities(data.utilityReminders) then return false end
    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local t = data[sec.field]
        if t ~= nil then
            if type(t) ~= "table" then return false end
            for _, inner in pairs(t) do
                if sec.value then
                    if type(inner) ~= sec.value then return false end
                    if sec.field == "bossLists" and not SpellList(inner) then return false end
                elseif type(inner) ~= "table" then
                    return false
                else
                    if sec.field == "integrationRules" then
                        local count = 0
                        for uid in pairs(inner) do
                            count = count + 1
                            if type(uid) ~= "string" or count > MAX_IMPORTED_RULES then
                                return false
                            end
                        end
                    end
                    for _, entry in pairs(inner) do
                        if type(entry) ~= "table" then return false end
                        if sec.field == "abilityBindings" and data.bindingsBySpec ~= false then
                            -- Current shape is spec -> encounter -> spell -> binding.
                            -- An older, unmigrated export explicitly carries false.
                            for _, binding in pairs(entry) do
                                if not ValidEntry(binding) then return false end
                            end
                        elseif sec.field == "integrationRules" then
                            if not (ns.Integrations and ns.Integrations.ValidRule(entry)) then return false end
                        elseif not ValidEntry(entry) then return false end
                    end
                end
            end
        end
    end
    if data.modules ~= nil and type(data.modules) ~= "table" then return false end
    if data.settings ~= nil then
        if type(data.settings) ~= "table" then return false end
        if data.settings.pos and not Fields(data.settings.pos,
            { point = "string", relPoint = "string", x = "number", y = "number" }) then return false end
    end
    return true
end

-- LibSerialize's Deserialize returns (ok, value); re-raised so callers' pcall sees a throw.
local function Codec()
    local LS = LibStub and LibStub("LibSerialize", true)
    local LD = LibStub and LibStub("LibDeflate", true)
    if not (LS and LD) then return nil end
    local Ser = {
        Serialize = function(v) return LS:Serialize(v) end,
        Deserialize = function(s)
            local ok, v = LS:Deserialize(s)
            if not ok then error(v, 0) end
            return v
        end,
    }
    return Ser, LD
end

-- Deep copy, so a pack never aliases live settings tables.
local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = Copy(val) end
    return out
end

-- Only settings this addon keeps, and only as the type it keeps them in.
local function ApplySettings(tr, settings)
    for k, v in pairs(settings) do
        if k == "pos" then
            if type(v) == "table" then tr.pos = Copy(v) end
        elseif type(v) == type(ns.SettingDefault(k)) then
            tr[k] = v
        end
    end
end

-- Also run over inactive profiles, read straight from saved variables without loading them.
local function DataFromProfile(tr)
    local data, any = {}, false
    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local t = tr[sec.field]
        if type(t) == "table" and next(t) ~= nil then
            data[sec.field] = Copy(t)
            any = true
        end
    end
    data.leadTime = tr.leadTime
    data.voiceNone = tr.voiceNone
    -- An inactive profile never ran the binding-scope migration, so its abilityBindings
    -- may be pre-migration; the landing side needs to know.
    data.bindingsBySpec = tr.bindingsBySpec == true
    local settings = {}
    local keys = ns.SettingKeys and ns.SettingKeys() or {}
    for i = 1, #keys do
        local v = tr[keys[i]]
        local vt = type(v)
        if vt == "number" or vt == "string" or vt == "boolean" then settings[keys[i]] = v end
    end
    if type(tr.pos) == "table" then settings.pos = Copy(tr.pos) end
    if next(settings) ~= nil then data.settings = settings end
    return data, any
end

-- allowImported hands work back to the curator whose pack this came from; only the slash
-- command passes it, never the Share button. Such a pack carries derivedFrom so it is not
-- mistaken for an original. Attribution, not a lock.
function ns.ExportPack(packName, author, allowImported)
    local Ser, LD = Codec()
    if not Ser then return nil, "The serializer libraries are missing from this build." end

    local db = ns.DB()
    local derivedFrom
    if type(db.importedPack) == "table" then
        -- Refused even for hand-back: an export carries no licence. Known gap: profiles
        -- imported before the licensed flag existed stay exportable until reimported
        -- (licences last 30 days, so this closes itself).
        if db.importedPack.licensed then
            return nil, ("This profile came from %s, which is licensed to the account that "
                .. "downloaded it. It cannot be exported. Get your own copy from naowh.gg."):format(
                db.importedPack.name)
        end
        if not allowImported then
            return nil, ("This profile contains an imported pack (%s by %s), so it cannot "
                .. "be shared onward. Build your own profile to share one."):format(
                db.importedPack.name, db.importedPack.author)
        end
        derivedFrom = { name = tostring(db.importedPack.name),
            author = tostring(db.importedPack.author) }
    end
    local data, any = DataFromProfile(db)
    data.modules = ns.ExportModuleSettings and ns.ExportModuleSettings(ns.SettingsRoot())
    if data.modules then any = true end
    if not any then return nil, "There is nothing to export yet." end

    local payload = {
        format  = PACK_FORMAT,
        name    = (packName and packName ~= "") and packName or "Reminder Pack",
        author  = (author and author ~= "") and author or (UnitName and UnitName("player")) or "unknown",
        made    = date and date("%Y-%m-%d") or "",
        derivedFrom = derivedFrom,
        data    = data,
    }
    local ok, serialized = pcall(Ser.Serialize, payload)
    if not ok then return nil, "The pack could not be serialized." end
    local compressed = LD:CompressDeflate(serialized)
    return PREFIX .. LD:EncodeForPrint(compressed)
end

-- Installer API: show DescribeProfilePack's text and get confirmation, then call
-- InstallProfilePack with the same opts. Guard on _G.NaowhForever (optional addon) and call
-- after our ADDON_LOADED, or the profile is written into nothing and lost at logout.
-- Returns text (|n-separated) and info, the same facts as a table. Mutates nothing.
function ns.DescribeProfilePack(str, opts)
    opts = type(opts) == "table" and opts or {}
    local payload, err = ns.DecodePack(str)
    if not payload then return nil, nil, err or "the string could not be read" end

    local multi = type(payload.profiles) == "table"
    local wantSettings = opts.settings ~= false
    local wantBind = opts.bindSpecs ~= false

    local profiles = {}
    if multi then
        local names = {}
        -- A "Default" profile is refused at apply time anyway.
        for name in pairs(payload.profiles) do
            if name ~= "Default" then names[#names + 1] = name end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        for i = 1, #names do
            local specs = ns.PackSpecs({ data = payload.profiles[names[i]] })
            local specNames = {}
            for j = 1, #specs do specNames[j] = specs[j].name end
            profiles[#profiles + 1] = { name = names[i], specs = specNames }
        end
    else
        local specs = ns.PackSpecs(payload)
        local specNames = {}
        for j = 1, #specs do specNames[j] = specs[j].name end
        profiles[1] = {
            name = (payload.name and payload.name ~= "") and payload.name or "Reminder Pack",
            specs = specNames,
        }
    end

    local accountProfileOK = nil
    if opts.accountProfile then
        accountProfileOK = false
        for i = 1, #profiles do
            if profiles[i].name == opts.accountProfile then accountProfileOK = true break end
        end
    end

    local movedChars = (opts.accountProfile and accountProfileOK) and ns.KnownCharacters() or {}

    local info = {
        packName = payload.name, packAuthor = payload.author,
        profiles = profiles,
        willApplySettings = wantSettings,
        willBindSpecs = multi and wantBind or false,
        accountProfile = opts.accountProfile,
        accountProfileOK = accountProfileOK,
        movedCharacters = movedChars,
    }

    local lines = {}
    lines[#lines + 1] = (ns.Color("accent", "%s") .. " by %s"):format(
        tostring(payload.name), tostring(payload.author))
    if type(payload.derivedFrom) == "table" then
        lines[#lines + 1] = ("|cffF0A830Built on|r %s by %s."):format(
            tostring(payload.derivedFrom.name), tostring(payload.derivedFrom.author))
    end
    lines[#lines + 1] = ("Will create %d new profile%s:"):format(
        #profiles, #profiles == 1 and "" or "s")
    for i = 1, #profiles do
        local p = profiles[i]
        local specText = #p.specs > 0 and (" -- " .. table.concat(p.specs, ", ")) or ""
        lines[#lines + 1] = ("  " .. ns.Color("accent", "%s") .. "%s"):format(p.name, specText)
    end
    lines[#lines + 1] = "Your own existing profiles are not changed."
    if wantSettings then
        lines[#lines + 1] = "Includes display, sound and behaviour settings, which will be "
            .. "applied."
    end
    if info.willBindSpecs then
        lines[#lines + 1] = "Each profile is bound to the specs it covers, and spec-matching "
            .. "is switched on: changing spec, on ANY character, auto-loads the matching one."
    end
    if opts.accountProfile then
        if accountProfileOK then
            lines[#lines + 1] = ("|cffff6060Every character on this account will be switched "
                .. "to '%s'|r, including any not yet listed below."):format(opts.accountProfile)
            if #movedChars > 0 then
                local names = {}
                for i = 1, #movedChars do
                    names[i] = ("%s (was %s)"):format(movedChars[i].char, movedChars[i].profile)
                end
                lines[#lines + 1] = "  Known characters: " .. table.concat(names, ", ")
            end
        else
            lines[#lines + 1] = ("|cffff6060'%s' is not one of the profiles this pack "
                .. "carries -- the account switch would fail.|r"):format(
                tostring(opts.accountProfile))
        end
    end

    return table.concat(lines, "|n"), info
end

-- ImportPackAsProfile maps the current spec to the profile it lands. Callers that then set the
-- account profile put this entry back, so per-spec switching turned on again keeps the
-- player's own choice.
local function CurrentSpecEntry()
    local spec = ns.CurrentSpec and ns.CurrentSpec()
    if not spec or spec <= 0 then return nil end
    return tostring(spec), ns.SpecProfileMap()[tostring(spec)]
end

-- opts, all optional:
--   accountProfile  point every character at this profile (must be one the pack carries).
--                   Turns per-spec switching off, so bindSpecs bindings land dormant.
--   bindSpecs       bind each landed profile to its specs and switch matching on. Default true.
--   settings        take the curator's display, sound and behaviour settings. Default true.
--   profileName     land a single-profile pack under this name, replacing a profile already
--                   there, so a rerun refreshes it instead of adding "Naowh 2".
-- Returns true and the number of profiles landed (the profile's name for a single-profile
-- pack), or false and a reason. Never throws.
function ns.InstallProfilePack(str, opts)
    opts = type(opts) == "table" and opts or {}
    local payload, err = ns.DecodePack(str)
    if not payload then return false, err or "the string could not be read" end

    local settings = opts.settings ~= false
    local multi = type(payload.profiles) == "table"
    local specKey, specWas = CurrentSpecEntry()
    local ok, landed
    if multi then
        local bind = opts.bindSpecs ~= false
        ok, landed = ns.ApplyProfiles(payload, nil, settings, bind)
        if ok and bind then ns.AutoSpecProfile(true) end
    else
        local name = type(opts.profileName) == "string" and opts.profileName or nil
        ok, landed = ns.ImportPackAsProfile(payload, nil, settings, name,
            name ~= nil and name:match("%S") ~= nil)
    end
    if not ok then return false, "the pack could not be applied" end

    if opts.accountProfile then
        local set, why = ns.SetAccountProfile(opts.accountProfile)
        if not set then
            return false, ("imported, but %s is not a profile in this pack (%s)"):format(
                tostring(opts.accountProfile), tostring(why))
        end
        if specKey and not multi then ns.SpecProfileMap()[specKey] = specWas end
    end

    if ns.ApplySpecProfile and ns.CurrentSpec then ns.ApplySpecProfile((ns.CurrentSpec())) end
    return true, landed
end

-- Public entry point for the NaowhUI installer, so it never calls into ns:
--   NaowhForever_API:ImportProfile(str, "Naowh")
-- A single-profile pack lands as profileName and becomes the account profile for every
-- character. A whole-file pack keeps its own names and binds them to specs instead.
local API = {}
_G.NaowhForever_API = API

function API:ImportProfile(str, profileName)
    local specKey, specWas = CurrentSpecEntry()
    local ok, landed = ns.InstallProfilePack(str, { profileName = profileName })
    -- The installer ignores the return values, so failures are reported here.
    if not ok then
        ns.Print("Naowh Forever import failed: " .. tostring(landed))
        return false, landed
    end
    if type(landed) == "string" then
        local set, autoOff = ns.SetAccountProfile(landed)
        if set and specKey then ns.SpecProfileMap()[specKey] = specWas end
        if set and autoOff then
            ns.Print(("Per-spec profile switching is off while every character shares '%s'; "
                .. "your spec choices are kept if you switch it back on."):format(landed))
        end
    end
    return true, landed
end

-- Decode and validate; returns the payload plus a human description, or nil
-- and a reason. Applies nothing.
function ns.DecodePack(str)
    local Ser, LD = Codec()
    if not Ser then return nil, "The serializer libraries are missing from this build." end
    if type(str) ~= "string" then return nil, "Nothing to read." end
    str = str:gsub("%s+", "")
    if str == "" then return nil, "Nothing to read." end
    if #str > MAX_PACK_CHARS then return nil, "That string is too large to be a Reminder Pack." end

    -- The print-encoded payload (a-zA-Z0-9() only) never contains a colon, so this
    -- can only match the real marker.
    local license
    local licStart = str:find(LICENSE_MARKER, 1, true)
    if licStart then
        license = str:sub(licStart + #LICENSE_MARKER)
        str = str:sub(1, licStart - 1)
    end

    if str:sub(1, #PREFIX) ~= PREFIX then
        return nil, "Not a Reminder Pack string (missing the " .. PREFIX .. " prefix)."
    end
    local decoded = LD:DecodeForPrint(str:sub(#PREFIX + 1))
    if not decoded then return nil, "The string is damaged (encoding)." end
    local decompressed = LD:DecompressDeflate(decoded)
    if not decompressed then return nil, "The string is damaged (compression)." end
    local ok, payload = pcall(Ser.Deserialize, decompressed)
    if not ok or type(payload) ~= "table" then
        return nil, "The string is damaged (contents)."
    end
    if payload.format ~= PACK_FORMAT then
        return nil, "This pack needs a newer version of the addon."
    end
    -- Never trusted off the wire: set here and nowhere else.
    payload.licensed = nil
    if license then
        local licOk, licErr = ns.CheckPackLicense(license)
        if not licOk then return nil, licErr end
        payload.licensed = true
    end
    local multi = type(payload.profiles) == "table" and next(payload.profiles) ~= nil
    if not multi and type(payload.data) ~= "table" then return nil, "The pack is empty." end
    for name, data in pairs(multi and payload.profiles or { payload.data }) do
        if multi and (type(name) ~= "string" or name == "") then
            return nil, "The string is damaged (profile name)."
        end
        if type(data) ~= "table" or not ValidData(data) then
            return nil, "The string is damaged (contents)."
        end
    end

    local parts = {}
    local refusedDefault = false
    if multi then
        local names = {}
        for name in pairs(payload.profiles) do
            if name ~= "Default" then
                names[#names + 1] = name
            else
                refusedDefault = true
            end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        for i = 1, #names do
            local specs = ns.PackSpecs({ data = payload.profiles[names[i]] })
            local specText
            for j = 1, #specs do
                specText = specText and (specText .. ", " .. specs[j].name) or specs[j].name
            end
            parts[#parts + 1] = (ns.Color("accent", "%s") .. "%s"):format(names[i],
                specText and (" -- " .. specText) or "")
        end
    else
        for i = 1, #SECTIONS do
            local sec = SECTIONS[i]
            local n = CountSection(sec.count, payload.data[sec.field])
            if n > 0 then parts[#parts + 1] = ("%d %s"):format(n, sec.label) end
        end
    end
    if #parts == 0 then
        -- Older exports could carry only a Default profile.
        if refusedDefault then
            return nil, "This pack carries only a profile named Default, which is never "
                .. "landed -- every account already has its own."
        end
        return nil, "The pack is empty."
    end

    -- Set only by /nutank share.
    local derived = ""
    if type(payload.derivedFrom) == "table" then
        derived = ("|n|cffF0A830Built on|r %s by %s."):format(
            tostring(payload.derivedFrom.name), tostring(payload.derivedFrom.author))
    end
    local desc = (ns.Color("accent", "%s") .. " by %s%s%s|n%s"):format(
        tostring(payload.name), tostring(payload.author),
        type(payload.made) == "string" and payload.made ~= "" and (" (" .. payload.made .. ")") or "",
        derived,
        table.concat(parts, multi and "|n" or ", "))
    return payload, desc
end

-- presets, activePreset and abilityBindings are keyed by spec; bossLists keys are
-- "spec:encounter". Every other section belongs to no spec.
function ns.PackSpecs(payload)
    if type(payload) ~= "table" or type(payload.data) ~= "table" then return {} end
    local d, seen = payload.data, {}
    for _, field in ipairs({ "presets", "activePreset", "abilityBindings" }) do
        if type(d[field]) == "table" then
            for k in pairs(d[field]) do seen[tostring(k)] = true end
        end
    end
    if type(d.bossLists) == "table" then
        for k in pairs(d.bossLists) do
            local spec = tostring(k):match("^(%d+):")
            if spec then seen[spec] = true end
        end
    end
    local out = {}
    for key in pairs(seen) do
        out[#out + 1] = { key = key, name = ns.SpecName(key) }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- wantSpecs: set of spec keys to take from the spec-keyed sections; nil takes everything.

local function FilterToSpecs(field, incoming, wantSpecs)
    if not wantSpecs then return Copy(incoming) end
    local out = {}
    if field == "bossLists" then
        for k, v in pairs(incoming) do
            local spec = tostring(k):match("^(%d+):")
            if spec and wantSpecs[spec] then out[k] = Copy(v) end
        end
    elseif field == "presets" or field == "activePreset" or field == "abilityBindings" then
        for k, v in pairs(incoming) do
            if wantSpecs[tostring(k)] then out[k] = Copy(v) end
        end
    else
        return Copy(incoming)
    end
    return out
end

-- A whole-file pack: each profile lands under its own name and the importer is not switched.
-- Existing same-name profiles are merged into: reminders one at a time, spec-keyed sections a
-- whole spec at a time, since a binding names its preset by key.
function ns.ApplyProfiles(payload, wantProfiles, wantSettings, bindSpecs)
    if type(payload) ~= "table" or type(payload.profiles) ~= "table" then return false end
    for name, data in pairs(payload.profiles) do
        if type(name) ~= "string" or name == "" or type(data) ~= "table" or not ValidData(data) then
            return false
        end
    end
    local existing = {}
    do
        local names = ns.ListProfiles and ns.ListProfiles() or {}
        for i = 1, #names do existing[names[i]] = true end
    end
    local landed = 0
    for name, data in pairs(payload.profiles) do
        -- Default is refused: older strings still carry one, and every account has its own.
        if name ~= "Default" and (not wantProfiles or wantProfiles[name])
            and type(data) == "table" then
            local isNewProfile = not existing[name]
            local tr = ns.EnsureProfile and ns.EnsureProfile(name)
            if tr then
                for i = 1, #SECTIONS do
                    local sec = SECTIONS[i]
                    local incoming = data[sec.field]
                    if type(incoming) == "table" then
                        if type(tr[sec.field]) ~= "table" then tr[sec.field] = {} end
                        local dst = tr[sec.field]
                        for k, v in pairs(incoming) do
                            if sec.perEntry and type(dst[k]) == "table" then
                                for uid, r in pairs(v) do dst[k][uid] = Copy(r) end
                            else
                                dst[k] = Copy(v)
                            end
                        end
                    end
                end
                if wantSettings and type(data.settings) == "table" then
                    ApplySettings(tr, data.settings)
                end
                if wantSettings and ns.ImportModuleSettings then
                    ns.ImportModuleSettings(ns.ProfileRoot(name), data.modules)
                end
                tr.importedPack = {
                    name = tostring(payload.name or "a pack"),
                    author = tostring(payload.author or "its curator"),
                    licensed = payload.licensed or nil,
                }
                -- Only a new profile trusts the source (nil, from older packs, means true).
                -- Forcing it on a merge could stamp a profile whose own legacy entries were
                -- never migrated, and the migration would never run on them.
                if isNewProfile then
                    tr.bindingsBySpec = data.bindingsBySpec ~= false
                end
                -- The last profile to claim a spec wins.
                if bindSpecs then
                    local specs = ns.PackSpecs({ data = data })
                    for si = 1, #specs do
                        ns.SetSpecProfile(tonumber(specs[si].key), name)
                    end
                end
                landed = landed + 1
            end
        end
    end
    if landed == 0 then return false end
    ns.RefreshRuntime()
    return true, landed
end

-- Merge one profile from a pack into an existing one, for contributors handing back the
-- specs they maintain. opts.specs filters to those specs, since a contributor's string
-- carries stale copies of every other spec. A chosen spec is taken whole: trash rules are
-- numbered per spec, so merging them one at a time left old rules behind. Per-boss
-- reminders filter by their recorded spec; spec-less sections need opts.extras.
-- opts.settings is off by default.
local MERGE_WHOLE_SPEC = { presets = true, activePreset = true,
    abilityBindings = true, integrationRules = true }
local MERGE_NO_SPEC = { utilityReminders = true, raidReminders = true, callouts = true, audioOff = true }

function ns.MergeProfileFromPack(payload, sourceName, targetName, opts)
    opts = type(opts) == "table" and opts or {}
    local wantSpecs = opts.specs
    if type(payload) ~= "table" then return false, "there is nothing to read" end
    local data
    if type(payload.profiles) == "table" then
        data = sourceName and payload.profiles[sourceName]
        if type(data) ~= "table" then return false, "that profile is not in this string" end
    else
        data = payload.data
    end
    if type(data) ~= "table" or not ValidData(data) then
        return false, "the string does not carry a profile"
    end
    if type(targetName) ~= "string" or targetName == "" then
        return false, "choose the profile to merge into"
    end
    if not (ns.ProfileExists and ns.ProfileExists(targetName)) then
        return false, "that profile no longer exists"
    end
    if wantSpecs and not next(wantSpecs) then return false, "choose at least one spec" end
    local tr = ns.EnsureProfile and ns.EnsureProfile(targetName)
    if not tr then return false, "that profile could not be opened" end

    -- Otherwise merging, then exporting the target, walks around ExportPack's licence guard.
    if payload.licensed then
        tr.importedPack = {
            name = tostring(payload.name or "a pack"),
            author = tostring(payload.author or "its curator"),
            licensed = true,
        }
    end

    local specs, entries = 0, 0
    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local incoming = data[sec.field]
        if type(incoming) == "table"
            and not (wantSpecs and MERGE_NO_SPEC[sec.field] and not opts.extras) then
            if type(tr[sec.field]) ~= "table" then tr[sec.field] = {} end
            local dst = tr[sec.field]
            for k, v in pairs(incoming) do
                local owner
                if MERGE_WHOLE_SPEC[sec.field] then owner = tostring(k)
                elseif sec.field == "bossLists" then owner = tostring(k):match("^(%d+):") end
                if not (wantSpecs and owner and not wantSpecs[owner]) then
                    if MERGE_WHOLE_SPEC[sec.field] then
                        dst[k] = Copy(v)
                        specs = specs + 1
                    elseif sec.field == "customReminders" then
                        if type(dst[k]) ~= "table" then dst[k] = {} end
                        for uid, r in pairs(v) do
                            local mine = not wantSpecs
                                or (type(r) == "table" and r.specID
                                    and wantSpecs[tostring(r.specID)] == true)
                            if mine then
                                dst[k][uid] = Copy(r)
                                entries = entries + 1
                            end
                        end
                    elseif sec.perEntry and type(dst[k]) == "table" then
                        for uid, r in pairs(v) do
                            dst[k][uid] = Copy(r)
                            entries = entries + 1
                        end
                    else
                        dst[k] = Copy(v)
                        specs = specs + 1
                    end
                end
            end
        end
    end
    if opts.settings and type(data.settings) == "table" then ApplySettings(tr, data.settings) end
    if opts.settings and ns.ImportModuleSettings then
        ns.ImportModuleSettings(ns.ProfileRoot(targetName), data.modules)
    end
    ns.RefreshRuntime()
    return true, specs, entries
end

local function FreeProfileName(base)
    base = (type(base) == "string" and base ~= "") and base or "Imported Profile"
    local taken = {}
    local names = ns.ListProfiles and ns.ListProfiles() or {}
    for i = 1, #names do taken[names[i]] = true end
    if not taken[base] then return base end
    local n = 2
    while taken[base .. " " .. n] do n = n + 1 end
    return base .. " " .. n
end

-- Imports as a new profile, touching nothing existing; replace once took a user's specs and
-- presets, twice. `overwrite` (opt-in, for monthly re-downloads of the same pack) clears the
-- target first and never applies to "Default".
function ns.ImportPackAsProfile(payload, wantSpecs, wantSettings, customName, overwrite)
    if type(payload) ~= "table" or type(payload.data) ~= "table" then return false end
    if not ValidData(payload.data) then return false end
    local wanted = (customName and customName ~= "") and customName or payload.name
    -- Trimmed to match ns.ProfileExists, which decides whether the dialog offers Replace.
    wanted = type(wanted) == "string" and wanted:match("^%s*(.-)%s*$") or ""
    if wanted == "" then wanted = "Imported Profile" end
    if overwrite and wanted == "Default" then overwrite = false end
    local name = overwrite and wanted or FreeProfileName(wanted)
    local tr = ns.EnsureProfile and ns.EnsureProfile(name)
    if not tr then return false end

    if overwrite then
        -- The loop below only writes sections the pack carries. Settings have their own tick.
        for i = 1, #SECTIONS do tr[SECTIONS[i].field] = nil end
    end

    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local incoming = payload.data[sec.field]
        if type(incoming) == "table" then
            tr[sec.field] = FilterToSpecs(sec.field, incoming, wantSpecs)
        end
    end

    if wantSettings and type(payload.data.settings) == "table" then
        ApplySettings(tr, payload.data.settings)
    end
    if wantSettings and ns.ImportModuleSettings then
        ns.ImportModuleSettings(ns.ProfileRoot(name), payload.data.modules)
    end
    if type(payload.data.leadTime) == "number" then tr.leadTime = payload.data.leadTime end
    if type(payload.data.voiceNone) == "string" and payload.data.voiceNone ~= "" then
        tr.voiceNone = payload.data.voiceNone
    end

    tr.importedPack = {
        name = tostring(payload.name or "a pack"),
        author = tostring(payload.author or "its curator"),
        licensed = payload.licensed or nil,
    }
    -- Always a fresh profile, so the source is trusted (see ApplyProfiles).
    tr.bindingsBySpec = payload.data.bindingsBySpec ~= false

    if ns.SwitchProfile then ns.SwitchProfile(name) end
    ns.RefreshRuntime()
    return true, name
end

-------------------------------------------------------------------------------
--  The two modals. Both are the house modal shell with a multiline box; the
--  difference is direction. Neither touches settings until Apply.
-------------------------------------------------------------------------------
-- Promoted to ns: the Custom Reminders tab's note box is the same widget.
function ns.MakeMultilineBox(panel, topOffset, height)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, topOffset)
    scroll:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, topOffset)
    scroll:SetHeight(height)
    ns.Solid(scroll, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(scroll)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(1)
    -- A multiline edit box sizes to its content, so an empty one is 0px tall and unclickable.
    box:SetHeight(height)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(self, w) box:SetWidth(w) end)

    -- Clicking anywhere in the field focuses the text, not just the exact glyph run.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    return box
end

-- A pack string has no spaces for word-wrap, so breaks are inserted, measured against the
-- real font (a guessed character count ran past the edge). DecodePack strips whitespace.
-- The gauge is parked off-screen, not hidden: a hidden FontString's GetStringWidth() is 0.
local wrapGauge
local function MeasureWidth(str)
    if not wrapGauge then
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(1, 1)
        host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
        wrapGauge = host:CreateFontString(nil, "ARTWORK")
        wrapGauge:SetFontObject("GameFontHighlightSmall")
        wrapGauge:SetPoint("TOPLEFT")
        host:Show()
    end
    wrapGauge:SetText(str)
    return wrapGauge:GetStringWidth()
end

-- How many characters of str, starting at "from", fit within maxWidth.
local function FitCount(str, from, maxWidth)
    local n = #str
    local lo, hi = 0, 1
    while from + hi - 1 <= n and MeasureWidth(str:sub(from, from + hi - 1)) <= maxWidth do
        lo = hi
        hi = hi * 2
    end
    hi = math.min(hi, n - from + 1)
    while lo < hi do
        local mid = lo + math.ceil((hi - lo) / 2)
        if MeasureWidth(str:sub(from, from + mid - 1)) <= maxWidth then
            lo = mid
        else
            hi = mid - 1
        end
    end
    -- At least one, or a too-narrow target loops forever.
    return math.max(lo, 1)
end

-- For when the width is unreadable or the gauge measures a non-empty string as zero.
local function FallbackWrap(str)
    local lines = {}
    for i = 1, #str, 50 do lines[#lines + 1] = str:sub(i, i + 49) end
    return table.concat(lines, "\n")
end

local function WrapForDisplay(str, maxWidth)
    if #str == 0 then return str end
    if not maxWidth or maxWidth <= 0 then return FallbackWrap(str) end
    local full = MeasureWidth(str)
    if full == 0 then return FallbackWrap(str) end
    if full <= maxWidth then return str end
    local lines, i, n = {}, 1, #str
    while i <= n do
        local count = FitCount(str, i, maxWidth)
        lines[#lines + 1] = str:sub(i, i + count - 1)
        i = i + count
    end
    return table.concat(lines, "\n")
end
-- The Profiles page's export shows its string the same way.
ns.WrapForDisplay = WrapForDisplay

local function MakeToggleRow(parent, w, h, frameLevel, get, set, toggleW, toggleH)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, h)
    if frameLevel then row:SetFrameLevel(frameLevel) end
    row.toggle = ns.UI.BuildToggleControl(row, row:GetFrameLevel() + 1, get, set,
        toggleW, toggleH)
    row.toggle:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label = ns.Font(row, 12, nil)
    row.label:SetPoint("LEFT", row.toggle, "RIGHT", 8, 0)
    return row
end

-- Spec rows read "Protection (Tank)"; naming the class left Arms and Fury identical.
-- GetSpecializationInfoByID returns (id, name, description, icon, role, primaryStat, className).
local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ROLE_SORT = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local function SpecInfo(specKey)
    local id = tonumber(specKey)
    if not (id and GetSpecializationInfoByID) then return nil, nil, nil end
    local ok, _, name, _, _, role, _, className = pcall(GetSpecializationInfoByID, id)
    if not ok then return nil, nil, nil end
    return name, className, role
end
-- classID doubles as the canonical class order.
local classLookup
local function ClassInfo(className)
    if not classLookup then
        classLookup = {}
        if GetNumClasses and GetClassInfo then
            for i = 1, GetNumClasses() do
                local displayName, token = GetClassInfo(i)
                if displayName and token then
                    classLookup[displayName] = { token = token, order = i }
                end
            end
        end
    end
    return className and classLookup[className]
end
local function SortSpecs(specs)
    for i = 1, #specs do
        specs[i].specName, specs[i].className, specs[i].role = SpecInfo(specs[i].key)
    end
    table.sort(specs, function(a, b)
        local ca, cb = ClassInfo(a.className), ClassInfo(b.className)
        local oa, ob = ca and ca.order or 99, cb and cb.order or 99
        if oa ~= ob then return oa < ob end
        local ra, rb = ROLE_SORT[a.role] or 9, ROLE_SORT[b.role] or 9
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return specs
end
-- Spec names repeat across classes (Protection, Frost, Holy...), so the class is the color.
local function PaintSpecLabel(label, spec)
    if spec.specName and spec.role then
        label:SetText(("%s (%s)"):format(spec.specName, ROLE_LABEL[spec.role] or spec.role))
    else
        label:SetText(spec.name)
    end
    local classColors = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
    local ci = spec.className and ClassInfo(spec.className)
    local color = (ci and classColors and classColors[ci.token]) or ns.THEME.fg
    label:SetTextColor(color.r, color.g, color.b, 1)
end

-- Built once: ns.MakeModal never releases a panel, so rebuilding per open stacked copies.
local packExport, packImport

function ns.ShowPackExport()
    if packExport then
        packExport.Regenerate()
        packExport.dimmer:Show()
        return
    end
    -- A floor; Regenerate grows the panel. Lower, the "every profile" tick landed inside
    -- the EditBox, which swallowed its clicks.
    local MIN_HEIGHT = 392
    local dimmer, panel = ns.MakeModal(560, MIN_HEIGHT, "packExport")
    local title = ns.Font(panel, 14, "OUTLINE")
    title:SetPoint("TOP", panel, "TOP", 0, -14)
    title:SetText("Share your Profile")

    local nameBox = CreateFrame("EditBox", nil, panel)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("GameFontHighlight")
    nameBox:SetSize(300, 22)
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    nameBox:SetText("My Reminder Pack")
    nameBox:SetTextColor(ns.THEME.accent.r, ns.THEME.accent.g, ns.THEME.accent.b, 1)
    ns.Solid(nameBox, "BACKGROUND", ns.THEME.line, 1):SetAllPoints()
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- A bare EditBox (no template) has no click-to-focus.
    nameBox:EnableMouse(true)
    nameBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
    hint:SetText("pack name, shown on import")

    local box = ns.MakeMultilineBox(panel, -78, 180)
    -- Left/right-anchored below: a single centered point let a long spec list run off the panel.
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetWordWrap(true)
    status:SetJustifyH("CENTER")

    local closeBtn

    local function Regenerate()
        local str, err = ns.ExportPack(nameBox:GetText(), UnitName and UnitName("player"))
        if str then
            -- Not box:GetWidth(): that comes from OnSizeChanged, a frame late on first open.
            local maxWidth = box:GetParent():GetWidth()
            box:SetText(WrapForDisplay(str, maxWidth))
            local names
            local specs = ns.PackSpecs({ data = { presets = ns.DB().presets,
                activePreset = ns.DB().activePreset, bossLists = ns.DB().bossLists,
                abilityBindings = ns.DB().abilityBindings } })
            for i = 1, #specs do
                names = names and (names .. ", " .. specs[i].name) or specs[i].name
            end
            status:SetText(("%d characters%s. Click the text, then Ctrl+A Ctrl+C."):format(
                #str, names and (" covering " .. names) or ""))
        else
            box:SetText("")
            status:SetText("|cffff6060" .. tostring(err) .. "|r")
        end
        -- 78+180 is the box's top offset and height; then the status/close stack.
        if closeBtn then
            local needed = 78 + 180 + 14 + status:GetHeight() + 10 + closeBtn:GetHeight() + 16
            panel:SetHeight(math.max(MIN_HEIGHT, needed))
        end
    end

    status:SetPoint("TOP", box:GetParent(), "BOTTOM", 0, -14)
    status:SetPoint("LEFT", panel, "LEFT", 14, 0)
    status:SetPoint("RIGHT", panel, "RIGHT", -14, 0)

    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(_, user) if user then Regenerate() end end)
    -- Not per keystroke: each pass serializes, compresses and re-wraps the whole profile.
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEditFocusLost", function() Regenerate() end)

    closeBtn = ns.Button(panel, "Close", 110, 26, function() dimmer:Hide() end)
    closeBtn:SetPoint("TOP", status, "BOTTOM", 0, -10)

    packExport = { dimmer = dimmer, Regenerate = Regenerate }
    Regenerate()
    dimmer:Show()
end

-- The diagnostic trace as copyable text; an addon cannot write a file.
local diagExport

function ns.ShowDiagExport(text)
    if not diagExport then
        local dimmer, panel = ns.MakeModal(620, 420, "diagExport")
        local title = ns.Font(panel, 14, "OUTLINE")
        title:SetPoint("TOP", panel, "TOP", 0, -14)
        title:SetText("Diagnostic Trace")

        local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetText("Click the text, then Ctrl+A Ctrl+C, and paste it to whoever asked.")

        local box = ns.MakeMultilineBox(panel, -56, 300)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnTextChanged", function(self, user)
            if user then self:SetText(diagExport.text or "") end
        end)

        ns.Button(panel, "Close", 110, 26, function() dimmer:Hide() end)
            :SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
        diagExport = { dimmer = dimmer, box = box }
    end
    diagExport.text = text or ""
    diagExport.box:SetText(diagExport.text)
    diagExport.dimmer:Show()
    diagExport.box:SetFocus()
end

-- Separate from Import, which always lands a new profile and never touches existing ones.
local profileMerge

function ns.ShowProfileMergeDialog()
    if profileMerge then
        profileMerge.box:SetText("")
        profileMerge.Revalidate()
        profileMerge.dimmer:Show()
        profileMerge.box:SetFocus()
        return
    end
    local BASE_HEIGHT = 560
    local dimmer, panel = ns.MakeModal(620, BASE_HEIGHT, "profileMerge")
    local title = ns.Font(panel, 14, "OUTLINE")
    title:SetPoint("TOP", panel, "TOP", 0, -14)
    title:SetText("Merge a Profile Into Yours")

    local box = ns.MakeMultilineBox(panel, -40, 110)
    local preview = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -158)
    preview:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -158)
    preview:SetJustifyH("LEFT")
    preview:SetText("Paste their profile string above.")

    local decoded, sourceName, targetName
    local wantSettings, wantExtras = false, false
    local specWanted, specSeeded = {}, false
    local mergeBtn
    local rowsHost = CreateFrame("Frame", nil, panel)
    rowsHost:SetAllPoints()
    -- Reused: Rebuild runs per keystroke, and frames are never given back.
    local specRows, rowKeys = {}, {}
    local selectAllBtn, deselectAllBtn

    local function SetAllWanted(on)
        for i = 1, #specRows do
            if specRows[i]:IsShown() then
                specWanted[rowKeys[i]] = on or nil
                specRows[i].toggle._refreshValue()
            end
        end
    end

    local function ClearRows()
        ns.UI.BeginReusableRows(rowsHost)
        for i = 1, #specRows do specRows[i]:Hide() end
        if selectAllBtn then selectAllBtn:Hide(); deselectAllBtn:Hide() end
    end

    local function SourceData()
        if not decoded then return nil end
        if type(decoded.profiles) == "table" then
            return sourceName and decoded.profiles[sourceName]
        end
        return decoded.data
    end

    local function Names()
        local out = {}
        if decoded and type(decoded.profiles) == "table" then
            for name in pairs(decoded.profiles) do
                if name ~= "Default" then out[#out + 1] = name end
            end
            table.sort(out, function(a, b) return a:lower() < b:lower() end)
        end
        return out
    end

    local Rebuild
    local function Picker(y, label, values, order, get, set)
        local row = ns.UI.Keep(rowsHost, "picker", function(host)
            local r = CreateFrame("Frame", nil, host)
            r.lbl = ns.Font(r, 12, nil, ns.THEME.muted)
            r.lbl:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
            r.dd = ns.UI.BuildDropdownControl(r, 280, nil, values, order, get, set)
            r.dd:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -20)
            return r
        end)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        row:SetSize(280, 44)
        row:SetFrameLevel(panel:GetFrameLevel() + 10)
        row.lbl:SetText(label)
        local dd = row.dd
        dd._values, dd._order, dd._get, dd._set = values, order, get, set
        dd:SetFrameLevel(row:GetFrameLevel() + 2)
        dd._refreshLabel()
        return row
    end

    Rebuild = function()
        ClearRows()
        if not decoded then
            panel:SetHeight(BASE_HEIGHT)
            specWanted, specSeeded = {}, false
            return
        end
        local y = -192

        local sources = Names()
        if #sources > 0 then
            if not sourceName or not decoded.profiles[sourceName] then
                sourceName = sources[1]
                specWanted, specSeeded = {}, false
            end
            local values = {}
            for _, n in ipairs(sources) do values[n] = n end
            Picker(y, "Take which of their profiles", values, sources,
                function() return sourceName end,
                function(v) sourceName = v; specWanted, specSeeded = {}, false; Rebuild() end)
            y = y - 50
        else
            sourceName = nil
        end

        local mine = ns.ListProfiles()
        if not targetName or not ns.ProfileExists(targetName) then
            targetName = ns.ActiveProfileName()
        end
        local values = {}
        for _, n in ipairs(mine) do values[n] = n end
        Picker(y, "Merge it into", values, mine,
            function() return targetName end,
            function(v) targetName = v end)
        y = y - 54

        local data = SourceData()
        local specs = data and SortSpecs(ns.PackSpecs({ data = data })) or {}
        -- Seeded once per string, so Deselect All survives the next keystroke.
        if not specSeeded then
            for _, s in ipairs(specs) do specWanted[s.key] = true end
            specSeeded = true
        end
        local head = ns.UI.Keep(rowsHost, "head", function(host)
            local f = CreateFrame("Frame", nil, host)
            f.text = ns.Font(f, 12, nil, ns.THEME.muted)
            f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
            return f
        end)
        head:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        head:SetSize(560, 16)
        head.text:SetText(#specs > 0 and "Take which specs" or "Their string names no specs")

        if not selectAllBtn then
            selectAllBtn = ns.Button(panel, "Select All", 84, 20,
                function() SetAllWanted(true) end)
            deselectAllBtn = ns.Button(panel, "Deselect All", 96, 20,
                function() SetAllWanted(false) end)
            selectAllBtn:SetPoint("TOPRIGHT", deselectAllBtn, "TOPLEFT", -6, 0)
        end
        deselectAllBtn:ClearAllPoints()
        deselectAllBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, y + 2)
        selectAllBtn:SetShown(#specs > 0)
        deselectAllBtn:SetShown(#specs > 0)
        y = y - 20

        local COLS, COL_W, ROW_H = 3, 188, 22
        for i, s in ipairs(specs) do
            local col, line = (i - 1) % COLS, math.floor((i - 1) / COLS)
            rowKeys[i] = s.key
            local row = specRows[i]
            if not row then
                row = MakeToggleRow(panel, COL_W, ROW_H, panel:GetFrameLevel() + 10,
                    function() return specWanted[rowKeys[i]] end,
                    function(v) specWanted[rowKeys[i]] = v or nil end, 28, 14)
                specRows[i] = row
            end
            row.toggle._refreshValue()
            PaintSpecLabel(row.label, s)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + col * COL_W, y - line * ROW_H)
            row:Show()
        end
        y = y - math.max(1, math.ceil(#specs / COLS)) * ROW_H - 8

        local settings = ns.UI.Keep(rowsHost, "settings", function(host)
            local r = MakeToggleRow(host, 460, 22, nil,
                function() return wantSettings end,
                function(v) wantSettings = v end)
            r.label:SetText("Also take their display, sound and behaviour settings")
            return r
        end)
        settings:SetFrameLevel(panel:GetFrameLevel() + 10)
        settings.toggle._refreshValue()
        settings:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        y = y - 24

        local extras = ns.UI.Keep(rowsHost, "extras", function(host)
            local r = MakeToggleRow(host, 460, 22, nil,
                function() return wantExtras end,
                function(v) wantExtras = v end)
            r.label:SetText("Also take their raid reminders and callout lines")
            ns.Tooltip(r, "Raid reminders and callout lines",
                "Neither records a spec, so a spec handover leaves them alone. Tick this only "
                .. "when you want theirs in place of yours.")
            return r
        end)
        extras:SetFrameLevel(panel:GetFrameLevel() + 10)
        extras.toggle._refreshValue()
        extras:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)

        -- Grows with the grid: 40 specs ran out through a fixed-height panel.
        panel:SetHeight(math.max(BASE_HEIGHT, -y + 78))
    end

    local function Revalidate()
        decoded = nil
        local text = box:GetText()
        if text and text:gsub("%s+", "") ~= "" then
            local payload, describe = ns.DecodePack(text)
            if payload then
                decoded = payload
                preview:SetText(describe or "Ready to merge.")
            else
                preview:SetText("|cffff6060" .. tostring(describe
                    or "That string could not be read.") .. "|r")
            end
        else
            preview:SetText("Paste their profile string above.")
        end
        Rebuild()
        if mergeBtn then mergeBtn:SetAlpha(decoded and 1 or 0.4) end
    end
    box:SetScript("OnTextChanged", function() Revalidate() end)

    mergeBtn = ns.Button(panel, "Merge", 130, 26, function()
        if not decoded then return end
        local ok, a, b = ns.MergeProfileFromPack(decoded, sourceName, targetName,
            { settings = wantSettings, extras = wantExtras, specs = specWanted })
        if not ok then
            preview:SetText("|cffff6060" .. tostring(a) .. "|r")
            return
        end
        ns.Print(("merged into " .. ns.Color("accent", "%s") .. ": %d spec sections and %d reminders. Specs you "
            .. "did not tick are exactly as they were."):format(
            tostring(targetName), a or 0, b or 0))
        dimmer:Hide()
        if ns.UI and ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
    end)
    mergeBtn:SetPoint("BOTTOM", panel, "BOTTOM", -70, 14)
    ns.Button(panel, "Cancel", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 70, 14)

    profileMerge = { dimmer = dimmer, box = box, Revalidate = Revalidate }
    Revalidate()
    dimmer:Show()
    box:SetFocus()
end

-- text: a pack string to start with, as the Profiles page's Import hands one over.
function ns.ShowPackImport(text)
    if packImport then
        packImport.box:SetText(text or "")
        packImport.Revalidate()
        packImport.dimmer:Show()
        packImport.box:SetFocus()
        return
    end
    local dimmer, panel = ns.MakeModal(700, 470, "packImport")
    local title = ns.Font(panel, 14, "OUTLINE")
    title:SetPoint("TOP", panel, "TOP", 0, -14)
    title:SetText("Import Profile")

    local box = ns.MakeMultilineBox(panel, -40, 150)
    local preview = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -200)
    preview:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -200)
    preview:SetJustifyH("LEFT")
    preview:SetText("Paste a pack string above.")

    local decoded
    local applyBtn

    local specRows, specWanted = {}, {}
    local settingsWanted, settingsBtn = true, nil
    local bindWanted, bindBtn = true, nil
    local accountWanted, accountBtn = true, nil
    local overwriteWanted, overwriteBtn = false, nil
    -- Below the grid at its left edge; the last spec row can sit in any column.
    local gridAnchor
    local nameLabel, nameBox
    local selectAllBtn, deselectAllBtn
    local function SetAllWanted(on)
        for i = 1, #specRows do
            local row = specRows[i]
            if row:IsShown() and row.specKey then
                specWanted[row.specKey] = on or nil
                if row.Repaint then row.Repaint() end
            end
        end
    end
    -- Under the preview, which grows a line per profile in the pack.
    local specHead = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    specHead:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -12)
    specHead:SetJustifyH("LEFT")
    specHead:Hide()

    -- The dialog is cached, so a Replace ticked for one pack would stay armed for the next.
    local function ClearOverwrite()
        overwriteWanted = false
        if overwriteBtn then
            if overwriteBtn.toggle and overwriteBtn.toggle._refreshValue then
                overwriteBtn.toggle._refreshValue()
            end
            overwriteBtn:Hide()
        end
    end

    local function BuildSpecRows(payload)
        ClearOverwrite()
        for i = 1, #specRows do specRows[i]:Hide() end
        if settingsBtn then settingsBtn:Hide() end
        if bindBtn then bindBtn:Hide() end
        if selectAllBtn then selectAllBtn:Hide() end
        if deselectAllBtn then deselectAllBtn:Hide() end
        wipe(specWanted)
        -- Rows are profiles for a whole-file pack, specs otherwise.
        local multi = payload and type(payload.profiles) == "table"
        local specs = {}
        if multi then
            local names = {}
            for name in pairs(payload.profiles) do
                if name ~= "Default" then names[#names + 1] = name end
            end
            table.sort(names, function(a, b) return a:lower() < b:lower() end)
            for i = 1, #names do specs[i] = { key = names[i], name = names[i] } end
        elseif payload then
            specs = SortSpecs(ns.PackSpecs(payload))
        end
        if #specs == 0 then
            specHead:Hide()
            -- Blanked, not just hidden: Finish reads this box regardless.
            if nameBox then nameBox:SetText(""); nameLabel:Hide(); nameBox:Hide() end
            if accountBtn then accountBtn:Hide() end
            if bindBtn then bindBtn:Hide() end
            if settingsBtn then settingsBtn:Hide() end
            return
        end
        specHead:SetText(multi and "Bring in which profiles:" or "Bring in which of these:")
        specHead:Show()
        -- A grid: 40 stacked spec rows ran off the bottom of the screen.
        local GRID_COLS, COL_W, ROW_H = 3, 220, 28
        for i = 1, #specs do
            local spec = specs[i]
            specWanted[spec.key] = true
            local btn = specRows[i]
            if not btn then
                btn = CreateFrame("Frame", nil, panel)
                btn:SetSize(COL_W, 22)
                -- Above the paste box, an EditBox that grows over these rows and takes their clicks.
                btn:SetFrameLevel(panel:GetFrameLevel() + 10)
                btn.label = ns.Font(btn, 12, nil)
                -- Reads btn.specKey at click time, so a reused row never acts on an earlier paste.
                local tgl, _, repaint = ns.UI.BuildToggleControl(btn, btn:GetFrameLevel() + 1,
                    function() return specWanted[btn.specKey] end,
                    function(v) specWanted[btn.specKey] = v or nil end, 28, 14)
                btn.toggle, btn.Repaint = tgl, repaint
                tgl:SetPoint("LEFT", btn, "LEFT", 0, 0)
                btn.label:SetPoint("LEFT", tgl, "RIGHT", 6, 0)
                specRows[i] = btn
            end
            local col = (i - 1) % GRID_COLS
            local row = math.floor((i - 1) / GRID_COLS)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", specHead, "BOTTOMLEFT",
                6 + col * COL_W, -6 - row * ROW_H)
            btn.specKey = spec.key
            btn.Repaint()
            PaintSpecLabel(btn.label, spec)
            btn:Show()
        end

        if not gridAnchor then
            gridAnchor = CreateFrame("Frame", nil, panel)
            gridAnchor:SetSize(1, 1)
        end
        gridAnchor:ClearAllPoints()
        gridAnchor:SetPoint("TOPLEFT", specHead, "BOTTOMLEFT",
            6, -6 - math.ceil(#specs / GRID_COLS) * ROW_H)

        -- Offered only when the pack has them: an older string carries none.
        if type(payload.data) == "table" and type(payload.data.settings) == "table" then
            if not settingsBtn then
                settingsBtn = MakeToggleRow(panel, 320, 22, panel:GetFrameLevel() + 10,
                    function() return settingsWanted end,
                    function(v) settingsWanted = v end)
                settingsBtn.label:SetText("Their display, sound and behaviour settings")
            end
            settingsBtn:ClearAllPoints()
            settingsBtn:SetPoint("TOPLEFT", gridAnchor or specHead, "BOTTOMLEFT",
                gridAnchor and 0 or 6, -10)
            settingsBtn:Show()
        elseif settingsBtn then
            settingsBtn:Hide()
        end

        -- No spec remap option: it let a DPS spec's choices overwrite a tank spec's in one pack.

        if multi then
            if not bindBtn then
                bindBtn = MakeToggleRow(panel, 380, 22, panel:GetFrameLevel() + 10,
                    function() return bindWanted end,
                    function(v) bindWanted = v end)
                bindBtn.label:SetText("Use each on the character whose spec it covers")
            end
            bindBtn:ClearAllPoints()
            bindBtn:SetPoint("TOPLEFT", (settingsBtn and settingsBtn:IsShown())
                and settingsBtn or (gridAnchor or specHead), "BOTTOMLEFT",
                (settingsBtn and settingsBtn:IsShown()) and 0
                    or (gridAnchor and 0 or 6), -6)
            bindBtn:Show()
        elseif bindBtn then
            bindBtn:Hide()
        end

        -- Profile choice is per character, so otherwise every alt had to be switched by hand.
        if not multi then
            if not accountBtn then
                accountBtn = MakeToggleRow(panel, 420, 22, panel:GetFrameLevel() + 10,
                    function() return accountWanted end,
                    function(v) accountWanted = v end)
            end
            -- Only characters that logged in with the addon are counted; the account default covers the rest.
            local known = ns.KnownCharacters and #ns.KnownCharacters() or 0
            accountBtn.label:SetText(known > 1
                and ("Use it on all %d characters on this account, and new ones"):format(known)
                or "Use it on every character on this account, and new ones")
            accountBtn:ClearAllPoints()
            accountBtn:SetPoint("TOPLEFT", (settingsBtn and settingsBtn:IsShown())
                and settingsBtn or (gridAnchor or specHead), "BOTTOMLEFT",
                (settingsBtn and settingsBtn:IsShown()) and 0 or (gridAnchor and 0 or 6), -6)
            accountBtn:Show()
        elseif accountBtn then
            accountBtn:Hide()
        end

        if not multi then
            if not nameBox then
                nameLabel = ns.Font(panel, 12, nil)
                nameLabel:SetText("Save as:")
                nameBox = CreateFrame("EditBox", nil, panel)
                nameBox:SetAutoFocus(false)
                nameBox:SetFontObject("GameFontHighlight")
                nameBox:SetSize(260, 22)
                nameBox:SetTextColor(ns.THEME.accent.r, ns.THEME.accent.g, ns.THEME.accent.b, 1)
                ns.Solid(nameBox, "BACKGROUND", ns.THEME.line, 1):SetAllPoints()
                -- Above the growing paste box, which otherwise takes its clicks.
                nameBox:SetFrameLevel(panel:GetFrameLevel() + 10)
                nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                -- A bare EditBox (no template) has no click-to-focus.
                nameBox:EnableMouse(true)
                nameBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
            end
            local anchorTo = (accountBtn and accountBtn:IsShown() and accountBtn)
                or (bindBtn and bindBtn:IsShown() and bindBtn)
                or (settingsBtn and settingsBtn:IsShown() and settingsBtn)
                or gridAnchor or specHead
            nameLabel:ClearAllPoints()
            nameLabel:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT",
                anchorTo == specHead and 6 or 0, -16)
            nameBox:ClearAllPoints()
            nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
            nameBox:SetText((payload.name and payload.name ~= "") and payload.name
                or "Imported Profile")
            nameLabel:Show()
            nameBox:Show()

            -- Offered only when the name is taken, so a tuned profile is never silently replaced.
            if not overwriteBtn then
                overwriteBtn = MakeToggleRow(panel, 420, 22, panel:GetFrameLevel() + 10,
                    function() return overwriteWanted end,
                    function(v) overwriteWanted = v end)
            end
            local function RefreshOverwrite()
                local typed = nameBox:GetText()
                if ns.ProfileExists and ns.ProfileExists(typed) then
                    overwriteBtn.label:SetText(
                        ("Replace the existing profile '%s' instead of making a copy"):format(typed))
                    overwriteBtn:Show()
                else
                    ClearOverwrite()
                end
            end
            overwriteBtn:ClearAllPoints()
            overwriteBtn:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -12)
            -- Rebound every refresh: the dialog is reused and the closure would go stale.
            nameBox:SetScript("OnTextChanged", function() RefreshOverwrite() end)
            RefreshOverwrite()
        elseif nameBox then
            nameLabel:Hide()
            nameBox:Hide()
            ClearOverwrite()
        end

        if not selectAllBtn then
            selectAllBtn = ns.Button(panel, "Select All", 84, 22, function() SetAllWanted(true) end)
            deselectAllBtn = ns.Button(panel, "Deselect All", 96, 22, function() SetAllWanted(false) end)
        end
        selectAllBtn:ClearAllPoints()
        if nameBox and nameBox:IsShown() then
            selectAllBtn:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
        else
            local anchorTo = (bindBtn and bindBtn:IsShown() and bindBtn)
                or (settingsBtn and settingsBtn:IsShown() and settingsBtn)
                or gridAnchor or specHead
            selectAllBtn:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT",
                anchorTo == specHead and 6 or 0, -16)
        end
        deselectAllBtn:ClearAllPoints()
        deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 6, 0)
        selectAllBtn:Show()
        deselectAllBtn:Show()

        local last = (overwriteBtn and overwriteBtn:IsShown() and overwriteBtn)
            or (nameBox and nameBox:IsShown() and nameLabel)
            or (bindBtn and bindBtn:IsShown() and bindBtn)
            or (settingsBtn and settingsBtn:IsShown() and settingsBtn)
            or specRows[#specs]
        if last then
            local used = panel:GetTop() - last:GetBottom()
            panel:SetHeight(math.max(470, used + 74))
        end
    end

    local function Revalidate()
        local payload, descOrErr = ns.DecodePack(box:GetText())
        decoded = payload
        if payload then
            preview:SetText(descOrErr)
        else
            preview:SetText("|cffff6060" .. tostring(descOrErr) .. "|r")
        end
        BuildSpecRows(payload)
        local on = payload ~= nil
        for _, b in ipairs({ applyBtn }) do
            if b then
                if on then b:Enable(); b:SetAlpha(1) else b:Disable(); b:SetAlpha(0.35) end
            end
        end
    end
    box:SetScript("OnTextChanged", function(_, user) if user then Revalidate() end end)

    local function Finish()
        if not decoded then return end
        if type(decoded.profiles) == "table" then
            local wantP, anyP = {}, false
            for name in pairs(decoded.profiles) do
                if specWanted[name] then wantP[name] = true; anyP = true end
            end
            if not anyP then
                preview:SetText("|cffff6060Pick at least one profile to bring in.|r")
                return
            end
            local ok, landed = ns.ApplyProfiles(decoded, wantP, settingsWanted, bindWanted)
            if ok then
                if bindWanted then ns.AutoSpecProfile(true) end
                ns.Print(("%d profile%s imported.%s"):format(landed,
                    landed == 1 and "" or "s",
                    bindWanted and " Each character will load the one for its spec."
                        or " Pick one under Active Profile."))
                if bindWanted and ns.ApplySpecProfile and ns.CurrentSpec then
                    ns.ApplySpecProfile((ns.CurrentSpec()))
                end
                dimmer:Hide()
                local EUIm = ns.UI
                if EUIm and EUIm.RefreshPage then EUIm:RefreshPage(true) end
            else
                preview:SetText("|cffff6060The pack could not be applied.|r")
            end
            return
        end

        -- Nil when every spec is ticked, so the import matches the curator exactly.
        local want, all, any = nil, true, false
        local specs = ns.PackSpecs(decoded)
        for i = 1, #specs do
            if specWanted[specs[i].key] then any = true else all = false end
        end
        if #specs > 0 and not any then
            preview:SetText("|cffff6060Pick at least one to bring in.|r")
            return
        end
        if #specs > 0 and not all then want = specWanted end
        local ok, newName = ns.ImportPackAsProfile(decoded, want, settingsWanted,
            nameBox and nameBox:GetText(), overwriteWanted)
        if ok then
            -- After the import: SetAccountProfile refuses a name that is not a profile yet,
            -- and the landed name may differ after a collision.
            local accountSet, autoOff = false, false
            if accountWanted and ns.SetAccountProfile then
                accountSet, autoOff = ns.SetAccountProfile(newName)
            end
            if accountSet then
                local known = ns.KnownCharacters and #ns.KnownCharacters() or 0
                ns.Print(("imported as the profile '%s'. %s on this account use%s it now, and "
                    .. "one logged into later will too. Switching a single character "
                    .. "afterwards moves only that one.%s"):format(
                    tostring(newName),
                    known == 1 and "The one character" or ("All " .. known .. " characters"),
                    known == 1 and "s" or "",
                    autoOff and " Per-spec profile switching is off while they share one "
                        .. "profile; your spec choices are kept if you switch it back on." or ""))
            else
                if overwriteWanted then
                    ns.Print(("replaced the profile '%s' with this pack, and switched to it."):format(
                        tostring(newName)))
                else
                    ns.Print(("imported as the profile '%s', and switched to it. Your own profile "
                        .. "is untouched -- switch back to it any time."):format(tostring(newName)))
                end
            end
            dimmer:Hide()
            local EUI = ns.UI
            if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
        else
            preview:SetText("|cffff6060The pack could not be applied.|r")
        end
    end

    applyBtn = ns.Button(panel, "Import", 130, 26, function() Finish() end)
    applyBtn:SetPoint("BOTTOM", panel, "BOTTOM", -70, 14)
    ns.Button(panel, "Cancel", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 70, 14)

    packImport = { dimmer = dimmer, box = box, Revalidate = Revalidate }
    if text then box:SetText(text) end
    Revalidate()
    dimmer:Show()
    box:SetFocus()
end
