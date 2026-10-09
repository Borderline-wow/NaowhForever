-- TierHeader.lua: a card's header for one standing's rewards or one rank's: its name, a check once reached, how far.
local ns = _G.NaowhForever

local T = ns.THEME
local J = ns.Journal
local Kinds = J.View.Kinds
local St = J.Style
local CHECK, HAVE_RGB, CARD_HEADER_H, CARD_NAME_SIZE = St.CHECK, St.HAVE_RGB, St.CARD_HEADER_H, St.CARD_NAME_SIZE
local UNREACHED, RULE_ALPHA, SMALL_SIZE = St.UNREACHED, St.RULE_ALPHA, St.SMALL_SIZE

local NAME_TOP, RIGHT_TOP = 11, 13
local CHECK_ICON = 14
local CHECK_GAP = 6
local NAME_ROOM = 12

Kinds.tier = {
    New = function(view)
        local row = CreateFrame("Frame", nil, view)
        row.name = ns.Font(row, CARD_NAME_SIZE, nil, T.fg)
        row.name:SetPoint("TOPLEFT", 0, -NAME_TOP)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.check = row:CreateTexture(nil, "ARTWORK")
        row.check:SetTexture(CHECK)
        row.check:SetSize(CHECK_ICON, CHECK_ICON)
        row.check:SetVertexColor(HAVE_RGB.r, HAVE_RGB.g, HAVE_RGB.b)
        row.check:SetPoint("LEFT", row.name, "RIGHT", CHECK_GAP, 0)
        row.right = ns.Font(row, SMALL_SIZE, nil, T.muted)
        row.right:SetPoint("TOPRIGHT", 0, -RIGHT_TOP)
        row.right:SetJustifyH("RIGHT")
        row.rule = ns.Solid(row, "ARTWORK", T.line, RULE_ALPHA)
        row.rule:SetPoint("BOTTOMLEFT")
        row.rule:SetPoint("BOTTOMRIGHT")
        ns.Hairline(row.rule, "h")
        return row
    end,
    Set = function(row, label, color, reached, right, shown)
        row.name:SetWidth(0)
        row.name:SetText(label)
        row.name:SetTextColor(color.r, color.g, color.b)
        row.name:SetAlpha(reached and 1 or UNREACHED)
        row.check:SetShown(reached)
        row.right:SetText(right or "")
        row.name:SetWidth(math.min(math.ceil(row.name:GetStringWidth()) + 1,
            row:GetWidth() - CHECK_ICON - NAME_ROOM - math.ceil(row.right:GetStringWidth())))
        row.rule:SetShown(shown > 0)
        return CARD_HEADER_H
    end,
}
