-- Editor.lua: Naowh's Forge's editor: the macro being written, its byte meter, line numbers and problems, and saving it (ns.Macros.Forge).
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local M = ns.Macros
local C = M.C
local St = M.Style
local Store = M.Store
local Sharing = M.Sharing
local P = M.Parts
local Text = ns.MacroText

local QUESTION, LIMIT, NAME_MAX = C.QUESTION, C.LIMIT, C.NAME_MAX
local PAD, BUTTON_H, CODE_FONT = St.PAD, St.BUTTON_H, St.CODE_FONT
local BLACK, WARNING, ERROR, OK = St.BORDER_RGB, St.WARNING_RGB, St.ERROR_RGB, St.OK_RGB
local SMALL_SIZE, NOTE_SIZE = St.SMALL_SIZE, St.NOTE_SIZE
local BIG_ICON = 56
local NAME_H, NAME_SIZE, NAME_GAP = 30, 20, 14
local SAVE_TO_DROP, SCOPE_GAP, GRIP_GAP = 2, 8, 8
local SCOPE_W, SCOPE_H, SCOPE_FILL = 108, 20, 0.18
local GRIP_W, GRIP_H, GRIP_DOT, GRIP_STEP, GRIP_DOTS, GRIP_COLS = 6, 10, 2, 4, 6, 2
local METER_H, METER_TOP, METER_RIGHT, COUNT_GAP, COUNT_SIZE = 6, 16, 200, 10, 11
local NEAR_LIMIT = 220
local CODE_SIZE, CODE_LINES, CODE_LINE_GAP, CODE_BOX_GAP = 13, 10, 4, 12
local CODE_LINE_H = CODE_SIZE + 3
local CODE_INSET_X, CODE_INSET_Y = 10, 6
local GUTTER_W, GUTTER_PAD = 30, 6
local SCROLLBAR_ROOM = St.SCROLLBAR_ROOM
local ISSUE_LINES, ISSUE_TOP, ISSUE_STEP, ISSUE_INDENT = 4, 8, 16, 2
local BUTTON_GAP, DISABLED_ALPHA = St.BUTTON_GAP, 0.45
local SAVE_W, SHORTEN_W, EXPORT_W, REVERT_W, LIBRARY_W, DELETE_W = 80, 74, 64, 64, 80, 64

local TEXT_NEW_MACRO = "New Macro"
local NEW_BODY = "#showtooltip\n/cast "
local TEXT_LOST = "That macro was changed or removed outside the Forge. Save makes it again as a new macro."
local TEXT_SAVE_IN_COMBAT = "Macros can be saved once the fight is over."
local TEXT_DELETE_IN_COMBAT = "Macros can be deleted once the fight is over."
local TEXT_BAD_NAME = "A macro's name is 1 to 16 bytes."
local TEXT_BAD_BODY = "A macro's text is 1 to 255 bytes."
local TEXT_TOO_LONG = "%d bytes over the game's 255: shorten it first."
local TEXT_NAME_TAKEN = "You already have a macro called %s. Give this one another name."
local TEXT_FULL = "%s macros are full. Delete one to make room."
local TEXT_SAVED = "Saved %s. Drag its icon to an action bar."
local TEXT_DELETE = "Delete %s? Its action bar buttons go with it."
local TEXT_LIBRARY_UPDATED = "Updated %s in your Library."
local TEXT_LIBRARY_SAVED = "Saved %s to your Library, for every %s you play."
local TEXT_COUNT = "%s / 255 bytes%s"
local TEXT_LEFT = " left"
local TEXT_LOOKS_GOOD = "Looks good: every command and condition is one the game knows."
local TEXT_SAVE, TEXT_SAVED_STATE, TEXT_CREATE = "Save", "Saved", "Create"
local TEXT_DRAG = "Drag the icon to an action bar"
local TEXT_FROM_PACK = "From your pack: Create makes it yours"
local TEXT_FROM_LIBRARY = "From your Library: Create makes it a macro"
local TEXT_NOT_SAVED = "Not saved yet"
local TEXT_SAVED_TO = "Saved to"
local TEXT_SHORTENED = "Shortened by %d bytes. It does the same."
local TEXT_SHORTEST = "It is as short as it safely gets."
local TEXT_ICON_TIP, TEXT_ICON_HINT = "Icon", "Click to pick another, drag to an action bar."
local TEXT_SHORTEN_TIP = "Saves bytes with spellings the game reads the same way: @ for target=, "
    .. "mod: and btn:, and no spaces around ; and ,."
local TEXT_LIBRARY_TIP = "Keeps a copy in the Library under your class, for every character "
    .. "of that class. Saving it again under the same name replaces it."
local ISSUE_LINE = "L%d   "
local COUNT_SEPARATOR = "  "

local F = { tab = "mine" }
M.Forge = F

local issueKinds = {}

local function Code()
    return Text.Strip(F.window.code:GetText())
end

local function SetCode(body)
    F.window.code:SetText(Text.Colorize(body))
end

local function Open(macro)
    local draft = { index = macro.index, account = macro.account == true, name = macro.name or TEXT_NEW_MACRO,
        icon = macro.icon or QUESTION, body = macro.body or "", source = macro.source or "game" }
    draft.saved = draft.index and draft.body or nil
    draft.savedName = draft.index and draft.name or nil
    draft.picked = (draft.source == "pack" or draft.source == "library") and macro.icon ~= nil or nil
    F.draft = draft
    local window = F.window
    if not window then return end
    window.name:SetText(draft.name)
    SetCode(draft.body)
    window.code:SetCursorPosition(0)
    window.editor.scroll:SetVerticalScroll(0)
end

local function NewDraft(body, name, source)
    Open({ name = name or TEXT_NEW_MACRO, body = body or NEW_BODY, account = false, source = source or "new" })
end

local function Current()
    local draft = F.draft
    return draft and draft.index and Store.Find(draft.savedName, draft.saved, draft.account)
end

local function Lost()
    local draft = F.draft
    draft.index, draft.saved, draft.savedName = nil, nil, nil
    ns.Print(TEXT_LOST)
    F.Render()
end

local function Save()
    if InCombatLockdown() then ns.Print(TEXT_SAVE_IN_COMBAT) return end
    local draft = F.draft
    local name, body = strtrim(F.window.name:GetText()), Code()
    if not Store.NameFits(name) then ns.Print(TEXT_BAD_NAME) return end
    if #body > LIMIT then ns.Print(TEXT_TOO_LONG:format(#body - LIMIT)) return end
    if name ~= draft.savedName and GetMacroIndexByName(name) > 0 then
        ns.Print(TEXT_NAME_TAKEN:format(name))
        return
    end
    if draft.index then
        local index = Current()
        if not index then return Lost() end
        EditMacro(index, name, draft.picked and draft.icon or nil, body)
    elseif Store.Room(draft.account) then
        CreateMacro(name, draft.picked and draft.icon or QUESTION, body, not draft.account)
    else
        ns.Print(TEXT_FULL:format(draft.account and "Account" or "Character"))
        return
    end
    draft.index = Store.Find(name, body, draft.account)
    draft.name, draft.body, draft.saved, draft.savedName, draft.source = name, body, body, name, "game"
    ns.Print(TEXT_SAVED:format(name))
    F.Render()
end

local function DeleteNow()
    if InCombatLockdown() then ns.Print(TEXT_DELETE_IN_COMBAT) return end
    local index = Current()
    if not index then return Lost() end
    DeleteMacro(index)
    NewDraft()
    F.Render()
end

local function Delete()
    if not F.draft.index then
        NewDraft()
        F.Render()
        return
    end
    ns.Confirm(TEXT_DELETE:format(F.draft.name), DeleteNow)
end

local function LibraryList(class)
    local account = ns.AccountSettings()
    account.libraryMacros = account.libraryMacros or {}
    account.libraryMacros[class] = account.libraryMacros[class] or {}
    return account.libraryMacros[class]
end

local function SaveToLibrary()
    local name, body = strtrim(F.window.name:GetText()), Code()
    if not Store.NameFits(name) then ns.Print(TEXT_BAD_NAME) return end
    if not Store.BodyFits(body) then ns.Print(TEXT_BAD_BODY) return end
    local _, class = UnitClass("player")
    local list = LibraryList(class)
    local draft = F.draft
    local icon = (draft.picked or draft.source == "game") and draft.icon ~= QUESTION and draft.icon or nil
    local entry = { name = name, body = body, icon = icon, pack = draft.source == "pack" or nil }
    for i, e in ipairs(list) do
        if e.name == name then
            list[i] = entry
            ns.Print(TEXT_LIBRARY_UPDATED:format(name))
            return
        end
    end
    list[#list + 1] = entry
    ns.Print(TEXT_LIBRARY_SAVED:format(name, LOCALIZED_CLASS_NAMES_MALE[class] or class))
end

local function Drag()
    local index = Current()
    if index and not InCombatLockdown() then PickupMacro(index) end
end

local function Shorten()
    local before = Code()
    local after = Text.Shorten(before)
    SetCode(after)
    ns.Print(#after < #before and TEXT_SHORTENED:format(#before - #after) or TEXT_SHORTEST)
end

local function ExportOne()
    local name, body = strtrim(F.window.name:GetText()), Code()
    if not Store.NameFits(name) then ns.Print(TEXT_BAD_NAME) return end
    if not Store.BodyFits(body) then ns.Print(TEXT_BAD_BODY) return end
    ns.ShowCopyBox(name, Sharing.Export({ { name = name, body = body } }))
end

local function Revert()
    local draft = F.draft
    if not draft.saved then return end
    F.window.name:SetText(draft.savedName)
    SetCode(draft.saved)
    F.RenderEditor()
end

local function IssueKinds(issues)
    wipe(issueKinds)
    for _, issue in ipairs(issues or {}) do
        if issue.line > 0 then
            local was = issueKinds[issue.line]
            issueKinds[issue.line] = (was == "error" or issue.kind == "error") and "error" or "warning"
        end
    end
    return issueKinds
end

local function KindColor(kind)
    return kind == "error" and ERROR or kind == "warning" and WARNING or T.muted
end

local function Gutter()
    local editor = F.window.editor
    editor.numbers.Release()
    local measure, y, n = editor.measure, 0, 0
    local kinds = IssueKinds(editor.issues)
    for line in (Code() .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local label = editor.numbers.Take()
        label:SetPoint("TOPRIGHT", editor.gutter, "TOPRIGHT", -GUTTER_PAD, -(CODE_INSET_Y + y))
        label:SetText(n)
        P.Paint(label, KindColor(kinds[n]))
        measure:SetText(line ~= "" and line or " ")
        y = y + math.max(CODE_LINE_H, measure:GetStringHeight())
    end
    local height = math.max(editor.scroll:GetHeight(), y + 2 * CODE_INSET_Y)
    editor.page:SetHeight(height)
    if height == editor.codeHeight then return end
    editor.codeHeight = height
    F.window.code:SetHeight(height)
end

local function PaintMeter(editor, bytes)
    local fill = math.min(1, bytes / LIMIT)
    editor.fill:SetWidth(math.max(1, (editor.track:GetWidth() or 1) * fill))
    local c = bytes > LIMIT and ERROR or bytes > NEAR_LIMIT and WARNING or T.accent
    editor.fill:SetColorTexture(c.r, c.g, c.b, 1)
    editor.count:SetText(TEXT_COUNT:format(ns.Color("fg", bytes),
        bytes <= LIMIT and (COUNT_SEPARATOR .. ns.Color("muted", (LIMIT - bytes) .. TEXT_LEFT)) or ""))
end

local function PaintIssues(editor, body)
    editor.issues = Text.Check(body, ns.MacroKnownCommands())
    for i = 1, ISSUE_LINES do
        local fs, issue = editor.issueLines[i], editor.issues[i]
        if issue then
            fs:SetText((issue.line > 0 and ISSUE_LINE:format(issue.line) or "") .. issue.text)
            P.Paint(fs, issue.kind == "error" and ERROR or WARNING)
        elseif i == 1 and body ~= "" then
            fs:SetText(TEXT_LOOKS_GOOD)
            P.Paint(fs, OK)
        else
            fs:SetText("")
        end
    end
end

local function Where(draft)
    if draft.index then return TEXT_DRAG end
    if draft.source == "pack" then return TEXT_FROM_PACK end
    if draft.source == "library" then return TEXT_FROM_LIBRARY end
    return TEXT_NOT_SAVED
end

local function PaintScope(editor, draft)
    editor.scopeAccount:SetEnabled(draft.index == nil)
    editor.scopeCharacter:SetEnabled(draft.index == nil)
    P.Paint(editor.scopeAccount.label, draft.account and T.fg or T.muted)
    P.Paint(editor.scopeCharacter.label, draft.account and T.muted or T.fg)
    editor.scopeAccount.fill:SetShown(draft.account)
    editor.scopeCharacter.fill:SetShown(not draft.account)
end

local function RenderEditor()
    local window, draft = F.window, F.draft
    if not (window and draft) then return end
    local editor, body = window.editor, Code()
    draft.body = body
    PaintMeter(editor, #body)
    PaintIssues(editor, body)
    Gutter()
    editor.icon:SetTexture(Store.ShownIcon(Current(), draft.picked and draft.icon or (draft.index and draft.icon), body))
    local changed = draft.saved == nil or draft.saved ~= body or (draft.index and window.name:GetText() ~= draft.name)
    editor.saveLabel:SetText(draft.index and (changed and TEXT_SAVE or TEXT_SAVED_STATE) or TEXT_CREATE)
    PaintScope(editor, draft)
    editor.where:SetText(Where(draft))
    editor.grip:SetShown(draft.index ~= nil)
    local dirty = draft.saved ~= nil and changed
    editor.revert:SetEnabled(dirty)
    editor.revert:SetAlpha(dirty and 1 or DISABLED_ALPHA)
    if window.inspector and window.inspector.Refresh then window.inspector.Refresh() end
end

local function ScopeClick(b)
    F.draft.account = b.account
    RenderEditor()
end

local function ScopeButton(parent, text, account)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SCOPE_W, SCOPE_H)
    b.account = account
    ns.Solid(b, "BACKGROUND", T.panel, 1):SetAllPoints()
    b.fill = ns.Solid(b, "BACKGROUND", T.accent, SCOPE_FILL)
    b.fill:SetAllPoints()
    ns.Border(b, BLACK)
    b.label = P.Text(b, SMALL_SIZE)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnClick", ScopeClick)
    return b
end

local function NameChanged(_, user)
    if user then RenderEditor() end
end

local function IconClick()
    F.window.inspector.Show("icons")
end

local function BuildIcon(editor)
    local iconButton = CreateFrame("Button", nil, editor)
    iconButton:SetSize(BIG_ICON, BIG_ICON)
    iconButton:SetPoint("TOPLEFT", PAD, -PAD)
    iconButton:RegisterForDrag("LeftButton")
    editor.icon = P.Icon(iconButton, BIG_ICON - St.ICON_EDGES)
    editor.icon.edge:SetPoint("TOPLEFT")
    iconButton:SetScript("OnClick", IconClick)
    iconButton:SetScript("OnDragStart", Drag)
    ns.Tooltip(iconButton, TEXT_ICON_TIP, TEXT_ICON_HINT)
    return iconButton
end

local function BuildName(editor, iconButton)
    local window = F.window
    window.name = ns.NewEditBox(editor)
    window.name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", NAME_GAP, 0)
    window.name:SetPoint("RIGHT", -PAD, 0)
    window.name:SetHeight(NAME_H)
    window.name:SetFont(ns.UIFontPath(), NAME_SIZE, "")
    window.name:SetMaxBytes(NAME_MAX + 1)
    window.name:SetScript("OnTextChanged", NameChanged)
end

local function BuildGrip(editor)
    editor.grip = CreateFrame("Frame", nil, editor)
    editor.grip:SetSize(GRIP_W, GRIP_H)
    editor.grip:SetPoint("RIGHT", editor.where, "LEFT", -GRIP_GAP, 0)
    for i = 0, GRIP_DOTS - 1 do
        local dot = ns.Solid(editor.grip, "ARTWORK", T.muted, 1)
        dot:SetSize(GRIP_DOT, GRIP_DOT)
        dot:SetPoint("TOPLEFT", (i % GRIP_COLS) * GRIP_STEP, -math.floor(i / GRIP_COLS) * GRIP_STEP)
    end
end

local function BuildScope(editor, iconButton)
    local saveTo = P.Text(editor, SMALL_SIZE, T.muted)
    saveTo:SetPoint("BOTTOMLEFT", iconButton, "BOTTOMRIGHT", NAME_GAP, SAVE_TO_DROP)
    saveTo:SetText(TEXT_SAVED_TO)
    editor.scopeAccount = ScopeButton(editor, "Account", true)
    editor.scopeAccount:SetPoint("LEFT", saveTo, "RIGHT", SCOPE_GAP, 0)
    editor.scopeCharacter = ScopeButton(editor, "This Character", false)
    editor.scopeCharacter:SetPoint("LEFT", editor.scopeAccount, "RIGHT", -1, 0)
    editor.where = P.Text(editor, SMALL_SIZE, T.muted)
    editor.where:SetPoint("RIGHT", -PAD, 0)
    editor.where:SetPoint("BOTTOM", saveTo, "BOTTOM")
    BuildGrip(editor)
end

local function BuildMeter(editor, iconButton)
    editor.track = ns.Solid(editor, "ARTWORK", T.line, 1)
    editor.track:SetPoint("TOPLEFT", iconButton, "BOTTOMLEFT", 0, -METER_TOP)
    editor.track:SetPoint("RIGHT", -METER_RIGHT, 0)
    editor.track:SetHeight(METER_H)
    editor.fill = editor:CreateTexture(nil, "OVERLAY")
    editor.fill:SetPoint("TOPLEFT", editor.track)
    editor.fill:SetHeight(METER_H)
    editor.count = P.Text(editor, NOTE_SIZE, T.muted)
    editor.count:SetFont(CODE_FONT, COUNT_SIZE, "")
    editor.count:SetPoint("LEFT", editor.track, "RIGHT", COUNT_GAP, 0)
end

local function CodeChanged(code)
    local shown = code:GetText()
    local colored = Text.Colorize(Text.Strip(shown))
    if colored ~= shown then
        local at = Text.PlainPos(shown, code:GetCursorPosition())
        code:SetText(colored)
        code:SetCursorPosition(Text.CodedPos(colored, at))
        return
    end
    RenderEditor()
end

local function PageSized(scroll, w)
    scroll.page:SetWidth(w)
    RenderEditor()
end

local function Follow(scroll)
    local at, shown = scroll:GetVerticalScroll(), scroll:GetHeight()
    local top, height = scroll.cursorTop, scroll.cursorHeight
    if top < at then
        scroll:SetVerticalScroll(top)
    elseif top + height > at + shown then
        scroll:SetVerticalScroll(top + height - shown)
    end
end

local function CursorMoved(code, _, y, _, h)
    local scroll = code.scroll
    scroll.cursorTop, scroll.cursorHeight = -y, h
    Follow(scroll)
end

local function BoxClicked(box)
    box.code:SetFocus()
end

local function BuildBox(editor)
    local box = CreateFrame("Frame", nil, editor)
    box:SetPoint("TOPLEFT", editor.track, "BOTTOMLEFT", 0, -CODE_BOX_GAP)
    box:SetPoint("RIGHT", -PAD, 0)
    box:SetHeight(CODE_LINES * (CODE_SIZE + CODE_LINE_GAP) + 2 * CODE_INSET_Y)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(box, BLACK)
    local scroll = UI.SlimScroll(box)
    scroll:SetPoint("TOPLEFT", 1, -1)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_ROOM, 1)
    scroll.cursorTop, scroll.cursorHeight = 0, 0
    local page = CreateFrame("Frame", nil, scroll)
    page:SetSize(1, box:GetHeight())
    scroll:SetScrollChild(page)
    scroll.page = page
    scroll:SetScript("OnSizeChanged", PageSized)
    editor.scroll, editor.page = scroll, page
    return box, scroll, page
end

local function NewNumber()
    return P.Text(F.window.editor.gutter, SMALL_SIZE, T.muted)
end

local function BuildGutter(editor, page)
    editor.gutter = CreateFrame("Frame", nil, page)
    editor.gutter:SetPoint("TOPLEFT")
    editor.gutter:SetPoint("BOTTOMLEFT")
    editor.gutter:SetWidth(GUTTER_W)
    local rule = ns.Solid(page, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", editor.gutter, "TOPRIGHT")
    rule:SetPoint("BOTTOMLEFT", editor.gutter, "BOTTOMRIGHT")
    ns.Hairline(rule, "v")
    editor.numbers = P.Pool(NewNumber)
end

local function BuildCode(editor, box, scroll, page)
    local code = CreateFrame("EditBox", nil, page)
    code:SetPoint("TOPLEFT", GUTTER_W + 1, 0)
    code:SetPoint("TOPRIGHT")
    code:SetMultiLine(true)
    code:SetAutoFocus(false)
    code:SetMaxLetters(0)
    code:SetFont(CODE_FONT, CODE_SIZE, "")
    code:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    code:SetTextInsets(CODE_INSET_X, CODE_INSET_X, CODE_INSET_Y, CODE_INSET_Y)
    code:SetScript("OnEscapePressed", code.ClearFocus)
    code:SetScript("OnTextChanged", CodeChanged)
    code.scroll = scroll
    code:SetScript("OnCursorChanged", CursorMoved)
    scroll:HookScript("OnScrollRangeChanged", Follow)
    box.code = code
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", BoxClicked)
    F.window.code = code
    editor.measure = page:CreateFontString(nil, "ARTWORK")
    editor.measure:SetFont(CODE_FONT, CODE_SIZE, "")
    editor.measure:SetPoint("TOPLEFT", code, "TOPLEFT", CODE_INSET_X, 0)
    editor.measure:SetPoint("RIGHT", code, "RIGHT", -CODE_INSET_X, 0)
    editor.measure:SetAlpha(0)
end

local function BuildIssues(editor, box)
    editor.issueLines = {}
    for i = 1, ISSUE_LINES do
        local fs = P.Text(editor, NOTE_SIZE)
        fs:SetPoint("TOPLEFT", box, "BOTTOMLEFT", ISSUE_INDENT, -ISSUE_TOP - (i - 1) * ISSUE_STEP)
        fs:SetPoint("RIGHT", -PAD, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        editor.issueLines[i] = fs
    end
end

local function BuildActions(editor)
    local save = ns.AccentBorder(ns.Button(editor, "Save", SAVE_W, BUTTON_H, Save))
    save:SetPoint("BOTTOMLEFT", PAD, PAD)
    editor.saveLabel = save.label
    local shorten = ns.Button(editor, "Shorten", SHORTEN_W, BUTTON_H, Shorten)
    shorten:SetPoint("LEFT", save, "RIGHT", BUTTON_GAP, 0)
    ns.Tooltip(shorten, "Shorten", TEXT_SHORTEN_TIP)
    local export = ns.Button(editor, "Export", EXPORT_W, BUTTON_H, ExportOne)
    export:SetPoint("LEFT", shorten, "RIGHT", BUTTON_GAP, 0)
    local revert = ns.Button(editor, "Revert", REVERT_W, BUTTON_H, Revert)
    revert:SetPoint("LEFT", export, "RIGHT", BUTTON_GAP, 0)
    editor.revert = revert
    local toLibrary = ns.Button(editor, "To Library", LIBRARY_W, BUTTON_H, SaveToLibrary)
    toLibrary:SetPoint("LEFT", revert, "RIGHT", BUTTON_GAP, 0)
    ns.Tooltip(toLibrary, "Save to Library", TEXT_LIBRARY_TIP)
    local delete = ns.Button(editor, "Delete", DELETE_W, BUTTON_H, Delete)
    delete:SetPoint("BOTTOMRIGHT", -PAD, PAD)
end

local function BuildEditor(parent)
    local editor = CreateFrame("Frame", nil, parent)
    editor:SetAllPoints()
    F.window.editor = editor
    local iconButton = BuildIcon(editor)
    BuildName(editor, iconButton)
    BuildScope(editor, iconButton)
    BuildMeter(editor, iconButton)
    local box, scroll, page = BuildBox(editor)
    BuildGutter(editor, page)
    BuildCode(editor, box, scroll, page)
    BuildIssues(editor, box)
    BuildActions(editor)
end

F.Code, F.SetCode, F.Open, F.NewDraft, F.Current = Code, SetCode, Open, NewDraft, Current
F.RenderEditor, F.BuildEditor = RenderEditor, BuildEditor
