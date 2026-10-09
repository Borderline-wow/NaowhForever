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
local ICON_SIZE = 22            -- a row's icons, left of its control
local ICON_REST, ICON_LIT, ICON_OFF = 0.4, 0.8, 0.12   -- an icon's alpha: resting, hovered, greyed out
local COG_W = 380               -- a cog's panel
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

-- The typed words of the sidebar's search, lit in a row's own text.
local function Marked(row, text)
    local filter = row:GetParent().filter
    return filter and ns.UI.Search.Mark(filter, text) or text
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
Controls.texture = Controls.choice
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
    if kind == "texture" then return ns.UI.TextureChoices(setting.get(), setting.texture) end
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
    if kind == "choice" or kind == "font" or kind == "texture" or kind == "sound" then
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

-- A row's icon (Settings.lua: row.icons, row.cog): dim until hovered, greyed out while it
-- cannot be used. A cog opens the panel of the rows set under it.
local ToggleCog, CogAnchored

local function IconEnter(icon)
    icon:SetAlpha(ICON_LIT)
    local tip = icon.spec and icon.spec.tip
    if tip then ns.UI.ShowWidgetTooltip(icon, tip) end
end

local function IconLeave(icon)
    icon:SetAlpha(ICON_REST)
    ns.UI.HideWidgetTooltip()
end

local function IconClicked(icon)
    local spec = icon.spec
    if not spec then return end
    if spec.cogFor then
        ToggleCog(icon, icon:GetParent().setting)
    elseif spec.open then
        spec.open(icon)
    end
end

local function NewIcon(row)
    local icon = CreateFrame("Button", nil, row)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetFrameLevel(row:GetFrameLevel() + 5)
    icon.tex = icon:CreateTexture(nil, "OVERLAY")
    icon.tex:SetAllPoints()
    icon:SetScript("OnEnter", IconEnter)
    icon:SetScript("OnLeave", IconLeave)
    icon:SetScript("OnClick", IconClicked)
    return icon
end

-- Lays the row's icons out from `left`, the control, outward; returns the last one, the new left.
local function SetIcons(row, setting, left, off)
    local icons = setting.icons or NO_EVENTS
    for i = 1, #icons do
        local spec = icons[i]
        local icon = row.icons[i]
        if not icon then
            icon = NewIcon(row)
            row.icons[i] = icon
        end
        local on = not off and (spec.enabled == nil or spec.enabled())
        icon.spec = spec
        icon.tex:SetTexture(spec.texture or ns.UI.COGS_ICON)
        -- A cog whose settings were changed shows it, as a row's dot does.
        local tint = spec.cogFor and Settings.CogChanged(setting.card, setting.label) and T.accentSoft or T.fg
        icon.tex:SetVertexColor(tint.r, tint.g, tint.b, 1)
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", left, "LEFT", -CONTROL_GAP, 0)
        icon:EnableMouse(on)
        icon:SetAlpha(on and ICON_REST or ICON_OFF)
        icon:Show()
        if spec.cogFor then CogAnchored(icon, setting) end
        left = icon
    end
    for i = #icons + 1, #row.icons do row.icons[i]:Hide() end
    return left
end

local function NewSetting(view)
    local row = CreateFrame("Frame", nil, view)
    row:SetHeight(ROW_H)
    row.Get = function() return RowGet(row) end
    row.Set = function(...) RowSet(row, ...) end
    row.controls = {}
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
    row.icons = {}
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
    elseif kind == "choice" or kind == "font" or kind == "texture" or kind == "sound" then
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
    if setting.tip then
        ns.Tooltip(control, setting.label, setting.tip)
    elseif kind ~= "button" and control._tipHooked then
        control._tipTitle, control._tipBody = nil, nil
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
    row.label:SetText(Marked(row, setting.label))
    row.hit.help = setting.help
    row.dot:SetShown(Settings.Changed(setting))
    row.split:SetShown(split)
    local off, why = Settings.Off(setting)
    Dim(row, control, off)
    local left = SetIcons(row, setting, control, off)
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
    if head.held or not Openable(card) then return end
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

-- held: a search holds the card open, so its head does not fold it.
local function SetHead(head, card, isOpen, held)
    head.card, head.held = card, held
    head.name:SetText(Marked(head, card.name))
    head.nameHit.help = card.help
    head.chevron:SetRotation(isOpen and -math.pi / 2 or 0)
    head.chevron:SetShown(Openable(card) and not held)
    head.rule:SetShown(isOpen)
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

-- A hidden row is set on the card's preview instead; it is still searched, counted and reset.
local function Hidden(row)
    local hidden = row.hidden
    if type(hidden) == "function" then hidden = hidden() end
    return hidden
end

-- only: the labels the search keeps (a group title stays while a setting under it does), or
-- nil for every row.
function Draw:Settings(card, only)
    local w = self:GetWidth()
    local columns = w >= TWO_COLUMNS_W and 2 or 1
    local half = math.floor(w / 2)
    local rows = wipe(self.shownRows)
    for _, row in ipairs(Settings.Rows(card)) do
        local group = row.kind == "group"
        local keep = not Hidden(row) and (not only or group or only[row.label])
        if keep and only and group and rows[#rows] and rows[#rows].kind == "group" then
            rows[#rows] = row
        elseif keep then
            rows[#rows + 1] = row
        end
    end
    if only and rows[#rows] and rows[#rows].kind == "group" then rows[#rows] = nil end
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

-- found: what the search kept of the card, true for all of it or its matching labels; a card
-- the search kept is drawn open.
function Draw:Card(card, found)
    local top = self.cursor
    self.left, self.width = 0, self:GetWidth()
    local frame = self:Acquire("card")
    frame:SetFrameLevel(self:GetFrameLevel())
    frame.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
    frame.note:Hide()
    local isOpen = (found ~= nil or Settings.IsOpen(card)) and Openable(card)
    self:Add("cardHead", card, isOpen, found ~= nil)
    if isOpen and card.info then
        for _, line in ipairs(card.rows) do
            if line.group then self:Add("group", line.group) else self:Add("infoLine", line) end
        end
    elseif isOpen then
        -- A match set on the preview (a hidden row) can only be changed there, so the card
        -- shows whole. Part of a card shows no reset, which would reset what is left out too.
        -- A match in a cog's panel keeps the row the cog is on, and opens the cog once drawn.
        local only, cogOwner = found ~= true and found or nil, nil
        for _, row in ipairs(only and Settings.Rows(card) or NO_EVENTS) do
            if only[row.label] and row.under ~= nil then
                only[row.under], cogOwner = true, row.under
            elseif only[row.label] and Hidden(row) then
                only = nil
                break
            end
        end
        if card.studio and self.kinds.studio and not only then self:Add("studio", card) end
        self:Settings(card, only)
        if cogOwner then self:OpenCogOn(card, cogOwner) end
        local changed = Settings.ChangedCount(card)
        if changed > 0 and not only then self:Add("cardFoot", card, changed) end
    end
    frame:SetHeight(self.cursor - top)
    self:Space(CARD_GAP)
end

-- With a search (self.filter), only the cards it kept are drawn, unless the page matched by
-- its own name.
function Draw:Redraw()
    self:Clear()
    local page = Settings.pages[self.pageKey]
    local f = self.filter
    if f and f.all[self.pageKey] then f = nil end
    if page then
        local drawn = false
        for _, item in ipairs(page.items) do
            if not f then
                if item.window then
                    self:Add("window", item)
                    self:Space(CARD_GAP)
                else
                    self:Card(item)
                end
            elseif not item.window and f.cards[item.uid] then
                self:Card(item, f.cards[item.uid])
                drawn = true
            end
        end
        if f and not drawn then self:Note("Nothing on this page matches the search.") end
    end
    self:Fit(NO_EVENTS)
end

-------------------------------------------------------------------------------
--  A cog's panel: the rows set under a row's cog, drawn as the page draws its rows, so their
--  dots, controls and help are the same. Under the cog; a second click on it closes it, and so
--  does its x, or the page going away.
-------------------------------------------------------------------------------
local cog   -- the one panel: cog.card and cog.label say whose rows it shows

local CogDraw = {}

function CogDraw:Redraw()
    self:Clear()
    local w = self:GetWidth()
    if cog.card then
        for _, row in ipairs(Settings.Rows(cog.card)) do
            if row.under == cog.label then
                self.left, self.width = 0, w
                self:Add("setting", row, false)
            end
        end
    end
    self:Fit(NO_EVENTS)
end

local function FitCog(height)
    cog:SetHeight(St.PANEL_HEADER + height + St.PANEL_PAD)
end

local function CogPanel()
    if cog then return cog end
    for k, v in pairs(Draw) do if CogDraw[k] == nil then CogDraw[k] = v end end
    cog = Parts.Panel("")
    cog:SetFrameStrata("DIALOG")
    cog:SetToplevel(true)
    cog:SetWidth(COG_W)
    cog.view = View.New(cog, kinds, CogDraw)
    cog.view.settingsRedrawFn = function() Draw.FlushSettings(cog.view) end
    cog.view.shownRows = {}
    cog.view.onResize = FitCog
    cog.view:SetPoint("TOPLEFT", St.PANEL_PAD, -St.PANEL_HEADER)
    cog.view:SetWidth(COG_W - St.PANEL_PAD * 2)
    cog:Hide()
    return cog
end

-- Whether the panel shows this row's cog: a redraw of the page puts the panel under the cog's
-- new place.
function CogAnchored(icon, setting)
    if not (cog and cog:IsShown() and cog.card == setting.card and cog.label == setting.label) then return end
    cog.icon = icon
    cog:ClearAllPoints()
    cog:SetPoint("TOP", icon, "BOTTOM", 0, -CONTROL_GAP)
end

local function OpenCog(icon, setting)
    CogPanel()
    cog.card, cog.label, cog.page = setting.card, setting.label, icon:GetParent():GetParent()
    cog.title:SetText((setting.cog and setting.cog.title) or setting.label)
    Draw.Watch(setting.card.store, cog.view)
    cog:Show()
    CogAnchored(icon, setting)
    cog.view:Redraw()
    FitCog(cog.view:GetHeight())
end

function ToggleCog(icon, setting)
    if cog and cog:IsShown() and cog.card == setting.card and cog.label == setting.label then
        cog:Hide()
        return
    end
    OpenCog(icon, setting)
end

-- The page has drawn the row with this label: its cog opens (a search hit behind it).
function Draw:OpenCogOn(card, label)
    for i = 1, self.pools.setting.used do
        local row = self.pools.setting[i]
        local setting = row.setting
        if setting and setting.card == card and setting.label == label then
            for _, icon in ipairs(row.icons) do
                if icon:IsShown() and icon.spec and icon.spec.cogFor then
                    if not (cog and cog:IsShown() and cog.card == card and cog.label == label) then
                        OpenCog(icon, setting)
                    end
                    return
                end
            end
        end
    end
end

Settings.CogPanel = function() return cog end

function Draw:QueueSettingsRedraw()
    if self.settingsQueued then return end
    self.settingsQueued = true
    C_Timer.After(0, self.settingsRedrawFn)
end

local DRAG_WAIT = 0.05   -- seconds between looks for the end of a slider drag

-- A slider being dragged (UI.sliderDrag) holds the redraw until it is let go: the redraw
-- hides and shows the rows again, and hiding the slider ended its drag after one step.
function Draw.FlushSettings(view)
    if ns.UI.sliderDrag then
        C_Timer.After(DRAG_WAIT, view.settingsRedrawFn)
        return
    end
    view.settingsQueued = false
    if view:IsVisible() then
        view.stale = nil
        view:Redraw()
        if view.onResize then view.onResize(view:GetHeight()) end
    else
        view.stale = true
    end
end

local watched = {}

-- A view changed while hidden is drawn again as it shows, so it never shows an old value (an
-- options window that stepped aside for a picker, a page another page changed).
function Draw.Watch(store, view)
    local views = watched[store]
    if not views then
        views = {}
        watched[store] = views
        store.OnChange(function()
            for v in pairs(views) do
                if v:IsVisible() then v:QueueSettingsRedraw() else v.stale = true end
            end
        end)
    end
    views[view] = true
end

local function ShownAgain(view)
    if not view.stale then return end
    view.stale = nil
    view:QueueSettingsRedraw()
end

-- The page's rows hide for a moment each time it is drawn again: the cog's panel closes only
-- once the page itself has gone.
local function PageGone(view)
    if not (cog and cog:IsShown() and cog.page == view) then return end
    C_Timer.After(0, view.goneFn)
end

local function NewView(parent)
    local view = View.New(parent, kinds, Draw)
    view.settingsRedrawFn = function() Draw.FlushSettings(view) end
    view.goneFn = function()
        if cog and cog.page == view and not view:IsVisible() then cog:Hide() end
    end
    view.shownRows = {}
    view:HookScript("OnShow", ShownAgain)
    view:HookScript("OnHide", PageGone)
    return view
end

-- filter: the sidebar search's (Core/NaowhForever_Search.lua), nil for the whole page.
function Settings.Render(parent, pageKey, onResize, filter)
    local view = parent.settingsView
    if not view then
        view = NewView(parent)
        parent.settingsView = view
    end
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", parent, "TOPLEFT", ns.UI.CONTENT_PAD, -ns.UI.CONTENT_PAD / 2)
    view:SetWidth(math.max(1, parent:GetWidth() - ns.UI.CONTENT_PAD * 2))
    view.pageKey, view.onResize, view.filter = pageKey, onResize, filter
    local page = Settings.pages[pageKey]
    for _, item in ipairs(page and page.items or NO_EVENTS) do
        if item.store then Draw.Watch(item.store, view) end
        -- Another module's settings the card is drawn from (card.watch = { store, ... }).
        for _, store in ipairs(item.watch or NO_EVENTS) do Draw.Watch(store, view) end
        for _, row in ipairs(item.rows or NO_EVENTS) do
            if row.store and row.store ~= item.store then Draw.Watch(row.store, view) end
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
    -- A setting set in a cog's panel: the row the cog is on, with the cog opened.
    local card = cardUid and label and Settings.CardOf(cardUid)
    local owner = card and Settings.UnderOf(card, label)
    if owner then
        label = owner
        view:OpenCogOn(card, owner)
    end
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
