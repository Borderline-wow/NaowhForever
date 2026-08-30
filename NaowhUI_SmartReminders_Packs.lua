-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Packs.lua -- shareable Reminder Packs.
--
--  A pack is a curator's judgment as data: priority lists per spec, per-boss
--  orders, callout lines, tank-buster marks, mutes, and authored reminders,
--  in one paste-able string. The wire format is EllesmereUI's own profile
--  machinery (serializer + LibDeflate + print encoding) under a distinct
--  prefix, so a pack can never be mistaken for a profile string or vice
--  versa.
--
--  Import rules that make this fit to charge money for:
--    * PREVIEW FIRST. A string decodes to a description -- name, author,
--      version, what is inside, counts -- before anything applies.
--    * NEVER PARTIAL. The payload is validated and staged whole; a bad
--      string is refused outright rather than half-applied.
--    * MERGE OR REPLACE is the importer's explicit choice. Merge keeps the
--      player's own entries where the pack has none; replace makes the
--      player's copy match the pack for every section the pack carries.
--
--  There is deliberately no license check, expiry, or key. A string is text
--  and always will be; what a subscription buys is the next version. The
--  version field on the preview is what makes that model legible.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

local PREFIX = "NSRPACK1:"
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

local function Codec()
    local EUI = _G.EllesmereUI
    local Ser = EUI and EUI._Serializer
    local LD = LibStub and LibStub("LibDeflate", true)
    if Ser and Ser.Serialize and Ser.Deserialize and LD then return Ser, LD end
    return nil
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

function ns.ExportPack(packName, author)
    local Ser, LD = Codec()
    if not Ser then return nil, "EllesmereUI's serializer is not available." end

    local db = ns.DB()
    local data, any = {}, false
    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local t = db[sec.field]
        if type(t) == "table" and next(t) ~= nil then
            data[sec.field] = Copy(t)
            any = true
        end
    end
    if not any then return nil, "There is nothing to export yet." end

    -- Carried but never required: an importer on defaults keeps their own.
    data.leadTime = db.leadTime
    data.voiceNone = db.voiceNone

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

-- Decode and validate; returns the payload plus a human description, or nil
-- and a reason. Applies nothing.
function ns.DecodePack(str)
    local Ser, LD = Codec()
    if not Ser then return nil, "EllesmereUI's serializer is not available." end
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
    if type(payload.data) ~= "table" then return nil, "The pack is empty." end

    local parts = {}
    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local n = CountSection(sec.count, payload.data[sec.field])
        if n > 0 then parts[#parts + 1] = ("%d %s"):format(n, sec.label) end
    end
    if #parts == 0 then return nil, "The pack is empty." end

    local desc = ("|cffF0A830%s|r by %s%s|n%s"):format(
        tostring(payload.name), tostring(payload.author),
        payload.made ~= "" and (" (" .. payload.made .. ")") or "",
        table.concat(parts, ", "))
    return payload, desc
end

-- Apply a decoded payload. mode "replace": every section the pack carries
-- overwrites the local one. mode "merge": pack entries win per key, local
-- entries the pack lacks survive. Either way the write happens LAST, after
-- everything staged cleanly, so a failure cannot leave a half-applied pack.
function ns.ApplyPack(payload, mode)
    if type(payload) ~= "table" or type(payload.data) ~= "table" then return false end
    local db = ns.DB()

    local staged = {}
    for i = 1, #SECTIONS do
        local sec = SECTIONS[i]
        local incoming = payload.data[sec.field]
        if type(incoming) == "table" then
            if mode == "merge" and type(db[sec.field]) == "table" then
                local merged = Copy(db[sec.field])
                for k, v in pairs(incoming) do merged[k] = Copy(v) end
                staged[sec.field] = merged
            else
                staged[sec.field] = Copy(incoming)
            end
        end
    end

    for field, value in pairs(staged) do db[field] = value end
    if type(payload.data.leadTime) == "number" and mode ~= "merge" then
        db.leadTime = payload.data.leadTime
    end
    if type(payload.data.voiceNone) == "string" and payload.data.voiceNone ~= ""
        and mode ~= "merge" then
        db.voiceNone = payload.data.voiceNone
    end

    ns.RefreshRuntime()
    return true
end

-------------------------------------------------------------------------------
--  The two modals. Both are the house modal shell with a multiline box; the
--  difference is direction. Neither touches settings until Apply.
-------------------------------------------------------------------------------
local function MakePackBox(panel, topOffset, height)
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
    local dimmer, panel = ns.MakeModal(560, 330, "packExport")
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

    local box = MakePackBox(panel, -78, 180)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOM", panel, "BOTTOM", 0, 46)

    local function Regenerate()
        local str, err = ns.ExportPack(nameBox:GetText(), UnitName and UnitName("player"))
        if str then
            box:SetText(str)
            status:SetText(("%d characters. Click the text, then Ctrl+A Ctrl+C."):format(#str))
        else
            box:SetText("")
            status:SetText("|cffff6060" .. tostring(err) .. "|r")
        end
    end
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- The string is display-only: retyping into it produces nothing valid, so
    -- any edit just regenerates from the real settings.
    box:SetScript("OnTextChanged", function(_, user) if user then Regenerate() end end)
    nameBox:SetScript("OnTextChanged", function(_, user) if user then Regenerate() end end)

    ns.Button(panel, "Close", 110, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)

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

        local box = MakePackBox(panel, -56, 300)
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
    local dimmer, panel = ns.MakeModal(560, 330, "packImport")
    local title = ns.Font(panel, 14, "OUTLINE")
    title:SetPoint("TOP", panel, "TOP", 0, -14)
    title:SetText("Import Profile")

    local box = MakePackBox(panel, -40, 150)
    local preview = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -200)
    preview:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -200)
    preview:SetJustifyH("LEFT")
    preview:SetText("Paste a pack string above.")

    local decoded
    local applyBtn, mergeBtn

    local function Revalidate()
        local payload, descOrErr = ns.DecodePack(box:GetText())
        decoded = payload
        if payload then
            preview:SetText(descOrErr)
        else
            preview:SetText("|cffff6060" .. tostring(descOrErr) .. "|r")
        end
        local on = payload ~= nil
        for _, b in ipairs({ applyBtn, mergeBtn }) do
            if b then
                if on then b:Enable(); b:SetAlpha(1) else b:Disable(); b:SetAlpha(0.35) end
            end
        end
    end
    box:SetScript("OnTextChanged", function(_, user) if user then Revalidate() end end)

    local function Finish(mode)
        if not decoded then return end
        if ns.ApplyPack(decoded, mode) then
            ns.Print(("pack applied (%s)."):format(mode))
            dimmer:Hide()
            local EUI = ns.UI
            if EUI and EUI.RefreshPage then EUI:RefreshPage(true) end
        else
            preview:SetText("|cffff6060The pack could not be applied.|r")
        end
    end

    -- Replace makes you match the curator; merge keeps your own entries where
    -- the pack has none. Both stated on the buttons rather than in a manual.
    applyBtn = ns.Button(panel, "Replace Mine", 130, 26, function() Finish("replace") end)
    applyBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 100, 14)
    mergeBtn = ns.Button(panel, "Merge Into Mine", 130, 26, function() Finish("merge") end)
    mergeBtn:SetPoint("BOTTOM", panel, "BOTTOM", 60, 14)
    ns.Button(panel, "Cancel", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14)

    packImport = { dimmer = dimmer, box = box, Revalidate = Revalidate }
    Revalidate()
    dimmer:Show()
    -- Focused on open: the only thing anyone does with this dialog is paste.
    box:SetFocus()
end
