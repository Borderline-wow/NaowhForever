-------------------------------------------------------------------------------
--  View/Parts.lua -- the Dungeon Journal's shared pieces (ns.Journal.View.Parts): the
--  chevron, text links, icon buttons, the plain grey of a where line, the panel the map and
--  the popup sit in, and the side panel that opens beside the window; and two row kinds used
--  across the page, a section title and a note.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal

local St = J.Style
local ARROW, PLACE_DOT, ACTION = St.ARROW, St.PLACE_DOT, St.ACTION
local SECTION_H, INDENT, NOTE_PAD = St.SECTION_H, St.INDENT, St.NOTE_PAD
local PANEL_W, PANEL_PAD, BORDER_RGB = St.PANEL_W, St.PANEL_PAD, St.BORDER_RGB
local PANEL_HEADER, PANEL_BUTTONS = St.PANEL_HEADER, St.PANEL_BUTTONS
local CARD_FILL, CARD_EDGE = St.WINDOW_CARD_FILL, St.WINDOW_CARD_EDGE

local View = J.View
local Kinds, Parts = View.Kinds, View.Parts

-------------------------------------------------------------------------------
--  Pieces
-------------------------------------------------------------------------------
-- The addon's chevron, pointing right; white, so it takes the colour it is given.
function Parts.Arrow(parent, size, color)
    local arrow = parent:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    arrow:SetSize(size, size)
    arrow:SetVertexColor(color.r, color.g, color.b)
    return arrow
end
local Arrow = Parts.Arrow

-- An action as a text link rather than a box: the accent colour, white and underlined under
-- the mouse. Boxes are kept for the window's controls, so the page reads as content. With
-- arrow, the chevron after the text, for a link that goes somewhere else.
local function LinkColor(link, color)
    link.text:SetTextColor(color.r, color.g, color.b)
    if link.arrow then link.arrow:SetVertexColor(color.r, color.g, color.b) end
end

local function LinkEnter(link)
    LinkColor(link, T.fg)
    link.underline:Show()
end

local function LinkLeave(link)
    LinkColor(link, T.accentSoft)
    link.underline:Hide()
end

local function Link(parent, onClick, arrow)
    local link = CreateFrame("Button", nil, parent)
    link:SetHeight(18)
    link.text = ns.Font(link, 12, nil, T.accentSoft)
    if arrow then
        link.arrow = Arrow(link, 10, T.accentSoft)
        -- Out by the chevron's own margin, so its point lines up with the text above.
        link.arrow:SetPoint("RIGHT", 2, 0)
        link.text:SetPoint("RIGHT", link.arrow, "LEFT", 0, 0)
    else
        link.text:SetPoint("RIGHT")
    end
    link.underline = ns.Solid(link, "ARTWORK", T.fg, 1)
    link.underline:SetPoint("TOPLEFT", link.text, "BOTTOMLEFT", 0, -1)
    link.underline:SetPoint("TOPRIGHT", link.text, "BOTTOMRIGHT", 0, -1)
    link.underline:SetHeight(1)
    link.underline:Hide()
    link:SetScript("OnClick", onClick)
    link:SetScript("OnEnter", LinkEnter)
    link:SetScript("OnLeave", LinkLeave)
    return link
end

local function SetLink(link, text)
    link.text:SetText(text)
    link:SetWidth(math.ceil(link.text:GetStringWidth()) + (link.arrow and 12 or 0))
end
Parts.Link, Parts.SetLink = Link, SetLink

-- An action as an icon: the accent colour, white under the mouse, its tip in a tooltip.
-- margin: the empty edge of the icon's own image on its right, in pixels at this size; the
-- icon moves out by it, so the shapes, not their boxes, line up on the right.
local function IconEnter(button)
    button.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    if button.label then button.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b) end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.tip)
    -- What else it does, as a hint under its name.
    if button.hint then GameTooltip:AddLine(button.hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Show()
end

local function IconLeave(button)
    button.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    if button.label then button.label:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Hide()
end

function Parts.IconButton(parent, onClick, texture, margin)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ACTION, ACTION)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(ACTION, ACTION)
    button.icon:SetPoint("RIGHT", margin or 0, 0)
    button.icon:SetTexture(texture)
    button.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", IconEnter)
    button:SetScript("OnLeave", IconLeave)
    return button
end

-- A where line in plain muted grey: its colour codes out (coloured parts would pull the eye
-- off the titles), and the data's dashes between place and person ("Ratchet- Crane
-- Operator") as dots. The data's lines are few and fixed, so each is made once.
local plain = {}

function Parts.Plain(text)
    local out = plain[text]
    if not out then
        out = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%-%s+", PLACE_DOT)
        plain[text] = out
    end
    return out
end

-------------------------------------------------------------------------------
--  The Journal window's backdrop, for any window that stands beside it: charcoal rather
--  than black, a gradient from the panel colour at the top to halfway between it and the
--  backdrop at the bottom, with lighter cards on it, each in a black edge. Theme colours,
--  so the presets follow. Textures on the frame itself, under its text.
--
--  Its opacity is painted into the colours (Paint), not set with SetAlpha: a texture's
--  alpha does not reach a gradient's colours, and the window stayed solid at any setting.
-------------------------------------------------------------------------------
local Backdrop = {}
Backdrop.__index = Backdrop

local EDGES = {
    { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
    { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true },
}

-- A flat texture of the backdrop: its colour and its alpha at full opacity.
function Backdrop:Keep(texture, color, alpha)
    texture.color, texture.alpha = color, alpha
    self.flat[#self.flat + 1] = texture
    return texture
end

-- A card from (left, top) to (right, bottom), each an inset from that side of the frame.
-- Returns its textures, its fill first: the edges follow the fill, so moving the fill moves
-- the card.
function Backdrop:Card(left, top, right, bottom)
    local frame = self.frame
    local fill = self:Keep(frame:CreateTexture(nil, "BACKGROUND", nil, -6), T.fg, CARD_FILL)
    fill:SetPoint("TOPLEFT", left, -top)
    fill:SetPoint("BOTTOMRIGHT", -right, bottom)
    local parts = { fill }
    for _, edge in ipairs(EDGES) do
        local line = self:Keep(frame:CreateTexture(nil, "BORDER"), BORDER_RGB, CARD_EDGE)
        line:SetPoint(edge[1], fill)
        line:SetPoint(edge[2], fill)
        if edge[3] then line:SetWidth(1) else line:SetHeight(1) end
        parts[#parts + 1] = line
    end
    return parts
end

-- Paints it at an opacity from 0 to 1.
function Backdrop:Paint(alpha)
    local top, bg = T.panel, T.bg
    self.bottom:SetRGBA((top.r + bg.r) / 2, (top.g + bg.g) / 2, (top.b + bg.b) / 2, alpha)
    self.top:SetRGBA(top.r, top.g, top.b, alpha)
    self.gradient:SetGradient("VERTICAL", self.bottom, self.top)
    local flat = self.flat
    for i = 1, #flat do
        local texture = flat[i]
        local c = texture.color
        texture:SetColorTexture(c.r, c.g, c.b, texture.alpha * alpha)
    end
end

function Parts.Backdrop(frame)
    local backdrop = setmetatable({ frame = frame, flat = {} }, Backdrop)
    backdrop.gradient = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop.gradient:SetAllPoints()
    backdrop.gradient:SetColorTexture(1, 1, 1, 1)
    backdrop.bottom, backdrop.top = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1)
    return backdrop
end

-- How long a fight took: "1:32".
---@param seconds number
function Parts.FightLength(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-------------------------------------------------------------------------------
--  Sharing a line in chat: to your party, raid or guild, the player you target, or in a box
--  to copy and paste anywhere. Never into the chat box: opening it from addon code taints
--  it, and the game then blocks the next message you send. Sending is off while the game
--  locks chat (in an encounter).
-------------------------------------------------------------------------------
-- In a group the game made for you (a dungeon finder), the party's chat is the instance's,
-- as the addon's other group messages have it.
local function PartyChat()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return "PARTY"
end

-- Opens the menu on owner. message is what is sent, or a function that makes it when it is
-- sent (a map pin link is made then); copyText is what the Copy box holds, under copyTitle.
---@param owner Frame
---@param title string the menu's title
---@param message string|fun(): string
---@param copyTitle string
---@param copyText string
function Parts.ShareMenu(owner, title, message, copyTitle, copyText)
    local locked = C_ChatInfo.InChatMessagingLockdown()
    local target = UnitIsPlayer("target") and not UnitIsUnit("target", "player") and UnitIsFriend("player", "target")
        and GetUnitName("target", true) or nil
    local function Send(channel, to)
        local text = type(message) == "function" and message() or message
        C_ChatInfo.SendChatMessage(text, channel, nil, to)
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        root:CreateButton("Party", function() Send(PartyChat()) end):SetEnabled(not locked and IsInGroup())
        root:CreateButton("Raid", function() Send("RAID") end):SetEnabled(not locked and IsInRaid())
        root:CreateButton("Guild", function() Send("GUILD") end):SetEnabled(not locked and IsInGuild())
        root:CreateButton(target and "Whisper " .. target or "Whisper your target", function()
            Send("WHISPER", target)
        end):SetEnabled(not locked and target ~= nil)
        root:CreateDivider()
        root:CreateButton("Copy", function() ns.ShowCopyBox(copyTitle, copyText) end)
        if locked then root:CreateTitle(ns.Color("muted", "Chat is locked right now.")) end
    end)
end

-- Shares a spot on the map: its line (ns.WaypointText) with a map pin link the reader can
-- click for the same pin, made when it is sent; the line alone to copy.
---@param owner Frame
---@param title string the menu's title
---@param name string what the spot is for
---@param map number uiMapID
---@param x number percent
---@param y number percent
---@param note? string
function Parts.SharePlace(owner, title, name, map, x, y, note)
    local text = ns.WaypointText(name, map, x, y, note)
    Parts.ShareMenu(owner, title, function()
        local link = ns.WaypointLink(map, x, y)
        return link and text .. " " .. link or text
    end, name, text)
end

-------------------------------------------------------------------------------
--  Numbers lined up to the pixel: the Naowh font's digits are not all as wide ("1" is
--  narrow), so "1/1" right-aligned stands off from "7/7", and "41-51" from "40-45". Each
--  character gets a cell of its own instead: every digit as wide as the widest, centred in
--  it, and "-" or "/" in a narrower one. The widths are measured once per size, in the font
--  itself, so they hold at any size. The caller anchors the rightmost cell, cells[1].
-------------------------------------------------------------------------------
local cellWidths = {}   -- text size -> { digit = w, ["-"] = w, ["/"] = w }

local function CellWidths(parent, size)
    local widths = cellWidths[size]
    if widths then return widths end
    local probe = ns.Font(parent, size)
    local digit = 0
    for d = 0, 9 do
        probe:SetText(d)
        digit = math.max(digit, math.ceil(probe:GetStringWidth()))
    end
    widths = { digit = digit }
    for _, mark in ipairs({ "-", "/" }) do
        probe:SetText(mark)
        widths[mark] = math.ceil(probe:GetStringWidth()) + 2
    end
    probe:Hide()
    cellWidths[size] = widths
    return widths
end

local Cells = {}
Cells.__index = Cells

-- Fills the cells from the right; the ones left over hide. Returns the leftmost shown, for
-- what follows on its left.
function Cells:SetText(text)
    text = tostring(text)
    local n, widths = #text, self.widths
    for i = 1, #self do
        local cell = self[i]
        if i <= n then
            local char = text:sub(n - i + 1, n - i + 1)
            cell:SetWidth(widths[char] or widths.digit)
            cell:SetText(char)
            cell:Show()
        else
            cell:Hide()
        end
    end
    return self[math.max(1, math.min(n, #self))]
end

function Cells:SetTextColor(r, g, b)
    for i = 1, #self do self[i]:SetTextColor(r, g, b) end
end

-- count cells of text at size, in color, made once; each one a font string on parent.
function Parts.Cells(parent, size, color, count)
    local cells = setmetatable({ widths = CellWidths(parent, size) }, Cells)
    for i = 1, count do
        local cell = ns.Font(parent, size, nil, color)
        cell:SetJustifyH("CENTER")
        if i > 1 then cell:SetPoint("RIGHT", cells[i - 1], "LEFT", 0, 0) end
        cells[i] = cell
    end
    return cells
end

-- The panel beside the world map and at the cursor: the addon's frame, a dark backdrop in a
-- black border, its title in the accent and a close button. The caller puts a view in it.
-- With windowLook, the Journal window's backdrop instead (panel.backdrop, painted by the
-- caller), for a panel that opens beside the window.
function Parts.Panel(title, windowLook)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(PANEL_W)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    if windowLook then
        panel.backdrop = Parts.Backdrop(panel)
    else
        ns.Solid(panel, "BACKGROUND", T.bg, 0.96):SetAllPoints()
    end
    ns.Border(panel, BORDER_RGB)
    panel.title = ns.Font(panel, 12, nil, T.accent)
    panel.title:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
    panel.title:SetPoint("RIGHT", -34, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    panel.title:SetText(title)
    panel.close = ns.Button(panel, "x", 20, 20, function() panel:Hide() end)
    panel.close:SetPoint("TOPRIGHT", -6, -6)
    return panel
end

-------------------------------------------------------------------------------
--  The side panel: details opened from the window (a quest in your log, a boss's kills and
--  loot), beside the frame they were opened from, on whichever side has room. The window's
--  look and opacity, a card behind a view that scrolls, and buttons along the bottom. It
--  closes with that frame, and one side panel opening closes the other.
-------------------------------------------------------------------------------
local SCROLL_GAP = 20    -- the view's right edge to the panel's, for the scrollbar
local SIDE_MIN_H = 320
local BUTTON_GAP = 4
local sidePanels = {}

-- The panel, with panel.view to draw in and a button for each of actions ({ label, onClick }),
-- kept as panel.buttons[label]; with none, the view runs to the bottom. Built once by its
-- caller.
function Parts.SidePanel(actions)
    local bottom = #actions > 0 and PANEL_BUTTONS or 0
    local panel = Parts.Panel("", true)
    panel:SetFrameStrata("HIGH")
    panel.backdrop:Card(4, PANEL_HEADER, 4, bottom + 4)
    panel.backdrop:Paint(J.Settings.Get("windowAlpha") or 1)
    local scroll = ns.UI.SlimScroll(panel)
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - 4)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, bottom + PANEL_PAD)
    local view = View.New(scroll)
    view:SetWidth(PANEL_W - PANEL_PAD * 2 - SCROLL_GAP)
    scroll:SetScrollChild(view)
    panel.scroll, panel.view, panel.owners, panel.buttons = scroll, view, {}, {}
    -- At least one, as the game's Lua stops on a division by zero (standard Lua gives inf).
    local count = math.max(1, #actions)
    local width = (PANEL_W - PANEL_PAD * 2 - BUTTON_GAP * (count - 1)) / count
    local previous
    for _, action in ipairs(actions) do
        local button = ns.Button(panel, action[1], width, 24, action[2])
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", BUTTON_GAP, 0)
        else
            button:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD)
        end
        panel.buttons[action[1]] = button
        previous = button
    end
    sidePanels[#sidePanels + 1] = panel
    return panel
end

-- The top of the frame a side panel is opened from: the Journal window, or the map panel.
local function Owner(frame)
    while frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
    return frame
end

-- Shows the side panel beside the frame holding from, at its top, scrolled to the top.
function Parts.ShowBeside(panel, from)
    for _, other in ipairs(sidePanels) do
        if other ~= panel then other:Hide() end
    end
    local owner = Owner(from)
    if not panel.owners[owner] then
        panel.owners[owner] = true
        owner:HookScript("OnHide", function() panel:Hide() end)
    end
    panel:SetScale(owner:GetScale())
    panel:SetHeight(math.max(SIDE_MIN_H, owner:GetHeight()))
    panel:ClearAllPoints()
    local right = (owner:GetRight() or 0) * owner:GetEffectiveScale()
    local room = UIParent:GetRight() * UIParent:GetEffectiveScale() - right
    if room >= (PANEL_W + 8) * owner:GetEffectiveScale() then
        panel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
    end
    panel.scroll:SetVerticalScroll(0)
    panel:Show()
end

-- The side panels follow the window's opacity.
J.Settings.OnChange(function(key, value)
    if key ~= "windowAlpha" then return end
    for _, panel in ipairs(sidePanels) do panel.backdrop:Paint(value or 1) end
end)

-------------------------------------------------------------------------------
--  Row kinds
-------------------------------------------------------------------------------
local function SectionClicked(row)
    if row.onToggle then row.onToggle() end
end

local function SectionLinkClicked(link)
    local row = link:GetParent()
    row.onLink(row.linkArg)
end

-- A section title over a line: its title, a muted count after it, and either a chevron
-- (it opens and closes on a click anywhere) or a link on its right.
Kinds.section = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.text = ns.Font(row, 12, nil, T.accentSoft)
        -- Right while closed, turned down while open.
        row.arrow = Arrow(row, 12, T.accentSoft)
        row.arrow:SetPoint("BOTTOMLEFT", -2, 5)
        row.line = ns.Solid(row, "ARTWORK", T.line, 1)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
        row.line:SetHeight(1)
        row.link = Link(row, SectionLinkClicked, true)
        row.link:SetPoint("BOTTOMRIGHT", 0, 4)
        row:SetScript("OnMouseUp", SectionClicked)
        return row
    end,
    ---@param title string
    ---@param count? number
    ---@param open? boolean with onToggle: whether it is open
    ---@param onToggle? fun() opens or closes it
    ---@param linkText? string
    ---@param onLink? fun(arg: any)
    ---@param linkArg? any
    Set = function(row, title, count, open, onToggle, linkText, onLink, linkArg)
        row.onToggle, row.onLink, row.linkArg = onToggle, onLink, linkArg
        row:EnableMouse(onToggle ~= nil)
        row.arrow:SetShown(onToggle ~= nil)
        row.arrow:SetRotation(open and -math.pi / 2 or 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("BOTTOMLEFT", onToggle and 14 or 0, 5)
        row.text:SetText(title:upper() .. (count and "   " .. ns.Color("muted", count) or ""))
        row.link:SetShown(linkText ~= nil)
        if linkText then SetLink(row.link, linkText) end
        return SECTION_H
    end,
}

Kinds.note = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.text = ns.Font(row, 11, nil, T.muted)
        row.text:SetPoint("TOPLEFT", INDENT, -2)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        return row
    end,
    Set = function(row, text)
        row.text:SetWidth(row:GetWidth() - INDENT)
        row.text:SetText(text)
        return math.ceil(row.text:GetStringHeight()) + NOTE_PAD
    end,
}
