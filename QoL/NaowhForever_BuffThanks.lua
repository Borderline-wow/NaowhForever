-------------------------------------------------------------------------------
--  NaowhForever_BuffThanks.lua -- the QoL Buff Thank You Message: a whisper of thanks when
--  another player gives you a class buff in the open world. The game only names a caster
--  who has a nameplate, is your target or mouseover, or is in your group; for anyone else,
--  an optional /emote instead (an addon may not /say outside instances).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local Parts = ns.Shared.Parts

-- Every rank and group version of each class buff another player can give you (Wowhead
-- Forever). Kept here, not read from Auras & Buffs: that module can be turned off. Each
-- family has its own lines under Lines Per Buff, in the setting named by key.
local FAMILIES = {
    { key = "buffThanksIntellect", label = "Intellect Lines", what = "Arcane Intellect and Brilliance",
      ids = { 10157, 10156, 1461, 1460, 1459, 23028 } },
    { key = "buffThanksStamina", label = "Fortitude Lines", what = "Power Word: Fortitude and its Prayer",
      ids = { 10938, 10937, 2791, 1245, 1244, 1243, 21564, 21562 } },
    { key = "buffThanksSpirit", label = "Spirit Lines", what = "Divine Spirit and its Prayer",
      ids = { 27841, 14819, 14818, 14752, 27681 } },
    { key = "buffThanksShadow", label = "Shadow Protection Lines", what = "Shadow Protection and its Prayer",
      ids = { 976, 10957, 10958, 27683 } },
    { key = "buffThanksWild", label = "Wild Lines", what = "Mark and Gift of the Wild",
      ids = { 9885, 9884, 8907, 5234, 6756, 5232, 1126, 21850, 21849 } },
    { key = "buffThanksThorns", label = "Thorns Lines", what = "Thorns",
      ids = { 467, 782, 1075, 8914, 9756, 9910 } },
    { key = "buffThanksBlessing", label = "Blessing Lines", what = "every Paladin blessing",
      ids = { 25291, 19838, 19837, 19836, 19835, 19834, 19740, 25916, 25782,    -- Might
          25290, 19854, 19853, 19852, 19850, 19742, 25918, 25894,               -- Wisdom
          20217, 25898, 1038, 25895, 19979, 19978, 19977, 25890,                -- Kings, Salvation, Light
          1022, 5599, 10278, 1044, 6940, 20729 } },                             -- Protection, Freedom, Sacrifice
}

-- The rest, always on the Whisper Lines.
local OTHERS = {
    1008, 8455, 10169, 10170,               -- Amplify Magic
    604, 8450, 8451, 10173, 10174,          -- Dampen Magic
    6346, 10060, 1706,                      -- Fear Ward, Power Infusion, Levitate
    29166,                                  -- Innervate
    5697, 132, 2970, 11743,                 -- Unending Breath, Detect Invisibility
    131, 546,                               -- Water Breathing, Water Walking
}

-- Other players decide when this speaks, so a crowd buffing you gets a few thanks, not a flood.
local SENT_MAX, SENT_WINDOW = 3, 60

local OPTIONS_WINDOW = "NaowhForeverOptions"
local EDITOR_INSET = 6      -- the lines' gap to the editor's edge
local EDGE = { r = 0, g = 0, b = 0 }    -- an input box's 1px black edge

local buffs                 -- spell ID -> its family's setting, or true; built on first enable
local thanked = {}          -- caster GUID (or name), or "?" .. buff for the emote, -> GetTime() of the last thanks
local windowAt, sentCount = 0, 0
local editor, editKey

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function On()
    return S.Get("enabled") and S.Get("buffThanks")
end

-- One of the setting's lines at random, with {buff} and {name} filled in; nil when it has none.
local function Line(key, buff, name)
    local lines = {}
    for line in S.Get(key):gmatch("[^\n]+") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    if #lines == 0 then return nil end
    local text = lines[math.random(#lines)]:gsub("{buff}", function() return buff end)
    return (text:gsub("{name}", function() return name end))
end

-- True, and marked, when key was not thanked within the cooldown. Entries past it are dropped.
local function Due(key)
    local now, wait = GetTime(), S.Get("buffThanksCooldown") * 60
    for k, at in pairs(thanked) do
        if now - at >= wait then thanked[k] = nil end
    end
    if thanked[key] then return false end
    thanked[key] = now
    return true
end

-- True while this minute's thanks are not used up.
local function Room(now)
    if now - windowAt >= SENT_WINDOW then windowAt, sentCount = now, 0 end
    return sentCount < SENT_MAX
end

local function Send(text, channel, to)
    sentCount = sentCount + 1
    C_ChatInfo.SendChatMessage(text, channel, nil, to)
end

local function Thank(aura)
    local unit, id = aura.sourceUnit, aura.spellId
    if Secret(unit) or Secret(id) or not buffs[id] or not Room(GetTime()) then return end
    local buff = aura.name
    if unit then
        if UnitIsUnit(unit, "player") or not UnitIsPlayer(unit) then return end
        if not S.Get("buffThanksGroup") and (UnitInParty(unit) or UnitInRaid(unit)) then return end
        local name, guid = GetUnitName(unit, true), UnitGUID(unit)
        -- Forever's first names are not unique: two players called the same each get their thanks.
        if not name or not Due(guid and not Secret(guid) and guid or name) then return end
        local short, family = Ambiguate(name, "short"), buffs[id]
        local text = S.Get("buffThanksPerBuff") and family ~= true and Line(family, buff, short)
            or Line("buffThanksText", buff, short)
        if text then Send(text, "WHISPER", name) end
    elseif S.Get("buffThanksEmote") and Due("?" .. buff) then
        local text = Line("buffThanksEmoteText", buff, "stranger")
        if text then Send(text, "EMOTE") end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, _, info)
    if not (info and info.addedAuras) or C_Secrets.ShouldAurasBeSecret() then return end
    if UnitAffectingCombat("player") or IsInInstance() or C_ChatInfo.InChatMessagingLockdown() then return end
    for _, aura in ipairs(info.addedAuras) do
        if aura.isHelpful then Thank(aura) end
    end
end)

-- Runs on every options change too; who was thanked is kept until the feature is turned off.
local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        wipe(thanked)
        return
    end
    if not buffs then
        buffs = {}
        for _, family in ipairs(FAMILIES) do
            for _, id in ipairs(family.ids) do buffs[id] = family.key end
        end
        for _, id in ipairs(OTHERS) do buffs[id] = true end
    end
    events:RegisterUnitEvent("UNIT_AURA", "player")
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "buffThanks" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  The line editor: a side panel beside the options window, one message per line.
-------------------------------------------------------------------------------
-- The box fills the scroll area down to the buttons, and grows past it with the lines.
local function FitEditor()
    if not editor then return end
    local view = editor.view
    view:SetHeight(math.max(editor.scroll:GetHeight(), view.box:GetHeight()))
end

-- Keeps the line being typed in sight.
local function FollowCursor(_, _, y, _, h)
    local scroll = editor.scroll
    local top, shown, offset = -y, scroll:GetHeight(), scroll:GetVerticalScroll()
    if top < offset then
        scroll:SetVerticalScroll(top)
    elseif top + h > offset + shown then
        scroll:SetVerticalScroll(top + h - shown)
    end
end

local function NewEditorView(scroll)
    local view = CreateFrame("Frame", nil, scroll)
    ns.Solid(view, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(view, EDGE)
    local box = CreateFrame("EditBox", nil, view)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(EDITOR_INSET, EDITOR_INSET, EDITOR_INSET, EDITOR_INSET)
    box:SetPoint("TOPLEFT")
    box:SetPoint("TOPRIGHT")
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnCursorChanged", FollowCursor)
    box:SetScript("OnSizeChanged", FitEditor)
    -- A click below the last line puts the cursor at the end.
    view:EnableMouse(true)
    view:SetScript("OnMouseDown", function()
        box:SetFocus()
        box:SetCursorPosition(#box:GetText())
    end)
    view.box = box
    return view
end

local function Opaque()
    return 1
end

local function SaveLines()
    S.Set(editKey, editor.view.box:GetText())
    editor:Hide()
end

local function EditLines(key, title)
    if not editor then
        editor = Parts.SidePanel({ { "Save", SaveLines }, { "Cancel", function() editor:Hide() end } },
            NewEditorView, Opaque)
        editor.scroll:HookScript("OnSizeChanged", FitEditor)
    end
    editKey = key
    editor.title:SetText(title)
    editor.view.box:SetText(S.Get(key))
    Parts.ShowBeside(editor, _G[OPTIONS_WINDOW])
    -- ShowBeside sets the height once; its bottom tied to the window's too, it follows a resize.
    local point, owner, relative, x = editor:GetPoint(1)
    editor:SetPoint(point == "TOPLEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT", owner,
        relative == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT", x, 0)
    FitEditor()
    editor.view.box:SetFocus()
end

local Group = ns.Shared.Settings.Group

local function PerBuffOff()
    return not S.Get("buffThanksPerBuff")
end

local rows = {
    { key = "buffThanksText", label = "Whisper Lines", buttonText = "Edit",
      button = function() EditLines("buffThanksText", "Whisper Lines") end,
      help = "One whisper per line, picked at random; {buff} and {name} are filled in." },
    { key = "buffThanksCooldown", label = "Once Per Player Every", slider = { 1, 60, 1 }, unit = "m",
      help = "The shortest time between two thanks to the same player." },
    { key = "buffThanksGroup", label = "Thank Group Members", toggle = true,
      help = "Also thanks players in your party or raid." },
    { key = "buffThanksPerBuff", label = "Lines Per Buff", toggle = true,
      help = "Own lines for the buffs below; one left empty uses the Whisper Lines." },
}
for _, family in ipairs(FAMILIES) do
    rows[#rows + 1] = { key = family.key, label = family.label, buttonText = "Edit", hidden = PerBuffOff,
        button = function() EditLines(family.key, family.label) end,
        help = "Whispers for " .. family.what .. "." }
end
rows[#rows + 1] = Group("Unknown Casters")
rows[#rows + 1] = { key = "buffThanksEmote", label = "Thank With an Emote", toggle = true,
    help = "An /emote of thanks when the game cannot name the caster." }
rows[#rows + 1] = { key = "buffThanksEmoteText", label = "Emote Lines", buttonText = "Edit", needs = "buffThanksEmote",
    button = function() EditLines("buffThanksEmoteText", "Emote Lines") end,
    help = "One emote per line, after your name, picked at random; {buff} is filled in." }

ns.Shared.Settings.Page("QoL/Questing & Group", S):Card({
    id = "buffThanks", name = "Buff Thank You Message", order = 40, switch = "buffThanks",
    help = "Whispers thanks when a player gives you a class buff in the open world; turn friendly "
        .. "nameplates on so the game can name them.",
    rows = rows,
})
