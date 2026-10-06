-------------------------------------------------------------------------------
--  NaowhForever_BlessingsPage.lua -- the Blessings settings page (/nf > Blessings), with a
--  preview of the bar that edits it (a class's blessing, the aura, size, spacing, the aura /
--  class gap, hiding and bringing back buttons) on plain frames, never the bar's secure ones,
--  and the assignments grid the Blessings window shows: a row per paladin in the group and a
--  column per class plus the aura.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local B = ns.Blessings
local Look = B.Look

local CELL, GAP, NAME_WIDTH = 32, 6, 170
local EMPTY = 134400

-- The house 1px black border, as on the bar.
local ICON_BORDER = { r = 0, g = 0, b = 0 }

local function NewCell(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CELL, CELL)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(btn.tex, 1)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(btn, ICON_BORDER)
    return btn
end

local function Cell(parent, x, y, icon, lit, title, body, onClick)
    local btn = ns.UI.Keep(parent, "cell", NewCell)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local tex = btn.tex
    tex:SetTexture(icon)
    tex:SetDesaturated(not lit)
    tex:SetAlpha(lit and 1 or 0.35)
    btn:SetScript("OnClick", onClick)
    ns.Tooltip(btn, title, body)
    return btn
end

function ns.BuildBlessingAssignmentsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Every paladin in your group running Naowh Forever, and the blessing "
        .. "they give each class. Click an icon to change it: your own row always, anyone's while "
        .. "you lead the group or are an assistant. Only what that paladin has learned is offered, "
        .. "and changes reach them straight away.", y); y = y - h

    _, h = W:SectionHeader(parent, "PLANNING", y); y = y - h
    local function Allowed()
        if B.CanPlanAll() then return true end
        ns.Print("Only the group leader or an assistant can plan every paladin's blessings.")
    end
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Auto-Assign", buttonText = "Assign",
          onClick = function()
              if Allowed() then
                  ns.Confirm("Replace every paladin's blessings and auras with an automatic plan?",
                      B.AutoAssign)
              end
          end },
        { type = "button", text = "Preset", buttonText = "Load",
          onClick = function()
              if not B.HasPreset() then return ns.Print("No preset saved yet.") end
              if Allowed() then
                  ns.Confirm("Load the saved preset for the paladins here now?", function()
                      if not B.LoadPreset() then ns.Print("Nobody in the preset is in your group.") end
                  end)
              end
          end }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Save the plan below as the preset", buttonText = "Save",
          onClick = function()
              if not B.HasPaladins() then
                  return ns.Print("No paladins running Naowh Forever to save a plan for.")
              end
              local function Save()
                  if B.SavePreset() then
                      ns.Print("Blessings preset saved.")
                  else
                      ns.Print("No paladins running Naowh Forever to save a plan for.")
                  end
              end
              if B.HasPreset() then ns.Confirm("Replace the saved preset?", Save) else Save() end
          end },
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "ASSIGNMENTS", y); y = y - h

    local left = UI.CONTENT_PAD
    local columns = {}
    for _, class in ipairs(B.CLASSES) do columns[#columns + 1] = class end
    columns[#columns + 1] = "AURA"
    for i, column in ipairs(columns) do
        local aura = column == "AURA"
        Cell(parent, left + NAME_WIDTH + (i - 1) * (CELL + GAP), y,
            aura and B.SpellIcon("devotion") or "Interface\\Icons\\ClassIcon_" .. column, true,
            aura and "Aura" or B.ClassName(column))
    end
    y = y - CELL - 10

    local lead = B.CanAssign("player")
    local roster = B.Roster()
    local rows = {}
    if B.IsPaladin() then
        local store = B.Store()
        rows[1] = { who = B.MyName(), you = true, plan = store, players = store.players, can = B.Learned,
            set = B.SetOwn }
    end
    local others = B.Others()
    local names = {}
    for who in pairs(others) do names[#names + 1] = who end
    table.sort(names)
    for _, who in ipairs(names) do
        local plan = others[who]
        rows[#rows + 1] = { who = who, plan = plan, players = plan.players,
            can = function(entry) return plan.known[entry.key] end,
            set = lead and function(column, key)
                B.SetFor(who, column, key)
                UI:RefreshPage(true)
            end }
    end
    for _, member in ipairs(roster) do
        if member.class == "PALADIN" and member.guid ~= UnitGUID("player") and not others[member.who] then
            rows[#rows + 1] = { who = member.who }
        end
    end
    -- Who in a class this paladin gives their own blessing instead, for the cell's tooltip.
    local function Own(players, class)
        local out = {}
        for _, member in ipairs(roster) do
            local key = member.class == class and players and players[member.guid]
            if key then out[#out + 1] = Ambiguate(member.who, "short") .. ": " .. B.SpellName(key) end
        end
        return #out > 0 and ("\n" .. table.concat(out, "\n")) or ""
    end
    if #rows == 0 then
        _, h = W:Note(parent, "No paladins in your group.", y); y = y - h
        return y
    end

    for _, row in ipairs(rows) do
        local label = UI.KeepFont(parent, "name", 13, "OUTLINE", RAID_CLASS_COLORS.PALADIN)
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", left, y - 9)
        label:SetWidth(NAME_WIDTH - 10)
        label:SetJustifyH("LEFT")
        label:SetText(Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""))
        if not row.plan then
            local note = UI.KeepFont(parent, "noAddon", 12, nil, T.muted)
            note:SetPoint("TOPLEFT", parent, "TOPLEFT", left + NAME_WIDTH, y - 10)
            note:SetText("Not running Naowh Forever")
        else
            for i, column in ipairs(columns) do
                local aura = column == "AURA"
                local key = aura and row.plan.aura or row.plan.classes[column]
                local title = aura and "Aura" or B.ClassName(column)
                local onClick = row.set and function(btn)
                    B.OpenMenu(btn, title, aura and B.AURAS or B.BLESSINGS,
                        function() return aura and row.plan.aura or row.plan.classes[column] end,
                        function(choice) row.set(column, choice) end, "None", row.can)
                end
                Cell(parent, left + NAME_WIDTH + (i - 1) * (CELL + GAP), y,
                    key and B.SpellIcon(key) or EMPTY, key ~= nil, title,
                    (key and B.SpellName(key) or "Nothing assigned")
                        .. (aura and "" or Own(row.players, column))
                        .. (onClick and "\nClick to change." or ""), onClick)
            end
        end
        y = y - CELL - GAP
    end
    return y - 10
end

local function PaladinCount()
    local n = 0
    for _, member in ipairs(B.Roster()) do
        if member.class == "PALADIN" then n = n + 1 end
    end
    return n
end

function B.Headline()
    if not IsInGroup() then return B.IsPaladin() and "Just you for now" or "Not in a group" end
    local n = PaladinCount()
    if n == 0 then return "No paladins in your group" end
    return n == 1 and "1 paladin in your group" or ("%d paladins in your group"):format(n)
end

function B.Detail()
    if not B.IsPaladin() then return "The group's paladins and the blessing each gives every class." end
    local planned, classes = 0, B.Store().classes
    for _, class in ipairs(B.CLASSES) do
        if classes[class] then planned = planned + 1 end
    end
    return ("Your blessings: %d of %d classes planned%s"):format(planned, #B.CLASSES,
        B.HasPreset() and ", preset saved" or "")
end

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group

local BLESSINGS_OFF = "Turn on Blessings"
local St = ns.Shared.Style
local STAGE_H, STAGE_MARGIN, LABEL_ROOM = 160, 16, 14
local NOTE_Y, NOTE_SIZE, NOTE_LINE = 10, 11, 15
local TEXT_ROOM = NOTE_Y + NOTE_LINE * 2
local REMOVE_SIZE, REMOVE_ICON, REMOVE_INSET = 12, 8, 3
local PLUS_ICON, PLUS_BG_ALPHA = 12, 0.6
local GRIP_MIN, GRIP_LINE = 6, 2
local EDIT_LEVEL = 10
local BLACK = { r = 0, g = 0, b = 0 }
local SIZE_SLIDER, SPACING_SLIDER, GROUP_SLIDER = { 20, 70, 1 }, { 0, 30, 1 }, { 0, 40, 1 }
local AURA_LABEL, FURY_LABEL, GROUP_LABEL = "Aura Button", "Righteous Fury Button", "Aura / Class Gap"
local HINT = "Right-click a class for its blessing. Wheel: size, Shift-wheel: spacing. x hides a button."
local HINT_OFF = "Turn on Blessings to edit the bar here."
local ADD_TITLE = "Add a Button"
local ADD_AURA, ADD_FURY, ADD_BOTH = "Brings back the Aura button.", "Brings back the Righteous Fury button.",
    "Choose which button to bring back."
local GAP_TIP = "Drag left or right to change the gap between your aura and the class buttons."
local AURA_HERE = "Here: click to choose your aura. Its x hides the button."
local SELF_HERE = "Here: its x hides the button."
local CLASS_TIP = "On the bar, left-click blesses the next %s who needs it, missing first, skipping anyone "
    .. "dead or out of range."
local CLASS_HERE = "Here: right-click to choose its blessing."
local STATES = {
    { key = "group", label = "In a Group", tip = "Your group in range: who is missing a blessing, who is running out, "
        .. "and who only needs their own." },
    { key = "range", label = "Out of Range", tip = "Nobody of a class you can reach: dead, offline or too far away." },
}
local SAMPLE = {
    { class = "WARRIOR", blessing = "might", colour = Look.RED, missing = 2, far = true },
    { class = "PRIEST", blessing = "wisdom", colour = Look.YELLOW, missing = 0, left = 4 * 60 },
    { class = "ROGUE", blessing = "might", colour = Look.BLUE, missing = 1, far = true },
    { class = "MAGE", blessing = "wisdom", missing = 0, left = 12 * 60 },
}
local NOTES = {
    group = "Red: missing the class blessing. Yellow: running out. Blue: only players with their own.",
    range = "Grey: nobody of that class in range. The number still counts who is missing it.",
}

local function On() return S.Get("blessings") == true end

local function Wheel(_, delta)
    if not On() then return end
    local key, range = "blessBarSize", SIZE_SLIDER
    if IsShiftKeyDown() then key, range = "blessSpacing", SPACING_SLIDER end
    local value = S.Get(key) + (delta > 0 and range[3] or -range[3])
    value = math.min(range[2], math.max(range[1], value))
    if value ~= S.Get(key) then S.Set(key, value) end
end

local function SelfEnter(button)
    local preview = button.preview
    if not preview.editable or preview.grip.dragging then return end
    local x = preview.remove
    x.owner = button
    x:ClearAllPoints()
    x:SetPoint("CENTER", button, "TOPRIGHT", -REMOVE_INSET, -REMOVE_INSET)
    x:Show()
end

local function SelfLeave(button)
    local x = button.preview.remove
    if x.owner == button and not x:IsMouseOver() then x:Hide() end
end

local function SelfClick(button)
    if button.preview.editable and button.menu then button.menu(button) end
end

local function ClassClick(cell, mouse)
    local preview = cell.preview
    if mouse == "RightButton" and preview.editable and preview.paladin then B.ClassMenu(cell, cell.class, true) end
end

local function RemoveEnter(x)
    x.icon:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
end

local function RemoveLeave(x)
    x.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    if not (x.owner and x.owner:IsMouseOver()) then x:Hide() end
end

local function RemoveClick(x)
    x:Hide()
    if x.owner then S.Set(x.owner.setting, false) end
end

local function ShowAura() S.Set("blessShowAura", true) end
local function ShowFury() S.Set("blessShowFury", true) end

local function AddMenu(_, root)
    root:CreateTitle(ADD_TITLE)
    root:CreateButton(AURA_LABEL, ShowAura)
    root:CreateButton(FURY_LABEL, ShowFury)
end

local function PlusClick(plus)
    local aura, fury = S.Get("blessShowAura"), S.Get("blessShowFury")
    if not (aura or fury) then
        if ns.UI.HideWidgetTooltip then ns.UI.HideWidgetTooltip() end
        MenuUtil.CreateContextMenu(plus, AddMenu)
    elseif not aura then
        ShowAura()
    elseif not fury then
        ShowFury()
    end
end

local function PlusEnter(plus)
    plus.icon:SetVertexColor(T.accent.r, T.accent.g, T.accent.b)
end

local function PlusLeave(plus)
    plus.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
end

local function GripUpdate(grip)
    local value = grip.from + math.floor((GetCursorPosition() - grip.fromX) / grip.scale + 0.5)
    value = math.min(GROUP_SLIDER[2], math.max(GROUP_SLIDER[1], value))
    if value ~= S.Get("blessGroupSpacing") then S.Set("blessGroupSpacing", value) end
end

local function GripEnter(grip)
    if grip.preview.editable then grip.line:Show() end
end

local function GripLeave(grip)
    if not grip.dragging then grip.line:Hide() end
end

local function GripDown(grip, mouse)
    if mouse ~= "LeftButton" or not grip.preview.editable then return end
    grip.fromX, grip.scale, grip.from = GetCursorPosition(), grip:GetEffectiveScale(), S.Get("blessGroupSpacing")
    grip.dragging = true
    grip.preview.remove:Hide()
    grip.line:Show()
    grip:SetScript("OnUpdate", GripUpdate)
end

local function GripStop(grip)
    if not grip.dragging then return end
    grip.dragging = nil
    grip:SetScript("OnUpdate", nil)
    grip.line:SetShown(grip:IsMouseOver())
end

local function GripUp(grip, mouse)
    if mouse == "LeftButton" then GripStop(grip) end
end

local function GripHidden(grip)
    GripStop(grip)
    grip.line:Hide()
end

local function NewButton(preview, onClick)
    local button = CreateFrame("Button", nil, preview.bar)
    button.preview = preview
    Look.Icon(button)
    button:SetHighlightTexture(Look.HIGHLIGHT, "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnMouseWheel", Wheel)
    preview.wheels[#preview.wheels + 1] = button
    return button
end

local function NewSelf(preview, setting, title, tip, here)
    local button = NewButton(preview, SelfClick)
    button.setting, button.title = setting, title
    button.tipOn = tip .. "\n\n" .. ns.Color("muted", here)
    button.tipOff = tip .. "\n\n" .. ns.Color("muted", HINT_OFF)
    button:SetScript("OnEnter", SelfEnter)
    button:SetScript("OnLeave", SelfLeave)
    return button
end

local function NewClass(preview, class)
    local cell = NewButton(preview, ClassClick)
    cell.class, cell.title = class, B.ClassName(class)
    Look.Label(cell, class)
    local tip = CLASS_TIP:format(cell.title)
    cell.tipOn = preview.paladin and (tip .. "\n\n" .. ns.Color("muted", CLASS_HERE)) or tip
    cell.tipOff = tip .. "\n\n" .. ns.Color("muted", HINT_OFF)
    return cell
end

local function NewPlus(preview)
    local plus = CreateFrame("Button", nil, preview.bar)
    plus.preview = preview
    ns.Solid(plus, "BACKGROUND", T.bg, PLUS_BG_ALPHA):SetAllPoints()
    ns.Border(plus, BLACK)
    plus.icon = plus:CreateTexture(nil, "ARTWORK")
    plus.icon:SetTexture(St.PLUS)
    plus.icon:SetSize(PLUS_ICON, PLUS_ICON)
    plus.icon:SetPoint("CENTER")
    PlusLeave(plus)
    plus:SetHighlightTexture(Look.HIGHLIGHT, "ADD")
    plus:SetScript("OnEnter", PlusEnter)
    plus:SetScript("OnLeave", PlusLeave)
    plus:SetScript("OnClick", PlusClick)
    plus:SetScript("OnMouseWheel", Wheel)
    preview.wheels[#preview.wheels + 1] = plus
    return plus
end

local function NewRemove(preview)
    local x = CreateFrame("Button", nil, preview)
    x:SetFrameLevel(preview:GetFrameLevel() + EDIT_LEVEL)
    x:SetSize(REMOVE_SIZE, REMOVE_SIZE)
    ns.Solid(x, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(x, BLACK)
    x.icon = x:CreateTexture(nil, "ARTWORK")
    x.icon:SetTexture(St.CROSS)
    x.icon:SetSize(REMOVE_ICON, REMOVE_ICON)
    x.icon:SetPoint("CENTER")
    RemoveLeave(x)
    x:SetScript("OnEnter", RemoveEnter)
    x:SetScript("OnLeave", RemoveLeave)
    x:SetScript("OnClick", RemoveClick)
    x:Hide()
    return x
end

local function NewGrip(preview)
    local grip = CreateFrame("Frame", nil, preview.bar)
    grip.preview = preview
    grip:SetFrameLevel(preview.bar:GetFrameLevel())
    grip.line = ns.Solid(grip, "OVERLAY", T.accent, 1)
    grip.line:SetPoint("TOP")
    grip.line:SetPoint("BOTTOM")
    grip.line:SetWidth(GRIP_LINE)
    grip.line:Hide()
    grip:EnableMouse(true)
    grip:SetScript("OnEnter", GripEnter)
    grip:SetScript("OnLeave", GripLeave)
    grip:SetScript("OnMouseDown", GripDown)
    grip:SetScript("OnMouseUp", GripUp)
    grip:SetScript("OnHide", GripHidden)
    grip:SetScript("OnMouseWheel", Wheel)
    ns.Tooltip(grip, GROUP_LABEL, GAP_TIP)
    preview.wheels[#preview.wheels + 1] = grip
    return grip
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.paladin = B.IsPaladin()
    preview.bar = CreateFrame("Frame", nil, preview)
    preview.bar:SetScript("OnMouseWheel", Wheel)
    preview.wheels = { preview.bar }
    preview.grip = NewGrip(preview)
    preview.plus = NewPlus(preview)
    preview.aura = NewSelf(preview, "blessShowAura", "Aura", B.AURA_TIP, preview.paladin and AURA_HERE or SELF_HERE)
    preview.aura.menu = preview.paladin and B.AuraMenu or nil
    preview.fury = NewSelf(preview, "blessShowFury", B.FuryName(), B.FURY_TIP, SELF_HERE)
    preview.cells = {}
    for i, sample in ipairs(SAMPLE) do preview.cells[i] = NewClass(preview, sample.class) end
    preview.remove = NewRemove(preview)
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y + NOTE_LINE)
    preview.hint = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.hint:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function Fit(preview)
    local bar = preview.bar
    local below = Look.labels and LABEL_ROOM or 0
    local w, h = bar:GetWidth(), bar:GetHeight() + below
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2 - TEXT_ROOM
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h * scale > roomH then scale = roomH / h end
    bar:SetScale(scale)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", preview, "CENTER", 0, (TEXT_ROOM / 2 + below / 2) / scale)
end

local function Tip(button, editable)
    ns.Tooltip(button, button.title, editable and button.tipOn or button.tipOff)
end

local function PaintSelf(button, shown, key, missing, x, bar, editable)
    if not shown then
        button:Hide()
        return x
    end
    button.icon:SetTexture(B.SpellIcon(key))
    Look.Self(button, missing)
    Tip(button, editable)
    return Look.Place(button, bar, x)
end

local function PlaceGrip(grip, shown, x, bar)
    grip:SetShown(shown)
    if not shown then return end
    local span = Look.gap + Look.groupGap
    local width = math.max(GRIP_MIN, span)
    grip:SetSize(width, Look.size)
    grip:ClearAllPoints()
    grip:SetPoint("LEFT", bar, "LEFT", x - Look.gap - (width - span) / 2, 0)
end

local function PaintPreview(preview, state)
    Look.Read()
    local editable = On()
    preview.editable = editable
    local bar, plus = preview.bar, preview.plus
    local showAura, showFury = S.Get("blessShowAura"), S.Get("blessShowFury")
    local x = 0
    local adding = editable and not (showAura and showFury)
    plus:SetShown(adding)
    if adding then
        plus:SetSize(Look.size, Look.size)
        plus:ClearAllPoints()
        plus:SetPoint("LEFT", bar, "LEFT", 0, 0)
        x = Look.size + Look.gap
        ns.Tooltip(plus, ADD_TITLE, showAura and ADD_FURY or showFury and ADD_AURA or ADD_BOTH)
    end
    local start = x
    x = PaintSelf(preview.aura, showAura, preview.paladin and B.CurrentAura() or "devotion", false, x, bar, editable)
    x = PaintSelf(preview.fury, showFury, "fury", true, x, bar, editable)
    PlaceGrip(preview.grip, editable and x > start, x, bar)
    if x > start then x = Look.Gap(x) end
    local classes = preview.paladin and B.Store().classes
    for i, sample in ipairs(SAMPLE) do
        local cell = preview.cells[i]
        local gone = state == "range" and sample.far
        local key = sample.blessing
        if classes then key = classes[sample.class] end
        cell.icon:SetTexture(B.SpellIcon(key))
        Look.Class(cell, not gone and sample.colour or nil, not gone, sample.missing, sample.left)
        Tip(cell, editable)
        x = Look.Place(cell, bar, x)
    end
    bar:SetSize(Look.Width(x), Look.size)
    Fit(preview)
    preview.note:SetText(NOTES[state])
    preview.hint:SetText(editable and HINT or HINT_OFF)
    local wheels = preview.wheels
    for i = 1, #wheels do wheels[i]:EnableMouseWheel(editable) end
    local remove = preview.remove
    if not (editable and remove.owner and remove.owner:IsShown()) then remove:Hide() end
end

local function BarSummary(store)
    return ("%d px buttons%s%s"):format(store.Get("blessBarSize"), store.Get("blessShowAura") and ", aura" or "",
        store.Get("blessTimers") and ", minutes left" or "")
end

local page = Settings.Page("Blessings/Settings", S)

page:Window({
    text = "Open Blessings",
    open = function() ns.OpenBlessingsWindow() end,
    headline = B.Headline,
    detail = B.Detail,
})

page:Card({
    id = "bar", name = "Blessing Bar", order = 10,
    help = "For paladins, a button per class in your group. Left-click blesses the next member of that class "
        .. "who needs it, missing first, skipping anyone dead or out of range. Right-click a class to choose "
        .. "its blessing or open its player list. Move it in Unlock Mode. The preview edits it: right-click a "
        .. "class for its blessing, click the aura to choose it, wheel for size and Shift-wheel for spacing, drag "
        .. "the gap after the aura, x hides a button and + brings it back.",
    summary = BarSummary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Buttons"),
        { key = "blessShowAura", label = AURA_LABEL, toggle = true, needs = On, why = BLESSINGS_OFF,
          help = "Casts your aura. Right-click it to choose which." },
        { key = "blessShowFury", label = FURY_LABEL, toggle = true, needs = On, why = BLESSINGS_OFF,
          help = "Casts Righteous Fury on yourself. A red ! means it is not up." },
        { key = "blessShowLabels", label = "Class Labels", toggle = true, needs = On, why = BLESSINGS_OFF,
          help = "Each class's name under its button." },
        { key = "blessTimers", label = "Minutes Left", toggle = true, needs = On, why = BLESSINGS_OFF,
          help = "Minutes left on each class's shortest blessing, and on each player's." },
        Group("Layout"),
        { key = "blessBarSize", label = "Button Size", slider = SIZE_SLIDER, needs = On, why = BLESSINGS_OFF,
          help = "How big each button is." },
        { key = "blessSpacing", label = "Button Spacing", slider = SPACING_SLIDER, needs = On, why = BLESSINGS_OFF,
          help = "The gap between two buttons." },
        { key = "blessGroupSpacing", label = GROUP_LABEL, slider = GROUP_SLIDER, needs = On,
          why = BLESSINGS_OFF, help = "The extra gap between your aura and Righteous Fury and the class buttons." },
        { key = "blessTimerSize", label = "Timer Text Size", slider = { 8, 24, 1 }, needs = On, why = BLESSINGS_OFF,
          help = "How big the minutes left are." },
        Group("Key Bindings"),
        { label = "Next Blessing", binding = "CLICK NaowhForeverBlessNext:LeftButton",
          help = "Blesses the next player who needs it, most urgent first. In combat each press steps through "
              .. "the players who needed it when the fight began." },
        { label = "Next Greater Blessing", binding = "CLICK NaowhForeverBlessNextGreater:LeftButton",
          help = "The same with a Greater Blessing, for a class that shares one blessing, while you carry "
              .. "Symbols of Kings." },
    },
})

page:Card({
    id = "window", name = "Window", order = 20,
    help = "Blessings' own window, with every paladin's blessing for each class, Auto-Assign and the preset.",
    rows = {
        { key = "blessWindowAlpha", label = "Window Opacity", slider = { ns.Shared.Style.OPACITY_MIN, 100, 5 },
          unit = "%", scale = 0.01, help = "How solid the window is, in percent. Also on its title bar." },
    },
})
