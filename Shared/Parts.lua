-------------------------------------------------------------------------------
--  Parts.lua -- the components a page is made of (ns.Shared.Parts): the chevron, text links,
--  icon buttons, icons inline in text, rank stars, an item's icon, the backdrop with its
--  cards, the panel a view sits in and the side panel that opens beside a window, numbers
--  lined up to the pixel, and sharing a line in chat. A window's own pieces (title bar,
--  opacity, switch, search, footer) are Window.lua's.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Parts = Shared.Parts

local St = Shared.Style
local ARROW, PLACE_DOT, ACTION, STAR = St.ARROW, St.PLACE_DOT, St.ACTION, St.STAR
local PANEL_W, PANEL_PAD, BORDER_RGB = St.PANEL_W, St.PANEL_PAD, St.BORDER_RGB
local PANEL_HEADER, PANEL_BUTTONS = St.PANEL_HEADER, St.PANEL_BUTTONS
local CARD_FILL, CARD_EDGE = St.WINDOW_CARD_FILL, St.WINDOW_CARD_EDGE
-- Forever's mark on an icon's corner: this share of the icon tall, never under FOREVER_MIN.
local FOREVER_MIN, FOREVER_SHARE = 7, 0.32

-------------------------------------------------------------------------------
--  Icons in text
-------------------------------------------------------------------------------
-- How much lower an icon in text sits, level with the letters: a tooltip's lines need 1; on a
-- card the Naowh font's capitals fill the middle of the line (measured in game, 2 Oct 2026).
Parts.TOOLTIP_DROP = 1
Parts.CARD_DROP = 0

---@param color { r: number, g: number, b: number }
function Parts.Inline(texture, color, drop)
    return ("|T%s:0:0:0:%d:64:64:0:64:0:64:%d:%d:%d|t"):format(texture, -(drop or Parts.TOOLTIP_DROP),
        color.r * 255, color.g * 255, color.b * 255)
end
local Inline = Parts.Inline

-------------------------------------------------------------------------------
--  Ranks on your BiS list: your BiS (#1) an orange star, your second pick a silver one, the
--  rest a muted number. Made once per rank and drop.
-------------------------------------------------------------------------------
local RANK_RGB = { St.BIS_RGB, St.SECOND_RGB }
local marks = {}

function Parts.RankColor(rank)
    return RANK_RGB[rank] or T.muted
end

---@param rank? number
---@param drop? number Parts.CARD_DROP on a card, else as in a tooltip
function Parts.RankMark(rank, drop)
    if not rank then return "" end
    drop = drop or Parts.TOOLTIP_DROP
    local byRank = marks[drop]
    if not byRank then
        byRank = {}
        marks[drop] = byRank
    end
    local mark = byRank[rank]
    if not mark then
        mark = RANK_RGB[rank] and Inline(STAR, RANK_RGB[rank], drop) or ns.Color("muted", "#" .. rank)
        byRank[rank] = mark
    end
    return mark
end

-------------------------------------------------------------------------------
--  The addon's lines in an item's tooltip, one fact each, one look: the mark, the words in
--  its colour, and after a dot, muted, whose it is. The BiS List's and Stat Weights' on every
--  tooltip, the Journal's and the BiS List's rows add theirs from the same makers, so the
--  same fact never reads two ways, or twice.
-------------------------------------------------------------------------------
-- "<star> Your BiS", "Your second pick", "#3 on your BiS list"; with a list's name, " . Die".
---@param listName? string
function Parts.RankLine(rank, listName)
    local words = rank == 1 and "Your BiS" or rank == 2 and "Your second pick" or ("#%d on your BiS list"):format(rank)
    local color = Parts.RankColor(rank)
    return Parts.RankMark(rank) .. " " .. ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255,
        color.b * 255, words) .. (listName and ns.Color("muted", PLACE_DOT .. listName) or "")
end

local upgradeArrow

-- "<green arrow> +18% upgrade . Combat": how much stronger it makes you, by your spec's weights.
---@param gain number percent
---@param specName? string
function Parts.UpgradeLine(gain, specName)
    upgradeArrow = upgradeArrow or ("|A:%s:0:0:0:%d|a"):format(St.UPGRADE_ATLAS, -Parts.TOOLTIP_DROP)
    return upgradeArrow .. " " .. St.UPGRADE_CODE .. "+" .. math.floor(gain + 0.5) .. "% upgrade|r"
        .. (specName and ns.Color("muted", PLACE_DOT .. specName) or "")
end

-------------------------------------------------------------------------------
--  WoW Forever's mark, on what is new in Forever (not in the original game): its infinity
--  sign, before a name or in text, and a tooltip line that says what it means.
-------------------------------------------------------------------------------
-- The sign fills its texture, 32 by 16, twice as wide as it is tall.
local FOREVER = St.FOREVER
local FOREVER_RGB = St.FOREVER_RGB
local foreverText = {}

---@param kind "items"|"quests"|"npcs"
---@return boolean new whether Wowhead's Forever database has it as new in Forever
function Parts.IsForever(kind, id)
    local new = Shared.ForeverNew
    return id ~= nil and new ~= nil and new[kind][id] == true
end

-- The mark at a height in text, after a space; made once per height and drop.
---@param height number the line's font size
---@param drop? number Parts.CARD_DROP on a card, else as in a tooltip
function Parts.ForeverInline(height, drop)
    drop = drop or Parts.TOOLTIP_DROP
    local key = height * 100 + drop
    local text = foreverText[key]
    if not text then
        text = (" |T%s:%d:%d:0:%d:32:16:0:32:0:16:%d:%d:%d|t"):format(FOREVER, height, height * 2, -drop,
            FOREVER_RGB.r * 255, FOREVER_RGB.g * 255, FOREVER_RGB.b * 255)
        foreverText[key] = text
    end
    return text
end

-- A texture drawn smaller than its file stays smooth: mipmapped ("TRILINEAR") where it is one
-- of the addon's own (pass the path), and never snapped to whole screen pixels, which makes a
-- scaled icon's edges step. A text icon (|T|t) cannot be smoothed: draw those near their size.
---@param path? string|number
function Parts.Smooth(texture, path)
    if path then texture:SetTexture(path, nil, nil, "TRILINEAR") end
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end
local Smooth = Parts.Smooth

-- The mark as a texture, height tall, for a row's own column.
function Parts.ForeverMark(parent, height)
    local mark = Smooth(parent:CreateTexture(nil, "OVERLAY"), FOREVER)
    mark:SetVertexColor(FOREVER_RGB.r, FOREVER_RGB.g, FOREVER_RGB.b)
    mark:SetSize(height * 2, height)
    return mark
end

local foreverLine

-- "<sign> New in WoW Forever", for a tooltip.
function Parts.ForeverLine()
    if not foreverLine then
        foreverLine = Parts.ForeverInline(12):sub(2) .. " " .. St.FOREVER_CODE .. "New in WoW Forever|r"
    end
    return foreverLine
end

-- "3/10", made once each, so a count redrawn makes no garbage.
local fractions = {}

function Parts.Fraction(part, whole)
    local byWhole = fractions[whole]
    if not byWhole then
        byWhole = {}
        fractions[whole] = byWhole
    end
    local text = byWhole[part]
    if not text then
        text = part .. "/" .. whole
        byWhole[part] = text
    end
    return text
end

-------------------------------------------------------------------------------
--  Pieces
-------------------------------------------------------------------------------
-- The addon's chevron, pointing right.
function Parts.Arrow(parent, size, color)
    local arrow = parent:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    arrow:SetSize(size, size)
    arrow:SetVertexColor(color.r, color.g, color.b)
    return arrow
end
local Arrow = Parts.Arrow

-- icon.texture is what to set.
function Parts.ItemIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame.edge = ns.Border(frame, BORDER_RGB)
    frame.texture = Smooth(frame:CreateTexture(nil, "ARTWORK"))
    frame.texture:SetPoint("TOPLEFT", 1, -1)
    frame.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- WoW Forever's mark in the opposite corner, just inside the icon's edge: no box, its own
    -- dark outline keeps it readable on the icon's art.
    local h = math.max(FOREVER_MIN, math.floor(size * FOREVER_SHARE))
    local forever = CreateFrame("Frame", nil, frame)
    forever:SetSize(h * 2, h)
    forever:SetPoint("TOPLEFT", 1, -1)
    forever:SetFrameLevel(frame:GetFrameLevel() + 3)
    local sign = Smooth(forever:CreateTexture(nil, "OVERLAY"), St.FOREVER_ICON)
    sign:SetVertexColor(FOREVER_RGB.r, FOREVER_RGB.g, FOREVER_RGB.b)
    sign:SetAllPoints()
    frame.forever = forever
    forever:Hide()
    return frame
end

-- Forever's badge on an item icon, for an item new in Forever.
function Parts.MarkForever(icon, itemID)
    icon.forever:SetShown(Parts.IsForever("items", itemID))
end

-- The tooltip's owner set, for a hover card; nothing while a menu is open, so moving the mouse
-- from a menu's owner over other rows to reach it does not cover the menu with their cards.
---@return boolean shown false while a menu is open: the caller shows nothing
function Parts.Tip(owner, anchor, x, y)
    if Menu.GetManager():IsAnyMenuOpen() then return false end
    GameTooltip:SetOwner(owner, anchor, x, y)
    return true
end
local Tip = Parts.Tip

-- What you wear, in a list's row: a green bar at its left edge, out by inset.
function Parts.WornBar(row, inset)
    local bar = ns.Solid(row, "ARTWORK", St.HAVE_RGB, 1)
    bar:SetPoint("TOPLEFT", -inset + 2, -4)
    bar:SetPoint("BOTTOMLEFT", -inset + 2, 4)
    bar:SetWidth(2)
    bar:Hide()
    return bar
end

-- An action on a page is a link, not a box, so the page reads as content; boxes are for a
-- window's controls. With arrow, a chevron after it, for one that goes somewhere else.
local function LinkColor(link, color)
    link.text:SetTextColor(color.r, color.g, color.b)
    if link.arrow then link.arrow:SetVertexColor(color.r, color.g, color.b) end
end
Parts.LinkColor = LinkColor

-- A disabled link rests muted and says why on hover.
local function LinkEnter(link)
    if link.tip then
        if not Tip(link, "ANCHOR_TOP") then return end
        GameTooltip:SetText(link.tip, 1, 1, 1)
        if link.tipLine then GameTooltip:AddLine(link.tipLine, T.muted.r, T.muted.g, T.muted.b, true) end
        GameTooltip:Show()
    end
    if link.disabled then return end
    LinkColor(link, T.fg)
    link.underline:Show()
end

local function LinkLeave(link)
    if link.tip then GameTooltip:Hide() end
    LinkColor(link, link.disabled and T.muted or T.accentSoft)
    link.underline:Hide()
end

function Parts.Link(parent, onClick, arrow)
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

function Parts.SetLink(link, text)
    link.text:SetText(text)
    link:SetWidth(math.ceil(link.text:GetStringWidth()) + (link.arrow and 12 or 0))
end

-- margin: the empty edge on the right of the icon's image; it moves out by it, so the shapes,
-- not their boxes, line up.
local function IconEnter(button)
    button.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
    if button.label then button.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b) end
    if not Tip(button, "ANCHOR_TOP") then return end
    GameTooltip:SetText(button.tip)
    if button.hint then GameTooltip:AddLine(button.hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Show()
end

local function IconLeave(button)
    button.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    if button.label then button.label:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Hide()
end

---@param tip? string what it does, on hover (or button.tip, set later)
function Parts.IconButton(parent, onClick, texture, margin, tip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ACTION, ACTION)
    button.icon = Smooth(button:CreateTexture(nil, "ARTWORK"), texture)
    button.icon:SetSize(ACTION, ACTION)
    button.icon:SetPoint("RIGHT", margin or 0, 0)
    button.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    button.tip = tip
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", IconEnter)
    button:SetScript("OnLeave", IconLeave)
    return button
end

-- The copy card the tooltips' Ctrl-Shift-C opens, its Wowhead link selected: the game cannot
-- put text on the clipboard for an addon. kind is Wowhead's: "item", "spell", "quest", "npc"
-- or "object".
local ID_LABELS = { item = "Item ID", spell = "Spell ID", quest = "Quest ID", npc = "NPC ID", object = "Object ID" }

function Parts.CopyWowhead(kind, id, name)
    ns.ShowCopyCard(kind, ID_LABELS[kind] or "ID", id, name, "url")
end

-- A where line without its colour codes (they pull the eye off the titles), dashes between
-- place and person ("Ratchet- Crane Operator") as dots. Made once each.
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
--  The backdrop of a window and its panels: a gradient from the theme's panel colour down
--  toward its backdrop, with lighter cards in black edges. Opacity is painted into the
--  colours, not set with SetAlpha: a texture's alpha does not reach a gradient's colours.
-------------------------------------------------------------------------------
local Backdrop = {}
Backdrop.__index = Backdrop

local EDGES = {
    { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
    { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true },
}

function Backdrop:Keep(texture, color, alpha)
    texture.color, texture.alpha = color, alpha
    self.flat[#self.flat + 1] = texture
    return texture
end

-- Insets from each side. Returns its textures, the fill first: the edges follow it, so moving
-- the fill moves the card.
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

---@param alpha number 0 to 1
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

-------------------------------------------------------------------------------
--  Sharing a line in chat, or in a box to copy. Never through the chat box: opening it from
--  addon code taints it, and the game then blocks the next message you send.
-------------------------------------------------------------------------------
-- A dungeon finder group's chat is the instance's.
local function PartyChat()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return "PARTY"
end

-- The Trade channel's number while you are in it (in a city), else nil.
local function TradeChannel()
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local name = list[i + 1]
        if type(name) == "string" and name:find("^Trade") then return list[i] end
    end
end

-- message, or a function making it when sent (a map pin link is made then). With trade,
-- Trade chat first: for asking the city. Copy puts copyText on a copy card, with icon.
---@param owner Frame
---@param title string the menu's title
---@param message string|fun(): string
---@param copyTitle string
---@param copyText string
---@param trade? boolean
---@param icon? number|string
function Parts.ShareMenu(owner, title, message, copyTitle, copyText, trade, icon)
    local locked = C_ChatInfo.InChatMessagingLockdown()
    local target = UnitIsPlayer("target") and not UnitIsUnit("target", "player") and UnitIsFriend("player", "target")
        and GetUnitName("target", true) or nil
    local function Send(channel, to)
        local text = type(message) == "function" and message() or message
        C_ChatInfo.SendChatMessage(text, channel, nil, to)
    end
    local tradeChannel = trade and TradeChannel()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        if trade then
            root:CreateButton("Trade", function() Send("CHANNEL", tradeChannel) end)
                :SetEnabled(not locked and tradeChannel ~= nil)
        end
        root:CreateButton("Party", function() Send(PartyChat()) end):SetEnabled(not locked and IsInGroup())
        root:CreateButton("Raid", function() Send("RAID") end):SetEnabled(not locked and IsInRaid())
        root:CreateButton("Guild", function() Send("GUILD") end):SetEnabled(not locked and IsInGuild())
        root:CreateButton(target and "Whisper " .. target or "Whisper your target", function()
            Send("WHISPER", target)
        end):SetEnabled(not locked and target ~= nil)
        root:CreateDivider()
        root:CreateButton("Copy", function() ns.ShowCopyLine(copyTitle, copyText, icon) end)
        if locked then root:CreateTitle(ns.Color("muted", "Chat is locked right now.")) end
        if trade and not tradeChannel then root:CreateTitle(ns.Color("muted", "Trade is open in a city.")) end
    end)
end

-- A spot on the map, with a map pin link the reader can click; the line alone to copy.
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
--  Numbers lined up to the pixel: the Naowh font's digits are not all as wide, so each
--  character gets a cell as wide as the widest digit ("-" and "/" narrower), measured once
--  per size. The caller anchors the rightmost cell, cells[1].
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

-- From the right, the rest hidden. Returns the leftmost shown.
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

-------------------------------------------------------------------------------
--  Panels
-------------------------------------------------------------------------------
-- Its title in the accent and a close button; the caller puts a view in it. With windowLook,
-- a window's backdrop (panel.backdrop, painted by the caller).
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
--  The side panel: details beside the window they were opened from, on whichever side has
--  room, with buttons along the bottom. It closes with that window, and opening one closes
--  the others.
-------------------------------------------------------------------------------
local SCROLL_GAP = 20    -- the view's right edge to the panel's, for the scrollbar
local SIDE_MIN_H = 320
local BUTTON_GAP = 4
local sidePanels = {}

-- panel.view is newView(scroll)'s; panel.buttons[label] each action's. opacity() is its
-- window's, 0 to 1.
---@param actions { [1]: string, [2]: fun() }[]
---@param newView fun(scroll: Frame): Frame
---@param opacity fun(): number
function Parts.SidePanel(actions, newView, opacity)
    local bottom = #actions > 0 and PANEL_BUTTONS or 0
    local panel = Parts.Panel("", true)
    panel:SetFrameStrata("HIGH")
    panel.opacity = opacity
    panel.backdrop:Card(4, PANEL_HEADER, 4, bottom + 4)
    panel.backdrop:Paint(opacity())
    local scroll = ns.UI.SlimScroll(panel)
    scroll:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEADER - 4)
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - SCROLL_GAP, bottom + PANEL_PAD)
    local view = newView(scroll)
    view:SetWidth(PANEL_W - PANEL_PAD * 2 - SCROLL_GAP)
    scroll:SetScrollChild(view)
    panel.scroll, panel.view, panel.owners, panel.buttons = scroll, view, {}, {}
    -- The game's Lua stops on a division by zero.
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

-- When a window's opacity changes.
function Parts.RepaintSidePanels()
    for _, panel in ipairs(sidePanels) do panel.backdrop:Paint(panel.opacity()) end
end

local function Owner(frame)
    while frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
    return frame
end

-- Beside the window holding from, scrolled to the top.
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
