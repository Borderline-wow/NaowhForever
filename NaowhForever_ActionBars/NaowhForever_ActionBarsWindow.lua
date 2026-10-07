-------------------------------------------------------------------------------
--  NaowhForever_ActionBarsWindow.lua -- Action Bars' own window (/nfbars, /nf bars, Open
--  Action Bars on its settings page), in three views: your class's saved sets (drawn by
--  ns.BuildActionBarsPage), the set builder (pick the bars, slots, keybinds and macros that
--  go in) and the import preview (your bars as an import would leave them).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ActionBarSettings
local Sets = ns.ActionBarSets
local UI = ns.UI
local T = ns.THEME
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 980, 640
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR = St.CONTENT_INSET, St.SCROLLBAR
local PAGE = "Action Bars/Settings"
local CARD = 6
local TOP_Y = -6
local SIDE_W = 320          -- the right-hand column of the builder and the preview
local GAP = 10              -- between cards
local KEEP_H = 330          -- the builder's Also Keep card
local INNER = 14            -- a card's edge to what is in it
local SCROLL_GAP = 6        -- a list to its scrollbar

local TILE, TILE_GAP = 42, 5
local ROW_PAD = 10          -- a bar's edge to its name and tiles
local ROW_HEAD = 20         -- a bar's name line
local ROW_GAP = 8           -- between bars
local ROW_FILL = 0.35       -- a bar's backing: the window backdrop, this solid
local BOX = 18              -- a tick box
local TICK = 12
local KEY_SIZE = 9          -- a tile's keybind
local ICON_CROP = 0.08      -- the game's icons carry a dark rim; cropped this far in
local OUT_ALPHA = 0.22      -- a slot left out of the set
local LATER_ALPHA = 0.45    -- a spell not known yet
local CHIP_H = 13
local CHIP_SIZE = 9
local LINE_GAP = 4
local MACRO_ROW_H = 38
local MACRO_GAP = 4
local SWITCH_W, SWITCH_H = 36, 18
local BUTTON_H = 30
local MARK = 24             -- the preview's row markers
local TEXT_X = MARK + 10    -- a marker's left edge to its text
local FACT_GAP = 14         -- between the preview's lines
local MACROS_SHOWN = 5      -- macros listed by name in the preview
local NAMES_SHOWN = 6       -- spells named in the preview's first line

local QUESTION_ICON = 134400

local LATER_RGB = { r = 0.79, g = 0.64, b = 0.29 }
local NEW_RGB = { r = 0.11, g = 0.37, b = 0.56 }
local ACCOUNT_RGB = { r = 0.17, g = 0.23, b = 0.29 }
local CHARACTER_RGB = { r = 0.23, g = 0.19, b = 0.31 }
local GOOD_RGB = St.HAVE_RGB

local window, views, view
local queued

-------------------------------------------------------------------------------
--  Small parts
-------------------------------------------------------------------------------
local function Label(parent, size, color)
    local fs = ns.Font(parent, size, nil, color)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Chip(parent)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetHeight(CHIP_H)
    chip.fill = ns.Solid(chip, "BACKGROUND", NEW_RGB, 1)
    chip.fill:SetAllPoints()
    ns.Border(chip, St.BORDER_RGB)
    chip.text = ns.Font(chip, CHIP_SIZE, nil, T.fg)
    chip.text:SetPoint("CENTER", 0, 0)
    return chip
end

local function PaintChip(chip, text, color)
    chip.text:SetText(text)
    chip.fill:SetColorTexture(color.r, color.g, color.b, 1)
    chip:SetWidth(math.ceil(chip.text:GetStringWidth()) + 8)
    chip:Show()
end

local function Box(parent)
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(BOX, BOX)
    box.fill = ns.Solid(box, "BACKGROUND", T.bg, 1)
    box.fill:SetAllPoints()
    ns.Border(box, St.BORDER_RGB)
    box.tick = box:CreateTexture(nil, "ARTWORK")
    box.tick:SetTexture(St.TICK)
    box.tick:SetSize(TICK, TICK)
    box.tick:SetPoint("CENTER")
    box:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    return box
end

local function PaintBox(box, on, locked)
    local c = on and T.accent or T.bg
    box.fill:SetColorTexture(c.r, c.g, c.b, locked and 0.5 or 1)
    box.tick:SetShown(on)
end

local function Switch(parent, get, set)
    return UI.BuildToggleControl(parent, nil, get, set, SWITCH_W, SWITCH_H)
end

local function Hint(owner, title, line)
    if not Parts.Tip(owner, "ANCHOR_TOP") then return end
    GameTooltip:SetText(title, 1, 1, 1)
    if line then GameTooltip:AddLine(line, T.muted.r, T.muted.g, T.muted.b, true) end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  A tile: one action slot, as its icon in a black edge with its key in the corner
-------------------------------------------------------------------------------
local function TileEnter(tile)
    if not tile.tip then return end
    if not Parts.Tip(tile, "ANCHOR_TOP") then return end
    tile.tip(GameTooltip)
    GameTooltip:Show()
end

local function TileClick(tile)
    if tile.onClick then tile.onClick() end
end

local function NewTile(parent)
    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(TILE, TILE)
    tile.back = ns.Solid(tile, "BACKGROUND", T.bg, 1)
    tile.back:SetAllPoints()
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    tile.edge = ns.Border(tile, St.BORDER_RGB)
    tile.key = ns.Font(tile, KEY_SIZE, "OUTLINE", T.fg)
    tile.key:SetPoint("TOPRIGHT", -2, -2)
    tile.badge = Chip(tile)
    tile.badge:SetPoint("CENTER", tile, "BOTTOM", 0, 1)
    tile.badge:SetFrameLevel(tile:GetFrameLevel() + 3)
    tile:SetScript("OnEnter", TileEnter)
    tile:SetScript("OnLeave", GameTooltip_Hide)
    tile:SetScript("OnClick", TileClick)
    return tile
end

-- look: { texture, key, alpha, grey, edge (a colour), badge, badgeColor, tip, onClick }
local function PaintTile(tile, look)
    tile.icon:SetTexture(look.texture)
    tile.icon:SetShown(look.texture ~= nil)
    tile.icon:SetDesaturated(look.grey or false)
    tile.icon:SetAlpha(look.alpha or 1)
    local edge = look.edge or St.BORDER_RGB
    tile.edge:SetColor(edge.r, edge.g, edge.b, 1)
    tile.key:SetText(look.key or "")
    if look.badge then PaintChip(tile.badge, look.badge, look.badgeColor) else tile.badge:Hide() end
    tile.tip, tile.onClick = look.tip, look.onClick
end

-------------------------------------------------------------------------------
--  A bar: its name, a tick box (the builder's), a count and twelve tiles
-------------------------------------------------------------------------------
local function NewBarRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_PAD * 2 + ROW_HEAD + TILE)
    ns.Solid(row, "BACKGROUND", T.bg, ROW_FILL):SetAllPoints()
    ns.Border(row, St.BORDER_RGB)
    row.box = Box(row)
    row.box:SetPoint("TOPLEFT", ROW_PAD, -ROW_PAD + 1)
    row.name = Label(row, 13, T.fg)
    row.count = ns.Font(row, 11, nil, T.muted)
    row.count:SetPoint("TOPRIGHT", -ROW_PAD, -ROW_PAD - 2)
    row.tiles = {}
    for i = 1, 12 do
        local tile = NewTile(row)
        tile:SetPoint("TOPLEFT", ROW_PAD + (i - 1) * (TILE + TILE_GAP), -(ROW_PAD + ROW_HEAD + 4))
        row.tiles[i] = tile
    end
    return row
end

local function KeyText(command)
    local key = command and GetBindingKey(command)
    return key and GetBindingText(key, true) or ""
end

-------------------------------------------------------------------------------
--  The window's views
-------------------------------------------------------------------------------
local function Opacity()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("windowAlpha", value / 100)
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
    window.note.text:SetText(Sets.Headline())
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
end

local Show

-- A scrolling list inside a pane, its content as wide as the pane leaves it.
local function List(pane, top, bottom)
    local scroll = UI.SlimScroll(pane)
    scroll:SetPoint("TOPLEFT", 0, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(SCROLL_GAP * 2), bottom or 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    return scroll, content
end

local function Pane(left, top, right, bottom)
    local pane = CreateFrame("Frame", nil, window)
    pane:SetPoint("TOPLEFT", left + INNER, -(top + INNER))
    pane:SetPoint("BOTTOMRIGHT", -(right + INNER), bottom + INNER)
    return pane
end

local function Heading(pane, text, hint)
    local title = Label(pane, 12, T.fg)
    title:SetPoint("TOPLEFT")
    title:SetText(text)
    if hint then
        local line = ns.Font(pane, 11, nil, T.muted)
        line:SetPoint("TOPRIGHT")
        line:SetText(hint)
        return title, line
    end
    return title
end

local function Divider(pane, y)
    local line = ns.Solid(pane, "ARTWORK", St.BORDER_RGB, 1)
    line:SetPoint("TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", 0, y)
    ns.Hairline(line, "h")
    return line
end

-------------------------------------------------------------------------------
--  Saved sets
-------------------------------------------------------------------------------
local function BuildSets()
    local v = { cards = window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD) }
    v.frame = CreateFrame("Frame", nil, window)
    v.frame:SetAllPoints()
    local left, top = CARD + INSET, HEADER + CARD + PAD
    v.scroll = UI.SlimScroll(v.frame)
    v.scroll:SetPoint("TOPLEFT", left, -top)
    v.scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    v.content = CreateFrame("Frame", nil, v.scroll)
    v.content:SetSize(WIDTH - left - CARD - SCROLLBAR - INSET, 1)
    v.scroll:SetScrollChild(v.content)
    v.title, v.subtitle = "Action Bars", "Save your bars, macros and keybinds, then import them on any character."
    function v.Draw()
        UI.BeginReusableRows(v.content)
        local y = ns.BuildActionBarsPage(v.content, TOP_Y)
        v.content:SetHeight(math.abs(y) + PAD)
    end
    return v
end

-------------------------------------------------------------------------------
--  The builder: your bars as they are now, each slot in or out, then keybinds, macros and a
--  name. A set saved from here keeps its choices, and saving it again (Save on Logout too)
--  makes the same picks.
-------------------------------------------------------------------------------
local draft

local function Copy(t)
    local out = {}
    for k, val in pairs(t or {}) do out[k] = val end
    return out
end

local function NewDraft(key)
    local set = key and Sets.Get(key)
    local choices = set and set.choices or {}
    draft = {
        key = set and key or nil, name = set and key or "",
        choices = { skip = Copy(choices.skip), macroOff = Copy(choices.macroOff),
            keys = choices.keys ~= false, macros = choices.macros ~= false },
    }
end

local function BarSlots(bar)
    local first = (bar.page - 1) * 12
    local list = {}
    for i = 1, 12 do list[i] = first + i end
    return list
end

local function Redraw()
    queued = false
    if not (window and window:IsShown()) then return end
    views[view].Draw()
    Paint()
end

local function RedrawSoon()
    if queued or not (window and window:IsShown()) then return end
    queued = true
    C_Timer.After(0, Redraw)
end

local function Flip(t, key)
    t[key] = not t[key] or nil
    Redraw()
end

local function SlotTip(slot, kept)
    return function(tip)
        if GetActionInfo(slot) then tip:SetAction(slot) else tip:SetText("Empty slot", 1, 1, 1) end
        tip:AddLine(" ")
        if kept then
            tip:AddLine(GetActionInfo(slot) and "In the set. Click to leave it out."
                or "In the set as empty: an import clears it. Click to leave it out.", T.muted.r, T.muted.g, T.muted.b, true)
        else
            tip:AddLine("Left out: an import leaves this slot as it is. Click to put it back in.",
                T.muted.r, T.muted.g, T.muted.b, true)
        end
    end
end

local function DrawBuilderBars(v)
    local content, skip = v.content, draft.choices.skip
    UI.BeginReusableRows(content)
    local y, actions = 0, 0
    for _, bar in ipairs(Sets.BARS) do
        local list, used, total, out = BarSlots(bar), 0, 0, 0
        for _, slot in ipairs(list) do
            if GetActionInfo(slot) then
                total = total + 1
                if not skip[slot] then used = used + 1 end
            end
            if skip[slot] then out = out + 1 end
        end
        if total > 0 or out > 0 then
            actions = actions + used
            local row = UI.Keep(content, "bar", NewBarRow)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", 0, y)
            local barOn = out < 12
            row:SetAlpha(barOn and 1 or 0.55)
            row.box:Show()
            PaintBox(row.box, barOn)
            row.box.onClick = function()
                for _, slot in ipairs(list) do skip[slot] = barOn or nil end
                Redraw()
            end
            row.box:SetScript("OnEnter", function(box)
                Hint(box, barOn and "Leave this bar out" or "Put this bar back in",
                    "A bar left out is not touched by an import.")
            end)
            row.box:SetScript("OnLeave", GameTooltip_Hide)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
            row.name:SetText(bar.name)
            row.count:SetText(("%d / %d"):format(used, total))
            for i, slot in ipairs(list) do
                local kept = not skip[slot]
                PaintTile(row.tiles[i], {
                    texture = GetActionTexture(slot),
                    key = GetActionInfo(slot) and KeyText(bar.button .. i) or "",
                    alpha = kept and 1 or OUT_ALPHA, grey = not kept,
                    edge = (not kept) and T.muted or nil,
                    tip = SlotTip(slot, kept),
                    onClick = function() Flip(skip, slot) end,
                })
            end
            y = y - row:GetHeight() - ROW_GAP
        end
    end
    content:SetHeight(math.max(1, -y))
    return actions
end

local function NewMacroRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(MACRO_ROW_H)
    ns.Solid(row, "BACKGROUND", T.bg, ROW_FILL):SetAllPoints()
    ns.Border(row, St.BORDER_RGB)
    row.box = Box(row)
    row.box:SetPoint("LEFT", 8, 0)
    row.box:EnableMouse(false)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(MACRO_ROW_H - 12, MACRO_ROW_H - 12)
    row.icon:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.scope = Chip(row)
    row.scope:SetPoint("TOPRIGHT", -8, -6)
    row.onBars = Chip(row)
    row.onBars:SetPoint("TOPRIGHT", row.scope, "BOTTOMRIGHT", 0, -3)
    row.name = Label(row, 13, T.fg)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.scope, "LEFT", -6, 0)
    row.name:SetWordWrap(false)
    row.body = Label(row, 10, T.muted)
    row.body:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.body:SetPoint("RIGHT", row.scope, "LEFT", -6, 0)
    row.body:SetWordWrap(false)
    row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    row:SetScript("OnEnter", function(self)
        Hint(self, self.tipTitle, self.tipLine)
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function DrawBuilderMacros(v, slots)
    local choices, content = draft.choices, v.macroContent
    local onBars = {}
    for slot, entry in pairs(slots) do
        if entry.kind == "macro" and not choices.skip[slot] then
            onBars[Sets.MacroKey(entry.name, entry.body)] = true
        end
    end
    UI.BeginReusableRows(content)
    local y, kept, all = 0, 0, Sets.CaptureMacros()
    for _, macro in ipairs(all) do
        local key = Sets.MacroKey(macro.name, macro.body)
        local locked = onBars[key]
        local on = locked or (choices.macros and not choices.macroOff[key])
        if on then kept = kept + 1 end
        local row = UI.Keep(content, "macro", NewMacroRow)
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", 0, y)
        row:SetAlpha((choices.macros or locked) and 1 or 0.45)
        PaintBox(row.box, on, locked)
        row.icon:SetTexture(macro.icon)
        row.name:SetText(macro.name)
        row.body:SetText((macro.body or ""):gsub("[\r\n]+", "  "))
        PaintChip(row.scope, macro.perCharacter and "Character" or "Account",
            macro.perCharacter and CHARACTER_RGB or ACCOUNT_RGB)
        if locked then PaintChip(row.onBars, "On bars", T.grey) else row.onBars:Hide() end
        row.tipTitle = macro.name
        row.tipLine = locked and "On a slot in the set, so it always comes along."
            or "An alt that already has this macro, by name and text or text alone, uses its own."
        row.onClick = function()
            if locked or not choices.macros then return end
            Flip(choices.macroOff, key)
        end
        y = y - MACRO_ROW_H - MACRO_GAP
    end
    content:SetHeight(math.max(1, -y))
    return kept, #all
end

local function BindingCount()
    local n = 0
    for _ in pairs(Sets.CaptureBindings()) do n = n + 1 end
    return n
end

local function SaveDraft()
    local name = strtrim(draft.box:GetText() or "")
    if name == "" then
        ns.Print("Give the set a name first.")
        return
    end
    local function Done()
        if Sets.Save(name, draft.choices) then Show("sets") end
    end
    local existing = Sets.Find(name)
    if existing and existing ~= draft.key then
        ns.Confirm(("Replace %s with these bars?"):format(existing), Done)
    else
        Done()
    end
end

local function BuildBuilder()
    local v = { cards = {} }
    local top, bottom = HEADER + CARD, FOOTER + CARD
    local rightX = WIDTH - CARD - SIDE_W
    for _, part in ipairs(window.backdrop:Card(CARD, top, SIDE_W + CARD + GAP, bottom)) do v.cards[#v.cards + 1] = part end
    for _, part in ipairs(window.backdrop:Card(rightX, top, CARD, HEIGHT - top - KEEP_H)) do v.cards[#v.cards + 1] = part end
    for _, part in ipairs(window.backdrop:Card(rightX, top + KEEP_H + GAP, CARD, bottom)) do v.cards[#v.cards + 1] = part end

    v.frame = CreateFrame("Frame", nil, window)
    v.frame:SetAllPoints()
    local bars = Pane(CARD, top, SIDE_W + CARD + GAP, bottom)
    bars:SetParent(v.frame)
    Heading(bars, "1. PICK YOUR BARS", "Click a slot to leave it out, or a bar's box for the whole bar.")
    v.scroll, v.content = List(bars, 26)

    local keep = Pane(rightX, top, CARD, HEIGHT - top - KEEP_H)
    keep:SetParent(v.frame)
    Heading(keep, "2. ALSO KEEP")
    local y = -26
    local keysName = Label(keep, 14, T.fg)
    keysName:SetPoint("TOPLEFT", 0, y)
    keysName:SetText("Keybinds")
    v.keysLine = Label(keep, 11, T.muted)
    v.keysLine:SetPoint("TOPLEFT", keysName, "BOTTOMLEFT", 0, -3)
    v.keysLine:SetPoint("RIGHT", -(SWITCH_W + 10), 0)
    v.keysSwitch = Switch(keep, function() return draft.choices.keys end, function(on)
        draft.choices.keys = on
        Redraw()
    end)
    v.keysSwitch:SetPoint("TOPRIGHT", 0, y - 4)
    y = y - 44
    Divider(keep, y)
    y = y - 10
    local macrosName = Label(keep, 14, T.fg)
    macrosName:SetPoint("TOPLEFT", 0, y)
    macrosName:SetText("Macros")
    v.macrosLine = Label(keep, 11, T.muted)
    v.macrosLine:SetPoint("TOPLEFT", macrosName, "BOTTOMLEFT", 0, -3)
    v.macrosLine:SetPoint("RIGHT", -(SWITCH_W + 10), 0)
    v.macrosSwitch = Switch(keep, function() return draft.choices.macros end, function(on)
        draft.choices.macros = on
        Redraw()
    end)
    v.macrosSwitch:SetPoint("TOPRIGHT", 0, y - 4)
    v.macroScroll, v.macroContent = List(keep, -(y - 44))

    local save = Pane(rightX, top + KEEP_H + GAP, CARD, bottom)
    save:SetParent(v.frame)
    Heading(save, "3. NAME AND SAVE")
    local label = Label(save, 11, T.muted)
    label:SetPoint("TOPLEFT", 0, -24)
    label:SetText("Set name")
    v.box = ns.NewEditBox(save)
    v.box:SetHeight(26)
    v.box:SetMaxLetters(40)
    v.box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -LINE_GAP)
    v.box:SetPoint("RIGHT")
    v.box:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    v.box:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    v.summary = Label(save, 12, T.fg)
    v.summary:SetPoint("TOPLEFT", v.box, "BOTTOMLEFT", 0, -10)
    v.summary:SetPoint("RIGHT")
    v.button = ns.AccentBorder(ns.Button(save, "Save Set", 10, BUTTON_H, SaveDraft))
    v.button:SetPoint("BOTTOMLEFT")
    v.button:SetPoint("BOTTOMRIGHT")

    v.title = "New Bar Set"
    v.subtitle = ("Pick what goes in, then import it on any %s."):format(UnitClass("player"))
    function v.Open()
        v.box:SetText(draft.name)
        draft.box = v.box
        v.title = draft.key and ("Edit " .. draft.key) or "New Bar Set"
    end
    function v.Draw()
        local slots = Sets.Capture()
        local actions = DrawBuilderBars(v)
        local kept, all = DrawBuilderMacros(v, slots)
        local choices = draft.choices
        local keys = choices.keys and BindingCount() or 0
        v.keysLine:SetText(choices.keys and ("All %d bound keys come along."):format(keys)
            or "Off: an import leaves your keys alone.")
        v.macrosLine:SetText(choices.macros and ("%d of %d come along. An alt reuses the ones it has."):format(kept, all)
            or "Only the macros on your kept slots come along.")
        v.keysSwitch._refreshValue()
        v.macrosSwitch._refreshValue()
        local parts = { ("%d actions"):format(actions) }
        if choices.keys then parts[#parts + 1] = ("%d keybinds"):format(keys) end
        parts[#parts + 1] = ("%d macros"):format(kept)
        v.summary:SetText("This set holds " .. table.concat(parts, ", ") .. ".")
    end
    v.events = { "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS" }
    return v
end

-------------------------------------------------------------------------------
--  The import preview: your bars as the import would leave them, then what comes across
-------------------------------------------------------------------------------
local importKey, preview

local function EntryTexture(entry)
    if entry.kind == "spell" then return C_Spell.GetSpellTexture(entry.id) end
    if entry.kind == "macro" then return entry.icon end
    if entry.kind == "item" then return C_Item.GetItemIconByID(entry.id) end
    return QUESTION_ICON
end

local function EntryTip(entry, line)
    return function(tip)
        if entry.kind == "spell" then
            tip:SetSpellByID(entry.id)
        elseif entry.kind == "item" then
            tip:SetItemByID(entry.id)
        else
            tip:SetText(Sets.Describe(entry), 1, 1, 1)
            if entry.kind == "macro" and entry.body then tip:AddLine(entry.body, 0.8, 0.8, 0.8, true) end
        end
        if line then
            tip:AddLine(" ")
            tip:AddLine(line, T.muted.r, T.muted.g, T.muted.b, true)
        end
    end
end

-- The key a slot will answer to: the set's own, when its keybinds come along.
local function PreviewKeys(set)
    if not (set.bindings and S.Get("importBindings")) then return KeyText end
    local byCommand = {}
    for key, command in pairs(set.bindings) do
        if not byCommand[command] or #key < #byCommand[command] then byCommand[command] = key end
    end
    return function(command)
        local key = byCommand[command]
        return key and GetBindingText(key, true) or ""
    end
end

local function PreviewLook(slot, row, key)
    local entry, state = row.entry, row.state
    if state == "skip" then
        return { texture = GetActionTexture(slot), key = key, alpha = OUT_ALPHA, grey = true,
            tip = function(tip)
                if GetActionInfo(slot) then tip:SetAction(slot) else tip:SetText("Empty slot", 1, 1, 1) end
                tip:AddLine(" ")
                tip:AddLine("Not in the set: stays as it is.", T.muted.r, T.muted.g, T.muted.b, true)
            end }
    elseif state == "clear" then
        return { key = key }
    elseif state == "later" then
        local level = row.level or 0
        local mine = UnitLevel("player")
        return { texture = EntryTexture(entry), key = key, alpha = LATER_ALPHA, grey = true, edge = LATER_RGB,
            badge = level > mine and ("LV" .. level) or "TRAIN", badgeColor = LATER_RGB,
            tip = EntryTip(entry, level > mine and ("You learn this at level %d."):format(level)
                or "Not known yet: train it, or take its talent.") }
    elseif state == "gone" then
        return { texture = EntryTexture(entry), key = key, alpha = OUT_ALPHA, grey = true,
            badge = "GONE", badgeColor = T.grey,
            tip = EntryTip(entry, "Cannot come back here, so the slot is left empty.") }
    end
    return { texture = EntryTexture(entry), key = key, edge = state == "new" and T.accent or nil,
        badge = state == "new" and "NEW" or nil, badgeColor = NEW_RGB,
        tip = EntryTip(entry, state == "new" and "A macro this character does not have yet: the import makes it." or nil) }
end

local function DrawPreviewBars(v, set)
    local content = v.content
    UI.BeginReusableRows(content)
    local keyFor, y = PreviewKeys(set), 0
    for _, bar in ipairs(Sets.BARS) do
        local list, shown = BarSlots(bar), false
        for _, slot in ipairs(list) do
            local row = preview.slots[slot]
            if row and (row.entry or (row.state == "skip" and GetActionInfo(slot))) then shown = true end
        end
        if shown then
            local row = UI.Keep(content, "bar", NewBarRow)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", 0, y)
            row:SetAlpha(1)
            row.box:Hide()
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", ROW_PAD, -ROW_PAD - 2)
            row.name:SetText(bar.name)
            local placed, total = 0, 0
            for i, slot in ipairs(list) do
                local result = preview.slots[slot]
                if result.entry and result.state ~= "skip" then
                    total = total + 1
                    if result.state == "ok" or result.state == "new" then placed = placed + 1 end
                end
                PaintTile(row.tiles[i], PreviewLook(slot, result, keyFor(bar.button .. i)))
            end
            row.count:SetText(("%d / %d"):format(placed, total))
            y = y - row:GetHeight() - ROW_GAP
        end
    end
    content:SetHeight(math.max(1, -y))
end

local function NewMarker(parent, texture, color)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(MARK, MARK)
    mark.fill = ns.Solid(mark, "BACKGROUND", color, 0.35)
    mark.fill:SetAllPoints()
    ns.Border(mark, St.BORDER_RGB)
    mark.icon = mark:CreateTexture(nil, "ARTWORK")
    mark.icon:SetTexture(texture)
    mark.icon:SetSize(MARK - 10, MARK - 10)
    mark.icon:SetPoint("CENTER")
    mark.icon:SetVertexColor(color.r, color.g, color.b, 1)
    return mark
end

-- A preview line: a marker, a title and a muted line under it.
local function NewFact(pane, texture, color)
    local fact = { mark = NewMarker(pane, texture, color) }
    fact.title = Label(pane, 14, T.fg)
    fact.title:SetPoint("TOPLEFT", fact.mark, "TOPRIGHT", TEXT_X - MARK, 1)
    fact.title:SetPoint("RIGHT")
    fact.line = Label(pane, 11, T.muted)
    fact.line:SetPoint("TOPLEFT", fact.title, "BOTTOMLEFT", 0, -3)
    fact.line:SetPoint("RIGHT")
    return fact
end

local function Names(list, shown)
    local names = {}
    for i = 1, math.min(#list, shown) do names[i] = list[i] end
    local text = table.concat(names, ", ")
    if #list > shown then text = text .. (", and %d more"):format(#list - shown) end
    return text
end

local function BuildPreview()
    local v = { cards = {} }
    local top, bottom = HEADER + CARD, FOOTER + CARD
    local rightX = WIDTH - CARD - SIDE_W
    for _, part in ipairs(window.backdrop:Card(CARD, top, SIDE_W + CARD + GAP, bottom)) do v.cards[#v.cards + 1] = part end
    for _, part in ipairs(window.backdrop:Card(rightX, top, CARD, bottom)) do v.cards[#v.cards + 1] = part end

    v.frame = CreateFrame("Frame", nil, window)
    v.frame:SetAllPoints()
    local bars = Pane(CARD, top, SIDE_W + CARD + GAP, bottom)
    bars:SetParent(v.frame)
    Heading(bars, "YOUR BARS AFTER THE IMPORT", "Nothing changes until you press Import.")
    v.scroll, v.content = List(bars, 26, 26)
    local newChip = Chip(bars)
    newChip:SetPoint("BOTTOMLEFT", 0, 4)
    PaintChip(newChip, "NEW", NEW_RGB)
    local newText = ns.Font(bars, 11, nil, T.muted)
    newText:SetPoint("LEFT", newChip, "RIGHT", 6, 0)
    newText:SetText("a macro made on this character")
    local laterChip = Chip(bars)
    laterChip:SetPoint("LEFT", newText, "RIGHT", 18, 0)
    PaintChip(laterChip, "LV", LATER_RGB)
    local laterText = ns.Font(bars, 11, nil, T.muted)
    laterText:SetPoint("LEFT", laterChip, "RIGHT", 6, 0)
    laterText:SetText("not learned yet")

    local side = Pane(rightX, top, CARD, bottom)
    side:SetParent(v.frame)
    Heading(side, "WHAT COMES ACROSS")
    v.actions = NewFact(side, St.TICK, GOOD_RGB)
    v.actions.mark:SetPoint("TOPLEFT", 0, -28)

    v.fill = CreateFrame("Frame", nil, side)
    v.fill:SetHeight(46)
    v.fill:SetPoint("LEFT")
    v.fill:SetPoint("RIGHT")
    ns.Solid(v.fill, "BACKGROUND", T.bg, ROW_FILL):SetAllPoints()
    ns.Border(v.fill, St.BORDER_RGB)
    local fillName = Label(v.fill, 13, T.fg)
    fillName:SetPoint("TOPLEFT", 10, -8)
    fillName:SetText("Fill in as you learn them")
    local fillLine = Label(v.fill, 11, T.muted)
    fillLine:SetPoint("TOPLEFT", fillName, "BOTTOMLEFT", 0, -3)
    fillLine:SetText("A trained spell drops into its saved slot.")
    v.fillSwitch = Switch(v.fill, function() return S.Get("fillLater") end, function(on) S.Set("fillLater", on) end)
    v.fillSwitch:SetPoint("RIGHT", -10, 0)

    v.macros = NewFact(side, St.PLUS, T.accentSoft)
    v.macroRows = {}
    for i = 1, MACROS_SHOWN do
        local line = CreateFrame("Frame", nil, side)
        line:SetHeight(CHIP_H + 4)
        line.name = Label(line, 12, T.fg)
        line.name:SetPoint("LEFT")
        line.chip = Chip(line)
        line.chip:SetPoint("RIGHT")
        v.macroRows[i] = line
    end
    v.macroMore = Label(side, 11, T.muted)
    v.keys = NewFact(side, St.TICK, T.muted)
    v.keys.mark.icon:Hide()
    v.keys.letter = ns.Font(v.keys.mark, 11, nil, T.fg)
    v.keys.letter:SetPoint("CENTER")
    v.keys.letter:SetText("K")

    local cancel = ns.Button(side, "Cancel", (SIDE_W - 2 * INNER - 8) / 3, BUTTON_H, function() Show("sets") end)
    v.import = ns.AccentBorder(ns.Button(side, "Import", 10, BUTTON_H, function()
        if Sets.Import(importKey) then Show("sets") end
    end))
    cancel:SetPoint("BOTTOMLEFT")
    v.import:SetPoint("BOTTOMRIGHT")
    v.import:SetPoint("LEFT", cancel, "RIGHT", 8, 0)

    v.title = "Import"
    function v.Open()
        local set = Sets.Get(importKey)
        v.title = "Import " .. importKey
        v.subtitle = ("Onto %s, level %d %s. Saved %s%s."):format(UnitName("player"), UnitLevel("player"),
            UnitClass("player"), date("%d %b %Y", set.saved), set.by and (" by " .. set.by) or "")
        preview = Sets.Preview(importKey)
    end
    function v.Draw()
        local set = Sets.Get(importKey)
        if not set then Show("sets") return end
        DrawPreviewBars(v, set)

        local later, gone = {}, {}
        for _, slot in ipairs(Sets.SlotList()) do
            local row = preview.slots[slot]
            if row.state == "later" then later[#later + 1] = Sets.Describe(row.entry) end
            if row.state == "gone" then gone[#gone + 1] = Sets.Describe(row.entry) end
        end
        v.actions.title:SetText(("%d of %d actions"):format(preview.placed, preview.actions))
        local lines = {}
        if #later > 0 then
            lines[#lines + 1] = ("%d you have not learned yet: %s."):format(#later, Names(later, NAMES_SHOWN))
        end
        if #gone > 0 then lines[#lines + 1] = ("%d cannot come back: %s."):format(#gone, Names(gone, NAMES_SHOWN)) end
        v.actions.line:SetText(#lines > 0 and table.concat(lines, " ") or "Everything goes back where it was.")

        v.fill:SetShown(#later > 0)
        v.macros.mark:ClearAllPoints()
        if #later > 0 then
            v.fill:ClearAllPoints()
            v.fill:SetPoint("TOPLEFT", v.actions.line, "BOTTOMLEFT", -TEXT_X, -FACT_GAP)
            v.fill:SetPoint("RIGHT", v.actions.title, "RIGHT")
            v.fillSwitch._refreshValue()
            v.macros.mark:SetPoint("TOPLEFT", v.fill, "BOTTOMLEFT", 0, -FACT_GAP)
        else
            v.macros.mark:SetPoint("TOPLEFT", v.actions.line, "BOTTOMLEFT", -TEXT_X, -FACT_GAP)
        end

        local fates = preview.macros
        local new, have, full = 0, 0, 0
        for _, m in ipairs(fates) do
            if m.fate == "new" then new = new + 1 elseif m.fate == "have" then have = have + 1 else full = full + 1 end
        end
        if not S.Get("importMacros") then
            v.macros.title:SetText("Macros")
            v.macros.line:SetText("Import Macros is off: a macro this character lacks stays missing.")
        else
            local title = ("%d macros: %d new, %d already here"):format(#fates, new, have)
            if full > 0 then title = title .. (", %d no room"):format(full) end
            v.macros.title:SetText(#fates > 0 and title or "No macros in this set")
            v.macros.line:SetText("Your macros are never changed or copied twice.")
        end
        local last = v.macros.line
        for i, line in ipairs(v.macroRows) do
            local m = S.Get("importMacros") and fates[i]
            line:SetShown(m and true or false)
            if m then
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -LINE_GAP)
                line:SetPoint("RIGHT", v.macros.title, "RIGHT")
                line.name:SetText(m.name)
                if m.fate == "new" then
                    PaintChip(line.chip, "New", NEW_RGB)
                elseif m.fate == "have" then
                    PaintChip(line.chip, "Already here", T.grey)
                else
                    PaintChip(line.chip, "No room", St.RED_RGB)
                end
                last = line
            end
        end
        local more = S.Get("importMacros") and #fates - MACROS_SHOWN or 0
        v.macroMore:SetShown(more > 0)
        if more > 0 then
            v.macroMore:ClearAllPoints()
            v.macroMore:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -LINE_GAP)
            v.macroMore:SetText(("and %d more"):format(more))
            last = v.macroMore
        end

        v.keys.mark:ClearAllPoints()
        v.keys.mark:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -TEXT_X, -FACT_GAP)
        if not set.bindings then
            v.keys.title:SetText("No keybinds in this set")
            v.keys.line:SetText("Your keys stay as they are.")
        elseif not S.Get("importBindings") then
            v.keys.title:SetText("Keybinds")
            v.keys.line:SetText("Import Keybinds is off: your keys stay as they are.")
        else
            v.keys.title:SetText(("%d keybinds"):format(preview.bound or 0))
            v.keys.line:SetText("Keys the set leaves free keep what they do here.")
        end
    end
    return v
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function OnEvent()
    RedrawSoon()
end

function Show(name)
    view = name
    for key, v in pairs(views) do
        local on = key == name
        v.frame:SetShown(on)
        for _, part in ipairs(v.cards) do part:SetShown(on) end
        for _, event in ipairs(v.events or {}) do
            if on then window:RegisterEvent(event) else window:UnregisterEvent(event) end
        end
    end
    local v = views[name]
    if v.Open then v.Open() end
    window.title:SetText(v.title)
    window.subtitle:SetText(v.subtitle)
    window.backLink:SetShown(name ~= "sets")
    Redraw()
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "actionBarsWindow")
    local close = Parts.TitleBar(window, "Action Bars", "", PAGE)
    local _, opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.opacity = opacity
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")
    Parts.SetLink(window.backLink, "Saved Sets")
    window.backLink:SetScript("OnClick", function() Show("sets") end)
    -- The builder's switches read the draft when they are made.
    if not draft then NewDraft() end
    window:SetScript("OnEvent", OnEvent)
    window:HookScript("OnHide", function()
        for _, v in pairs(views) do
            for _, event in ipairs(v.events or {}) do window:UnregisterEvent(event) end
        end
    end)
    views = { sets = BuildSets(), build = BuildBuilder(), import = BuildPreview() }
end

S.OnChange(function(key)
    if not (window and window:IsShown()) then return end
    if key == "windowAlpha" then Paint() else RedrawSoon() end
end)

hooksecurefunc(ns.UI, "RefreshPage", function()
    if view == "sets" then RedrawSoon() end
end)
hooksecurefunc(ns, "Apply", RedrawSoon)

local function Open(name)
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Show(name)
end

function ns.OpenActionBarsWindow()
    Open("sets")
end

function ns.ToggleActionBarsWindow()
    if window and window:IsShown() then window:Hide() else Open("sets") end
end

-- key: a saved set to edit and save again, with its choices; none for a new one.
function ns.OpenActionBarsBuilder(key)
    NewDraft(key)
    Open("build")
end

function ns.OpenActionBarsImport(key)
    if not Sets.Get(key) then return end
    importKey = key
    Open("import")
end
