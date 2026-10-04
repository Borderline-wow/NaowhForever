-------------------------------------------------------------------------------
--  NaowhForever_MacroWindow.lua -- Naowh's Forge, the Macros module's own window (/nfmacros).
--  My Macros: your account and character macros, and your pack's, in a list; the one you pick
--  in the editor, with its size against the game's 255 bytes, the lines that will not work
--  and, beside it, what it does in plain words, a condition builder, the commands, and icons.
--  Smart Macros: the macros the module keeps up to date, with what each will use right now.
--  Library: by class, the macros you saved to it from the editor and those your profile pack brings.
--  Built the first time it opens.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local S = ns.MacroSettings
local Text = ns.MacroText
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local NAME = "Naowh's Forge"
local PAGE = "Macros/Settings"   -- its options page, opened from the logo and the footer
local WIDTH, HEIGHT = 1100, 720
local HEADER, FOOTER = St.WINDOW_HEADER, St.WINDOW_FOOTER
local CARD_INSET, GAP = 6, 6
local TOOL_GAP = 10
local TOP = HEADER + TOOL_GAP + St.TAB_H + TOOL_GAP
local SWITCH_W, SEARCH_W = 330, 240
local LIST_W, INSPECTOR_W, CLASS_W = 270, 320, 200
local PAD = 14             -- a card's edge to what is in it
local ROW_H, ROW_ICON = 42, 30
local SECTION_H = St.SECTION_H
local BLACK = St.BORDER_RGB
local STRIPE, HOVER, PICKED = St.STRIPE, 0.05, 0.10
local SELECTED_BAR = 2
local BIG_ICON = 56
local CODE_FONT = "Interface\\AddOns\\NaowhForever\\Media\\Fonts\\JetBrainsMonoNL-Regular.ttf"
local CODE_SIZE = 13
local CODE_LINES = 10      -- lines the editor shows; a macro rarely needs more
local GUTTER_W = 30
local METER_H = 6
local BUTTON_H = 26
local ISSUE_LINES = 4
local QUESTION = 134400    -- the question mark: #showtooltip then shows the spell
local WARN = { r = 0.94, g = 0.70, b = 0.29 }
local ERR = { r = 0.97, g = 0.44, b = 0.44 }
local OK = { r = 0.30, g = 0.82, b = 0.48 }
local METER_W = 54         -- the slot meters beside the subtitle
local GOLD_CODE = St.GOLD_CODE
local CARD_COLS, CARD_GAP = 3, 10
local SMART_H, LIB_H = 150, 168
local ICON_COLS, ICON_ROWS, ICON_SIZE, ICON_GAP = 7, 6, 36, 6
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local window, tab = nil, "mine"
local draft            -- the macro in the editor: { index, account, name, icon, body, saved, source }
local libClass

-------------------------------------------------------------------------------
--  Small parts
-------------------------------------------------------------------------------
local function Text14(parent, size, color)
    local fs = ns.Font(parent, size or 13, nil, color)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.85)
    return fs
end

local function Paint(fs, c) fs:SetTextColor(c.r, c.g, c.b, 1) end

-- A pool of one kind of row: Take hands out the next one, Release hides them all again.
local function Pool(make)
    local pool = { list = {}, used = 0 }
    function pool.Take()
        pool.used = pool.used + 1
        local f = pool.list[pool.used]
        if not f then
            f = make()
            pool.list[pool.used] = f
        end
        f:ClearAllPoints()
        f:Show()
        return f
    end
    function pool.Release()
        for i = 1, #pool.list do pool.list[i]:Hide() end
        pool.used = 0
    end
    return pool
end

-- An icon in the house's black edge, trimmed of the art's own border.
local function Icon(parent, size)
    local edge = parent:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(0, 0, 0, 1)
    edge:SetSize(size + 2, size + 2)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(icon, 1, edge)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.edge = edge
    return icon
end

-- A section title as every page draws it, with a muted count and a note on the right.
local function NewSection(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(SECTION_H)
    h.title = Text14(h, 12, T.accentSoft)
    h.title:SetPoint("BOTTOMLEFT", PAD, 5)
    h.note = Text14(h, 11, T.muted)
    h.note:SetPoint("BOTTOMRIGHT", -PAD, 5)
    local rule = ns.Solid(h, "ARTWORK", T.line, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    ns.Hairline(rule, "h")
    return h
end

local function SetSection(h, title, count, note)
    h.title:SetText(title:upper() .. (count and note and ("   " .. ns.Color("muted", count)) or ""))
    h.note:SetText(note or count or "")
end

-- The banded list rows of the Journal: a faint band on every other row, a soft one under the
-- mouse, and an accent edge on the picked one.
local function ListRow(b)
    b.stripe = ns.Solid(b, "BACKGROUND", T.fg, STRIPE)
    b.stripe:SetAllPoints()
    b.band = ns.Solid(b, "BACKGROUND", T.fg, 1)
    b.band:SetAllPoints()
    b.band:SetAlpha(0)
    b.bar = ns.Solid(b, "ARTWORK", T.accent, 1)
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(SELECTED_BAR)
    b:SetScript("OnEnter", function(self) if not self.picked then self.band:SetAlpha(HOVER) end end)
    b:SetScript("OnLeave", function(self) if not self.picked then self.band:SetAlpha(0) end end)
end

local function Pick(b, picked)
    b.picked = picked
    b.bar:SetShown(picked)
    b.band:SetAlpha(picked and PICKED or 0)
end

local function Toast(text) ns.Print(text) end

-------------------------------------------------------------------------------
--  The game's macros
-------------------------------------------------------------------------------
local function Limits()
    return Constants.MacroConsts.MAX_ACCOUNT_MACROS, Constants.MacroConsts.MAX_CHARACTER_MACROS
end

-- The icon a body would show: the spell or item #showtooltip names, else the first cast or use.
local function BodyIcon(body)
    local item = body:match("item:(%d+)")
    if item then return C_Item.GetItemIconByID(tonumber(item)) or QUESTION end
    local named = body:match("#showtooltip%s+([^\n]+)") or body:match("/cast%s+%[[^\n]-%]%s*([^;\n%[]+)")
        or body:match("/cast%s+([^;\n%[]+)")
    named = named and strtrim(named)
    if named and named ~= "" and not named:find("^%d+$") then
        return C_Spell.GetSpellTexture(named) or C_Item.GetItemIconByID(named) or QUESTION
    end
    local used = body:match("/use%s+%[?[^\n]-%]?%s*([^;\n%[%]]+)")
    used = used and strtrim(used)
    return used and used ~= "" and not used:find("^%d+$") and C_Item.GetItemIconByID(used) or QUESTION
end

-- The icon a macro shows: its own, or for a question mark what #showtooltip shows.
local function ShownIcon(index, icon, body)
    if icon and icon ~= QUESTION then return icon end
    local spell = index and GetMacroSpell(index)
    if spell then return C_Spell.GetSpellTexture(spell) or QUESTION end
    return BodyIcon(body or "")
end

-- Account macros, then this character's: { index, account, name, icon, body }.
local function GameMacros()
    local maxAccount, maxCharacter = Limits()
    local list = {}
    for index = 1, maxAccount + maxCharacter do
        local name, icon, body = GetMacroInfo(index)
        if name then
            list[#list + 1] = { index = index, account = index <= maxAccount, name = name, icon = icon,
                body = body or "" }
        end
    end
    return list
end

-- Where a macro is once saved: the game sorts by name, so its index moves on a rename.
local function Find(name, body, account)
    local maxAccount, maxCharacter = Limits()
    local from, to = account and 1 or maxAccount + 1, account and maxAccount or maxAccount + maxCharacter
    for index = from, to do
        local n, _, b = GetMacroInfo(index)
        if n == name and b == body then return index end
    end
end

local function Room(account)
    local accountCount, characterCount = GetNumMacros()
    local maxAccount, maxCharacter = Limits()
    if account then return accountCount < maxAccount end
    return characterCount < maxCharacter
end

local function PackMacros(class)
    return (S.Get("classMacros") or {})[class] or {}
end

-- Macros the player saved to the Library, by class, for every character: { name, body, icon, pack }.
-- pack marks a copy of a pack macro, whose script still gets the shared-pack warning.
local function OwnMacros(class)
    local own = ns.AccountSettings().libraryMacros
    return own and own[class] or {}
end

-------------------------------------------------------------------------------
--  Opening a macro in the editor
-------------------------------------------------------------------------------
local Render, RenderEditor

-- The macro in the editor, without the colour codes it is shown with.
local function Code()
    return Text.Strip(window.code:GetText())
end

local function SetCode(body)
    window.code:SetText(Text.Colorize(body))
end

local function Open(macro)
    draft = { index = macro.index, account = macro.account == true, name = macro.name or "New Macro",
        icon = macro.icon or QUESTION, body = macro.body or "", source = macro.source or "game" }
    draft.saved = draft.index and draft.body or nil
    draft.savedName = draft.index and draft.name or nil
    -- A pack macro is made with the icon the pack (or the player, on the Class Macros page) gave it.
    draft.picked = (draft.source == "pack" or draft.source == "library") and macro.icon ~= nil or nil
    if window then
        window.name:SetText(draft.name)
        SetCode(draft.body)
        window.code:SetCursorPosition(0)
        window.editor.scroll:SetVerticalScroll(0)
    end
end

local function NewDraft(body, name, source)
    Open({ name = name or "New Macro", body = body or "#showtooltip\n/cast ", account = false, source = source or "new" })
end

-- Where the open macro is now. The game sorts macros by name and moves them whenever any is
-- added, renamed or deleted (a Smart Macro, an import), so the index it was opened at is only a
-- hint: it is found again by the name and text it was last saved with.
local function Current()
    return draft and draft.index and Find(draft.savedName, draft.saved, draft.account)
end

-- The open macro is no longer where it was saved: it becomes a new one, nothing else is touched.
local function Lost()
    draft.index, draft.saved, draft.savedName = nil, nil, nil
    Toast("That macro was changed or removed outside the Forge. Save makes it again as a new macro.")
    Render()
end

-- Save into the game: a new macro where the editor says, an existing one in place. The icon is
-- written only when one was picked; otherwise a question mark keeps following #showtooltip.
local function Save()
    if InCombatLockdown() then Toast("Macros can be saved once the fight is over.") return end
    local name, body = strtrim(window.name:GetText()), Code()
    if name == "" or #name > 16 then Toast("A macro's name is 1 to 16 bytes.") return end
    if #body > Text.LIMIT then Toast(("%d bytes over the game's 255: shorten it first."):format(#body - Text.LIMIT)) return end
    if name ~= draft.savedName and GetMacroIndexByName(name) > 0 then
        Toast("You already have a macro called " .. name .. ". Give this one another name.")
        return
    end
    if draft.index then
        local index = Current()
        if not index then return Lost() end
        EditMacro(index, name, draft.picked and draft.icon or nil, body)
    else
        if not Room(draft.account) then
            Toast((draft.account and "Account" or "Character") .. " macros are full. Delete one to make room.")
            return
        end
        CreateMacro(name, draft.picked and draft.icon or QUESTION, body, not draft.account)
    end
    draft.index = Find(name, body, draft.account)
    draft.name, draft.body, draft.saved, draft.savedName, draft.source = name, body, body, name, "game"
    Toast("Saved " .. name .. ". Drag its icon to an action bar.")
    Render()
end

local function Delete()
    if not draft.index then
        NewDraft()
        Render()
        return
    end
    ns.Confirm(("Delete %s? Its action bar buttons go with it."):format(draft.name), function()
        if InCombatLockdown() then Toast("Macros can be deleted once the fight is over.") return end
        local index = Current()
        if not index then return Lost() end
        DeleteMacro(index)
        NewDraft()
        Render()
    end)
end

-- A copy of what is in the editor into the Library under this class, replacing one of the same name.
local function SaveToLibrary()
    local name, body = strtrim(window.name:GetText()), Code()
    if name == "" or #name > 16 then Toast("A macro's name is 1 to 16 bytes.") return end
    if body == "" or #body > Text.LIMIT then Toast("A macro's text is 1 to 255 bytes.") return end
    local _, class = UnitClass("player")
    local account = ns.AccountSettings()
    account.libraryMacros = account.libraryMacros or {}
    account.libraryMacros[class] = account.libraryMacros[class] or {}
    local list = account.libraryMacros[class]
    local icon = (draft.picked or draft.source == "game") and draft.icon ~= QUESTION and draft.icon or nil
    local entry = { name = name, body = body, icon = icon, pack = draft.source == "pack" or nil }
    for i, e in ipairs(list) do
        if e.name == name then
            list[i] = entry
            Toast("Updated " .. name .. " in your Library.")
            return
        end
    end
    list[#list + 1] = entry
    Toast(("Saved %s to your Library, for every %s you play."):format(name,
        LOCALIZED_CLASS_NAMES_MALE[class] or class))
end

local function Drag()
    local index = Current()
    if index and not InCombatLockdown() then PickupMacro(index) end
end

-------------------------------------------------------------------------------
--  Sharing: one macro or many as a string
-------------------------------------------------------------------------------
local SHARE = "!NFM1!"
local SCRIPTS = { ["/run"] = true, ["/script"] = true, ["/dump"] = true }

local function RunsScript(body)
    for line in body:gmatch("[^\n]+") do
        local command = line:match("^%s*(/%a+)")
        if command and SCRIPTS[command:lower()] then return true end
    end
    return false
end

local function Codec()
    return LibStub("LibSerialize"), LibStub("LibDeflate")
end

local function Export(macros)
    local LS, LD = Codec()
    local out = {}
    for i, m in ipairs(macros) do out[i] = { name = m.name, body = m.body } end
    return SHARE .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({ v = 1, macros = out })))
end

-- Parsed as data, never run: names and bodies within the game's limits, no more than the game
-- holds in all.
local function Decode(text)
    local LS, LD = Codec()
    local body = type(text) == "string" and text:match("^%s*" .. SHARE:gsub("!", "%%!") .. "(%S+)%s*$")
    local packed = body and LD:DecodeForPrint(body)
    local raw = packed and LD:DecompressDeflate(packed)
    if not raw then return end
    local ok, data = LS:Deserialize(raw)
    if not (ok and type(data) == "table" and data.v == 1 and type(data.macros) == "table") then return end
    local out = {}
    local maxAccount, maxCharacter = Limits()
    for i, m in ipairs(data.macros) do
        if i > maxAccount + maxCharacter or type(m) ~= "table" or type(m.name) ~= "string" or type(m.body) ~= "string" then
            return
        end
        local name = m.name:gsub("[|\r\n]", "")
        if #name < 1 or #name > 16 or #m.body > Text.LIMIT then return end
        out[i] = { name = name, body = m.body }
    end
    return #out > 0 and out or nil
end

local function Import()
    ns.PromptText("Paste a Naowh Forever macro string", "", 0, function(text)
        local macros = Decode(text)
        if not macros then Toast("That is not a Naowh Forever macro string.") return end
        local runs = false
        for _, m in ipairs(macros) do runs = runs or RunsScript(m.body) end
        ns.Confirm(("Add %d %s as character macros?%s"):format(#macros, #macros == 1 and "macro" or "macros",
            runs and " One runs a script: read it in the editor before you use it." or ""), function()
            if InCombatLockdown() then Toast("Macros can be added once the fight is over.") return end
            local added, taken, full = 0, 0, 0
            for _, m in ipairs(macros) do
                if GetMacroIndexByName(m.name) > 0 then
                    taken = taken + 1
                elseif Room(false) then
                    CreateMacro(m.name, QUESTION, m.body, true)
                    added = added + 1
                else
                    full = full + 1
                end
            end
            local why = {}
            if taken > 0 then why[#why + 1] = taken .. (taken == 1 and " uses" or " use") .. " a name you already have" end
            if full > 0 then why[#why + 1] = "character macros are full" end
            Toast(added == #macros and ("Added %d."):format(added)
                or ("Added %d of %d: %s."):format(added, #macros, table.concat(why, ", ")))
            Render()
        end)
    end)
end

-------------------------------------------------------------------------------
--  My Macros: the list
-------------------------------------------------------------------------------
local function NewMacroRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForDrag("LeftButton")
    ListRow(r)
    r.icon = Icon(r, ROW_ICON)
    r.icon.edge:SetPoint("LEFT", PAD, 0)
    r.name = Text14(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon.edge, "TOPRIGHT", 10, -2)
    r.name:SetPoint("RIGHT", -PAD, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.line = Text14(r, 11, T.muted)
    r.line:SetFont(CODE_FONT, 10, "")
    r.line:SetPoint("BOTTOMLEFT", r.icon.edge, "BOTTOMRIGHT", 10, 2)
    r.line:SetPoint("RIGHT", -PAD, 0)
    r.line:SetJustifyH("LEFT")
    r.line:SetWordWrap(false)
    r.dot = ns.Solid(r, "OVERLAY", ERR, 1)
    r.dot:SetSize(6, 6)
    r:SetScript("OnDragStart", function(self)
        if self.macro.index and not InCombatLockdown() then PickupMacro(self.macro.index) end
    end)
    return r
end

local function FirstCommand(body)
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(1, 1) == "/" then return line end
    end
    return body:match("^([^\n]*)") or ""
end

local function DrawList()
    local view = window.list
    view.rows.Release()
    view.sections.Release()
    local query = strtrim(window.search:GetText() or ""):lower()
    local known = ns.MacroKnownCommands()
    local _, class = UnitClass("player")
    local groups = { { title = "Account", rows = {} }, { title = "This Character", rows = {} },
        { title = "From Your Pack", rows = {}, note = "Your profile pack" } }
    for _, m in ipairs(GameMacros()) do
        local g = m.account and groups[1] or groups[2]
        g.rows[#g.rows + 1] = m
    end
    for _, entry in ipairs(PackMacros(class)) do
        if type(entry.name) == "string" and type(entry.body) == "string" then
            groups[3].rows[#groups[3].rows + 1] = { name = entry.name, body = entry.body,
                icon = ns.MacroEntryIcon(entry), source = "pack" }
        end
    end
    local current = Current()
    local y = 0
    for _, g in ipairs(groups) do
        local shown = {}
        for _, m in ipairs(g.rows) do
            if query == "" or (m.name .. "\n" .. m.body):lower():find(query, 1, true) then shown[#shown + 1] = m end
        end
        if #shown > 0 or (query == "" and g.title ~= "From Your Pack") then
            local h = view.sections.Take()
            h:SetPoint("TOPLEFT", view.body, "TOPLEFT", 0, y)
            h:SetPoint("TOPRIGHT", view.body, "TOPRIGHT", 0, y)
            SetSection(h, g.title, #shown, g.note)
            y = y - SECTION_H - 4
            for i, m in ipairs(shown) do
                local r = view.rows.Take()
                r:SetPoint("TOPLEFT", view.body, "TOPLEFT", 0, y)
                r:SetPoint("TOPRIGHT", view.body, "TOPRIGHT", 0, y)
                r.macro = m
                r.icon:SetTexture(ShownIcon(m.index, m.icon, m.body))
                r.name:SetText(m.name .. (m.source == "pack" and ("  " .. GOLD_CODE .. "PACK|r") or ""))
                r.line:SetText(FirstCommand(m.body))
                local worst
                for _, issue in ipairs(Text.Check(m.body, known)) do
                    if issue.kind == "error" then worst = ERR break end
                    worst = WARN
                end
                r.dot:SetShown(worst ~= nil)
                r.dot:ClearAllPoints()
                r.dot:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), LIST_W - 2 * PAD - ROW_ICON - 40) + 6, 0)
                if worst then r.dot:SetColorTexture(worst.r, worst.g, worst.b, 1) end
                r.stripe:SetShown(i % 2 == 0)
                Pick(r, draft ~= nil and ((m.index and m.index == current)
                    or (not m.index and draft.source == "pack" and draft.name == m.name)))
                r:SetScript("OnClick", function()
                    Open(m)
                    Render()
                end)
                y = y - ROW_H
            end
        end
    end
    view.body:SetHeight(math.max(1, -y))
end

-------------------------------------------------------------------------------
--  My Macros: the editor
-------------------------------------------------------------------------------
-- The lines of the text as the box wraps them: each line number goes where its line starts.
local function Gutter()
    local editor = window.editor
    editor.numbers.Release()
    local measure, y, n = editor.measure, 0, 0
    local issues = {}
    for _, issue in ipairs(editor.issues or {}) do
        if issue.line > 0 then
            issues[issue.line] = (issues[issue.line] == "error" or issue.kind == "error") and "error" or "warning"
        end
    end
    for line in (Code() .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local label = editor.numbers.Take()
        label:SetPoint("TOPRIGHT", editor.gutter, "TOPRIGHT", -6, -(6 + y))
        label:SetText(n)
        local kind = issues[n]
        Paint(label, kind == "error" and ERR or kind == "warning" and WARN or T.muted)
        measure:SetText(line ~= "" and line or " ")
        y = y + math.max(CODE_SIZE + 3, measure:GetStringHeight())
    end
    local height = math.max(editor.scroll:GetHeight(), y + 12)
    editor.page:SetHeight(height)
    window.code:SetHeight(height)
end

RenderEditor = function()
    if not (window and draft) then return end
    local editor, body = window.editor, Code()
    draft.body = body
    local bytes = #body
    local fill = math.min(1, bytes / Text.LIMIT)
    editor.fill:SetWidth(math.max(1, (editor.track:GetWidth() or 1) * fill))
    local c = bytes > Text.LIMIT and ERR or bytes > 220 and WARN or T.accent
    editor.fill:SetColorTexture(c.r, c.g, c.b, 1)
    editor.count:SetText(("%s / 255 bytes%s"):format(ns.Color("fg", bytes),
        bytes <= Text.LIMIT and ("  " .. ns.Color("muted", (Text.LIMIT - bytes) .. " left")) or ""))
    editor.issues = Text.Check(body, ns.MacroKnownCommands())
    for i = 1, ISSUE_LINES do
        local fs, issue = editor.issueLines[i], editor.issues[i]
        if issue then
            fs:SetText((issue.line > 0 and ("L" .. issue.line .. "   ") or "") .. issue.text)
            Paint(fs, issue.kind == "error" and ERR or WARN)
        elseif i == 1 and body ~= "" then
            fs:SetText("Looks good: every command and condition is one the game knows.")
            Paint(fs, OK)
        else
            fs:SetText("")
        end
    end
    Gutter()
    editor.icon:SetTexture(ShownIcon(Current(), draft.picked and draft.icon or (draft.index and draft.icon), body))
    local changed = draft.saved == nil or draft.saved ~= body or (draft.index and window.name:GetText() ~= draft.name)
    editor.saveLabel:SetText(draft.index and (changed and "Save" or "Saved") or "Create")
    editor.scopeAccount:SetEnabled(draft.index == nil)
    editor.scopeCharacter:SetEnabled(draft.index == nil)
    Paint(editor.scopeAccount.label, draft.account and T.fg or T.muted)
    Paint(editor.scopeCharacter.label, draft.account and T.muted or T.fg)
    editor.scopeAccount.fill:SetShown(draft.account)
    editor.scopeCharacter.fill:SetShown(not draft.account)
    editor.where:SetText(draft.index and "Drag the icon to an action bar" or
        (draft.source == "pack" and "From your pack: Create makes it yours"
        or draft.source == "library" and "From your Library: Create makes it a macro" or "Not saved yet"))
    editor.grip:SetShown(draft.index ~= nil)
    local dirty = draft.saved ~= nil and changed
    editor.revert:SetEnabled(dirty)
    editor.revert:SetAlpha(dirty and 1 or 0.45)
    if window.inspector and window.inspector.Refresh then window.inspector.Refresh() end
end

local function ScopeButton(parent, text, account)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(108, 20)
    ns.Solid(b, "BACKGROUND", T.panel, 1):SetAllPoints()
    b.fill = ns.Solid(b, "BACKGROUND", T.accent, 0.18)
    b.fill:SetAllPoints()
    ns.Border(b, BLACK)
    b.label = Text14(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnClick", function()
        draft.account = account
        RenderEditor()
    end)
    return b
end

local function BuildEditor(parent)
    local editor = CreateFrame("Frame", nil, parent)
    editor:SetAllPoints()
    window.editor = editor
    -- The icon: click for the icon picker, drag to an action bar.
    local iconButton = CreateFrame("Button", nil, editor)
    iconButton:SetSize(BIG_ICON, BIG_ICON)
    iconButton:SetPoint("TOPLEFT", PAD, -PAD)
    iconButton:RegisterForDrag("LeftButton")
    editor.icon = Icon(iconButton, BIG_ICON - 2)
    editor.icon.edge:SetPoint("TOPLEFT")
    iconButton:SetScript("OnClick", function() window.inspector.Show("icons") end)
    iconButton:SetScript("OnDragStart", Drag)
    ns.Tooltip(iconButton, "Icon", "Click to pick another, drag to an action bar.")
    window.name = ns.NewEditBox(editor)
    window.name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 14, 0)
    window.name:SetPoint("RIGHT", -PAD, 0)
    window.name:SetHeight(30)
    window.name:SetFont(ns.UIFontPath(), 20, "")
    window.name:SetMaxBytes(17)
    window.name:SetScript("OnTextChanged", function(_, user) if user then RenderEditor() end end)
    local saveTo = Text14(editor, 11, T.muted)
    saveTo:SetPoint("BOTTOMLEFT", iconButton, "BOTTOMRIGHT", 14, 2)
    saveTo:SetText("Saved to")
    editor.scopeAccount = ScopeButton(editor, "Account", true)
    editor.scopeAccount:SetPoint("LEFT", saveTo, "RIGHT", 8, 0)
    editor.scopeCharacter = ScopeButton(editor, "This Character", false)
    editor.scopeCharacter:SetPoint("LEFT", editor.scopeAccount, "RIGHT", -1, 0)
    editor.where = Text14(editor, 11, T.muted)
    editor.where:SetPoint("RIGHT", -PAD, 0)
    editor.where:SetPoint("BOTTOM", saveTo, "BOTTOM")
    editor.grip = CreateFrame("Frame", nil, editor)
    editor.grip:SetSize(6, 10)
    editor.grip:SetPoint("RIGHT", editor.where, "LEFT", -8, 0)
    for i = 0, 5 do
        local dot = ns.Solid(editor.grip, "ARTWORK", T.muted, 1)
        dot:SetSize(2, 2)
        dot:SetPoint("TOPLEFT", (i % 2) * 4, -math.floor(i / 2) * 4)
    end
    -- The byte meter.
    editor.track = ns.Solid(editor, "ARTWORK", T.line, 1)
    editor.track:SetPoint("TOPLEFT", iconButton, "BOTTOMLEFT", 0, -16)
    editor.track:SetPoint("RIGHT", -200, 0)
    editor.track:SetHeight(METER_H)
    editor.fill = editor:CreateTexture(nil, "OVERLAY")
    editor.fill:SetPoint("TOPLEFT", editor.track)
    editor.fill:SetHeight(METER_H)
    editor.count = Text14(editor, 12, T.muted)
    editor.count:SetFont(CODE_FONT, 11, "")
    editor.count:SetPoint("LEFT", editor.track, "RIGHT", 10, 0)
    -- The text, with its line numbers beside it.
    local box = CreateFrame("Frame", nil, editor)
    box:SetPoint("TOPLEFT", editor.track, "BOTTOMLEFT", 0, -12)
    box:SetPoint("RIGHT", -PAD, 0)
    box:SetHeight(CODE_LINES * (CODE_SIZE + 4) + 12)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(box, BLACK)
    local scroll = UI.SlimScroll(box)
    scroll:SetPoint("TOPLEFT", 1, -1)
    scroll:SetPoint("BOTTOMRIGHT", -12, 1)
    local page = CreateFrame("Frame", nil, scroll)
    page:SetSize(1, box:GetHeight())
    scroll:SetScrollChild(page)
    scroll:SetScript("OnSizeChanged", function(_, w) page:SetWidth(w) end)
    editor.scroll, editor.page = scroll, page
    editor.gutter = CreateFrame("Frame", nil, page)
    editor.gutter:SetPoint("TOPLEFT")
    editor.gutter:SetPoint("BOTTOMLEFT")
    editor.gutter:SetWidth(GUTTER_W)
    local rule = ns.Solid(page, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", editor.gutter, "TOPRIGHT")
    rule:SetPoint("BOTTOMLEFT", editor.gutter, "BOTTOMRIGHT")
    ns.Hairline(rule, "v")
    editor.numbers = Pool(function() return Text14(editor.gutter, 11, T.muted) end)
    local code = CreateFrame("EditBox", nil, page)
    code:SetPoint("TOPLEFT", GUTTER_W + 1, 0)
    code:SetPoint("TOPRIGHT")
    code:SetMultiLine(true)
    code:SetAutoFocus(false)
    code:SetMaxLetters(0)
    code:SetFont(CODE_FONT, CODE_SIZE, "")
    code:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    code:SetTextInsets(10, 10, 6, 6)
    code:SetScript("OnEscapePressed", code.ClearFocus)
    code:SetScript("OnTextChanged", function(self)
        local shown = self:GetText()
        local colored = Text.Colorize(Text.Strip(shown))
        if colored ~= shown then
            local at = Text.PlainPos(shown, self:GetCursorPosition())
            self:SetText(colored)
            self:SetCursorPosition(Text.CodedPos(colored, at))
            return
        end
        RenderEditor()
    end)
    -- Keep the cursor's line in view; the range can grow a frame after the text does.
    local cursorTop, cursorHeight = 0, 0
    local function Follow()
        local at, shown = scroll:GetVerticalScroll(), scroll:GetHeight()
        if cursorTop < at then
            scroll:SetVerticalScroll(cursorTop)
        elseif cursorTop + cursorHeight > at + shown then
            scroll:SetVerticalScroll(cursorTop + cursorHeight - shown)
        end
    end
    -- The client draws no insertion cursor in this box, so it gets its own.
    local caret = code:CreateTexture(nil, "OVERLAY")
    caret:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    caret:SetWidth(2)
    caret:Hide()
    local blink = 0
    local function Blink(self, elapsed)
        blink = blink + elapsed
        caret:SetShown(blink % (2 * self:GetBlinkSpeed()) < self:GetBlinkSpeed())
    end
    code:SetScript("OnEditFocusGained", function(self)
        blink = 0
        caret:Show()
        self:SetScript("OnUpdate", Blink)
    end)
    code:SetScript("OnEditFocusLost", function(self)
        self:SetScript("OnUpdate", nil)
        caret:Hide()
    end)
    code:SetScript("OnCursorChanged", function(self, x, y, _, h)
        cursorTop, cursorHeight = -y, h
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", x, y)
        caret:SetHeight(h)
        blink = 0
        caret:SetShown(self:HasFocus())
        Follow()
    end)
    scroll:HookScript("OnScrollRangeChanged", Follow)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() code:SetFocus() end)
    window.code = code
    -- The same font at the same width, to find where each line wraps.
    editor.measure = page:CreateFontString(nil, "ARTWORK")
    editor.measure:SetFont(CODE_FONT, CODE_SIZE, "")
    editor.measure:SetPoint("TOPLEFT", code, "TOPLEFT", 10, 0)
    editor.measure:SetPoint("RIGHT", code, "RIGHT", -10, 0)
    editor.measure:SetAlpha(0)
    -- What will not work.
    editor.issueLines = {}
    for i = 1, ISSUE_LINES do
        local fs = Text14(editor, 12)
        fs:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -8 - (i - 1) * 16)
        fs:SetPoint("RIGHT", -PAD, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        editor.issueLines[i] = fs
    end
    -- The actions.
    local save = ns.AccentBorder(ns.Button(editor, "Save", 80, BUTTON_H, Save))
    save:SetPoint("BOTTOMLEFT", PAD, PAD)
    editor.saveLabel = save.label
    local shorten = ns.Button(editor, "Shorten", 74, BUTTON_H, function()
        local before = Code()
        local after = Text.Shorten(before)
        SetCode(after)
        Toast(#after < #before and ("Shortened by %d bytes. It does the same."):format(#before - #after)
            or "It is as short as it safely gets.")
    end)
    shorten:SetPoint("LEFT", save, "RIGHT", 6, 0)
    ns.Tooltip(shorten, "Shorten", "Saves bytes with spellings the game reads the same way: @ for target=, "
        .. "mod: and btn:, and no spaces around ; and ,.")
    local export = ns.Button(editor, "Export", 64, BUTTON_H, function()
        local name, body = strtrim(window.name:GetText()), Code()
        if name == "" or #name > 16 then Toast("A macro's name is 1 to 16 bytes.") return end
        if body == "" or #body > Text.LIMIT then Toast("A macro's text is 1 to 255 bytes.") return end
        ns.ShowCopyBox(name, Export({ { name = name, body = body } }))
    end)
    export:SetPoint("LEFT", shorten, "RIGHT", 6, 0)
    local revert = ns.Button(editor, "Revert", 64, BUTTON_H, function()
        if not draft.saved then return end
        window.name:SetText(draft.savedName)
        SetCode(draft.saved)
        RenderEditor()
    end)
    revert:SetPoint("LEFT", export, "RIGHT", 6, 0)
    editor.revert = revert
    local toLibrary = ns.Button(editor, "To Library", 80, BUTTON_H, SaveToLibrary)
    toLibrary:SetPoint("LEFT", revert, "RIGHT", 6, 0)
    ns.Tooltip(toLibrary, "Save to Library", "Keeps a copy in the Library under your class, for every character "
        .. "of that class. Saving it again under the same name replaces it.")
    local delete = ns.Button(editor, "Delete", 64, BUTTON_H, Delete)
    delete:SetPoint("BOTTOMRIGHT", -PAD, PAD)
end

-------------------------------------------------------------------------------
--  My Macros: the inspector beside the editor
-------------------------------------------------------------------------------
local CONDITION_UNITS = { [""] = "Your target", ["@mouseover"] = "Your mouseover", ["@focus"] = "Your focus",
    ["@player"] = "Yourself", ["@targettarget"] = "Your target's target", ["@cursor"] = "The cursor" }
local CONDITION_UNIT_ORDER = { "", "@mouseover", "@focus", "@player", "@targettarget", "@cursor" }
local CONDITION_MODS = { [""] = "Any key", ["mod:shift"] = "Shift", ["mod:ctrl"] = "Ctrl", ["mod:alt"] = "Alt",
    nomod = "No modifier" }
local CONDITION_MOD_ORDER = { "", "mod:shift", "mod:ctrl", "mod:alt", "nomod" }
local CONDITION_FLAGS = { { "harm", "Hostile" }, { "help", "Friendly" }, { "exists", "Exists" },
    { "nodead", "Alive" }, { "combat", "In combat" }, { "nocombat", "Out of combat" } }
local COMMANDS = {
    { "Casting", { { "/cast", "Cast a spell, with conditions" }, { "/castsequence", "One spell per press, in order" },
        { "/stopcasting", "Stop your current cast" }, { "/use", "Use an item, or a slot: 13, 14" } } },
    { "Targeting", { { "/target", "Target a unit by name" }, { "/focus", "Set your focus" },
        { "/assist", "Take your target's target" }, { "/cleartarget", "Clear your target" } } },
    { "Combat", { { "/startattack", "Start auto attack" }, { "/stopattack", "Stop auto attack" },
        { "/petattack", "Send your pet in" }, { "/tm 8", "Skull on your target" },
        { "/cancelaura", "Remove a buff from you" } } },
    { "On the button", { { "#showtooltip", "Show the spell on the button" } } },
}

local function Insert(text)
    window.code:SetFocus()
    window.code:Insert(text)
end

local function BuildInspector(parent)
    local inspector = CreateFrame("Frame", nil, parent)
    inspector:SetAllPoints()
    window.inspector = inspector
    local panes = {}
    local function Show(key)
        Parts.PaintTabs(inspector.tabs, key)
        for k, pane in pairs(panes) do pane:SetShown(k == key) end
        inspector.shown = key
        inspector.Refresh()
    end
    inspector.Show = Show
    inspector.tabs = Parts.Tabs(inspector, INSPECTOR_W - 2 * PAD, {
        { key = "explain", label = "Explain" }, { key = "conditions", label = "Conditions" },
        { key = "commands", label = "Commands" }, { key = "icons", label = "Icons" },
    }, Show)
    inspector.tabs:SetPoint("TOPLEFT", PAD, -PAD)
    local function Pane()
        local pane = CreateFrame("Frame", nil, inspector)
        pane:SetPoint("TOPLEFT", inspector.tabs, "BOTTOMLEFT", 0, -12)
        pane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        pane:Hide()
        return pane
    end

    -- Explain: what each line does, numbered.
    panes.explain = Pane()
    local hint = Text14(panes.explain, 11, T.muted)
    hint:SetPoint("TOPLEFT")
    hint:SetText("What this macro does, line by line.")
    local lines = Pool(function()
        local row = CreateFrame("Frame", nil, panes.explain)
        row.box = CreateFrame("Frame", nil, row)
        row.box:SetSize(20, 20)
        row.box:SetPoint("TOPLEFT", 0, 1)
        ns.Solid(row.box, "BACKGROUND", T.bg, 1):SetAllPoints()
        ns.Border(row.box, BLACK)
        row.number = Text14(row.box, 11, T.muted)
        row.number:SetPoint("CENTER")
        row.text = Text14(row, 13)
        row.text:SetPoint("TOPLEFT", 30, 0)
        row.text:SetWidth(INSPECTOR_W - 2 * PAD - 30)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        row.text:SetSpacing(2)
        return row
    end)

    -- Conditions: build the brackets, then Insert them at the cursor.
    panes.conditions = Pane()
    local built = { unit = "", mod = "", flags = {} }
    local function Brackets()
        local parts = {}
        if built.unit ~= "" then parts[#parts + 1] = built.unit end
        for _, flag in ipairs(CONDITION_FLAGS) do
            if built.flags[flag[1]] then parts[#parts + 1] = flag[1] end
        end
        if built.mod ~= "" then parts[#parts + 1] = built.mod end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local onLabel = Text14(panes.conditions, 11, T.muted)
    onLabel:SetPoint("TOPLEFT")
    onLabel:SetText("On")
    local unitDrop = UI.BuildDropdownControl(panes.conditions, INSPECTOR_W - 2 * PAD, panes.conditions:GetFrameLevel() + 2,
        CONDITION_UNITS, CONDITION_UNIT_ORDER, function() return built.unit end,
        function(v) built.unit = v; inspector.Refresh() end)
    unitDrop:SetPoint("TOPLEFT", onLabel, "BOTTOMLEFT", 0, -4)
    local flags = {}
    for i, flag in ipairs(CONDITION_FLAGS) do
        local b = ns.Button(panes.conditions, flag[2], (INSPECTOR_W - 2 * PAD - 6) / 2, 24, function()
            built.flags[flag[1]] = not built.flags[flag[1]] or nil
            inspector.Refresh()
        end)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", unitDrop, "BOTTOMLEFT", col * ((INSPECTOR_W - 2 * PAD) / 2 + 3), -10 - row * 30)
        b.flag = flag[1]
        flags[i] = b
    end
    local modLabel = Text14(panes.conditions, 11, T.muted)
    modLabel:SetPoint("TOPLEFT", unitDrop, "BOTTOMLEFT", 0, -10 - 3 * 30 - 4)
    modLabel:SetText("Holding")
    local modDrop = UI.BuildDropdownControl(panes.conditions, INSPECTOR_W - 2 * PAD, panes.conditions:GetFrameLevel() + 2,
        CONDITION_MODS, CONDITION_MOD_ORDER, function() return built.mod end,
        function(v) built.mod = v; inspector.Refresh() end)
    modDrop:SetPoint("TOPLEFT", modLabel, "BOTTOMLEFT", 0, -4)
    local preview = Text14(panes.conditions, 13, { r = 0.95, g = 0.83, b = 0.42 })
    preview:SetPoint("TOPLEFT", modDrop, "BOTTOMLEFT", 0, -14)
    preview:SetPoint("RIGHT")
    preview:SetJustifyH("LEFT")
    local reads = Text14(panes.conditions, 12, T.muted)
    reads:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
    reads:SetPoint("RIGHT")
    reads:SetJustifyH("LEFT")
    local insertConditions = ns.AccentBorder(ns.Button(panes.conditions, "Insert", 96, BUTTON_H, function()
        Insert(Brackets() .. " ")
    end))
    insertConditions:SetPoint("BOTTOMLEFT")

    -- Commands: click one to put it on a new line.
    panes.commands = Pane()
    local commandRows = Pool(function()
        local b = CreateFrame("Button", nil, panes.commands)
        b:SetHeight(34)
        ListRow(b)
        b.code = Text14(b, 13, { r = 0.42, g = 0.77, b = 1 })
        b.code:SetPoint("TOPLEFT", 8, -4)
        b.text = Text14(b, 11, T.muted)
        b.text:SetPoint("BOTTOMLEFT", 8, 4)
        return b
    end)
    local commandTitles = Pool(function()
        local fs = Text14(panes.commands, 11, T.accentSoft)
        return fs
    end)

    -- Icons: favourites first, then every icon, a page at a time; right-click stars one.
    panes.icons = Pane()
    local page = 1
    local function Favorites()
        local account = ns.AccountSettings()
        account.macroFavoriteIcons = account.macroFavoriteIcons or {}
        return account.macroFavoriteIcons
    end
    local iconButtons = {}
    for i = 1, ICON_COLS * ICON_ROWS do
        local b = CreateFrame("Button", nil, panes.icons)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.icon = Icon(b, ICON_SIZE - 2)
        b.icon.edge:SetPoint("TOPLEFT")
        b.star = Text14(b, 12, { r = 0.9, g = 0.8, b = 0.5 })
        b.star:SetPoint("TOPRIGHT", 1, 1)
        b.star:SetText("*")
        local col, row = (i - 1) % ICON_COLS, math.floor((i - 1) / ICON_COLS)
        b:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_GAP), -22 - row * (ICON_SIZE + ICON_GAP))
        b:SetScript("OnClick", function(self, button)
            if not self.fileID then return end
            if button == "RightButton" then
                Favorites()[self.fileID] = not Favorites()[self.fileID] or nil
            else
                draft.icon, draft.picked = self.fileID, true
                local index = Current()
                if index and not InCombatLockdown() then
                    EditMacro(index, draft.savedName, draft.icon, draft.saved)
                end
                Render()
            end
            inspector.Refresh()
        end)
        iconButtons[i] = b
    end
    local pageLabel = Text14(panes.icons, 11, T.muted)
    pageLabel:SetPoint("TOPLEFT")
    local iconHint = Text14(panes.icons, 11, T.muted)
    iconHint:SetPoint("BOTTOMLEFT")
    iconHint:SetText("Right-click to star an icon. Scroll for more.")
    panes.icons:EnableMouseWheel(true)
    panes.icons:SetScript("OnMouseWheel", function(_, delta)
        page = math.max(1, page - delta)
        inspector.Refresh()
    end)

    function inspector.Refresh()
        if not draft then return end
        local key = inspector.shown
        if key == "explain" then
            lines.Release()
            local y = -22
            local said = Text.Explain(Code())
            for i, sentence in ipairs(said) do
                local row = lines.Take()
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", 0, y)
                row.number:SetText(i)
                row.box:Show()
                row.text:SetText(sentence)
                local h = math.max(18, row.text:GetStringHeight())
                row:SetHeight(h)
                y = y - h - 10
            end
            if #said == 0 then
                local row = lines.Take()
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", 0, y)
                row.box:Hide()
                row.text:SetText(ns.Color("muted", "Write a line and this says what it does."))
                row:SetHeight(18)
            end
        elseif key == "conditions" then
            for _, b in ipairs(flags) do
                b._rest = built.flags[b.flag] and T.accent or BLACK
                b._border:SetColor(b._rest.r, b._rest.g, b._rest.b, 1)
            end
            local brackets = Brackets()
            preview:SetText(brackets)
            local sentence = Text.Explain("/cast " .. brackets .. " the spell")[1] or ""
            reads:SetText("Reads as: " .. sentence)
        elseif key == "commands" then
            commandRows.Release()
            commandTitles.Release()
            local y, n = 0, 0
            for _, group in ipairs(COMMANDS) do
                local title = commandTitles.Take()
                title:SetPoint("TOPLEFT", 0, y)
                title:SetText(group[1]:upper())
                y = y - 18
                for _, command in ipairs(group[2]) do
                    n = n + 1
                    local b = commandRows.Take()
                    b:SetPoint("TOPLEFT", 0, y)
                    b:SetPoint("RIGHT")
                    b.code:SetText(command[1])
                    b.text:SetText(command[2])
                    b.stripe:SetShown(n % 2 == 0)
                    Pick(b, false)
                    b:SetScript("OnClick", function() Insert("\n" .. command[1] .. " ") end)
                    y = y - 34
                end
                y = y - 8
            end
        elseif key == "icons" then
            local list, favorites = {}, Favorites()
            for fileID in pairs(favorites) do list[#list + 1] = fileID end
            table.sort(list)
            for _, fileID in ipairs(ns.MacroIconList()) do
                if not favorites[fileID] then list[#list + 1] = fileID end
            end
            local perPage = ICON_COLS * ICON_ROWS
            local pages = math.max(1, math.ceil(#list / perPage))
            page = math.min(page, pages)
            pageLabel:SetText(("Page %d of %d"):format(page, pages))
            for i, b in ipairs(iconButtons) do
                local fileID = list[(page - 1) * perPage + i]
                b.fileID = fileID
                b:SetShown(fileID ~= nil)
                if fileID then
                    b.icon:SetTexture(fileID)
                    b.star:SetShown(favorites[fileID] == true)
                end
            end
        end
    end
    Show("explain")
end

-------------------------------------------------------------------------------
--  Smart Macros
-------------------------------------------------------------------------------
-- What a smart macro will use right now, read from the text the module writes for it.
local function Uses(key, body)
    local uses = {}
    for id in (body or ""):gmatch("item:(%d+)") do
        id = tonumber(id)
        uses[#uses + 1] = { icon = C_Item.GetItemIconByID(id) or QUESTION,
            text = C_Item.GetItemNameByID(id) or ("Item " .. id), count = "x" .. C_Item.GetItemCount(id) }
    end
    local slot = (body or ""):match("/use (1[34])")
    if slot then
        local id = GetInventoryItemID("player", tonumber(slot))
        uses[#uses + 1] = { icon = id and C_Item.GetItemIconByID(id) or QUESTION,
            text = id and (C_Item.GetItemNameByID(id) or "Your trinket") or "No trinket worn", count = "slot " .. slot }
    end
    if key == "focus" then
        uses[#uses + 1] = { icon = 132212, text = "Mouseover, else target", count = "" }
    elseif key == "acceptPopup" then
        uses[#uses + 1] = { icon = 136814, text = "Clicks Yes on popups", count = "" }
    end
    if #uses == 0 then uses[1] = { icon = QUESTION, text = "Nothing in your bags", count = "" } end
    return uses
end

local SMART_NOTES = { health = "Healthstone or potion", mana = "Best mana potion", food = "Conjured food first",
    bandage = "On yourself", trinket1 = "Top trinket slot", trinket2 = "Bottom trinket slot",
    focus = "Marks and announces", acceptPopup = "Ready checks, summons" }

local function NewSmartCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(SMART_H)
    ns.Solid(c, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(c, BLACK)
    c.drag = CreateFrame("Button", nil, c)
    c.drag:SetSize(ROW_ICON + 2, ROW_ICON + 2)
    c.drag:SetPoint("TOPLEFT", 12, -12)
    c.drag:RegisterForDrag("LeftButton")
    c.icon = Icon(c.drag, ROW_ICON)
    c.icon.edge:SetPoint("TOPLEFT")
    c.title = Text14(c, 16)
    c.title:SetPoint("TOPLEFT", c.drag, "TOPRIGHT", 10, 0)
    c.title:SetJustifyH("LEFT")
    c.title:SetWordWrap(false)
    c.note = Text14(c, 11, T.muted)
    c.note:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
    c.note:SetJustifyH("LEFT")
    c.note:SetWordWrap(false)
    c.toggle = UI.BuildToggleControl(c, c:GetFrameLevel() + 2, function() return S.Get(c.key) == true end,
        function(v) S.Set(c.key, v) end)
    c.toggle:SetPoint("TOPRIGHT", -12, -14)
    c.uses = {}
    for i = 1, 2 do
        local row = CreateFrame("Frame", nil, c)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 12, -56 - (i - 1) * 28)
        row:SetPoint("RIGHT", -12, 0)
        row.lead = Text14(row, 11, T.muted)
        row.lead:SetPoint("LEFT")
        row.lead:SetWidth(34)
        row.lead:SetJustifyH("LEFT")
        row.icon = Icon(row, 20)
        row.icon.edge:SetPoint("LEFT", 36, 0)
        row.count = Text14(row, 11, T.muted)
        row.count:SetPoint("RIGHT")
        row.text = Text14(row, 12)
        row.text:SetPoint("LEFT", row.icon.edge, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        c.uses[i] = row
    end
    c.dragHint = Text14(c, 11, T.muted)
    c.dragHint:SetPoint("BOTTOMRIGHT", -12, 10)
    c.dragHint:SetText("Drag the icon to a bar")
    c.drag:SetScript("OnDragStart", function() ns.PickupManagedMacro(c.key) end)
    c.drag:SetScript("OnClick", function() ns.PickupManagedMacro(c.key) end)
    return c
end

local function DrawSmart()
    local view = window.smart
    view.cards.Release()
    local w = math.floor((view.body:GetWidth() - (CARD_COLS - 1) * CARD_GAP) / CARD_COLS)
    for i, m in ipairs(ns.MacroSmart.list) do
        local c = view.cards.Take()
        local col, line = (i - 1) % CARD_COLS, math.floor((i - 1) / CARD_COLS)
        c:SetPoint("TOPLEFT", view.body, "TOPLEFT", col * (w + CARD_GAP), -line * (SMART_H + CARD_GAP))
        c:SetWidth(w)
        c.key = m.key
        local on = S.Get(m.key) == true
        c:SetAlpha(on and 1 or 0.6)
        -- The title and note stop short of the switch.
        local textW = w - 12 - (ROW_ICON + 2) - 10 - 8 - c.toggle:GetWidth() - 12
        c.title:SetWidth(textW)
        c.note:SetWidth(textW)
        c.title:SetText(m.name)
        c.note:SetText(SMART_NOTES[m.key] or "")
        c.toggle._refreshValue()
        local uses = Uses(m.key, ns.MacroSmart.Body(m.key))
        c.icon:SetTexture(uses[1].icon)
        for k, row in ipairs(c.uses) do
            local use = uses[k]
            row:SetShown(use ~= nil)
            if use then
                row.lead:SetText(k == 1 and "Uses" or "then")
                row.icon:SetTexture(use.icon)
                row.text:SetText(use.text)
                Paint(row.text, k == 1 and T.fg or T.muted)
                row.count:SetText(use.count)
            end
        end
    end
    view.body:SetHeight(math.ceil(#ns.MacroSmart.list / CARD_COLS) * (SMART_H + CARD_GAP))
    local on = 0
    for _, m in ipairs(ns.MacroSmart.list) do
        if S.Get(m.key) then on = on + 1 end
    end
    window.smartSummary:SetText(("%d of %d Smart Macros on."):format(on, #ns.MacroSmart.list))
end

-------------------------------------------------------------------------------
--  Library
-------------------------------------------------------------------------------
-- A pack macro onto this character, as the Class Macros page adds one: within the game's limits,
-- once, and a script from a shared pack only after the player says so.
local function AddFromPack(entry)
    if #entry.name < 1 or #entry.name > 16 or #entry.body < 1 or #entry.body > Text.LIMIT then
        Toast(entry.name .. " is not a macro the game can hold: a name is 1 to 16 bytes, its text 1 to 255.")
        return
    end
    local function Add()
        if InCombatLockdown() then Toast("Macros can be added once the fight is over.") return end
        local index = Find(entry.name, entry.body, false)
        local icon = entry.icon
        if not entry.own then icon = ns.MacroEntryIcon(entry) end
        icon = icon or QUESTION
        if not index then
            if GetMacroIndexByName(entry.name) > 0 then
                Toast("You already have a different macro called " .. entry.name .. ". Rename it to add this one.")
                return
            end
            if not Room(false) then Toast("Character macros are full. Delete one to make room.") return end
            CreateMacro(entry.name, icon, entry.body, true)
            index = Find(entry.name, entry.body, false)
            Toast("Added " .. entry.name .. " to this character. Drag it to a bar from My Macros.")
        else
            Toast(entry.name .. " is already one of this character's macros.")
        end
        Open({ index = index, account = false, name = entry.name, icon = icon, body = entry.body })
        Render()
    end
    if RunsScript(entry.body) and (entry.pack or not entry.own) then
        ns.Confirm(entry.name .. " runs a script from a shared pack. Open it in the editor to read it first. Add it?",
            Add)
    else
        Add()
    end
end

local function NewClassRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(34)
    ListRow(b)
    b.name = ns.Font(b, 15)
    b.name:SetPoint("LEFT", PAD, 0)
    b.count = Text14(b, 11, T.muted)
    b.count:SetPoint("RIGHT", -PAD, 0)
    return b
end

local function NewLibCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(LIB_H)
    ns.Solid(c, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(c, BLACK)
    c.icon = Icon(c, ROW_ICON)
    c.icon.edge:SetPoint("TOPLEFT", 12, -12)
    c.title = Text14(c, 16)
    c.title:SetPoint("LEFT", c.icon.edge, "RIGHT", 10, 0)
    c.tag = Text14(c, 10)
    c.tag:SetPoint("TOPRIGHT", -12, -16)
    c.note = Text14(c, 12, T.muted)
    c.note:SetPoint("TOPLEFT", c.icon.edge, "BOTTOMLEFT", 0, -8)
    c.note:SetPoint("TOPRIGHT", -12, -(12 + ROW_ICON + 2 + 8))
    c.note:SetJustifyH("LEFT")
    local code = CreateFrame("Frame", nil, c)
    code:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -8)
    code:SetPoint("RIGHT", -12, 0)
    code:SetPoint("BOTTOM", 0, 44)
    ns.Solid(code, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(code, BLACK)
    c.body = Text14(code, 11)
    c.body:SetPoint("TOPLEFT", 8, -6)
    c.body:SetPoint("BOTTOMRIGHT", -8, 6)
    c.body:SetJustifyH("LEFT")
    c.body:SetJustifyV("TOP")
    c.add = ns.AccentBorder(ns.Button(c, "Add", 64, BUTTON_H))
    c.add:SetPoint("BOTTOMRIGHT", -12, 10)
    c.open = ns.Button(c, "Open in Editor", 110, BUTTON_H)
    c.open:SetPoint("RIGHT", c.add, "LEFT", -6, 0)
    c.remove = ns.Button(c, "Remove", 70, BUTTON_H)
    c.remove:SetPoint("BOTTOMLEFT", 12, 10)
    return c
end

local function DrawLibrary()
    local view = window.lib
    local _, myClass = UnitClass("player")
    libClass = libClass or myClass
    view.classes.Release()
    local y = 0
    for i, class in ipairs(CLASSES) do
        local b = view.classes.Take()
        b:SetPoint("TOPLEFT", view.classBody, "TOPLEFT", 0, y)
        b:SetPoint("TOPRIGHT", view.classBody, "TOPRIGHT", 0, y)
        local color = RAID_CLASS_COLORS[class]
        b.name:SetText(color:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[class] or class))
        local n = #OwnMacros(class) + #PackMacros(class)
        b.count:SetText(n > 0 and (n .. " macros") or "")
        b.stripe:SetShown(i % 2 == 0)
        Pick(b, class == libClass)
        b:SetScript("OnClick", function()
            libClass = class
            DrawLibrary()
        end)
        y = y - 34
    end
    view.cards.Release()
    local list = {}
    for _, entry in ipairs(OwnMacros(libClass)) do
        list[#list + 1] = { name = entry.name, note = "", body = entry.body, icon = entry.icon, own = true,
            pack = entry.pack }
    end
    for _, entry in ipairs(PackMacros(libClass)) do
        if type(entry.name) == "string" and type(entry.body) == "string" then
            list[#list + 1] = { name = entry.name, note = entry.note or "", body = entry.body, icon = entry.icon }
        end
    end
    local color = RAID_CLASS_COLORS[libClass]
    view.title:SetText(color:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[libClass] or libClass))
    view.lead:SetText(libClass == myClass and "Macros for your class. Open one to change it first, or Add it as it is."
        or "Another class's macros, to read. Add them on a character of that class.")
    local w = math.floor((view.body:GetWidth() - CARD_GAP) / 2)
    for i, entry in ipairs(list) do
        local c = view.cards.Take()
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        c:SetPoint("TOPLEFT", view.body, "TOPLEFT", col * (w + CARD_GAP), -line * (LIB_H + CARD_GAP))
        c:SetWidth(w)
        local icon = entry.icon
        if not entry.own then icon = ns.MacroEntryIcon(entry) end
        c.icon:SetTexture(ShownIcon(nil, icon, entry.body))
        c.title:SetText(entry.name)
        if entry.own then
            c.tag:SetText("YOURS")
            Paint(c.tag, T.accent)
        else
            c.tag:SetText(GOLD_CODE .. "NAOWH|r")
            Paint(c.tag, T.fg)
        end
        c.remove:SetShown(entry.own == true)
        c.remove._onClick = function()
            ns.Confirm(("Remove %s from your Library? Macros already made from it stay."):format(entry.name),
                function()
                    local saved = OwnMacros(libClass)
                    for k, e in ipairs(saved) do
                        if e.name == entry.name then table.remove(saved, k) break end
                    end
                    DrawLibrary()
                end)
        end
        c.note:SetText(entry.note or "")
        c.body:SetText(entry.body:gsub("|", "||"))
        local own = libClass == myClass
        c.add:SetEnabled(own)
        c.add:SetAlpha(own and 1 or 0.4)
        c.add._onClick = function() AddFromPack(entry) end
        c.open._onClick = function()
            Open({ name = entry.name, body = entry.body, icon = icon, account = false,
                source = entry.own and "library" or "pack" })
            window.SetTab("mine")
        end
    end
    view.body:SetHeight(math.max(1, math.ceil(#list / 2) * (LIB_H + CARD_GAP)))
    view.lead:SetShown(#list > 0)
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function Subtitle()
    local accountCount, characterCount = GetNumMacros()
    local maxAccount, maxCharacter = Limits()
    local function Count(n, max)
        local text = n .. "/" .. max
        return n >= max and ns.Color("accent", text) or text
    end
    local _, class = UnitClass("player")
    local className = LOCALIZED_CLASS_NAMES_MALE[class] or class
    local classColor = RAID_CLASS_COLORS[class]
    window.subtitle:SetText(classColor:WrapTextInColorCode(UnitName("player") .. ", " .. className))
    local meters = window.meters
    meters[1].fill:SetWidth(math.max(1, METER_W * math.min(1, accountCount / maxAccount)))
    meters[1].label:SetText("Account " .. Count(accountCount, maxAccount))
    meters[2].fill:SetWidth(math.max(1, METER_W * math.min(1, characterCount / maxCharacter)))
    meters[2].fill:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    meters[2].label:SetText(className .. " " .. Count(characterCount, maxCharacter))
end

Render = function()
    if not (window and window:IsShown()) then return end
    Subtitle()
    if not draft then NewDraft() end
    if tab == "mine" then
        DrawList()
        RenderEditor()
    elseif tab == "smart" then
        DrawSmart()
    else
        DrawLibrary()
    end
end

local function ShowCard(card, shown)
    for _, part in ipairs(card) do part:SetShown(shown) end
end

local function SetTab(key)
    tab = key
    Parts.PaintTabs(window.switch, key)
    window.mine:SetShown(key == "mine")
    window.smartView:SetShown(key == "smart")
    window.libView:SetShown(key == "lib")
    for name, cards in pairs(window.cards) do
        for _, card in ipairs(cards) do ShowCard(card, name == key) end
    end
    window.search:SetShown(key == "mine")
    if window:IsShown() then Render() end
end

-- A card's area on the window, as a frame its contents can fill.
local function Area(left, right)
    local f = CreateFrame("Frame", nil, window)
    f:SetPoint("TOPLEFT", left, -TOP)
    f:SetPoint("BOTTOMRIGHT", -right, FOOTER + CARD_INSET)
    return f
end

local function Scroller(parent, top)
    local scroll = UI.SlimScroll(parent)
    scroll:SetPoint("TOPLEFT", 0, -(top or 0))
    scroll:SetPoint("BOTTOMRIGHT", -12, 4)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll:SetScript("OnSizeChanged", function(self, w) body:SetWidth(w) end)
    return scroll, body
end

local function OpacityGet() return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5) end
local function OpacitySet(value) S.Set("windowAlpha", value / 100) end
ns.MacroOpacityGet, ns.MacroOpacitySet = OpacityGet, OpacitySet

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "macroWindow")
    local close = Parts.TitleBar(window, NAME, "", PAGE)
    local opacityIcon, slider = Parts.Opacity(window, close, OpacityGet, OpacitySet)
    window.opacity = slider
    window.meters = {}
    local after = window.subtitle
    for i = 1, 2 do
        local track = ns.Solid(window, "ARTWORK", T.line, 1)
        track:SetSize(METER_W, 3)
        track:SetPoint("LEFT", after, "RIGHT", i == 1 and 12 or 14, 0)
        local fill = ns.Solid(window, "OVERLAY", T.accent, 1)
        fill:SetPoint("TOPLEFT", track)
        fill:SetHeight(3)
        local label = Text14(window, 11, T.muted)
        label:SetPoint("LEFT", track, "RIGHT", 6, 0)
        window.meters[i] = { fill = fill, label = label }
        after = label
    end
    local exportButton = Parts.BarButton(window, St.EXPORT, "Export", "Every macro in the list, as one string to share.",
        function()
            local all = {}
            local smart = {}
            for _, m in ipairs(ns.MacroSmart.list) do smart[m.name] = true end
            for _, m in ipairs(GameMacros()) do
                if not smart[m.name] then all[#all + 1] = m end
            end
            if #all == 0 then Toast("You have no macros to export yet.") return end
            ns.ShowCopyBox("Your macros", Export(all))
        end, "Export")
    exportButton:SetPoint("RIGHT", opacityIcon, "LEFT", -St.BAR_GAP - 6, 0)
    local importButton = Parts.BarButton(window, St.IMPORT, "Import", "Add macros someone shared with you.", Import,
        "Import")
    importButton:SetPoint("RIGHT", exportButton, "LEFT", -St.BAR_GAP, 0)
    local newButton = Parts.BarButton(window, St.PLUS, "New Macro", "Start a new macro in the editor.", function()
        NewDraft()
        SetTab("mine")
        window.code:SetFocus()
    end, "New")
    newButton:SetPoint("RIGHT", importButton, "LEFT", -St.BAR_GAP, 0)

    window.switch = Parts.Tabs(window, SWITCH_W, {
        { key = "mine", label = "My Macros", tip = "Your macros, and the editor." },
        { key = "smart", label = "Smart Macros", tip = "Macros that keep themselves up to date." },
        { key = "lib", label = "Library", tip = "Macros by class, for every character. Add yours with To Library in the editor." },
    }, SetTab)
    window.switch:SetPoint("TOPLEFT", CARD_INSET, -(HEADER + TOOL_GAP))
    window.search = Parts.SearchBox(window, "Search your macros", function() if tab == "mine" then DrawList() end end)
    window.search:SetSize(SEARCH_W, St.SEARCH_H)
    window.search:SetPoint("RIGHT", window, "TOPRIGHT", -CARD_INSET, -(HEADER + TOOL_GAP + St.TAB_H / 2))

    local backdrop, bottom = window.backdrop, FOOTER + CARD_INSET
    local editorLeft = CARD_INSET + LIST_W + GAP
    local inspectorLeft = WIDTH - CARD_INSET - INSPECTOR_W
    window.cards = {
        mine = { backdrop:Card(CARD_INSET, TOP, WIDTH - CARD_INSET - LIST_W, bottom),
            backdrop:Card(editorLeft, TOP, CARD_INSET + INSPECTOR_W + GAP, bottom),
            backdrop:Card(inspectorLeft, TOP, CARD_INSET, bottom) },
        smart = { backdrop:Card(CARD_INSET, TOP, CARD_INSET + INSPECTOR_W + GAP, bottom),
            backdrop:Card(inspectorLeft, TOP, CARD_INSET, bottom) },
        lib = { backdrop:Card(CARD_INSET, TOP, WIDTH - CARD_INSET - CLASS_W, bottom),
            backdrop:Card(CARD_INSET + CLASS_W + GAP, TOP, CARD_INSET, bottom) },
    }

    -- My Macros.
    window.mine = CreateFrame("Frame", nil, window)
    window.mine:SetAllPoints()
    local listArea = Area(CARD_INSET, WIDTH - CARD_INSET - LIST_W)
    listArea:SetParent(window.mine)
    local list = { area = listArea }
    list.scroll, list.body = Scroller(listArea, 4)
    list.rows = Pool(function() return NewMacroRow(list.body) end)
    list.sections = Pool(function() return NewSection(list.body) end)
    window.list = list
    local editorArea = Area(editorLeft, CARD_INSET + INSPECTOR_W + GAP)
    editorArea:SetParent(window.mine)
    BuildEditor(editorArea)
    local inspectorArea = Area(inspectorLeft, CARD_INSET)
    inspectorArea:SetParent(window.mine)
    BuildInspector(inspectorArea)

    -- Smart Macros.
    window.smartView = CreateFrame("Frame", nil, window)
    window.smartView:SetAllPoints()
    local smartArea = Area(CARD_INSET, CARD_INSET + INSPECTOR_W + GAP)
    smartArea:SetParent(window.smartView)
    local smartTitle = NewSection(smartArea)
    smartTitle:SetPoint("TOPLEFT")
    smartTitle:SetPoint("TOPRIGHT")
    SetSection(smartTitle, "Smart Macros", nil, "They keep themselves up to date from your bags and gear")
    local smart = {}
    smart.scroll, smart.body = Scroller(smartArea, SECTION_H + 10)
    smart.scroll:SetPoint("TOPLEFT", PAD, -(SECTION_H + 10))
    smart.cards = Pool(function() return NewSmartCard(smart.body) end)
    window.smart = smart
    local sideArea = Area(inspectorLeft, CARD_INSET)
    sideArea:SetParent(window.smartView)
    local sideTitle = NewSection(sideArea)
    sideTitle:SetPoint("TOPLEFT")
    sideTitle:SetPoint("TOPRIGHT")
    SetSection(sideTitle, "How They Work")
    window.smartSummary = Text14(sideArea, 13)
    window.smartSummary:SetPoint("TOPLEFT", PAD, -(SECTION_H + 12))
    window.smartSummary:SetPoint("RIGHT", -PAD, 0)
    window.smartSummary:SetJustifyH("LEFT")
    local sideNote = Text14(sideArea, 12, T.muted)
    sideNote:SetPoint("TOPLEFT", window.smartSummary, "BOTTOMLEFT", 0, -10)
    sideNote:SetPoint("RIGHT", -PAD, 0)
    sideNote:SetJustifyH("LEFT")
    sideNote:SetSpacing(3)
    sideNote:SetText("Each one is an account macro. Put it on a bar once and it keeps itself current: loot a "
        .. "better potion, conjure fresh food or pick up bandages and the macro is rewritten to use the best "
        .. "you carry.\n\nThe game does not let macros change mid-fight, so a change during combat waits "
        .. "until it ends.")

    -- Library.
    window.libView = CreateFrame("Frame", nil, window)
    window.libView:SetAllPoints()
    local classArea = Area(CARD_INSET, WIDTH - CARD_INSET - CLASS_W)
    classArea:SetParent(window.libView)
    local lib = {}
    local classTitle = NewSection(classArea)
    classTitle:SetPoint("TOPLEFT")
    classTitle:SetPoint("TOPRIGHT")
    SetSection(classTitle, "Classes")
    lib.classScroll, lib.classBody = Scroller(classArea, SECTION_H + 4)
    lib.classes = Pool(function() return NewClassRow(lib.classBody) end)
    local libArea = Area(CARD_INSET + CLASS_W + GAP, CARD_INSET)
    libArea:SetParent(window.libView)
    lib.title = ns.Font(libArea, 22)
    lib.title:SetPoint("TOPLEFT", PAD, -PAD)
    lib.lead = Text14(libArea, 12, T.muted)
    lib.lead:SetPoint("TOPLEFT", lib.title, "BOTTOMLEFT", 0, -6)
    lib.scroll, lib.body = Scroller(libArea, 64)
    lib.scroll:SetPoint("TOPLEFT", PAD, -64)
    lib.cards = Pool(function() return NewLibCard(lib.body) end)
    window.lib = lib

    Parts.FooterBrand(window, PAGE, CARD_INSET)
    Parts.FooterNote(window, "Macros are kept by the game: Account for every character, Character for this one")

    window:HookScript("OnShow", function(self)
        self:RegisterEvent("UPDATE_MACROS")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self.backdrop:Paint(S.Get("windowAlpha") or 1)
        Render()
    end)
    window:HookScript("OnHide", function(self) self:UnregisterAllEvents() end)
    window:SetScript("OnEvent", function() Render() end)
    SetTab(tab)
    window:Hide()
end

function ns.OpenMacroWindow(view)
    if not window then Build() end
    if view then SetTab(view) end
    window:SetScale(ns.UIScale())
    if window:IsShown() then Render() else window:Show() end
end

function ns.ToggleMacroWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenMacroWindow() end
end

-- A pack import or a profile switch changes what the Library holds.
hooksecurefunc(ns, "Apply", function() Render() end)

-- The Smart Macros and the window both read the module's settings.
hooksecurefunc(S, "Set", function(key)
    if not window then return end
    if key == "windowAlpha" then
        window.backdrop:Paint(S.Get("windowAlpha") or 1)
        window.opacity._refreshValue()
    elseif window:IsShown() then
        Render()
    end
end)
