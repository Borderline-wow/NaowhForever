-- Builder.lua: the Forge's Build view: each line as a sentence edited with menus, the problems with a fix, lines and recipes to add, and Test it, which answers what one press does.
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local M = ns.Macros
local C = M.C
local St = M.Style
local Text = M.Text
local P = M.Parts
local F = M.Forge
local Parts = ns.Shared.Parts

local BLACK = St.BORDER_RGB
local WARNING, ERROR, CHIP = St.WARNING_RGB, St.ERROR_RGB, St.CHIP_RGB
local SMALL_SIZE, NOTE_SIZE, TEXT_SIZE = St.SMALL_SIZE, St.NOTE_SIZE, St.TEXT_SIZE
local SCROLLBAR_ROOM, TAB_H = St.SCROLLBAR_ROOM, St.TAB_H
local SECTION_GAP, BLOCK_GAP = 14, 8
local TITLE_H, HINT_GAP = 18, 4
local CARD_PAD, CARD_HEAD_H, CARD_FILL = 10, 20, 0.04
local ROW_H, ROW_GAP, CHIP_GAP, LABEL_W, VERB_W = 22, 8, 4, 92, 70
local UNIT_W, ADD_W, X_W, CHIP_PAD, OTHERWISE_W = 150, 72, 20, 24, 110
local ISSUE_FIX_W, ISSUE_GAP = 56, 6
local LINE_BUTTON_W, RECIPE_H = 120, 40
local SPELL_W = 220
local ANSWER_PAD, ANSWER_FILL = 10, 0.08
local CHIP_FILL, CHIP_TEXT_X, CHIP_X_X, RECIPE_TEXT_Y = 0.08, 8, 6, 8
local QUESTION_GAP = 6

local NEW_BODY = "#showtooltip\n/cast "
local DEFAULT_UNIT = "target"
local SHOWTOOLTIP = "#showtooltip"
local SPELL_COMMANDS = { ["/cast"] = true, ["/castrandom"] = true }

local TEXT_PROBLEMS = ns.L("Problems")
local TEXT_FIX = ns.L("Fix it")
local TEXT_LINE = ns.L("Line %d")
local TEXT_WHOLE = ns.L("Whole macro")
local TEXT_IF, TEXT_ELSE_IF, TEXT_ELSE, TEXT_ALWAYS = ns.L("If"), ns.L("Otherwise, if"), ns.L("Otherwise"), ns.L("Always")
local TEXT_WHEN = ns.L("+ when")
local TEXT_OTHERWISE = ns.L("+ Otherwise")
local TEXT_SHOWS = ns.L("Button shows")
local TEXT_SHOWS_HINT = ns.L("Leave empty to show what the macro will cast.")
local TEXT_RAW = ns.L("Edit this line in Advanced.")
local TEXT_EMPTY = ns.L("Nothing written yet. Add a line or start from a recipe.")
local TEXT_ADD_LINE = ns.L("Add a line")
local TEXT_RECIPES = ns.L("Start from a recipe")
local TEXT_RECIPE_HINT = ns.L("Type the spell once, then pick what the macro should do with it.")
local TEXT_SPELL_FIRST = ns.L("Type the spell for the recipe first.")
local TEXT_REPLACE = ns.L("Replace this macro's text with the recipe? Undo brings it back.")
local TEXT_TEST = ns.L("Test it")
local TEXT_TEST_HINT = ns.L("Answer what the macro depends on and see what one press does.")
local TEXT_SAME = ns.L("It does the same thing on every press.")
local TEXT_PRESS = ns.L("When you press it")
local TEXT_NOTHING = ns.L("Nothing happens.")
local TEXT_SKIPPED = ns.L("Only one spell or item goes off per press: %s is skipped.")
local TEXT_STOPPED = ns.L("The rest of the macro is not reached.")
local TEXT_UNIT_TIP = ns.L("Who the line aims at")

local UNITS = { "target", "mouseover", "focus", "player", "targettarget", "pet", "cursor" }

local WHEN = {
    { title = ns.L("The unit") },
    { "help", ns.L("is friendly") }, { "harm", ns.L("is hostile") }, { "nodead", ns.L("is alive") },
    { "dead", ns.L("is dead") }, { "exists", ns.L("exists") },
    { title = ns.L("You") },
    { "combat", ns.L("are in combat") }, { "nocombat", ns.L("are out of combat") },
    { "mounted", ns.L("are mounted") }, { "nomounted", ns.L("are not mounted") },
    { title = ns.L("Key held") },
    { "mod:shift", ns.L("Shift") }, { "mod:ctrl", ns.L("Ctrl") }, { "mod:alt", ns.L("Alt") },
    { "nomod", ns.L("No modifier") },
    { title = ns.L("Stance or form") },
    { "stance:1", ns.L("Stance 1") }, { "stance:2", ns.L("Stance 2") }, { "stance:3", ns.L("Stance 3") },
    { "stance:4", ns.L("Stance 4") },
}

local CHIP_WORDS = {
    help = ns.L("friendly"), harm = ns.L("hostile"), nodead = ns.L("alive"), dead = ns.L("dead"),
    exists = ns.L("exists"), noexists = ns.L("missing"), combat = ns.L("in combat"), nocombat = ns.L("out of combat"),
    mounted = ns.L("mounted"), nomounted = ns.L("not mounted"), ["mod:shift"] = ns.L("Shift held"),
    ["mod:ctrl"] = ns.L("Ctrl held"), ["mod:alt"] = ns.L("Alt held"), nomod = ns.L("no key held"),
    mod = ns.L("any key held"),
}

local OPPOSITE = { help = "harm", harm = "help", dead = "nodead", nodead = "dead", combat = "nocombat",
    nocombat = "combat", mounted = "nomounted", nomounted = "mounted", exists = "noexists", noexists = "exists" }

local VERBS = { ["/cast"] = ns.L("Cast"), ["/use"] = ns.L("Use"), ["/castsequence"] = ns.L("Cast in order"),
    ["/castrandom"] = ns.L("Cast one of"), ["/userandom"] = ns.L("Use one of"), ["/target"] = ns.L("Target"),
    ["/focus"] = ns.L("Focus"), ["/cancelaura"] = ns.L("Remove"), ["/equip"] = ns.L("Equip") }

local LINES = {
    { label = ns.L("Cast a spell"), text = "/cast " },
    { label = ns.L("Use an item"), text = "/use " },
    { label = ns.L("Stop casting"), text = "/stopcasting" },
    { label = ns.L("Start attacking"), text = "/startattack" },
    { label = ns.L("Show on button"), text = SHOWTOOLTIP, top = true },
}

local RECIPES = {
    { title = ns.L("Heal the unit under my mouse"), note = ns.L("Else your friendly target, else yourself."),
      text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] %s" },
    { title = ns.L("Attack the unit under my mouse"), note = ns.L("Else your target."),
      text = "#showtooltip\n/cast [@mouseover,harm,nodead][] %s" },
    { title = ns.L("Cast on myself while Alt is held"), note = ns.L("Else on your target."),
      text = "#showtooltip\n/cast [mod:alt,@player][] %s" },
    { title = ns.L("Cast on my focus"), note = ns.L("Else on your target."),
      text = "#showtooltip\n/cast [@focus,exists,nodead][] %s" },
}

local QUESTIONS = {
    { key = "target", label = ns.L("What are you targeting?"), unit = true },
    { key = "mouseover", label = ns.L("What is under your mouse?"), unit = true },
    { key = "focus", label = ns.L("Who is your focus?"), unit = true },
    { key = "combat", label = ns.L("Are you in combat?"), yesNo = true },
    { key = "mounted", label = ns.L("Are you mounted?"), yesNo = true },
    { key = "mod", label = ns.L("Which key do you hold?"), items = {
        { key = "none", label = ns.L("None") }, { key = "shift", label = ns.L("Shift") },
        { key = "ctrl", label = ns.L("Ctrl") }, { key = "alt", label = ns.L("Alt") } } },
    { key = "stance", label = ns.L("Which stance or form are you in?"), items = {
        { key = "0", label = ns.L("None") }, { key = "1", label = "1" }, { key = "2", label = "2" },
        { key = "3", label = "3" }, { key = "4", label = "4" } } },
}

local UNIT_ANSWERS = { { key = "none", label = ns.L("Nothing") }, { key = "friend", label = ns.L("A friend") },
    { key = "enemy", label = ns.L("An enemy") }, { key = "corpse", label = ns.L("Something dead") } }
local YES_NO = { { key = "no", label = ns.L("No") }, { key = "yes", label = ns.L("Yes") } }

local state = { target = "enemy", mouseover = "none", focus = "none", combat = false, mounted = false,
    mod = "none", stance = 0 }

local function Lines()
    return Text.Lines(F.draft.body)
end

local function SetLines(lines)
    F.SetBody(table.concat(lines, "\n"), true)
end

local function Replace(n, line)
    local lines = Lines()
    if line then lines[n] = line else table.remove(lines, n) end
    SetLines(lines)
end

local function Edit(n, change)
    local p = Text.Expand(Text.Parse(Lines()[n]))
    if change(p) == false then return end
    if #p.clauses == 0 then return Replace(n, nil) end
    Replace(n, Text.Build(p))
end

local function Token(c)
    return (c.neg and "no" or "") .. c.base .. (c.value and (":" .. c.value) or "")
end

local function DropEmpty(p, clause)
    local group = clause.groups[1]
    if group and #group.parts == 0 and #p.clauses == 1 then table.remove(clause.groups, 1) end
end

local function SetUnit(n, ci, unit)
    Edit(n, function(p)
        local clause = p.clauses[ci]
        local group = clause.groups[1]
        if not group then
            if unit == DEFAULT_UNIT then return false end
            group = { parts = {} }
            clause.groups[1] = group
        end
        for k = #group.parts, 1, -1 do
            if Text.Condition(group.parts[k]).unit then table.remove(group.parts, k) end
        end
        if unit ~= DEFAULT_UNIT then table.insert(group.parts, 1, "@" .. unit) end
        DropEmpty(p, clause)
    end)
end

local function Conflicts(token, other)
    if OPPOSITE[token] == other then return true end
    local mod = token:find("^mod") or token == "nomod"
    if mod and (other:find("^mod") or other == "nomod") then return true end
    return token:find("^stance:") and other:find("^stance:") ~= nil
end

local function AddCondition(n, ci, token)
    Edit(n, function(p)
        local clause = p.clauses[ci]
        local group = clause.groups[1]
        if not group then
            group = { parts = {} }
            clause.groups[1] = group
        end
        for k = #group.parts, 1, -1 do
            local c = Text.Condition(group.parts[k])
            if not c.unit then
                local other = Token(c)
                if other == token then return false end
                if Conflicts(token, other) then table.remove(group.parts, k) end
            end
        end
        group.parts[#group.parts + 1] = token
    end)
end

local function RemoveCondition(n, ci, k)
    Edit(n, function(p)
        local clause = p.clauses[ci]
        table.remove(clause.groups[1].parts, k)
        DropEmpty(p, clause)
    end)
end

local function SetArg(n, ci, arg)
    Edit(n, function(p)
        local clause = p.clauses[ci]
        if clause.arg == arg then return false end
        clause.arg = arg
    end)
end

local function RemoveClause(n, ci)
    Edit(n, function(p) table.remove(p.clauses, ci) end)
end

local function AddOtherwise(n)
    Edit(n, function(p)
        local last = p.clauses[#p.clauses]
        p.clauses[#p.clauses + 1] = { groups = {}, arg = last.arg }
    end)
end

local function SetShows(n, arg)
    Replace(n, SHOWTOOLTIP .. (arg ~= "" and (" " .. arg) or ""))
end

local function AddLine(entry)
    local lines = Lines()
    if lines[#lines] == "" then lines[#lines] = nil end
    if entry.top then table.insert(lines, 1, entry.text) else lines[#lines + 1] = entry.text end
    SetLines(lines)
end

local function Blank(body)
    local trimmed = strtrim(body)
    return trimmed == "" or trimmed == strtrim(NEW_BODY)
end

local function UseRecipe(view, recipe)
    local spell = strtrim(view.spell:GetText() or "")
    if spell == "" then ns.Print(TEXT_SPELL_FIRST) return end
    local body = recipe.text:format(spell)
    if Blank(F.draft.body) then return F.SetBody(body, true) end
    ns.Confirm(TEXT_REPLACE, function() F.SetBody(body, true) end)
end

local function Coverable(p)
    if p.kind ~= "cmd" or not p.clauses or C.SCRIPT_COMMANDS[p.cmd] then return false end
    for _, clause in ipairs(p.clauses) do
        if #clause.groups > 1 then return false end
        for _, group in ipairs(clause.groups) do
            for _, part in ipairs(group.parts) do
                local c = Text.Condition(part)
                if not (c.unit or c.known) then return false end
            end
        end
    end
    return true
end

local function ClauseUnit(clause)
    local group = clause.groups[1]
    return group and Text.GroupUnit(group) or DEFAULT_UNIT
end

local function HasConditions(clause)
    local group = clause.groups[1]
    if not group then return false end
    for _, part in ipairs(group.parts) do
        if not Text.Condition(part).unit then return true end
    end
    return false
end

local function Lead(p, ci)
    if HasConditions(p.clauses[ci]) then return ci == 1 and TEXT_IF or TEXT_ELSE_IF end
    return ci == 1 and TEXT_ALWAYS or TEXT_ELSE
end

local function Label(parent, size, color)
    local fs = P.Text(parent, size or SMALL_SIZE, color)
    fs:SetJustifyH("LEFT")
    return fs
end

local function SmallButton(parent, text, w, onClick)
    return ns.Button(parent, text, w, ROW_H, onClick)
end

local function Menu(owner, fill)
    MenuUtil.CreateContextMenu(owner, function(_, root) fill(root) end)
end

local function SpellBox(box)
    box:SetScript("OnEditFocusGained", F.SuggestOpen)
    box:SetScript("OnTextChanged", F.SuggestTyped)
    box:SetScript("OnArrowPressed", F.SuggestMove)
    box:SetScript("OnHide", F.SuggestClose)
    box:SetScript("OnEnterPressed", function(self)
        F.SuggestAccept(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        if F.SuggestHeld() then return end
        F.SuggestClose(self)
        if self.Commit then self:Commit() end
    end)
    return box
end

local function ArgBox(parent, commit)
    local box = SpellBox(ns.NewEditBox(parent))
    box:SetHeight(ROW_H)
    box:SetFont(ns.UIFontPath(), TEXT_SIZE, "")
    box:SetScript("OnEscapePressed", function(self)
        F.SuggestClose(self)
        self:SetText(self.committed or "")
        self:ClearFocus()
    end)
    function box:Commit()
        local text = strtrim(self:GetText() or "")
        if text ~= (self.committed or "") then commit(self, text) end
    end
    return box
end

local function NewChip(row)
    local chip = CreateFrame("Button", nil, row)
    chip:SetHeight(ROW_H)
    ns.Solid(chip, "BACKGROUND", CHIP, CHIP_FILL):SetAllPoints()
    ns.Border(chip, CHIP)
    chip.label = Label(chip, SMALL_SIZE, CHIP)
    chip.label:SetPoint("LEFT", CHIP_TEXT_X, 0)
    chip.x = Label(chip, SMALL_SIZE, CHIP)
    chip.x:SetPoint("RIGHT", -CHIP_X_X, 0)
    chip.x:SetText("x")
    chip:SetScript("OnClick", function(self) RemoveCondition(self.line, self.clause, self.part) end)
    return chip
end

local function UnitMenu(button)
    Menu(button, function(root)
        for _, unit in ipairs(UNITS) do
            root:CreateButton(Text.UnitWord(unit), function() SetUnit(button.line, button.clause, unit) end)
        end
    end)
end

local function WhenMenu(button)
    Menu(button, function(root)
        for _, entry in ipairs(WHEN) do
            if entry.title then
                root:CreateTitle(entry.title)
            else
                root:CreateButton(entry[2], function() AddCondition(button.line, button.clause, entry[1]) end)
            end
        end
    end)
end

local function NewClause(card)
    local row = CreateFrame("Frame", nil, card)
    row.lead = Label(row, SMALL_SIZE, T.accentSoft)
    row.lead:SetPoint("TOPLEFT", 0, -(ROW_H - SMALL_SIZE) / 2)
    row.lead:SetWidth(LABEL_W)
    row.unit = SmallButton(row, "", UNIT_W)
    row.unit:SetPoint("TOPLEFT", LABEL_W, 0)
    row.unit._onClick = function() UnitMenu(row.unit) end
    ns.Tooltip(row.unit, TEXT_UNIT_TIP)
    row.chips = P.Pool(function() return NewChip(row) end)
    row.when = SmallButton(row, TEXT_WHEN, ADD_W)
    row.when._onClick = function() WhenMenu(row.when) end
    row.remove = SmallButton(row, "x", X_W)
    row.remove:SetPoint("TOPRIGHT")
    row.remove._onClick = function() RemoveClause(row.unit.line, row.unit.clause) end
    row.verb = Label(row, SMALL_SIZE, T.muted)
    row.verb:SetWidth(VERB_W)
    row.arg = ArgBox(row, function(box, text) SetArg(box.line, box.clause, text) end)
    return row
end

local function NewCard(body)
    local card = CreateFrame("Frame", nil, body)
    ns.Solid(card, "BACKGROUND", T.fg, CARD_FILL):SetAllPoints()
    ns.Border(card, BLACK)
    card.title = Label(card, SMALL_SIZE, T.muted)
    card.title:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    card.remove = SmallButton(card, "x", X_W)
    card.remove:SetPoint("TOPRIGHT", -CARD_PAD, -CARD_PAD)
    card.remove._onClick = function() Replace(card.line, nil) end
    card.note = Label(card, TEXT_SIZE)
    card.note:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + CARD_HEAD_H))
    card.note:SetPoint("RIGHT", -CARD_PAD, 0)
    card.note:SetWordWrap(true)
    card.hint = Label(card, SMALL_SIZE, T.muted)
    card.shows = ArgBox(card, function(box, text) SetShows(box.line, text) end)
    card.shows.spells = true
    card.clauses = P.Pool(function() return NewClause(card) end)
    card.otherwise = SmallButton(card, TEXT_OTHERWISE, OTHERWISE_W)
    card.otherwise._onClick = function() AddOtherwise(card.line) end
    return card
end

local function NewIssue(body)
    local row = CreateFrame("Frame", nil, body)
    row.text = Label(row, NOTE_SIZE)
    row.text:SetPoint("TOPLEFT")
    row.text:SetWordWrap(true)
    row.fix = SmallButton(row, TEXT_FIX, ISSUE_FIX_W)
    row.fix:SetPoint("TOPRIGHT")
    row.fix._onClick = function() F.SetBody(Text.Fix(F.draft.body, row.issue), true) end
    return row
end

local function Title(parent, text)
    local fs = Label(parent, NOTE_SIZE, T.accentSoft)
    fs:SetText(text:upper())
    return fs
end

local function Answer(q, key)
    if q.unit then
        state[q.key] = key
    elseif q.yesNo then
        state[q.key] = key == "yes"
    elseif q.key == "stance" then
        state.stance = tonumber(key)
    else
        state[q.key] = key
    end
    F.RenderEditor()
end

local function Shown(q)
    if q.yesNo then return state[q.key] and "yes" or "no" end
    if q.key == "stance" then return tostring(state.stance) end
    return state[q.key]
end

local function NewQuestion(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Label(row, NOTE_SIZE)
    row.label:SetPoint("TOPLEFT")
    row.bar = Parts.Tabs(row, 1, {}, function(key) Answer(row.question, key) end)
    row.bar:SetPoint("TOPLEFT", 0, -(NOTE_SIZE + QUESTION_GAP))
    return row
end

local function NewTester(parent)
    local t = CreateFrame("Frame", nil, parent)
    t.title = Title(t, TEXT_TEST)
    t.title:SetPoint("TOPLEFT")
    t.hint = Label(t, SMALL_SIZE, T.muted)
    t.hint:SetPoint("TOPLEFT", 0, -(TITLE_H))
    t.hint:SetPoint("RIGHT")
    t.hint:SetWordWrap(true)
    t.hint:SetText(TEXT_TEST_HINT)
    t.questions = P.Pool(function() return NewQuestion(t) end)
    t.answer = CreateFrame("Frame", nil, t)
    t.answerFill = ns.Solid(t.answer, "BACKGROUND", T.accent, ANSWER_FILL)
    t.answerFill:SetAllPoints()
    ns.Border(t.answer, BLACK)
    t.answerHead = Label(t.answer, SMALL_SIZE, T.accentSoft)
    t.answerHead:SetPoint("TOPLEFT", ANSWER_PAD, -ANSWER_PAD)
    t.answerText = Label(t.answer, TEXT_SIZE)
    t.answerText:SetPoint("TOPLEFT", ANSWER_PAD, -(ANSWER_PAD + TITLE_H))
    t.answerText:SetPoint("RIGHT", -ANSWER_PAD, 0)
    t.answerText:SetWordWrap(true)
    return t
end

local function Outcome(rows)
    local out, notes, n, why = {}, {}, 0, nil
    for _, row in ipairs(rows) do
        if row.status == "fire" then
            n = n + 1
            out[#out + 1] = n .. ". " .. row.action
        elseif row.status == "skipped" then
            notes[#notes + 1] = TEXT_SKIPPED:format(row.action)
        elseif row.status == "unreached" then
            if notes[#notes] ~= TEXT_STOPPED then notes[#notes + 1] = TEXT_STOPPED end
        elseif row.status == "none" then
            why = why or row.why
        end
    end
    if n == 0 then out[1] = TEXT_NOTHING .. (why and (" " .. why) or "") end
    for _, note in ipairs(notes) do out[#out + 1] = ns.Color("muted", note) end
    return table.concat(out, "\n")
end

local function DrawTester(t, width)
    t:SetWidth(width)
    local body = F.draft.body
    local needs = Text.Needs(body)
    t.questions.Release()
    local y = TITLE_H + t.hint:GetStringHeight() + BLOCK_GAP
    local asked = 0
    for _, q in ipairs(QUESTIONS) do
        if needs[q.key] then
            asked = asked + 1
            local row = t.questions.Take()
            row.question = q
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetSize(width, NOTE_SIZE + QUESTION_GAP + TAB_H)
            row.label:SetText(q.label)
            row.bar:SetWidth(width)
            Parts.SetTabs(row.bar, q.unit and UNIT_ANSWERS or q.yesNo and YES_NO or q.items)
            Parts.PaintTabs(row.bar, Shown(q))
            y = y + NOTE_SIZE + QUESTION_GAP + TAB_H + BLOCK_GAP
        end
    end
    t.answer:ClearAllPoints()
    t.answer:SetPoint("TOPLEFT", 0, -y)
    t.answer:SetWidth(width)
    t.answerHead:SetText(TEXT_PRESS:upper())
    local text = Outcome(Text.Simulate(body, state))
    if asked == 0 then text = text .. "\n" .. ns.Color("muted", TEXT_SAME) end
    t.answerText:SetText(text)
    local answerH = ANSWER_PAD * 2 + TITLE_H + t.answerText:GetStringHeight()
    t.answer:SetHeight(answerH)
    local h = y + answerH
    t:SetHeight(h)
    return h
end

local function Place(frame, body, x, y, w)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
    if w then frame:SetWidth(w) end
end

local function DrawIssues(view, issues, width, y)
    view.issues.Release()
    view.problemsTitle:SetShown(#issues > 0)
    if #issues == 0 then return y end
    Place(view.problemsTitle, view.body, 0, y)
    y = y + TITLE_H
    for _, issue in ipairs(issues) do
        local row = view.issues.Take()
        row.issue = issue
        local color = issue.kind == "error" and ERROR or WARNING
        local where = issue.line > 0 and TEXT_LINE:format(issue.line) or TEXT_WHOLE
        row.text:SetWidth(width - ISSUE_FIX_W - ISSUE_GAP)
        row.text:SetText(ns.Color("muted", where .. ": ") .. issue.text)
        P.Paint(row.text, color)
        row.fix:SetShown(issue.from ~= nil and issue.to ~= nil)
        local h = math.max(ROW_H, row.text:GetStringHeight())
        row:SetHeight(h)
        Place(row, view.body, 0, y, width)
        y = y + h + ISSUE_GAP
    end
    return y + SECTION_GAP - ISSUE_GAP
end

local function FlowChips(row, p, ci, n, width)
    row.chips.Release()
    local clause = p.clauses[ci]
    local group = clause.groups[1]
    local x, line = LABEL_W + UNIT_W + CHIP_GAP, 0
    local right = width - X_W - CHIP_GAP
    local function Put(frame, w)
        if x + w > right and x > LABEL_W then
            x, line = LABEL_W, line + 1
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", x, -line * (ROW_H + CHIP_GAP))
        x = x + w + CHIP_GAP
    end
    for k, part in ipairs(group and group.parts or {}) do
        local c = Text.Condition(part)
        if not c.unit then
            local chip = row.chips.Take()
            chip.line, chip.clause, chip.part = n, ci, k
            local token = Token(c)
            chip.label:SetText(CHIP_WORDS[token] or token)
            local w = math.ceil(chip.label:GetStringWidth()) + CHIP_PAD
            chip:SetWidth(w)
            Put(chip, w)
        end
    end
    Put(row.when, ADD_W)
    return line + 1
end

local function DrawClause(card, p, ci, n, width, y)
    local row = card.clauses.Take()
    local clause = p.clauses[ci]
    row:SetPoint("TOPLEFT", CARD_PAD, -y)
    row:SetWidth(width)
    row.lead:SetText(Lead(p, ci))
    row.unit.line, row.unit.clause = n, ci
    row.when.line, row.when.clause = n, ci
    ns.SetButtonText(row.unit, Text.UnitWord(ClauseUnit(clause)))
    row.remove:SetShown(#p.clauses > 1)
    local lines = FlowChips(row, p, ci, n, width)
    local argY = lines * (ROW_H + CHIP_GAP)
    local verb = VERBS[p.cmd]
    row.verb:ClearAllPoints()
    row.verb:SetPoint("TOPLEFT", 0, -(argY + (ROW_H - SMALL_SIZE) / 2))
    row.arg:ClearAllPoints()
    row.arg:SetPoint("TOPLEFT", LABEL_W, -argY)
    row.arg:SetPoint("RIGHT", 0, 0)
    row.arg.line, row.arg.clause = n, ci
    row.arg.committed = strtrim(clause.arg or "")
    row.arg.spells = SPELL_COMMANDS[p.cmd]
    row.arg:SetShown(verb ~= nil)
    row.verb:SetWidth(verb and VERB_W or width)
    row.verb:SetText(verb or Text.Action(p, clause))
    if verb then row.arg:SetText(row.arg.committed) end
    local h = argY + ROW_H
    row:SetHeight(h)
    return h
end

local function DrawCommandCard(card, p, n, inner)
    local y = CARD_PAD + CARD_HEAD_H
    for ci = 1, #p.clauses do
        y = y + DrawClause(card, p, ci, n, inner, y) + ROW_GAP
    end
    local more = HasConditions(p.clauses[#p.clauses])
    card.otherwise:SetShown(more)
    if more then
        card.otherwise:ClearAllPoints()
        card.otherwise:SetPoint("TOPLEFT", CARD_PAD + LABEL_W, -y)
        y = y + ROW_H + ROW_GAP
    end
    return y
end

local function DrawCard(card, p, n, width)
    card.line, card.shows.line = n, n
    card.clauses.Release()
    card.note:Hide()
    card.hint:Hide()
    card.shows:Hide()
    card.otherwise:Hide()
    card:SetWidth(width)
    card.title:SetText(TEXT_LINE:format(n))
    local inner = width - 2 * CARD_PAD
    local y
    if p.kind == "meta" and p.word == SHOWTOOLTIP then
        card.title:SetText(TEXT_LINE:format(n) .. "  " .. TEXT_SHOWS)
        card.shows:Show()
        card.shows:ClearAllPoints()
        card.shows:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + CARD_HEAD_H))
        card.shows:SetWidth(math.min(inner, SPELL_W))
        card.shows.committed = p.arg
        card.shows:SetText(p.arg)
        card.hint:Show()
        card.hint:ClearAllPoints()
        card.hint:SetPoint("LEFT", card.shows, "RIGHT", ROW_GAP, 0)
        card.hint:SetPoint("RIGHT", -CARD_PAD, 0)
        card.hint:SetText(TEXT_SHOWS_HINT)
        y = CARD_PAD + CARD_HEAD_H + ROW_H + CARD_PAD
    elseif Coverable(p) then
        y = DrawCommandCard(card, p, n, inner) + CARD_PAD - ROW_GAP
    else
        card.note:Show()
        local said = Text.Explain(p.raw)[1]
        card.note:SetText((said and said.text or p.raw:gsub("|", "||")) .. "\n" .. ns.Color("muted", TEXT_RAW))
        y = CARD_PAD + CARD_HEAD_H + card.note:GetStringHeight() + CARD_PAD
    end
    card:SetHeight(y)
    return y
end

local function DrawCards(view, width, y)
    view.cards.Release()
    local any = false
    for n, line in ipairs(Lines()) do
        local p = Text.Parse(line)
        if p.kind ~= "blank" then
            any = true
            local card = view.cards.Take()
            Place(card, view.body, 0, y)
            y = y + DrawCard(card, Text.Expand(p), n, width) + BLOCK_GAP
        end
    end
    view.empty:SetShown(not any)
    if not any then
        Place(view.empty, view.body, 0, y, width)
        y = y + view.empty:GetStringHeight() + BLOCK_GAP
    end
    return y + SECTION_GAP - BLOCK_GAP
end

local function HasShowtooltip()
    local first = Lines()[1] or ""
    return Text.Parse(first).kind == "meta"
end

local function DrawAddLine(view, width, y)
    Place(view.addTitle, view.body, 0, y)
    y = y + TITLE_H
    local x = 0
    for i, b in ipairs(view.lineButtons) do
        local on = not (LINES[i].top and HasShowtooltip())
        b:SetShown(on)
        if on then
            if x + LINE_BUTTON_W > width then x, y = 0, y + ROW_H + CHIP_GAP end
            Place(b, view.body, x, y)
            x = x + LINE_BUTTON_W + CHIP_GAP
        end
    end
    return y + ROW_H + SECTION_GAP
end

local function DrawRecipes(view, width, y)
    Place(view.recipeTitle, view.body, 0, y)
    y = y + TITLE_H
    Place(view.recipeHint, view.body, 0, y, width)
    y = y + view.recipeHint:GetStringHeight() + HINT_GAP * 2
    Place(view.spell, view.body, 0, y, math.min(width, SPELL_W))
    y = y + ROW_H + BLOCK_GAP
    for _, b in ipairs(view.recipeButtons) do
        Place(b, view.body, 0, y, width)
        y = y + RECIPE_H + CHIP_GAP
    end
    return y
end

local function DrawView(view, issues)
    if not F.draft then return end
    local width = math.max(1, view.body:GetWidth())
    local y = DrawIssues(view, issues, width, 0)
    y = DrawCards(view, width, y)
    if view.tester then
        Place(view.tester, view.body, 0, y)
        y = y + DrawTester(view.tester, width) + SECTION_GAP
    end
    if view.addTitle then
        y = DrawAddLine(view, width, y)
        y = DrawRecipes(view, width, y)
    end
    view.body:SetHeight(math.max(1, y))
end

local function BodySized(scroll, w)
    scroll.body:SetWidth(w)
    if F.draft and scroll.view:IsVisible() then DrawView(scroll.view, F.issues or {}) end
end

local function NewRecipeButton(view, recipe)
    local b = CreateFrame("Button", nil, view.body)
    b:SetHeight(RECIPE_H)
    P.ListRow(b)
    ns.Border(b, BLACK)
    b.title = Label(b, TEXT_SIZE)
    b.title:SetPoint("TOPLEFT", CARD_PAD, -RECIPE_TEXT_Y)
    b.title:SetText(recipe.title)
    b.note = Label(b, SMALL_SIZE, T.muted)
    b.note:SetPoint("BOTTOMLEFT", CARD_PAD, RECIPE_TEXT_Y)
    b.note:SetText(recipe.note)
    b:SetScript("OnClick", function() UseRecipe(view, recipe) end)
    return b
end

local function BuildExtras(view)
    local body = view.body
    view.addTitle = Title(body, TEXT_ADD_LINE)
    view.lineButtons = {}
    for i, entry in ipairs(LINES) do
        view.lineButtons[i] = ns.Button(body, entry.label, LINE_BUTTON_W, ROW_H, function() AddLine(entry) end)
    end
    view.recipeTitle = Title(body, TEXT_RECIPES)
    view.recipeHint = Label(body, SMALL_SIZE, T.muted)
    view.recipeHint:SetWordWrap(true)
    view.recipeHint:SetText(TEXT_RECIPE_HINT)
    view.spell = SpellBox(ns.NewEditBox(body))
    view.spell.spells = true
    view.spell:SetHeight(ROW_H)
    view.spell:SetScript("OnEscapePressed", function(self)
        F.SuggestClose(self)
        self:ClearFocus()
    end)
    view.recipeButtons = {}
    for i, recipe in ipairs(RECIPES) do view.recipeButtons[i] = NewRecipeButton(view, recipe) end
end

function F.BuildBuilder(parent, opts)
    opts = opts or {}
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    local scroll = UI.SlimScroll(view)
    scroll:SetPoint("TOPLEFT", opts.inset or 0, -(opts.inset or 0))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_ROOM, opts.inset or 0)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll.body, scroll.view = body, view
    scroll:SetScript("OnSizeChanged", BodySized)
    view.scroll, view.body = scroll, body
    view.problemsTitle = Title(body, TEXT_PROBLEMS)
    view.issues = P.Pool(function() return NewIssue(body) end)
    view.cards = P.Pool(function() return NewCard(body) end)
    view.empty = Label(body, NOTE_SIZE, T.muted)
    view.empty:SetWordWrap(true)
    view.empty:SetText(TEXT_EMPTY)
    if opts.test ~= false then view.tester = NewTester(body) end
    if opts.extras ~= false then BuildExtras(view) end
    return view
end

function F.NewTester(parent)
    return NewTester(parent)
end

F.DrawTester = DrawTester
F.DrawBuilderView = DrawView

function F.DrawBuilder(issues)
    DrawView(F.window.editor.builder, issues)
end

F.BuilderState = state
