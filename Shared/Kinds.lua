-------------------------------------------------------------------------------
--  Kinds.lua -- the rows every page has (ns.Shared.Kinds): a section title, a note and a
--  card. See View.lua for what a kind is.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Kinds, Parts = Shared.Kinds, Shared.Parts

local St = Shared.Style
local SECTION_H, INDENT, NOTE_PAD = St.SECTION_H, St.INDENT, St.NOTE_PAD
local CARD_FILL, CARD_HEADER_H, BORDER_RGB = St.CARD_FILL, St.CARD_HEADER_H, St.BORDER_RGB

-- "TITLE   3": made once per title and count.
local labels = {}

local function Label(title, count)
    local byCount = labels[title]
    if not byCount then
        byCount = { [false] = title:upper() }
        labels[title] = byCount
    end
    local key = count or false
    local label = byCount[key]
    if not label then
        label = byCount[false] .. "   " .. ns.Color("muted", count)
        byCount[key] = label
    end
    return label
end

local function SectionClicked(row)
    if row.onToggle then row.onToggle() end
end

-- The link comes too, for a window to open beside what it was clicked in.
local function SectionLinkClicked(link)
    local row = link:GetParent()
    if row.onLink then row.onLink(row.linkArg, link) end
end

-- A title over a line: a muted count after it, and either a chevron (it opens and closes on a
-- click anywhere) or a link on its right.
Kinds.section = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.text = ns.Font(row, 12, nil, T.accentSoft)
        row.arrow = Parts.Arrow(row, 12, T.accentSoft)
        row.arrow:SetPoint("BOTTOMLEFT", -2, 5)
        row.line = ns.Solid(row, "ARTWORK", T.line, 1)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
        ns.Hairline(row.line, "h")
        row.link = Parts.Link(row, SectionLinkClicked, true)
        row.link:SetPoint("BOTTOMRIGHT", 0, 4)
        row:SetScript("OnMouseUp", SectionClicked)
        return row
    end,
    ---@param title string
    ---@param count? number
    ---@param open? boolean with onToggle: whether it is open
    ---@param onToggle? fun() opens or closes it
    ---@param linkText? string
    ---@param onLink? fun(arg: any, link: Frame)
    ---@param linkArg? any
    ---@param linkTip? string with no onLink: the link rests muted, and this says why on hover
    ---@param linkTipLine? string a second, muted line under it
    Set = function(row, title, count, open, onToggle, linkText, onLink, linkArg, linkTip, linkTipLine)
        row.onToggle, row.onLink, row.linkArg = onToggle, onLink, linkArg
        row:EnableMouse(onToggle ~= nil)
        row.arrow:SetShown(onToggle ~= nil)
        row.arrow:SetRotation(open and -math.pi / 2 or 0)
        row.text:ClearAllPoints()
        -- A view whose rows sit on bands insets their text (view.inset); its titles line up.
        local inset = row:GetParent().inset or 0
        row.text:SetPoint("BOTTOMLEFT", (onToggle and 14 or 0) + inset, 5)
        row.link:SetPoint("BOTTOMRIGHT", -inset, 4)
        row.text:SetText(Label(title, count))
        row.link:SetShown(linkText ~= nil)
        if linkText then
            local link = row.link
            Parts.SetLink(link, linkText)
            link.disabled, link.tip, link.tipLine = onLink == nil, linkTip, linkTipLine
            Parts.LinkColor(link, link.disabled and T.muted or T.accentSoft)
            link.underline:Hide()
        end
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

-- Under its rows, a level below them so they draw on top. card.note is a line in the middle
-- of its body for a card with nothing in it: the grid stretches a card to its row's
-- tallest, and the line stays centred under the header.
Kinds.card = {
    New = function(view)
        local card = CreateFrame("Frame", nil, view)
        ns.Solid(card, "BACKGROUND", T.fg, CARD_FILL):SetAllPoints()
        card.edge = ns.Border(card, BORDER_RGB)
        card.note = ns.Font(card, 11, nil, T.muted)
        card.note:SetPoint("CENTER", 0, -CARD_HEADER_H / 2)
        card.note:Hide()
        return card
    end,
}
