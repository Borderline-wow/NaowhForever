-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Packs.lua -- shareable Reminder Packs.
--
--  A pack is a curator's judgment as data: priority lists per spec, per-boss
--  orders, callout lines, tank-buster marks, mutes, and authored reminders,
--  in one paste-able string. The wire format is LibSerialize + LibDeflate + print
--  encoding under a distinct
--  prefix, so a pack can never be mistaken for a profile string or vice
--  versa.
--
--  Import rules that make this fit to charge money for:
--    * PREVIEW FIRST. A string decodes to a description -- name, author,
--      version, what is inside, counts -- before anything applies.
--    * NEVER PARTIAL. The payload is validated and staged whole; a bad
--      string is refused outright rather than half-applied.
--    * NEVER OVERWRITES. An import lands in a NEW profile and switches to it,
--      so the importer's own profile is untouched and going back to it restores
--      everything they had. There is no merge-or-replace to get wrong, and no
--      way for a pack to take a preset, a spec or a profile with it.
--
--  There is deliberately no license check, expiry, or key. A string is text
--  and always will be; what a subscription buys is the next version. The
--  version field on the preview is what makes that model legible.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

local PREFIX = "NSRPACK2:"
local PACK_FORMAT = 1

-- Sections a pack may carry, in display order. Keyed by the profile field;
-- label is what the preview calls it; count says how its size is measured.
-- customReminders, not `reminders`. The latter is a storage layer nothing ever writes to,
-- so the section it named could only ever be empty: a curator exported a pack and lost
-- every custom reminder they had authored, silently, which is the one part of their work
-- this file exists to carry.
--
-- activePreset rides along with presets because a pack that ships three lists and cannot
-- say which is live lands the importer on whichever key next() happens to return, not the
-- one the curator meant. Nothing breaks without it -- ActivePresetKey self-heals a stale
-- pointer -- but the choice does not survive the trip.
local SECTIONS = {
    { field = "presets",         label = "spec priority lists",  count = "nested" },
    { field = "activePreset",    label = "active preset choice", count = "keys" },
    { field = "bossLists",       label = "per-boss orders",      count = "keys" },
    { field = "callouts",        label = "callout lines",        count = "keys" },
    { field = "customReminders", label = "custom reminders",     count = "nested" },
    { field = "abilityBindings", label = "ability on/off",       count = "nested" },
    { field = "audioOff",        label = "audio switches",       count = "keys" },
    { field = "raidReminders",   label = "raid reminders",       count = "nested" },
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

-- LibSerialize's Deserialize returns (ok, value); the adapter re-raises the failure so the
-- existing pcall call sites keep their one contract: Serialize/Deserialize either answer
-- or throw.
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

-- Deep copy, so a pack never aliases live settings tables: an exported pack
-- edited later must not mutate the profile, and an applied pack must not let
-- a second apply see half-changed data.
local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = Copy(val) end
    return out
end

-- One profile's worth of pack data. Split out of ExportPack so a whole-file export can run
-- it over every profile without loading each one in turn: profiles other than the active one
-- are read straight from saved variables and never become the live table.
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
    -- A non-active profile is read straight from saved variables above and never runs the
    -- binding-scope migration, so its abilityBindings can still be pre-migration shape.
    -- Carried across so the landing side knows whether it's actually safe to call this
    -- migrated, instead of just assuming so because it came through this file.
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

function ns.ExportPack(packName, author)
    local Ser, LD = Codec()
    if not Ser then return nil, "The serializer libraries are missing from this build." end

    local db = ns.DB()
    if type(db.importedPack) == "table" then
        return nil, ("This profile contains an imported pack (%s by %s), so it cannot "
            .. "be shared onward. Build your own profile to share one."):format(
            db.importedPack.name, db.importedPack.author)
    end
    local data, any = DataFromProfile(db)
    if not any then return nil, "There is nothing to export yet." end

    local payload = {
        format  = PACK_FORMAT,
        name    = (packName and packName ~= "") and packName or "Reminder Pack",
        author  = (author and author ~= "") and author or (UnitName and UnitName("player")) or "unknown",
        made    = date and date("%Y-%m-%d") or "",
        data    = data,
    }
    local ok, serialized = pcall(Ser.Serialize, payload)
    if not ok then return nil, "The pack could not be serialized." end
    local compressed = LD:CompressDeflate(serialized)
    return PREFIX .. LD:EncodeForPrint(compressed)
end

-- The one call an installer needs, paired with the one call that describes it first.
-- NaowhUI's own installer offers Smart Reminders as a step:
--
--   local SR = _G.NaowhUITankReminder
--   if SR and SR.InstallProfilePack then
--       local opts = { accountProfile = "Naowh" }
--       local text = SR.DescribeProfilePack(str, opts)
--       -- show `text` and get the player's confirmation before this next line runs --
--       -- accountProfile in particular moves every character on the account, and that has
--       -- to be said plainly before it happens, not discovered afterwards.
--       local ok, err = SR.InstallProfilePack(str, opts)
--   end
--
-- Guard on the global: this addon is optional and may not be installed at all. Call it after
-- our ADDON_LOADED -- saved variables do not exist before that, and a profile written into
-- nothing is lost at logout.
--
-- opts, all optional, shared by both calls so the description matches what actually runs:
--   accountProfile  point every character at this profile once the pack has landed. The
--                   name must be one the pack carries, or the call fails and says so.
--   bindSpecs       bind each landed profile to the specs it covers and switch on the
--                   matching, so an alt lands on the right one without being told. Default
--                   true for a whole-file pack.
--   settings        take the curator's display, sound and behaviour settings. Default true,
--                   since an installer offering a UI is asking for exactly that.
--
-- Returns true plus the number of profiles landed, or false and a reason. Never throws: an
-- installer step failing should report, not break the install.
-- What InstallProfilePack is ABOUT to do, in plain language, without doing any of it. Meant
-- for an installer to show before the step runs -- "this will do X" read on a confirmation
-- screen, not discovered afterwards from what changed. Same opts as InstallProfilePack, since
-- the answer depends on them (accountProfile in particular is the one worth confirming: it
-- moves every character on the account, not just the one running the installer).
--
-- Returns text, info: text is a ready-to-show multi-line string (|n between lines, matching
-- DecodePack's own preview); info is the same facts as a plain table, for an installer that
-- wants to build its own layout instead. Neither call mutates anything -- info.accountProfileOK
-- says whether accountProfile names a profile the pack actually carries, checked the same way
-- InstallProfilePack itself would fail if it does not.
function ns.DescribeProfilePack(str, opts)
    opts = type(opts) == "table" and opts or {}
    local payload, err = ns.DecodePack(str)
    if not payload then return nil, nil, err or "the string could not be read" end

    local multi = type(payload.profiles) == "table"
    local wantSettings = opts.settings ~= false
    local wantBind = opts.bindSpecs ~= false

    -- One row per profile the pack will create, named, with the specs it covers -- the same
    -- pairing an import dialog already shows, so a curator checking their own export sees the
    -- identical picture an installer would show a buyer.
    local profiles = {}
    if multi then
        local names = {}
        for name in pairs(payload.profiles) do names[#names + 1] = name end
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
    lines[#lines + 1] = ("|cff0091ed%s|r by %s"):format(
        tostring(payload.name), tostring(payload.author))
    lines[#lines + 1] = ("Will create %d new profile%s:"):format(
        #profiles, #profiles == 1 and "" or "s")
    for i = 1, #profiles do
        local p = profiles[i]
        local specText = #p.specs > 0 and (" -- " .. table.concat(p.specs, ", ")) or ""
        lines[#lines + 1] = ("  |cff0091ed%s|r%s"):format(p.name, specText)
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

function ns.InstallProfilePack(str, opts)
    opts = type(opts) == "table" and opts or {}
    local payload, err = ns.DecodePack(str)
    if not payload then return false, err or "the string could not be read" end

    local settings = opts.settings ~= false
    local ok, landed
    if type(payload.profiles) == "table" then
        local bind = opts.bindSpecs ~= false
        ok, landed = ns.ApplyProfiles(payload, nil, settings, bind)
        if ok and bind then ns.AutoSpecProfile(true) end
    else
        ok, landed = ns.ImportPackAsProfile(payload, nil, settings, nil)
    end
    if not ok then return false, "the pack could not be applied" end

    if opts.accountProfile then
        local set, why = ns.SetAccountProfile(opts.accountProfile)
        if not set then
            return false, ("imported, but %s is not a profile in this pack (%s)"):format(
                tostring(opts.accountProfile), tostring(why))
        end
    end

    if ns.ApplySpecProfile and ns.CurrentSpec then ns.ApplySpecProfile((ns.CurrentSpec())) end
    return true, landed
end

-- Every profile in one string, for a curator who keeps a profile per class rather than one
-- profile holding every spec. Both shapes are legitimate -- a profile accumulates specs, so
-- ten classes fit in one -- but a seller building them separately would otherwise have to
-- hand out ten strings and talk the buyer through ten imports.
--
-- Reads the stored settings of each profile directly; only the active one is ever the live
-- table, and loading each in turn to export it would switch the player around their own
-- characters.
function ns.ExportAllProfiles(packName, author)
    local Ser, LD = Codec()
    if not Ser then return nil, "The serializer libraries are missing from this build." end

    local profiles, count = {}, 0
    local names = ns.ListProfiles and ns.ListProfiles() or {}
    for i = 1, #names do
        local tr = ns.ProfileSettings and ns.ProfileSettings(names[i])
        if tr then
            -- An imported profile is not the exporter's to pass on, the same rule the
            -- single-profile export follows; it is skipped rather than failing the lot.
            if type(tr.importedPack) ~= "table" then
                local data, any = DataFromProfile(tr)
                if any then
                    profiles[names[i]] = data
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil, "None of your profiles have anything in them yet." end

    local payload = {
        format   = PACK_FORMAT,
        name     = (packName and packName ~= "") and packName or "Reminder Pack",
        author   = (author and author ~= "") and author or (UnitName and UnitName("player")) or "unknown",
        made     = date and date("%Y-%m-%d") or "",
        profiles = profiles,
    }
    local ok, serialized = pcall(Ser.Serialize, payload)
    if not ok then return nil, "The pack could not be serialized." end
    local compressed = LD:CompressDeflate(serialized)
    return PREFIX .. LD:EncodeForPrint(compressed)
end

-- Decode and validate; returns the payload plus a human description, or nil
-- and a reason. Applies nothing.
function ns.DecodePack(str)
    local Ser, LD = Codec()
    if not Ser then return nil, "The serializer libraries are missing from this build." end
    if type(str) ~= "string" then return nil, "Nothing to read." end
    str = str:gsub("%s+", "")
    if str == "" then return nil, "Nothing to read." end
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
    local multi = type(payload.profiles) == "table" and next(payload.profiles) ~= nil
    if not multi and type(payload.data) ~= "table" then return nil, "The pack is empty." end

    local parts = {}
    if multi then
        -- Named, with what each carries, so the preview says what is about to land rather
        -- than a count of profiles.
        local names = {}
        for name in pairs(payload.profiles) do names[#names + 1] = name end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        for i = 1, #names do
            local specs = ns.PackSpecs({ data = payload.profiles[names[i]] })
            local specText
            for j = 1, #specs do
                specText = specText and (specText .. ", " .. specs[j].name) or specs[j].name
            end
            parts[#parts + 1] = ("|cff0091ed%s|r%s"):format(names[i],
                specText and (" -- " .. specText) or "")
        end
    else
        for i = 1, #SECTIONS do
            local sec = SECTIONS[i]
            local n = CountSection(sec.count, payload.data[sec.field])
            if n > 0 then parts[#parts + 1] = ("%d %s"):format(n, sec.label) end
        end
    end
    if #parts == 0 then return nil, "The pack is empty." end

    local desc = ("|cff0091ed%s|r by %s%s|n%s"):format(
        tostring(payload.name), tostring(payload.author),
        payload.made ~= "" and (" (" .. payload.made .. ")") or "",
        table.concat(parts, multi and "|n" or ", "))
    return payload, desc
end

-- Apply a decoded payload. mode "replace": every section the pack carries
-- overwrites the local one. mode "merge": pack entries win per key, local
-- entries the pack lacks survive. Either way the write happens LAST, after
-- everything staged cleanly, so a failure cannot leave a half-applied pack.
-- Which specs a pack carries, named. presets, activePreset and abilityBindings are keyed by
-- spec outright; bossLists keys are "spec:encounter". Everything else in a pack -- callout
-- lines, audio switches, custom and raid reminders -- is keyed by spell or encounter and
-- belongs to no spec in particular.
--
-- A profile accumulates a spec the first time it is configured there, and every character on
-- an account shares one profile unless it is changed, so a curator who plays ten classes
-- ends up with all ten in a single string.
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

-- wantSpecs, when given, is a set of spec keys to take; the spec-keyed sections are filtered
-- to it and everything else comes across whole. Nil means the whole pack, which is what an
-- older caller and the merge path both expect.

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

-- A whole-file pack: several named profiles at once. Each lands in a profile of that name,
-- created if it is new, and the importer stays where they are -- switching them into a
-- stranger's profile as a side effect of importing would be its own surprise. They pick
-- one from Active Profile afterwards.
--
-- Existing profiles of the same name are merged into per key rather than replaced, so a
-- buyer who already has a "Default" keeps whatever the seller's does not mention.
function ns.ApplyProfiles(payload, wantProfiles, wantSettings, bindSpecs)
    if type(payload) ~= "table" or type(payload.profiles) ~= "table" then return false end
    -- Taken before any profile in this pack is created, so a name the pack itself introduces
    -- twice still reads as new both times.
    local existing = {}
    do
        local names = ns.ListProfiles and ns.ListProfiles() or {}
        for i = 1, #names do existing[names[i]] = true end
    end
    local landed = 0
    for name, data in pairs(payload.profiles) do
        if (not wantProfiles or wantProfiles[name]) and type(data) == "table" then
            local isNewProfile = not existing[name]
            local tr = ns.EnsureProfile and ns.EnsureProfile(name)
            if tr then
                for i = 1, #SECTIONS do
                    local sec = SECTIONS[i]
                    local incoming = data[sec.field]
                    if type(incoming) == "table" then
                        if type(tr[sec.field]) ~= "table" then tr[sec.field] = {} end
                        for k, v in pairs(incoming) do tr[sec.field][k] = Copy(v) end
                    end
                end
                if wantSettings and type(data.settings) == "table" then
                    for k, v in pairs(data.settings) do
                        if k == "pos" then
                            if type(v) == "table" then tr.pos = Copy(v) end
                        else
                            tr[k] = v
                        end
                    end
                end
                -- Marked the same way a single-profile import is: what arrived from someone
                -- else is not the importer's to sell on.
                tr.importedPack = {
                    name = tostring(payload.name or "a pack"),
                    author = tostring(payload.author or "its curator"),
                }
                -- A brand-new profile has nothing pre-existing to conflict with, so it's safe
                -- to trust what the source reports. A pack made before this field existed
                -- carries no opinion (nil) and defaults to true, the same assumption this fix
                -- started from: every real export has been spec-shaped except the one gap
                -- this closes. Only an explicit false -- a source profile that was itself
                -- never migrated -- defers to the real migration once this profile goes
                -- active.
                --
                -- A merge into a profile that was already here is left alone. Forcing this
                -- true on a merge could stamp a profile that still has its own un-migrated
                -- legacy entries sitting under keys the incoming pack didn't touch, and the
                -- real migration would never get another chance to run on them.
                if isNewProfile then
                    tr.bindingsBySpec = data.bindingsBySpec ~= false
                end
                -- Bind each landed profile to the specs it carries, so the character that
                -- plays one lands on it without being told which is theirs. A profile
                -- covering several specs claims each of them; the last profile to claim a
                -- spec wins, which is the same rule a curator applies by naming them.
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

-- A name no existing profile has. "Naowh Raid", then "Naowh Raid 2", and so on.
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

-- Import as a NEW profile, always. Nothing the importer already has is touched, so there is
-- no merge-or-replace to get wrong and no way for a pack to take a spec, a preset or a whole
-- profile with it -- which is what replace did on this account, twice. Their own profile is
-- still there; switching back to it restores everything exactly as it was.
--
-- The profile is fresh, so the sections copy in wholesale: there is nothing underneath to
-- merge with, which is the other half of why this is simpler than what it replaces.
function ns.ImportPackAsProfile(payload, wantSpecs, wantSettings, remapSpec)
    if type(payload) ~= "table" or type(payload.data) ~= "table" then return false end
    local name = FreeProfileName(payload.name)
    local tr = ns.EnsureProfile and ns.EnsureProfile(name)
    if not tr then return false end

    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local incoming = payload.data[sec.field]
        if type(incoming) == "table" then
            tr[sec.field] = FilterToSpecs(sec.field, incoming, wantSpecs)
        end
    end

    if remapSpec and type(tr.abilityBindings) == "table" then
        local target = tr.abilityBindings[remapSpec]
        if type(target) ~= "table" then target = {} end
        for specKey, byEncounter in pairs(tr.abilityBindings) do
            if specKey ~= remapSpec and type(byEncounter) == "table" then
                for enc, abilities in pairs(byEncounter) do
                    if type(target[enc]) ~= "table" then target[enc] = {} end
                    for sid, binding in pairs(abilities) do
                        target[enc][sid] = Copy(binding)
                    end
                end
            end
        end
        tr.abilityBindings[remapSpec] = target
    end

    if wantSettings and type(payload.data.settings) == "table" then
        for k, v in pairs(payload.data.settings) do
            if k == "pos" then
                if type(v) == "table" then tr.pos = Copy(v) end
            else
                tr[k] = v
            end
        end
    end
    if type(payload.data.leadTime) == "number" then tr.leadTime = payload.data.leadTime end
    if type(payload.data.voiceNone) == "string" and payload.data.voiceNone ~= "" then
        tr.voiceNone = payload.data.voiceNone
    end

    tr.importedPack = {
        name = tostring(payload.name or "a pack"),
        author = tostring(payload.author or "its curator"),
    }
    -- See the same line in ApplyProfiles: this is always a fresh profile, so there's nothing
    -- pre-existing to conflict with -- it's safe to trust whatever the source reports, nil
    -- (a pack made before this field existed) included.
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
    -- Given the same field treatment as every other edit box here. Without it there is
    -- nothing on screen marking where the text goes, which on the import side reads as a
    -- dialog with no input at all.
    ns.Solid(scroll, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(scroll)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(1)
    -- A multiline edit box sizes itself to its CONTENT, so an empty one is zero pixels
    -- tall and cannot be clicked into -- which is why the export box worked (it opens
    -- full of text) and the import box did not. Start it at the full scroll height; text
    -- longer than that still grows it from here.
    box:SetHeight(height)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(self, w) box:SetWidth(w) end)

    -- Clicking anywhere in the field focuses the text, not just the exact glyph run.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    return box
end

-- A pack string is one giant run with no spaces for the client's own word-wrap to break
-- on, so real line breaks are inserted here instead. Measured against this box's actual
-- font rather than a guessed characters-per-line count -- a guess already turned out
-- wrong once, still running past the edge of the same box it was meant to fix, since
-- this alphabet renders wider than the guess assumed.
--
-- Free on the way back in either way: DecodePack strips all whitespace before it looks
-- at the string, so every inserted break disappears again on import.
-- Parked off-screen rather than :Hide()'d. A hidden FontString does not get its text
-- metrics computed at all -- GetStringWidth() answers 0 for it regardless of the text --
-- so the first version of this measured every candidate line as "fits" and wrapped
-- nothing. Shown, just nowhere anyone can see it, so the client actually lays it out.
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

-- How many characters of str, starting at "from", fit within maxWidth. Grows the
-- candidate span geometrically to bound the search, then narrows it exactly -- a few
-- dozen measurements per line, run once per box open or edit, not per frame.
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
    -- At least one character even if it overflows maxWidth: a target too small to fit
    -- anything must still make progress rather than loop forever on the same position.
    return math.max(lo, 1)
end

-- Fixed, conservative character count, used whenever something needed to answer the real
-- width and could not -- the container's own width unreadable, or the gauge measuring a
-- non-empty string as zero. Either is the gauge lying rather than the text fitting, which
-- is exactly how the :Hide()'d version of this failed silently the first time: trusting a
-- broken answer instead of falling back to something that still wraps.
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

-- Built once and reused. ns.MakeModal hands out a fresh dimmer and panel on every call
-- and never releases the old one, so rebuilding these per open stacked a new copy on the
-- screen each time the button was pressed -- reported as spawning infinite boxes. Same
-- cached-dialog shape ShowNamePrompt in Bosses.lua already uses.
local packExport, packImport

function ns.ShowPackExport()
    if packExport then
        packExport.Regenerate()
        packExport.dimmer:Show()
        return
    end
    -- 392 is the floor, not the fixed height: Regenerate grows the panel to fit however
    -- many lines the covered-specs line below the box wraps to (see MIN_HEIGHT below).
    -- 392 itself is the text box running to -258 plus the "every profile" tick needing to
    -- sit clear below it -- at a lower floor that tick landed inside the box, which
    -- swallowed every click on it since the box is an EditBox that grows with its content
    -- and takes the mouse.
    local MIN_HEIGHT = 392
    local dimmer, panel = ns.MakeModal(560, MIN_HEIGHT, "packExport")
    -- ns.Font, not a guard on ns.MakeFontString: that name is defined nowhere in the addon,
    -- so the guard was always false and this title alone skipped the shared helper every
    -- other heading here uses.
    local title = ns.Font(panel, 14, "OUTLINE")
    title:SetPoint("TOP", panel, "TOP", 0, -14)
    title:SetText("Share your Profile")

    local nameBox = CreateFrame("EditBox", nil, panel)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("GameFontHighlight")
    nameBox:SetSize(300, 22)
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    nameBox:SetText("My Reminder Pack")
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
    hint:SetText("pack name, shown on import")

    local box = ns.MakeMultilineBox(panel, -78, 180)
    -- Left/right-anchored and word-wrapped, not the single centered anchor point this had
    -- before: that let the line grow as wide as its own text needed with nothing to stop
    -- it, so a curator's whole class list rendered as one line running out past the panel
    -- on both sides onto the game world behind it. Positioned once allBtn exists, below.
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetWordWrap(true)
    status:SetJustifyH("CENTER")

    local everyProfile, allBtn, closeBtn = false, nil, nil

    local function Regenerate()
        local str, err
        if everyProfile then
            str, err = ns.ExportAllProfiles(nameBox:GetText(), UnitName and UnitName("player"))
        else
            str, err = ns.ExportPack(nameBox:GetText(), UnitName and UnitName("player"))
        end
        if str then
            -- The scroll frame's own width, not box:GetWidth(): box's width is set from
            -- OnSizeChanged, which can still be one frame behind on the very first open,
            -- while the scroll frame's is anchor-derived off the panel's literal SetSize
            -- and correct the instant it's asked for.
            local maxWidth = box:GetParent():GetWidth()
            box:SetText(WrapForDisplay(str, maxWidth))
            -- Named, not counted. A curator sharing a set for ten classes wants to see that
            -- all ten went in, and the only way to be sure was to import it somewhere.
            local names
            if everyProfile then
                local profs = ns.ListProfiles and ns.ListProfiles() or {}
                for i = 1, #profs do
                    names = names and (names .. ", " .. profs[i]) or profs[i]
                end
            else
                local specs = ns.PackSpecs({ data = { presets = ns.DB().presets,
                    activePreset = ns.DB().activePreset, bossLists = ns.DB().bossLists,
                    abilityBindings = ns.DB().abilityBindings } })
                for i = 1, #specs do
                    names = names and (names .. ", " .. specs[i].name) or specs[i].name
                end
            end
            status:SetText(("%d characters%s. Click the text, then Ctrl+A Ctrl+C."):format(
                #str, names and (" covering " .. names) or ""))
        else
            box:SetText("")
            status:SetText("|cffff6060" .. tostring(err) .. "|r")
        end
        -- Grown to fit however tall status turned out to be, not truncated to fit a fixed
        -- height: the whole point of naming every class is reassuring a curator who just
        -- exported ten of them that all ten actually went in. 78+180 is the box's own
        -- fixed top offset and height; everything after it is the allBtn/status/close
        -- stack that now chains off status's real wrapped height instead of a guess.
        if allBtn and closeBtn then
            local needed = 78 + 180 + 14 + allBtn:GetHeight() + 10 + status:GetHeight()
                + 10 + closeBtn:GetHeight() + 16
            panel:SetHeight(math.max(MIN_HEIGHT, needed))
        end
    end

    -- A curator keeping a profile per class needs one string, not ten. Off by default: the
    -- usual case is sharing the setup you are standing in.
    allBtn = ns.Button(panel, "", 300, 22, function()
        everyProfile = not everyProfile
        allBtn.label:SetText((everyProfile and "|cff0091ed[x]|r  " or "[  ]  ")
            .. "Every profile, not just this one")
        Regenerate()
    end)
    -- Anchored below the scroll frame itself, not a fixed panel-bottom offset: the scroll
    -- frame is always exactly 180 tall regardless of the panel's own (now variable) height,
    -- so this row's position never has to know how tall the panel ended up being.
    allBtn:SetPoint("TOP", box:GetParent(), "BOTTOM", 0, -14)
    -- Above the scroll frame either way, so a box grown by a long string cannot cover it.
    allBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
    allBtn.label:SetText("[  ]  Every profile, not just this one")

    -- status chains off allBtn (now that it exists) rather than a fixed panel-bottom
    -- offset, so it always starts right below the tick regardless of panel height.
    status:SetPoint("TOP", allBtn, "BOTTOM", 0, -10)
    status:SetPoint("LEFT", panel, "LEFT", 14, 0)
    status:SetPoint("RIGHT", panel, "RIGHT", -14, 0)

    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- The string is display-only: retyping into it produces nothing valid, so
    -- any edit just regenerates from the real settings.
    box:SetScript("OnTextChanged", function(_, user) if user then Regenerate() end end)
    nameBox:SetScript("OnTextChanged", function(_, user) if user then Regenerate() end end)

    closeBtn = ns.Button(panel, "Close", 110, 26, function() dimmer:Hide() end)
    -- Chained off status's own bottom, not the panel's, for the same reason as allBtn:
    -- status can be one line or several depending on how many classes a pack covers, and
    -- this has to end up below it either way rather than guessing a fixed offset that
    -- fits only the common case.
    closeBtn:SetPoint("TOP", status, "BOTTOM", 0, -10)

    packExport = { dimmer = dimmer, Regenerate = Regenerate }
    Regenerate()
    dimmer:Show()
end

-- The diagnostic trace, in the same copyable box the pack export uses. There is no way
-- for an addon to write a file, and asking a tester to find and attach SavedVariables has
-- its own failure modes, so the trace leaves as text they select and paste.
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
        -- Display only: an edit here would just corrupt the paste, so any change puts the
        -- captured text straight back.
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

function ns.ShowPackImport()
    if packImport then
        packImport.box:SetText("")
        packImport.Revalidate()
        packImport.dimmer:Show()
        packImport.box:SetFocus()
        return
    end
    local dimmer, panel = ns.MakeModal(560, 470, "packImport")
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

    -- One row per spec the pack carries, so a curator's ten-class string can be taken a
    -- class at a time. Built once and reused: this dialog is cached between opens, and the
    -- rows have to survive pasting a different string into the same window.
    local specRows, specWanted = {}, {}
    local settingsWanted, settingsBtn = true, nil
    local remapWanted, remapBtn = false, nil
    local bindWanted, bindBtn = true, nil
    -- Anchored under the preview rather than at a fixed offset: the preview grows a line per
    -- profile in the pack, and at a fixed offset the two ran into each other the moment a
    -- string carried more than one.
    local specHead = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    specHead:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -12)
    specHead:SetJustifyH("LEFT")
    specHead:Hide()

    local function BuildSpecRows(payload)
        for i = 1, #specRows do specRows[i]:Hide() end
        if settingsBtn then settingsBtn:Hide() end
        if remapBtn then remapBtn:Hide() end
        if bindBtn then bindBtn:Hide() end
        wipe(specWanted)
        -- A whole-file pack is a list of PROFILES; a single-profile one is a list of specs
        -- inside it. Same rows either way, and the same wanted set drives the apply.
        local multi = payload and type(payload.profiles) == "table"
        local specs = {}
        if multi then
            local names = {}
            for name in pairs(payload.profiles) do names[#names + 1] = name end
            table.sort(names, function(a, b) return a:lower() < b:lower() end)
            for i = 1, #names do specs[i] = { key = names[i], name = names[i] } end
        elseif payload then
            specs = ns.PackSpecs(payload)
        end
        if #specs == 0 then
            specHead:Hide()
            return
        end
        specHead:SetText(multi and "Bring in which profiles:" or "Bring in which of these:")
        specHead:Show()
        for i = 1, #specs do
            local spec = specs[i]
            specWanted[spec.key] = true
            local btn = specRows[i]
            if not btn then
                btn = ns.Button(panel, "", 250, 22, nil)
                -- Above the paste box: it is an EditBox that grows with its content, and
                -- a whole-file string is long enough to reach down over these rows and
                -- take their clicks. The export tick lost every click to exactly that.
                btn:SetFrameLevel(panel:GetFrameLevel() + 10)
                specRows[i] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", i == 1 and specHead or specRows[i - 1],
                i == 1 and "BOTTOMLEFT" or "BOTTOMLEFT", i == 1 and 6 or 0, -6)
            local function Paint()
                -- ns.Button keeps its own font string; the frame has none of its own.
                btn.label:SetText((specWanted[spec.key] and "|cff0091ed[x]|r  " or "[  ]  ")
                    .. spec.name)
            end
            btn:SetScript("OnClick", function()
                specWanted[spec.key] = not specWanted[spec.key] or nil
                Paint()
            end)
            Paint()
            btn:Show()
        end

        -- Offered only when the pack has them: an older string carries none.
        if type(payload.data) == "table" and type(payload.data.settings) == "table" then
            if not settingsBtn then
                settingsBtn = ns.Button(panel, "", 320, 22, nil)
                settingsBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
            end
            settingsBtn:ClearAllPoints()
            settingsBtn:SetPoint("TOPLEFT", specRows[#specs] or specHead, "BOTTOMLEFT",
                specRows[#specs] and 0 or 6, -10)
            local function PaintSettings()
                settingsBtn.label:SetText((settingsWanted and "|cff0091ed[x]|r  " or "[  ]  ")
                    .. "Their display, sound and behaviour settings")
            end
            settingsBtn:SetScript("OnClick", function()
                settingsWanted = not settingsWanted
                PaintSettings()
            end)
            PaintSettings()
            settingsBtn:Show()
        elseif settingsBtn then
            settingsBtn:Hide()
        end

        -- Offered only when it would actually do something: the pack has boss ability
        -- choices, and none of them are already under the spec being played.
        local mySpec = ns.CurrentSpec and ns.CurrentSpec()
        local bindings = (not multi) and payload and type(payload.data) == "table"
            and payload.data.abilityBindings
        local elsewhere = false
        if type(bindings) == "table" and mySpec and mySpec > 0 then
            for specKey in pairs(bindings) do
                if tostring(specKey) ~= tostring(mySpec) then elsewhere = true end
            end
        end
        if elsewhere then
            if not remapBtn then
                remapBtn = ns.Button(panel, "", 380, 22, nil)
                remapBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
            end
            remapBtn:ClearAllPoints()
            remapBtn:SetPoint("TOPLEFT", (settingsBtn and settingsBtn:IsShown())
                and settingsBtn or (specRows[#specs] or specHead), "BOTTOMLEFT",
                (settingsBtn and settingsBtn:IsShown()) and 0
                    or (specRows[#specs] and 0 or 6), -6)
            local function PaintRemap()
                remapBtn.label:SetText((remapWanted and "|cff0091ed[x]|r  " or "[  ]  ")
                    .. "Use their boss ability choices on my " .. ns.SpecName(mySpec))
            end
            remapBtn:SetScript("OnClick", function()
                remapWanted = not remapWanted
                PaintRemap()
            end)
            PaintRemap()
            remapBtn:Show()
        elseif remapBtn then
            remapBtn:Hide()
        end

        -- Only for a whole-file pack: binding one profile to its own specs would just
        -- describe where the importer already is.
        if multi then
            if not bindBtn then
                bindBtn = ns.Button(panel, "", 380, 22, nil)
                bindBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
            end
            bindBtn:ClearAllPoints()
            bindBtn:SetPoint("TOPLEFT", (settingsBtn and settingsBtn:IsShown())
                and settingsBtn or (specRows[#specs] or specHead), "BOTTOMLEFT",
                (settingsBtn and settingsBtn:IsShown()) and 0
                    or (specRows[#specs] and 0 or 6), -6)
            local function PaintBind()
                bindBtn.label:SetText((bindWanted and "|cff0091ed[x]|r  " or "[  ]  ")
                    .. "Use each on the character whose spec it covers")
            end
            bindBtn:SetScript("OnClick", function()
                bindWanted = not bindWanted
                PaintBind()
            end)
            PaintBind()
            bindBtn:Show()
        elseif bindBtn then
            bindBtn:Hide()
        end

        -- The panel takes whatever the rows came to. A pack covering ten classes is ten rows
        -- longer than one covering one, and a fixed height either wasted half the dialog or
        -- ran the last rows under the Import button.
        local last = (bindBtn and bindBtn:IsShown() and bindBtn)
            or (remapBtn and remapBtn:IsShown() and remapBtn)
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
        -- Nil rather than an empty set when every spec is ticked, so a pack whose specs are
        -- all wanted still takes the plain replace path and matches the curator exactly.
        -- A whole-file pack lands its profiles and leaves the importer where they are; the
        -- merge/replace choice is about one profile's sections and does not apply.
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
                -- Turning the switching on is part of asking for the binding: a map nothing
                -- consults would leave the tick looking broken.
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
        local mine = ns.CurrentSpec and ns.CurrentSpec()
        local remap = (remapWanted and mine and mine > 0) and tostring(mine) or nil
        local ok, newName = ns.ImportPackAsProfile(decoded, want, settingsWanted, remap)
        if ok then
            ns.Print(("imported as the profile '%s', and switched to it. Your own profile "
                .. "is untouched -- switch back to it any time."):format(tostring(newName)))
            dimmer:Hide()
            local EUI = ns.UI
            if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
        else
            preview:SetText("|cffff6060The pack could not be applied.|r")
        end
    end

    -- Import or Cancel, and nothing else to weigh up. Merge and Replace were a choice about
    -- what a pack should do to the profile you were standing in; now it never touches it, so
    -- there is no question to put.
    applyBtn = ns.Button(panel, "Import", 130, 26, function() Finish() end)
    applyBtn:SetPoint("BOTTOM", panel, "BOTTOM", -70, 14)
    ns.Button(panel, "Cancel", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 70, 14)

    packImport = { dimmer = dimmer, box = box, Revalidate = Revalidate }
    Revalidate()
    dimmer:Show()
    -- Focused on open: the only thing anyone does with this dialog is paste.
    box:SetFocus()
end
