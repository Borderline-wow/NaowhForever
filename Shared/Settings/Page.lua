-------------------------------------------------------------------------------
--  Page.lua -- draws a declared settings page on the shared row engine: a card per feature
--  with its head, its live preview and its settings. Used by the options window
--  (Core/NaowhForever_Window.lua).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Settings, View, Parts = Shared.Settings, Shared.View, Shared.Parts

local St = Shared.Style
local BORDER_RGB, CARD_GAP = St.BORDER_RGB, St.CARD_GAP

local ROW_H = 36
local HEAD_H = 44
local GROUP_H = 30
local FOOT_H = 30
local PAD = 14
local DOT_X = 5
local DOT_SIZE, DOT_HIT = 6, 12
local LABEL_SIZE, NAME_SIZE, SMALL_SIZE = 13, 14, 11
local RULE_ALPHA = 0.6
local TWO_COLUMNS_W = 620
local CONTROL_GAP = 8
local TRACK_W, BOX_W, BOX_H = 110, 44, 20
local CHOICE_W, TEXT_W, BUTTON_W, BUTTON_H = 170, 200, 110, 24
local BINDING_W = 170
local DIM = 0.35
local TOGGLE_GAP = 10
local CHEVRON_SIZE = 12
local FIND_MARK_W = 3     -- the accent bar left of the setting the search bar is on
local NO_EVENTS = {}

local function HelpEnter(hit)
    local text = hit.help
    if text and text ~= "" then
        ns.UI.ShowWidgetTooltip(hit, text, { anchor = "cursor", justify = "LEFT" })
    end
end

local function HelpLeave()
    ns.UI.HideWidgetTooltip()
end

local function HelpHit(parent, region)
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetPoint("TOPLEFT", region, "TOPLEFT", -4, 4)
    hit:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 4, -4)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", HelpEnter)
    hit:SetScript("OnLeave", HelpLeave)
    return hit
end

local function Found(label, cardUid)
    local focus = ns.UI.searchFocus
    return focus ~= nil and focus.label == label and focus.card == cardUid
end

local function FindMark(frame, layer)
    local mark = ns.Solid(frame, layer, T.accent, 1)
    mark:SetPoint("TOPLEFT")
    mark:SetPoint("BOTTOMLEFT")
    mark:SetWidth(FIND_MARK_W)
    return mark
end

local function Rule(frame, alpha)
    local rule = ns.Solid(frame, "ARTWORK", T.line, alpha or RULE_ALPHA)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    ns.Hairline(rule, "h")
    return rule
end

local Controls = {}

function Controls.toggle(row)
    return ns.UI.BuildToggleControl(row, row:GetFrameLevel() + 2, row.Get, row.Set)
end

function Controls.slider(row)
    local track, box = ns.UI.BuildSliderCore(row, TRACK_W, 4, 12, BOX_W, BOX_H, 12, 1, 0, 1, 1, row.Get, row.Set)
    box:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    track:SetPoint("RIGHT", box, "LEFT", -CONTROL_GAP, 0)
    track.leftEdge = track
    return track
end

function Controls.choice(row)
    return (ns.UI.BuildDropdownControl(row, CHOICE_W, row:GetFrameLevel() + 2, {}, {}, row.Get, row.Set))
end
Controls.font = Controls.choice
Controls.sound = Controls.choice

function Controls.binding(row)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetSize(BINDING_W, BUTTON_H)
    holder.fields = {}
    holder._refreshValue = function() end
    return holder
end

function Controls.colour(row)
    return ns.UI.BuildColorSwatchControl(row, row.Get, row.Set, false)
end

local function TextCommit(box)
    box:ClearFocus()
    local row = box:GetParent()
    if row.setting then row.setting.set(box:GetText()) end
end

local function TextReset(box)
    local row = box:GetParent()
    if row.setting then box:SetText(row.setting.get() or "") end
    box:ClearFocus()
end

function Controls.text(row)
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(TEXT_W, BOX_H + 2)
    box:SetAutoFocus(false)
    box:SetFont(ns.UIFontPath(), 12, "")
    box:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    box:SetTextInsets(6, 6, 0, 0)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    box.border = ns.Border(box, BORDER_RGB)
    box:SetScript("OnEnterPressed", TextCommit)
    box:SetScript("OnEditFocusLost", TextCommit)
    box:SetScript("OnEscapePressed", TextReset)
    box._refreshValue = function()
        if not box:HasFocus() and row.setting then box:SetText(row.setting.get() or "") end
    end
    return box
end

local function ButtonClicked(row)
    if row.setting then row.setting.button() end
end

function Controls.button(row)
    local button = ns.Button(row, "", BUTTON_W, BUTTON_H, function() ButtonClicked(row) end)
    return button
end

local function RowGet(row)
    local setting = row.setting
    return setting.get()
end

local SoundSet

local function RowSet(row, ...)
    local setting = row.setting
    if setting.kind == "sound" then SoundSet(setting, ...) else setting.set(...) end
end

local function FontValues(setting)
    return ns.UI.FontChoices(setting.get())
end

local soundValues, soundOrder

local function SoundValues()
    if soundValues then return soundValues, soundOrder end
    local _, names, order = nil, nil, nil
    if ns.SoundChoices then _, names, order = ns.SoundChoices() end
    soundValues, soundOrder = { none = "None" }, { "none" }
    for _, key in ipairs(order or {}) do
        soundValues[key] = names[key]
        soundOrder[#soundOrder + 1] = key
    end
    return soundValues, soundOrder
end

local function ChoiceValues(setting)
    local kind = setting.kind
    if kind == "font" then return FontValues(setting) end
    if kind == "sound" then return SoundValues() end
    if type(setting.choice) == "function" then return setting.choice() end
    return setting.choice[1] or setting.choice.values, setting.choice[2] or setting.choice.order
end

local function ShownValue(setting, v)
    local kind = setting.kind
    if kind == "toggle" then return v and "On" or "Off" end
    if kind == "slider" and type(v) == "number" then
        if setting.scale then v = math.floor(v / setting.scale + 0.5) end
        return tostring(v) .. (setting.unit or "")
    end
    if kind == "choice" or kind == "font" or kind == "sound" then
        local values = ChoiceValues(setting)
        local label = values and values[v]
        return label and tostring(label) or nil
    end
    if kind == "text" and type(v) == "string" then return v == "" and "empty" or ('"' .. v .. '"') end
end

local function DotEnter(dot)
    local setting = dot:GetParent().setting
    dot.mark:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 1)
    GameTooltip:SetOwner(dot, "ANCHOR_RIGHT")
    GameTooltip:SetText("Changed", 1, 1, 1)
    local default = ShownValue(setting, setting.store.Default(setting.key))
    GameTooltip:AddLine(default and ("The default is " .. default .. ". Click to put it back.")
        or "Click to put back the default.", T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function DotLeave(dot)
    dot.mark:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1)
    GameTooltip:Hide()
end

local function DotClicked(dot)
    local row = dot:GetParent()
    DotLeave(dot)
    Settings.ResetRow(row.setting)
    row:GetParent():QueueSettingsRedraw()
end

local function NewSetting(view)
    local row = CreateFrame("Frame", nil, view)
    row:SetHeight(ROW_H)
    row.Get = function() return RowGet(row) end
    row.Set = function(...) RowSet(row, ...) end
    row.controls = {}
    row.found = FindMark(row, "ARTWORK")
    row.rule = Rule(row)
    row.split = ns.Solid(row, "ARTWORK", T.line, RULE_ALPHA)
    row.split:SetPoint("TOPRIGHT")
    row.split:SetPoint("BOTTOMRIGHT")
    ns.Hairline(row.split, "v")
    row.dot = CreateFrame("Button", nil, row)
    row.dot:SetSize(DOT_HIT, DOT_HIT)
    row.dot:SetPoint("CENTER", row, "LEFT", DOT_X + DOT_SIZE / 2, 0)
    row.dot.mark = row.dot:CreateTexture(nil, "ARTWORK")
    row.dot.mark:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\circle_mask.tga", nil, nil, "TRILINEAR")
    row.dot.mark:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1)
    row.dot.mark:SetSize(DOT_SIZE, DOT_SIZE)
    row.dot.mark:SetPoint("CENTER")
    row.dot:SetScript("OnClick", DotClicked)
    row.dot:SetScript("OnEnter", DotEnter)
    row.dot:SetScript("OnLeave", DotLeave)
    row.label = ns.Font(row, LABEL_SIZE, nil, T.fg)
    row.label:SetPoint("LEFT", PAD, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.why = ns.Font(row, SMALL_SIZE, nil, T.muted)
    row.why:SetJustifyH("RIGHT")
    row.why:SetWordWrap(false)
    row.hit = HelpHit(row, row.label)
    row.dot:SetFrameLevel(row.hit:GetFrameLevel() + 1)
    return row
end

local function Control(row, kind)
    local control = row.controls[kind]
    if not control then
        control = Controls[kind](row)
        if kind ~= "slider" then control:SetPoint("RIGHT", row, "RIGHT", -PAD, 0) end
        row.controls[kind] = control
    end
    return control
end

function SoundSet(setting, v)
    setting.set(v)
    if v ~= "none" and ns.UI.PlaySoundKey then ns.UI.PlaySoundKey(v) end
end

local function BindingField(control, setting)
    for _, field in pairs(control.fields) do field:Hide() end
    local field = control.fields[setting.binding]
    if not field then
        field = CreateFrame("Frame", nil, control)
        field:SetAllPoints()
        ns.UI.KeyField(field, setting.binding, setting.label)
        control.fields[setting.binding] = field
    end
    field:Show()
end

local unitFormats = {}

local function UnitFormat(unit)
    local format = unitFormats[unit]
    if not format then
        format = function(v) return v .. unit end
        unitFormats[unit] = format
    end
    return format
end

local function Bind(control, setting)
    local kind = setting.kind
    if kind == "toggle" then
        control._refreshValue()
    elseif kind == "slider" then
        local range = setting.slider
        ns.UI.SetSliderRange(control, range[1], range[2], range[3])
        local unit = setting.unit
        control._format = unit and UnitFormat(unit) or nil
        control._refreshValue()
    elseif kind == "choice" or kind == "font" or kind == "sound" then
        control._values, control._order = ChoiceValues(setting)
        control._refreshLabel()
    elseif kind == "colour" then
        control._hasAlpha = setting.colour == "alpha"
        control._refreshValue()
    elseif kind == "text" then
        control._refreshValue()
    elseif kind == "button" then
        ns.SetButtonText(control, setting.buttonText or "Go")
        if setting.help then ns.Tooltip(control, setting.label, setting.help) end
    elseif kind == "binding" then
        BindingField(control, setting)
    end
end

local function Dim(row, control, off)
    local alpha = off and DIM or 1
    row.label:SetAlpha(alpha)
    control:SetAlpha(alpha)
    control:EnableMouse(not off)
    local box = control._valBox
    if box then
        box:SetAlpha(alpha)
        box:EnableMouse(not off)
        if off then box:ClearFocus() end
    end
    if off and control._menu then
        control._menu:Close()
        control._menu = nil
    end
end

local function SetSetting(row, setting, split)
    row.setting = setting
    for kind, control in pairs(row.controls) do control:SetShown(kind == setting.kind) end
    local control = Control(row, setting.kind)
    control:Show()
    if control._valBox then control._valBox:Show() end
    for kind, other in pairs(row.controls) do
        if other._valBox and kind ~= setting.kind then other._valBox:Hide() end
    end
    Bind(control, setting)
    row.label:SetText(setting.label)
    row.hit.help = setting.help
    row.dot:SetShown(Settings.Changed(setting))
    row.split:SetShown(split)
    row.found:SetShown(Found(setting.label, setting.card.uid))
    local off, why = Settings.Off(setting)
    Dim(row, control, off)
    local left = control._valBox and control or control
    row.why:ClearAllPoints()
    row.why:SetPoint("RIGHT", left, "LEFT", -CONTROL_GAP, 0)
    row.why:SetText(off and why or "")
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", PAD, 0)
    row.label:SetPoint("RIGHT", (off and why) and row.why or left, "LEFT", -CONTROL_GAP, 0)
    return ROW_H
end

local function Openable(card)
    return card.studio ~= nil or card.info or #Settings.Rows(card) > 0
end

local function HeadClicked(head)
    local card = head.card
    if not Openable(card) then return end
    Settings.SetOpen(card, not Settings.IsOpen(card))
    head:GetParent():QueueSettingsRedraw()
end

local function HeadSwitchSet(head, v)
    local card = head.card
    card.switchSet(v)
    if v then Settings.SetOpen(card, true) end
    head:GetParent():QueueSettingsRedraw()
end

local function NewHead(view)
    local head = CreateFrame("Button", nil, view)
    head:SetHeight(HEAD_H)
    ns.Solid(head, "BACKGROUND", T.panel, 1):SetAllPoints()
    head.rule = Rule(head, 1)
    head.found = FindMark(head, "ARTWORK")
    head.chevron = head:CreateTexture(nil, "ARTWORK")
    head.chevron:SetTexture(ns.UI.CHEVRON)
    head.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
    head.chevron:SetPoint("LEFT", PAD, 0)
    head.chevron:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    head.name = ns.Font(head, NAME_SIZE, nil, T.fg)
    head.name:SetPoint("LEFT", head.chevron, "RIGHT", CONTROL_GAP, 0)
    head.nameHit = HelpHit(head, head.name)
    head.switch = ns.UI.BuildToggleControl(head, head:GetFrameLevel() + 2,
        function() local card = head.card; return card and card.switchGet and card.switchGet() end,
        function(v) HeadSwitchSet(head, v) end)
    head.summary = ns.Font(head, SMALL_SIZE, nil, T.muted)
    head.summary:SetJustifyH("LEFT")
    head.summary:SetWordWrap(false)
    head:SetScript("OnClick", HeadClicked)
    head:SetScript("OnEnter", function(self)
        self.chevron:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
    end)
    head:SetScript("OnLeave", function(self)
        self.chevron:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    end)
    return head
end

local function SetHead(head, card, isOpen)
    head.card = card
    head.name:SetText(card.name)
    head.nameHit.help = card.help
    head.chevron:SetRotation(isOpen and -math.pi / 2 or 0)
    head.chevron:SetShown(Openable(card))
    head.rule:SetShown(isOpen)
    head.found:SetShown(Found(card.name, card.uid))
    local anchor = head.name
    if card.switchGet then
        head.switch:Show()
        head.switch._refreshValue()
        head.switch:ClearAllPoints()
        head.switch:SetPoint("LEFT", head.name, "RIGHT", TOGGLE_GAP, 0)
        anchor = head.switch
    else
        head.switch:Hide()
    end
    local off = card.switchGet and not card.switchGet()
    local summary = card.summary
    if type(summary) == "function" then summary = summary(card.store) end
    if off then summary = "Off" end
    head.summary:ClearAllPoints()
    head.summary:SetPoint("LEFT", anchor, "RIGHT", TOGGLE_GAP + 2, 0)
    head.summary:SetPoint("RIGHT", -PAD, 0)
    head.summary:SetText(summary or "")
    return HEAD_H
end

local function NewGroup(view)
    local row = CreateFrame("Frame", nil, view)
    row.text = ns.Font(row, SMALL_SIZE, nil, T.accentSoft)
    row.text:SetPoint("BOTTOMLEFT", PAD, 7)
    Rule(row)
    return row
end

local groupLabels = {}

local function SetGroup(row, title)
    local label = groupLabels[title]
    if not label then
        label = title:upper()
        groupLabels[title] = label
    end
    row.text:SetText(label)
    return GROUP_H
end

local function ResetClicked(link)
    local foot = link:GetParent()
    Settings.Reset(foot.card)
    foot:GetParent():QueueSettingsRedraw()
end

local function NewFoot(view)
    local foot = CreateFrame("Frame", nil, view)
    foot.text = ns.Font(foot, SMALL_SIZE, nil, T.muted)
    foot.text:SetPoint("LEFT", PAD, 0)
    foot.reset = Parts.Link(foot, ResetClicked, true)
    foot.reset:SetPoint("RIGHT", -PAD, 0)
    return foot
end

local changedText = {}

local function SetFoot(foot, card, changed)
    foot.card = card
    local text = changedText[changed]
    if not text then
        text = changed == 1 and "1 setting changed from its default" or (changed .. " settings changed from their defaults")
        changedText[changed] = text
    end
    foot.text:SetText(text)
    Parts.SetLink(foot.reset, "Reset " .. card.name)
    return FOOT_H
end

local function Value(value)
    if type(value) == "function" then return value() end
    return value
end

local INFO_TOP, INFO_GAP, INFO_BOTTOM = 10, 4, 10

local function NewInfoLine(view)
    local row = CreateFrame("Frame", nil, view)
    row.rule = Rule(row)
    row.title = ns.Font(row, LABEL_SIZE, nil, T.fg)
    row.title:SetPoint("TOPLEFT", PAD, -INFO_TOP)
    row.where = ns.Font(row, SMALL_SIZE, nil, T.muted)
    row.where:SetPoint("BOTTOMLEFT", row.title, "BOTTOMRIGHT", CONTROL_GAP, 0)
    row.text = ns.Font(row, LABEL_SIZE - 1, nil, T.muted)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    return row
end

local function SetInfoLine(row, line)
    local titled = line.title ~= nil
    row.title:SetText(line.title or "")
    row.where:SetText(line.where or "")
    row.text:ClearAllPoints()
    if titled then
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -INFO_GAP)
    else
        row.text:SetPoint("TOPLEFT", PAD, -INFO_TOP)
    end
    row.text:SetWidth(row:GetWidth() - PAD * 2)
    row.text:SetText(line.text or "")
    local textH = line.text and math.ceil(row.text:GetStringHeight()) or 0
    local titleH = titled and (LABEL_SIZE + (line.text and INFO_GAP or 0)) or 0
    return INFO_TOP + titleH + textH + INFO_BOTTOM
end

local function NewWindowCard(view)
    return Parts.SettingsCardFrame(view)
end

local function SetWindowCard(card, spec)
    return Parts.PaintSettingsCard(card, spec.text, spec.open, Value(spec.headline), Value(spec.detail))
end

local kinds = View.NewKinds()
kinds.setting = { New = NewSetting, Set = SetSetting }
kinds.cardHead = { New = NewHead, Set = SetHead }
kinds.group = { New = NewGroup, Set = SetGroup }
kinds.cardFoot = { New = NewFoot, Set = SetFoot }
kinds.window = { New = NewWindowCard, Set = SetWindowCard }
kinds.infoLine = { New = NewInfoLine, Set = SetInfoLine }
Settings.kinds = kinds

local Draw = {}

function Draw:Settings(card)
    local w = self:GetWidth()
    local columns = w >= TWO_COLUMNS_W and 2 or 1
    local half = math.floor(w / 2)
    -- A hidden row is set on the card's preview instead; it is still searched, counted and reset.
    local rows = wipe(self.shownRows)
    for _, row in ipairs(Settings.Rows(card)) do
        local hidden = row.hidden
        if type(hidden) == "function" then hidden = hidden() end
        if not hidden then rows[#rows + 1] = row end
    end
    local i = 1
    while i <= #rows do
        local row = rows[i]
        self.left, self.width = 0, w
        if row.kind == "group" then
            self:Add("group", row.group)
            i = i + 1
        elseif row.wide or columns == 1 then
            self:Add("setting", row, false)
            i = i + 1
        else
            local top = self.cursor
            local second = rows[i + 1]
            local pair = second and second.kind ~= "group" and not second.wide
            self.width = half
            self:Add("setting", row, true)
            if pair then
                self.cursor = top
                self.left, self.width = half, w - half
                self:Add("setting", second, false)
                i = i + 2
            else
                i = i + 1
            end
            self.left, self.width = 0, w
        end
    end
end

function Draw:Card(card)
    local top = self.cursor
    self.left, self.width = 0, self:GetWidth()
    local frame = self:Acquire("card")
    frame:SetFrameLevel(self:GetFrameLevel())
    frame.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
    frame.note:Hide()
    local isOpen = Settings.IsOpen(card) and Openable(card)
    self:Add("cardHead", card, isOpen)
    if isOpen and card.info then
        for _, line in ipairs(card.rows) do
            if line.group then self:Add("group", line.group) else self:Add("infoLine", line) end
        end
    elseif isOpen then
        if card.studio and self.kinds.studio then self:Add("studio", card) end
        self:Settings(card)
        local changed = Settings.ChangedCount(card)
        if changed > 0 then self:Add("cardFoot", card, changed) end
    end
    frame:SetHeight(self.cursor - top)
    self:Space(CARD_GAP)
end

function Draw:Redraw()
    self:Clear()
    local page = Settings.pages[self.pageKey]
    if page then
        for _, item in ipairs(page.items) do
            if item.window then
                self:Add("window", item)
                self:Space(CARD_GAP)
            else
                self:Card(item)
            end
        end
    end
    self:Fit(NO_EVENTS)
end

function Draw:QueueSettingsRedraw()
    if self.settingsQueued then return end
    self.settingsQueued = true
    C_Timer.After(0, self.settingsRedrawFn)
end

local DRAG_WAIT = 0.05   -- seconds between looks for the end of a slider drag

-- A slider being dragged (UI.sliderDrag) holds the redraw until it is let go: the redraw
-- hides and shows the rows again, and hiding the slider ended its drag after one step.
local function FlushSettings(view)
    if ns.UI.sliderDrag then
        C_Timer.After(DRAG_WAIT, view.settingsRedrawFn)
        return
    end
    view.settingsQueued = false
    if view:IsVisible() then
        view:Redraw()
        if view.onResize then view.onResize(view:GetHeight()) end
    end
end

local watched = {}

local function Watch(store, view)
    local views = watched[store]
    if not views then
        views = {}
        watched[store] = views
        store.OnChange(function()
            for v in pairs(views) do
                if v:IsVisible() then v:QueueSettingsRedraw() end
            end
        end)
    end
    views[view] = true
end

local function NewView(parent)
    local view = View.New(parent, kinds, Draw)
    view.settingsRedrawFn = function() FlushSettings(view) end
    view.shownRows = {}
    return view
end

function Settings.Render(parent, pageKey, onResize)
    local view = parent.settingsView
    if not view then
        view = NewView(parent)
        parent.settingsView = view
    end
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", parent, "TOPLEFT", ns.UI.CONTENT_PAD, -ns.UI.CONTENT_PAD / 2)
    view:SetWidth(math.max(1, parent:GetWidth() - ns.UI.CONTENT_PAD * 2))
    view.pageKey, view.onResize = pageKey, onResize
    local page = Settings.pages[pageKey]
    for _, item in ipairs(page and page.items or NO_EVENTS) do
        if item.store then Watch(item.store, view) end
        for _, row in ipairs(item.rows or NO_EVENTS) do
            if row.store and row.store ~= item.store then Watch(row.store, view) end
        end
    end
    view:Show()
    view:Redraw()
    return view:GetHeight() + ns.UI.CONTENT_PAD
end

local findLabel, findCard

local function IsSetting(row)
    return row.setting.label == findLabel and (not findCard or row.setting.card.uid == findCard)
end

local function IsHead(head)
    return (findLabel == nil or head.card.name == findLabel) and (not findCard or head.card.uid == findCard)
end

function Settings.FindRow(parent, label, cardUid)
    local view = parent.settingsView
    if not view then return nil end
    findLabel, findCard = label, cardUid
    local row = (label and view:Find("setting", IsSetting)) or view:Find("cardHead", IsHead)
    findLabel, findCard = nil, nil
    if not row then return nil end
    return row, row.top + ns.UI.CONTENT_PAD / 2
end

function Settings.Reveal(cardUid)
    local card = cardUid and Settings.CardOf(cardUid)
    if card then Settings.SetOpen(card, true) end
end
