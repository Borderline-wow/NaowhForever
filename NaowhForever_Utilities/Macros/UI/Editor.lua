-- Editor.lua: My Macros' editor in Naowh's Forge: the macro being written, its name, icon and list, its byte meter, the code box, and saving, undoing and deleting it.
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local M = ns.Macros
local S = M.Settings
local C = M.C
local St = M.Style
local Store = M.Store
local Sharing = M.Sharing
local Commands = M.Commands
local Text = M.Text
local P = M.Parts
local F = M.Forge

local QUESTION, LIMIT, NAME_MAX = C.QUESTION, C.LIMIT, C.NAME_MAX
local PAD, BUTTON_H, BUTTON_GAP, CODE_FONT = St.PAD, St.BUTTON_H, St.BUTTON_GAP, St.CODE_FONT
local BLACK, WARNING, ERROR = St.BORDER_RGB, St.WARNING_RGB, St.ERROR_RGB
local SMALL_SIZE, NOTE_SIZE = St.SMALL_SIZE, St.NOTE_SIZE
local SCROLLBAR_ROOM = St.SCROLLBAR_ROOM
local BIG_ICON = 52
local NAME_H, NAME_SIZE, NAME_GAP = 28, 18, 14
local SCOPE_W, SCOPE_H, SCOPE_FILL, SCOPE_DROP = 108, 20, 0.18, 2
local BODY_GAP = 12
local METER_H, METER_RIGHT, COUNT_GAP, COUNT_SIZE, SHORTEN_W = 6, 260, 10, 11, 74
local NEAR_LIMIT = 220
local FOOT_H = 2 * BUTTON_H + 3 * PAD
local CODE_SIZE, CODE_LINE_H = 13, 16
local CODE_INSET_X, CODE_INSET_Y = 10, 6
local GUTTER_W, GUTTER_PAD = 30, 6
local UNDO_MAX = 40
local DISABLED_ALPHA = 0.45
local SAVE_W, UNDO_W, REVERT_W, SHARE_W, LIBRARY_W, DELETE_W = 70, 60, 64, 60, 84, 64

local TEXT_NEW_MACRO = ns.L("New Macro")
local NEW_BODY = "#showtooltip\n/cast "
local TEXT_LOST = ns.L("That macro was changed or removed outside Macros. Save makes it again as a new macro.")
local TEXT_SAVE_IN_COMBAT = ns.L("Macros can be saved once the fight is over.")
local TEXT_DELETE_IN_COMBAT = ns.L("Macros can be deleted once the fight is over.")
local TEXT_BAD_NAME = ns.L("A macro's name is 1 to 16 bytes.")
local TEXT_BAD_BODY = ns.L("A macro's text is 1 to 255 bytes.")
local TEXT_TOO_LONG = ns.L("%d bytes over the game's 255: shorten it first.")
local TEXT_NAME_TAKEN = ns.L("You already have a macro called %s. Give this one another name.")
local TEXT_FULL = ns.L("%s macros are full. Delete one to make room.")
local TEXT_SAVED = ns.L("Saved %s. Drag its icon to an action bar.")
local TEXT_DELETE = ns.L("Delete %s? Its action bar buttons go with it.")
local TEXT_COUNT = ns.L("%s / 255 bytes%s")
local TEXT_LEFT = ns.L(" left")
local TEXT_SAVE, TEXT_SAVED_STATE, TEXT_CREATE = ns.L("Save"), ns.L("Saved"), ns.L("Create")
local TEXT_DRAG = ns.L("Drag the icon to an action bar")
local TEXT_NOT_SAVED = ns.L("Not saved yet")
local TEXT_UNSAVED = ns.L("Unsaved changes")
local TEXT_SHORTENED = ns.L("Shortened by %d bytes. It does the same.")
local TEXT_SHORTEST = ns.L("It is as short as it safely gets.")
local TEXT_NOTHING_TO_UNDO = ns.L("Nothing to undo.")
local TEXT_ICON_TIP, TEXT_ICON_HINT = ns.L("Icon"), ns.L("Click to pick another, drag to an action bar.")
local TEXT_SHORTEN_TIP = ns.L("Saves bytes with spellings the game reads the same way.")
local TEXT_LIBRARY_TIP = ns.L("Keeps a copy in the Library for every character of your class.")
local TEXT_SHARE_TIP = ns.L("This macro as a string to share.")
local TEXT_UNDO_TIP = ns.L("Takes back the last change.")
local TEXT_ACCOUNT, TEXT_CHARACTER = ns.L("Account"), ns.L("This Character")
local TEXT_ACCOUNT_TIP = ns.L("Account macros are on every character. Character macros only on this one.")
local COUNT_SEPARATOR = "  "

local function Code()
    return Text.Strip(F.window.code:GetText())
end

local function SetCode(body)
    F.window.code:SetText(Text.Colorize(body))
end

local function Simple()
    return S.Get("forgeMode") ~= "advanced"
end

local function Open(macro)
    local draft = { index = macro.index, account = macro.account == true, name = macro.name or TEXT_NEW_MACRO,
        icon = macro.icon or QUESTION, body = macro.body or "", undo = {} }
    draft.saved = draft.index and draft.body or nil
    draft.savedName = draft.index and draft.name or nil
    F.draft = draft
    local window = F.window
    if not window then return end
    window.name:SetText(draft.name)
    SetCode(draft.body)
    window.code:SetCursorPosition(0)
end

local function NewDraft(body, name)
    Open({ name = name or TEXT_NEW_MACRO, body = body or NEW_BODY, account = false })
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

local function Remember(draft)
    local undo = draft.undo
    if undo[#undo] == draft.body then return end
    undo[#undo + 1] = draft.body
    if #undo > UNDO_MAX then table.remove(undo, 1) end
end

local function SetBody(body, record)
    local draft = F.draft
    if body == draft.body then return end
    if record then Remember(draft) end
    draft.body = body
    SetCode(body)
    F.RenderEditor()
end

local function Undo()
    local draft = F.draft
    local undo = draft.undo
    if #undo == 0 then ns.Print(TEXT_NOTHING_TO_UNDO) return end
    draft.body = table.remove(undo)
    SetCode(draft.body)
    F.RenderEditor()
end

local function Save()
    if InCombatLockdown() then ns.Print(TEXT_SAVE_IN_COMBAT) return end
    local draft = F.draft
    local name, body = strtrim(F.window.name:GetText()), draft.body
    if not Store.NameFits(name) then ns.Print(TEXT_BAD_NAME) return end
    if #body > LIMIT then ns.Print(TEXT_TOO_LONG:format(#body - LIMIT)) return end
    if not Store.BodyFits(body) then ns.Print(TEXT_BAD_BODY) return end
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
        ns.Print(TEXT_FULL:format(draft.account and TEXT_ACCOUNT or TEXT_CHARACTER))
        return
    end
    draft.index = Store.Find(name, body, draft.account)
    draft.name, draft.saved, draft.savedName = name, body, name
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
    ns.Confirm(TEXT_DELETE:format(F.draft.savedName), DeleteNow)
end

local function ToLibrary()
    local name, body = strtrim(F.window.name:GetText()), F.draft.body
    if not Store.NameFits(name) then ns.Print(TEXT_BAD_NAME) return end
    if not Store.BodyFits(body) then ns.Print(TEXT_BAD_BODY) return end
    local draft = F.draft
    F.SaveToLibrary({ name = name, body = body, icon = (draft.picked or draft.index) and draft.icon or QUESTION })
end

local function Share()
    local name, body = strtrim(F.window.name:GetText()), F.draft.body
    if not Store.NameFits(name) then ns.Print(TEXT_BAD_NAME) return end
    if not Store.BodyFits(body) then ns.Print(TEXT_BAD_BODY) return end
    ns.ShowCopyBox(name, Sharing.Export({ { name = name, body = body } }))
end

local function Drag()
    local index = Current()
    if index and not InCombatLockdown() then PickupMacro(index) end
end

local function Shorten()
    local before = F.draft.body
    local after = Text.Shorten(before)
    SetBody(after, true)
    ns.Print(#after < #before and TEXT_SHORTENED:format(#before - #after) or TEXT_SHORTEST)
end

local function Revert()
    local draft = F.draft
    if not draft.saved then return end
    Remember(draft)
    F.window.name:SetText(draft.savedName)
    draft.name, draft.body = draft.savedName, draft.saved
    SetCode(draft.saved)
    F.RenderEditor()
end

local function Changed(draft)
    return draft.saved == nil or draft.saved ~= draft.body or draft.name ~= draft.savedName
end

local function KindColor(kind)
    return kind == "error" and ERROR or kind == "warning" and WARNING or T.muted
end

local function Gutter(issues)
    local editor = F.window.editor
    editor.numbers.Release()
    local kinds = {}
    for _, issue in ipairs(issues) do
        if issue.line > 0 and kinds[issue.line] ~= "error" then kinds[issue.line] = issue.kind end
    end
    local measure, y = editor.measure, 0
    for n, line in ipairs(Text.Lines(F.draft.body)) do
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

local function PaintScope(editor, draft)
    editor.scopeAccount:SetEnabled(draft.index == nil)
    editor.scopeCharacter:SetEnabled(draft.index == nil)
    P.Paint(editor.scopeAccount.label, draft.account and T.fg or T.muted)
    P.Paint(editor.scopeCharacter.label, draft.account and T.muted or T.fg)
    editor.scopeAccount.fill:SetShown(draft.account)
    editor.scopeCharacter.fill:SetShown(not draft.account)
end

local function Enable(button, on)
    button:SetEnabled(on)
    button:SetAlpha(on and 1 or DISABLED_ALPHA)
end

local function RenderChrome()
    local window, draft = F.window, F.draft
    local editor = window.editor
    PaintMeter(editor, #draft.body)
    editor.icon:SetTexture(Store.ShownIcon(Current(), (draft.picked or draft.index) and draft.icon or nil, draft.body))
    local changed = Changed(draft)
    editor.saveLabel:SetText(draft.index and (changed and TEXT_SAVE or TEXT_SAVED_STATE) or TEXT_CREATE)
    PaintScope(editor, draft)
    editor.where:SetText(not draft.index and TEXT_NOT_SAVED or changed and ns.Color("accent", TEXT_UNSAVED) or TEXT_DRAG)
    Enable(editor.revert, draft.saved ~= nil and changed)
    Enable(editor.undo, #draft.undo > 0)
end

local function RenderEditor()
    local window, draft = F.window, F.draft
    if not (window and draft) then return end
    RenderChrome()
    local issues = Text.Check(draft.body, Commands.Known())
    F.issues = issues
    local simple = Simple()
    window.editor.codeBox:SetShown(not simple)
    window.editor.simple:SetShown(simple)
    window.editor.share:SetShown(not simple)
    window.editor.toLibrary:SetShown(not simple)
    if simple then
        F.DrawSimple()
    else
        Gutter(issues)
        F.DrawInspector(issues)
    end
    F.DrawListMarks()
end

local function ScopeClick(b)
    F.draft.account = b.account
    RenderChrome()
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
    ns.Tooltip(b, text, TEXT_ACCOUNT_TIP)
    return b
end

local function NameChanged(box, user)
    if not user then return end
    F.draft.name = strtrim(box:GetText())
    RenderChrome()
    F.DrawListMarks()
end

local function IconClick(button)
    F.OpenIconPicker(button)
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
    editor.iconButton = iconButton
    return iconButton
end

local function BuildHeader(editor)
    local window = F.window
    local iconButton = BuildIcon(editor)
    window.name = ns.NewEditBox(editor)
    window.name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", NAME_GAP, 0)
    window.name:SetPoint("RIGHT", -PAD, 0)
    window.name:SetHeight(NAME_H)
    window.name:SetFont(ns.UIFontPath(), NAME_SIZE, "")
    window.name:SetMaxBytes(NAME_MAX + 1)
    window.name:SetScript("OnTextChanged", NameChanged)
    window.name:SetScript("OnEscapePressed", window.name.ClearFocus)
    window.name:SetScript("OnEnterPressed", window.name.ClearFocus)
    editor.scopeAccount = ScopeButton(editor, TEXT_ACCOUNT, true)
    editor.scopeAccount:SetPoint("BOTTOMLEFT", iconButton, "BOTTOMRIGHT", NAME_GAP, SCOPE_DROP)
    editor.scopeCharacter = ScopeButton(editor, TEXT_CHARACTER, false)
    editor.scopeCharacter:SetPoint("LEFT", editor.scopeAccount, "RIGHT", -1, 0)
    editor.where = P.Text(editor, SMALL_SIZE, T.muted)
    editor.where:SetPoint("RIGHT", -PAD, 0)
    editor.where:SetPoint("BOTTOM", editor.scopeAccount, "BOTTOM", 0, SCOPE_DROP)
    return iconButton
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
    local draft = F.draft
    local body = Text.Strip(shown)
    if not draft or body == draft.body then return end
    draft.body = body
    RenderEditor()
end

local function CodeFocused()
    Remember(F.draft)
end

local function PageSized(scroll, w)
    scroll.page:SetWidth(w)
    if F.draft and not Simple() then Gutter(F.issues or {}) end
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

local function NewNumber()
    return P.Text(F.window.editor.gutter, SMALL_SIZE, T.muted)
end

local function BuildCodeBox(editor, area)
    local box = CreateFrame("Frame", nil, area)
    box:SetAllPoints()
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(box, BLACK)
    local scroll = UI.SlimScroll(box)
    scroll:SetPoint("TOPLEFT", 1, -1)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_ROOM, 1)
    scroll.cursorTop, scroll.cursorHeight = 0, 0
    local page = CreateFrame("Frame", nil, scroll)
    page:SetSize(1, 1)
    scroll:SetScrollChild(page)
    scroll.page = page
    scroll:SetScript("OnSizeChanged", PageSized)
    editor.scroll, editor.page, editor.codeBox = scroll, page, box
    editor.gutter = CreateFrame("Frame", nil, page)
    editor.gutter:SetPoint("TOPLEFT")
    editor.gutter:SetPoint("BOTTOMLEFT")
    editor.gutter:SetWidth(GUTTER_W)
    local rule = ns.Solid(page, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", editor.gutter, "TOPRIGHT")
    rule:SetPoint("BOTTOMLEFT", editor.gutter, "BOTTOMRIGHT")
    ns.Hairline(rule, "v")
    editor.numbers = P.Pool(NewNumber)
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
    code:SetScript("OnEditFocusGained", CodeFocused)
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

local function BuildMeter(editor)
    editor.track = ns.Solid(editor, "ARTWORK", T.line, 1)
    editor.track:SetPoint("BOTTOMLEFT", PAD, PAD + BUTTON_H + PAD + (BUTTON_H - METER_H) / 2)
    editor.track:SetPoint("RIGHT", -METER_RIGHT, 0)
    editor.track:SetHeight(METER_H)
    editor.fill = editor:CreateTexture(nil, "OVERLAY")
    editor.fill:SetPoint("TOPLEFT", editor.track)
    editor.fill:SetHeight(METER_H)
    editor.count = P.Text(editor, NOTE_SIZE, T.muted)
    editor.count:SetFont(CODE_FONT, COUNT_SIZE, "")
    editor.count:SetPoint("LEFT", editor.track, "RIGHT", COUNT_GAP, 0)
    local shorten = ns.Button(editor, "Shorten", SHORTEN_W, BUTTON_H, Shorten)
    shorten:SetPoint("BOTTOMRIGHT", -PAD, PAD + BUTTON_H + PAD)
    ns.Tooltip(shorten, "Shorten", TEXT_SHORTEN_TIP)
end

local function BuildActions(editor)
    local save = ns.AccentBorder(ns.Button(editor, "Save", SAVE_W, BUTTON_H, Save))
    save:SetPoint("BOTTOMLEFT", PAD, PAD)
    editor.saveButton, editor.saveLabel = save, save.label
    editor.undo = ns.Button(editor, "Undo", UNDO_W, BUTTON_H, Undo)
    editor.undo:SetPoint("LEFT", save, "RIGHT", BUTTON_GAP, 0)
    ns.Tooltip(editor.undo, "Undo", TEXT_UNDO_TIP)
    editor.revert = ns.Button(editor, "Revert", REVERT_W, BUTTON_H, Revert)
    editor.revert:SetPoint("LEFT", editor.undo, "RIGHT", BUTTON_GAP, 0)
    editor.share = ns.Button(editor, "Share", SHARE_W, BUTTON_H, Share)
    editor.share:SetPoint("LEFT", editor.revert, "RIGHT", BUTTON_GAP, 0)
    ns.Tooltip(editor.share, "Share", TEXT_SHARE_TIP)
    editor.toLibrary = ns.Button(editor, "To Library", LIBRARY_W, BUTTON_H, ToLibrary)
    editor.toLibrary:SetPoint("LEFT", editor.share, "RIGHT", BUTTON_GAP, 0)
    ns.Tooltip(editor.toLibrary, "To Library", TEXT_LIBRARY_TIP)
    editor.deleteButton = ns.Button(editor, "Delete", DELETE_W, BUTTON_H, Delete)
    editor.deleteButton:SetPoint("BOTTOMRIGHT", -PAD, PAD)
end

local function BuildEditor(parent)
    local editor = CreateFrame("Frame", nil, parent)
    editor:SetAllPoints()
    F.window.editor = editor
    local iconButton = BuildHeader(editor)
    local area = CreateFrame("Frame", nil, editor)
    area:SetPoint("TOPLEFT", iconButton, "BOTTOMLEFT", 0, -BODY_GAP)
    area:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H)
    editor.area = area
    BuildCodeBox(editor, area)
    editor.simple = F.BuildSimple(area)
    BuildMeter(editor)
    BuildActions(editor)
end

F.Code, F.SetBody, F.Open, F.NewDraft, F.Current, F.Simple = Code, SetBody, Open, NewDraft, Current, Simple
F.RenderEditor, F.BuildEditor = RenderEditor, BuildEditor
