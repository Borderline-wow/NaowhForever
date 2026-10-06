-------------------------------------------------------------------------------
--  NaowhForever_ProfileShare.lua -- the Profiles page's Export and Import. Export makes the
--  parts ticked of the profile in use one string: every module's settings and positions, the
--  macros, the macro Library, Smart Reminders, talent builds, the BiS lists and the account's
--  look. Import shows what a string holds, takes the parts left ticked into a new profile and
--  switches to it; no existing profile changes. Any other Naowh Forever string pasted there
--  goes to its own import: a Smart Reminders pack, Forge macros, a talent build, a BiS list.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local PREFIX = "NFPROFILE1:"
local PACK_PREFIX = "NSRPACK2:"
local FORMAT = 1
local MAX_DEPTH = 12
local MAX_VALUES = 200000   -- values a string may hold; more is refused as too big

-- The account's look: every profile shares it, so it travels as its own part.
local LOOK = { "themePreset", "themeColors", "uiFont", "windowScale" }

-- The parts, in the order the import and the Profiles page list them. help: what Import does
-- with one; share: what the page's export says it is.
local PARTS = {
    { key = "settings", label = "Settings", help = "Every module's settings and positions",
      share = "Every module's settings and where its frames sit." },
    { key = "macros", label = "Macros", help = "Your class macros and the Macros settings",
      share = "Your class macros and the Macros settings." },
    { key = "library", label = "Macro Library", help = "Added next to your Library, never over it",
      share = "The macros you saved to the Forge's Library." },
    { key = "smartReminders", label = "Smart Reminders", help = "Reminders, priorities and callouts",
      share = "Reminders, priorities and callouts." },
    { key = "builds", label = "Talent Builds", help = "Added next to your saved builds",
      share = "The talent builds you saved in the Training Planner." },
    { key = "bisLists", label = "BiS Lists", help = "Added next to your own lists, never over them",
      share = "Your BiS lists, for every class." },
    { key = "look", label = "Look", help = "Theme colours, font and window scale, for every profile",
      share = "Theme colours, font and window scale." },
}

-------------------------------------------------------------------------------
--  The string
-------------------------------------------------------------------------------
local function Codec()
    local LS = LibStub and LibStub("LibSerialize", true)
    local LD = LibStub and LibStub("LibDeflate", true)
    if LS and LD then return LS, LD end
end

-- Plain data only (strings, numbers, booleans, tables keyed by strings or numbers), so
-- nothing live or unsaveable is shared or taken in. budget.over once there is too much.
local function Plain(v, depth, budget)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" or depth > MAX_DEPTH or budget.over then return nil end
    local out = {}
    for k, val in pairs(v) do
        budget.n = budget.n + 1
        if budget.n > MAX_VALUES then
            budget.over = true
            return nil
        end
        local kt = type(k)
        if kt == "string" or kt == "number" then out[k] = Plain(val, depth + 1, budget) end
    end
    return out
end

-- Forever's Lua raises on 1 / 0, which LibSerialize does to every 0 it writes (to spot -0), so
-- a 0 travels as ZERO and is put back on import.
local ZERO = "\0"

local function Swap(v, from, to)
    if v == from then return to end
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[Swap(k, from, to)] = Swap(val, from, to) end
    return out
end

-- A module's values as its settings keep them: a value with a default only as that type.
local function Checked(values, defaults)
    local out = {}
    for k, v in pairs(values) do
        local d = defaults[k]
        if d == nil or type(v) == type(d) then out[k] = v end
    end
    return out
end

-- Every part the profile in use can share, what had to stay behind, and whether it is too big.
local function Collect()
    local root, account = ns.SettingsRoot(), ns.AccountSettings()
    local budget = { n = 0 }
    local parts, note = {}, nil

    local settings = {}
    for key, values in pairs(root) do
        if key ~= "tankReminder" and key ~= "macros" and type(values) == "table" and ns.ModuleDefaults(key) then
            settings[key] = Plain(values, 1, budget)
        end
    end
    if next(settings) then parts.settings = settings end

    -- A profile made from someone's pack keeps their work: the pack export refuses it too.
    local sr = root.tankReminder
    local packed = type(sr) == "table" and type(sr.importedPack) == "table"
    if packed then
        note = ("Smart Reminders and class macros came from %s, so they are left out."):format(
            tostring(sr.importedPack.name))
    end

    local macros = {}
    if type(root.macros) == "table" then macros.module = Plain(root.macros, 1, budget) end
    local utility = type(sr) == "table" and sr.utilityReminders
    if not packed and type(utility) == "table" and type(utility.classMacros) == "table" then
        macros.classMacros = Plain(utility.classMacros, 1, budget)
    end
    if next(macros) then parts.macros = macros end

    -- Class macros live in Smart Reminders' data; they travel as Macros only, so leaving
    -- Macros unticked on import leaves them out.
    if type(sr) == "table" and not packed then
        local copy = Plain(sr, 1, budget)
        if copy and type(copy.utilityReminders) == "table" then copy.utilityReminders.classMacros = nil end
        parts.smartReminders = copy
    end

    if type(account.bisLists) == "table" then
        local lists = {}
        for class, store in pairs(account.bisLists) do
            if type(store) == "table" and type(store.lists) == "table" and #store.lists > 0 then
                lists[class] = Plain(store.lists, 1, budget)
            end
        end
        if next(lists) then parts.bisLists = lists end
    end

    -- A Library copy of a pack macro stays with the pack's curator, as the pack's macros do.
    if type(account.libraryMacros) == "table" then
        local library, copies = {}, false
        for class, list in pairs(account.libraryMacros) do
            local own = {}
            for _, m in ipairs(list) do
                if m.pack then copies = true else own[#own + 1] = Plain(m, 1, budget) end
            end
            if #own > 0 then library[class] = own end
        end
        if next(library) then parts.library = library end
        if copies then
            note = (note and note .. "\n" or "") .. "Library macros copied from a pack are left out."
        end
    end

    if type(account.trainingBuilds) == "table" then
        local builds = {}
        for classID, list in pairs(account.trainingBuilds) do
            local out = {}
            for i, b in ipairs(list) do
                out[i] = { name = b.name, spec = b.spec, points = Plain(b.points, 1, budget) }
            end
            if #out > 0 then builds[classID] = out end
        end
        if next(builds) then parts.builds = builds end
    end

    local look = {}
    for _, key in ipairs(LOOK) do
        if account[key] ~= nil then look[key] = Plain(account[key], 1, budget) end
    end
    if next(look) then parts.look = look end

    return parts, note, budget.over
end

--- The parts ticked in wanted ({ [partKey] = true }, nil for all) of the profile in use as a
--- string. Returns it and, when a part had to stay behind, why.
---@return string? text
---@return string? note an error when text is nil, else what was left out
function ns.ExportProfile(wanted)
    local LS, LD = Codec()
    if not LS then return nil, "The serializer libraries are missing from this build." end
    local all, note, over = Collect()
    if over then return nil, "This profile is too big to share." end
    local parts = {}
    for key, data in pairs(all) do
        if not wanted or wanted[key] then parts[key] = data end
    end
    if not next(parts) then
        return nil, next(all) and "Tick a part to share." or "There is nothing to export yet."
    end
    local payload = {
        format = FORMAT, name = ns.ActiveProfileName(), author = UnitName("player"),
        made = date("%Y-%m-%d"), build = ns.CODE_BUILD, parts = parts,
    }
    return PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize(Swap(payload, 0, ZERO)))), note
end

--- A string back into what it holds. "pack" for a Smart Reminders pack string.
---@return table? payload
---@return string? err
function ns.DecodeProfile(text)
    text = (text or ""):gsub("%s", "")
    if text == "" then return nil end
    if text:sub(1, #PACK_PREFIX) == PACK_PREFIX then return nil, "pack" end
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "This is not a Naowh Forever profile string." end
    local LS, LD = Codec()
    if not LS then return nil, "The serializer libraries are missing from this build." end
    local compressed = LD:DecodeForPrint(text:sub(#PREFIX + 1))
    local raw = compressed and LD:DecompressDeflate(compressed)
    if not raw then return nil, "The string is damaged: copy it again in full." end
    local ok, payload = LS:Deserialize(raw)
    if not ok or type(payload) ~= "table" or type(payload.parts) ~= "table" then
        return nil, "The string is damaged: copy it again in full."
    end
    if payload.format ~= FORMAT then return nil, "This string is from a newer Naowh Forever: update first." end
    local budget = { n = 0 }
    payload.parts = Plain(Swap(payload.parts, ZERO, 0), 1, budget)
    if budget.over then return nil, "This string is too big." end
    return payload
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- What a decoded string holds, part by part: { key, label, help, detail }.
function ns.ProfileStringParts(payload)
    local out, parts = {}, payload.parts
    for _, part in ipairs(PARTS) do
        local data = parts[part.key]
        if type(data) == "table" and next(data) then
            local detail
            if part.key == "settings" then
                detail = ("%d modules"):format(Count(data))
            elseif part.key == "macros" then
                local n = 0
                for _, list in pairs(type(data.classMacros) == "table" and data.classMacros or {}) do
                    if type(list) == "table" then n = n + Count(list) end
                end
                detail = ("%d class macros"):format(n)
            elseif part.key == "bisLists" or part.key == "library" or part.key == "builds" then
                local n = 0
                for _, list in pairs(data) do
                    if type(list) == "table" then n = n + #list end
                end
                detail = ("%d %s"):format(n, part.key == "bisLists" and "lists"
                    or part.key == "library" and "macros" or "builds")
            end
            out[#out + 1] = { key = part.key, label = part.label, help = part.help, detail = detail }
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  Taking a string in
-------------------------------------------------------------------------------
local function FreeProfileName(base)
    base = type(base) == "string" and base:match("^%s*(.-)%s*$") or ""
    if base == "" then base = "Imported Profile" end
    if not ns.ProfileExists(base) then return base end
    local n = 2
    while ns.ProfileExists(base .. " " .. n) do n = n + 1 end
    return base .. " " .. n
end

local function SameList(a, b)
    if a.name ~= b.name or type(a.slots) ~= type(b.slots) then return false end
    if type(a.slots) ~= "table" then return true end
    for slot, id in pairs(a.slots) do if b.slots[slot] ~= id then return false end end
    for slot in pairs(b.slots) do if a.slots[slot] == nil then return false end end
    return true
end

-- Each list joins its class's lists under a free name; one already there as it is, is skipped.
local function AddBisLists(incoming)
    local account = ns.AccountSettings()
    account.bisLists = type(account.bisLists) == "table" and account.bisLists or {}
    local added = 0
    for class, lists in pairs(incoming) do
        if type(class) == "string" and type(lists) == "table" then
            local store = account.bisLists[class]
            if type(store) ~= "table" or type(store.lists) ~= "table" then
                store = { lists = {}, nextID = 1 }
                account.bisLists[class] = store
            end
            store.nextID = tonumber(store.nextID) or #store.lists + 1
            for _, list in ipairs(lists) do
                local have = false
                for _, mine in ipairs(store.lists) do
                    if type(list) == "table" and SameList(mine, list) then have = true end
                end
                if type(list) == "table" and type(list.name) == "string" and not have then
                    local name, n = list.name, 1
                    local function Taken(try)
                        for _, mine in ipairs(store.lists) do
                            if type(mine.name) == "string" and mine.name:lower() == try:lower() then return true end
                        end
                    end
                    while Taken(name) do
                        n = n + 1
                        name = ("%s %d"):format(list.name, n)
                    end
                    list.name, list.id = name, store.nextID
                    store.nextID = store.nextID + 1
                    store.lists[#store.lists + 1] = list
                    added = added + 1
                end
            end
        end
    end
    return added
end

-- Each macro joins its class's Library when it fits a macro; a name already there keeps yours.
local function AddLibrary(incoming)
    local account = ns.AccountSettings()
    account.libraryMacros = type(account.libraryMacros) == "table" and account.libraryMacros or {}
    local added = 0
    for class, list in pairs(incoming) do
        if type(class) == "string" and type(list) == "table" then
            local mine = account.libraryMacros[class] or {}
            for _, m in ipairs(list) do
                local name = type(m) == "table" and type(m.name) == "string" and m.name:gsub("[|\r\n]", "")
                local body = name and m.body
                local taken = false
                for _, e in ipairs(mine) do taken = taken or e.name == name end
                if name and #name >= 1 and #name <= 16 and type(body) == "string" and #body >= 1
                    and #body <= ns.MacroText.LIMIT and not taken then
                    local icon = (type(m.icon) == "number" or type(m.icon) == "string") and m.icon or nil
                    mine[#mine + 1] = { name = name, body = body, icon = icon }
                    account.libraryMacros[class] = mine
                    added = added + 1
                end
            end
        end
    end
    return added
end

local function SameBuild(a, b)
    if a.name ~= b.name or #a.points ~= #b.points then return false end
    for i, node in ipairs(a.points) do if b.points[i] ~= node then return false end end
    return true
end

-- Each build joins its class's saved builds when its points can be taken in that order; one
-- already there as it is, is skipped.
local function AddBuilds(incoming)
    local Training = ns.Training
    local account = ns.AccountSettings()
    account.trainingBuilds = type(account.trainingBuilds) == "table" and account.trainingBuilds or {}
    local added = 0
    for classID, list in pairs(incoming) do
        local tree = ns.TrainingBuilds[classID]
        if tree and type(list) == "table" then
            local saved = account.trainingBuilds[classID] or {}
            for _, b in ipairs(list) do
                local points = {}
                for i, node in ipairs(type(b) == "table" and type(b.points) == "table" and b.points or {}) do
                    points[i] = node
                end
                if #points > 0 and not Training.CheckBuild(tree, points) then
                    local build = { name = Training.BuildName(b.name, "Imported Build"),
                        spec = Training.BuildName(b.spec, "Imported"), points = points, saved = true }
                    local have = false
                    for _, mine in ipairs(saved) do have = have or SameBuild(mine, build) end
                    if not have then
                        saved[#saved + 1] = build
                        account.trainingBuilds[classID] = saved
                        added = added + 1
                    end
                end
            end
        end
    end
    if added > 0 then Training.Changed() end
    return added
end

--- The parts of a decoded string ticked in wanted ({ [partKey] = true }), as a new profile
--- named name (made free if taken), then switched to. The look, Library, builds and BiS lists
--- are account-wide.
---@return string name the profile made
---@return table added how many { bisLists, library, builds } joined the account's
function ns.ImportProfile(payload, wanted, name)
    local parts = payload.parts
    name = FreeProfileName(name or payload.name)
    local root = ns.ProfileRoot(name)

    if wanted.settings and type(parts.settings) == "table" then
        for key, values in pairs(parts.settings) do
            local defaults = ns.ModuleDefaults(key)
            if defaults and key ~= "macros" and key ~= "tankReminder" and type(values) == "table" then
                root[key] = Checked(values, defaults)
            end
        end
    end
    if wanted.smartReminders and type(parts.smartReminders) == "table" then
        root.tankReminder = parts.smartReminders
        root.tankReminder.importedPack = nil
    end
    if wanted.macros and type(parts.macros) == "table" then
        local macros = parts.macros
        if type(macros.module) == "table" then root.macros = Checked(macros.module, ns.ModuleDefaults("macros") or {}) end
        if type(macros.classMacros) == "table" then
            local sr = root.tankReminder
            if type(sr.utilityReminders) ~= "table" then sr.utilityReminders = {} end
            sr.utilityReminders.classMacros = macros.classMacros
        end
    end
    local added = { bisLists = 0, library = 0, builds = 0 }
    if wanted.bisLists and type(parts.bisLists) == "table" then added.bisLists = AddBisLists(parts.bisLists) end
    -- The Library and builds are checked by the Macros and Training Planner code, so they wait
    -- for those modules to be on.
    if wanted.library and ns.MacroText and type(parts.library) == "table" then added.library = AddLibrary(parts.library) end
    if wanted.builds and ns.Training and type(parts.builds) == "table" then added.builds = AddBuilds(parts.builds) end
    if wanted.look and type(parts.look) == "table" then
        local account = ns.AccountSettings()
        for _, key in ipairs(LOOK) do
            if parts.look[key] ~= nil then account[key] = parts.look[key] end
        end
    end

    ns.SwitchProfile(name)
    if ns.RefreshRuntime then ns.RefreshRuntime() end
    return name, added
end

-------------------------------------------------------------------------------
--  The two dialogs, in the house modal
-------------------------------------------------------------------------------
local EXPORT_W, EXPORT_H, BOX_H = 560, 360, 180
local IMPORT_W, IMPORT_H, PASTE_H = 600, 520, 110
local PAD, ROW_H, BUTTON_W, BUTTON_H = 14, 24, 120, 26
local TOGGLE_W, TOGGLE_H = 32, 16

-- Strings another import takes in: what the dialog says, and the button that hands them over.
-- `needs` is the ns function the hand-off calls, missing while its `module` is switched off.
local HANDOFFS = {
    { prefix = PACK_PREFIX, button = "Open Pack Import",
      what = "This is a Smart Reminders pack. The pack import takes it in, with its specs and licence.",
      go = function(text) ns.ShowPackImport(text) end },
    { prefix = "!NFM1!", button = "Add Macros", module = "Macros", needs = "ImportMacroString",
      what = "These are Forge macros. They are added as character macros on this character.",
      go = function(text) ns.ImportMacroString(text) end },
    { prefix = "!NFB1!", button = "Add Build", module = "Training Planner", needs = "Training",
      what = "This is a talent build. It is added to your builds in the Training Planner.",
      go = function(text) ns.Training.ImportBuild(text, function() end) end },
    { prefix = "!NBIS1!", button = "Add BiS List", module = "BiS List", needs = "ImportBisList",
      what = "This is a BiS list. It is added next to your own lists.",
      go = function(text) ns.ImportBisList(text) end },
}

local export

-- The string for the parts ticked in wanted (nil for all), ready to copy.
function ns.ShowProfileExport(wanted)
    if not export then
        local dimmer, panel = ns.MakeModal(EXPORT_W, EXPORT_H, "profileExport")
        local title = ns.Font(panel, 14, "OUTLINE")
        title:SetPoint("TOP", 0, -PAD)
        title:SetText("Export Profile")
        local what = UI.KeepFont(panel, "what", 11, nil, ns.THEME.muted)
        what:SetPoint("TOPLEFT", PAD, -40)
        what:SetPoint("RIGHT", -PAD, 0)
        what:SetJustifyH("LEFT")
        local box = ns.MakeMultilineBox(panel, -62, BOX_H)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        -- The text is the export: typing in it is undone.
        box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(export.text or "") end end)
        local status = UI.KeepFont(panel, "status", 11, nil, ns.THEME.fg)
        status:SetPoint("TOPLEFT", PAD, -(62 + BOX_H + 12))
        status:SetPoint("RIGHT", -PAD, 0)
        status:SetJustifyH("LEFT")
        local close = ns.Button(panel, "Close", BUTTON_W, BUTTON_H, function() dimmer:Hide() end)
        close:SetPoint("BOTTOM", 0, PAD)
        export = { dimmer = dimmer, box = box, what = what, status = status }
    end
    local labels = {}
    for _, part in ipairs(PARTS) do
        if not wanted or wanted[part.key] then labels[#labels + 1] = part.label end
    end
    export.what:SetText(("Profile: %s. %s."):format(ns.ActiveProfileName() or "?", table.concat(labels, ", ")))
    local text, note = ns.ExportProfile(wanted)
    if text then
        export.text = ns.WrapForDisplay(text, export.box:GetParent():GetWidth())
        export.box:SetText(export.text)
        export.status:SetText(("%d characters. Click the text, then Ctrl+A and Ctrl+C.%s"):format(#text,
            note and ("\n" .. note) or ""))
    else
        export.text = ""
        export.box:SetText("")
        export.status:SetText(note or "")
    end
    export.dimmer:Show()
end

local import

local function PaintImport()
    local text = import.box:GetText()
    local flat = text:gsub("%s", "")
    import.handoff = nil
    for _, handoff in ipairs(HANDOFFS) do
        if flat:sub(1, #handoff.prefix) == handoff.prefix then import.handoff = handoff end
    end
    for _, row in ipairs(import.rows) do row:Hide() end
    if import.handoff then
        import.payload = nil
        import.nameRow:Hide()
        if import.handoff.needs and not ns[import.handoff.needs] then
            import.preview:SetText(("Turn on %s under Settings > Modules to add this."):format(import.handoff.module))
            import.go:Hide()
            return
        end
        import.preview:SetText(import.handoff.what)
        ns.SetButtonText(import.go, import.handoff.button)
        import.go:Show()
        return
    end
    local payload, err = ns.DecodeProfile(text)
    import.payload = payload
    import.nameRow:SetShown(payload ~= nil)
    ns.SetButtonText(import.go, "Import")
    import.go:SetShown(payload ~= nil)
    if not payload then
        import.preview:SetText(err or "Paste a profile, macro, talent build or BiS list string above.")
        return
    end
    import.preview:SetText(("%s, shared by %s on %s. Untick what you don't want."):format(
        tostring(payload.name or "A profile"), tostring(payload.author or "someone"), tostring(payload.made or "?")))
    local y = -(40 + PASTE_H + 44)
    for i, part in ipairs(ns.ProfileStringParts(payload)) do
        local row = import.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, import.panel)
            row:SetHeight(ROW_H)
            row.toggle = UI.BuildToggleControl(row, nil, function() return import.wanted[row.key] end,
                function(on) import.wanted[row.key] = on == true end, TOGGLE_W, TOGGLE_H)
            row.toggle:SetPoint("LEFT", 0, 0)
            row.label = UI.KeepFont(row, "label", 12, nil, ns.THEME.fg)
            row.label:SetPoint("LEFT", row.toggle, "RIGHT", 10, 0)
            row.help = UI.KeepFont(row, "help", 11, nil, ns.THEME.muted)
            row.help:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
            import.rows[i] = row
        end
        row.key = part.key
        if import.wanted[part.key] == nil then import.wanted[part.key] = true end
        row.label:SetText(part.label)
        row.help:SetText(part.detail and (part.help .. " (" .. part.detail .. ")") or part.help)
        row.toggle._refreshValue()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, y)
        row:SetPoint("RIGHT", -PAD, 0)
        row:Show()
        y = y - ROW_H
    end
    import.nameRow:ClearAllPoints()
    import.nameRow:SetPoint("TOPLEFT", PAD, y - 10)
    import.nameRow:SetPoint("RIGHT", -PAD, 0)
    import.nameBox:SetText(FreeProfileName(payload.name))
end

local function Go()
    if import.handoff then
        local text = import.box:GetText()
        import.dimmer:Hide()
        import.handoff.go(text)
        return
    end
    local payload = import.payload
    if not payload then return end
    local name, added = ns.ImportProfile(payload, import.wanted, import.nameBox:GetText())
    import.dimmer:Hide()
    if UI.RefreshPage then UI:RefreshPage(true) end
    local joined = {}
    if added.library > 0 then joined[#joined + 1] = added.library .. " Library macros" end
    if added.builds > 0 then joined[#joined + 1] = added.builds .. " talent builds" end
    if added.bisLists > 0 then joined[#joined + 1] = added.bisLists .. " BiS lists" end
    local extra = #joined > 0 and (" Added %s."):format(table.concat(joined, ", ")) or ""
    ns.ConfirmReload(("Imported as %s and switched to it.%s Reload so every module picks it up?"):format(name, extra))
end

-- text: what was pasted on the Profiles page, to carry on with here.
function ns.ShowProfileImport(text)
    if not import then
        local dimmer, panel = ns.MakeModal(IMPORT_W, IMPORT_H, "profileImport")
        local title = ns.Font(panel, 14, "OUTLINE")
        title:SetPoint("TOP", 0, -PAD)
        title:SetText("Import")
        local box = ns.MakeMultilineBox(panel, -40, PASTE_H)
        local preview = UI.KeepFont(panel, "preview", 12, nil, ns.THEME.fg)
        preview:SetPoint("TOPLEFT", PAD, -(40 + PASTE_H + 14))
        preview:SetPoint("RIGHT", -PAD, 0)
        preview:SetJustifyH("LEFT")
        local nameRow = CreateFrame("Frame", nil, panel)
        nameRow:SetHeight(ROW_H)
        local nameLabel = UI.KeepFont(nameRow, "label", 12, nil, ns.THEME.fg)
        nameLabel:SetPoint("LEFT", 0, 0)
        nameLabel:SetText("New profile's name")
        local nameBox = ns.NewEditBox(nameRow)
        nameBox:SetSize(220, 22)
        nameBox:SetMaxLetters(40)
        nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
        nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local go = ns.AccentBorder(ns.Button(panel, "Import", BUTTON_W, BUTTON_H, Go))
        go:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, PAD)
        local cancel = ns.Button(panel, "Cancel", BUTTON_W, BUTTON_H, function() dimmer:Hide() end)
        cancel:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 4, PAD)
        import = { dimmer = dimmer, panel = panel, box = box, preview = preview, nameRow = nameRow,
            nameBox = nameBox, go = go, rows = {}, wanted = {} }
        box:SetScript("OnTextChanged", function(_, user) if user then PaintImport() end end)
    end
    import.box:SetText(text or "")
    wipe(import.wanted)
    PaintImport()
    import.dimmer:Show()
    import.box:SetFocus()
end

-------------------------------------------------------------------------------
--  The Profiles page: three cards. The profile in use with the others under it, the parts
--  to share as a grid of switches, and a paste box for Import.
-------------------------------------------------------------------------------
local HEAD_H, HEAD_SIZE = 44, 14     -- a card's head, as the settings pages draw theirs
local INSET = 16                     -- a card's contents from its edge
local GAP = 8                        -- between buttons, and between the share's tiles
local NAME_SIZE, LINE_SIZE, SMALL_SIZE = 13, 12, 11
local ACTIVE_H, ACTIVE_SIZE = 76, 18 -- the profile in use, its name larger
local MARK_W, MARK_INSET, MARK_GAP = 3, 16, 12   -- the accent bar beside it
local LINE_GAP = 6                   -- a name to the muted line under it
local ACTION_W = 84                  -- Use, Copy, Reset and Delete, one column each
local SMALL_H = 22                   -- buttons on the other profiles' rows and in a head
local NEW_W = 110
local GROUP_H = 30
local PROFILE_H = 46
local SHOWN_CHARS = 2                -- names before "and N more"
local TILE_H, TILE_PAD, TILE_GAP = 52, 12, 12   -- a part's tile, its padding, its switch to its name
local TWO_COLUMNS_W = 620            -- narrower than this, the tiles go one per row
local SEND_H = 58
local FIELD_H = 112                  -- the paste box, about six lines
local FIELD_TEXT = 12
local FIELD_INSET_X, FIELD_INSET_Y = 8, 6
local SCROLL_ROOM = 13               -- right of the paste box's text, for its scroll bar
local IMPORT_GAP = 12                -- the paste box to the row under it
local DIM = 0.4

-- Picks on the share, by part key: false when left out, so every part starts in.
local wanted = {}

local function Ticked(key)
    return wanted[key] ~= false
end

local function Done(ok, err)
    if not ok and err then ns.Print(err) end
    UI:RefreshPage(true)
end

local function NewProfile()
    ns.PromptText("New Profile", "", 40, function(text)
        local name = strtrim(text)
        local function Make(overwrite)
            local ok, err = ns.CreateProfile(name, overwrite)
            if ok then ns.SwitchProfile(name) end
            Done(ok, err)
        end
        if not ns.ProfileExists(name) then return Make(false) end
        ns.Confirm(("Replace %s with a profile at default settings? Cannot be undone."):format(name),
            function() Make(true) end, nil, "Replace")
    end)
end

local function CopyNamed(from)
    ns.PromptText("Copy " .. from, "", 40, function(text)
        local name = strtrim(text)
        local function Make(overwrite)
            local ok, err = ns.CopyProfile(from, name, overwrite)
            if ok then ns.SwitchProfile(name) end
            Done(ok, err)
        end
        if not ns.ProfileExists(name) then return Make(false) end
        ns.Confirm(("Overwrite %s with a copy of %s? Cannot be undone."):format(name, from),
            function() Make(true) end, nil, "Overwrite")
    end)
end

-- Only the profile in use: ResetProfileNamed clears just Smart Reminders on any other.
local function ResetActive(name)
    ns.Confirm(("Reset %s to default settings? Cannot be undone."):format(name),
        function() Done(ns.ResetProfileNamed(name)) end, nil, "Reset")
end

local function DeleteNamed(name)
    ns.Confirm(("Delete %s? Characters using it move to the account's default profile."):format(name),
        function() Done(ns.DeleteProfile(name)) end, nil, "Delete")
end

local function UseNamed(name)
    Done(ns.SwitchProfile(name))
end

-- Who else is on each profile, by name without the realm.
local function Characters()
    local me = UnitName("player") .. "-" .. GetRealmName()
    local by = {}
    for _, known in ipairs(ns.KnownCharacters()) do
        if known.char ~= me then
            local list = by[known.profile] or {}
            by[known.profile] = list
            list[#list + 1] = known.char:match("^[^-]+")
        end
    end
    return by
end

local function NameList(names)
    local n = #names
    if n > SHOWN_CHARS + 1 then
        return ("%s and %d more"):format(table.concat(names, ", ", 1, SHOWN_CHARS), n - SHOWN_CHARS)
    end
    if n == 1 then return names[1] end
    return table.concat(names, ", ", 1, n - 1) .. " and " .. names[n]
end

local function WhoUses(names, active)
    if active then
        return #names == 0 and "In use on this character" or "In use on this character and on " .. NameList(names)
    end
    return #names == 0 and "Not in use on any character" or "In use on " .. NameList(names)
end

local function Rule(frame, point)
    local rule = ns.Solid(frame, "ARTWORK", ns.THEME.line, 1)
    rule:SetPoint(point .. "LEFT")
    rule:SetPoint(point .. "RIGHT")
    ns.Hairline(rule, "h")
    return rule
end

-- The whole list of names behind "and N more".
local function WhoEnter(hit)
    local T = ns.THEME
    if not (hit.names and ns.Shared.Parts.Tip(hit, "ANCHOR_TOP")) then return end
    GameTooltip:SetText("Also in use on", 1, 1, 1)
    for _, name in ipairs(hit.names) do GameTooltip:AddLine(name, T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:Show()
end

local function WhoLeave()
    GameTooltip:Hide()
end

local function WhoLine(row, size)
    row.line = ns.Font(row, size, nil, ns.THEME.muted)
    row.line:SetJustifyH("LEFT")
    row.line:SetWordWrap(false)
    row.who = CreateFrame("Frame", nil, row)
    row.who:SetAllPoints(row.line)
    row.who:EnableMouse(true)
    row.who:SetScript("OnEnter", WhoEnter)
    row.who:SetScript("OnLeave", WhoLeave)
end

local function SetWho(row, names, active)
    row.line:SetText(WhoUses(names, active))
    row.who.names = #names > SHOWN_CHARS + 1 and names or nil
end

-- A button that cannot be used yet: dimmed, and deaf to the mouse.
local function SetUsable(button, on)
    button:SetAlpha(on and 1 or DIM)
    button:EnableMouse(on)
end

local function Paint(fs, color, alpha)
    fs:SetTextColor(color.r, color.g, color.b, alpha or 1)
end

-- Delete on the last profile stays dimmed and says why on hover.
local function SetDelete(button, alone)
    button.alone = alone
    button:SetAlpha(alone and DIM or 1)
    ns.Tooltip(button, alone and "The last profile cannot be deleted." or nil)
end

local function DeleteButton(row, h)
    local button = ns.Button(row, "Delete", ACTION_W, h, function()
        if not row.delete.alone then DeleteNamed(row.profile) end
    end)
    Paint(button.label, ns.Shared.Style.RED_RGB)
    return button
end

-------------------------------------------------------------------------------
--  A card's head: its name, a muted line, and a button or a link on the right
-------------------------------------------------------------------------------
local function HeadAction(head)
    if head.action then head.action(head.arg) end
end

local function HeadLinkClicked(link)
    HeadAction(link:GetParent())
end

local function NewHead(view)
    local T = ns.THEME
    local head = CreateFrame("Frame", nil, view)
    ns.Solid(head, "BACKGROUND", T.panel, 1):SetAllPoints()
    Rule(head, "BOTTOM")
    head.name = ns.Font(head, HEAD_SIZE, nil, T.fg)
    head.name:SetPoint("LEFT", INSET, 0)
    head.summary = ns.Font(head, SMALL_SIZE, nil, T.muted)
    head.summary:SetPoint("LEFT", head.name, "RIGHT", GAP + 4, 0)
    head.summary:SetJustifyH("LEFT")
    head.summary:SetWordWrap(false)
    head.button = ns.Button(head, "", NEW_W, SMALL_H, function() HeadAction(head) end)
    head.button:SetPoint("RIGHT", -INSET, 0)
    head.link = ns.Shared.Parts.Link(head, HeadLinkClicked)
    head.link:SetPoint("RIGHT", -INSET, 0)
    return head
end

-- asLink: the action as a link instead of a button; with no action, it rests muted.
local function SetHead(head, title, summary, actionText, action, arg, asLink)
    local T, Parts = ns.THEME, ns.Shared.Parts
    head.action, head.arg = action, arg
    head.name:SetText(title)
    head.summary:SetText(summary or "")
    head.button:SetShown(actionText ~= nil and not asLink)
    head.link:SetShown(actionText ~= nil and asLink == true)
    local right = head
    if actionText and asLink then
        Parts.SetLink(head.link, actionText)
        head.link.disabled = action == nil
        Parts.LinkColor(head.link, action and T.accentSoft or T.muted)
        right = head.link
    elseif actionText then
        ns.SetButtonText(head.button, actionText)
        right = head.button
    end
    head.summary:SetPoint("RIGHT", right, right == head and "RIGHT" or "LEFT", -INSET, 0)
    return HEAD_H
end

-------------------------------------------------------------------------------
--  Profiles: the one in use, then the others
-------------------------------------------------------------------------------
local function NewActive(view)
    local T = ns.THEME
    local row = CreateFrame("Frame", nil, view)
    row.mark = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.mark:SetPoint("TOPLEFT", INSET, -MARK_INSET)
    row.mark:SetPoint("BOTTOMLEFT", INSET, MARK_INSET)
    row.mark:SetWidth(MARK_W)
    row.name = ns.Font(row, ACTIVE_SIZE, nil, T.fg)
    row.name:SetPoint("BOTTOMLEFT", row, "LEFT", INSET + MARK_W + MARK_GAP, LINE_GAP / 2)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    WhoLine(row, LINE_SIZE)
    row.line:SetPoint("TOPLEFT", row, "LEFT", INSET + MARK_W + MARK_GAP, -LINE_GAP / 2)
    row.delete = DeleteButton(row, BUTTON_H)
    row.delete:SetPoint("RIGHT", -INSET, 0)
    row.copy = ns.Button(row, "Copy", ACTION_W, BUTTON_H, function() CopyNamed(row.profile) end)
    row.copy:SetPoint("RIGHT", row.delete, "LEFT", -GAP, 0)
    ns.Tooltip(row.copy, "Copy this profile into a new one and switch to it.")
    row.reset = ns.Button(row, "Reset", ACTION_W, BUTTON_H, function() ResetActive(row.profile) end)
    row.reset:SetPoint("RIGHT", row.copy, "LEFT", -GAP, 0)
    ns.Tooltip(row.reset, "Put every setting in this profile back to its default.")
    row.name:SetPoint("RIGHT", row.reset, "LEFT", -INSET, 0)
    row.line:SetPoint("RIGHT", row.reset, "LEFT", -INSET, 0)
    return row
end

local function SetActive(row, name, names, alone)
    row.profile = name
    row.name:SetText(name)
    SetWho(row, names, true)
    SetDelete(row.delete, alone)
    return ACTIVE_H
end

local function NewGroup(view)
    local row = CreateFrame("Frame", nil, view)
    Rule(row, "TOP")
    row.text = ns.Font(row, SMALL_SIZE, nil, ns.THEME.accentSoft)
    row.text:SetPoint("BOTTOMLEFT", INSET, LINE_GAP)
    return row
end

local function SetGroup(row, title)
    row.text:SetText(title)
    return GROUP_H
end

local function RowEnter(row)
    row.hover:Show()
end

local function RowLeave(row)
    if not row:IsMouseOver() then row.hover:Hide() end
end

local function PartEntered(part)
    RowEnter(part:GetParent())
end

local function PartLeft(part)
    RowLeave(part:GetParent())
end

local function NewProfileRow(view)
    local T = ns.THEME
    local row = CreateFrame("Frame", nil, view)
    ns.Shared.Parts.RowBands(row, INSET)
    row.name = ns.Font(row, NAME_SIZE, nil, T.fg)
    row.name:SetPoint("BOTTOMLEFT", row, "LEFT", INSET, LINE_GAP / 2 - 1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    WhoLine(row, SMALL_SIZE)
    row.line:SetPoint("TOPLEFT", row, "LEFT", INSET, -LINE_GAP / 2 + 1)
    row.delete = DeleteButton(row, SMALL_H)
    row.delete:SetPoint("RIGHT", -INSET, 0)
    row.copy = ns.Button(row, "Copy", ACTION_W, SMALL_H, function() CopyNamed(row.profile) end)
    row.copy:SetPoint("RIGHT", row.delete, "LEFT", -GAP, 0)
    row.use = ns.AccentBorder(ns.Button(row, "Use", ACTION_W, SMALL_H, function() UseNamed(row.profile) end))
    row.use:SetPoint("RIGHT", row.copy, "LEFT", -GAP, 0)
    for _, part in ipairs({ row.delete, row.copy, row.use, row.who }) do
        part:HookScript("OnEnter", PartEntered)
        part:HookScript("OnLeave", PartLeft)
    end
    row.name:SetPoint("RIGHT", row.use, "LEFT", -INSET, 0)
    row.line:SetPoint("RIGHT", row.use, "LEFT", -INSET, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

local function SetProfileRow(row, name, names, striped)
    row.profile = name
    row.stripe:SetShown(striped)
    row.hover:Hide()
    row.name:SetText(name)
    SetWho(row, names, false)
    SetDelete(row.delete, false)
    return PROFILE_H
end

-------------------------------------------------------------------------------
--  Share: a tile per part, then the summary and the button
-------------------------------------------------------------------------------
local function PickAll(view)
    local all = true
    for _, part in ipairs(PARTS) do
        if view.status[part.key] == "ready" and not Ticked(part.key) then all = false end
    end
    for _, part in ipairs(PARTS) do wanted[part.key] = not all end
    view:Redraw()
end

local function Pick(tile, on)
    if not tile.ready then return end
    wanted[tile.key] = on
    tile:GetParent():Redraw()
end

local function TileClicked(tile)
    Pick(tile, not Ticked(tile.key))
end

local function TileEnter(tile)
    local T = ns.THEME
    if tile.ready then tile.edge:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end
    if not ns.Shared.Parts.Tip(tile, "ANCHOR_TOP") then return end
    GameTooltip:SetText(tile.name:GetText(), 1, 1, 1)
    GameTooltip:AddLine(tile.tip, T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function TileLeave(tile)
    local c = ns.Shared.Style.BORDER_RGB
    tile.edge:SetColor(c.r, c.g, c.b, 1)
    GameTooltip:Hide()
end

local function NewTile(view)
    local T, St = ns.THEME, ns.Shared.Style
    local tile = CreateFrame("Button", nil, view)
    ns.Solid(tile, "BACKGROUND", T.fg, St.CARD_FILL):SetAllPoints()
    tile.edge = ns.Border(tile, St.BORDER_RGB)
    tile.switch = UI.BuildToggleControl(tile, nil, function() return tile.ready and Ticked(tile.key) end,
        function(on) Pick(tile, on) end)
    tile.switch:SetPoint("LEFT", TILE_PAD, 0)
    tile.name = ns.Font(tile, NAME_SIZE, nil, T.fg)
    tile.name:SetPoint("BOTTOMLEFT", tile.switch, "RIGHT", TILE_GAP, 1)
    tile.name:SetPoint("RIGHT", -TILE_PAD, 0)
    tile.name:SetJustifyH("LEFT")
    tile.name:SetWordWrap(false)
    tile.detail = ns.Font(tile, SMALL_SIZE, nil, T.muted)
    tile.detail:SetPoint("TOPLEFT", tile.switch, "RIGHT", TILE_GAP, -3)
    tile.detail:SetPoint("RIGHT", -TILE_PAD, 0)
    tile.detail:SetJustifyH("LEFT")
    tile.detail:SetWordWrap(false)
    tile:SetScript("OnClick", TileClicked)
    tile:SetScript("OnEnter", TileEnter)
    tile:SetScript("OnLeave", TileLeave)
    return tile
end

-- Ready: its switch on while it goes in. Empty or from a pack: dimmed, its switch off and still.
local function SetTile(tile, part, state, detail)
    local T, St = ns.THEME, ns.Shared.Style
    tile.key, tile.ready = part.key, state == "ready"
    tile.name:SetText(part.label)
    Paint(tile.name, T.fg, tile.ready and 1 or DIM)
    if state == "pack" then
        tile.detail:SetText("From a pack")
        Paint(tile.detail, St.WARN_RGB)
        tile.tip = "Came with a pack, so it stays with the pack's author."
    else
        tile.detail:SetText(state == "empty" and "Nothing saved yet" or detail or (part.share:gsub("%.$", "")))
        Paint(tile.detail, T.muted, tile.ready and 1 or DIM)
        tile.tip = part.share
    end
    tile.switch._refreshValue()
    SetUsable(tile.switch, tile.ready)
    return TILE_H
end

local function Send()
    local ticks = {}
    for _, part in ipairs(PARTS) do ticks[part.key] = Ticked(part.key) or nil end
    ns.ShowProfileExport(ticks)
end

local function NewSend(view)
    local row = CreateFrame("Frame", nil, view)
    Rule(row, "TOP")
    row.count = ns.Font(row, LINE_SIZE, nil, ns.THEME.muted)
    row.count:SetPoint("LEFT", INSET, 0)
    row.send = ns.AccentBorder(ns.Button(row, "Export", BUTTON_W, BUTTON_H, Send))
    row.send:SetPoint("RIGHT", -INSET, 0)
    row.count:SetPoint("RIGHT", row.send, "LEFT", -INSET, 0)
    row.count:SetJustifyH("LEFT")
    return row
end

local function SetSend(row, count, ready)
    row.count:SetText(count > 0 and ("%d of %d parts of %s go in the string."):format(count, ready,
        ns.ActiveProfileName() or "?") or "Pick a part to share.")
    SetUsable(row.send, count > 0)
    return SEND_H
end

-------------------------------------------------------------------------------
--  Import: a paste box, and the button that takes what is in it to the import
-------------------------------------------------------------------------------
local function Typed(box)
    local has = box:GetText():find("%S") ~= nil
    box.hint:SetShown(not has)
    SetUsable(box.go, has)
end

local function TakeIn(box)
    local text = box:GetText()
    box:SetText("")
    box:ClearFocus()
    Typed(box)
    ns.ShowProfileImport(text)
end

local function NewPaste(view)
    local T, St = ns.THEME, ns.Shared.Style
    local row = CreateFrame("Frame", nil, view)
    local field = CreateFrame("Frame", nil, row)
    field:SetPoint("TOPLEFT", INSET, -INSET)
    field:SetPoint("TOPRIGHT", -INSET, -INSET)
    field:SetHeight(FIELD_H)
    ns.Solid(field, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(field, St.BORDER_RGB)
    local scroll = UI.SlimScroll(field)
    scroll:SetPoint("TOPLEFT", 1, -1)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_ROOM, 1)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFont(ns.UIFontPath(), FIELD_TEXT, "")
    box:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    box:SetTextInsets(FIELD_INSET_X, FIELD_INSET_X, FIELD_INSET_Y, FIELD_INSET_Y)
    -- A multiline box is as tall as its text, so an empty one would take no clicks.
    box:SetHeight(FIELD_H - 2)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", Typed)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(_, w) box:SetWidth(w) end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    box.hint = ns.Font(field, FIELD_TEXT, nil, T.muted)
    box.hint:SetPoint("TOPLEFT", FIELD_INSET_X + 1, -(FIELD_INSET_Y + 1))
    box.hint:SetText("Paste a profile, macro, talent build or BiS list string here.")
    box.go = ns.AccentBorder(ns.Button(row, "Import", BUTTON_W, BUTTON_H, function() TakeIn(box) end))
    box.go:SetPoint("TOPRIGHT", field, "BOTTOMRIGHT", 0, -IMPORT_GAP)
    local note = ns.Font(row, SMALL_SIZE, nil, T.muted)
    note:SetPoint("LEFT", field, "BOTTOMLEFT", 0, -(IMPORT_GAP + BUTTON_H / 2))
    note:SetPoint("RIGHT", box.go, "LEFT", -INSET, 0)
    note:SetJustifyH("LEFT")
    note:SetText("You see what it holds and pick the parts before anything changes.")
    row.box = box
    Typed(box)
    return row
end

local function SetPaste()
    return INSET + FIELD_H + IMPORT_GAP + BUTTON_H + INSET
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
local kinds
local Draw = {}

function Draw:BeginCard()
    self.left, self.width = 0, self:GetWidth()
    local card = self:Acquire("card")
    card:SetFrameLevel(self:GetFrameLevel())
    return card
end

function Draw:EndCard(card)
    card:SetHeight(self.cursor - card.top)
    self:Space(ns.Shared.Style.CARD_GAP)
end

function Draw:Tiles()
    local w = self:GetWidth() - INSET * 2
    local columns = self:GetWidth() >= TWO_COLUMNS_W and 2 or 1
    local tileW = math.floor((w - GAP * (columns - 1)) / columns)
    local top = self.cursor + INSET
    for i, part in ipairs(PARTS) do
        local column = (i - 1) % columns
        if column == 0 and i > 1 then top = top + TILE_H + GAP end
        self.cursor = top
        self.left = INSET + column * (tileW + GAP)
        self.width = column == columns - 1 and w - column * (tileW + GAP) or tileW
        self:Add("part", part, self.status[part.key], self.details[part.key])
    end
    self.cursor = top + TILE_H + INSET
    self.left, self.width = 0, self:GetWidth()
end

function Draw:Redraw()
    self:Clear()
    local order, by = ns.ListProfiles(), Characters()
    local active = ns.ActiveProfileName()

    local card = self:BeginCard()
    self:Add("head", "Profiles", #order == 1 and "1 profile on this account" or (#order .. " profiles on this account"),
        "New Profile", NewProfile)
    self:Add("active", active, by[active] or {}, #order == 1)
    if #order > 1 then
        self:Add("group", "OTHER PROFILES")
        local n = 0
        for _, name in ipairs(order) do
            if name ~= active then
                n = n + 1
                self:Add("profile", name, by[name] or {}, n % 2 == 0)
            end
        end
    end
    self:EndCard(card)

    local count, ready = 0, 0
    for _, part in ipairs(PARTS) do
        if self.status[part.key] == "ready" then
            ready = ready + 1
            if Ticked(part.key) then count = count + 1 end
        end
    end
    card = self:BeginCard()
    self:Add("head", "Share", "Pick what goes in the string you give someone.",
        count < ready and "Pick All" or "Pick None", ready > 0 and PickAll or nil, self, true)
    self:Tiles()
    self:Add("send", count, ready)
    self:EndCard(card)

    card = self:BeginCard()
    self:Add("head", "Import", "Profiles, Forge macros, talent builds, BiS lists and Smart Reminders packs.")
    self:Add("paste")
    self:EndCard(card)
    self:Fit({})
end

local function Kinds()
    if kinds then return kinds end
    kinds = ns.Shared.View.NewKinds()
    kinds.head = { New = NewHead, Set = SetHead }
    kinds.active = { New = NewActive, Set = SetActive }
    kinds.group = { New = NewGroup, Set = SetGroup }
    kinds.profile = { New = NewProfileRow, Set = SetProfileRow }
    kinds.part = { New = NewTile, Set = SetTile }
    kinds.send = { New = NewSend, Set = SetSend }
    kinds.paste = { New = NewPaste, Set = SetPaste }
    return kinds
end

function ns.BuildProfileSettings(parent, y)
    local view = parent.profilesView
    if not view then
        view = ns.Shared.View.New(parent, Kinds(), Draw)
        parent.profilesView = view
    end
    local all = Collect()
    local sr = ns.SettingsRoot().tankReminder
    local packed = type(sr) == "table" and type(sr.importedPack) == "table"
    view.status, view.details = {}, {}
    for _, part in ipairs(PARTS) do
        view.status[part.key] = all[part.key] and "ready"
            or packed and part.key == "smartReminders" and "pack" or "empty"
    end
    for _, part in ipairs(ns.ProfileStringParts({ parts = all })) do view.details[part.key] = part.detail end
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, y - UI.CONTENT_PAD / 2)
    view:SetWidth(math.max(1, parent:GetWidth() - UI.CONTENT_PAD * 2))
    view:Show()
    view:Redraw()
    return y - view:GetHeight() - UI.CONTENT_PAD
end
